# Longhorn v1.12.2 Release Notes

Longhorn v1.12.2 introduces important improvements and bug fixes that enhance system quality, resilience, stability, and security.

We welcome feedback and contributions to help continuously improve Longhorn.

For terminology and context on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

> [!IMPORTANT]
> **Live upgrade of the V2 Data Engine from v1.12.2 to v1.13.0 is not supported**
>
> During a V2 Data Engine live upgrade, replicas are rebuilt while volumes are serving I/O. Because Longhorn v1.13.0 was released before several critical V2 rebuild and live-upgrade fixes (which are included in v1.12.2 and v1.13.1), `spdk_tgt` in the v1.13.0 instance-manager pods may crash or get stuck and prevent the upgrade from completing. These issues include [Instance Manager Pod Crashes](#instance-manager-pod-crashes), [Issue #14425](https://github.com/longhorn/longhorn/issues/14425), and other stability issues fixed in this release (see [Important Improvements and Fixes](#important-improvements-and-fixes)).
>
> - **Upgrading from v1.12.2 to v1.13.0:** Detach all V2 volumes before upgrading. The V2 instance-manager pods then restart with the new instance-manager image.
> - **Upgrading from v1.12.2 to v1.13.1 or later:** Live upgrade of the V2 Data Engine is supported. For instructions, see [V2 Instance Manager Upgrade](https://longhorn.io/docs/1.13.1/deploy/upgrade/v2-instance-upgrade/).
>
> **Periodic backups are recommended for V2 volumes**
>
> In the V2 Data Engine, if a snapshot deletion or system-snapshot purge fails or is interrupted partway through (for example, by a disk I/O error, exhausted metadata pages, an `spdk_tgt` crash, an instance-manager pod restart, or a node reboot), inconsistent blobstore metadata can cause V2 volume data corruption, `spdk_tgt` crashes, or a disk lvstore load failure ([Issue #14474](https://github.com/longhorn/longhorn/issues/14474)). To protect against potential data loss, configure periodic backups for V2 volumes and avoid restarting V2 instance-manager pods or rebooting nodes while snapshots are being deleted or purged.

## Breaking Changes

### Deprecation of Legacy V2 Linked Clone Volumes

V2 linked-clone volumes created in v1.12.0 or earlier are marked as legacy and deprecated starting in v1.12.1. The new linked-clone architecture introduced in [Issue #12552](https://github.com/longhorn/longhorn/issues/12552) is not compatible with the legacy design.

After upgrading to v1.12.1 or later, **legacy linked-clone volumes cannot be operated on except for detachment and deletion**.

To replace, create new linked-clone volumes from the same source volumes that back the legacy ones. As long as a legacy volume exists, its source volume is guaranteed to still be present, so you can create a replacement linked clone directly; no data copy is required.

For more information, see [Issue #12552](https://github.com/longhorn/longhorn/issues/12552).

## Important Improvements and Fixes

This release includes several important improvements and critical stability fixes.

### V1 Data Engine

#### IPv6 and Dual-Stack Support for Backing Images

The backing image manager and data source now follow Longhorn's IP family selection logic and serve on an IPv4 or IPv6 address that matches the cluster or storage network, including IPv4-first and IPv6-first dual-stack clusters. Previously they always used IPv4.

For more information, see [Issue #14148](https://github.com/longhorn/longhorn/issues/14148) and [Issue #13864](https://github.com/longhorn/longhorn/issues/13864).

#### Data Loss During Replica Rebuilds with Concurrent Unaligned Writes

Fixes a bug in which acknowledged writes could be silently lost during a replica rebuild. Concurrent writes smaller than 4 KiB to the same 4 KiB sector (for example, a database transaction log using 512-byte writes) could overwrite each other because the read-modify-write sequence was not locked. Longhorn now serializes these writes with a range lock. Users running such workloads on V1 volumes are strongly encouraged to upgrade.

For more information, see [Issue #14451](https://github.com/longhorn/longhorn/issues/14451) and [Issue #14447](https://github.com/longhorn/longhorn/issues/14447).

#### Replica Rebuild Failure Caused by a Lost gRPC TCP Keepalive

Fixes replica rebuilds that randomly failed on busy networks because a single lost TCP keepalive terminated the idle sync-agent gRPC connection after 20 seconds. The sync-agent now uses the operating system's default keepalive parameters.

For more information, see [Issue #13768](https://github.com/longhorn/longhorn/issues/13768) and [Issue #13703](https://github.com/longhorn/longhorn/issues/13703).

### V2 Data Engine

#### Dedicated CPU Core for the SPDK Admin Reactor

The first core of the SPDK CPU mask now runs only the admin reactor, and the other cores run the I/O pollers (NVMe-oF target poll groups and ublk target). This keeps I/O load from starving the admin reactor. With a single-core mask, the admin reactor and the pollers share the core.

> [!IMPORTANT]
> **For stability, configure at least 2 CPU cores for the V2 Data Engine. With a multi-core mask, one core is reserved for the admin reactor, so one fewer core serves I/O.**

For more information, see [Issue #14443](https://github.com/longhorn/longhorn/issues/14443) and [Issue #14190](https://github.com/longhorn/longhorn/issues/14190).

#### Configurable NVMe-TCP Initiator I/O Queue Count

You can now limit the number of I/O queues the kernel NVMe-TCP initiator creates for V2 volumes, instead of one per CPU core, to reduce memory use on high-core-count nodes. Set it globally with `default-nvme-tcp-nr-io-queues` (default `0`, the kernel default) or per volume with `nvmeTcpNrIoQueues`. Valid values are `0` or `1`-`128`, and changes take effect on the next attach.

For more information, see [Issue #13725](https://github.com/longhorn/longhorn/issues/13725) and [Issue #13706](https://github.com/longhorn/longhorn/issues/13706).

#### Instance Manager Pod Crashes

Fixes several critical issues in which `spdk_tgt` aborted and brought down the V2 instance-manager pod, taking every V2 volume on the node offline:

- **Replica rebuild finishing under I/O:** If suspending the engine frontend timed out, the rebuild switched the parent of the destination replica head while it was still serving I/O, causing the `bdev_channel_destroy_resource: Assertion 'TAILQ_EMPTY(&ch->io_submitted)' failed` abort. This is more likely when many replicas are rebuilt under load, such as during a live upgrade. See [Issue #14495](https://github.com/longhorn/longhorn/issues/14495) and [Issue #14411](https://github.com/longhorn/longhorn/issues/14411).
- **Replica rebuilds:** `spdk_tgt` could abort with `double free or corruption (fasttop)` during replica rebuilds. See [Issue #14484](https://github.com/longhorn/longhorn/issues/14484) and [Issue #14482](https://github.com/longhorn/longhorn/issues/14482).
- **Large-block reads in interrupt mode:** Large reads (for example, 1 MiB at a high queue depth) could flood the NVMe-oF TCP target with flush retries, and a retry could run after its connection was freed, causing the `spdk_for_each_channel: Assertion 'false' failed` abort. See [Issue #14162](https://github.com/longhorn/longhorn/issues/14162) and [Issue #14095](https://github.com/longhorn/longhorn/issues/14095).
- **Deleting a snapshot of an expanded volume:** Deleting a snapshot that is smaller than its child and not a multiple of 512 MiB could leave lvol metadata that SPDK fails to load, causing the instance-manager pod to crash-loop after the next restart or reboot. See [Issue #14347](https://github.com/longhorn/longhorn/issues/14347) and [Issue #14344](https://github.com/longhorn/longhorn/issues/14344).

#### Engine Fault Caused by a Replica Rebuild Destination Failure

Fixes a critical issue in which a failure while setting up a rebuild on the destination replica faulted the entire engine and recreated the frontend, even though healthy replicas remained. Now only the failed destination replica is marked `ERR`, and the engine, frontend, and I/O are preserved.

For more information, see [Issue #13780](https://github.com/longhorn/longhorn/issues/13780) and [Issue #13673](https://github.com/longhorn/longhorn/issues/13673).

### Storage Sharding (Experimental)

#### Erasure-Coded Volume Write Stall on arm64

Fixes a lost wakeup in the SPDK erasure-coding bdev that could stall writes and leave the SPDK target unresponsive, blocking volume deletion until the instance-manager pod was restarted. The race is more likely on arm64.

For more information, see [Issue #13895](https://github.com/longhorn/longhorn/issues/13895) and [Issue #13789](https://github.com/longhorn/longhorn/issues/13789).

## Installation

> [!IMPORTANT]
> **Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.12.2.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.12.2/deploy/install/) in the Longhorn documentation.

## Upgrade

> [!IMPORTANT]
> **Ensure that your cluster is running Kubernetes v1.25 or later before upgrading to Longhorn v1.12.2.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.12.2/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues in this release


### Feature

- [BACKPORT][v1.12.2][FEATURE] Backing image supports IPv6 and dual-stack IP families [14148](https://github.com/longhorn/longhorn/issues/14148) - @COLDTURNIP @yangchiu

### Improvement

- [BACKPORT][v1.12.2][IMPROVEMENT] Tuning CPU usage of SPDK and nvme-tcp for v2 engine [14443](https://github.com/longhorn/longhorn/issues/14443) - @yangchiu @shuo-wu
- [BACKPORT][v1.12.2][IMPROVEMENT] Skip the filesystem sync when suspending the frontend for replica rebuilding [14419](https://github.com/longhorn/longhorn/issues/14419) - @derekbit @roger-ryao
- [BACKPORT][v1.12.2][IMPROVEMENT] Sync v2 volume and engine image fields after upgrade [14318](https://github.com/longhorn/longhorn/issues/14318) - @davidcheng0922
- [BACKPORT][v1.12.2][IMPROVEMENT] Disk monitor repeatedly logs error when disk health collection fails [14300](https://github.com/longhorn/longhorn/issues/14300) - @derekbit
- [BACKPORT][v1.12.2][IMPROVEMENT] CSI ignores EC StorageClass parameters (silent replicated fallback) [13793](https://github.com/longhorn/longhorn/issues/13793) - @apoorvajagtap @chriscchien
- [BACKPORT][v1.12.2][IMPROVEMENT] CSI Resize may idle for a long time after volume clone or restore [14108](https://github.com/longhorn/longhorn/issues/14108) - @shuo-wu @roger-ryao
- [BACKPORT][v1.12.2][IMPROVEMENT] Enable CPU Isolation for V2 Data Engine [14034](https://github.com/longhorn/longhorn/issues/14034) - @derekbit @roger-ryao
- [BACKPORT][v1.12.2][IMPROVEMENT] backup target availability status metric [13981](https://github.com/longhorn/longhorn/issues/13981) - @yangchiu
- [BACKPORT][v1.12.2][IMPROVEMENT] (chart) Precedence of image.*.*.registry [13738](https://github.com/longhorn/longhorn/issues/13738) - @bachmanity1 @roger-ryao
- [BACKPORT][v1.12.2][IMPROVEMENT] v2 volumes: allow configuring the NVMe-TCP initiator I/O queue count (nr-io-queues) [13725](https://github.com/longhorn/longhorn/issues/13725) - @hookak @chriscchien

### Bug

- [BACKPORT][v1.12.2][BUG] `spdk_tgt` crashes with "double free or corruption (fasttop)" around replica rebuilds [14484](https://github.com/longhorn/longhorn/issues/14484) - @derekbit @chriscchien
- [BACKPORT][v1.12.2][BUG] Concurrent unaligned writes during replica rebuild lose data (unlocked read-modify-write in writeInWOMode) [14451](https://github.com/longhorn/longhorn/issues/14451) - @yangchiu @derekbit
- [BACKPORT][v1.12.2][BUG] v2 instance-manager is crashed by disk recovery failure in SPDK [14347](https://github.com/longhorn/longhorn/issues/14347) - @shuo-wu @chriscchien
- [BACKPORT][v1.12.2][BUG] a rebuilding replica sometimes disappears in the `Engine.Status.ReplicaModeMap` [13917](https://github.com/longhorn/longhorn/issues/13917) - @mantissahz @roger-ryao
- [BACKPORT][v1.12.2][BUG] Concurrent volume attachments can create multiple NVMe-oF transports and crash spdk_tgt [14400](https://github.com/longhorn/longhorn/issues/14400) - @derekbit @chriscchien
- [BACKPORT][v1.12.2][BUG] V2 instance manager live upgrade stuck in  relocating-engines  because the EngineFrontend switchover keeps retrying  promoting  against a recreated target engine [14425](https://github.com/longhorn/longhorn/issues/14425) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.12.2][BUG] V2 instance-manager `spdk_tgt` allocates its hugepages from another pod's hugetlbfs mount (via `/host`), blocking that pod's teardown [14430](https://github.com/longhorn/longhorn/issues/14430) - @yangchiu @derekbit
- [BACKPORT][v1.12.2][BUG] A stalled NVMe device makes engine frontends of unrelated v2 volumes fail validation and be recreated [14373](https://github.com/longhorn/longhorn/issues/14373) - @hookak @roger-ryao
- [BACKPORT][v1.12.2][BUG] nvme list zombie processes leak when NVMe admin queue returns EAGAIN (v2 data engine) [13764](https://github.com/longhorn/longhorn/issues/13764) - @chriscchien
- [BACKPORT][v1.12.2][BUG] SystemBackup stuck in `CreatingVolumeBackups` on v1.12.1: controller either silently stops reconciling after all volume backups complete, or loops forever on `snapshot not found` (auto-cleanup race) [14375](https://github.com/longhorn/longhorn/issues/14375) - @yangchiu @c3y1huang
- [BACKPORT][v1.12.2][BUG] v2 spdk_tgt aborts with assertion in blob_insert_cluster_msg due to an extent page race [14370](https://github.com/longhorn/longhorn/issues/14370) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.12.2][BUG] Fast replica rebuild skips a snapshot file that was changed by purge/coalesce (stale .img.checksum), leaving the rebuilt replica missing data; snapshot-data-integrity: fast-check does not detect it [14335](https://github.com/longhorn/longhorn/issues/14335) - @derekbit @chriscchien
- [BACKPORT][v1.12.2][BUG] Transient status RPC failure marks healthy replica failed and can fault a volume [14332](https://github.com/longhorn/longhorn/issues/14332) - @yangchiu
- [BACKPORT][v1.12.2][BUG] Disk health data never collected for V1 filesystem disks whose path is not itself a mount point ("mount path ... not found") [14311](https://github.com/longhorn/longhorn/issues/14311) - @derekbit @chriscchien
- [BACKPORT][v1.12.2][BUG] Test case `Test Encrypted RWO Block Volume Online Expansion` fails [14296](https://github.com/longhorn/longhorn/issues/14296) - @yangchiu @mantissahz
- [BACKPORT][v1.12.2][BUG] Force-deleted pod VolumeAttachment cleanup ignores "Waiting for detach" events (Kubernetes v1.35.9+, v1.36.4+, v1.37) [14218](https://github.com/longhorn/longhorn/issues/14218) - @roger-ryao
- [BUG] csi-resizer fails to start with "unrecognized feature gate: RecoverVolumeExpansionFailure" in v1.12.x-head with csi-resizer:v2.3.0 [14249](https://github.com/longhorn/longhorn/issues/14249) - @c3y1huang @roger-ryao
- [BACKPORT][v1.12.2][BUG] V2 DR volume restore does not retry when backupstore lock is held [14220](https://github.com/longhorn/longhorn/issues/14220) - @derekbit @roger-ryao
- [BACKPORT][v1.12.2][BUG] All v1 volume I/O stalls silently with longhorn-engine v1.7.1 through v1.9.2 on Rocky Linux 9.7 / RKE2 (iSCSI login timeout, attach/detach loop); engine v1.7.0 and v1.6.4 work on every platform version [13927](https://github.com/longhorn/longhorn/issues/13927) - @davidcheng0922
- [BACKPORT][v1.12.2][BUG] Sharded/EC volume: writes stall to ~0 and wedge the SPDK target on arm64/AIO, blocking volume deletion; plus CSI drops EC StorageClass params [13895](https://github.com/longhorn/longhorn/issues/13895) - @c3y1huang @roger-ryao
- [BACKPORT][v1.12.2][BUG] Volume expansion snapshot CR name expand-<size> collides across volumes [13824](https://github.com/longhorn/longhorn/issues/13824) - @derekbit @roger-ryao
- [BACKPORT][v1.12.2][BUG] Longhorn v2 engine crashes on large-block reads in interrupt mode - spdk_for_each_channel "Assertion 'false' failed" [14162](https://github.com/longhorn/longhorn/issues/14162) - @derekbit @chriscchien
- [BACKPORT][v1.12.2][BUG] v2 volume gets stuck in `Attaching` in an IPv6 storage network environment [13955](https://github.com/longhorn/longhorn/issues/13955) - @yangchiu @derekbit
- [BACKPORT][v1.12.2][BUG] v1.11.3 regenerates the webhook CA on upgrade from an ECDSA (dynamiclistener) CA, deadlocking every longhorn-manager [14192](https://github.com/longhorn/longhorn/issues/14192) - 
- [BACKPORT][v1.12.2][BUG] SystemBackup fails when a snapshot has an empty status.creationTime [14140](https://github.com/longhorn/longhorn/issues/14140) - @yangchiu
- [BACKPORT][v1.12.2][BUG] Longhorn may not reject expansion requests when the volume clone is in-progress [14066](https://github.com/longhorn/longhorn/issues/14066) - @yangchiu @shuo-wu
- [BACKPORT][v1.12.2][BUG] invalid block disks should not block Longhorn system uninstallation [13925](https://github.com/longhorn/longhorn/issues/13925) - @yangchiu @apoorvajagtap
- [BACKPORT][v1.12.2][BUG] deleting nodes.longhorn.io failed due to KubernetesNodeGone [14029](https://github.com/longhorn/longhorn/issues/14029) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.12.2][BUG] v1.12.1 chart: new default-on `networkPolicies.restrictInternalTraffic` silently breaks Prometheus scraping of longhorn-manager (metrics/alerting blackout on patch upgrade) [13741](https://github.com/longhorn/longhorn/issues/13741) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.12.2][BUG] V2 replica rebuild destination failure faults the entire engine [13780](https://github.com/longhorn/longhorn/issues/13780) - @roger-ryao
- [BACKPORT][v1.12.2][BUG] NodeStageVolume can trigger destructive mkfs on existing volume during temporary I/O errors, risking data loss [14060](https://github.com/longhorn/longhorn/issues/14060) - 
- [BACKPORT][v1.12.2][BUG] Test case `Test V2 Volume Engine Live Switchover` may fail on v1.13.x-head [13987](https://github.com/longhorn/longhorn/issues/13987) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.12.2][BUG] instance-manager crashes with "concurrent map iteration and map write" in ProcessList (Process.Conditions shared with the response) [14115](https://github.com/longhorn/longhorn/issues/14115) - @derekbit @chriscchien
- [BACKPORT][v1.12.2][BUG] SystemRestore job ignores the registry-secret setting [13969](https://github.com/longhorn/longhorn/issues/13969) - @chriscchien @bachmanity1
- [BACKPORT][v1.12.2][BUG] DR replicas break [14057](https://github.com/longhorn/longhorn/issues/14057) - @derekbit @chriscchien
- [BACKPORT][v1.12.2][BUG] Cloned volume stuck "not ready for workloads" after the clone finishes (v1.12.0, v1 engine) [13978](https://github.com/longhorn/longhorn/issues/13978) - @yangchiu @chriscchien
- [BACKPORT][v1.12.2][BUG] Test case `test_csi_block_volume_online_expansion` fails with 'assert md5sum: == ...' on v2 volume (AMD64 only) [14050](https://github.com/longhorn/longhorn/issues/14050) - @derekbit @roger-ryao
- [BACKPORT][v1.12.2][BUG] Runtime container images contain development (-devel) packages [14051](https://github.com/longhorn/longhorn/issues/14051) - 
- [BACKPORT][v1.12.2][BUG] Adding V2 disk using the "Default Data Path" /dev/disk/by-id/scsi-* path fails [13870](https://github.com/longhorn/longhorn/issues/13870) - @davidcheng0922 @roger-ryao
- [BACKPORT][v1.12.2][BUG] Request Schema in Upgrade Responder is Outdate [14049](https://github.com/longhorn/longhorn/issues/14049) - @mantissahz @roger-ryao
- [BACKPORT][v1.12.2][BUG] v1 replica rebuild fails after a single gRPC TCP keepalive is lost [13768](https://github.com/longhorn/longhorn/issues/13768) - @chriscchien
- [BACKPORT][v1.12.2][BUG] test `test_single_replica_failed_during_engine_start` fails [13862](https://github.com/longhorn/longhorn/issues/13862) - @davidcheng0922
- [BACKPORT][v1.12.2][BUG] Test case `V2 Volume Should Cleanup Resources When Instance Manager Is Deleted` fails [13988](https://github.com/longhorn/longhorn/issues/13988) - @roger-ryao @carterli0407-cell
- [BACKPORT][v1.12.2][BUG] v2 volume expansion is reported complete before the frontend dm device is resized [14002](https://github.com/longhorn/longhorn/issues/14002) - @derekbit @chriscchien
- [BACKPORT][v1.12.2][BUG] Terminal workload pods cause NodePublishVolume to abort with "no Pending workload pods" [13995](https://github.com/longhorn/longhorn/issues/13995) - @yangchiu
- [BACKPORT][v1.12.2][BUG] v1 engine never starts: a stale `stopped` process record makes createInstance a silent no-op, volume stuck in `attaching` forever [13850](https://github.com/longhorn/longhorn/issues/13850) - @derekbit @roger-ryao
- [BACKPORT][v1.12.2][BUG] v1.12.1 default NetworkPolicies miss legitimate non-pod-labeled and host-originated callers, silently breaking CSI attach/detach [13804](https://github.com/longhorn/longhorn/issues/13804) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.12.2][BUG] Recurring-job pods report success after startup or volume execution errors [13752](https://github.com/longhorn/longhorn/issues/13752) - @christophersherman @roger-ryao
- [BACKPORT][v1.12.2][BUG] Test case `Power Off Replica Node Should Not Rebuild New Replica On Same Node` fails [13819](https://github.com/longhorn/longhorn/issues/13819) - @yangchiu @derekbit
- [BACKPORT][v1.12.2][BUG] V1 volumes not rebuilding after cluster shutdown [13751](https://github.com/longhorn/longhorn/issues/13751) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.12.2][BUG] v2: spdk_tgt aborts on bdev_channel_destroy_resource assertion when rebuild finish sets the dst replica parent under I/O [14495](https://github.com/longhorn/longhorn/issues/14495) - @davidcheng0922 @chriscchien

### Performance

- [BACKPORT][v1.12.2][IMPROVEMENT] nsmounter: kubelet PID lookup on Talos takes seconds per call [14174](https://github.com/longhorn/longhorn/issues/14174) - @yangchiu

### Resilience

- [BACKPORT][v1.12.2][BUG] V2 instance-manager liveness probe errors ('test: -eq: unary operator expected') -> self-kill -> node-wide replica fault under rebuild load [13959](https://github.com/longhorn/longhorn/issues/13959) - @yangchiu @mantissahz
- [BACKPORT][v1.12.2][BUG] V2 Instance Manager panics in backupstore when S3 volume.cfg is missing, taking all node volumes offline [13805](https://github.com/longhorn/longhorn/issues/13805) - @mantissahz @chriscchien

### Stability

- [BACKPORT][v1.12.2][BUG] Admission webhook calls for one resource type (backups.longhorn.io) fail with instant EOF, zero network I/O — deterministic, fleet-wide, persists across apiserver restarts and egress-selector modes [14316](https://github.com/longhorn/longhorn/issues/14316) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.12.2][BUG] Recurring snapshot-cleanup aborts the entire run when any volume's replica is rebuilding [13781](https://github.com/longhorn/longhorn/issues/13781) - @derekbit @chriscchien
- [BACKPORT][v1.12.2][BUG] V2 backup readers race snapshot cleanup and panic the instance manager [14021](https://github.com/longhorn/longhorn/issues/14021) - @yangchiu
- [BACKPORT][v1.12.2][IMPROVEMENT] Avoid re-sending an unchanged Node status update [14145](https://github.com/longhorn/longhorn/issues/14145) - @hookak @chriscchien

### Misc

- [BACKPORT][v1.12.2][TASK] Add Helm chart image HIP-0015 annotations [14204](https://github.com/longhorn/longhorn/issues/14204) - @roger-ryao @carterli0407-cell
- [BACKPORT][v1.12.2][BUG] Live migration and replica rebuild enter circular wait after nodes are uncordoned [14154](https://github.com/longhorn/longhorn/issues/14154) - @chriscchien @carterli0407-cell
- [BACKPORT][v1.12.2][BUG] instance-manager panics (nil pointer) in sync.(*Task).HashSnapshotStatus when a replica is rebuilding: shadowed err in isRebuilding branch [14252](https://github.com/longhorn/longhorn/issues/14252) - @chriscchien
- [BACKPORT][v1.12.2][BUG] RWX volume mounts are delayed up to 2 minutes when the share manager is stopped and started repeatedly (e.g. by a CronJob) [14178](https://github.com/longhorn/longhorn/issues/14178) - @roger-ryao
- [BACKPORT][v1.12.2][BUG] Longhorn block disk remains Ready=False and Schedulable=False when NVMe device is bound to vfio-pci [13934](https://github.com/longhorn/longhorn/issues/13934) - @derekbit @chriscchien
- [BACKPORT][v1.12.2][IMPROVEMENT] Chart value to allow metrics scrapers through the longhorn-manager NetworkPolicy [13989](https://github.com/longhorn/longhorn/issues/13989) - @yangchiu
- [BACKPORT][v1.12.2][BUG] CSI method-level request logs bypass secret sanitization [13727](https://github.com/longhorn/longhorn/issues/13727) - @yangchiu

## Contributors

- @COLDTURNIP 
- @apoorvajagtap 
- @bachmanity1 
- @c3y1huang 
- @carterli0407-cell 
- @chriscchien 
- @christophersherman 
- @davidcheng0922 
- @derekbit 
- @hookak 
- @innobead 
- @mantissahz 
- @roger-ryao 
- @shuo-wu 
- @yangchiu 
- @sushant-suse
- @rebeccazzzz
- @forbesguthrie
- @asettle
