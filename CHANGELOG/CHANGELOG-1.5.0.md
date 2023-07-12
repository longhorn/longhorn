## Release Note
### **v1.5.0 released!** 🎆

Longhorn v1.5.0 is the latest version of Longhorn 1.5.
It introduces many enhancements, improvements, and bug fixes as described below including performance, stability, maintenance, resilience, and so on. Please try it and feedback. Thanks for all the contributions!

> For the definition of stable or latest release, please check [here](https://github.com/longhorn/longhorn#releases).

  - [v2 Data Engine based on SPDK - Preview](https://github.com/longhorn/longhorn/issues/5751)
    > **Please note that this is a preview feature, so should not be used in any production environment. A preview feature is disabled by default and would be changed in the following versions until it becomes general availability.**
    
    In addition to the existing iSCSI stack (v1) data engine, we are introducing the v2 data engine based on SPDK (Storage Performance Development Kit). This release includes the introduction of volume lifecycle management, degraded volume handling, offline replica rebuilding, block device management, and orphaned replica management. For the performance benchmark and comparison with v1, check the report [here](https://longhorn.io/docs/1.5.0/spdk/performance-benchmark/).

  - [Longhorn Volume Attachment](https://github.com/longhorn/longhorn/issues/3715)
    Introducing the new Longhorn VolumeAttachment CR, which ensures exclusive attachment and supports automatic volume attachment and detachment for various headless operations such as volume cloning, backing image export, and recurring jobs.

  - [Cluster Autoscaler - GA](https://github.com/longhorn/longhorn/issues/5238)
    Cluster Autoscaler was initially introduced as an experimental feature in v1.3. After undergoing automatic validation on different public cloud Kubernetes distributions and receiving user feedback, it has now reached general availability.

  - [Instance Manager Engine & Replica Consolidation](https://github.com/longhorn/longhorn/issues/5208)
    Previously, there were two separate instance manager pods responsible for volume engine and replica process management. However, this setup required high resource usage, especially during live upgrades. In this release, we have merged these pods into a single instance manager, reducing the initial resource requirements.

  - [Volume Backup Compression Methods](https://github.com/longhorn/longhorn/issues/5189)
    Longhorn supports different compression methods for volume backups, including lz4, gzip, or no compression. This allows users to choose the most suitable method based on their data type and usage requirements.

  - [Automatic Volume Trim Recurring Job](https://github.com/longhorn/longhorn/issues/5186)
    While volume filesystem trim was introduced in v1.4, users had to perform the operation manually. From this release, users can create a recurring job that automatically runs the trim process, improving space efficiency without requiring human intervention.

  - [RWX Volume Trim](https://github.com/longhorn/longhorn/issues/5143)
    Longhorn supports filesystem trim for RWX (Read-Write-Many) volumes, expanding the trim functionality beyond RWO (Read-Write-Once) volumes only.

  - [Upgrade Path Enforcement & Downgrade Prevention](https://github.com/longhorn/longhorn/issues/5131)
    To ensure compatibility after an upgrade, we have implemented upgrade path enforcement. This prevents unintended downgrades and ensures the system and data remain intact.

  - [Backing Image Management via CSI VolumeSnapshot](https://github.com/longhorn/longhorn/issues/5005)
    Users can now utilize the unified CSI VolumeSnapshot interface to manage Backing Images similar to volume snapshots and backups.

  - [Snapshot Cleanup & Delete Recurring Job](https://github.com/longhorn/longhorn/issues/3836)
    Introducing two new recurring job types specifically designed for snapshot cleanup and deletion. These jobs allow users to remove unnecessary snapshots for better space efficiency.

  - [CIFS Backup Store](https://github.com/longhorn/longhorn/issues/3599) & [Azure Backup Store](https://github.com/longhorn/longhorn/issues/1309)
    To enhance users' backup strategies and align with data governance policies, Longhorn now supports additional backup storage protocols, including CIFS and Azure.

  - [Kubernetes Upgrade Node Drain Policy](https://github.com/longhorn/longhorn/issues/3304)  
    The new Node Drain Policy provides flexible strategies to protect volume data during Kubernetes upgrades or node maintenance operations. This ensures the integrity and availability of your volumes.

## Installation

> **Please ensure your Kubernetes cluster is at least v1.21 before installing Longhorn v1.5.0.**

Longhorn supports 3 installation ways including Rancher App Marketplace, Kubectl, and Helm. Follow the installation instructions [here](https://longhorn.io/docs/1.5.0/deploy/install/).

## Upgrade

> **Please ensure your Kubernetes cluster is at least v1.21 before upgrading to Longhorn v1.5.0 from v1.4.x. Only support upgrading from 1.4.x.**

Follow the upgrade instructions [here](https://longhorn.io/docs/1.5.0/deploy/upgrade/).

## Deprecation & Incompatibilities

Please check the [important notes](https://longhorn.io/docs/1.5.0/deploy/important-notes/) to know more about deprecated, removed, incompatible features and important changes. If you upgrade indirectly from an older version like v1.3.x, please also check the corresponding important note for each upgrade version path.

## Known Issues after Release

Please follow up on [here](https://github.com/longhorn/longhorn/wiki/Outstanding-Known-Issues-of-Releases) about any outstanding issues found after this release. 

## Highlights
  
  - [DOC] Provide the user guide for Kubernetes upgrade ([494](https://github.com/longhorn/longhorn/issues/494)) - @PhanLe1010
  - [FEATURE] Backups to Azure Blob Storage ([1309](https://github.com/longhorn/longhorn/issues/1309)) - @mantissahz @chriscchien
  - [IMPROVEMENT] Use PDB to protect Longhorn components from unexpected drains ([3304](https://github.com/longhorn/longhorn/issues/3304)) - @yangchiu @PhanLe1010
  - [FEATURE] CIFS Backup Store Support ([3599](https://github.com/longhorn/longhorn/issues/3599)) - @derekbit @chriscchien
  - [IMPROVEMENT] Consolidate volume attach/detach implementation ([3715](https://github.com/longhorn/longhorn/issues/3715)) - @yangchiu @PhanLe1010
  - [IMPROVEMENT] Periodically clean up volume snapshots ([3836](https://github.com/longhorn/longhorn/issues/3836)) - @c3y1huang @chriscchien
  - [IMPROVEMENT] Introduce timeout mechanism for the sparse file syncing service ([4305](https://github.com/longhorn/longhorn/issues/4305)) - @yangchiu @ChanYiLin
  - [IMPROVEMENT] Recurring jobs create new snapshots while being not able to clean up old ones ([4898](https://github.com/longhorn/longhorn/issues/4898)) - @mantissahz @chriscchien
  - [FEATURE] BackingImage Management via VolumeSnapshot ([5005](https://github.com/longhorn/longhorn/issues/5005)) - @ChanYiLin @chriscchien
  - [FEATURE] Upgrade path enforcement & downgrade prevention ([5131](https://github.com/longhorn/longhorn/issues/5131)) - @yangchiu @mantissahz
  - [FEATURE] Support RWX volume trim ([5143](https://github.com/longhorn/longhorn/issues/5143)) - @derekbit @chriscchien
  - [FEATURE] Auto Trim via recurring job ([5186](https://github.com/longhorn/longhorn/issues/5186)) - @c3y1huang @chriscchien
  - [FEATURE] Introduce faster compression and multiple threads for volume backup & restore  ([5189](https://github.com/longhorn/longhorn/issues/5189)) - @derekbit @roger-ryao
  - [FEATURE] Consolidate Instance Manager Engine & Replica for resource consumption reduction ([5208](https://github.com/longhorn/longhorn/issues/5208)) - @yangchiu @c3y1huang
  - [FEATURE] Cluster Autoscaler Support GA ([5238](https://github.com/longhorn/longhorn/issues/5238)) - @yangchiu @c3y1huang
  - [FEATURE] Update K8s version support and component/pkg/build dependencies for Longhorn 1.5 ([5595](https://github.com/longhorn/longhorn/issues/5595)) - @yangchiu @ejweber
  - [FEATURE] Support SPDK Data Engine - Preview ([5751](https://github.com/longhorn/longhorn/issues/5751)) - @derekbit @shuo-wu @DamiaSan
  
## Enhancements
  
  - [FEATURE] Allow users to directly activate a restoring/DR volume as long as there is one ready replica. ([1512](https://github.com/longhorn/longhorn/issues/1512)) - @mantissahz @weizhe0422
  - [REFACTOR] volume controller refactoring/split up, to simplify the control flow ([2527](https://github.com/longhorn/longhorn/issues/2527)) - @PhanLe1010 @chriscchien
  - [FEATURE] Import and export SPDK longhorn volumes to longhorn sparse file directory ([4100](https://github.com/longhorn/longhorn/issues/4100)) - @DamiaSan
  - [FEATURE] Add a global `storage reserved` setting for newly created longhorn nodes' disks ([4773](https://github.com/longhorn/longhorn/issues/4773)) - @mantissahz @chriscchien
  - [FEATURE] Support backup volumes during system backup ([5011](https://github.com/longhorn/longhorn/issues/5011)) - @c3y1huang @chriscchien
  - [FEATURE] Support SPDK lvol shallow copy for newly replica creation ([5217](https://github.com/longhorn/longhorn/issues/5217)) - @DamiaSan
  - [FEATURE] Introduce longhorn-spdk-engine for SPDK volume management ([5282](https://github.com/longhorn/longhorn/issues/5282)) - @shuo-wu
  - [FEATURE] Support replica-zone-soft-anti-affinity setting per volume ([5358](https://github.com/longhorn/longhorn/issues/5358)) - @ChanYiLin @smallteeths @chriscchien
  - [FEATURE] Install Opt-In NetworkPolicies  ([5403](https://github.com/longhorn/longhorn/issues/5403)) - @yangchiu @ChanYiLin
  - [FEATURE] Create Longhorn SPDK Engine component with basic fundamental functions ([5406](https://github.com/longhorn/longhorn/issues/5406)) - @shuo-wu
  - [FEATURE] Add status APIs for shallow copy and IO pause/resume ([5647](https://github.com/longhorn/longhorn/issues/5647)) - @DamiaSan
  - [FEATURE] Introduce a new disk type, disk management and replica scheduler for SPDK volumes ([5683](https://github.com/longhorn/longhorn/issues/5683)) - @derekbit @roger-ryao
  - [FEATURE] Support replica scheduling for SPDK volume  ([5711](https://github.com/longhorn/longhorn/issues/5711)) - @derekbit
  - [FEATURE] Create SPDK gRPC service for instance manager ([5712](https://github.com/longhorn/longhorn/issues/5712)) - @shuo-wu
  - [FEATURE] Environment check script for Longhorn with SPDK ([5738](https://github.com/longhorn/longhorn/issues/5738)) - @derekbit @chriscchien
  - [FEATURE] Deployment manifests for helping install SPDK dependencies, utilities and libraries ([5739](https://github.com/longhorn/longhorn/issues/5739)) - @yangchiu @derekbit
  - [FEATURE] Implement Disk gRPC Service in Instance Manager for collecting SPDK disk statistics from SPDK gRPC service  ([5744](https://github.com/longhorn/longhorn/issues/5744)) - @derekbit @chriscchien
  - [FEATURE] Support for SPDK RAID1 by setting the minimum number of base_bdevs to 1 ([5758](https://github.com/longhorn/longhorn/issues/5758)) - @yangchiu @DamiaSan
  - [FEATURE] Add a global setting for enabling and disabling SPDK feature ([5778](https://github.com/longhorn/longhorn/issues/5778)) - @yangchiu @derekbit
  - [FEATURE] Identify and manage orphaned lvols and raid bdevs if the associated `Volume` resources are not existing ([5827](https://github.com/longhorn/longhorn/issues/5827)) - @yangchiu @derekbit
  - [FEATURE] Longhorn UI for SPDK feature ([5846](https://github.com/longhorn/longhorn/issues/5846)) - @smallteeths @chriscchien
  - [FEATURE] UI modification to work with new AD mechanism (Longhorn UI -> Longhorn API) ([6004](https://github.com/longhorn/longhorn/issues/6004)) - @yangchiu @smallteeths
  - [FEATURE] Replica offline rebuild over SPDK - data engine ([6067](https://github.com/longhorn/longhorn/issues/6067)) - @shuo-wu
  - [FEATURE] Support automatic offline replica rebuilding of volumes using SPDK data engine ([6071](https://github.com/longhorn/longhorn/issues/6071)) - @yangchiu @derekbit
  
## Improvement
  
  - [IMPROVEMENT] Do not count the failure replica reuse failure caused by the disconnection ([1923](https://github.com/longhorn/longhorn/issues/1923)) - @yangchiu @mantissahz
  - [IMPROVEMENT] Consider changing the over provisioning default/recommendation to 100% percentage (no over provisioning) ([2694](https://github.com/longhorn/longhorn/issues/2694)) - @c3y1huang @chriscchien
  - [BUG] StorageClass of pv and pvc of a recovered pv should not always be default. ([3506](https://github.com/longhorn/longhorn/issues/3506)) - @ChanYiLin @smallteeths @roger-ryao
  - [IMPROVEMENT] Auto-attach volume for K8s CSI snapshot ([3726](https://github.com/longhorn/longhorn/issues/3726)) - @weizhe0422 @PhanLe1010
  - [IMPROVEMENT] Change Longhorn API to create/delete snapshot CRs instead of calling engine CLI ([3995](https://github.com/longhorn/longhorn/issues/3995)) - @yangchiu @PhanLe1010
  - [IMPROVEMENT] Add support for crypto parameters for RWX volumes ([4829](https://github.com/longhorn/longhorn/issues/4829)) - @mantissahz @roger-ryao
  - [IMPROVEMENT] Remove the global setting `mkfs-ext4-parameters` ([4914](https://github.com/longhorn/longhorn/issues/4914)) - @ejweber @roger-ryao
  - [IMPROVEMENT] Move all snapshot related settings at one place. ([4930](https://github.com/longhorn/longhorn/issues/4930)) - @smallteeths @roger-ryao
  - [IMPROVEMENT] Remove system managed component image settings  ([5028](https://github.com/longhorn/longhorn/issues/5028)) - @mantissahz @chriscchien
  - [IMPROVEMENT] Set default `engine-replica-timeout` value for engine controller start command ([5031](https://github.com/longhorn/longhorn/issues/5031)) - @derekbit @chriscchien
  - [IMPROVEMENT] Support bundle collects dmesg, syslog and related information of longhorn nodes ([5073](https://github.com/longhorn/longhorn/issues/5073)) - @weizhe0422 @roger-ryao
  - [IMPROVEMENT] Collect volume, system, feature info for metrics for better usage awareness ([5235](https://github.com/longhorn/longhorn/issues/5235)) - @c3y1huang @chriscchien @roger-ryao
  - [IMPROVEMENT] Update uninstallation info to include the 'Deleting Confirmation Flag'  in chart ([5250](https://github.com/longhorn/longhorn/issues/5250)) - @PhanLe1010 @roger-ryao
  - [IMPROVEMENT] Disable Revision Counter for Strict-Local dataLocality ([5257](https://github.com/longhorn/longhorn/issues/5257)) - @derekbit @roger-ryao
  - [IMPROVEMENT] Fix Guaranteed Engine Manager CPU recommendation formula in UI ([5338](https://github.com/longhorn/longhorn/issues/5338)) - @c3y1huang @smallteeths @roger-ryao
  - [IMPROVEMENT] Update PSP validation in the Longhorn upstream chart  ([5339](https://github.com/longhorn/longhorn/issues/5339)) - @yangchiu @PhanLe1010
  - [IMPROVEMENT] Update ganesha nfs to 4.2.3 ([5356](https://github.com/longhorn/longhorn/issues/5356)) - @derekbit @roger-ryao
  - [IMPROVEMENT] Set write-cache of longhorn block device to off explicitly ([5382](https://github.com/longhorn/longhorn/issues/5382)) - @derekbit @chriscchien
  - [IMPROVEMENT] Clean up unused backupstore mountpoint ([5391](https://github.com/longhorn/longhorn/issues/5391)) - @derekbit @chriscchien
  - [DOC] Update Kubernetes version info to have consistent description from the longhorn documentation in chart ([5399](https://github.com/longhorn/longhorn/issues/5399)) - @ChanYiLin @roger-ryao
  - [IMPROVEMENT] Fix BackingImage uploading/downloading flow to prevent client timeout ([5443](https://github.com/longhorn/longhorn/issues/5443)) - @ChanYiLin @chriscchien
  - [IMPROVEMENT] Assign the pods to the same node where the strict-local volume is present ([5448](https://github.com/longhorn/longhorn/issues/5448)) - @c3y1huang @chriscchien
  - [IMPROVEMENT] Have explicitly message when trying to attach a volume which it's engine and replica were on deleted node  ([5545](https://github.com/longhorn/longhorn/issues/5545)) - @ChanYiLin @chriscchien
  - [IMPROVEMENT] Create a new setting so that Longhorn removes PDB for instance-manager-r that doesn't have any running instance inside it ([5549](https://github.com/longhorn/longhorn/issues/5549)) - @PhanLe1010 @roger-ryao
  - [IMPROVEMENT] Merge conversion/admission webhook and recovery backend services into longhorn-manager ([5590](https://github.com/longhorn/longhorn/issues/5590)) - @ChanYiLin @chriscchien
  - [IMPROVEMENT][UI] Recurring jobs create new snapshots while being not able to clean up old one ([5610](https://github.com/longhorn/longhorn/issues/5610)) - @mantissahz @smallteeths @roger-ryao
  - [IMPROVEMENT] Only activate replica if it doesn't have deletion timestamp during volume engine upgrade ([5632](https://github.com/longhorn/longhorn/issues/5632)) - @PhanLe1010 @roger-ryao
  - [IMPROVEMENT] Clean up backup target if the backup target setting is unset ([5655](https://github.com/longhorn/longhorn/issues/5655)) - @yangchiu @ChanYiLin
  - [IMPROVEMENT] Bump CSI sidecar components' version ([5672](https://github.com/longhorn/longhorn/issues/5672)) - @yangchiu @ejweber
  - [IMPROVEMENT] Configure log level of Longhorn components ([5888](https://github.com/longhorn/longhorn/issues/5888)) - @ChanYiLin @weizhe0422
  - [IMPROVEMENT] Remove development toolchain from Longhorn images ([6022](https://github.com/longhorn/longhorn/issues/6022)) - @ChanYiLin @derekbit
  - [IMPROVEMENT] Reduce replica process's number of allocated ports  ([6079](https://github.com/longhorn/longhorn/issues/6079)) - @ChanYiLin @derekbit
  - [IMPROVEMENT] UI supports automatic replica rebuilding for SPDK volumes ([6107](https://github.com/longhorn/longhorn/issues/6107)) - @smallteeths @roger-ryao
  - [IMPROVEMENT] Minor UX changes for Longhorn SPDK ([6126](https://github.com/longhorn/longhorn/issues/6126)) - @derekbit @roger-ryao
  - [IMPROVEMENT] Instance manager spdk_tgt resilience due to spdk_tgt crash ([6155](https://github.com/longhorn/longhorn/issues/6155)) - @yangchiu @derekbit
  - [IMPROVEMENT] Determine number of replica/engine port count in longhorn-manager (control plane) instead ([6163](https://github.com/longhorn/longhorn/issues/6163)) - @derekbit @chriscchien
  - [IMPROVEMENT] SPDK client should functions after encountering decoding error ([6191](https://github.com/longhorn/longhorn/issues/6191)) - @yangchiu @shuo-wu
  
## Performance
  
  - [REFACTORING] Evaluate the impact of removing the client side compression for backup blocks ([1409](https://github.com/longhorn/longhorn/issues/1409)) - @derekbit
  
## Resilience
  
  - [BUG] If backing image downloading fails on one node, it doesn't try on other nodes. ([3746](https://github.com/longhorn/longhorn/issues/3746)) - @ChanYiLin
  - [BUG] Replica rebuilding caused by rke2/kubelet restart ([5340](https://github.com/longhorn/longhorn/issues/5340)) - @derekbit @chriscchien
  - [BUG] Volume restoration will never complete if attached node is down ([5464](https://github.com/longhorn/longhorn/issues/5464)) - @derekbit @weizhe0422 @chriscchien
  - [BUG] Node disconnection test failed ([5476](https://github.com/longhorn/longhorn/issues/5476)) - @yangchiu @derekbit
  - [BUG] Physical node down test failed ([5477](https://github.com/longhorn/longhorn/issues/5477)) - @derekbit @chriscchien
  - [BUG] Backing image with sync failure ([5481](https://github.com/longhorn/longhorn/issues/5481)) - @ChanYiLin @roger-ryao
  - [BUG] share-manager pod failed to restart after kubelet restart ([5507](https://github.com/longhorn/longhorn/issues/5507)) - @yangchiu @derekbit
  - [BUG] Directly mark replica as failed if the node is deleted ([5542](https://github.com/longhorn/longhorn/issues/5542)) - @weizhe0422 @roger-ryao
  - [BUG] RWX volume is stuck at detaching when the attached node is down  ([5558](https://github.com/longhorn/longhorn/issues/5558)) - @derekbit @roger-ryao
  - [BUG] Unable to export RAID1 bdev in degraded state  ([5650](https://github.com/longhorn/longhorn/issues/5650)) - @chriscchien @DamiaSan
  - [BUG] Backup monitor gets stuck in an infinite loop if backup isn't found ([5662](https://github.com/longhorn/longhorn/issues/5662)) - @derekbit @chriscchien
  - [BUG] Resources such as replicas are somehow not mutated when network is unstable  ([5762](https://github.com/longhorn/longhorn/issues/5762)) - @derekbit @roger-ryao
  - [BUG] filesystem corrupted after delete instance-manager-r for a locality best-effort volume ([5801](https://github.com/longhorn/longhorn/issues/5801)) - @yangchiu @ChanYiLin @mantissahz
  
## Stability
  
  - [BUG] nfs backup broken - NFS server: mkdir - file exists ([4626](https://github.com/longhorn/longhorn/issues/4626)) - @yangchiu @derekbit
  - [BUG] Memory leak in CSI plugin caused by stuck umount processes if the RWX volume is already gone ([5296](https://github.com/longhorn/longhorn/issues/5296)) - @derekbit @roger-ryao
  
## Bugs
  
  - [BUG] 'Upgrade Engine' still shows up in a specific situation when engine already upgraded ([3063](https://github.com/longhorn/longhorn/issues/3063)) - @weizhe0422 @PhanLe1010 @smallteeths
  - [BUG] DR volume even after activation remains in standby mode if there are one or more failed replicas. ([3069](https://github.com/longhorn/longhorn/issues/3069)) - @yangchiu @mantissahz
  - [BUG] volume not able to attach with raw type backing image ([3437](https://github.com/longhorn/longhorn/issues/3437)) - @yangchiu @ChanYiLin
  - [BUG] Delete a uploading backing image, the corresponding LH temp file is not deleted ([3682](https://github.com/longhorn/longhorn/issues/3682)) - @ChanYiLin @chriscchien
  - [BUG] Cloned PVC from detached volume will stuck at not ready for workload ([3692](https://github.com/longhorn/longhorn/issues/3692)) - @PhanLe1010 @chriscchien
  - [BUG] Block device volume failed to unmount when it is detached unexpectedly ([3778](https://github.com/longhorn/longhorn/issues/3778)) - @PhanLe1010 @chriscchien
  - [BUG] After migration of Longhorn from Rancher old UI to dashboard, the csi-plugin doesn't update ([4519](https://github.com/longhorn/longhorn/issues/4519)) - @mantissahz @roger-ryao
  - [BUG] Volumes Stuck in Attach/Detach Loop when running on OpenShift/OKD ([4988](https://github.com/longhorn/longhorn/issues/4988)) - @ChanYiLin
  - [BUG] Longhorn 1.3.2 fails to backup & restore volumes behind Internet proxy  ([5054](https://github.com/longhorn/longhorn/issues/5054)) - @mantissahz @chriscchien
  - [BUG] Instance manager pod does not respect of node taint? ([5161](https://github.com/longhorn/longhorn/issues/5161)) - @ejweber
  - [BUG] RWX doesn't work with release 1.4.0 due to end grace update error from recovery backend ([5183](https://github.com/longhorn/longhorn/issues/5183)) - @derekbit @chriscchien
  - [BUG] Incorrect indentation of charts/questions.yaml ([5196](https://github.com/longhorn/longhorn/issues/5196)) - @mantissahz @roger-ryao
  - [BUG] Updating option "Allow snapshots removal during trim" for old volumes failed  ([5218](https://github.com/longhorn/longhorn/issues/5218)) - @shuo-wu @roger-ryao
  - [BUG] Since 1.4.0 RWX volume failing regularly ([5224](https://github.com/longhorn/longhorn/issues/5224)) - @derekbit
  - [BUG] Can not create backup in engine image not fully deployed cluster ([5248](https://github.com/longhorn/longhorn/issues/5248)) - @ChanYiLin @roger-ryao
  - [BUG] Incorrect router retry mechanism ([5259](https://github.com/longhorn/longhorn/issues/5259)) - @mantissahz @chriscchien
  - [BUG] System Backup is stuck at Uploading if there are PVs not provisioned by CSI driver ([5286](https://github.com/longhorn/longhorn/issues/5286)) - @c3y1huang @chriscchien
  - [BUG] Sync up with backup target during DR volume activation ([5292](https://github.com/longhorn/longhorn/issues/5292)) - @yangchiu @weizhe0422
  - [BUG] environment_check.sh does not handle different kernel versions in cluster correctly ([5304](https://github.com/longhorn/longhorn/issues/5304)) - @achims311 @roger-ryao
  - [BUG] instance-manager-r high memory consumption ([5312](https://github.com/longhorn/longhorn/issues/5312)) - @derekbit @roger-ryao
  - [BUG] Unable to upgrade longhorn from v1.3.2 to master-head ([5368](https://github.com/longhorn/longhorn/issues/5368)) - @yangchiu @derekbit
  - [BUG] Modify engineManagerCPURequest and replicaManagerCPURequest won't raise resource request in instance-manager-e pod ([5419](https://github.com/longhorn/longhorn/issues/5419)) - @c3y1huang
  - [BUG] Error message not consistent between create/update recurring job when retain number greater than 50 ([5434](https://github.com/longhorn/longhorn/issues/5434)) - @c3y1huang @chriscchien
  - [BUG] Do not copy Host header to API requests forwarded to Longhorn Manager ([5438](https://github.com/longhorn/longhorn/issues/5438)) - @yangchiu @smallteeths
  - [BUG] RWX Volume attachment is getting Failed ([5456](https://github.com/longhorn/longhorn/issues/5456)) - @derekbit
  - [BUG] test case test_backup_lock_deletion_during_restoration failed ([5458](https://github.com/longhorn/longhorn/issues/5458)) - @yangchiu @derekbit
  - [BUG] Unable to create support bundle agent pod in air-gap environment ([5467](https://github.com/longhorn/longhorn/issues/5467)) - @yangchiu @c3y1huang
  - [BUG] Example of data migration doesn't work for hidden/./dot-files) ([5484](https://github.com/longhorn/longhorn/issues/5484)) - @hedefalk @shuo-wu @chriscchien
  - [BUG] Upgrade engine --> spec.restoreVolumeRecurringJob and spec.snapshotDataIntegrity Unsupported value ([5485](https://github.com/longhorn/longhorn/issues/5485)) - @yangchiu @derekbit
  - [BUG] test case test_dr_volume_with_backup_block_deletion failed ([5489](https://github.com/longhorn/longhorn/issues/5489)) - @yangchiu @derekbit
  - [BUG] Bulk backup deletion cause restoring volume to finish with attached state. ([5506](https://github.com/longhorn/longhorn/issues/5506)) - @ChanYiLin @roger-ryao
  - [BUG] volume expansion starts for no reason, gets stuck on current size > expected size ([5513](https://github.com/longhorn/longhorn/issues/5513)) - @mantissahz @roger-ryao
  - [BUG] RWX volume attachment failed if tried more enough times ([5537](https://github.com/longhorn/longhorn/issues/5537)) - @yangchiu @derekbit
  - [BUG] instance-manager-e emits `Wait for process pvc-xxxx to shutdown` constantly ([5575](https://github.com/longhorn/longhorn/issues/5575)) - @derekbit @roger-ryao
  - [BUG] Support bundle kit should respect node selector & taint toleration ([5614](https://github.com/longhorn/longhorn/issues/5614)) - @yangchiu @c3y1huang
  - [BUG] Value overlapped in page Instance Manager Image ([5622](https://github.com/longhorn/longhorn/issues/5622)) - @smallteeths @chriscchien
  - [BUG] Updated Rocky 9 (and others) can't attach due to SELinux ([5627](https://github.com/longhorn/longhorn/issues/5627)) - @yangchiu @ejweber
  - [BUG] Fix misleading error messages when creating a mount point for a backup store ([5630](https://github.com/longhorn/longhorn/issues/5630)) - @derekbit
  - [BUG] Instance manager PDB created with wrong selector thus blocking the draining of the wrongly selected node forever ([5680](https://github.com/longhorn/longhorn/issues/5680)) - @PhanLe1010 @chriscchien
  - [BUG] During volume live engine upgrade, if the replica pod is killed, the volume is stuck in upgrading forever ([5684](https://github.com/longhorn/longhorn/issues/5684)) - @yangchiu @PhanLe1010
  - [BUG] Instance manager PDBs cannot be removed if the longhorn-manager pod on its spec node is not available ([5688](https://github.com/longhorn/longhorn/issues/5688)) - @PhanLe1010 @roger-ryao
  - [BUG] Rebuild rebuilding is possibly issued to a wrong replica ([5709](https://github.com/longhorn/longhorn/issues/5709)) - @ejweber @roger-ryao
  - [BUG] Observing repilca on new IM-r before upgrading of volume ([5729](https://github.com/longhorn/longhorn/issues/5729)) - @c3y1huang
  - [BUG] longhorn upgrade is not upgrading engineimage ([5740](https://github.com/longhorn/longhorn/issues/5740)) - @shuo-wu @chriscchien
  - [BUG] `test_replica_auto_balance_when_replica_on_unschedulable_node` Error in creating volume with nodeSelector and dataLocality parameters ([5745](https://github.com/longhorn/longhorn/issues/5745)) - @c3y1huang @roger-ryao
  - [BUG] Unable to backup volume after NFS server IP change ([5856](https://github.com/longhorn/longhorn/issues/5856)) - @derekbit @roger-ryao
  - [BUG] Prevent Longhorn uninstallation from getting stuck due to backups in error ([5868](https://github.com/longhorn/longhorn/issues/5868)) - @ChanYiLin @mantissahz
  - [BUG]  Unable to create support bundle if the previous one stayed in ReadyForDownload phase ([5882](https://github.com/longhorn/longhorn/issues/5882)) - @c3y1huang @roger-ryao
  - [BUG] share-manager for a given pvc keep restarting (other pvc are working fine) ([5954](https://github.com/longhorn/longhorn/issues/5954)) - @yangchiu @derekbit
  - [BUG] Replica auto-rebalance doesn't respect node selector ([5971](https://github.com/longhorn/longhorn/issues/5971)) - @c3y1huang @roger-ryao
  - [BUG] Volume detached automatically after upgrade Longhorn ([5983](https://github.com/longhorn/longhorn/issues/5983)) - @yangchiu @PhanLe1010
  - [BUG] Extra snapshot generated when clone from a detached volume ([5986](https://github.com/longhorn/longhorn/issues/5986)) - @weizhe0422 @ejweber
  - [BUG] User created snapshot deleted after node drain and uncordon ([5992](https://github.com/longhorn/longhorn/issues/5992)) - @yangchiu @mantissahz
  - [BUG] Webhook PDBs are not removed after upgrading to master-head ([6026](https://github.com/longhorn/longhorn/issues/6026)) - @weizhe0422 @PhanLe1010
  - [BUG] In some specific situation, system backup auto deleted when creating another one ([6045](https://github.com/longhorn/longhorn/issues/6045)) - @c3y1huang @chriscchien
  - [BUG] Backing Image deletion stuck if it's deleted during uploading process and bids is ready-for-transfer state ([6086](https://github.com/longhorn/longhorn/issues/6086)) - @WebberHuang1118 @chriscchien
  - [BUG] A backup target backed by a Samba server is not recognized ([6100](https://github.com/longhorn/longhorn/issues/6100)) - @derekbit @weizhe0422
  - [BUG] Backing image manager fails when SELinux is enabled ([6108](https://github.com/longhorn/longhorn/issues/6108)) - @ejweber @chriscchien
  - [BUG] Force delete volume make SPDK disk unschedule ([6110](https://github.com/longhorn/longhorn/issues/6110)) - @derekbit
  - [BUG] share-manager terminated during Longhorn upgrading causes rwx volume not working ([6120](https://github.com/longhorn/longhorn/issues/6120)) - @yangchiu @derekbit
  - [BUG] SPDK Volume snapshotList API Error ([6123](https://github.com/longhorn/longhorn/issues/6123)) - @derekbit @chriscchien
  - [BUG] test_recurring_jobs_allow_detached_volume failed ([6124](https://github.com/longhorn/longhorn/issues/6124)) - @ChanYiLin @roger-ryao
  - [BUG] Cron job triggered replica rebuilding keeps repeating itself after corrupting snapshot data ([6129](https://github.com/longhorn/longhorn/issues/6129)) - @yangchiu @mantissahz
  - [BUG] test_dr_volume_with_restore_command_error failed ([6130](https://github.com/longhorn/longhorn/issues/6130)) - @mantissahz @roger-ryao
  - [BUG] RWX volume remains attached after workload deleted if it's upgraded from v1.4.2 ([6139](https://github.com/longhorn/longhorn/issues/6139)) - @PhanLe1010 @chriscchien
  - [BUG] timestamp or checksum not matched in test_snapshot_hash_detect_corruption test case ([6145](https://github.com/longhorn/longhorn/issues/6145)) - @yangchiu @derekbit
  - [BUG] When a v2 volume is attached in maintenance mode, removing a replica will lead to volume stuck in attaching-detaching loop  ([6166](https://github.com/longhorn/longhorn/issues/6166)) - @derekbit @chriscchien
  - [BUG] Misleading offline rebuilding hint if offline rebuilding is not enabled ([6169](https://github.com/longhorn/longhorn/issues/6169)) - @smallteeths @roger-ryao
  - [BUG] Longhorn doesn't remove the system backups crd on uninstallation ([6185](https://github.com/longhorn/longhorn/issues/6185)) - @c3y1huang @khushboo-rancher
  - [BUG] Volume attachment related error logs in uninstaller pod ([6197](https://github.com/longhorn/longhorn/issues/6197)) - @yangchiu @PhanLe1010
  - [BUG] Test case test_ha_backup_deletion_recovery failed in rhel or rockylinux arm64 environment ([6213](https://github.com/longhorn/longhorn/issues/6213)) - @yangchiu @ChanYiLin @mantissahz
  - [BUG] migration test cases could fail due to unexpected volume controllers and replicas status ([6215](https://github.com/longhorn/longhorn/issues/6215)) - @yangchiu @PhanLe1010
  - [BUG] Engine continues to attempt to rebuild replica while detaching ([6217](https://github.com/longhorn/longhorn/issues/6217)) - @yangchiu @ejweber
  
## Misc
  
  - [TASK] Remove deprecated volume spec recurringJobs and storageClass recurringJobs field ([2865](https://github.com/longhorn/longhorn/issues/2865)) - @c3y1huang @chriscchien
  - [TASK] Remove deprecated fields after CRD API version bump ([3289](https://github.com/longhorn/longhorn/issues/3289)) - @c3y1huang @roger-ryao
  - [TASK] Replace jobq lib with an alternative way for listing remote backup volumes and info ([4176](https://github.com/longhorn/longhorn/issues/4176)) - @ChanYiLin @chriscchien
  - [DOC] Update the Longhorn document in Uninstalling Longhorn using kubectl ([4841](https://github.com/longhorn/longhorn/issues/4841)) - @roger-ryao
  - [TASK] Remove a deprecated feature `disable-replica-rebuild` from longhorn-manager ([4997](https://github.com/longhorn/longhorn/issues/4997)) - @ejweber @chriscchien
  - [TASK]  Update the distro matrix supports on Longhorn docs for 1.5 ([5177](https://github.com/longhorn/longhorn/issues/5177)) - @yangchiu
  - [TASK] Clarify if any upcoming K8s API deprecation/removal will impact Longhorn 1.4 ([5180](https://github.com/longhorn/longhorn/issues/5180)) - @PhanLe1010
  - [TASK] Revert affinity for Longhorn user deployed components ([5191](https://github.com/longhorn/longhorn/issues/5191)) - @weizhe0422 @ejweber
  - [TASK] Add GitHub action for CI to lib repos for supporting dependency bot ([5239](https://github.com/longhorn/longhorn/issues/5239)) - 
  - [DOC] Update the readme of longhorn-spdk-engine about using new Longhorn (RAID1) bdev ([5256](https://github.com/longhorn/longhorn/issues/5256)) - @DamiaSan
  - [TASK][UI] add new recurring job tasks ([5272](https://github.com/longhorn/longhorn/issues/5272)) - @smallteeths @chriscchien
  - [DOC] Update the node maintenance doc to cover upgrade prerequisites for Rancher ([5278](https://github.com/longhorn/longhorn/issues/5278)) - @PhanLe1010
  - [TASK] Run build-engine-test-images automatically when having incompatible engine on master ([5400](https://github.com/longhorn/longhorn/issues/5400)) - @yangchiu
  - [TASK] Update k8s.gcr.io to registry.k8s.io in repos ([5432](https://github.com/longhorn/longhorn/issues/5432)) - @yangchiu
  - [TASK][UI] add new recurring job task - filesystem trim ([5529](https://github.com/longhorn/longhorn/issues/5529)) - @smallteeths @chriscchien
  - doc: update prerequisites in chart readme to make it consistent with documentation v1.3.x ([5531](https://github.com/longhorn/longhorn/pull/5531)) - @ChanYiLin
  - [FEATURE] Remove deprecated `allow-node-drain-with-last-healthy-replica` ([5620](https://github.com/longhorn/longhorn/issues/5620)) - @weizhe0422 @PhanLe1010
  - [FEATURE] Set recurring jobs to PVCs ([5791](https://github.com/longhorn/longhorn/issues/5791)) - @yangchiu @c3y1huang
  - [TASK] Automatically update crds.yaml in longhorn repo from longhorn-manager repo ([5854](https://github.com/longhorn/longhorn/issues/5854)) - @yangchiu
  - [IMPROVEMENT] Remove privilege requirement from lifecycle jobs ([5862](https://github.com/longhorn/longhorn/issues/5862)) - @mantissahz @chriscchien
  - [TASK][UI] support new aio typed instance managers ([5876](https://github.com/longhorn/longhorn/issues/5876)) - @smallteeths @chriscchien
  - [TASK] Remove `Guaranteed Engine Manager CPU`, `Guaranteed Replica Manager CPU`, and `Guaranteed Engine CPU` settings. ([5917](https://github.com/longhorn/longhorn/issues/5917)) - @c3y1huang @roger-ryao
  - [TASK][UI] Support volume backup policy ([6028](https://github.com/longhorn/longhorn/issues/6028)) - @smallteeths @chriscchien
  - [TASK] Reduce BackupConcurrentLimit and RestoreConcurrentLimit default values  ([6135](https://github.com/longhorn/longhorn/issues/6135)) - @derekbit @chriscchien
  
## Contributors

- @ChanYiLin
- @DamiaSan
- @PhanLe1010
- @WebberHuang1118
- @achims311
- @c3y1huang
- @chriscchien
- @derekbit
- @ejweber
- @hedefalk
- @innobead
- @khushboo-rancher
- @mantissahz
- @roger-ryao
- @shuo-wu
- @smallteeths
- @weizhe0422
- @yangchiu
