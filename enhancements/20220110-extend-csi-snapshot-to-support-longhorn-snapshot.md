# Title

Extend CSI snapshot to support Longhorn snapshot

## Summary

Before this feature, if the user uses [the CSI Snapshotter mechanism](https://kubernetes-csi.github.io/docs/snapshot-restore-feature.html),
they can only create Longhorn backups (out of cluster). We want to extend the CSI Snapshotter to support creating for 
Longhorn snapshot (in-cluster) as well.

### Related Issues

https://github.com/longhorn/longhorn/issues/2534

## Motivation

### Goals

Extend the CSI Snapshotter to support:
* Creating Longhorn snapshot
* Deleting Longhorn snapshot
* Creating a new PVC from a CSI snapshot that is associated with a Longhorn snapshot

### Non-goals

* Longhorn snapshot Reverting is not a goal because CSI snapshotter doesn't support replace in place for now: 
  https://github.com/container-storage-interface/spec/blob/master/spec.md#createsnapshot

## Proposal

### User Stories

Before this feature is implemented, users can only use CSI Snapshotter to create/restore Longhorn backups.
This means that users must set up a backup target outside of the cluster. Uploading/downloading data from
backup target is a long/costly operation. Sometimes, users might just want to use CSI Snapshotter to take
an in-cluster Longhorn snapshot and create a new volume from that snapshot. The Longhorn snapshot operation
is cheap and faster than the backup operation and doesn't require setting up a backup target.

### User Experience In Detail

To use this feature, users need to do:
1. Deploy the CSI snapshot CRDs, Controller as instructed at https://longhorn.io/docs/1.2.3/snapshots-and-backups/csi-snapshot-support/enable-csi-snapshot-support/
1. Deploy a VolumeSnapshotClass with the parameter `type: longhorn-snapshot`. I.e.,
    ```yaml
    kind: VolumeSnapshotClass
    apiVersion: snapshot.storage.k8s.io/v1beta1
    metadata:
      name: longhorn-snapshot
    driver: driver.longhorn.io
    deletionPolicy: Delete
    parameters:
      type: longhorn-snapshot
    ```
1. To create a new CSI snapshot associated with a Longhorn snapshot of the volume `test-vol`, users deploy the following VolumeSnapshot CR:
    ```yaml
    apiVersion: snapshot.storage.k8s.io/v1beta1
    kind: VolumeSnapshot
    metadata:
      name: test-snapshot
    spec:
      volumeSnapshotClassName: longhorn-snapshot
      source:
        persistentVolumeClaimName: test-vol
    ```
   A new Longhorn snapshot is created for the volume `test-vol`
1. To create a new PVC from the CSI snapshot, users can deploy the following yaml:
    ```yaml
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: test-restore-snapshot-pvc
    spec:
      storageClassName: longhorn
      dataSource:
        name: test-snapshot
        kind: VolumeSnapshot
        apiGroup: snapshot.storage.k8s.io
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 5Gi # should be the same as the size of `test-vol`
    ```
    A new PVC will be created with the same content as in the VolumeSnapshot `test-snapshot`
1. Deleting the VolumeSnapshot `test-snapshot` will lead to the deletion of the corresponding Longhorn snapshot of the volume `test-vol`

### API changes
None

## Design

### Implementation Overview

We follow the specification in [the CSI spec](https://github.com/container-storage-interface/spec/blob/master/spec.md#createsnapshot) when supporting the CSI snapshot.

We define a new parameter in the VolumeSnapshotClass `type`.
The value of the parameter `type` can be `longhorn-snapshot` or `longhorn-backup`.
When `type` is `longhorn-snapshot` it means that the CSI VolumeSnapshot created with this VolumeSnapshotClass is associated with a Longhorn snapshot.
When `type` is `longhorn-backup` it means that the CSI VolumeSnapshot created with this VolumeSnapshotClass is associated with a Longhorn backup.

In [CreateSnapshot function](https://github.com/longhorn/longhorn-manager/blob/878cfb868c568396d6ebfa4ce096c5d95d9b31e3/csi/controller_server.go#L539), we get the
value of parameter `type`. If it is `longhorn-backup`, we take a Longhorn backup as before. If it is `longhorn-snapshot` we do:
* Get the name of the Longhorn volume
* Check if the volume is in attached state.
  If it is not, return `codes.FailedPrecondition`. 
  We cannot take a snapshot of non-attached volume.
* Check if a Longhorn snapshot with the same name as the requested CSI snapshot already exists. 
  If yes, return OK without taking a new Longhorn snapshot.
* Take a new Longhorn snapshot. Encode the snapshotId in the format `snap://volume-name/snapshot-name`. 
  This snaphotId will be used in the later CSI CreateVolume and DeleteSnapshot call. 
  
In [CreateVolume function](https://github.com/longhorn/longhorn-manager/blob/878cfb868c568396d6ebfa4ce096c5d95d9b31e3/csi/controller_server.go#L63):
* If the VolumeContentSource is a `VolumeContentSource_Snapshot` type, decode the snapshotId in the format from the above step. 
* Create a new volume with the `dataSource` set to `snap://volume-name/snapshot-name`. This will trigger Longhorn to clone the content of the snapshot to the new volume.
  Note that if the source volume is not attached, Longhorn cannot verify the existence of the snapshot inside the Longhorn volume.
  This means that [the API will return error](https://github.com/longhorn/longhorn-manager/blob/878cfb868c568396d6ebfa4ce096c5d95d9b31e3/manager/volume.go#L347-L352) and new PVC cannot be provisioned. 

In [DeleteSnapshot function](https://github.com/longhorn/longhorn-manager/blob/878cfb868c568396d6ebfa4ce096c5d95d9b31e3/csi/controller_server.go#L675):
* Decode the snapshotId in the format from the above step.
  If the type is `longhorn-backup` we delete the backup as before.
  If the type is `longhorn-snapshot`, we delete the corresponding Longhorn snapshot of the source volume.
  If the source volume or the snapshot is no longer exist, we return OK as specified in [the CSI spec](https://github.com/container-storage-interface/spec/blob/master/spec.md#deletesnapshot)

### Test plan

Integration test plan.

1. Deploy the CSI snapshot CRDs, Controller as instructed at https://longhorn.io/docs/1.2.3/snapshots-and-backups/csi-snapshot-support/enable-csi-snapshot-support/
1. Deploy 4 VolumeSnapshotClass:
    ```yaml
    kind: VolumeSnapshotClass
    apiVersion: snapshot.storage.k8s.io/v1beta1
    metadata:
      name: longhorn-backup-1
    driver: driver.longhorn.io
    deletionPolicy: Delete
    ```
    ```yaml
    kind: VolumeSnapshotClass
    apiVersion: snapshot.storage.k8s.io/v1beta1
    metadata:
      name: longhorn-backup-2
    driver: driver.longhorn.io
    deletionPolicy: Delete
    parameters:
      type: longhorn-backup
    ```   
    ```yaml
    kind: VolumeSnapshotClass
    apiVersion: snapshot.storage.k8s.io/v1beta1
    metadata:
      name: longhorn-snapshot
    driver: driver.longhorn.io
    deletionPolicy: Delete
    parameters:
      type: longhorn-snapshot
    ```
    ```yaml
    kind: VolumeSnapshotClass
    apiVersion: snapshot.storage.k8s.io/v1beta1
    metadata:
      name: invalid-class
    driver: driver.longhorn.io
    deletionPolicy: Delete
    parameters:
      type: invalid
    ```
1. Create Longhorn volume `test-vol` of 5GB. Create PV/PVC for the Longhorn volume.
1. Create a workload that uses the volume. Write some data to the volume.
   Make sure data persist to the volume by running `sync`
1. Set up a backup target for Longhorn

#### Scenarios 1: CreateSnapshot
  * `type` is `longhorn-backup` or `""` 
    
    * Create a VolumeSnapshot with the following yaml
      ```yaml
      apiVersion: snapshot.storage.k8s.io/v1beta1
      kind: VolumeSnapshot
      metadata:
        name: test-snapshot-longhorn-backup
      spec:
        volumeSnapshotClassName: longhorn-backup-1
        source:
          persistentVolumeClaimName: test-vol
      ```
    * Verify that a backup is created.
    * Delete the `test-snapshot-longhorn-backup`
    * Verify that the backup is deleted
    * Create the `test-snapshot-longhorn-backup` VolumeSnapshot with `volumeSnapshotClassName: longhorn-backup-2`
    * Verify that a backup is created.
  * `type` is `longhorn-snapshot`
    * volume is in detached state. 
      * Scale down the workload of `test-vol` to detach the volume.
      * Create `test-snapshot-longhorn-snapshot` VolumeSnapshot with `volumeSnapshotClassName: longhorn-snapshot`.
      * Verify the error `volume ... invalid state ... for taking snapshot` in the Longhorn CSI plugin.
    * volume is in attached state. 
      * Scale up the workload to attach `test-vol`
      * Verify that a Longhorn snapshot is created for the `test-vol`.
  * invalid type
    * Create `test-snapshot-invalid` VolumeSnapshot with `volumeSnapshotClassName: invalid-class`.
    * Verify the error `invalid snapshot type: %v. Must be %v or %v or` in the Longhorn CSI plugin.
    * Delete `test-snapshot-invalid` VolumeSnapshot.

#### Scenarios 2: Create new volume from CSI snapshot
  * From `longhorn-backup` type
    * Create a new PVC with the flowing yaml:
      ```yaml
      apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: test-restore-pvc
      spec:
        storageClassName: longhorn
        dataSource:
          name: test-snapshot-longhorn-backup
          kind: VolumeSnapshot
          apiGroup: snapshot.storage.k8s.io
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
      ```
    * Attach the PVC `test-restore-pvc` and verify the data 
    * Delete the PVC
  * From `longhorn-snapshot` type
    * Source volume is attached && Longhorn snapshot exist
        * Create a PVC with the following yaml:
          ```yaml
          apiVersion: v1
          kind: PersistentVolumeClaim
          metadata:
            name: test-restore-pvc
          spec:
            storageClassName: longhorn
            dataSource:
              name: test-snapshot-longhorn-snapshot
              kind: VolumeSnapshot
              apiGroup: snapshot.storage.k8s.io
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 5Gi
          ```
        * Attach the PVC `test-restore-pvc` and verify the data 
        * Delete the PVC
    * Source volume is detached
      * Scale down the workload to detach the `test-vol`
      * Create the same PVC `test-restore-pvc` as in the `Source volume is attached && Longhorn snapshot exist` section
      * Verify that PVC provisioning failed because the source volume is detached so Longhorn cannot verify the existence of the Longhorn snapshot in the source volume.
      * Scale up the workload to attach `test-vol`  
      * Wait for PVC to finish provisioning and be bounded
      * Attach the PVC `test-restore-pvc` and verify the data
      * Delete the PVC
    * Source volume is attached && Longhorn snapshot doesn’t  exist
      * Find the VolumeSnapshotContent of the VolumeSnapshot `test-snapshot-longhorn-snapshot`.
        Find the Longhorn snapshot name inside the field `VolumeSnapshotContent.snapshotHandle`.
        Go to Longhorn UI. Delete the Longhorn snapshot.
      * Repeat steps in the section `Longhorn snapshot exist` above.
        PVC should be stuck in provisioning because Longhorn snapshot of the source volume doesn't exist.
      * Delete the PVC `test-restore-pvc` PVC
  
#### Scenarios 3: Delete CSI snapshot
  * `longhorn-backup` type
    * Done in the above step
  * `longhorn-snapshot` type
    * volume is attached && snapshot doesn’t exist
      * Delete the VolumeSnapshot `test-snapshot-longhorn-snapshot` and verify that the VolumeSnapshot is deleted.
    * volume is attached && snapshot exist
      * Recreate the VolumeSnapshot `test-snapshot-longhorn-snapshot`
      * Verify the creation of Longhorn snapshot with the name in the field `VolumeSnapshotContent.snapshotHandle`
      * Delete the VolumeSnapshot `test-snapshot-longhorn-snapshot` 
      * Verify that Longhorn snapshot is removed or marked as removed
      * Verify that the VolumeSnapshot `test-snapshot-longhorn-snapshot` is deleted.
    * volume is detached
      * Recreate the VolumeSnapshot `test-snapshot-longhorn-snapshot`
      * Scale down the workload to detach `test-vol`
      * Delete the VolumeSnapshot `test-snapshot-longhorn-snapshot`
      * Verify that VolumeSnapshot `test-snapshot-longhorn-snapshot` is stuck in deleting


### Upgrade strategy

No upgrade strategy needed

## Note [optional]

We need to update the docs and examples to reflect the new parameter in the VolumeSnapshotClass, `type`.
