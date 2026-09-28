# Recurring Volume Group Snapshot

## Summary

This LEP extends the Volume Group Snapshot LEP (LEP 20260811): introduced the SnapshotGroup CRD and controller, so a set of volumes can be snapshot together as one group. 
It adds new RecurringJob task types: `snapshot-group`. On each scheduled run the job creates one `SnapshotGroup` through the group snapshot feature, covering the volumes the job selects.

### Related Issues

https://github.com/longhorn/longhorn/issues/13821
https://github.com/longhorn/longhorn/issues/13349

## Motivation

### Goals

- Add a RecurringJob task, `snapshot-group`, that creates a `SnapshotGroup` on a cron schedule. 
- Reuse the existing RecurringJob configuration model so users configure group jobs the same way as other jobs.
- Never delete groups that the job did not create (groups made by users, CSI, or other jobs).
- Ensure `snapshot-delete` task skips deletion of snapshots belonging to group, and delete the oldest snapshot that is independent of any groups.
- Add `Snapshot Group` as an option in the task dropdown when creating a recurring job in the Longhorn UI.
- Make failures visible: a run that cannot create a group reports the reason through events and job status instead of failing silently.

### Non-goals [optional]

- A group-level retention task: which lets the job keep the newest N groups it created and deletes older whole groups, so group snapshots do not pile up on member volumes.
- Application-level consistency (pausing the application). This remains future work in longhorn/longhorn#2128.
- Changes to the SnapshotGroup CRD, its controller, or its webhooks.

## Proposal

- Introduce a new `RecurringJobType`: snapshot-group
- Recurring job periodically creates `snapshotGroup` to take snapshot of the volume groups.

### User Stories

- The user can create a RecurringJob with `spec.task=snapshot-group` to instruct Longhorn periodically take snapshots for the multi-volume applications.

### User Experience In Detail

1. The user labels PVCs to be used for snapshot grouping (for example `app-group: demo`).
2. The user creates a RecurringJob:
  ```yaml
  apiVersion: longhorn.io/v1beta2
  kind: RecurringJob
  metadata:
   name: recurring-group-snapshot
   namespace: longhorn-system
  spec:
   cron: '* * * * *'
   groups: []
   labels: {}
   name: recurring-group-snapshot
   task: snapshot-group
  ```
3. On each run, one `SnapshotGroup` appears in longhorn-system, carrying a label that identifies the creating job.

### API changes
`None`

## Design

### Implementation Overview

1. **Task registration**:
   - Add `RecurringJobTypeSnapshotGroup`, register in [isValidRecurringJobTask()](https://github.com/longhorn/longhorn-manager/blob/c15c9afe72e4203df5b20536ac5f4e32ad189ecc/datastore/longhorn.go#L6741).
2. **Dispatch**:
  - Add explicit switch cases for task so neither falls into the per-volume [default: StartVolumeJobs](https://github.com/longhorn/longhorn-manager/blob/master/app/recurring_job.go#L92) path.
3. **StartSnapshotGroupJob**:
  - modeled on `StartSystemBackupJob`.
  - Resolve member volumes once per run.
  - Generate a group name create one `SnapshotGroup`.
  - Apply retention.
  - If member resolution or group creation fails, record an event and end the run without failing the process.
4. **Concurrency**: 
  - If the job's previous group is still `InProgress`, skip creating a new one this run and record an event.
5. **snapshot-delete interaction**:
  - Modify `snapshot-delete` to skip snapshots labeled as group members, and delete the oldest non-member snapshot on that volume.
  - If no non-member snapshot exists, skip deletion and emit a warning event that the volume may exceed `snapshot-max-count`.

### Test plan

1. Deploy a multi-volume application.
2. Create a RecurringJob with the `snapshot-group` task type, targeting the app's `Groups` label.
3. Wait for the job to run on schedule.
4. Verify a `SnapshotGrou`p is created containing a snapshot for each labeled volume, taken as one run.
5. Verify a second run while the first is still `InProgress` is skipped (event logged, no new group created).
6. Trigger `snapshot-delete` on a member volume and verify group snapshots are skipped, with the oldest non-member snapshot removed instead.

### Upgrade strategy

The new task type has no effect on existing RecurringJobs, and the base LEP's group toggle and CRD are unchanged. The feature depends on the SnapshotGroup CRD and controller from the base LEP, so it can only be used on versions that include them.

## Note [optional]

Additional notes.
