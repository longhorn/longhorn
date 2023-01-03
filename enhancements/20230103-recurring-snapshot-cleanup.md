# Recurring Snapshot Cleanup
## Summary

Currently, Longhorn's recurring job automatically cleans up older snapshots of volumes to retain no more than the defined snapshot number. However, this is limited to the snapshot created by the recurring job. For the non-recurring volume snapshots or snapshots created by backups, the user needs to clean them manually.

Having periodic snapshot cleanup could help to delete/purge those extra snapshots regardless of the creation method.

### Related Issues

https://github.com/longhorn/longhorn/issues/3836

## Motivation

### Goals

Introduce new recurring job types:
- `snapshot-delete`: periodically remove and purge all kinds of snapshots that exceed the retention count.
- `snapshot-cleanup`: periodically purge removable or system snapshots.

### Non-goals [optional]

`None`

## Proposal

- Introduce two new `RecurringJobType`:
  - snapshot-delete
  - snapshot-cleanup
- Recurring job periodically deletes and purges the snapshots for RecurringJob using the `snapshot-delete` task type. Longhorn will retain snapshots based on the given retain number.
- Recurring job periodically purges the snapshots for RecurringJob using the `snapshot-cleanup` task type.

### User Stories

- The user can create a RecurringJob with `spec.task=snapshot-delete` to instruct Longhorn periodically delete and purge snapshots.
- The user can create a RecurringJob with `spec.task=snapshot-cleanup` to instruct Longhorn periodically purge removable or system snapshots.

### User Experience In Detail

#### Recurring Snapshot Deletion
1. Have some volume backups and snapshots.
1. Create RecurringJob with the `snapshot-delete` task type.
   ```yaml
   apiVersion: longhorn.io/v1beta2
   kind: RecurringJob
   metadata:
     name: recurring-snap-delete-per-min
     namespace: longhorn-system
   spec:
     concurrency: 1
     cron: '* * * * *'
     groups: []
     labels: {}
     name: recurring-snap-delete-per-min
     retain: 2
     task: snapshot-delete
   ```
1. Assign the RecurringJob to volume.
1. Longhorn deletes all expired snapshots. As a result of the above example, the user will see two snapshots after the job completes.

#### Recurring Snapshot Cleanup
1. Have some system snapshots.
1. Create RecurringJob with the `snapshot-cleanup` task type.
   ```yaml
   apiVersion: longhorn.io/v1beta2
   kind: RecurringJob
   metadata:
     name: recurring-snap-cleanup-per-min
     namespace: longhorn-system
   spec:
     concurrency: 1
     cron: '* * * * *'
     groups: []
     labels: {}
     name: recurring-snap-cleanup-per-min
     task: snapshot-cleanup
   ```
1. Assign the RecurringJob to volume.
1. Longhorn deletes all expired system snapshots. As a result of the above example, the user will see 0 system snapshot after the job completes.

### API changes

`None`

## Design

### Implementation Overview

#### The RecurringJob `snapshot-delete` Task Type

1. List all expired snapshots (similar to the current `listSnapshotNamesForCleanup` implementation), and use as the [cleanupSnapshotNames](https://github.com/longhorn/longhorn-manager/blob/d20e1ca6e04b229b9823c1a941d865929007874c/app/recurring_job.go#L418) in `doSnapshotCleanup`.
1. Continue with the current implementation to purge snapshots.

#### The RecurringJob `snapshot-cleanup` Task Type

1. Do snapshot purge only in `doSnapshotCleanup`.

### RecurringJob Mutate

1. Mutate the `Recurringjob.Spec.Retain` to 0 when the task type is `snapshot-cleanup` since retain value has no effect on the purge.

### Test plan

#### Test Recurring Snapshot Delete
1. Create volume.
1. Create 2 volume backups.
1. Create 2 volume snapshots.
1. Create a snapshot RecurringJob with the `snapshot-delete` task type.
1. Assign the RecurringJob to volume.
1. Wait until the recurring job is completed.
1. Should see the number of snapshots matching the Recurring job `spec.retain`.

#### Test Recurring Snapshot Cleanup
1. Create volume.
1. Create 2 volume system snapshots, ex: delete replica, online expansion.
1. Create a snapshot RecurringJob with the `snapshot-cleanup` task type.
1. Assign the RecurringJob to volume.
1. Wait until the recurring job is completed.
1. Should see the volume has 0 system snapshots.

### Upgrade strategy

`None`

## Note [optional]

`None`
