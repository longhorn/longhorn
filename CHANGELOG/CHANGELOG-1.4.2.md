## Release Note
### **v1.4.2 released!** 🎆

Longhorn v1.4.2 is the latest stable version of Longhorn 1.4.
It introduces improvements and bug fixes in the areas of stability, performance, space efficiency, resilience, and so on. Please try it out and provide feedback. Thanks for all the contributions!

> For the definition of stable or latest release, please check [here](https://github.com/longhorn/longhorn#releases).

## Installation

> **Please ensure your Kubernetes cluster is at least v1.21 before installing v1.4.2.**

Longhorn supports 3 installation ways including Rancher App Marketplace, Kubectl, and Helm. Follow the installation instructions [here](https://longhorn.io/docs/1.4.2/deploy/install/).

## Upgrade

> **Please read the [important notes](https://longhorn.io/docs/1.4.2/deploy/important-notes/) first and ensure your Kubernetes cluster is at least v1.21 before upgrading to Longhorn v1.4.2 from v1.3.x/v1.4.x, which are only supported source versions.**

Follow the upgrade instructions [here](https://longhorn.io/docs/1.4.2/deploy/upgrade/).

## Deprecation & Incompatibilities

N/A

## Known Issues after Release

Please follow up on [here](https://github.com/longhorn/longhorn/wiki/Outstanding-Known-Issues-of-Releases) about any outstanding issues found after this release.


## Highlights
  
  - [IMPROVEMENT] Use PDB to protect Longhorn components from unexpected drains ([3304](https://github.com/longhorn/longhorn/issues/3304)) - @yangchiu @PhanLe1010
  - [IMPROVEMENT] Introduce timeout mechanism for the sparse file syncing service ([4305](https://github.com/longhorn/longhorn/issues/4305)) - @yangchiu @ChanYiLin
  - [IMPROVEMENT] Recurring jobs create new snapshots while being not able to clean up old ones ([4898](https://github.com/longhorn/longhorn/issues/4898)) - @mantissahz @chriscchien
  
## Improvement
  
  - [IMPROVEMENT] Support bundle collects dmesg, syslog and related information of longhorn nodes ([5073](https://github.com/longhorn/longhorn/issues/5073)) - @weizhe0422 @roger-ryao
  - [IMPROVEMENT] Fix BackingImage uploading/downloading flow to prevent client timeout ([5443](https://github.com/longhorn/longhorn/issues/5443)) - @ChanYiLin @chriscchien
  - [IMPROVEMENT] Create a new setting so that Longhorn removes PDB for instance-manager-r that doesn't have any running instance inside it ([5549](https://github.com/longhorn/longhorn/issues/5549)) - @PhanLe1010 @khushboo-rancher
  - [IMPROVEMENT] Deprecate the setting `allow-node-drain-with-last-healthy-replica` and replace it by `node-drain-policy` setting ([5585](https://github.com/longhorn/longhorn/issues/5585)) - @yangchiu @PhanLe1010
  - [IMPROVEMENT][UI] Recurring jobs create new snapshots while being not able to clean up old one ([5610](https://github.com/longhorn/longhorn/issues/5610)) - @mantissahz @smallteeths @roger-ryao
  - [IMPROVEMENT] Only activate replica if it doesn't have deletion timestamp during volume engine upgrade ([5632](https://github.com/longhorn/longhorn/issues/5632)) - @PhanLe1010 @roger-ryao
  - [IMPROVEMENT] Clean up backup target if the backup target setting is unset ([5655](https://github.com/longhorn/longhorn/issues/5655)) - @yangchiu @ChanYiLin
  
## Resilience
  
  - [BUG] Directly mark replica as failed if the node is deleted ([5542](https://github.com/longhorn/longhorn/issues/5542)) - @weizhe0422 @roger-ryao
  - [BUG] RWX volume is stuck at detaching when the attached node is down  ([5558](https://github.com/longhorn/longhorn/issues/5558)) - @derekbit @roger-ryao
  - [BUG] Backup monitor gets stuck in an infinite loop if backup isn't found ([5662](https://github.com/longhorn/longhorn/issues/5662)) - @derekbit @chriscchien
  - [BUG] Resources such as replicas are somehow not mutated when network is unstable  ([5762](https://github.com/longhorn/longhorn/issues/5762)) - @derekbit @roger-ryao
  - [BUG] Instance manager may not update instance status for a minute after starting ([5809](https://github.com/longhorn/longhorn/issues/5809)) - @ejweber @chriscchien
  
## Bugs
  
  - [BUG] Delete a uploading backing image, the corresponding LH temp file is not deleted ([3682](https://github.com/longhorn/longhorn/issues/3682)) - @ChanYiLin @chriscchien
  - [BUG] Can not create backup in engine image not fully deployed cluster ([5248](https://github.com/longhorn/longhorn/issues/5248)) - @ChanYiLin @roger-ryao
  - [BUG] Upgrade engine --> spec.restoreVolumeRecurringJob and spec.snapshotDataIntegrity Unsupported value ([5485](https://github.com/longhorn/longhorn/issues/5485)) - @yangchiu @derekbit
  - [BUG] Bulk backup deletion cause restoring volume to finish with attached state. ([5506](https://github.com/longhorn/longhorn/issues/5506)) - @ChanYiLin @roger-ryao
  - [BUG] volume expansion starts for no reason, gets stuck on current size > expected size ([5513](https://github.com/longhorn/longhorn/issues/5513)) - @mantissahz @roger-ryao
  - [BUG] RWX volume attachment failed if tried more enough times ([5537](https://github.com/longhorn/longhorn/issues/5537)) - @yangchiu @derekbit
  - [BUG] instance-manager-e emits `Wait for process pvc-xxxx to shutdown` constantly ([5575](https://github.com/longhorn/longhorn/issues/5575)) - @derekbit @roger-ryao
  - [BUG] Support bundle kit should respect node selector & taint toleration ([5614](https://github.com/longhorn/longhorn/issues/5614)) - @yangchiu @c3y1huang
  - [BUG] Value overlapped in page Instance Manager Image ([5622](https://github.com/longhorn/longhorn/issues/5622)) - @smallteeths @chriscchien
  - [BUG] Instance manager PDB created with wrong selector thus blocking the draining of the wrongly selected node forever ([5680](https://github.com/longhorn/longhorn/issues/5680)) - @PhanLe1010 @chriscchien
  - [BUG] During volume live engine upgrade, if the replica pod is killed, the volume is stuck in upgrading forever ([5684](https://github.com/longhorn/longhorn/issues/5684)) - @yangchiu @PhanLe1010
  - [BUG] Instance manager PDBs cannot be removed if the longhorn-manager pod on its spec node is not available ([5688](https://github.com/longhorn/longhorn/issues/5688)) - @PhanLe1010 @roger-ryao
  - [BUG] Rebuild rebuilding is possibly issued to a wrong replica ([5709](https://github.com/longhorn/longhorn/issues/5709)) - @ejweber @roger-ryao
  - [BUG] longhorn upgrade is not upgrading engineimage ([5740](https://github.com/longhorn/longhorn/issues/5740)) - @shuo-wu @chriscchien
  - [BUG] `test_replica_auto_balance_when_replica_on_unschedulable_node` Error in creating volume with nodeSelector and dataLocality parameters ([5745](https://github.com/longhorn/longhorn/issues/5745)) - @c3y1huang @roger-ryao
  - [BUG] Unable to backup volume after NFS server IP change ([5856](https://github.com/longhorn/longhorn/issues/5856)) - @derekbit @roger-ryao
  
## Misc
  
  - [TASK] Check and update the networking doc & example YAMLs ([5651](https://github.com/longhorn/longhorn/issues/5651)) - @yangchiu @shuo-wu
  
## Contributors

- @ChanYiLin
- @PhanLe1010
- @c3y1huang
- @chriscchien
- @derekbit
- @ejweber
- @innobead
- @khushboo-rancher
- @mantissahz
- @roger-ryao
- @shuo-wu
- @smallteeths
- @weizhe0422
- @yangchiu
