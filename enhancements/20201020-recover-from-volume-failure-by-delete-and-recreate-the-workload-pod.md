# Recover From Volume Failure by Delete and Recreate The Workload Pod

## Summary

[The current implementation](https://github.com/longhorn/longhorn-manager/blob/ba4ca64ad03911194c8586932e9f529e19c884a4/util/util.go#L712) of the remount feature doesn't work when the workload pod uses subpath. 
This enhancement proposed a new way to handle volume remount which is deleting the workload Pod if it is controlled by a controller 
(e.g. deployment, statefulset, daemonset).
By doing so, Kubernetes will restart the pod, detach, attach, and remount the volume.

### Related Issues

https://github.com/longhorn/longhorn/issues/1719

## Motivation

### Goals

Make sure that when volume attached after it is detached unexpectedly or after it is auto salvaged,
the workload pod can use the volume even if the containers inside the pod use subpaths.

## Solution Space

### #1 Use `findmnt` to detect the mount point of subpath

The command `findmnt <DEV-NAME>`can be used to find all existing mount points corresponding to the device.
The example output of this command when a pod is using subpath:
```
root@worker-1:~# findmnt /dev/longhorn/pvc-1ce69c7e-90ce-41ce-a88e-8b968d9a8ff9 
TARGET                                                                                                                                  SOURCE                                                        FSTYPE OPTIONS
/var/lib/kubelet/pods/0429305b-faf1-4668-aaed-139a2cf4989c/volumes/kubernetes.io~csi/pvc-1ce69c7e-90ce-41ce-a88e-8b968d9a8ff9/mount     /dev/longhorn/pvc-1ce69c7e-90ce-41ce-a88e-8b968d9a8ff9        ext4   rw,rela
/var/lib/kubelet/pods/0429305b-faf1-4668-aaed-139a2cf4989c/volume-subpaths/pvc-1ce69c7e-90ce-41ce-a88e-8b968d9a8ff9/nginx/0             /dev/longhorn/pvc-1ce69c7e-90ce-41ce-a88e-8b968d9a8ff9[/html] ext4   rw,rela
```
We can identify which mount point is subpath and which mount point mounts to the root of the volume's filesystem.
Then, Longhorn can remount the mount point which mounts to the root of the volume's filesystem.

### #2 Delete the workload pod

Instead of manually finding and remounting all mount points of the volume, we delete the pod that has a controller. 
The pod's controller will recreate it. After that, Kubernetes handles the reattachment and remount of the volume.
 
This solves the issue that remount doesn't work when the workload pod uses subpath in PVC.

## Proposal

I would like to choose approach #2, `Delete the workload pod` because it is cleaner.
Manually doing remount is cumbersome and leaves duplicated mount points on the host.

### User Stories

#### Story 1

Users use subpath in PVC that is bounded to Longhorn volume.
When the network goes bad, the volume becomes faulty (if there is no local replica).
Longhorn auto salvages the volume when the network comes back. 
Then Longhorn does auto-remount but [the current remount logic](https://github.com/longhorn/longhorn-manager/blob/ba4ca64ad03911194c8586932e9f529e19c884a4/util/util.go#L712) doesn't support subpath.

### User Experience In Detail

When users deploy workload using controller such as deployment, statefulset, or daemonset, 
They are assured that volume gets reattached and remounted in case it is detached unexpectedly. 

What about a pod without a controller? Users have to manually delete and recreate it.
 
### API changes

There is no API change

## Design

### Implementation Overview

The idea is that `VolumeControler` will set `RemountRequestedAt` when the volume needs to remount. 
The `KubernetesPodController` will compare `RemountRequestedAt` with the pod's `podStartTime`. 
If pod's `startTime` < `vol.Status.RemountRequestAt`, `KubernetesPodController` deletes the pod. 
We don't delete the pod immediately though. 
Wait until `timeNow` > `vol.Status.RemountRequestedAt` + `delayDuration` (5s).
The `delayDuration` is to make sure we don't repeatedly delete the pod too fast when `vol.Status.RemountRequestedAt` is updated too quickly by `VolumeController`
After `KubernetesPodController` deletes the pod, there is no need to pass the information back to `VolumeController` because there is no need to reset the field `LastRemountRequestAt` which is just an event in the past.

### Test plan

1. Deploy a storage class with parameter `numberOfReplicas: 1` and `datalocality: best-effort`
1. Deploy a statefulset with `replicas: 1` and using the above storageclass. 
   Make sure the container in the pod template uses subpath, like this:
   ```yaml
   volumeMounts:
   - name: <PVC-NAME>
     mountPath: /mnt
     subPath: html
   ```
1. Find the node where the statefulset pods are running. 
   Let's say `pod-1` is on `node-1`, and use `vol-1`.
1. exec into `pod-1`, create a file `test_data.txt` inside the folder `/mnt/html`
1. Kill the replica instance manager pod on `node-1`. 
   This action simulates a network disconnection (the engine process of the PVC cannot talk to the replica process on the killed replica instance manager pod).
1. in a 2 minutes retry loop: 
   Exec into the `pod-1`, run `ls /mnt/html`. 
   Verify the file `test_data.txt` exists.
1. Kill the replica instance manager pod on `node-1` one more time. 
1. Wait for volume to become healthy, kill the replica instance manager pod on `node-1` one more time. 
1. in a 2 minutes retry loop: 
   Exec into the `pod-1`, run `ls /mnt/html`. 
   Verify the file `test_data.txt` exists.
   
1. Update `numberOfReplicas` to 3.
   Wait for replicas rebuilding finishes.
1. Kill the engine instance manager pod on `node-1`
1. In a 2 minutes retry loop:
   Exec into the `pod-1`, run `ls /mnt/html`.
   Verify the file `test_data.txt` exists.
   
1. Delete `pod-1`.
1. in a 2 minutes retry loop: 
   Exec into the `pod-1`, run `ls /mnt/html`. 
   Verify the file `test_data.txt` exists.

### Upgrade strategy

There is no upgrade needed.
