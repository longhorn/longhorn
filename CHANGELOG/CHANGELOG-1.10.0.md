# Longhorn v1.10.0 Release Notes

Longhorn v1.10.0 is a major release focused on improving stability, performance, and the overall user experience. This version introduces significant enhancements to our core features, including the V2 Data Engine, and streamlines configuration for easier management.

The key highlights include improvements to the V2 Data Engine, enhanced resilience, simplified configuration, and better observability.

We welcome feedback and contributions to help continuously improve Longhorn.

For terminology and context on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

## Removal

### `longhorn.io/v1beta1` API

The `v1beta1` Longhorn API version has been removed.

See [GitHub Issue #10249](https://github.com/longhorn/longhorn/issues/10249) for details.

### `replica.status.evictionRequested` Field

The deprecated `replica.status.evictionRequested` field has been removed.

See [GitHub Issue #7022](https://github.com/longhorn/longhorn/issues/7022) for details.

## Primary Highlights

### New V2 Data Engine Features

#### Interrupt Mode Support

Interrupt mode has been added to the V2 Data Engine to help reduce CPU usage. This feature is especially beneficial for clusters with idle or low I/O workloads, where conserving CPU resources is more important than minimizing latency.

While interrupt mode lowers CPU consumption, it may introduce slightly higher I/O latency compared to polling mode. In addition, the current implementation uses a hybrid approach, which still incurs a minimal, constant CPU load even when interrupts are enabled.

> [!NOTE]
> **Limitation:** Supports **AIO disks only**.

See [Interrupt Mode](https://longhorn.io/docs/1.10.0/v2-data-engine/features/interrupt-mode) and [GitHub Issue#9834](https://github.com/longhorn/longhorn/issues/9834) for details.

#### Volume and Snapshot Cloning

V2 volumes now support two types of cloning:

- **Full-Copy Clone**: Creates a new PVC with a complete, independent copy of the source data, providing full isolation.
- **Linked-Clone (Fast/Smart Clone)**: Creates a PVC that shares data blocks with the source volume for near-instant creation. Ideal for temporary workloads, backups, or testing. Linked-clones are lightweight, fast, and reduce storage overhead.

See [Volume Clone Support](https://longhorn.io/docs/1.10.0/v2-data-engine/features/volume-clone) and [GitHub Issue#7794](https://github.com/longhorn/longhorn/issues/7794) for details.

#### Replica Rebuild QoS

Provides Quality of Service (QoS) control for V2 volume replica rebuilds. You can configure bandwidth limits globally or per volume to prevent storage throughput overload on source and destination nodes.

See [Replica Rebuild QoS](https://longhorn.io/docs/1.10.0/v2-data-engine/features/replica-rebuild-qos) and [GitHub Issue#10770](https://github.com/longhorn/longhorn/issues/10770) for details.

#### Volume Expansion

Longhorn now supports volume expansion for V2 Data Engine volumes. You can expand the volume through the UI or by modifying the PVC manifest.

See [V2 Volume Expansion](https://longhorn.io/docs/1.10.0/v2-data-engine/features/volume-expansion) and [GitHub Issue#8022](https://github.com/longhorn/longhorn/issues/8022) for details.

#### Support for Running Without Hugepages

This reduces memory pressure on low-spec nodes and increases deployment flexibility. Performance may be lower compared to running with Hugepages.

See [GitHub Issue#7066](https://github.com/longhorn/longhorn/issues/7066) for details.

### New V1 Data Engine Features

#### IPv6 Support

V1 volumes now support single-stack IPv6 Kubernetes clusters.

> **Warning:** Dual-stack Kubernetes clusters and V2 volumes are **not supported** in this release.

See [GitHub Issue #2259](https://github.com/longhorn/longhorn/issues/2259) for details.

### Consolidated Global Settings

To simplify management, Longhorn settings are now unified across V1 and V2 Data Engines, using a new, more flexible JSON format.

- **Single value (applies to all Data Engines)**: Non-JSON string (e.g., `1024`).
- **Data-engine-specific**: JSON object (e.g., `{"v1": "value1", "v2": "value2"}`)
- **V1-only**: JSON object with v1 key (e.g., `{"v1":"value1"}`).
- **V2-only**: JSON object with v2 key (e.g., `{"v2":"value1"}`).

See [Longhorn Settings](https://longhorn.io/docs/1.10.0/references/settings) and [GitHub Issue#10926](https://github.com/longhorn/longhorn/issues/10926) for details.

### Pod Scheduling with CSIStorageCapacity

Longhorn now supports **CSIStorageCapacity**, allowing Kubernetes to verify node storage before scheduling pods using StorageClasses with **WaitForFirstConsumer**. This reduces scheduling errors and improves reliability.

See [GitHub Issue #10685](https://github.com/longhorn/longhorn/issues/10685) for details.

### Configurable Backup Block Size

Backup block size can now be configured when creating a volume to optimize performance and efficiency.

See [Create Longhorn Volumes](https://longhorn.io/docs/1.10.0/nodes-and-volumes/volumes/create-volumes) and [GitHub Issue#5215](https://github.com/longhorn/longhorn/issues/5215) for details.

### Volume Attachment Summary

The UI now shows a summary of attachment tickets on each volume page for improved visibility.

See [GitHub Issue #11400](https://github.com/longhorn/longhorn/issues/11400) for details.

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.10.0.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.10.0/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.9.x to v1.10.0.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.10.0/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

### Highlight

- [FEATURE] V2 Volume Supports Cloning [7794](https://github.com/longhorn/longhorn/issues/7794) - @yangchiu @PhanLe1010
- [FEATURE] v2 supports volume expansion [8022](https://github.com/longhorn/longhorn/issues/8022) - @davidcheng0922 @chriscchien
- [UI][FEATURE] V2 Volume Supports Cloning [11736](https://github.com/longhorn/longhorn/issues/11736) - @yangchiu @houhoucoop
- [FEATURE] V2 volumes support interrupt mode [9834](https://github.com/longhorn/longhorn/issues/9834) - @yangchiu @c3y1huang
- [FEATURE] Support v2 volume without hugepage [7066](https://github.com/longhorn/longhorn/issues/7066) - @derekbit @chriscchien
- [FEATURE] Configurable Backup Block Size [5215](https://github.com/longhorn/longhorn/issues/5215) - @COLDTURNIP @yangchiu
- [UI][FEATURE] Configurable Backup Block Size [11586](https://github.com/longhorn/longhorn/issues/11586) - 
- [FEATURE]  Add QoS support to limit replica rebuilding load [10770](https://github.com/longhorn/longhorn/issues/10770) - @hookak @roger-ryao
- [FEATURE]  Volume granular setting parity for V2 to match V1 data engine [10926](https://github.com/longhorn/longhorn/issues/10926) - @derekbit @chriscchien
- [IMPROVEMENT] Support CSIStorageCapacity in Longhorn CSI driver to enable capacity-aware pod scheduling [10685](https://github.com/longhorn/longhorn/issues/10685) - @bachmanity1 @roger-ryao
- [FEATURE] IPV6 for V1 Data Engine [2259](https://github.com/longhorn/longhorn/issues/2259) - @yangchiu @c3y1huang
- [FEATURE] Delta Replica Rebuilding using Delta Snapshot: Control and Data Planes [10037](https://github.com/longhorn/longhorn/issues/10037) - @shuo-wu @roger-ryao
- [FEATURE] Remove v1beta1 API CRD in Longhorn v1.10 [10249](https://github.com/longhorn/longhorn/issues/10249) - @derekbit @roger-ryao

### Feature

- [FEATURE] Add option to restart kubelet through `longhornctl` after huge page update [11241](https://github.com/longhorn/longhorn/issues/11241) - @chriscchien @bachmanity1
- [UI][FEATURE] Configurable Backup Block Size [11351](https://github.com/longhorn/longhorn/issues/11351) - @yangchiu @houhoucoop
- [UI][FEATURE] Display a summary of the attachment tickets in an individual volume's overview page [11401](https://github.com/longhorn/longhorn/issues/11401) - @yangchiu @houhoucoop
- [UI][FEATURE]  Add QoS support to limit replica rebuilding load [11306](https://github.com/longhorn/longhorn/issues/11306) - @davidcheng0922 @houhoucoop @roger-ryao
- [UI][FEATURE]  Volume granular setting parity for V2 to match V1 data engine [11354](https://github.com/longhorn/longhorn/issues/11354) - @chriscchien @houhoucoop
- [FEATURE] Display a summary of the attachment tickets in an individual volume's overview page [11400](https://github.com/longhorn/longhorn/issues/11400) - @yangchiu @davidcheng0922
- [FEATURE] Allow longhorn to restart pods with custom controllers, while the `Automatically Delete Workload Pod when The Volume Is Detached Unexpectedly` feature is enabled [8353](https://github.com/longhorn/longhorn/issues/8353) - @derekbit @roger-ryao
- [FEATURE] Standardized way to override container image registry [11064](https://github.com/longhorn/longhorn/issues/11064) - @marcosbc @yangchiu @roger-ryao
- [FEATURE] Standardized way to specify image pull secrets [11062](https://github.com/longhorn/longhorn/issues/11062) - @marcosbc @chriscchien

### Improvement

- [IMPROVEMENT] Add usage metrics for Longhorn installation variant [11792](https://github.com/longhorn/longhorn/issues/11792) - @derekbit
- [IMPROVEMENT] Allow applying different values of snapshot checksum related settings for v1 and v2 data engine [11537](https://github.com/longhorn/longhorn/issues/11537) - @chriscchien @nzhan126
- [IMPROVEMENT] Make `longhornctl` usable in air-gapped environments [11291](https://github.com/longhorn/longhorn/issues/11291) - @chriscchien @bachmanity1
- [IMPROVEMENT] SAST Potential dereference of the null pointer in controller/volume_controller.go in longhorn-manager [11780](https://github.com/longhorn/longhorn/issues/11780) - @c3y1huang
- [IMPROVEMENT] Collect Logs from the Host Directory Defined by the Setting `log-path` [11522](https://github.com/longhorn/longhorn/issues/11522) - @c3y1huang @roger-ryao
- [IMPROVEMENT] Enhance Offline Rebuilding with Resource Awareness and Retry Backoff [11270](https://github.com/longhorn/longhorn/issues/11270) - @mantissahz @chriscchien
- [IMPROVEMENT] Collect mount table, process status and process table in support bundle   [8397](https://github.com/longhorn/longhorn/issues/8397) - @mantissahz @chriscchien
- [IMPROVEMENT] Volume attachment should automatically exclude nodes with `disable-v2-data-engine="true"` [11695](https://github.com/longhorn/longhorn/issues/11695) - @derekbit @chriscchien
- [IMPROVEMENT] Introduce `System Info` Category for Settings [11656](https://github.com/longhorn/longhorn/issues/11656) - @derekbit @roger-ryao
- [IMPROVEMENT] RBAC permissions [11345](https://github.com/longhorn/longhorn/issues/11345) - @davidcheng0922 @chriscchien
- [IMPROVEMENT] Improve Longhorn Pods Logging Precision to Nanoseconds [11596](https://github.com/longhorn/longhorn/issues/11596) - @derekbit @roger-ryao
- [IMPROVEMENT] Update validation logics for v2 data engine [11600](https://github.com/longhorn/longhorn/issues/11600) - @derekbit @chriscchien
- [IMPROVEMENT] Improve log messages of longhorn-engine, tgt and liblonghorn for troubleshooting [11545](https://github.com/longhorn/longhorn/issues/11545) - @yangchiu @derekbit
- [IMPROVEMENT] rename the backing image manager to reduce the probability of CR name collision [11455](https://github.com/longhorn/longhorn/issues/11455) - @COLDTURNIP @chriscchien
- [IMPROVEMENT] Remove outdated prerequisite installation scripts in longhorn/longhorn [11430](https://github.com/longhorn/longhorn/issues/11430) - @yangchiu @roger-ryao @sushant-suse
- [UI][IMPROVEMENT] Add UI Warning for Force-Detach Actions to Prevent Out-of-Sync Kubernetes and Longhorn VolumeAttachments [9944](https://github.com/longhorn/longhorn/issues/9944) - @yangchiu @houhoucoop
- [IMPROVEMENT] Add `node-selector` option to `longhornctl` to select nodes on which to run DaemonSet [11213](https://github.com/longhorn/longhorn/issues/11213) - @yangchiu @bachmanity1
- [IMPROVEMENT] Improve volume `Scheduled` condition message [11460](https://github.com/longhorn/longhorn/issues/11460) - @yangchiu @derekbit @chriscchien
- [IMPROVEMENT] Launching a new mechanism to collect instance manager logs [5948](https://github.com/longhorn/longhorn/issues/5948) - @yangchiu @derekbit
- [IMPROVEMENT] adjust the hardcoded timeout limitation for backing image downloading [11309](https://github.com/longhorn/longhorn/issues/11309) - @COLDTURNIP @roger-ryao
- [IMPROVEMENT] Make liveness probe parameters of instance-manager pod configurable [10788](https://github.com/longhorn/longhorn/issues/10788) - @yangchiu @derekbit
- [IMPROVEMENT] Enhance menu descriptions for Longhorn CLI [8998](https://github.com/longhorn/longhorn/issues/8998) - @roger-ryao @sushant-suse
- [IMPROVEMENT] Improve longhorn-engine controller log messages [11507](https://github.com/longhorn/longhorn/issues/11507) - @derekbit @chriscchien
- [IMPROVEMENT] Add a comment to explain what `isSettingDataEngineSynced` does in the instance manager controller. [11321](https://github.com/longhorn/longhorn/issues/11321) - @mantissahz
- [IMPROVEMENT] Flooding and misleading log message `Deleting orphans on evicted node ...` [11500](https://github.com/longhorn/longhorn/issues/11500) - @yangchiu @derekbit
- [IMPROVEMENT] Reject `volume.spec.replicaRebuildingBandwidthLimit` update for V1 Data Engine [11497](https://github.com/longhorn/longhorn/issues/11497) - @derekbit @roger-ryao
- [IMPROVEMENT] Detach an offline rebuilding volume if rebuilding can not start [11274](https://github.com/longhorn/longhorn/issues/11274) - @mantissahz
- [IMPROVEMENT] backing image handle node disk deleting events [10983](https://github.com/longhorn/longhorn/issues/10983) - @COLDTURNIP @chriscchien
- [IMPROVEMENT] Rename `RebuildingMbytesPerSecond` to `ReplicaRebuildBandwidthLimit` [11403](https://github.com/longhorn/longhorn/issues/11403) - @derekbit @roger-ryao
- [IMPROVEMENT] Make the sync agent profilable [11386](https://github.com/longhorn/longhorn/issues/11386) - @COLDTURNIP @yangchiu
- [IMPROVEMENT] Add performance metrics for Longhorn disk I/O [11223](https://github.com/longhorn/longhorn/issues/11223) - @hookak @DamiaSan
- [IMPROVEMENT] Make CLI preflight check non-blocking for subsequent checkups [9877](https://github.com/longhorn/longhorn/issues/9877) - @davidcheng0922 @DamiaSan
- [IMPROVEMENT] Add namespace argument/parameter to cli pre-flight check [9749](https://github.com/longhorn/longhorn/issues/9749) - @davidcheng0922 @DamiaSan
- [IMPROVEMENT] `Orphaned Data` should not be placed under Settings [10383](https://github.com/longhorn/longhorn/issues/10383) - @houhoucoop @DamiaSan @sushant-suse
- [IMPROVEMENT] Upgrade Node v20 in longhorn-ui [11315](https://github.com/longhorn/longhorn/issues/11315) - @chriscchien @houhoucoop
- [IMPROVEMENT] useful error message from /v1/backuptargets is not displayed in UI [10428](https://github.com/longhorn/longhorn/issues/10428) - @houhoucoop @DamiaSan
- [IMPROVEMENT] Check if the backup target is available before creating a backup, backup backing image, and system backup [10085](https://github.com/longhorn/longhorn/issues/10085) - @yangchiu @nzhan126
- [IMPROVEMENT] Backoff Retry Interval for Instance Manager Pod Re-creation in Resource Constraint Scenarios [10263](https://github.com/longhorn/longhorn/issues/10263) - @yangchiu @bachmanity1
- [IMPROVEMENT] record the detail while webhook rejecting migration attachment tickets [11150](https://github.com/longhorn/longhorn/issues/11150) - @COLDTURNIP @roger-ryao
- [IMPROVEMENT] Handle credential secret containing mixed invalid conditions  [8537](https://github.com/longhorn/longhorn/issues/8537) - @yangchiu @nzhan126
- [IMPROVEMENT] Add the possibility of setting floating point values for `guaranteed-instance-manager-cpu` and `node.spec.instanceManagerCPURequest` [11179](https://github.com/longhorn/longhorn/issues/11179) - @yangchiu @gigabyte132
- [IMPROVEMENT] Remove the Patch `preserveUnknownFields: false` for CRDs [11263](https://github.com/longhorn/longhorn/issues/11263) - @derekbit @chriscchien
- [IMPROVEMENT] Schedule at least one replica locally when locality is `best-effort` [11007](https://github.com/longhorn/longhorn/issues/11007) - @chriscchien @bachmanity1
- [IMPROVEMENT] Improve the disk space un-schedulable condition message [10436](https://github.com/longhorn/longhorn/issues/10436) - @yangchiu @davidcheng0922
- [IMPROVEMENT] Improve the condition message of engine image check [9845](https://github.com/longhorn/longhorn/issues/9845) - @derekbit @chriscchien
- [IMPROVEMENT] Improve the logging when detecting multiple backup volumes of the same volume on the same backup target [11152](https://github.com/longhorn/longhorn/issues/11152) - @PhanLe1010 @chriscchien
- [IMPROVEMENT] Implement Documentation Validation for `longhorn/cli` [11229](https://github.com/longhorn/longhorn/issues/11229) - @derekbit
- [IMPROVEMENT] Move validation from each resource deletion to validation webhook [5156](https://github.com/longhorn/longhorn/issues/5156) - @derekbit @roger-ryao
- [IMPROVEMENT] Validate node.longhorn.io resource spec fields [11079](https://github.com/longhorn/longhorn/issues/11079) - @Felipalds @chriscchien
- [IMPROVEMENT] add support for custom annotations in the UI service on Longhorn Helm Chart [11031](https://github.com/longhorn/longhorn/issues/11031) - @josimar-silva @roger-ryao
- [IMPROVEMENT] Adding retry logic for longhorn-csi-plugin when it trying to contact the longhorn-manager pods [9482](https://github.com/longhorn/longhorn/issues/9482) - @PhanLe1010 @roger-ryao

### Bug

- [BUG] failed to load DataEngineSpecific boolean setting from configmap [11810](https://github.com/longhorn/longhorn/issues/11810) - @COLDTURNIP @roger-ryao
- [BUG] V2 stop working - connectNVMfBdev() -> "code": -95,"message": "Operation not supported" (1.10.0-rc2) [11761](https://github.com/longhorn/longhorn/issues/11761) - @yangchiu @c3y1huang
- [BUG] [UI] Inconsistent Default Value for Data Engine in Clone Volume [11802](https://github.com/longhorn/longhorn/issues/11802) - @houhoucoop @roger-ryao
- [BUG] System backup could get stuck in `CreatingVolumeBackups` if some nodes are labeled with `disable-v2-data-engine=true` [11774](https://github.com/longhorn/longhorn/issues/11774) - @mantissahz @roger-ryao
- [BUG] Potential Data Corruption During Volume Resizing When Created from Snapshot [11484](https://github.com/longhorn/longhorn/issues/11484) - @yangchiu @PhanLe1010
- [BUG] Block disk may never become `Schedulable` after re-adding [11760](https://github.com/longhorn/longhorn/issues/11760) - @derekbit @chriscchien
- [BUG] v2 volume could get stuck in `Detaching/Faulted` state after nodes reboot [10112](https://github.com/longhorn/longhorn/issues/10112) - @yangchiu @shuo-wu
- [BUG] Fail to dynamically provision a v2 volume with a backing image if the backing image doesn't exist before PVC creation [11762](https://github.com/longhorn/longhorn/issues/11762) - @COLDTURNIP @yangchiu
- [BUG] v2 DR volume faulted after origin volume expand and backuped [11767](https://github.com/longhorn/longhorn/issues/11767) - @davidcheng0922 @roger-ryao
- [BUG] longhorn manager crash in installation [11743](https://github.com/longhorn/longhorn/issues/11743) - @derekbit @chriscchien
- [BUG] Unable to sync existing backups from a remote backup store [11758](https://github.com/longhorn/longhorn/issues/11758) - @yangchiu @mantissahz
- [BUG] Longhorn pvcs are in pending state. [11654](https://github.com/longhorn/longhorn/issues/11654) - @yangchiu @derekbit
- [BUG] Volume becomes faulted when its replica node disks run out of space during a write operation [10718](https://github.com/longhorn/longhorn/issues/10718) - @yangchiu @mantissahz
- [BUG] [v1.10.0-rc1] `longhornctl trim volume` command hangs [11704](https://github.com/longhorn/longhorn/issues/11704) - @davidcheng0922 @chriscchien
- [BUG]  longhornctl preflight install should load and check iscsi_tcp kernel module. [11706](https://github.com/longhorn/longhorn/issues/11706) - @mantissahz @chriscchien
- [BUG] spdk_tgt crash after replica rebuilding due to bdev_channel_destroy_resource() assert failure [11109](https://github.com/longhorn/longhorn/issues/11109) - @hookak @chriscchien
- [BUG] Unable to set replica affinity when creating a v2 volume (`test_soft_anti_affinity_scheduling_volume_enable`) [11642](https://github.com/longhorn/longhorn/issues/11642) - @yangchiu @derekbit
- [BUG] BackupBackingImage may be created from an unready BackingImageManager [11675](https://github.com/longhorn/longhorn/issues/11675) - @WebberHuang1118 @roger-ryao
- [BUG] Creating a 2 Gi volume with a 200 Mi backing image is rejected with “volume size should be larger than the backing image size” [11362](https://github.com/longhorn/longhorn/issues/11362) - @COLDTURNIP @yangchiu
- [BUG] Replica auto balance disk in pressure fails on v2 volumes [10551](https://github.com/longhorn/longhorn/issues/10551) - @yangchiu @hookak
- [BUG] Backup stuck when ownerID is assigned to a node with node.longhorn.io/disable-v2-data-engine: "true" [11619](https://github.com/longhorn/longhorn/issues/11619) - @davidcheng0922 @roger-ryao
- [BUG] Engine process continues running after rapid volume detachment [11605](https://github.com/longhorn/longhorn/issues/11605) - @COLDTURNIP @yangchiu
- [BUG] remaining unknown OS condition in node CR [11612](https://github.com/longhorn/longhorn/issues/11612) - @COLDTURNIP @roger-ryao
- [BUG] Longhorn Manager continues to send replica deletion requests to the Instance Manager for the v2 volume indefinitely [11553](https://github.com/longhorn/longhorn/issues/11553) - @yangchiu @shuo-wu
- [BUG] Unable to disable v2-data-engine even though there is no v2 volumes, backing images or orphaned data [11330](https://github.com/longhorn/longhorn/issues/11330) - @shuo-wu @roger-ryao
- [BUG] longhorn-manager repeatedly emits `No instance manager for node xxx for update instance state of orphan instance orphan-xxx..` [11597](https://github.com/longhorn/longhorn/issues/11597) - @COLDTURNIP @chriscchien
- [BUG] Volumes fails to remount when they go read-only [8572](https://github.com/longhorn/longhorn/issues/8572) - @derekbit @chriscchien
- [BUG] Dangling Volume State When Live Migration Terminates Unexpectedly [11479](https://github.com/longhorn/longhorn/issues/11479) - @PhanLe1010 @chriscchien
- [BUG] S3 Backup target reverts randomly to previous value [9581](https://github.com/longhorn/longhorn/issues/9581) - @yangchiu @mantissahz
- [BUG] Longhornctl / CLI -  no configuration has been provided, try setting KUBERNETES_MASTER environment variable [10094](https://github.com/longhorn/longhorn/issues/10094) - @davidcheng0922 @chriscchien
- [BUG] longhorn-images.txt specifies CSI component repo tags not found [11575](https://github.com/longhorn/longhorn/issues/11575) - @yangchiu @derekbit
- [BUG] DR volume's backup block size should be set from the latest backup [11580](https://github.com/longhorn/longhorn/issues/11580) - @COLDTURNIP @yangchiu
- [BUG] longhornctl --enable-spdk doesn't support arm64 [11551](https://github.com/longhorn/longhorn/issues/11551) - @yangchiu @davidcheng0922
- [BUG] extra invalid BackupVolumeCR may be created during cluster split-brain [11154](https://github.com/longhorn/longhorn/issues/11154) - @mantissahz @roger-ryao
- [BUG]  system backup error [11232](https://github.com/longhorn/longhorn/issues/11232) - @c3y1huang @roger-ryao
- [BUG] Can not create backup using `Create Backup` icon in UI [11451](https://github.com/longhorn/longhorn/issues/11451) - @yangchiu @mantissahz @houhoucoop
- [BUG] Unable to create backup for old snapshots on v2 volumes: failed to find snapshot lvol range [11461](https://github.com/longhorn/longhorn/issues/11461) - @c3y1huang @chriscchien
- [BUG] Uninstall fail because find backuptargets remaining [11486](https://github.com/longhorn/longhorn/issues/11486) - @COLDTURNIP @yangchiu
- [BUG] Setting v2 data engine can be enabled without fulfilling the hugepage requirement, causing error v2 instance manager CR dangling in the system [11519](https://github.com/longhorn/longhorn/issues/11519) - @yangchiu @derekbit
- [BUG] Unable to setup backup target in storage network environment: cannot find a running instance manager for node [11478](https://github.com/longhorn/longhorn/issues/11478) - @yangchiu @derekbit
- [BUG] Volume migration negative test cases fail on v2 volumes [10800](https://github.com/longhorn/longhorn/issues/10800) - @shuo-wu @chriscchien
- [BUG] V2 volume fails to cleanup error replica and rebuild new one - test_data_locality_basic [10335](https://github.com/longhorn/longhorn/issues/10335) - @shuo-wu @chriscchien
- [BUG] Issue auto detecting nvme drive on talos cluster (vfio-pci driver instead of expected vfio_pci) [11127](https://github.com/longhorn/longhorn/issues/11127) - @Hugome @roger-ryao
- [BUG] Test case `test_running_volume_with_scheduling_failure` failed due to unexpected new replica created [11512](https://github.com/longhorn/longhorn/issues/11512) - @derekbit @chriscchien
- [BUG] Regression test cases failed due to unable to clean up dummy backups [11487](https://github.com/longhorn/longhorn/issues/11487) - @COLDTURNIP @yangchiu
- [BUG][v1.9.0-rc1] Unexpected orphaned data are created after v2 instance managers deleted [10829](https://github.com/longhorn/longhorn/issues/10829) - @yangchiu @derekbit
- [BUG] v2 Engine loops in detaching and attaching state after rebuilding [10396](https://github.com/longhorn/longhorn/issues/10396) - @shuo-wu @roger-ryao
- [BUG] `test_basic.py::test_backup_status_for_unavailable_replicas` is failed [11416](https://github.com/longhorn/longhorn/issues/11416) - @derekbit @roger-ryao
- [BUG] Build fails due to outdated SLES repo [11481](https://github.com/longhorn/longhorn/issues/11481) - @PhanLe1010
- [BUG] Unable to set up S3 backup target if backups already exist [11337](https://github.com/longhorn/longhorn/issues/11337) - @mantissahz @chriscchien
- [BUG][UI] `Snapshots and Backups` graph is stuck loading and console shows error messages [10529](https://github.com/longhorn/longhorn/issues/10529) - @yangchiu @davidcheng0922
- [BUG] The Backup YAML example in the Longhorn doc does not work [11216](https://github.com/longhorn/longhorn/issues/11216) - @roger-ryao @nzhan126
- [BUG] v2 volume workload IO could get `Bad message` error after network disconnect [10113](https://github.com/longhorn/longhorn/issues/10113) - @yangchiu @shuo-wu
- [BUG] Test case `Test Replica Auto Balance Node Least Effort` failed on v2 volume [10977](https://github.com/longhorn/longhorn/issues/10977) - @yangchiu @c3y1huang
- [BUG] IsJSONRPCRespErrorNoSuchDevice fails on wrapped errors for ublk client [11361](https://github.com/longhorn/longhorn/issues/11361) - @yangchiu @davidcheng0922
- [BUG] longhorn-manager is crashed due to `SIGSEGV: segmentation violation` [11420](https://github.com/longhorn/longhorn/issues/11420) - @derekbit @chriscchien
- [BUG] Test Case `test_replica_auto_balance_node_least_effort` Is Sometimes Failed [11388](https://github.com/longhorn/longhorn/issues/11388) - @derekbit @chriscchien
- [BUG] volume gets stuck at detaching/faulted state for spdk v2 engine intermittently [10724](https://github.com/longhorn/longhorn/issues/10724) - @DamiaSan
- [BUG] Typo in configuration parameter: "offlineRelicaRebuilding" should be "offlineReplicaRebuilding" [11380](https://github.com/longhorn/longhorn/issues/11380) - @yangchiu @in-jun
- [BUG][DOC] OpenShift documentation [11174](https://github.com/longhorn/longhorn/issues/11174) - @yangchiu @mlacko64
- [BUG] In single node Harvester, endless "unable to schedule replica" is logged in longhorn-manager [3708](https://github.com/longhorn/longhorn/issues/3708) - @derekbit @chriscchien
- [BUG] Uninstallation fail due to deleting the running Longhorn node is not allowed [11131](https://github.com/longhorn/longhorn/issues/11131) - @COLDTURNIP @roger-ryao
- [BUG] Engine v2 I/O Blocked Over 1-2 Minutes After Instance Manager Pod Deletion [10167](https://github.com/longhorn/longhorn/issues/10167) - @c3y1huang @chriscchien
- [BUG] Regression test cases failed: expecting volume to be detached but it's attached [11273](https://github.com/longhorn/longhorn/issues/11273) - @yangchiu @mantissahz
- [BUG] Volume expansion fails with "unsupported disk encryption format ext4" [11120](https://github.com/longhorn/longhorn/issues/11120) - @COLDTURNIP @mantissahz @roger-ryao
- [BUG] longhorn-spdk-engine rebuilding unit tests may get stuck for 2 minutes [11099](https://github.com/longhorn/longhorn/issues/11099) - @shuo-wu @roger-ryao
- [BUG] v2 volume could get stuck in `detaching/detached` loop when `Migration Confirmation After Migration Node Down` [10157](https://github.com/longhorn/longhorn/issues/10157) - @yangchiu @PhanLe1010
- [BUG] Longhorn will not reuse the failed v2 replicas when a race condition is triggered after the instance manager pod restart [11188](https://github.com/longhorn/longhorn/issues/11188) - @shuo-wu @roger-ryao
- [BUG] Auto-generated CLI document overwrite by make [11219](https://github.com/longhorn/longhorn/issues/11219) - @bachmanity1
- [BUG] Incorrect value of `remove-snapshots-during-filesystem-trim` in longhorn chart/values.yaml [11264](https://github.com/longhorn/longhorn/issues/11264) - @derekbit @chriscchien
- [BUG][v1.9.0-rc1] v2 volumes don't reuse failed replicas as expected after a node goes down [10828](https://github.com/longhorn/longhorn/issues/10828) - @yangchiu @shuo-wu
- [BUG] CSI Plugin restart triggers unintended restart of migratable RWX volume workloads [11158](https://github.com/longhorn/longhorn/issues/11158) - @c3y1huang @roger-ryao
- [BUG] in the browser UI: Volume -> Clone Volume results in the broken browser page [11165](https://github.com/longhorn/longhorn/issues/11165) - @houhoucoop @roger-ryao
- [BUG] "mkfsParams" in StorageClass are not passed to share-manager for filesystem formatting [11107](https://github.com/longhorn/longhorn/issues/11107) - @Florianisme @roger-ryao
- [BUG] Test case `test_engine_image_not_fully_deployed_perform_volume_operations` failed: unable to detach a volume [10874](https://github.com/longhorn/longhorn/issues/10874) - @mantissahz @chriscchien
- [BUG] Creating support-bundle panic NPE [11169](https://github.com/longhorn/longhorn/issues/11169) - @c3y1huang @roger-ryao
- [BUG] Unable to Build Longhorn-Share-Manager Image Due to CMAKE Compatibility [11159](https://github.com/longhorn/longhorn/issues/11159) - @derekbit @roger-ryao
- [BUG] Uninstallation fail due to deleting the default engine image is not allowed [11130](https://github.com/longhorn/longhorn/issues/11130) - @COLDTURNIP @chriscchien
- [BUG] v2 volume gets stuck in degraded state and continuously rebuilds/deletes replicas after a kubelet restart [10107](https://github.com/longhorn/longhorn/issues/10107) - @shuo-wu
- [BUG] SPDK API bdev_lvol_detach_parent does not work as expected [11046](https://github.com/longhorn/longhorn/issues/11046) - @DamiaSan @roger-ryao
- [BUG] Recurring jobs fail when assigned to default group [11016](https://github.com/longhorn/longhorn/issues/11016) - @c3y1huang @chriscchien
- [BUG] v2 volume data checksum mismatch after replica rebuilding [10118](https://github.com/longhorn/longhorn/issues/10118) - @yangchiu @shuo-wu
- [BUG] Most of regression test cases are failing due to unable to update settings [11042](https://github.com/longhorn/longhorn/issues/11042) - @yangchiu @mantissahz
- [BUG] unable to clean up the backing image volume replica after node eviction [11053](https://github.com/longhorn/longhorn/issues/11053) - @COLDTURNIP @roger-ryao
- [BUG] backing image volume replica NPE crash during evicting node [11034](https://github.com/longhorn/longhorn/issues/11034) - @COLDTURNIP @chriscchien
- [BUG]  A degraded DR volume remains in standby and attached after activation. [2107](https://github.com/longhorn/longhorn/issues/2107) - @roger-ryao
- [BUG] DR volume gets stuck if there is only a rebuilding replica running [2753](https://github.com/longhorn/longhorn/issues/2753) - @c3y1huang @roger-ryao

### Stability

- [DOC] Document Volume Stability Risks Caused by I/O Latency on HDDs [11240](https://github.com/longhorn/longhorn/issues/11240) - @chriscchien @sushant-suse

### Misc

- [DOC] Add Information on Replica Failure Tolerance [11526](https://github.com/longhorn/longhorn/issues/11526) - @roger-ryao @sushant-suse
- [TASK] KB for backup store lock conflict error message [11293](https://github.com/longhorn/longhorn/issues/11293) - @yangchiu @pratikjagrut
- [DOC] Document Replica Rebuilding Mechanisms and Their Limitations [11119](https://github.com/longhorn/longhorn/issues/11119) - @mantissahz @chriscchien
- [DOC] V2 Engine usage contradiction [11409](https://github.com/longhorn/longhorn/issues/11409) - @shuo-wu @roger-ryao
- [DOC] Talos new volumes strategy [11015](https://github.com/longhorn/longhorn/issues/11015) - @yangchiu @DrummyFloyd
- [TASK] [pytest] automatically add -m v2_volume_test if RUN_V2_TEST enabled [11376](https://github.com/longhorn/longhorn/issues/11376) - @chriscchien
- Revise the document about node space [3021](https://github.com/longhorn/longhorn/issues/3021) - @derekbit @chriscchien
- [DOC] Troubleshooting KB for Mount Failure with XFS Filesystem [11214](https://github.com/longhorn/longhorn/issues/11214) - @derekbit @roger-ryao
- [DOC] Explain Longhorn VolumeAttachment operation and behavior [11142](https://github.com/longhorn/longhorn/issues/11142) - @derekbit @roger-ryao
- [DOC] Update Broken Links on Website [11288](https://github.com/longhorn/longhorn/issues/11288) - @yangchiu @sushant-suse
- [DOC] Clarify privateRegistry.createSecret and registrySecret usage in chart README [11251](https://github.com/longhorn/longhorn/issues/11251) - @chriscchien
- [DOC] KB: failed to complete volume migration during VM upgrade [11149](https://github.com/longhorn/longhorn/issues/11149) - @COLDTURNIP @chriscchien
- [DOC] Elaborate how to enable DR volume using kubectl [10958](https://github.com/longhorn/longhorn/issues/10958) - @derekbit @chriscchien
- [DOC] Remove `defaultSettings.registrySecret` reference from air gap installation guide [11237](https://github.com/longhorn/longhorn/issues/11237) - @chriscchien
- [TASK] Remove deprecated replica.status.evictionRequested field [7022](https://github.com/longhorn/longhorn/issues/7022) - @yangchiu @derekbit @roger-ryao
- [TASK] Create longhorn/spdk longhorn-v25.05 branch [11048](https://github.com/longhorn/longhorn/issues/11048) - @derekbit @chriscchien
- [TASK] Create a Dedicated Repository for libqcow to Improve Maintainability and Build Management [10988](https://github.com/longhorn/longhorn/issues/10988) - @derekbit @chriscchien
- [DOC] Update examples using deprecated crd version v1beta1 to v1beta2 on 1.9.0 [11019](https://github.com/longhorn/longhorn/issues/11019) - @falmar @roger-ryao
- [TASK] POC for ui-extension migration [10516](https://github.com/longhorn/longhorn/issues/10516) - @houhoucoop
- [TASK] Ensure support-bundle-kit builds use vendored dependencies [11106](https://github.com/longhorn/longhorn/issues/11106) - @yangchiu @c3y1huang
- [DOC] Fix the broken links present in documentation [11028](https://github.com/longhorn/longhorn/issues/11028) - @chriscchien @sushant-suse
- [DOC] Update website front page to include community meeting links [10890](https://github.com/longhorn/longhorn/issues/10890) - @yangchiu @divya-mohan0209 @sushant-suse
- [REFACTOR] Use go pkg for system operation instead of relying on external system call via shell command [5193](https://github.com/longhorn/longhorn/issues/5193) - @c3y1huang

## New Contributors

- @Felipalds
- @Florianisme
- @Hugome
- @divya-mohan0209
- @falmar
- @gigabyte132
- @in-jun
- @josimar-silva
- @mlacko64
- @pratikjagrut

## Contributors

- @COLDTURNIP
- @DamiaSan
- @DrummyFloyd
- @PhanLe1010
- @WebberHuang1118
- @bachmanity1
- @c3y1huang
- @chriscchien
- @davidcheng0922
- @derekbit
- @hookak
- @houhoucoop
- @innobead
- @mantissahz
- @marcosbc
- @nzhan126
- @roger-ryao
- @shuo-wu
- @sushant-suse
- @yangchiu