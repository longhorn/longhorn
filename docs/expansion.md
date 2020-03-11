# Volume Expansion

## Overview
- Longhorn supports OFFLINE volume expansion only. 
- Longhorn will expand frontend (e.g. block device) then expand filesystem.

## Prerequisite:
1. Longhorn version v0.8.0 or higher.
2. The volume to be expanded is state `detached`.

## Expand a Longhorn volume
There are two ways to expand a Longhorn volume:

#### Via PVC 
- This method is applied only if:
  1. Kubernetes version v1.16 or higher.
  2. The PVC is dynamically provisioned by the Kubernetes with Longhorn StorageClass.
  3. The field `allowVolumeExpansion` should be `true` in the related StorageClass.
- This method is recommended if it's applicable. Since the PVC and PV will be updated automatically and everything keeps consistent after expansion.
- Usage: Find the corresponding PVC for Longhorn volume then modify requested `storage` of the PVC spec. e.g.,
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"v1","kind":"PersistentVolumeClaim","metadata":{"annotations":{},"name":"longhorn-simple-pvc","namespace":"default"},"spec":{"accessModes":["ReadWriteOnce"],"resources":{"requests":{"storage":"1Gi"}},"storageClassName":"longhorn"}}
    pv.kubernetes.io/bind-completed: "yes"
    pv.kubernetes.io/bound-by-controller: "yes"
    volume.beta.kubernetes.io/storage-provisioner: driver.longhorn.io
  creationTimestamp: "2019-12-21T01:36:16Z"
  finalizers:
  - kubernetes.io/pvc-protection
  name: longhorn-simple-pvc
  namespace: default
  resourceVersion: "162431"
  selfLink: /api/v1/namespaces/default/persistentvolumeclaims/longhorn-simple-pvc
  uid: 0467ae73-22a5-4eba-803e-464cc0b9d975
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn
  volumeMode: Filesystem
  volumeName: pvc-0467ae73-22a5-4eba-803e-464cc0b9d975
status:
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: 1Gi
  phase: Bound
```
Modify `spec.resources.requests.storage` of this PVC.


#### Via Longhorn UI
- If your Kubernetes version is v1.14 or v1.15, this method is the only choice for Longhorn volume expansion. 
- Notice that The volume size will be updated after the expansion but the capacity of corresponding PVC and PV won't change. Users need to take care of them.
- Usage: On the volume page of Longhorn UI, click `Expand` for the volume.


## Frontend expansion
- To prevent the frontend expansion from being interfered by unexpected data R/W, Longhorn supports OFFLINE expansion only. 
The `detached` volume will be automatically attached to a random node with maintenance mode.
- Rebuilding/adding replicas is not allowed during the expansion and vice versa. 
 

## Filesystem expansion
#### Longhorn will try to expand the file system only if:
1. The expanded size should be greater than the current size.
2. There is a Linux filesystem in the Longhorn volume. 
3. The filesystem used in the Longhorn volume is one of the followings:
    1. ext4
    2. XFS
4. The Longhorn volume is using block device frontend. 

#### Handling volume revert:
If users revert a volume to a snapshot with smaller size, the frontend of the volume is still holding the expanded size. But the filesystem size will be the same as that of the reverted snapshot. In this case, users need to handle the filesystem manually:
  1. Attach the volume to a random nodes.
  2. Log into the corresponding node, expand the filesystem:
  - If the filesystem is `ext4`, the volume might need to be mounted and umounted once before resizing the filesystem manually. Otherwise, executing `resize2fs` might result in an error:
    ```
    resize2fs: Superblock checksum does not match superblock while trying to open ......
    Couldn't find valid filesystem superblock.
    ```
    Follow the steps below to resize the filesystem:  
    ```
    mount /dev/longhorn/<volume name> <arbitrary mount directory>
    umount /dev/longhorn/<volume name>
    mount /dev/longhorn/<volume name> <arbitrary mount directory>
    resize2fs /dev/longhorn/<volume name>
    umount /dev/longhorn/<volume name>
    ```
  - If the filesystem is `xfs`, users can directly mount then expand the filesystem.
    ```
    mount /dev/longhorn/<volume name> <arbitrary mount directory>
    xfs_growfs <the mount directory>
    umount /dev/longhorn/<volume name>
    ```
