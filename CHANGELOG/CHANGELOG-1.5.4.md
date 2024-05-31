## Longhorn v1.5.4 Release Notes

This latest stable version of Longhorn 1.5 introduces several improvements and bug fixes that are intended to improve system quality, resilience, and stability. 

The Longhorn team appreciates your contributions and anticipates receiving feedback regarding this release.

> **Note:**
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

**Ensure that your cluster is running Kubernetes v1.21 or later before installing Longhorn v1.5.4.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.5.4/deploy/install/) in the Longhorn documentation.

## Upgrade

**Ensure that your cluster is running Kubernetes v1.21 or later before upgrading from Longhorn v1.4.x to v1.5.4.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.5.4/deploy/upgrade/) in the Longhorn documentation.

## Deprecation & Incompatibilities

For information about important changes, including feature incompatibility, deprecation, and removal, see [Important Notes](https://longhorn.io/docs/1.5.4/deploy/important-notes/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Highlight
- [BACKPORT][v1.5.4][FEATURE] Add a new settings that allows Longhorn to evict replicas automatically when a node is drained [7421](https://github.com/longhorn/longhorn/issues/7421) - @yangchiu @ejweber

### Improvement
- [BACKPORT][v1.5.4][IMPROVEMENT] Use HEAD instead of a GET to fetch the `Content-Length` of an resource via URL [7981](https://github.com/longhorn/longhorn/issues/7981) - @votdev @roger-ryao
- [BACKPORT][v1.5.4][IMPROVEMENT] Change support-bundle-manager image pull policy to PullIfNotPresent [7999](https://github.com/longhorn/longhorn/issues/7999) - @ChanYiLin @chriscchien
- [BACKPORT][v1.5.4][FEATURE] Update base image of Longhorn components to BCI 15.5 [7134](https://github.com/longhorn/longhorn/issues/7134) - @nitendra-suse
- [BACKPORT][v1.5.4]Allow to set mount options for storageclass via values.yaml in helm chart [7593](https://github.com/longhorn/longhorn/issues/7593) - @ChanYiLin @mantissahz
- [BACKPORT][v1.5.4][IMPROVEMENT] Remove startup probe of CSI driver after liveness probe conn fix ready [7933](https://github.com/longhorn/longhorn/issues/7933) - @ejweber @chriscchien
- [IMPROVEMENT] Make environment_check look for a global default K8s priority class in those releases that it affects. [7831](https://github.com/longhorn/longhorn/issues/7831) - @mantissahz @james-munson
- [BACKPORT][v1.5.4][IMPROVEMENT] Allow deployment of Prometheus ServiceMonitor with the Longhorn helm chart [7864](https://github.com/longhorn/longhorn/issues/7864) - @mantissahz @chriscchien
- [BACKPORT][v1.5.4][IMPROVEMENT] Remove unused process manager connection in longhorn-manager [7785](https://github.com/longhorn/longhorn/issues/7785) - @derekbit @roger-ryao
- [BACKPORT][v1.5.4][IMPROVEMENT] Clean up backup target in IM-R pod if the backup target setting is unset [7145](https://github.com/longhorn/longhorn/issues/7145) - @ChanYiLin @chriscchien
- [BACKPORT][v1.5.4][IMPROVEMENT] BackingImage should be compressed when downloading and use the name as filename instead of UUID [7397](https://github.com/longhorn/longhorn/issues/7397) - @ChanYiLin @roger-ryao
- [BACKPORT][v1.5.4][IMPROVEMENT] Automatically remount read-only RWO volume to read-write [7500](https://github.com/longhorn/longhorn/issues/7500) - @ChanYiLin @chriscchien
- [BACKPORT][v1.5.4][IMPROVEMENT] deploy: driver deployer shouldn't cleanup previous deployment if Kubernetes version changes [7345](https://github.com/longhorn/longhorn/issues/7345) - @PhanLe1010 @roger-ryao
- [BACKPORT][v1.5.4][IMPROVEMENT] Only restarts pods with volumes in the unexpected Read-Only state [7729](https://github.com/longhorn/longhorn/issues/7729) - @yangchiu @ChanYiLin
- [BACKPORT][v1.5.4][IMPROVEMENT] Improve handling of 16TiB+ volumes with ext4 as the underlying file system [7429](https://github.com/longhorn/longhorn/issues/7429) - @mantissahz @chriscchien
- [BACKPORT][v1.5.4][IMPROVEMENT] Volumes: metrics for snapshots include (size and type: system vs user) [7725](https://github.com/longhorn/longhorn/issues/7725) - @c3y1huang @chriscchien
- [BACKPORT][v1.5.4][IMPROVEMENT] Improve the profiler of longhorn-engine for runtime profiling [7545](https://github.com/longhorn/longhorn/issues/7545) - @Vicente-Cheng @chriscchien
- [BACKPORT][v1.5.4][IMPROVEMENT] Don't crash the migration engine when kubelet restarts [7328](https://github.com/longhorn/longhorn/issues/7328) - @yangchiu @ejweber
- [BACKPORT][v1.5.4][IMPROVEMENT] Upgrade CSI components to the latest patch release [7492](https://github.com/longhorn/longhorn/issues/7492) - @c3y1huang @roger-ryao
- [BACKPORT][v1.5.4][IMPROVEMENT] Reject the last replica deletion if its volume.spec.deletionTimestamp is not set [7432](https://github.com/longhorn/longhorn/issues/7432) - @yangchiu @derekbit
- [BACKPORT][v1.5.4][IMPROVEMENT] Upgrade support bundle kit version to v0.0.33 [7279](https://github.com/longhorn/longhorn/issues/7279) - @c3y1huang
- [BACKPORT][v1.5.4][IMPROVEMENT] Review and simplify longhorn component image build [7162](https://github.com/longhorn/longhorn/issues/7162) - @ChanYiLin
- [BACKPORT][v1.5.4][IMPROVEMENT] Replace deprecated grpc.WithInsecure [7364](https://github.com/longhorn/longhorn/issues/7364) - @c3y1huang
- [BACKPORT][v1.5.4][IMPROVEMENT] Have a setting to disable snapshot purge for maintenance purpose [7265](https://github.com/longhorn/longhorn/issues/7265) - @ejweber @chriscchien
- [BACKPORT][v1.5.4][IMPROVEMENT] Bypass upgrade when installing a fresh setup [7283](https://github.com/longhorn/longhorn/issues/7283) - @mantissahz @roger-ryao

### Bug
- [BACKPORT][v1.5.4][BUG][v1.5.4-rc4] Test case test_backuptarget_available_during_engine_image_not_ready failed to wait for backup target available [8054](https://github.com/longhorn/longhorn/issues/8054) - @yangchiu @c3y1huang
- [BACKPORT][v1.5.4][BUG] The activated DR volume do not contain the latest data. [7947](https://github.com/longhorn/longhorn/issues/7947) - @shuo-wu @roger-ryao
- [BUG][v1.5.x] DR volume unable to be activated if the latest backup's been deleted [7997](https://github.com/longhorn/longhorn/issues/7997) - @yangchiu @shuo-wu
- [BUG] Backup related test cases failed [7989](https://github.com/longhorn/longhorn/issues/7989) - @yangchiu @shuo-wu
- [BACKPORT][v1.5.4][BUG][v1.5.x] Recurring job fails to create backup when volume detached [8015](https://github.com/longhorn/longhorn/issues/8015) - @yangchiu @mantissahz @PhanLe1010 @c3y1huang
- [BACKPORT][v1.5.4][BUG] Deadlock for RWX volume if an error occurs in its share-manager pod [7186](https://github.com/longhorn/longhorn/issues/7186) - @ejweber @chriscchien
- [BACKPORT][v1.5.4][BUG] Deadlock is possible in v1.6.0 instance manager [7941](https://github.com/longhorn/longhorn/issues/7941) - @ejweber @roger-ryao
- [BACKPORT][v1.5.4][BUG] Longhorn may keep corrupted salvaged replicas and discard good ones [7801](https://github.com/longhorn/longhorn/issues/7801) - @ejweber @chriscchien
- [BACKPORT][v1.5.4][BUG] Deadlock between volume migration and upgrade after Longhorn upgrade [7869](https://github.com/longhorn/longhorn/issues/7869) - @ejweber @chriscchien
- [BACKPORT][v1.5.4][BUG] Executing fstrim while rebuilding causes IO errors [7867](https://github.com/longhorn/longhorn/issues/7867) - @ejweber @chriscchien
- [BACKPORT][v1.5.4][BUG] BackingImage does not download URL correctly in some situation [7986](https://github.com/longhorn/longhorn/issues/7986) - @yangchiu
- [BACKPORT][v1.5.4][BUG] The feature of auto remount read only volume not work on a single node cluster. [7844](https://github.com/longhorn/longhorn/issues/7844) - @ChanYiLin @chriscchien
- [BACKPORT][v1.5.4][BUG] Volumes stuck upgrading after 1.5.3 -> 1.6.0 upgrade. [7901](https://github.com/longhorn/longhorn/issues/7901) - @yangchiu @ejweber
- [BUG][v1.5.4-rc1] V2 volume have engine upgrade option on UI after upgrade from v1.5.3 to v1.5.4-rc1 [7863](https://github.com/longhorn/longhorn/issues/7863) - @chriscchien @scures
- [BACKPORT][v1.5.4][BUG] longhorn manager pod fails to start in container-based K3s [7848](https://github.com/longhorn/longhorn/issues/7848) - @ChanYiLin
- [BACKPORT][v1.5.4][BUG] Relax S3 client retry intervals, for throttled requests [7098](https://github.com/longhorn/longhorn/issues/7098) - @mantissahz @chriscchien
- [BACKPORT][v1.5.4][BUG][v1.6.0-rc1] Negative test case failed: Stop Volume Node Kubelet For More Than Pod Eviction Timeout While Workload Heavy Writing [7761](https://github.com/longhorn/longhorn/issues/7761) - @yangchiu @c3y1huang
- [BACKPORT][v1.5.4][BUG] Volumes don't mount with mTLS enabled [7789](https://github.com/longhorn/longhorn/issues/7789) - @derekbit @roger-ryao
- [BACKPORT][v1.5.4][BUG] supportbundle/kubelet.log empty in k3s environment [7123](https://github.com/longhorn/longhorn/issues/7123) - @c3y1huang @chriscchien @roger-ryao
- [BUG] v1.5.x/v1.4.x BackingImage download fails if URL has query parameters [7822](https://github.com/longhorn/longhorn/issues/7822) - @ChanYiLin @mantissahz
- [BACKPORT][v1.5.4][BUG] Metric totalVolumeSize and totalVolumeActualSize incorrect due to v2 volume counts [7392](https://github.com/longhorn/longhorn/issues/7392) - @c3y1huang @chriscchien
- [BACKPORT][v1.5.4][BUG] Continuously auto-balancing replicas when zone does not have enough space [7306](https://github.com/longhorn/longhorn/issues/7306) - @c3y1huang @chriscchien
- [BACKPORT][v1.5.4][BUG] Unable to list backups when backuptarget resource is picked up by a cordoned node [7621](https://github.com/longhorn/longhorn/issues/7621) - @mantissahz @c3y1huang
- [BUG] The wrong template in default-setting.yaml of the Longhorn chart in v1.5 and v1.4 [7459](https://github.com/longhorn/longhorn/issues/7459) - @mantissahz @roger-ryao
- [BACKPORT][v1.5.4][BUG]  Failed to `check_volume_data` after volume engine upgrade/migration [7402](https://github.com/longhorn/longhorn/issues/7402) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.5.4][BUG] Volume conditions are not represented in the UI for v1.4.x and newer [7242](https://github.com/longhorn/longhorn/issues/7242) - @m-ildefons @roger-ryao
- [BACKPORT][v1.5.4][BUG] Confusing logging when trying to attach a new volume with no scheduled replicas [7245](https://github.com/longhorn/longhorn/issues/7245) - @ejweber @roger-ryao
- [BACKPORT][v1.5.4][BUG] Environment check script claims success when kubectl fails. [7216](https://github.com/longhorn/longhorn/issues/7216) - @james-munson @roger-ryao
- [BACKPORT][v1.5.4][BUG] Backup volume attachment tickets might not be cleaned up after completion. [7604](https://github.com/longhorn/longhorn/issues/7604) - @james-munson @chriscchien
- [BACKPORT][v1.5.4][BUG][v1.6.0-rc1] Some Longhorn resources remaining after longhorn-uninstall job completed [7663](https://github.com/longhorn/longhorn/issues/7663) - @yangchiu @PhanLe1010
- [BACKPORT][v1.5.4][BUG] Backing Image Data Inconsistency if it's Exported from a Backing Image Backed Volume [7701](https://github.com/longhorn/longhorn/issues/7701) - @yangchiu @ChanYiLin
- [BACKPORT][v1.5.4][BUG] CSI components CrashLoopBackOff, failed to connect to unix://csi/csi.sock after cluster restart [7426](https://github.com/longhorn/longhorn/issues/7426) - @ejweber @roger-ryao
- [BACKPORT][v1.5.4][BUG] Volume could not be remounted after engine process killed [7772](https://github.com/longhorn/longhorn/issues/7772) - @ChanYiLin @shuo-wu @roger-ryao
- [BACKPORT][v1.5.4][BUG] Enabling replica-auto-balance tries to replicate to disabled nodes causing lots of errors in the logs and in the UI [7275](https://github.com/longhorn/longhorn/issues/7275) - @yangchiu @c3y1huang
- [BACKPORT][v1.5.4][BUG] `allow-collecting-longhorn-usage-metrics` setting is missing from chart settings [7250](https://github.com/longhorn/longhorn/issues/7250) - @ChanYiLin @roger-ryao
- [BACKPORT][v1.5.4][BUG] When disabling revision counter, salvaging a faulty volume not work as expected [7732](https://github.com/longhorn/longhorn/issues/7732) - @james-munson @roger-ryao
- [BACKPORT][v1.5.4][BUG] During volume live engine upgrade, delete replica with old engine image will make volume degraded forever [7334](https://github.com/longhorn/longhorn/issues/7334) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.5.4][BUG] Uninstallation job stuck forever if the MutatingWebhookConfigurations or ValidatingWebhookConfigurations already deleted [7658](https://github.com/longhorn/longhorn/issues/7658) - @PhanLe1010 @roger-ryao
- [BACKPORT][v1.5.4][BUG] Volume encryption doesn't work on Amazon Linux 2 [7165](https://github.com/longhorn/longhorn/issues/7165) - @derekbit @chriscchien
- [BACKPORT][v1.5.4][BUG] Rancher cannot import longhorn 1.5 charts due to "error converting YAML to JSON: yaml: line 699: did not find expected key" [7776](https://github.com/longhorn/longhorn/issues/7776) - @mantissahz @PhanLe1010
- [BACKPORT][v1.5.4][BUG] Delete kubernetes node did not remove `node.longhorn.io` [7538](https://github.com/longhorn/longhorn/issues/7538) - @ejweber @chriscchien
- [BACKPORT][v1.5.4][BUG] backingimage download server error [7381](https://github.com/longhorn/longhorn/issues/7381) - @scures @roger-ryao
- [BACKPORT][v1.5.4][BUG] Longhorn-manager does not deploy CSI driver when integrated with linkerd service mesh [7391](https://github.com/longhorn/longhorn/issues/7391) - @yangchiu @mantissahz
- [BACKPORT][v1.5.4][BUG] Helm2 install error: 'lookup' function not defined in validate-psp-install.yaml [7435](https://github.com/longhorn/longhorn/issues/7435) - @roger-ryao
- [BACKPORT][v1.5.4][BUG] Warning events are being spammed by Longhorn - CRD [7309](https://github.com/longhorn/longhorn/issues/7309) - @m-ildefons @roger-ryao
- [BACKPORT][v1.5.4][BUG] Persistent volume is not ready for workloads [7314](https://github.com/longhorn/longhorn/issues/7314) - @james-munson @roger-ryao
- [BACKPORT][v1.5.4][BUG] Download backing image failed with HTTP 502 error if Storage Network configured [7239](https://github.com/longhorn/longhorn/issues/7239) - @ChanYiLin @roger-ryao
- [BACKPORT][v1.5.4][BUG] Errors found by static checker in volume controller [7269](https://github.com/longhorn/longhorn/issues/7269) - @m-ildefons

### Misc
- [TASK] Update v1.5.x Longhorn components vendor dependencies [8003](https://github.com/longhorn/longhorn/issues/8003) - @mantissahz @chriscchien
- [BACKPORT][v1.5.4][TASK] Review why sessionAffinity: ClientIP is used in most services [7760](https://github.com/longhorn/longhorn/issues/7760) - @ejweber @roger-ryao
- [BACKPORT][v1.5.4][TASK] Synchronize version of CSI components in longhorn/longhorn and longhorn/longhorn-manager [7378](https://github.com/longhorn/longhorn/issues/7378) - @c3y1huang @roger-ryao
- [BACKPORT][v1.5.4][TASK] Bump the versions of dependent libs or components [7150](https://github.com/longhorn/longhorn/issues/7150) - @c3y1huang
- [BACKPORT][v1.5.4][DOC] Fix erroneous value for default StorageMinimalAvailablePercentage setting. [7400](https://github.com/longhorn/longhorn/issues/7400) - @james-munson

## Contributors
- @ChanYiLin
- @PhanLe1010
- @Vicente-Cheng
- @c3y1huang
- @chriscchien
- @derekbit
- @ejweber
- @innobead
- @james-munson
- @m-ildefons
- @mantissahz
- @nitendra-suse
- @roger-ryao
- @scures
- @shuo-wu
- @votdev
- @yangchiu 

