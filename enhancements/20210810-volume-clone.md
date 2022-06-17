# Support CSI Volume Cloning

## Summary

We want to support CSI volume cloning so users can create a new PVC that has identical data as a source PVC.


### Related Issues

https://github.com/longhorn/longhorn/issues/1815

## Motivation

### Goals

* Support exporting the snapshot data of a volume
* Allow user to create a PVC with identical data as the source PVC

## Proposal

There are multiple parts in implementing this feature:

### Sparse-tools
Implement a function that fetches data from a readable object then sends it to a remote server via HTTP.

### Longhorn engine
* Implementing `VolumeExport()` gRPC in replica SyncAgentServer.
  When called, `VolumeExport()` exports volume data at the input snapshot to the receiver on the remote host.
* Implementing `SnapshotCloneCmd()` and `SnapshotCloneStatusCmd()` CLIs. Longhorn manager can trigger the volume cloning process by 
  calling `SnapshotCloneCmd()` on the replica of new volume.
  Longhorn manager can fetch the cloning status by calling `SnapshotCloneStatusCmd()` on the replica of the new volume.

### Longhorn manager

* When the volume controller detects that a volume clone is needed, it will attach the target volume.
  Start 1 replica for the target volume. 
  Auto-attach the source volume if needed.
  Take a snapshot of the source volume.
  Copy the snapshot from a replica of the source volume to the new replica by calling `SnapshotCloneCmd()`.
  After the snapshot was copied over to the replica of the new volume, the volume controller marks volume as completed cloning. 
    
* Once the cloning is done, the volume controller detaches the source volume if it was auto attached. 
  Detach the target volume to allow the workload to start using it. 
  Later on, when the target volume is attached by workload pod, Longhorn will start rebuilding other replicas. 

### Longhorn CSI plugin
* Advertise that Longhorn CSI driver has ability to clone a volume, `csi.ControllerServiceCapability_RPC_CLONE_VOLUME`
* When receiving a volume creat request, inspect `req.GetVolumeContentSource()` to see if it is from another volume.
  If so, create a new Longhorn volume with appropriate `DataSource` set so Longhorn volume controller can start cloning later on.


### User Stories

Before this feature, to create a new PVC with the same data as another PVC, the users would have to use one of the following methods:
1. Create a backup of the source volume. Restore the backup to a new volume. 
   Create PV/PVC for the new volume. This method requires a backup target.
   Data has to move through an extra layer (the backup target) which might cost money.
1. Create a new PVC (that leads to creating a new Longhorn volume). 
   Mount both new PVC and source PVC to the same pod then copy the data over.
   See more [here](https://github.com/longhorn/longhorn/blob/v1.1.2/examples/data_migration.yaml).
   This copying method only applied for PVC with `Filesystem` volumeMode. Also, it requires manual steps.
   
After this cloning feature, users can clone a volume by specifying `dataSource` in the new PVC pointing to an existing PVC.

### User Experience In Detail

Users can create a new PVC that uses `longhorn` storageclass from an existing PVC which also uses `longhorn` storageclass by
specifying `dataSource` in new PVC pointing to the existing PVC:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
    name: clone-pvc
    namespace: myns
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 5Gi
  dataSource:
    kind: PersistentVolumeClaim
    name: source-pvc
```

### API changes

`VolumeCreate` API will check/validate data a new field, `DataSource` which is a new field in `v.Spec` that 
specifies the source of the Longhorn volume.

## Design

### Implementation Overview

### Sparse-tools
Implement a generalized function, `SyncContent()`, which syncs the content of a `ReaderWriterAt` object to a file on remote host.
The `ReaderWriterAt` is interface that has `ReadAt()`, `WriteAt()` and `GetDataLayout()` method:
```go
type ReaderWriterAt interface {
 	io.ReaderAt
 	io.WriterAt
 	GetDataLayout (ctx context.Context) (<-chan FileInterval, <-chan error, error)
 }
```
Using those methods, the Sparse-tools know where is a data/hole interval to transfer to a file on the remote host.

### Longhorn engine
* Implementing `VolumeExport()` gRPC in replica SyncAgentServer. When called, `VolumeExport()` will:
  * Create and open a read-only replica from the input snapshot
  * Pre-load `r.volume.location` (which is the map of data sector to snapshot file) by:
    * If the volume has backing file layer and users want to export the backing file layer, 
      we initialize all elements of `r.volume.location` to 1 (the index of the backing file layer).
      Otherwise, initialize all elements of `r.volume.location` to 0 (0 means we don't know the location for this sector yet)
    * Looping over `r.volume.files` and populates `r.volume.location` (which is the map of data sector to snapshot file) with correct values.
  * The replica is able to know which region is data/hole region. 
    This logic is implemented inside the replica's method `GetDataLayout()`.
    The method checks `r.volume.location`. 
    The sector at offset `i` is in data region if `r.volume.location[i] >= 1`. 
    Otherwise, the sector is inside a hole region.
  * Call and pass the read-only replica into `SyncContent()` function in the Sparse-tools module to copy the snapshot to a file on the remote host. 
    
* Implementing `SnapshotCloneCmd()` and `SnapshotCloneStatusCmd()` CLIs. 
  * Longhorn manager can trigger the volume cloning process by calling `SnapshotCloneCmd()` on the replica of the new volume.
    The command finds a healthy replica of the source volume by listing replicas of the source controller and selecting a `RW` replica.
    The command then calls `CloneSnapshot()` method on replicas of the target volumes. This method in turn does:
    * Call `SnapshotClone()` on the sync agent of the target replica. 
      This will launch a receiver server on the target replica. 
      Call `VolumeExport()` on the sync agent of the source replica to export the snapshot data to the target replica.
      Once the snapshot data is copied over, revert the target replica to the newly copied snapshot.
  * Longhorn manager can fetch cloning status by calling `SnapshotCloneStatusCmd()` on the target replica.

### Longhorn manager
* Add a new field to volume spec, `DataSource`. The `DataSource` is of type `VolumeDataSource`. 
  Currently, there are 2 types of data sources: `volume` type and `snapshot` type. 
  `volume` data source type has the format `vol://<VOLUME-NAME>`.
  `snapshot` data source type has the format `snap://<VOLUME-NAME>/<SNAPSHOT-NAME>`.
  In the future, we might want to refactor `fromBackup` field into a new type of data source with format `bk://<VOLUME-NAME>/<BACKUP-NAME>`.
  
* Add a new field into volume status, `CloneStatus` of type `VolumeCloneStatus`:
  ```go
    type VolumeCloneStatus struct {
        SourceVolume string           `json:"sourceVolume"`
        Snapshot     string           `json:"snapshot"`
        State        VolumeCloneState `json:"state"`
    }
    type VolumeCloneState string
    const (
        VolumeCloneStateEmpty          = VolumeCloneState("")
        VolumeCloneStateInitiated      = VolumeCloneState("initiated")
        VolumeCloneStateCompleted      = VolumeCloneState("completed")
        VolumeCloneStateFailed         = VolumeCloneState("failed")
    )
  ```
  
* Add a new field into engine spec, `RequestedDataSource` of type `VolumeDataSource`
  
* Add a new field into engine status, `CloneStatus`. 
  `CloneStatus` is a map of `SnapshotCloneStatus` inside each replica:
    ```go
    type SnapshotCloneStatus struct {
        IsCloning          bool   `json:"isCloning"`
        Error              string `json:"error"`
        Progress           int    `json:"progress"`
        State              string `json:"state"`
        FromReplicaAddress string `json:"fromReplicaAddress"`
        SnapshotName       string `json:"snapshotName"`
    }
    ```  
  This will keep track of status of snapshot cloning inside the target replica.
* When the volume controller detect that a volume clone is needed 
  (`v.Spec.DataSource` is `volume` or `snapshot` type and `v.Status.CloneStatus.State == VolumeCloneStateEmpty`), 
  it will auto attach the source volume if needed.
  Take a snapshot of the source volume if needed.
  Fill the `v.Status.CloneStatus` with correct value for `SourceVolume`, `Snapshot`, and `State`(`initiated`).
  Auto attach the target volume.
  Start 1 replica for the target volume.
  Set `e.Spec.RequestedDataSource` to the correct value, `snap://<SOURCE-VOL-NAME/<SNAPSHOT-NAME>`.
  
* Engine controller monitoring loop will start the snapshot clone by calling `SnapshotCloneCmd()`. 
  
* After the snapshot is copied over to the replica of the new volume, volume controller marks `v.Status.CloneStatus.State = VolumeCloneStateCompleted`
  and clear the `e.Spec.RequestedDataSource`

* Once the cloning is done, the volume controller detaches the source volume if it was auto attached.
  Detach the target volume to allow the workload to start using it.
  
* When workload attach volume, Longhorn starts rebuilding other replicas of the volume.

### Longhorn CSI plugin
* Advertise that Longhorn CSI driver has ability to clone a volume, `csi.ControllerServiceCapability_RPC_CLONE_VOLUME`
* When receiving a volume creat request, inspect `req.GetVolumeContentSource()` to see if it is from another volume.
  If so, create a new Longhorn volume with appropriate `DataSource` set so Longhorn volume controller can start cloning later on.

### Test plan

Integration test plan.

#### Clone volume that doesn't have backing image
1. Create a PVC:
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
1. Specify the `source-pvc` in a pod yaml and start the pod
1. Wait for the pod to be running, write some data to the mount path of the volume
1. Clone a volume by creating the PVC:
    ```yaml
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: cloned-pvc
    spec:
      storageClassName: longhorn
      dataSource:
        name: source-pvc
        kind: PersistentVolumeClaim
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 10Gi
    ```
1. Specify the `cloned-pvc` in a cloned pod yaml and deploy the cloned pod
1. Wait for the `CloneStatus.State` in `cloned-pvc` to be `completed`
1. In 3-min retry loop, wait for the cloned pod to be running
1. Verify the data in `cloned-pvc` is the same as in `source-pvc`
1. In 2-min retry loop, verify the volume of the `clone-pvc` eventually becomes healthy
1. Cleanup the cloned pod, `cloned-pvc`. Wait for the cleaning to finish
1. Scale down the source pod so the `source-pvc` is detached. 
1. Wait for the `source-pvc` to be in detached state
1. Clone a volume by creating the PVC:
    ```yaml
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: cloned-pvc
    spec:
      storageClassName: longhorn
      dataSource:
        name: source-pvc
        kind: PersistentVolumeClaim
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 10Gi
    ```
1. Specify the `cloned-pvc` in a cloned pod yaml and deploy the cloned pod
1. Wait for `source-pvc` to be attached
1. Wait for a new snapshot created in `source-pvc` volume created
1. Wait for the `CloneStatus.State` in `cloned-pvc` to be `completed`
1. Wait for `source-pvc` to be detached
1. In 3-min retry loop, wait for the cloned pod to be running
1. Verify the data in `cloned-pvc` is the same as in `source-pvc`
1. In 2-min retry loop, verify the volume of the `clone-pvc` eventually becomes healthy
1. Cleanup the test

#### Clone volume that has backing image
1. Deploy a storage class that has backing image parameter
  ```yaml
  kind: StorageClass
  apiVersion: storage.k8s.io/v1
  metadata:
    name: longhorn-bi-parrot
  provisioner: driver.longhorn.io
  allowVolumeExpansion: true
  parameters:
    numberOfReplicas: "3"
    staleReplicaTimeout: "2880" # 48 hours in minutes
    backingImage: "bi-parrot"
    backingImageURL: "https://longhorn-backing-image.s3-us-west-1.amazonaws.com/parrot.qcow2"
  ```
Repeat the `Clone volume that doesn't have backing image` test with `source-pvc` and `cloned-pvc` use `longhorn-bi-parrot` instead of `longhorn` storageclass

#### Interrupt volume clone process

1. Create a PVC:
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
1. Specify the `source-pvc` in a pod yaml and start the pod
1. Wait for the pod to be running, write 1GB of data to the mount path of the volume
1. Clone a volume by creating the PVC:
    ```yaml
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: cloned-pvc
    spec:
      storageClassName: longhorn
      dataSource:
        name: source-pvc
        kind: PersistentVolumeClaim
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 10Gi
    ```
1. Specify the `cloned-pvc` in a cloned pod yaml and deploy the cloned pod
1. Wait for the `CloneStatus.State` in `cloned-pvc` to be `initiated`
1. Kill all replicas process of the `source-pvc`
1. Wait for the `CloneStatus.State` in `cloned-pvc` to be `failed`
1. In 2-min retry loop, verify cloned pod cannot start
1. Clean up cloned pod and `clone-pvc`
1. Redeploy `cloned-pvc` and clone pod   
1. In 3-min retry loop, verify cloned pod become running
2. `cloned-pvc` has the same data as `source-pvc`   
1. Cleanup the test

### Upgrade strategy

No upgrade strategy needed

