## Release Note
**v1.4.1 released!** 🎆

This release introduces improvements and bug fixes as described below about stability, performance, space efficiency, resilience, and so on. Please try it and feedback. Thanks for all the contributions!

## Installation

> **Please ensure your Kubernetes cluster is at least v1.21 before installing Longhorn v1.4.1.**

Longhorn supports 3 installation ways including Rancher App Marketplace, Kubectl, and Helm. Follow the installation instructions [here](https://longhorn.io/docs/1.4.1/deploy/install/).

## Upgrade

> **Please ensure your Kubernetes cluster is at least v1.21 before upgrading to Longhorn v1.4.1 from v1.3.x/v1.4.0, which are only supported source versions.**

Follow the upgrade instructions [here](https://longhorn.io/docs/1.4.1/deploy/upgrade/).

## Deprecation & Incompatibilities

N/A

## Known Issues after Release

Please follow up on [here](https://github.com/longhorn/longhorn/wiki/Outstanding-Known-Issues-of-Releases) about any outstanding issues found after this release.


## Highlights

- [IMPROVEMENT] Periodically clean up volume snapshots ([3836](https://github.com/longhorn/longhorn/issues/3836)) - @c3y1huang @chriscchien

## Improvement

- [IMPROVEMENT] Do not count the failure replica reuse failure caused by the disconnection ([1923](https://github.com/longhorn/longhorn/issues/1923)) - @yangchiu @mantissahz
- [IMPROVEMENT] Update uninstallation info to include the 'Deleting Confirmation Flag'  in chart ([5250](https://github.com/longhorn/longhorn/issues/5250)) - @PhanLe1010 @roger-ryao
- [IMPROVEMENT] Fix Guaranteed Engine Manager CPU recommendation formula in UI ([5338](https://github.com/longhorn/longhorn/issues/5338)) - @c3y1huang @smallteeths @roger-ryao
- [IMPROVEMENT] Update PSP validation in the Longhorn upstream chart  ([5339](https://github.com/longhorn/longhorn/issues/5339)) - @yangchiu @PhanLe1010
- [IMPROVEMENT] Update ganesha nfs to 4.2.3 ([5356](https://github.com/longhorn/longhorn/issues/5356)) - @derekbit @roger-ryao
- [IMPROVEMENT] Set write-cache of longhorn block device to off explicitly ([5382](https://github.com/longhorn/longhorn/issues/5382)) - @derekbit @chriscchien

## Stability

- [BUG] Memory leak in CSI plugin caused by stuck umount processes if the RWX volume is already gone ([5296](https://github.com/longhorn/longhorn/issues/5296)) - @derekbit @roger-ryao
- [BUG] share-manager pod failed to restart after kubelet restart ([5507](https://github.com/longhorn/longhorn/issues/5507)) - @yangchiu @derekbit

## Bugs

- [BUG] Longhorn 1.3.2 fails to backup & restore volumes behind Internet proxy  ([5054](https://github.com/longhorn/longhorn/issues/5054)) - @mantissahz @chriscchien
- [BUG] RWX doesn't work with release 1.4.0 due to end grace update error from recovery backend ([5183](https://github.com/longhorn/longhorn/issues/5183)) - @derekbit @chriscchien
- [BUG] Incorrect indentation of charts/questions.yaml ([5196](https://github.com/longhorn/longhorn/issues/5196)) - @mantissahz @roger-ryao
- [BUG] Updating option "Allow snapshots removal during trim" for old volumes failed  ([5218](https://github.com/longhorn/longhorn/issues/5218)) - @shuo-wu @roger-ryao
- [BUG] Incorrect router retry mechanism ([5259](https://github.com/longhorn/longhorn/issues/5259)) - @mantissahz @chriscchien
- [BUG] System Backup is stuck at Uploading if there are PVs not provisioned by CSI driver ([5286](https://github.com/longhorn/longhorn/issues/5286)) - @c3y1huang @chriscchien
- [BUG] Sync up with backup target during DR volume activation ([5292](https://github.com/longhorn/longhorn/issues/5292)) - @yangchiu @weizhe0422
- [BUG] environment_check.sh does not handle different kernel versions in cluster correctly ([5304](https://github.com/longhorn/longhorn/issues/5304)) - @achims311 @roger-ryao
- [BUG] instance-manager-r high memory consumption ([5312](https://github.com/longhorn/longhorn/issues/5312)) - @derekbit @roger-ryao
- [BUG] Replica rebuilding caused by rke2/kubelet restart ([5340](https://github.com/longhorn/longhorn/issues/5340)) - @derekbit @chriscchien
- [BUG] Error message not consistent between create/update recurring job when retain number greater than 50 ([5434](https://github.com/longhorn/longhorn/issues/5434)) - @c3y1huang @chriscchien
- [BUG] Do not copy Host header to API requests forwarded to Longhorn Manager ([5438](https://github.com/longhorn/longhorn/issues/5438)) - @yangchiu @smallteeths
- [BUG] RWX Volume attachment is getting Failed ([5456](https://github.com/longhorn/longhorn/issues/5456)) - @derekbit
- [BUG] test case test_backup_lock_deletion_during_restoration failed ([5458](https://github.com/longhorn/longhorn/issues/5458)) - @yangchiu @derekbit
- [BUG] [master] [v1.4.1-rc1] Volume restoration will never complete if attached node is down ([5464](https://github.com/longhorn/longhorn/issues/5464)) - @derekbit @weizhe0422 @chriscchien
- [BUG] Unable to create support bundle agent pod in air-gap environment ([5467](https://github.com/longhorn/longhorn/issues/5467)) - @yangchiu @c3y1huang
- [BUG] Node disconnection test failed ([5476](https://github.com/longhorn/longhorn/issues/5476)) - @yangchiu @derekbit
- [BUG] Physical node down test failed ([5477](https://github.com/longhorn/longhorn/issues/5477)) - @derekbit @chriscchien
- [BUG] Backing image with sync failure ([5481](https://github.com/longhorn/longhorn/issues/5481)) - @ChanYiLin @roger-ryao
- [BUG] Example of data migration doesn't work for hidden/./dot-files) ([5484](https://github.com/longhorn/longhorn/issues/5484)) - @hedefalk @shuo-wu @chriscchien
- [BUG] test case test_dr_volume_with_backup_block_deletion failed ([5489](https://github.com/longhorn/longhorn/issues/5489)) - @yangchiu @derekbit

## Misc

- [TASK][UI] add new recurring job tasks ([5272](https://github.com/longhorn/longhorn/issues/5272)) - @smallteeths @chriscchien

## Contributors

- @ChanYiLin
- @PhanLe1010
- @achims311
- @c3y1huang
- @chriscchien
- @derekbit
- @hedefalk
- @innobead
- @mantissahz
- @roger-ryao
- @shuo-wu
- @smallteeths
- @weizhe0422
- @yangchiu
