## Release Note
### **v1.4.3 released!** 🎆

Longhorn v1.4.3 is the latest stable version of Longhorn 1.4.
It introduces improvements and bug fixes in the areas of stability, resilience, and so on. Please try it out and provide feedback. Thanks for all the contributions!

> For the definition of stable or latest release, please check [here](https://github.com/longhorn/longhorn#releases).

## Installation

> **Please ensure your Kubernetes cluster is at least v1.21 before installing v1.4.3.**

Longhorn supports 3 installation ways including Rancher App Marketplace, Kubectl, and Helm. Follow the installation instructions [here](https://longhorn.io/docs/1.4.3/deploy/install/).

## Upgrade

> **Please read the [important notes](https://longhorn.io/docs/1.4.3/deploy/important-notes/) first and ensure your Kubernetes cluster is at least v1.21 before upgrading to Longhorn v1.4.3 from v1.3.x/v1.4.x, which are only supported source versions.**

Follow the upgrade instructions [here](https://longhorn.io/docs/1.4.3/deploy/upgrade/).

## Deprecation & Incompatibilities

N/A

## Known Issues after Release

Please follow up on [here](https://github.com/longhorn/longhorn/wiki/Outstanding-Known-Issues-of-Releases) about any outstanding issues found after this release.


## Improvement
  
  - [IMPROVEMENT] Assign the pods to the same node where the strict-local volume is present ([5448](https://github.com/longhorn/longhorn/issues/5448)) - @c3y1huang @chriscchien
  
## Resilience
  
  - [BUG] filesystem corrupted after delete instance-manager-r for a locality best-effort volume ([5801](https://github.com/longhorn/longhorn/issues/5801)) - @yangchiu @ChanYiLin @mantissahz
  
## Bugs
  
  - [BUG] 'Upgrade Engine' still shows up in a specific situation when engine already upgraded ([3063](https://github.com/longhorn/longhorn/issues/3063)) - @weizhe0422 @PhanLe1010 @smallteeths
  - [BUG] DR volume even after activation remains in standby mode if there are one or more failed replicas. ([3069](https://github.com/longhorn/longhorn/issues/3069)) - @yangchiu @mantissahz
  - [BUG] Prevent Longhorn uninstallation from getting stuck due to backups in error ([5868](https://github.com/longhorn/longhorn/issues/5868)) - @ChanYiLin @mantissahz
  - [BUG]  Unable to create support bundle if the previous one stayed in ReadyForDownload phase ([5882](https://github.com/longhorn/longhorn/issues/5882)) - @c3y1huang @roger-ryao
  - [BUG] share-manager for a given pvc keep restarting (other pvc are working fine) ([5954](https://github.com/longhorn/longhorn/issues/5954)) - @yangchiu @derekbit
  - [BUG] Replica auto-rebalance doesn't respect node selector ([5971](https://github.com/longhorn/longhorn/issues/5971)) - @c3y1huang @roger-ryao
  - [BUG] Extra snapshot generated when clone from a detached volume ([5986](https://github.com/longhorn/longhorn/issues/5986)) - @weizhe0422 @ejweber
  - [BUG] User created snapshot deleted after node drain and uncordon ([5992](https://github.com/longhorn/longhorn/issues/5992)) - @yangchiu @mantissahz
  - [BUG] In some specific situation, system backup auto deleted when creating another one ([6045](https://github.com/longhorn/longhorn/issues/6045)) - @c3y1huang @chriscchien
  - [BUG] Backing Image deletion stuck if it's deleted during uploading process and bids is ready-for-transfer state ([6086](https://github.com/longhorn/longhorn/issues/6086)) - @WebberHuang1118 @chriscchien
  - [BUG] Backing image manager fails when SELinux is enabled ([6108](https://github.com/longhorn/longhorn/issues/6108)) - @ejweber @chriscchien
  - [BUG] test_dr_volume_with_restore_command_error failed ([6130](https://github.com/longhorn/longhorn/issues/6130)) - @mantissahz @roger-ryao
  - [BUG] Longhorn doesn't remove the system backups crd on uninstallation ([6185](https://github.com/longhorn/longhorn/issues/6185)) - @c3y1huang @khushboo-rancher
  - [BUG] Test case test_ha_backup_deletion_recovery failed in rhel or rockylinux arm64 environment ([6213](https://github.com/longhorn/longhorn/issues/6213)) - @yangchiu @ChanYiLin @mantissahz
  - [BUG] Engine continues to attempt to rebuild replica while detaching ([6217](https://github.com/longhorn/longhorn/issues/6217)) - @yangchiu @ejweber
  - [BUG] Unable to receive support bundle from UI when it's large (400MB+) ([6256](https://github.com/longhorn/longhorn/issues/6256)) - @c3y1huang @chriscchien 
  - [BUG] Migration test case failed: unable to detach volume migration is not ready yet ([6238](https://github.com/longhorn/longhorn/issues/6238)) - @yangchiu @PhanLe1010 @khushboo-rancher
  - [BUG] Restored Volumes stuck in attaching state ([6239](https://github.com/longhorn/longhorn/issues/6239)) - @derekbit @roger-ryao
  
## Contributors

- @ChanYiLin
- @PhanLe1010
- @WebberHuang1118
- @c3y1huang
- @chriscchien
- @derekbit
- @ejweber
- @innobead
- @khushboo-rancher
- @mantissahz
- @roger-ryao
- @smallteeths
- @weizhe0422
- @yangchiu
