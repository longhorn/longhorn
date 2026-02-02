# Longhorn v1.11.0 Release Notes

The Longhorn team is excited to announce the release of Longhorn v1.11.0. This release marks a major milestone, with the **V2 Data Engine** officially entering the **Technical Preview** stage following significant stability improvements.

Additionally, this version optimizes the stability of the whole system and introduces critical improvements in resource observability, scheduling, and utilization.

For terminology and background on Longhorn releases, see [Releases](https://github.com/longhorn/longhorn#releases).

> [!WARNING]
>
> ## Hotfix
>
> The `longhorn-instance-manager:v1.11.0` image is affected by a [regression issue](https://github.com/longhorn/longhorn/issues/12573) introduced by the new longhorn-instance-manager Proxy service APIs. The bug causes Proxy connection leaks in the longhorn-instance-manager pods, resulting in increased memory usage. To mitigate this issue, replace `longhornio/longhorn-instance-manager:v1.11.0` with the hotfixed image `longhornio/longhorn-instance-manager:v1.11.0-hotfix-1`.
>
> You can apply the update by following these steps:
>
> 1. **Update the `longhorn-instance-manager` image**
>
>    - Change the longhorn-instance-manager image tag from `v1.11.0` to `v1.11.0-hotfix-1` in the appropriate file:
>        - For Helm: Update `values.yaml`
>        - For manifests: Update the deployment manifest directly.
>
> 2. **Proceed with the upgrade**
>
>    - Apply the changes using your standard Helm upgrade command or reapply the updated manifest.

## Deprecation

### V2 Backing Image Deprecation

The Backing Image feature for the V2 Data Engine is now deprecated in v1.11.0 and is scheduled for removal in v1.12.0.

Users using V2 volumes for virtual machines are encouraged to adopt the [Containerized Data Importer (CDI)](https://kubevirt.io/user-guide/operations/containerized_data_importer/) for volume population instead.

[GitHub Issue #12237](https://github.com/longhorn/longhorn/issues/12237)

## Primary Highlights

### V2 Data Engine

#### Now in Technical Preview Stage

We are pleased to announce that the V2 Data Engine has officially graduated to the **Technical Preview** stage. This indicates increased stability and feature maturity as we move toward General Availability.

> **Limitation:** While the engine is in Technical Preview, live upgrade is not supported yet. V2 volumes must be detached (offline) before engine upgrade.

#### Support for `ublk` Frontend

Users can now configure `ublk` (Userspace Block Device) as the frontend for V2 Data Engine volumes. This provides a high-performance alternative to the NVMe-oF frontend for environments running Kernel v6.0+.

[GitHub Issue #11039](https://github.com/longhorn/longhorn/issues/11039)

### V1 Data Engine

#### Faster Replica Rebuilding from Multiple Sources

The V1 Data Engine now supports parallel rebuilding. When a replica needs to be rebuilt, the engine can now stream data from multiple healthy replicas simultaneously rather than a single source. This significantly reduces the time required to restore redundancy for volumes containing tons of scattered data chunks.

[GitHub Issue #11331](https://www.google.com/search?q=https://github.com/longhorn/longhorn/issues/11331)

### General

#### Balance-Aware Algorithm Disk Selection For Replica Scheduling

Longhorn improves the disk selection for the replica scheduling by introducing an intelligent `balance-aware` scheduling algorithm, reducing uneven storage usage across nodes and disks.

[GitHub Issue #10512](https://github.com/longhorn/longhorn/issues/10512)

#### Node Disk Health Monitoring

Longhorn now actively monitors the physical health of the underlying disks used for storage by using S.M.A.R.T. data. This allows administrators to identify issues and raise alerts when abnormal SMART metrics are detected, helping prevent failed volumes.

[GitHub Issue #12016](https://github.com/longhorn/longhorn/issues/12016)

#### Share Manager Networking

Users can now configure an extra network interface for the Share Manager to support complex network segmentation requirements.

[GitHub Issue #10269](https://github.com/longhorn/longhorn/issues/10269)

#### ReadWriteOncePod (RWOP) Support
  
Full support for the Kubernetes `ReadWriteOncePod` access mode has been added.

[GitHub Issue #9727](https://github.com/longhorn/longhorn/issues/9727)

#### StorageClass `allowedTopologies` Support

Administrators can now use the `allowedTopologies` field in Longhorn StorageClasses to restrict volume provisioning to specific zones, regions, or nodes within the cluster.

[GitHub Issue #12261](https://github.com/longhorn/longhorn/issues/12261)

## Installation

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.11.0.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.11.0/deploy/install/) in the Longhorn documentation.

## Upgrade

> [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.10.x to v1.11.0.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.11.0/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues in this release

### Highlight

- [FEATURE] Add support for ReadWriteOncePod access mode [9727](https://github.com/longhorn/longhorn/issues/9727) - @derekbit @shikanime @chriscchien @Copilot
- [FEATURE] Scale replica rebuilding speed from multiple healthy replicas [11331](https://github.com/longhorn/longhorn/issues/11331) - @derekbit @shuo-wu @roger-ryao @Copilot
- [FEATURE] Support StorageClass allowedTopologies for Longhorn volumes [12261](https://github.com/longhorn/longhorn/issues/12261) - @yangchiu @derekbit @hookak @Copilot
- [FEATURE] Support extra network interface (not only storage network) on the share manager pod [10269](https://github.com/longhorn/longhorn/issues/10269) - @yangchiu @c3y1huang
- [FEATURE] Monitor Node Disk Health [12016](https://github.com/longhorn/longhorn/issues/12016) - @c3y1huang @roger-ryao
- [FEATURE] Replica Auto Balance Across Nodes based on Node Disk Space Consumption [10512](https://github.com/longhorn/longhorn/issues/10512) - @davidcheng0922 @chriscchien

### Feature

- [FEATURE] Guess Linux distro from the package manager [12153](https://github.com/longhorn/longhorn/issues/12153) - @yangchiu @derekbit @NamrathShetty @Copilot
- [FEATURE] Provide a helm chart setting to define the managerUrl [10583](https://github.com/longhorn/longhorn/issues/10583) - @lexfrei @yangchiu
- [FEATURE] Add metric for last backup of a volume [6049](https://github.com/longhorn/longhorn/issues/6049) - @c3y1huang @roger-ryao
- [FEATURE] Real-time volume performance monitoring [368](https://github.com/longhorn/longhorn/issues/368) - @derekbit @hookak
- [UI][FEATURE] Monitor Node Disk Health [12263](https://github.com/longhorn/longhorn/issues/12263) - @houhoucoop @roger-ryao
- [FEATURE] custom annotation/label of UI's k8s service on value.yaml of helm chart [11754](https://github.com/longhorn/longhorn/issues/11754) - @yangchiu @lucasl0st
- [FEATURE] Make `longhornctl` load `ublk_drv` module when kernel version is 6 or newer [11803](https://github.com/longhorn/longhorn/issues/11803) - @chriscchien @bachmanity1
- [BUG] Inherit namespace for longhorn-share-manager in FastFailover mode [12244](https://github.com/longhorn/longhorn/issues/12244) - @yangchiu @semenas
- [FEATURE] Enable CSI pod anti-affinity preset update [12100](https://github.com/longhorn/longhorn/issues/12100) - @yangchiu @yulken
- [FEATURE] [Dependency] aws-sdk-go v1.55.7 is EOL as of 2025-07-31 — plan to migrate to v2? [12098](https://github.com/longhorn/longhorn/issues/12098) - @mantissahz @roger-ryao
- [FEATURE] Change volume operation menu button behaviour from hover to click. [11408](https://github.com/longhorn/longhorn/issues/11408) - @yangchiu @houhoucoop
- [FEATURE] "hard" podAntiAffinity for csi-attacher/csi-provisioner/csi-resizer/csi-snapshotter [11617](https://github.com/longhorn/longhorn/issues/11617) - @yangchiu @yulken
- [FEATURE] node storage scheduled metrics [11949](https://github.com/longhorn/longhorn/issues/11949) - @yangchiu @AoRuiAC

### Improvement

- [IMPROVEMENT] Generalize the offline rebuilding setting for both data engines [12484](https://github.com/longhorn/longhorn/issues/12484) - @mantissahz @chriscchien
- [IMPROVEMENT] Introduce Concurrent Job Limit for Snapshot Operations [11635](https://github.com/longhorn/longhorn/issues/11635) - @yangchiu @derekbit @davidcheng0922 @Copilot
- [IMPROVEMENT] Improve disk error logging to retain errors from newDiskServiceClients() [12446](https://github.com/longhorn/longhorn/issues/12446) - @yangchiu @davidcheng0922
- [IMPROVEMENT] Propagate longhorn-manager's timezone to instance-manager and CSI pods [12448](https://github.com/longhorn/longhorn/issues/12448) - @hookak @roger-ryao
- [UI][FEATURE] Scale replica rebuilding speed from multiple healthy replicas [12461](https://github.com/longhorn/longhorn/issues/12461) - @houhoucoop @roger-ryao
- [IMPROVEMENT] Configure rolling update strategy for longhorn-manager and CSI deployments [12240](https://github.com/longhorn/longhorn/issues/12240) - @hookak @chriscchien
- [IMPROVEMENT] Improve log messages for `rebuildNewReplica()` in longhorn-manager [12426](https://github.com/longhorn/longhorn/issues/12426) - @derekbit @chriscchien
- [IMPROVEMENT] misleading message when instance manager tries to create the pod [11759](https://github.com/longhorn/longhorn/issues/11759) - @mantissahz @chriscchien
- [IMPROVEMENT] To improve the debugging process and UX, it would be nice that the error is recorded in the `instancemanager.status.conditions`. [6732](https://github.com/longhorn/longhorn/issues/6732) - @mantissahz @chriscchien
- [IMPROVEMENT] Add setting to disable node disk health monitoring [12300](https://github.com/longhorn/longhorn/issues/12300) - @derekbit @roger-ryao @Copilot
- [IMPROVEMENT] Avoid repeat engine restart when there are replica unavailable during migration [11397](https://github.com/longhorn/longhorn/issues/11397) - @yangchiu @shuo-wu
- [IMPROVEMENT]  [Script] Minor script adjustments from PR #12177 [12187](https://github.com/longhorn/longhorn/issues/12187) - @rauldsl @yangchiu
- [IMPROVEMENT] Check toolchain versions before generate k8s codes [12164](https://github.com/longhorn/longhorn/issues/12164) - @derekbit @roger-ryao
- [IMPROVEMENT] Create Volume UI improvement, Automatically Filter `Data Source` Based on v1 or v2 Selection [11846](https://github.com/longhorn/longhorn/issues/11846) - @yangchiu @houhoucoop
- [IMPROVEMENT] Disable the snapshot of v1 volume hashing while it is being deleted [10294](https://github.com/longhorn/longhorn/issues/10294) - @davidcheng0922 @chriscchien
- [IMPROVEMENT] Expose SPDK UBLK Parameters [11039](https://github.com/longhorn/longhorn/issues/11039) - @derekbit @PhanLe1010 @roger-ryao @Copilot
- [IMPROVEMENT] Check that block device is not in use before creating disk [12078](https://github.com/longhorn/longhorn/issues/12078) - @chriscchien @bachmanity1
- [UI][IMPROVEMENT] Awareness of when an offline replica rebuilding is triggered for an individual volume [11247](https://github.com/longhorn/longhorn/issues/11247) - @houhoucoop @roger-ryao
- [IMPROVEMENT] Ensure synchronized upgrades between longhorn-manager and instance-manager [12309](https://github.com/longhorn/longhorn/issues/12309) - @hookak @chriscchien
- [IMPROVEMENT] Add Resource Limits Configuration for Longhorn manager/instance-manager [12225](https://github.com/longhorn/longhorn/issues/12225) - @hookak @chriscchien
- [IMPROVEMENT] Add Validation Webhook to Volume Expansion When Node Disk Is Full [12134](https://github.com/longhorn/longhorn/issues/12134) - @yangchiu @davidcheng0922
- [UI][IMPROVEMENT] Expose SPDK UBLK Parameters [12166](https://github.com/longhorn/longhorn/issues/12166) - @houhoucoop @roger-ryao
- [IMPROVEMENT] Fix V2 Volume CSI Clone Slowness Caused by VolumeAttachment Webhook Blocking [12328](https://github.com/longhorn/longhorn/issues/12328) - @PhanLe1010 @roger-ryao
- [IMPROVEMENT] Use label-based state in metrics instead of numeric values [10723](https://github.com/longhorn/longhorn/issues/10723) - @hookak @roger-ryao
- [IMPROVEMENT] Add Resource Limits Configuration for CSI Components [12224](https://github.com/longhorn/longhorn/issues/12224) - @yangchiu @hookak @Copilot
- [IMPROVEMENT] Awareness of when an offline replica rebuilding is triggered for an individual volume [11246](https://github.com/longhorn/longhorn/issues/11246) - @yangchiu @mantissahz
- [IMPROVEMENT] Add loadBalancerClass value inside a helm chart for ui service [12273](https://github.com/longhorn/longhorn/issues/12273) - @ehpc @chriscchien
- [IMPROVEMENT] Add DNS round-robin load balancing to the pool of S3 addresses [12296](https://github.com/longhorn/longhorn/issues/12296) - @yangchiu
- [UI][IMPROVEMENT] Should Not Hide the Deleted Snapshots on UI [11620](https://github.com/longhorn/longhorn/issues/11620) - @yangchiu @houhoucoop
- [IMPROVEMENT] Helm chart Multiple TLS FQDNs [12127](https://github.com/longhorn/longhorn/issues/12127) - @yangchiu @hrabalvojta
- [IMPROVEMENT] Removing executables from mirrored-longhornio-longhorn-engine image [11254](https://github.com/longhorn/longhorn/issues/11254) - @derekbit @chriscchien
- [IMPROVEMENT] [DOC] Clarify replica auto-balance behavior for unhealthy and detached volumes [12002](https://github.com/longhorn/longhorn/issues/12002) - @roger-ryao @sushant-suse
- [IMPROVEMENT] CRD enum values [9718](https://github.com/longhorn/longhorn/issues/9718) - @roger-ryao @nzhan126
- [DOC] Troubleshooting KB Articles Fix Typos [12199](https://github.com/longhorn/longhorn/issues/12199) - @jmeza-xyz
- [IMPROVEMENT] Remove backupstore related settings [11026](https://github.com/longhorn/longhorn/issues/11026) - @nzhan126
- [IMPROVEMENT] Reject Trim Operation on Block Volume [12048](https://github.com/longhorn/longhorn/issues/12048) - @yangchiu @derekbit
- [IMPROVEMENT] Replace `github.com/pkg/errors` with `github.com/cockroachdb/errors` [11413](https://github.com/longhorn/longhorn/issues/11413) - @derekbit @chriscchien
- [UI][IMPROVEMENT] UI shows the backing image virtual size [11674](https://github.com/longhorn/longhorn/issues/11674) - @chriscchien @houhoucoop
- [IMPROVEMENT] Simplify locking in unsub and stream methods [12057](https://github.com/longhorn/longhorn/issues/12057) - @derekbit @NamrathShetty
- [UI][IMPROVEMENT] Show Error Message for Unschedulable Disks [11449](https://github.com/longhorn/longhorn/issues/11449) - @yangchiu @houhoucoop
- [IMPROVEMENT] The `auto-delete-pod-when-volume-detached-unexpectedly` should only focus on the Kubernetes builtin workload. [12120](https://github.com/longhorn/longhorn/issues/12120) - @derekbit @chriscchien @sushant-suse
- [IMPROVEMENT] `CSIStorageCapacity` objects must show schedulable (allocatable) capacity [12014](https://github.com/longhorn/longhorn/issues/12014) - @chriscchien @bachmanity1
- [IMPROVEMENT] improve error logging for failed mounting during node publish volume [12025](https://github.com/longhorn/longhorn/issues/12025) - @COLDTURNIP @roger-ryao
- [IMPROVEMENT] Improve Helm Chart defaultSettings handling with automatic quoting and multi-type support [12019](https://github.com/longhorn/longhorn/issues/12019) - @derekbit @chriscchien
- [IMPROVEMENT] volume `spec.backingImage` and `spec.encrypted` shouldn't allow to update for both v1 and v2 data engines [11615](https://github.com/longhorn/longhorn/issues/11615) - @yulken @roger-ryao

### Bug

- [BUG] V2 DR volume failed if backupstore is temporarily unavailable after node reboot [12543](https://github.com/longhorn/longhorn/issues/12543) - @c3y1huang @roger-ryao
- [BUG] SnapshotBack proxy request might be sent to incorrect instance-manager pod [12475](https://github.com/longhorn/longhorn/issues/12475) - @derekbit @chriscchien
- [BUG] Replica rebuild, clone and restore fail, traffic being sent to HTTP proxy [12304](https://github.com/longhorn/longhorn/issues/12304) - @derekbit @chriscchien @roger-ryao
- [BUG]  `instance-manager` on nodes that don't have hard or solid state disk DDOSing cluster DNS server with TXT query  `_grpc_config.localhost` [12521](https://github.com/longhorn/longhorn/issues/12521) - @COLDTURNIP @chriscchien
- [BUG][v1.11.0-rc3] test_basic.py::test_snapshot fails on v2 data engine [12526](https://github.com/longhorn/longhorn/issues/12526) - @derekbit @chriscchien
- [BUG] RWX volume causes process uninterruptible sleep [11907](https://github.com/longhorn/longhorn/issues/11907) - @COLDTURNIP @chriscchien
- [BUG] Healthy replica could be deleted unexpectedly after reducing volume's number of replicas [12511](https://github.com/longhorn/longhorn/issues/12511) - @yangchiu @shuo-wu
- [BUG] Auto balance feature may lead to volumes falling into a replica deletion-recreation loop [11730](https://github.com/longhorn/longhorn/issues/11730) - @shuo-wu @roger-ryao
- [BUG] Data locality enabled volume fails to remove an existing running replica after numberOfReplicas reduced [12488](https://github.com/longhorn/longhorn/issues/12488) - @derekbit @chriscchien
- [BUG] Single replica volume could get stuck in attaching/detaching loop after the replica node rebooted [9141](https://github.com/longhorn/longhorn/issues/9141) - @COLDTURNIP @yangchiu
- [BUG] v2 volume rebuild performance doesn't improve after enabling snapshot integrity [12416](https://github.com/longhorn/longhorn/issues/12416) - @yangchiu @davidcheng0922
- [BUG] Request Header Or Cookie Too Large in Web UI with OIDC auth [12077](https://github.com/longhorn/longhorn/issues/12077) - @chriscchien @houhoucoop
- [BUG] v1.11.x upgrade test may fail because the default disk of a node is removed during a test case and cannot be re-added [12469](https://github.com/longhorn/longhorn/issues/12469) - @COLDTURNIP @yangchiu
- [BUG] Potential Instance Manager Client Context Leak [12198](https://github.com/longhorn/longhorn/issues/12198) - @derekbit @chriscchien
- [BUG] v2 DR volume becomes faulted during incremental restoration after source volume expansion [12465](https://github.com/longhorn/longhorn/issues/12465) - @yangchiu @davidcheng0922
- [BUG] `rebuildConcurrentSyncLimit` field is omitted from `volume.spec` when value is `0` [12471](https://github.com/longhorn/longhorn/issues/12471) - @derekbit @houhoucoop @roger-ryao
- [BUG] Adding multiple disks to the same node concurrently may occasionally fail [11971](https://github.com/longhorn/longhorn/issues/11971) - @davidcheng0922 @roger-ryao
- [BUG] unknown OS condition in node CR is not properly removed during upgrade [12450](https://github.com/longhorn/longhorn/issues/12450) - @COLDTURNIP @roger-ryao
- [BUG] Longhorn charts does not take care timezone [11965](https://github.com/longhorn/longhorn/issues/11965) - @hookak @roger-ryao
- [BUG] Pod failed to use an activated DR volume, got `UNEXPECTED INCONSISTENCY; RUN fsck MANUALLY` error [12444](https://github.com/longhorn/longhorn/issues/12444) - @yangchiu
- [BUG] v2 volumes do not reuse failed replicas for rebuilding as expected [12413](https://github.com/longhorn/longhorn/issues/12413) - @yangchiu @shuo-wu
- [BUG] v2 volumes complete offline rebuilding with an extra failed replica if a node is rebooted during the rebuild [12407](https://github.com/longhorn/longhorn/issues/12407) - @yangchiu @mantissahz
- [BUG] Test case `test_rebuild_failure_with_intensive_data` is failing because replicas cannot be rebuilt after replica process crashed [12436](https://github.com/longhorn/longhorn/issues/12436) - @yangchiu @shuo-wu
- [BUG] Replica mode becomes empty and replica rebuilding cannot be triggered after upgrading from v1.10.1 to master-head or v1.11.0-rc1 [12431](https://github.com/longhorn/longhorn/issues/12431) - @yangchiu @derekbit
- [BUG] v2 volumes get stuck in `Attaching/Detaching` loop after node reboots [12406](https://github.com/longhorn/longhorn/issues/12406) - @yangchiu @c3y1huang
- [BUG] test_basic.py::test_expansion_basic is flaky on v2 data engine due to revert snapshot fail [12235](https://github.com/longhorn/longhorn/issues/12235) - @davidcheng0922 @chriscchien
- [BUG] Longhorn nodes may fail to recover after node reboots [12422](https://github.com/longhorn/longhorn/issues/12422) - @COLDTURNIP @yangchiu
- [BUG] Missing `Frontend` default value when creating v2 volumes via Longhorn UI [12152](https://github.com/longhorn/longhorn/issues/12152) - @houhoucoop @roger-ryao
- [BUG] setting values are not converted to strings in Longhorn UI [12192](https://github.com/longhorn/longhorn/issues/12192) - @chriscchien @houhoucoop
- [BUG] `disk health information` appears briefly [12415](https://github.com/longhorn/longhorn/issues/12415) - @c3y1huang @roger-ryao
- [BUG] encrypted v2 volume gets stuck in `Attaching/Detaching` loop after volume expansion [12359](https://github.com/longhorn/longhorn/issues/12359) - @yangchiu @davidcheng0922
- [BUG] Unexpected orphaned replica is created after node reboot, preventing new replica from being scheduled on that node, and blocking v2 volume from recovering to healthy state [11333](https://github.com/longhorn/longhorn/issues/11333) - @yangchiu @c3y1huang
- [BUG] RWX volume becomes unavailable after drain node [12226](https://github.com/longhorn/longhorn/issues/12226) - @yangchiu @mantissahz
- [BUG] invalid memory address or nil pointer dereference [11939](https://github.com/longhorn/longhorn/issues/11939) - @bachmanity1 @roger-ryao
- [BUG] share-manager excessive memory usage [11938](https://github.com/longhorn/longhorn/issues/11938) - @derekbit @chriscchien
- [BUG] Encrypted Volume Cannot Be Expanded Online [12366](https://github.com/longhorn/longhorn/issues/12366) - @yangchiu @chriscchien
- [BUG] Backing image download gets stuck after network disconnection [11622](https://github.com/longhorn/longhorn/issues/11622) - @COLDTURNIP @chriscchien
- [BUG] Can not delete the parent of volume head snapshot of a v2 volume [9064](https://github.com/longhorn/longhorn/issues/9064) - @yulken @chriscchien
- [BUG] changing of the volume controller owner caused: BUG: multiple engines detected when volume is detached [1755](https://github.com/longhorn/longhorn/issues/1755) - @PhanLe1010 @chriscchien
- [BUG] mounting error is not properly handled during CSI node publish volume [12006](https://github.com/longhorn/longhorn/issues/12006) - @COLDTURNIP @yangchiu
- [BUG] test_rebuild_after_replica_file_crash failed on master-head [12389](https://github.com/longhorn/longhorn/issues/12389) - @derekbit @chriscchien
- [BUG] `test_backing_image_auto_resync` is flaky due to recent commit [12387](https://github.com/longhorn/longhorn/issues/12387) - @derekbit @chriscchien
- [BUG] Flooding messages `Failed to resolve sysfs path for \"/sys/class/block/root\  ...`  in longhorn-manager [12344](https://github.com/longhorn/longhorn/issues/12344) - @c3y1huang @roger-ryao
- [BUG] v2 volumes could fail to auto salvage after cluster restart [11336](https://github.com/longhorn/longhorn/issues/11336) - @yangchiu @c3y1huang
- [BUG] The auo generated backing image pod name is complained by kubelet [12356](https://github.com/longhorn/longhorn/issues/12356) - @COLDTURNIP @yangchiu
- [BUG] `test_restore_inc_with_offline_expansion` fails on v2 data engine [12313](https://github.com/longhorn/longhorn/issues/12313) - @davidcheng0922 @chriscchien
- [BUG] Block disks have a chance become Unschedulable in v2 regression test in test_rebuild_with_restoration [11446](https://github.com/longhorn/longhorn/issues/11446) - @shuo-wu @chriscchien
- [BUG] v2 volume workload FailedMount with message Staging target path `/var/lib/kubelet/plugins/kubernetes.io/csi/driver.longhorn.io/xxx/globalmount is no longer valid` [10476](https://github.com/longhorn/longhorn/issues/10476) - @yangchiu @shuo-wu
- [BUG] [v1.10.0-rc1] v2 DR volume stuck Unhealthy after incremental restore with replica deletion(`test_rebuild_with_inc_restoration`) [11684](https://github.com/longhorn/longhorn/issues/11684) - @c3y1huang @chriscchien
- [BUG] `test_data_locality_strict_local_node_affinity` fails at master-head [12343](https://github.com/longhorn/longhorn/issues/12343) - @derekbit @chriscchien
- [BUG] `tests.test_cloning.test_cloning_basic` fails at  msater-head [12341](https://github.com/longhorn/longhorn/issues/12341) - @derekbit @chriscchien @Copilot
- [BUG] v2 volume could get stuck in `Detaching` indefinitely after node reboot [11332](https://github.com/longhorn/longhorn/issues/11332) - @yangchiu @c3y1huang
- [Bug] A cloned volume cannot be attached to a workload [12206](https://github.com/longhorn/longhorn/issues/12206) - @yangchiu @PhanLe1010
- [BUG] Block Mode Volume Migration Stuck [12311](https://github.com/longhorn/longhorn/issues/12311) - @COLDTURNIP @yangchiu @shuo-wu
- [BUG] Replica auto balance disk pressure threshold stalled with stopped volumes [10837](https://github.com/longhorn/longhorn/issues/10837) - @c3y1huang @chriscchien
- [BUG] short name mode is enforcing, but image name longhornio/longhorn-manager:v1.10. │ │ 0 returns ambiguous list [12268](https://github.com/longhorn/longhorn/issues/12268) - @yangchiu @Wqrld
- [BUG] invalid memory address or nil pointer dereference (again) [12233](https://github.com/longhorn/longhorn/issues/12233) - @chriscchien @bachmanity1
- [BUG] Restored v2 volume gets stuck in `RestoreInProgress` state if backup is deleted during restoration [11828](https://github.com/longhorn/longhorn/issues/11828) - @yangchiu @c3y1huang
- [BUG] spdk_tgt is crashed due to SIGSEGV [11698](https://github.com/longhorn/longhorn/issues/11698) - @c3y1huang
- [BUG] Longhorn ignores `Replica Node Level Soft Anti-Affinity` when auto balance is set to `best-effort` [11189](https://github.com/longhorn/longhorn/issues/11189) - @c3y1huang @chriscchien
- [BUG] SPDK NVMe synchronous calls [11096](https://github.com/longhorn/longhorn/issues/11096) -
- [BUG] Replicas accumulate during engine upgrade [12111](https://github.com/longhorn/longhorn/issues/12111) - @c3y1huang @chriscchien
- [BUG] Some default settings in questions.yaml are placed incorrectly. [12219](https://github.com/longhorn/longhorn/issues/12219) - @derekbit @roger-ryao
- [BUG] Chart does not handle defaultSettings.taintToleration with a trailing colon [12162](https://github.com/longhorn/longhorn/issues/12162) - @derekbit @chriscchien
- [BUG] Fix SPDK v25.05 CVE issue [11969](https://github.com/longhorn/longhorn/issues/11969) - @derekbit @roger-ryao
- [BUG] Potential BackingImageManagerClient Connection and Context Leak [12194](https://github.com/longhorn/longhorn/issues/12194) - @derekbit @chriscchien
- [BUG] Instance manager pod `awsIAMRoleArn` annotation disappearing [9923](https://github.com/longhorn/longhorn/issues/9923) - @yangchiu @mantissahz
- [BUG] Node block-type disk is unable to unbind after Longhorn uninstall [9127](https://github.com/longhorn/longhorn/issues/9127) - @yangchiu @davidcheng0922
- [BUG] longhorn-manager fails to start after upgrading from 1.9.2 to 1.10.0 [11864](https://github.com/longhorn/longhorn/issues/11864) - @derekbit @roger-ryao
- [BUG][UI] When creating volume/backing image, change `Data Engine` will reset `Number of Replicas` [11775](https://github.com/longhorn/longhorn/issues/11775) - @yangchiu @houhoucoop
- [BUG] Backup target metric is broken [12073](https://github.com/longhorn/longhorn/issues/12073) - @mantissahz @roger-ryao
- [BUG] panic: runtime error: invalid memory address or nil pointer dereference [signal SIGSEGV: segmentation violation code=0x1 at longhorn-engine/pkg/controller/control.go:218 +0x2de [12081](https://github.com/longhorn/longhorn/issues/12081) - @liyimeng @roger-ryao
- [BUG] Unable to complete uninstallation due to the remaining backuptarget [11934](https://github.com/longhorn/longhorn/issues/11934) - @mantissahz @roger-ryao
- [BUG] NVME disk not found in v2 data engine (failed to find device for BDF) [11903](https://github.com/longhorn/longhorn/issues/11903) - @derekbit @roger-ryao
- [BUG] NPE error during recurring job execution [11925](https://github.com/longhorn/longhorn/issues/11925) - @yangchiu @shuo-wu
- [BUG] v2 volume creation failed on talos nodes [11910](https://github.com/longhorn/longhorn/issues/11910) - @c3y1huang @chriscchien
- [BUG] DR volume gets stuck in `unknown` state if engine image is deleted from the attached node [11995](https://github.com/longhorn/longhorn/issues/11995) - @yangchiu @shuo-wu
- [BUG] Volume gets stuck in `attaching` state if engine image image is not deployed on one of nodes [11994](https://github.com/longhorn/longhorn/issues/11994) - @yangchiu @shuo-wu
- [BUG] Rebooting the volume attached node during a v2 DR volume incremental restoration, the restoration is left incomplete and the activation has no effect [11778](https://github.com/longhorn/longhorn/issues/11778) - @yangchiu @c3y1huang
- [BUG] Unable to detach a v2 volume after labeling `disable-v2-data-engine=true` [11799](https://github.com/longhorn/longhorn/issues/11799) - @yangchiu @mantissahz
- [BUG] `test_system_backup_and_restore` test case failed on master-head [11933](https://github.com/longhorn/longhorn/issues/11933) - @derekbit @chriscchien
- [BUG] Shebang refactor in scripts may cause compatibility issues [11815](https://github.com/longhorn/longhorn/issues/11815) - @NamrathShetty @chriscchien
- [BUG] longhorn-spdk-engine CIs complain that the unit tests successfully hash system created snapshots [11822](https://github.com/longhorn/longhorn/issues/11822) - @yangchiu @shuo-wu
- [BUG] Unable to re-add block-type disks by BDF after re-enable v2 data engine [11860](https://github.com/longhorn/longhorn/issues/11860) - @yangchiu @davidcheng0922
- [BUG] V2 volume stuck in volume attachment (V2 interrupt mode) [11816](https://github.com/longhorn/longhorn/issues/11816) - @c3y1huang
- [BUG] Goroutine leak in instance-manager when using v2 data engine [11959](https://github.com/longhorn/longhorn/issues/11959) - @PhanLe1010 @chriscchien
- [BUG] csi-provisioner silently fails to create CSIStorageCapacity if dataEngine parameter is missing [11906](https://github.com/longhorn/longhorn/issues/11906) - @yangchiu @bachmanity1
- [BUG][v1.8.x] v2 volume stuck at attaching due to stopped replica [10486](https://github.com/longhorn/longhorn/issues/10486) - @chriscchien
- [BUG] longhorn-engine's UI panics [11867](https://github.com/longhorn/longhorn/issues/11867) - @derekbit @chriscchien @Copilot
- [BUG] v2 volume workload gets stuck in `ContainerCreating` or `Unknown` state with `FailedMount` error [10111](https://github.com/longhorn/longhorn/issues/10111) - @yangchiu @shuo-wu
- [BUG] Volume is unable to upgrade if the number of active replicas is larger than `volume.spec.numberOfReplicas` [11825](https://github.com/longhorn/longhorn/issues/11825) - @yangchiu @derekbit
- [BUG] UI fails to deploy when only IPv4 is enabled on nodes with v1.10.0 version [11869](https://github.com/longhorn/longhorn/issues/11869) - @yangchiu @c3y1huang
- [BUG] v2 DR volume fails to auto-reattach when engine image missing on current node [11772](https://github.com/longhorn/longhorn/issues/11772) - @chriscchien
- [BUG] inconsistent behavior of v2 volume after labeling disable-v2-data-engine to the volume attached node and deleting the instance manager [11578](https://github.com/longhorn/longhorn/issues/11578) - @yangchiu

### Misc

- [DOC] Fix Talos install documentation for current versions [12514](https://github.com/longhorn/longhorn/issues/12514) -
- [DOC] Add KB article for the failure of RWX volume detachment [12238](https://github.com/longhorn/longhorn/issues/12238) - @sushant-suse
- [TASK] Fix flaky regression test case `test_recurring_job.py::test_recurring_job_snapshot_cleanup` for v2 data engine [12464](https://github.com/longhorn/longhorn/issues/12464) - @derekbit @chriscchien
- [DOC] Review and Update Ingress Controller Examples for Longhorn UI [12252](https://github.com/longhorn/longhorn/issues/12252) - @yangchiu @sushant-suse
- [DOC] Incorrect longhornctl subcommand [12423](https://github.com/longhorn/longhorn/issues/12423) - @chriscchien @roger-ryao
- [TASK] Update nvme and libnvme to v2.16 and v1.16.1 [12391](https://github.com/longhorn/longhorn/issues/12391) - @derekbit @chriscchien
- [DOC] Disk Aggregation Options [12378](https://github.com/longhorn/longhorn/issues/12378) - @davidcheng0922 @roger-ryao
- [TASK] Deprecate V2 Backing Image Feature [12237](https://github.com/longhorn/longhorn/issues/12237) - @derekbit @chriscchien
- feat(chart): Add Gateway API HTTPRoute support for Longhorn UI [12299](https://github.com/longhorn/longhorn/issues/12299) - @lexfrei @derekbit @chriscchien @Copilot
- [DOC] V2 data engine: delete snapshot after volume-head behaves inconsistently vs v1 [12355](https://github.com/longhorn/longhorn/issues/12355) - @chriscchien @sushant-suse
- [TASK] Revert Base Image bci-base:16.0 to bci-base:15.7 [12354](https://github.com/longhorn/longhorn/issues/12354) - @derekbit @chriscchien
- [DOC] Clarify share-manager image update behavior after system upgrade with attached RWX volumes [12363](https://github.com/longhorn/longhorn/issues/12363) - @derekbit @chriscchien
- [DOC] Clarify expected behavior of old instance manager pods after live engine upgrade [12361](https://github.com/longhorn/longhorn/issues/12361) - @derekbit @chriscchien
- [TASK] Update Longhorn v1.11.0 SPDK to v25.09 [11975](https://github.com/longhorn/longhorn/issues/11975) - @derekbit @chriscchien
- [TASK] Bump Longhorn Component `registry.suse.com/bci/bci-base` to 16.0 [12145](https://github.com/longhorn/longhorn/issues/12145) - @derekbit @chriscchien
- [DOC] Add KB Article: Handling Persistent Replica Failures via Disk Isolation [12242](https://github.com/longhorn/longhorn/issues/12242) - @derekbit @roger-ryao
- [DOC] Document how to permanently enable hugepages [12167](https://github.com/longhorn/longhorn/issues/12167) - @roger-ryao @sushant-suse
- [DOC] Update existing terminologies and add new terminologies [12302](https://github.com/longhorn/longhorn/issues/12302) - @sushant-suse
- [DOC] Add a KB for restoring data from an orphan replica directory [9972](https://github.com/longhorn/longhorn/issues/9972) - @yangchiu @sushant-suse
- [DOC] [UI][IMPROVEMENT] Should Not Hide the Deleted Snapshots on UI #11620 [12214](https://github.com/longhorn/longhorn/issues/12214) - @chriscchien @sushant-suse
- [DOC] Add `Enterprise` Page in Longhorn Official Document [12110](https://github.com/longhorn/longhorn/issues/12110) - @sushant-suse
- [DOC] Update Talos Linux Support with Longhorn [12108](https://github.com/longhorn/longhorn/issues/12108) - @roger-ryao @egrosdou01
- [DOC] [FEATURE] Add support for ReadWriteOncePod access mode [12228](https://github.com/longhorn/longhorn/issues/12228) - @chriscchien
- [DOC] Workaround KB doc for backing image manager disk UUID collision issue [12114](https://github.com/longhorn/longhorn/issues/12114) - @COLDTURNIP @roger-ryao
- [TASK] Remove testing credentials from backup target manifest examples [11076](https://github.com/longhorn/longhorn/issues/11076) - @davidcheng0922 @roger-ryao
- [DOC] Document the Migratable RWX Volume in the Official Document [11277](https://github.com/longhorn/longhorn/issues/11277) - @derekbit @chriscchien @sushant-suse
- [DOC][UI][IMPROVEMENT] Show Error Message for Unschedulable Disks #11449 [12151](https://github.com/longhorn/longhorn/issues/12151) - @yangchiu @sushant-suse
- [TASK] Create a GitHub Action to Update Versions in longhorn/dev-versions [12062](https://github.com/longhorn/longhorn/issues/12062) - @derekbit
- [DOC] Update NFSv4 client installation docs to verify actual NFS version in use [11944](https://github.com/longhorn/longhorn/issues/11944) - @derekbit @chriscchien
- [REFACTOR] SAST checks for UI component [11540](https://github.com/longhorn/longhorn/issues/11540) - @sminux @chriscchien
- [DOC] Update Longhorn README file [10891](https://github.com/longhorn/longhorn/issues/10891) - @divya-mohan0209
- [BUG] Block disk deletion fails without error message [11952](https://github.com/longhorn/longhorn/issues/11952) - @davidcheng0922 @roger-ryao
- [REFACTOR] Remove redundant assignment [11705](https://github.com/longhorn/longhorn/issues/11705) - @jvanz
- [TASK] Remove deprecated instances field and instance type from instance manager CR [5844](https://github.com/longhorn/longhorn/issues/5844) - @derekbit @chriscchien
- [DOC] Update deployment links according to the document version [11847](https://github.com/longhorn/longhorn/issues/11847) - @yulken

## New Contributors

* @ADN182
* @AoRuiAC
* @Henllage-hqb
* @Mmx233
* @NamrathShetty
* @Wqrld
* @adegoodyer
* @ah8ad3
* @boomam
* @brandboat
* @bvankampen
* @danielskowronski
* @davepgreene
* @egrosdou01
* @ehpc
* @enterdv
* @fatihmete
* @hrabalvojta
* @inqode-lars
* @jmeza-xyz
* @jvanz
* @kocmoc1
* @koeberlue
* @lexfrei
* @lucasl0st
* @madeITBelgium
* @marnixbouhuis
* @mattn
* @maximemoreillon
* @mo124121
* @nachtschatt3n
* @rajeshkio
* @rauldsl
* @saimikiry
* @sdre15
* @semenas
* @shikanime
* @sminux
* @zijiren233

## Contributors

Thank you to the following contributors who made this release possible.

> **Note:** Starting from v1.11.0, as long as a GitHub issue is resolved in the current release, the corresponding authors will be listed in this contributor list as well. If there is still a missing, please contact Longhorn team for the update. 

- @ADN182
- @AoRuiAC
- @COLDTURNIP
- @DamiaSan
- @Henllage-hqb
- @Mmx233
- @NRCan-LGariepy
- @NamrathShetty
- @PhanLe1010
- @Vicente-Cheng
- @WebberHuang1118
- @Wqrld
- @adegoodyer
- @ah8ad3
- @bachmanity1
- @boomam
- @brandboat
- @bvankampen
- @c3y1huang
- @chriscchien
- @danielskowronski
- @davepgreene
- @davidcheng0922
- @derekbit
- @dhedberg
- @divya-mohan0209
- @egrosdou01
- @ehpc
- @enterdv
- @fatihmete
- @fmunteanu
- @forbesguthrie
- @hoo29
- @hookak
- @houhoucoop
- @hrabalvojta
- @innobead
- @inqode-lars
- @james-munson
- @jmeza-xyz
- @jvanz
- @kocmoc1
- @koeberlue
- @lexfrei
- @liyimeng
- @lucasl0st
- @madeITBelgium
- @mantissahz
- @marnixbouhuis
- @mattn
- @maximemoreillon
- @mcerveny
- @mo124121
- @nachtschatt3n
- @nzhan126
- @rajeshkio
- @rauldsl
- @rebeccazzzz
- @roger-ryao
- @runningman84
- @saimikiry
- @sdre15
- @semenas
- @shikanime
- @shuo-wu
- @sminux
- @sushant-suse
- @w13915984028
- @yangchiu
- @yasker
- @yulken
- @zijiren233
