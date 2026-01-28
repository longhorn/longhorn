# Longhorn v1.10.2 Release Notes

Longhorn 1.10.2 introduces several improvements and bug fixes that are intended to improve system quality, resilience, stability and security.

We welcome feedback and contributions to help continuously improve Longhorn.

For terminology and context on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

## Important Fixes

This release includes several critical stability fixes.

### RWX Volume Unavailable After Node Drain

Fixed a race condition where **ReadWriteMany (RWX) volumes** could remain in the *attaching* state after node drains, causing workloads to become unavailable.

For more details, see [Issue #12231](https://github.com/longhorn/longhorn/issues/12231).

### Encrypted Volume Cannot Be Expanded Online

Fixed an issue where online expansion of encrypted volumes did not propagate the new size to the dm-crypt device.

For more details, see [Issue #12368](https://github.com/longhorn/longhorn/issues/12368).

### Cloned Volume Cannot Be Attached to Workload

Fixed a bug where cloned volumes could fail to reach a healthy state, preventing attachment to workloads.

For more details, see [Issue #12208](https://github.com/longhorn/longhorn/issues/12208).

### Block Mode Volume Migration Stuck

Fixed a regression in block-mode volume migrations where newly created replicas could incorrectly inherit the `lastFailedAt` timestamp from source replicas, causing repeated deletion and blocking migration completion.

For more details, see [Issue #12312](https://github.com/longhorn/longhorn/issues/12312).

### Replica Auto Balance Disk Pressure Threshold Stalled

Fixed an issue where replica auto-balance under disk pressure could be blocked if stopped volumes were present on the disk.

For more details, see [Issue #12334](https://github.com/longhorn/longhorn/issues/12334).

### Replicas Accumulate During Engine Upgrade

Fixed a bug where temporary replicas could accumulate during engine upgrade. High etcd latency could cause new replicas to fail verification, leading to accumulation over multiple reconciliation cycles.

For more details, see [Issue #12115](https://github.com/longhorn/longhorn/issues/12115).

### Potential Client Connection and Context Leak

Fixed potential context leaks in the instance manager client and backing image manager client, improving stability and preventing resource exhaustion.

For more details, see [Issue #12200](https://github.com/longhorn/longhorn/issues/12200) and [Issue #12195](https://github.com/longhorn/longhorn/issues/12195).

### Replica Node Level Soft Anti-Affinity Ignored

Fixed a bug of replica scheduling loop where replicas could be scheduled onto nodes that already host a replica, even when *Replica Node-Level Soft Anti-Affinity* was disabled.

For more details, see [Issue #12251](https://github.com/longhorn/longhorn/issues/12251).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.10.2.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.10.2/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.9.x to v1.10.2.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.10.2/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Feature

- [BACKPORT][v1.10.2][FEATURE] Inherit namespace for longhorn-share-manager in FastFailover mode [12245](https://github.com/longhorn/longhorn/issues/12245) - @yangchiu
- [BACKPORT][v1.10.2][FEATURE] [Dependency] aws-sdk-go v1.55.7 is EOL as of 2025-07-31 — plan to migrate to v2? [12181](https://github.com/longhorn/longhorn/issues/12181) - @mantissahz @roger-ryao

### Improvement

- [BACKPORT][v1.10.2][IMPROVEMENT] Fix V2 Volume CSI Clone Slowness Caused by VolumeAttachment Webhook Blocking [12329](https://github.com/longhorn/longhorn/issues/12329) - @PhanLe1010 @roger-ryao

### Bug

- [BACKPORT][v1.10.2][BUG]  `instance-manager` on nodes that don't have hard or solid state disk DDOSing cluster DNS server with TXT query  `_grpc_config.localhost` [12536](https://github.com/longhorn/longhorn/issues/12536) - @COLDTURNIP @chriscchien
- [BACKPORT] Replica rebuild, clone and restore fail, traffic being sent to HTTP proxy [12518](https://github.com/longhorn/longhorn/issues/12518) - @yangchiu @derekbit
- [BACKPORT][v1.10.2][BUG] Healthy replica could be deleted unexpectedly after reducing volume's number of replicas [12512](https://github.com/longhorn/longhorn/issues/12512) - @yangchiu @shuo-wu
- [BACKPORT][v1.10.2][BUG] Data locality enabled volume fails to remove an existing running replica after numberOfReplicas reduced [12509](https://github.com/longhorn/longhorn/issues/12509) - @derekbit @chriscchien
- [BACKPORT][v1.10.2][BUG] System backup may fail to be created or deleted [12479](https://github.com/longhorn/longhorn/issues/12479) - @yangchiu @mantissahz
- [BACKPORT][v1.10.2][BUG] Some default settings in questions.yaml are placed incorrectly. [12222](https://github.com/longhorn/longhorn/issues/12222) - @derekbit @roger-ryao
- [BACKPORT][v1.10.2][BUG] Auto balance feature may lead to volumes falling into a replica deletion-recreation loop [12482](https://github.com/longhorn/longhorn/issues/12482) - @shuo-wu @roger-ryao
- [BACKPORT][v1.10.2][BUG] Single replica volume could get stuck in attaching/detaching loop after the replica node rebooted [12494](https://github.com/longhorn/longhorn/issues/12494) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.10.2][BUG] Potential Instance Manager Client Context Leak [12200](https://github.com/longhorn/longhorn/issues/12200) - @derekbit @chriscchien
- [BACKPORT][v1.10.2][BUG] SnapshotBack proxy request might be sent to incorrect instance-manager pod [12476](https://github.com/longhorn/longhorn/issues/12476) - @derekbit @chriscchien
- [BACKPORT][v1.10.2][BUG] unknown OS condition in node CR is not properly removed during upgrade [12451](https://github.com/longhorn/longhorn/issues/12451) - @COLDTURNIP @roger-ryao
- [BACKPORT][v1.10.2][BUG] RWX volume becomes unavailable after drain node [12231](https://github.com/longhorn/longhorn/issues/12231) - @yangchiu @mantissahz
- [BACKPORT][v1.10.2][BUG] mounting error is not properly hanedled during CSI node publish volume [12382](https://github.com/longhorn/longhorn/issues/12382) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.10.2][BUG] Encrypted Volume Cannot Be Expanded Online [12368](https://github.com/longhorn/longhorn/issues/12368) - @yangchiu @mantissahz
- [BACKPORT][v1.10.2][BUG] The auo generated backing image pod name is complained by kubelet [12357](https://github.com/longhorn/longhorn/issues/12357) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.10.2][BUG] `tests.test_cloning.test_cloning_basic` fails at  msater-head [12342](https://github.com/longhorn/longhorn/issues/12342) - @c3y1huang
- [BACKPORT][v1.10.2][Bug] A cloned volume cannot be attached to a workload [12208](https://github.com/longhorn/longhorn/issues/12208) - @yangchiu @PhanLe1010
- [BACKPORT][v1.10.2][BUG] Block Mode Volume Migration Stuck [12312](https://github.com/longhorn/longhorn/issues/12312) - @COLDTURNIP @yangchiu @shuo-wu
- [BACKPORT][v1.10.2][BUG] Replica auto balance disk pressure threshold stalled with stopped volumes [12334](https://github.com/longhorn/longhorn/issues/12334) - @c3y1huang @chriscchien
- [BACKPORT][v1.10.2][BUG] short name mode is enforcing, but image name longhornio/longhorn-manager:v1.10. │ │ 0 returns ambiguous list [12270](https://github.com/longhorn/longhorn/issues/12270) - @yangchiu
- [BACKPORT][v1.10.2][BUG] Replicas accumulate during engine upgrade [12115](https://github.com/longhorn/longhorn/issues/12115) - @c3y1huang @chriscchien
- [BACKPORT][v1.10.2][BUG] Potential BackingImageManagerClient Connection and Context Leak [12195](https://github.com/longhorn/longhorn/issues/12195) - @derekbit @chriscchien
- [BACKPORT][v1.10.2][BUG] Longhorn ignores `Replica Node Level Soft Anti-Affinity` when auto balance is set to `best-effort` [12251](https://github.com/longhorn/longhorn/issues/12251) - @c3y1huang @chriscchien
- [BACKPORT][v1.10.2][BUG] invalid memory address or nil pointer dereference (again) [12234](https://github.com/longhorn/longhorn/issues/12234) - @chriscchien @bachmanity1
- [BACKPORT][v1.10.2][BUG] Request Header Or Cookie Too Large in Web UI with OIDC auth [12213](https://github.com/longhorn/longhorn/issues/12213) - @chriscchien @houhoucoop

## Contributors

- @COLDTURNIP
- @PhanLe1010
- @bachmanity1
- @c3y1huang
- @chriscchien
- @derekbit
- @houhoucoop
- @innobead
- @mantissahz
- @rebeccazzzz
- @roger-ryao
- @shuo-wu
- @sushant-suse
- @yangchiu