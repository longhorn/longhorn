# ReadOnlyMany Support

## Summary

Longhorn should support a ReadOnlyMany behavior, along the lines of https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/readonlymany-disks.  It should do so using the same share-manager mechanism with exposure through NFS that ReadWriteMany uses.

### Related Issues

https://github/longhorn/longhorn/issues/5401

## Motivation

### Goals

Pods and multi-pod workloads such as deployments and statefulssets can mount an existing volume's data without being able to alter it.

The configuration should be simple to use, to document, and to detect.

### Non-goals [optional]

The mounted volume need not be read-only at all levels. In particular, the CSI mount to share-manager may be read/write.

## Proposal

Add a parameter to storageclass and thus to volume spec named `mountReadOnly` with default value of `false`.

### User Stories

The user can already do something very close to this with existing share-manager code. If a volume is made ReadWriteMany, but uses a storage class with `nfsOptions` overrides that include "ro", it is mounted read-only for all the workload pods it attaches to.

It's not a complete solution for a couple of reasons. First, it feels "back-door", more like a workaround than a supported feature.

Second, and more critical, Longhorn code has to be able to determine that a volume that is read-only is intended to be so. Otherwise, the logic that attempts to un-mount and re-mount as writable will continually try and fail to do so, causing repeated attach/detach sequences.

There are several possible implementations. They all use the share-manager to achieve multiple readers. The mount onto the sharemanager in `/export` is not itself read-only. Only the NFS mount by the workload pod(s) is read-only.

The alternatives are

  1. Just document to use "ro" in storageclass parameter `nfsOptions`.
  2. Make a `ReadOnlyMany` access mode enum value (alias `rox`) and use it instead of `ReadWriteMany (rwx)` but still link it to the share-manager.
  3. Introduce another parameter, `mountReadOnly: true` in storage class (defaults to false).  

The pros and cons:

#### 1. As is:
  - Doesn't feel like a feature; more of a back-door.
  - Auto-remount feature (volumes that are read-only due to some mishap but should not be) needs a way to check the volume's intent. It would be cumbersome to make it parse the NFS mount options to figure that out.
  - Since it requires using `nfsOptions`, the user is responsible for knowing all the other necessary mount options to add to "ro".

#### 2. New `ReadOnlyMany` access mode enum value:
  - Feels the most like the related Kubernetes feature.
  - Requires touching a lot of code, in places that are checking for "should share-manager be involved?"
    - longhorn-manager
    - longhorn-share-manager
    - longhorn-ui

#### 3. New `mountReadOnly` parameter:
  - Easy to implement.
  - Volumes are still nominally `ReadWriteMany` so most logic can remain the same.
  - Requires checking one attribute in longhorn-manager node_server.go.
  - Allows Longhorn to use the same set of default NFS mount options to go with "ro" if that's all the user wants to set.
  - Does require Longhorn to specify precedence of mountReadOnly and nfsOptions if both are set.
    - mountReadOnly option always wins.


### User Experience In Detail

The user can instantiate a read-only volume from a backup of a writable volume, or from a clone.

*[Is it possible to modify the volume and reattach it? Need to try this.]*

#### From Backup
For instance, they create a volume with the necessary data, and make a backup of it.  Then they make a storageclass with `fromBackup` that points to the backup and `mountReadOnly: true`, and uses that to instantiate a PVC that can be bound to a workload.
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-rox-backup
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  fromBackup: "nfs://longhorn-test-nfs-svc.default:/opt/backupstore?volume=volume1&backup=backup1"
  fsType: "ext4"
  mountReadOnly: true
```

The workload using a PVC with that storageclass would get a volume written with the contents of `volume`` copied from `backup1` at creation, and then mounted into the workload pods as NFS read-only.

#### From Clone

Suppose `volume1` is created with this PVC:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: source-pvc
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

Then use a storageclass and PVC combination for the workload that looks like
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-rox-clone
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  fsType: "ext4"
  mountReadOnly: true

----

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cloned-pvc
spec:
  storageClassName: longhorn-rox-clone
  dataSource:
    name: source-pvc
    kind: PersistentVolumeClaim
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
```

### API changes

## Design

### Implementation Overview

Only the step to mount the shared volume from its share-manager NFS server is affected.  The code in [csi/node_server.go](https://github.com/longhorn/longhorn-manager/blob/2ec649c35486d782731982c9dff1db41c9031c99/csi/node_server.go#L244) will need to look at the parameter `mountReadOnly: true` and decide to append an "ro" to the list of mount options to use, whether defaulted or user-supplied.

Note that there is the possibility that `mountReadyOnly: false` can conflict with an `nfsOptions: "ro,soft,..."` setting.  If that happens, the parsing logic must strip out the "ro", because the intent is that `mountReadOnly` is the sole source of truth and may be trusted by other Longhorn code to reflect the actual situation.


### Test plan

Integration test plan *TBS*

For engine enhancement, also requires engine integration test plan.

### Upgrade strategy

None needed.  The parameter is optional and can default to the existing situation if using an existing storageclass that lacks it.

## Note [optional]

Additional notes.
