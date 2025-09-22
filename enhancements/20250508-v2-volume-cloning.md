# V2 Volume Cloning

## Summary

Support volume cloning feature for v2 data engine volumes

### Related Issues

https://github.com/longhorn/longhorn/issues/7794

## Motivation

### Goals

This ticket has 2 goals:
1. Regular cloning in which the data is decoupled from the source volume.
1. Fast cloning in which data is depended on the source volume.
   There should be zero data copy in this case and clone should be instant.

Optionally, this feature can also serve as the foundation for v2 volume exporting/downloading 

## Proposal

### User Stories

#### Story 1 - Regular v2 cloning

User are using Longhorn v2 data engine volumes. 
They want to create a new independent volume from a snapshot of the source volume.
Before this feature, the user can only do it with v1 data engine volume.
Main use case for this one is general CSI cloning and Harvester VM image feature.


#### Story 2 - Fast v2 cloning

User are using Longhorn with some external backup solution such as Kasten or Velero.
These solution want to take a snapshot of a volume.
Then quickly clone that snapshot into a new PVC.
Then read data of the new snapshot and upload it to backup store such as S3 object store.
The fast cloning feature will help improve efficiency for this use case.

### User Experience In Detail

### API changes

#### Longhorn API
Add a new field into `volume.Spec` to indicate whether user wants a fast cloning or regular cloning for a new volume provisioned from a snapshot of other volume.
For example:
```go
type VolumeSpec struct {
  // +optional 
  DataSource VolumeDataSource `json:"dataSource"`
  // +kubebuilder:validation:Enum=fast;full;decoupled
  // +optional 
  CloneMode bool `json:"cloneMode"`
}
```
With:
1. `CloneMode: fast`: Longhorn should perform fast clone 
1. `CloneMode: full`: Longhorn should perform regular clone
1. `CloneMode: decoupled`: If the user initially clone the volume by fast clone, the volume are dependent on the source volume's snapshot. 
    There are a few restriction for a volume in this mode (see below section for more detail).
    The user can change the mode to `decoupled` which will make the volume become independent of the source snapshot. 

#### SPDK API

Implement a new SPDK feature/APIs:
1. `bdev_lvol_start_deep_copy` will transfer the clusters which are either owned by the target snapshot or its parent. 
   Therefore, the new cloning volume are kept thin provisioned.
1. `bdev_lvol_check_deep_copy` will check the status of the deep copy operation

## Design

### Regular v2 cloning

Requirements and assumptions:
1. The data is decoupled from the source volume
1. The newly target volume can have multiple replicas
1. The replicas of the target volume can live in different nodes/disks than the replicas of the source volume
1. Should consume minimal space / network bandwidth / CPU consumption during and after the cloning

Main use case for this one is general CSI cloning and Harvester VM image feature:
* User want to create a new PVC from a CSI snapshot
* Harvester want to create a new root disk from a golden image.
  This will integrate well with the new Harvester's general image management feature.
  A.K.A This can serve as an alternative to the Longhorn v2 backing image feature

Flow:
1. User create a new volume with:
    ```yaml
    volumeSpec:
      dataSource: "snap://source-volume/source-snapshot-1"
      cloneMode: "full"
    ```
1. Longhorn manager create a new volume with 1 replica and schedule the replica to a suitable node
1. Longhorn manager send the clone GRPC to the replica server 
1. Replica server then call SPDK API `bdev_lvol_start_deep_copy` (see [definition of this API above](#spdk-api)) to copy the data from the source snapshot `source-snapshot-1` into the new snapshot of the replica
1. Replica server periodically check the status of the transfer using `bdev_lvol_check_deep_copy` (see [definition of this API above](#spdk-api)) SPDK API
1. Once the data was transfer replica server reloads
1. Volume controller then rebuild more replica for the volume to meet the HA requirement

### Fast v2 cloning

Requirements and assumptions:
1. There should be zero data copy in this case and clone should be instant
1. The data is depended on the source volume
1. The newly target volume can only have 1 replica. 
   And the replica of the target volume must be on same disk as one of the replica of the source volume
1. Replica cannot move to new node and cannot be rebuilt 
1. All restriction can be removed if the user decouple the volume (see [Decoupled a fast v2 cloned volume](#decoupled-a-fast-v2-cloned-volume) )

Main use case for this is external backup operation like Kasten or Velero which only need to read the data once and delete the cloned volume

Flow:
1. User create a new volume with:
    ```yaml
    volumeSpec:
      dataSource: "snap://source-volume/source-snapshot-1"
      cloneMode: "fast"
    ```
1. Longhorn manager create a new volume with 1 replica and schedule the replica to the node which has a healthy replica of the source volume
1. Longhorn manager send the clone GRPC to the replica server
1. Replica server then call SPDK API `bdev_lvol_snapshot` to create new snapshot `source-snapshot-1-clone-entry-point` from source snapshot `source-snapshot-1`
1. Replica server then call SPDK API `bdev_lvol_clone` to create new lvol as a clone of the snapshot `source-snapshot-1-clone-entry-point`
1. Replica server reloads
1. Clone finished 
1. The source volume should ignore the all snapshot with the name `*-entry-point` and its children when building snapshot tree or rebuilding

See more details about the flow at [here](./assets/v2-volume-cloning/longhorn-v2-fast-cloning.pdf)

### Decoupled a fast v2 cloned volume

Requirements and assumptions:
1. A volume is create in fast clone mode
1. It has [restrictions](#fast-v2-cloning) above 
1. If wanted, user can remove the restriction by performing volume decouple

Flow:

Continue from the flow in the section [Fast v2 cloning](#fast-v2-cloning) above
1. User update the volume with:
    ```yaml
    volumeSpec:
      dataSource: "snap://source-volume/source-snapshot-1"
      cloneMode: "decoupled"
    ```
1. Longhorn manager send the gRPC to the replica server
1. Replica server find the root snapshot which is the child of the snapshot `source-snapshot-1-clone-entry-point`
1. Replica server then call SPDK API `bdev_lvol_decouple_parent` repeatedly to decouple it from all of the parents
1. If the snapshot `source-snapshot-1-clone-entry-point` as no more child, it is removed
1. The decoupling finished
1. All restrictions are removed 



### Test plan

TODO

### Upgrade strategy

No upgrade strategy is need 

## Note [optional]

Additional notes.
