## Longhorn v1.7.2 Release Notes

Longhorn 1.7.2 introduces several improvements and bug fixes that are intended to improve system quality, resilience, stability and security.

The Longhorn team appreciates your contributions and expects to receive feedback regarding this release.

> [!NOTE]
> For more information about release-related terminology, see [Releases](https://github.com/longhorn/longhorn#releases).

## Installation

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before installing Longhorn v1.7.2.**

You can install Longhorn using a variety of tools, including Rancher, Kubectl, and Helm. For more information about installation methods and requirements, see [Quick Installation](https://longhorn.io/docs/1.7.2/deploy/install/) in the Longhorn documentation.

## Upgrade

>  [!IMPORTANT]
**Ensure that your cluster is running Kubernetes v1.21 or later before upgrading from Longhorn v1.6.x or v1.7.x (< v1.7.0) to v1.7.2.**

Longhorn only allows upgrades from supported versions. For more information about upgrade paths and procedures, see [Upgrade](https://longhorn.io/docs/1.7.2/deploy/upgrade/) in the Longhorn documentation.

## Deprecation & Incompatibilities

The functionality of the [environment check script](https://github.com/longhorn/longhorn/blob/v1.7.x/scripts/environment_check.sh) overlaps with that of the Longhorn CLI, which is available starting with v1.7.0. Because of this, the script is deprecated in v1.7.0 and is scheduled for removal in v1.8.0.

For information about important changes, including feature incompatibility, deprecation, and removal, see [Important Notes](https://longhorn.io/docs/1.7.2/important-notes/) in the Longhorn documentation.

## Post-Release Known Issues

For information about issues identified after this release, see [Release-Known-Issues](https://github.com/longhorn/longhorn/wiki/Release-Known-Issues).

## Resolved Issues

### Improvement

- [BACKPORT][v1.7.2][IMPROVEMENT] Allow specify data engine version for the default storageclass during Helm installation [9632](https://github.com/longhorn/longhorn/issues/9632) - @shuo-wu @chriscchien
- [BACKPORT][v1.7.2][IMPROVEMENT] Remove mirrored openshift image from Longhorn [9598](https://github.com/longhorn/longhorn/issues/9598) - @derekbit @chriscchien
- [BACKPORT][v1.7.2][IMPROVEMENT] Fix contradicting node status events [9326](https://github.com/longhorn/longhorn/issues/9326) - @yangchiu @PhanLe1010
- [BACKPORT][v1.7.2][IMPROVEMENT] Check kernel module `dm_crypt` on host machines [9317](https://github.com/longhorn/longhorn/issues/9317) - @yangchiu @mantissahz

### Bug

- [BACKPORT][v1.7.2][BUG] longhornctl install preflight --operating-system=cos failed on COS_CONTAINERD [9666](https://github.com/longhorn/longhorn/issues/9666) - @c3y1huang @chriscchien
- [BACKPORT][v1.7.2][BUG] System Restore Stuck at Pending due to Tolerations not Applied [9655](https://github.com/longhorn/longhorn/issues/9655) - @c3y1huang @chriscchien
- [BACKPORT][v1.7.2][BUG][v1.7.x] Disks modal broken layout [9633](https://github.com/longhorn/longhorn/issues/9633) - @a110605 @roger-ryao
- [BACKPORT][v1.7.2][BUG] Single Replica Node Down test cases fail [9628](https://github.com/longhorn/longhorn/issues/9628) - @yangchiu @c3y1huang
- [BACKPORT][v1.7.2][BUG] Test case `Stopped replicas on deleted nodes should not be counted as healthy replicas when draining nodes` fails [9621](https://github.com/longhorn/longhorn/issues/9621) - @yangchiu @derekbit
- [BUG] robot test case `Single Replica Node Down Deletion Policy do-nothing With RWO Volume Replica Locate On Replica Node` fails to wait for the volume getting stuck in attaching state [9498](https://github.com/longhorn/longhorn/issues/9498) - @c3y1huang
- [BACKPORT][v1.7.2][BUG] All Backups are lost in the Backup Target if the NFS Service Disconnects and Reconnects again [9542](https://github.com/longhorn/longhorn/issues/9542) - @yangchiu @mantissahz
- [BACKPORT][v1.7.2][BUG] PV Annotation Isn't Updated After Creating An Oversize Volume [9515](https://github.com/longhorn/longhorn/issues/9515) - @c3y1huang @chriscchien
- [BACKPORT][v1.7.2][BUG] Instance manager missing required selector labels after manager crash [9471](https://github.com/longhorn/longhorn/issues/9471) - @c3y1huang @chriscchien
- [BACKPORT][v1.7.2][BUG] Engine Upgrade to 1.7.1 fails on volumes with strict-local data locality [9416](https://github.com/longhorn/longhorn/issues/9416) - @yangchiu @james-munson
- [BACKPORT][v1.7.2][BUG] Longhorn did not close and open encrypted volumes correctly when the service k3s-agent restarted for a while [9387](https://github.com/longhorn/longhorn/issues/9387) - @yangchiu @mantissahz
- [BACKPORT][v1.7.2][BUG] Longhorn keeps resetting my storageClass [9396](https://github.com/longhorn/longhorn/issues/9396) - @yangchiu @mantissahz
- [BACKPORT][v1.7.2][BUG] Fix test case test_rwx_delete_share_manager_pod failure after changes to RWX workload restart. [9505](https://github.com/longhorn/longhorn/issues/9505) - @yangchiu @james-munson
- [BACKPORT][v1.7.2][BUG] Remove unnecessary restart of RWX workload. [9290](https://github.com/longhorn/longhorn/issues/9290) - @yangchiu @james-munson
- [BACKPORT][v1.7.2][BUG] Faulted RWX volume upon creation [9474](https://github.com/longhorn/longhorn/issues/9474) - @yangchiu @james-munson
- [BACKPORT][v1.7.2][BUG] Accidentally encountered a single replica volume backup stuck at progress 17% indefinitely after a node rebooted [9312](https://github.com/longhorn/longhorn/issues/9312) - @yangchiu @ChanYiLin
- [BACKPORT][v1.7.2][BUG] Longhorn thinks node is unschedulable [9382](https://github.com/longhorn/longhorn/issues/9382) - @c3y1huang @roger-ryao

## Misc

- [BACKPORT][v1.7.2][TASK] Fix CVE issues in support bundle [9659](https://github.com/longhorn/longhorn/issues/9659) - @yangchiu @c3y1huang
- [BACKPORT][v1.7.2][TASK] Update CSI components to address CVE issues [9563](https://github.com/longhorn/longhorn/issues/9563) - @derekbit @c3y1huang @chriscchien

## Contributors

- @ChanYiLin 
- @PhanLe1010 
- @a110605 
- @c3y1huang 
- @chriscchien 
- @derekbit 
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