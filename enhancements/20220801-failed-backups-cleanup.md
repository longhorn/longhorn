# Failed Backup Clean Up

## Summary

Longhorn will leave the failed backups behind and will not delete the backups automatically either until the backup target is removed. Failed backup cleanup will be occurred when making a backup to remote backup target failed. This LEP will trigger the deletion of failed backups automatically.

### Related Issues

[[IMPROVEMENT] Support failed/obsolete orphaned backup cleanup](https://github.com/longhorn/longhorn/issues/3898)

## Motivation

### Goals

- Support the auto-deletion of failed backups that exceeded the TTL.
- Support the global auto-deletion option of failed backups cleanup for users.
- The process should not be stuck in the reconciliation of the controllers.

### Non-goals [optional]

- Clean up unknown files or directories on the remote backup target.

## Proposal

1. The `backup_volume_controller` will be responsible for deleting Backup CR when there is a backup which state is in `Error` or `Unknown`.

    The reconciliation procedure of the `backup_volume_controller` gets the latest failed backups from the datastore and delete the failed backups.

    ```text

          queue           ┌───────────────┐
         ┌┐ ┌┐ ┌┐         │               │
     ... ││ ││ ││ ──────► │ syncHandler() |
         └┘ └┘ └┘         │               │
                          └───────┬───────┘
                                  │
                       ┌──────────▼───────────┐
                       │                      │
                       │     reconcile()      |
                       │                      │
                       └──────────┬───────────┘
                                  │
                       ┌──────────▼───────────┐
                       │                      │
                       │  get failed backups  │
                       │                      |
                       |  then delete them    │
                       │                      │
                       └──────────────────────┘



    ```

### User Stories

When a user or recurring job tries to make a backup and store it in the remote backup target, many situations will cause the backup procedure failed. In some cases, there will be some failed backups still staying in the Longhorn system and this kind of backups are not handled by the Longhorn system until user removes the backup target. Or users can manage the failed backups via Longhorn GUI or command line tools manually.

After the enhancement, Longhorn can delete the failed backups automatically after enabling auto-deletion.

### User Experience In Detail

- Via Longhorn GUI
  - Users can be aware of that backup was failed if auto-deletion is disabled.
  - Users can check the event log to understand why the backup failed and deleted.

- Via `kubectl`
  - Users can list the failed backups by `kubectl -n longhorn-system get backups` if auto-deletion is disabled.

## Design

### Implementation Overview

**Settings**

- Add setting `failed-backup-ttl`. Default value is `1440` minutes and set to `0` to disable the auto-deletion.

**Failed Backup**

- Backups in the state `longhorn.BackupStateError` or `longhorn.BackupStateUnknown`.

**Backup Controller**

- Start the monitor and sync the backup status with the monitor in each reconcile loop.
- Update the backup status.
- Trigger `backup_volume_controller` to delete the failed backups.

**Backup Volume controller**

- Reconcile loop usually is triggered after backupstore polling which is controlled by **Backupstore Poll Interval** setting.
- Start to get all backups in each reconcile loop
- Tell failed backups from all backups and try to delete failed backups by default.
- Update the backup volume CR status.

### Test plan

**Integration tests**

- `backups` CRs with `Error` or `Unknown` state will be removed by `backup_volume_controller` triggered by backupstore polling when the `backup_monitor` detects the backup failed.
- `backups` CRs with `Error` or `Unknown` state will not be handled if the auto-deletion is disabled.

## Note [optional]

### Why not leverage the current orphan framework

1. We already have the backup CR to handle the backup resources and failed backup is not like orphaned replica which is not owned by any volume at the beginning.

2. Cascading deletion of orphaned CR and backup CR would be more complicated than we just handle the failed backups immediately when backup procedure failed. Both in this LEP or orphan framework we would delete the failed backups by `backup_volume_controller`.

3. Listing orphaned backups and failed backups on both two UI pages `Orphaned Data` and `Backup` might be a bit confusing for users. Deleting items manually on either of two pages would be involved in what it mentioned at statement 2.
