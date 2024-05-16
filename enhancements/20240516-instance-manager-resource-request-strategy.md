# Instance Manager Resource Request Strategy

## Disclaimer

This is a VERY early draft meant to facilitate discussion about how a new feature might work.

## Summary

### Potential Strategies

- Best effort
  - No guaranteed instance-manager CPU resources.
  - Instance-manager may become CPU starved and volumes may crash.
  - Possible today by setting `guaranteed-instance-manager-cpu = 0`.
- Manual
  - The user takes manual control of the `guaranteed-instance-manager-cpu` setting and/or `InstanceManagerCPURequest`
    node field.
  - The user must guess the right value based on data provided in Longhorn documentation.
  - Semi-effective without `InPlaceVerticalPodScaling`. Instance-managers can get the new value when they happen to
    restart.
  - More effective with `InPlaceVerticalPodScaling`. Instance-manager can get the new value immediately.
  - Possible today by setting `guaranteed-instance-manager-cpu = <some_value>` and/or
    `InstanceManagerCPURequest = <some_value>`. Longhorn documentation may need additional/enhanced formulas.
- Automatic, formula-based, volume-level granularity
  - Longhorn-manager sets instance-manager CPU requests to the same value on ALL instance-managers automatically based
    on the number of volumes in the cluster (and some formula).
  - Semi-effective without `InPlaceVerticalPodScaling`. Instance-managers can get the new value when they happen to
    restart.
  - More effective with `InPlaceVerticalPodScaling`. Instance-manager can get the new value immediately.
- Automatic, formula-based, instance-manager-level granularity
  - Longhorn-manager sets each instance-manager's CPU requests to a particular value based on the number of engines and
    replicas it is currently running (and some formula).
  - Only effective with `InPlaceVerticalPodScaling` since it reacts to the number of proccesses in a RUNNING
    instance-manager.
- Automatic, fully dynamic
  - Longhorn relies on the [vertical pod
    autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) to set instance-manager
    CPU requests based on current usage.
  - Lower and upper bounds for instance-manager CPU requests are still configurable in Longhorn settings.

### Related Issues

https://github.com/longhorn/longhorn/issues/6351

## Motivation

### Goals

### Non-goals [optional]

## Proposal

### User Stories

#### Story 1

#### Story 2

### User Experience In Detail

### API changes

## Design

### Implementation Overview

### Test plan

### Upgrade strategy

## Note [optional]
