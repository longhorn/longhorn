# Local Data Engine

## Summary

Longhorn supports `strict-local` data locality, which is designed for latency-sensitive applications. In
practice, however, it remains significantly slower than local-disk storage because I/O must still traverse a
data path designed for distributed block storage. This enhancement proposes a local-only Longhorn data engine
backed by LVM logical volumes. It removes the Longhorn engine and replica processes from the data path. Each
volume is exposed directly as a local kernel block device, allowing I/O to pass through the kernel LVM stack
to the physical disk. This delivers near-local-disk performance while retaining the same properties as
existing `strict-local` volumes.

### Related Issues

- https://github.com/longhorn/longhorn/issues/13481

Measured results for the design described here are in the companion report,
[Local Data Engine Performance Benchmark](./assets/local-data-engine/performance-benchmark.md).

## Motivation

### Goals

- Deliver performance close to that of a local disk.
- Remove all Longhorn userspace processes and network transports from the I/O path.
- Integrate the LVM-based local data engine into Longhorn so that one storage system can provide both
  high-performance replicated volumes and high-performance local volumes.
  - Support v1/v2 features that do not depend on synchronous replication:
    - Over-provisioning.
    - Snapshots, backups, and restores.
    - Encryption.

### Non-goals

- Synchronous replication, automatic replica rebuild, or transparent failover after node or disk loss.
- Asynchronous replication or automatic failover after node or disk loss.
  - Asynchronous replication may be considered in the future, but it cannot prevent partial data loss.
- Read-write-many volumes or simultaneous attachment from multiple nodes.

### Advantages over v1/v2 `strict-local` volumes

- Significantly better performance than v1/v2 `strict-local` volumes.
- No Longhorn userspace components in the data path.
  - There is no engine process comparable to v1/v2, so engine live upgrades are unnecessary.
  - This is especially valuable for v2, where live upgrades of `strict-local` volumes would be complicated,
    if not impossible.
  - The instance manager operates only in the control plane, handling volume and disk lifecycle operations.

### Advantages over using standalone LVM storage providers

- Automatic physical volume and volume group management. Unlike TopoLVM and OpenEBS LocalPV-LVM, which
  require administrators to create and manage volume groups in advance, Longhorn will manage:
  - Physical volume initialization.
  - Volume group creation and expansion.
- Integrated backup and restore.
  - TopoLVM and OpenEBS LocalPV-LVM do not offer backup and restore natively and rely on third-party tools
    such as Velero.
- Out-of-the-box encryption.
  - TopoLVM and OpenEBS LocalPV-LVM require administrator-created dm-crypt devices.
- A single storage system and operational model.
  - Users do not need to deploy and manage Longhorn alongside a separate local-storage provider.

## User Stories

### Story 1 — One storage system instead of two

An operator uses Longhorn for workloads that require replicated storage. The same cluster also runs
latency-sensitive applications that provide their own replication and need local-only volumes, but existing
`strict-local` volumes do not meet their performance requirements.

By enabling the local data engine and selecting it through a StorageClass, the operator can manage replicated
and local-only volumes through the same Longhorn installation, CRDs, CSI driver, UI, monitoring, backup
targets, and operational knowledge. There is no need to deploy and maintain a second CSI storage system.

### Story 2 — Instance-manager upgrades without I/O interruption

An operator needs to roll out a new instance-manager image while local-storage workloads continue to serve
traffic.

Because an attached local volume is a kernel device-mapper device, its I/O does not depend on the instance
manager process. Restarting or replacing the instance-manager pod temporarily pauses new control-plane
operations, while reads and writes to existing mounts continue uninterrupted.

### User Experience In Detail

The administrator enables the local data engine and adds an LVM-type disk to a Longhorn Node resource. The
instance manager contains the required `lvm2` tools, so the host does not need to provide them. When the disk
is registered, the instance manager verifies that it has no existing filesystem or partition table,
initializes it as a physical volume, and creates its volume group.

The host prerequisites are the ones Longhorn already requires. The instance-manager pod is privileged and
mounts the host root filesystem for every data engine, so it already reaches the host's block devices and
`/dev/mapper/control`, and the existing environment check already probes for the `device-mapper` host package
and the `dm_crypt` module. Thin mode is the only case that adds a requirement: it needs the `dm_thin_pool`
module, which the environment check does not cover today, so it is added to the checked modules when the
local data engine is enabled.

A user selects the local data engine through a StorageClass and creates a PVC normally. Longhorn enforces
`strict-local` data locality and exactly one replica. When the `csi-storage-capacity-tracking` setting is
enabled, the kube-scheduler filters out nodes that cannot fit the requested volume; otherwise it places the
pod without regard to local capacity, and provisioning fails on a node without enough capacity. The instance
manager then creates a logical volume, and CSI formats and mounts the logical-volume device directly into the
workload.

### API Changes

- Add one data-engine identifier for the local data engine.
- Add `lvm` as a disk type.
- Add the `local-data-engine` setting that enables or disables the local data engine.
- Add the `local-data-engine-provisioning-mode` setting, with the options `thick` and `thin`.
- Add an immutable Volume spec field recording the effective provisioning mode. It is empty for v1 and v2
  volumes.
- Add a `localProvisioningMode` StorageClass parameter.
- Add the `local-data-engine-storage-layout` setting, with the options `per-disk` and `per-node`.
- Extend the node environment check to require the `dm_thin_pool` kernel module when the local data engine
  is enabled in thin mode. No other host prerequisite is added.
- Extend the instance-manager protobuf data-engine and disk-type enumerations.
- Extend the existing CRD validation enums and generated clients for the new values.
- Do not add new Kubernetes resource kinds. Existing Volume, Engine, Replica, Node, VolumeAttachment,
  Snapshot, Backup, and related resources are reused.

The name for the new data engine must be decided. This document uses `local`, but `vlocal`, `v-local`, `v0`,
and `v3` remain alternatives until the LEP review is complete.

## Design

### Terminology

| Term | Meaning |
|---|---|
| PV (physical volume) | A block device initialized for LVM use. |
| VG (volume group) | A storage pool formed from one or more PVs. Logical volumes are allocated from its extents. |
| LV (logical volume) | A block device allocated from a VG and exposed at `/dev/<vg>/<lv>`. |
| Thick LV | An LV that reserves its full physical capacity at creation and maps logical blocks to fixed VG extents. |
| Thin pool | A special LV holding the data and metadata of thin LVs. |
| Thin LV | An LV that reserves virtual capacity only and allocates chunks from a thin pool as it is written, which is what allows over-provisioning. |

### Object Model

Existing Longhorn resources retain their control-plane roles:

| Longhorn object | Local-engine representation                                           |
|---|-----------------------------------------------------------------------|
| Replica | The thick or thin logical volume (LV) containing the volume data      |
| Engine | The `longhorn-engine=<engine-name>` tag on the replica LV; no process |
| Volume | The existing user-facing Longhorn volume                              |

LVM has no Engine equivalent, but Longhorn's control-plane model depends on the Engine entity. Removing it
only for the local data engine would require substantial changes across the existing controllers. To
preserve this model, the Replica and Engine must represent the 3 lifecycle states below. The simplest
mapping uses LV activation for Replica state and an LV tag for Engine state:

```text
1. LV inactive                      Replica stopped    Engine stopped
       │ activate
       ▼
2. LV active, no engine tag         Replica running    Engine stopped
       │ add tag longhorn-engine=<name>
       ▼
3. LV active, engine tag present    Replica running    Engine running
```

This design minimizes local engine specific controller code while keeping the Engine representation as
lightweight as possible. The tag persists in LVM metadata, allowing the instance manager to rediscover the
attachment after restarting without adding another process, device-mapper layer, or state store.

The local engine always uses one replica and `strict-local` placement. Admission validation rejects any
other replica count, locality, shared-access, or migration configuration.

### Thin Versus Thick Provisioning

A thick LV reserves its requested physical capacity when it is created and maps logical blocks directly to
fixed VG extents. This provides predictable capacity and a simple data path close to direct-disk
performance.

A thin LV reserves virtual capacity, while physical chunks are allocated from a shared thin pool as data is
written. This permits over-provisioning.

Thin snapshots are also cheaper than classic thick LVM snapshots. A thin snapshot is created through
metadata operations, reserves no separate fixed-size COW volume, and shares unchanged chunks with the source
and other snapshots. A thick snapshot requires a separate COW LV with reserved capacity; when source data
changes, the original blocks must be copied into the applicable snapshot COW volumes. Its capacity
consumption and write amplification can therefore increase as snapshots accumulate.

#### Provisioning options

The local data engine operates in one cluster-wide provisioning mode:

- **`thick`** (default) fully allocates each LV. It does not support over-provisioning.
- **`thin`** uses thin LVs and zeroes newly allocated pool chunks before exposing them.

Thick is the default because it offers the most predictable performance. The mode can change only when no
local data engine volumes exist. Each local StorageClass may declare its expected mode through the
`localProvisioningMode` parameter. If the parameter is omitted, it defaults to `thick`. Provisioning is
rejected when the StorageClass mode differs from the cluster-wide mode, preventing an outdated StorageClass
from silently creating a different kind of volume.

Each Volume records the effective provisioning mode in an immutable spec field. This field remains
authoritative for expansion, actual-size accounting, snapshot validation. It is empty for v1 and v2 volumes.

In thin mode, creating the first volume in a VG creates a thin pool named `longhorn-thin-pool`. The
pool reserves 5 GiB of the VG for metadata, metadata repair, and future metadata expansion, and uses the
remaining capacity for pool data. Deleting the last thin LV in the VG also deletes the thin pool, so no empty
thin pool remains in any VG.

If the managed thin pool exists, disk status reports its data capacity and usage as well as metadata
fullness. Otherwise, disk status reports VG capacity and free extents. Thin mode respects Longhorn's global
storage over-provisioning setting. Thick mode limits effective over-provisioning to 100%, regardless of a
higher global value.

For thick LVs, actual size equals the provisioned size. For thin LVs without snapshots, actual size is the
physically allocated data. Thin volumes with snapshots require snapshot-aware accounting so that chunks
shared by the head and snapshots are not counted more than once.

Supporting both modes on the same disk at once was considered and deliberately rejected, because every way of
sharing one VG between thick LVs and a thin pool complicates capacity accounting. A fixed split, such as
50/50, wastes whichever side is idle. Growing the thin pool as thin volumes are scheduled is workable, but
LVM cannot shrink a thin pool once it has been extended, so capacity freed by a deleted thin volume stays
locked in the pool, and replica scheduling and over-provisioning accounting then have to reason about
capacity that is neither in use nor available. A dedicated disk type per mode would avoid the shared-capacity
problem, but it adds another disk concept for administrators to manage. One cluster-wide mode keeps capacity
accounting unambiguous. This can be revisited if there is demand for mixing the two.

### Node storage layout

The local data engine operates in one cluster-wide storage layout:

- **`per-disk`** (default) creates a separate VG for each LVM disk.
- **`per-node`** adds all LVM disks on a node to one shared VG. This layout is risky because failure of a
  single member disk can make all local volumes on the node unusable.

#### Per-disk mode

```text
Disk 1 ─► PV 1 ─► VG 1
Disk 2 ─► PV 2 ─► VG 2
Disk 3 ─► PV 3 ─► VG 3
```

Every disk reports its VG capacity and is independently schedulable.

#### Per-node mode

```text
Disk 1 ─► PV 1 (representative) ─┐
Disk 2 ─► PV 2 (member)          ├─► one node VG
Disk 3 ─► PV 3 (member)         ─┘
```

The representative disk reports the shared VG capacity and receives all replica assignments. Other members
remain visible and ready but report zero schedulable capacity, preventing the shared capacity from being
counted more than once.

Each disk is identified by its PV UUID. VGs use opaque, randomly generated names such as`longhorn-vg-a7f3c921`.

Adding a disk in `per-node` mode extends the existing VG. If the VG contains a managed thin pool, the new
capacity also extends that pool.

The layout can change only while every node has at most one LVM disk. The representative disk cannot be
removed while the VG has other PVs; member disks must be removed first. No disk can be removed while its VG
contains LVs.

### LVM command execution

All instance-manager LVM commands use `--devicesfile longhorn.devices`. Longhorn persists this file on the
host and mounts it into local instance-manager pods, keeping the managed-device set consistent across pod
restarts and upgrades. This cleanly isolates Longhorn-managed LVM storage from other LVM configurations on
the host, prevents Longhorn from modifying unrelated devices, and avoids failures or hangs caused by LVM
scanning unresponsive devices that do not belong to Longhorn.

LVM normally delegates device-node management to udev and synchronizes through udev cookies, which would
require the instance-manager pod to share the host IPC namespace. Because host IPC is invasive and may be
blocked in security-restricted environments, udev integration is disabled entirely with
`--config 'devices { external_device_info_source = "none" } activation { udev_sync = 0 udev_rules = 0 }'`.
LVM and device-mapper then work without udev, managing device nodes themselves and synchronously in the
host-bound `/dev`.

### Continuous I/O During Instance Manager Restart or Upgrade

During a local instance-manager restart, the replica state and volume robustness temporarily become
`unknown`, because the control plane cannot confirm the LV state. The volume remains attached and the
workload pod is not disturbed: its I/O continues through the existing kernel device-mapper device without
depending on the instance manager. When the replacement instance manager rediscovers the LV, the replica
returns to `running` and the volume robustness returns to `healthy`.

### Metrics

Capacity and health metrics come from LVM status. In thick mode, disk status reports VG capacity and free
space. In thin mode, it reports thin-pool data capacity and usage, so the disk is not reported as having no
free space and allocated capacity is represented correctly. I/O throughput, IOPS, and latency are derived
from Linux block-device statistics for each LV and disk.

### Snapshots

Snapshots use native LVM thin snapshots and are therefore available in thin provisioning mode. Snapshot
creation is a metadata operation, and the source and snapshot share unchanged chunks until one of them is
modified. Whether thick volumes should also support snapshots, through classic COW LVs, is still open.

### Backup and Restore

The existing Longhorn backup control plane, recurring jobs, backup format, deduplication, compression,
backup targets, retention, and garbage collection are reused. The local engine implements the engine-side
operations required to read a snapshot, identify changed ranges, and write restored blocks to a new LV.

Changed blocks can be obtained from thin-pool metadata using `thin_delta`. Longhorn backup blocks use a
fixed 2 MiB unit, so changed thin-pool chunks must be coalesced into aligned 2 MiB ranges. If efficient delta
calculation is unavailable, the implementation can conservatively report all backup blocks; checksum-based
deduplication preserves correctness at the cost of additional reads.

A completed off-node backup is the only Longhorn-managed protection against permanent loss of a local
volume. The UI and documentation must state this explicitly and expose the time of the last successful
backup.

### Encryption

Encryption reuses Longhorn's CSI-layer LUKS/dm-crypt flow. The encrypted mapping sits above the LV, so
the data path remains kernel-only.

### Test Plan

A comprehensive end-to-end test suite is added for the local data engine. Because the change also touches
shared data-engine dispatch, the existing v1 and v2 regression suites must continue to pass.

Benchmarks comparing `strict-local` v1 and v2 volumes, a directly consumed local disk, and the local data
engine are also part of validation. The local data engine is expected to perform within a single-digit
percentage of direct local-disk performance.

## Upgrade Strategy

There is no per-volume or per-node engine binary to upgrade. Instance manager upgrades temporarily
prevent disk/volume management operations on the affected node, but attached volumes continue I/O through
the kernel device-mapper stack.

## Alternatives Considered
