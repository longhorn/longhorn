## Longhorn v1.6.0 Release Notes

This latest version of Longhorn introduces several features, enhancements, and bug fixes that are intended to improve system quality and the overall user experience. Highlights include new V2 Data Engine features, platform-agnostic deployment, node maintenance, and improvements to stability, performance, and resilience.

The Longhorn team appreciates your contributions and anticipates receiving feedback regarding this release.

> **Note:**
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Primary Highlights

### New V2 Data Engine Features

Although the V2 Data Engine is still considered a preview feature in this release, the core functions have been significantly enhanced. For example, you can now seamlessly perform volume backup and restore operations between the V1 and V2 Data Engines, paving the way for volume migration between the two data engines in the future.

- [Volume Snapshot and Revert](https://github.com/longhorn/longhorn/issues/6137)
- [Volume Backup and Restore](https://github.com/longhorn/longhorn/issues/6138)
- [Separate Data Plane for v1 and v2 Data Engines](https://github.com/longhorn/longhorn/issues/7015)
- [ARM64 Support](https://github.com/longhorn/longhorn/issues/6021)

The Longhorn team will continue to develop features for the V1 Data Engine and to prepare the V2 Data Engine for use in all types of environments.

### Platform-Agnostic Deployment

Longhorn is designed to seamlessly operate on general-purpose Linux distributions, and on certain container-optimized systems such as SLE Micro. In response to numerous requests, v1.6.0 was enhanced to allow installation of Longhorn components on [Talos](https://www.talos.dev/), which is a secure, immutable, and minimal Kubernetes OS. v1.6.0 also includes OKD support, which was contributed by community member @ArthurVardevanyan.

- [Talos Support](https://github.com/longhorn/longhorn/issues/3161) 
- [OKD (OpenShift Origin) Support](https://github.com/longhorn/longhorn/issues/1831)

The Longhorn team is committed to making Longhorn an adaptive storage solution and anticipates receiving feedback regarding your preferred platforms.

### Space Efficiency

Starting with v1.6.0, Longhorn allows you to configure the maximum snapshot count and the maximum aggregate snapshot size for all volumes and for specific volumes. Both settings, whether applied globally or individually, aid in space estimation and management. Earlier Longhorn versions do not provide mechanisms for controlling or predicting the quantity and size of volume snapshots.

- [Snapshot Space Management](https://github.com/longhorn/longhorn/issues/6563)

### GitOps Friendly

Longhorn has been validated with popular GitOps solutions, including [Flux](https://github.com/longhorn/longhorn/issues/6343), [Argo CD](https://github.com/longhorn/longhorn/issues/6434), and [Fleet](https://github.com/longhorn/longhorn/issues/6935). Future releases will include enhancements that further solidify Longhorn's status as a GitOps-aware storage solution.

### Data Protection

Longhorn now supports [block volume encryption](https://github.com/longhorn/longhorn/issues/4883), which is particularly beneficial in virtualization use cases such as Harvester and KubeVirt.

### Node Maintenance

v1.6.0 includes two new [node drain policy options](https://longhorn.io/docs/1.6.0/references/settings/#node-drain-policy): *Block For Eviction* and *Block For Eviction If Contains Last Replica*. Both options allow automatic eviction and relocation of healthy replicas from draining nodes (before the nodes are cordoned).

The Longhorn team recommends enabling these options only during planned maintenance to minimize impact on data movement. For more information about the advantages and disavantages of all options, see [Node Drain Policy Recommendations](../../volumes-and-nodes/maintenance/#node-drain-policy-recommendations) in the Longhorn documentation.

### Backing Image Management

Longhorn now allows you to [create and restore backups of backing images](https://github.com/longhorn/longhorn/issues/4165), which can streamline the management of backing images across clusters. This feature is particularly beneficial in virtualization use cases such as Harvester and KubeVirt.

## Installation

**Ensure that your cluster is running Kubernetes v1.21 or later before installing Longhorn v1.6.0.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.6.0/deploy/install/) in the Longhorn documentation.

## Upgrade

**Ensure that your cluster is running Kubernetes v1.21 or later before upgrading from Longhorn v1.5.x to v1.6.0.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.6.0/deploy/upgrade/) in the Longhorn documentation.

## Deprecation & Incompatibilities

For information about important changes, including feature incompatibility, deprecation, and removal, see [Important Notes](https://longhorn.io/docs/1.6.0/deploy/important-notes/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Highlights
- [FEATURE] Longhorn snapshot space management [6563](https://github.com/longhorn/longhorn/issues/6563) - @FrankYang0529 @yangchiu
- [FEATURE] v2 data engine volume snapshot and revert [6137](https://github.com/longhorn/longhorn/issues/6137) - @shuo-wu @roger-ryao
- [FEATURE] Support eventual danger zone setting update [7173](https://github.com/longhorn/longhorn/issues/7173) - @mantissahz @chriscchien
- [FEATURE] Engine upgrade enforcement [5842](https://github.com/longhorn/longhorn/issues/5842) - @yangchiu @mantissahz @c3y1huang
- [FEATURE] Selective V2 Data Engine Activation [7015](https://github.com/longhorn/longhorn/issues/7015) - @derekbit @chriscchien @roger-ryao
- [FEATURE] Have default priorityClass to prevent unexpected longhorn pods eviction [6528](https://github.com/longhorn/longhorn/issues/6528) - @mantissahz @chriscchien
- [FEATURE] v2 volume supports volume backup/restore [6138](https://github.com/longhorn/longhorn/issues/6138) - @yangchiu @derekbit
- [IMPROVEMENT] Remove or Change Helm pre-upgrade hook to support ArgoCD [6415](https://github.com/longhorn/longhorn/issues/6415) - @mantissahz
- [FEATURE] Restore BackingImage for BackupVolume in a new cluster [4165](https://github.com/longhorn/longhorn/issues/4165) - @ChanYiLin @roger-ryao
- [FEATURE] Talos support [3161](https://github.com/longhorn/longhorn/issues/3161) - @yangchiu @c3y1huang
- [FEATURE] Support v2 volume on ARM64 platform [6021](https://github.com/longhorn/longhorn/issues/6021) - @derekbit @chriscchien @roger-ryao
- [IMPROVEMENT] Add a new setting that allows Longhorn to evict replicas automatically when a node is drained [2238](https://github.com/longhorn/longhorn/issues/2238) - @ejweber @chriscchien
- [FEATURE] Add linear dm device on the top of v2 volume [7357](https://github.com/longhorn/longhorn/issues/7357) - @derekbit @chriscchien
- [FEATURE] Support Encryption for VolumeMode Block [4883](https://github.com/longhorn/longhorn/issues/4883) - @derekbit @roger-ryao
- [TASK] Add install/upgrade longhorn by gitops (flux) pipeline [6343](https://github.com/longhorn/longhorn/issues/6343) - @yangchiu
- [FEATURE] OKD/Openshift support [1831](https://github.com/longhorn/longhorn/issues/1831) - @mantissahz @ArthurVardevanyan @roger-ryao

### Features
- [UI][FEATURE] Longhorn snapshot space management [7522](https://github.com/longhorn/longhorn/issues/7522) - @yangchiu @scures
- [FEATURE] RWX volume supports different NFS version (4.2) and mount options [7638](https://github.com/longhorn/longhorn/issues/7638) - @james-munson
- [FEATURE] Introduce `upgradeVersionCheck` to decide version upgrade enforcement  [7539](https://github.com/longhorn/longhorn/issues/7539) - @mantissahz @chriscchien
- [FEATURE] v2 volume replica management [5420](https://github.com/longhorn/longhorn/issues/5420) - @DamiaSan
- [FEATURE] Update nfs-genesha to 5.x for share manager [6000](https://github.com/longhorn/longhorn/issues/6000) - @james-munson @chriscchien
- [FEATURE] Allow to set mount options for storageclass via values.yaml in helm chart [7351](https://github.com/longhorn/longhorn/issues/7351) - @ChanYiLin @chriscchien
- [FEATURE] Flush on-the-fly IOs in the queue before snapshotting [5648](https://github.com/longhorn/longhorn/issues/5648) - @DamiaSan
- [FEATURE] Update base image of Longhorn components to BCI 15.5 [6206](https://github.com/longhorn/longhorn/issues/6206) - @nitendra-suse
- [FEATURE] Customize MaxRecurringJobRetain [5713](https://github.com/longhorn/longhorn/issues/5713) - @mantissahz @chriscchien
- [FEATURE] Replica rebuild over SPDK [5216](https://github.com/longhorn/longhorn/issues/5216) - @shuo-wu @DamiaSan
- [FEATURE] Allow kubectl drain to stop manually attached volumes [6978](https://github.com/longhorn/longhorn/issues/6978) - @ChanYiLin @chriscchien
- [FEATURE] Single Node Disk affinity [3823](https://github.com/longhorn/longhorn/issues/3823) - @ejweber @roger-ryao
- [FEATURE] Storage network support for Multus v4.0 thick-plugin [5048](https://github.com/longhorn/longhorn/issues/5048) - @c3y1huang @chriscchien
- [FEATURE] Add disk status prometheus metrics [6858](https://github.com/longhorn/longhorn/issues/6858) - @c3y1huang @chriscchien
- [FEATURE] Add a brand new/empty bdev with WriteOnly mode to the RAID1 bdev [5865](https://github.com/longhorn/longhorn/issues/5865) - @DamiaSan
- [FEATURE] Add a script to identify the valid volumes to recover given s3 backup url and secret [1523](https://github.com/longhorn/longhorn/issues/1523) - @weizhe0422
- [FEATURE] Pause IO when raid1 bdev snapshotting [5421](https://github.com/longhorn/longhorn/issues/5421) - @DamiaSan
- [FEATURE] Change the replica selector behavior so that an absent selector is able to select nodes without a TAG [4826](https://github.com/longhorn/longhorn/issues/4826) - @ChanYiLin @roger-ryao
- [FEATURE] Helm Chart make loglevel configurable [3655](https://github.com/longhorn/longhorn/issues/3655) - @mantissahz

### Improvements
- [IMPROVEMENT] Use ensureFolderPath rather than ensureMount for checking folder path in CSI plugin [7784](https://github.com/longhorn/longhorn/issues/7784) - @derekbit @roger-ryao
- [IMPROVEMENT] Remove unused process manager connection in longhorn-manager [7783](https://github.com/longhorn/longhorn/issues/7783) - @derekbit @chriscchien
- [IMPROVEMENT] Revert RWX volume back to NFS v4.1 [7741](https://github.com/longhorn/longhorn/issues/7741) - @yangchiu @james-munson
- [IMPROVEMENT] Remove static sessionAffinity: ClientIP set in most services if not required [7399](https://github.com/longhorn/longhorn/issues/7399) - @yangchiu @ejweber
- [IMPROVEMENT] Automatically remount read-only RWO volume to read-write [6386](https://github.com/longhorn/longhorn/issues/6386) - @ChanYiLin @chriscchien
- [IMPROVEMENT] Only restarts pods with volumes in the unexpected Read-Only state  [7728](https://github.com/longhorn/longhorn/issues/7728) - @ChanYiLin @chriscchien
- [IMPROVEMENT] Volumes: metrics for snapshots include (size and type: system vs user) [5869](https://github.com/longhorn/longhorn/issues/5869) - @c3y1huang @chriscchien
- [IMPROVEMENT] Have a clear message when reverting the parent of a volume-head snapshot for a v2 volume [7630](https://github.com/longhorn/longhorn/issues/7630) - @derekbit @chriscchien
- [IMPROVEMENT] Flooding error messages `failed to sync setting for.....` [7654](https://github.com/longhorn/longhorn/issues/7654) - @mantissahz @chriscchien
- [IMPROVEMENT] Enhance the code quality in the instance-manager instance and disk gRPC server methods. [7628](https://github.com/longhorn/longhorn/issues/7628) - @derekbit
- [IMPROVEMENT] Increase the hugepage size for spdk_tgt to 2GiB [7606](https://github.com/longhorn/longhorn/issues/7606) - @derekbit @chriscchien
- [IMPROVEMENT] Reject DR volume creation for v2 volume [7627](https://github.com/longhorn/longhorn/issues/7627) - @derekbit @roger-ryao
- [IMPROVEMENT] Do not use `--force` for dmsetup remove command [7615](https://github.com/longhorn/longhorn/issues/7615) -
- [IMPROVEMENT] Update nvme-cli to v2.7.1 in instance-manager pod [7609](https://github.com/longhorn/longhorn/issues/7609) - @derekbit
- [IMPROVEMENT] Prevent from complains in spdk_tgt when deleting a v2 volume [7568](https://github.com/longhorn/longhorn/issues/7568) - @yangchiu @derekbit @roger-ryao
- [IMPROVEMENT] Expose actual size of a logical volume [5947](https://github.com/longhorn/longhorn/issues/5947) - @derekbit @shuo-wu @chriscchien @DamiaSan
- [IMPROVEMENT] UI backup restoration supports v1 and v2 `Data Engine` [6597](https://github.com/longhorn/longhorn/issues/6597) - @derekbit @scures @roger-ryao
- [IMPROVEMENT][UI] Display v2 volume actual size [7524](https://github.com/longhorn/longhorn/issues/7524) - @derekbit @chriscchien
- [IMPROVEMENT] Recreate instance manager pod for v2 volume when `spdk_tgt` is dead [7551](https://github.com/longhorn/longhorn/issues/7551) - @derekbit @chriscchien
- [IMPROVEMENT] Add reserve storage percentage of nodes setting in helm chart [5958](https://github.com/longhorn/longhorn/issues/5958) - @mantissahz @roger-ryao
- [IMPROVEMENT] Reconcile engine/replica instance state of v2 volume like v1 volume [7326](https://github.com/longhorn/longhorn/issues/7326) - @derekbit @chriscchien
- [IMPROVEMENT] Improve handling of 16TiB+ volumes with ext4 as the underlying file system [7423](https://github.com/longhorn/longhorn/issues/7423) - @mantissahz @chriscchien
- [IMPROVEMENT] Rename backendStoreDriver to dataEngin in instance-manager and associated components [7480](https://github.com/longhorn/longhorn/issues/7480) - @yangchiu @derekbit
- [IMPROVEMENT][UI] Validate volume creation according to the enabled data engines [7505](https://github.com/longhorn/longhorn/issues/7505) - @derekbit @chriscchien
- [IMPROVEMENT] Add guaranteed instanceManager CPU setting for v2 volume [7361](https://github.com/longhorn/longhorn/issues/7361) - @derekbit @roger-ryao
- [IMPROVEMENT] Support backup list if there is only v2-data-engine enabled [7486](https://github.com/longhorn/longhorn/issues/7486) - @derekbit @chriscchien
- [IMPROVEMENT] Upgrade CSI components to the latest patch release [7384](https://github.com/longhorn/longhorn/issues/7384) - @c3y1huang @roger-ryao
- [IMPROVEMENT] Add global setting for enable v1 or v2 volume support [7095](https://github.com/longhorn/longhorn/issues/7095) - @yangchiu @derekbit
- [IMPROVEMENT] Blindly stop raid bdev exposure before exposing it for V2 volume [7324](https://github.com/longhorn/longhorn/issues/7324) - @yangchiu @derekbit @roger-ryao
- [IMPROVEMENT] instance-managers for v1 and v2 volumes respectively   [6984](https://github.com/longhorn/longhorn/issues/6984) - @yangchiu @derekbit
- [IMPROVEMENT] BackingImage should be compressed when downloading and use the name as filename instead of UUID [7295](https://github.com/longhorn/longhorn/issues/7295) - @ChanYiLin @chriscchien
- [IMPROVEMENT] Reject the creation of encrypted v2 volume in validating webhook [7404](https://github.com/longhorn/longhorn/issues/7404) - @derekbit @chriscchien
- [IMPROVEMENT] Longhorn-engine processes should refuse to serve requests not intended for them [5845](https://github.com/longhorn/longhorn/issues/5845) - @ejweber @chriscchien
- [IMPROVEMENT] Collect v2 Data Engine related info for the usage metrics [6033](https://github.com/longhorn/longhorn/issues/6033) - @c3y1huang @chriscchien
- [IMPROVEMENT] Review and simplify longhorn component image build [5911](https://github.com/longhorn/longhorn/issues/5911) - @ChanYiLin @chriscchien
- [IMPROVEMENT] Gracefully shut down spdk_tgt [7263](https://github.com/longhorn/longhorn/issues/7263) - @derekbit @chriscchien
- [IMPROVEMENT] Reject the last replica deletion if its volume.spec.deletionTimestamp is not set [7372](https://github.com/longhorn/longhorn/issues/7372) - @yangchiu @derekbit
- [IMPROVEMENT] add build script to generate gRPC related code more convenient [6973](https://github.com/longhorn/longhorn/issues/6973) - @Vicente-Cheng
- [IMPROVEMENT] Upgrade support bundle kit version to v0.0.33 [7277](https://github.com/longhorn/longhorn/issues/7277) - @c3y1huang
- [IMPROVEMENT] Upgrade CSI sidecar components version [6916](https://github.com/longhorn/longhorn/issues/6916) - @c3y1huang @roger-ryao
- [IMPROVEMENT] Have a setting to disable snapshot purge for maintenance purpose [7075](https://github.com/longhorn/longhorn/issues/7075) - @ejweber @roger-ryao
- [IMPROVEMENT] Don't crash the migration engine when kubelet restarts [7302](https://github.com/longhorn/longhorn/issues/7302) - @ejweber @chriscchien
- [IMPROVEMENT] deploy: driver deployer shouldn't cleanup previous deployment if Kubernetes version changes  [5474](https://github.com/longhorn/longhorn/issues/5474) - @PhanLe1010 @chriscchien
- [IMPROVEMENT] Replace deprecated grpc.WithInsecure [7291](https://github.com/longhorn/longhorn/issues/7291) - @c3y1huang
- [IMPROVEMENT] Allow deployment of Prometheus ServiceMonitor with the Longhorn helm chart [7041](https://github.com/longhorn/longhorn/issues/7041) - @mantissahz @chriscchien
- [IMPROVEMENT] Disable CGO in longhorn components if not used [7135](https://github.com/longhorn/longhorn/issues/7135) - @derekbit
- [IMPROVEMENT] Add test for longhorn-spdk-engine [6060](https://github.com/longhorn/longhorn/issues/6060) - @shuo-wu
- [IMPROVEMENT] Thread-safe SPDK JSON client [6106](https://github.com/longhorn/longhorn/issues/6106) - @shuo-wu
- [IMPROVEMENT] Bypass upgrade when installing a fresh setup [6988](https://github.com/longhorn/longhorn/issues/6988) - @mantissahz @roger-ryao
- [IMPROVEMENT] Upgrade support bundle kit version to v0.0.32 [7152](https://github.com/longhorn/longhorn/issues/7152) - @c3y1huang @chriscchien
- [IMPROVEMENT] Support custom options for network filesystems for backup [6608](https://github.com/longhorn/longhorn/issues/6608) - @james-munson @roger-ryao
- [IMPROVEMENT] Global setting `default-data-path` supports block device [7234](https://github.com/longhorn/longhorn/issues/7234) - @derekbit @chriscchien
- [IMPROVEMENT] Clean up backup target in IM-R pod if the backup target setting is unset [5741](https://github.com/longhorn/longhorn/issues/5741) - @ChanYiLin @chriscchien
- [IMPROVEMENT] Improve log level for resource update failure able to reconcile again [6843](https://github.com/longhorn/longhorn/issues/6843) - @PhanLe1010 @nitendra-suse
- [IMPROVEMENT] Add missing volume settings to the default storage class [6496](https://github.com/longhorn/longhorn/issues/6496) - @james-munson
- [IMPROVEMENT] High memory consumption of longhorn-manager pods since Longhorn v1.5 [6936](https://github.com/longhorn/longhorn/issues/6936) - @derekbit @roger-ryao
- [IMPROVEMENT] Upgrade support bundle kit version to v0.0.29 [6922](https://github.com/longhorn/longhorn/issues/6922) - @c3y1huang @chriscchien
- [IMPROVEMENT] Improve upgrade path and make it more solid [6294](https://github.com/longhorn/longhorn/issues/6294) - @PhanLe1010 @roger-ryao
- [IMPROVEMENT] Use nvme-cli in instance-manager pod instead [6798](https://github.com/longhorn/longhorn/issues/6798) - @derekbit @chriscchien
- [IMPROVEMENT] Add PVC namespace to longhorn_volume metrics [7077](https://github.com/longhorn/longhorn/issues/7077) - @mantissahz @roger-ryao @antoninferrand
- [IMPROVEMENT] Don't log about inability to change settings that didn't change. [6812](https://github.com/longhorn/longhorn/issues/6812) - @james-munson @roger-ryao
- [IMPROVEMENT] Consolidate the mounts in longhorn-manager and instance-manager [5883](https://github.com/longhorn/longhorn/issues/5883) - @ChanYiLin
- [IMPROVEMENT] Make the timeout value of a filesystem-based backup store configurable [5723](https://github.com/longhorn/longhorn/issues/5723) - @ChanYiLin
- [IMPROVEMENT] Unify logs with extra static info like module/method/function/line [5509](https://github.com/longhorn/longhorn/issues/5509) - @ChanYiLin @roger-ryao
- [IMPROVEMENT] Prevent Volume Provision if Related Backing Image Stuck in Ready-For-Trasfer State [6615](https://github.com/longhorn/longhorn/issues/6615) - @ChanYiLin @roger-ryao
- [IMPROVEMENT] Remove dummy services of each CSI sidecar if not required [6581](https://github.com/longhorn/longhorn/issues/6581) - @ejweber @roger-ryao
- [IMPROVEMENT] Old kernel such as 3.10.0 set provisioning_mode to wrong value (writesame_16, disabled, full, ...) but not the correct value (unmap) so the trim feature doesn't work [6854](https://github.com/longhorn/longhorn/issues/6854) - @PhanLe1010 @chriscchien
- [IMPROVEMENT] Support both NFS `hard` and `soft` with custom `timeo` and `retrans` options for RWX volumes [6655](https://github.com/longhorn/longhorn/issues/6655) - @derekbit @roger-ryao
- [IMPROVEMENT] Prevent unexpected engine creation [6682](https://github.com/longhorn/longhorn/issues/6682) - @PhanLe1010 @ejweber @roger-ryao
- [IMPROVEMENT] Add pvc name to longhorn_volume metrics [5297](https://github.com/longhorn/longhorn/issues/5297) - @c3y1huang @nitendra-suse
- [IMPROVEMENT] Replace `engineImage` field in CRDs with `image` [6647](https://github.com/longhorn/longhorn/issues/6647) - @derekbit @chriscchien
- [IMPROVEMENT]  Fix scheduling flooding logs [6019](https://github.com/longhorn/longhorn/issues/6019) - @ChanYiLin @roger-ryao
- [IMPROVEMENT] Avoid the accident deletion of longhorn settings [4984](https://github.com/longhorn/longhorn/issues/4984) - @ejweber @roger-ryao
- [IMPROVEMENT] UI: making batch deletion dialog more readable [4080](https://github.com/longhorn/longhorn/issues/4080) - @smallteeths
- [IMPROVEMENT] Upgrade Longhorn upgrade-responder server and build new Grafana dashboard [6368](https://github.com/longhorn/longhorn/issues/6368) - @PhanLe1010
- [IMPROVEMENT] Consider adding owner reference Backup/BackupVolume CR [5896](https://github.com/longhorn/longhorn/issues/5896) - @ChanYiLin
- [IMPROVEMENT] Include /var/log/messages during the support-bundle syslog collection [6544](https://github.com/longhorn/longhorn/issues/6544) - @c3y1huang @roger-ryao
- [IMPROVEMENT] UI Volume detail page still shows `Block Device` when `spec.disableFrontend` is true [6167](https://github.com/longhorn/longhorn/issues/6167) - @smallteeths @chriscchien
- [IMPROVEMENT] Remove Longhorn engine path mismatch log [3786](https://github.com/longhorn/longhorn/issues/3786) - @c3y1huang @roger-ryao
- [IMPROVEMENT] Provide more information for volume scheduling failure [6461](https://github.com/longhorn/longhorn/issues/6461) - @smallteeths @chriscchien
- [IMPROVEMENT] Implement/fix the unit tests of Volume Attachment and volume controller [6005](https://github.com/longhorn/longhorn/issues/6005) - @PhanLe1010 @roger-ryao
- [QUESTION] Repetitive warnings and errors in a new longhorn setup [6257](https://github.com/longhorn/longhorn/issues/6257) - @derekbit @c3y1huang @roger-ryao
- [IMPROVEMENT] Make environment check script recognize iscsid.socket enable instead of iscsid.server only   [5380](https://github.com/longhorn/longhorn/issues/5380) - @derekbit @roger-ryao

### Bug Fixes
- [BUG] Volumes don't mount with mTLS enabled [7040](https://github.com/longhorn/longhorn/issues/7040) - @sfackler @derekbit @c3y1huang @ejweber @chriscchien
- [BUG] Negative test case failed: Stop Volume Node Kubelet For More Than Pod Eviction Timeout While Workload Heavy Writing [7694](https://github.com/longhorn/longhorn/issues/7694) - @yangchiu @c3y1huang
- [BUG] Rancher cannot import longhorn 1.5 charts due to "error converting YAML to JSON: yaml: line 699: did not find expected key" [7496](https://github.com/longhorn/longhorn/issues/7496) - @mantissahz @PhanLe1010
- [BUG] Volume could not be remounted after engine process killed [7751](https://github.com/longhorn/longhorn/issues/7751) - @yangchiu @ChanYiLin @shuo-wu
- [BUG][v1.6.0-rc2] rwx volume failed to execute trim filesystem [7768](https://github.com/longhorn/longhorn/issues/7768) - @c3y1huang @roger-ryao
- [BUG] Protect spdkClient in ReplicaCreate [7752](https://github.com/longhorn/longhorn/issues/7752) - @derekbit @chriscchien
- [BUG] When disabling revision counter, salvaging a faulty volume not work as expected [7714](https://github.com/longhorn/longhorn/issues/7714) - @james-munson @roger-ryao
- [BUG] Chart v1.6.0-rc2 is not synced between longhorn/longhorn and longhorn/charts [7743](https://github.com/longhorn/longhorn/issues/7743) - @innobead @chriscchien
- [BUG] v2 Engine does not show the rebuilding replica mode  [7718](https://github.com/longhorn/longhorn/issues/7718) - @shuo-wu
- [BUG] Volume rebuilding never succeed after the first rebuilding failed [7723](https://github.com/longhorn/longhorn/issues/7723) - @shuo-wu @chriscchien
- [BUG] Backing Image Data Inconsistency if it's Exported from a Backing Image Backed Volume [6899](https://github.com/longhorn/longhorn/issues/6899) - @ChanYiLin @chriscchien
- [BUG] Remove v2 volume rebuild snapshot could cause volume stuck in detaching/faulted state [7573](https://github.com/longhorn/longhorn/issues/7573) - @yangchiu @shuo-wu
- [BUG] Incompatible engine image kept in "deploying" state on master-head [7683](https://github.com/longhorn/longhorn/issues/7683) - @mantissahz @chriscchien
- [BUG] Updating Taint Toleration is allowed if there are volumes attached [7675](https://github.com/longhorn/longhorn/issues/7675) - @yangchiu @mantissahz
- [BUG] After v2 volume offline rebuilding, re-attached volume remains degraded [7574](https://github.com/longhorn/longhorn/issues/7574) - @yangchiu @shuo-wu
- [BUG] Update settings GuaranteedInstanceManagerCPU and V2DataEngineGuaranteedInstanceManagerCPU separately [7676](https://github.com/longhorn/longhorn/issues/7676) - @mantissahz @chriscchien
- [BUG] Uninstallation job stuck forever if the MutatingWebhookConfigurations or ValidatingWebhookConfigurations already deleted [7657](https://github.com/longhorn/longhorn/issues/7657) - @PhanLe1010 @roger-ryao
- [BUG][v1.6.0-rc1] Some Longhorn resources remaining after longhorn-uninstall job completed [7645](https://github.com/longhorn/longhorn/issues/7645) - @yangchiu @PhanLe1010
- [BUG] Crypt device mapper of RWX volume with `migratable=true` is not cleaned up [7678](https://github.com/longhorn/longhorn/issues/7678) - @derekbit @chriscchien
- [BUG] replica not rebuild in v1.6.0-dev if engine image is v1.4.x [7631](https://github.com/longhorn/longhorn/issues/7631) - @mantissahz @chriscchien
- [BUG] Warning events are being spammed by Longhorn - CRD [7290](https://github.com/longhorn/longhorn/issues/7290) - @m-ildefons @roger-ryao
- [BUG][v1.6.0-rc1] Error message in longhorn-uninstall job logs [7643](https://github.com/longhorn/longhorn/issues/7643) - @yangchiu @ChanYiLin
- [BUG][v1.6.0-rc1] Failed to run instance-manager in storage network environment [7640](https://github.com/longhorn/longhorn/issues/7640) - @yangchiu @c3y1huang
- [BUG] Volume with v1.5.x engine not worked well in v1.6.0-rc1 [7642](https://github.com/longhorn/longhorn/issues/7642) - @FrankYang0529 @chriscchien
- [BUG] Unable to list backups when backuptarget resource is picked up by a cordoned node [7619](https://github.com/longhorn/longhorn/issues/7619) - @derekbit @c3y1huang @chriscchien
- [BUG] Update the description of v2-data-engine setting [7655](https://github.com/longhorn/longhorn/issues/7655) - @derekbit
- [BUG] Deleting instance-manager during restoring a v2 volume, the volume stuck in detaching state [7581](https://github.com/longhorn/longhorn/issues/7581) - @derekbit @chriscchien @roger-ryao
- [BUG] Deleting instance-manager pod causes v2 volume stuck in attaching/detaching loop [7579](https://github.com/longhorn/longhorn/issues/7579) - @derekbit @roger-ryao
- [BUG] After some v2 volume operations, v2 instance manager on a specific node somehow doesn't work [7608](https://github.com/longhorn/longhorn/issues/7608) - @yangchiu @derekbit
- [BUG] Inconsistent behavior of snapshot list between v1 and v2 volume [7622](https://github.com/longhorn/longhorn/issues/7622) - @yangchiu @derekbit
- [BUG] Fix and improve the offline rebuilding after introducing the SPDK snapshot feature [7596](https://github.com/longhorn/longhorn/issues/7596) - @shuo-wu @chriscchien
- [BUG] Backup volume attachment tickets might not be cleaned up after completion. [6654](https://github.com/longhorn/longhorn/issues/6654) - @james-munson @chriscchien
- [BUG] Correct the naming of v2 volume snapshot created after backup restoration  [7577](https://github.com/longhorn/longhorn/issues/7577) - @derekbit @chriscchien
- [BUG] Randomly failed to create volume with backing image [7543](https://github.com/longhorn/longhorn/issues/7543) - @yangchiu @ChanYiLin
- [BUG] v2 volume becomes faulted and detached after deleting one replica during full restoration [7597](https://github.com/longhorn/longhorn/issues/7597) - @derekbit @chriscchien
- [BUG] Creating volume randomly failed: failed to find a node that is ready and has the default engine image [7413](https://github.com/longhorn/longhorn/issues/7413) - @yangchiu @PhanLe1010
- [BUG] Delete error backup could cause v2 volume stuck in detaching/faulted state [7575](https://github.com/longhorn/longhorn/issues/7575) - @derekbit @roger-ryao
- [BUG] Restore v2 volume stuck in detaching/faulted state if the backup is corrupted [7583](https://github.com/longhorn/longhorn/issues/7583) - @derekbit @chriscchien
- [BUG] After upgrade to master-head, existing volume won't rebuild replica if one deleted, and the volume keeps healthy instead of degraded [7555](https://github.com/longhorn/longhorn/issues/7555) - @FrankYang0529 @yangchiu @derekbit
- [BUG] Delete the backup during restoring a v2 volume from the backup, the restore volume will be detached and faulted [7584](https://github.com/longhorn/longhorn/issues/7584) - @derekbit
- [BUG] Fix the failure of `test_basic.py:: test_volume_scheduling_failure` for v2 volumes [7570](https://github.com/longhorn/longhorn/issues/7570) - @derekbit @chriscchien
- [BUG] Fix using deprecated option of `blockdev` command in go-spdk-helper [7567](https://github.com/longhorn/longhorn/issues/7567) - @derekbit
- [BUG] Delete kubernetes node did not remove `node.longhorn.io`  [7475](https://github.com/longhorn/longhorn/issues/7475) - @ejweber @chriscchien
- [BUG]  Failed to `check_volume_data` after volume engine upgrade/migration [7396](https://github.com/longhorn/longhorn/issues/7396) - @PhanLe1010 @james-munson @roger-ryao
- [BUG] Failed RWX mount due to connection timeout still happening [7301](https://github.com/longhorn/longhorn/issues/7301) - @james-munson
- [BUG] V2 volume is attached to a node first, the V1 volume will fails to attach. [7511](https://github.com/longhorn/longhorn/issues/7511) - @c3y1huang @roger-ryao
- [BUG] v2 volume always displays engine upgrade available on UI [7489](https://github.com/longhorn/longhorn/issues/7489) - @scures
- [BUG] Create volume(v1) faulted [7536](https://github.com/longhorn/longhorn/issues/7536) - @FrankYang0529 @chriscchien
- [BUG] Persistent volume is not ready for workloads [6776](https://github.com/longhorn/longhorn/issues/6776) - @james-munson @roger-ryao
- [BUG] Unable to create snapshot: cannot get engine client because it isn't deployed [7438](https://github.com/longhorn/longhorn/issues/7438) - @yangchiu @PhanLe1010
- [BUG] Deadlock for RWX volume if an error occurs in its share-manager pod [7183](https://github.com/longhorn/longhorn/issues/7183) - @derekbit @chriscchien
- [BUG] Volume conditions are not represented in the UI for v1.4.x and newer [7241](https://github.com/longhorn/longhorn/issues/7241) - @m-ildefons @chriscchien
- [BUG] backingimage download server error [7288](https://github.com/longhorn/longhorn/issues/7288) - @scures @roger-ryao
- [BUG] CSI components CrashLoopBackOff, failed to connect to unix://csi/csi.sock after cluster restart [7116](https://github.com/longhorn/longhorn/issues/7116) - @yangchiu @ejweber
- [BUG] Kubelet cannot finish terminating a pod that uses a PVC with volumeMode: Block when restarting the node [6919](https://github.com/longhorn/longhorn/issues/6919) - @PhanLe1010 @chriscchien
- [BUG] Test case `test_node_default_disk_labeled` failed [7385](https://github.com/longhorn/longhorn/issues/7385) - @derekbit @roger-ryao
- [BUG] Helm2 install error: 'lookup' function not defined in validate-psp-install.yaml [6318](https://github.com/longhorn/longhorn/issues/6318) - @innobead @roger-ryao
- [BUG] Client in go-spdk-helper is stuck after encountering IO timeout [7395](https://github.com/longhorn/longhorn/issues/7395) - @derekbit @chriscchien
- [BUG] DataEngineV2 Unable to attach a PV to a pod in the newer kernel [7190](https://github.com/longhorn/longhorn/issues/7190) - @yangchiu @derekbit
- [BUG] orphaned pod pod_id found, but error not a directory occurred when trying to remove the volumes dir [3207](https://github.com/longhorn/longhorn/issues/3207) - @weizhe0422 @roger-ryao
- [BUG] Download backing image failed with HTTP 502 error if Storage Network configured [7236](https://github.com/longhorn/longhorn/issues/7236) - @ChanYiLin @roger-ryao
- [BUG] During volume live engine upgrade, delete replica with old engine image will make volume degraded forever [7012](https://github.com/longhorn/longhorn/issues/7012) - @PhanLe1010 @chriscchien
- [BUG] A race after a node reboot leads to I/O errors with migratable volumes [6961](https://github.com/longhorn/longhorn/issues/6961) - @yangchiu @ejweber
- [BUG] Metric totalVolumeSize and totalVolumeActualSize incorrect due to v2 volume counts [7380](https://github.com/longhorn/longhorn/issues/7380) - @c3y1huang @chriscchien
- [BUG] Longhorn-manager does not deploy CSI driver when integrated with linkerd service mesh [3809](https://github.com/longhorn/longhorn/issues/3809) - @mantissahz @chriscchien
- [BUG] Test case `test_node_eviction`  failed [7210](https://github.com/longhorn/longhorn/issues/7210) - @ejweber @roger-ryao
- [BUG] Cannot add block-type disk to node resource due to timeout error [7253](https://github.com/longhorn/longhorn/issues/7253) - @yangchiu @shuo-wu
- [BUG] multiple "for-cloning-volume" snapshots created after cloning volume  [5835](https://github.com/longhorn/longhorn/issues/5835) - @PhanLe1010 @chriscchien
- [BUG] Volume has 2 active engines at the same time that blocks the volume controller reconciliation loop  [4827](https://github.com/longhorn/longhorn/issues/4827) - @PhanLe1010 @chriscchien @roger-ryao
- [BUG] Volume UI displays only the last backup when using the recurring job [2997](https://github.com/longhorn/longhorn/issues/2997) - @mantissahz @chriscchien @roger-ryao
- [BUG] Volume gets stuck in an unknown state forever if created in an engine not fully deployed environment [6131](https://github.com/longhorn/longhorn/issues/6131) - @yangchiu @PhanLe1010
- [BUG] Continuously auto-balancing replicas when zone does not have enough space [6671](https://github.com/longhorn/longhorn/issues/6671) - @yangchiu @c3y1huang @roger-ryao
- [BUG] `backing-image-manager-` hostPath selection exception [7062](https://github.com/longhorn/longhorn/issues/7062) - @ChanYiLin @chriscchien
- [BUG] GET error for volume attachment on node reboot [4188](https://github.com/longhorn/longhorn/issues/4188) - @PhanLe1010
- [BUG] Errors found by static checker in volume controller [7009](https://github.com/longhorn/longhorn/issues/7009) - @m-ildefons
- [BUG] Enabling replica-auto-balance tries to replicate to disabled nodes causing lots of errors in the logs and in the UI [6508](https://github.com/longhorn/longhorn/issues/6508) - @c3y1huang @chriscchien
- [BUG] Confusing logging when trying to attach a new volume with no scheduled replicas [7244](https://github.com/longhorn/longhorn/issues/7244) - @ejweber @chriscchien
- [BUG] `allow-collecting-longhorn-usage-metrics` setting is missing from chart settings [7050](https://github.com/longhorn/longhorn/issues/7050) - @ChanYiLin @yardenshoham @roger-ryao
- [BUG] Longhorn storage network is incompatible with Multus version above v4.0.0 [6953](https://github.com/longhorn/longhorn/issues/6953) - @c3y1huang @chriscchien
- [BUG] The archived docs page is broken [7222](https://github.com/longhorn/longhorn/issues/7222) - @innobead
- [IMPROVEMENT] Optimize the resource cache to prevent high memory usage in longhorn-manager  [6954](https://github.com/longhorn/longhorn/issues/6954) - @derekbit @nitendra-suse
- [DOC] longhorn-csi-plugin stuck in CrashLoopBackOff after system crash (SELinux related) [5348](https://github.com/longhorn/longhorn/issues/5348) - @ejweber
- [BUG] Cannot detach the restored volume when there is a node goes down during restoring [2103](https://github.com/longhorn/longhorn/issues/2103) - @ejweber @chriscchien
- [BUG] Failing to mount encrypted volumes [7033](https://github.com/longhorn/longhorn/issues/7033) - @mantissahz @chriscchien
- [BUG] The instance manager with state unknown will be cleaned up in the split-brain case [6479](https://github.com/longhorn/longhorn/issues/6479) - @shuo-wu @chriscchien
- [BUG] Orphan snapshot attachment tickets prevent volume from detaching [6652](https://github.com/longhorn/longhorn/issues/6652) - @ejweber @chriscchien
- [BUG] Test case `test_system_backup_and_restore` failed [7143](https://github.com/longhorn/longhorn/issues/7143) - @ChanYiLin @roger-ryao
- [BUG] missing description in support-bundle metadata.yaml [6997](https://github.com/longhorn/longhorn/issues/6997) - @c3y1huang @roger-ryao
- [BUG] Cannot mount XFS PV  [7140](https://github.com/longhorn/longhorn/issues/7140) - @PhanLe1010 @roger-ryao
- [BUG] Volume encryption doesn't work on Amazon Linux 2 [5944](https://github.com/longhorn/longhorn/issues/5944) - @derekbit @chriscchien
- [BUG] Test case `test_csi_minimal_volume_size` failed [7170](https://github.com/longhorn/longhorn/issues/7170) - @roger-ryao
- [BUG] Deleting a PVC bound to a CSI PV, will delete associated volume and the CSI PV in result. [7172](https://github.com/longhorn/longhorn/issues/7172) -
- [BUG] Relax S3 client retry intervals, for throttled requests [2810](https://github.com/longhorn/longhorn/issues/2810) - @mantissahz @chriscchien
- [BUG] supportbundle/kubelet.log empty in k3s environment [7121](https://github.com/longhorn/longhorn/issues/7121) - @c3y1huang @chriscchien
- [BUG] Failing to mount encrypted volumes v1.5.2 [7045](https://github.com/longhorn/longhorn/issues/7045) - @derekbit @nitendra-suse
- [BUG] Invalid volume name containing less-than sign [7092](https://github.com/longhorn/longhorn/issues/7092) -
- [BUG] Somehow the Rebuilding field inside volume.meta is set to true when one replica only, causing the volume into attaching/detaching loop  [6626](https://github.com/longhorn/longhorn/issues/6626) - @c3y1huang @nitendra-suse
- [BUG] [longhorn-engine] [s390x] intermittent fail pipeline on build step [6975](https://github.com/longhorn/longhorn/issues/6975) - @Anarkis
- [BUG] Longhorn Read-Only setting can be modified [5989](https://github.com/longhorn/longhorn/issues/5989) - @mantissahz @roger-ryao
- [BUG] UI: All components handle window resizing events incorrectly [7036](https://github.com/longhorn/longhorn/issues/7036) - @votdev
- [BUG] UI: The action menu handler should stop event propagation [7032](https://github.com/longhorn/longhorn/issues/7032) - @votdev
- [BUG] longhorn manager isn't annotated with iam.amazonaws.com/role [6947](https://github.com/longhorn/longhorn/issues/6947) - @mantissahz @chriscchien
- [BUG]  invalid memory address or nil pointer dereference in BackupVolumeController [6998](https://github.com/longhorn/longhorn/issues/6998) - @mantissahz @roger-ryao
- [BUG] Longhorn manager pods in 1.5.1 consuming 20GB+ RAM and 3-4 vCPUs [6866](https://github.com/longhorn/longhorn/issues/6866) - @derekbit @shuo-wu
- [BUG] MountVolume.MountDevice failed for volume Output: mount.nfs: Protocol not supported [6887](https://github.com/longhorn/longhorn/issues/6887) - @derekbit
- [BUG] High CPU usage on one node. [6578](https://github.com/longhorn/longhorn/issues/6578) - @derekbit @chriscchien
- [BUG] Set a invalid backup target when backup in progress will cause backup never finish [6491](https://github.com/longhorn/longhorn/issues/6491) - @ChanYiLin @chriscchien
- [BUG] duplicate MIME type "text/html" in `/var/config/nginx/nginx.conf` [7002](https://github.com/longhorn/longhorn/issues/7002) - @votdev
- [BUG] After crashed engine process, volume stuck in `Unknown` state [6699](https://github.com/longhorn/longhorn/issues/6699) - @ChanYiLin @nitendra-suse
- [BUG] Longhorn Instance Manager Memory leak  [6481](https://github.com/longhorn/longhorn/issues/6481) - @james-munson @chriscchien
- [BUG] Two active engine when volume migrating [6642](https://github.com/longhorn/longhorn/issues/6642) - @PhanLe1010 @chriscchien
- [BUG] Button "Take Snapshot" and "Create Backup" grayed out. [6841](https://github.com/longhorn/longhorn/issues/6841) - @votdev
- [BUG] Environment Check Script Fails To Perform All Checks [5653](https://github.com/longhorn/longhorn/issues/5653) - @PhanLe1010 @roger-ryao
- [BUG] Volumes failing to mount because of engine upgradedReplicaAddressMap reference [6762](https://github.com/longhorn/longhorn/issues/6762) - @PhanLe1010 @chriscchien
- [BUG] Unable to add a block-type disk with a new name [6849](https://github.com/longhorn/longhorn/issues/6849) - @derekbit @chriscchien
- [BUG] IO error occurs when detaching RWX volume [6829](https://github.com/longhorn/longhorn/issues/6829) - @derekbit @chriscchien
- [BUG] DR volume failed when synchronizing the incremental backup [6750](https://github.com/longhorn/longhorn/issues/6750) - @mantissahz @chriscchien
- [BUG] Salvage failing in attaching and detaching loop, another pod is attached with health unknown [6662](https://github.com/longhorn/longhorn/issues/6662) - @james-munson
- [BUG] 1.5.0: AttachVolume.Attach failed for volume, the volume is currently attached to different node [6287](https://github.com/longhorn/longhorn/issues/6287) - @yangchiu @derekbit
- [BUG] Helm installation with privateRegistry.registryUrl set doesn't work [3057](https://github.com/longhorn/longhorn/issues/3057) - @PhanLe1010 @chriscchien
- [BUG] cifs backup mount paths with dollar sign are not allowed [6660](https://github.com/longhorn/longhorn/issues/6660) - @derekbit @roger-ryao
- [BUG] Failed Statefulset Pod Creation with RWX Workload on Longhorn v1.3.3 and SLES 15 SP5 [6494](https://github.com/longhorn/longhorn/issues/6494) - @ejweber @roger-ryao
- [BUG] Failure to update backup status leads to infinite reconciliation [6358](https://github.com/longhorn/longhorn/issues/6358) - @ejweber @chriscchien
- [BUG] longhorn installation randomly failed on sles 15-sp5 due to longhorn manager CrashLoopBackOff [6504](https://github.com/longhorn/longhorn/issues/6504) - @ejweber @chriscchien
- [BUG] Can't delete volumesnapshot if backup target not set [4979](https://github.com/longhorn/longhorn/issues/4979) - @ejweber @chriscchien
- [BUG] Share manager pod will stay in IO error when the volume becomes read only [5961](https://github.com/longhorn/longhorn/issues/5961) - @ChanYiLin @roger-ryao
- [BUG] SettingNameSnapshotDataIntegrityCronJob should be sent as boolean value [6410](https://github.com/longhorn/longhorn/issues/6410) - @c3y1huang @roger-ryao
- [BUG] Permission denied when starting longhorn-ui container [6430](https://github.com/longhorn/longhorn/issues/6430) - @mantissahz @chriscchien
- [BUG] Longhorn manager crashed during backing image 100gb volume export [5209](https://github.com/longhorn/longhorn/issues/5209) - @ChanYiLin @chriscchien
- [BUG] Removed IM CPU request settings still exists and new IM CPU request missed from chart settings [6465](https://github.com/longhorn/longhorn/issues/6465) - @c3y1huang @chriscchien
- [BUG] Error during backup process will be removed quickly without user knowing [1249](https://github.com/longhorn/longhorn/issues/1249) - @mantissahz @chriscchien
- [BUG] PV using v2 engine cannot attach [6441](https://github.com/longhorn/longhorn/issues/6441) - @derekbit @chriscchien @nitendra-suse
- [BUG] Backup Job returns "Completed" despite running into errors [4255](https://github.com/longhorn/longhorn/issues/4255) - @mantissahz @chriscchien
- [BUG] 1.5.0 Upgrade: Longhorn conversion webhook server fails [6259](https://github.com/longhorn/longhorn/issues/6259) - @derekbit @roger-ryao
- [BUG] Webhook is never called for BackingImageManager [6328](https://github.com/longhorn/longhorn/issues/6328) - @ejweber @chriscchien
- [BUG] Error message not getting cleaned up on switching the backupstore [2944](https://github.com/longhorn/longhorn/issues/2944) - @mantissahz
- [BUG] Unable to list backup from a local backupstore in RKE2 CIS-1.23 environment [6342](https://github.com/longhorn/longhorn/issues/6342) - @mantissahz
- [BUG] test case test_inc_restoration_with_multiple_rebuild_and_expansion randomly failed [5496](https://github.com/longhorn/longhorn/issues/5496) - @mantissahz
- [BUG] disk monitor cannot recognize disks if disk paths are somehow changed after reboot [6125](https://github.com/longhorn/longhorn/issues/6125) - @yangchiu @derekbit
- [BUG] Can not delete type=`bi` VolumeSnapshot if related backing image not exist [6266](https://github.com/longhorn/longhorn/issues/6266) - @ChanYiLin @chriscchien
- [BUG] Race leaves snapshot CRs that cannot be deleted [6298](https://github.com/longhorn/longhorn/issues/6298) - @yangchiu @PhanLe1010 @ejweber
- [BUG] test case test_setting_priority_class failed in master and v1.5.x [6319](https://github.com/longhorn/longhorn/issues/6319) - @derekbit @chriscchien
- [BUG] Upgrade to 1.5.0 failed: validator.longhorn.io denied the request if having orphan resources [6246](https://github.com/longhorn/longhorn/issues/6246) - @derekbit @roger-ryao
- [BUG] Longhorn Manager Pods CrashLoop after upgrade from 1.4.0 to 1.5.0 while backing up volumes [6264](https://github.com/longhorn/longhorn/issues/6264) - @ChanYiLin @roger-ryao
- [BUG] Unable to receive support bundle from UI when it's large (400MB+) [6256](https://github.com/longhorn/longhorn/issues/6256) - @c3y1huang @chriscchien
- [BUG] Live upgrade stuck if the same volume name backup exists in the backup store [3403](https://github.com/longhorn/longhorn/issues/3403) - @ChanYiLin @chriscchien
- [BUG] Instance manager may not update instance status for a minute after starting [5809](https://github.com/longhorn/longhorn/issues/5809) - @ejweber @chriscchien

### Performance
- [FEATURE] Increase read bandwidth of v2 volume from all downstream replicas [5759](https://github.com/longhorn/longhorn/issues/5759) - @derekbit @chriscchien
- [TASK] Add 1.5 performance benchmark to performance benchmark WIKI page [6203](https://github.com/longhorn/longhorn/issues/6203) - @derekbit

### Miscellaneous
- [TASK] Bump the versions of dependent libs or components [7001](https://github.com/longhorn/longhorn/issues/7001) - @c3y1huang @chriscchien
- [DOC] Make `Troubleshooting` section as an individual chapter   [7706](https://github.com/longhorn/longhorn/issues/7706) - @derekbit
- [TASK] Update the descriptions of setting variables in chart after doc review [7667](https://github.com/longhorn/longhorn/issues/7667) - @ChanYiLin
- [REFACTOR] Remove unnecessary Kubernetes version check in chart manfests [7601](https://github.com/longhorn/longhorn/issues/7601) - @c3y1huang @roger-ryao
- [TASK] Bump up the minimum supported Kubernetes version [7224](https://github.com/longhorn/longhorn/issues/7224) - @c3y1huang @roger-ryao
- [TASK] Update CLIAPIVersion in longhorn-manager [7588](https://github.com/longhorn/longhorn/issues/7588) - @FrankYang0529 @roger-ryao
- [TASK] Security vulnerabilities in docker images [7523](https://github.com/longhorn/longhorn/issues/7523) - @c3y1huang @roger-ryao
- [TASK][UI] v2 volume does not support engine image upgrade [7445](https://github.com/longhorn/longhorn/issues/7445) - @chriscchien @scures @roger-ryao
- [DOC] Add missing descriptions for Helm  [7485](https://github.com/longhorn/longhorn/issues/7485) - @mantissahz
- [TASK] Update protoc to v24.3 [6666](https://github.com/longhorn/longhorn/issues/6666) - @FrankYang0529
- [FEATURE] Enable resource profiling for IM [6377](https://github.com/longhorn/longhorn/issues/6377) - @derekbit @roger-ryao
- [TASK] Synchronize version of CSI components in longhorn/longhorn and longhorn/longhorn-manager [7377](https://github.com/longhorn/longhorn/issues/7377) - @c3y1huang @roger-ryao
- [TASK] Upgrade csi-snapshotter to mitigate rapid retry bug [6506](https://github.com/longhorn/longhorn/issues/6506) - @ejweber
- [TASK] Remove engine image dependency of v2 volumes [7157](https://github.com/longhorn/longhorn/issues/7157) - @derekbit
- [DOC] Fix erroneous value for default StorageMinimalAvailablePercentage setting. [7342](https://github.com/longhorn/longhorn/issues/7342) - @james-munson
- [DOC] FS Trim for RWX is supported, but docs are out of date. [6733](https://github.com/longhorn/longhorn/issues/6733) - @james-munson
- [REFACTOR] Abstract the disk/lvol file operations in backupstore [6576](https://github.com/longhorn/longhorn/issues/6576) - @derekbit @chriscchien
- [TASK] Implement xattr get and set operations on SPDK logical volumes (lvol) [6604](https://github.com/longhorn/longhorn/issues/6604) - @derekbit
- [DOC] Stress using object store as best practice for backups. [6773](https://github.com/longhorn/longhorn/issues/6773) - @james-munson
- [DOC] Run fsck.ext4 on newer Longhorn volume from older Linux distro [6859](https://github.com/longhorn/longhorn/issues/6859) - @ejweber @roger-ryao
- [TASK] Move common functions for backup to backupstore lib [6514](https://github.com/longhorn/longhorn/issues/6514) - @derekbit
- [TASK] Investigate SELinux enabled with Longhorn [6074](https://github.com/longhorn/longhorn/issues/6074) - @yangchiu @ejweber
- [IMPROVEMENT] List of Longhorn Helm Chart Flags [5455](https://github.com/longhorn/longhorn/issues/5455) - @ChanYiLin
- [REFACTOR] UI: Disable `Delete` menu for default engine image [7029](https://github.com/longhorn/longhorn/issues/7029) - @votdev
- [TASK][UI] Replace `spec.engineImage` field in volume, engine and replica CRDs with `spec.image` [6685](https://github.com/longhorn/longhorn/issues/6685) - @votdev
- [EPIC] Side effects of increasing resync period in informer's event handlers [3629](https://github.com/longhorn/longhorn/issues/3629) - @PhanLe1010
- [TASK] The development branch should reference to the head images in longhorn-image.txt [6737](https://github.com/longhorn/longhorn/issues/6737) - @c3y1huang @chriscchien
- [TASK] Create a CIFS backup store example in longhorn repo [6530](https://github.com/longhorn/longhorn/issues/6530) - @chriscchien
- [DOC] Explanation of storage class parameters [4776](https://github.com/longhorn/longhorn/issues/4776) - @james-munson @roger-ryao
- [DOC] Create a KB for high space consumption issue guideline [6592](https://github.com/longhorn/longhorn/issues/6592) - @shuo-wu
- [DOC] Create a KB for incorrect replica expansion [6391](https://github.com/longhorn/longhorn/issues/6391) - @ejweber
- [DOC] `deploy/longhorn.yaml` out of date - causes all longhorn-manager instances to crash-loop [6428](https://github.com/longhorn/longhorn/issues/6428) - @c3y1huang
- [REFACTORING] Move adding finalizer of resources to mutation webhooks as volume/engine/replica  [4872](https://github.com/longhorn/longhorn/issues/4872) - @ejweber @chriscchien
- [TASK]  Update or remove out-of-date cleanup script [6316](https://github.com/longhorn/longhorn/issues/6316) - @james-munson
- [DOC] v1.5.0 additional outgoing firewall ports need to be opened 9501 9502 9503 [6317](https://github.com/longhorn/longhorn/issues/6317) - @ChanYiLin @chriscchien
- [TASK] Check and update the networking doc & example YAMLs [5651](https://github.com/longhorn/longhorn/issues/5651) - @yangchiu @shuo-wu

## Contributors
- @Anarkis
- @ArthurVardevanyan
- @ChanYiLin
- @DamiaSan
- @FrankYang0529
- @PhanLe1010
- @Vicente-Cheng
- @antoninferrand
- @c3y1huang
- @chriscchien
- @derekbit
- @ejweber
- @innobead
- @james-munson
- @jillian-maroket 
- @m-ildefons
- @mantissahz
- @nitendra-suse
- @roger-ryao
- @scures
- @sfackler
- @shuo-wu
- @smallteeths
- @votdev
- @weizhe0422
- @yangchiu
- @yardenshoham
