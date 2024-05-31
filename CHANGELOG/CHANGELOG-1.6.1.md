## Longhorn v1.6.1 Release Notes

Longhorn 1.6.1 introduces several improvements and bug fixes that are intended to improve system quality, resilience, and stability.

The Longhorn team appreciates your contributions and expects to receive feedback regarding this release.

> **Note:**
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

**Ensure that your cluster is running Kubernetes v1.21 or later before installing Longhorn v1.6.1.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.6.1/deploy/install/) in the Longhorn documentation.

## Upgrade

**Ensure that your cluster is running Kubernetes v1.21 or later before upgrading from Longhorn v1.5.x or v1.6.x to v1.6.1.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.6.1/deploy/upgrade/) in the Longhorn documentation.

## Deprecation & Incompatibilities

For information about important changes, including feature incompatibility, deprecation, and removal, see [Important Notes](https://longhorn.io/docs/1.6.1/deploy/important-notes/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Improvement
- [BACKPORT][v1.6.1][IMPROVEMENT] Add dmsetup and dmcrypt utilities check in environment check script [8234](https://github.com/longhorn/longhorn/issues/8234) - @derekbit @chriscchien
- [BACKPORT][v1.6.1][IMPROVEMENT] Upgrade support bundle kit version to v0.0.36 [8162](https://github.com/longhorn/longhorn/issues/8162) - @c3y1huang @roger-ryao
- [BACKPORT][v1.6.1][IMPROVEMENT] Cannot read/write to block volume when the container is run as non-root [8122](https://github.com/longhorn/longhorn/issues/8122) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.6.1][IMPROVEMENT] Improve environment_check script for NFS protocol bug and the host system self diagnosis [7971](https://github.com/longhorn/longhorn/issues/7971) - @james-munson @roger-ryao
- [BACKPORT][v1.6.1][IMPROVEMENT] Use HEAD instead of a GET to fetch the `Content-Length` of an resource via URL [7973](https://github.com/longhorn/longhorn/issues/7973) - @votdev @roger-ryao
- [BACKPORT][v1.6.1][IMPROVEMENT] Remove startup probe of CSI driver after liveness probe conn fix ready [7886](https://github.com/longhorn/longhorn/issues/7886) - @ejweber @roger-ryao
- [BACKPORT][v1.6.1][IMPROVEMENT] Change support-bundle-manager image pull policy to PullIfNotPresent [8000](https://github.com/longhorn/longhorn/issues/8000) - @ChanYiLin @roger-ryao

### Bug
- [BUG][v1.6.1-rc3] test_backup_lock_creation_during_deletion failed with *.lck type 1 acquisition [8269](https://github.com/longhorn/longhorn/issues/8269) - @ChanYiLin @chriscchien
- [BACKPORT][v1.6.1][BUG] Replica rebuild failed [8258](https://github.com/longhorn/longhorn/issues/8258) - @shuo-wu @roger-ryao
- [BACKPORT][v1.6.1][BUG] potential risk to unmap a negative number [8237](https://github.com/longhorn/longhorn/issues/8237) - @Vicente-Cheng @roger-ryao
- [BACKPORT][v1.6.1][BUG] Can't use longhorn with Generic ephemeral volumes [8213](https://github.com/longhorn/longhorn/issues/8213) - @ejweber @chriscchien
- [BUG] [v1.6.1-rc1] v2 volume replica offline rebuilding fail [8187](https://github.com/longhorn/longhorn/issues/8187) - @shuo-wu @chriscchien
- [BACKPORT][v1.6.1][BUG] Longhorn api-server PUT request rate [8152](https://github.com/longhorn/longhorn/issues/8152) - @ejweber @roger-ryao
- [BACKPORT][v1.6.1][BUG] Use config map to update `default-replica-count` won't apply to `default-replica-count.definition.default` if the value equal to current `default-replica-count.value` [8134](https://github.com/longhorn/longhorn/issues/8134) - @james-munson @roger-ryao
- [BACKPORT][v1.6.1][BUG] Failed to restore a backup to file by the scripts/restore-backup-to-file.sh with a CIFS backup target. [8128](https://github.com/longhorn/longhorn/issues/8128) - @mantissahz @roger-ryao
- [BACKPORT][v1.6.1][BUG] Exporting data from the existing replicas has issues in 1.6.0 [8096](https://github.com/longhorn/longhorn/issues/8096) - @ChanYiLin @chriscchien
- [BACKPORT][v1.6.1][BUG] longhorn manager pod fails to start in container-based K3s [7847](https://github.com/longhorn/longhorn/issues/7847) - @ChanYiLin @khushboo-rancher @chriscchien
- [BACKPORT][v1.6.1][BUG] no Pending workload pods for volume xxx to be mounted [8081](https://github.com/longhorn/longhorn/issues/8081) - @c3y1huang @chriscchien
- [BACKPORT][v1.6.1][BUG] Deadlock is possible in v1.6.0 instance manager [7920](https://github.com/longhorn/longhorn/issues/7920) - @roger-ryao
- [BACKPORT][v1.6.1][BUG][1.6.0] ENGINE v2 : disk /dev/xxxx is already used by AIO bdev disk-x [8133](https://github.com/longhorn/longhorn/issues/8133) - @derekbit @chriscchien
- [BACKPORT][v1.6.1][BUG] A replica may be incorrectly scheduled to a node with an existing failed replica [8044](https://github.com/longhorn/longhorn/issues/8044) - @ejweber @chriscchien
- [BACKPORT][v1.6.1][BUG] Deadlock between volume migration and upgrade after Longhorn upgrade [7870](https://github.com/longhorn/longhorn/issues/7870) - @ejweber @roger-ryao
- [BACKPORT][v1.6.1][BUG] Volume cannot attach because of the leftover non-empty volume.status.PendingNodeID after upgrading Longhorn [7995](https://github.com/longhorn/longhorn/issues/7995) - @james-munson @chriscchien
- [BACKPORT][v1.6.1][BUG] Longhorn may keep corrupted salvaged replicas and discard good ones [7885](https://github.com/longhorn/longhorn/issues/7885) - @ejweber @roger-ryao
- [BACKPORT][v1.6.1][BUG] LH manager reboots due to the webhook is not ready [8037](https://github.com/longhorn/longhorn/issues/8037) - @ChanYiLin @chriscchien
- [BACKPORT][v1.6.1][BUG] BackingImage does not download URL correctly in some situation [7987](https://github.com/longhorn/longhorn/issues/7987) - @votdev @yangchiu
- [BACKPORT][v1.6.1][BUG] Executing fstrim while rebuilding causes IO errors [7868](https://github.com/longhorn/longhorn/issues/7868) - @yangchiu @ejweber
- [BACKPORT][v1.6.1][BUG] The feature of auto remount read only volume not work on a single node cluster. [7846](https://github.com/longhorn/longhorn/issues/7846) - @yangchiu @ChanYiLin
- [BACKPORT][v1.6.1][BUG] Missed NodeStageVolume after reboot leads to CreateContainerError [8012](https://github.com/longhorn/longhorn/issues/8012) - @ejweber @chriscchien
- [BACKPORT][v1.6.1][BUG] persistence.removeSnapshotsDuringFilesystemTrim Helm variable is unreferenced [7952](https://github.com/longhorn/longhorn/issues/7952) - @ejweber @chriscchien
- [BACKPORT][v1.6.1][BUG][v1.5.4-rc4] Test case test_backuptarget_available_during_engine_image_not_ready failed to wait for backup target available [8055](https://github.com/longhorn/longhorn/issues/8055) - @c3y1huang @chriscchien
- [BACKPORT][v1.6.1][BUG] Add Snapshot Maximum Count to the Settings [7979](https://github.com/longhorn/longhorn/issues/7979) - @FrankYang0529 @roger-ryao
- [BACKPORT][v1.6.1][BUG] Volumes stuck upgrading after 1.5.3 -> 1.6.0 upgrade. [7899](https://github.com/longhorn/longhorn/issues/7899) - @ejweber @roger-ryao
- [BACKPORT][v1.6.1][BUG] The activated DR volume do not contain the latest data. [7946](https://github.com/longhorn/longhorn/issues/7946) - @shuo-wu @roger-ryao
- [BACKPORT][v1.6.1][BUG][v1.5.x] Recurring job fails to create backup when volume detached [8013](https://github.com/longhorn/longhorn/issues/8013) - @yangchiu @mantissahz @PhanLe1010 @c3y1huang
- [BACKPORT][v1.6.1][BUG] Create backup failed: failed lock lock-*.lck type 1 acquisition [7875](https://github.com/longhorn/longhorn/issues/7875) - @yangchiu @ChanYiLin @chriscchien
- [BUG] Fix errors in questions.yaml [6392](https://github.com/longhorn/longhorn/issues/6392) - @james-munson @chriscchien

### Misc
- [BACKPORT][v1.6.1][REFACTOR] move mount point check function to common lib [8124](https://github.com/longhorn/longhorn/issues/8124) - @ChanYiLin @chriscchien
- [TASK] Fix updating patch digest dependencies (v1.6.x)  [8107](https://github.com/longhorn/longhorn/issues/8107) - @mantissahz

## Contributors
- @ChanYiLin
- @FrankYang0529
- @PhanLe1010
- @Vicente-Cheng
- @c3y1huang
- @chriscchien
- @derekbit
- @ejweber
- @innobead
- @james-munson
- @khushboo-rancher
- @mantissahz
- @roger-ryao
- @shuo-wu
- @votdev
- @yangchiu 
