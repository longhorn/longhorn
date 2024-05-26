## Longhorn v1.5.5 Release Notes

This latest stable version of Longhorn 1.5 introduces several improvements and bug fixes that are intended to improve system quality, resilience, and stability. 

The Longhorn team appreciates your contributions and anticipates receiving feedback regarding this release.

> [!NOTE]
> **For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).**

## Installation

>  [!IMPORTANT]  
> **Ensure that your cluster is running Kubernetes v1.21 or later before installing Longhorn v1.5.5.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.5.5/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]  
> **Ensure that your cluster is running Kubernetes v1.21 or later before upgrading from Longhorn v1.4.x or v1.5.x (< v1.5.5) to v1.5.5.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.5.5/deploy/upgrade/) in the Longhorn documentation.

## Deprecation & Incompatibilities

For information about important changes, including feature incompatibility, deprecation, and removal, see [Important Notes](https://longhorn.io/docs/1.5.5/deploy/important-notes/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Improvements
- [BACKPORT][v1.5.5][IMPROVEMENT] Cannot read/write to block volume when the container is run as non-root [8123](https://github.com/longhorn/longhorn/issues/8123) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.5.5][IMPROVEMENT] Do not terminate nfs-ganesha in share-manager pod after failing to access recovery backend [8347](https://github.com/longhorn/longhorn/issues/8347) - @derekbit @chriscchien
- [BACKPORT][v1.5.5][IMPROVEMENT] Expose virtual size of qcow2 backing images [8321](https://github.com/longhorn/longhorn/issues/8321) - @shuo-wu @chriscchien
-  [BACKPORT][v1.5.5][IMPROVEMENT] Improve logging in CSI plugin when mount fails.  [8286](https://github.com/longhorn/longhorn/issues/8286) - @james-munson @chriscchien
- [BACKPORT][v1.5.5][IMPROVEMENT] Upgrade support bundle kit version to v0.0.36 [8161](https://github.com/longhorn/longhorn/issues/8161) - @c3y1huang @roger-ryao
- [BACKPORT][v1.5.5][IMPROVEMENT] Improve environment_check script for NFS protocol bug and the host system self diagnosis [7972](https://github.com/longhorn/longhorn/issues/7972) - @james-munson @roger-ryao

### Bug Fixes
- Security issues in latest longhorn docker images [8372](https://github.com/longhorn/longhorn/issues/8372) - @c3y1huang @chriscchien
- [BACKPORT][v1.5.5][BUG] Backup marked as "completed" cannot be restored, gzip: invalid header [8378](https://github.com/longhorn/longhorn/issues/8378) - @derekbit @chriscchien
- [BACKPORT][v1.5.5][BUG][v1.6.0-rc1] Failed to run instance-manager in storage network environment [8305](https://github.com/longhorn/longhorn/issues/8305) - @yangchiu @ejweber
- [BACKPORT][v1.5.5][BUG] Replica rebuild failed [8257](https://github.com/longhorn/longhorn/issues/8257) - @shuo-wu @chriscchien
- [BACKPORT][v1.5.5][BUG] longhorn manager pod fails to start in container-based K3s [7948](https://github.com/longhorn/longhorn/issues/7948) - @ChanYiLin @chriscchien
- [BACKPORT][v1.5.5][BUG] persistence.removeSnapshotsDuringFilesystemTrim Helm variable is unreferenced [7951](https://github.com/longhorn/longhorn/issues/7951) - @ejweber @roger-ryao
- [BACKPORT][v1.5.5][BUG] Failed to restore a backup to file by the scripts/restore-backup-to-file.sh with a CIFS backup target. [8127](https://github.com/longhorn/longhorn/issues/8127) - @mantissahz @roger-ryao
- [BACKPORT][v1.5.5][BUG] Longhorn api-server PUT request rate [8153](https://github.com/longhorn/longhorn/issues/8153) - @ejweber @roger-ryao
- [BACKPORT][v1.5.5][BUG] A replica may be incorrectly scheduled to a node with an existing failed replica [8116](https://github.com/longhorn/longhorn/issues/8116) - @ejweber @chriscchien
- [BACKPORT][v1.5.5][BUG] potential risk to unmap a negative number [8236](https://github.com/longhorn/longhorn/issues/8236) - @Vicente-Cheng @roger-ryao
- [BACKPORT][v1.5.5][BUG] Use config map to update `default-replica-count` won't apply to `default-replica-count.definition.default` if the value equal to current `default-replica-count.value` [8135](https://github.com/longhorn/longhorn/issues/8135) - @james-munson @chriscchien
- [BACKPORT][v1.5.5][BUG] LH manager reboots due to the webhook is not ready [8036](https://github.com/longhorn/longhorn/issues/8036) - @ChanYiLin @chriscchien
- [BACKPORT][v1.5.5][BUG] Can't use longhorn with Generic ephemeral volumes [8201](https://github.com/longhorn/longhorn/issues/8201) - @ejweber @roger-ryao
- [BACKPORT][v1.5.5][BUG] Volume cannot attach because of the leftover non-empty volume.status.PendingNodeID after upgrading Longhorn [7996](https://github.com/longhorn/longhorn/issues/7996) - @james-munson @roger-ryao
- [BACKPORT][v1.5.5][BUG] no Pending workload pods for volume xxx to be mounted [8082](https://github.com/longhorn/longhorn/issues/8082) - @c3y1huang @roger-ryao

### Miscellaneous
- [TASK] update go-iscsi-helper and go-common-lib in v1.5.x [7960](https://github.com/longhorn/longhorn/issues/7960) - @ChanYiLin
- [BACKPORT][v1.5.5][REFACTOR] move mount point check function to common lib [8125](https://github.com/longhorn/longhorn/issues/8125) - @ChanYiLin @roger-ryao

## Contributors
- @ChanYiLin
- @PhanLe1010
- @Vicente-Cheng
- @c3y1huang
- @chriscchien
- @derekbit
- @ejweber
- @innobead
- @james-munson
- @mantissahz
- @roger-ryao
- @shuo-wu
- @yangchiu 
