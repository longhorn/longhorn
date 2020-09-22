# CSI Snapshot Support

## Summary

To allow users to create/restore/delete backups programmatically, 
we want to add support for the csi snapshot mechanism.
This way existing tools can be used to create kubernetes `VolumeSnapshot` api resources, 
which we can react to in the csi plugin.

### Related Issues

https://github.com/longhorn/longhorn/issues/304
https://github.com/longhorn/longhorn/issues/610
https://github.com/longhorn/longhorn/issues/1127
https://github.com/kubernetes/community/blob/master/contributors/design-proposals/storage/csi-snapshot.md

## Motivation

Provide user with programmatic access for backup operations via the standardized csi interface.
https://kubernetes.io/docs/concepts/storage/volume-snapshots/#provisioning-volume-snapshot

### Goals

- add csi snapshot support to our csi driver

### Non-goals

- VolumeBackup crd refactor
- Changes to the longhorn backup code

## Proposal

- support csi CreateSnapshot call 
- support csi DeleteSnapshot call
- support snapshot as ContentSource for restoration during CreateVolume calls

### User Stories

Currently, it's hard for users to interact with the backup system programmatically,
after this enhancement the users will be able to use the standard kubernetes csi mechanisms for
backup creation / deletion and restoration of a new volume based on a backup.

### User Experience In Detail

#### Backup creation via VolumeSnapshot resource

The user can request a backup of a volume by creation of a kubernetes `VolumeSnapshot` object.
Example below for a volume named `test-vol`

```yaml
apiVersion: snapshot.storage.k8s.io/v1beta1
kind: VolumeSnapshot
metadata:
  name: test-snapshot-pvc
spec:
  volumeSnapshotClassName: longhorn
  source:
    persistentVolumeClaimName: test-vol
```

#### Restoration via VolumeSnapshot resource

The user can request the creation of a volume based on a prior created `VolumeSnapshot` object.
Example below for a volume named `test-vol-restore`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-vol-restore
spec:
  storageClassName: longhorn
  dataSource:
    name: test-vol-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
```

#### Restoration of an existing Longhorn backup (pre-provisioning)

The user can request the creation of a volume based on a prior longhorn backup, that was not created via the csi layer.
The user needs to create a `VolumeSnapshotContent` object with an associated `VolumeSnapshot` object.
The `snapshotHandle` of the `VolumeSnapshotContent` needs to point to an existing longhorn backup.
Example below for a volume named `test-restore-existing-backup`

```yaml
apiVersion: snapshot.storage.k8s.io/v1beta1
kind: VolumeSnapshotContent
metadata:
  name: test-existing-backup
spec:
  volumeSnapshotClassName: longhorn
  driver: driver.longhorn.io
  deletionPolicy: Delete
  source:
    # NOTE: change this to point to an existing backup on the backupstore
    snapshotHandle: bs://test-vol/backup-625159fb469e492e
  volumeSnapshotRef:
    name: test-snapshot-existing-backup
    namespace: default
```

```yaml
apiVersion: snapshot.storage.k8s.io/v1beta1
kind: VolumeSnapshot
metadata:
  name: test-snapshot-existing-backup
spec:
  volumeSnapshotClassName: longhorn
  source:
    volumeSnapshotContentName: test-existing-backup
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-restore-existing-backup
spec:
  storageClassName: longhorn
  dataSource:
    name: test-snapshot-existing-backup
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
```

#### Backup deletion via VolumeSnapshot resource

The user can request the deletion of a backup by removing the associated `VolumeSnapshot` object.
If the DeletionPolicy is Delete, then the referenced longhorn backup will be deleted along with the `VolumeSnapshotContent` object. 
If the DeletionPolicy is Retain, then both the referenced longhorn backup and `VolumeSnapshotContent` object remain.
The default DeletionPolicy is set to Delete, if the user wants to retain the longhorn backups, 
the user can create a snapshotClass with DeletionPolicy set to Retain.
https://kubernetes.io/docs/concepts/storage/volume-snapshot-classes/#deletionpolicy

Example below for a snapshot named `test-snapshot-pvc`
`kubectl delete volumesnapshots test-snapshot-pvc`

Deletion is triggered by deleting the VolumeSnapshot object, and the DeletionPolicy will be followed. 

The default deletion policy

### API changes

no changes necessary

## Design

### Implementation Overview

#### Implement CSI CreateSnapshot call

The creation of a `VolumeSnapshot` resource triggers the creation of a longhorn snapshot afterwards, 
that snapshot will be backed up via the longhorn backup mechanism to a user defined backupstore (s3, nfs). 
While the backup isn't completed the csi snapshot will be marked not ready to use.

The csi-snapshot-request name is generated by the csi snapshotter, based on the configured prefix + `VolumeSnapshot.uuid` 
This information is also used to generate the `VolumeSnapshotContent.name = snapcontent-uuid`

The csi-snapshotter will always call the longhorn csi plugin with the same csi snapshot request name for a specific Snapshot object.
This means we have to use the csi snapshotter generated name, for the longhorn snapshot 
or introduce a CRD (VolumeBackup) so that we have a persisted way of associating 
csiSnapshot - longhornSnapshot - longhornBackup

If we would ignore the requested name, we would end up generating a new snapshot for each successive call, 
since a backup can take a long time for very big volumes, that would not be the desired behavior.

To be able to lookup the backup during a following `DeleteSnapshot` or `CreateVolume` call, 
we encode the backupVolume and backupName as part of the snapshotID 
which is returned from the csi CreateSnapshot call.

this will be set as the `VolumeSnapshotContent.snapshotHandle` for the kubernetes created `VolumeSnapshotContent` object.
We use the format `type://backupVolume/backupName` where the default type equals `bs` for direct references to longhorn backups.

This is so that in the future we can refer to a custom kubernetes resource, which we can use for backup metadata persistence.

#### Implement CSI DeleteSnapshot call

For backup deletion all we have todo is decode the snapshotID then trigger the backup delete calls via the longhorn api.

#### Add CSI CreateVolume ContentSource support.

For the volume creation based on a CSI snapshot we can decode the snapshotID to lookup the backup in the backupstore.
This will provide us with the backupURL which we can add to the `fromBackup` field in the longhorn created Volume resource.
As part of prior work longhorn already knows how to restore these backups, this was initially used for a StorageClass
parameter, by reusing the same mechanism we don't have to maintain multiple code paths for volume restoration.

### Test plan

See examples of the necessary yaml manifests in the `User Experience In Detail` section.

Creation test:
- create volume
- write data to volume
- create a `VolumeSnapshot` object
- wait for `VolumeSnapshot` to be ready to use
- check for backup existence on the backupstore

Deletion test:
- create volume
- write data to volume
- create a `VolumeSnapshot` object
- wait for `VolumeSnapshot` to be ready to use
- check for backup existence on the backupstore 
- delete `VolumeSnapshot` object
- wait for backup removal from the backupstore

Restore csi snapshot test:
- create volume
- write data to volume
- create a `VolumeSnapshot` object
- wait for `VolumeSnapshot` to be ready to use
- check for backup existence on the backupstore 
- create PVC with content source set to the `VolumeSnapshot` object
- wait for volume restoration
- verify restored volume data == previously written data

Restore existing longhorn backup test:
- create volume
- write data to volume
- create a longhorn backup
- check for backup existence on the backupstore
- create a `VolumeSnapshotContent` object pointing to the longhorn backup
- create a `VolumeSnapshot` object pointing to the `VolumeSnapshotContent` object
- create PVC with content source set to the `VolumeSnapshot` object
- wait for volume restoration
- verify restored volume data == previously written data

### Upgrade strategy

For csi snapshot support the user needs to update their kubernetes installation to at least 1.17

For environments where the user has pinned their csi images (airgap) 
the users need to manually provide the following images:

- longhornio/csi-provisioner:v1.6.0
- longhornio/csi-snapshotter:v2.1.1

We upgraded the csi-provsioner from 1.4 to 1.6, which still supports kubernetes 1.13 as a minimum version

## Note

Since we cannot assume that the users distribution has csi snapshotter support, the user needs to create a
`VolumeSnapshotClass` to be able to use the csi snapshot support.

Example longhorn `VolumeSnapshotClass`
```yaml
kind: VolumeSnapshotClass
apiVersion: snapshot.storage.k8s.io/v1beta1
metadata:
  name: longhorn
driver: driver.longhorn.io
deletionPolicy: Delete
```

The CRDs and snapshot controller installations are the responsibility of the Kubernetes distribution.
See: https://kubernetes.io/docs/concepts/storage/volume-snapshots/#introduction

We are discussing whether longhorn can provide these as part of the longhorn installation, but there isn't really
a good way of making sure that there isn't a snapshot controller already deployed in the cluster.

Make sure your cluster contains the below crds, rancher rke did not deploy them for me.
https://github.com/kubernetes-csi/external-snapshotter/tree/master/client/config/crd

Make sure your cluster contains the snapshot controller, rancher rke did not deploy it for me.
https://github.com/kubernetes-csi/external-snapshotter/tree/master/deploy/kubernetes/snapshot-controller
