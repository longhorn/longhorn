# Recurring Filesystem Trim
## Summary

Longhorn currently supports the [filesystem trim](./20221103-filesystem-trim.md) feature, which allows users to reclaim volume disk spaces of deleted files. However, this is a manual process, which can be time-consuming and inconvenient.

To improve user experience, Longhorn could automate the process by implementing a new RecurringJob `filesystem-trim` type. This enhancement enables regularly freeing up unused volume spaces and reducing the need for manual interventions.

### Related Issues

https://github.com/longhorn/longhorn/issues/5186

## Motivation

### Goals

Introduce a new recurring job type called `filesystem-trim` to periodically trim the volume filesystem to reclaim disk spaces.

### Non-goals [optional]

`None`

## Proposal

To extend the RecurringJob custom resource definition by adding new `RecurringJobType: filesystem-trim`.

### User Stories

To schedule regular volume filesystem trims, user can create a RecurringJob with `spec.task=filesystem-trim` and associating it with volumes.

### User Experience In Detail

#### Recurring Filesystem Trim
1. The user sees workload volume size has increased over time.
1. Create RecurringJob with the `filesystem-trim` task type and assign it to the volume.
   ```yaml
   apiVersion: longhorn.io/v1beta2
   kind: RecurringJob
   metadata:
     name: recurring-fs-trim-per-min
     namespace: longhorn-system
   spec:
     concurrency: 1
     cron: '* * * * *'
     groups: []
     labels: {}
     name: recurring-fs-trim-per-min
     retain: 0
     task: filesystem-trim
   ```
1. The RecurringJob runs and relaims some volume spaces.

### API changes

`None`

## Design

### Implementation Overview

#### The RecurringJob `filesystem-trim` Task Type

1. Call Volume API `ActionTrimFilesystem` when the RecurringJob type is `filesystem-trim`.

### RecurringJob Mutate

1. Mutate the `Recurringjob.Spec.Retain` to 0 when the task type is `filesystem-trim` as it is not effective for this type of task.

### Test plan

#### Test Recurring Filesystem Trim
1. Create workload.
1. Create a file with some data in the workload.
1. Volume actual size should increase.
1. Delete the file.
1. Volume actual size should not decrease.
1. Create RecurringJob with type `filesystem-trim` and assign to the workload volume.
1. Wait for RecurringJob to complete.
1. Volume actual size should decrease.

### Upgrade strategy

`None`

## Note [optional]

`None`
