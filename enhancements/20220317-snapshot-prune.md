# Snapshot Prune

## Summary
Snapshot prune is a new snapshot-purge-related operation that helps **reclaim some space** from the snapshot file that is already marked as _Removed_ but **cannot be completely deleted**. This kind of snapshot is typically the one directly stands behind the volume head.

### Related Issues
https://github.com/longhorn/longhorn/issues/3613

## Motivation
### Goals
Snapshots could store historical data for a volume. This means extra space will be required, and the volume actual size can be much greater than the spec size.
To avoid existing volumes using too much space, users can clean up snapshots by marking the snapshots as _Removed_ then waiting for Longhorn purging them. 
But there is one issue: By design, the snapshot that directly stands behind the volume head, as known as the latest snapshot, cannot be purged by Longhorn after being marked as _Removed_. The space consumed by it cannot be released any matter if users care about historical data or not. 
Hence, Longhorn should do something special to reclaim space "wasted" by this kind of snapshot.

### Non-goals:
Volume trim/shrink: https://github.com/longhorn/longhorn/issues/836

## Proposal
1. Deleting a snapshot consists of 2 steps, marking the snapshot as _Removed_ then waiting for Longhorn purging it. And the snapshot purge consists of 3 steps: copy data from the newer snapshot to the old snapshot, replace the new snapshot with the updated old snapshot, remove the new snapshot.
   This operation is named "coalesce" or "fold" in Longhorn. As mentioned before, it cannot be applied to the latest snapshot file since the newer one of it is actually the volume head, which cannot be modified by others except for users/workloads. 
   In other words, we cannot use this operation to handle the latest snapshot. 
   ```
   +--------------+     +--------------+     +--------------+
   |  Snapshot A  | --- |  Snapshot B  | --- | Volume head  |
   +--------------+     +--------------+     +--------------+
          ^
          | 
   Marked Snapshot A (the old snapshot) as _Removed_
   
   +--------------+     +--------------+     +--------------+
   |  Snapshot A  | --- |  Snapshot B  | --- | Volume head  |
   +--------------+     +--------------+     +--------------+
          ^                     |
          +---------------------+
   Copy data from the Snapshot B (the newer snapshot) to Snapshot A
   
   +---------------------------------+       +--------------+
   | Rename snapshot A to snapshot B | ----- | Volume head  |
   +---------------------------------+       +--------------+
          ^
          |
   Delete Snapshot B then rename snapshot A to Snapshot B
   ```
2. Longhorn needs to somehow reclaim the space from the latest snapshot without directly deleting the file itself or modifying the volume head. 
   Notice that Longhorn can still read the volume head as well as modify the snapshot once the snapshot itself is marked as _Removed_. This means we can detect which part of the latest snapshot is overwritten by the volume head. Then punching holes in the overlapping parts of the snapshot would reclaim the space.
   Here, we call this new operation as "prune".
   ```
   +--------------+     +---------------+
   |  Snapshot A  | --- |  Volume head  |
   +--------------+     +---------------+
          ^                     |
          +---------------------+
   Snapshot A is the latest snapshot of the volume.
   Longhorn will scan the volume head. For each data chunk of the volume head, Longhorn will punch a hole at the same position for snapshot A. 
   ```
3. Punching holes means modifying the data of the snapshot. Therefore, once the snapshot is marked as _Removed_ and the cleanup happens, Longhorn should not allow users to revert to the snapshot anymore. This is the prerequisite of this enhancement.
   This snapshot revert issue is handled in https://github.com/longhorn/longhorn/issues/3748.

### User Stories
#### Cleanup the data of the latest snapshot
Before the enhancement, users need to create a new snapshot, then remove the target snapshot so that Longhorn will coalesce the target snapshot with the newly created one. But the issue is, the volume head would be filled up later, and users may loop into redoing the operation to reclaim the space occupied by the historical data of the snapshot. 

After the enhancement, as long as there is no newer snapshot created, users can directly reclaim the space from the latest snapshot by simply deleting the snapshot via UI. 

### User Experience In Detail
Assume that there are heavy writing tasks for a volume and the only snapshot is filled up with the historical data (this snapshot may be created by rebuilding or backup). The actual size of the volume is typical twice the spec size.
Now users just need to remove the only/latest snapshot via UI, Longhorn would reclaim almost all space used by the snapshot, which is the spec size here. 
Then as long as users don't create a new snapshot, the actual size of this volume is the space used by the volume head only, which is up to the spec size in total.

### API Changes
N/A

## Design
### Implementation Overview
#### longhorn-engine:
When the snapshot purge is triggered, replicas will identify if the snapshot being removed is the latest snapshot by checking one child of it is the volume head. If YES, they will start the snapshot pruning operation:
  1. Before pruning, replicas will make sure the apparent size of the snapshot is the same as that of the volume head. If No, we will truncate/expand the snapshot first. 
  2. During pruning, replicas need to iterate the volume head fiemap. Then as long as there is a data chunk found in the volume head file, they will blindly punch a hole at the same position of the snapshot file.
If there are multiple snapshots including the latest one being removed simultaneously, we need to make sure the pruning is done only after all the other snapshots have done coalescing and deletion.

#### longhorn-ui:
Allow users to remove the snapshots that are already marked as Removed. And in this case, the frontend just needs to send a `SnapshotPurge` call to the backend.

### Test Plan
#### Integration tests
Test this snapshot prune operations with snapshot coalesce, snapshot revert, and volume expansion.

### Upgrade strategy
N/A

