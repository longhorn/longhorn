## Longhorn v1.9.1 Release Notes

Longhorn 1.9.1 introduces several improvements and bug fixes that are intended to improve system quality, resilience, stability and security.

The Longhorn team appreciates your contributions and expects to receive feedback regarding this release.

> [!NOTE]
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.9.1.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.9.1/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.8.x or v1.9.x (< v1.9.1) to v1.9.1.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.9.1/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Feature

- [BACKPORT][v1.9.1][FEATURE] Standardized way to override container image registry [11068](https://github.com/longhorn/longhorn/issues/11068) - @marcosbc @roger-ryao
- [BACKPORT][v1.9.1][FEATURE] Standardized way to specify image pull secrets [11072](https://github.com/longhorn/longhorn/issues/11072) - @marcosbc @chriscchien

### Improvement

- [BACKPORT][v1.9.1][IMPROVEMENT] Remove the Patch `preserveUnknownFields: false` for CRDs [11280](https://github.com/longhorn/longhorn/issues/11280) - @derekbit @chriscchien
- [BACKPORT][v1.9.1][IMPROVEMENT] Improve the disk space un-schedulable condition message [11212](https://github.com/longhorn/longhorn/issues/11212) - @yangchiu @davidcheng0922
- [BACKPORT][v1.9.1][IMPROVEMENT] Improve the condition message of engine image check [11196](https://github.com/longhorn/longhorn/issues/11196) - @derekbit @chriscchien
- [BACKPORT][v1.9.1][IMPROVEMENT] Improve the logging when detecting multiple backup volumes of the same volume on the same backup target [11225](https://github.com/longhorn/longhorn/issues/11225) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.9.1][IMPROVEMENT] extra invalid BackupVolumeCR may be created during cluster split-brain [11168](https://github.com/longhorn/longhorn/issues/11168) - @mantissahz @roger-ryao
- [BACKPORT][v1.9.1][IMPROVEMENT] Full replica rebuilding when a node goes down for a while and then comes back [11069](https://github.com/longhorn/longhorn/issues/11069) - @mantissahz
- [BACKPORT][v1.9.1][IMPROVEMENT] Adding retry logic for longhorn-csi-plugin when it trying to contact the longhorn-manager pods [10914](https://github.com/longhorn/longhorn/issues/10914) - @PhanLe1010 @roger-ryao

### Bug

- [BACKPORT][v1.9.1][BUG] Incorrect value of `remove-snapshots-during-filesystem-trim` in longhorn chart/values.yaml [11266](https://github.com/longhorn/longhorn/issues/11266) - @derekbit @chriscchien
- [BACKPORT][v1.9.1][BUG] privateRegistry.registryUrl does not work when overriding specific image registries [11258](https://github.com/longhorn/longhorn/issues/11258) - @marcosbc @chriscchien
- [BACKPORT][v1.9.1][BUG]  system backup error [11235](https://github.com/longhorn/longhorn/issues/11235) - @c3y1huang @roger-ryao
- [BACKPORT][v1.9.1][BUG] Volume expansion fails with "unsupported disk encryption format ext4" [11184](https://github.com/longhorn/longhorn/issues/11184) - @COLDTURNIP @mantissahz @roger-ryao
- [BACKPORT][v1.9.1][BUG] The Backup YAML example in the Longhorn doc does not work [11217](https://github.com/longhorn/longhorn/issues/11217) - @mantissahz @nzhan126
- [BACKPORT][v1.9.1][BUG] CSI Plugin restart triggers unintended restart of migratable RWX volume workloads [11164](https://github.com/longhorn/longhorn/issues/11164) - @c3y1huang @roger-ryao
- [BACKPORT][v1.9.1][BUG] in the browser UI: Volume -> Clone Volume results in the broken browser page [11180](https://github.com/longhorn/longhorn/issues/11180) - @houhoucoop @roger-ryao
- [BACKPORT][v1.9.1][BUG] Test case `test_engine_image_not_fully_deployed_perform_volume_operations` failed: unable to detach a volume [10917](https://github.com/longhorn/longhorn/issues/10917) - @mantissahz @chriscchien
- [BACKPORT][v1.9.1][BUG] Creating support-bundle panic NPE [11170](https://github.com/longhorn/longhorn/issues/11170) - @c3y1huang @roger-ryao
- [BACKPORT][v1.9.1][BUG] Unable to Build Longhorn-Share-Manager Image Due to CMAKE Compatibility [11162](https://github.com/longhorn/longhorn/issues/11162) - @derekbit @roger-ryao
- [BACKPORT][v1.9.1][BUG] Recurring jobs fail when assigned to default group [11020](https://github.com/longhorn/longhorn/issues/11020) - @c3y1huang @chriscchien
- [BACKPORT][v1.9.1][BUG] SPDK API bdev_lvol_detach_parent does not work as expected [11047](https://github.com/longhorn/longhorn/issues/11047) - @DamiaSan @roger-ryao
- [BACKPORT][v1.9.1][BUG] unable to clean up the backing image volume replica after node eviction [11056](https://github.com/longhorn/longhorn/issues/11056) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.9.1][BUG] backing image volume replica NPE crash during evicting node [11035](https://github.com/longhorn/longhorn/issues/11035) - @COLDTURNIP @chriscchien

## Misc

- [HOTFIX] Create hotfixed image for longhorn-manager:v1.9.0 [11140](https://github.com/longhorn/longhorn/issues/11140) - @derekbit @chriscchien
- [BACKPORT][v1.9.1][TASK] Ensure support-bundle-kit builds use vendored dependencies [11118](https://github.com/longhorn/longhorn/issues/11118) - @yangchiu @c3y1huang

## New Contributors

- @davidcheng0922 
- @marcosbc 
- @nzhan126 
 
## Contributors

- @COLDTURNIP 
- @DamiaSan 
- @PhanLe1010 
- @c3y1huang 
- @chriscchien 
- @derekbit 
- @houhoucoop 
- @innobead 
- @mantissahz 
- @roger-ryao 
- @yangchiu 
- @sushant-suse
- @rebeccazzzz
- @forbesguthrie
- @asettle