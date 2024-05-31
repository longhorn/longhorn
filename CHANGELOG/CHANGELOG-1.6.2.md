## Longhorn v1.6.2 Release Notes

Longhorn 1.6.2 introduces several improvements and bug fixes that are intended to improve system quality, resilience, and stability.

The Longhorn team appreciates your contributions and expects to receive feedback regarding this release.

> [!NOTE]
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before installing Longhorn v1.6.2.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.6.2/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before upgrading from Longhorn v1.5.x or v1.6.x (< v1.6.2) to v1.6.2.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.6.2/deploy/upgrade/) in the Longhorn documentation.

## Deprecation & Incompatibilities

For information about important changes, including feature incompatibility, deprecation, and removal, see [Important Notes](https://longhorn.io/docs/1.6.2/deploy/important-notes/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Improvement
- [BACKPORT][v1.6.2][IMPROVEMENT] Saving Settings page changes [8600](https://github.com/longhorn/longhorn/issues/8600) - @a110605 @roger-ryao
- [BACKPORT][v1.6.2][IMPROVEMENT] Expose virtual size of qcow2 backing images [8322](https://github.com/longhorn/longhorn/issues/8322) - @chriscchien
- [BACKPORT][v1.6.2][IMPROVEMENT] Prevent unnecessary updates of instanceManager status [8421](https://github.com/longhorn/longhorn/issues/8421) - @yangchiu @derekbit
- [BACKPORT][v1.6.2][UI][IMPROVEMENT] Allow users to request backup volume update [8539](https://github.com/longhorn/longhorn/issues/8539) - @a110605 @chriscchien
- [BACKPORT][v1.6.2][IMPROVEMENT] Allow users to request backup volume update [8154](https://github.com/longhorn/longhorn/issues/8154) - @yangchiu @mantissahz
- [BACKPORT][v1.6.2][IMPROVEMENT] Investigate performance bottleneck in v1 data path [8511](https://github.com/longhorn/longhorn/issues/8511) - @PhanLe1010 @roger-ryao
- [BACKPORT][v1.6.2]Mirror the `quay.io/openshift/origin-oauth-proxy` image to Longhorn repo similar to what we are doing for CSI sidecar images [8334](https://github.com/longhorn/longhorn/issues/8334) - @PhanLe1010 @roger-ryao
- [BACKPORT][v1.6.2][IMPROVEMENT] Avoid misleading log messages in longhorn manager while syncing danger zone settings [8383](https://github.com/longhorn/longhorn/issues/8383) - @yangchiu @mantissahz
- [BACKPORT][v1.6.2][IMPROVEMENT] Do not terminate nfs-ganesha in share-manager pod after failing to access recovery backend [8346](https://github.com/longhorn/longhorn/issues/8346) - @derekbit @chriscchien
- [BACKPORT][v1.6.2][IMPROVEMENT] Improve environment_check script for NFS protocol bug and the host system self diagnosis [8277](https://github.com/longhorn/longhorn/issues/8277) - @james-munson @chriscchien

### Bug
- [BACKPORT][v1.6.2][BUG] Longhorn upgrade from 1.4.4 to 1.5.5 failing [8607](https://github.com/longhorn/longhorn/issues/8607) - @PhanLe1010 @roger-ryao
- [BACKPORT][v1.6.2][BUG] BackupTarget conditions don't reflect connection errors in v1.6.0 [8223](https://github.com/longhorn/longhorn/issues/8223) - @ejweber @chriscchien
- [BACKPORT][v1.6.2][BUG] share-manager-pvc appears to be leaking memory [8426](https://github.com/longhorn/longhorn/issues/8426) - @derekbit @roger-ryao
- [BACKPORT][v1.6.2][BUG] Secret for backup not found [8512](https://github.com/longhorn/longhorn/issues/8512) - @yangchiu @mantissahz
- [BUG][v1.6.2-rc1] Workload pod got stuck in ContainerStatusUnknown after node shutdown and reboot [8550](https://github.com/longhorn/longhorn/issues/8550) - @c3y1huang
- [BACKPORT][v1.6.2][BUG] Valid backup secret produces error message: "there is space or new line in AWS_CERT" [8477](https://github.com/longhorn/longhorn/issues/8477) - @yangchiu @mantissahz
- [BACKPORT][v1.6.2][BUG] Backup marked as "completed" cannot be restored, gzip: invalid header [8377](https://github.com/longhorn/longhorn/issues/8377) - @derekbit @roger-ryao
- [BACKPORT][v1.6.2][BUG] Lost connection to unix:///csi/csi.sock [8493](https://github.com/longhorn/longhorn/issues/8493) - @ejweber @roger-ryao
- [BACKPORT][v1.6.2][BUG] Longhorn Helm uninstall times out. [8409](https://github.com/longhorn/longhorn/issues/8409) - @ChanYiLin @roger-ryao
- [BACKPORT][v1.6.2][BUG] Disable tls 1.0 and 1.1 on webhook service [8388](https://github.com/longhorn/longhorn/issues/8388) - @ChanYiLin @roger-ryao
- [BACKPORT][v1.6.2][BUG] longhorn-manager build failed [8410](https://github.com/longhorn/longhorn/issues/8410) - @yangchiu @mantissahz
- [BACKPORT][v1.6.2][BUG] RWX volume is hang on Photon OS [8279](https://github.com/longhorn/longhorn/issues/8279) - @yangchiu @PhanLe1010

### Misc
- [BACKPORT][v1.6.2]DOCS - Incorrect documentation on pre-upgrade checker configuration [8342](https://github.com/longhorn/longhorn/issues/8342) - @yangchiu

## Contributors
- @ChanYiLin 
- @PhanLe1010 
- @a110605 
- @c3y1huang 
- @chriscchien 
- @derekbit 
- @ejweber 
- @forbesguthrie 
- @innobead 
- @james-munson 
- @jillian-maroket 
- @mantissahz
- @rebeccazzzz  
- @roger-ryao 
- @shuo-wu 
- @yangchiu 
