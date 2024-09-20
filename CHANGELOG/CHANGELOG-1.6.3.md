## Longhorn v1.6.3 Release Notes

Longhorn 1.6.3 introduces several improvements and bug fixes that are intended to improve system quality, resilience, and stability.

The Longhorn team appreciates your contributions and expects to receive feedback regarding this release.

> [!NOTE]
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before installing Longhorn v1.6.3.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.6.3/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before upgrading from Longhorn v1.5.x or v1.6.x (< v1.6.3) to v1.6.3.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.6.3/deploy/upgrade/) in the Longhorn documentation.

## Deprecation & Incompatibilities

For information about important changes, including feature incompatibility, deprecation, and removal, see [Important Notes](https://longhorn.io/docs/1.6.3/deploy/important-notes/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Features
- [BACKPORT][v1.6.3][FEATURE] Add additional monitoring settings to ServiceMonitor resource. [8984](https://github.com/longhorn/longhorn/issues/8984) - @ejweber @chriscchien

### Improvement
- [BACKPORT][v1.6.3][IMPROVEMENT] Fix contradicting node status events [9327](https://github.com/longhorn/longhorn/issues/9327) - @ejweber @roger-ryao
- [BACKPORT][v1.6.3][IMPROVEMENT] Always update the built-in installed system packages when building component images [8722](https://github.com/longhorn/longhorn/issues/8722) - @yangchiu @c3y1huang
- [BACKPORT][v1.6.3][IMPROVEMENT] Update sizes in Engine and Volume resources less frequently [8684](https://github.com/longhorn/longhorn/issues/8684) - @ejweber @roger-ryao
- [BACKPORT][v1.6.3][IMPROVEMENT] Longhor Manager Flood with "Failed to get engine proxy of ... cannot get client for engine" Message [8729](https://github.com/longhorn/longhorn/issues/8729) - @derekbit @roger-ryao
- [BACKPORT][v1.6.3][IMPROVEMENT] Restore Latest Backup should be applied with BackingImage name value [8671](https://github.com/longhorn/longhorn/issues/8671) - @a110605 @roger-ryao
- [BACKPORT][v1.6.3][IMPROVEMENT] Improve and simplify chart values.yaml [8636](https://github.com/longhorn/longhorn/issues/8636) - @ChanYiLin @chriscchien
- [BACKPORT][v1.6.3][IMPROVEMENT] BackingImage UI improvement [8655](https://github.com/longhorn/longhorn/issues/8655) - @a110605 @roger-ryao
- [BACKPORT][v1.6.3][IMPROVEMENT] Saving Settings page changes [8602](https://github.com/longhorn/longhorn/issues/8602) - @a110605 @roger-ryao
- [BACKPORT][v1.6.3][IMPROVEMENT] The client-go rest client rate limit inside the csi sidecar component might be too small (csi-provisioner, csi-attacjer. csi-snappshotter, csi-attacher) [8726](https://github.com/longhorn/longhorn/issues/8726) - @PhanLe1010
- [BACKPORT][v1.6.3][IMPROVEMENT] Add setting to configure support bundle timeout for node bundle collection [8624](https://github.com/longhorn/longhorn/issues/8624) - @c3y1huang @chriscchien
- [BACKPORT][v1.6.3][IMPROVEMENT] Problems mounting XFS volume clones / restored snapshots [8797](https://github.com/longhorn/longhorn/issues/8797) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.6.3][IMPROVEMENT] Cannot expand a volume created by Longhorn UI [8828](https://github.com/longhorn/longhorn/issues/8828) - @mantissahz
- [BACKPORT][v1.6.3][IMPROVEMENT] environment_check.sh should check for the iscsi_tcp kernel module [8720](https://github.com/longhorn/longhorn/issues/8720) - @tserong @roger-ryao
- [BACKPORT][v1.6.3][IMPROVEMENT] `toomanysnapshots` UI element not prominent enough to prevent runaway snapshots [8672](https://github.com/longhorn/longhorn/issues/8672) - @a110605 @roger-ryao

### Bug
- [BACKPORT][v1.6.3][BUG] instance-manager is stuck at starting state [8678](https://github.com/longhorn/longhorn/issues/8678) - @derekbit
- [BACKPORT][v1.6.3][BUG] kubectl drain node is blocked by unexpected orphan engine processes [9446](https://github.com/longhorn/longhorn/issues/9446) - @ejweber @chriscchien @roger-ryao
- [BACKPORT][v1.6.3][BUG] Uninstallation will fail if invalid backuptarget is set. [8793](https://github.com/longhorn/longhorn/issues/8793) - @mantissahz @chriscchien
- [BACKPORT][v1.6.3][BUG] Longhorn thinks node is unschedulable [9052](https://github.com/longhorn/longhorn/issues/9052) - @c3y1huang @roger-ryao
- [BACKPORT][v1.6.3][BUG] Can not revert V2 volume snapshot after upgrade from v1.6.2 to v1.7.0-dev [9066](https://github.com/longhorn/longhorn/issues/9066) - @chriscchien @DamiaSan
- [BACKPORT][v1.6.3][BUG] Canceling expansion results in a volume expansion error [9469](https://github.com/longhorn/longhorn/issues/9469) - @derekbit
- [BACKPORT][v1.6.3][BUG] Pod auto-deletion may cause thousands of logs [9020](https://github.com/longhorn/longhorn/issues/9020) - @ejweber @roger-ryao
- [BACKPORT][v1.6.3][BUG] Engine Upgrade to 1.7.1 fails on volumes with strict-local data locality [9447](https://github.com/longhorn/longhorn/issues/9447) - @james-munson @chriscchien
- [BACKPORT][v1.6.3][BUG] Fix longhorn-manager `TestCleanupRedundantInstanceManagers` [8670](https://github.com/longhorn/longhorn/issues/8670) - @derekbit @roger-ryao
- [BUG] Security issues in longhorn 1.6.2 version images [9132](https://github.com/longhorn/longhorn/issues/9132) - @c3y1huang
- [BACKPORT][v1.6.3][BUG] Longhorn keeps resetting my storageClass [9395](https://github.com/longhorn/longhorn/issues/9395) - @mantissahz @roger-ryao
- [BUG] Regression in 1.6.x-head, significant increase in execution time [9439](https://github.com/longhorn/longhorn/issues/9439) - @ChanYiLin @roger-ryao
- [BACKPORT][v1.6.3][BUG] System Backup Fails and DR Volume Enters Attach-Detach Loop When Volume Backup Policy is Set to `Always` [9339](https://github.com/longhorn/longhorn/issues/9339) - @c3y1huang @roger-ryao
- [BACKPORT][v1.6.3][BUG] `toomanysnapshots` UI message displays incorrect snapshot count [8700](https://github.com/longhorn/longhorn/issues/8700) - @ejweber
- [BACKPORT][v1.6.3][BUG] Longhorn can no longer create XFS volumes smaller than 300 MiB [8560](https://github.com/longhorn/longhorn/issues/8560) - @ejweber @chriscchien
- [BACKPORT][v1.6.3][BUG] test case `test_system_backup_and_restore_volume_with_backingimage` failed on sle-micro ARM64 [9227](https://github.com/longhorn/longhorn/issues/9227) - @ChanYiLin @roger-ryao
- [BACKPORT][v1.6.3][BUG] Longhorn did not close and open encrypted volumes correctly when the service k3s-agent restarted for a while [9386](https://github.com/longhorn/longhorn/issues/9386) - @mantissahz @roger-ryao
- [BUG] test case `test_recurring_job` the backup recurring job's retain is not working on `v1.6.x-head` for `amd64` [9454](https://github.com/longhorn/longhorn/issues/9454) - @mantissahz @chriscchien
- [BUG][v1.6.x] Abnormal snapshot missing status field [9438](https://github.com/longhorn/longhorn/issues/9438) - @yangchiu @derekbit
- [BACKPORT][v1.6.3][BUG] Instance manager missing required selector labels after manager crash [9472](https://github.com/longhorn/longhorn/issues/9472) - @c3y1huang @chriscchien
- [BUG] test case `test_support_bundle_should_not_timeout` timeout on `v1.6.x-head` for `amd64` [9452](https://github.com/longhorn/longhorn/issues/9452) - @yangchiu @derekbit
- [BACKPORT][v1.6.3][BUG] Replica Auto Balance options under General Setting and under Volume section should have similar case [8786](https://github.com/longhorn/longhorn/issues/8786) - @yangchiu @a110605
- [BUG][UI][v1.6.x] blank dropdown menu in update volume property modals [9465](https://github.com/longhorn/longhorn/issues/9465) - @a110605
- [BACKPORT][v1.6.3][BUG] Accidentally encountered a single replica volume backup stuck at progress 17% indefinitely after a node rebooted [9399](https://github.com/longhorn/longhorn/issues/9399) - @yangchiu @ChanYiLin
- [BACKPORT][v1.6.3][BUG] Non-existing block device results in longhorn-manager to be in Crashloopbackoff state [9074](https://github.com/longhorn/longhorn/issues/9074) - @yangchiu @derekbit
- [BACKPORT][v1.6.3][BUG] Volume failed to create healthy replica after data locality and replica count changed and got stuck in degraded state forever [8561](https://github.com/longhorn/longhorn/issues/8561) - @ejweber @chriscchien @roger-ryao
- [BACKPORT][v1.6.3][BUG] [Backupstore] Need to close the reader after downloading files for the Azure backup store driver. [9283](https://github.com/longhorn/longhorn/issues/9283) - @yangchiu @mantissahz
- [BACKPORT][v1.6.3][BUG] LH fails silently when node has attached volumes [9211](https://github.com/longhorn/longhorn/issues/9211) - @yangchiu @ejweber
- [BACKPORT][v1.6.3][BUG] Volume stuck in degraded [9295](https://github.com/longhorn/longhorn/issues/9295) - @PhanLe1010 @roger-ryao
- [BACKPORT][v1.6.3][BUG] v1 volume replica rebuild fail after upgrade from v1.7.0 to v1.7.1-rc1 [9336](https://github.com/longhorn/longhorn/issues/9336) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.6.3][BUG] instance-manager pod for v2 volume is killed due to a failed liveness probe. [8808](https://github.com/longhorn/longhorn/issues/8808) - @derekbit @chriscchien
- [BACKPORT][v1.6.3][BUG] Share manager controller reconciles tens of thousands of times [9088](https://github.com/longhorn/longhorn/issues/9088) - @ejweber @roger-ryao
- [BACKPORT][v1.6.3][BUG]  Scale replica snapsots warning [8851](https://github.com/longhorn/longhorn/issues/8851) - @ejweber
- [BACKPORT][v1.6.3][BUG]filesystem trim RecurringJob times out (volumes where files are frequently created and deleted) [9048](https://github.com/longhorn/longhorn/issues/9048) - @c3y1huang @chriscchien
- [BACKPORT][v1.6.3][BUG] Rebuilding Replica fails on larger volumes [8949](https://github.com/longhorn/longhorn/issues/8949) - 
- [BACKPORT][v1.6.3][BUG] Orphan longhorn-engine-manager and longhorn-replica-manager services [8858](https://github.com/longhorn/longhorn/issues/8858) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.6.3][BUG] When revision counter is disabled, the engine might choose a replica with a smaller head size to be the source of truth for auto-salvage [8661](https://github.com/longhorn/longhorn/issues/8661) - @PhanLe1010

### Misc
- [BACKPORT][v1.6.3][TASK] Update the best practice page to mention these broken kernels [8882](https://github.com/longhorn/longhorn/issues/8882) - @PhanLe1010

## Contributors
- @ChanYiLin 
- @DamiaSan 
- @PhanLe1010 
- @a110605 
- @c3y1huang 
- @chriscchien 
- @derekbit 
- @ejweber 
- @innobead 
- @james-munson 
- @mantissahz 
- @roger-ryao 
- @tserong 
- @yangchiu
- @jillian-maroket
- @jhkrug 
- @rebeccazzzz
- @forbesguthrie
- @asettle