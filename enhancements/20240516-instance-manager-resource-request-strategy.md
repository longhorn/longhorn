# Instance Manager Resource Request Strategy

## Disclaimer

This is a VERY early draft meant to facilitate discussion about how a new feature might work.

## Current Questions

- Is there value in tackling this feature before `InPlacePodVerticalScaling`? Maybe we should collect the data and
  improve documentation for now in preparation.
- What is the best way to express/capture the different fields required by the different strategies? Should we have a
  CRD, use multiple settings, use a setting with a complex value, etc.? For example, we could try the below:
  
  ```
  kind: ResourceRequest
  spec:
    strategy: BestEffort
  ```

  ```
  kind: ResourceRequest
  spec:
    strategy: Manual
    cpu:
      percentPerNode: 12 // Mutually exclusive with below.
      sharePerNode: 500m // Mutually exclusive with above.
      sharePerEngine:    // Invalid
      sharePerReplica:   // Invalid
  ```

  ```
  kind: ResourceRequest
  spec:
    strategy: AutomaticPerProcessesInCluster
    cpu:
      percentPerNode // Invalid 
      sharePerNode:  // Invalid
      sharePerEngine:  100m
      sharePerReplica: 100m
  ```

  ```
  kind: ResourceRequest
  spec:
    strategy: AutomaticPerProcessesOnNode
    cpu:
      percentPerNode // Invalid 
      sharePerNode:  // Invalid
      sharePerEngine:  100m
      sharePerReplica: 100m
  ```

## Summary

This feature is designed to help users set the CPU/memory limits/requests of instance-manager pods in order to:

- Ensure volumes running within instance-manager pods don't crash due to resource starvation.
- Ensure volumes running within instance-manager pods have enough resources to meet I/O performance targets.
- Ensure instance-manager pods don't reserve more resources than are required.

### Related Issues

https://github.com/longhorn/longhorn/issues/6351

## Motivation

Today, Longhorn has the `guaranteed-instance-manager-cpu` setting and `InstanceManagerCPURequest` node field, which
combine to determine the CPU request field of instance-manager pods. The documentation provides [some
guidance](https://longhorn.io/docs/1.6.1/references/settings/#guaranteed-instance-manager-cpu) on how to set these
fields to ensure volumes don't crash. However:

- The documentation does not help users set these fields to ensure engines and replicas have enough CPU to hit I/O
  performance targets.
- The provided guidance is based on the maximum number of expected engine and replica processes on a node. This can
  lead to unnecessary allocations early in the life of a cluster (when there are few volumes).
- These fields are difficult to change, as this requires all processes running within an instance manager to stop.

### Why do instance-manager pods need CPU requests?

In Kubernetes, a CPU request guarantees a pod receives at least as much CPU time as requested. If a node can not
make this guarantee, the pod is not scheduled to the node. If the pod bypasses the scheduler (as is the case for
instance-manager pods), it does not start.

A Longhorn volume crashes if an I/O takes longer than eight seconds to complete, and each I/O takes CPU to service. If
there is not enough CPU for all engines to keep up with the eight second response window, volumes will crash. Since
volume crashes carry the potential for data corruption, it is important to ensure there is always enough available CPU
to avoid them. In addition, I/O performance improves greatly when there is more CPU to handle I/O requests. Increasing
the CPU request of the instance-manager ensures more CPU, and thus better I/O performance.

### Goals

### Non-goals [optional]

## Proposal

### Strategies

We have identified five potential strategies for managing instance-manager resources. These are general approaches that
do not necessarily correspond to the value of a specific setting.

- BestEffort
  - No guaranteed instance-manager CPU resources.
  - No guaranteed instance-manager memory resources.
  - Instance-manager may become CPU starved and volumes may crash.
  - Instance-manager may be OOM-killed.
  - Similar to the behavior today when setting `guaranteed-instance-manager-cpu = 0`.
- Manual
  - Instance-manager CPU request equals `instance-manager-cpu-request` setting or `InstanceManagerCPURequest` node
    field.
  - Instance-manager memory request equals `instance-manager-memory-request` setting or `InstanceManagerMemoryRequest`
    node field.
  - The user sets the above manually.
  - The user must guess the right value based on data provided in Longhorn documentation. Factors to consider include:
    - The number of expected engines/replicas running on the average node or on each individual node.
    - The expected I/O characteristics of each volume.
  - The user must reconsider and update the setting/field when their usage changes.
  - Semi-effective without `InPlaceVerticalPodScaling`. Instance-managers can get the new value when they happen to
    restart.
  - More effective with `InPlaceVerticalPodScaling`. Instance-manager can get the new value immediately.
  - Similar to the behavior today when setting `guaranteed-instance-manager-cpu = <some_value>` and/or
    `InstanceManagerCPURequest = <some_value>`.
- AutomaticPerProcessesInCluster
  - Longhorn-manager sets instance-manager CPU and memory requests to the same value on ALL instance-managers
    automatically based on the number of processes (engine and replica) in the cluster (and some formula calculated as above).
  - ~~The `instance-manager-cpu-request` setting and `InstanceManagerCPURequest` node field are interpreted as CPU per
    process (potentially with engine/replica weighting).~~ (We cannot reinterpret these fields. When the strategy
    setting changes, this would cause temporary chaos.)
  - ~~The `instance-manager-memory-request` setting and `InstanceManagerMemoryRequest` node field are interpreted as
    memory per process (potentially with engine/replica weighting).~~ (We cannot reinterpret these fields. When the
    strategy setting changes, this would cause temporary chaos.)
  - Semi-effective without `InPlaceVerticalPodScaling`. Instance-managers can get the new value when they happen to
    restart.
  - More effective with `InPlaceVerticalPodScaling`. Instance-manager can get the new value immediately.
  - __Is this valueable? It is based off the assumption that volumes are evenly distributed.__
- AutomaticPerProcessesOnNode
  - Longhorn-manager sets each instance-manager's CPU and memory requests to particular values based on the number of
    processes (engine and replica) it is currently running (and some formula calculated as above).
  - ~~The `instance-manager-cpu-request` setting and `InstanceManagerCPURequest` node field are interpreted as CPU per
    process (potentially with engine/replica weighting).~~ (We cannot reinterpret these fields. When the strategy
    setting changes, this would cause temporary chaos.)
  - ~~The `instance-manager-memory-request` setting and `InstanceManagerMemoryRequest` node field are interpreted as
    memory per process (potentially with engine/replica weighting).~~ (We cannot reinterpret these fields. When the
    strategy setting changes, this would cause temporary chaos.)
  - Only effective with `InPlaceVerticalPodScaling` since it reacts to the number of processes in a RUNNING
    instance-manager.
- Dynamic
  - Longhorn relies on the [vertical pod
    autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) to set instance-manager
    CPU requests based on current usage.
  - Lower and upper bounds for instance-manager CPU and memory requests are still configurable with a
    VerticalPodAutoscalar CR.

### Phases

This feature is best implemented in the following phases:

- Phase 1
  - Targeted for v1.7.0.
  - Instrument Longhorn to gather CPU and memory utilization statistics per process.
- Phase 2
  - Targeted for v1.7.0.
  - Use this instrumentation and an adapted version of the [scalability
    test](https://github.com/longhorn/longhorn/pull/7905) to determine the minimum amount of CPU and memory an engine or
    replica process needs to keep from crashing, and the amount of CPU it needs per I/O performance characteristic.
  - For example, an engine may need `100 mCPU` to keep from crashing and approximately `1 CPU` for `10,000 IOPs`. So it
    can be estimated to need `400 mCPU` for `4,000 IOPs`.
  - Determine whether we can use a constant scaling factor for engines and replicas (e.g. an engine needs the same
    resources as all of its replicas combined) or we need to consider them separately. __This affects how many settings
    and fields we need.__
- Phase 3
  - Targeted for v1.7.0.
  - Deprecate the existing `guaranteed-instance-manager-cpu` setting, which is expressed as a percent.
  - Introduce the `instance-manager-cpu-request` and `instance-manager-memory-request` settings.
  - Introduce the `instance-manager-memory-request` node field.
  - Introduce the `instance-manager-resource-request-strategy` setting, which defaults to `Manual`.
  - To maintain backwards compatibility... __How do we maintain backwards compatibility with the percentage based
    approach?__
- Phase 4
  - Targeted for the release after `InPlaceVerticalPodScaling` goes Beta.
  - Test the behavior of `AutomaticPerProcessesInCluster` with `InPlaceVerticalPodScaling`.
  - Add the logic to support `AutomaticPerProcessesOnNode`.
- Phase 5
  - Targeted for the release after Phase 4.
  - Add the logic to support `Dynamic`.

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
