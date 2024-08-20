## Longhorn v1.7.0 Release Notes

This latest version of Longhorn introduces several features, enhancements, and bug fixes that are intended to improve system quality and the overall user experience. Highlights include new V2 Data Engine features, platform-agnostic deployment, high availability, and improvements to data protection, stability, performance, and resilience.

The Longhorn team appreciates your contributions and anticipates receiving feedback regarding this release.

> **Note:**
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Deprecation & Incompatibilities

The functionality of the [environment check script](https://github.com/longhorn/longhorn/blob/v1.7.x/scripts/environment_check.sh) overlaps with that of the Longhorn CLI, which is available starting with v1.7.0. Because of this, the script is deprecated in v1.7.0 and is scheduled for removal in v1.8.0.

For information about important changes, including feature incompatibility, deprecation, and removal, see [Important Notes](https://longhorn.io/docs/1.7.0/deploy/important-notes/) in the Longhorn documentation.

## Primary Highlights

### New V2 Data Engine Features

Although the V2 Data Engine is still considered a preview feature in this release, the core functions have been significantly enhanced.

- [Online replica rebuilding](https://github.com/longhorn/longhorn/issues/7199): Allows Longhorn to rebuild replicas while the volume is running without any IO interruptions.
- [Filesystem trim](https://github.com/longhorn/longhorn/issues/7534): Reclaims unused space more effectively.
- [Block-type disk support for SPDK AIO, NVMe and VirtIO Bdev drivers](https://github.com/longhorn/longhorn/issues/7672): Broadens the range of compatible hardware and improves performance in high-demand environments.
- [V2 volume support for data plane live upgrade](https://github.com/longhorn/longhorn/issues/6001): Enables upgrading of the spdk_tgt process, which handles IO operations, without any downtime. Coverage of the live upgrade function will be extended to the control plane in a future release.

The Longhorn team will continue to develop features for the V1 Data Engine and to prepare the V2 Data Engine for use in all types of environments.

### Platform-Agnostic Deployment

Longhorn is designed to seamlessly operate on general-purpose Linux distributions and certain container-optimized operating systems. v1.7.0 provides robust and efficient persistent storage solutions for Kubernetes clusters running on [Container-Optimized OS (COS)](https://github.com/longhorn/longhorn/issues/6165).

### High Availability

v1.7.0 introduces features that enhance system resilience and address potential single points of failure. 

- [High availability for backing images](github.com/longhorn/longhorn/issues/2856): Mitigates risks associated with image failures. 
- [RWX volumes fast failover](https://github.com/longhorn/longhorn/issues/6205): Enables rapid detection of and response to Share Manager pod failures (independent of the timing and sequence of Kubernetes node failures).

### Data Protection

Starting with v1.7.0, Longhorn supports [periodic and on-demand full backups](https://github.com/longhorn/longhorn/issues/7070) that help reduce the likelihood of backup corruption and enhance the overall reliability of the backup process.

### Scheduling

The [replica auto-balancing](https://github.com/longhorn/longhorn/issues/4105) feature was enhanced to address disk space pressure from growing volumes. These enhancements reduce manual intervention by automatically rebalancing replicas under disk pressure and improve performance with faster replica rebuilding through local file copying.

### Storage Network

The storage network now [supports RWX volumes]((https://github.com/longhorn/longhorn/issues/8184)) with network segregation, enabling dedicated traffic lanes for storage operations.

### Longhorn CLI

The [Longhorn CLI](https://github.com/longhorn/longhorn/issues/7927), which is the official Longhorn command line tool, is introduced in v1.7.0. This tool interacts with Longhorn by creating Kubernetes custom resources (CRs) and executing commands inside a dedicated pod for in-cluster and host operations. Usage scenarios include installation, operations such as exporting replicas, and troubleshooting.

## Installation

**Ensure that your cluster is running Kubernetes v1.21 or later before installing Longhorn v1.7.0.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.7.0/deploy/install/) in the Longhorn documentation.

## Upgrade

**Ensure that your cluster is running Kubernetes v1.21 or later before upgrading from Longhorn v1.6.x to v1.7.0.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.7.0/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Highlights
- [FEATURE] Longhorn block-type disks supports different SPDK disk bdev drivers [7672](https://github.com/longhorn/longhorn/issues/7672) - @derekbit @roger-ryao
- [FEATURE] Volume cloning enhancement [2907](https://github.com/longhorn/longhorn/issues/2907) - @yangchiu @PhanLe1010
- [FEATURE] Share manager HA - Experimental [6205](https://github.com/longhorn/longhorn/issues/6205) - @PhanLe1010 @james-munson @roger-ryao
- [FEATURE] v2 volume replica online rebuilding [7199](https://github.com/longhorn/longhorn/issues/7199) - @shuo-wu @chriscchien
- [FEATURE] v2 volume supports live upgrade for data plane [6001](https://github.com/longhorn/longhorn/issues/6001) - @derekbit @chriscchien
- [IMPROVEMENT] Use `fsfreeze` instead of `sync` before snapshot [2187](https://github.com/longhorn/longhorn/issues/2187) - @ejweber @chriscchien
- [FEATURE] Auto-balancing volumes between nodes & disks [4105](https://github.com/longhorn/longhorn/issues/4105) - @yangchiu @c3y1huang
- [FEATURE] HA backing image [2856](https://github.com/longhorn/longhorn/issues/2856) - @ChanYiLin @chriscchien
- [FEATURE] Create Longhorn CLI focusing on non CR resource operations [7927](https://github.com/longhorn/longhorn/issues/7927) - @c3y1huang @chriscchien
- [FEATURE] Support periodic or on-demand full backups to enhance backup reliability [7070](https://github.com/longhorn/longhorn/issues/7070) - @ChanYiLin @chriscchien
- [IMPROVEMENT] Improve rebuilding is canceled if it takes longer than 24 hours [2765](https://github.com/longhorn/longhorn/issues/2765) - @PhanLe1010 @chriscchien
- [UI][FEATURE]  Support volume cloning using UI [8741](https://github.com/longhorn/longhorn/issues/8741) - @a110605 @chriscchien
- [UI][FEATURE] Add backing image encryption and clone support  [8789](https://github.com/longhorn/longhorn/issues/8789) - @a110605 @mantissahz
- [FEATURE] Support volume encryption for (encrypted) backing image volumes [7051](https://github.com/longhorn/longhorn/issues/7051) - @ChanYiLin @roger-ryao
- [FEATURE] Container-Optimized OS support [6165](https://github.com/longhorn/longhorn/issues/6165) - @yangchiu @c3y1huang

### Features
- [FEATURE] v2 volume supports filesystem trim  [7534](https://github.com/longhorn/longhorn/issues/7534) - @derekbit @chriscchien
- [FEATURE] Add nodeSelector as a parameter to VolumeSnapshotClass for backing images [6526](https://github.com/longhorn/longhorn/issues/6526) - @ChanYiLin @chriscchien
- [FEATURE] Add additional monitoring settings to ServiceMonitor resource. [8142](https://github.com/longhorn/longhorn/issues/8142) - @yangchiu @ejweber @kejrak
- [FEATURE] Support storage network for RWX volumes [8184](https://github.com/longhorn/longhorn/issues/8184) - @c3y1huang @chriscchien
- [FEATURE] Add BackupBackingImage UI [7541](https://github.com/longhorn/longhorn/issues/7541) - @a110605 @mantissahz
- [FEATURE][UI] Add parameters support to the Backup and RecurringJob [8291](https://github.com/longhorn/longhorn/issues/8291) - @a110605 @chriscchien
- [UI][FEATURE] Add Fields to Backing Image Creation and Update [8485](https://github.com/longhorn/longhorn/issues/8485) - @a110605 @chriscchien
- [FEATURE] Change parent of a logical volume for volume rebuild [5866](https://github.com/longhorn/longhorn/issues/5866) - @DamiaSan

### Improvements
- [IMPROVEMENT] Restore Latest Backup should be applied with BackingImage name value [7560](https://github.com/longhorn/longhorn/issues/7560) - @a110605 @roger-ryao
- [IMPROVEMENT] Remove Offline Rebuilding from UI on master and v1.7.0 [9090](https://github.com/longhorn/longhorn/issues/9090) - @a110605 @derekbit @chriscchien
- [IMPROVEMENT] Add a label and selector for webhooks to longhorn-manager pod manifest. [8803](https://github.com/longhorn/longhorn/issues/8803) - @james-munson @roger-ryao
- [IMPROVEMENT] Fix outdated environment check in longhorn manager [7571](https://github.com/longhorn/longhorn/issues/7571) - @mantissahz @roger-ryao
- [IMPROVEMENT] v2 volume snapshot supports `UserCreated` flag [7578](https://github.com/longhorn/longhorn/issues/7578) - @DamiaSan @roger-ryao
- [IMPROVEMENT] Undocumented traffic on port 8503 [9076](https://github.com/longhorn/longhorn/issues/9076) - @derekbit
- [IMPROVEMENT] Cannot expand a volume created by Longhorn UI [6446](https://github.com/longhorn/longhorn/issues/6446) - @mantissahz @chriscchien
- [IMPROVEMENT] Minor log improvement [6396](https://github.com/longhorn/longhorn/issues/6396) - @Vicente-Cheng
- [IMPROVEMENT] Refactor the usage of timer reset in SPDK JSON-RPC read method [7297](https://github.com/longhorn/longhorn/issues/7297) - @shuo-wu
- [IMPROVEMENT] Update sizes in Engine and Volume resources less frequently [8076](https://github.com/longhorn/longhorn/issues/8076) - @ejweber @chriscchien
- [IMPROVEMENT] Docker build of instance-manager should error out if the execution of SPDK pkgdep.sh fails [8063](https://github.com/longhorn/longhorn/issues/8063) - @derekbit @roger-ryao
- [IMPROVEMENT] Enable spdk_tgt debug log for helping debug [7939](https://github.com/longhorn/longhorn/issues/7939) - @derekbit @chriscchien
- [BUG] Do not terminate nfs-ganesha in share-manager pod after failing to access recovery backend [8345](https://github.com/longhorn/longhorn/issues/8345) - @derekbit @chriscchien
- [IMPROVEMENT] Fall back to a running instance-manager if a default is not available [8464](https://github.com/longhorn/longhorn/issues/8464) - @derekbit @chriscchien
- [IMPROVEMENT] Only sync log settings to running instance manager pod [8466](https://github.com/longhorn/longhorn/issues/8466) - @derekbit
- [IMPROVEMENT] Expose local logical volume and attach it to local node [8551](https://github.com/longhorn/longhorn/issues/8551) - @derekbit @chriscchien
- [IMPROVEMENT] Update nfs-ganesha to v5.9 [9008](https://github.com/longhorn/longhorn/issues/9008) - @derekbit @chriscchien
- [IMPROVEMENT] Pre-pull images (share-manager image and instance-manager image) on each Longhorn node [8376](https://github.com/longhorn/longhorn/issues/8376) - @mantissahz @chriscchien
- [IMPROVEMENT]  Add websocket for backup backing image [8849](https://github.com/longhorn/longhorn/issues/8849) - @ChanYiLin @roger-ryao
- [IMPROVEMENT] Allow users to request backup volume update [7982](https://github.com/longhorn/longhorn/issues/7982) - @mantissahz @chriscchien
- [IMPROVEMENT] Problems mounting XFS volume clones / restored snapshots [8796](https://github.com/longhorn/longhorn/issues/8796) - @PhanLe1010 @chriscchien
- [IMPROVEMENT] Do not start any instance-manager pods for the v2 data engine on a node if one is already running [8456](https://github.com/longhorn/longhorn/issues/8456) - @derekbit @roger-ryao
- [IMPROVEMENT] Auto cleanup related Snapshot when removing Backup [8365](https://github.com/longhorn/longhorn/issues/8365) - @FrankYang0529 @roger-ryao
- [IMPROVEMENT] Improve environment_check script for NFS protocol bug and the host system self diagnosis  [7931](https://github.com/longhorn/longhorn/issues/7931) - @james-munson @roger-ryao
- [UI][IMPROVEMENT] Tweak some minor UI issues [8646](https://github.com/longhorn/longhorn/issues/8646) - @a110605 @roger-ryao
- [IMPROVEMENT] environment_check.sh should check for the iscsi_tcp kernel module [8697](https://github.com/longhorn/longhorn/issues/8697) - @tserong @roger-ryao
- [IMPROVEMENT] Improve and simplify chart values.yaml [5089](https://github.com/longhorn/longhorn/issues/5089) - @yangchiu @ChanYiLin
- [IMPROVEMENT] The client-go rest client rate limit inside the csi sidecar component might be too small (csi-provisioner, csi-attacjer. csi-snappshotter, csi-attacher)  [8699](https://github.com/longhorn/longhorn/issues/8699) - @PhanLe1010 @chriscchien
- [IMPROVEMENT] Always update the built-in installed system packages when building component images [8721](https://github.com/longhorn/longhorn/issues/8721) - @c3y1huang @roger-ryao
- [UI][IMPROVEMENT] Improve the UX of updating danger zone settings [8071](https://github.com/longhorn/longhorn/issues/8071) - @a110605 @roger-ryao
- [IMPROVEMENT] Prevent unnecessary updates of instanceManager status [8420](https://github.com/longhorn/longhorn/issues/8420) - @derekbit @chriscchien
- [IMPROVEMENT] Longhor Manager Flood with "Failed to get engine proxy of ... cannot get client for engine" Message [8266](https://github.com/longhorn/longhorn/issues/8266) - @derekbit @chriscchien
- [IMPROVEMENT] Add setting value limits in `SettingDefinition` [7441](https://github.com/longhorn/longhorn/issues/7441) - @ChanYiLin @roger-ryao
- [IMPROVEMENT] Investigate performance bottleneck in v1 data path  [8436](https://github.com/longhorn/longhorn/issues/8436) - @PhanLe1010 @roger-ryao
- [IMPROVEMENT] Disable revision counter by default [8563](https://github.com/longhorn/longhorn/issues/8563) - @PhanLe1010 @chriscchien
- [IMPROVEMENT] BackingImage UI improvement [7293](https://github.com/longhorn/longhorn/issues/7293) - @a110605 @roger-ryao
- [IMPROVEMENT] Avoid misleading log messages in longhorn manager while syncing danger zone settings [7797](https://github.com/longhorn/longhorn/issues/7797) - @mantissahz @chriscchien
- [IMPROVEMENT] Add setting to configure support bundle timeout for node bundle collection [8623](https://github.com/longhorn/longhorn/issues/8623) - @c3y1huang @roger-ryao
- [IMPROVEMENT] RWX volume scheduling [7872](https://github.com/longhorn/longhorn/issues/7872) - @derekbit @chriscchien
- [IMPROVEMENT] Expose virtual size of qcow2 backing images [7923](https://github.com/longhorn/longhorn/issues/7923) - @tserong @roger-ryao
- [IMPROVEMENT] Saving Settings page changes  [7497](https://github.com/longhorn/longhorn/issues/7497) - @a110605 @roger-ryao
- [IMPROVEMENT] UI does not find credentials for Backblaze B2 s3-compatible storage for backup [8462](https://github.com/longhorn/longhorn/issues/8462) - @mantissahz
- [IMPROVEMENT] Add documents for Longhorn deployed with GitOps [6948](https://github.com/longhorn/longhorn/issues/6948) - @yangchiu
- [UI][IMPROVEMENT] Allow users to request backup volume update [8501](https://github.com/longhorn/longhorn/issues/8501) - @a110605
- [IMPROVEMENT] Record instance-manager name for a block disksin `node.spec.diskStatus` [8458](https://github.com/longhorn/longhorn/issues/8458) - @derekbit @chriscchien
- [TASK] Mirror the `quay.io/openshift/origin-oauth-proxy` image to Longhorn repo similar to what we are doing for CSI sidecar images [8329](https://github.com/longhorn/longhorn/issues/8329) - @PhanLe1010 @roger-ryao
- [IMPROVEMENT] Helm Chart: Support Gateway API and improve Ingress [7889](https://github.com/longhorn/longhorn/issues/7889) - @e3b0c442 @mantissahz @roger-ryao
- [IMPROVEMENT] Upgrade support bundle kit version to v0.0.36 [8159](https://github.com/longhorn/longhorn/issues/8159) - @c3y1huang @roger-ryao
- [IMPROVEMENT] Cannot read/write to block volume when the container is run as non-root [8088](https://github.com/longhorn/longhorn/issues/8088) - @PhanLe1010 @chriscchien
- [IMPROVEMENT] Change support-bundle-manager image pull policy to PullIfNotPresent [7998](https://github.com/longhorn/longhorn/issues/7998) - @ChanYiLin @roger-ryao
- [IMPROVEMENT] Use HEAD instead of a GET to fetch the `Content-Length` of an resource via URL [7892](https://github.com/longhorn/longhorn/issues/7892) - @votdev @chriscchien
- [IMPROVEMENT] Remove startup probe of CSI driver after liveness probe conn fix ready [7428](https://github.com/longhorn/longhorn/issues/7428) - @ejweber @chriscchien
- [IMPROVEMENT] Implement TLS to proxy client [3975](https://github.com/longhorn/longhorn/issues/3975) - @c3y1huang
- [DOC] Snapshot Maximum Count setting is missing from the Settings Reference page  [7894](https://github.com/longhorn/longhorn/issues/7894) - @FrankYang0529

### Bug Fixes
- [BUG] v2 Volume Filesystem Trim doesn't work without enabling `uio_pci_generic` [9182](https://github.com/longhorn/longhorn/issues/9182) - @derekbit
- [BUG] Backup CR Stuck in Deletion if the Source PVC is already removed [9252](https://github.com/longhorn/longhorn/issues/9252) - @mantissahz @chriscchien
- [BUG] v2 volume workload pod failed mount with error: UNEXPECTED INCONSISTENCY [9196](https://github.com/longhorn/longhorn/issues/9196) - @derekbit @shuo-wu @chriscchien
- [BUG] `longhornctl` doesn't work on `amazon linux` and `sle-micro` [9139](https://github.com/longhorn/longhorn/issues/9139) - @mantissahz @chriscchien
- [BUG] v2 volume could get stuck in attaching/detaching loop if deleting replica while replica rebuilding [9190](https://github.com/longhorn/longhorn/issues/9190) - @yangchiu @derekbit @shuo-wu @chriscchien
- [BUG] Networking between longhorn-csi-plugin and longhorn-manager is broken after upgrading Longhorn to 1.7.0-rc3  [9223](https://github.com/longhorn/longhorn/issues/9223) - @PhanLe1010 @roger-ryao
- [BUG] Longhorn didn't choose to rebuild on an existing replica if there is a scheduling failed replica after  [1992](https://github.com/longhorn/longhorn/issues/1992) - @yangchiu @c3y1huang
- [BUG] test case `test_system_backup_and_restore_volume_with_backingimage` failed on sle-micro ARM64 [9209](https://github.com/longhorn/longhorn/issues/9209) - @ChanYiLin
- [BUG] v2 volume size could become 0 if deleting replica while replica rebuilding [9191](https://github.com/longhorn/longhorn/issues/9191) - @derekbit @shuo-wu @chriscchien
- [BUG] Degraded v2 volume write error after replica rebuild [9166](https://github.com/longhorn/longhorn/issues/9166) - @shuo-wu @chriscchien
- [BUG] SPDK NVMe bdev is unable to create on some NVMe disks (on Equinix platform) [8813](https://github.com/longhorn/longhorn/issues/8813) - @derekbit @roger-ryao
- [BUG] Node block-type disk is unable to unbind from userspace driver after failed to add it to node disk [9126](https://github.com/longhorn/longhorn/issues/9126) - @derekbit @roger-ryao
- [BUG] Test case test_rwx_delete_share_manager_pod fails after changes for RWX HA. [9081](https://github.com/longhorn/longhorn/issues/9081) - @yangchiu @PhanLe1010 @james-munson
- [BUG] RWX volume is stuck in auto-salvage loop forever if volume becomes faulted and RWX fast failover setting is enabled [9089](https://github.com/longhorn/longhorn/issues/9089) - @PhanLe1010 @chriscchien
- [BUG]filesystem trim RecurringJob times out (volumes where files are frequently created and deleted) [6868](https://github.com/longhorn/longhorn/issues/6868) - @c3y1huang @roger-ryao
- [BUG] Can not revert V2 volume snapshot after upgrade from v1.6.2 to v1.7.0-dev [9054](https://github.com/longhorn/longhorn/issues/9054) - @chriscchien @DamiaSan
- [BUG] Share manager controller reconciles tens of thousands of times [9086](https://github.com/longhorn/longhorn/issues/9086) - @ejweber @roger-ryao
- [BUG] Non-existing block device results in longhorn-manager to be in Crashloopbackoff state  [9073](https://github.com/longhorn/longhorn/issues/9073) - @yangchiu @derekbit
- [BUG] v2 snapshot creation time will change in UI from time to time [7641](https://github.com/longhorn/longhorn/issues/7641) - @chriscchien @DamiaSan
- [BUG][v1.7.x-head] Test case `test_support_bundle_should_not_timeout` support bundle cleanup failed [9055](https://github.com/longhorn/longhorn/issues/9055) - @yangchiu @mantissahz
- [BUG][v1.7.0-rc1] Clone DR volume result in fail [9016](https://github.com/longhorn/longhorn/issues/9016) - @a110605 @PhanLe1010 @chriscchien
- [BUG] longhorn rwx volume fails to mount on first pod [6857](https://github.com/longhorn/longhorn/issues/6857) - @james-munson
- [BUG][v1.7.0-rc1] Test case `test_csi_encrypted_block_volume` failed even though `cryptsetup` has been installed [9000](https://github.com/longhorn/longhorn/issues/9000) - @ejweber @roger-ryao
- [BUG] System restore with backing image could fail due to backing image checksum mismatch [9041](https://github.com/longhorn/longhorn/issues/9041) - @ChanYiLin @roger-ryao
- [BUG] Longhorn v.1.7.0-rc1 on ARM, the v2-data-engine failed to enable the instance-manager pod  [9004](https://github.com/longhorn/longhorn/issues/9004) - @derekbit @roger-ryao
- [BUG][v1.7.x-head] Test case `test_engine_image_not_fully_deployed_perform_auto_upgrade_engine` failed due to engine image unable to deploy on one of nodes [9038](https://github.com/longhorn/longhorn/issues/9038) - @yangchiu @mantissahz
- [BUG][v1.7.x-head] Test case `test_allow_volume_creation_with_degraded_availability_csi` failed due to inconsistent `Scheduled` status [9035](https://github.com/longhorn/longhorn/issues/9035) - @yangchiu @ejweber
- [BUG] V2 volume snapshot creation time disappear after upgrade from v1.6.2 to v1.7.0-dev [9045](https://github.com/longhorn/longhorn/issues/9045) - @chriscchien @DamiaSan
- [BUG] RWX pod stuck in hanging forever after a node shutdown/reboot [9022](https://github.com/longhorn/longhorn/issues/9022) - @yangchiu @c3y1huang
- [BUG][v1.7.0-rc1] Workload unable to recover after kubelet restart with error: MountVolume.MountDevice failed [9014](https://github.com/longhorn/longhorn/issues/9014) - @yangchiu @c3y1huang
- [BUG][v1.7.0-rc1] Require unexpected long time to remount RWX volume after share manager restarted [8999](https://github.com/longhorn/longhorn/issues/8999) - @yangchiu @c3y1huang
- [BUG][v1.7.x] V2 volume cannot detach after upgrade if a recurring job was set before the upgrade [9032](https://github.com/longhorn/longhorn/issues/9032) - @derekbit @chriscchien
- [BUG] Pod auto-deletion may cause thousands of logs [9019](https://github.com/longhorn/longhorn/issues/9019) - @yangchiu @ejweber
- [BUG] HA Volume Migration: Volume does not auto-attach to another node after turning off the original node [9039](https://github.com/longhorn/longhorn/issues/9039) - @ejweber @roger-ryao
- [BUG][UI][v1.7.0-rc1] Instance manager image search by state not work properly [9010](https://github.com/longhorn/longhorn/issues/9010) - @a110605 @chriscchien
- [BUG] The check of longhorn-cli for spdk environment is set to 1024 MiB [8994](https://github.com/longhorn/longhorn/issues/8994) - @derekbit @mantissahz
- [BUG] Encrypted volume can't be mounted to the workload [9002](https://github.com/longhorn/longhorn/issues/9002) - 
- [BUG] The volume remain in attached state even if detach action is called on the volume which is in migration process and old engine node is powered down. [3401](https://github.com/longhorn/longhorn/issues/3401) - @ejweber @chriscchien
- [BUG][UI] Snapshots and Backups content not alignment in volume detail page of a restored v2 volume  [8964](https://github.com/longhorn/longhorn/issues/8964) - @derekbit @roger-ryao
- [BUG] Can not change `storage-network-for-rwx-volume-enabled` when RWX volume attached [8979](https://github.com/longhorn/longhorn/issues/8979) - @c3y1huang @chriscchien
- [BUG] Undocumented changes in migration behavior since v1.4.x [8735](https://github.com/longhorn/longhorn/issues/8735) - @yangchiu @ejweber
- [BUG] v2 volume data are not sync before taking a snapshot [8977](https://github.com/longhorn/longhorn/issues/8977) - @derekbit @chriscchien
- [BUG] Extra recurring jobs being created after volume restoration [8874](https://github.com/longhorn/longhorn/issues/8874) - @ChanYiLin @mantissahz
- [BUG] Backing image related test cases failed [8887](https://github.com/longhorn/longhorn/issues/8887) - @ChanYiLin @mantissahz
- [BUG] Cannot do a Helm upgrade after PR 2763 [8974](https://github.com/longhorn/longhorn/issues/8974) - @mantissahz @roger-ryao
- [BUG] OpenShift 4.15.3 - Lonhorn 1.6.1 - longhorn-ui nginx (13: Permission denied) [8300](https://github.com/longhorn/longhorn/issues/8300) - @mantissahz @roger-ryao
- [BUG] Can not create V2 volume(faulted) after upgrade from v1.6.2 to v1.7.0-dev [8967](https://github.com/longhorn/longhorn/issues/8967) - @derekbit @chriscchien
- [BUG] Cloned PVC from detached volume will stuck at not ready for workload [3692](https://github.com/longhorn/longhorn/issues/3692) - @PhanLe1010 @chriscchien
- [BUG] Volume cloning retry logic causes unnecessary updates to engine CR [8952](https://github.com/longhorn/longhorn/issues/8952) - @PhanLe1010 @roger-ryao
- [BUG] controller-gen panic while generating crds.yaml [8901](https://github.com/longhorn/longhorn/issues/8901) - @derekbit @chriscchien
- [BUG] Create backup from UI volume page failed [8947](https://github.com/longhorn/longhorn/issues/8947) - @yangchiu @a110605 @chriscchien
- [BUG] iscsid - connect to x.x.x.x failed - no route to host [7386](https://github.com/longhorn/longhorn/issues/7386) - @PhanLe1010 @roger-ryao
- [BUG] Longhorn upgrade from 1.4.4 to 1.5.5 failing [8578](https://github.com/longhorn/longhorn/issues/8578) - @PhanLe1010 @roger-ryao
- [BUG] v2 volume snapshot invalid date [8862](https://github.com/longhorn/longhorn/issues/8862) - @yangchiu @DamiaSan
- [BUG] Pod mount took a long time even PV/PVC bound [2590](https://github.com/longhorn/longhorn/issues/2590) - @yangchiu @mantissahz
- [BUG] Uninstallation fails if backup exists in error state [3082](https://github.com/longhorn/longhorn/issues/3082) - @mantissahz @chriscchien
- [BUG] Executing fstrim while rebuilding causes IO errors [7103](https://github.com/longhorn/longhorn/issues/7103) - @yangchiu @ejweber
- [BUG] Workload cannot recover after tainting node [2517](https://github.com/longhorn/longhorn/issues/2517) - @ejweber @chriscchien @roger-ryao
- [BUG] Backup marked as "completed" cannot be restored, gzip: invalid header [7687](https://github.com/longhorn/longhorn/issues/7687) - @derekbit @roger-ryao
- [BUG] Use config map to update `default-replica-count` won't apply to `default-replica-count.definition.default` if the value equal to current `default-replica-count.value` [7755](https://github.com/longhorn/longhorn/issues/7755) - @james-munson @chriscchien
- [BUG] Deadlock between volume migration and upgrade after Longhorn upgrade [7833](https://github.com/longhorn/longhorn/issues/7833) - @ejweber @roger-ryao
- [BUG] After perform volume online expand to a unavailable value, expand volume again with a proper value will succeed but actually the storage size not changed. [7841](https://github.com/longhorn/longhorn/issues/7841) - @mantissahz @chriscchien
- [BUG] The feature of auto remount read only volume not work on a single node cluster. [7843](https://github.com/longhorn/longhorn/issues/7843) - @ChanYiLin @chriscchien
- [BUG] Add Snapshot Maximum Count to the Settings [7906](https://github.com/longhorn/longhorn/issues/7906) - @FrankYang0529 @yardenshoham @roger-ryao
- [BUG] BackingImage does not download URL correctly in some situation [7914](https://github.com/longhorn/longhorn/issues/7914) - @votdev @yangchiu
- [BUG] The activated DR volume do not contain the latest data. [7945](https://github.com/longhorn/longhorn/issues/7945) - @shuo-wu @roger-ryao
- [BUG] A replica may be incorrectly scheduled to a node with an existing failed replica [8043](https://github.com/longhorn/longhorn/issues/8043) - @ejweber @chriscchien
- [BUG] Exporting data from the existing replicas has issues in 1.6.0 [8094](https://github.com/longhorn/longhorn/issues/8094) - @ChanYiLin @chriscchien
- [BUG] Failed to restore a backup to file by the scripts/restore-backup-to-file.sh with a CIFS backup target. [8126](https://github.com/longhorn/longhorn/issues/8126) - @mantissahz @chriscchien
- [BUG] potential risk to unmap a negative number [8235](https://github.com/longhorn/longhorn/issues/8235) - @Vicente-Cheng @roger-ryao
- [BUG] Failed to delete a v2 orphan replica [8642](https://github.com/longhorn/longhorn/issues/8642) - @shuo-wu
- [BUG] When revision counter is disabled, the engine might choose a replica with a smaller head size to be the source of truth for auto-salvage [8659](https://github.com/longhorn/longhorn/issues/8659) - @PhanLe1010 @chriscchien
- [BUG] Uninstallation will fail if invalid backuptarget is set. [8784](https://github.com/longhorn/longhorn/issues/8784) - @mantissahz @chriscchien
- [BUG] Unable to create backup recurring job with label [8868](https://github.com/longhorn/longhorn/issues/8868) - @yangchiu @ChanYiLin
- [BUG] Test case `test_reuse_failed_replica` failed due to issues with replica-replenishment-wait-interval behavior [8891](https://github.com/longhorn/longhorn/issues/8891) - @yangchiu @c3y1huang
- [BUG] Test case `test_allow_volume_creation_with_degraded_availability_restore` failed. Inconsistent replica creation behavior. [8893](https://github.com/longhorn/longhorn/issues/8893) - @yangchiu @c3y1huang
- [BUG] Scheduling related test cases fail with wrong Scheduled status [8867](https://github.com/longhorn/longhorn/issues/8867) - @yangchiu @c3y1huang
- [BUG] Volume failed to create a new replica after Replica Replenishment Wait Interval [8870](https://github.com/longhorn/longhorn/issues/8870) - @c3y1huang @chriscchien
- [BUG] Failed to create a new replica after an existing replica node becomes unschedulable [8872](https://github.com/longhorn/longhorn/issues/8872) - @c3y1huang @roger-ryao
- [BUG] Test case `test_migration_with_unscheduled_replica` failed [8873](https://github.com/longhorn/longhorn/issues/8873) - @yangchiu @c3y1huang
- [BUG] Unable to create backing image [8877](https://github.com/longhorn/longhorn/issues/8877) - @yangchiu @ChanYiLin
- [BUG] Volume failed to delete redundant replicas on the same node [8869](https://github.com/longhorn/longhorn/issues/8869) - @c3y1huang @chriscchien
- [BUG] Failed to backup snapshot: Internal error occurred: invalid character 'i' looking for beginning of value [8861](https://github.com/longhorn/longhorn/issues/8861) - @yangchiu @ChanYiLin
- [BUG] No replica is created after increased replica count [8871](https://github.com/longhorn/longhorn/issues/8871) - @c3y1huang @chriscchien
- [BUG] Helm upgrade from v1.6.2 to v1.7.0-dev failed due to the longhorn-post-upgrade job exceeding the BackoffLimit. [8866](https://github.com/longhorn/longhorn/issues/8866) - @PhanLe1010 @chriscchien
- [BUG] Orphan longhorn-engine-manager and longhorn-replica-manager services  [8844](https://github.com/longhorn/longhorn/issues/8844) - @PhanLe1010 @chriscchien
- [BUG] v2-data-engine-log-level not applied [8865](https://github.com/longhorn/longhorn/issues/8865) - @derekbit @chriscchien
- [BUG]  Scale replica snapsots warning [4126](https://github.com/longhorn/longhorn/issues/4126) - @yangchiu @ejweber
- [BUG] RWX volume is hang on Photon OS [8253](https://github.com/longhorn/longhorn/issues/8253) - @PhanLe1010 @chriscchien
- [BUG] spdk_tgt somehow ran into an internal error. [7703](https://github.com/longhorn/longhorn/issues/7703) - @yangchiu @DamiaSan
- [BUG] Can not add block disk - Failed to initialize OpenSSL [8846](https://github.com/longhorn/longhorn/issues/8846) - @derekbit @chriscchien
- [BUG] longhorn-manager /usr/local/sbin/ volume and noexec configuration [8780](https://github.com/longhorn/longhorn/issues/8780) - @chriscchien @lenglet-k
- [IMPROVEMENT] System restore unable to restore volume with backing image [5085](https://github.com/longhorn/longhorn/issues/5085) - @ChanYiLin @roger-ryao
- [BUG] backing image isn't restored after restored a system backup  [8515](https://github.com/longhorn/longhorn/issues/8515) - @ChanYiLin @roger-ryao
- [BUG] System backup failed because backup creation failed. [8650](https://github.com/longhorn/longhorn/issues/8650) - @ChanYiLin @chriscchien
- [BUG] instance-manager pod for v2 volume is killed due to a failed liveness probe. [8807](https://github.com/longhorn/longhorn/issues/8807) - @derekbit @chriscchien
- [BUG] Replica Auto Balance options under General Setting and under Volume section should have similar case  [7530](https://github.com/longhorn/longhorn/issues/7530) - @yangchiu @a110605
- [BUG] longhorn-manager build failed [8400](https://github.com/longhorn/longhorn/issues/8400) - @yangchiu @mantissahz @hookak
- [BUG][v1.6.0-rc3] Randomly observed v2 volume the first replica rebuilding failed [7810](https://github.com/longhorn/longhorn/issues/7810) - @DamiaSan
- [BUG] Sometimes v2 volume stuck at attaching because engine error [6176](https://github.com/longhorn/longhorn/issues/6176) - @shuo-wu
- [BUG] `toomanysnapshots` UI message displays incorrect snapshot count [8668](https://github.com/longhorn/longhorn/issues/8668) - @ejweber @roger-ryao
- [BUG in the internal Testing code] Create backup failed: failed lock lock-*.lck type 1 acquisition [7744](https://github.com/longhorn/longhorn/issues/7744) - @yangchiu @ChanYiLin @chriscchien
- [BUG] Missed NodeStageVolume after reboot leads to CreateContainerError [8009](https://github.com/longhorn/longhorn/issues/8009) - @ejweber @chriscchien
- [BUG] Backing image disk state unknown after unmount disk [6443](https://github.com/longhorn/longhorn/issues/6443) - @ChanYiLin @chriscchien
- [BUG] Can not add block disk on longhorn node [8320](https://github.com/longhorn/longhorn/issues/8320) - @derekbit @chriscchien
- [BUG] longhorn-engine integration-test fails after introducing the fix of golangci-lint error [8548](https://github.com/longhorn/longhorn/issues/8548) - @derekbit @chriscchien
- [BUG] instance-manager is stuck at starting state [8455](https://github.com/longhorn/longhorn/issues/8455) - @derekbit @chriscchien
- [BUG] system restore stuck because of the volume/PV/PVC restoration [8601](https://github.com/longhorn/longhorn/issues/8601) - @ChanYiLin @roger-ryao
- [BUG] Fix longhorn-manager `TestCleanupRedundantInstanceManagers` [8658](https://github.com/longhorn/longhorn/issues/8658) - @derekbit @roger-ryao
- [BUG] Volume cannot attach because of the leftover non-empty volume.status.PendingNodeID after upgrading Longhorn [7994](https://github.com/longhorn/longhorn/issues/7994) - @james-munson @chriscchien
- [BUG] LH manager reboots due to the webhook is not ready [8005](https://github.com/longhorn/longhorn/issues/8005) - @ChanYiLin @chriscchien
- [BUG] BackupTarget conditions don't reflect connection errors in v1.6.0 [8210](https://github.com/longhorn/longhorn/issues/8210) - @ejweber @chriscchien
- [BUG] Longhorn can no longer create XFS volumes smaller than 300 MiB [8488](https://github.com/longhorn/longhorn/issues/8488) - @ejweber @chriscchien
- [BUG] Secret for backup not found [8299](https://github.com/longhorn/longhorn/issues/8299) - @mantissahz @roger-ryao
- [BUG] Volume failed to create healthy replica after data locality and replica count changed and got stuck in degraded state forever [8522](https://github.com/longhorn/longhorn/issues/8522) - @ejweber @roger-ryao
- [BUG] VolumeSnapshot keeps in a non-ready state even related LH snapshot and backup are ready [8618](https://github.com/longhorn/longhorn/issues/8618) - @PhanLe1010
- [BUG] Valid backup secret produces error message: "there is space or new line in AWS_CERT" [7159](https://github.com/longhorn/longhorn/issues/7159) - @mantissahz @chriscchien
- [BUG][1.5.0] instance-manager doesn't seem to apply the tolerations [6313](https://github.com/longhorn/longhorn/issues/6313) - @ejweber
- [BUG] The README.md in `longhorn-manager` is outdated [6914](https://github.com/longhorn/longhorn/issues/6914) - @mantissahz
- [BUG] Instance manager pod consumes high CPU usage  [8496](https://github.com/longhorn/longhorn/issues/8496) - @derekbit @roger-ryao
- [BUG] Lost connection to unix:///csi/csi.sock [8427](https://github.com/longhorn/longhorn/issues/8427) - @ejweber @roger-ryao
- [BUG] share-manager-pvc appears to be leaking memory [8394](https://github.com/longhorn/longhorn/issues/8394) - @derekbit @roger-ryao
- [BUG] Longhorn Helm uninstall times out. [8408](https://github.com/longhorn/longhorn/issues/8408) - @ChanYiLin @roger-ryao
- [BUG] Disable tls 1.0 and 1.1 on webhook service [8387](https://github.com/longhorn/longhorn/issues/8387) - @ChanYiLin @roger-ryao
- [BUG] Longhorn may keep corrupted salvaged replicas and discard good ones [7425](https://github.com/longhorn/longhorn/issues/7425) - @ejweber @roger-ryao
- [BUG] v2 volume gets stuck after force deleting one of its replicas [8354](https://github.com/longhorn/longhorn/issues/8354) - @derekbit @chriscchien
- [BUG] Decrement the number allocated clusters of a blob after executing UNMAP [8411](https://github.com/longhorn/longhorn/issues/8411) - @DamiaSan
- [BUG] gRPC server reflection doesn't work for ProxyEngineService [5752](https://github.com/longhorn/longhorn/issues/5752) - @FrankYang0529 @roger-ryao
- [BUG] Replica rebuild failed [8091](https://github.com/longhorn/longhorn/issues/8091) - @yangchiu @shuo-wu
- [BUG] persistence.removeSnapshotsDuringFilesystemTrim Helm variable is unreferenced [7909](https://github.com/longhorn/longhorn/issues/7909) - @ejweber @roger-ryao
- [BUG] mount volume with rwx mode, frequent error output "kernel: nfs: Deprecated parameter 'intr'" [6599](https://github.com/longhorn/longhorn/issues/6599) - 
- [BUG] longhorn manager pod fails to start in container-based K3s [5693](https://github.com/longhorn/longhorn/issues/5693) - @ChanYiLin @chriscchien @andrewd-zededa
- [BUG] Longhorn api-server PUT request rate [8114](https://github.com/longhorn/longhorn/issues/8114) - @ejweber @roger-ryao
- [BUG] DOCS - Incorrect documentation on pre-upgrade checker configuration [8336](https://github.com/longhorn/longhorn/issues/8336) - @yangchiu
- [BUG] Can't use longhorn with Generic ephemeral volumes [8198](https://github.com/longhorn/longhorn/issues/8198) - @ejweber @roger-ryao
- [BUG] no Pending workload pods for volume xxx to be mounted [8072](https://github.com/longhorn/longhorn/issues/8072) - @c3y1huang @roger-ryao
- [BUG] RWX volumes are broken after share-manager base image update [8166](https://github.com/longhorn/longhorn/issues/8166) - @ejweber
- [BUG] automatically updating Rancher image mirror list is not working [8066](https://github.com/longhorn/longhorn/issues/8066) - @PhanLe1010
- [BUG] Panic during collecting metrics [8098](https://github.com/longhorn/longhorn/issues/8098) - @derekbit
- [BUG] metric `longhorn_volume_robustness` did not reflect detached volume [8139](https://github.com/longhorn/longhorn/issues/8139) - @c3y1huang @chriscchien
- [BUG] Deadlock is possible in v1.6.0 instance manager [7919](https://github.com/longhorn/longhorn/issues/7919) - @ejweber @chriscchien
- [BUG] ENGINE v2 : disk /dev/xxxx is already used by AIO bdev disk-x [8129](https://github.com/longhorn/longhorn/issues/8129) - @derekbit @chriscchien
- [BUG] Volumes stuck upgrading after 1.5.3 -> 1.6.0 upgrade. [7887](https://github.com/longhorn/longhorn/issues/7887) - @yangchiu @ejweber
- [BUG][v1.5.4-rc4] Test case test_backuptarget_available_during_engine_image_not_ready failed to wait for backup target available [8045](https://github.com/longhorn/longhorn/issues/8045) - @yangchiu @c3y1huang
- [BUG][v1.5.x] Recurring job fails to create backup when volume detached [7937](https://github.com/longhorn/longhorn/issues/7937) - @yangchiu @mantissahz @PhanLe1010 @c3y1huang
- [BUG] Fix codespell issues in backing-image-manager [7893](https://github.com/longhorn/longhorn/issues/7893) - @votdev
- [BUG][v1.5.4-rc1] Recurring job failed to create/delete backups after node reboot [7854](https://github.com/longhorn/longhorn/issues/7854) - @ChanYiLin @james-munson
- [BUG][v1.6.0-rc1] Negative test case failed: Stress Volume Node CPU/Memory When Volume Is Offline Expanding [7707](https://github.com/longhorn/longhorn/issues/7707) - @PhanLe1010

### Performance
- [DOC] Reference Architecture and Sizing Guidelines [2598](https://github.com/longhorn/longhorn/issues/2598) - @yangchiu @PhanLe1010

### Benchmark
- [TASK] Add 1.6.0 performance report [7829](https://github.com/longhorn/longhorn/issues/7829) - @derekbit

### Miscellaneous
- [DOC] Last-ditch uninstall cleanup instructions are out of date. [9116](https://github.com/longhorn/longhorn/issues/9116) - @james-munson
- [TASK] Fix CVE issues for v1.7.0 (RC3)  [9172](https://github.com/longhorn/longhorn/issues/9172) - @c3y1huang
- [DOC] Update `Quick Installation` document for `longhornctl` [9075](https://github.com/longhorn/longhorn/issues/9075) - @mantissahz @chriscchien
- [TASK] Fix CVE issues for v1.7.0 (RC1) [8976](https://github.com/longhorn/longhorn/issues/8976) - @c3y1huang
- [DOC] Improve the usage and official doc for Longhorn CLI [8992](https://github.com/longhorn/longhorn/issues/8992) - @c3y1huang
- [TASK] Move longhorn/[samba,nfs-ganesha] to rancher/[samba,nfs-ganesha] before v1.7.0-rc2 [8991](https://github.com/longhorn/longhorn/issues/8991) - @derekbit
- [TASK] Bump base images to SLES 15.6 [8273](https://github.com/longhorn/longhorn/issues/8273) - @mantissahz
- [TASK] Update the best practice page to mention some broken kernels [8881](https://github.com/longhorn/longhorn/issues/8881) - @yangchiu @PhanLe1010
- [REFACTOR] Move the construction of each backup store service to service constructor  [5840](https://github.com/longhorn/longhorn/issues/5840) - @mantissahz @chriscchien
- [DOC] Update v2 engine prerequisites [8819](https://github.com/longhorn/longhorn/issues/8819) - @DamiaSan
- [TASK] Update nvme-cli to v2.9.1 for v2 data engine [8836](https://github.com/longhorn/longhorn/issues/8836) - @derekbit @roger-ryao
- [TASK] Update longhorn-spdk-engine and longhorn-instance-manager to SPDK longhorn-v24.05 [8820](https://github.com/longhorn/longhorn/issues/8820) - @DamiaSan
- [TASK] Manage Shallow copy async in go-spdk-helper [8772](https://github.com/longhorn/longhorn/issues/8772) - @DamiaSan
- [REFACTOR] Build a method to differentiate process type instead of port number [7393](https://github.com/longhorn/longhorn/issues/7393) - @yangchiu @ChanYiLin
- [TASK] Creation of longhorn-v24.05 branch [8595](https://github.com/longhorn/longhorn/issues/8595) - @DamiaSan
- [TASK] Upgrade Go version to 1.22 [8337](https://github.com/longhorn/longhorn/issues/8337) - @FrankYang0529
- [FEATURE] Support backing image metrics collection [7563](https://github.com/longhorn/longhorn/issues/7563) - @ChanYiLin @chriscchien
- [REFACTOR] move mount point check function to common lib [7394](https://github.com/longhorn/longhorn/issues/7394) - @ChanYiLin @roger-ryao
- [TASK] Fix errors when upgrading K8s lib to 0.30 [8056](https://github.com/longhorn/longhorn/issues/8056) - @mantissahz @chriscchien
- [DOC] Incorrect and invalid links  [8633](https://github.com/longhorn/longhorn/issues/8633) - @jillian-maroket
- [TASK] Remove v2 volume offline rebuilding in Longhorn v1.7 [8442](https://github.com/longhorn/longhorn/issues/8442) - @derekbit @chriscchien
- [TASK] Performance and scalability report for Longhorn [2986](https://github.com/longhorn/longhorn/issues/2986) - @PhanLe1010
- [TASK] Sync longohorn/spdk codes with upstream codes [7812](https://github.com/longhorn/longhorn/issues/7812) - @DamiaSan
- [QUESTION] Safe node shutdown, disk eviction, replicas and orphaned volumes [6921](https://github.com/longhorn/longhorn/issues/6921) - 
- [DOC] Hugepage-2Mi recommended [7008](https://github.com/longhorn/longhorn/issues/7008) - 
- [DOC] uninstall longhorn with argocd,  the longhorn is still running. [8395](https://github.com/longhorn/longhorn/issues/8395) - 
- [DOC] Add uninstall and upgrade doc for GitOps solutions [8441](https://github.com/longhorn/longhorn/issues/8441) - @yangchiu
- [TASK] Clarify the reason for k8s.io replace directives in go.mod files [8481](https://github.com/longhorn/longhorn/issues/8481) - @ejweber
- [DOC] Add a doc for elaborating when will the requesting remount be triggered [7965](https://github.com/longhorn/longhorn/issues/7965) - @ChanYiLin
- [TASK] Collect all proto files in longhorn-types repo [6744](https://github.com/longhorn/longhorn/issues/6744) - @FrankYang0529
- Algolia search for DS [8178](https://github.com/longhorn/longhorn/issues/8178) - @jhkrug
- Netlify preview site for Docusaurus, provided by the project infrastructure. [8181](https://github.com/longhorn/longhorn/issues/8181) - @jhkrug
- DS requires an `authors.yml` file for the KB. [8182](https://github.com/longhorn/longhorn/issues/8182) - @jhkrug
- Improve ordering in sections [8220](https://github.com/longhorn/longhorn/issues/8220) - @jhkrug
- Improve broken links management [8215](https://github.com/longhorn/longhorn/issues/8215) - @jhkrug
- Styling to match the current website in feel [8173](https://github.com/longhorn/longhorn/issues/8173) - @jhkrug
- Remove or change Hugo formatting to Docusaurus [8165](https://github.com/longhorn/longhorn/issues/8165) - @jhkrug
- [TASK] Downgrade the package `github.com/prometheus/common` [8274](https://github.com/longhorn/longhorn/issues/8274) - @mantissahz
- [TASK] SPDK raid merge with upstream [8074](https://github.com/longhorn/longhorn/issues/8074) - @DamiaSan
- [DOC] Update fleet document for ignoring more modified crd [8214](https://github.com/longhorn/longhorn/issues/8214) - @yangchiu
- [TASK] Generate BackupBackingImage Backend API [8068](https://github.com/longhorn/longhorn/issues/8068) - @ChanYiLin @chriscchien
- [DOC] Typo on Longhorn-specific StorageClass parameters [8170](https://github.com/longhorn/longhorn/issues/8170) - 
- [UI][TASK] Generate BackupBackingImage Backend API [8069](https://github.com/longhorn/longhorn/issues/8069) - 
- [TASK] Clean up defunct patches and scripts [5945](https://github.com/longhorn/longhorn/issues/5945) - @ejweber
- [TASK] Update version file in component repos automatically when starting a new release [7958](https://github.com/longhorn/longhorn/issues/7958) - 

## Contributors
- @ChanYiLin 
- @DamiaSan 
- @FrankYang0529 
- @PhanLe1010 
- @Vicente-Cheng 
- @a110605 
- @andrewd-zededa 
- @c3y1huang 
- @chriscchien 
- @derekbit 
- @e3b0c442 
- @ejweber 
- @hookak 
- @innobead 
- @james-munson 
- @jhkrug 
- @jillian-maroket 
- @kejrak 
- @lenglet-k 
- @mantissahz 
- @roger-ryao 
- @shuo-wu 
- @tserong 
- @votdev 
- @yangchiu 
- @yardenshoham
- @rebeccazzzz
- @forbesguthrie
- @asettle