# Longhorn v1.11.3 Release Notes

Longhorn 1.11.3 introduces several improvements and bug fixes that are intended to improve system quality, resilience, stability and security.

We welcome feedback and contributions to help continuously improve Longhorn.

For terminology and context on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

## Important Fixes

This release includes several critical stability fixes.

### V1 volumes not operable fix after iscsid restart

Resolved the issue caused by the `iscsid` restart where volume operations could become stuck or fail, including PVC resize failures.

For more details, see [#13411](https://github.com/longhorn/longhorn/issues/13411), [#13413](https://github.com/longhorn/longhorn/issues/13413), and [#13383](https://github.com/longhorn/longhorn/issues/13383).

### Replica rebuild stability fix

Fixed a nil pointer dereference panic in `longhorn-instance-manager` during replica rebuild, improving rebuild stability under failure conditions.

For more details, see [#13129](https://github.com/longhorn/longhorn/issues/13129).

### Migration engine readiness transition fix

Resolved an issue where the migration engine could be unexpectedly deleted while the target node was still transitioning to ready, which could interrupt migration workflows.

For more details, see [#13133](https://github.com/longhorn/longhorn/issues/13133).

### Recurring trim job deadlock fix

Resolved a deadlock that could cause recurring trim jobs to fail.

For more details, see [#13424](https://github.com/longhorn/longhorn/issues/13424).

## Installation

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.11.3.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.11.3/deploy/install/) in the Longhorn documentation.

## Upgrade

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.10.x or v1.11.0 to v1.11.3.**

> [!IMPORTANT]
**Users on v1.11.0 who experienced the memory leaks of longhorn-instance-manager pods [12575](https://github.com/longhorn/longhorn/issues/12575) are highly encouraged to upgrade to v1.11.3 to receive the permanent fix for the proxy connection leaks.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.11.3/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues in this release

### Improvement

- [BACKPORT][v1.11.3][IMPROVEMENT] longhorn-manager pods race on webhook TLS Secret at scale [13116](https://github.com/longhorn/longhorn/issues/13116) - @yangchiu @hookak
- [BACKPORT][v1.11.3][IMPROVEMENT]  Add metrics to collect information about LONGHORN_DISTRO [13283](https://github.com/longhorn/longhorn/issues/13283) - @derekbit @chriscchien

### Bug

- [BACKPORT][v1.11.3][BUG] volume expansion stuck [13411](https://github.com/longhorn/longhorn/issues/13411) - @shuo-wu @roger-ryao
- [BACKPORT][v1.11.3][BUG] pvc resize fails after iscsid restart [13413](https://github.com/longhorn/longhorn/issues/13413) - @yangchiu @shuo-wu
- [BACKPORT][v1.11.3][BUG] expanding the volume fails [13383](https://github.com/longhorn/longhorn/issues/13383) - @chriscchien
- [BACKPORT][v1.11.3][BUG] Migration Engine Can Be Unexpectedly Deleted If the Target Node Is Still in Readiness Transition [13133](https://github.com/longhorn/longhorn/issues/13133) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.11.3][BUG] System Backup RecurringJob retention prunes newest CR — sorts by Status.CreatedAt (zero for Error/racing CRs) [13211](https://github.com/longhorn/longhorn/issues/13211) - @roger-ryao
- [BACKPORT][v1.11.3][BUG] when uploading backup to S3 storage (NetApp appliance) it fails [13296](https://github.com/longhorn/longhorn/issues/13296) - @mantissahz
- [BACKPORT][v1.11.3][BUG] spdk interrupt mode value is missing in chart/values.yaml [13270](https://github.com/longhorn/longhorn/issues/13270) - @yangchiu
- [BACKPORT][v1.11.3][BUG] nil pointer dereference panic in instance-manager during replica rebuild. [13129](https://github.com/longhorn/longhorn/issues/13129) - @derekbit @shuo-wu @roger-ryao
- [BACKPORT][v1.11.3][BUG] Test Encrypted Volume Upgrade: Old-engine RWO volume shows 1008 MiB  after expansion to 2 GiB instead of expected 2032 MiB [13200](https://github.com/longhorn/longhorn/issues/13200) - @derekbit @mantissahz @roger-ryao
- [BACKPORT][v1.11.3][BUG] HTTP response body leaks in support bundle status polling and webhook readiness checks [13124](https://github.com/longhorn/longhorn/issues/13124) - @derekbit @roger-ryao
- [BACKPORT][v1.11.3][BUG] global.cattle.systemDefaultRegistry is not applied as the image registry prefix in 108.2.1+up1.10.2 [13099](https://github.com/longhorn/longhorn/issues/13099) - @COLDTURNIP @yangchiu
- [BACKPORT][v1.11.3][BUG] [longhorn-engine/dataserver] Handling EOF returned by io.ReadFull robustly [13080](https://github.com/longhorn/longhorn/issues/13080) - @yangchiu
- [BACKPORT][v1.11.3][BUG] PrometheusTimeseriesCardinality for metric longhorn_rest_client_rate_limiter_latency_seconds_bucket [13088](https://github.com/longhorn/longhorn/issues/13088) - @derekbit
- [BACKPORT][v1.11.3][BUG] Recurring trim job fails with deadlock [13424](https://github.com/longhorn/longhorn/issues/13424) - @c3y1huang @roger-ryao

### Stability

- [BACKPORT][v1.11.3][BUG] longhorn-manager panic in BackupController.setInprogressDeletionMap during backup deletion [13247](https://github.com/longhorn/longhorn/issues/13247) - @roger-ryao

### Misc

- [BACKPORT][v1.11.3][TASK] Add distro information to upgrade responder requests [13278](https://github.com/longhorn/longhorn/issues/13278) - @davidcheng0922 @roger-ryao

## Contributors

- @COLDTURNIP 
- @chriscchien 
- @davidcheng0922 
- @derekbit 
- @hookak 
- @innobead 
- @mantissahz 
- @roger-ryao 
- @shuo-wu 
- @yangchiu
- @c3y1huang
- @rebeccazzzz
- @forbesguthrie
- @asettle