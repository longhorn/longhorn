# Dedicated Recovery Backend for RWX Volume's NFS Server

## Summary

A NFS server located within the share-manager pod is a key component of a RWX volume. The share-manager controller will recreate the share-manager pod and attach the volume to another node while the node where the share-manager pod is running is down.  However, the failover cannot work correctly because the NFS server lacks an appropriate recovery backend and the connection information cannot be persistent. As a result, the client's workload will be interrupted during the failover. To make the NFS server have failover capability, we want to implement a dedicated recovery backend  and associated modifications for Longhorn.

### Related Issues

[https://github.com/longhorn/longhorn/issues/2293](https://github.com/longhorn/longhorn/issues/2293)

## Motivation

### Goals

- Implement a dedicated recovery backend for Longhorn and make the NFS server highly available.

### Non-goals

- Active/active or Active/passive NFS server pattern

## Proposal

To support NFS server's failover capability, we need to change both the client and server configurations. A dedicated recovery backend for Kubernetes and Longhorn is also necessary.
In the implementation, we will not implement the active/active or active/passive server pattern. Longhorn currently supports local filesystems such as ext4 and xfs. Thus, any change in the node, which is providing service, cannot update to the standby node. The limitation will hinder the active/active design. Currently, the creation of an engine process needs at least one replica and then exports the iSCSI frontend. That is, the standby engine process of the active/passive configuration is not allowable in current Longhorn architecture.

### User Stories

While the node where the share-manager pod is running is down, the share-manager controller will recreate the share-manager pod and attach the volume to another node.  However, the failover cannot work correctly because the connection information are lost after restarting the NFS server. As a result, the locks cannot be reclaimed correctly, and the interruptions of the clients’ filesystem operations happen.


### User Experience In Detail

1. The changes and improvements should not impact the usage of the RWX volumes.
2. NFS filesystem operation will not be interrupted after the failover of the share-manager pod.
3. After the crash of the share-manager pod, the application on the client side’s IO operations will be stuck until the share-manager and NFS are recreated.
4. To make the improvement work, users have to make sure the hostname of each node in the Longhorn system is unique by checking each node's hostname using `hostname` command.
5. To shorten the failover time, users can
    - Multiple coredns pods in the Kubernetes cluster to ensure the recovery backend be always accessible.
    - Reduce the NFS server's `Grace_Period` and `Lease_Lifetime`. By default, `Grace_Period` and `Lease_Lifetime` are 90 and 60 seconds, respectively. However, the value can be reduced to a smaller value for early termination of the grace period at the expense of security. Please refer to [Long client timeouts when failing over the NFS Ganesha IP resource](https://www.suse.com/support/kb/doc/?id=000019374).
    - Reduce `node-monitor-period` and `node-monitor-grace-period` values in the Kubelet. The unresponsive node will be marked as `NotReady` and speed up the NFS server's failover process.

## Design

### Implementation Overview

- **longhorn-manager**
    
    The speed of a share-manager pod and volume's failover is affected by the cluster's settings and resources, so it is unpredictable how long it takes to failover. Thus, the NFS client mount options `soft, timeo=30, retrans=3` are replaced with `hard`.
    
- **share-manager**
    
    To allow the NFSv4 clients to reclaim locks after the failover of the NFS server, the grace period is enabled by setting
    
    - Lease_Lifetime = 60
    - Grace_Period = 90
    
    Additionally, set `NFS_Core_Param.Clustered` to `false`. The NFS server will use the hostname rather than such as `node0` in the share-manager pod, which is same as the name of the share-manager pod, to create a corresponding storage in the recovery backend. The unique hostname avoids the naming conflict in the recovery backend.
    

- **nfs-ganesha (user-space NFS server)**
    
    ```
                                 ┌────────────────────────────────────────────────┐
                                 │                     service                    │
                              ┌──►                                                │
                              │  │          longhorn-nfs-recovery-backend         │
                              │  └───────────────────────┬────────────────────────┘
                              │                          │
                          HTTP API         ┌─────────────┴──────────────┐
                              │            │                            │
                              │            │ endpoint 1                 │ endpoint N
     ┌──────────────────────┐ │  ┌─────────▼────────┐          ┌────────▼─────────┐
     │  share-manager pod   │ │  │ recovery-backend │          │ recovery-backend │
     │                      │ │  │      pod         │          │      pod         │
     │ ┌──────────────────┐ │ │  │                  │   ...    │                  │
     │ │    nfs server    ├─┼─┘  │                  │          │                  │
     │ └──────────────────┘ │    │                  │          │                  │
     │                      │    │                  │          │                  │
     └──────────────────────┘    └──────────┬───────┘          └──────────┬───────┘
                                            │                             │
                                            │        ┌─────────────┐      │
                                            └───────►│  configMap  │◄─────┘
                                                     └─────────────┘
    ```
    
    1. Introduce a recovery-backend service backed by multiple recovery-backend pods. The recover-backend is shared by multiple RWX volumes to reduce the costs of the resources.
    2. Implement a set of dedicating recovery-backend operations for Longhorn in nfs-ganesha
        - recovery_init
            - Create a configmap, `recovery-backend-${share-manager-pod-name}`, storing the client information
        - end_grace
            - Clean up the configmap
        - recovery_read_clids
            - Create the client reclaim list from the configmap
        - add_clid
            - Add the client key (client’s hostname) into the configmap
        - rm_clid
            - Remove the client key (client’s hostname) from the configmap
        - add_revoke_fh
            - Revoke the delegation
    3. Then, the data from the above operations are persisted by sending to the recovery-backend service. The data will be saved in the configmap, `recovery-backend-${share-manager-pod-name}`.
    
- **Dedicating Configmap Format**

    ```
    name: `recovery-backend-${share-manager-pod-name}`
    labels:
        longhorn.io/component: nfs-recovery-backend
        ...
    annotations:
        version: 8-bytes random id, e.g. 6SVVI1LE
    data:
    6SVVI1LE: {….json encoded content (containing the client identity information…}
    ```

    One example
    ```
    apiVersion: v1
    data:
    6SVVI1LE: '{"31:Linux NFSv4.1 rancher50-worker1":[],"31:Linux NFSv4.1 rancher50-worker2":[],"31:Linux
        NFSv4.1 rancher50-worker3":[]}'
    kind: ConfigMap
    metadata:
    annotations:
        version: 6SVVI1LE
    creationTimestamp: "2022-12-01T01:27:14Z"
    labels:
        longhorn.io/component: share-manager-configmap
        longhorn.io/managed-by: longhorn-manager
        longhorn.io/share-manager: pvc-de201ca5-ec0b-42ea-9501-253a7935fc3e
    name: recovery-backend-share-manager-pvc-de201ca5-ec0b-42ea-9501-253a7935fc3e
    namespace: longhorn-system
    resourceVersion: "47544"
    uid: 60e29c30-38b8-4986-947b-68384fcbb9ef
    ```
    
### Notice

- **In the event that the original share manager pod is unavailable, a new share manager pod cannot be created**
    In the client side, IO to the RWX volume will hang until a share-manager pod replacement is successfully created on another node.

- **Failed to reclaim locks in 90-seconds grace period**
    If locks cannot be reclaimed after a grace period, the locks are discarded and return IO errors to the client. The client reestablishes a new lock. The application should handle the IO error. Nevertheless, not all applications can handle IO errors due to their implementation. Thus, it may result in the failure of the IO operation and the loss of data. Data consistency may be an issue.

- **If the DNS service goes down, share-manager pod will not be able to communicate with longhorn-nfs-recovery-backend**
    The NFS-ganesha server in the share-manager pod communicates with longhorn-nfs-recovery-backend via the service `longhorn-recovery-backend` IP. Thus, the high availability of the DNS services is recommended for avoiding the communication failure.

### Test Plan

- Setup
    
    3 worker nodes for the Longhorn cluster
    
    - Attach 1 RWO volume to node-1
    - Attach 2 RWO volumes to node-2
    - Attach 3 RWO volumes to node-3
- Tests
    1. Create 1 RWX volume and then run an app pod with the RWX volume on each worker node.Execute the command in each app pod
        
        `( exec 7<>/data/testfile-${i}; flock -x 7; while date | dd conv=fsync >&7 ; do sleep 1; done )`
        
        where ${i} is the node number.
        
        Turn off the node where share-manager is running. Once the share-manager pod is recreated on a different node, check
        
        - Expect
            - In the client side, IO to the RWX volume will hang until a share-manager pod replacement is successfully created on another node.
            - During the grace period, the server rejects READ and WRITE operations and non-reclaim locking requests (i.e., other LOCK and OPEN operations) with an error of NFS4ERR_GRACE.
            - The clients can continue working without IO error.
            - Lock reclaim process can be finished earlier than the 90-seconds grace period.
            - During the grace period, the server reject READ and WRITE operations and non-reclaim
            - If locks cannot be reclaimed after a grace period, the locks are discarded and return IO errors to the client. The client reestablishes a new lock.

    2. Turn the deployment into a daemonset in [example]([https://github.com/longhorn/longhorn/blob/master/examples/rwx/rwx-nginx-deployment.yaml](https://github.com/longhorn/longhorn/blob/master/examples/rwx/rwx-nginx-deployment.yaml) ) and disable `Automatically Delete Workload Pod when The Volume Is Detached Unexpectedly`. Then, deploy the daemonset with a RWX volume.
        
        Turn off the node where share-manager is running. Once the share-manager pod is recreated on a different node, check
        
        - Expect
            - The other active clients should not run into the stale handle errors after the failover.
            - Lock reclaim process can be finished earlier than the 90-seconds grace period.
    3. Multiple locks one single file tested by byte-range file locking

        Each client ([range_locking.c](https://github.com/longhorn/longhorn/files/9208112/range_locking.txt)) in each app pod locks a different range of the same file. Afterwards, it writes data repeatedly into the file.
        
        Turn off the node where share-manager is running. Once the share-manager pod is recreated on a different node, check
        
        - The clients continue the tasks after the server's failover without IO or stale handle errors.
        - Lock reclaim process can be finished earlier than the 90-seconds grace period.

## Note[optional]

### Reference for the NFSv4 implementation

- [Network File System (NFS) Version 4 Protocol](https://datatracker.ietf.org/doc/html/rfc7530)
- [Long client timeouts when failing over the NFS Ganesha IP resource](https://www.suse.com/support/kb/doc/?id=000019374)
- [Necessary NFS Server Cluster Design for NFS Client Lock Preservation](https://www.suse.com/support/kb/doc/?id=000020396)
- [How NFSv4 file delegations work](https://library.netapp.com/ecmdocs/ECMP1401220/html/GUID-DE6FECB5-FA4D-4957-BA68-4B8822EF8B43.html)