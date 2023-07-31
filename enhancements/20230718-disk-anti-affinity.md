# Disk Anti-Affinity

## Summary

Longhorn supports multiple disks per node, but there is currently no way to ensure that two replicas for the same
volume that schedule to the same node end up on different disks. In fact, the replica scheduler currently doesn't make
any attempt achieve this goal, even when it is possible to do so.

With the addition of a Disk Anti-Affinity feature, the Longhorn replica scheduler will attempt to schedule two replicas
for the same volume to different disks when possible. Optionally, the scheduler will refuse to schedule a replica to a
disk that has another replica for the same volume.

Although the comparison is not perfect, this enhancement can be thought of as enabling RAID 1 for Longhorn (mirroring
across multiple disks on the same node).

See the [Motivation section](#motivation) for potential benefits.

### Related Issues

- https://github.com/longhorn/longhorn/issues/3823
- https://github.com/longhorn/longhorn/issues/5149

### Existing Related Features

#### Replica Node Level Soft Anti-Affinity

Disabled by default. When disabled, prevents the scheduling of a replica to a node with an existing healthy replica of
the same volume.

Can also be set at the volume level to override the global default.

#### Replica Zone Level Soft Anti-Affinity

Enabled by default. When disabled, prevents the scheduling of a replica to a zone with an existing healthy replica of
the same volume.

Can also be set at the volume level to override the global default.

## Motivation

- Large, multi-node clusters will likely not benefit from this enhancement.
- Single-node clusters and small, multi-node clusters (on which the number of replicas per volume exceeds the number
  of available nodes) will experience:
  - Increased data durability. If a single disk fails, a healthy replica will still exist on an disk that
    has not failed.
  - Increased data availability. If a single disk on a node becomes unavailable, but the node itself remains
    healthy, at least one replica remains healthy. On a single-node cluster, this can directly prevent a volume crash.
    On a small, multi-node cluster, this can prevent a future volume crash due to the loss of a different node.

### Goals

- In all situations, the Longhorn replica scheduler will make a best effort to ensure two replicas for the same volume
  do not schedule to the same disk.
- Optionally, the scheduler will refuse to schedule a replica to a disk that has another replica of the same volume.

## Proposal

### User Stories

#### Story 1

My cluster consists of a single node with multiple attached SSDs. When I create any new volume, I want replicas to
distribute across these disks so that I can recover from n - 1 disk failures. If there are not as many available disks
as desired replicas, I want Longhorn to do the best it can.

#### Story 2

My cluster consists of a single node with multiple attached SSDs. When I create any new volume, I want replicas to
distribute across these disks so that I can recover from n - 1 disk failure. If there are not as many available disks
as desired replicas, I want scheduling to fail obviously. It is important that I know my volumes aren't being protected
so I can take action.

#### Story 3

My cluster consists of a single node with multiple attached SSDs. When I create a specific, high-priority volume, I want
replicas to distribute across these disks so that I can recover from n - 1 disk failure. If there are not as many
available disks as desired replicas, I want scheduling to fail obviously. It is important that I know high-priority
volume isn't being protected so I can take action.

### User Experience In Detail

### API changes

Introduce a new Replica Disk Level Soft Anti-Affinity setting with the following definition. By default, set it to
`true`. While it is generally desirable to schedule replicas to different disks, it would break with existing behavior
to refuse to schedule replicas when different disks are not available.

```golang
SettingDefinitionReplicaDiskSoftAntiAffinity = SettingDefinition{
    DisplayName: "Replica Disk Level Soft Anti-Affinity",
    Description: "Allow scheduling on disks with existing healthy replicas of the same volume",
    Category:    SettingCategoryScheduling,
    Type:        SettingTypeBool,
    Required:    true,
    ReadOnly:    false,
    Default:     "true",
}
```

Introduce a new `spec.replicaDiskSoftAntiAffinity` volume field. By default, set it to `ignored`. Similar to the
existing `spec.replicaSoftAntiAffinity` and `spec.replicaSoftZoneAntiAffinityFields`, override the global setting if
this field is set to `enabled` or `disabled`.

```yaml
replicaDiskSoftAntiAffinity:
  description: Replica disk soft anti affinity of the volume. Set enabled
    to allow replicas to be scheduled in the same disk.
  enum:
  - ignored
  - enabled
  - disabled
  type: string
```

## Design

### Implementation Overview

The current replica scheduler does the following:

1. Determines which nodes a replica can be scheduled to based on node condition and the `ReplicaSoftAntiAffinity` and
   `ReplicaZoneSoftAntiAffinity` settings.
1. Creates a list of all schedulable disks on these nodes.
1. Chooses the disk with the most available space for scheduling.

Add a step so that the replica scheduler:

1. Determines which nodes a replica can be scheduled to based on node condition and the `ReplicaSoftAntiAffinity` and
   `ReplicaZoneSoftAntiAffinity` settings.
1. Creates a list of all schedulable disks on these nodes.
1. Filters the list to include only disks with the least number of existing matching replicas and optionally only disks
   with no existing matching replicas.
1. Chooses the disk from the filtered list with the most available space for scheduling.

### Test plan

Minimally implement two new test cases:

1. In a cluster that includes nodes with multiple available disks, create a volume with
   `spec.replicaSoftAntiAffinity = true`, `spec.replicaDiskSoftAntiAffinity = true`, and `numberOfReplicas` equal to the
   total number of disks in the cluster. Confirm that each replica schedules to a different disk. It may be necessary
   to tweak additional factors. For example, ensure that one disk has enough free space that the old scheduling
   behavior would assign two replicas to it instead of distributing the replicas evenly among the disks.
1. In a cluster that includes nodes with multiple available disks, create a volume with
   `spec.replicaSoftAntiAffinity = true`, `spec.replicaDiskSoftAntiAffinity = false`, and `numberOfReplicas` equal to
   one more than the total number of disks in the cluster. Confirm that a replica fails to schedule. Previously,
   multiple replicas would have scheduled to the same disk and no error would have occurred.

### Upgrade strategy

The Replica Disk Level Soft Anti-Affinity setting defaults to `true` to maintain backwards compatibility. It if is set
to `false``, new replicas that require scheduling will follow the new behavior.

The `spec.replicaDiskSoftAntiAffinity` volume field defaults to `ignored` to maintain backwards compatibility. If it is
set to `enabled` on a volume, new replicas for that volume that require scheduling will follow the new behavior.
