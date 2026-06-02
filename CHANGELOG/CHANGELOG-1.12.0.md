# Longhorn v1.12.0 Release Notes

The Longhorn team is excited to announce the release of Longhorn v1.12.0. This feature release marks a major milestone for Longhorn: the **V2 Data Engine** is now officially **Generally Available (GA)**.

With the V2 Data Engine reaching GA, Longhorn v1.12.0 strengthens the production story for modern workloads with topology-aware provisioning, dual-stack and V2 IPv6 support, improved observability and operational tooling, and clearer guidance around V1 and V2 behavior and feature parity.

For terminology and background on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

## Removal

### V2 Backing Image Removal

V2 Backing Images are removed in Longhorn v1.12.0. Suggest using the [Containerized Data Importer (CDI)](https://longhorn.io/docs/1.12.0/advanced-resources/containerized-data-importer/containerized-data-importer/) to import VM disk images into V2 volumes to achieve the same purpose.

If you have V2 volumes that were created from backing images, you must migrate them before upgrading to v1.12.0:

1. **Backup and recreate** (recommended): Create a backup of the V2 volume, delete the original volume, then restore from backup. The restored volume will not have a backing image dependency.
2. **Delete the volume**: If the data is not needed, delete the V2 volume directly.

V2 volumes with backing image dependencies cannot be upgraded in-place. Attempting to upgrade without migration may result in volume attachment failures.

[GitHub Issue #13181](https://github.com/longhorn/longhorn/issues/13181)

## Primary Highlights

### V2 Data Engine

#### Generally Available

We are pleased to announce that the V2 Data Engine has officially graduated to **General Availability** in Longhorn v1.12.0.

This milestone reflects major progress in stability, operational safety, networking support, and feature maturity. Compared with earlier releases, V2 volumes are better positioned for production use, combining GA readiness with modern networking support, more precise scheduling behavior, and clearer visibility into where V2 already matches V1 behavior and where differences still matter.


> [!IMPORTANT]
> **V2 Live Upgrade:**
>
> V2 volumes do not support live upgrades between Longhorn v1.12 patch releases and must be detached before upgrading. Support is planned when upgrading from a Longhorn v1.12 release to a Longhorn v1.13 release.
>
> **V2 Volume Attach Latency at Scale:**
>
> In environments with a growing number of attached V2 volumes, increased attach latency has been observed for subsequent volumes. Initial analysis suggests this may be related to NVMe-TCP connection handling at scale, though the precise layer, SPDK user-space or Linux kernel, has not yet been identified. Further investigation is in progress. For follow-up status, see [Issue #13241](https://github.com/longhorn/longhorn/issues/13241).
>
> **ARM64 NVMe-backed Block-Type Node Disk Limitation:**
>
> On ARM64 systems, V2 volumes may experience stuck I/O when SPDK is configured with two or more CPU cores and node disks use the NVMe driver. The root cause may lie in either the Linux kernel or SPDK itself, and further investigation is required. As a workaround, use [AIO-backed node disks](https://longhorn.io/docs/1.12.0/nodes-and-volumes/nodes/multidisk/#using-aio-disks) instead of [NVMe-backed node disks](https://longhorn.io/docs/1.12.0/nodes-and-volumes/nodes/multidisk/#using-nvme-disks) on ARM64 systems. For follow-up status, see [Issue #13243](https://github.com/longhorn/longhorn/issues/13243).
>
> **UBLK Frontend Kernel Limitation:**
>
> The UBLK frontend for V2 data engine volumes remains experimental and is only functional on Linux kernels below v6.17. On kernel v6.17.0 and above, UBLK fails due to upstream UBLK API changes that cause `EINVAL` errors when starting UBLK devices. For follow-up status, see [Issue #11977](https://github.com/longhorn/longhorn/issues/11977).

For a summary of the current V1 and V2 volume behavior differences and feature parity, see [V1 and V2 Volume Feature Support](https://longhorn.io/docs/1.12.0/v1-v2-volume-behavior-and-feature-parity/).

Looking ahead, the roadmap remains active: **fast volume cloning for V2 data engine** ([#12552](https://github.com/longhorn/longhorn/issues/12552)) and **Sharding Storage (Experimental Feature)** ([#1061](https://github.com/longhorn/longhorn/issues/1061)) are planned for Longhorn v1.12.1.

### Smarter Provisioning and Modern Networking

#### Topology-Aware PV Node Affinity Control

Longhorn v1.12.0 adds the `csi-allowed-topology-keys` setting and `strictTopology` StorageClass parameter for more precise control of PV `nodeAffinity`. These options allow users to limit which topology keys are propagated and, with `WaitForFirstConsumer`, pin the PV to the selected node topology when needed.

[GitHub Issue #12684](https://github.com/longhorn/longhorn/issues/12684)

#### IPv6 Support for V2 Volumes

V2 volumes now support single-stack IPv6 Kubernetes clusters.

[GitHub Issue #10928](https://github.com/longhorn/longhorn/issues/10928)

#### Dual-Stack Cluster Support

Longhorn now supports dual-stack Kubernetes clusters when all nodes are configured with their IP families in the same order, either all IPv4-first or all IPv6-first. This applies to both the V1 and V2 data engines.

> **Warning:** Dual-stack clusters with mixed IP family ordering across nodes are not supported and may result in connectivity failures between replicas and the engine.

[GitHub Issue #11531](https://github.com/longhorn/longhorn/issues/11531)

### Better Operations and Observability

#### Default CPU Allocation

Longhorn v1.12.0 changes the default `data-engine-cpu-mask` from `0x1`, one CPU core, to `0x3`, two CPU cores. V2 Data Engine uses a busy-polling reactor model where the master reactor handles both I/O polling and management RPCs. When only a single core is assigned, heavy I/O workloads can delay or starve RPC processing, resulting in increased latency, timeout events, and operational instability.

Assigning two or more cores allows I/O and management tasks to run on separate reactors, improving responsiveness and operational stability.

[GitHub Issue #13237](https://github.com/longhorn/longhorn/issues/13237)

#### On-Demand Snapshot Checksum Calculation

Longhorn v1.12.0 adds `longhornctl` support for triggering on-demand snapshot checksum calculation. The command can target a specific volume, all volumes on a specific node, or all volumes in the cluster, and the checksum operation runs asynchronously in the background.

[GitHub Issue #11442](https://github.com/longhorn/longhorn/issues/11442)

#### Toggle Kubernetes Metrics Server Integration

Longhorn v1.12.0 adds the `Kubernetes Metrics Server Metrics Enabled` setting to disable metrics-server-dependent metrics when the Kubernetes Metrics Server API is unavailable. This reduces repeated scrape warnings and unnecessary API calls while preserving other Longhorn metrics.

[GitHub Issue #13011](https://github.com/longhorn/longhorn/issues/13011)

#### Longhorn Manager Memory Optimization

Longhorn v1.12.0 optimizes longhorn-manager informer caching to reduce memory usage, especially in large clusters with high pod counts. This lowers cluster-wide memory overhead caused by repeated caching of non-Longhorn pod data on every manager instance.

[GitHub Issue #12771](https://github.com/longhorn/longhorn/issues/12771)

#### Configurable Engine Image Pod Liveness Probe

Longhorn v1.12.0 adds settings to configure the engine-image DaemonSet liveness probe period, timeout, and failure threshold. These settings help reduce unnecessary engine-image pod restarts on resource-constrained clusters, especially during upgrades or transient CPU spikes.

[GitHub Issue #12846](https://github.com/longhorn/longhorn/issues/12846)

### Critical Stability Fixes

#### Instance Manager Stability During Replica Rebuild Storms

Longhorn v1.12.0 fixes an instance-manager panic that could occur during replica rebuild storms. In affected environments, the panic could terminate all iSCSI targets served by the instance-manager and trigger cascading volume detachments across multiple PVCs.

[GitHub Issue #13087](https://github.com/longhorn/longhorn/issues/13087)

#### Replica Rebuild Progress Reporting

Longhorn v1.12.0 fixes a replica rebuild progress reporting bug that could display values greater than 100% after file-sync retries on unstable networks. Progress accounting is now reset correctly for retried files, so rebuild progress remains within the valid 0% to 100% range.

[GitHub Issue #12949](https://github.com/longhorn/longhorn/issues/12949)

#### Replica Auto-Balance Scheduling Loop

Longhorn v1.12.0 fixes a regression in replica auto-balance that could trigger a repeated replica create-and-delete loop when `Replica Auto Balance` was set to `best-effort`. In affected clusters, Longhorn could keep scheduling an extra replica instead of stabilizing at the configured replica count.

[GitHub Issue #12926](https://github.com/longhorn/longhorn/issues/12926)

#### Replica CR Leak During Failed Local Scheduling

Longhorn v1.12.0 fixes a replica scheduling issue where large numbers of stopped Replica CRs could accumulate when `dataLocality` was set to `best-effort` and the node did not have enough eligible local disk space for another replica. In affected clusters, recurring reconciliation could keep creating placeholder Replica CRs instead of reusing a single failed-schedule placeholder.

[GitHub Issue #13152](https://github.com/longhorn/longhorn/issues/13152)

#### CSI Storage Capacity Tracking

Longhorn v1.12.0 fixes a CSIStorageCapacity scheduling issue that could cause compute nodes without Longhorn disks to report zero capacity and be rejected by `WaitForFirstConsumer` scheduling. In affected clusters with separated compute and storage nodes, new PVCs could remain pending even though eligible storage was available on storage nodes.

[GitHub Issue #12807](https://github.com/longhorn/longhorn/issues/12807)

#### Encrypted Volume Size Correction

Longhorn v1.12.0 pre-allocates the 16 MiB LUKS2 header in the replica backend file for encrypted volumes, so the dm-crypt device now exposes the full requested size to workloads after the engine image is upgraded.

This change also introduces an upgrade constraint for encrypted migratable volumes: live migration is not supported when using an engine image with a CLI API version older than 12. Upgrade the engine image to v1.12.0 or later before attempting live migration of encrypted volumes.

[GitHub Issue #9205](https://github.com/longhorn/longhorn/issues/9205)

## Installation

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.12.0.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.12.0/deploy/install/) in the Longhorn documentation.

## Upgrade

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.11.x to v1.12.0.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.12.0/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues in this release

### Highlight

- [FEATURE] Decouple V2 Data Engine Initiator and Target Placement [7124](https://github.com/longhorn/longhorn/issues/7124) - @derekbit @shuo-wu @chriscchien
- [FEATURE] IPv6 for V2 Data Engine [10928](https://github.com/longhorn/longhorn/issues/10928) - @COLDTURNIP @chriscchien
- [FEATURE] Support IPv4/IPv6 Dual-Stack with IPv6 Family First or IPv4 Family First [11531](https://github.com/longhorn/longhorn/issues/11531) - @COLDTURNIP @c3y1huang @chriscchien
- [FEATURE] Support v2 Data Engine (GA) [6229](https://github.com/longhorn/longhorn/issues/6229) - @derekbit

### Feature

- [FEATURE] Support on-demand snapshot checksum calculation [11442](https://github.com/longhorn/longhorn/issues/11442) - @yangchiu @davidcheng0922
- [FEATURE] Add `--tolerations` flag to `longhornctl` for scheduling DaemonSet pods on tainted nodes [12993](https://github.com/longhorn/longhorn/issues/12993) - @chriscchien @bachmanity1

### Improvement

- [IMPROVEMENT] Use per-volume file lock to eliminate cross-volume blocking in NVMe/TCP initiator operations [13236](https://github.com/longhorn/longhorn/issues/13236) - @derekbit @chriscchien
- [IMPROVEMENT] Increase Default SPDK CPU Mask to Use 2+ CPU Cores for V2 Data Engine [13237](https://github.com/longhorn/longhorn/issues/13237) - @derekbit @mantissahz @chriscchien
- [IMPROVEMENT] Remove v2 backing image monitoring [13181](https://github.com/longhorn/longhorn/issues/13181) - @COLDTURNIP @derekbit @chriscchien
- [IMPROVEMENT] Wait for spdk_tgt process to terminate during pre-stop cleanup [13179](https://github.com/longhorn/longhorn/issues/13179) - @derekbit @chriscchien
- [IMPROVEMENT] Restart Instance Manager pod when hugepage settings change and no instances are running [13170](https://github.com/longhorn/longhorn/issues/13170) - @derekbit @chriscchien
- [IMPROVEMENT] Support CPU list format for V2 Data Engine CPU Mask setting with automatic conversion to hex mask [13166](https://github.com/longhorn/longhorn/issues/13166) - @derekbit @chriscchien
- [IMPROVEMENT] Update Longhorn `distro` in chart to `longhorn` [13160](https://github.com/longhorn/longhorn/issues/13160) - @derekbit @chriscchien
- [IMPROVEMENT] Misleading storage values [12633](https://github.com/longhorn/longhorn/issues/12633) - @elTwingo @davidcheng0922 @houhoucoop @roger-ryao
- [IMPROVEMENT] Implement Network Reconnection for Enhancing Replica Rebuilding Resilience [9626](https://github.com/longhorn/longhorn/issues/9626) - @yangchiu @mschneider82
- [IMPROVEMENT] Add support of new StorageClass parameters to helm chart [9324](https://github.com/longhorn/longhorn/issues/9324) - @yangchiu @TheFutonEng
- [IMPROVEMENT] Make Kubernetes Metrics Server (metrics.k8s.io) integration toggleable [13011](https://github.com/longhorn/longhorn/issues/13011) - @yangchiu @mantissahz @hookak
- [IMPROVEMENT] Reduce longhorn-manager memory usage by optimizing cluster-wide informer caching [12771](https://github.com/longhorn/longhorn/issues/12771) - @hookak @roger-ryao
- [IMPROVEMENT] Topology-aware PV nodeAffinity control: allowedTopologies keys + strictTopology [12684](https://github.com/longhorn/longhorn/issues/12684) - @hookak @roger-ryao
- [IMPROVEMENT] Set storage class annotations using helm values [13137](https://github.com/longhorn/longhorn/issues/13137) - @yangchiu @Profiidev
- [IMPROVEMENT] longhorn-manager pods race on webhook TLS Secret at scale [13012](https://github.com/longhorn/longhorn/issues/13012) - @yangchiu @hookak
- [IMPROVEMENT] Improve Longhorn auto-salvage observability [13018](https://github.com/longhorn/longhorn/issues/13018) - @yangchiu @derekbit
- [IMPROVEMENT] Removing Scheduled condition check during volume expansion [12606](https://github.com/longhorn/longhorn/issues/12606) - @yangchiu @davidcheng0922
- [IMPROVEMENT] `TooManySnapshots` volume condition uses a hard-coded threshold despite configurable snapshot max count [12396](https://github.com/longhorn/longhorn/issues/12396) - @COLDTURNIP @yangchiu
- [IMPROVEMENT] Move v2 volume backup restore from replica to engine [9277](https://github.com/longhorn/longhorn/issues/9277) - @davidcheng0922 @roger-ryao
- [IMPROVEMENT] Is there any way to have longhorn without python [12679](https://github.com/longhorn/longhorn/issues/12679) - @roger-ryao
- [IMPROVEMENT] sparse-tools APIs must not introduce breaking changes to existing APIs. [12967](https://github.com/longhorn/longhorn/issues/12967) - @yangchiu @derekbit
- [UI][IMPROVEMENT] `TooManySnapshots` volume condition uses a hard-coded threshold despite configurable snapshot max count [12922](https://github.com/longhorn/longhorn/issues/12922) - @chriscchien @houhoucoop
- [IMPROVEMENT] Add `Backup Target` to volume list `custom column` options [12619](https://github.com/longhorn/longhorn/issues/12619) - @yangchiu @houhoucoop
- [IMPROVEMENT] Allow disabling creation of the default longhorn StorageClass via Helm [12906](https://github.com/longhorn/longhorn/issues/12906) - @hookak @roger-ryao
- [IMPROVEMENT][TEST] Add unit tests for util parsing and string conversion helpers [12898](https://github.com/longhorn/longhorn/issues/12898) - @archy-rock3t-cloud @chriscchien
- [IMPROVEMENT] Metrics for backups [11387](https://github.com/longhorn/longhorn/issues/11387) - @yangchiu @mantissahz @Copilot
- [IMPROVEMENT] chart: allow specifying spec.sampleLimit on ServiceMonitor [12671](https://github.com/longhorn/longhorn/issues/12671) - @grelland @yangchiu
- [IMPROVEMENT] Add metrics for non-Encrypted and encrypted volumes [12462](https://github.com/longhorn/longhorn/issues/12462) - @derekbit @mantissahz @chriscchien @Copilot
- [IMPROVEMENT] Clarify helm version in generate-longhorn-yaml error message [12630](https://github.com/longhorn/longhorn/issues/12630) - @luojiyin1987 @chriscchien
- [IMPROVEMENT][UI] Link version number to git releases [11132](https://github.com/longhorn/longhorn/issues/11132) - @chriscchien @houhoucoop
- [IMPROVEMENT] Record the current share manager image in the Share Manager CR status [11203](https://github.com/longhorn/longhorn/issues/11203) - @derekbit @roger-ryao @Copilot
- [IMPROVEMENT] Snapshot tree color explanation [12247](https://github.com/longhorn/longhorn/issues/12247) - @houhoucoop
- [IMPROVEMENT] Refuse to attach strict-local volume to the wrong node [8546](https://github.com/longhorn/longhorn/issues/8546) - @yangchiu @derekbit @mantissahz @Copilot
- [IMPROVEMENT] Ensure V2 Engine ReplicaAdd respects the fast-replica-rebuild-enabled setting [12540](https://github.com/longhorn/longhorn/issues/12540) - @davidcheng0922 @roger-ryao
- [IMPROVEMENT] Relax `endpoint-network-for-rwx-volume` validation for migratable block-mode volumes [12644](https://github.com/longhorn/longhorn/issues/12644) - @c3y1huang @chriscchien
- [IMPROVEMENT] detailed log for the reason of node controller deleting backing image copies [12584](https://github.com/longhorn/longhorn/issues/12584) - @COLDTURNIP @yangchiu
- [IMPROVEMENT] RBAC permissions for csi-resizer [12681](https://github.com/longhorn/longhorn/issues/12681) - @yangchiu @konstantin-kelemen
- [IMPROVEMENT] Adding a message to hint users to clean up non-existing disks in Backing Image CR [10617](https://github.com/longhorn/longhorn/issues/10617) - @chriscchien @Copilot
- [IMPROVEMENT] Keep workload pod in the original zone and region [12517](https://github.com/longhorn/longhorn/issues/12517) - @bachmanity1
- [IMPROVEMENT] Consider node storage capacity when scheduling pods with existing PVs [12398](https://github.com/longhorn/longhorn/issues/12398) - @bachmanity1
- [IMPROVEMENT] Volume may enter faulty state without clear reason when backing image size mismatches [11673](https://github.com/longhorn/longhorn/issues/11673) - @COLDTURNIP @derekbit @roger-ryao @Copilot

### Bug

- [BUG] Adding V2 disk using `/dev/disk/by-path/pci-*` path fails (should use aio driver, but incorrectly thinks it's a BDF path) [13228](https://github.com/longhorn/longhorn/issues/13228) - @tserong @chriscchien
- [BUG] v2 RWX workload IO timed out after Longhorn components are deleted and restarted [13217](https://github.com/longhorn/longhorn/issues/13217) - @yangchiu @derekbit
- [BUG] v2 volume gets stuck in `Degraded` state after instance manager is deleted and restarted [13215](https://github.com/longhorn/longhorn/issues/13215) - @yangchiu @derekbit
- [BUG] nil pointer dereference panic in instance-manager during replica rebuild. [13087](https://github.com/longhorn/longhorn/issues/13087) - @derekbit @shuo-wu @roger-ryao
- [BUG] Test Encrypted Volume Upgrade: Old-engine RWO volume shows 1008 MiB  after expansion to 2 GiB instead of expected 2032 MiB [13194](https://github.com/longhorn/longhorn/issues/13194) - @derekbit @mantissahz @roger-ryao
- [BUG] v2 volume deletion clears `Spec.NodeID` before delete, potentially orphaning replicas when `Status.InstanceManagerName` is empty [13198](https://github.com/longhorn/longhorn/issues/13198) - @derekbit @chriscchien
- [BUG] Backup target still shows `Available` after being reset to empty [13195](https://github.com/longhorn/longhorn/issues/13195) - @yangchiu @derekbit
- [BUG] v2 instance-manager pod stuck in create/delete loop when engine frontend recovery blocks gRPC startup [13185](https://github.com/longhorn/longhorn/issues/13185) - @derekbit @chriscchien
- [BUG] global.cattle.systemDefaultRegistry is not applied as the image registry prefix in 108.2.1+up1.10.2 [13071](https://github.com/longhorn/longhorn/issues/13071) - @COLDTURNIP @yangchiu
- [BUG] Potential resource leak in longhorn-instance-manager [13143](https://github.com/longhorn/longhorn/issues/13143) - @derekbit @chriscchien
- [BUG] Encrypt volume provided size is 16MB shorter than the claimed size [9205](https://github.com/longhorn/longhorn/issues/9205) - @mantissahz @roger-ryao
- [BUG]  CSIStorageCapacity reports 0 for compute nodes without Longhorn disks, breaking WaitForFirstConsumer scheduling [12807](https://github.com/longhorn/longhorn/issues/12807) - @bachmanity1 @roger-ryao
- [BUG] Google Cloud Storage (GCS) backup target always fails with SignatureDoesNotMatch due to AWS SDK Go v2 CRC32 checksum incompatibility [12676](https://github.com/longhorn/longhorn/issues/12676) - @mantissahz @chriscchien
- [BUG] Longhorn Fails to enable volume security on FIPS enabled systems [12721](https://github.com/longhorn/longhorn/issues/12721) - @davidcheng0922 @chriscchien
- [BUG] Replica Auto-Balance Causes Infinite Replica Scheduling Loop [12926](https://github.com/longhorn/longhorn/issues/12926) - @yangchiu @shuo-wu
- [BUG] Replica rebuild progress can go over 100% [12949](https://github.com/longhorn/longhorn/issues/12949) - @yangchiu @mschneider82 @davidcheng0922
- [BUG] v2 backup/restore open failure paths can leak NVMe initiators and exposed bdevs [13114](https://github.com/longhorn/longhorn/issues/13114) - @derekbit @roger-ryao
- [BUG] Connection leak in longhorn-spdk-engine [13101](https://github.com/longhorn/longhorn/issues/13101) - @derekbit @roger-ryao @Copilot
- [BUG] HTTP response body leaks in support bundle status polling and webhook readiness checks [13115](https://github.com/longhorn/longhorn/issues/13115) - @derekbit @roger-ryao
- [BUG] Encrypted volume stuck in Attaching/Detaching loop after node reboot and instance manager deletion [11510](https://github.com/longhorn/longhorn/issues/11510) - @yangchiu @mantissahz
- [BUG] Test case `test_cleanup_system_generated_snapshots` fails on v2 volumes [13123](https://github.com/longhorn/longhorn/issues/13123) - @yangchiu @davidcheng0922
- [BUG] Test case `test_drain_with_block_for_eviction_if_contains_last_replica_success` failed on v1 volumes [13103](https://github.com/longhorn/longhorn/issues/13103) - @derekbit @chriscchien
- [BUG] Volume may get stuck when the snapshot CR deletion cannot be handled [12489](https://github.com/longhorn/longhorn/issues/12489) - @COLDTURNIP @yangchiu
- [BUG] `snapshot-max-count` doesn't work on v2 volumes [12921](https://github.com/longhorn/longhorn/issues/12921) - @yangchiu @davidcheng0922
- [BUG][v1.12.0-rc1] RWX Volume Gets Stuck in Detaching/Attaching Loop After Reboot Replica Node While Heavy Writing And Recurring Jobs on v2 Data Engine [13062](https://github.com/longhorn/longhorn/issues/13062) - @derekbit @chriscchien
- [BUG] After a node is rebooted and attach a v2 volume to the rebooted node, the volume gets stuck in the `Attaching` state [13084](https://github.com/longhorn/longhorn/issues/13084) - @yangchiu @derekbit
- [BUG] [v1.12.0-rc1] longhornctl fails on sle-micro 6.1 [13048](https://github.com/longhorn/longhorn/issues/13048) - @COLDTURNIP @roger-ryao
- [BUG] [longhorn-engine/dataserver] Handling EOF returned by io.ReadFull robustly [12964](https://github.com/longhorn/longhorn/issues/12964) - @yangchiu @apoorvajagtap
- [BUG] PrometheusTimeseriesCardinality for metric longhorn_rest_client_rate_limiter_latency_seconds_bucket [13085](https://github.com/longhorn/longhorn/issues/13085) - @derekbit @chriscchien
- [BUG] [v1.12.0-rc1] longhornctl fails on Ubuntu 26.04 [13072](https://github.com/longhorn/longhorn/issues/13072) - @derekbit @roger-ryao
- [BUG] longhorn-spdk-engine `verify()` race overwrites `replicaMap`, breaking concurrent replica rebuild [13074](https://github.com/longhorn/longhorn/issues/13074) - @derekbit @roger-ryao
- [BUG] spdk_tgt crash during rebuild cleanup [13076](https://github.com/longhorn/longhorn/issues/13076) - @derekbit @roger-ryao
- [BUG] Stopping spdk_tgt during v2 volume expansion leaves the volume stuck in detaching and does not record the failure in the Engine CR [12903](https://github.com/longhorn/longhorn/issues/12903) - @davidcheng0922 @chriscchien
- [BUG] RWX Workload becomes Read-only after nodes shutdown and share manager is recreated on a new node [12986](https://github.com/longhorn/longhorn/issues/12986) - @yangchiu @davidcheng0922
- [BUG] `test_support_bundle.py` test cases fail on `hardened cluster` with `IPv6 mode` [13066](https://github.com/longhorn/longhorn/issues/13066) - @COLDTURNIP @yangchiu
- [BUG] [v1.12.0-rc1] `test_delete_backup_during_restoring_volume` fails on v2 volume, volume not faulted and condition Restore is True [13061](https://github.com/longhorn/longhorn/issues/13061) - @derekbit @chriscchien
- [BUG] Test cases in test_engine_upgrade.py failed [13014](https://github.com/longhorn/longhorn/issues/13014) - @mantissahz @roger-ryao
- [BUG] v2 DR volume may get stuck in `Degraded` state if replica rebuilding is triggered during incremental restoration [12515](https://github.com/longhorn/longhorn/issues/12515) - @davidcheng0922 @chriscchien
- [BUG] Unexpected replica remains on node after all volumes have been cleaned up and causing unexpected scheduled storage [11177](https://github.com/longhorn/longhorn/issues/11177) - @yangchiu @c3y1huang
- [BUG] V2 volume created from backup become data corrupted after crashing one replica during restore [12830](https://github.com/longhorn/longhorn/issues/12830) - @chriscchien
- [BUG] [UI] replica shown as gray when v2 volume engine live switchover [13029](https://github.com/longhorn/longhorn/issues/13029) - @derekbit @chriscchien
- [Bug] `test_rebuild_with_restoration` is flaky on v2 volume [11447](https://github.com/longhorn/longhorn/issues/11447) - @derekbit @chriscchien
- [BUG] `lastBackup` of a v2 volume may remain empty after a backup is created [12542](https://github.com/longhorn/longhorn/issues/12542) - @mantissahz @roger-ryao
- [BUG] `dd && sync ` command hangs on v2 rwx encrypted volume [12649](https://github.com/longhorn/longhorn/issues/12649) - @mantissahz @chriscchien
- [BUG] VolumeSnapshot snapshot.storage.k8s.io/v1 report stale error [11429](https://github.com/longhorn/longhorn/issues/11429) - @COLDTURNIP @yangchiu
- [BUG] Test case `test_storage_capacity_aware_pod_scheduling` fails [13001](https://github.com/longhorn/longhorn/issues/13001) - @yangchiu @bachmanity1
- [BUG] Crash Single Instance Manager While RWO Encrypted Volume Backup Is Restoring fails on v2 volume [12938](https://github.com/longhorn/longhorn/issues/12938) - @chriscchien
- [BUG] Encrypted V2 volume cannot be mounted and stays in unknown robustness [12924](https://github.com/longhorn/longhorn/issues/12924) - @derekbit @chriscchien
- [BUG] Backup to S3 fails at 95% [12713](https://github.com/longhorn/longhorn/issues/12713) - @yangchiu @mantissahz
- [BUG] Node exhaustion caused by backup inspect buildup induced due to NFS latency [12896](https://github.com/longhorn/longhorn/issues/12896) - @COLDTURNIP @roger-ryao
- [BUG] Failed to collect health data for block disk (AIO) when disk path is a /dev/disk/by-id symlink [12910](https://github.com/longhorn/longhorn/issues/12910) - @yangchiu @hookak
- [BUG] "snapshot becomes not ready to use" Warning events emitted during expected auto-cleanup after backup [12850](https://github.com/longhorn/longhorn/issues/12850) - @yangchiu @EpochBoy
- [BUG] V1.11.0 very high memory consumption for instance manager [12573](https://github.com/longhorn/longhorn/issues/12573) - @derekbit @roger-ryao
- [BUG] (chart) image.openshift.oauthProxy.registry is silently ignored - global.imageRegistry: "docker.io" default always wins [12685](https://github.com/longhorn/longhorn/issues/12685) - @drewmullen @roger-ryao
- [BUG] Annotations not being applied to ingress [4014](https://github.com/longhorn/longhorn/issues/4014) - @DodoLeDev @roger-ryao
- [BUG] Regression test case `test_replica_scheduler_rebuild_restore_is_too_big` creates a volume with an incorrect data engine type. [12776](https://github.com/longhorn/longhorn/issues/12776) - @derekbit @chriscchien
- [BUG] Backing image data source pod fails when HTTP proxy is enabled [12779](https://github.com/longhorn/longhorn/issues/12779) - @c3y1huang @chriscchien
- [BUG] Block disks become Unschedulable on SLES 16.0 during v2 regression [12404](https://github.com/longhorn/longhorn/issues/12404) - @davidcheng0922 @chriscchien
- [BUG] v2 DR volume could become faulted and fail to restore from backups if volume attached node is rebooted during restoration [12412](https://github.com/longhorn/longhorn/issues/12412) - @c3y1huang @chriscchien
- [BUG] orphan controller does not cleanup the instance on the corresponding instance manager on a multiple IM node [12786](https://github.com/longhorn/longhorn/issues/12786) - @COLDTURNIP @roger-ryao
- [BUG] V2 Volume Clone Status is Changed Over Time [12746](https://github.com/longhorn/longhorn/issues/12746) - @davidcheng0922 @roger-ryao
- [BUG] `spdk_tgt` encountered an assertion failure in `longhorn-spdk-helper` during a CI test run [10599](https://github.com/longhorn/longhorn/issues/10599) - @derekbit @roger-ryao
- [BUG] Enable to set defaultSettings.nodeDiskHealthMonitoring [12729](https://github.com/longhorn/longhorn/issues/12729) - @Turgon37 @chriscchien
- [BUG] stale name variable in nsmounter get_pid [12703](https://github.com/longhorn/longhorn/issues/12703) - @ionfury @chriscchien
- [BUG] After upgrading to 1.11.0, new persistent volumes have nodeAffinity [12656](https://github.com/longhorn/longhorn/issues/12656) - @hookak @chriscchien
- [BUG]  Incorrect storage double-counting causes scheduling failure when multiple replicas exist on the same node [12653](https://github.com/longhorn/longhorn/issues/12653) - @yangchiu @davidcheng0922
- [BUG] Longhorn validating webhook blocks k3s server node joins - flannel CNI fails to initialize [12578](https://github.com/longhorn/longhorn/issues/12578) - @yangchiu @mantissahz
- [BUG] [v2] Can't use partition as block device [12599](https://github.com/longhorn/longhorn/issues/12599) - @chriscchien @bachmanity1
- [BUG] v2 encrypted volume stuck at attach-detach loop after delete correspond instance manager pod [12648](https://github.com/longhorn/longhorn/issues/12648) - @mantissahz
- [BUG] Reboot node while volume expansion, will cause pod stuck at creating state [5171](https://github.com/longhorn/longhorn/issues/5171) - @roger-ryao
- [BUG] Longhorn v1.10 Volume API is not compatible with the v1.8.1 manifest [12613](https://github.com/longhorn/longhorn/issues/12613) - @mantissahz @roger-ryao
- [BUG] Volume.Spec.CloneMode is empty after upgrading to v1.10.x and following version [12614](https://github.com/longhorn/longhorn/issues/12614) - @mantissahz
- [BUG] System backup may fail to be created or deleted [12472](https://github.com/longhorn/longhorn/issues/12472) - @yangchiu @mantissahz
- [BUG] Unexpected replica rebuilding is triggered again after a previous replica rebuilding has completed [12510](https://github.com/longhorn/longhorn/issues/12510) - @chriscchien

### Performance

- [TASK] Evaluate the CPU and memory consumption of the Longhorn engine and replica instances [12936](https://github.com/longhorn/longhorn/issues/12936) - @roger-ryao

### Resilience

- [DOC] Enhance Longhorn docs about Instance Manager [13197](https://github.com/longhorn/longhorn/issues/13197) - @Felipalds
- [IMPROVEMENT] Make liveness probe parameters of engine-image DaemonSet configurable [12846](https://github.com/longhorn/longhorn/issues/12846) - @roger-ryao @aviralgarg05

### Stability

- [BUG] longhorn-manager panic in BackupController.setInprogressDeletionMap during backup deletion [13245](https://github.com/longhorn/longhorn/issues/13245) - @EpochBoy @chriscchien @roger-ryao
- [BUG] v1.10.2: dataLocality=best-effort with insufficient local storage leaks N Replica CRs per recurring-job firing (#12488 follow-up) [13152](https://github.com/longhorn/longhorn/issues/13152) - @derekbit @roger-ryao

### Misc

- [TASK] Add distro information to upgrade responder requests [12778](https://github.com/longhorn/longhorn/issues/12778) - @yangchiu @davidcheng0922
- [DOC] Expected inconsistent behavior of between v1 and v2 volume [7624](https://github.com/longhorn/longhorn/issues/7624) - @yangchiu @derekbit @sushant-suse
- [EPIC] Integrate "V2 Data Engine" content into standard documentation structure [13054](https://github.com/longhorn/longhorn/issues/13054) - @mantissahz @chriscchien @sushant-suse
- [BUG] UI does not update v2 backup state from Error to Completed [12842](https://github.com/longhorn/longhorn/issues/12842) - @derekbit @mantissahz @chriscchien
- [BUG] v1.11.1 upgrade to v1.12.x-head fail due to v2 volume snapshot unknown field `status.requestedTime` [13113](https://github.com/longhorn/longhorn/issues/13113) - @chriscchien
- [DOC] Create a KB post for Longhorn node eviction workflows during node rolling replacement [12870](https://github.com/longhorn/longhorn/issues/12870) - @COLDTURNIP @yangchiu
- [DOC] Document for gracefully node removing [12961](https://github.com/longhorn/longhorn/issues/12961) - @roger-ryao @sushant-suse
- [BUG] v2 Volume fails to rebuild on existing replica when a scheduling-failed replica exists [12664](https://github.com/longhorn/longhorn/issues/12664) - @shuo-wu @chriscchien
- [WEBSITE][DOC] Update website footer to new LF Projects Series LLC trademark disclaimer [12982](https://github.com/longhorn/longhorn/issues/12982) - @sushant-suse
- [DOC] Helm chart: v4 compatibility? [12894](https://github.com/longhorn/longhorn/issues/12894) - @COLDTURNIP
- [TASK] Ensure all remaining GitHub Actions are pinned to specific commit SHAs [12920](https://github.com/longhorn/longhorn/issues/12920) - @carterli0407-cell
- [DOC] Broken links in the nginx ingress deprecation notice [12904](https://github.com/longhorn/longhorn/issues/12904) - @Copilot
- [IMPROVEMENT] Add validation to prevent duplicate disk `paths` when patching node via `kubectl` [12480](https://github.com/longhorn/longhorn/issues/12480) - @yangchiu @carterli0407-cell
- [REFACTOR] Remove redundant type casts [12316](https://github.com/longhorn/longhorn/issues/12316) - @futhgar @roger-ryao
- [DOC] Add a KB for the insufficient space issue [8785](https://github.com/longhorn/longhorn/issues/8785) - @mantissahz @roger-ryao @sushant-suse
- [BUG] invalid character '<' looking for beginning of value [12569](https://github.com/longhorn/longhorn/issues/12569) - @COLDTURNIP @roger-ryao
- [DOC] Add documentation to restore a backup using CRs instead of only documenting the UI [12810](https://github.com/longhorn/longhorn/issues/12810) - @chriscchien @sushant-suse
- [DOC] Update doc as ingress-nginx will be deprecated [12758](https://github.com/longhorn/longhorn/issues/12758) - @yangchiu @sushant-suse
- [DOC] Improve `Configurable CPU Cores` description [12740](https://github.com/longhorn/longhorn/issues/12740) - @chriscchien @sushant-suse
- [DOC] KB for iSCSI loop back connection issues [12548](https://github.com/longhorn/longhorn/issues/12548) - @COLDTURNIP @roger-ryao
- [DOC] Fix typos in documentation and enhancement files [12628](https://github.com/longhorn/longhorn/issues/12628) - @luojiyin1987
- [TASK] Add FOSSA action workflow to longhorn/<component> repos [12506](https://github.com/longhorn/longhorn/issues/12506) - @derekbit
- [DOC] Evaluate HugePage Usage of Longhorn V2 Volumes [12504](https://github.com/longhorn/longhorn/issues/12504) - @derekbit

## New Contributors

- @DodoLeDev
- @Edo78
- @Flou21
- @Nemric
- @Profiidev
- @SquaredPotato
- @TheFutonEng
- @Turgon37
- @abacef
- @adarmi
- @apoorvajagtap
- @archy-rock3t-cloud
- @aviralgarg05
- @carterli0407-cell
- @chamarakera
- @drewmullen
- @elTwingo
- @farukheaver
- @flori4n
- @futhgar
- @grelland
- @ionfury
- @jeven2016
- @jimmy-wei
- @johnwc
- @konstantin-kelemen
- @kudodenko
- @lelgenio
- @luojiyin1987
- @mschneider82
- @mzac
- @peyremorgan
- @rrishabh6172
- @thisisobate
- @tomklapka
- @wstutt

## Contributors

- @COLDTURNIP 
- @EpochBoy 
- @Felipalds 
- @PhanLe1010 
- @WebberHuang1118 
- @bachmanity1 
- @boomam 
- @brandboat 
- @c3y1huang 
- @chriscchien 
- @davepgreene 
- @davidcheng0922 
- @derekbit 
- @ejweber 
- @hoo29 
- @hookak 
- @houhoucoop 
- @innobead 
- @mantissahz 
- @roger-ryao 
- @shuo-wu 
- @sushant-suse 
- @yangchiu
- @tserong
- @rebeccazzzz
- @forbesguthrie
