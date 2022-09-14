# Record Recurring Jobs in the Backup Volume

## Summary

Provide a way that users can record recurring jobs/groups during the backup creation and restore them during the backup restoration. The feature will back up all recurring jobs/groups of the volume into the backup volume configuration on the backup target and restore all jobs when users want to create a volume from a backup with recurring jobs/groups stored in the backup volume.

### Related Issues

https://github.com/longhorn/longhorn/issues/2227

## Motivation

### Goals

1. Backup or update all recurring jobs/groups to the backup volume during the backup creation.
2. Create recurring jobs/groups and bind them to the volume restored from a backup optionally.
3. It is backward compatible for current backups w/o recurring jobs info.

### Non-goals [optional]

1. Not support to back up or restore a specific recurring job/group.
2. A DR volume will not restore recurring jobs/groups during a backup restoration.

## Proposal

1. Add a global boolean setting `restore-volume-recurring-jobs`. Default value is `false`.
   When users create a volume from a backup and this setting is set to be `true`, it will automatically restore all recurring jobs/groups stored in the backup volume.
2. Add a customized string parameter `RestoreVolumeRecurringJob` in `Volume` CR. Default value is `"ignored"`. `"enabled"` is to restore recurring jobs/groups. By contrast, `"disabled"` is not to restore.
   Users can override the default behavior during the restoration at runtime by this parameter.

### User Stories

#### Story 1

Users can simply create recurring jobs from restoring a backup created by other Longhorn systems.
And continue to back up this restoring volume to the backup target with the same recurring jobs settings.

#### Story 2

When the users delete recurring jobs of the volume by accident, they could restore some recurring jobs from the backup volume by restoring a backup if they do not want to create recurring jobs manually.

### User Experience In Detail

#### Via Longhorn GUI

- Users can set `restore-volume-recurring-jobs` to be `true` on the `Settings` page.
- When users restore a backup to create a volume, they can see the recurring jobs/groups are restored and enabled automatically on the volume details page.
- Users can check the checkbox `enabled` or `disabled` to override the global setting of restoring recurring jobs/groups.

#### Via `kubectl`

- User can use the command `kubectl -n longhorn-system edit settings` to set `restore-volume-recurring-jobs` to be `true`
- Users can set `Volume.spec.restoreVolumeRecurringJob` to `enabled` or `disabled` to override the global setting of restoring recurring jobs/groups when creating a volume from a backup.
- When users create a volume by restoring a backup, they can see the recurring jobs/groups are restored as `RecurringJob` CRs and labeled in the `Volume` CR.

```yaml
...
kind: Volume
metadata:
  labels:
    longhornvolume: restore-demo
  name: restore-demo
  namespace: longhorn-system
spec:
  RestoreVolumeRecurringJob: "enabled"
  fromBackup: "nfs://nfs-sever.com:/opt/shared-path/?backup=backup-f6d9b9caa9444543&volume=backup1"
...
```

### API changes

Add a string parameter `RestoreVolumeRecurringJob` to the `Volume` struct utilized by the http client,
This ends up being stored in `Volume.spec.restoreVolumeRecurringJob` of the volume CR.

## Design

### Implementation Overview

1. Add a global boolean setting `restore-volume-recurring-jobs`. Default value is `false`. It will restore all recurring jobs/groups of the backup volume during a backup restoration if this setting is set to be `true`.
2. Add the parameter `RestoreVolumeRecurringJob` into `Volume` struct of api/model.go and volume CR. Default value is `"ignored"`.
3. Store all recurring jobs information of the volume into the backup volume configuration on the backup target during the backup creation.
   - We had saved the `"RecurringJob":"c-jaim49"` information in the `spec.labels` of the backup CR to show you the backup is created by a recurring job and this information will also be stored into backup volume configuration on the backup target and update to `status.labels` of the backup volume CR but it only contains the recurring job name and it will be changed after any recurring job creates a backup.
   - Now we back up the details of recurring jobs/groups information into backup volume configuration on the backup target and synchronized to `status.labels` of the backup volume CR. When users need to restore recurring jobs/groups to the current Longhorn system or another, it will get the recurring jobs/groups configuration from backup volume CR.

    ```text
    Backup Controller

          queue           ┌───────────────┐         ┌───────────────────────┐
         ┌┐ ┌┐ ┌┐         │               │         │                       │
     ... ││ ││ ││ ──────► │      ...      | ──────► │      reconcile()      │
         └┘ └┘ └┘         │               │         │                       │
                          └───────────────┘         └──────────┬────────────┘
                                                               │                                                        instance-manager
                                                    ┌──────────▼────────────┐         ┌──────────────────────┐         ┌──────────────────────┐
                                                    │                       │         │                      │         │                      │
                                                    │ enableBackupMonitor() │ ──────► │  NewBackupMonitor()  │  ... ─► │   SnapshotBackup()   │  ...
                                                    │                       │         │                      │         │                      │
                                                    └───────────────────────┘         └──────────────────────┘         └──────────────────────┘



    ```

    1. The `backup_controller` will be responsible for collecting recurring jobs information and send it to the backup monitor when detecting a new backup CR created.
    2. The `backup_monitor` will put recurring jobs information with a new key `VolumeRecurringJobs` into the `spec.labels` of the backup CR and trigger the backup creation.
    3. Recurring jobs information in the labels will be stored into the backup volume configuration by `backupstore`.

    Example of recurring jobs/groups information stored in the backup volume configuration.

    ```json
    { ...,
      "Labels": {
        "RecurringJob":"c-jaim49",
        "VolumeRecurringJobInfo": "{
          \"c-jaim49\": {
              \"jobSpec\": {\"name\":\"c-jaim49\",\"task\":\"backup\",\"cron\":\"0/1 * * * *\",\"retain\":3,\"concurrency\":1},
              \"fromGroup\":null,
              \"fromJob\":true
            },
          \"c-qakbzx\": {
            \"jobSpec\":{\"name\":\"c-qakbzx\",\"groups\":[\"default\"],\"task\":\"backup\",\"cron\":\"0 0 * * *\",\"retain\":5,\"concurrency\":3},
            \"fromGroup\":[\"default\"],
            \"fromJob\":false
          },
          \"c-ua7pxz\": {
            \"jobSpec\":{\"name\":\"c-ua7pxz\",\"groups\":[\"testgroup01\"],\"task\":\"backup\",\"cron\":\"0/10 0/2 * * *\",\"retain\":3,\"concurrency\":3},
            \"fromGroup\":[\"testgroup01\"],
            \"fromJob\":true
          }
        }",
        "longhorn.io/volume-access-mode":"rwo"
      },
      ...,
    }
    ```

4. Create all recurring jobs if they do not exist when restoring a backup with the setting `restore-volume-recurring-jobs` being `true` or `Volume.spec.restoreVolumeRecurringJob` being `"enabled"`.

    ```text
    Volume Controller

          queue           ┌───────────────┐         ┌───────────────────────┐
         ┌┐ ┌┐ ┌┐         │               │         │                       │
     ... ││ ││ ││ ──────► │      ...      | ──────► │      syncVolume()     │
         └┘ └┘ └┘         │               │         │                       │
                          └───────────────┘         └──────────┬────────────┘
                                                               │
                                                   ┌───────────▼─────────────┐
                                                   │                         │
                                                   │  updateRecurringJobs()  │
                                                   │                         │
                                                   └─────────────────────────┘

    ```

    1. Create all recurring jobs gotten from the backup volume CR if they do not exist or configuration is different and set volume labels of recurring jobs to be `"enabled"` before a restoration starts.

### Test plan

#### Prepare

1. Create a volume and attach it to a node or a workload.
2. Create some recurring jobs (some are in groups)
3. Label the volume with created recurring jobs (some are in groups)
4. Create a backup or wait for a recurring job starting
5. Wait for backup creation completed.
6. Check if recurring jobs/groups information is stored in the backup volume configuration on the backup target

#### Recurring Jobs exist

1. Create a volume from the backup just created.
2. Check the volume if it has labels of recurring jobs and groups.

#### Recurring Jobs do not exist

1. Delete recurring jobs that are already stored in the backup volume on the backup.
2. Create a volume from the backup just created.
3. Check if recurring jobs have been created.
4. Check if restoring volume has labels of recurring jobs and groups.

### Upgrade strategy

This enhancement doesn't require an upgrade strategy.
