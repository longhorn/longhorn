# Disk Reconnection

## Summary
When disks are reconnected/migrated to other Longhorn nodes, Longhorn should be able to figure out the disk reconnection and update the node ID as well as the data path for the related replicas (including failed replicas). 

### Related Issues
https://github.com/longhorn/longhorn/issues/1269

## Motivation
### Goals
The goal of this feature is to reuse the existing data of the failed replica when the corresponding disk is back. 

### Non-Goals
As for how to reuse the existing data and handle rebuild related feature, it is already implemented in #1304, which is not the intention of this enhancement.

## Proposal
Identifying the disk that is previously used in Longhorn is not the the key point. The essential of this feature is that Longhorn should know where to reuse existing data of all related replicas when the disk is reconnected.
In other words, the fields that indicating the replica data position should be updated when the disk is reconnected.

### User Stories
#### Migrate the existing disks to new nodes
Before the enhancement, there is no way to reuse the existing data when a disk is reconnected/migrated. 

After the enhancement, this can be done by:
1. detach the volumes using the disk
2. Reconnect the disk to the another node (both nodes keep running)
3. reattach the related volumes

#### Scale down the node but reuse the disks on the node
Before the enhancement, there is no chance to reuse the failed replicas on the node.

After the enhancement, Longhorn will update the path and node id for all failed replicas using the disks, then Longhorn can reuse the failed replicas during rebuilding.

### User Experience In Detail
#### Migrate the existing disks to new nodes
1. Detach all related volumes using the disk before the disk migration.
2. Directly move the disk to the new node (physically or in cloud vendor) and mount the disk.
3. Add the disk with the new mount point to the corresponding new Longhorn node in Longhorn Node page.
4. Attach the volumes for the workloads.

#### Scale down the node but reuse the disks on the node
1. Directly shut down the node when there are replicas on the node. Then the replicas on the node will fail.
2. Move the disks on the down node to other running nodes (physically or in cloud vendor).
3. Add the disk with the new mount point to the corresponding new Longhorn node in Longhorn Node page.
4. Wait then verify the failed replicas using the disk will be reused, and the node ID & path info will be updated.

### API Changes
There is no API change.

## Design
### Implementation Overview
#### longhorn-manager:
1. When a disk is ready, Longhorn can list all related replicas via `replica.Spec.DiskID` then sync up node ID and path info for these replicas.
    - If a disk is not ready, the scheduling info will be cleaned up. Longhorn won't be confused of updating replicas if multiple disconnected disks using the same Disk UUID.
    - Need to add a disk related label for replicas. 
2. Store DiskUUID rather than the disk name in `replica.Spec.DiskID`
    - Need to update `DiskID` for existing replicas during upgrade.
3. Since the disk path of a replica may get changed but the data directory name is immutable. It's better to split `replica.Spec.DataPath` to `replica.Spec.DiskPath` and `replica.Spec.DataDirectoryName`. Then it's more convenient to sync up the disk path for replicas.
    - Need to update the path fields for existing replicas during upgrade.

### Test Plan
#### Integration Tests
##### Disk migration
1. Disable the node soft anti-affinity.
2. Create a new host disk.
3. Disable the default disk and add the extra disk with scheduling enabled for the current node.
4. Launch a Longhorn volume with 1 replica. 
   Then verify the only replica is scheduled to the new disk.
5. Write random data to the volume then verify the data.
6. Detach the volume.
7. Unmount then remount the disk to another path. (disk migration)
8. Create another Longhorn disk based on the migrated path.
9. Verify the Longhorn disk state.
   - The Longhorn disk added before the migration should become "unschedulable".
   - The Longhorn disk created after the migration should become "schedulable".
10. Verify the replica DiskID and the path is updated.
11. Attach the volume. Then verify the state and the data.

#### Manual Tests
##### Some Longhorn worker nodes in AWS Auto Scaling group is in replacement
1. Set `ReplicaReplenishmentWaitInterval`. Make sure it's longer than the time needs for node replacement.
2. Launch a Kubernetes cluster with the nodes in AWS Auto Scaling group. Then Deploy Longhorn.
3. Deploy some workloads using Longhorn volumes.
4. Wait for/Trigger the ASG instance replacement.
5. Verify new replicas won't be created before reaching `ReplicaReplenishmentWaitInterval`.
6. Verify the failed replicas are reused after the node recovery.
7. Verify if workloads still work fine with the volumes after the recovery.

##### Longhorn upgrade with node down and removal
1. Launch Longhorn v1.0.x
2. Create and attach a volume, then write data to the volume.
3. Directly remove a Kubernetes node, and shut down a node.
4. Wait for the related replicas failure. Then record `replica.Spec.DiskID` for the failed replicas.
5. Upgrade to Longhorn master
6. Verify the Longhorn node related to the removed node is gone.
7. Verify 
    1. `replica.Spec.DiskID` on the down node is updated and the field of the replica on the gone node is unchanged.
    2.  `replica.Spec.DataPath` for all replicas becomes empty.
8. Remove all unscheduled replicas.
9. Power on the down node. Wait for the failed replica on the down node being reused.
10. Wait for a new replica being replenished and available.

### Upgrade strategy
Need to update disk ID and data path for existing replicas.
