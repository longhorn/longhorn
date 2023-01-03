## Release Note
**v1.4.0 released!** 🎆

This release introduces many enhancements, improvements, and bug fixes as described below about stability, performance, data integrity, troubleshooting, and so on. Please try it and feedback. Thanks for all the contributions!

- [Kubernetes 1.25 Support](https://github.com/longhorn/longhorn/issues/4003) [[doc]](https://longhorn.io/docs/1.4.0/deploy/important-notes/#pod-security-policies-disabled--pod-security-admission-introduction)
  In the previous versions, Longhorn relies on Pod Security Policy (PSP) to authorize Longhorn components for privileged operations. From Kubernetes 1.25, PSP has been removed and replaced with Pod Security Admission (PSA). Longhorn v1.4.0 supports opt-in PSP enablement, so it can support Kubernetes versions with or without PSP.

- [ARM64 GA](https://github.com/longhorn/longhorn/issues/4206)
  ARM64 has been experimental from Longhorn v1.1.0. After receiving more user feedback and increasing testing coverage, ARM64 distribution has been stabilized with quality as per our regular regression testing, so it is qualified for general availability.

- [RWX GA](https://github.com/longhorn/longhorn/issues/2293) [[lep]](https://github.com/longhorn/longhorn/blob/master/enhancements/20220727-dedicated-recovery-backend-for-rwx-volume-nfs-server.md)[[doc]](https://longhorn.io/docs/1.4.0/advanced-resources/rwx-workloads/)
  RWX has been experimental from Longhorn v1.1.0, but it lacks availability support when the Longhorn Share Manager component behind becomes unavailable. Longhorn v1.4.0 supports NFS recovery backend based on Kubernetes built-in resource, ConfigMap, for recovering NFS client connection during the fail-over period. Also, the NFS client hard mode introduction will further avoid previous potential data loss. For the detail, please check the issue and enhancement proposal.

- [Volume Snapshot Checksum](https://github.com/longhorn/longhorn/issues/4210) [[lep]](https://github.com/longhorn/longhorn/blob/master/enhancements/20220922-snapshot-checksum-and-bit-rot-detection.md)[[doc]](https://longhorn.io/docs/1.4.0/references/settings/#snapshot-data-integrity)
  Data integrity is a continuous effort for Longhorn. In this version, Snapshot Checksum has been introduced w/ some settings to allow users to enable or disable checksum calculation with different modes.

- [Volume Bit-rot Protection](https://github.com/longhorn/longhorn/issues/3198) [[lep]](https://github.com/longhorn/longhorn/blob/master/enhancements/20220922-snapshot-checksum-and-bit-rot-detection.md)[[doc]](https://longhorn.io/docs/1.4.0/references/settings/#snapshot-data-integrity)
  When enabling the Volume Snapshot Checksum feature, Longhorn will periodically calculate and check the checksums of volume snapshots, find corrupted snapshots, then fix them.

- [Volume Replica Rebuilding Speedup](https://github.com/longhorn/longhorn/issues/4783)
  When enabling the Volume Snapshot Checksum feature, Longhorn will use the calculated snapshot checksum to avoid needless snapshot replication between nodes for improving replica rebuilding speed and resource consumption.

- [Volume Trim](https://github.com/longhorn/longhorn/issues/836) [[lep]](https://github.com/longhorn/longhorn/blob/master/enhancements/20221103-filesystem-trim.md)[[doc]](https://longhorn.io/docs/1.4.0/volumes-and-nodes/trim-filesystem/#trim-the-filesystem-in-a-longhorn-volume)
  Longhorn engine supports UNMAP SCSI command to reclaim space from the block volume.

- [Online Volume Expansion](https://github.com/longhorn/longhorn/issues/1674) [[doc]](https://longhorn.io/docs/1.4.0/volumes-and-nodes/expansion)
  Longhorn engine supports optional parameters to pass size expansion requests when updating the volume frontend to support online volume expansion and resize the filesystem via CSI node driver.

- [Local Volume via Data Locality Strict Mode](https://github.com/longhorn/longhorn/issues/3957) [[lep]](https://github.com/longhorn/longhorn/blob/master/enhancements/20200819-keep-a-local-replica-to-engine.md)[[doc]](https://longhorn.io/docs/1.4.0/references/settings/#default-data-locality)
  Local volume is based on a new Data Locality setting, Strict Local. It will allow users to create one replica volume staying in a consistent location, and the data transfer between the volume frontend and engine will be through a local socket instead of the TCP stack to improve performance and reduce resource consumption.

- [Volume Recurring Job Backup Restore](https://github.com/longhorn/longhorn/issues/2227) [[lep]](https://github.com/longhorn/longhorn/blob/master/enhancements/20201002-allow-recurring-backup-detached-volumes.md)[[doc]](https://longhorn.io/docs/1.4.0/snapshots-and-backups/backup-and-restore/restore-recurring-jobs-from-a-backup/)
  Recurring jobs binding to a volume can be backed up to the remote backup target together with the volume backup metadata. They can be restored back as well for a better operation experience.

- [Volume IO Metrics](https://github.com/longhorn/longhorn/issues/2406) [[doc]](https://longhorn.io/docs/1.4.0/monitoring/metrics/#volume)
  Longhorn enriches Volume metrics by providing real-time IO stats including IOPS, latency, and throughput of R/W IO. Users can set up a monotoning solution like Prometheus to monitor volume performance.

- [Longhorn System Backup & Restore](https://github.com/longhorn/longhorn/issues/1455) [[lep]](https://github.com/longhorn/longhorn/blob/master/enhancements/20220913-longhorn-system-backup-restore.md)[[doc]](https://longhorn.io/docs/1.4.0/advanced-resources/system-backup-restore/)
  Users can back up the longhorn system to the remote backup target. Afterward, it's able to restore back to an existing cluster in place or a new cluster for specific operational purposes.

- [Support Bundle Enhancement](https://github.com/longhorn/longhorn/issues/2759) [[lep]](https://github.com/longhorn/longhorn/blob/master/enhancements/20221109-support-bundle-enhancement.md)
  Longhorn introduces a new support bundle integration based on a general [support bundle kit](https://github.com/rancher/support-bundle-kit) solution. This can help us collect more complete troubleshooting info and simulate the cluster environment.

- [Tunable Timeout between Engine and Replica](https://github.com/longhorn/longhorn/issues/4491) [[doc]](https://longhorn.io/docs/1.4.0/references/settings/#engine-to-replica-timeout)
  In the current Longhorn versions, the default timeout between the Longhorn engine and replica is fixed without any exposed user settings. This will potentially bring some challenges for users having a low-spec infra environment. By exporting the setting configurable, it will allow users adaptively tune the stability of volume operations.

## Installation

> **Please ensure your Kubernetes cluster is at least v1.21 before installing Longhorn v1.4.0.**

Longhorn supports 3 installation ways including Rancher App Marketplace, Kubectl, and Helm. Follow the installation instructions [here](https://longhorn.io/docs/1.4.0/deploy/install/).

## Upgrade

> **Please ensure your Kubernetes cluster is at least v1.21 before upgrading to Longhorn v1.4.0 from v1.3.x. Only support upgrading from 1.3.x.**

Follow the upgrade instructions [here](https://longhorn.io/docs/1.4.0/deploy/upgrade/).

## Deprecation & Incompatibilities

- Pod Security Policy is an opt-in setting. If installing Longhorn with PSP support, need to enable it first.
- The built-in CSI Snapshotter sidecar is upgraded to v5.0.1. The v1beta1 version of Volume Snapshot custom resource is deprecated but still supported. However, it will be removed after upgrading CSI Snapshotter to 6.1 or later versions in the future, so please start using v1 version instead before the deprecated version is removed.

## Known Issues after Release

Please follow up on [here](https://github.com/longhorn/longhorn/wiki/Outstanding-Known-Issues-of-Releases) about any outstanding issues found after this release.

## Highlights

- [FEATURE] Reclaim/Shrink space of volume ([836](https://github.com/longhorn/longhorn/issues/836)) - @yangchiu @derekbit @smallteeths @shuo-wu
- [FEATURE] Backup/Restore Longhorn System ([1455](https://github.com/longhorn/longhorn/issues/1455)) - @c3y1huang @khushboo-rancher
- [FEATURE] Online volume expansion ([1674](https://github.com/longhorn/longhorn/issues/1674)) - @shuo-wu @chriscchien
- [FEATURE] Record recurring schedule in the backups and allow user choose to use it for the restored volume ([2227](https://github.com/longhorn/longhorn/issues/2227)) - @yangchiu @mantissahz
- [FEATURE] NFS support (RWX) GA ([2293](https://github.com/longhorn/longhorn/issues/2293)) - @derekbit @chriscchien
- [FEATURE] Support metrics for Volume IOPS, throughput and latency real time ([2406](https://github.com/longhorn/longhorn/issues/2406)) - @derekbit @roger-ryao
- [FEATURE] Support bundle enhancement ([2759](https://github.com/longhorn/longhorn/issues/2759)) - @c3y1huang @chriscchien
- [FEATURE] Automatic identifying of corrupted replica (bit rot detection) ([3198](https://github.com/longhorn/longhorn/issues/3198)) - @yangchiu @derekbit
- [FEATURE] Local volume for distributed data workloads ([3957](https://github.com/longhorn/longhorn/issues/3957)) - @derekbit @chriscchien
- [IMPROVEMENT] Support K8s 1.25 by updating removed deprecated resource versions like PodSecurityPolicy ([4003](https://github.com/longhorn/longhorn/issues/4003)) - @PhanLe1010 @chriscchien
- [IMPROVEMENT] Faster resync time for fresh replica rebuilding ([4092](https://github.com/longhorn/longhorn/issues/4092)) - @yangchiu @derekbit
- [FEATURE] Introduce checksum for snapshots ([4210](https://github.com/longhorn/longhorn/issues/4210)) - @derekbit @roger-ryao
- [FEATURE] Update K8s version support and component/pkg/build dependencies ([4239](https://github.com/longhorn/longhorn/issues/4239)) - @yangchiu @PhanLe1010
- [BUG] data corruption due to COW and block size not being aligned during rebuilding replicas  ([4354](https://github.com/longhorn/longhorn/issues/4354)) - @PhanLe1010 @chriscchien
- [IMPROVEMENT]  Adjust the iSCSI timeout and the engine-to-replica timeout settings ([4491](https://github.com/longhorn/longhorn/issues/4491)) - @yangchiu @derekbit
- [IMPROVEMENT] Using specific block size in Longhorn volume's filesystem ([4594](https://github.com/longhorn/longhorn/issues/4594)) - @derekbit @roger-ryao
- [IMPROVEMENT] Speed up replica rebuilding by the metadata such as ctime of snapshot disk files ([4783](https://github.com/longhorn/longhorn/issues/4783)) - @yangchiu @derekbit

## Enhancements

- [FEATURE] Configure successfulJobsHistoryLimit of CronJobs ([1711](https://github.com/longhorn/longhorn/issues/1711)) - @weizhe0422 @chriscchien
- [FEATURE] Allow customization of the cipher used by cryptsetup in volume encryption ([3353](https://github.com/longhorn/longhorn/issues/3353)) - @mantissahz @chriscchien
- [FEATURE] New setting to limit the concurrent volume restoring from backup ([4558](https://github.com/longhorn/longhorn/issues/4558)) - @c3y1huang @chriscchien
- [FEATURE] Make FS format options configurable in storage class ([4642](https://github.com/longhorn/longhorn/issues/4642)) - @weizhe0422 @chriscchien

## Improvement

- [IMPROVEMENT] Change the script into a docker run command mentioned in 'recovery from longhorn backup without system installed' doc ([1521](https://github.com/longhorn/longhorn/issues/1521)) - @weizhe0422 @chriscchien
- [IMPROVEMENT] Improve 'recovery from longhorn backup without system installed' doc. ([1522](https://github.com/longhorn/longhorn/issues/1522)) - @weizhe0422 @roger-ryao
- [IMPROVEMENT] Dump NFS ganesha logs to pod stdout ([2380](https://github.com/longhorn/longhorn/issues/2380)) - @weizhe0422 @roger-ryao
- [IMPROVEMENT] Support failed/obsolete orphaned backup cleanup ([3898](https://github.com/longhorn/longhorn/issues/3898)) - @mantissahz @chriscchien
- [IMPROVEMENT] liveness and readiness probes with longhorn csi plugin daemonset ([3907](https://github.com/longhorn/longhorn/issues/3907)) - @c3y1huang @roger-ryao
- [IMPROVEMENT] Longhorn doesn't reuse failed replica on a disk with full allocated space ([3921](https://github.com/longhorn/longhorn/issues/3921)) - @PhanLe1010 @chriscchien
- [IMPROVEMENT] Reduce syscalls while reading and writing requests in longhorn-engine (engine <-> replica) ([4122](https://github.com/longhorn/longhorn/issues/4122)) - @yangchiu @derekbit
- [IMPROVEMENT] Reduce read and write calls in liblonghorn (tgt <-> engine) ([4133](https://github.com/longhorn/longhorn/issues/4133)) - @derekbit
- [IMPROVEMENT] Replace the GCC allocator in liblonghorn with a more efficient memory allocator ([4136](https://github.com/longhorn/longhorn/issues/4136)) - @yangchiu @derekbit
- [DOC] Update Helm readme and document ([4175](https://github.com/longhorn/longhorn/issues/4175)) - @derekbit
- [IMPROVEMENT] Purging a volume before rebuilding starts ([4183](https://github.com/longhorn/longhorn/issues/4183)) - @yangchiu @shuo-wu
- [IMPROVEMENT] Schedule volumes based on available disk space ([4185](https://github.com/longhorn/longhorn/issues/4185)) - @yangchiu @c3y1huang
- [IMPROVEMENT] Recognize default toleration and node selector to allow Longhorn run on the RKE mixed cluster ([4246](https://github.com/longhorn/longhorn/issues/4246)) - @c3y1huang @chriscchien
- [IMPROVEMENT] Support bundle doesn't collect the snapshot yamls ([4285](https://github.com/longhorn/longhorn/issues/4285)) - @yangchiu @PhanLe1010
- [IMPROVEMENT] Avoid accidentally deleting engine images that are still in use ([4332](https://github.com/longhorn/longhorn/issues/4332)) - @derekbit @chriscchien
- [IMPROVEMENT] Show non-JSON error from backup store ([4336](https://github.com/longhorn/longhorn/issues/4336)) - @c3y1huang
- [IMPROVEMENT] Update nfs-ganesha to v4.0 ([4351](https://github.com/longhorn/longhorn/issues/4351)) - @derekbit
- [IMPROVEMENT] show error when failed to init frontend ([4362](https://github.com/longhorn/longhorn/issues/4362)) - @c3y1huang
- [IMPROVEMENT]  Too many debug-level log messages in engine instance-manager ([4427](https://github.com/longhorn/longhorn/issues/4427)) - @derekbit @chriscchien
- [IMPROVEMENT] Add prep work for fixing the corrupted filesystem using fsck in KB ([4440](https://github.com/longhorn/longhorn/issues/4440)) - @derekbit
- [IMPROVEMENT] Prevent users from accidentally uninstalling Longhorn ([4509](https://github.com/longhorn/longhorn/issues/4509)) - @yangchiu @PhanLe1010
- [IMPROVEMENT] add possibility to use nodeSelector on the storageClass ([4574](https://github.com/longhorn/longhorn/issues/4574)) - @weizhe0422 @roger-ryao
- [IMPROVEMENT] Check if node schedulable condition is set before trying to read it ([4581](https://github.com/longhorn/longhorn/issues/4581)) - @weizhe0422 @roger-ryao
- [IMPROVEMENT] Review/consolidate  the sectorSize in replica server, replica volume, and engine ([4599](https://github.com/longhorn/longhorn/issues/4599)) - @yangchiu @derekbit
- [IMPROVEMENT] Reorganize longhorn-manager/k8s/patches and auto-generate preserveUnknownFields field ([4600](https://github.com/longhorn/longhorn/issues/4600)) - @yangchiu @derekbit
- [IMPROVEMENT] share-manager pod bypasses the kubernetes scheduler ([4789](https://github.com/longhorn/longhorn/issues/4789)) - @joshimoo @chriscchien
- [IMPROVEMENT] Unify the format of returned error messages in longhorn-engine ([4828](https://github.com/longhorn/longhorn/issues/4828)) - @derekbit
- [IMPROVEMENT] Longhorn system backup/restore UI ([4855](https://github.com/longhorn/longhorn/issues/4855)) - @smallteeths
- [IMPROVEMENT] Replace the modTime (mtime) with ctime in snapshot hash ([4934](https://github.com/longhorn/longhorn/issues/4934)) - @derekbit @chriscchien
- [BUG] volume is stuck in attaching/detaching loop with error `Failed to init frontend: device...` ([4959](https://github.com/longhorn/longhorn/issues/4959)) - @derekbit @PhanLe1010 @chriscchien
- [IMPROVEMENT] Affinity in the longhorn-ui deployment within the helm chart ([4987](https://github.com/longhorn/longhorn/issues/4987)) - @mantissahz @chriscchien
- [IMPROVEMENT] Allow users to change volume.spec.snapshotDataIntegrity on UI ([4994](https://github.com/longhorn/longhorn/issues/4994)) - @yangchiu @smallteeths
- [IMPROVEMENT] Backup and restore recurring jobs on UI ([5009](https://github.com/longhorn/longhorn/issues/5009)) - @smallteeths @chriscchien
- [IMPROVEMENT] Disable `Automatically Delete Workload Pod when The Volume Is Detached Unexpectedly` for RWX volumes ([5017](https://github.com/longhorn/longhorn/issues/5017)) - @derekbit @chriscchien
- [IMPROVEMENT] Enable fast replica rebuilding by default ([5023](https://github.com/longhorn/longhorn/issues/5023)) - @derekbit @roger-ryao
- [IMPROVEMENT] Upgrade tcmalloc in longhorn-engine ([5050](https://github.com/longhorn/longhorn/issues/5050)) - @derekbit
- [IMPROVEMENT] UI show error when backup target is empty for system backup ([5056](https://github.com/longhorn/longhorn/issues/5056)) - @smallteeths @khushboo-rancher
- [IMPROVEMENT] System restore job name should be Longhorn prefixed ([5057](https://github.com/longhorn/longhorn/issues/5057)) - @c3y1huang @khushboo-rancher
- [BUG] Error in logs while restoring the system backup ([5061](https://github.com/longhorn/longhorn/issues/5061)) - @c3y1huang @chriscchien
- [IMPROVEMENT] Add warning message to when deleting the restoring backups ([5065](https://github.com/longhorn/longhorn/issues/5065)) - @smallteeths @khushboo-rancher @roger-ryao
- [IMPROVEMENT] Inconsistent name convention across volume backup restore and system backup restore ([5066](https://github.com/longhorn/longhorn/issues/5066)) - @smallteeths @roger-ryao
- [IMPROVEMENT] System restore should proceed to restore other volumes if restoring one volume keeps failing for a certain time. ([5086](https://github.com/longhorn/longhorn/issues/5086)) - @c3y1huang @khushboo-rancher @roger-ryao
- [IMPROVEMENT] Support customized number of replicas of webhook and recovery-backend ([5087](https://github.com/longhorn/longhorn/issues/5087)) - @derekbit @chriscchien
- [IMPROVEMENT] Simplify the page by placing some configuration items in the advanced configuration when creating the volume ([5090](https://github.com/longhorn/longhorn/issues/5090)) - @yangchiu @smallteeths
- [IMPROVEMENT] Support replica sync client timeout setting to stabilize replica rebuilding ([5110](https://github.com/longhorn/longhorn/issues/5110)) - @derekbit @chriscchien
- [IMPROVEMENT] Set a newly created volume's data integrity from UI to `ignored` rather than `Fast-Check`. ([5126](https://github.com/longhorn/longhorn/issues/5126)) - @yangchiu @smallteeths

## Performance

- [BUG] Turn a node down and up, workload takes longer time to come back online in Longhorn v1.2.0 ([2947](https://github.com/longhorn/longhorn/issues/2947)) - @yangchiu @PhanLe1010
- [TASK] RWX volume performance measurement and investigation ([3665](https://github.com/longhorn/longhorn/issues/3665)) - @derekbit
- [TASK] Verify spinning disk/HDD via the current e2e regression ([4182](https://github.com/longhorn/longhorn/issues/4182)) - @yangchiu
- [BUG] test_csi_snapshot_snap_create_volume_from_snapshot failed when using HDD as Longhorn disks ([4227](https://github.com/longhorn/longhorn/issues/4227)) - @yangchiu @PhanLe1010
- [TASK] Disable tcmalloc in data path because newer tcmalloc version leads to performance drop ([5096](https://github.com/longhorn/longhorn/issues/5096)) - @derekbit @chriscchien

## Stability

- [BUG] Longhorn won't fail all replicas if there is no valid backend during the engine starting stage ([1330](https://github.com/longhorn/longhorn/issues/1330)) - @derekbit @roger-ryao
- [BUG] Every other backup fails and crashes the volume (Segmentation Fault) ([1768](https://github.com/longhorn/longhorn/issues/1768)) - @olljanat @mantissahz
- [BUG] Backend sizes do not match 5368709120 != 10737418240 in the engine initiation phase ([3601](https://github.com/longhorn/longhorn/issues/3601)) - @derekbit @chriscchien
- [BUG] Somehow the Rebuilding field inside volume.meta is set to true causing the volume to stuck in attaching/detaching loop ([4212](https://github.com/longhorn/longhorn/issues/4212)) - @yangchiu @derekbit
- [BUG] Engine binary cannot be recovered after being removed accidentally ([4380](https://github.com/longhorn/longhorn/issues/4380)) - @yangchiu @c3y1huang
- [TASK] Disable tcmalloc in longhorn-engine and longhorn-instance-manager ([5068](https://github.com/longhorn/longhorn/issues/5068)) - @derekbit

## Bugs

- [BUG] Removing old instance records after the new IM pod is launched will take 1 minute ([1363](https://github.com/longhorn/longhorn/issues/1363)) - @mantissahz
- [BUG] Restoring volume stuck forever if the backup is already deleted. ([1867](https://github.com/longhorn/longhorn/issues/1867)) - @mantissahz @chriscchien
- [BUG] Duplicated default instance manager leads to engine/replica cannot be started ([3000](https://github.com/longhorn/longhorn/issues/3000)) - @PhanLe1010 @roger-ryao
- [BUG] Restore from backup sometimes failed if having high frequent recurring backup job w/ retention ([3055](https://github.com/longhorn/longhorn/issues/3055)) - @mantissahz @roger-ryao
- [BUG] Newly created backup stays in `InProgress` when the volume deleted before backup finished ([3122](https://github.com/longhorn/longhorn/issues/3122)) - @mantissahz @chriscchien
- [Bug] Degraded volume generate failed replica make volume unschedulable ([3220](https://github.com/longhorn/longhorn/issues/3220)) - @derekbit @chriscchien
- [BUG] The default access mode of a restored RWX volume is RWO ([3444](https://github.com/longhorn/longhorn/issues/3444)) - @weizhe0422 @roger-ryao
- [BUG] Replica rebuilding failure with error "Replica must be closed, Can not add in state: open" ([3828](https://github.com/longhorn/longhorn/issues/3828)) - @mantissahz @roger-ryao
- [BUG] Max length of volume name not consist between frontend and backend ([3917](https://github.com/longhorn/longhorn/issues/3917)) - @weizhe0422 @roger-ryao
- [BUG] Can't delete volumesnapshot if backup removed first  ([4107](https://github.com/longhorn/longhorn/issues/4107)) - @weizhe0422 @chriscchien
- [BUG] A IM-proxy connection not closed in full regression 1.3 ([4113](https://github.com/longhorn/longhorn/issues/4113)) - @c3y1huang @chriscchien
- [BUG] Scale replica warning ([4120](https://github.com/longhorn/longhorn/issues/4120)) - @c3y1huang @chriscchien
- [BUG] Wrong nodeOrDiskEvicted collected in node monitor ([4143](https://github.com/longhorn/longhorn/issues/4143)) - @yangchiu @derekbit
- [BUG] Misleading log "BUG: replica is running but storage IP is empty" ([4153](https://github.com/longhorn/longhorn/issues/4153)) - @shuo-wu @chriscchien
- [BUG] longhorn-manager cannot start while upgrading if the configmap contains volume sensitive settings ([4160](https://github.com/longhorn/longhorn/issues/4160)) - @derekbit @chriscchien
- [BUG] Replica stuck in buggy state with status.currentState is error and the spec.desireState is running ([4197](https://github.com/longhorn/longhorn/issues/4197)) - @yangchiu @PhanLe1010
- [BUG] After updating longhorn to version 1.3.0, only 1 node had problems and I can't even delete it ([4213](https://github.com/longhorn/longhorn/issues/4213)) - @derekbit @c3y1huang @chriscchien
- [BUG] Unable to use a TTY error when running environment_check.sh ([4216](https://github.com/longhorn/longhorn/issues/4216)) - @flkdnt @chriscchien
- [BUG] The last healthy replica may be evicted or removed ([4238](https://github.com/longhorn/longhorn/issues/4238)) - @yangchiu @shuo-wu
- [BUG] Volume detaching and attaching repeatedly while creating multiple snapshots with a same id ([4250](https://github.com/longhorn/longhorn/issues/4250)) - @yangchiu @derekbit
- [BUG] Backing image is not deleted and recreated correctly ([4256](https://github.com/longhorn/longhorn/issues/4256)) - @shuo-wu @chriscchien
- [BUG] longhorn-ui fails to start on RKE2 with cis-1.6 profile for Longhorn v1.3.0 with helm install ([4266](https://github.com/longhorn/longhorn/issues/4266)) - @yangchiu @mantissahz
- [BUG] Longhorn volume stuck in deleting state ([4278](https://github.com/longhorn/longhorn/issues/4278)) - @yangchiu @PhanLe1010
- [BUG]  the IP address is duplicate when using storage network and the second network is contronllerd by ovs-cni. ([4281](https://github.com/longhorn/longhorn/issues/4281)) - @mantissahz
- [BUG] build longhorn-ui image error ([4283](https://github.com/longhorn/longhorn/issues/4283)) - @smallteeths
- [BUG] Wrong conditions in the Chart default-setting manifest for Rancher deployed Windows Cluster feature ([4289](https://github.com/longhorn/longhorn/issues/4289)) - @derekbit @chriscchien
- [BUG] Volume operations/rebuilding error during eviction ([4294](https://github.com/longhorn/longhorn/issues/4294)) - @yangchiu @shuo-wu
- [BUG] longhorn-manager deletes same pod multi times when rebooting ([4302](https://github.com/longhorn/longhorn/issues/4302)) - @mantissahz @w13915984028
- [BUG] test_setting_backing_image_auto_cleanup failed because the backing image file isn't deleted on the corresponding node as expected ([4308](https://github.com/longhorn/longhorn/issues/4308)) - @shuo-wu @chriscchien
- [BUG] After automatically force delete terminating pods of deployment on down node, data lost and I/O error ([4384](https://github.com/longhorn/longhorn/issues/4384)) - @yangchiu @derekbit @PhanLe1010
- [BUG] Volume can not attach to node when engine image DaemonSet pods are not fully deployed ([4386](https://github.com/longhorn/longhorn/issues/4386)) - @PhanLe1010 @chriscchien
- [BUG] Error/warning during uninstallation of Longhorn v1.3.1 via manifest ([4405](https://github.com/longhorn/longhorn/issues/4405)) - @PhanLe1010 @roger-ryao
- [BUG] can't upgrade engine if a volume was created in Longhorn v1.0 and the volume.spec.dataLocality is `""` ([4412](https://github.com/longhorn/longhorn/issues/4412)) - @derekbit @chriscchien
- [BUG] Confusing description the label for replica delition ([4430](https://github.com/longhorn/longhorn/issues/4430)) - @yangchiu @smallteeths
- [BUG] Update the Longhorn document in Using the Environment Check Script ([4450](https://github.com/longhorn/longhorn/issues/4450)) - @weizhe0422 @roger-ryao
- [BUG] Unable to search 1.3.1 doc by algolia ([4457](https://github.com/longhorn/longhorn/issues/4457)) - @mantissahz @roger-ryao
- [BUG] Misleading message "The volume is in expansion progress from size 20Gi to 10Gi" if the expansion is invalid ([4475](https://github.com/longhorn/longhorn/issues/4475)) - @yangchiu @smallteeths
- [BUG] Flaky case test_autosalvage_with_data_locality_enabled ([4489](https://github.com/longhorn/longhorn/issues/4489)) - @weizhe0422
- [BUG] Continuously rebuild when auto-balance==least-effort and existing node becomes unschedulable ([4502](https://github.com/longhorn/longhorn/issues/4502)) - @yangchiu @c3y1huang
- [BUG] Inconsistent system snapshots between replicas after rebuilding ([4513](https://github.com/longhorn/longhorn/issues/4513)) - @derekbit
- [BUG] Prometheus metric for backup state (longhorn_backup_state) returns wrong values ([4521](https://github.com/longhorn/longhorn/issues/4521)) - @mantissahz @roger-ryao
- [BUG] Longhorn accidentally schedule all replicas onto a worker node even though the setting Replica Node Level Soft Anti-Affinity is currently disabled ([4546](https://github.com/longhorn/longhorn/issues/4546)) - @yangchiu @mantissahz
- [BUG] LH continuously reports `invalid customized default setting taint-toleration` ([4554](https://github.com/longhorn/longhorn/issues/4554)) - @weizhe0422 @roger-ryao
- [BUG] the values.yaml in the longhorn helm chart contains values not used. ([4601](https://github.com/longhorn/longhorn/issues/4601)) - @weizhe0422 @roger-ryao
- [BUG] longhorn-engine integration test test_restore_to_file_with_backing_file failed after upgrade to sles 15.4 ([4632](https://github.com/longhorn/longhorn/issues/4632)) - @mantissahz
- [BUG] Can not pull a backup created by another Longhorn system from the remote backup target ([4637](https://github.com/longhorn/longhorn/issues/4637)) - @yangchiu @mantissahz @roger-ryao
- [BUG] Fix the share-manager deletion failure if the confimap is not existing ([4648](https://github.com/longhorn/longhorn/issues/4648)) - @derekbit @roger-ryao
- [BUG] Updating volume-scheduling-error failure for RWX volumes and expanding volumes ([4654](https://github.com/longhorn/longhorn/issues/4654)) - @derekbit @chriscchien
- [BUG] charts/longhorn/questions.yaml include oudated csi-image tags ([4669](https://github.com/longhorn/longhorn/issues/4669)) - @PhanLe1010 @roger-ryao
- [BUG] rebuilding the replica failed after upgrading from 1.2.4 to 1.3.2-rc2 ([4705](https://github.com/longhorn/longhorn/issues/4705)) - @derekbit @chriscchien
- [BUG] Cannot re-run helm uninstallation if the first one failed and cannot fetch logs of failed uninstallation pod ([4711](https://github.com/longhorn/longhorn/issues/4711)) - @yangchiu @PhanLe1010 @roger-ryao
- [BUG] The old instance-manager-r Pods are not deleted after upgrade ([4726](https://github.com/longhorn/longhorn/issues/4726)) - @mantissahz @chriscchien
- [BUG] Replica Auto Balance repeatedly delete the local replica and trigger rebuilding ([4761](https://github.com/longhorn/longhorn/issues/4761)) - @c3y1huang @roger-ryao
- [BUG] Volume metafile getting deleted or empty results in a detach-attach loop ([4846](https://github.com/longhorn/longhorn/issues/4846)) - @mantissahz @chriscchien
- [BUG] Backing image is stuck at `in-progress` status if the provided checksum is incorrect ([4852](https://github.com/longhorn/longhorn/issues/4852)) - @FrankYang0529 @chriscchien
- [BUG] Duplicate channel close error in the backing image manage related components ([4865](https://github.com/longhorn/longhorn/issues/4865)) - @weizhe0422 @roger-ryao
- [BUG] The node ID of backing image data source somehow get changed then lead to file handling failed ([4887](https://github.com/longhorn/longhorn/issues/4887)) - @shuo-wu @chriscchien
- [BUG] Cannot upload a backing image larger than 10G ([4902](https://github.com/longhorn/longhorn/issues/4902)) - @smallteeths @shuo-wu @chriscchien
- [BUG] Failed to build longhorn-instance-manager master branch ([4946](https://github.com/longhorn/longhorn/issues/4946)) - @derekbit
- [BUG] PVC only works with plural annotation `volumes.kubernetes.io/storage-provisioner: driver.longhorn.io` ([4951](https://github.com/longhorn/longhorn/issues/4951)) - @weizhe0422
- [BUG] Failed to create a replenished replica process because of the newly adding option ([4962](https://github.com/longhorn/longhorn/issues/4962)) - @yangchiu @derekbit
- [BUG] Incorrect log messages in longhorn-engine processRemoveSnapshot() ([4980](https://github.com/longhorn/longhorn/issues/4980)) - @derekbit
- [BUG] System backup showing wrong age ([5047](https://github.com/longhorn/longhorn/issues/5047)) - @smallteeths @khushboo-rancher
- [BUG] System backup should validate empty backup target ([5055](https://github.com/longhorn/longhorn/issues/5055)) - @c3y1huang @khushboo-rancher
- [BUG] missing the `restoreVolumeRecurringJob` parameter in the VolumeGet API ([5062](https://github.com/longhorn/longhorn/issues/5062)) - @mantissahz @roger-ryao
- [BUG] System restore stuck in restoring if pvc exists with identical name ([5064](https://github.com/longhorn/longhorn/issues/5064)) - @c3y1huang @roger-ryao
- [BUG] No error shown on UI if system backup conf not available ([5072](https://github.com/longhorn/longhorn/issues/5072)) - @c3y1huang @khushboo-rancher
- [BUG] System restore missing services ([5074](https://github.com/longhorn/longhorn/issues/5074)) - @yangchiu @c3y1huang
- [BUG] In a system restore, PV & PVC are not restored if PVC was created with 'longhorn-static' (created via Longhorn GUI) ([5091](https://github.com/longhorn/longhorn/issues/5091)) - @c3y1huang @khushboo-rancher
- [BUG][v1.4.0-rc1] image security scan CRITICAL issues ([5107](https://github.com/longhorn/longhorn/issues/5107)) - @yangchiu @mantissahz
- [BUG] Snapshot trim wrong label in the volume detail page. ([5127](https://github.com/longhorn/longhorn/issues/5127)) - @smallteeths @chriscchien
- [BUG] Filesystem on the volume with a backing image is corrupted after applying trim operation ([5129](https://github.com/longhorn/longhorn/issues/5129)) - @derekbit @chriscchien
- [BUG] Error in uninstall job ([5132](https://github.com/longhorn/longhorn/issues/5132)) - @c3y1huang @chriscchien
- [BUG] Uninstall job unable to delete the systembackup and systemrestore cr. ([5133](https://github.com/longhorn/longhorn/issues/5133)) - @c3y1huang @chriscchien
- [BUG] Nil pointer dereference error on restoring the system backup ([5134](https://github.com/longhorn/longhorn/issues/5134)) - @yangchiu @c3y1huang
- [BUG] UI option Update Replicas Auto Balance should use capital letter like others ([5154](https://github.com/longhorn/longhorn/issues/5154)) - @smallteeths @chriscchien
- [BUG] System restore cannot roll out when volume name is different to the PV ([5157](https://github.com/longhorn/longhorn/issues/5157)) - @yangchiu @c3y1huang
- [BUG] Online expansion doesn't succeed after a failed expansion ([5169](https://github.com/longhorn/longhorn/issues/5169)) - @derekbit @shuo-wu @khushboo-rancher

## Misc

- [DOC] RWX support for NVIDIA JETSON Ubuntu 18.4LTS kernel requires enabling NFSV4.1 ([3157](https://github.com/longhorn/longhorn/issues/3157)) - @yangchiu @derekbit
- [DOC] Add information about encryption algorithm to documentation ([3285](https://github.com/longhorn/longhorn/issues/3285)) - @mantissahz
- [DOC] Update the doc of volume size after introducing snapshot prune ([4158](https://github.com/longhorn/longhorn/issues/4158)) - @shuo-wu
- [Doc] Update the outdated "Customizing Default Settings" document ([4174](https://github.com/longhorn/longhorn/issues/4174)) - @derekbit
- [TASK] Refresh distro version support for 1.4 ([4401](https://github.com/longhorn/longhorn/issues/4401)) - @weizhe0422
- [TASK] Update official document Longhorn Networking ([4478](https://github.com/longhorn/longhorn/issues/4478)) - @derekbit
- [TASK] Update preserveUnknownFields fields in longhorn-manager CRD manifest  ([4505](https://github.com/longhorn/longhorn/issues/4505)) - @derekbit @roger-ryao
- [TASK] Disable doc search for archived versions < 1.1 ([4524](https://github.com/longhorn/longhorn/issues/4524)) - @mantissahz
- [TASK] Update longhorn components with the latest backupstore ([4552](https://github.com/longhorn/longhorn/issues/4552)) - @derekbit
- [TASK] Update base image of all components from BCI 15.3 to 15.4 ([4617](https://github.com/longhorn/longhorn/issues/4617)) - @yangchiu
- [DOC] Update the Longhorn document in Install with Helm ([4745](https://github.com/longhorn/longhorn/issues/4745)) - @roger-ryao
- [TASK] Create longhornio support-bundle-kit image ([4911](https://github.com/longhorn/longhorn/issues/4911)) - @yangchiu
- [DOC] Add Recurring * Jobs History Limit to setting reference ([4912](https://github.com/longhorn/longhorn/issues/4912)) - @weizhe0422 @roger-ryao
- [DOC] Add Failed Backup TTL to setting reference ([4913](https://github.com/longhorn/longhorn/issues/4913)) - @mantissahz
- [TASK] Create longhornio liveness probe image ([4945](https://github.com/longhorn/longhorn/issues/4945)) - @yangchiu
- [TASK] Make system managed components branch-based build ([5024](https://github.com/longhorn/longhorn/issues/5024)) - @yangchiu
- [TASK] Remove unstable s390x from PR check for all repos ([5040](https://github.com/longhorn/longhorn/issues/5040)) -
- [TASK] Update longhorn-share-manager's nfs-ganesha to V4.2.1 ([5083](https://github.com/longhorn/longhorn/issues/5083)) - @derekbit @mantissahz
- [DOC] Update the Longhorn document in Setting up Prometheus and Grafana ([5158](https://github.com/longhorn/longhorn/issues/5158)) - @roger-ryao

## Contributors

- @FrankYang0529
- @PhanLe1010
- @c3y1huang
- @chriscchien
- @derekbit
- @flkdnt
- @innobead
- @joshimoo
- @khushboo-rancher
- @mantissahz
- @olljanat
- @roger-ryao
- @shuo-wu
- @smallteeths
- @w13915984028
- @weizhe0422
- @yangchiu
