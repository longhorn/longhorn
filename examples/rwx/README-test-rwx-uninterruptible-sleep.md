# RWX Volume Uninterruptible Sleep Test

## Overview

This test case is designed to reproduce and verify the fix for issue [#11907](https://github.com/longhorn/longhorn/issues/11907) where RWX volumes can cause processes to enter uninterruptible sleep.

## Issue Description

When multiple pods write to the same file on an RWX (ReadWriteMany) Longhorn volume, one of the writer processes may enter an uninterruptible sleep state (D state) indefinitely. The process gets stuck in NFS/NFSv4 kernel operations and cannot be killed or interrupted.

### Symptoms

- Process enters `Ds+` state (uninterruptible sleep)
- Process stack trace shows NFS operations like `nfs_set_open_stateid_locked`
- The NFS volume remains accessible to other processes
- Terminating other writer processes allows the stuck process to resume

## Test Environment Requirements

- Single-node or multi-node Kubernetes cluster
- Longhorn v1.10.0 or later installed
- Default Longhorn StorageClass available
- SSH access to cluster nodes (for manual verification)

## Running the Test

### 1. Deploy the Test Workload

```bash
kubectl apply -f test-rwx-uninterruptible-sleep.yaml
```

### 2. Wait for Pods to be Ready

```bash
kubectl wait --for=condition=ready pod -l app=rwx-uninterruptible-sleep-test --timeout=300s
```

### 3. Verify Initial State

Check that both pods are running:

```bash
kubectl get pods -l app=rwx-uninterruptible-sleep-test
```

You should see 2 pods in Running state.

### 4. Monitor for the Issue

The issue typically manifests after several minutes of continuous writing. To monitor:

#### Option A: Manual Monitoring (requires node SSH access)

SSH into the node where the pods are running:

```bash
# Find which node the pods are on
kubectl get pods -l app=rwx-uninterruptible-sleep-test -o wide

# SSH to the node
ssh <node-name>

# Monitor process states - look for 'D' or 'Ds+' in STAT column
watch 'ps aux | grep "echo.*index.html"'
```

Example output showing the issue:
```
root  123312  0.1  0.0  4508  1536 pts/0  Ss+  09:00  1:00 /bin/sh -c sleep 10; touch /data/index.html; while true; do echo ...
root  123315  0.0  0.0  4508  1536 pts/0  Ds+  09:00  0:12 /bin/sh -c sleep 10; touch /data/index.html; while true; do echo ...
```

Note the `Ds+` state on PID 123315 - this indicates uninterruptible sleep.

#### Option B: Check Process Stack (if issue occurs)

If a process enters D state, check its kernel stack:

```bash
cat /proc/<PID>/stack
```

Expected output showing NFS operations:
```
[<0>] nfs_set_open_stateid_locked+0x100/0x380 [nfsv4]
[<0>] update_open_stateid+0xa0/0x2b0 [nfsv4]
[<0>] _nfs4_opendata_to_nfs4_state+0x11b/0x220 [nfsv4]
...
```

### 5. Verify NFS Mount Status

Check the NFS mount statistics:

```bash
nfsstat --mount
```

Look for the mount with the Longhorn volume path showing flags like:
```
Flags: rw,relatime,vers=4.1,rsize=1048576,wsize=1048576,namlen=255,softerr,softreval,noresvport,proto=tcp,timeo=600,retrans=5,sec=sys,...
```

### 6. Test the Workaround (if issue occurs)

If the issue is reproduced, verify the workaround:

1. Identify the healthy writer process
2. Kill it: `kubectl delete pod <healthy-pod-name>`
3. Observe that the stuck process resumes

## Expected Results

### Before Fix

- After several minutes, one writer process enters D state (uninterruptible sleep)
- Process cannot be killed or interrupted
- Process stack shows NFS operations
- Killing other writer allows stuck process to resume

### After Fix

- All writer processes remain in S state (interruptible sleep)
- No processes enter D state
- All pods continue writing successfully
- File size grows continuously without interruption

## Automated Testing

This test case can be automated by:

1. **Deployment**: Apply the manifest via kubectl
2. **Monitoring**: Parse `ps aux` output on the node to detect D state processes
3. **Duration**: Run for at least 10-15 minutes to allow the issue to manifest
4. **Validation**: Assert no processes enter D state during the test period
5. **Cleanup**: Delete the deployment and PVC

### Example Automated Test Script

```python
import subprocess
import time
import re

def check_for_d_state_processes(node_name, duration_minutes=15):
    """
    Monitor for processes in D state on the given node.
    Returns True if issue is detected, False otherwise.
    """
    end_time = time.time() + (duration_minutes * 60)
    
    while time.time() < end_time:
        # SSH to node and check process states
        cmd = f"ssh {node_name} 'ps aux | grep \"echo.*index.html\"'"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        
        # Look for D or Ds+ in STAT column
        if re.search(r'\s+D[s+]*\s+', result.stdout):
            print(f"ISSUE DETECTED: Process in D state found")
            print(result.stdout)
            return True
        
        time.sleep(10)  # Check every 10 seconds
    
    return False

# Usage
issue_detected = check_for_d_state_processes('worker-node-1', duration_minutes=15)
assert not issue_detected, "RWX uninterruptible sleep issue detected!"
```

## Cleanup

```bash
kubectl delete -f test-rwx-uninterruptible-sleep.yaml
```

## References

- Original Issue: https://github.com/longhorn/longhorn/issues/11907
- NFS Ganesha Issue: https://github.com/nfs-ganesha/nfs-ganesha/issues/1327
- Changelog Entry: CHANGELOG-1.11.0.md

## Notes

- This issue is specific to NFSv4.1 with certain mount options
- The issue manifests more quickly on systems under higher I/O load
- Multiple concurrent writers to the same file increase reproduction probability
- The issue affects Linux kernel NFS client behavior when interacting with NFS Ganesha
