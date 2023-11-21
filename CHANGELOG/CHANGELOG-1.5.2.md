## Release Note

### **v1.5.2 released!** 🎆

This release introduces bug fixes and improvements, with the main focus on stability. Please try it and provide feedback. Thanks for all the contributions!

> For the definition of stable or latest release, please check [here](https://github.com/longhorn/longhorn#releases).

## Installation

> **Please ensure your Kubernetes cluster is at least v1.21 before installing v1.5.2.**

Longhorn supports three installation ways including Rancher App Marketplace, Kubectl, and Helm. Follow the installation instructions [here](https://longhorn.io/docs/1.5.2/deploy/install/).

## Upgrade

> **Please read the [important notes](https://longhorn.io/docs/1.5.2/deploy/important-notes/) first and ensure your Kubernetes cluster is at least v1.21 before upgrading to Longhorn v1.5.2 from v1.4.x/v1.5.x, which are only supported source versions.**

Follow the upgrade instructions here. [Here](https://longhorn.io/docs/1.5.2/deploy/upgrade/).

## Deprecation & Incompatibilities

N/A

## Known Issues after Release

Please follow up on [here](https://github.com/longhorn/longhorn/wiki/Outstanding-Known-Issues-of-Releases) about any outstanding issues found after this release.

## Resolved Issues

### Enhancement
- [FEATURE] Add disk status prometheus metrics [6858](https://github.com/longhorn/longhorn/issues/6858) - @c3y1huang @chriscchien

### Improvement
- [IMPROVEMENT] High memory consumption of longhorn-manager pods since Longhorn v1.5 [6936](https://github.com/longhorn/longhorn/issues/6936) - @derekbit
- [IMPROVEMENT] Old kernel such as 3.10.0 set provisioning_mode to wrong value (writesame_16, disabled, full, ...) but not the correct value (unmap) so the trim feature doesn't work [6854](https://github.com/longhorn/longhorn/issues/6854) - @PhanLe1010 @chriscchien
- [IMPROVEMENT] Improve log level for resource update failure able to reconcile again [6843](https://github.com/longhorn/longhorn/issues/6843) - @PhanLe1010 @nitendra-suse
- [IMPROVEMENT] Don't log about inability to change settings that didn't change. [6812](https://github.com/longhorn/longhorn/issues/6812) - @james-munson @roger-ryao
- [IMPROVEMENT] Use nvme-cli in instance-manager pod instead [6798](https://github.com/longhorn/longhorn/issues/6798) - @derekbit
- [IMPROVEMENT] Prevent unexpected engine creation [6682](https://github.com/longhorn/longhorn/issues/6682) - @PhanLe1010 @ejweber @roger-ryao
- [IMPROVEMENT] Support both NFS `hard` and `soft` with custom `timeo` and `retrans` options for RWX volumes [6655](https://github.com/longhorn/longhorn/issues/6655) - @derekbit @roger-ryao
- [IMPROVEMENT] Prevent Volume Provision if Related Backing Image Stuck in Ready-For-Trasfer State [6615](https://github.com/longhorn/longhorn/issues/6615) - @ChanYiLin @roger-ryao
- [IMPROVEMENT] Support custom options for network filesystems for backup [6608](https://github.com/longhorn/longhorn/issues/6608) - @james-munson
- [IMPROVEMENT] Remove dummy services of each CSI sidecar if not required [6581](https://github.com/longhorn/longhorn/issues/6581) - @ejweber @roger-ryao
- [IMPROVEMENT] Include /var/log/messages during the support-bundle syslog collection [6544](https://github.com/longhorn/longhorn/issues/6544) - @c3y1huang @roger-ryao
- [IMPROVEMENT] Provide more information for volume scheduling failure [6461](https://github.com/longhorn/longhorn/issues/6461) - @smallteeths @chriscchien
- [IMPROVEMENT] Remove or Change Helm pre-upgrade hook to support ArgoCD [6415](https://github.com/longhorn/longhorn/issues/6415) - @mantissahz
- [IMPROVEMENT] Improve upgrade path and make it more solid [6294](https://github.com/longhorn/longhorn/issues/6294) - @PhanLe1010 @roger-ryao
- [IMPROVEMENT] UI Volume detail page still shows `Block Device` when `spec.disableFrontend` is true [6167](https://github.com/longhorn/longhorn/issues/6167) - @smallteeths @chriscchien
- [IMPROVEMENT]  Fix scheduling flooding logs [6019](https://github.com/longhorn/longhorn/issues/6019) - @ChanYiLin @roger-ryao
- [IMPROVEMENT] Add reserve storage percentage of nodes setting in helm chart [5958](https://github.com/longhorn/longhorn/issues/5958) - @mantissahz @roger-ryao
- [IMPROVEMENT] Longhorn-engine processes should refuse to serve requests not intended for them [5845](https://github.com/longhorn/longhorn/issues/5845) - @ejweber @chriscchien
- [IMPROVEMENT] Unify logs with extra static info like module/method/function/line [5509](https://github.com/longhorn/longhorn/issues/5509) - @ChanYiLin @roger-ryao
- [IMPROVEMENT] Add pvc name to longhorn_volume metrics [5297](https://github.com/longhorn/longhorn/issues/5297) - @c3y1huang @nitendra-suse
- [IMPROVEMENT] Avoid the accident deletion of longhorn settings [4984](https://github.com/longhorn/longhorn/issues/4984) - @ejweber @roger-ryao
- [IMPROVEMENT] Remove Longhorn engine path mismatch log [3786](https://github.com/longhorn/longhorn/issues/3786) - @c3y1huang @roger-ryao

### Performance
- [IMPROVEMENT] Optimize the resource cache to prevent high memory usage in longhorn-manager  [6954](https://github.com/longhorn/longhorn/issues/6954) - @derekbit @nitendra-suse
- [BUG] Longhorn manager pods in 1.5.1 consuming 20GB+ RAM and 3-4 vCPUs [6866](https://github.com/longhorn/longhorn/issues/6866) - @derekbit @shuo-wu
- [BUG] Longhorn Instance Manager Memory leak  [6481](https://github.com/longhorn/longhorn/issues/6481) - @james-munson @chriscchien

### Stability
- [BUG] DR volume failed when synchronizing the incremental backup [6750](https://github.com/longhorn/longhorn/issues/6750) - @mantissahz @chriscchien
- [BUG] After crashed engine process, volume stuck in `Unknown` state [6699](https://github.com/longhorn/longhorn/issues/6699) - @ChanYiLin @nitendra-suse
- [BUG] Two active engine when volume migrating [6642](https://github.com/longhorn/longhorn/issues/6642) - @PhanLe1010 @chriscchien
- [BUG] Somehow the Rebuilding field inside volume.meta is set to true when one replica only, causing the volume into attaching/detaching loop  [6626](https://github.com/longhorn/longhorn/issues/6626) - @c3y1huang @nitendra-suse

### Resilience
- [BUG] RWX workload gets stuck in ContainerCreating after cluster restart [6924](https://github.com/longhorn/longhorn/issues/6924) - @yangchiu @derekbit
- [BUG] Volumes failing to mount because of engine upgradedReplicaAddressMap reference [6762](https://github.com/longhorn/longhorn/issues/6762) - @PhanLe1010 @chriscchien
- [BUG] Set a invalid backup target when backup in progress will cause backup never finish [6491](https://github.com/longhorn/longhorn/issues/6491) - @ChanYiLin @chriscchien
- [BUG] Share manager pod will stay in IO error when the volume becomes read only [5961](https://github.com/longhorn/longhorn/issues/5961) - @ChanYiLin @roger-ryao

### Bug
- [BUG] duplicate MIME type "text/html" in `/var/config/nginx/nginx.conf` [7002](https://github.com/longhorn/longhorn/issues/7002) - @votdev
- [BUG]  invalid memory address or nil pointer dereference in BackupVolumeController [6998](https://github.com/longhorn/longhorn/issues/6998) - @mantissahz @roger-ryao
- [BUG] Unable to upgrade longhorn from v1.4.x to v1.5.x: longhorn-manager CrashLoopBackOff [6987](https://github.com/longhorn/longhorn/issues/6987) - @mantissahz @chriscchien
- [BUG] Longhorn storage network is incompatible with Multus version above v4.0.0 [6953](https://github.com/longhorn/longhorn/issues/6953) - @c3y1huang
- [BUG] longhorn manager isn't annotated with iam.amazonaws.com/role [6947](https://github.com/longhorn/longhorn/issues/6947) - @mantissahz
- [BUG] Unable to add a block-type disk with a new name [6849](https://github.com/longhorn/longhorn/issues/6849) - @derekbit @chriscchien
- [BUG] IO error occurs when detaching RWX volume [6829](https://github.com/longhorn/longhorn/issues/6829) - @derekbit @chriscchien
- [BUG] cifs backup mount paths with dollar sign are not allowed [6660](https://github.com/longhorn/longhorn/issues/6660) - @derekbit @roger-ryao
- [BUG] Orphan snapshot attachment tickets prevent volume from detaching [6652](https://github.com/longhorn/longhorn/issues/6652) - @ejweber
- [BUG] High CPU usage on one node. [6578](https://github.com/longhorn/longhorn/issues/6578) - @derekbit @chriscchien
- [BUG] The instance manager with state unknown will be cleaned up in the split-brain case [6479](https://github.com/longhorn/longhorn/issues/6479) - @shuo-wu
- [BUG] Removed IM CPU request settings still exists and new IM CPU request missed from chart settings [6465](https://github.com/longhorn/longhorn/issues/6465) - @c3y1huang @chriscchien
- [BUG] PV using v2 engine cannot attach [6441](https://github.com/longhorn/longhorn/issues/6441) - @derekbit @chriscchien @nitendra-suse
- [BUG] SettingNameSnapshotDataIntegrityCronJob should be sent as boolean value [6410](https://github.com/longhorn/longhorn/issues/6410) - @c3y1huang @roger-ryao
- [BUG] Fix errors in questions.yaml [6392](https://github.com/longhorn/longhorn/issues/6392) - @james-munson @chriscchien
- [BUG] Webhook is never called for BackingImageManager [6328](https://github.com/longhorn/longhorn/issues/6328) - @ejweber @chriscchien
- [BUG] Longhorn Read-Only setting can be modified [5989](https://github.com/longhorn/longhorn/issues/5989) - @mantissahz
- [BUG] Environment Check Script Fails To Perform All Checks [5653](https://github.com/longhorn/longhorn/issues/5653) - @PhanLe1010 @roger-ryao
- [BUG] Can't delete volumesnapshot if backup target not set [4979](https://github.com/longhorn/longhorn/issues/4979) - @ejweber @chriscchien
- [BUG] Backup Job returns "Completed" despite running into errors [4255](https://github.com/longhorn/longhorn/issues/4255) - @mantissahz @chriscchien
- [BUG] Error during backup process will be removed quickly without user knowing [1249](https://github.com/longhorn/longhorn/issues/1249) - @mantissahz @chriscchien

### Misc
- [TASK] Revert "Disable Automatically Delete Workload Pod when The Volume Is Detached Unexpectedly for RWX volumes" [6838](https://github.com/longhorn/longhorn/issues/6838) - @derekbit @roger-ryao

## Contributors
- @ChanYiLin 
- @PhanLe1010 
- @c3y1huang 
- @chriscchien 
- @derekbit 
- @ejweber 
- @innobead 
- @james-munson 
- @mantissahz 
- @nitendra-suse 
- @roger-ryao 
- @shuo-wu 
- @smallteeths 
- @votdev 
- @yangchiu 
