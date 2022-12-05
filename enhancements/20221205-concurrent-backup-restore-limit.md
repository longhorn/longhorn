# Concurrent Backup Restore Per Node Limit

## Summary
Longhorn has no boundary on the number of concurrent volume backup restoring.

Having a new `concurrent-backup-restore-per-node-limit` setting allows the user to limit the concurring backup restoring. Setting this restriction lowers the potential risk of overloading the cluster when volumes restoring from backup concurrently. For ex: during the Longhorn system restore.

### Related Issues
https://github.com/longhorn/longhorn/issues/4558

## Motivation
### Goals
Introduce a new `concurrent-backup-restore-per-node-limit` setting to define the boundary of the concurrent volume backup restoring.

### Non-goals
`None`

## Proposal
1. Introduce a new `concurrent-backup-restore-per-node-limit` setting.
1. Track the number of per-node volumes restoring from backup with atomic count (thread-safe) in the engine monitor.

### User Stories
Allow the user to set the concurrent backup restore per node limit to control the risk of cluster overload when Longhorn volume is restoring from backup concurrently.

### User Experience In Detail
1. Longhorn holds the engine backup restore when the number of volume backups restoring on a node reaches the `concurrent-backup-restore-per-node-limit`.
1. The volume backup restore continues when the number of volume backups restoring on a node is below the limit.

## Design

### Implementation Overview

#### The `concurrent-backup-restore-per-node-limit` Setting

This setting controls how many engines on a node can restore the backup concurrently.

Longhorn engine monitor backs off when the volume [backup restoring count](#track-the-volume-backup-restoring-per-node) reaches the setting limit.

Set the value to **0** to disable backup restore.

```
Category = SettingCategoryGeneral,
Type     = integer
Default  = 5  # same as the default replica rebuilding number
```

#### Track the volume backup restoring per node

1. Create a new atomic counter in the engine controller.
   ```
   type EngineController struct {
      restoringCounter util.Counter
   }
   ```
1. Pass the restoring counter to each of its engine monitors.
   ```
   type EngineMonitor struct {
      restoringCounter util.Counter
   }
   ```

1. Increase the restoring counter before backup restore.
   > Ignore DR volumes (volume.Status.IsStandby).
1. Decrease the restoring counter when the backup restore caller method ends

### Test plan

- Test the setting should block backup restore when creating multiple volumes from the backup at the same time.
- Test the setting should be per-node limited.
- Test the setting should not have effect on DR volumes.

### Upgrade strategy

`None`

## Note [optional]

`None`
