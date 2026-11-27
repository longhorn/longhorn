# Longhorn v1.10.5 Release Notes

Longhorn 1.10.5 introduces several improvements and bug fixes that are intended to improve system quality, resilience, stability and security.

We welcome feedback and contributions to help continuously improve Longhorn.

For terminology and context on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.10.5.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/archives/1.10.5/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.9.x to v1.10.5.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/archives/1.10.5/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Bug
- [BUG] `v1.10.5-rc1` Support bundle manager pod fails with ImagePullBackOff due to non-existent image `longhornio/support-bundle-kit:v0.0.99` [14647](https://github.com/longhorn/longhorn/issues/14647) - @c3y1huang @roger-ryao
- [BACKPORT][v1.10.5][BUG] expanding the volume fails [13385](https://github.com/longhorn/longhorn/issues/13385) - @chriscchien

### Misc
- [BACKPORT][v1.10.5][TASK] Add Helm chart image HIP-0015 annotations [14266](https://github.com/longhorn/longhorn/issues/14266) - @roger-ryao @carterli0407-cell

## Contributors

- @c3y1huang 
- @carterli0407-cell 
- @chriscchien 
- @innobead 
- @roger-ryao 
- @yangchiu
- @sushant-suse
- @rebeccazzzz
- @asettle
