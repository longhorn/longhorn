# Identify Disk Reconnection

## Summary
When disks are reconnected to other Longhorn nodes, Longhorn should be able to figure out the disk reconnection and update the node ID, disk ID as well as the data path for the related replicas (including failed replicas). 

### Related Issues
https://github.com/longhorn/longhorn/issues/1269

## Motivation
### Goals
The ultimate goal of this feature and [#1304](https://github.com/longhorn/longhorn/issues/1304) is to reuse the existing data to speed up replica rebuild as well as save bandwidth. 
As the first step, Longhorn should identify the reconnected disks which contain the existing data left by the failed replicas. 
Then Longhorn needs to make sure the failed replicas are still able to find out the data after the disk migration.
Finally, there is an opportunity to reuse the existing data to rebuild new replicas with the existing data.

### Non-Goals
As for how to reuse the existing data and handle rebuild related feature, it will be left to #1304, which is not the intention of this enhancement.

## Proposal
1. Use separate CRD resources to manage disk lifecycle, so that the disks and nodes are decoupled. Then there is a chance to reuse replica data on the disks:
    1. The new disk objects will be created automatically (as the default/customized disks) when a Longhorn node is introduced.
    2. The disk creation/deletion/update calls will be separated from the node editing. 
    3. Launch Disk Controller to monitor and update the disk.
    4. When a physical disk previously used by Longhorn is reconnected to a node, Longhorn should be able to figure it out and update all replicas using the disk.
2. Modify the node deletion logic.
    1. Right now the ownership of replicas is taken by disk rather than node. We can remove the replica check in the node deletion function.
    2. We can add an setting `Retain disks during node deletion` to determine if Longhorn needs to clean up disks.
3. As long as the failed replicas is not cleaned up (it depends on the replica stale timeout), Longhorn may ba able to reuse the data of the failed replicas later.

### User Stories
#### Migrate the existing disks to new nodes
Before the enhancement, users need to:
1. disable the scheduling for the disk
2. attach all volumes using the disk
3. disable scheduling then evict the disk (this guarantees the HA)
4. reconnect the disk to another node

After the enhancement, this can be done by:
1. detach the volumes using the disk
2. Reconnect the disk to the another node (both nodes keep running)
3. reattach the related volumes

#### Scale down the node but reuse the disks on the node
Before the enhancement, there is no chance to reuse the failed replicas on the node.

After the enhancement, the node ID of all failed replicas on the node will be updated once the related disks are reconnected to other running nodes. Then the data of those failed replicas can be reused after implementing #1304.

### User Experience In Detail
#### Migrate the existing disks to new nodes
1. Detach all related volumes using the disk before the disk migration.
2. Directly move the disk to the new node (physically or in cloud vendor) and mount the disk.
3. Click `Connect Disk` with new the mount point and the new node ID in Longhorn Node page.
4. Attach the volumes for the workloads.

#### Scale down the node but reuse the disks on the node
1. Directly shut down the node when there are replicas on the node. Then the replicas on the node will fail.
2. Move the disks on the down node to other running nodes (physically or in cloud vendor).
3. Click `Connect Disk` with new the mount point and the new node ID in Longhorn Node page.
4. Wait then verify the node ID of the failed replicas will be updated.
5. Longhorn will reuse the failed replicas to speed up the rebuilding once the feature [#1304](https://github.com/longhorn/longhorn/issues/1304) is done.

### API Changes
Disk related HTTP APIs are required.

## Design
### Implementation Overview
#### longhorn-manager:
1. Create a CRD for `disk`.
    1. The field `Disks` and `DiskStatus` will be deprecated from `NodeSpec` and `NodeStatus`, respectively. 
    2. A new field `NodeID` will be added to `DiskSpec`. It will be set during the disk creation.
    3. A new field `State` will be added to `DiskStatus`. The state of a disk is always `connected` or `disconnected`.
2. Add a new setting `Retain disks during node deletion`.
3. Create disk HTTP API calls. And separate the disk related logic from the node API if necessary.
    1. The disk creation call will blindly create the disk objects for active nodes.
    2. The disk deletion function will be responsible for setting the deletion timestamp the disk objects.
    3. The node creation call will invoke the disk creation function for default/customized disks.
    4. The node deletion call may invoke the disk deletion function based on the setting `Retain disks during node deletion`.
4. Launch Disk Controller to handle the disk status monitoring and update.
    1. Move the disk update logic from Node Controller to Disk Controller.
    2. `DiskStatus.State` will be `DiskStateDisconnected` in one of the following cases:
        1. The disk is not handled by the conroller  of the preferred node (disk.Spec.NodeID). in Disk Controller: If `DiskSpec.NodeID` is empty or the related node is down, the state . Otherwise, the state is `DiskStateConnected`.
        2. The preferred node is down or deleted.
        3. The disk info cannot be fetched.
        4. There is another disk has the same FSID or DiskUUID.
    3. When there is an existing DiskUUID (meta file) in the new disk and this UUID is still used in a disconnected disk, it means the physical disk is migrated. In this case, we need to transfer the ownership of the related replicas and update the replica fields so that the new disk can take care of those replicas. 
       Then the field `Status.DiskUUID` will be cleaned up for the existing disconnected disk.
    4. The running replicas will be marked as failure if the related disk beomces `disconnected`.
5. Need to update nodes and replicas as well as create disks for Longhorn v1.1.0 upgrade. 

#### longhorn-ui:
1. Group all disconnected disks into a special list. Then present it in Node Page, too.
2. Add button `Operation` for each disk, which contains the following calls:
    1. `Delete`: Add warning "Directly deleting the disk will fail replicas using the disk".
    2. `Update`: This call receives 3 inputs `AllowScheduling`, `EvictionRequested`, `StorageReserved`, and `Path`.
3. Rename button `Edit Node and Disks` to `Edit Node`. And remove disk related operations from the node editing page.
4. Add button `Connect Disk` at the top right of Node Page.
    1. Input `Name` is optional.
    2. Input `Path` and `NodeID` are required.
    3. Input `AllowScheduling` and `EvictionRequested` are True and False by default, respectively. 

### Test Plan
##### Disk migration
1. Add an extra disk for a Kubernetes worker node.
2. Connect the disk to the Longhorn node via UI or [the node annotations](https://longhorn.io/docs/1.0.2/advanced-resources/default-disk-and-node-config/#launch-longhorn-with-multiple-disks).
3. Disable the default disk for the nodes containing extra disks.
4. Create and attach a 3-replica volume. Make sure there is one replica using the extra disk.
5. Write data to the volume and get the checksum.
6. Detach the volume.
7. Migrate the extra disk used by the volume replica to another worker node (in the cloud vendor management platform).
8. Connect the disk with the new mount path and new node ID in Node Page.
9. Verify the old Longhorn disk object using the extra path becomes `disconnected`. And the new Longhorn disk object using the extra path is `connected`. 
10. Attach the volume. Verify the volume works fine and there is no failed replica.
11. Verify the data. 

##### Scale down the node but reuse the disks on the node
1. Launch Longhorn in a 3-node cluster.
2. Connect an extra disk with scheduling enabled for one worker node Node1, and disable the default disk for Node1.
3. Create and attach a 3-replica volume. Write data to the volume. (Make sure the volume is not attached to Node1.)
4. Shut down the worker node.
5. Move the extra disk used by the volume replica to another worker node Node2 (in the cloud vendor management platform). 
6. Disconnect the disk then reconnect it to the corresponding Longhorn node Node2 in Node Page.
7. Verify there is a failed replica. And the node ID of the failed replica is updated to Node2.

##### Longhorn upgrade
1. Deploy Longhorn v1.0.2.
2. Launch some volumes and write data.
3. Upgrade Longhorn to the latest version.
4. Make sure the disk count is unchanged and there is no disconnected disk.
5. Verify all volumes work fine, and the related data is correct.
6. Verify volume CRUD work fine.

### Upgrade strategy
No special upgrade strategy is required.

### Notes
The hard anti-affinity restriction will be broken for the existing volumes after the disk migration.
