# Recover volume after unexpected detachment

## Overview
1. Now Longhorn can automatically reattach then remount volumes if unexpected detachment happens. e.g., [Kubernetes upgrade](https://github.com/longhorn/longhorn/issues/703), [Docker reboot](https://github.com/longhorn/longhorn/issues/686).
2. After **reattachment** and **remount** complete, users may need to **manually restart the related workload containers** for the volume restoration **if the following recommended setup is not applied**.

#### Reattachment
Longhorn will reattach the volume if the volume engine deads unexpectedly.

#### Remount
- Longhorn will detect and remount filesystem for the volume after the reattachment. 
- But **the auto remount does not work for `xfs` filesystem**. 
    - Since mounting one more layers with `xfs` filesystem is not allowed and will trigger the error `XFS (sdb): Filesystem has duplicate UUID <filesystem UUID> - can't mount`.
    - Users need to manually unmount then mount the `xfs` filesystem on the host. The device path on host for the attached volume is `/dev/longhorn/<volume name>`  

## Recommended setup when using Longhorn volumes
In order to recover unexpectedly detached volumes automatically, users can set `restartPolicy` to `Always` then add `livenessProbe` for the workloads using Longhorn volumes.
Then those workloads will be restarted automatically after reattachment and remount.

Here is one example for the setup:
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-volv-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: volume-test
  namespace: default
spec:
  restartPolicy: Always
  containers:
  - name: volume-test
    image: nginx:stable-alpine
    imagePullPolicy: IfNotPresent
    livenessProbe:
      exec:
        command:
        - ls
        - /data/lost+found
      initialDelaySeconds: 5
      periodSeconds: 5
    volumeMounts:
    - name: volv
      mountPath: /data
    ports:
    - containerPort: 80
  volumes:
  - name: volv
    persistentVolumeClaim:
      claimName: longhorn-volv-pvc
```
- The directory used in the `livenessProbe` will be `<volumeMount.mountPath>/lost+found`
- Don't set a short interval for `livenessProbe.periodSeconds`, e.g., 1s. The liveness command is CPU consuming.

## Manually restart workload containers
## This solution is applied only if:
1. The Longhorn volume is reattached and remounted automatically.
2. The above setup is not included when the related workload is launched.

### Steps
1. Figure out on which node the related workload's containers are running
```
kubectl -n <namespace of your workload> get pods <workload's pod name> -o wide
```
2. Connect to the node. e.g., `ssh`
3. Figure out the containers belonging to the workload
```
docker ps
```
By checking the columns `COMMAND` and `NAMES` of the output, you can find the corresponding container

4. Restart the container
```
docker restart <the container ID of the workload>
```

### Reason
Typically the volume mount propagation is not `Bidirectional`. It means the Longhorn remount operation won't be propagated to the workload containers if the containers are not restarted.
