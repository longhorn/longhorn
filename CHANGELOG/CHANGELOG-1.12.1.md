# Longhorn v1.12.1 Release Notes

Longhorn v1.12.1 introduces V2 Data Engine fast volume cloning and storage sharding (experimental), along with important improvements and bug fixes that enhance system quality, resilience, stability, and security.

We welcome feedback and contributions to help continuously improve Longhorn.

For terminology and context on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

## Breaking Changes

### Deprecation of Legacy V2 Linked Clone Volumes

V2 linked-clone volumes created in v1.12.0 or earlier are marked as legacy and deprecated starting in v1.12.1. The new linked-clone architecture introduced in [Issue #12552](https://github.com/longhorn/longhorn/issues/12552) is not compatible with the legacy design.

After upgrading to v1.12.1, **legacy linked-clone volumes cannot be operated on except for detachment and deletion**.

To replace, create new linked-clone volumes from the same source volumes that back the legacy ones. As long as a legacy volume exists, its source volume is guaranteed to still be present, so you can create a replacement linked clone directly; no data copy is required.

For more information, see [Issue #12552](https://github.com/longhorn/longhorn/issues/12552).

## Highlighted Features

### Fast Volume Cloning

Longhorn v1.12.1 enhances fast volume cloning for the V2 Data Engine. A `linked-clone` volume shares data blocks with its source instead of copying data. With the new architecture, a source replica can share its data blocks with multiple linked-clone volumes, and multiple clone replicas can be created in parallel.

Linked-clone volumes now support most operations available to regular volumes, including snapshots, expansion, replica rebuilding, and use as the source of nested linked clones.

For more information, see [Issue #12552](https://github.com/longhorn/longhorn/issues/12552) and [CSI Volume Clone](https://longhorn.io/docs/1.12.1/snapshots-and-backups/csi-volume-clone).

> [!NOTE]
**V2 fast cloning does not currently support volume backup and restore. This improvement is tracked in [Issue #13714](https://github.com/longhorn/longhorn/issues/13714).**

### Storage Sharding (Experimental)

Longhorn v1.12.1 introduces storage sharding as an experimental data protection and storage layout feature built on the V2 Data Engine. Instead of storing a full copy of the volume on each replica, sharding uses erasure coding to encode written data into data and parity chunks, which are distributed across multiple nodes. This allows a volume to grow beyond the capacity of a single disk or node while using less disk space to achieve the same level of fault tolerance.

Because this feature is experimental, it is intended for evaluation and testing only and is not recommended for production use.

For more information, see [Issue #1061](https://github.com/longhorn/longhorn/issues/1061) and [Sharding with Erasure Coding](https://longhorn.io/docs/1.12.1/advanced-resources/v2-data-engine/sharding).

## Important Improvements and Fixes

This release includes several important improvements and critical stability fixes.

### Internal Network Policies

Longhorn v1.12.1 enables ingress `NetworkPolicy` resources for internal component endpoints and RPCs by default to improve security by restricting access to Longhorn internal services, including the instance-manager gRPC endpoint used for engine control. These policies only take effect when a `NetworkPolicy` provider is available in the cluster.

Longhorn has validated the internal network policies with the following Kubernetes distribution and CNI plugin combinations. See the [CNI Plugin Compatibility](https://longhorn.io/docs/1.12.1/best-practices/#cni-plugin-compatibility) table for the validated combinations. The minimum required Kubernetes version is v1.25.

For more information and troubleshooting guidance, see [Internal Network Policies](https://longhorn.io/docs/1.12.1/important-notes/#internal-network-policies) and [Issue #13438](https://github.com/longhorn/longhorn/issues/13438).

> [!NOTE]
**ServiceMonitor discovery does not automatically authorize network traffic. Cross-namespace Prometheus scrapers might be blocked by the Longhorn Manager's network policy. To allow this traffic, apply a scoped additive policy as detailed in the [Prometheus and Grafana setup](https://longhorn.io/docs/1.12.1/monitoring/prometheus-and-grafana-setup/) guide.**


### Instance Manager gRPC mTLS Coverage

In previous versions, mutual TLS (mTLS) for the instance-manager gRPC endpoint only covered the instance and proxy services when the `longhorn-grpc-tls` secret was configured. Other services, including the disk service and the SPDK service, accepted plaintext connections.

Longhorn v1.12.1 extends mTLS to all remaining instance-manager gRPC services, so every gRPC port now requires a valid client certificate when the `longhorn-grpc-tls` secret is configured.

For more information, see [Issue #7787](https://github.com/longhorn/longhorn/issues/7787).

### CPU Core Allocation with the Kubernetes CPU Manager

Longhorn v1.12.1 can allocate exclusive CPU cores to the SPDK target daemon, which runs in each V2 Instance Manager pod, through the Kubernetes CPU Manager by using the `data-engine-number-of-cpu-cores` setting.

The setting can be applied only when the kubelet CPU Manager policy is set to `static` on all worker nodes; otherwise, the update is rejected. When the value is positive, it takes precedence, and `data-engine-cpu-mask` is ignored.

For more information, see [Issue #13248](https://github.com/longhorn/longhorn/issues/13248).

### Host CPU Isolation

The `data-engine-cpu-isolation-enabled` setting now also configures host network Receive Packet Steering (RPS) to steer RX softirq processing away from the CPU cores used by the SPDK target daemon, in addition to hardware IRQs and unbound kernel workqueue workers. Without this, the kernel can distribute incoming network packets to the SPDK reactor cores, and the resulting softirq work competes with the reactor's busy-poll loop, degrading volume I/O under network load.

For more information, see [Issue #13483](https://github.com/longhorn/longhorn/issues/13483) and [Issue #13502](https://github.com/longhorn/longhorn/issues/13502).

### V2 Data Engine SPDK iobuf Pool Size Configuration

Longhorn v1.12.1 allows tuning the SPDK iobuf buffer pools used by the V2 Data Engine. The `data-engine-iobuf-large-pool-size` and `data-engine-iobuf-small-pool-size` settings configure the large and 8 KiB small buffer pools, respectively. Increasing the small pool can relieve buffer exhaustion under high-queue-depth workloads with small I/O sizes. Because iobuf pools can only be sized at SPDK target startup, changing either setting recreates V2 Instance Manager pods that have no running instances.

For more information, see [Issue #13322](https://github.com/longhorn/longhorn/issues/13322) and [Issue #13674](https://github.com/longhorn/longhorn/issues/13674).

### Encrypted Volume Size Correction

Longhorn reserves an additional 16 MiB of raw capacity for the LUKS2 metadata used by encrypted volumes, allowing the mapped device to expose the full capacity requested by the workload. Previously, the metadata was taken from usable capacity, so a requested 1 GiB encrypted volume exposed only 1008 MiB. This discrepancy could cause operations such as block-level copies between equally sized unencrypted and encrypted volumes to fail.

- **V1 Data Engine**: This correction was introduced in Longhorn v1.12.0. Existing encrypted V1 volumes created with v1.11.x or earlier receive the additional capacity automatically when their engine image is upgraded to v1.12 or later. Encrypted migratable V1 volumes cannot be live-migrated until they are upgraded to the version (>= v1.12.0).
- **V2 Data Engine**: Longhorn v1.12.1 applies the correction to newly created encrypted V2 volumes.

> [!NOTE]
**Encrypted V2 volumes created before v1.12.1, and volumes restored from the backup of such volumes, do not receive the additional 16 MiB of raw capacity and continue to expose 16 MiB less than requested. Existing data is preserved.**

For more information, see [Issue #9205](https://github.com/longhorn/longhorn/issues/9205) and [Issue #13163](https://github.com/longhorn/longhorn/issues/13163).

## Installation

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.12.1.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.12.1/deploy/install/) in the Longhorn documentation.

## Upgrade

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.12.1.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.12.1/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues in this release

### Highlight

- [BACKPORT][v1.12.1][UI][FEATURE] V2 Data Engine Fast Cloning [13672](https://github.com/longhorn/longhorn/issues/13672) - @shuo-wu @roger-ryao
- [BACKPORT][v1.12.1][FEATURE] V2 Data Engine Sharding - Experimental [13176](https://github.com/longhorn/longhorn/issues/13176) - @c3y1huang @chriscchien
- [BACKPORT][v1.12.1][FEATURE] V2 Data Engine Fast Cloning [13174](https://github.com/longhorn/longhorn/issues/13174) - @shuo-wu @roger-ryao

### Feature
- [BACKPORT][v1.12.1][FEATURE] Support Kubernetes CPU Manager for Longhorn V2 instance-manager SPDK CPU assignment [13320](https://github.com/longhorn/longhorn/issues/13320) - @yangchiu @mantissahz @Copilot

### Improvement

- [BACKPORT][v1.12.1][IMPROVEMENT] Allow configuring SPDK iobuf small pool size [13675](https://github.com/longhorn/longhorn/issues/13675) - @yangchiu @hookak
- [BACKPORT][v1.12.1][IMPROVEMENT] go-common-libs: kill the child process when command execution times out [13621](https://github.com/longhorn/longhorn/issues/13621) - @hookak
- [BACKPORT][v1.12.1][IMPROVEMENT] always setup NetworkPolicy for the internal communication [13439](https://github.com/longhorn/longhorn/issues/13439) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.12.1][IMPROVEMENT] Steer host RPS away from SPDK reactor cores [13502](https://github.com/longhorn/longhorn/issues/13502) - @bachmanity1 @roger-ryao
- [BACKPORT][v1.12.1][IMPROVEMENT] updateBackupCompressionMethod may write the Volume even when the method is unchanged [13480](https://github.com/longhorn/longhorn/issues/13480) - @yangchiu
- [BACKPORT][v1.12.1][IMPROVEMENT] Add metrics to collect information about V2 data engine usage [13262](https://github.com/longhorn/longhorn/issues/13262) - @derekbit @chriscchien
- [BACKPORT][v1.12.1][IMPROVEMENT] Improving error transparency for volume attachment failure [13431](https://github.com/longhorn/longhorn/issues/13431) - @derekbit @chriscchien
- [BACKPORT][v1.12.1][IMPROVEMENT] Allow configuring SPDK iobuf large pool size [13415](https://github.com/longhorn/longhorn/issues/13415) - @chriscchien @bachmanity1
- [BACKPORT][v1.12.1][IMPROVEMENT] V2 volume write I/O stalls(~10s) when a replica is removed during migration [13310](https://github.com/longhorn/longhorn/issues/13310) - @hookak @chriscchien
- [BACKPORT][v1.12.1][IMPROVEMENT] Support mTLS encrypted communication for remaining gRPC services in instance manager [13299](https://github.com/longhorn/longhorn/issues/13299) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.12.1][IMPROVEMENT]  Add metrics to collect information about LONGHORN_DISTRO [13253](https://github.com/longhorn/longhorn/issues/13253) - @derekbit @chriscchien

### Bug

- [BACKPORT][v1.12.1][BUG] Host OS nvmf-autoconnect connects kernel initiators to v2 replica subsystems, stalling volume attach/detach for minutes [13660](https://github.com/longhorn/longhorn/issues/13660) - @hookak @chriscchien
- [BACKPORT][v1.12.1][BUG] Longhorn Helm Chart NetworkPolicies do not honor new RKE2 "rke2-traefik" ingress controller [13665](https://github.com/longhorn/longhorn/issues/13665) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.12.1][BUG] Longhorn may try to attach volumes to a node without valid IM pod during the clone [13640](https://github.com/longhorn/longhorn/issues/13640) - @yangchiu @shuo-wu
- [BACKPORT][v1.12.1][BUG] Test case `test_volume_scheduling_failure` fails on v2 volumes [13656](https://github.com/longhorn/longhorn/issues/13656) - @yangchiu @c3y1huang
- [BACKPORT][v1.12.1][BUG] `Backup Listing With More Than 1000 Backups` fails on v2 volume due to an empty replica address in the backup status [13612](https://github.com/longhorn/longhorn/issues/13612) - @COLDTURNIP @chriscchien
- [BACKPORT][v1.12.1][BUG] Incorrect Web Link in GUI [13539](https://github.com/longhorn/longhorn/issues/13539) - @yangchiu @sushant-suse
- [BACKPORT][v1.12.1][BUG] Encrypted V2 volume size is 16MB short of the claimed size [13175](https://github.com/longhorn/longhorn/issues/13175) - @mantissahz @roger-ryao
- [BACKPORT][v1.12.1][BUG] CSI pods do not respect anti-affinity preset update [13548](https://github.com/longhorn/longhorn/issues/13548) - @chriscchien @carterli0407-cell
- [BACKPORT][v1.12.1][BUG] Failed to add v2 block disk with virtio-scsi BDF path [13475](https://github.com/longhorn/longhorn/issues/13475) - @chriscchien @carterli0407-cell
- [BACKPORT][v1.12.1][BUG]  V2 encrypted volume keeps switching between Attaching and Detaching state after expand operation [13562](https://github.com/longhorn/longhorn/issues/13562) - @mantissahz @roger-ryao
- [BACKPORT][v1.12.1][BUG] GCS backup target: backup of large volume fails at final .cfg PUT with SignatureDoesNotMatch (residual of #12676 in v1.12.0) [13574](https://github.com/longhorn/longhorn/issues/13574) - @derekbit @chriscchien
- [BACKPORT][v1.12.1][BUG] Fail to restore a volume from a full backup if a previous backup is corrupted [13538](https://github.com/longhorn/longhorn/issues/13538) - @yangchiu @derekbit
- [BACKPORT][v1.12.1][BUG] Test case `Recurring Job Pod Should Not Crash` fails [13568](https://github.com/longhorn/longhorn/issues/13568) - @yangchiu @c3y1huang
- [BACKPORT][v1.12.1][BUG] Longhorn 1.12.0: AWS chunked encoding not supported with OCI S3 buckets [13478](https://github.com/longhorn/longhorn/issues/13478) - @derekbit @mantissahz @roger-ryao
- [BACKPORT][v1.12.1][BUG] Error logs in longhorn-uninstall job [13549](https://github.com/longhorn/longhorn/issues/13549) - @yangchiu @c3y1huang
- [BACKPORT][v1.12.1][BUG] V2 Data Engine: UBLK fails with EINVAL on Linux kernel 6.17.0 [13274](https://github.com/longhorn/longhorn/issues/13274) - @chriscchien @carterli0407-cell
- [BACKPORT][v1.12.1][BUG] Kernel Workqueue Lockup and Unstable RKE2 Service After Enabling LH V2 in Harvester [13495](https://github.com/longhorn/longhorn/issues/13495) - @derekbit @chriscchien
- [BACKPORT][v1.12.1][BUG] V2 expansion can report success while the engine remains at the old size [13380](https://github.com/longhorn/longhorn/issues/13380) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.12.1][BUG] FilesystemReadOnly never detected on kernel >= 6.12 — ext4 reports emergency_ro, not ro; read-only auto-remount silently inoperative [13482](https://github.com/longhorn/longhorn/issues/13482) - @yangchiu
- [BACKPORT][v1.12.1][BUG] csi.*ReplicaCount Helm values silently no-op on existing csi-* deployments (only applied at first creation) [13465](https://github.com/longhorn/longhorn/issues/13465) - @roger-ryao
- [BACKPORT][v1.12.1][BUG] v2 volume may crash again after the auto reattachment [13337](https://github.com/longhorn/longhorn/issues/13337) - @shuo-wu @roger-ryao
- [BACKPORT][v1.12.1][BUG] V2 Volume Cannot Be Attached When the Storage Network Is Enabled [13490](https://github.com/longhorn/longhorn/issues/13490) - @c3y1huang
- [BACKPORT][v1.12.1][BUG] v2 volume repeated replica reuse failure [13336](https://github.com/longhorn/longhorn/issues/13336) - @shuo-wu @chriscchien
- [BACKPORT][v1.12.1][BUG] V2 Encrypted Volume Restore Fails [13365](https://github.com/longhorn/longhorn/issues/13365) - @mantissahz @roger-ryao
- [BACKPORT][v1.12.1][BUG] V2 backup/snapshot can leave NVMe/TCP frontend or dm device stale, causing pod EIO on attached volumes [13332](https://github.com/longhorn/longhorn/issues/13332) - @davidcheng0922 @chriscchien
- [BACKPORT][v1.12.1][BUG] (chart) ArgoCD OutOfSync when using Gateway API [13446](https://github.com/longhorn/longhorn/issues/13446) - @yangchiu
- [BACKPORT][v1.12.1][BUG] Migration Engine Can Be Unexpectedly Deleted If the Target Node Is Still in Readiness Transition [13367](https://github.com/longhorn/longhorn/issues/13367) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.12.1][BUG] Recurring trim job fails with deadlock [13425](https://github.com/longhorn/longhorn/issues/13425) - @c3y1huang @roger-ryao
- [BACKPORT][v1.12.1][BUG] volume expansion stuck [13368](https://github.com/longhorn/longhorn/issues/13368) - @shuo-wu @chriscchien
- [BACKPORT][v1.12.1][BUG] pvc resize fails after iscsid restart [13412](https://github.com/longhorn/longhorn/issues/13412) - @yangchiu @shuo-wu
- [BACKPORT][v1.12.1][BUG] expanding the volume fails [13384](https://github.com/longhorn/longhorn/issues/13384) - @chriscchien
- [BACKPORT][v1.12.1][BUG] Test case `test_rwx_delete_share_manager_pod` fails because it's unable to find the exported volume in share manager pod after it's deleted and restarted [13226](https://github.com/longhorn/longhorn/issues/13226) - @davidcheng0922 @roger-ryao
- [BACKPORT][v1.12.1][BUG] System Backup RecurringJob retention prunes newest CR — sorts by Status.CreatedAt (zero for Error/racing CRs) [13209](https://github.com/longhorn/longhorn/issues/13209) - @roger-ryao
- [BACKPORT][v1.12.1][BUG] CSI components may have 0 running replica during upgrade [13348](https://github.com/longhorn/longhorn/issues/13348) - @yangchiu @carterli0407-cell
- [BACKPORT][v1.12.1][BUG] Node update forces a complete rebuild [13357](https://github.com/longhorn/longhorn/issues/13357) - @mantissahz
- [BACKPORT][v1.12.1][BUG] Creating backup for a v2 volume may fail [13191](https://github.com/longhorn/longhorn/issues/13191) - @mantissahz
- [BACKPORT][v1.12.1][BUG] when uploading backup to S3 storage (NetApp appliance) it fails [13297](https://github.com/longhorn/longhorn/issues/13297) - @mantissahz
- [BACKPORT][v1.12.1][BUG] spdk interrupt mode value is missing in chart/values.yaml [13269](https://github.com/longhorn/longhorn/issues/13269) - @yangchiu

### Resilience

- [BACKPORT][v1.12.1][BUG] Transient SPDK lvol metadata failure can permanently fault a healthy v2 replica [13542](https://github.com/longhorn/longhorn/issues/13542) - @roger-ryao

### Misc

- [BACKPORT][v1.12.1][DOC] NetworkPolicy setup guidance [13622](https://github.com/longhorn/longhorn/issues/13622) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.12.1][DOC] Chart values.yaml still refers to Data Engine V2 as experimental [13615](https://github.com/longhorn/longhorn/issues/13615) - @sushant-suse
- [BACKPORT][v1.12.1][DOC] Update the minimum Kubernetes version requirement to v1.34. [13577](https://github.com/longhorn/longhorn/issues/13577) - @derekbit @roger-ryao
- [BACKPORT][v1.12.1][BUG] v2 volume stuck `attaching` with Storage Network enabled because the `EngineFrontend` target uses the engine pod IP instead of `StorageIP` [13353](https://github.com/longhorn/longhorn/issues/13353) - @yangchiu @c3y1huang

## Contributors

- @COLDTURNIP 
- @bachmanity1 
- @c3y1huang 
- @carterli0407-cell 
- @chriscchien 
- @davidcheng0922 
- @derekbit 
- @hookak 
- @innobead 
- @mantissahz 
- @roger-ryao 
- @shuo-wu 
- @sushant-suse 
- @yangchiu 
- @rebeccazzzz
- @forbesguthrie
- @asettle
