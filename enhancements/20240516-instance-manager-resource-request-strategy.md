# Instance Manager Resource Request Strategy

## Disclaimer

This is a VERY early draft meant to facilitate discussion about how a new feature might work.

## Summary

### Background

#### Why do instance-manager pods need CPU requests?

In Kubernetes, a CPU request guarantees a pod receives at least as much CPU time as requested. If a node can not
make this guarantee, the pod is not scheduled to the node.

TODO: Verify that the last statement is true for instance-manager pods, since they bypass the scheduler.

A Longhorn volume crashes if an I/O takes longer than eight seconds to complete, and each I/O takes CPU to service. If
there is not enough CPU for all engines to keep up with the eight second response window, volumes will crash. Since
volume crashes carry the potential for data corruption, it is important to ensure there is always enough available CPU
to avoid them. In addition, I/O performance improves greatly when there is more CPU to handle I/O requests. Increasing
the CPU request of the instance-manager ensures more CPU, and thus better I/O performance.

### Potential Strategies

- Best effort
  - No guaranteed instance-manager CPU resources.
  - Instance-manager may become CPU starved and volumes may crash.
  - Possible today by setting `guaranteed-instance-manager-cpu = 0`.
- Manual
  - The user takes manual control of the `guaranteed-instance-manager-cpu` setting and/or `InstanceManagerCPURequest`
    node field.
  - The user must guess the right value based on data provided in Longhorn documentation. Factors to consider include:
    - The number of expected engines/replicas running on the average node or on each individual node.
    - The expected I/O characteristics of each volume.
  - The user must reconsider and update the setting/field when their usage changes.
  - Semi-effective without `InPlaceVerticalPodScaling`. Instance-managers can get the new value when they happen to
    restart.
  - More effective with `InPlaceVerticalPodScaling`. Instance-manager can get the new value immediately.
  - Possible today by setting `guaranteed-instance-manager-cpu = <some_value>` and/or
    `InstanceManagerCPURequest = <some_value>`. Longhorn documentation may need additional/enhanced formulas.
- Automatic, formula-based, depends on the number of volumes in the cluster
  - Longhorn-manager sets instance-manager CPU requests to the same value on ALL instance-managers automatically based
    on the number of volumes in the cluster (and some formula calculated as above).
  - An additional parameter/setting can help control the amount of CPU requested per volume. E.g. 1% per volume, or 100
    mCPU per volume, or low/medium/high performance.
  - Semi-effective without `InPlaceVerticalPodScaling`. Instance-managers can get the new value when they happen to
    restart.
  - More effective with `InPlaceVerticalPodScaling`. Instance-manager can get the new value immediately.
- Automatic, formula-based, depends on the number of processes in an instance-manager
  - Longhorn-manager sets each instance-manager's CPU requests to a particular value based on the number of engines and
    replicas it is currently running (and some formula calculated as above).
  - An additional parameter/setting can help control the amount of CPU requested per volume. E.g. 1% per process, or 100
    mCPU per process, or low/medium/high performance.
  - Only effective with `InPlaceVerticalPodScaling` since it reacts to the number of processes in a RUNNING
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
