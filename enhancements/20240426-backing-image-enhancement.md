# Backing Image Enhancement

## Summary

This feature enhances the management of BackingImages in Longhorn. With **High Availability**, Longhorn maintains more than one BackingImage copy in the cluster to avoid data loss. Additionally, by incorporating **nodeSelector and diskSelector**, Longhorn can store the BackingImages on specific nodes and disks to improve space efficiency. Lastly, with the addition of **eviction handling**, Longhorn can move the BackingImage to other nodes when users request eviction on the node.

### Related Issues

- https://github.com/longhorn/longhorn/issues/2856
- https://github.com/longhorn/longhorn/issues/6526

## Motivation

### Goals

#### HA
1. A user can set global high available factor for all the BackingImages or specify the number for each BackingIamge.
2. Longhorn will maintain the number of BackingImage copy in the cluster.
3. Longhorn will delete the extra BackingImage copy if it is not used for a while and the number of copy is more than the factor in the cluster.


#### nodeSelector and diskSelector
1. A user can add `nodeSelector` and `diskSelector` when creating BackingImage
2. The BackingImage copies will be located on the nodes and disks with the corresponding `tags`.
3. When the node or disk is disabled for scheduling, the BackingImage copies can't be placed on the node or disk.
4. Replica is not able to be scheduled on the nodes and disks where Backingimage can not be stored.


#### Eviction Handling
1. When a user disables the scheduling and set eviction request on the node or disk, Longhorn will move the BackingImage copies to other nodes or disks.


### Non-goals

#### Eviction Handling When Cordoning or Draining Node.

We only support evicting BackingImage copy when manually set eviction request to the node or disk. That is, if a user want to cordon or drain the node. Longhorn won't evict the BackingImage copies automatically like what it does for the Replicas. In this case, the user needs to set eviction request to the node or disk first before draining the node.

The reason is that we will need to set PDB to protect BackingImageManager from deleting during draining process. It increases the complexity of the process and adding risk of stucking in the process.

## Proposal

### User Stories

#### HA
Before this feature, users might lose the BackingImage copy if the node that holds the only copy in the cluster crashes or gets drained. Users then need to prepare the BackingImage again.

With this feature, Longhorn maintains the number of copy in the cluster to reduce the possibility of the data loss.

#### Node Selector and Disk Selector

Before this feature, Longhorn stores the BackingImage copy on a random node and a random disk. When a replica needs the BackingImage, Longhorn needs to copy the BackingImage to the disk where replica is.

Similar to Volume Replicas scheduling, with adding `nodeSelector` and `diskSelector` to the BackingImage, Longhorn will place the BackingImage copies to the specific nodes or disks. BackingImages will be stored in the same set of nodes and disks as Replicas if they have the same `nodeSelector` and `diskSelector`. It improves space efficiency.


#### Replica Scheduling

Since replica won't be able to start on the node where BackingImage can not be stored. Thus, we will not schedule the replica to the node and disk where the BackingImage can not be stored because of the `nodeSelector` and `diskSelector`.

#### Eviction Handling

Before this feature, Longhorn won't move the BackingImage copies to other nodes when the node is set to eviction requested.

With this feature, a user can manually request eviction on the node or disk to evict all the BackingImage copies to other nodes and disks. 


### API changes

## Design - HA

### Implementation Overview

#### CRD

- Add `numOfCopies` to BackingImage

#### BackingImage Controller

- After first BackingImage is ready, the controller starts maintaining the number of copies in the clusters.
- If the number is lower, then the controller picks another valid node and disk for the BackingImage copy. Increase one every time until it is equal or larger than the number.
- If the copy is not used for a while and the number of copy is larger than the setting, Longhorn deletes the unused BackingImage copies. (already implemented before: [ref](https://github.com/longhorn/longhorn-manager/blob/v1.6.1/controller/node_controller.go#L1152))

## Design - NodeSelector and DiskSelector

### Implementation Overview

#### CRD

- Add `diskSelector` and `nodeSelector` to the BackingImage

#### BackingImage Controller

- When selecting node/disk for the BackingImage, Longhorn needs to follow the `diskSelector` and `nodeSelector` settings.

#### Replica Scheduler

- For the node candidates and the disk candidates, we also check if they are available for the BackingImage used by the Replica. If the BackingImage can not be stored on the node or the disk, we will not schedule the Replica to the node either.


## Design - Eviction Handling

### Implementation Overview

#### CRD

- Change the BackingImage Spec to add `EvictionRequested` for each BackingImage copy on disk.
```
type BackingImageSpec struct {
	Disks map[string]string `json:"disks"`
	Checksum string `json:"checksum"`
	SourceType BackingImageDataSourceType `json:"sourceType"`
	SourceParameters map[string]string `json:"sourceParameters"`
}
```

```
type BackingImageSpec struct {
	Disks map[string]*BackingImageDiskFileSpec `json:"disks"`
	Checksum string `json:"checksum"`
	SourceType BackingImageDataSourceType `json:"sourceType"`
	SourceParameters map[string]string `json:"sourceParameters"`
}

type BackingImageDiskFileSpec struct {
	EvictionRequested bool `json:"evictionRequested"`
}
```

##### Node Controller 
- When the node or disk is set to `evictionRequested = true`, node controller will update EvictionRequested for all the BackingImage copy on the node.


#### BackingImage
- `replenishBackingImageCopies()`
    - if `nonFailedCopies >= MinNumberOfCopies`, we check if we need to replenish one copy for eviction
        - replenish one if `NonEvictingCount < MinNumberOfCopies`
    - if `nonFailedCopies < MinNumberOfCopies`
        - replenish one copy to meet the MinNumberOfCopies requirement.
- `cleanupEvictionRequestedBackingImageCopies()`
    - If there is no non evicted healthy copy, don't delete the copy.
    - Otherwise, delete the evicted copy. 

---

### Test plan

1. HA
    - Create a BackingImage with `minNumberOfCopies = 2`
    - After creation, it will sync the file to another node/disk immediately
    - Update the `Backing Image Cleanup Wait Interval to 1 min`
    - Update the `minNumberOfCopies = 1`
    - The extra Backing Image will be cleaned up

2. nodeSelector/diskSelector
    - Set node1 with `nodeTag: [node1], diskTag:[disk1]`
    - Create a BackingImage with 
        - `minNumberOfCopies = 2`
        - `nodeSelector = [node1]`
        - `diskSelector = [disk1]`
    - After creation, the first BackingImage copy will be on node1, disk1
    - But the second one will never show up
    - The log will show `unable to get a ready node disk`

3. Different nodeSelector and diskSelector as Replicas (Negative Test)
    - Set `nodeTag: [node1], diskTag: [disk1]` to node1/disk1
    - Set `nodeTag: [node2], diskTag: [disk2]` to node2/disk2
    - Create a BackingImage with following specs
        - `minNumberOfCopies = 1`
        - `nodeSelector = [node1]`
        - `diskSelector = [disk1]`
    - Create a Volume with following specs and attach to node2
        - `numberOfReplicas = 1`
        - `nodeSelector = [node2]`
        - `diskSelector = [disk2]`
    - The volume condition `Scheduled` will be `false` because the replica is not able to be scheduled. 
    
    
3. Eviction - 1
    - Create BackingImage with one copy
    - Evict the node where copy is on
    - The BackingImage will first create another copy in another node
    - The evicted copy will be deleted 

4. Eviction - 2
    - Set BackingImage `minNumberOfCopies=1`
    - Create BackingImage with two copies
    - Evict the node where one of the copy is on
    - The evicted copy will be deleted

5. Eviction - 3 (Negative Test)
    - Set nodeTag: [node1], diskTag:[disk1]
    - Create a BackingImage with following settings to place the copy on node1 
        - `minNumberOfCopies = 1`
        - `nodeSelector = [node1]`
        - `diskSelector = [disk1]`
    - Evict node1
    - The copy would not be deleted because it is the only copy
    - The copy can't be duplicated to other nodes because of the selector settings.


### Upgrade strategy

None

## Note [optional]

Additional notes.