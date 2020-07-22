# Refactor restore for rebuild enabling 

## Summary
This enhancement will refactor the restore implementation and enable rebuild for restore/DR volumes.

### Related Issues
https://github.com/longhorn/longhorn/issues/1279

## Motivation

### Goals
The goal of this enhancement is to simplify the restore flow so that it can work for rebuilding replicas of restore/DR volumes without breaking the live upgrade feature.

### Non-goals
This enhancement won't guarantee that the restore/DR volume activation won't be blocked by replica rebuilding.  

## Proposal
- When there are replicas crashing among restore/DR volumes, new rebuilding replicas will be created as usual. But instead of following the normal replica rebuilding workflow (syncing data/files from other running replicas), the rebuilding replicas of restore/DR volumes will directly restore data from backup.
    - The normal rebuilding (file syncing) workflow implicitly considers that all existing snapshots won't change and newer data during the rebuilding will be written into volume head. But for restore/DR volumes, new data writing is directly handled by replica (sync agent server) and it will be written to underlying snapshots rather than volume heads. As a result, the normal rebuilding logic doesn't fit restore/DR volumes.  
    - In order to skip the file syncing and snapshotting and directly do restore, the rebuilding related API should be updated, which will lead to API version bumps.
- As long as there is a replica having not restored the newest/latest backup, longhorn manager will directly call restore command. Then rebuilding replicas will be able to start the restore even if all other replicas are up-to-date.
    - Previously, in order to maintain the consistency of DR volume replicas, Longhorn manager will guarantee that all replicas have restored the same backup before starting the next backup restore. But considering the case that the newly rebuilt replicas are empty whereas the existing replicas have restored some backups, This restriction makes replica rebuilding become impossible in some cases. Hence we need to break the restriction.
    - This restriction break degrades the consistency of DR volume replicas. But it's acceptable as long as all replicas can finish the latest backup restore and the DR volume can be activated in the end. 
    - This modification means engines and replicas should be intelligent enough to decide if they need to do restore and which kind of restore they need to launch.
    - Actually replica processes have all information about the restore status and they can decide if they need incremental restore or full restore by themself. Specifying the last backup in the restore command is redundant.
    - Longhorn manager only needs to tell the replicas what is the latest backup they should restore.
    - Longhorn manager still need to know what is the last restored backup of all replicas, since it relies on it to determine if the restore/DR volume is available/can be activated.
- Longhorn should wait for rebuild complete and check restore status before auto detachment.
    - Otherwise, the restore volume will be automatically detached when the rebuild is in progress then the rebuild is meaningless in this case.  

### User Stories

#### Replica crashes when a restore/DR volume is in restore progress
Before, the restore volume keeps state `Degraded` if there is replica crashing. And the volume will finally become `Faulted` if all replicas are crashed one by one during restoring.

After, the restore volume will start replica rebuilding automatically then be back to state `Healthy` if there is replica crashing. The volume is available as long as all replicas are not crashed at the same time. And volume will finish activation/auto-detachment after the rebuild is done.

### User Experience In Detail

#### Replica crash on restore volume
1. Users create a restore volume and wait for restore complete.
2. When the restore is in progress, some replicas somehow get crashed. Then the volume rebuilds new replicas immediately, and it will become `Healthy` once the new replicas start rebuilding.
4. The volume will be detached automatically once the restore and the rebuild complete.

#### Replica crash on DR volume
1. Users create a DR volume.
2. Some replicas get crashed. Then the DR volume automatically rebuilds new replicas and restores the latest backup for the rebuilt replicas.
3. Users try to activate the DR volume. The DR volume will wait for the rebuild of all replicas and successful restoration of the latest backup before detachment.

### API changes

#### CLI API
- Add a new flag `--restore` for command `add-replica`, which indicates skipping file syncing and snapshotting.
- Deprecate the arg `lastRestoreBackup` and the flag `--incrementally` for command `backup restore`.
- Add a new command `verify-rebuild-replica`, which can mark the rebuilding replicas as available (mode `RW`) for restore/DR volumes after the initial restore is done.

#### Controller gRPC API
- Create a separate message/struct for `ReplicaCreate` request then add the two new fields `Mode` and `SnapshotRequired` to the request.

## Design

### Implementation Overview

#### Engine Part:
1. Modify command `add-replica` related APIs:
    1. Use a new flag `--restore` in command `add-replica` to indicate that file syncing and snapshotting should be skipped for restore/DR volumes.
    2. The current controller gRPC call `ReplicaCreate` used in the command will directly create a snapshot before the rebuilding. But considering the (snapshot) consistency of of restore/DR volumes, snapshots creation/deletion is fully controlled by the restore command (and the expansion command during the restore). Hence, the snapshotting here needs to be skipped by updating the gRPC call `ReplicaCreate`.
2. Add command `verify-rebuild-replica`:
    1. It just calls the existing controller gRPC function `ReplicaVerifyRebuild`.
    2. It's mainly used to mark the rebuilding replica of restore/DR volumes as mode `RW` with some verifications and a replica reload.
3. Modify command `backup restore`:
    1. Deprecate/Ignore the arg `lastRestoreBackup` in the restore command and the following sync agent gRPC function. Instead, the sync agent server will directly do a full restore or a incremental restore based on its current restore status.
    2. Deprecate/Ignore the flag `--incrementally` for command `backup restore`. By checking the disk list of all existing replicas, the command function knows if it needs to generate a new snapshot name.
    3. The caller of the gRPC call `BackupRestore` only needs to tell the name of the final snapshot file that stores restored data. 
        1. For new restore volume, there is no existing snapshot among all replicas hence we will generate a random snapshot name.
        2. For replicas of DR volumes or rebuilding replicas of restore volumes, the caller will find the replica containing the most snapshots then use the latest snapshot of the replica in the following restore.
        3. As for the delta file used in the incremental restore, it will be generated by the sync agent server rather than by the caller. Since the caller has no idea about the last restored backup now and the delta file naming format is `volume-delta-<last restored backup name>.img`.
    4. To avoid disk/snapshot chain inconsistency between rebuilt replicas and old replicas of a DR volume, snapshot purge is required if there are more than 1 snapshots in one replica. And the (incremental) restore will be blocked before the snapshot purge complete.
3. Make the sync agent gRPC call `BackupRestore` more “intelligent”: The function will check the restore status first. If there is no restore record in the sync agent server or the last restored backup is invalid, a full restore will be applied. This means we can remove the gRPC call `BackupRestoreIncrementally`.
4. Remove the expansion before the restore call. The expansion of DR volumes should be guaranteed by longhorn manager.
5. Coalesce the incremental restore related functions to normal restore functions if possible.

#### Manager Part:
1. Allow replica replenishment for restore/DR volumes. 
2. Add the new flag `--restore` when using command `add-replica` to rebuild replicas of restore/DR volumes. 
3. Modify the pre-restore check and restore status sync logic: 
    1. Previously, the restore command will be invoked only if there is no restoring replica. Right now the command will be called as long as there is a replica having not restored the latest backup.
    2. Do not apply the consensual check as the prerequisite of the restore command invocation. The consensual check will be used for `engine.Status.LastRestoredBackup` update only.
    3. Invoke `verify-rebuild-replica` when there is a complete restore for a rebuilding replica (mode `WO`).
4. Modify the way to invoke restore command:
    1. Retain the old implementation for compatibility. 
    2. For the engine using the new engine image, call restore command directly as long as the pre-restore check gets passed.
    3. Need to ignore some errors. e.g.: replicas are restoring, the requested backup restore is the same as the last backup restore, or replicas need to complete the snapshot purge before the restore.
5. Mark the rebuilding replicas as mode `ERR` and disable the replica replenishment during the expansion.
6. Modify the prerequisites of restore volume auto detachment or DR volume activation:
    1. Wait for the rebuild complete and the volume becoming `Healthy`.
    2. Check and wait for the snapshot purge.
    3. This prerequisite check works only for new restore/DR volumes. 

### Test plan

#### Engine integration tests:

##### Restore volume simple rebuild:
1. Create a restore volume with 2 replicas.
2. Run command `backup restore` for the DR volume.
3. Delete one replica of the restore volume.
4. Initialize a new replica, and add the replica to the restore volume.
5. Run command `backup restore`.
6. Verify the restored data is correct, and all replicas work fine.

##### DR volume rebuild after expansion:
1. Create a DR volume with 2 replicas.
2. Run command `backup restore` for the DR volume.
3. Wait for restore complete.
4. Expand the DR volume and wait for the expansion complete.
5. Delete one replica of the DR volume.
6. Initialize a new replica, and add the replica to the DR volume. 
7. Run command `backup restore`. The old replica should start snapshot purge and the restore is actually not launched.
8. Wait for the snapshot purge complete.
9. Re-run command `backup restore`. Then wait for the restore complete.
10. Check if the restored data is correct, and all replicas work fine. And verify all replicas contain only 1 snapshot.

#### Manager integration tests:

##### Restore volume rebuild:
1. Launch a pod with Longhorn volume.
2. Write data to the volume and take a backup.
3. Create a restore volume from the backup and wait for the restore start.
4. Crash one random replicas. Then check if the replicas will be rebuilt and the restore volume can be `Healthy` after the rebuilding.
5. Wait for the restore complete and auto detachment.
6. Launch a pod for the restored volume.
7. Verify all replicas work fine with the correct data.

##### DR volume rebuild during the restore:
1. Launch a pod with Longhorn volume.
2. Write data to the volume and take the 1st backup.
3. Wait for the 1st backup creation complete then write more data to the volume (which is the data of the 2nd backup).
4. Create a DR volume from the 1st backup and wait for the restore start.
5. Crash one random replica.
6. Take the 2nd backup for the original volume. Then trigger DR volume last backup update immediately (by calling backup list API) after the 2nd backup creation complete. 
7. Check if the replicas will be rebuilt and the restore volume can be `Healthy` after the rebuilding.
8. Wait for the restore complete then activate the volume.
9. Launch a pod for the activated DR volume.
10. Verify all replicas work fine with the correct data.

##### DR volume rebuild with expansion:
1. Launch a pod with Longhorn volume.
2. Write data to the volume and take the 1st backup.
3. Create a DR volume from the 1st backup.
4. Shutdown the pod and wait for the original volume detached.
5. Expand the original volume and wait for the expansion complete.
6. Re-launch a pod for the original volume.
7. Write data to the original volume and take the 2nd backup. (Make sure the total data size is larger than the original volume size so that there is date written to the expanded part.)
8. Wait for the 2nd backup creation complete. 
9. Trigger DR volume and crash one random replica of the DR volume.
10. Check if the replicas will be rebuilt, and the restore volume can be `Healthy` after the rebuilding.
11. Wait for the expansion, restore, and rebuild complete.
12. Verify the DR volume size and snapshots count after the restore.
13. Write data to the original volume and take the 3rd backup.
14. Wait for the 3rd backup creation complete then trigger the incremental restore for the DR volume.
15. Activate the DR volume and wait for the DR volume activated.
16. Launch a pod for the activated DR volume.
17. Verify the restored data of the activated DR volume.
18. Write more data to the activated DR volume. Then verify all replicas are still running.
19. Crash one random replica of the activated DR volume. 
20. Wait for the rebuild complete then verify the activated volume still works fine.

### Manual test
1. Launch Longhorn v1.0.1.
2. Launch a pod with Longhorn volume.
3. Write data to the volume and take the 1st backup.
4. Create 2 DR volumes from the 1st backup.
5. Shutdown the pod and wait for the original volume detached.
6. Expand the original volume and wait for the expansion complete.
7. Write data to the original volume and take the 2nd backup. (Make sure the total data size is larger than the original volume size so that there is date written to the expanded part.)
8. Trigger incremental restore for the DR volumes by listing the backup volumes, and wait for restore complete.
9. Upgrade Longhorn to the latest version.
10. Crash one random replica for the 1st DR volume .
11. Verify the 1st DR volume won't rebuild replicas and keep state `Degraded`.
12. Write data to the original volume and take the 3rd backup.
13. Trigger incremental restore for the DR volumes, and wait for restore complete.
14. Do live upgrade for the 1st DR volume. This live upgrade call should fail and nothing gets changed.
15. Activate the 1st DR volume. 
16. Launch a pod for the 1st activated volume, and verify the restored data is correct.
17. Do live upgrade for the original volume and the 2nd DR volumes.
18. Crash one random replica for the 2nd DR volume.
19. Wait for the restore & rebuild complete.
20. Delete one replica for the 2nd DR volume, then activate the DR volume before the rebuild complete.
21. Verify the DR volume will be auto detached after the rebuild complete.
22. Launch a pod for the 2nd activated volume, and verify the restored data is correct.
23. Crash one replica for the 2nd activated volume.
24. Wait for the rebuild complete, then verify the volume still works fine by reading/writing more data.

### Upgrade strategy
Live upgrade is supported.

## Note
It's possible that the restore/DR volume rebuilding somehow gets stuck, or users have no time to wait for the restore/DR volume rebuilding done. We need to provide a way that users can use the volume as soon as possible. This enhancement is tracked in https://github.com/longhorn/longhorn/issues/1512.
