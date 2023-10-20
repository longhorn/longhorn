# Volume Backup Policy for Longhorn System Backup

The current implementation of the Longhorn system backup lacks integration with the volume backup feature. As a result, users are required to manually ensure that all volume backups are up-to-date before initiating the Longhorn system backup.

## Summary

This document proposed to include the volume backup feature in the Longhorn system backup by introducing volume backup policies.

By implementing the volume backup policies, users will gain the ability to define how volume data should be backed up during the Longhorn system backup.

### Related Issues

https://github.com/longhorn/longhorn/issues/5011

## Motivation

### Goals

1. **Customization:** By offering different volume backup policy options, users can choose the one best fit with their requirements.
1. **Reduce Manual Efforts:** By integrating volume backup into the Longhorn system backup, users no longer have to ensure that all volume backups are up-to-date before initiating the system backup,
1. **Enhanced Data Integrity:** By aligning the system backup with a new up-to-date volume backups, the restored volume data will be more accurate.

Overall, the proposed volume backup policies aim to improve the Longhorn system backup functionality and providing a more robust and customizable system backup solution.

### Non-goals [optional]

`None`

## Proposal

1. When volume backup policy is specified:
   - `if-not-present`: Longhorn will create a backup for volumes that do not have an existing backup.
   - `always`: Longhorn will create a backup for all volumes, regardless of their existing backups.
   - `disabled`: Longhorn will not create any backups for volumes.
1. If a volume backup policy is not specified, the policy will be automatically set to `if-not-present`. This ensures that volumes without any existing backups will be backed up during the Longhorn system backup.

### User Stories

As a user, I want the ability to specify the volume backup policy when creating the Longhorn system backup. This will allow me to define how volumes should be backed up according to my scenario.

- **Scenario 1: if-not-present Policy:** When I set the volume backup policy to `if-not-present`, I expect Longhorn to create a backup for volumes that do not already have a backup.

- **Scenario 2: always Policy:** When I set the volume backup policy to `always`, I expect Longhorn to create backups for all volumes, regardless of whether they already have a backup.

- **Scenario 3: disabled Policy:** When I set the volume backup policy to `disabled`, I expect Longhorn to not create any backups for the volumes.

In cases where I don't explicitly specify the volume backup policy during the system backup configuration, I expect Longhorn to automatically apply the `if-not-present` policy as the default.

### User Experience In Detail

To set the volume backup policy, users can set the volume backup policy when creating the system backup through the UI. Alternatively, users can specify it in the manifest when creating the SystemBackup custom resource using the kubectl command.

In scenarios where no specific volume backup policy is provided, Longhorn will automatically set the policy as `if-not-present`.

### API changes

Add a new `volumeBackupPolicy` field to the HTTP request and response payload.

## Design

### Implementation Overview

#### SystemBackup Custom Resource

- Introduce a new `volumeBackupPolicy` field. This field allows user to specify the volume backup policy.
- Add a new state (phase) called `CreatingVolumeBackups` to track the progress of volume backup creation during the Longhorn system backup.

#### CreatingVolumeBackups phase

- Iterate through each Longhorn volume.
  - If the policy is `if-not-present`, create a volume snapshot and backup only for volumes that do not already have a backup (lastBackup is empty).
  - If the policy is `always`, create a volume snapshot and backup for all volumes, regardless of their existing backups.
  - If the policy is `disabled`, skip the volume backup creation step for all volumes and proceed to the next phase.
- Wait for all volume backups created by the SystemBackup to finish (completed or error state) before proceeding to the next phase (Generating or Error). Backup will have timeout limit of 24 hours. Any of the backups failure will lead the SystemBackup to and Error state.

#### Mutate empty volume backup policy

When the volume backup policy is not provided in the SystemBackup custom resource, automatically set the policy to `if-not-present`.

### Test plan

1. When the volume backup policy is `if-not-present`, the system backup should only create volume backup when there is no existing backup in Volume.
1. When the volume backup policy is `always`, the system backup should create volume backup regardless of the existing backup.
1. When the volume backup policy is `disabled`, the system backup should not create volume backup.

### Upgrade strategy

`None`

## Note [optional]

`None`
