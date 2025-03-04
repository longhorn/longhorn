## Longhorn v1.7.3 Release Notes

Longhorn 1.7.3 introduces several improvements and bug fixes that are intended to improve system quality, resilience, stability and security.

The Longhorn team appreciates your contributions and expects to receive feedback regarding this release.

> [!NOTE]
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before installing Longhorn v1.7.3.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.7.3/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before upgrading from Longhorn v1.6.x or v1.7.x (< v1.7.0) to v1.7.3.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.7.3/deploy/upgrade/) in the Longhorn documentation.

## Deprecation & Incompatibilities

The functionality of the [environment check script](https://github.com/longhorn/longhorn/blob/v1.7.x/scripts/environment_check.sh) overlaps with that of the Longhorn CLI, which is available starting with v1.7.0. Because of this, the script is deprecated in v1.7.0 and is scheduled for removal in v1.8.0.

For information about important changes, including feature incompatibility, deprecation, and removal, see [Important Notes](https://longhorn.io/docs/1.7.3/important-notes/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Feature
- [BACKPORT][v1.7.3][FEATURE] Add periodic HugePages (2Mi) configuration check to ensure v2 data engine compatibility [10029](https://github.com/longhorn/longhorn/issues/10029) - @jangseon-ryu @yangchiu

### Improvement

- [BACKPORT][v1.7.3][IMPROVEMENT] Settings change validation should go back to using Volume state to determine "are all volumes detached" [10375](https://github.com/longhorn/longhorn/issues/10375) - @yangchiu @james-munson
- [BACKPORT][v1.7.3][IMPROVEMENT] Add support for JSON log format configuration in Longhorn components (UI, driver) [10082](https://github.com/longhorn/longhorn/issues/10082) - @chriscchien
- [BACKPORT][v1.7.3][IMPROVEMENT] Logging the reason why the instance manager pod is going to be deleted. [9887](https://github.com/longhorn/longhorn/issues/9887) - @derekbit @chriscchien
- [BACKPORT][v1.7.3][IMPROVEMENT] Why is it not possible to change the replica count in v2 longhorn volume? [9806](https://github.com/longhorn/longhorn/issues/9806) - @chriscchien
- [BACKPORT][v1.7.3][IMPROVEMENT] Check NFS versions in /etc/nfsmount.conf instead [9831](https://github.com/longhorn/longhorn/issues/9831) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.7.3][IMPROVEMENT] Add dmsetup and dmcrypt utilities check in cli [9935](https://github.com/longhorn/longhorn/issues/9935) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.7.3][UI][IMPROVEMENT] Improve the volume size information on UI [9964](https://github.com/longhorn/longhorn/issues/9964) - @houhoucoop @roger-ryao
- [BACKPORT][v1.7.3][IMPROVEMENT] Prevent Volume Resize Stuck [9914](https://github.com/longhorn/longhorn/issues/9914) - @c3y1huang @roger-ryao
- [BACKPORT][v1.7.3][IMPROVEMENT][UI] Add backupBackingImage table in backup page with tabs [9970](https://github.com/longhorn/longhorn/issues/9970) - @houhoucoop
- [BACKPORT][v1.7.3][IMPROVEMENT] Reject strict-local + RWX volume creation [9930](https://github.com/longhorn/longhorn/issues/9930) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.7.3][IMPROVEMENT] Configure the log level of other system and user managed components via longhorn manager setting [9617](https://github.com/longhorn/longhorn/issues/9617) - @yangchiu @james-munson
- [BACKPORT][v1.7.3][IMPROVEMENT] Change confusing error message to warning level [9917](https://github.com/longhorn/longhorn/issues/9917) - @yangchiu @derekbit
- [BACKPORT][v1.7.3][IMPROVEMENT] Building longhorn-manager takes long time [9693](https://github.com/longhorn/longhorn/issues/9693) - @derekbit @chriscchien
- [BACKPORT][v1.7.3][IMPROVEMENT] Talos support for environment check in longhorn manager [9723](https://github.com/longhorn/longhorn/issues/9723) - @yangchiu @c3y1huang

### Bug

- [BACKPORT][v1.7.3][BUG] Data lost caused by Longhorn CSI plugin doing a wrong filesystem format action in a rare race condition [10417](https://github.com/longhorn/longhorn/issues/10417) - @yangchiu @PhanLe1010 @chriscchien
- [BACKPORT][v1.7.3][BUG] kubectl drain node is blocked by unexpected orphan engine processes [10427](https://github.com/longhorn/longhorn/issues/10427) - @yangchiu @PhanLe1010
- [BACKPORT][v1.7.3][BUG] Test case `test_csi_mount_volume_online_expansion` is failing due to unable to expand PVC [10413](https://github.com/longhorn/longhorn/issues/10413) - @yangchiu @c3y1huang
- [BACKPORT][v1.7.3][BUG] Workload pod will not be able to move to new node when backup operation is taking a long time [10173](https://github.com/longhorn/longhorn/issues/10173) - @yangchiu
- [BUG][v1.7.x] Excessive memory consumption caused by RWX volumes / ganesha.nfsd [8523](https://github.com/longhorn/longhorn/issues/8523) - @james-munson @chriscchien
- [BACKPORT][v1.7.3][BUG] WebUI Volumes Disappear and Reappear [10331](https://github.com/longhorn/longhorn/issues/10331) - @PhanLe1010 @chriscchien @houhoucoop
- [BACKPORT][v1.7.3][BUG] "Error get size" from "metrics_collector.(*BackupCollector).Collect" on every metric scrape [10362](https://github.com/longhorn/longhorn/issues/10362) - @derekbit @chriscchien
- [BACKPORT][v1.7.3][BUG] Engine stuck in "stopped" state, prevent volume attach [9954](https://github.com/longhorn/longhorn/issues/9954) - @ChanYiLin @roger-ryao
- [BACKPORT][v1.7.3][BUG] Backup Execution Timeout setting issue in Helm chart [10326](https://github.com/longhorn/longhorn/issues/10326) - @james-munson @chriscchien
- [BACKPORT][v1.7.3][BUG] Instability after power failure [10185](https://github.com/longhorn/longhorn/issues/10185) - @yangchiu @james-munson
- [BACKPORT][v1.7.3][BUG] CSI plugin pod keep crashing util the backup volume appears  when creation a backup via the CSI snapshotter [10024](https://github.com/longhorn/longhorn/issues/10024) - @mantissahz @chriscchien
- [BACKPORT][v1.7.3][BUG] insufficient storage;precheck new replica failed after a temporary shutdown of a node [10223](https://github.com/longhorn/longhorn/issues/10223) - @PhanLe1010 @roger-ryao
- [BACKPORT][v1.7.3][BUG] longhorn-manager seems to crash rpm-DB on the host by continuously calling rpm -q ... [10022](https://github.com/longhorn/longhorn/issues/10022) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.7.3][BUG] Backup progress should not add block failed to upload to successful count [9793](https://github.com/longhorn/longhorn/issues/9793) - @derekbit @chriscchien
- [BACKPORT][v1.7.3][BUG][v1.8.x] Can not create backup, backup become in error state immediately [10180](https://github.com/longhorn/longhorn/issues/10180) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.7.3][BUG] Storage doesn't reschedule in v1.7.2 [10109](https://github.com/longhorn/longhorn/issues/10109) - @PhanLe1010
- [BACKPORT][v1.7.3][BUG] Old backups are not cleaned up after timeout [9731](https://github.com/longhorn/longhorn/issues/9731) - @mantissahz @roger-ryao
- [BACKPORT][v1.7.3][BUG] UnknowOS Message in Longhorn Node Condition on RHEL [9833](https://github.com/longhorn/longhorn/issues/9833) - @yangchiu @mantissahz @roger-ryao
- [BACKPORT][v1.7.3][BUG] volume FailedMount - Input/output error [10005](https://github.com/longhorn/longhorn/issues/10005) - @PhanLe1010 @roger-ryao
- [BACKPORT][v1.7.3][BUG] Unable to delete backing image backup through UI [10068](https://github.com/longhorn/longhorn/issues/10068) - @chriscchien @houhoucoop @roger-ryao
- [BACKPORT][v1.7.3][BUG] Error notification appears on the volume backup details page [10071](https://github.com/longhorn/longhorn/issues/10071) - @houhoucoop @roger-ryao
- [BACKPORT][v1.7.3][BUG] Missing `fromBackup` Parameter in API Request When Restoring Multiple Files from Backup List [10051](https://github.com/longhorn/longhorn/issues/10051) - @a110605 @roger-ryao
- [BACKPORT][v1.7.3][BUG] Webhook servers initialization blocks longhorn-manager from running [10055](https://github.com/longhorn/longhorn/issues/10055) - @c3y1huang @chriscchien
- [BACKPORT][v1.7.3][BUG] CLI check preflight glosses over absence of NFS installation. [9893](https://github.com/longhorn/longhorn/issues/9893) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.7.3][BUG] Detached Volume Stuck in Attached State During Node Eviction [9810](https://github.com/longhorn/longhorn/issues/9810) - @yangchiu @c3y1huang
- [BACKPORT][v1.7.3][BUG] Test case test_node_eviction_multiple_volume failed to reschedule replicas after volume detached [9866](https://github.com/longhorn/longhorn/issues/9866) - @yangchiu @c3y1huang
- [BACKPORT][v1.7.3][BUG] DR volume fails to reattach and faulted after node stop and start during incremental restore [9803](https://github.com/longhorn/longhorn/issues/9803) - @c3y1huang @roger-ryao
- [BACKPORT][v1.7.3][BUG] Share manager is permanently stuck in stopping/error if we shutdown the node of share manager pod. This makes RWX PVC cannot attach to any new node [9856](https://github.com/longhorn/longhorn/issues/9856) - 
- [BACKPORT][v1.7.3][BUG] Fail to resize RWX PVC at filesystem resizing step [9738](https://github.com/longhorn/longhorn/issues/9738) - @james-munson
- [BACKPORT][v1.7.3][BUG] Failed to inspect the backup backing image information if NFS backup target URL with options [9703](https://github.com/longhorn/longhorn/issues/9703) - @yangchiu @mantissahz
- [BACKPORT][v1.7.3][BUG] Pre-upgrade pod should event the reason for any failures. [9643](https://github.com/longhorn/longhorn/issues/9643) - @yangchiu @james-munson

## Misc

- [TASK] Fix CVE issues for v1.7.3 [9897](https://github.com/longhorn/longhorn/issues/9897) - @c3y1huang
- [BACKPORT][v1.7.3][TASK] Install the latest grpc_health_probe at build time [9715](https://github.com/longhorn/longhorn/issues/9715) - @yangchiu @c3y1huang

## Contributors

- @COLDTURNIP 
- @ChanYiLin 
- @PhanLe1010 
- @a110605 
- @c3y1huang 
- @chriscchien 
- @derekbit 
- @houhoucoop 
- @innobead 
- @james-munson
- @jangseon-ryu  
- @mantissahz 
- @roger-ryao 
- @yangchiu 
- @jillian-maroket 
- @jhkrug
- @rebeccazzzz
- @forbesguthrie
- @asettle
