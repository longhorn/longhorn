# Configurable V2 Logical Block Size

## Summary

Longhorn currently creates every AIO-backed V2 disk with a hard-coded 512-byte logical block size. This prevents a 4Kn block device from becoming ready because SPDK refuses to expose an AIO bdev with a logical block size smaller than the block device reports. It also prevents users from intentionally presenting a 512-byte-native device as a 4096-byte AIO bdev.

This enhancement makes the AIO disk block size configurable while preserving 512 bytes as the default. It also introduces an immutable logical block size for V2 volumes. The volume-level field is necessary because SPDK RAID requires all base bdevs to have the same block size: configuring disks without constraining replica and shard placement would move the failure from disk initialization to volume attachment or rebuild.

Longhorn will initially support logical block sizes of 512 and 4096 bytes. A cluster may contain both, but all replicas or erasure-coded shards belonging to one volume must use disks with the volume's logical block size. Existing V2 volumes and disks with unset fields are resolved from observed state without silently reformatting or reinterpreting initialized storage.

V2 backing-image creation has been rejected since Longhorn v1.12.0 and is not reintroduced by this enhancement. If V2 backing images are enabled again, their first supported contract remains limited to 512-byte volumes unless a separate enhancement adds an explicit compatibility declaration for 4096-byte images. This preserves the compatibility lesson from images originating in the V1 data engine, which may contain a filesystem whose block size is smaller than 4096 bytes.

### Related Issues

- https://github.com/longhorn/longhorn/issues/10745
- https://github.com/longhorn/longhorn/issues/10053
- https://github.com/longhorn/longhorn/issues/13181
- https://github.com/longhorn/longhorn-manager/pull/5021

## Motivation

The block size sent to SPDK has two separate effects:

1. For an AIO disk, it determines how SPDK presents the underlying block device to the logical volume store.
2. For a V2 volume, it becomes the logical block size of each replica lvol, the SPDK RAID bdev, and ultimately the frontend device presented to the workload.

These effects cannot be managed independently. SPDK rejects an AIO block size smaller than the logical block size detected from the device. SPDK also rejects a RAID whose base bdevs have different block sizes. Without a volume-level constraint, a scheduler could place one replica on a 512-byte disk and another on a 4096-byte disk even though each disk is individually healthy.

Backing images add another compatibility boundary. Copying bytes between devices with different logical block sizes does not prove that the contents can be consumed through either device. For example, an ext filesystem with a 1024-byte filesystem block size can be read from a 512-byte logical-sector device but cannot be mounted from a 4096-byte logical-sector device. Longhorn cannot reliably infer the requirements of an arbitrary raw image.

### Goals

- Allow an AIO-backed V2 disk to be initialized with a 512-byte or 4096-byte logical block size.
- Allow a true 4Kn block device to become a schedulable V2 disk when configured with 4096 bytes.
- Record the effective logical block size reported by every initialized V2 block disk, including AIO, NVMe, and virtio disks.
- Allow 512-byte and 4096-byte V2 disks to coexist in one cluster.
- Give every V2 volume one immutable logical block size and schedule all of its replicas or shards only to matching disks.
- Preserve the volume logical block size through every lifecycle workflow supported by the selected data layout.
- Upgrade existing disks and volumes without assuming that every unset resource uses 512 bytes.
- Fail early with an actionable scheduling or validation message instead of allowing SPDK RAID creation to fail later.

### Non-goals

- Changing the logical block size of an initialized disk or existing volume in place.
- Converting replica, snapshot, backup, or backing-image data between logical block sizes.
- Supporting logical block sizes other than 512 and 4096 bytes in the first implementation.
- Reintroducing V2 backing images, or supporting 4096-byte V2 volumes created from backing images.
- Changing the logical block size behavior of the V1 data engine.
- Automatically moving an existing 512-byte volume to 4096-byte disks, or the reverse, during eviction or replica balancing.
- Adding clone, backup, restore, or DR support to EC volumes; those workflows remain governed by the existing data-layout restrictions.

## Proposal

The design separates three values that have different owners:

| Value | Owner | Meaning |
| --- | --- | --- |
| Requested disk block size | `Node.spec.disks[*].blockSize` | The AIO block size requested when initializing the disk. |
| Observed disk block size | `Node.status.diskStatus[*].actualBlockSize` | The effective block size reported by the initialized SPDK lvstore. This is the scheduling capability. |
| Volume logical block size | `Volume.spec.logicalBlockSize` | The immutable block size required for every replica or shard and exposed by the volume frontend. |

The requested disk value is meaningful only for AIO. The observed value is meaningful for every V2 block disk. The scheduler always compares a volume against the observed value, never against the requested value.

The initially supported values are:

| Value | Disk behavior | Volume behavior |
| --- | --- | --- |
| `0` | Unset or legacy. A new AIO disk uses the compatible default of 512. An initialized disk retains its observed value. | Unresolved legacy value only. Admission defaults a new blank V2 volume to 512 or inherits a known source value. |
| `512` | Request a 512-byte AIO bdev. | Require 512-byte replica or shard disks. This is the default. |
| `4096` | Request a 4096-byte AIO bdev. | Require 4096-byte replica or shard disks. |

### User Stories

#### Use a 4Kn device as a V2 disk

An administrator has a block device that reports a 4096-byte logical block size. Today the disk remains unavailable because Longhorn requests 512 bytes. The administrator configures the disk with `blockSize: 4096`, and Longhorn initializes it, reports an actual block size of 4096, and makes it available for 4096-byte V2 volumes.

#### Use a mixed-storage cluster safely

An administrator has existing 512-byte V2 disks and adds 4096-byte disks. Existing and default V2 volumes continue to use 512-byte disks. A StorageClass requesting 4096 bytes creates volumes whose replicas are placed only on 4096-byte disks. Rebuild, eviction, and replica balancing preserve the same constraint.

#### Preserve a volume across failure and restore

A 4096-byte volume loses a replica, restarts its instance manager, or is restored from a backup. Longhorn retains the volume's 4096-byte contract and never rebuilds or restores it as a 512-byte volume.

#### Upgrade a cluster with inferred block-size disks

An existing cluster contains an NVMe disk whose driver inferred a 4096-byte block size, or an older AIO lvstore initialized with 4096 bytes while its new spec field is unset. During upgrade, Longhorn records the observed value and resolves existing volumes from their replica or shard disks. It does not rewrite either resource to 512 merely because the new field was absent.

### User Experience In Detail

#### Configure a V2 disk

The block size is set on a block-type disk in the Longhorn node configuration. It is also accepted by the existing default-disks-config annotation because that annotation embeds the disk specification.

```yaml
apiVersion: longhorn.io/v1beta2
kind: Node
metadata:
  name: worker-1
  namespace: longhorn-system
spec:
  disks:
    nvme-4kn:
      diskType: block
      path: /dev/nvme0n1
      diskDriver: aio
      blockSize: 4096
      allowScheduling: true
```

An explicit value is accepted only when the selected driver is AIO, or when `auto` with a device path deterministically resolves to AIO. NVMe and virtio drivers infer their block size from hardware and reject an explicit disk value. Their observed block size is still published and used by the scheduler.

The disk block size is immutable after initialization. To use a different value, the administrator must disable scheduling, evacuate all replicas and other data objects, delete the disk from Longhorn, clean or intentionally replace its on-disk data, and add it again.

If an uninitialized disk is already in `Error` because it was attempted with the wrong block size, changing the requested value causes Longhorn to clean up the failed in-memory bdev and retry. Removing and re-adding the Node disk entry is not required.

#### Create a 4096-byte V2 volume

The default remains 512. A 4096-byte volume is requested through a StorageClass:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-v2-4k
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  dataEngine: v2
  logicalBlockSize: "4096"
  numberOfReplicas: "3"
```

The same field is available when creating a Volume through the Longhorn API or UI. It is shown only for the V2 data engine. A directly created blank V2 Volume CR with an unset value is mutated to 512. Clone, restore, and DR creation resolve source metadata before applying any default.

There is no global default setting in the first implementation. A fixed 512-byte default is predictable, retains the existing compatibility behavior, and requires 4096-byte use to be explicit at the Volume or StorageClass boundary.

If no matching disks are available, the volume remains unscheduled with a block-size mismatch in its scheduling condition and PV annotation. Longhorn does not fall back to another block size.

The volume size and every expanded size must be an integer multiple of the logical block size. Longhorn's normal size alignment already satisfies this requirement, but admission validates it explicitly.

#### Backing-image behavior

Longhorn v1.12.0 removed V2 backing-image support, and current admission rejects creation of a V2 BackingImage. This enhancement keeps that behavior. Reintroduction requires a separate compatibility design because Longhorn cannot infer a safe logical sector size from arbitrary image contents.

#### Backup, restore, DR, and clone behavior

The logical block size is part of the volume data contract and is recorded in each backup's metadata. A restore or DR volume inherits it and cannot override it when the metadata is present. A volume clone likewise inherits the source volume's logical block size.

Legacy backups do not contain this metadata. A legacy V2 restore must explicitly assert 512 or 4096; a same-named live Volume is not trusted as provenance, and the UI does not guess. A backup identified as V1 uses 512 when restored as V2 because the V1 frontend contract is 512. The assertion chooses compatible placement and does not transform the data.

`backupBlockSize`, which controls backup chunking, is independent from the volume logical block size described here.

### API changes

#### Node disk specification and status

```go
type DiskSpec struct {
	// BlockSize is the requested logical block size for an AIO-backed V2 block disk.
	// Zero uses the legacy default when initializing a new disk.
	// +kubebuilder:validation:Enum=0;512;4096
	// +optional
	BlockSize int64 `json:"blockSize"`
}

type DiskStatus struct {
	// ActualBlockSize is the logical block size reported by an initialized V2 block disk.
	// +optional
	ActualBlockSize int64 `json:"actualBlockSize"`
}
```

The status value is populated for AIO, NVMe, and virtio disks. It is retained while an initialized disk is temporarily unavailable and replaced only after Longhorn observes the same disk UUID ready again.

#### Volume specification

```go
type VolumeSpec struct {
	// LogicalBlockSize is the immutable logical block size of a V2 volume.
	// Zero is reserved for unresolved resources created before this field existed.
	// +kubebuilder:validation:Enum=0;512;4096
	// +kubebuilder:validation:XValidation:rule="oldSelf == 0 || self == oldSelf",message="LogicalBlockSize is immutable"
	// +optional
	LogicalBlockSize int64 `json:"logicalBlockSize"`
}
```

The volume mutator sets 512 for new blank V2 volumes with an unset value. For clone, restore, and DR creation, it inherits known source metadata instead. A nonzero value is rejected for V1 volumes. The validator allows an existing legacy V2 volume to transition from zero to its resolved value once, then treats the field as immutable.

Defaulting is performed only by the admission webhook on Volume creation. The CRD schema does not declare 512 as a default, and the update mutator preserves zero on an existing unresolved Volume. Otherwise, installing the new CRD or updating an unrelated field could erase the migration sentinel before the controller observes existing replicas.

#### CSI and REST API

- Add `logicalBlockSize` as a V2 StorageClass parameter. It accepts the decimal byte strings `"512"` and `"4096"`.
- Add the requested and observed disk fields to the node REST resource and generated clients.
- Add the volume field to volume create, inspect, and generated client models.
- A disk update must preserve an existing nonzero value when an older API client omits the new field. The REST disk update endpoint currently replaces the complete disk map, so its API-only update model needs presence tracking, such as a pointer field, to merge an omitted value from the stored spec instead of silently requesting zero.

#### Backup metadata

Add `VolumeLogicalBlockSize` to each backup's backupstore metadata, `BackupStatus`, and REST Backup model. `BackupVolumeStatus` may expose the latest known value as a cache and consistency check, but it is not authoritative because a Kubernetes Volume can be deleted and recreated under the same name with a different contract. The manager copies the per-backup value into the restored Volume spec. A missing value identifies unknown legacy metadata and requires an explicit restore assertion.

The existing disk-service `DiskCreate` RPC already carries a block size and reports the effective size. Engine, replica, rebuild, and shard-group create requests gain an expected logical block size so the data plane can validate connected bdevs against the Volume contract rather than merely checking that they match each other.

## Design

### Implementation Overview

| Component | Responsibilities |
| --- | --- |
| `longhorn-manager` | CRD and API fields, admission, disk monitoring and retry, legacy resolution, replica and shard scheduling, CSI parameter handling, backup/clone propagation, and upgrade conditions. |
| `longhorn-spdk-engine` | Clear preflight validation before RAID or EC creation and before adding a rebuilding member. If retry cleanup is implemented in the disk service, safely replace failed uninitialized runtime disk records. |
| `backupstore` and backup engine integration | Persist, inspect, and restore the volume logical block size independently from backup chunk size. |
| `longhorn-ui` | Disk requested/observed fields, V2 volume creation choice, immutable detail display, and continued omission of V2 backing-image controls. |
| `longhorn-tests` | Automated mixed-size scheduling, lifecycle, upgrade, and backup/restore coverage. |
| `longhorn` and `longhorn.io` | CRD/chart integration, release notes, compatibility documentation, and operational procedures. |

### Core invariants

1. An initialized disk's observed block size is authoritative. Its requested value is not used as a scheduling capability.
2. A V2 volume has exactly one logical block size for its lifetime.
3. Every replica or shard for that volume is placed on a disk with the same observed block size.
4. Unknown is not compatible. A disk without an observed block size is not eligible for a V2 volume until monitoring succeeds.
5. Longhorn never converts data between logical block sizes as a side effect of scheduling, rebuild, restore, or upgrade.

### Disk initialization and monitoring

For a new AIO disk, the manager resolves an unset requested value to 512 and sends the value to the disk service. The disk monitor records the block size returned by the lvstore in `actualBlockSize`. A disk is not schedulable until the actual value is nonzero and supported.

For an initialized AIO disk whose spec remains zero, the upgrade controller pins the spec to the first supported size observed from the ready lvstore. Until that update succeeds, the manager passes the last observed status value when recreating the disk after an instance-manager restart. This is important for older 4096-byte AIO lvstores: resolving zero to 512 on every restart would make the existing lvstore unavailable. NVMe and virtio specs remain zero because their size is not configurable.

If the spec contains a nonzero request and the ready disk reports a different actual value, Longhorn marks the disk unschedulable with a block-size mismatch. This protects restored CRs and environments where admission was bypassed.

When an initialized AIO disk has a known UUID but neither a pinned spec nor an observed status value, Longhorn does not guess. The disk remains unavailable until the administrator supplies a one-time explicit value. The webhook permits this recovery transition only from zero and only while the disk's Ready condition is not true; it never permits an assertion over a ready initialized disk. `DiskCreate` must import the existing UUID and must never create a new lvstore when a UUID is supplied, so an incorrect assertion fails instead of replacing data. A failed assertion detaches its temporary bdev before another attempt.

Changing the requested value on an uninitialized failed disk triggers a retry. The disk service or monitor removes the failed runtime record and any partial bdev that does not contain an initialized lvstore, then issues `DiskCreate` with the new request.

### Volume block-size resolution

Admission ensures all newly created V2 volumes have an explicit value from either source metadata, an explicit request, or the blank-volume default. Zero is retained only as a migration sentinel for objects that predate this enhancement.

The volume controller resolves an existing zero-valued volume as follows:

1. If the volume has source metadata, such as a clone, backup, or DR source, use that value and verify existing placements against it.
2. Otherwise, collect the observed block sizes of disks holding all scheduled nonfailed or potentially reusable replicas or EC shards.
3. If every relevant placement is known and exactly one distinct supported value exists, persist it to `Volume.spec.logicalBlockSize`.
4. If there are no placements and no source metadata, use 512.
5. If any relevant placement is unknown, reports an unsupported value, or multiple values exist, leave the field unresolved and set a condition describing the conflict.

While a volume is unresolved, Longhorn blocks new attachment, engine reconstruction, DR activation, clone/restore creation, and replica or shard placement. An already-running attachment is not interrupted solely for migration. A conflict requires operator investigation rather than an automatic choice.

### Scheduling

Block-size eligibility is part of the common V2 disk filter. It is applied before storage scoring and balancing in all of the following paths:

- Initial replica scheduling, including strict and best-effort data locality.
- Replica replenishment and online rebuild.
- Failed-replica reuse.
- Disk and node eviction.
- Replica auto-balance and disk-pressure balance.
- Offline rebuilding.
- Linked and full V2 volume cloning.
- EC shard placement and replacement.

A dedicated scheduling error, such as `disk block size mismatch`, is included in the Volume scheduled condition and PV scheduling-error annotation. The message includes the required and observed values.

The scheduler uses `DiskStatus.ActualBlockSize`, not `DiskSpec.BlockSize`. This handles non-AIO devices and prevents a requested value from being treated as successfully applied before disk initialization completes.

### Engine validation

The manager passes the immutable expected logical block size through engine, replica, rebuild, and shard-group requests. The data plane validates the invariant at its trust boundary:

- Before creating or reconstructing an SPDK RAID bdev, verify every connected base bdev equals the expected value and reject a mismatch with a clear error.
- Before adding a rebuilding replica to an existing RAID, compare the destination bdev with both the expected value and the existing RAID.
- Apply the equivalent expected-value validation when constructing an EC bdev from shard endpoints.

SPDK already rejects base bdevs that differ from each other, but that does not detect one replica, or several equally wrong replicas, that violate the Volume contract. The explicit expected-value checks provide a stable Longhorn error and prevent a generic late JSON-RPC failure from being the first indication of a scheduler or restored-CR problem.

### Encryption

For a new encrypted V2 volume, Longhorn passes the volume logical block size to `cryptsetup luksFormat --sector-size` as the LUKS2 data-sector size. The LUKS2 header persists that value, and attach validates both the header and the opened device-mapper device against `Volume.spec.logicalBlockSize`. A mismatch blocks attachment rather than silently exposing a 512-byte mapper for a 4096-byte volume. Existing encrypted volumes retain the sector size stored in their LUKS2 header during upgrade; a conflict with resolved replica placement is reported as an unresolved volume.

### Backup and restore

The backup engine records `volumeLogicalBlockSize` in every backup independently from the backup chunk size. Backup inspection returns it to the manager. Restore, DR activation, and restore-to-new-volume flows set the destination Volume field before replica scheduling begins.

Backup-volume metadata may cache the value to detect conflicting new backups, but each backup remains authoritative for its own restore. This avoids reinterpreting old backups if a Kubernetes Volume is deleted and recreated under the same name with another logical block size.

For legacy V2 backup metadata, the restore request must provide an explicit assertion because a same-named live Volume is not stable provenance. The assertion is validated against the supported values and recorded on the new volume. Longhorn does not claim that this converts or verifies application data. A backup explicitly identified as V1 uses the V1 logical-sector contract of 512 when restored into V2.

### Phased implementation

#### Phase 1: Disk capability foundation

- Add the requested disk and observed status fields.
- Validate AIO-only configuration and supported values.
- Preserve observed values for legacy initialized disks.
- Retry an uninitialized disk after its requested value changes.
- Display requested and observed values through the API and UI.

These API additions may merge separately only if admission continues to reject 4096 or the behavior is feature-gated off. A schedulable 4096-byte disk is unsafe before Phase 2 because an ordinary 512-byte volume can otherwise land on it.

#### Phase 2: Volume contract and safe scheduling

- Add and default the immutable Volume field.
- Add StorageClass, REST API, and UI creation support.
- Resolve legacy volumes.
- Enforce exact matching in every replica and EC scheduling path.
- Add data-plane preflight validation.
- Record and restore the value through backup and clone workflows.
- Preserve the existing rejection of V2 backing-image creation.

Phases 1 and 2 ship in the same Longhorn release. The 4096 option is enabled only after volume defaulting, scheduling enforcement, data-plane validation, upgrade resolution, and metadata propagation are all present.

### Alternatives considered

#### Require one block size for the whole cluster

This would avoid a Volume API change and simplify scheduling. It was rejected because it prevents gradual adoption, makes heterogeneous hardware unusable, and would require disruptive cluster-wide migration.

#### Rely on disk tags and selectors

Administrators could tag disks as 512 or 4096 and manually select them in StorageClasses. This was rejected because tags are not an integrity constraint. Missing or incorrect tags would still allow a late SPDK RAID failure, and rebuild paths could bypass the user's intended grouping.

#### Infer the volume block size from the first scheduled replica

This reduces user-facing configuration, but makes the result dependent on map iteration and current capacity. It also cannot express intent before backup restore, backing-image selection, clone, or multi-replica scheduling. An explicit immutable Volume field is deterministic and portable.

#### Auto-detect every unset AIO disk

SPDK can auto-detect a block device's logical block size when the request is omitted. This would make true 4Kn disks initialize automatically. It was not chosen because Longhorn intentionally changed the compatible AIO default to 512, and auto-detection does not cover the valid case of intentionally presenting a 512-byte-native device as 4096. Recovery of an initialized disk instead requires an explicit assertion tied to its known UUID.

#### Make the volume default a global setting

A global default would reduce repeated StorageClass configuration for clusters that exclusively use 4096-byte disks. It was not selected for the first implementation because changing the setting could make otherwise identical volume requests behave differently over time, and a fixed 512-byte default preserves the existing contract. A StorageClass already provides an explicit, auditable cluster-level choice.

#### Allow any SPDK-supported power-of-two value

SPDK AIO accepts a broad range, but Longhorn's lvstore cluster size, Linux block stack, frontends, filesystems, encryption, and test matrix impose additional constraints. The existing 1 MiB lvstore cluster rejects a block size larger than the cluster or one that does not divide it. Supporting only 512 and 4096 reflects real hardware formats and keeps the compatibility contract testable. More values can be proposed after end-to-end validation.

### Longhorn UI and documentation

The UI will:

- Offer 512 and 4096 when adding or editing an uninitialized AIO disk.
- Show requested and observed block sizes separately in disk details.
- Offer the logical block size during V2 volume and StorageClass creation, defaulting to 512.
- Show the immutable value in volume details.
- Lock the value to source metadata for clone and restore flows.
- Continue to omit the removed V2 backing-image options.

Documentation will include:

- A compatibility table for AIO, NVMe, virtio, 512-byte, 512e, and 4Kn devices.
- Examples for node disks, default-disks-config, StorageClasses, and direct Volume creation.
- The difference between disk requested size, disk observed size, volume logical block size, filesystem block size, and backup chunk size.
- The removal of V2 backing-image support, the [CDI-based import alternative](https://longhorn.io/docs/1.12.0/advanced-resources/containerized-data-importer/containerized-data-importer/), and the historical compatibility reason for retaining 512 as the default.
- Upgrade and recovery procedures for legacy unset disks and volumes.
- The evacuation and data-removal requirements for changing an initialized disk.
- A release note that older managers do not enforce mixed-size scheduling.

### Test plan

#### Unit and controller tests

- Validate disk values `0`, `512`, and `4096`; reject unsupported values and explicit values for non-AIO drivers.
- Verify a new unset AIO disk resolves to 512.
- Verify an initialized unset disk reuses `actualBlockSize` on disk-service recreation.
- Verify requested and observed mismatch makes the disk unschedulable.
- Verify changing an uninitialized failed disk request causes cleanup and retry.
- Verify an initialized disk cannot change its effective value, while a legacy zero may be pinned to the observed value or explicitly asserted only while the disk is not ready.
- Validate new V2 Volume defaulting, V1 rejection, immutability, and size alignment.
- Resolve legacy volumes from 512-byte replicas, 4096-byte replicas, EC shards, source metadata, no placements, unknown placements, and conflicting placements.
- Exercise scheduler matrices containing 512-byte, 4096-byte, unknown, and unsupported disks for every placement path listed above.
- Verify failed-replica reuse and auto-balance cannot cross the block-size boundary.
- Verify current admission continues to reject V2 BackingImage creation and no Volume creation path establishes a new V2 backing-image dependency.
- Verify backup and clone metadata is inherited and conflicting metadata is rejected.
- Verify a legacy V2 backup requires an explicit restore assertion and does not infer from a same-named live Volume.
- Verify a V1 backup restored as V2 receives the 512-byte V1 frontend contract.
- Verify a whole-map REST disk update preserves an existing block size when the client omits the field.

#### SPDK engine integration tests

- Create and expose replicas on 512-byte and 4096-byte lvstores.
- Create RAID1 and EC volumes whose members all use 512 and all use 4096.
- Reject mixed-block-size RAID1 base bdevs before RAID creation.
- Reject a rebuilding replica whose block size differs from the existing RAID.
- Reject mixed-block-size EC shard endpoints.
- Reject one or more equally wrong RAID or EC members when they differ from the expected Volume value.
- Exercise snapshot, revert, expansion, rebuild, frontend restart, and instance-manager restart on a 4096-byte volume.
- Exercise NVMe/TCP and ublk frontends with 4096-byte devices.
- Exercise encrypted 4096-byte volumes and verify the frontend retains the expected logical block size.

#### Automated end-to-end tests

Where test infrastructure permits, create 4096-byte logical-sector loop devices with `losetup --sector-size 4096` so the AIO path is covered without requiring physical 4Kn hardware.

1. Add a 512-byte AIO disk and run the existing V2 volume regression suite.
2. Add a 4096-byte AIO disk, create a 4096-byte V2 volume, attach it, create a filesystem, write and verify data, snapshot it, rebuild a replica, expand it, and restart its instance manager.
3. Run a mixed cluster with both disk sizes. Create 512-byte and 4096-byte multi-replica volumes and verify every replica remains in the correct pool through rebuild, eviction, and auto-balance.
4. Run the equivalent mixed-disk tests for an EC volume.
5. Back up a 4096-byte volume and restore it into a cluster with both disk sizes. Verify the restored volume remains 4096 and its data is intact.
6. Clone a 4096-byte volume and verify the clone inherits the source value.
7. Restore a legacy V2 backup without block-size metadata. Verify it requires an explicit assertion even when a same-named live Volume exists.
8. Verify V2 BackingImage creation remains rejected and a new V2 Volume cannot establish a backing-image dependency, for both supported volume block sizes.
9. Verify V1 backing-image behavior is unaffected by the V2-only Volume field.
10. Start an AIO disk with the wrong value, update the uninitialized disk to the correct value, and verify it becomes ready without removing the Node disk entry.
11. Upgrade fixtures containing unset 512-byte AIO disks, unset legacy 4096-byte AIO disks, native 4096-byte NVMe disks, and V2 volumes on each. Verify resolution does not change their effective value.
12. Verify rollback remains supported for an all-512 fixture and is blocked or explicitly warned once a new or legacy 4096-byte AIO resource is discovered.

#### Manual hardware tests

- Repeat disk initialization and sustained I/O on a physical 4Kn NVMe device through the AIO driver.
- Verify an explicit 512-byte request is rejected on a true 4Kn device without changing existing data.
- Verify an explicit 4096-byte AIO override on a 512-byte-native device.
- Run failure recovery across node reboot, unclean instance-manager restart, replica rebuild, and network interruption.
- Confirm the logical block size reported by the workload node with `blockdev --getss` or equivalent for each supported frontend.

### Upgrade strategy

The new fields are additive, but their zero values require deliberate handling.

#### Existing disks

- All existing Node disk specs initially have `blockSize: 0`.
- The disk monitor records the actual value reported by each ready lvstore.
- A new 512-byte AIO disk with an unset value continues to use 512.
- An initialized unset AIO disk is pinned to its first supported observed value and uses status as a fallback until the spec update succeeds.
- Native NVMe and virtio disks retain the block size reported by hardware; their spec remains zero because it is not configurable.
- Longhorn does not rewrite on-disk lvstore metadata during upgrade.
- If a known initialized disk cannot be observed, it remains unschedulable rather than being recreated with a guessed value.

#### Existing volumes

- Existing V2 Volumes initially have `logicalBlockSize: 0` and are resolved by the volume controller from replica or shard disk status.
- The controller persists the single resolved value before scheduling new replicas or shards.
- A volume without placements or source metadata resolves to 512.
- A volume with unknown or conflicting placements is surfaced for operator action and is not assigned a value by guesswork.
- Existing attachments are not forcibly interrupted solely to perform resolution.

#### Existing backups and backing images

- Existing backup metadata has no volume block size. A V2 restore requires an explicit assertion and does not infer from a same-named live Volume.
- There are no supported V2 backing-image resources to migrate from v1.12 or v1.13. Users upgrading from a release that allowed V2 backing images must first follow the v1.12 migration requirement to back up and recreate or delete dependent volumes.
- Any stale V2 backing-image runtime objects continue through the existing cleanup behavior; this enhancement does not make them schedulable again.

#### Version skew and rollback

An older manager does not understand `Volume.spec.logicalBlockSize`, does not filter mixed-size disks, and sends the historical 512-byte request when recreating an AIO disk. Therefore, creating or initializing 4096-byte resources requires every manager pod to run a version that implements this enhancement.

After a 4096-byte AIO disk or volume is created or a legacy 4096-byte AIO resource is discovered, rolling back to an older manager is not supported. Disabling scheduling is insufficient because an older disk monitor can still recreate an AIO bdev with 512 after an instance-manager restart. The compatible manager version must be restored before controllers resume. A rollback retains the existing 512-byte behavior only when no new or legacy 4096-byte AIO resources are present.

The existing disk-service RPC already transports the requested and observed values, so normal manager and instance-manager rollout skew does not require a protocol fallback. Any data-plane preflight additions return clearer errors but do not change the on-disk format.

## References

- [SPDK AIO bdev](https://github.com/spdk/spdk/blob/master/module/bdev/aio/bdev_aio.c) requires an explicit block size to be at least the detected device block size and uses the detected size when none is supplied.
- [SPDK RAID](https://github.com/spdk/spdk/blob/master/module/bdev/raid/bdev_raid.c) requires every base bdev to have the same block length.
- V2 backing-image removal is tracked in [longhorn/longhorn#13181](https://github.com/longhorn/longhorn/issues/13181); the earlier design is retained in `enhancements/20241203-v2-backing-image-support.md` as historical context.
- Configurable backup chunk sizing is a separate feature documented in `enhancements/20250701-configurable-backup-block-size.md`.
