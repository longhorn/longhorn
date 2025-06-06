## Longhorn v1.8.2 Release Notes

Longhorn 1.8.2 introduces several improvements and bug fixes that are intended to improve system quality, resilience, stability and security.

The Longhorn team appreciates your contributions and expects to receive feedback regarding this release.

> [!NOTE]
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.8.2.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.8.2/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.7.x or v1.8.x (< v1.8.2) to v1.8.2.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.8.2/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Improvement

- [BACKPORT][v1.8.2][IMPROVEMENT] Adding retry logic for longhorn-csi-plugin when it is trying to contact the longhorn-manager pods [11027](https://github.com/longhorn/longhorn/issues/11027) - @PhanLe1010 @roger-ryao
- [BACKPORT][v1.8.2][IMPROVEMENT] add strict field validation to the update option in upgrade path [10648](https://github.com/longhorn/longhorn/issues/10648) - @ChanYiLin
- [BACKPORT][v1.8.2][IMPROVEMENT] Move `SettingNameV2DataEngineHugepageLimit` to danger zone settings [10568](https://github.com/longhorn/longhorn/issues/10568) - @derekbit @chriscchien
- [BACKPORT][v1.8.2][IMPROVEMENT] Reduce auto balancing logging noise for detached volumes [10692](https://github.com/longhorn/longhorn/issues/10692) - @roger-ryao
- [BACKPORT][v1.8.2][IMPROVEMENT] Improve the Warning Message When Failed to Remove `Block`-Type Disks [10576](https://github.com/longhorn/longhorn/issues/10576) - @yangchiu @ChanYiLin

### Bug

- [BACKPORT][v1.8.2][BUG] unable to clean up the backing image volume replica after node eviction [11057](https://github.com/longhorn/longhorn/issues/11057) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.8.2][BUG] backing image volume replica NPE crash during evicting node [11036](https://github.com/longhorn/longhorn/issues/11036) - @COLDTURNIP @chriscchien
- [BUG] V2 Backing image failed after upgrade from v1.8.1 to v1.8.2-rc1 [10969](https://github.com/longhorn/longhorn/issues/10969) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.8.2][BUG] Error on git checkout in a container [10975](https://github.com/longhorn/longhorn/issues/10975) - @derekbit @chriscchien
- [BACKPORT][v1.8.2][BUG] Helm persistence.backupTargetName not referenced in storageclass template [10964](https://github.com/longhorn/longhorn/issues/10964) - @yangchiu @mantissahz
- [BACKPORT][v1.8.2][BUG] MultiUnmapper floods logs with warnings about size mismatch. [10565](https://github.com/longhorn/longhorn/issues/10565) - @shuo-wu @roger-ryao
- [BACKPORT][v1.8.2][BUG] Test case `test_snapshot_prune_and_coalesce_simultaneously_with_backing_image` fails [10822](https://github.com/longhorn/longhorn/issues/10822) - @yangchiu @c3y1huang
- [BACKPORT][v1.8.2][BUG] System backup could get stuck in `CreatingBackingImageBackups` indefinitely [10748](https://github.com/longhorn/longhorn/issues/10748) - @yangchiu @ChanYiLin
- [BACKPORT][v1.8.2][BUG] Failed to terminate namespace `longhorn-system` if there is a support bundle `ReadyForDownload` [10732](https://github.com/longhorn/longhorn/issues/10732) - @yangchiu @c3y1huang
- [BACKPORT][v1.8.2][BUG] [v1.9.0-rc1] DR volume does not sync with latest backup when activation [10842](https://github.com/longhorn/longhorn/issues/10842) - @c3y1huang @chriscchien
- [BACKPORT][v1.8.2][BUG] Can NOT delete an oversized Not Ready volume [10742](https://github.com/longhorn/longhorn/issues/10742) - @WebberHuang1118 @chriscchien
- [BACKPORT][v1.8.2][BUG][UI] Bulk backup creation with a detached volume returns error 405 and error messages show in browser console [10725](https://github.com/longhorn/longhorn/issues/10725) - @yangchiu @a110605
- [BACKPORT][v1.8.2][BUG] Naming collision when creating the name of the new backing image manager [10618](https://github.com/longhorn/longhorn/issues/10618) - @yangchiu @ChanYiLin
- [BACKPORT][v1.8.2][BUG] I/O errors on Longhorn v1.7.2 volume during VM migration while upgrading Harvester v1.4.1 [10549](https://github.com/longhorn/longhorn/issues/10549) - @derekbit @roger-ryao
- [BACKPORT][v1.8.2][BUG] Adding a non-existing disk to a node will cause the longhorn-manager to crash [10750](https://github.com/longhorn/longhorn/issues/10750) - @ChanYiLin @roger-ryao
- [BACKPORT][v1.8.2][BUG] After node down and force delete the terminating deployment pod, volume can not attach success [10713](https://github.com/longhorn/longhorn/issues/10713) - @c3y1huang @chriscchien
- [BACKPORT][v1.8.2][BUG] Instance manager image build fail [10654](https://github.com/longhorn/longhorn/issues/10654) - @shuo-wu
- [BACKPORT][v1.8.2][BUG] Longhorn Volume Encryption Not Working in Talos 1.9.x [10605](https://github.com/longhorn/longhorn/issues/10605) - @c3y1huang @roger-ryao
- [BACKPORT][v1.8.2][BUG] integer divide by zero in replica scheduler [10504](https://github.com/longhorn/longhorn/issues/10504) - @c3y1huang

## Misc

- [TASK] Fix CVE issues for v1.8.2 [10913](https://github.com/longhorn/longhorn/issues/10913) - @c3y1huang

## Contributors

- @COLDTURNIP
- @ChanYiLin
- @WebberHuang1118
- @a110605
- @c3y1huang
- @chriscchien
- @derekbit
- @innobead
- @mantissahz
- @roger-ryao
- @shuo-wu
- @yangchiu
- @sushant-suse
- @jillian-maroket
- @rebeccazzzz
- @forbesguthrie
- @asettle
