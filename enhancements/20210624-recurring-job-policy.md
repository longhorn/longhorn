# Recurring Job Policy

## Summary

Allow users to create recurring backup/snapshot job policies with new `RecurringJobPolicy` CRD and have a new recurring job type - `Policy` that allows users to reference the policy in volume. 

Users can also update the recurring job policy, and Longhorn will automatically update the cronjob associated with volume and the policy.

When instruct Longhorn to delete a recurring job policy, this will also remove the cronjob associated with volume and the policy.

### Related Issues

https://github.com/longhorn/longhorn/issues/467

## Motivation

### Goals

- Ability to create multiple recurring backup/snapshot job policies with UI or YAML.
- Ability to apply volume recurring job type - `Policy` for policy reference.
- Ability to automatically apply default recurring backup/snapshot policy on all volumes without a recurring job.
- Recurring job policy should include recurring job settings; `name`, `task`, `cron`, `retain`.

### Non-goals [optional]

When volumes are all using the same recurring backup/snapshot policy, means all volumes will perform backups at the same time. As the original issue suggested, `Ideally, a range should be provided.`. This is currently an existing issue and should also be a problem when the recurring jobs are set at the storage class level.

> This will not be looked at here, reference to https://github.com/longhorn/longhorn/pull/2737#discussion_r660040985

## Proposal

#### Story 1 - refer volume to recurring job policy
As a Longhorn user / System administrator.

I want the ability to create a backup/snapshot recurring job as policy and select as type `Policy` during creating `Recurring Snapshot and Backup Schedule` or using YAML.

So I do not need to repeat the same recurring job setup for every volume.

#### Story 2 - default recurring job policy reference
As a Longhorn user / System administrator.

I want the ability to set backup/snapshot policy as default. Any volumes with no recurring job should automatically apply with the default backup/snapshot policy.

So I do not need to manually check and create recurring jobs in all volumes.
And I can be assured that all volumes will have backup/snapshot recurring jobs even if I removed the customed set in the volume spec.


### User Experience In Detail

#### Story 1 - refer volume to recurring job policy

1. Create a recurring job policy in UI or `kubectl`.
2. In UI, Navigate to Volume, `Recurring Snapshot and Backup Schedule`
3. Select `Policy` from the `Type` list.
4. Select existing recurring job policy from the `Name` list.
5. Click `Save` should see `Schedule`, `Retain` referred from the `recurring job policy` CRs.

**Before enhancement**
Manually create recurring jobs for each volume.

**After enhancement**
Create a recurring job with type `Policy` automatically reference to the recurring job policy.

#### Story 2 - default recurring job policy reference

1. Create single or multiple recurring job policies with `default` set to `true` in UI or `kubectl`.
2. Default recurring job policies will automatically be applied to any volume with no recurring job setup.

> ~~Question: Should the default recurring job policy overrule the storageClass recurring backup jobs? Or should they co-exist?~~


### API changes

- Add new HTTP endpoints:
  - GET `/v1/recurringjobpolicies` to list of recurring job policies.
  - GET `/v1/recurringjobpolicies/{name}` to get specific recurring job policy.
  - DELETE `/v1/recurringjobpolicies/{name}` to delete specific recurring job policy.
  - POST `/v1/recurringjobpolicies` to create a recurring job policy.
  - PUT `/v1/recurringjobpolicies/{name}` to update specific recurring job policy.
  - `/v1/ws/recurringjobpolicies` and `/v1/ws/{period}/recurringjobpolicies` for websocket stream.
- Add new RESTful APIs for the new `RecurringJobPolicy` CRD:
  - `Create`
  - `Update`
  - `List`
  - `Get`
  - `Delete`

## Design

### Implementation Overview

- Add recurring job policy CRD.
  - Update the ClusterRole to include `recurringjobpolices`.
  - The `Name` will be referenced to the volume snapshot/backup.
  - The `Task` should be one of `backup`, `snapshot` and can be validated in the CRD YAML pattern regex match.
  - Printer column should include `Name`, `Task`, `Default`, `Recurring`, `Retain`, `Age`.

- In the longhorn-manager binary,
  1. Add new command `snapshot-policy <policy-name> <volume-names>` with flags `--label`, `--retain`, `--backup`.

     The `<volume-names>` should be a string separated by commas.
  2. Run goroutine to create `NewJob()` and `job.run()` for all volumes in the given argument.
     The job `snapshotName` format will be `p-<policy-name>-c-<RandomID>`.

- In the volume controller,
  1. Skip `DeleteCronJob` if the applied cron job with label `longhorn.io/job-task` is set to `policy`.

- Add recurring job policy controller.
  - The code structure will be the same as other controllers.
  - The controller will be informed by `recurringJobPolicyInformer`, `volumeInformer`.
  - Add the finalizer to the recurring job policy CRs.
  - Create and update CronJob per policy.
    1. Get a list of volumes with no recurring jobs.
    2. Generate a new cronjob object from the volume spec.
       - Include labels `longhorn.io/job-policy`, `longhorn.io/job-task`.
         ```
         longhorn.io/job-policy: test1
         longhorn.io/job-task: policy
         ```
       - Compose command,
         ```
         longhorn-manager -d\
           snapshot-policy <policy-name> <volume-names>\
           --manager-url <url>\
           --labeles <recurring-job-label>=<policy-name>\
           --retain <policy.spec.retain>\
           <--backup>
         ```
    2. set annotation `last-applied-cronjob-spec` and create cronjob if not already applied in cronjob.
    3. update annotation `last-applied-cronjob-spec` and update cronjob if the new cronjob is different than the last applied spec.
  - Clean up cronjobs when a recurring job policy gets deleted.
    1. Delete the cronjob with selected labels: `longhorn.io/job-task`, `longhorn.io/job-policy`.
    2. Remove the finalizer when the policy-associated cronjobs is deleted.

### Test plan

> WIP

#### Integration test - test_recurring_job_policy_default

Scenario: test default recurring job policy

    Given 1 volume created.

    When create `snapshot1` recurring job and set to default.
         create `snapshot2` recurring job
         create `snpashot3` recurring job and set to default.
         create `backup1` recurring job and set to default.
         create `backup2` recurring job
         create `backup3` recurring job and set to default.
    Then default `snapshot1` cron job should exist.
         `snapshot2` cron job should not exist.
         default `snapshot3` cron job should exist.
         default `backup1` cron job should exist.
         `backup2` cron job should not exist.
         default `backup3` cron job should exist.

    # Setting snapshot and backup policy in volume spec should
    # remove the defaults.
    When set `snapshot2` policy in volume spec.
         set `backup2` policy in volume spec.
    Then default `snapshot1` cron job should not exist.
         `snapshot2` cron job should exist.
         default `snapshot3` cron job should not exist.
         default `backup1` cron job should not exist.
         `backup2` cron job should exist.
         default `backup3` cron job should not exist.

    # Should be able to set default snapshot and backup policy
    # in volume spec.
    When add default `snapshot3` policy to volume spec.
         add default `backup3` policy in volume spec.
    Then default `snapshot1` cron job should not exist.
         `snapshot2` cron job should exist.
         default `snapshot3` cron job should exist.
         default `backup1` cron job should not exist.
         `backup2` cron job should exist.
         default `backup3` cron job should exist.

    # Remove volume backup policy should bring in default backup
    # policy
    When set only `snapshot2` in volume spec.
         delete all backup policy in volume spec.
    Then default `snapshot1` cron job should not exist.
         `snapshot2` cron job should exist.
         default `snapshot3` cron job should not exist.
         default `backup1` cron job should exist.
         `backup2` cron job should not exist.
         default `backup3` cron job should exist.

    # Remove volume snapshot policy should bring in default snapshot
    # policy
    When delete all snapshot policy in volume spec.
    Then default `snapshot1` cron job should exist.
         `snapshot2` cron job should not exist.
         default `snapshot3` cron job should exist.
         default `backup1` cron job should exist.
         `backup2` cron job should not exist.
         default `backup3` cron job should exist.

    # Update snapshot and backup recurring job policy to default
    # should also reflect on the cronjobs
    When update `snapshot2` policy to default.
         update `backup2` policy to default.
    Then default `snapshot1` cron job should exist.
         default `snapshot2` cron job should exist.
         default `snapshot3` cron job should exist.
         default `backup1` cron job should exist.
         default `backup2` cron job should exist.
         default `backup3` cron job should exist.

    # Update recurring job policy default to false should also
    # reflect on the cronjobs
    When set `snapshot3` policy default to false.
    Then default `snapshot1` cron job should exist.
         default `snapshot2` cron job should exist.
         `snapshot3` cron job should not exist.
         default `backup1` cron job should exist.
         default `backup2` cron job should exist.
         default `backup3` cron job should exist.


#### Integration test - test_recurring_job_policy_delete

> TBU

#### Integration test - test_recurring_job_policy_volume_reference

> TBU

#### Integration test - test_recurring_job_policy_multiple_volumes

> TBU

### Upgrade strategy
There is no upgrade needed.

## Note [optional]
`None`
