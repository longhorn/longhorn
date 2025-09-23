## Longhorn v1.9.2 Release Notes

Longhorn 1.9.2 introduces several improvements and bug fixes that are intended to improve system quality, resilience, stability and security.

The Longhorn team appreciates your contributions and expects to receive feedback regarding this release.

> [!NOTE]
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.9.2.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.9.2/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.8.x or v1.9.x (< v1.9.2) to v1.9.2.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.9.2/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Improvement

- [BACKPORT][v1.9.2][IMPROVEMENT] Add usage metrics for Longhorn installation variant [11805](https://github.com/longhorn/longhorn/issues/11805) - @derekbit
- [BACKPORT][v1.9.2][IMPROVEMENT] SAST Potential dereference of the null pointer in controller/volume_controller.go in longhorn-manager [11782](https://github.com/longhorn/longhorn/issues/11782) - @c3y1huang
- [BACKPORT][v1.9.2][IMPROVEMENT] Collect mount table, process status and process table in support bundle [11726](https://github.com/longhorn/longhorn/issues/11726) - @mantissahz @chriscchien
- [BACKPORT][v1.9.2][IMPROVEMENT] rename the backing image manager to reduce the probability of CR name collision [11567](https://github.com/longhorn/longhorn/issues/11567) - @COLDTURNIP @chriscchien
- [BACKPORT][v1.9.2][IMPROVEMENT] Improve log messages of longhorn-engine, tgt and liblonghorn for troubleshooting [11604](https://github.com/longhorn/longhorn/issues/11604) - @yangchiu @derekbit
- [BACKPORT][v1.9.2][IMPROVEMENT] Misleading log message `Deleting orphans on evicted node ...` [11501](https://github.com/longhorn/longhorn/issues/11501) - @yangchiu @derekbit
- [BACKPORT][v1.9.2][IMPROVEMENT] Check if the backup target is available before creating a backup, backup backing image, and system backup [11324](https://github.com/longhorn/longhorn/issues/11324) - @yangchiu @nzhan126
- [BACKPORT][v1.9.2][IMPROVEMENT] adjust the hardcoded timeout limitation for backing image downloading [11310](https://github.com/longhorn/longhorn/issues/11310) - @COLDTURNIP @chriscchien
- [BACKPORT][v1.9.2][IMPROVEMENT] Improve longhorn-engine controller log messages [11508](https://github.com/longhorn/longhorn/issues/11508) - @derekbit @chriscchien
- [BACKPORT][v1.9.2][IMPROVEMENT] Make liveness probe parameters of instance-manager pod configurable [11506](https://github.com/longhorn/longhorn/issues/11506) - @derekbit @chriscchien
- [BACKPORT][v1.9.2][IMPROVEMENT] backing image handle node disk deleting events [11488](https://github.com/longhorn/longhorn/issues/11488) - @COLDTURNIP @chriscchien
- [BACKPORT][v1.9.2][IMPROVEMENT] Handle credential secret containing mixed invalid conditions [11327](https://github.com/longhorn/longhorn/issues/11327) - @yangchiu @nzhan126
- [BACKPORT][v1.9.2][IMPROVEMENT] Improve the condition message of engine image check [11193](https://github.com/longhorn/longhorn/issues/11193) - @derekbit @chriscchien

### Bug

- [BACKPORT][v1.9.2][BUG] Potential Data Corruption During Volume Resizing When Created from Snapshot [11788](https://github.com/longhorn/longhorn/issues/11788) - @yangchiu @PhanLe1010
- [BUG] [v1.9.x] support bundle stuck at 33% [11744](https://github.com/longhorn/longhorn/issues/11744) - @mantissahz @chriscchien
- [BACKPORT][v1.9.2][BUG] Unable to disable v2-data-engine even though there is no v2 volumes, backing images or orphaned data [11639](https://github.com/longhorn/longhorn/issues/11639) - @shuo-wu @chriscchien
- [BACKPORT][v1.9.2][BUG] Longhorn pvcs are in pending state. [11722](https://github.com/longhorn/longhorn/issues/11722) - @yangchiu @derekbit
- [BUG] Broken link in documentation [11729](https://github.com/longhorn/longhorn/issues/11729) - @consideRatio
- [BACKPORT][v1.9.2][BUG]  longhornctl preflight install should load and check iscsi_tcp kernel module. [11710](https://github.com/longhorn/longhorn/issues/11710) - @mantissahz @chriscchien
- [BACKPORT][v1.9.2][BUG] Backing image download gets stuck after network disconnection [11624](https://github.com/longhorn/longhorn/issues/11624) - @COLDTURNIP
- [BACKPORT][v1.9.2][BUG] Volume becomes faulted when its replica node disks run out of space during a write operation [11341](https://github.com/longhorn/longhorn/issues/11341) - @mantissahz @chriscchien
- [BACKPORT][v1.9.2][BUG] Engine process continues running after rapid volume detachment [11606](https://github.com/longhorn/longhorn/issues/11606) - @COLDTURNIP @yangchiu @chriscchien
- [BACKPORT][v1.9.2][BUG] Creating a 2 Gi volume with a 200 Mi backing image is rejected with “volume size should be larger than the backing image size” [11648](https://github.com/longhorn/longhorn/issues/11648) - @COLDTURNIP @yangchiu @chriscchien
- [BACKPORT][v1.9.2][BUG] longhorn-manager repeatedly emits `No instance manager for node xxx for update instance state of orphan instance orphan-xxx..` [11599](https://github.com/longhorn/longhorn/issues/11599) - @COLDTURNIP @chriscchien
- [BACKPORT][v1.9.2][BUG] BackupBackingImage may be created from an unready BackingImageManager [11692](https://github.com/longhorn/longhorn/issues/11692) - @WebberHuang1118 @roger-ryao
- [BACKPORT][v1.9.2][BUG] Longhorn fails to create Backing Image Backup on ARM platform [11570](https://github.com/longhorn/longhorn/issues/11570) - @COLDTURNIP
- [BACKPORT][v1.9.2][BUG] remaining unknown OS condition in node CR [11614](https://github.com/longhorn/longhorn/issues/11614) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.9.2][BUG] Volumes fails to remount when they go read-only [11584](https://github.com/longhorn/longhorn/issues/11584) - @derekbit @chriscchien
- [BACKPORT][v1.9.2][BUG] Dangling Volume State When Live Migration Terminates Unexpectedly [11590](https://github.com/longhorn/longhorn/issues/11590) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.9.2][BUG] Unable to setup backup target in storage network environment: cannot find a running instance manager for node [11482](https://github.com/longhorn/longhorn/issues/11482) - @derekbit @chriscchien
- [BACKPORT][v1.9.2][BUG] Test case `test_recurring_jobs_when_volume_detached_unexpectedly` failed: backup completed but progress did not reach 100% [11476](https://github.com/longhorn/longhorn/issues/11476) - @yangchiu @mantissahz
- [BACKPORT][v1.9.2][BUG] Recurring Job with 'default' group causes goroutine deadlock on v1.9.1 (Regression of #11020) [11494](https://github.com/longhorn/longhorn/issues/11494) - @c3y1huang
- [BACKPORT][v1.9.2][BUG] Test Case `test_replica_auto_balance_node_least_effort` Is Sometimes Failed [11391](https://github.com/longhorn/longhorn/issues/11391) - @derekbit @chriscchien
- [BACKPORT][v1.9.2][BUG] Unable to set up S3 backup target if backups already exist [11344](https://github.com/longhorn/longhorn/issues/11344) - @mantissahz @chriscchien
- [BACKPORT][v1.9.2][BUG] longhorn-manager is crashed due to `SIGSEGV: segmentation violation` [11422](https://github.com/longhorn/longhorn/issues/11422) - @derekbit @roger-ryao
- [BACKPORT][v1.9.2][BUG] Typo in configuration parameter: "offlineRelicaRebuilding" should be "offlineReplicaRebuilding" [11382](https://github.com/longhorn/longhorn/issues/11382) - @yangchiu
- [BUG][UI][v1.9.2-rc2] Unable to Retrieve Volume's Backup List in the Operation [11841](https://github.com/longhorn/longhorn/issues/11841) - @houhouhoucoop @roger-ryao

## New Contributors

- @consideRatio 
 
## Contributors

- @COLDTURNIP 
- @PhanLe1010 
- @WebberHuang1118 
- @c3y1huang 
- @chriscchien 
- @derekbit 
- @innobead 
- @mantissahz 
- @nzhan126 
- @roger-ryao 
- @shuo-wu 
- @yangchiu 
