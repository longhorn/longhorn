# Longhorn v1.11.2 Release Notes

Longhorn 1.11.2 introduces several improvements and bug fixes that are intended to improve system quality, resilience, stability and security.

We welcome feedback and contributions to help continuously improve Longhorn.

For terminology and context on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

## Important Fixes

This release includes several critical stability fixes.

### Replica rebuild progress fix

Resolved an issue where replica rebuild progress could exceed 100% under unstable network conditions. Progress reporting is now capped at 100%.

For more details, see [#12949](https://github.com/longhorn/longhorn/issues/12949).

### CSIStorageCapacity scheduling enhancement

Introduced a new setting to control CSIStorageCapacity reporting. Previously, compute nodes without Longhorn disks incorrectly reported 0 capacity, breaking WaitForFirstConsumer scheduling. With this enhancement, capacity tracking can be configured to avoid rejecting compute nodes in separated compute/storage architectures.

For more details, see [#12807](https://github.com/longhorn/longhorn/issues/12807).

## Improvement

### Manager memory optimization

Optimized longhorn‑manager Pod informer caching to reduce cluster‑wide memory usage.

For more details, see [#12771](https://github.com/longhorn/longhorn/issues/12771).

### 

## Installation

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.11.2.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.11.2/deploy/install/) in the Longhorn documentation.

## Upgrade

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.10.x or v1.11.0 to v1.11.2.**

> [!IMPORTANT]
**Users on v1.11.0 who experienced the memory leaks of longhorn-instance-manager pods [12575](https://github.com/longhorn/longhorn/issues/12575) are highly encouraged to upgrade to v1.11.2 to receive the permanent fix for the proxy connection leaks.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.11.2/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues in this release

### Improvement

- [BACKPORT][v1.11.2][IMPROVEMENT] Reduce longhorn-manager memory usage by optimizing cluster-wide informer caching [12819](https://github.com/longhorn/longhorn/issues/12819) - @hookak @roger-ryao

### Bug

- [BACKPORT][v1.11.2][BUG] Test case `test_storage_capacity_aware_pod_scheduling` fails [13006](https://github.com/longhorn/longhorn/issues/13006) - @yangchiu @bachmanity1
- [BACKPORT][v1.11.2][BUG] Replica Auto-Balance Causes Infinite Replica Scheduling Loop [12928](https://github.com/longhorn/longhorn/issues/12928) - @yangchiu @shuo-wu
- [BACKPORT][v1.11.2][BUG] CSIStorageCapacity reports 0 for compute nodes without Longhorn disks, breaking WaitForFirstConsumer scheduling [12918](https://github.com/longhorn/longhorn/issues/12918) - @chriscchien @bachmanity1
- [BACKPORT][v1.11.2][BUG] Replica rebuild progress can go over 100% [12952](https://github.com/longhorn/longhorn/issues/12952) - @yangchiu @davidcheng0922
- [BACKPORT][v1.11.2][BUG] Node exhaustion caused by backup inspect buildup induced due to NFS latency [12945](https://github.com/longhorn/longhorn/issues/12945) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.11.2][BUG] Failed to collect health data for block disk (AIO) when disk path is a /dev/disk/by-id symlink [12911](https://github.com/longhorn/longhorn/issues/12911) - @yangchiu @hookak
- [BACKPORT][v1.11.2][BUG] "snapshot becomes not ready to use" Warning events emitted during expected auto-cleanup after backup [12856](https://github.com/longhorn/longhorn/issues/12856) - @EpochBoy @yangchiu

### Stability

- [BACKPORT][v1.11.1][BUG] Potential NEP in Volume Metrics Collector [12733](https://github.com/longhorn/longhorn/issues/12733) - @derekbit @chriscchien

## Contributors

- @COLDTURNIP 
- @bachmanity1 
- @chriscchien 
- @davidcheng0922 
- @derekbit
- @EpochBoy
- @github-actions[bot] 
- @hookak 
- @innobead 
- @roger-ryao 
- @shuo-wu 
- @yangchiu 
- @sushant-suse
- @rebeccazzzz
- @forbesguthrie
