## Longhorn v1.8.1 Release Notes

Longhorn 1.8.1 introduces several improvements and bug fixes that are intended to improve system quality, resilience, stability and security.

The Longhorn team appreciates your contributions and expects to receive feedback regarding this release.

> [!NOTE]
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before installing Longhorn v1.8.1.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.8.1/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.25 or later before upgrading from Longhorn v1.7.x or v1.8.x (< v1.8.1) to v1.8.1.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.8.1/deploy/upgrade/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Improvement

- [BACKPORT][v1.8.1][IMPROVEMENT] Support configurable upgrade-responder URL [10439](https://github.com/longhorn/longhorn/issues/10439) - @derekbit @roger-ryao
- [BACKPORT][v1.8.1][IMPROVEMENT] Several warning for unknown reason [10420](https://github.com/longhorn/longhorn/issues/10420) - @roger-ryao
- [BACKPORT][v1.8.1][IMPROVEMENT] Settings change validation should go back to using Volume state to determine "are all volumes detached" [10376](https://github.com/longhorn/longhorn/issues/10376) - @yangchiu @james-munson

### Bug

- [BACKPORT][v1.8.1][BUG] csi keeps creating backup if the backup target is unavailable [10510](https://github.com/longhorn/longhorn/issues/10510) - @mantissahz @roger-ryao
- [BACKPORT][v1.8.1][BUG] integer divide by zero in replica scheduler [10506](https://github.com/longhorn/longhorn/issues/10506) - @c3y1huang @chriscchien
- [BACKPORT][v1.8.1][BUG] Leading or trailing spaces in Longhorn UI break search [10508](https://github.com/longhorn/longhorn/issues/10508) - @houhoucoop @roger-ryao
- [BACKPORT][v1.8.1][BUG] When replica rebuilding completed, the progress could be 99 instead of 100 [10485](https://github.com/longhorn/longhorn/issues/10485) - @shuo-wu @chriscchien
- [BACKPORT][v1.8.1][BUG] list_backupVolume API could randomly returns `failed to find a node that is ready and has the default engine image` error [10478](https://github.com/longhorn/longhorn/issues/10478) - @yangchiu @mantissahz
- [BACKPORT][v1.8.1][BUG] nil pointer when the backing image copy is delete from the spec but also gets evicted at the same time [10466](https://github.com/longhorn/longhorn/issues/10466) - @yangchiu @ChanYiLin
- [BACKPORT][v1.8.1][BUG] 2 uninstall pods could be created after uninstall job was created, one failed with `deleting-confirmation-flag is set to false` error, while the other completed successfully [10484](https://github.com/longhorn/longhorn/issues/10484) - 
- [BACKPORT][v1.8.1][BUG][UI] Backup store setting doesn't apply to the cloned volume [10468](https://github.com/longhorn/longhorn/issues/10468) - @yangchiu @mantissahz
- [BACKPORT][v1.8.1][BUG] v2 volume workload FailedMount with message Staging target path `/var/lib/kubelet/plugins/kubernetes.io/csi/driver.longhorn.io/xxx/globalmount is no longer valid` [10477](https://github.com/longhorn/longhorn/issues/10477) - 
- [BACKPORT][v1.8.1][BUG][UI] Bulk backup creation with a detached volume returns error 405 and error messages show in browser console [10462](https://github.com/longhorn/longhorn/issues/10462) - @mantissahz
- [BACKPORT][v1.8.1][BUG] V2 volume fails to cleanup error replica and rebuild new one - test_data_locality_basic [10364](https://github.com/longhorn/longhorn/issues/10364) - @shuo-wu @chriscchien
- [BACKPORT][v1.8.1][BUG] Data lost caused by Longhorn CSI plugin doing a wrong filesystem format action in a rare race condition [10418](https://github.com/longhorn/longhorn/issues/10418) - @yangchiu @PhanLe1010
- [BACKPORT][v1.8.1][BUG] v2 Engine loops in detaching and attaching state after rebuilding [10397](https://github.com/longhorn/longhorn/issues/10397) - @shuo-wu
- [BACKPORT][v1.8.1][BUG]  A V2 volume checksum will change after replica rebuilding if the volume created with backing image [10341](https://github.com/longhorn/longhorn/issues/10341) - @shuo-wu @chriscchien
- [BACKPORT][v1.8.1][BUG] Bug in snapshot count enforcement cause volume faulted and stuck in detaching/attaching loop [10309](https://github.com/longhorn/longhorn/issues/10309) - @PhanLe1010 @roger-ryao
- [BACKPORT][v1.8.1][BUG] Test case `test_csi_mount_volume_online_expansion` is failing due to unable to expand PVC [10414](https://github.com/longhorn/longhorn/issues/10414) - @yangchiu @c3y1huang
- [BACKPORT][v1.8.1][BUG] V2 BackingImage failed after node reboot [10343](https://github.com/longhorn/longhorn/issues/10343) - @ChanYiLin @chriscchien
- [BACKPORT][v1.8.1][BUG] Workload pod will not be able to move to new node when backup operation is taking a long time [10172](https://github.com/longhorn/longhorn/issues/10172) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.8.1][BUG] WebUI Volumes Disappear and Reappear [10332](https://github.com/longhorn/longhorn/issues/10332) - @PhanLe1010 @chriscchien @houhoucoop
- [BACKPORT][v1.8.1][BUG] "Error get size" from "metrics_collector.(*BackupCollector).Collect" on every metric scrape [10361](https://github.com/longhorn/longhorn/issues/10361) - @derekbit @chriscchien
- [BACKPORT][v1.8.1][BUG] [UI] 'Create' button on the System Backup page is disabled after reloading page [10354](https://github.com/longhorn/longhorn/issues/10354) - @chriscchien @houhoucoop
- [BACKPORT][v1.8.1][BUG] Proxy gRPC API ReplicaList returns different output formats for v1 and v2 volumes [10353](https://github.com/longhorn/longhorn/issues/10353) - @shuo-wu @roger-ryao
- [BACKPORT][v1.8.1][BUG] constant attaching/reattaching of volumes after upgrading to 1.8 [10315](https://github.com/longhorn/longhorn/issues/10315) - @james-munson
- [BACKPORT][v1.8.1][BUG] Backup Execution Timeout setting issue in Helm chart [10325](https://github.com/longhorn/longhorn/issues/10325) - @james-munson @chriscchien
- [BACKPORT][v1.8.1][BUG] v2 engine stuck in detaching-attaching loop if the previous replica is not cleaned up correct [10363](https://github.com/longhorn/longhorn/issues/10363) - @shuo-wu @chriscchien
- [BACKPORT][v1.8.1][BUG] Longhorn CSI plugin 1.8.0 crashes consistently when trying to create a snapshot [10319](https://github.com/longhorn/longhorn/issues/10319) - @PhanLe1010 @chriscchien
- [BACKPORT][v1.8.1][BUG] Engine stuck in "stopped" state, prevent volume attach [10329](https://github.com/longhorn/longhorn/issues/10329) - @ChanYiLin @chriscchien
- [BACKPORT][v1.8.1][BUG] After upgrading to v1.8.0 the version number lost on the web-ui [10337](https://github.com/longhorn/longhorn/issues/10337) - @derekbit
- [BACKPORT][v1.8.1][BUG] insufficient storage;precheck new replica failed after a temporary shutdown of a node [10234](https://github.com/longhorn/longhorn/issues/10234) - @PhanLe1010

## Misc

- [TASK] Fix CVE issues for v1.8.1 [10318](https://github.com/longhorn/longhorn/issues/10318) - @c3y1huang

## Contributors

- @ChanYiLin 
- @PhanLe1010 
- @c3y1huang 
- @chriscchien 
- @derekbit 
- @houhoucoop 
- @innobead 
- @james-munson 
- @mantissahz 
- @roger-ryao 
- @shuo-wu 
- @yangchiu 
- @jillian-maroket 
- @jhkrug
- @rebeccazzzz
- @forbesguthrie
- @asettle
