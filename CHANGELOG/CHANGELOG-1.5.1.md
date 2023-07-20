## Release Note
### **v1.5.1 released!** 🎆

Longhorn v1.5.1 is the latest version of Longhorn 1.5.
This release introduces bug fixes as described below about 1.5.0 upgrade issues, stability, troubleshooting and so on. Please try it and feedback. Thanks for all the contributions!

> For the definition of stable or latest release, please check [here](https://github.com/longhorn/longhorn#releases).

## Installation

> **Please ensure your Kubernetes cluster is at least v1.21 before installing v1.5.1.**

Longhorn supports 3 installation ways including Rancher App Marketplace, Kubectl, and Helm. Follow the installation instructions [here](https://longhorn.io/docs/1.5.1/deploy/install/).

## Upgrade

> **Please read the [important notes](https://longhorn.io/docs/1.5.1/deploy/important-notes/) first and ensure your Kubernetes cluster is at least v1.21 before upgrading to Longhorn v1.5.1 from v1.4.x/v1.5.0, which are only supported source versions.**

Follow the upgrade instructions [here](https://longhorn.io/docs/1.5.1/deploy/upgrade/).

## Deprecation & Incompatibilities

N/A

## Known Issues after Release

Please follow up on [here](https://github.com/longhorn/longhorn/wiki/Outstanding-Known-Issues-of-Releases) about any outstanding issues found after this release.

## Improvement
  
  - [IMPROVEMENT] Implement/fix the unit tests of Volume Attachment and volume controller ([6005](https://github.com/longhorn/longhorn/issues/6005)) - @PhanLe1010
  - [QUESTION] Repetitive warnings and errors in a new longhorn setup ([6257](https://github.com/longhorn/longhorn/issues/6257)) - @derekbit @c3y1huang @roger-ryao
  
## Resilience
  
  - [BUG] 1.5.0 Upgrade: Longhorn conversion webhook server fails ([6259](https://github.com/longhorn/longhorn/issues/6259)) - @derekbit @roger-ryao
  - [BUG] Race leaves snapshot CRs that cannot be deleted ([6298](https://github.com/longhorn/longhorn/issues/6298)) - @yangchiu @PhanLe1010 @ejweber
  
## Bugs
  
  - [BUG] Engine continues to attempt to rebuild replica while detaching ([6217](https://github.com/longhorn/longhorn/issues/6217)) - @yangchiu @ejweber
  - [BUG] Upgrade to 1.5.0 failed: validator.longhorn.io denied the request if having orphan resources ([6246](https://github.com/longhorn/longhorn/issues/6246)) - @derekbit @roger-ryao
  - [BUG] Unable to receive support bundle from UI when it's large (400MB+) ([6256](https://github.com/longhorn/longhorn/issues/6256)) - @c3y1huang @chriscchien
  - [BUG] Longhorn Manager Pods CrashLoop after upgrade from 1.4.0 to 1.5.0 while backing up volumes ([6264](https://github.com/longhorn/longhorn/issues/6264)) - @ChanYiLin @roger-ryao
  - [BUG] Can not delete type=`bi` VolumeSnapshot if related backing image not exist ([6266](https://github.com/longhorn/longhorn/issues/6266)) - @ChanYiLin @chriscchien
  - [BUG] 1.5.0: AttachVolume.Attach failed for volume, the volume is currently attached to a different node ([6287](https://github.com/longhorn/longhorn/issues/6287)) - @yangchiu @derekbit
  - [BUG] test case test_setting_priority_class failed in master and v1.5.x ([6319](https://github.com/longhorn/longhorn/issues/6319)) - @derekbit @chriscchien
  - [BUG] Unused webhook and recovery backend deployment left in helm chart ([6252](https://github.com/longhorn/longhorn/issues/6252)) - @ChanYiLin @chriscchien
  
## Misc
  
  - [DOC] v1.5.0 additional outgoing firewall ports need to be opened 9501 9502 9503 ([6317](https://github.com/longhorn/longhorn/issues/6317)) - @ChanYiLin @chriscchien
  
## Contributors

- @ChanYiLin
- @PhanLe1010
- @c3y1huang
- @chriscchien
- @derekbit
- @ejweber
- @innobead
- @roger-ryao
- @yangchiu

