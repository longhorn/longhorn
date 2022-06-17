# Upgrade Volume's Engine Image Automatically

## Summary

Currently, users need to upgrade the engine image manually in the UI after upgrading Longhorn.
We should provide an option. When it is enabled, automatically upgrade engine images for volumes when it is applicable.

### Related Issues

https://github.com/longhorn/longhorn/issues/2152

## Motivation

### Goals

Reduce the amount of manual work users have to do when upgrading Longhorn by automatically upgrade engine images 
for volumes when they are ok to upgrade. E.g. when we can do engine live upgrade or when volume is in detaching state.

## Proposal

Add a new boolean setting, `Concurrent Automatic Engine Upgrade Per Node Limit`, so users can control how Longhorn upgrade engines.
The value of this setting specifies the maximum number of engines per node that are allowed to upgrade to the default engine image at the same time.
If the value is 0, Longhorn will not automatically upgrade volumes' engines to default version.

After user upgrading Longhorn to a new version, there will be a new default engine image and possibly a new default instance manager image.

The proposal has 2 parts:
1. In which component we will do the upgrade.
2. Identify when is it ok to upgrade engine for volume to the new default engine image.

For part 1, we will do the upgrade inside `engine image controller`. 
The controller will constantly watch and upgrade the engine images for volumes when it is ok to upgrade.

For part 2, we upgrade engine image for a volume when the following conditions are met:
1. The new default engine image is ready
1. Volume is not upgrading engine image
1. The volume condition is one of the following:
   1. Volume is in detached state.
   1. Volume is in attached state (live upgrade).
      And volume is healthy.
      And The current volume's engine image is compatible with the new default engine image.
      And If volume is not a DR volume.
      And Volume is not expanding.

### User Stories

Before this enhancement, users have to manually upgrade engine images for volume after upgrading Longhorn system to a newer version.
If there are thousands of volumes in the system, this is a significant manual work.

After this enhancement users either have to do nothing (in case live upgrade is possible) 
or they only have to scale down/up the workload (in case there is a new default IM image)

### User Experience In Detail

1. User upgrade Longhorn to a newer version. 
The new Longhorn version is compatible with the volume's current engine image. 
Longhorn automatically do live engine image upgrade for volumes

2. User upgrade Longhorn to a newer version. 
The new Longhorn version is not compatible with the volume's current engine image. 
Users only have to scale the workload down and up.
This experience is similar to restart Google Chrome to use a new version. 

3. Note that users need to disable this feature if they want to update the engine image to a specific version for the volumes.
If `Concurrent Automatic Engine Upgrade Per Node Limit` setting is bigger than 0, Longhorn will not allow user to manually upgrade engine to a version other than the default version.

### API changes

No API change is needed.

## Design

### Implementation Overview

1. Inside `engine image controller` sync function, get the value of the setting `Concurrent Automatic Engine Upgrade Per Node Limit` and assign it to concurrentAutomaticEngineUpgradePerNodeLimit variable.
  If concurrentAutomaticEngineUpgradePerNodeLimit <= 0, we skip upgrading.
1. Find the new default engine image. Check if the new default engine image is ready. If it is not we skip the upgrade.

1. List all volumes in Longhorn system. 
   Select a set of volume candidate for upgrading.
   We select candidates that has the condition is one of the following case:
   1. Volume is in detached state.
   1. Volume is in attached state (live upgrade).
      And volume is healthy.
      And Volume is not upgrading engine image.
      And The current volume's engine image is compatible with the new default engine image.
      And the volume is not a DR volume.
      And volume is not expanding.
     
1. Make sure not to upgrade too many volumes on the same node at the same time.
   Filter the upgrading candidate set so that total number of upgrading volumes and candidates per node is not over `concurrentAutomaticEngineUpgradePerNodeLimit`.
1. For each volume candidate, set `v.Spec.EngineImage = new default engine image` to update the engine for the volume.
1. If the engine upgrade failed to complete (e.g. the v.Spec.EngineImage != v.Status.CurrentImage), 
   we just consider it is the same as volume is in upgrading process and skip it.
   Volume controller will handle the reconciliation when it is possible.

### Test plan


Integration test plan.

Preparation:
1. set up a backup store
2. Deploy a compatible new engine image

Case 1: Concurrent engine upgrade
1. Create 10 volumes each of 1Gb.
2. Attach 5 volumes vol-0 to vol-4. Write data to it
3. Upgrade all volumes to the new engine image
4. Wait until the upgrades are completed (volumes' engine image changed,
   replicas' mode change to RW for attached volumes, reference count of the
   new engine image changed, all engine and replicas' engine image changed)
5. Set concurrent-automatic-engine-upgrade-per-node-limit setting to 3
6. In a retry loop, verify that the number of volumes who
   is upgrading engine is always smaller or equal to 3
7. Wait until the upgrades are completed (volumes' engine image changed,
   replica mode change to RW for attached volumes, reference count of the
   new engine image changed, all engine and replicas' engine image changed,
   etc ...)
8. verify the volumes' data

Case 2: Dr volume
1. Create a backup for vol-0. Create a DR volume from the backup
2. Try to upgrade the DR volume engine's image to the new engine image
3. Verify that the Longhorn API returns error. Upgrade fails.
4. Set concurrent-automatic-engine-upgrade-per-node-limit setting to 0
5. Try to upgrade the DR volume engine's image to the new engine image
6. Wait until the upgrade are completed (volumes' engine image changed,
   replicas' mode change to RW, reference count of the new engine image
   changed, engine and replicas' engine image changed)
7. Wait for the DR volume to finish restoring
8. Set concurrent-automatic-engine-upgrade-per-node-limit setting to 3
9. In a 2-min retry loop, verify that Longhorn doesn't automatically
   upgrade engine image for DR volume.

Case 3: Expanding volume
1. set concurrent-automatic-engine-upgrade-per-node-limit setting to 0
2. Upgrade vol-0 to the new engine image
3. Wait until the upgrade are completed (volumes' engine image changed,
   replicas' mode change to RW, reference count of the new engine image
   changed, engine and replicas' engine image changed)
4. Detach vol-0
5. Expand the vol-0 from 1Gb to 5GB
6. Wait for the vol-0 to start expanding
7. Set concurrent-automatic-engine-upgrade-per-node-limit setting to 3
8. While vol-0 is expanding, verify that its engine is not upgraded to
   the default engine image
9. Wait for the expansion to finish and vol-0 is detached
10. Verify that Longhorn upgrades vol-0's engine to the default version

Case 4: Degraded volume
1. set concurrent-automatic-engine-upgrade-per-node-limit setting to 0
2. Upgrade vol-1 (an healthy attached volume) to the new engine image
3. Wait until the upgrade are completed (volumes' engine image changed,
   replicas' mode change to RW, reference count of the new engine image
   changed, engine and replicas' engine image changed)
4. Increase number of replica count to 4 to make the volume degraded
5. Set concurrent-automatic-engine-upgrade-per-node-limit setting to 3
6. In a 2-min retry loop, verify that Longhorn doesn't automatically
   upgrade engine image for vol-1.

Cleaning up:
1. Clean up volumes
2. Reset automatically-upgrade-engine-to-default-version setting in
   the client fixture

### Upgrade strategy

No upgrade strategy is needed.


### Additional Context
None