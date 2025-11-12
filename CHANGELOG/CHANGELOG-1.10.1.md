# Longhorn v1.10.1 Release Notes

Longhorn 1.10.1 introduces several improvements and bug fixes that are intended to improve system quality, resilience, stability and security.

We welcome feedback and contributions to help continuously improve Longhorn.

For terminology and context on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

## Important Fixes

This release includes several critical stability and performance improvements:

### Goroutine Leak in Instance Manager (V2 Data Engine)

Fixed a goroutine leak in the instance manager when using the V2 data engine. This issue could lead to increased memory usage and potential stability problems over time.

For more details, see [Issue #11962](https://github.com/longhorn/longhorn/issues/11962).

### V2 Volume Attachment Failure in Interrupt Mode

Fixed an issue where V2 volumes using interrupt mode with NVMe disks could fail to complete the attachment process, causing volumes to remain stuck in the attaching state indefinitely.

In Longhorn v1.10.0, interrupt mode supports only **AIO disks**. Interrupt mode for **NVMe disks** is supported starting in v1.10.1.

For more details, see [Issue #11816](https://github.com/longhorn/longhorn/issues/11816).

### UI Deployment Failure on IPv4-Only Nodes

Fixed a bug introduced in v1.10.0 where the Longhorn UI failed to deploy on nodes with only IPv4 enabled. The UI now correctly supports IPv4-only configurations without requiring IPv6.

For more details, see [Issue #11875](https://github.com/longhorn/longhorn/issues/11875).

### Share Manager Excessive Memory Usage

Fixed excessive memory consumption in the share manager for RWX (ReadWriteMany) volumes. The component now maintains stable memory usage under normal operation.

For more details, see [Issue #12043](https://github.com/longhorn/longhorn/issues/12043).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.10.1.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.10.0/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.9.x to v1.10.1.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.10.0/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Improvement

- [BACKPORT][v1.10.1][IMPROVEMENT] The `auto-delete-pod-when-volume-detached-unexpectedly` should only focus on the kubernetes builtin workload. [12125](https://github.com/longhorn/longhorn/issues/12125) - @derekbit @chriscchien
- [BACKPORT][v1.10.1][IMPROVEMENT] `CSIStorageCapacity` objects must show schedulable (allocatable) capacity [12036](https://github.com/longhorn/longhorn/issues/12036) - @chriscchien @bachmanity1
- [BACKPORT][v1.10.1][IMPROVEMENT] improve error logging for failed mounting during node publish volume [12033](https://github.com/longhorn/longhorn/issues/12033) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.10.1][IMPROVEMENT] Improve Helm Chart defaultSettings handling with automatic quoting and multi-type support [12020](https://github.com/longhorn/longhorn/issues/12020) - @derekbit @chriscchien
- [BACKPORT][v1.10.1][IMPROVEMENT] Avoid repeat engine restart when there are replica unavailable during migration [11945](https://github.com/longhorn/longhorn/issues/11945) - @yangchiu @shuo-wu
- [BACKPORT][v1.10.1][IMPROVEMENT] Adjust maximum of GuaranteedInstanceManagerCPU to a big value [11968](https://github.com/longhorn/longhorn/issues/11968) - @mantissahz
- [BACKPORT][v1.10.1][IMPROVEMENT] Add usage metrics for Longhorn installation variant [11795](https://github.com/longhorn/longhorn/issues/11795) - @derekbit

### Bug

- [BACKPORT][v1.10.1][BUG] Backup target metric is broken [12089](https://github.com/longhorn/longhorn/issues/12089) - @mantissahz @roger-ryao
- [BACKPORT][v1.10.1][BUG] Backing image download gets stuck after network disconnection [12094](https://github.com/longhorn/longhorn/issues/12094) - @COLDTURNIP @chriscchien
- [BACKPORT][v1.10.1][BUG] panic: runtime error: invalid memory address or nil pointer dereference [signal SIGSEGV: segmentation violation code=0x1 at longhorn-engine/pkg/controller/control.go:218 +0x2de [12088](https://github.com/longhorn/longhorn/issues/12088) - @roger-ryao
- [BACKPORT][v1.10.1][BUG] Unable to complete uninstallation due to the remaining backuptarget [11964](https://github.com/longhorn/longhorn/issues/11964) - @mantissahz @roger-ryao
- [BACKPORT][v1.10.1][BUG] share-manager excessive memory usage [12043](https://github.com/longhorn/longhorn/issues/12043) - @derekbit @chriscchien
- [BACKPORT][v1.10.1][BUG] NVME disk not found in v2 data engine (failed to find device for BDF) [12029](https://github.com/longhorn/longhorn/issues/12029) - @derekbit @roger-ryao
- [BACKPORT][v1.10.1][BUG] NPE error during recurring job execution [11926](https://github.com/longhorn/longhorn/issues/11926) - @yangchiu @shuo-wu
- [BACKPORT][v1.10.1][BUG] v2 volume creation failed on talos nodes [12026](https://github.com/longhorn/longhorn/issues/12026) - @c3y1huang @chriscchien
- [BACKPORT][v1.10.1][BUG] mounting error is not properly hanedled during CSI node publish volume [12008](https://github.com/longhorn/longhorn/issues/12008) - @COLDTURNIP
- [BACKPORT][v1.10.1][BUG] Adding multiple disks to the same node concurrently may occasionally fail [12018](https://github.com/longhorn/longhorn/issues/12018) - @davidcheng0922 @roger-ryao
- [BUG] upgrading from 1.9.1 to 1.10.0 fails due to old resources still being in v1beta1 [11886](https://github.com/longhorn/longhorn/issues/11886) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.10.1][BUG] DR volume gets stuck in `unknown` state if engine image is deleted from the attached node [11998](https://github.com/longhorn/longhorn/issues/11998) - @yangchiu @shuo-wu
- [BACKPORT][v1.10.1][BUG] Volume gets stuck in `attaching` state if engine image image is not deployed on one of nodes [11996](https://github.com/longhorn/longhorn/issues/11996) - @yangchiu @shuo-wu
- [BACKPORT][v1.10.1][BUG] Unable to re-add block-type disks by BDF after re-enable v2 data engine [12000](https://github.com/longhorn/longhorn/issues/12000) - @yangchiu @davidcheng0922
- [BACKPORT][v1.10.1][BUG] `test_system_backup_and_restore` test case failed on master-head [12005](https://github.com/longhorn/longhorn/issues/12005) - @derekbit @chriscchien
- [BACKPORT][v1.10.1][BUG] Fix SPDK v25.05 CVE issue [11970](https://github.com/longhorn/longhorn/issues/11970) - @derekbit @roger-ryao
- [BACKPORT][v1.10.1][BUG] V2 volume stuck in volume attachment (V2 interrupt mode) [11976](https://github.com/longhorn/longhorn/issues/11976) - @c3y1huang @chriscchien
- [BACKPORT][v1.10.1][BUG] RWX volume causes process uninterruptible sleep [11958](https://github.com/longhorn/longhorn/issues/11958) - @COLDTURNIP @chriscchien
- [BACKPORT][v1.10.1][BUG] longhorn-manager fails to start after upgrading from 1.9.2 to 1.10.0 [11865](https://github.com/longhorn/longhorn/issues/11865) - @derekbit @roger-ryao
- [BACKPORT][v1.10.1][BUG] Block disk deletion fails without error message [11954](https://github.com/longhorn/longhorn/issues/11954) - @davidcheng0922 @roger-ryao
- [BACKPORT][v1.10.1][BUG] Goroutine leak in instance-manager when using v2 data engine [11962](https://github.com/longhorn/longhorn/issues/11962) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.10.1][BUG] invalid memory address or nil pointer dereference [11942](https://github.com/longhorn/longhorn/issues/11942) - @bachmanity1 @roger-ryao
- [BACKPORT][v1.10.1][BUG] csi-provisioner silently fails to create CSIStorageCapacity if dataEngine parameter is missing [11918](https://github.com/longhorn/longhorn/issues/11918) - @yangchiu @bachmanity1
- [BACKPORT][v1.10.1][BUG] longhorn-engine's UI panics [11901](https://github.com/longhorn/longhorn/issues/11901) - @derekbit @chriscchien
- [BACKPORT][v1.10.1][BUG] Volume is unable to upgrade if the number of active replicas is larger than `volumme.spec.numberOfReplicas` [11895](https://github.com/longhorn/longhorn/issues/11895) - @yangchiu @derekbit
- [BACKPORT][v1.10.1][BUG] UI fails to deploy when only IPv4 is enabled on nodes with v1.10.0 version [11875](https://github.com/longhorn/longhorn/issues/11875) - @yangchiu @c3y1huang
- [BACKPORT][v1.10.1][BUG] Unable to detach a v2 volume after labeling `disable-v2-data-engine=true` [11801](https://github.com/longhorn/longhorn/issues/11801) - @mantissahz

### Misc

- [BACKPORT][v1.10.1][REFACTOR] SAST checks for UI component [11992](https://github.com/longhorn/longhorn/issues/11992) - @chriscchien
- [HOTFIX] Create hotfixed image for longhorn-manager:v1.10.0 [11951](https://github.com/longhorn/longhorn/issues/11951) - @c3y1huang @roger-ryao

## Contributors

- @COLDTURNIP
- @PhanLe1010
- @bachmanity1
- @c3y1huang
- @chriscchien
- @davidcheng0922
- @derekbit
- @forbesguthrie
- @innobea
- @mantissahz
- @rebeccazzzz
- @roger-ryao
- @sushant-suse
- @shuo-wu
- @yangchiu
