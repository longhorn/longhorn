## Longhorn v1.6.4 Release Notes

Longhorn 1.6.4 introduces several improvements and bug fixes that are intended to improve system quality, resilience, and stability.

The Longhorn team appreciates your contributions and expects to receive feedback regarding this release.

> [!NOTE]
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before installing Longhorn v1.6.4.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.6.4/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before upgrading from Longhorn v1.5.x or v1.6.x (< v1.6.4) to v1.6.4.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.6.4/deploy/upgrade/) in the Longhorn documentation.

## Deprecation & Incompatibilities

For information about important changes, including feature incompatibility, deprecation, and removal, see [Important Notes](https://longhorn.io/docs/1.6.4/deploy/important-notes/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Improvement
- [BACKPORT][v1.6.4][IMPROVEMENT] Add support for JSON log format configuration in Longhorn components (UI, driver) [10080](https://github.com/longhorn/longhorn/issues/10080) - @chriscchien
- [BACKPORT][v1.6.4][IMPROVEMENT] Logging the reason why the instance manager pod is going to be deleted. [9888](https://github.com/longhorn/longhorn/issues/9888) - @derekbit @chriscchien
- [BACKPORT][v1.6.4][IMPROVEMENT] Check NFS versions in /etc/nfsmount.conf instead [9832](https://github.com/longhorn/longhorn/issues/9832) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.6.4][IMPROVEMENT] Prevent Volume Resize Stuck [9913](https://github.com/longhorn/longhorn/issues/9913) - @c3y1huang @roger-ryao
- [BACKPORT][v1.6.4][IMPROVEMENT] Reject strict-local + RWX volume creation [9931](https://github.com/longhorn/longhorn/issues/9931) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.6.4][IMPROVEMENT] Configure the log level of other system and user managed components via longhorn manager setting [9618](https://github.com/longhorn/longhorn/issues/9618) - @yangchiu @james-munson
- [BACKPORT][v1.6.4][IMPROVEMENT] Change misleading error message to warning level [9918](https://github.com/longhorn/longhorn/issues/9918) - @yangchiu @derekbit
- [BACKPORT][v1.6.4][IMPROVEMENT] Building longhorn-manager takes long time [9694](https://github.com/longhorn/longhorn/issues/9694) - @derekbit @chriscchien
- [BACKPORT][v1.6.4][IMPROVEMENT] Remove mirrored openshift image from Longhorn [9599](https://github.com/longhorn/longhorn/issues/9599) - @derekbit @chriscchien

### Bug
- [BUG][v1.6.x-head] Share manager pod kept restarting [10096](https://github.com/longhorn/longhorn/issues/10096) - @c3y1huang @chriscchien
- [BACKPORT][v1.6.4][BUG] Webhook servers initialization blocks longhorn-manager from running [10067](https://github.com/longhorn/longhorn/issues/10067) - @c3y1huang
- [BACKPORT][v1.6.4][BUG] Missing `fromBackup` Parameter in API Request When Restoring Multiple Files from Backup List [10065](https://github.com/longhorn/longhorn/issues/10065) - @a110605 @chriscchien
- [BACKPORT][v1.6.4][BUG] Busrt ISCSI Connection Errors, and IM Pod Restarting to make LH Volume disconnection [9890](https://github.com/longhorn/longhorn/issues/9890) - @yangchiu @ChanYiLin @chriscchien
- [BACKPORT][v1.6.4][BUG] Failed to inspect the backup backing image information if NFS backup target URL with options [9704](https://github.com/longhorn/longhorn/issues/9704) - @yangchiu @mantissahz @chriscchien
- [BACKPORT][v1.6.4][BUG] Error notification appears on the volume backup details page [10070](https://github.com/longhorn/longhorn/issues/10070) - @a110605 @houhoucoop
- [BACKPORT][v1.6.4][BUG][v1.8.x] Unable to add block disk after node deleted and added back [10041](https://github.com/longhorn/longhorn/issues/10041) - 
- [BACKPORT][v1.6.4][BUG] Detached Volume Stuck in Attached State During Node Eviction [9809](https://github.com/longhorn/longhorn/issues/9809) - @c3y1huang @roger-ryao
- [BACKPORT][v1.6.4][BUG] Backup progress should not add block failed to upload to successful count [9792](https://github.com/longhorn/longhorn/issues/9792) - @yangchiu @derekbit
- [BACKPORT][v1.6.4][BUG] S3 Backup target reverts randomly to previous value [9589](https://github.com/longhorn/longhorn/issues/9589) - @c3y1huang
- [BACKPORT][v1.6.4][BUG] Old backups are not cleaned up after timeout [9730](https://github.com/longhorn/longhorn/issues/9730) - @yangchiu @mantissahz
- [BACKPORT][v1.6.4][BUG] Share manager is permanently stuck in stopping/error if we shutdown the node of share manager pod. This makes RWX PVC cannot attach to any new node [9855](https://github.com/longhorn/longhorn/issues/9855) - @yangchiu @PhanLe1010
- [BACKPORT][v1.6.4][BUG] Test case test_node_eviction_multiple_volume failed to reschedule replicas after volume detached [9867](https://github.com/longhorn/longhorn/issues/9867) - @yangchiu @c3y1huang
- [BACKPORT][v1.6.4][BUG] DR volume fails to reattach and faulted after node stop and start during incremental restore [9802](https://github.com/longhorn/longhorn/issues/9802) - @c3y1huang @roger-ryao
- [BACKPORT][v1.6.4][BUG] Fail to resize RWX PVC at filesystem resizing step [9737](https://github.com/longhorn/longhorn/issues/9737) - @james-munson
- [BACKPORT][v1.6.4][BUG] Test case `Stopped replicas on deleted nodes should not be counted as healthy replicas when draining nodes` fails [9625](https://github.com/longhorn/longhorn/issues/9625) - @yangchiu @derekbit
- [BACKPORT][v1.6.4][BUG] Pre-upgrade pod should event the reason for any failures. [9644](https://github.com/longhorn/longhorn/issues/9644) - @yangchiu @james-munson
- [BACKPORT][v1.6.4][BUG] All Backups are lost in the Backup Target if the NFS Service Disconnects and Reconnects again [9543](https://github.com/longhorn/longhorn/issues/9543) - @yangchiu @mantissahz
- [BACKPORT][v1.6.4][BUG] kubectl drain node is blocked by unexpected orphan engine processes [9443](https://github.com/longhorn/longhorn/issues/9443) - @ejweber

### Misc
- [TASK] Fix CVE issues for v1.6.4 [9898](https://github.com/longhorn/longhorn/issues/9898) - @c3y1huang
- [TASK] Update base image version to 15.6 for v1.6.4 [10073](https://github.com/longhorn/longhorn/issues/10073) - @c3y1huang
- [BACKPORT][v1.6.4][TASK] Install the latest grpc_health_probe at build time [9716](https://github.com/longhorn/longhorn/issues/9716) - @yangchiu @c3y1huang

## Contributors
- @COLDTURNIP 
- @ChanYiLin 
- @PhanLe1010 
- @a110605 
- @c3y1huang 
- @chriscchien 
- @derekbit 
- @ejweber 
- @houhoucoop 
- @innobead 
- @james-munson 
- @mantissahz 
- @roger-ryao 
- @yangchiu 
- @jillian-maroket
- @jhkrug 
- @rebeccazzzz
- @forbesguthrie
- @asettle