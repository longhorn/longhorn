## Release Note

### **v1.5.3 released!** 🎆

This release focuses on resolving a regression issue from v1.5.2 related to volume encryption, along with a few other fixes and improvements. Please try it and provide feedback. Thanks for all the contributions!

> For the definition of stable or latest release, please check [here](https://github.com/longhorn/longhorn#releases).

## Installation

> **Please ensure your Kubernetes cluster is at least v1.21 before installing v1.5.3.**

Longhorn supports three installation ways including Rancher App Marketplace, Kubectl, and Helm. Follow the installation instructions [here](https://longhorn.io/docs/1.5.3/deploy/install/).

## Upgrade

> **Please read the [important notes](https://longhorn.io/docs/1.5.3/deploy/important-notes/) first and ensure your Kubernetes cluster is at least v1.21 before upgrading to Longhorn v1.5.3 from v1.4.x/v1.5.x, which are only supported source versions.**

Follow the upgrade instructions [here](https://longhorn.io/docs/1.5.3/deploy/upgrade/).

## Deprecation & Incompatibilities

N/A

## Known Issues after Release

Please follow up on [here](https://github.com/longhorn/longhorn/wiki/Outstanding-Known-Issues-of-Releases) about any outstanding issues found after this release.

## Resolved Issues

### Improvement
- [IMPROVEMENT] Add PVC namespace to longhorn_volume metrics [7077](https://github.com/longhorn/longhorn/issues/7077) - @mantissahz @roger-ryao @antoninferrand

### Resilience
- [BUG] A race after a node reboot leads to I/O errors with migratable volumes [6961](https://github.com/longhorn/longhorn/issues/6961) - @yangchiu @ejweber

### Bug
- [BUG] Share manager unmount/unexport RWX volume timing issue [7106](https://github.com/longhorn/longhorn/issues/7106) - @yangchiu @derekbit
- [BUG] `backing-image-manager-` hostPath selection exception [7062](https://github.com/longhorn/longhorn/issues/7062) - @ChanYiLin @nitendra-suse
- [BUG] Failing to mount encrypted volumes v1.5.2 [7045](https://github.com/longhorn/longhorn/issues/7045) - @derekbit @nitendra-suse
- [BUG] Fix RWX volume mount option typo in v1.5.x [7104](https://github.com/longhorn/longhorn/issues/7104) - @yangchiu @derekbit
- [BUG] Upgrade from v1.5.2 to v1.5.3-rc1 failed if there's an attached v1 volume and a detached v2 volume [7094](https://github.com/longhorn/longhorn/issues/7094) - @derekbit

## Contributors
- @ChanYiLin 
- @antoninferrand 
- @derekbit 
- @ejweber 
- @innobead 
- @mantissahz 
- @nitendra-suse 
- @roger-ryao 
- @yangchiu 
