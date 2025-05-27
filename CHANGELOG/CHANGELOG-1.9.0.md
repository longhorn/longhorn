## Longhorn v1.9.0 Release Notes

Longhorn v1.9.0 introduces new features, enhancements, and bug fixes aimed at improving system stability and user experience. Key highlights include V2 Data Engine improvements, orphaned instance deletion, offline replica rebuilding, recurring system backups, and enhanced observability of Longhorn resources.

The Longhorn team appreciates your contributions and anticipates receiving feedback regarding this release.

For terminology and background on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

## Removal

### Environment Check Script

The `environment_check.sh` script, deprecated in v1.7.0, has been removed in v1.9.0. Use the [Longhorn Command Line Tool](https://longhorn.io/docs/1.9.0/advanced-resources/longhornctl/) (`longhornctl`) to check your environment for potential issues.

### Orphan Resource Auto-Deletion

The `orphan-auto-deletion` setting has been replaced by `orphan-resource-auto-deletion` in v1.9.0. To replicate the previous behavior, include `replica-data` in the `orphan-resource-auto-deletion` value. During the upgrade, the original `orphan-auto-deletion` setting is automatically migrated.

For more information, see [Orphan Data Cleanup](https://longhorn.io/docs/1.9.0/advanced-resources/data-cleanup/).

### Deprecated Fields in `longhorn.io/v1beta2` CRDs

Deprecated fields have been removed from the CRDs. For details, see issue [#6684](https://github.com/longhorn/longhorn/issues/6684).

## Deprecation & Incompatibilities

### `longhorn.io/v1beta1` API

The `v1beta1` version of the Longhorn API is marked unserved and unsupported in v1.9.0 and will be removed in v1.10.0.

For more details, see [Issue #10250](https://github.com/longhorn/longhorn/issues/10250).

### Breaking Change in V2 Backing Image

Starting with Longhorn v1.9.0, V2 backing images are incompatible with earlier versions due to naming conflicts in the extended attributes (`xattrs`) used by SPDK backing image logical volumes. As a result, V2 backing images must be deleted and recreated during the upgrade process. Since backing images cannot be deleted while volumes using them still exist, you must first back up, delete, and later restore those volumes as the following steps:

- Before upgrading to v1.9.0:
  - Verify that backup targets are functioning properly.
  - Create full backups of all volumes that use a V2 backing image.
  - Detach and delete these volumes after the backups complete.
  - In the **Backing Image** page, save the specifications of all V2 backing images, including the name and the image source.
  - Delete all V2 backing images.
- After upgrading:
  - Recreate the V2 backing images using the same names and image sources.
  - Restore the volumes from your backups.

For more details, see [Issue #10805](https://github.com/longhorn/longhorn/issues/10805).

## Primary Highlights

### New V2 Data Engine Features

While the V2 Data Engine remains experimental in this release, several core functions have been significantly improved:

- [Support UBLK Frontend](https://github.com/longhorn/longhorn/issues/9719): Support for UBLK frontend in the V2 Data Engine, which allows for better performance and resource utilization.
- [Storage Network](https://github.com/longhorn/longhorn/issues/6450): Introduces support for storage networks in the V2 Data Engine to allow network segregation.
- [Offline Replica Rebuilding](https://github.com/longhorn/longhorn/issues/8443): Support for offline replica rebuilding, which allows degraded volumes to automatically recover replicas even while the volume is detached. This capability ensures high data availability without manual intervention.

### Recurring System Backup

Starting with Longhorn v1.9.0, you can create a recurring job for system backup creation.

[Documentation](https://longhorn.io/docs/1.9.0/advanced-resources/system-backup-restore/backup-longhorn-system/) | [GitHub Issue](https://github.com/longhorn/longhorn/issues/6534)

### Offline Replica Rebuilding

Longhorn introduces offline replica rebuilding, a feature that allows degraded volumes to automatically recover replicas even while the volume is detached. This capability minimizes the need for manual recovery steps, accelerates restoration, and ensures high data availability. By default, offline replica rebuilding is disabled. To enable it, set the `offline-replica-rebuilding` setting to `true` in the Longhorn UI or CLI.

[Documentation](https://longhorn.io/docs/1.9.0/advanced-resources/rebuilding/offline-replica-rebuilding/) | [GitHub Issue](https://github.com/longhorn/longhorn/issues/8443)

### Orphaned Instance Deletion

Longhorn can now track and remove orphaned instances, which are leftover resources like replicas or engines that are no longer associated with an active volume. These instances may accumulate due to unexpected failures or incomplete cleanup.

To reduce resource usage and maintain system performance, Longhorn supports both automatic and manual cleanup. By default, this feature is disabled. To enable it, set the `orphan-resource-auto-deletion` setting to `instance` in the Longhorn UI or CLI.

[Documentation](https://longhorn.io/docs/1.9.0/advanced-resources/data-cleanup/orphaned-instance-cleanup/) | [GitHub Issue](https://github.com/longhorn/longhorn/issues/6764)

### Improved Metrics for Replica, Engine, and Rebuild Status

Longhorn improves observability with new Prometheus metrics that expose the status and identity of Replica and Engine CRs, along with rebuild activity. These metrics make it easier to monitor rebuilds across the cluster.

For more information, see [#10550](https://github.com/longhorn/longhorn/issues/10550) and [#10722](https://github.com/longhorn/longhorn/issues/10722).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.9.0.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.9.0/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.8.x to v1.9.0.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.9.0/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

### Highlight

- [FEATURE] Cleanup orphaned volume runtime resources if the v1 resources already deleted [6764](https://github.com/longhorn/longhorn/issues/6764) - @COLDTURNIP @chriscchien
- [FEATURE] v2 volume supports UBLK frontend [9456](https://github.com/longhorn/longhorn/issues/9456) - @PhanLe1010 @chriscchien
- [FEATURE] V1 and V2 volume offline replica rebuilding [8443](https://github.com/longhorn/longhorn/issues/8443) - @mantissahz @roger-ryao
- [TASK] Migrate v1beta1 CR to v1beta2 [10250](https://github.com/longhorn/longhorn/issues/10250) - @COLDTURNIP @roger-ryao
- [FEATURE] Storage network with V2 data engine [6450](https://github.com/longhorn/longhorn/issues/6450) - @c3y1huang @roger-ryao
- [FEATURE] Recurring system backup [6534](https://github.com/longhorn/longhorn/issues/6534) - @yangchiu @c3y1huang

### Feature

- [FEATURE] Delta Replica Rebuilding using Delta Snapshot: SPDK API Development [10799](https://github.com/longhorn/longhorn/issues/10799) - @yangchiu @DamiaSan
- [FEATURE] Running replicas field in volume table [10817](https://github.com/longhorn/longhorn/issues/10817) - @xelab04 @roger-ryao
- [FEATURE] Longhorn UI supports orphaned instance CRs management [10760](https://github.com/longhorn/longhorn/issues/10760) - @yangchiu @houhoucoop
- [FEATURE] Allow auto deleting snapshot when a backup is created from that snapshot. [9213](https://github.com/longhorn/longhorn/issues/9213) - @yangchiu @mantissahz
- [FEATURE] Add missing metrics of number of volumes/replicas by node/cluster [7599](https://github.com/longhorn/longhorn/issues/7599) - @c3y1huang @roger-ryao

### Improvement

- [IMPROVEMENT] Remove unnecessary lasso dependency [10856](https://github.com/longhorn/longhorn/issues/10856) - @derekbit @chriscchien
- [IMPROVEMENT] Configurable wait interval for orphaned instance CR creation [10904](https://github.com/longhorn/longhorn/issues/10904) - @derekbit @chriscchien
- [IMPROVEMENT] Prevent creating orphans while deleting the v1 instances [10888](https://github.com/longhorn/longhorn/issues/10888) - @COLDTURNIP @chriscchien
- [IMPROVEMENT] prevent false logs from deleting volume with offline rebuilding is disabled. [10889](https://github.com/longhorn/longhorn/issues/10889) - @mantissahz @chriscchien
- [IMPROVEMENT] Add Prometheus metrics for Replica and Engine CRs [10722](https://github.com/longhorn/longhorn/issues/10722) - @hookak @chriscchien
- [IMPROVEMENT]  Export longhorn engine rebuild status as prometheus metrics [10550](https://github.com/longhorn/longhorn/issues/10550) - @hookak @chriscchien
- [IMPROVEMENT] Disable Snapshot Checksum Calculation for Single-Replica V1 Volume [10518](https://github.com/longhorn/longhorn/issues/10518) - @derekbit @chriscchien
- [IMPROVEMENT] add extraObject in charts [10835](https://github.com/longhorn/longhorn/issues/10835) - @DrummyFloyd @chriscchien
- [IMPROVEMENT] Disable the v2 snapshot hashing while it is being deleted [10563](https://github.com/longhorn/longhorn/issues/10563) - @shuo-wu @roger-ryao
- [IMPROVEMENT] v2 checksum calculation and update should follow the v1 flow [10480](https://github.com/longhorn/longhorn/issues/10480) - @shuo-wu @roger-ryao
- [IMPROVEMENT] add strict field validation to the update option in upgrade path [10644](https://github.com/longhorn/longhorn/issues/10644) - @ChanYiLin @chriscchien
- [IMPROVEMENT] Show snapshot size during in-progress backup [9783](https://github.com/longhorn/longhorn/issues/9783) - @yangchiu @houhoucoop
- [IMPROVEMENT] Don't synchronize all filesystem before snapshotting a v2 volume [9023](https://github.com/longhorn/longhorn/issues/9023) - @yangchiu @DamiaSan
- [IMPROVEMENT] spdk_tgt can cancel lvol checksum calculation while there is high priority task [10421](https://github.com/longhorn/longhorn/issues/10421) - @yangchiu @DamiaSan
- [IMPROVEMENT] Lvol is not force-removed if Blob is busy [10474](https://github.com/longhorn/longhorn/issues/10474) - @yangchiu @DamiaSan
- [IMPROVEMENT] Remove deprecated fields from CRDs [6684](https://github.com/longhorn/longhorn/issues/6684) - @derekbit @roger-ryao
- [IMPROVEMENT] Longhorn CLI fails to recognize Raspbian OS [10676](https://github.com/longhorn/longhorn/issues/10676) - @bachmanity1 @roger-ryao
- [IMPROVEMENT] Reduce auto balancing logging noise for detached volumes [10691](https://github.com/longhorn/longhorn/issues/10691) - @dihmandrake @roger-ryao
- [IMPROVEMENT] Remove the upper bound of v2-data-engine-guaranteed-instance-manager-cpu [10662](https://github.com/longhorn/longhorn/issues/10662) - @derekbit @roger-ryao
- [IMPROVEMENT] Clean up BackupTarget condition message handling [8224](https://github.com/longhorn/longhorn/issues/8224) - @chriscchien @houhoucoop
- [IMPROVEMENT] Longhorn CLI supports SLES micro [9256](https://github.com/longhorn/longhorn/issues/9256) - @yangchiu @DamiaSan
- [IMPROVEMENT] Allow `volumeBindingMode` to be set from helm values [10592](https://github.com/longhorn/longhorn/issues/10592) - @ruant @roger-ryao
- [DOC] Prepare a knowledge base for backing image trouble shooting during upgrade [10590](https://github.com/longhorn/longhorn/issues/10590) - @ChanYiLin @chriscchien
- [IMPROVEMENT] Missing Prometheus Metrics for Engine v2 Volumes [10472](https://github.com/longhorn/longhorn/issues/10472) - @hookak @roger-ryao
- [IMPROVEMENT] Create Volume UI improvement, Automatically Filter Backing Image Based on `v1` or `v2` Selection [10086](https://github.com/longhorn/longhorn/issues/10086) - @houhoucoop @roger-ryao
- [UI][IMPROVEMENT] Improve the Warning Message When Failed to Remove `Block`-Type Disks [10580](https://github.com/longhorn/longhorn/issues/10580) - @houhoucoop @roger-ryao
- [IMPROVEMENT] Pass full backup mode option to CSI volume snapshot type backup [9785](https://github.com/longhorn/longhorn/issues/9785) - @ChanYiLin @roger-ryao
- [UI][IMPROVEMENT] Clean up BackupTarget condition message handling [10579](https://github.com/longhorn/longhorn/issues/10579) - @houhoucoop
- [IMPROVEMENT] Improve the Warning Message When Failed to Remove `Block`-Type Disks [10522](https://github.com/longhorn/longhorn/issues/10522) - @yangchiu @ChanYiLin
- [IMPROVEMENT] Move `SettingNameV2DataEngineHugepageLimit` to danger zone settings [7746](https://github.com/longhorn/longhorn/issues/7746) - @derekbit @chriscchien
- [IMPROVEMENT] Include the /proc/mounts file and multipath.config in the support-bundle [6754](https://github.com/longhorn/longhorn/issues/6754) - @c3y1huang @roger-ryao
- [IMPROVEMENT] Use code-generator/kube_codegen.sh to generate K8s stubs and CRDs [7944](https://github.com/longhorn/longhorn/issues/7944) - @derekbit @chriscchien
- [IMPROVEMENT] CRD & API code generator decouple from Go conventional source path [10556](https://github.com/longhorn/longhorn/issues/10556) - @COLDTURNIP
- [IMPROVEMENT] Support configurable upgrade-responder URL [10437](https://github.com/longhorn/longhorn/issues/10437) - @derekbit @roger-ryao
- [IMPROVEMENT] Settings change validation should go back to using Volume state to determine "are all volumes detached" [10233](https://github.com/longhorn/longhorn/issues/10233) - @yangchiu @james-munson
- [IMPROVEMENT] Improve the UX of updating danger zone settings [8070](https://github.com/longhorn/longhorn/issues/8070) - @yangchiu @mantissahz
- [UI][FEATURE] V1 and V2 volume offline replica rebuilding [10581](https://github.com/longhorn/longhorn/issues/10581) - @houhoucoop @roger-ryao
- [UI][FEATURE] Recurring system backup [10262](https://github.com/longhorn/longhorn/issues/10262) - @yangchiu @houhoucoop

### Bug

- [BUG] Error on git checkout in a container [10621](https://github.com/longhorn/longhorn/issues/10621) - @derekbit @chriscchien
- [BUG] Test case `test_snapshot_prune_and_coalesce_simultaneously_with_backing_image` fails [10808](https://github.com/longhorn/longhorn/issues/10808) - @yangchiu @c3y1huang
- [BUG] Failed to terminate namespace `longhorn-system` if there is a support bundle `ReadyForDownload` [10731](https://github.com/longhorn/longhorn/issues/10731) - @yangchiu @c3y1huang
- [BUG] Helm persistence.backupTargetName not referenced in storageclass template [10961](https://github.com/longhorn/longhorn/issues/10961) - @yangchiu @mantissahz
- [BUG] SPDK API lvol_get_snapshot_range_checksums cannot get the correct result [10950](https://github.com/longhorn/longhorn/issues/10950) - @shuo-wu @roger-ryao
- [BUG] V2 Backing image not ready after upgrade from v1.8.1 to v1.9.x [10805](https://github.com/longhorn/longhorn/issues/10805) - @COLDTURNIP @chriscchien
- [BUG] v2 replica rebuilding will miss the backing image [10909](https://github.com/longhorn/longhorn/issues/10909) - @shuo-wu @chriscchien
- [BUG] minor spacing issues found with yamllint in the helm chart [10681](https://github.com/longhorn/longhorn/issues/10681) - @codekow
- [BUG][UI] Snapshots of v2 volume with backing image aren't shown on the `Snapshots and Backups` graph [10526](https://github.com/longhorn/longhorn/issues/10526) - @derekbit @chriscchien
- [BUG] Deleted orphan data still renders on the page until page refresh [10803](https://github.com/longhorn/longhorn/issues/10803) - @COLDTURNIP @chriscchien @houhoucoop
- [BUG] DR volume does not sync with latest backup when activation [10824](https://github.com/longhorn/longhorn/issues/10824) - @c3y1huang @chriscchien
- [BUG][v1.9.0-rc1] Block disks become temporarily unavailable after the upgrading from `v1.8.1` to `v1.9.0-rc1` [10821](https://github.com/longhorn/longhorn/issues/10821) - @mantissahz
- [BUG] Naming collision when creating the name of the new backing image manager [10616](https://github.com/longhorn/longhorn/issues/10616) - @yangchiu @ChanYiLin
- [BUG] v2 volume replica status `error` after snapshot deletion with `Immediate Data Integrity Check` Enabled [10798](https://github.com/longhorn/longhorn/issues/10798) - @shuo-wu
- [BUG] Enabling `V2 Data Engine` setting, v2 instance manager doesn't start after certain negative factor operations [10791](https://github.com/longhorn/longhorn/issues/10791) - @COLDTURNIP @yangchiu
- [BUG] spdk emits `Device or resource busy` while registering lvol checksum calculation [10140](https://github.com/longhorn/longhorn/issues/10140) - @shuo-wu @roger-ryao
- [BUG] v2 instance managers keep crashing on master-head arm64 environment [10768](https://github.com/longhorn/longhorn/issues/10768) - @yangchiu @PhanLe1010
- [BUG] Wrong image name in `longhorn-images.txt` [10774](https://github.com/longhorn/longhorn/issues/10774) - @c3y1huang
- [BUG] After node down and force delete the terminating deployment pod, volume can not attach success [10689](https://github.com/longhorn/longhorn/issues/10689) - @c3y1huang @chriscchien
- [BUG] Deleting a replica of one v2 volume will also degrade the other v2 volume [10527](https://github.com/longhorn/longhorn/issues/10527) - @yangchiu @ChanYiLin
- [BUG] Adding a non-existing disk to a node will cause the longhorn-manager to crash [10749](https://github.com/longhorn/longhorn/issues/10749) - @ChanYiLin @roger-ryao
- [BUG] Upgrading Longhorn from v1.8.1 to master-head causes longhorn-manager to crash [10762](https://github.com/longhorn/longhorn/issues/10762) - @yangchiu @mantissahz
- [BUG] After node rebooted and workload pod restarted, pod data size became 0, and the mounted volume turned read-only [9248](https://github.com/longhorn/longhorn/issues/9248) - @yangchiu @c3y1huang
- [BUG] Test case `test_engine_crash_during_live_upgrade` failed due to data loss [10751](https://github.com/longhorn/longhorn/issues/10751) - @c3y1huang @roger-ryao
- [BUG] System backup could get stuck in `CreatingBackingImageBackups` indefinitely [10740](https://github.com/longhorn/longhorn/issues/10740) - @yangchiu @ChanYiLin
- [BUG] v2 volume with backing image gets stuck in `Attaching` state [10743](https://github.com/longhorn/longhorn/issues/10743) - @yangchiu @ChanYiLin
- [BUG] Can NOT delete an oversized Not Ready volume [10741](https://github.com/longhorn/longhorn/issues/10741) - @WebberHuang1118 @chriscchien
- [BUG][UI] Bulk backup creation with a detached volume returns error 405 and error messages show in browser console [10460](https://github.com/longhorn/longhorn/issues/10460) - @yangchiu @a110605
- [BUG] `spdk_tgt` encountered `Lvol store removed with error: -16` in `longhorn-spdk-helper` during a CI test [10622](https://github.com/longhorn/longhorn/issues/10622) - @derekbit @roger-ryao
- [BUG] 2 uninstall pods could be created after uninstall job was created, one failed with `deleting-confirmation-flag is set to false` error, while the other completed successfully [10483](https://github.com/longhorn/longhorn/issues/10483) - @yangchiu @derekbit
- [BUG] SPDK constantly emits "Bad length of checksum xattr" [10399](https://github.com/longhorn/longhorn/issues/10399) - @ChanYiLin @chriscchien
- [BUG] Can't create v2 block-type disk via BDF on Talos [10313](https://github.com/longhorn/longhorn/issues/10313) - @derekbit @roger-ryao
- [BUG] I/O errors on Longhorn v1.7.2 volume during VM migration while upgrading Harvester v1.4.1 [10495](https://github.com/longhorn/longhorn/issues/10495) - @derekbit @roger-ryao
- [BUG] MultiUnmapper floods logs with warnings about size mismatch. [6406](https://github.com/longhorn/longhorn/issues/6406) - @shuo-wu @roger-ryao
- [BUG] `spdk_tgt` segfaulted in `longhorn-spdk-helper` during a CI test run. [10598](https://github.com/longhorn/longhorn/issues/10598) - @derekbit @roger-ryao
- [BUG] Backup Execution Timeout setting issue in Helm chart [10323](https://github.com/longhorn/longhorn/issues/10323) - @yangchiu @james-munson
- [BUG] Longhorn Volume Encryption Not Working in Talos 1.9.x [10584](https://github.com/longhorn/longhorn/issues/10584) - @c3y1huang @roger-ryao
- [BUG][UI] Inconsistent capitalization in the `Allow snapshots removal during trim` volume setting [10470](https://github.com/longhorn/longhorn/issues/10470) - @yangchiu @houhoucoop
- [BUG] Expand Volume option is greyed under Volume tab but working in the volume detail section.  [7529](https://github.com/longhorn/longhorn/issues/7529) - @yangchiu @houhoucoop
- [BUG] Instance manager image build fail [10653](https://github.com/longhorn/longhorn/issues/10653) - @shuo-wu
- [BUG] Recurring job pod stuck in pending state and unable to create new snapshots after node reboot [7956](https://github.com/longhorn/longhorn/issues/7956) - @c3y1huang @chriscchien
- [BUG] Instance manager pod stuck in Terminating state after upgrade with v2 backing image [10520](https://github.com/longhorn/longhorn/issues/10520) - @ChanYiLin @chriscchien
- [BUG] Extra replica created when create volume in a engine image not fully deployed environment [8263](https://github.com/longhorn/longhorn/issues/8263) - @c3y1huang @chriscchien
- [BUG] [v1.8.0-rc1] Uninstallation fail if having backing images, the instance-manager pod stuck at terminating [10044](https://github.com/longhorn/longhorn/issues/10044) - @ChanYiLin @chriscchien
- [BUG] test_statefulset_restore fails on integration test run with NFS backup store [3451](https://github.com/longhorn/longhorn/issues/3451) - @roger-ryao
- [BUG] csi keeps creating backup if the backup target is unavailable [10501](https://github.com/longhorn/longhorn/issues/10501) - @mantissahz @roger-ryao
- [BUG] nil pointer when the backing image copy is delete from the spec but also gets evicted at the same time [10464](https://github.com/longhorn/longhorn/issues/10464) - @yangchiu @ChanYiLin
- [BUG] Mutex is copied in getLatestBackup [6965](https://github.com/longhorn/longhorn/issues/6965) - @james-munson @roger-ryao
- [BUG] integer divide by zero in replica scheduler [10502](https://github.com/longhorn/longhorn/issues/10502) - @c3y1huang @chriscchien
- [BUG] Leading or trailing spaces in Longhorn UI break search [10491](https://github.com/longhorn/longhorn/issues/10491) - @houhoucoop @roger-ryao
- [BUG] When replica rebuilding completed, the progress could be 99 instead of 100 [8589](https://github.com/longhorn/longhorn/issues/8589) - @shuo-wu @chriscchien
- [BUG] Workload with RWX volume cannot recover when Kubelet restarts [2933](https://github.com/longhorn/longhorn/issues/2933) - @james-munson @chriscchien
- [BUG][UI] Backup store setting doesn't apply to the cloned volume [10463](https://github.com/longhorn/longhorn/issues/10463) - @yangchiu @mantissahz
- [BUG] Data lost caused by Longhorn CSI plugin doing a wrong filesystem format action in a rare race condition [10416](https://github.com/longhorn/longhorn/issues/10416) - @yangchiu @PhanLe1010
- [BUG] WebUI Volumes Disappear and Reappear [10314](https://github.com/longhorn/longhorn/issues/10314) - @yangchiu @PhanLe1010 @houhoucoop
- [BUG] Longhorn-manager logs "Failed to sync backup status" on every backup [10301](https://github.com/longhorn/longhorn/issues/10301) - @derekbit @chriscchien
- [BUG] Rebuilding stuck for DR volume if the node was power down while restoring [2747](https://github.com/longhorn/longhorn/issues/2747) - @COLDTURNIP @roger-ryao
- [BUG] Uninstalling K3s without uninstalling Longhorn first when Longhorn SPDK volumes exist hangs on arm64 [8132](https://github.com/longhorn/longhorn/issues/8132) - @roger-ryao
- [BUG]  A V2 volume checksum will change after replica rebuilding if the volume created with backing image [10340](https://github.com/longhorn/longhorn/issues/10340) - @shuo-wu @chriscchien
- [BUG] RWX volume becomes faulted after the node reconnects [5658](https://github.com/longhorn/longhorn/issues/5658) - @james-munson @chriscchien
- [BUG] V2 BackingImage failed after node reboot [10342](https://github.com/longhorn/longhorn/issues/10342) - @ChanYiLin @chriscchien
- [BUG] degraded v2 volume doesn't create new replica even though there is an available disk [9197](https://github.com/longhorn/longhorn/issues/9197) - @c3y1huang
- [BUG] Bug in snapshot count enforcement cause volume faulted and stuck in detaching/attaching loop [10308](https://github.com/longhorn/longhorn/issues/10308) - @PhanLe1010 @roger-ryao
- [BUG] Test case `test_csi_mount_volume_online_expansion` is failing due to unable to expand PVC [10411](https://github.com/longhorn/longhorn/issues/10411) - @yangchiu @c3y1huang
- [BUG] Longhorn CSI plugin 1.8.0 crashes consistently when trying to create a snapshot [10303](https://github.com/longhorn/longhorn/issues/10303) - @yangchiu @PhanLe1010
- [BUG] Workload pod will not be able to move to new node when backup operation is taking a long time [10171](https://github.com/longhorn/longhorn/issues/10171) - @yangchiu @PhanLe1010
- [BUG] v2 engine stuck in detaching-attaching loop if the previous replica is not cleaned up correct [10293](https://github.com/longhorn/longhorn/issues/10293) - @yangchiu @shuo-wu
- [BUG] [UI] 'Create' button on the System Backup page is disabled after reloading page [10351](https://github.com/longhorn/longhorn/issues/10351) - @yangchiu @houhoucoop
- [BUG] "Error get size" from "metrics_collector.(*BackupCollector).Collect" on every metric scrape [10358](https://github.com/longhorn/longhorn/issues/10358) - @derekbit @chriscchien
- [BUG] Proxy gRPC API ReplicaList returns different output formats for v1 and v2 volumes [10347](https://github.com/longhorn/longhorn/issues/10347) - @shuo-wu @roger-ryao
- [BUG] Engine stuck in "stopped" state, prevent volume attach [9938](https://github.com/longhorn/longhorn/issues/9938) - @ChanYiLin @roger-ryao
- [BUG] After upgrading to v1.8.0 the version number lost on the web-ui [10336](https://github.com/longhorn/longhorn/issues/10336) - @derekbit
- [BUG] constant attaching/reattaching of volumes after upgrading to 1.8 [10304](https://github.com/longhorn/longhorn/issues/10304) - @PhanLe1010
- [BUG] Sometimes attached DR volume checksum fluctuates [9305](https://github.com/longhorn/longhorn/issues/9305) - @c3y1huang
- [BUG] Backing image manager pods unable to come up on RHEL 8.4 [2767](https://github.com/longhorn/longhorn/issues/2767) - @roger-ryao
- [BUG] Failed to upgrade Longhorn from `v1.8.x-head` to `master-head` [10143](https://github.com/longhorn/longhorn/issues/10143) - @roger-ryao
- [BUG] [v1.5.4-rc2] V2 volume perform engine upgrade when concurrent-automatic-engine-upgrade-per-node-limit > 0 [7930](https://github.com/longhorn/longhorn/issues/7930) - @derekbit
- [BUG] Negative test case got stuck in waiting for longhorn-ui pods [8248](https://github.com/longhorn/longhorn/issues/8248) - @c3y1huang

### Misc

- [DOC] Replica count behaviour is unclear. [10861](https://github.com/longhorn/longhorn/issues/10861) - @hoo29 @chriscchien
- [DOC] Update "Upgrade Path Enforcement and Downgrade Prevention" [10945](https://github.com/longhorn/longhorn/issues/10945) - @derekbit @roger-ryao
- [TASK] Update the longhornio/nfs-ganesha image [10878](https://github.com/longhorn/longhorn/issues/10878) - @derekbit @c3y1huang @chriscchien
- [DOC] No `BackupTargetSecret` in `Settings/General` [10858](https://github.com/longhorn/longhorn/issues/10858) - @vnwnv @roger-ryao
- [DOC] Create system backup first before upgrade system [10633](https://github.com/longhorn/longhorn/issues/10633) - @ChanYiLin @chriscchien
- [TASK] [UI] [FEATURE] v2 volume supports UBLK frontend [10735](https://github.com/longhorn/longhorn/issues/10735) - @chriscchien @houhoucoop
- [DOC] Adding support for RKE2/k3s in data-recovery steps [10714](https://github.com/longhorn/longhorn/issues/10714) - @mattmattox @roger-ryao
- [DOC] Architecture Diagram [6761](https://github.com/longhorn/longhorn/issues/6761) - @derekbit @chriscchien
- [TASK] Fix longhorn/website to support latest Hugo server version [10632](https://github.com/longhorn/longhorn/issues/10632) - @chriscchien @sushant-suse
- [TASK] fix lint problems in longhorn-manager [10639](https://github.com/longhorn/longhorn/issues/10639) - @COLDTURNIP @chriscchien
- [DOC] Codeblocks in KB don't line wrap [8143](https://github.com/longhorn/longhorn/issues/8143) - @roger-ryao @sushant-suse
- [TASK] Longhorn UI assessment for ui-extension migration [10487](https://github.com/longhorn/longhorn/issues/10487) - @houhoucoop
- [DOC] Update the steps to set up the Azure backup target [9688](https://github.com/longhorn/longhorn/issues/9688) - @mantissahz
- [DOC] Explain the process of creating backing images from existing volumes [10093](https://github.com/longhorn/longhorn/issues/10093) - @ChanYiLin @chriscchien
- [DOC] Update ArgoCD installation document [10588](https://github.com/longhorn/longhorn/issues/10588) - @mantissahz
- [TASK] Remove environment check script since v1.9.0 [9239](https://github.com/longhorn/longhorn/issues/9239) - @yangchiu @derekbit
- [TASK] Add platform architect and volume encryption info to metrics [7047](https://github.com/longhorn/longhorn/issues/7047) - @c3y1huang @roger-ryao
- [DOC] Update the document and create a KB to address the limitation that BackingImage should be multiple of 512B [10536](https://github.com/longhorn/longhorn/issues/10536) - @ChanYiLin
- [Doc] Clarifications on defaultSettings.defaultDataLocality and persistence.defaultDataLocality usage [10253](https://github.com/longhorn/longhorn/issues/10253) - @james-munson @roger-ryao

## New Contributors

- @bachmanity1
- @codekow
- @DrummyFloyd
- @hoo29
- @hookak
- @dihmandrake
- @mattmattox
- @ruant
- @vnwnv
- @xelab04

## Contributors

- @COLDTURNIP
- @ChanYiLin
- @DamiaSan
- @PhanLe1010
- @WebberHuang1118
- @a110605
- @c3y1huang
- @chriscchien
- @derekbit
- @houhoucoop
- @innobead
- @james-munson
- @mantissahz
- @roger-ryao
- @shuo-wu
- @yangchiu
- @sushant-suse
- @jillian-maroket
- @rebeccazzzz
- @forbesguthrie
- @asettle
