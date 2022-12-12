# Label-driven Recurring Job

## Summary

Replace volume spec `recurringJobs` with the label-driven model. Abstract volume recurring jobs to a new CRD named "RecurringJob". The names or groups of recurring jobs can be referenced in volume labels.

Users can set a recurring job to the `Default` group and Longhorn will automatically apply when the volume has no job labels.

Only one cron job will be created per recurring job. Users can also update the recurring job, and Longhorn reflects the changes to the associated cron job.

When instruct Longhorn to delete a recurring job, this will also remove the associated cron job.

StorageClass now should use `recurringJobSelector` instead to refer to the recurring job names.

During the version upgrade, existing volume spec `recurringJobs` and storageClass `recurringJobs` will automatically translate to volume labels, and recurring job CRs will get created.

### Related Issues

https://github.com/longhorn/longhorn/issues/467

## Motivation

### Goals

Phase 1:
- Each recurring job can be in single or multiple groups.
- Each group can have single or multiple recurring jobs.
- The jobs and groups can be reference with the volume label.
- The recurring job in `default` group will automatically apply to a volume that has no job labels.
- Can create multiple recurring jobs with UI or YAML.
- The recurring job should include settings; `name`, `groups`, `task`, `cron`, `retain`, `concurrency`, `labels`.

Phase2:
The StorageClass and upgrade migration are still dependent on volume spec, thus complete removal of volume spec should be done in phase 2.

### Non-goals [optional]

1. Does the snapshot/backup operation one by one. The operation order can be defined as sequential, consistent (for volume group snapshot), or throttled (with a concurrent number as a parameter) in the future.

> https://github.com/longhorn/longhorn/pull/2737#issuecomment-887985811

## Proposal

#### Story 1 - set recurring jobs and groups by volume labels

As a Longhorn user / System administrator.

I want to directly update recurring jobs referenced in multiple volumes.

So I do not need to update each volume with cron job definition.

#### Story 2 - automatically applies for the default recurring jobs.

As a Longhorn user / System administrator.

I want the ability to set one or multiple `backup` and `snapshot` recurring jobs as default. All volumes without any recurring job label should automatically apply with the default recurring jobs.

So I can be assured that all volumes without any recurring job label will automatically apply with default.

#### Story 3 - automatically upgrade migration

As a Longhorn user / System administrator

I want Longhorn to automatically convert existing volume spec `recurringJobs` to volume labels, and create associate recurring job CRs.

So I don't have to manually create recurring job CRs and patch the labels.

### User Experience In Detail

#### Story 1 - set recurring job in volume

1. Create a recurring job on UI `Recurring Job` page or via `kubectl`.
2. In UI, Navigate to Volume, `Recurring Jobs Schedule`.
3. User can choose from `Job` or job `Group` from the tab.
  - On `Job` tab,
    1. User sees existing recurring jobs that volume had labeled.
    1. User able to select `Backup` or `Snapshot` for the `Type` from the drop-down list.
    2. User able to edit the `Schedule`, `Retain`, `Concurrency` and `Labels`.
  - On the job `Group` tab.
    1. User sees all existing recurring job groups from the `Name` drop-down list.
    2. User selects the job from the drop-down list.
    3. User sees all recurring `jobs` under the `group`.
4. Click `Save` updates to the volume label.
5. Update the recurring job CRs also reflect on the cron job and UI `Recurring Jobs Schedule`.

**Before enhancement**

Recurring jobs can only be added and updated per volume spec.

Create cron job definitions for each volume causing duplicated setup effort.

The recurring job can only be updated per volume.

**After enhancement**

Recurring jobs can be added and update as the volume label.

Can select a recurring job from the UI drop-down menu and will automatically show the information from the recurring job CRs.

Update the recurring job definition will automatically apply to all volumes with the job label.

#### Story 2 - automatically apply to default recurring jobs

1. Add `default` to one or multiple recurring jobs `Groups` in UI or `kubectl`.
2. Longhorn automatically applies the `default` group recurring jobs to all volumes without job labels.

**Before enhancement**

Default recurring jobs are set via StorageClass at PVC creation only. No default recurring job can be set up for UI-created volumes.

Updating StorageClass does not reflect on the existing volumes.

**After enhancement**

Have the option to set default recurring jobs via `StorageClass` or `RecurringJob`.

Longhorn recurring job controller automatically applies default recurring jobs to all volumes without the job labels.

Longhorn adds the default recurring jobs when all job labels are removed from the volume.

When the `RecurringJobSelector` is set in the `StorageClass`, it will be used as default instead.

#### Story 3 - automatically upgrade migration

1. Perform upgrade.
2. StorageClass `recurringJobs` will get convert to `recurringJobSelector`.
3. Recurring job CRs will get created from `recurringJobs`.
4. Volume will be labeled with `recurring-job.longhorn.io/<jobTask>-<jobRetain>-<hash(jobCron)>-<hash(jobLabelJSON)>: enabled` from volume spec `recurringJobs`.
5. Recurring job CRs will get created from volume spec `recurringJobs`. When the config is identical among multiple volumes, only one will get created and volumes will share this recurring job CR.
6. Volume spec `recurringJobs` will get removed.

### API Changes

- Add new HTTP endpoints:
  - GET `/v1/recurringjobs` to list of recurring jobs.
  - GET `/v1/recurringjobs/{name}` to get specific recurring job.
  - DELETE `/v1/recurringjobs/{name}` to delete specific recurring job.
  - POST `/v1/recurringjobs` to create a recurring job.
  - PUT `/v1/recurringjobs/{name}` to update specific recurring job.
  - `/v1/ws/recurringjobs` and `/v1/ws/{period}/recurringjobs` for websocket stream.
- Add new RESTful APIs for the new `RecurringJob` CRD:
  - `Create`
  - `Update`
  - `List`
  - `Get`
  - `Delete`
- Add new APIs for users to update recurring jobs for individual volume. The :
  - `/v1/volumes/<VOLUME_NAME>?action=recurringJobAdd`, expect request's body in form {name:<name>, isGroup:<bool>}.
  - `/v1/volumes/<VOLUME_NAME>?action=recurringJobList`.
  - `/v1/volumes/<VOLUME_NAME>?action=recurringJobDelete`, expect request's body in form {name:<name>, isGroup:<bool>}.

## Design

### Implementation Overview

#### Add Recurring Job CRD.
  - Update the ClusterRole to include `recurringjob`.
  - Printer column should include `Name`, `Groups`, `Task`, `Cron`, `Retain`, `Concurrency`, `Age`, `Labels`.
     ```
     NAME        GROUPS                 TASK       CRON        RETAIN   CONCURRENCY   AGE   LABELS
     snapshot1   ["default","group1"]   snapshot   * * * * *   1        2             14m   {"label/1":"a","label/2":"b"}

     ```
     - The `Name`: String used to reference the recurring job in volume with the label `recurring-job.longhorn.io/<Name>: enabled`.
     - The `Groups`: Array of strings that set groupings to the recurring job. This is used to reference the recurring job group in volume with the label `recurring-job-group.longhorn.io/<Name>: enabled`. When including `default`, the recurring job will be added to the volume label if no other job exists in the volume label.
     - The `Task`: String of either one of `backup` or `snapshot`.
       Also, add validation in the CRD YAML with pattern regex match.
     - The `Cron`: String in cron expression represents recurring job scheduling.
     - The `Retain`: Integer of the number of snapshots/backups to keep for the volume.
     - The `Concurrency`: Integer of the concurrent job to run by each cron job.
     - The `Age`: Date of the CR creation timestamp.
     - The `Labels`: Dictionary of the labels.

#### Add Command `recurring-job` To `longhorn-manager` Binary

  1. Add new command `recurring-job <job.name> --longhorn-manager <URL>` and remove old command `snapshot`.
     > Get the `recurringJob.Spec` on execution using Kubernetes API.
  2. Get volumes by label selector `recurring-job.longhorn.io/<job.name>: enabled` to filter out volumes.
  3. Get volumes by label selector `recurring-job-group.longhorn.io/<job.group>: enabled` to filter out volumes if the job is set with a group.
  4. Filter and create a list of the volumes in the state `attached` or setting `allow-recurring-job-while-volume-detached`.
  5. Use the concurrent number parameter to throttle goroutine with channel. Each goroutine creates `NewJob()` and `job.run()` for the volumes.
     The job `snapshotName` format will be `<job.name>-c-<RandomID>`.

#### Changes In The Volume Controller

  1. The `updateRecurringJobs` method is responsible to add the default label if not other labels exist.

  > Since the storage class and upgrade migration contains recurringJobs spec. So we will keep the `VolumeSpec.RecurringJobs` in code to create the recurring jobs for volumes from the `storageClass`.

  > In case names are duplicated between different `storageClasses`, only one recurring job CR will be created.

#### Changes In The VolumeManager `CreateVolume`

  - Add new method input `recurringJobSelector`:
     1. Convert `Volume.Spec.RecurringJobs` to `recurringJobSelector`.
     2. Add recurring job label if `recurringJobSelector` method input is not empty.

#### Changes In The Datastore

  - For `CreateVolume` and `UpdateVolume` add a function similar to `fixupMetadata` that handles recurring jobs:
     1. Add recurring job labels if `Volume.Spec.RecurringJobs` is not empty. Then unset `Volume.Spec.RecurringJobs`.
     2. Label with `default` job-group if no other recurring job label exists.

#### Introduce `recurringJobSelector` As Part Of StorageClass Parameters.
  - The CSI controller can use `recurringJobSelector` for volume creation.

#### Changes In CSI Controller Server

  1. Put `recurringJobSelector` to `vol.RecurringJobSelector` at HTTP API layer to use for adding volume recurring job label in `VolumeManager.CreateVolume`. The `CreateVolume` method will have a new input `recurringJobSelector`.
  2. Get `recurringJobs` from parameters, validate and create recurring job CRs via API if not already exist.

#### Add Recurring Job Controller

  - The code structure will be the same as other controllers.
  - Add the finalizer to the recurring job CRs if not exist.
  - The controller will be informed by `recurringJobInformer` and `enqueueRecurringJob`.
  - Create and update CronJob per recurring job.
    1. Generate a new cron job object.
       - Include labels `recurring-job.longhorn.io`.
         ```
         recurring-job.longhorn.io: <Name>
         ```
       - Compose command,
         ```
         longhorn-manager -d\
           recurring-job <job.name>\
           --manager-url <url>
         ```
    2. Create new cron job with annotation `last-applied-cronjob-spec` or update cron job if the new cron job spec is different from the `last-applied-cronjob-spec`.
  - Use defer to clean up CronJob.
    1. When a recurring job gets deleted.
      1. Delete the cron job with selected labels: `recurring-job.longhorn.io/<Name>`.
      2. Remove the finalizer.


#### UI

##### Add New Page `Recurring Job` In UI

A new page for `Recurring Job` to create/update/delete recurring jobs.

```
Recurring Job                                                                                        [Custom Column]
====================================================================================================================
[Create] [Delete]                                                                  [Search Box   v ][__________][Go]
                                                                                   | Name
                                                                                   | Group
                                                                                   | Type
                                                                                   | Schedule
                                                                                   | Labels
                                                                                   | Retain
                                                                                   | Concurrency
===================================================================================================================
[] | Name  | Group  | Type   | Schedule        | Labels       | Retain | Concurrency | Operation   |
---+-------+--------+--------+-----------------+--------------+--------+-------------+-------------+--------------|
[] | dummy | aa, bb | backup | 00:00 every day | k1:v1, k2:v2 | 20     | 10          | [Icon]    v |
                                                                                       | Update
                                                                                       | Delete
===================================================================================================================
                                                 [<] [1] [>]
```

**Scenario: Add Recurring Job**

*Given* user sees `Create` on top left of the page.

*When* user click `Create`.  
*Then* user sees a pop-up form.

```
* Name
[      ]

Groups +

* Task
[Backup]

* Schedule
[00:00 every day]

* Retain
[20]

* Concurrency
[10]

* Labels +
```

- Field with `*` is mendatory
- User can click on `+` next to `Group` to add more groups.
- User can click on the `Schedule` field and a window will pop-up for `Cron` and `Generate Cron`.
- `Retain` cannot be `0`.
- `Concurrency` cannot be `0`.
- User can click on `+` next to `Labels` to add more labels.

*When* user click `OK`.  
*Then* frontend **POST** `/v1/recurringjobs` to create a recurring job.
```
❯ curl -X POST -H "Content-Type: application/json" \
-d '{"name": "sample", "groups": ["group-1", "group-2"], "task": "snapshot", "cron": "* * * * *", "retain": 2, "concurrency": 1, "labels": {"label/1": "a"}}' \
http://54.251.150.85:30944/v1/recurringjobs | jq
{
  "actions": {},
  "concurrency": 1,
  "cron": "* * * * *",
  "groups": [
    "group-1",
    "group-2"
  ],
  "id": "sample",
  "labels": {
    "label/1": "a"
  },
  "links": {
    "self": "http://54.251.150.85:30944/v1/recurringjobs/sample"
  },
  "name": "sample",
  "retain": 2,
  "task": "snapshot",
  "type": "recurringJob"
}
```

**Scenario: Update Recurring Job**

*Given* an `Operation` drop-down list next to the recurring job. 

*When* user click `Edit`.  
*Then* user sees a pop-up form.
```
Name
[sample]

Groups
[group-1]
[group-2]

Task
[Backup]

Schedule
[00:00 every day]

Retain
[20]

Concurrency
[10]

Labels
[labels/1]: [a]
[labels/2]: [b]
```
- `Name` field should be immutable.
- `Task` field should be immutable.

*And* user edit the fields in the form.

*When* user click `Save`.  
*Then* frontend **PUT** `/v1/recurringjobs/{name}` to update specific recurring job.
```
❯ curl -X PUT -H "Content-Type: application/json" \
-d '{"name": "sample", "groups": ["group-1", "group-2"], "task": "snapshot", "cron": "* * * * *", "retain": 2, "concurrency": 1, "labels": {"label/1": "a", "label/2": "b"}}' \
http://54.251.150.85:30944/v1/recurringjobs/sample | jq
{
  "actions": {},
  "concurrency": 1,
  "cron": "* * * * *",
  "groups": [
    "group-1",
    "group-2"
  ],
  "id": "sample",
  "labels": {
    "label/1": "a",
    "label/2": "b"
  },
  "links": {
    "self": "http://54.251.150.85:30944/v1/recurringjobs/sample"
  },
  "name": "sample",
  "retain": 2,
  "task": "snapshot",
  "type": "recurringJob"
}
```

**Scenario: Delete Recurring Job**

*Given* an `Operation` drop-down list next to the recurring job.  

*When* user click `Delete`.  
*Then* user should see a pop-up window for confirmation.

*When* user click `OK`.  
*Then* frontend **DELETE** `/v1/recurringjobs/{name}` to delete specific recurring job.
```
❯ curl -X DELETE http://54.251.150.85:30944/v1/recurringjobs/sample | jq
```

> Also need a button for batch deletion on top left of the table.

##### Updates `Volume` Page On UI

**Scenario: Select From Recurring Job or Job Group**

*When* user should be able to choose if want to add recurring job as `Job` or `Group` from the tab.

**Scenario: Add Recurring Job Group On Volume Page**

*Given* user go to job `Group` tab.  
*When* user click `+ New`.  
*And* Frontend can **GET** `/v1/recurringjobs` to list of recurring jobs.  
*And* Frontend need to gather all `groups` from data.  
```
❯ curl -X GET http://54.251.150.85:30783/v1/recurringjobs | jq
{
  "data": [
    {
      "actions": {},
      "concurrency": 2,
      "cron": "* * * * *",
      "groups": [
        "group2",
        "group3"
      ],
      "id": "backup1",
      "labels": null,
      "links": {
        "self": "http://54.251.150.85:30783/v1/recurringjobs/backup1"
      },
      "name": "backup1",
      "retain": 1,
      "task": "backup",
      "type": "recurringJob"
    },
    {
      "actions": {},
      "concurrency": 2,
      "cron": "* * * * *",
      "groups": [
        "default",
        "group1"
      ],
      "id": "snapshot1",
      "labels": {
        "label/1": "a",
        "label/2": "b"
      },
      "links": {
        "self": "http://54.251.150.85:30783/v1/recurringjobs/snapshot1"
      },
      "name": "snapshot1",
      "retain": 1,
      "task": "snapshot",
      "type": "recurringJob"
    }
  ],
  "links": {
    "self": "http://54.251.150.85:30783/v1/recurringjobs"
  },
  "resourceType": "recurringJob",
  "type": "collection"
}
```
*Then* the user selects the group from the drop-down list.

*When* user click on `Save`.  
*Then* frontend **POST** `/v1/volumes/<VOLUME_NAME>?action=recurringJobAdd` with request body `{name: <group-name>, isGroup: true}`.  
```
❯ curl -X POST -H "Content-Type: application/json" \
-d '{"name": "test3", "isGroup": true}' \
http://54.251.150.85:30783/v1/volumes/pvc-4011f9a6-bae3-43e3-a2a1-893997d0aa63\?action\=recurringJobAdd | jq
{
  "data": [
    {
      "actions": {},
      "id": "default",
      "isGroup": true,
      "links": {
        "self": "http://54.251.150.85:30783/v1/volumerecurringjobs/default"
      },
      "name": "default",
      "type": "volumeRecurringJob"
    },
    {
      "actions": {},
      "id": "test3",
      "isGroup": true,
      "links": {
        "self": "http://54.251.150.85:30783/v1/volumerecurringjobs/test3"
      },
      "name": "test3",
      "type": "volumeRecurringJob"
    }
  ],
  "links": {
    "self": "http://54.251.150.85:30783/v1/volumes/pvc-4011f9a6-bae3-43e3-a2a1-893997d0aa63"
  },
  "resourceType": "volumeRecurringJob",
  "type": "collection"
}
```
*And* user sees all `jobs` with the `group`.  

**Scenario: Remove Recurring Job Group On Volume Page**

*Given* user go to job `Group` tab.  
*When* user click the `bin` icon of the recurring job group.  
*Then* frontend `/v1/volumes/<VOLUME_NAME>?action=recurringJobDelete` with request body `{name: <group-name>, isGroup: true}`.
```
❯ curl -X POST -H "Content-Type: application/json" \
-d '{"name": "test3", "isGroup": true}' \
http://54.251.150.85:30783/v1/volumes/pvc-4011f9a6-bae3-43e3-a2a1-893997d0aa63\?action\=recurringJobDelete | jq
{
  "data": [
    {
      "actions": {},
      "id": "default",
      "isGroup": true,
      "links": {
        "self": "http://54.251.150.85:30783/v1/volumerecurringjobs/default"
      },
      "name": "default",
      "type": "volumeRecurringJob"
    }
  ],
  "links": {
    "self": "http://54.251.150.85:30783/v1/volumes/pvc-4011f9a6-bae3-43e3-a2a1-893997d0aa63"
  },
  "resourceType": "volumeRecurringJob",
  "type": "collection"
}
```

**Scenario: Add Recurring Job On Volume Page**

*Given* user go to `Job` tab.  
*When* user click `+ New`.  
*And* user sees the name is auto-generated.  
*And* user can select `Backup` or `Snapshot` from the drop-down list.  
*And* user can edit `Schedule`, `Labels`, `Retain` and `Concurrency`.

*When* user click on `Save`.  
*Then* frontend **POST** /v1/recurringjobs to create a recurring job.
```
❯ curl -X POST -H "Content-Type: application/json" \
-d '{"name": "backup1", "groups": [], "task": "backup", "cron": "* * * * *", "retain": 2, "concurrency": 1, "labels": {"label/1": "a"}}' \
http://54.251.150.85:30944/v1/recurringjobs | jq
{
  "actions": {},
  "concurrency": 1,
  "cron": "* * * * *",
  "groups": [],
  "id": "backup1",
  "labels": {
    "label/1": "a"
  },
  "links": {
    "self": "http://54.251.150.85:30783/v1/recurringjobs/backup1"
  },
  "name": "backup1",
  "retain": 2,
  "task": "backup",
  "type": "recurringJob"
}
```
*And* frontend **POST** `/v1/volumes/<VOLUME_NAME>?action=recurringJobAdd` with request body `{name: <job-name>, isGroup: false}`.
```
❯ curl -X POST -H "Content-Type: application/json" \
-d '{"name": "backup1", "isGroup": false}' \
http://54.251.150.85:30783/v1/volumes/pvc-4011f9a6-bae3-43e3-a2a1-893997d0aa63\?action\=recurringJobAdd | jq
{
  "data": [
    {
      "actions": {},
      "id": "default",
      "isGroup": true,
      "links": {
        "self": "http://54.251.150.85:30783/v1/volumerecurringjobs/default"
      },
      "name": "default",
      "type": "volumeRecurringJob"
    },
    {
      "actions": {},
      "id": "backup1",
      "isGroup": false,
      "links": {
        "self": "http://54.251.150.85:30783/v1/volumerecurringjobs/backup1"
      },
      "name": "backup1",
      "type": "volumeRecurringJob"
    }
  ],
  "links": {
    "self": "http://54.251.150.85:30783/v1/volumes/pvc-4011f9a6-bae3-43e3-a2a1-893997d0aa63"
  },
  "resourceType": "volumeRecurringJob",
  "type": "collection"
}
```

**Scenario: Delete Recurring Job On Volume Page**

Same as **Scenario: Remove Recurring Job Group in Volume Page** with request body `{name: <group-name>, isGroup: false}`.
```
❯ curl -X POST -H "Content-Type: application/json" \
-d '{"name": "backup1", "isGroup": false}' \
http://54.251.150.85:30783/v1/volumes/pvc-4011f9a6-bae3-43e3-a2a1-893997d0aa63\?action\=recurringJobDelete | jq
{
  "data": [
    {
      "actions": {},
      "id": "default",
      "isGroup": true,
      "links": {
        "self": "http://54.251.150.85:30783/v1/volumerecurringjobs/default"
      },
      "name": "default",
      "type": "volumeRecurringJob"
    }
  ],
  "links": {
    "self": "http://54.251.150.85:30783/v1/volumes/pvc-4011f9a6-bae3-43e3-a2a1-893997d0aa63"
  },
  "resourceType": "volumeRecurringJob",
  "type": "collection"
}
```

**Scenario: Keep Recurring Job Details Updated On Volume Page**

- Frontend can monitor new websocket `/v1/ws/recurringjobs` and `/v1/ws/{period}/recurringjobs`.
- When a volume is labeled with a none-existing recurring job or job-group. UI should show warning icon.

### Test plan

> The existing recurring job test cases need to be fixed or replaced.

#### Integration test - test_recurring_job_group

Scenario: test recurring job groups (S3/NFS)

    Given create `snapshot1` recurring job with `group-1, group-2` in groups.
               set cron job to run every 2 minutes.
               set retain to 1.
          create `backup1`   recurring job with `group-1`          in groups.
               set cron job to run every 3 minutes.
               set retain to 1
    And volume `test-job-1` created, attached, and healthy.
        volume `test-job-2` created, attached, and healthy.

    When set `group1` recurring job in volume `test-job-1` label.
         set `group2` recurring job in volume `test-job-2` label.
    And write some data to volume `test-job-1`.
        write some data to volume `test-job-2`.
    And wait for 2 minutes.
    And write some data to volume `test-job-1`.
        write some data to volume `test-job-2`.
    And wait for 1 minute.

    Then volume `test-job-1` should have 3 snapshots after scheduled time.
         volume `test-job-2` should have 2 snapshots after scheduled time.
     And volume `test-job-1` should have 1 backup after scheduled time.
         volume `test-job-2` should have 0 backup after scheduled time.

#### Integration test - test_recurring_job_default

Scenario: test recurring job set with default in groups

    Given 1 volume created, attached, and healthy.

    When create `snapshot1` recurring job with `default, group-1` in groups.
         create `snapshot2` recurring job with `default`          in groups..
         create `snapshot3` recurring job with ``                 in groups.
         create `backup1`   recurring job with `default, group-1` in groups.
         create `backup2`   recurring job with `default`          in groups.
         create `backup3`   recurring job with ``                 in groups.
    Then default `snapshot1` cron job should     exist.
         default `snapshot2` cron job should     exist.
                 `snapshot3` cron job should not exist.
         default `backup1`   cron job should     exist.
         default `backup2`   cron job should     exist.
                 `backup3`   cron job should not exist.

    # Setting recurring job in volume label should not remove the defaults.
    When set `snapshot3` recurring job in volume label.
    Then should contain `default`   job-group in volume labels.
         should contain `snapshot3` job       in volume labels.
    And  default `snapshot1` cron job should     exist.
         default `snapshot2` cron job should     exist.
                 `snapshot3` cron job should     exist.
         default `backup1`   cron job should     exist.
         default `backup2`   cron job should     exist.
                 `backup3`   cron job should not exist.

    # Should be able to remove the default.
    When delete recurring job-group `default` in volume label.
    And  default `snapshot1` cron job should not exist.
         default `snapshot2` cron job should not exist.
                 `snapshot3` cron job should     exist.
         default `backup1`   cron job should not exist.
         default `backup2`   cron job should not exist.
                 `backup3`   cron job should not exist.

    # Remove all volume recurring job labels should bring in default
    When delete all recurring jobs in volume label.
    Then default `snapshot1` cron job should     exist.
         default `snapshot2` cron job should     exist.
                 `snapshot3` cron job should not exist.
         default `backup1`   cron job should     exist.
         default `backup2`   cron job should     exist.
                 `backup3`   cron job should not exist.

    # Add `default` to snapshot3 and backup3 recurring job `Group`.
    # should also reflect on the cron jobs
    When add `snapshot3` recurring job with `default` in groups.
         add `backup3`   recurring job with `default` in groups.
    Then default `snapshot1` cron job should exist.
         default `snapshot2` cron job should exist.
         default `snapshot3` cron job should exist.
         default `backup1`   cron job should exist.
         default `backup2`   cron job should exist.
         default `backup3`   cron job should exist.

    # Remove `default` in recurring job `Group` should also
    # reflect on the cron jobs
    When remove `default` from `snapshot3` recurring job groups.
    Then default `snapshot1` cron job should     exist.
         default `snapshot2` cron job should     exist.
                 `snapshot3` cron job should not exist.
         default `backup1`   cron job should     exist.
         default `backup2`   cron job should     exist.
         default `backup3`   cron job should     exist.

    # Remove `default` in all recurring job `Group` should also
    # reflect on the cron jobs
    When remove `default` from all recurring jobs groups.
    Then `snapshot1` cron job should not exist.
         `snapshot2` cron job should not exist.
         `snapshot3` cron job should not exist.
         `backup1`   cron job should not exist.
         `backup2`   cron job should not exist.
         `backup3`   cron job should not exist.


#### Integration test - test_recurring_job_delete

Scenario: test delete recurring job

    Given 1 volume created, attached, and healthy.

    When create `snapshot1` recurring job with `default, group-1` in groups.
         create `snapshot2` recurring job with `default`          in groups..
         create `snapshot3` recurring job with ``                 in groups.
         create `backup1`   recurring job with `default, group-1` in groups.
         create `backup2`   recurring job with `default`          in groups.
         create `backup3`   recurring job with ``                 in groups.
    Then default `snapshot1` cron job should     exist.
         default `snapshot2` cron job should     exist.
                 `snapshot3` cron job should not exist.
         default `backup1`   cron job should     exist.
         default `backup2`   cron job should     exist.
                 `backup3`   cron job should not exist.

    # Delete `snapshot2` recurring job should delete the cron job
    When delete `snapshot-2` recurring job.
    Then default `snapshot1` cron job should     exist.
         default `snapshot2` cron job should not exist.
                 `snapshot3` cron job should not exist.
         default `backup1`   cron job should     exist.
         default `backup2`   cron job should     exist.
                 `backup3`   cron job should not exist.
     
    # Delete multiple recurring jobs should reflect on the cron jobs.
    When delete `backup-1` recurring job.
         delete `backup-2` recurring job.
         delete `backup-3` recurring job.
    Then default `snapshot1` cron job should     exist.
         default `snapshot2` cron job should not exist.
                 `snapshot3` cron job should not exist.
         default `backup1`   cron job should not exist.
         default `backup2`   cron job should not exist.
                 `backup3`   cron job should not exist.
     
     # Should be able to delete recurring job while existing in volume label
     When add `snapshot1` recurring job to volume label.
          add `snapshot3` recurring job to volume label.
     And default `snapshot1` cron job should     exist.
         default `snapshot2` cron job should not exist.
                 `snapshot3` cron job should     exist.
     And delete `snapshot1` recurring job.
         delete `snapshot3` recurring job.
     Then default `snapshot1` cron job should not exist.
          default `snapshot2` cron job should not exist.
                  `snapshot3` cron job should not exist.


#### Integration test - test_recurring_job_volume_labeled_none_existing_recurring_job

Scenario: test volume with a none-existing recurring job label
          and later on added back.

    Given create `snapshot1` recurring job.
          create `backup1`   recurring job.
    And 1 volume created, attached, and healthy.
        add `snapshot1` recurring job to volume label.
        add `backup1`   recurring job to volume label.
    And `snapshot1` cron job exist.
        `backup1`   cron job exist.

    When delete `snapshot1` recurring job.
         delete `backup1`   recurring job.
    Then `snapshot1` cron job should not exist.
         `backup1`   cron job should not exist.
    And `snapshot1` recurring job should exist in volume label.
        `backup1` recurring job should exist in volume label.

    # Add back the recurring jobs.
    When create `snapshot1` recurring job.
         create `backup1`   recurring job.
    Then `snapshot1` cron job should exist.
         `backup1`   cron job should exist.

#### Integration test - test_recurring_job_with_multiple_volumes

Scenario: test recurring job with multiple volumes

    Given volume `test-job-1` created, attached and healthy.
    And  create `snapshot1` recurring job with `default` in groups.
         create `snapshot2` recurring job with ``        in groups.
         create `backup1`   recurring job with `default` in groups.
         create `backup2`   recurring job with ``        in groups.
    And volume `test-job-1` should have recurring job-group `default` label.
    And default `snapshot1` cron job exist.
        default `backup1`   cron job exist.

    When create and attach volume `test-job-2`.
         wait for volume `test-job-2` to be healthy.
    Then volume `test-job-2` should have recurring job-group `default` label.

    When add `snapshot2` in `test-job-2` volume label.
         add `backup2`   in `test-job-2` volume label.
    Then default `snapshot1` cron job should exist.
                 `snapshot2` cron job should exist.
         default `backup1`   cron job should exist.
                 `backup2`   cron job should exist.
    And volume `test-job-1` should have recurring job-group `default` label.
        volume `test-job-2` should have recurring job `snapshot2` label.
        volume `test-job-2` should have recurring job `backup2`   label.

#### Integration test - test_recurring_job_snapshot

Scenario: test recurring job snapshot

    Given volume `test-job-1` created, attached, and healthy.
          volume `test-job-2` created, attached, and healthy.

    When create `snapshot1` recurring job with `default` in groups.
    Then should have 1 cron job.
    And volume `test-job-1` should have volume-head 1 snapshot.
        volume `test-job-2` should have volume-head 1 snapshot.

    When write some data to volume `test-job-1`.
         write some data to volume `test-job-2`.
    Then volume `test-job-1` should have 2 snapshots after scheduled time.
         volume `test-job-2` should have 2 snapshots after scheduled time.

    When write some data to volume `test-job-1`.
         write some data to volume `test-job-2`.
    And wait for `snapshot1` cron job scheduled time.
    Then volume `test-job-1` should have 3 snapshots after scheduled time.
         volume `test-job-2` should have 3 snapshots after scheduled time.

#### Integration test - test_recurring_job_backup

Scenario: test recurring job backup (S3/NFS)

    Given volume `test-job-1` created, attached, and healthy.
          volume `test-job-2` created, attached, and healthy.

    When create `backup1` recurring job with `default` in groups.
    Then should have 1 cron job.
    And volume `test-job-1` should have 0 backup.
        volume `test-job-2` should have 0 backup.

    When write some data to volume `test-job-1`.
         write some data to volume `test-job-2`.
    And wait for `backup1` cron job scheduled time.
    Then volume `test-job-1` should have 1 backups.
         volume `test-job-2` should have 1 backups.

    When write some data to volume `test-job-1`.
         write some data to volume `test-job-2`.
    And wait for `backup1` cron job scheduled time.
    Then volume `test-job-1` should have 2 backups.
         volume `test-job-2` should have 2 backups.

#### Integration test - test_recurring_job_while_volume_detached

Scenario: test recurring job while volume is detached

    Given volume `test-job-1` created, and detached.
          volume `test-job-2` created, and detached.
    And attach volume `test-job-1` and write some data.
        attach volume `test-job-2` and write some data.
    And detach volume `test-job-1`.
        detach volume `test-job-2`.

    When create `snapshot1` recurring job running at 1 minute interval,
               and with `default` in groups,
               and with `retain` set to `2`.
    And 1 cron job should be created.
    And wait for 2 minutes.
    Then attach volume `test-job-1` and wait until healthy.
    And volume `test-job-1` should have only 1 snapshot.

    When wait for 1 minute.
    Then volume `test-job-1` should have only 2 snapshots.

    When set setting `allow-recurring-job-while-volume-detached` to `true`.
    And wait for 2 minutes.
    Then attach volume `test-job-2` and wait until healthy.
    And volume `test-job-2` should have only 2 snapshots.

#### Manual test - recurring job skip to create job while volume is detached

Scenario: test recurring job while volume is detached

    Given volume `test-job-1` created, and detached.
          volume `test-job-2` created, and detached.

    When create `snapshot1` recurring job running at 1 minute interval,
    And wait until job pod created and complete

    Then monitor the job pod logs.
    And should see `Cannot create job for test-job-1 volume in state detached`.
        should see `Cannot create job for test-job-2 volume in state detached`.

#### Manual test - recurring job upgrade migration

Scenario: test recurring job upgrade migration

    Given cluster with Longhorn version prior to v1.2.0.
    And storageclass with recurring job `snapshot1`.
    And volume `test-job-1` created, and attached.

    When upgrade Longhorn to v1.2.0.

    Then should have recurring job CR created with format `<jobTask>-<jobRetain>-<hash(jobCron)>-<hash(jobLabelJSON)>`.
    And volume should be labeled with `recurring-job.longhorn.io/<jobTask>-<jobRetain>-<hash(jobCron)>-<hash(jobLabelJSON)>: enabled`.
    And recurringJob should be removed in volume spec.
    And storageClass in `longhorn-storageclass` configMap should not have `recurringJobs`.
        storageClass in `longhorn-storageclass` configMap should     have `recurringJobSelector`.
          ```
          recurringJobSelector: '[{"name":"snapshot-1-97893a05-77074ba4","isGroup":false},{"name":"backup-1-954b3c8c-59467025","isGroup":false}]'
          ```

    When create new PVC.
    And volume should be labeled with items in `recurringJobSelector`.
    And recurringJob should not exist in volume spec.

#### Manual test - snapshot concurrency

Scenario: test recurring job concurrency

    Given create `snapshot1` recurring job with `concurrency` set to `2`.
          include `snapshot1` recurring job `default` in groups.

    When create volume `test-job-1`.
         create volume `test-job-2`.
         create volume `test-job-3`.
         create volume `test-job-4`.
         create volume `test-job-5`.

    Then monitor the cron job pod log.
    And should see 2 jobs created concurrently.

    When update `snapshot1` recurring job with `concurrency` set to `3`.
    Then monitor the cron job pod log.
    And should see 3 jobs created concurrently.

### Upgrade strategy

#### Automated Migration

1. Create `v110to120/upgrade.go`
2. Translate `storageClass` `recurringJobs` to `recurringJobSelector`.
  1. Convert the `recurringJobs` to `recurringJobSelector` object.
     ```
     {
       Name: <jobTask>-<jobRetain>-<hash(jobCron)>-<hash(jobLabelJSON)>
       IsGroup: false,
     }
     ```
  2. Add `recurringJobSelector` to `longhorn-storageclass` configMap.
  3. Remove `recurringJobs` in configMap.
  4. Update configMap.
     ```
      parameters:
        fromBackup: ""
        numberOfReplicas: "3"
        recurringJobSelector: '[{"name":"snapshot-1-97893a05-77074ba4","isGroup":false},{"name":"backup-1-954b3c8c-59467025","isGroup":false}]'
        staleReplicaTimeout: "2880"
      provisioner: driver.longhorn.io
     ```
3. Translate volume spec `recurringJobs` to volume labels.
  1. List all volumes and its spec `recurringJobs` and create labels in format `recurring-job.longhorn.io/<jobTask>-<jobRetain>-<hash(jobCron)>-<hash(jobLabelJSON)>: enabled`.
  2. Update volume labels and remove volume spec `recurringJobs`.
     ```
     labels:
       longhornvolume: pvc-d37caaed-5cda-43b1-ae49-9d0490ffb3db
       recurring-job.longhorn.io/backup-1-954b3c8c-59467025: enabled
       recurring-job.longhorn.io/snapshot-1-97893a05-77074ba4: enabled
     ```

3. translate volume spec `recurringJobs` to recurringJob CRs.
  1. Gather the recurring jobs from `recurringJobSelector` and volume labels.
  2. Create recurringJob CRs.
     ```
     NAME                           GROUPS   TASK       CRON          RETAIN   CONCURRENCY      AGE   LABELS
     snapshot-1-97893a05-77074ba4            snapshot   */1 * * * *   1        10               13m   
     backup-1-954b3c8c-59467025              backup     */2 * * * *   1        10               13m   {"interval":"2m"}
     ```

4. Cleanup applied volume cron jobs.
  1. Get all applied cron jobs for volumes.
  2. Delete cron jobs.

> The migration translates existing volume recurring job with format `recurring-job.longhorn.io/<jobTask>-<jobRetain>-<hash(jobCron)>-<hash(jobLabelJSON)>: enabled`. The name maps to the recurring job CR `<jobTask>-<jobRetain>-<hash(jobCron)>-<hash(jobLabelJSON)>`.

> The migration translates existing volume recurring job with format `recurring-job.longhorn.io/<jobTask>-<jobRetain>-<hash(jobCron)>-<hash(jobLabelJSON)>: enabled`. The numbers could look random and also differs from the recurring job name of the CR name created by the StorageClass - `recurring-job.longhorn.io/<name>: enabled`. This is because there is no info to determine if the volume spec `recurringJob` is coming from a `storageClass` or which `storageClass`. Should note this behavior in the document to lessen the confusion unless there is a better solution.

#### Manual

After the migration, the `<hash(jobCron)>-<hash(jobLabelJSON)>` in volume label and recurring job name could look random and confusing. Users might want to rename it to something more meaningful. Currently, the only way is to create a new recurring job CR and replace the volume label.

## Note [optional]

`None`
