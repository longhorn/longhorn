# Longhorn v1.13.1 Release Notes

Longhorn v1.13.1 introduces important improvements and bug fixes that enhance system quality, resilience, stability, and security.

We welcome feedback and contributions to help continuously improve Longhorn.

For terminology and context on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

> [!IMPORTANT]
> **Live upgrade of the V2 Data Engine to v1.13.1 is supported from v1.12.2 or later.**
>
> Upgrades from earlier versions, such as Longhorn v1.12.0 and v1.12.1, do not support V2 Data Engine live upgrade. Detach all V2 volumes and ensure their replicas are stopped before upgrading from those versions. For instructions, see [V2 Data Engine Instance Manager Upgrade](https://longhorn.io/docs/1.13.1/deploy/upgrade/v2-instance-upgrade/).
>
> A live upgrade to v1.13.0 deleted user-created snapshots of V2 volumes. This is fixed in Longhorn v1.13.1. See [User Snapshots Deleted During Live Upgrade](#user-snapshots-deleted-during-live-upgrade).
>
> **Periodic backups are recommended for V2 volumes.**
>
> In the V2 Data Engine, a snapshot deletion or system-snapshot purge that fails or is interrupted (for example, by a disk I/O error, an instance-manager pod restart, or a node reboot) can leave inconsistent blobstore metadata. This can cause V2 volume data corruption, `spdk_tgt` crashes, or a disk lvstore load failure ([Issue #14474](https://github.com/longhorn/longhorn/issues/14474)). Configure periodic backups for V2 volumes, and avoid restarting V2 instance-manager pods or rebooting nodes while snapshots are being deleted or purged.

## Breaking Changes

### Deprecation of Legacy V2 Linked Clone Volumes

V2 linked-clone volumes created in v1.12.0 or earlier are marked as legacy and deprecated starting in v1.12.1. The new linked-clone architecture introduced in [Issue #12552](https://github.com/longhorn/longhorn/issues/12552) is not compatible with the legacy design.

After upgrading to v1.12.1 or later, **legacy linked-clone volumes cannot be operated on except for detachment and deletion**.

To replace, create new linked-clone volumes from the same source volumes that back the legacy ones. As long as a legacy volume exists, its source volume is guaranteed to still be present, so you can create a replacement linked clone directly; no data copy is required.

For more information, see [Issue #12552](https://github.com/longhorn/longhorn/issues/12552).

### V1 iSCSI Rule Removed From the Default Instance Manager NetworkPolicy

With `networkPolicies.restrictInternalTraffic=true` and an empty `networkPolicies.v1DataEngineInitiatorSourceCIDRs`, the instance-manager NetworkPolicy no longer renders a TCP/3260 rule. Previously, the rule had no source restriction, so any pod that could reach an instance-manager pod could log in to the V1 iSCSI target. The V1 initiator runs on the same node as its target, and Kubernetes NetworkPolicy always allows traffic from the pod's own node, so the default configuration is not affected.

> [!IMPORTANT]
> If your CNI or mesh rewrites the source address of host traffic (for example, Istio Ambient), or if initiators on other hosts connect to the iSCSI frontend, add their source CIDRs to `networkPolicies.v1DataEngineInitiatorSourceCIDRs` before you upgrade. Otherwise, V1 volumes can fail to attach.

The rule is also removed from `longhorn.yaml` and `longhorn-okd.yaml`. Manifest installations that need the rule must apply a separate NetworkPolicy for TCP/3260.

For more information, see:

- [Issue #14416](https://github.com/longhorn/longhorn/issues/14416)
- [Network Policy](https://longhorn.io/docs/1.13.1/advanced-resources/security/network-policy)
- [Troubleshooting volume attachment stuck due to CNI NetworkPolicies](https://longhorn.io/kb/troubleshooting-volume-attachment-stuck-cni-networkpolicies)

## Important Improvements and Fixes

This release includes several important improvements and critical stability fixes.

### V1 Data Engine

#### Data Loss During Replica Rebuilds With Concurrent Unaligned Writes

A V1 volume no longer loses data when concurrent writes that are not aligned to 4 KiB hit the same 4 KiB block while a replica is rebuilding. Previously, the later write could overwrite an already acknowledged write with stale data.

For more information, see [Issue #14447](https://github.com/longhorn/longhorn/issues/14447).

#### Missing Data After Fast Replica Rebuild

Fast replica rebuild no longer skips a snapshot file that a snapshot purge has changed. Previously, the purge left the old checksum file in place, so the rebuild skipped the file and the rebuilt replica was missing data.

For more information, see [Issue #14096](https://github.com/longhorn/longhorn/issues/14096).

#### Instance Manager Panic During Replica Rebuild

The V1 instance manager no longer panics when it checks snapshot checksum status while a replica is rebuilding. Previously, the panic took down every V1 engine on the node.

For more information, see [Issue #14251](https://github.com/longhorn/longhorn/issues/14251).

#### iSCSI Login Deadlock

A V1 volume now attaches even when the kernel reads from the device during iSCSI login. Previously, the login could time out, and the volume kept detaching and reattaching.

For more information, see [Issue #13606](https://github.com/longhorn/longhorn/issues/13606).

#### iSCSI Exposed on IPv4 in IPv6-First Dual-Stack Clusters

A V1 volume is now exposed over iSCSI on the primary IP address of the instance-manager pod. Previously, when Longhorn was installed as IPv6 single-stack in an IPv6-first dual-stack cluster, the volume could be exposed on the pod's IPv4 address.

For more information, see [Issue #14334](https://github.com/longhorn/longhorn/issues/14334).

### V2 Data Engine

#### User Snapshots Deleted During Live Upgrade

A V2 Data Engine live upgrade now keeps the user-created snapshots of V2 volumes. Previously, a live upgrade to v1.13.0 deleted them.

For more information, see [Issue #14582](https://github.com/longhorn/longhorn/issues/14582).

#### Instance Manager Pod Crashes

`spdk_tgt` no longer crashes in the following cases. Each crash restarted every V2 replica and engine on the node.

- Double free in the NVMe-oF unmap path. See [Issue #14482](https://github.com/longhorn/longhorn/issues/14482).
- Assertion in `bdev_channel_destroy_resource` when a replica's parent was changed under I/O after a suspend timeout. See [Issue #14411](https://github.com/longhorn/longhorn/issues/14411).
- Race in `blob_insert_cluster_msg` when a snapshot was taken while writes allocated new clusters. See [Issue #14353](https://github.com/longhorn/longhorn/issues/14353).
- Multiple NVMe-oF transports created by concurrent expose requests. See [Issue #14399](https://github.com/longhorn/longhorn/issues/14399).
- Large block reads in interrupt mode. See [Issue #14095](https://github.com/longhorn/longhorn/issues/14095).

#### Disks Offline After Deleting a Snapshot of an Expanded Volume

Deleting or purging a snapshot no longer crashes `spdk_tgt` when the volume was expanded after the snapshot was taken and the snapshot size is not a multiple of 512 MiB. Previously, `spdk_tgt` crashed on every disk load until the metadata was repaired, and every V2 disk on the node stayed offline.

For more information, see [Issue #14344](https://github.com/longhorn/longhorn/issues/14344).

#### Replica Rebuild Under Load and With Snapshots

Three problems with V2 replica rebuilds are resolved:

- Heavy writes during replica rebuilds no longer deadlock I/O on every V2 volume on the node. Previously, I/O stayed stopped until the instance-manager pod was deleted. On an upgraded cluster, also set the [larger iobuf pool](#larger-default-iobuf-large-pool-size), which the fix was tested with. See [Issue #14589](https://github.com/longhorn/longhorn/issues/14589).
- A rebuild that starts during a snapshot operation no longer deadlocks with it. Previously, the rebuild failed after about 3 minutes and the volume's I/O stayed suspended. See [Issue #14619](https://github.com/longhorn/longhorn/issues/14619).
- A snapshot taken a few seconds before a rebuild starts is now kept. Previously, Longhorn deleted it when the rebuild finished, and restoring from its CSI VolumeSnapshot failed. See [Issue #14596](https://github.com/longhorn/longhorn/issues/14596).

#### Dedicated CPU Core for the SPDK Admin Reactor

When the V2 Data Engine is assigned two or more CPU cores, the lowest core now runs only the SPDK admin reactor, which handles management RPCs, and the remaining cores run the I/O pollers. Heavy I/O no longer delays RPC processing. With the default two-core mask, I/O now runs on one core instead of two; add cores to `data-engine-cpu-mask` if the node needs more I/O capacity.

> [!IMPORTANT]
> A minimum of 2 CPU cores is recommended for the V2 Data Engine. With a single core, the admin reactor and the I/O pollers share it, so heavy I/O can delay RPC processing and cause increased latency, timeouts, and instability.

For more information, see [Issue #14190](https://github.com/longhorn/longhorn/issues/14190).

#### Larger Default iobuf Large Pool Size

The default value of `data-engine-iobuf-large-pool-size` is now `6144` instead of `1024`, which avoids running out of large buffers under heavy I/O and during concurrent replica rebuilds. An upgraded cluster keeps its current value; set it to `6144` to use the larger pool.

> [!IMPORTANT]
> On hosts with 4 or more NUMA nodes, or if you have lowered `Data Engine Memory Size`, `spdk_tgt` might not start with a value of `6144`. In that case, increase `Data Engine Memory Size` and the hugepages on the host, or set this value closer to `1024`.

For more information, see [Issue #14589](https://github.com/longhorn/longhorn/issues/14589) and [Data Engine iobuf Large Pool Size](https://longhorn.io/docs/1.13.1/references/settings/#data-engine-iobuf-large-pool-size).

#### Volume Expansion

Changes to V2 volume expansion:

- Expanding a replicated V2 volume no longer tears down and recreates the NVMe-oF target, so the frontend stays connected. See [Issue #14580](https://github.com/longhorn/longhorn/issues/14580).
- Expanding a volume while it is attaching no longer times out. See [Issue #14521](https://github.com/longhorn/longhorn/issues/14521).
- During a replica rebuild, an expansion is reported complete only after the block device is resized. See [Issue #13993](https://github.com/longhorn/longhorn/issues/13993).
- Expanding a V2 encrypted volume created in v1.12.1 or later by 16 MiB or less (the LUKS2 header size) is now rejected. See [Issue #14521](https://github.com/longhorn/longhorn/issues/14521).

#### Settings and Images Synced During Instance Manager Upgrade

During a V2 instance manager upgrade:

- The `spec.image` and `status.currentImage` of replicated V2 volumes, engines, and replicas now show the image of the instance manager they run on. See [Issue #14317](https://github.com/longhorn/longhorn/issues/14317).
- The `data-engine-log-level` and `data-engine-log-flags` settings now apply to the new instance manager. Previously, it logged at `DEBUG`, which slowed replica rebuilds and could stall the upgrade. See [Issue #14390](https://github.com/longhorn/longhorn/issues/14390).

#### DR Volume Faulted on Backupstore Lock Conflict

A V2 DR volume now retries the restore when another operation, such as a backup deletion, holds the backupstore lock. Previously, the volume became `Faulted`.

For more information, see [Issue #14085](https://github.com/longhorn/longhorn/issues/14085).

#### Hugepages Allocated From Another Pod's hugetlbfs

The V2 instance manager now allocates hugepages only from its own hugepages volume. Previously, `spdk_tgt` could take them from another pod's hugepages volume, and that pod then stayed in `Terminating` when it was deleted.

For more information, see [Issue #14340](https://github.com/longhorn/longhorn/issues/14340).

### Node and Disk Management

#### Disk Config Regenerated on an Unmounted Disk Path

Longhorn no longer creates a new disk config for a disk that already has a recorded UUID. If the disk's filesystem is not mounted (for example, after a node reboot), the disk stays `Ready=False` with reason `DiskFilesystemChanged` until the filesystem is mounted. Previously, Longhorn wrote a new disk config to whatever was behind the path, such as the root filesystem.

For more information, see [Issue #14102](https://github.com/longhorn/longhorn/issues/14102).

#### Backing Image Manager Not Restarted After Disk Recovery

When a disk becomes `Ready` again (for example, after its filesystem is remounted), Longhorn now recreates the backing image manager pod on that disk. Previously, the pod could not see the backing image files on the remounted disk.

For more information, see [Issue #14111](https://github.com/longhorn/longhorn/issues/14111).

#### Block-Type Disks Unschedulable After Node Reboot

V2 block-type disks on virtio devices no longer stay `Unschedulable` after a node reboot. Previously, Longhorn tried to load the disk before the device was ready and did not retry.

For more information, see [Issue #12197](https://github.com/longhorn/longhorn/issues/12197).

### General

#### Unnecessary Rebuilds After Transient Failures

Two short-lived failures no longer cause Longhorn to rebuild healthy replicas:

- When a longhorn-manager pod is briefly not ready, such as during a restart or an upgrade, replica auto-balance now waits up to 3 minutes before it rebuilds the replicas of that node on other nodes. See [Issue #13941](https://github.com/longhorn/longhorn/issues/13941).
- When a request for a replica's snapshot purge or restore status fails on a dropped connection, Longhorn now retries the request. Previously, one failed request marked the replica as failed, and a volume with a single replica could become `Faulted`. See [Issue #13943](https://github.com/longhorn/longhorn/issues/13943).

#### Volume Attachment Cleanup for Force-Deleted Pods on Newer Kubernetes

Longhorn now removes the volume attachment of a force-deleted pod when Kubernetes reports `Waiting for detach` instead of `Multi-Attach error`. Kubernetes v1.35.9 and later, v1.36.4 and later, and v1.37 report the new message. Previously, Longhorn did not recognize it, so the replacement pod waited about 6 minutes for the volume.

For more information, see [Issue #14182](https://github.com/longhorn/longhorn/issues/14182).

#### Volume Clone With Mismatched Encryption Settings

Longhorn now rejects a volume clone when one volume is encrypted and the other is not. Previously, cloning an unencrypted PVC into an encrypted StorageClass completed, but the new volume could not be mounted.

For more information, see [Issue #14222](https://github.com/longhorn/longhorn/issues/14222).

#### Topology Spread Constraints for Longhorn Global Manager

The Helm chart adds `longhornGlobalManager.topologySpreadConstraints` (default `[]`) so the `longhorn-global-manager` replicas can be spread across zones or nodes.

For more information, see [Issue #14224](https://github.com/longhorn/longhorn/issues/14224) and [Longhorn Global Manager Settings](https://longhorn.io/docs/1.13.1/references/helm-values/#longhorn-global-manager-settings).

#### Development Packages Removed From Runtime Images

The instance-manager image no longer includes the `-devel` packages and build tools that were only needed at build time. This reduces image size and the number of packages reported by vulnerability scanners.

For more information, see [Issue #14135](https://github.com/longhorn/longhorn/issues/14135).

## Installation

> [!IMPORTANT]
> **Ensure that your cluster is running Kubernetes v1.34 or later before installing Longhorn v1.13.1.**

You can install Longhorn using a variety of tools, including Rancher, kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.13.1/deploy/install/) in the Longhorn documentation.

## Upgrade

> [!IMPORTANT]
> **Ensure that your cluster is running Kubernetes v1.34 or later before upgrading to Longhorn v1.13.1.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.13.1/deploy/upgrade/) in the Longhorn documentation.

Automated pre-upgrade checks do not cover all scenarios. Before upgrading to v1.13.1, review the manual checks in [Important Notes](https://longhorn.io/docs/1.13.1/important-notes/#manual-checks-before-upgrade). For V2 Data Engine volumes, check the [V2 live upgrade prerequisites](https://longhorn.io/docs/1.13.1/deploy/upgrade/v2-instance-upgrade/#prerequisites). If your deployment does not meet these prerequisites, detach all V2 volumes and ensure their replicas are stopped before upgrading.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues in this release

### Improvement
- [BACKPORT][v1.13.1][IMPROVEMENT] Sync v2 volume and engine image fields after upgrade [14319](https://github.com/longhorn/longhorn/issues/14319) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.13.1][IMPROVEMENT] Expand v2 RAID1 volumes without tearing down the engine RAID bdev [14581](https://github.com/longhorn/longhorn/issues/14581) - @derekbit @roger-ryao
- [BACKPORT][v1.13.1][IMPROVEMENT] Reload BackingImageManager when disk configuration drift detected. [14112](https://github.com/longhorn/longhorn/issues/14112) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.13.1][IMPROVEMENT] Chart: option to drop the open TCP/3260 rule from the instance-manager NetworkPolicy [14467](https://github.com/longhorn/longhorn/issues/14467) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.13.1][IMPROVEMENT] Add a disk condition "Initialized" to distinguish disk identity from disk readiness [14103](https://github.com/longhorn/longhorn/issues/14103) - @mantissahz @chriscchien
- [BACKPORT][v1.13.1][IMPROVEMENT] Sync V2 log settings to instance manager during in-place upgrade [14391](https://github.com/longhorn/longhorn/issues/14391) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.13.1][IMPROVEMENT] Tuning CPU usage of SPDK and nvme-tcp for v2 engine [14444](https://github.com/longhorn/longhorn/issues/14444) - @yangchiu @shuo-wu
- [BACKPORT][v1.13.1][IMPROVEMENT] Skip the filesystem sync when suspending the frontend for replica rebuilding [14418](https://github.com/longhorn/longhorn/issues/14418) - @derekbit @roger-ryao
- [BACKPORT][v1.13.1][IMPROVEMENT] CSI ControllerPublishVolume takes at least 2 s because the volume state is polled every 2 s [14200](https://github.com/longhorn/longhorn/issues/14200) - @chriscchien
- [BACKPORT][v1.13.1][IMPROVEMENT] Expose topologySpreadConstraints for longhorn-global-manager in the Helm chart [14236](https://github.com/longhorn/longhorn/issues/14236) - @yangchiu

### Bug
- [CI] CSI snapshotter tests fail on v1.13.x due to missing CSI snapshotter v8.7.1 Git [14644](https://github.com/longhorn/longhorn/issues/14644) - 
- [BACKPORT][v1.13.1][BUG] v2 volume deadlocks when a replica rebuild starts while a user snapshot is being created, and the frontend can stay suspended [14620](https://github.com/longhorn/longhorn/issues/14620) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.13.1][BUG] v2 snapshot is auto-deleted when a replica rebuild starts right after it [14604](https://github.com/longhorn/longhorn/issues/14604) - @davidcheng0922 @roger-ryao
- [BACKPORT][v1.13.1][BUG] V2 I/O stops on all volumes when replicas rebuild under heavy write load and SPDK stays stuck until the instance-manager is restarted [14593](https://github.com/longhorn/longhorn/issues/14593) - @derekbit @chriscchien
- [BACKPORT][v1.13.1][BUG] v2 clone gets stuck forever after one failed deep copy: stale replica clone error blocks retries,and a Failed clone never re-attaches its source [14531](https://github.com/longhorn/longhorn/issues/14531) - @shuo-wu @roger-ryao
- [BACKPORT][v1.13.1][BUG] v2 migration EngineFrontend is not reconnected after the migration engine restarts on a new port [14579](https://github.com/longhorn/longhorn/issues/14579) - @c3y1huang @chriscchien
- [BACKPORT][v1.13.1][BUG] v2 live upgrade deletes user created snapshots [14584](https://github.com/longhorn/longhorn/issues/14584) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.13.1][BUG] Block-type disks become `Unschedulable` after node reboot on HAL [14592](https://github.com/longhorn/longhorn/issues/14592) - @davidcheng0922 @roger-ryao
- [BACKPORT][v1.13.1][BUG] Snapshot CR deletion denied by the validation webhook when the snapshot name exceeds 63 characters [14563](https://github.com/longhorn/longhorn/issues/14563) - @derekbit @chriscchien
- [BACKPORT][v1.13.1][BUG] Test case `test_recurring_job_snapshot_cleanup` fails with v2 data engine because the expected system snapshot isn't created [14535](https://github.com/longhorn/longhorn/issues/14535) - @yangchiu @mantissahz
- [BACKPORT][v1.13.1][BUG] Test case `test_system_backup_and_restore_volume_with_backingimage` fails with `CIFS` backup store [14568](https://github.com/longhorn/longhorn/issues/14568) - @yangchiu @derekbit
- [BACKPORT][v1.13.1][BUG] Test case `test_system_backup_delete_when_other_system_backup_using_name_as_prefix` fails with `CIFS` backup store [14567](https://github.com/longhorn/longhorn/issues/14567) - @yangchiu @derekbit
- [BACKPORT][v1.13.1][BUG] Test case `test_engine_live_upgrade` fails in `dual-stack-ipv6-first` environment [14559](https://github.com/longhorn/longhorn/issues/14559) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.13.1][BUG] SingleStack Longhorn in IPv6 within Dual Stack IPv6 kubernetes is working with IPv4 [14433](https://github.com/longhorn/longhorn/issues/14433) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.13.1][BUG] V2 volume expansion never completes when expand request races with attach [14538](https://github.com/longhorn/longhorn/issues/14538) - @davidcheng0922 @roger-ryao
- [BACKPORT][v1.13.1][BUG] v2 volume expansion is reported complete before the frontend dm device is resized [14012](https://github.com/longhorn/longhorn/issues/14012) - @davidcheng0922 @roger-ryao
- [BACKPORT][v1.13.1][BUG] Best-effort zone balancing stalls at 3+1 due to shadowed adjustCount [14450](https://github.com/longhorn/longhorn/issues/14450) - @yangchiu @c3y1huang
- [BACKPORT][v1.13.1][BUG] Test case `Activate Degraded DR Volume With Failed Replica Node` fails with v2 data engine [14423](https://github.com/longhorn/longhorn/issues/14423) - @yangchiu @c3y1huang
- [BACKPORT][v1.13.1][BUG] Transient longhorn-manager pod unreadiness makes replica auto-balance rebuild healthy replicas [14472](https://github.com/longhorn/longhorn/issues/14472) - @yangchiu
- [BACKPORT][v1.13.1][BUG] Test case `Test Incremental Restore` may fail with v2 data engine [13997](https://github.com/longhorn/longhorn/issues/13997) - @yangchiu @c3y1huang
- [BACKPORT][v1.13.1][BUG] v2: spdk_tgt aborts on bdev_channel_destroy_resource assertion when rebuild finish sets the dst replica parent under I/O [14412](https://github.com/longhorn/longhorn/issues/14412) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.13.1][BUG] Concurrent volume attachments can create multiple NVMe-oF transports and crash spdk_tgt [14401](https://github.com/longhorn/longhorn/issues/14401) - @derekbit @roger-ryao
- [BACKPORT][v1.13.1][BUG] `test_engine_crash_for_dr_volume` may fails on v2 data engine due to `activate_standby_volume` assert error [14442](https://github.com/longhorn/longhorn/issues/14442) - @roger-ryao @carterli0407-cell
- [BACKPORT][v1.13.1][BUG] Test case `Test Longhorn Global Manager Leader Failover` fails with v2 data engine [14421](https://github.com/longhorn/longhorn/issues/14421) - @yangchiu @hookak
- [BACKPORT][v1.13.1][BUG] `spdk_tgt` crashes with "double free or corruption (fasttop)" around replica rebuilds [14483](https://github.com/longhorn/longhorn/issues/14483) - @derekbit @chriscchien
- [BACKPORT][v1.13.1][BUG] Volume reconcile fails with `instancemanager.longhorn.io "" not found` when a v1 volume has extra healthy replicas and a stopped replica [14410](https://github.com/longhorn/longhorn/issues/14410) - @roger-ryao
- [BACKPORT][v1.13.1][BUG] Concurrent unaligned writes during replica rebuild lose data (unlocked read-modify-write in writeInWOMode) [14449](https://github.com/longhorn/longhorn/issues/14449) - @yangchiu @derekbit
- [BACKPORT][v1.13.1][BUG] A stalled NVMe device makes engine frontends of unrelated v2 volumes fail validation and be recreated [14328](https://github.com/longhorn/longhorn/issues/14328) - @hookak @roger-ryao
- [BACKPORT][v1.13.1][BUG]  BackingImage export snapshot (vmi-*) is marked userCreated=true instead of system-generated [14431](https://github.com/longhorn/longhorn/issues/14431) - @roger-ryao @carterli0407-cell
- [BACKPORT][v1.13.1][BUG] v2 instance-manager is crashed by disk recovery failure in SPDK [14348](https://github.com/longhorn/longhorn/issues/14348) - @shuo-wu @chriscchien
- [BACKPORT][v1.13.1][BUG] V2 instance manager live upgrade stuck in  relocating-engines  because the EngineFrontend switchover keeps retrying  promoting  against a recreated target engine [14426](https://github.com/longhorn/longhorn/issues/14426) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.13.1][BUG] V2 instance-manager `spdk_tgt` allocates its hugepages from another pod's hugetlbfs mount (via `/host`), blocking that pod's teardown [14429](https://github.com/longhorn/longhorn/issues/14429) - @yangchiu @derekbit
- [BACKPORT][v1.13.1][BUG] remote.Factory.Create() fails to clean up connections and dataconn goroutines on error paths [14297](https://github.com/longhorn/longhorn/issues/14297) - @roger-ryao
- [BACKPORT][v1.13.1][BUG] CSI clone from a plain PVC to an encrypted StorageClass produces an unusable volume [14270](https://github.com/longhorn/longhorn/issues/14270) - @yangchiu @mantissahz
- [BUG] nvme list zombie processes leak when NVMe admin queue returns EAGAIN (v2 data engine) [13761](https://github.com/longhorn/longhorn/issues/13761) - @lynn901 @hookak @chriscchien
- [BACKPORT][v1.13.1][BUG] nvme list zombie processes leak when NVMe admin queue returns EAGAIN (v2 data engine) [14385](https://github.com/longhorn/longhorn/issues/14385) - @hookak @chriscchien
- [BACKPORT][v1.13.1][BUG] SystemBackup stuck in `CreatingVolumeBackups` on v1.12.1: controller either silently stops reconciling after all volume backups complete, or loops forever on `snapshot not found` (auto-cleanup race) [14376](https://github.com/longhorn/longhorn/issues/14376) - @yangchiu @c3y1huang
- [BACKPORT][v1.13.1][BUG] v2 spdk_tgt aborts with assertion in blob_insert_cluster_msg due to an extent page race [14371](https://github.com/longhorn/longhorn/issues/14371) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.13.1][BUG] CSI CreateVolume panics on a StorageClass with a negative numberOfReplicas [14164](https://github.com/longhorn/longhorn/issues/14164) - @roger-ryao
- [BACKPORT][v1.13.1][BUG] Fast replica rebuild skips a snapshot file that was changed by purge/coalesce (stale .img.checksum), leaving the rebuilt replica missing data; snapshot-data-integrity: fast-check does not detect it [14336](https://github.com/longhorn/longhorn/issues/14336) - @derekbit @chriscchien
- [BACKPORT][v1.13.1][BUG] a rebuilding replica sometimes disappears in the `Engine.Status.ReplicaModeMap` [13915](https://github.com/longhorn/longhorn/issues/13915) - @mantissahz @roger-ryao
- [BACKPORT][v1.13.1][BUG] Transient status RPC failure marks healthy replica failed and can fault a volume [14277](https://github.com/longhorn/longhorn/issues/14277) - @yangchiu
- [BACKPORT][v1.13.1][BUG] Disk health data never collected for V1 filesystem disks whose path is not itself a mount point ("mount path ... not found") [14305](https://github.com/longhorn/longhorn/issues/14305) - @derekbit @chriscchien
- [BACKPORT][v1.13.1][BUG] Test case `Test Encrypted RWO Block Volume Online Expansion` fails [14295](https://github.com/longhorn/longhorn/issues/14295) - @yangchiu @mantissahz
- [BACKPORT][v1.13.1][BUG] `test_engine_crash_for_dr_volume` fails on v2 data engine [14013](https://github.com/longhorn/longhorn/issues/14013) - @derekbit @chriscchien
- [BACKPORT][v1.13.1][BUG] Force-deleted pod VolumeAttachment cleanup ignores "Waiting for detach" events (Kubernetes v1.35.9+, v1.36.4+, v1.37) [14216](https://github.com/longhorn/longhorn/issues/14216) - @roger-ryao
- [BACKPORT][v1.13.1][BUG] Test case `Test Snapshot Cleanup Recurring Job Cleans System Generated Snapshots During Replica Rebuild` fails [13983](https://github.com/longhorn/longhorn/issues/13983) - @yangchiu @apoorvajagtap
- [BACKPORT][v1.13.1][BUG] V2 DR volume restore does not retry when backupstore lock is held [14086](https://github.com/longhorn/longhorn/issues/14086) - @derekbit @roger-ryao
- [BACKPORT][v1.13.1][BUG] Longhorn v2 engine crashes on large-block reads in interrupt mode - spdk_for_each_channel "Assertion 'false' failed" [14163](https://github.com/longhorn/longhorn/issues/14163) - @derekbit @chriscchien
- [BACKPORT][v1.13.1][BUG] SystemBackup fails when a snapshot has an empty status.creationTime [14139](https://github.com/longhorn/longhorn/issues/14139) - @yangchiu

### Performance
- [BACKPORT][v1.13.1][BUG] RWX share manager starts up to 30 s late because the share manager controller does not watch volume attachments [14230](https://github.com/longhorn/longhorn/issues/14230) - @chriscchien

### Stability
- [BACKPORT][v1.13.1][BUG] All v1 volume I/O stalls silently with longhorn-engine v1.7.1 through v1.9.2 on Rocky Linux 9.7 / RKE2 (iSCSI login timeout, attach/detach loop); engine v1.7.0 and v1.6.4 work on every platform version [14254](https://github.com/longhorn/longhorn/issues/14254) - @yangchiu @davidcheng0922
- [BACKPORT][v1.13.1][BUG] Admission webhook calls for one resource type (backups.longhorn.io) fail with instant EOF, zero network I/O — deterministic, fleet-wide, persists across apiserver restarts and egress-selector modes [14315](https://github.com/longhorn/longhorn/issues/14315) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.13.1][IMPROVEMENT] Avoid re-sending an unchanged Node status update [14146](https://github.com/longhorn/longhorn/issues/14146) - @hookak @chriscchien

### Misc
- [BACKPORT][v1.13.1][BUG] Recurring backup job fails with "cannot find the status of the backup" when the backup monitor is re-created [14227](https://github.com/longhorn/longhorn/issues/14227) - @mantissahz @roger-ryao
- [BACKPORT][v1.13.1][BUG] Rancher app form ignores three settings because questions.yaml variables do not match values.yaml [14497](https://github.com/longhorn/longhorn/issues/14497) - @roger-ryao
- [BACKPORT][v1.13.1][TASK] Update module github.com/urfave/cli to v3 [14293](https://github.com/longhorn/longhorn/issues/14293) - @yangchiu @mantissahz
- [BACKPORT][v1.13.1][BUG] RWX volume mounts are delayed up to 2 minutes when the share manager is stopped and started repeatedly (e.g. by a CronJob) [14179](https://github.com/longhorn/longhorn/issues/14179) - @roger-ryao
- [BACKPORT][v1.13.1][BUG] Remaining -devel packages in longhorn-instance-manager runtime image (follow-up to #13479) [14136](https://github.com/longhorn/longhorn/issues/14136) - @roger-ryao
- [BACKPORT][v1.13.1][BUG] longhorn-manager v1.11.1 exits fatal on settings update conflict during startup, should retry on apierrors.IsConflict [14149](https://github.com/longhorn/longhorn/issues/14149) - @chriscchien
- [BACKPORT][v1.13.1][TASK] Add Helm chart image HIP-0015 annotations [14205](https://github.com/longhorn/longhorn/issues/14205) - @roger-ryao @carterli0407-cell
- [BACKPORT][v1.13.1][BUG] Live migration and replica rebuild enter circular wait after nodes are uncordoned [14155](https://github.com/longhorn/longhorn/issues/14155) - @carterli0407-cell
- [BACKPORT][v1.13.1][BUG] instance-manager panics (nil pointer) in sync.(*Task).HashSnapshotStatus when a replica is rebuilding: shadowed err in isRebuilding branch [14253](https://github.com/longhorn/longhorn/issues/14253) - @chriscchien
- [BACKPORT][v1.13.1][IMPROVEMENT] nsmounter: kubelet PID lookup on Talos takes seconds per call [14175](https://github.com/longhorn/longhorn/issues/14175) - @yangchiu

## Contributors
- @COLDTURNIP
- @apoorvajagtap
- @c3y1huang
- @carterli0407-cell
- @chriscchien
- @davidcheng0922
- @derekbit
- @github-actions[bot]
- @hookak
- @innobead
- @lynn901
- @mantissahz
- @roger-ryao
- @shuo-wu
- @yangchiu
- @rebeccazzzz
- @forbesguthrie
- @asettle
- @sushant-suse