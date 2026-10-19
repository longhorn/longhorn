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

- No mandatory manual LVM preparation. TopoLVM and OpenEBS LocalPV-LVM require administrators to create
  volume groups in advance. Longhorn turns one or more empty disks into a volume group itself, and still
  accepts administrator-created volume groups for any other layout.
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

The administrator enables the local data engine and adds an `lvm` disk to a Longhorn Node resource, giving
as its path either one or more empty block devices or the name of a volume group they created. The first
LVM disk on a node starts the local instance-manager pod there. The instance manager contains the required
`lvm2` tools, so the host does not need to provide them for Longhorn's own operations. For block devices,
the instance manager initializes each as a physical volume and creates one volume group across them. For a
volume group name, it verifies that the group holds no logical volumes and takes it over. Either way, the
disk Longhorn sees from then on is the volume group, and its path cannot be edited afterwards.

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
- Add `lvm` as a disk type. Its `path` is either one or more empty block devices separated by `;`, or the
  name of an existing volume group.
- Reject any change to the `path` of an existing `lvm` disk in the node admission webhook. Devices cannot
  be added to or removed from a volume group in the first version.
- Add the `local-data-engine` setting that enables or disables the local data engine.
- Add the data-engine-specific `data-engine-provisioning-mode` setting, with the options `thick` and `thin`
  and the default `{"local":"thick"}`. Only the local data engine is listed for now.
- Add an immutable `provisioningMode` Volume spec field recording the effective provisioning mode. It is
  empty for v1 and v2 volumes.
- Add a `provisioningMode` StorageClass parameter.
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
| Disk | In the local data engine, a Longhorn disk is a VG. Longhorn allocates LVs from it and identifies it by the VG UUID. |

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

The local data engine operates in one cluster-wide provisioning mode, selected by the local entry of the
`data-engine-provisioning-mode` setting:

- **`thick`** (default) fully allocates each LV. It does not support over-provisioning.
- **`thin`** uses thin LVs and zeroes newly allocated pool chunks before exposing them.

Thick is the default because it offers the most predictable performance. The mode can change only when no
local data engine volumes exist. Each local StorageClass may declare its expected mode through the
`provisioningMode` parameter. If the parameter is omitted, it defaults to `thick`. Provisioning is
rejected when the StorageClass mode differs from the cluster-wide mode, preventing an outdated StorageClass
from silently creating a different kind of volume.

Each Volume records the effective provisioning mode in the immutable `provisioningMode` spec field. This
field remains authoritative for expansion, actual-size accounting, snapshot validation. It is empty for v1
and v2 volumes.

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

### Disks Are Volume Groups

In the local data engine, a disk is a volume group. Longhorn allocates LVs from the VG, reports the VG's
capacity, and identifies the disk by the VG UUID. It does not manage or depend on the VG's internal layout.
How many PVs the VG has and what they sit on are the administrator's decisions. There is no storage layout
setting.

The `path` of an `lvm` disk is either one or more block devices separated by `;`, such as `/dev/sda` or
`/dev/sda;/dev/sdb`, or the name of an existing VG, given as `<vg>` or `/dev/<vg>`. The instance manager
detects which on registration:

```text
every path element is a block device
  ├─ all empty: no filesystem, partition table, or LVM signature
  │     → pvcreate each, vgcreate longhorn-vg-<random> across them, tagged; the disk is that VG
  └─ any element not empty → rejected, naming the device

path is a single element that is not a block device → treated as a VG name
  ├─ VG exists and contains no LVs
  │     → tagged and adopted; the disk is that VG
  ├─ VG exists and contains LVs, including a pre-made thin pool
  │     → rejected, naming the LVs
  └─ no such VG → rejected, stating that the path is neither a block device nor a VG

anything else, such as a list mixing devices and names → rejected
```

Creating a VG from several devices is all or nothing: on a partial failure the instance manager removes the
PV signatures and devices-file entries it added, so a retry starts from empty devices.

The block-device form builds a VG from empty disks without manual LVM work. Any other layout is built by the
administrator and registered by name. Once registered, the two forms are indistinguishable to Longhorn.

#### Ownership and re-registration

Every VG Longhorn creates or adopts carries a Longhorn VG tag. Registration is idempotent: a device list
whose PVs already form one tagged VG, or the name of a tagged VG, returns the existing disk and reactivates
its LVs that carry an engine tag. This is how a disk that still holds volumes is re-registered after
`/var/lib/longhorn` and the Node resource are lost, as v1 and v2 do from the disk config file and the
lvstore.

#### Identity and duplicates

The disk UUID is the VG UUID; the path is used only at registration. The node admission webhook rejects a
device listed in two disk entries on a node. Any other way of registering one VG twice yields the same disk
UUID, and the node controller's existing duplicate disk ID handling marks the second entry not ready.

#### Capacity and health

Disk status reports the VG's size and free extents, or the managed thin pool's capacity and usage when the
pool exists. Longhorn never extends or reduces a VG in the first version. If the administrator grows an
adopted VG with `vgextend`, Longhorn picks up the new free capacity on its next status refresh and, in thin
mode, extends the managed thin pool into it. Health data is collected from the VG's physical volumes.

#### Editing and removal

The `path` of an `lvm` disk is immutable; the node admission webhook rejects any change. Devices cannot be
added to or removed from a VG in the first version. To change the member set, remove the disk and register
it again. Editing the device set of an empty VG and online extension may be added later.

A disk can be removed only while its VG contains no LVs. Removal deletes the VG and the PV signatures of all
its devices, whether Longhorn created the VG or adopted it, and drops its devices-file entries.

### LVM command execution

All instance-manager LVM commands use `--devicesfile longhorn.devices`. Longhorn persists this file on the
host and mounts it into local instance-manager pods, keeping the managed-device set consistent across pod
restarts and upgrades. This cleanly isolates Longhorn-managed LVM storage from other LVM configurations on
the host, prevents Longhorn from modifying unrelated devices, and avoids failures or hangs caused by LVM
scanning unresponsive devices that do not belong to Longhorn. An empty block device is added to the file
when it is registered. For an administrator-created VG, `vgimportdevices` adds exactly that VG's physical
volumes, so only devices backing registered VGs are ever visible to Longhorn's LVM commands.

LVM normally delegates device-node management to udev and synchronizes through udev cookies, which would
require the instance-manager pod to share the host IPC namespace. Because host IPC is invasive and may be
blocked in security-restricted environments, udev integration is disabled entirely with
`--config 'devices { external_device_info_source = "none" } activation { udev_sync = 0 udev_rules = 0 }'`.
LVM and device-mapper then work without udev, managing device nodes themselves and synchronously in the
host-bound `/dev`.

### Instance Manager Placement

The local data engine serves only `strict-local` volumes, so a node without an LVM disk never hosts a local
volume and does not need a local instance manager. Longhorn runs the local instance-manager pod on a node
only while the node has at least one `lvm` disk: adding the first LVM disk creates the pod, and removing the
last one removes it once the disk is deregistered and no instance is running. Nodes with only `block` or
`filesystem` disks never reserve the local engine's instance-manager resources. v1 and v2 keep their current
behaviour, since their engine process may run on a node without disks.

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
