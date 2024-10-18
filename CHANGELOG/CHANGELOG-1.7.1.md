## Longhorn v1.7.1 Release Notes

Longhorn 1.7.1 introduces several improvements and bug fixes that are intended to improve system quality, resilience, and stability.

The Longhorn team appreciates your contributions and expects to receive feedback regarding this release.

> [!NOTE]
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before installing Longhorn v1.7.1.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.7.1/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before upgrading from Longhorn v1.6.x or v1.7.x (< v1.7.0) to v1.7.1.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.7.1/deploy/upgrade/) in the Longhorn documentation.

## Deprecation & Incompatibilities

The functionality of the [environment check script](https://github.com/longhorn/longhorn/blob/v1.7.x/scripts/environment_check.sh) overlaps with that of the Longhorn CLI, which is available starting with v1.7.0. Because of this, the script is deprecated in v1.7.0 and is scheduled for removal in v1.8.0.

For information about important changes, including feature incompatibility, deprecation, and removal, see [Important Notes](https://longhorn.io/docs/1.7.1/important-notes/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Improvement

- [BACKPORT][v1.7.1][IMPROVEMENT] Longhorn CLI should install `cryptsetup` [9316](https://github.com/longhorn/longhorn/issues/9316) - @mantissahz @roger-ryao
- [BACKPORT][v1.7.1][IMPROVEMENT] Resilience handling for the last replica timeout [9275](https://github.com/longhorn/longhorn/issues/9275) - @ejweber @chriscchien
- [BACKPORT][v1.7.1][IMPROVEMENT] Check kernel module `dm_crypt` on host machines [9310](https://github.com/longhorn/longhorn/issues/9310) - @mantissahz


### Bug
- [BACKPORT][v1.7.1][BUG] Fix security issues in v1.7.1 RC images [9363](https://github.com/longhorn/longhorn/issues/9363) - @c3y1huang
- [BACKPORT][v1.7.1][BUG] should set backing image minNumberOfCopies to 1 when upgrading Longhorn [9353](https://github.com/longhorn/longhorn/issues/9353) - @ChanYiLin @chriscchien
- [BACKPORT][v1.7.1][BUG] System Backup Fails and DR Volume Enters Attach-Detach Loop When Volume Backup Policy is Set to `Always` [9333](https://github.com/longhorn/longhorn/issues/9333) - @c3y1huang @roger-ryao
- [BACKPORT][v1.7.1][BUG] [Backupstore] Need to close the reader after downloading files for the Azure backup store driver. [9282](https://github.com/longhorn/longhorn/issues/9282) - @yangchiu @mantissahz
- [BACKPORT][v1.7.1][BUG] Unable to access azurite backup store by DNS hostname [9341](https://github.com/longhorn/longhorn/issues/9341) - @mantissahz
- [BACKPORT][v1.7.1][BUG] v1 volume replica rebuild fail after upgrade from v1.7.0 to v1.7.1-rc1 [9332](https://github.com/longhorn/longhorn/issues/9332) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.7.1][BUG] v2-data-engine setting validator doesn't take disabled nodes into account when checking hugepages [9320](https://github.com/longhorn/longhorn/issues/9320) - @tserong @roger-ryao
- [BACKPORT][v1.7.1][BUG] Some volumes stuck in "Attaching" state after upgrade to 1.7.0 [9270](https://github.com/longhorn/longhorn/issues/9270) - @ChanYiLin @roger-ryao
- [BACKPORT][v1.7.1][BUG] error logs appeared in uninstallation job [9304](https://github.com/longhorn/longhorn/issues/9304) - @ChanYiLin @chriscchien
- [BACKPORT][v1.7.1][BUG] Incorrect NFS endpoint after enable/disable storage network for RWX volume [9273](https://github.com/longhorn/longhorn/issues/9273) - @Vicente-Cheng @roger-ryao
- [BACKPORT][v1.7.1][BUG] Volume stuck in degraded [9285](https://github.com/longhorn/longhorn/issues/9285) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.7.1][BUG] LH fails silently when node has attached volumes [9210](https://github.com/longhorn/longhorn/issues/9210) - @ejweber @chriscchien

## Contributors
- @ChanYiLin 
- @PhanLe1010 
- @Vicente-Cheng 
- @c3y1huang 
- @chriscchien 
- @ejweber 
- @innobead 
- @mantissahz 
- @roger-ryao 
- @tserong 
- @yangchiu
- @jillian-maroket 
- @yardenshoham
- @rebeccazzzz
- @forbesguthrie
- @asettle