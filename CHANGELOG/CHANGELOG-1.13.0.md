# Longhorn v1.13.0 Release Notes

The Longhorn team is excited to announce the release of Longhorn v1.13.0. This feature release brings **live upgrade** to the **V2 Data Engine**, which reached general availability in v1.12.0. V2 volumes can now stay attached while Longhorn is upgraded, as long as your cluster meets the [live upgrade prerequisites](https://longhorn.io/docs/1.13.0/deploy/upgrade/v2-instance-upgrade/#prerequisites).

Longhorn v1.13.0 also introduces full interrupt mode for the V2 Data Engine, volume group snapshots, age-based retention for recurring jobs, topology-constrained replica scheduling, a scheduler extender, and the `longhorn-global-manager` Deployment that lowers control-plane overhead in large clusters.

For terminology and background on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

## Breaking Changes

### Kubernetes v1.34 Minimum Version

Because the CSI external-provisioner is upgraded to v6.3.0, all clusters must be running Kubernetes v1.34 or later before installing or upgrading to Longhorn v1.13.0.

### Legacy V2 Linked-Clone Volumes

Since v1.12.1, V2 linked-clone volumes created in Longhorn v1.12.0 or earlier **can only be detached or deleted**. To replace one, create a new linked clone from the same source volume; no data copy is required.

[GitHub Issue #12552](https://github.com/longhorn/longhorn/issues/12552)

## Primary Highlights

### V2 Data Engine

The V2 Data Engine became generally available in Longhorn v1.12.0. Longhorn v1.13.0 adds live upgrade and full interrupt mode, and enables CPU isolation by default for new installations.

> [!IMPORTANT]
> **V2 Volume Attach Latency at Scale:**
>
> In clusters with many attached V2 volumes, attaching additional volumes takes longer. The root cause is under investigation. For follow-up status, see [Issue #13241](https://github.com/longhorn/longhorn/issues/13241).
>
> **ARM64 NVMe-backed Block-Type Node Disk Limitation:**
>
> On ARM64 systems, V2 volumes may experience stuck I/O when SPDK is configured with two or more CPU cores and node disks use the NVMe driver. The root cause is under investigation. As a workaround, use [AIO-backed node disks](https://longhorn.io/docs/1.13.0/nodes-and-volumes/nodes/multidisk/#using-aio-disks) instead of [NVMe-backed node disks](https://longhorn.io/docs/1.13.0/nodes-and-volumes/nodes/multidisk/#using-nvme-disks) on ARM64 systems. For follow-up status, see [Issue #13243](https://github.com/longhorn/longhorn/issues/13243).
>
> **UBLK Frontend Kernel Limitation:**
>
> The UBLK frontend for V2 Data Engine volumes remains experimental. On kernel v6.17, attaching a UBLK volume can cause a kernel panic. Do not use the UBLK frontend on this kernel version. For more information, see [Issue #13509](https://github.com/longhorn/longhorn/issues/13509) and [UBLK Frontend Support](https://longhorn.io/docs/1.13.0/advanced-resources/v2-data-engine/ublk-frontend-support).

For the expected behavior differences between V1 and V2 volumes and the feature support matrix, see [V1 and V2 Volume Feature Support](https://longhorn.io/docs/1.13.0/v1-v2-volume-behavior-and-feature-parity/).

[GitHub Issue #6229](https://github.com/longhorn/longhorn/issues/6229)

#### Live Upgrade

Longhorn v1.13.0 supports live upgrade of V2 volumes, so the V2 instance managers can be upgraded without detaching the volumes. For more information, see [V2 Data Engine Instance Manager Upgrade](https://longhorn.io/docs/1.13.0/deploy/upgrade/v2-instance-upgrade/).

> [!IMPORTANT]
> **Upgrade path:**
>
> V2 live upgrade to v1.13.0 is supported only from Longhorn v1.12.2. When upgrading from v1.12.0 or v1.12.1, or when the [prerequisites](https://longhorn.io/docs/1.13.0/deploy/upgrade/v2-instance-upgrade/#prerequisites) are not met, detach all V2 volumes and ensure their replicas are stopped before upgrading.

[GitHub Issue #9104](https://github.com/longhorn/longhorn/issues/9104)

#### Full Interrupt Mode

Interrupt mode was introduced in v1.10.0 to reduce V2 Data Engine CPU usage for idle or low I/O workloads. Its implementation used a hybrid approach that still incurred a minimal, constant CPU load even when volumes were idle. In Longhorn v1.13.0, interrupt mode is fully event-driven: SPDK reactors wait for I/O events instead of polling continuously, and only low-frequency background checks remain. Idle instance manager pods therefore use very little CPU. As before, interrupt mode may introduce slightly higher I/O latency than polling mode under sustained high-throughput workloads.

Polling mode remains the default. To switch, set `data-engine-interrupt-mode-enabled` to `{"v2":"true"}` while no V2 volumes are attached. For more information, see [Interrupt Mode Support](https://longhorn.io/docs/1.13.0/advanced-resources/v2-data-engine/interrupt-mode).

[GitHub Issue #11662](https://github.com/longhorn/longhorn/issues/11662)

#### CPU Isolation Enabled by Default

CPU isolation keeps interrupts and other kernel background work off the CPU cores used by the V2 Data Engine. Longhorn v1.13.0 sets `data-engine-cpu-isolation-enabled` to `{"v2":"true"}` by default for new installations; clusters upgraded from v1.12.x keep their existing value and can opt in by setting it to `{"v2":"true"}`. CPU isolation applies only in polling mode; Longhorn skips it automatically when interrupt mode is enabled. For more information, see [Data Engine CPU Isolation Enabled](https://longhorn.io/docs/1.13.0/references/settings/#data-engine-cpu-isolation-enabled).

[GitHub Issue #13724](https://github.com/longhorn/longhorn/issues/13724), [GitHub Issue #13973](https://github.com/longhorn/longhorn/issues/13973)

#### Fast Volume Cloning

Since v1.12.1, fast volume cloning uses a linked-clone architecture: a `linked-clone` volume shares data blocks with its source instead of copying them. One source volume can back multiple linked clones. Linked-clone volumes support most operations available to regular volumes, including snapshots, expansion, replica rebuilding, backup and restore, and use as the source of nested linked clones. For more information, see [Volume Clone Support](https://longhorn.io/docs/1.13.0/snapshots-and-backups/csi-volume-clone).

[GitHub Issue #12552](https://github.com/longhorn/longhorn/issues/12552)

#### Storage Sharding (Experimental)

Introduced in v1.12.1, storage sharding is an experimental V2 Data Engine feature. Instead of keeping a full copy of the volume on every replica, it splits written data into data and parity chunks and spreads them across nodes. A volume can then be larger than any single disk or node, and tolerate the same number of failures with less disk space.

Sharded volumes do not support backup and restore, volume cloning, backing images, disaster recovery (DR) volumes, or live migration. This feature is for evaluation and testing only and is not recommended for production. For more information, see [Sharding with Erasure Coding](https://longhorn.io/docs/1.13.0/advanced-resources/v2-data-engine/sharding).

[GitHub Issue #1061](https://github.com/longhorn/longhorn/issues/1061)

#### SPDK iobuf Pool Size Configuration

Introduced in v1.12.1, the `data-engine-iobuf-large-pool-size` and `data-engine-iobuf-small-pool-size` settings control the size of the SPDK buffer pools used by the V2 Data Engine. Larger pools help avoid running out of buffers under high-queue-depth workloads. Because the pools are sized when SPDK starts, changing either setting recreates V2 instance manager pods that have no running engines or replicas.

[GitHub Issue #13322](https://github.com/longhorn/longhorn/issues/13322), [GitHub Issue #13674](https://github.com/longhorn/longhorn/issues/13674)

### Snapshots and Backups

#### Volume Group Snapshot Support

Longhorn v1.13.0 can snapshot a set of volumes as one group with a single request from the Longhorn UI, kubectl, or Kubernetes `VolumeGroupSnapshot` objects through CSI. The CSI path also supports group backups but is disabled by default.

> [!NOTE]
> **Snapshot Consistency:** Each member volume is snapshotted independently, so the group is **not** captured at a single point in time. Application-level consistency across the group is future work ([Issue #2128](https://github.com/longhorn/longhorn/issues/2128)).

For more information, see [Create a Snapshot Group](https://longhorn.io/docs/1.13.0/snapshots-and-backups/snapshot-groups) and [Enable CSI Volume Group Snapshot Support](https://longhorn.io/docs/1.13.0/snapshots-and-backups/csi-snapshot-support/enable-csi-volume-group-snapshot-support).

[GitHub Issue #13349](https://github.com/longhorn/longhorn/issues/13349)

#### Age-Based Retention for Recurring Jobs

Longhorn v1.13.0 adds an `age-based` retention policy for snapshot, backup, and system backup recurring jobs. Set `retentionPolicy` to `age-based` and `retainAge` to a duration such as `720h`; each run deletes snapshots or backups older than that age. The `count-based` policy remains the default, and existing recurring jobs are unchanged after the upgrade.

[GitHub Issue #12060](https://github.com/longhorn/longhorn/issues/12060)

### Smarter Scheduling

#### Volume Topology Constraint

Longhorn v1.13.0 adds the `volumeTopology` StorageClass parameter (`any`, `zonal`, or `regional`) to keep a volume's replicas in the zone or region where it was provisioned, including during rebuilds and replica count changes. Previously, zone labels only spread replicas apart, so a rebuild could place a replica in a different zone from the workload. For more information, see [Topology-Aware Provisioning](https://longhorn.io/docs/1.13.0/nodes-and-volumes/nodes/topology-aware-provisioning).

[GitHub Issue #13493](https://github.com/longhorn/longhorn/issues/13493)

#### Scheduler Extender

Longhorn v1.13.0 adds a scheduler extender that lets kube-scheduler check actual Longhorn disk capacity when placing pods. Without it, kube-scheduler relies on `CSIStorageCapacity` objects, which can be stale during bursts of pod creation and are not used for pods whose PVCs are already bound. The extender also places a restarted pod on the node that already holds all of its replicas, which is most useful with `best-effort` data locality. It runs inside longhorn-manager but requires a kube-scheduler configuration change, which is not possible on managed Kubernetes services such as GKE and EKS.

[GitHub Issue #12591](https://github.com/longhorn/longhorn/issues/12591)

### Better Operations

#### Longhorn Global Manager

Longhorn v1.13.0 moves the cluster-wide pod and PersistentVolume controllers out of the longhorn-manager DaemonSet into a new `longhorn-global-manager` Deployment, so kube-apiserver load and longhorn-manager memory no longer grow with the number of nodes. The Deployment is created on install and upgrade with three replicas by default. Before upgrading, make sure at least one of its pods can be scheduled. For more information, see [Upgrading Longhorn Manager](https://longhorn.io/docs/1.13.0/deploy/upgrade/longhorn-manager).

[GitHub Issue #13059](https://github.com/longhorn/longhorn/issues/13059)

### Security Hardening

#### Internal Network Policies

Since v1.12.1, Longhorn creates ingress `NetworkPolicy` resources for its internal components by default. They take effect only when the CNI plugin enforces `NetworkPolicy`. Longhorn v1.12.2 resolves the CNI compatibility issues found in v1.12.1 and adds three Helm values:

- `networkPolicies.v1DataEngineInitiatorSourceCIDRs` and `networkPolicies.recoveryBackendAdditionalIngressPorts` allow traffic that the v1.12.1 policies blocked.
- `networkPolicies.metricsScrapeSources` lets Prometheus and other scrapers reach longhorn-manager metrics on TCP port 9500.

For more information, see [Internal Network Policies](https://longhorn.io/docs/1.13.0/important-notes/#internal-network-policies).

[GitHub Issue #13438](https://github.com/longhorn/longhorn/issues/13438), [GitHub Issue #13802](https://github.com/longhorn/longhorn/issues/13802), [GitHub Issue #13740](https://github.com/longhorn/longhorn/issues/13740), [GitHub Issue #13947](https://github.com/longhorn/longhorn/issues/13947)

#### Instance Manager gRPC mTLS Coverage

Before v1.12.1, when the `longhorn-grpc-tls` secret was configured, mutual TLS (mTLS) covered only the instance manager's instance and proxy gRPC services; the disk and SPDK services still accepted plaintext connections. Since v1.12.1, mTLS covers all instance manager gRPC services, so every gRPC port requires a valid client certificate when the secret is configured.

[GitHub Issue #7787](https://github.com/longhorn/longhorn/issues/7787), [GitHub Issue #13212](https://github.com/longhorn/longhorn/issues/13212)

#### Dedicated CSI Service Account

Longhorn v1.13.0 runs the CSI controller sidecars under a dedicated `longhorn-csi-service-account` instead of the shared `longhorn-service-account`. For compatibility with existing Secret references, the new service account still receives cluster-wide `get` access to Secrets by default. You can turn this off with the `csi.allowControllerSecretAccess` Helm value after removing `csi.storage.k8s.io/provisioner-secret-*` parameters from Longhorn StorageClasses. For more information, see [Optional Restriction of CSI Controller Secret Access](https://longhorn.io/docs/1.13.0/important-notes/#optional-restriction-of-csi-controller-secret-access).

[GitHub Issue #14020](https://github.com/longhorn/longhorn/issues/14020)

### Critical Stability Fixes

#### Linked-Clone Backup Restore

Longhorn v1.13.0 fixes a V2 linked-clone backup restore issue that could produce a corrupted volume when the source volume or the snapshot the clone was created from no longer existed. Backups of V2 linked-clone volumes now record the source volume and snapshot, and a restore fails with an error if either is missing.

[GitHub Issue #13714](https://github.com/longhorn/longhorn/issues/13714)

#### CSI Volume Clone with Strict-Local Data Locality

Longhorn v1.13.0 fixes a CSI volume clone issue where cloning a volume with `dataLocality: strict-local` could fail with `hard affinity cannot be satisfied`. Longhorn now picks a node that matches the volume's `nodeSelector` and `diskSelector` for the clone.

[GitHub Issue #12792](https://github.com/longhorn/longhorn/issues/12792)

#### Longhorn Node Removal After Kubernetes Node Deletion

Longhorn v1.13.0 fixes a node cleanup issue where a Longhorn node could not be removed after its Kubernetes node had been deleted without eviction. You can now disable scheduling on the node, remove its remaining replicas and engines, and then delete it. Evicting a node before deleting it from the cluster is still the recommended procedure. For more information, see [Graceful Node Removal](https://longhorn.io/docs/1.13.0/nodes-and-volumes/nodes/graceful-node-removal).

[GitHub Issue #13494](https://github.com/longhorn/longhorn/issues/13494)

#### Backing Image Copies on IPv6 Clusters

Longhorn v1.13.0 fixes a backing image issue where copies were always transferred over IPv4, so on IPv6 single-stack and IPv6-first dual-stack clusters a backing image stayed at one copy. Backing images are now copied over the cluster's IP family and the storage network.

[GitHub Issue #13864](https://github.com/longhorn/longhorn/issues/13864)

## Installation

> [!IMPORTANT]
> **Ensure that your cluster is running Kubernetes v1.34 or later before installing Longhorn v1.13.0.**

You can install Longhorn using a variety of tools, including Rancher, kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.13.0/deploy/install/) in the Longhorn documentation.

## Upgrade

> [!IMPORTANT]
> **Ensure that your cluster is running Kubernetes v1.34 or later before upgrading from Longhorn v1.12.x to v1.13.0.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.13.0/deploy/upgrade/) in the Longhorn documentation.

Automated pre-upgrade checks do not cover all scenarios. Before upgrading, review the manual checks in [Important Notes](https://longhorn.io/docs/1.13.0/important-notes/#manual-checks-before-upgrade), and for V2 volumes confirm the [live upgrade prerequisites](https://longhorn.io/docs/1.13.0/deploy/upgrade/v2-instance-upgrade/#prerequisites) or detach them and ensure their replicas are stopped before upgrading.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues in this release

### Highlight
- [FEATURE] Support v2 Data Engine (GA) [6229](https://github.com/longhorn/longhorn/issues/6229) - @derekbit
- [FEATURE] V2 Volume Supports Live Upgrade [9104](https://github.com/longhorn/longhorn/issues/9104) - @yangchiu @davidcheng0922
- [FEATURE] VolumeGroupSnapshot support [13349](https://github.com/longhorn/longhorn/issues/13349) - @c3y1huang @chriscchien
- [FEATURE] Full Interrupt Mode for V2 Data Engine [11662](https://github.com/longhorn/longhorn/issues/11662) - @au2001 @chriscchien
- [FEATURE] V2 Data Engine Fast Cloning  [12552](https://github.com/longhorn/longhorn/issues/12552) - @shuo-wu @roger-ryao
- [FEATURE] V2 Data Engine Sharding - Experimental [1061](https://github.com/longhorn/longhorn/issues/1061) - @c3y1huang @chriscchien

### Feature
- [FEATURE] Support Age-Based Retention for Recurring Jobs [12060](https://github.com/longhorn/longhorn/issues/12060) - @mantissahz @roger-ryao
- [UI][FEATURE] V2 Data Engine Fast Cloning [13671](https://github.com/longhorn/longhorn/issues/13671) - @shuo-wu @roger-ryao
- [FEATURE] Backing image supports IPv6 and dual-stack IP families [13864](https://github.com/longhorn/longhorn/issues/13864) - @COLDTURNIP @yangchiu
- [UI][FEATURE] VolumeGroupSnapshot support [13707](https://github.com/longhorn/longhorn/issues/13707) - @a110605 @chriscchien
- [FEATURE] Allow configuring Gateway API filters [12976](https://github.com/longhorn/longhorn/issues/12976) - @apoorvajagtap @chriscchien
- [UI][FEATURE] Support Age-Based Retention for Recurring Jobs [13669](https://github.com/longhorn/longhorn/issues/13669) - @yangchiu @a110605 @houhoucoop
- [FEATURE] TLS gRPC API for instance manager [13212](https://github.com/longhorn/longhorn/issues/13212) - @COLDTURNIP

### Improvement
- [IMPROVEMENT] Restrict the Secret access of CSI components [14020](https://github.com/longhorn/longhorn/issues/14020) - @COLDTURNIP @roger-ryao
- [IMPROVEMENT] [CLI] preflight checks on Elemental3-based systems fails [13949](https://github.com/longhorn/longhorn/issues/13949) - @rdoxenham @yangchiu
- [IMPROVEMENT] Enable CPU Isolation for V2 Data Engine [13724](https://github.com/longhorn/longhorn/issues/13724) - @derekbit @roger-ryao @Copilot
- [IMPROVEMENT] Introduce longhorn-global-manager Deployment for cluster-wide controllers [13059](https://github.com/longhorn/longhorn/issues/13059) - @hookak @chriscchien
- [IMPROVEMENT] backup target availability status metric [13980](https://github.com/longhorn/longhorn/issues/13980) - @yangchiu @eklatzer
- [IMPROVEMENT] Disable CPU Isolation When V2 Data Engine Uses Interruption Mode [13973](https://github.com/longhorn/longhorn/issues/13973) - @derekbit @chriscchien
- [IMPROVEMENT] Add longhorn-cli command to check if the user's environment supports IOMMU [12076](https://github.com/longhorn/longhorn/issues/12076) - @yangchiu @apoorvajagtap
- [IMPROVEMENT] Make `ignoreSigningHeaders` configurable — SigV4 `Accept-Encoding` breaks every S3 backup target behind a header-rewriting proxy, not just GCS [13756](https://github.com/longhorn/longhorn/issues/13756) - @kinorai @roger-ryao
- [IMPROVEMENT] Longhorn Scheduler Extender [12591](https://github.com/longhorn/longhorn/issues/12591) - @bachmanity1
- [IMPROVEMENT] v2 data engine: gate the replica host-ACL restriction on cluster-wide instance manager version [13699](https://github.com/longhorn/longhorn/issues/13699) - @hookak
- [IMPROVEMENT] CSI ignores EC StorageClass parameters (silent replicated fallback) [13792](https://github.com/longhorn/longhorn/issues/13792) - @yangchiu @apoorvajagtap
- [IMPROVEMENT][Helm] Allow setting spec.trafficDistribution [13814](https://github.com/longhorn/longhorn/issues/13814) - @mydoomfr @yangchiu
- [IMPROVEMENT] (chart) Precedence of image.*.*.registry [12611](https://github.com/longhorn/longhorn/issues/12611) - @bachmanity1 @roger-ryao
- [IMPROVEMENT] Add metrics to collect information about V2 data engine usage [12941](https://github.com/longhorn/longhorn/issues/12941) - @derekbit @chriscchien @Copilot
- [IMPROVEMENT] Allow configuring SPDK iobuf large pool size [13322](https://github.com/longhorn/longhorn/issues/13322) - @chriscchien @bachmanity1
- [IMPROVEMENT] Truncate the attached-to pod list in the volume table for volumes with many pods [13851](https://github.com/longhorn/longhorn/issues/13851) - @HypeMC @chriscchien
- [IMPROVEMENT] Add a pod filter to the Workload/Pod detail popup [13852](https://github.com/longhorn/longhorn/issues/13852) - @HypeMC @chriscchien
- [IMPROVEMENT] Every longhorn-manager pod builds its DataStore and informer caches twice [13782](https://github.com/longhorn/longhorn/issues/13782) - @hookak @roger-ryao
- [IMPROVEMENT] Expose topologySpreadConstraints for longhorn-ui in the Helm chart [13731](https://github.com/longhorn/longhorn/issues/13731) - @yangchiu @seanblake
- [IMPROVEMENT] Respect volume topology in replica scheduling (opt-in zonal/regional volume placement) [13493](https://github.com/longhorn/longhorn/issues/13493) - @yangchiu @hookak
- [IMPROVEMENT] longhorn-manager watches Leases cluster-wide but reads only those in the Longhorn namespace [13786](https://github.com/longhorn/longhorn/issues/13786) - @hookak @chriscchien
- [IMPROVEMENT] longhorn-manager caches every Secret in the cluster in order to watch one [13726](https://github.com/longhorn/longhorn/issues/13726) - @yangchiu @hookak
- [IMPROVEMENT] v2 volumes: allow configuring the NVMe-TCP initiator I/O queue count (nr-io-queues) [13706](https://github.com/longhorn/longhorn/issues/13706) - @hookak @chriscchien
- [IMPROVEMENT] Allow configuring SPDK iobuf small pool size [13674](https://github.com/longhorn/longhorn/issues/13674) - @yangchiu @hookak
- [IMPROVEMENT] Increase `kbench` fio numjobs to higher value [9100](https://github.com/longhorn/longhorn/issues/9100) - @derekbit
- [IMPROVEMENT] Simplify kbench Metrics to Focus on Key Performance Indicators [9460](https://github.com/longhorn/longhorn/issues/9460) - @derekbit
- [IMPROVEMENT] go-common-libs: kill the child process when command execution times out [13619](https://github.com/longhorn/longhorn/issues/13619) - @hookak
- [IMPROVEMENT] always setup NetworkPolicy for the internal communication [13438](https://github.com/longhorn/longhorn/issues/13438) - @COLDTURNIP @roger-ryao
- [IMPROVEMENT] Steer host RPS away from SPDK reactor cores [13483](https://github.com/longhorn/longhorn/issues/13483) - @bachmanity1 @roger-ryao
- [IMPROVEMENT] updateBackupCompressionMethod may write the Volume even when the method is unchanged [13460](https://github.com/longhorn/longhorn/issues/13460) - @yangchiu @ChaoHuang2018
- [IMPROVEMENT] Improving error transparency for volume attachment failure [9968](https://github.com/longhorn/longhorn/issues/9968) - @derekbit @chriscchien @Copilot
- [IMPROVEMENT] Add usage metrics for volume size [11521](https://github.com/longhorn/longhorn/issues/11521) - @derekbit @chriscchien @Copilot
- [IMPROVEMENT] V2 volume write I/O stalls(~10s) when a replica is removed during migration [13309](https://github.com/longhorn/longhorn/issues/13309) - @hookak @chriscchien
- [IMPROVEMENT] Support mTLS encrypted communication for remaining gRPC services in instance manager [7787](https://github.com/longhorn/longhorn/issues/7787) - @COLDTURNIP @yangchiu
- [IMPROVEMENT]  Add metrics to collect information about LONGHORN_DISTRO [13252](https://github.com/longhorn/longhorn/issues/13252) - @derekbit @chriscchien
- [IMPROVEMENT] Exporting a volume from a single replica via crictl command [7711](https://github.com/longhorn/longhorn/issues/7711) - @c3y1huang

### Bug
- [BUG] Runtime container images contain development (-devel) packages [13479](https://github.com/longhorn/longhorn/issues/13479) - @yangchiu @benispeti
- [BUG] DR replicas break [13685](https://github.com/longhorn/longhorn/issues/13685) - @derekbit @chriscchien
- [BUG] Longhorn may not reject expansion requests when the volume clone is in-progress [14065](https://github.com/longhorn/longhorn/issues/14065) - @yangchiu @shuo-wu
- [BUG] Request Schema in Upgrade Responder is Outdate [14027](https://github.com/longhorn/longhorn/issues/14027) - @yangchiu @roger-ryao
- [BUG] Test case `test_csi_block_volume_online_expansion` fails with 'assert md5sum: == ...' on v2 volume (AMD64 only) [14045](https://github.com/longhorn/longhorn/issues/14045) - @derekbit @roger-ryao
- [BUG] `Disconnect Volume Node Network For More Than Pod Eviction Timeout While Workload Heavy Writing With RWX Fast Failover Disabled` fails on v2 data engine [13913](https://github.com/longhorn/longhorn/issues/13913) - @derekbit @shuo-wu @chriscchien
- [BUG] deleting nodes.longhorn.io failed due to KubernetesNodeGone [13494](https://github.com/longhorn/longhorn/issues/13494) - @COLDTURNIP @yangchiu
- [BUG] test `test_single_replica_failed_during_engine_start` fails [13861](https://github.com/longhorn/longhorn/issues/13861) - @davidcheng0922
- [BUG] Cloned volume stuck "not ready for workloads" after the clone finishes (v1.12.0, v1 engine) [13335](https://github.com/longhorn/longhorn/issues/13335) - @roger-ryao @somanchi004-code
- [BUG] SystemRestore job ignores the registry-secret setting [13968](https://github.com/longhorn/longhorn/issues/13968) - @bachmanity1 @roger-ryao
- [BUG] After host restart one node no longer abe to start any replica [13733](https://github.com/longhorn/longhorn/issues/13733) - @roger-ryao
- [BUG] `test_engine_image_not_fully_deployed_perform_dr_restoring_expanding_volume` fails on v1.13.x-head [13974](https://github.com/longhorn/longhorn/issues/13974) - @shuo-wu @chriscchien
- [BUG] v2 workload IO gets stuck in `Continuous IO Test` [13912](https://github.com/longhorn/longhorn/issues/13912) - @yangchiu @c3y1huang
- [BUG] Test case `Test V2 Volume Engine Live Switchover` may fail on v1.13.x-head [13951](https://github.com/longhorn/longhorn/issues/13951) - @yangchiu @davidcheng0922
- [BUG] Terminal workload pods cause NodePublishVolume to abort with "no Pending workload pods" [13723](https://github.com/longhorn/longhorn/issues/13723) - @yangchiu @guolxingxing
- [BUG] v2 volumes might get stuck in `deleting` state [13585](https://github.com/longhorn/longhorn/issues/13585) - @yangchiu @davidcheng0922 @sushant-suse
- [UI][BUG] The restore of V2 Linked Clone volumes misses src volume handling [13922](https://github.com/longhorn/longhorn/issues/13922) - @shuo-wu @roger-ryao
- [BUG] The restore of V2 Linked Clone volumes misses src volume handling [13714](https://github.com/longhorn/longhorn/issues/13714) - @shuo-wu @roger-ryao
- [BUG] Sharded/EC volume: writes stall to ~0 and wedge the SPDK target on arm64/AIO, blocking volume deletion; plus CSI drops EC StorageClass params [13789](https://github.com/longhorn/longhorn/issues/13789) - @c3y1huang @chriscchien
- [BUG] Regression test fails with v2 BDF block disks [13939](https://github.com/longhorn/longhorn/issues/13939) - @yangchiu @davidcheng0922 @sushant-suse
- [BUG] v2 volume gets stuck in `Attaching` in an IPv6 storage network environment [13933](https://github.com/longhorn/longhorn/issues/13933) - @yangchiu @derekbit
- [BUG] CSI volume cloning doesn't respect node-/diskSelector [12792](https://github.com/longhorn/longhorn/issues/12792) - @roger-ryao @carterli0407-cell
- [BUG] [v1.13.0-rc1] V2 volume DD easy to stuck in V2 interrupt mode [13937](https://github.com/longhorn/longhorn/issues/13937) - @au2001 @roger-ryao
- [BUG] v1.12.1 default NetworkPolicies miss legitimate non-pod-labeled and host-originated callers, silently breaking CSI attach/detach [13802](https://github.com/longhorn/longhorn/issues/13802) - @COLDTURNIP @roger-ryao
- [BUG] Replica rebuiliding may fail with `Input/output error` on v2 volumes [13189](https://github.com/longhorn/longhorn/issues/13189) - @derekbit @chriscchien
- [BUG] Test case `Test DR Volume Live Upgrade And Rebuild` fails [13911](https://github.com/longhorn/longhorn/issues/13911) - @yangchiu @derekbit
- [BUG] Creating default disks with `createDefaultDiskLabeledNodes` setting and `create-default-disk` label doesn't work with BDF [13491](https://github.com/longhorn/longhorn/issues/13491) - @yangchiu @davidcheng0922
- [BUG] Test case `test_node_default_disk_labeled` fails [13910](https://github.com/longhorn/longhorn/issues/13910) - @roger-ryao
- [BUG] invalid block disks should not block Longhorn system uninstallation [13572](https://github.com/longhorn/longhorn/issues/13572) - @apoorvajagtap @chriscchien
- [BUG]  The manifests in the /deploy directory of the longhorn/cli repository do not work due to an error in the command: field. [13514](https://github.com/longhorn/longhorn/issues/13514) - @chattytak @roger-ryao
- [BUG] V2 replica rebuild destination failure faults the entire engine [13673](https://github.com/longhorn/longhorn/issues/13673) - @christophersherman @roger-ryao
- [BUG] v1 engine never starts: a stale `stopped` process record makes createInstance a silent no-op, volume stuck in `attaching` forever [13687](https://github.com/longhorn/longhorn/issues/13687) - @derekbit @roger-ryao
- [BUG] SPDK initialization fails on Talos OS with "nsenter: operation not permitted" [12709](https://github.com/longhorn/longhorn/issues/12709) - @c3y1huang @roger-ryao @sushant-suse
- [BUG] V2 expansion can report success while the engine remains at the old size [13379](https://github.com/longhorn/longhorn/issues/13379) - @davidcheng0922 @chriscchien
- [BUG] Recurring trim job fails with deadlock [13416](https://github.com/longhorn/longhorn/issues/13416) - @c3y1huang @roger-ryao
- [BUG] Kernel Workqueue Lockup and Unstable RKE2 Service After Enabling LH V2 in Harvester [13417](https://github.com/longhorn/longhorn/issues/13417) - @derekbit @chriscchien
- [BUG] Failed to add v2 block disk with virtio-scsi BDF path [13474](https://github.com/longhorn/longhorn/issues/13474) - @chriscchien @carterli0407-cell
- [BUG] Longhorn 1.12.0: AWS chunked encoding not supported with OCI S3 buckets [13477](https://github.com/longhorn/longhorn/issues/13477) - @derekbit @mantissahz @roger-ryao
- [BUG] Host OS nvmf-autoconnect connects kernel initiators to v2 replica subsystems, stalling volume attach/detach for minutes [13651](https://github.com/longhorn/longhorn/issues/13651) - @hookak @chriscchien
- [BUG] Adding V2 disk using the "Default Data Path" /dev/disk/by-id/scsi-* path fails [13557](https://github.com/longhorn/longhorn/issues/13557) - @davidcheng0922 @roger-ryao
- [BUG] backupvolume.longhorn.io not updated on cluster with nodes drained [13859](https://github.com/longhorn/longhorn/issues/13859) - @derekbit @chriscchien
- [BUG] Volume expansion snapshot CR name expand-<size> collides across volumes [13386](https://github.com/longhorn/longhorn/issues/13386) - @derekbit @chriscchien
- [BUG] System managed components don't respect System Managed Components Node Selector [12834](https://github.com/longhorn/longhorn/issues/12834) - @COLDTURNIP @yangchiu
- [BUG] Recurring-job pods report success after startup or volume execution errors [13587](https://github.com/longhorn/longhorn/issues/13587) - @christophersherman @roger-ryao
- [BUG] backupvolume.longhorn.io not created on cluster have nodes drained [13775](https://github.com/longhorn/longhorn/issues/13775) - @derekbit @chriscchien
- [BUG] Backup not started on cluster have nodes drained [12562](https://github.com/longhorn/longhorn/issues/12562) - @chriscchien @carterli0407-cell
- [BUG] Test case `Power Off Replica Node Should Not Rebuild New Replica On Same Node` fails [13705](https://github.com/longhorn/longhorn/issues/13705) - @yangchiu @derekbit
- [BUG] v1 replica rebuild fails after a single gRPC TCP keepalive is lost [13703](https://github.com/longhorn/longhorn/issues/13703) - @dnesting @chriscchien
- [BUG] v1.12.1 chart: new default-on `networkPolicies.restrictInternalTraffic` silently breaks Prometheus scraping of longhorn-manager (metrics/alerting blackout on patch upgrade) [13740](https://github.com/longhorn/longhorn/issues/13740) - @COLDTURNIP @roger-ryao
- [BUG] Longhorn UI is not  running with PID 1 [13680](https://github.com/longhorn/longhorn/issues/13680) - @yangchiu @xandau
- [BUG][v1.6.2-rc2] Volume failed to recover after nodes reboot, pod failed to mount the volume with Input/output error [8587](https://github.com/longhorn/longhorn/issues/8587) - @shuo-wu @roger-ryao
- [BUG] Snapshot CR is missing for backup CR of recurring job [10184](https://github.com/longhorn/longhorn/issues/10184) - @yangchiu @christophersherman
- [BUG] V1 volumes not rebuilding after cluster shutdown [13571](https://github.com/longhorn/longhorn/issues/13571) - @COLDTURNIP @yangchiu
- [BUG] Incorrect Web Link in GUI [13352](https://github.com/longhorn/longhorn/issues/13352) - @yangchiu @sushant-suse
- [BUG] V2 backup/snapshot can leave NVMe/TCP frontend or dm device stale, causing pod EIO on attached volumes [13331](https://github.com/longhorn/longhorn/issues/13331) - @davidcheng0922 @chriscchien
- [BUG] Longhorn Helm Chart NetworkPolicies do not honor new RKE2 "rke2-traefik" ingress controller [13653](https://github.com/longhorn/longhorn/issues/13653) - @COLDTURNIP @roger-ryao
- [BUG] v2 volume repeated replica reuse failure [13315](https://github.com/longhorn/longhorn/issues/13315) - @shuo-wu @chriscchien
- [BUG] Longhorn may try to attach volumes to a node without valid IM pod during the clone [13639](https://github.com/longhorn/longhorn/issues/13639) - @yangchiu @shuo-wu
- [BUG] Test case `test_volume_scheduling_failure` fails on v2 volumes [13655](https://github.com/longhorn/longhorn/issues/13655) - @yangchiu @c3y1huang
- [BUG] `Backup Listing With More Than 1000 Backups` fails on v2 volume due to an empty replica address in the backup status [13611](https://github.com/longhorn/longhorn/issues/13611) - @COLDTURNIP @chriscchien
- [BUG] Interrupt Mode V2 stuck high CPU after workload completed [12066](https://github.com/longhorn/longhorn/issues/12066) - @c3y1huang
- [BUG] Encrypted V2 volume size is 16MB short of the claimed size [13163](https://github.com/longhorn/longhorn/issues/13163) - @mantissahz @roger-ryao
- [BUG] Transient SPDK lvol metadata failure can permanently fault a healthy v2 replica [13541](https://github.com/longhorn/longhorn/issues/13541) - @christophersherman @roger-ryao
- [BUG] CSI pods do not respect anti-affinity preset update [13546](https://github.com/longhorn/longhorn/issues/13546) - @chriscchien @carterli0407-cell
- [BUG]  V2 encrypted volume keeps switching between Attaching and Detaching state after expand operation [13561](https://github.com/longhorn/longhorn/issues/13561) - @mantissahz @roger-ryao
- [BUG] Test case `Recurring Job Pod Should Not Crash` fails [13567](https://github.com/longhorn/longhorn/issues/13567) - @yangchiu @c3y1huang
- [BUG] Fail to restore a v2 volume from a full backup if a previous backup is corrupted [13526](https://github.com/longhorn/longhorn/issues/13526) - @yangchiu @derekbit
- [BUG] Error logs in longhorn-uninstall job [13547](https://github.com/longhorn/longhorn/issues/13547) - @yangchiu @c3y1huang
- [BUG] V2 Data Engine: UBLK fails with EINVAL on Linux kernel 6.17.0 [11977](https://github.com/longhorn/longhorn/issues/11977) - @chriscchien @carterli0407-cell
- [BUG] csi.*ReplicaCount Helm values silently no-op on existing csi-* deployments (only applied at first creation) [13461](https://github.com/longhorn/longhorn/issues/13461) - @sebastiangaiser @roger-ryao
- [BUG] v2 volume may crash again after the auto reattachment [13314](https://github.com/longhorn/longhorn/issues/13314) - @shuo-wu @roger-ryao
- [BUG] V2 Encrypted Volume Restore Fails [13363](https://github.com/longhorn/longhorn/issues/13363) - @mantissahz @roger-ryao
- [BUG] (chart) ArgoCD OutOfSync when using Gateway API [13340](https://github.com/longhorn/longhorn/issues/13340) - @yangchiu @SalvoRusso8
- [BUG] Migration Engine Can Be Unexpectedly Deleted If the Target Node Is Still in Readiness Transition [13109](https://github.com/longhorn/longhorn/issues/13109) - @COLDTURNIP @yangchiu
- [BUG] volume expansion stuck [13334](https://github.com/longhorn/longhorn/issues/13334) - @shuo-wu @roger-ryao
- [BUG] expanding the volume fails [13355](https://github.com/longhorn/longhorn/issues/13355) - @AoRuiAC @chriscchien
- [BUG] Test case `test_rwx_delete_share_manager_pod` fails because it's unable to find the exported volume in share manager pod after it's deleted and restarted [13221](https://github.com/longhorn/longhorn/issues/13221) - @davidcheng0922 @roger-ryao
- [BUG] System Backup RecurringJob retention prunes newest CR — sorts by Status.CreatedAt (zero for Error/racing CRs) [13203](https://github.com/longhorn/longhorn/issues/13203) - @issmirnov @roger-ryao
- [BUG] CSI components may have 0 running replica during upgrade [13105](https://github.com/longhorn/longhorn/issues/13105) - @yangchiu @carterli0407-cell
- [BUG] Test case `test_best_effort_data_locality` fails because there is no replica for the created volume [13222](https://github.com/longhorn/longhorn/issues/13222) - @yangchiu @carterli0407-cell
- [BUG] spdk interrupt mode value is missing in chart/values.yaml [13266](https://github.com/longhorn/longhorn/issues/13266) - @yangchiu @kema-dev
- [BUG] Misconfigured and deleted Talos node causes Driver Deployer to constantly restart [12159](https://github.com/longhorn/longhorn/issues/12159) - @c3y1huang

### Resilience
- [BUG] V2 instance-manager liveness probe errors ('test: -eq: unary operator expected') -> self-kill -> node-wide replica fault under rebuild load [13957](https://github.com/longhorn/longhorn/issues/13957) - @yangchiu @mantissahz @Copilot
- [DOC] Enhance Longhorn docs about Instance Manager [13197](https://github.com/longhorn/longhorn/issues/13197) - @Felipalds @chriscchien
- [BUG] V2 Instance Manager panics in backupstore when S3 volume.cfg is missing, taking all node volumes offline [13790](https://github.com/longhorn/longhorn/issues/13790) - @mantissahz @chriscchien

### Stability
- [BUG] V2 backup readers race snapshot cleanup and panic the instance manager [14017](https://github.com/longhorn/longhorn/issues/14017) - @christophersherman @roger-ryao
- [BUG] Recurring snapshot-cleanup aborts the entire run when any volume's replica is rebuilding [13623](https://github.com/longhorn/longhorn/issues/13623) - @derekbit @chriscchien

### Misc
- [DOC] the upgrade behavior for volumes differs between the v1 and v2 data engines [14023](https://github.com/longhorn/longhorn/issues/14023) - @mantissahz @chriscchien
- [IMPROVEMENT] Chart value to allow metrics scrapers through the longhorn-manager NetworkPolicy [13947](https://github.com/longhorn/longhorn/issues/13947) - @alekc @yangchiu
- [IMPROVEMENT] Help large replicas on full disks reclaim the space and squash all data into the heads [13636](https://github.com/longhorn/longhorn/issues/13636) - @apoorvajagtap @roger-ryao
- [DOC] Remove backing image dependency from v2 BI backup guide [13858](https://github.com/longhorn/longhorn/issues/13858) - @COLDTURNIP @chriscchien
- [BUG] Longhorn block disk remains Ready=False and Schedulable=False when NVMe device is bound to vfio-pci [13893](https://github.com/longhorn/longhorn/issues/13893) - @derekbit @chriscchien
- [DOC] Add Data Path Diagrams for V1 and V2 Data Engines [13570](https://github.com/longhorn/longhorn/issues/13570) - @derekbit @chriscchien
- [TASK] Clarify the share manager NFS server dual-stack compatibility [13900](https://github.com/longhorn/longhorn/issues/13900) - @COLDTURNIP
- [DOC] Broken image URL for OpenShift OAuth proxy [13339](https://github.com/longhorn/longhorn/issues/13339) - @geragio @roger-ryao
- [DOC] Create a Rancher Chart Generation and Release Wiki Page [13346](https://github.com/longhorn/longhorn/issues/13346) - @carterli0407-cell
- [TASK] document to cleanup orphaned backing image copies manually [13523](https://github.com/longhorn/longhorn/issues/13523) - @COLDTURNIP @chriscchien
- [BUG] CSI method-level request logs bypass secret sanitization [13613](https://github.com/longhorn/longhorn/issues/13613) - @anthonymartin @yangchiu
- [DOC] Improve contributing documentation [10814](https://github.com/longhorn/longhorn/issues/10814) - @derekbit
- [DOC] NetworkPolicy setup guidance [13591](https://github.com/longhorn/longhorn/issues/13591) - @COLDTURNIP @roger-ryao
- [DOC] Chart values.yaml still refers to Data Engine V2 as experimental [13614](https://github.com/longhorn/longhorn/issues/13614) - @sushant-suse
- [TASK] fix longhorn-instance-manager lint validation failure [13313](https://github.com/longhorn/longhorn/issues/13313) - @COLDTURNIP @roger-ryao
- [IMPROVEMENT] Add opt-in PodDisruptionBudget for the Longhorn UI Deployment [13466](https://github.com/longhorn/longhorn/issues/13466) - @yangchiu @somaz94
- [DOC] Update the minimum Kubernetes version requirement to v1.34 [13576](https://github.com/longhorn/longhorn/issues/13576) - @derekbit @roger-ryao
- [BUG] v2 volume stuck `attaching` with Storage Network enabled because the `EngineFrontend` target uses the engine pod IP instead of `StorageIP` [13351](https://github.com/longhorn/longhorn/issues/13351) - @yangchiu @c3y1huang
- [FEATURE] Support Kubernetes CPU Manager for Longhorn V2 instance-manager SPDK CPU assignment [13248](https://github.com/longhorn/longhorn/issues/13248) - @yangchiu @mantissahz
- [REFACTOR] Refactor longhorn-spdk-engine codes [12491](https://github.com/longhorn/longhorn/issues/12491) - @derekbit
- [TASK] Remove downstream security patches for CSI sidecar images [13329](https://github.com/longhorn/longhorn/issues/13329) - @derekbit

## Contributors
- @98jan
- @AoRuiAC
- @COLDTURNIP
- @ChaoHuang2018
- @DrJosh9000
- @Felipalds
- @HypeMC
- @IggyGG
- @Martin-Weiss
- @NRCan-LGariepy
- @PhanLe1010
- @SalvoRusso8
- @WebberHuang1118
- @Xeboc
- @a110605
- @abonillabeeche
- @alekc
- @anthonymartin
- @antoinemichea
- @apoorvajagtap
- @au2001
- @bachmanity1
- @benispeti
- @boomam
- @brandboat
- @c3y1huang
- @carterli0407-cell
- @chattytak
- @chriscchien
- @christophersherman
- @cosmo-wang
- @daftu
- @darkpixel
- @davidcheng0922
- @derekbit
- @divya-mohan0209
- @dnesting
- @eklatzer
- @foobardmr
- @geragio
- @guolxingxing
- @hookak
- @houhoucoop
- @innobead
- @issmirnov
- @jabrown93
- @jkempson
- @jzaehrin
- @kema-dev
- @kinorai
- @kolonelkrazy
- @kondanta
- @lictw
- @mantissahz
- @mydoomfr
- @rd-eng
- @rdoxenham
- @roger-ryao
- @seanblake
- @sebastiangaiser
- @shuo-wu
- @somanchi004-code
- @somaz94
- @steled
- @sushant-suse
- @tarlomitico
- @tvanderka
- @vanchaxy
- @xandau
- @yangchiu
- @yasker
- @yhamouda
- @zauguin
- @rebeccazzzz
- @forbesguthrie
- @asettle
