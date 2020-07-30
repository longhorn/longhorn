# Upgrade Rollback

## Summary
This enhancement adds a mechanism for users to be able to rollback from later versions of Longhorn and restore previous versions of their CRDs.

### Related Issues
https://github.com/longhorn/longhorn/issues/1455

## Motivation

### Goals
The goal of this enhancement is to provide a mechanism for saving the state of the Longhorn installation prior to an upgrade to a new version. This enhancement should also provide a mechanism for rolling back to prior versions of Longhorn and restoring the saved state of the Longhorn installation so that the installation can operate correctly again once restored to the old version.

### Non-goals
This enhancement should only save a copy of the state in-cluster for the purposes of having a fallback to use if the user decides to rollback to an old version of Longhorn. This enhancement is not intended as a way to backup the state of the Longhorn installation.

## Proposal
When upgrading to a new version of Longhorn, the system should save the state of all Longhorn CRD instances in an annotation on that CRD instance. This step should take place before other actions are taken by the Upgrade Controller in case any actions taken by the Upgrade Controller cause damage to the CRD instances.

In case the upgrade failed or the user wants to rollback to the previous version of Longhorn, the user should just be able to apply the previous version of Longhorn via whichever installation method they used to install Longhorn. On startup, the previous version of Longhorn should detect that there is a rollback occuring, and the Upgrade Controller should reapply the saved states of the CRD instances before starting up the rest of the Longhorn Manager.

### User Stories

#### User Upgrade and Rollback
Currently, there is no mechanism for rollback to a previous version after an upgrade. This can be problematic if the user finds that they are not able to use the upgraded version of Longhorn for any reason, such as the upgrade failing.

After this enhancement, the upgrade process will look the same as in previous versions from the user's perspective. However, if the upgrade fails, or the user otherwise wants to rollback to a previous version of Longhorn, then the user can follow the upgrade steps to instead install a previous version of Longhorn, which will automatically restore the old CRD instances and should give them the previous working installation back.

### User Experience In Detail

#### User Upgrade and Rollback
1. The user follows the upgrade steps for Longhorn depending on whichever method they used to install Longhorn initially.
2. The user decides to rollback to the previous version of Longhorn for any reason. They use the upgrade steps to install the previous version of Longhorn again.
3. The Upgrade Controller will automatically restore the saved state of the CRD instances, and once completed, the user will have a working version of Longhorn once more.

### API changes
All instances of CRDs should have an annotation created on them called `rollback.longhorn.io/{version}`, where `{version}` is the version from Longhorn that's being upgraded from. This annotation should store a backup of the CRD as part of the upgrade process, so the user can rollback to this version if they wish.

A new setting will need to be added to Longhorn named `current-version` that contains the current version of Longhorn. This is needed so that during upgrade time, the Upgrade Controller knows that there is either a version upgrade/downgrade going on so that it can either store CRD instance state or rollback properly.

## Design
### Implementation Overview
The required changes need to be implemented in the Longhorn Manager as part of the Upgrade Controller:
- Before conducting the other actions on the Upgrade Controller, compare the current version of Longhorn against the version stored in the `current-version` setting:
    - If the version of Longhorn Manager is less than `current-version`, perform the rollback logic:
        - If annotations with `rollback.longhorn.io/{version}` exist matching the version of Longhorn Manager, restore those CRD instances. Once complete, clean up the annotations and then continue running Longhorn Manager.
        - If the annotation does not exist, error out noting that a rollback to that version is not possible.
    - If the version of Longhorn Manager is equal to `current-version`, skip any upgrade or rollback logic.
    - If the version of Longhorn Manager is greater than `current-version`, save the current state of the CRD instances onto an annotation matching `rollback.longhorn.io/{version}` (with `{version}` being the `current-version` value) and then proceed with the upgrade logic.

### Test Plan
TBD

### Upgrade Strategy
No special steps should be required for the user to upgrade to this feature.

## Notes
- There are likely some other rollback changes that will need to occur as a result of specific upgrade changes that happen from release to release (for example, the engine binary migration between v0.7.0 and v0.8.0). These rollback changes will need to be handled separately in the Upgrade Controller somehow.
