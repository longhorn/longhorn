# 20240314-recurring-and-manual-full-backup-support

## Summary

This feature enables Longhorn to create **recurring job** for full backup or **manually trigger** the full backup of the volume.

### Related Issues

- Community issue: https://github.com/longhorn/longhorn/issues/7069
- Improvement issue: https://github.com/longhorn/longhorn/issues/7070

## Motivation

Longhorn always does incremental backup which only backup the newly updated blocks.
There is a chance that the previous backup blocks on the backupstore are corrupted. In this case, users can not restore the volume anymore because Longhorn aborts the restoration when it finds those blocks have different checksum.

### Goals

- Add new fields to `RecurringJob`
  - `Parameters` to `Spec`:
    - `full-backup-interval`: used in `RecurringJob - Backup Type` to execute full backup every N incremental backups (default to 0 for always incremental)
      - For example, if N is 5, then after 5 regular incremental backups, the job will perform full backup for the 6th backup
  - `ExecutionCount` to `Status`:
    - So the job knows when to run full backup if `full-backup-interval` is provided.
- Add a new fields `BackupMode` to `Backup.Spec`
  - `BackupMode`: used in `Backup` CR to trigger the full backup (Options: `"full"`, `"incremental"`, default to `"incremental"` for always incremental)
- When doing full backup, Longhorn will backup **all the current blocks** of the volume and **overwrite them** on the backupstore even if those blocks already exists on the backupstore.

- Collect metrics of `newly upload data size` and `overwritten data size` for user to better understand the cost.
  - `newly upload data size`: the data size uploaded to the backupstore in this backup
  - `overwritten data size`: the data size uploaded to the backupstore and overwritten the exists block on the backupstore.

## Proposal

### User Stories

### User Experience In Detail

#### Recurring Full Backup - Always

1. Create a `Backup` task type RecurringJob with the parameter `full-backup-interval: 0` and assign it to the volume
```
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: recurring-full-backup-per-min
  namespace: longhorn-system
spec:
  concurrency: 1
  cron: '* * * * *'
  groups: []
  labels: {}
  parameters:
    full-backup-interval: 0
  name: recurring-full-backup-per-min
  retain: 0
  task: backup
```
2. The RecurringJob runs and fully backup the volume every time.

#### Recurring Full Backup - Every N Incremental Backups

1. Create a `Backup` task type RecurringJob with the label `full-backup-interval: 5` and assign it to the volume
```
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: recurring-full-backup-per-min
  namespace: longhorn-system
spec:
  concurrency: 1
  cron: '* * * * *'
  groups: []
  labels: {}
  parameters:
    full-backup-interval: 5
  name: recurring-full-backup-per-min
  retain: 0
  task: backup
```
2. The RecurringJob runs and fully backup the volume every 5 incremental backups.

#### Manual Full Backup

1. When creating backup, users can check the checkbox `Full Backup: []` or assign `BackupMode: full` to the spec.
2. The backup will be full backup.
3. Maybe adjust the UI to make the process more simple 

## Design

### Implementation Overview

#### Metrics

1. Add two new fields `new upload data size`, `reupload data size` to the Backup Status

#### UI

1. In **Volume Page** >> **Create Backup** , add a checkbox `Full Backup: []`
  - If it is checked, automatically add the parameters `backup-mode: full` to the request payload
  - For example:
    ```
    HTTP/1.1 POST /v1/volumes/${VOLUME_NAME}?action=snapshotBackup
    Host: localhost:8080
    Accept: application/json
    Content-Type: application/json
    Content-Length: 55

    {
      "parameters": {
        "backup-mode": "full",
      },
      "name": ${BACKUP_NAME},
    }
    ```

2. In **Recurring Jo** >> **Create Recurring Job**, add a new sector for user to fill in the parameters when the task is `Backup` related task.
  - Currently only support:
    - `full-backup-interval`

3. In **Backup** >> **${BackVOlume}**, add a new field `Backup Mode`
  - If it has the parameters `backup-mode: full`, show `full`, otherwise show `incremental`

#### CRD

1. **BackupVolume**: 

2. **Backup**: add a new fields `BackupMode` to the `Spec`.
  - `BackupMode`: `"full"` to trigger full backup. Default to `"incremental"` for incremental backup

3. **RecurringJob**: add a new fields `parameters` to `Spec` and `ExecutionCount` to `Status`.
  - `Spec.Parameters["full-backup-interval"]`: Only used in `Backup` related task. Execute full backup every N incremental backups. Default to 0 for always incremental
  - `Status.ExecutionCount` to record how many job have been executed for this recurring job.

Backup CR Example
```yaml
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: backup-abcde1234
  namespace: longhorn-system
spec:
  snapshot: fake-snapshot
  backupMode: full
```

#### Backupstore
1. Need to pass `parameters` through the grpc function call chain.
2. In our implementation, if the Volume has `lastBackup`, we then always perform incremental Backup.
3. Now, if `backup-mode: full` exists in the parameters,
    - we then pretend the last Backup does not exist and force it to do the full Backup.
    - overwrites the block on the backupstore even it already exists.
4. store the `new upload data size`, `reupload data size` to the Backup Status.

#### Webhook
1. Check the parameters to prevent from typo.
2. ReucrringJob currently only accept `full-backup-interval`
3. Backup currently only accept `backup-mode`

### Test plan

#### Manually Full Backup
1. Create a Volume 4MB and fill in the content.
2. Create a Backup of the Volume.
3. Intentionally replace the content of the first block(2MB) on the backupstore
4. Restore the Volume, and will get error logs like below
    ```
    [pvc-XXXXXX] time="XXXX" level=error msg="Backup data restore Error Found in Server[gzip: invalid checksum]"
    ```
5. Create a full backup with the Spec `BackupMode: full`
6. Restore the backup, this time should work

#### Recurring Job Full Backup
1. Create a Volume 4MB and fill in the content.
2. Create a Backup of the Volume.
3. Intentionally replace the content of the first block(2MB) on the backupstore
4. Restore the Volume, and will get error logs like below
    ```
    [pvc-XXXXXX] time="XXXX" level=error msg="Backup data restore Error Found in Server[gzip: invalid checksum]"
    ```
5. Create a `backup` task type RecurringJob with the parameter `full-backup-interval: 1` and assign it to the volume
```
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: recurring-full-backup-per-min
  namespace: longhorn-system
spec:
  concurrency: 1
  cron: '* * * * *'
  groups: []
  labels: {}
  parameters:
    full-backup-interval: 1
  name: recurring-full-backup-per-min
  retain: 0
  task: backup
```
6. Wait for the recurring job to be finished.
7. Restore the backup, this time should work

#### DR Volume with Full Backup
1. Setup a backupstore.
2. Create a pod with a volume and wait for pod to start.
3. Write data to `/data/test1` inside the pod.
4. Create the 1st backup for the volume.
5. Create a DR volume based on the backup and wait for the init restoration complete.
6. Write more data to the original volume and get the md5sum.
7. Create a full backup recurring job.
8. Wait for the full backup job to be finished.
9. Activate the DR volume and check the md5sum is the same as the original volume.

### Upgrade strategy

No need.

## Note [optional]

None.