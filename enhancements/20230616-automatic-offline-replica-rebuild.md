# Automatic Offline Replica Rebuilding

## Summary

Currently, Longhorn does not have the capability to support online replica rebuilding for volumes utilizing the V2 Data Engine. However, an automatic offline replica rebuilding mechanism has been implemented as a solution to address this limitation.

### Related Issues

https://github.com/longhorn/longhorn/issues/6071

## Motivation

### Goals

1. Support volumes using v2 data engine

### Non-goals

2. Support volumes using v1 data engine

## Proposal

## User Stories


In the event of abnormal power outages or network partitions, replicas of a volume may be lost, resulting in volume degradation. Unfortunately, volumes utilizing the v2 data engine do not currently have the capability for online replica rebuilding. As a solution to address this limitation, Longhorn has implemented an automatic offline replica rebuilding mechanism.

When a degraded volume is detached, this mechanism places the volume in maintenance mode and initiates the rebuilding process. After the rebuilding is successfully completed, the volume is detached according to the user's specified expectations.

### User Experience In Details

- If a volume using the v2 data engine is degraded, the online replica rebuilding process is currently unsupported.

- If offline replica rebuilding feature is enabled when one of the conditions is met
    - Global setting `offline-replica-rebuild` is `enabled` and `Volume.Spec.OfflineReplicaRebuilding` is  `ignored`
    - `Volume.Spec.OfflineReplicaRebuilding` is `enabled`
    The volume's `Spec.OfflineReplicaRebuildingRequired` is set to `true` if a volume is degraded.

- When a degraded volume is detached, this mechanism places the volume in maintenance mode and initiates the rebuilding process. After the rebuilding is successfully completed, the volume is detached according to the user's specified expectations.

- If a user attaches the volume without enabling maintenance mode while the replica rebuilding process is in progress, the ongoing replica rebuilding operation will be terminated. 

## Design

### Implementation Overview

**Settings**

- Add global setting `offline-replica-rebuilding`. Default value is `enabled`. The available options are:
  - `enabled`
  - `disable`

**CRD**

- Add `Volume.Spec.OfflineReplicaRebuilding`. The available options are:
  - ignored`: The volume's offline replica rebuilding behavior follows the settings defined by the global setting `offline-replica-rebuilding`.
  - `enabled`: Offline replica rebuilding of the volume is always enabled.
  - `disabled`: Offline replica rebuilding of the volume is always disabled.

- Add `Volume.Status.OfflineReplicaRebuildingRequired`

**Controller**

- Add `volume-rebuilding-controller` for creating and deleting `volume-rebuilding-controller` attachment ticket.

**Logics**

1. A volume-controller sets 'Volume.Status.OfflineReplicaRequired' to 'true' when it realizes a v2 data engine is degraded.

2. If a volume's `Volume.Status.OfflineReplicaRebuildingRequired` is `true`, volume-rebuilding-controller creates a `volume-rebuilding-controller` attachment ticket with frontend disabled and lower priority than tickets with workloads.

3. When the volume is detached, volume-attachment-controller attaches the volume with a `volume-rebuilding-controller` attachment ticket in maintenance mode.

4. volume-controller triggers replica rebuilding.

5. After finishing the replica rebuilding, the volume-controller sets `Volume.Status.OfflineReplicaRebuildingRequired` to `false` if a number of healthy replicas is expected.

6. volume-rebuilding-controller deletes the 'volume-rebuilding-controller' attachment ticket.

7. volume-attachment-controller is aware of the deletion of the `volume-rebuilding-controller` attachment ticket, which causes volume detachment.

### Test Plan

### Integration Tests

1. Degraded Volume lifecycle (creation, attachment, detachment and deletion) and automatic replica rebuilding