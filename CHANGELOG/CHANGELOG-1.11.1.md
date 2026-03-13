# Longhorn v1.11.1 Release Notes

Longhorn v1.11.1 is a patch release that focuses on critical bug fixes, security hardening, and stability improvements for both V1 and V2 data engines. Key highlights include a fix for a significant memory leak in the instance manager and improvements to backup reliability and volume scheduling.

We welcome feedback and contributions to help continuously improve Longhorn.

For terminology and context on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

## Important Fixes

This release includes several critical stability fixes.

### Longhorn workload pods memory leak

Fixed a critical regression where proxy connection leaks in the longhorn-instance-manager pods caused high memory consumption.

For more details, see [#12575](https://github.com/longhorn/longhorn/issues/12575)

### Backup & Restore compatibility fix

Resolved compatibility issues introduced by aws-go-sdk v2, including backups to S3-compatible storage (like Storj or Google Cloud Storage). This fix ensures the completion of large data transfers to remote backup targets with correct authorization.

For more details, see [#12714](https://github.com/longhorn/longhorn/issues/12714) and [12688](https://github.com/longhorn/longhorn/issues/12688)

### V2 Data Engine (SPDK) refinements

Several enhancements were delivered for some V2 Data Engine features, including fast replica rebuild and clone.

For more details, see [#12751](https://github.com/longhorn/longhorn/issues/12751) and [12748](https://github.com/longhorn/longhorn/issues/12748)

### CSI scheduling enhancement

Support CSI topology-aware PV nodeAffinity control.

For more details, see [#12689](https://github.com/longhorn/longhorn/issues/12689) and [12656](https://github.com/longhorn/longhorn/issues/12656)

## Installation

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.11.1.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.11.1/deploy/install/) in the Longhorn documentation.

## Upgrade

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.10.x or v1.11.0 to v1.11.1.**

> [!IMPORTANT]
**Users on v1.11.0 who experienced the memory leaks of longhorn-instance-manager pods [12575](https://github.com/longhorn/longhorn/issues/12575) are highly encouraged to upgrade to v1.11.1 to receive the permanent fix for the proxy connection leaks.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.11.1/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues in this release

### Improvement

- [BACKPORT][v1.11.1][IMPROVEMENT] Ensure V2 Engine ReplicaAdd respects the fast-replica-rebuild-enabled setting [12751](https://github.com/longhorn/longhorn/issues/12751) - @davidcheng0922 @roger-ryao
- [BACKPORT][v1.11.1][IMPROVEMENT] Topology-aware PV nodeAffinity control: allowedTopologies keys + strictTopology [12689](https://github.com/longhorn/longhorn/issues/12689) - @hookak @roger-ryao
- [BACKPORT][v1.11.1][IMPROVEMENT] detailed log for the reason of node controller deleting backing image copies [12585](https://github.com/longhorn/longhorn/issues/12585) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.11.1][IMPROVEMENT] Relax `endpoint-network-for-rwx-volume` validation for migratable block-mode volumes [12711](https://github.com/longhorn/longhorn/issues/12711) - @c3y1huang @chriscchien
- [BACKPORT][v1.11.1][IMPROVEMENT] RBAC permissions for csi-resizer [12694](https://github.com/longhorn/longhorn/issues/12694) - @yangchiu

### Bug

- [BACKPORT][v1.11.1][BUG] Failed replicas accumulate during engine upgrade [12768](https://github.com/longhorn/longhorn/issues/12768) - @davidcheng0922
- [BACKPORT][v1.11.1][BUG] V2 Volume Clone Status is Changed Over Time [12748](https://github.com/longhorn/longhorn/issues/12748) - @davidcheng0922 @roger-ryao
- [BACKPORT][v1.11.1][BUG] Backup to S3 fails at 95% [12714](https://github.com/longhorn/longhorn/issues/12714) - @yangchiu @mantissahz
- [BACKPORT][v1.11.1][BUG] `spdk_tgt` encountered an assertion failure in `longhorn-spdk-helper` during a CI test run [12738](https://github.com/longhorn/longhorn/issues/12738) - @derekbit @roger-ryao
- [BACKPORT][v1.11.1][BUG] Google Cloud Storage (GCS) backup target always fails with SignatureDoesNotMatch due to AWS SDK Go v2 CRC32 checksum incompatibility [12688](https://github.com/longhorn/longhorn/issues/12688) - @mantissahz @chriscchien
- [BACKPORT][v1.11.1][BUG] Enable to set defaultSettings.nodeDiskHealthMonitoring [12730](https://github.com/longhorn/longhorn/issues/12730) - @chriscchien
- [BACKPORT][v1.11.1][BUG] stale name variable in nsmounter get_pid [12704](https://github.com/longhorn/longhorn/issues/12704) - @chriscchien
- [BACKPORT][v1.11.1][BUG] After upgrading to 1.11.0, new persistent volumes have nodeAffinity [12665](https://github.com/longhorn/longhorn/issues/12665) - @chriscchien
- [BACKPORT][v1.11.1][BUG]  Incorrect storage double-counting causes scheduling failure when multiple replicas exist on the same node [12661](https://github.com/longhorn/longhorn/issues/12661) - @yangchiu @davidcheng0922
- [BACKPORT][v1.11.1][BUG] Recreated block disk with same name never becomes schedulable after volume and disk deletion [12641](https://github.com/longhorn/longhorn/issues/12641) - @davidcheng0922
- [BACKPORT][v1.11.1][BUG] Longhorn v1.10 Volume API is not compatible with the v1.8.1 manifest [12618](https://github.com/longhorn/longhorn/issues/12618) - @mantissahz @roger-ryao
- [BACKPORT][v1.11.1][BUG] [v2] Can't use partition as block device [12626](https://github.com/longhorn/longhorn/issues/12626) - @bachmanity1
- [BACKPORT][v1.11.1][BUG] Volume.Spec.CloneMode is empty after upgrading to v1.10.x and following version [12615](https://github.com/longhorn/longhorn/issues/12615) - @mantissahz
- [BACKPORT][v1.11.1][BUG] Longhorn validating webhook blocks k3s server node joins - flannel CNI fails to initialize [12589](https://github.com/longhorn/longhorn/issues/12589) - @yangchiu @mantissahz
- [BACKPORT][v1.11.1][BUG] V1.11.0 very high memory consumption for instance manager [12575](https://github.com/longhorn/longhorn/issues/12575) - @derekbit @roger-ryao
- [BACKPORT][v1.11.1][BUG] Backing image data source pod fails when HTTP proxy is enabled [12780](https://github.com/longhorn/longhorn/issues/12780) - @c3y1huang @chriscchien
- [BACKPORT][v1.11.1][BUG] orphan controller does not cleanup the instance on the corresponding instance manager on a multiple IM node [12788](https://github.com/longhorn/longhorn/issues/12788) - @COLDTURNIP @roger-ryao

### Stability

- [BACKPORT][v1.11.1][BUG] Potential NEP in Volume Metrics Collector [12733](https://github.com/longhorn/longhorn/issues/12733) - @derekbit @chriscchien

## Contributors

- @COLDTURNIP
- @PhanLe1010
- @bachmanity1
- @c3y1huang
- @chriscchien
- @davidcheng0922
- @derekbit
- @forbesguthrie
- @github-actions[bot]
- @hookak
- @houhoucoop
- @innobead
- @mantissahz
- @rebeccazzzz
- @roger-ryao
- @shuo-wu
- @sushant-suse
- @yangchiu 
