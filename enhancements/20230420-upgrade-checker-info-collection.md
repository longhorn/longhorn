# Upgrade Checker Info Collection

The website https://metrics.longhorn.io/ offers valuable insights into how Longhorn is being utilized, which can be accessed by the public. This information serves as a useful reference for user who are new to Longhorn, as well as those considering upgrading Longhorn or the underlying Kubernetes version. Additionally, it is useful for the Longhorn team to understand how it is being used in the real world.

To gain a deeper understanding of usage patterns, it would be beneficial to gather additional information on volumes, host systems, and features. This data would not only offer insights into how to further improve Longhorn but also provide valuable ideas on how to steer Longhorn development in the right direction.

## Summary

This proposal aims to enhance Longhorn's upgrade checker `extraInfo` by collecting additional information includes node and cluster information, and some Longhorn settings.

This proposal introduces a new setting, `Allow Collecting Longhorn Usage Metrics`, to allow users to enable or disable the collection.

### Related Issues

https://github.com/longhorn/longhorn/issues/5235

## Motivation

### Goals

1. Extend collections of user cluster info during upgrade check.
1. Have a new setting to provide user with option to enable or disable the collection.

### Non-goals [optional]

`None`

## Proposal

1. Collect and sends through upgrade responder request.
   - Node info:
     - Kernel release
     - OS distro
     - Disk types (HDD, SSD, NVMe)
     - Node provider
   - Cluster info:
     - Longhorn namespace UID for adaption rate
     - Number of nodes
     - Longhorn components CPU and memory usage
     - Volumes info; such as access mode, frontend, average snapshot per volume, etc.
     - Some Longhorn settings
1. Introduce new `Allow Collecting Longhorn Usage Metrics` setting.

### User Stories

Users can view how Longhorn is being utilized on https://metrics.longhorn.io/.

Additionally, users have the ability to disable the collection by Longhorn.

### User Experience In Detail

Users can find a list of items that Longhorn collects as extra information in the Longhorn documentation.

Users can enable or disable the collection through the `Allow Collecting Longhorn Usage Metrics` setting. This setting can be configured using the UI or through kubectl, similar to other settings.

### API changes

`None`

## Design

### Implementation Overview

#### `Allow Collecting Longhorn Usage Metrics` Setting

- If this value is set to false, extra information will not be collected.
- Setting definition:
  ```
	DisplayName: "Allow Collecting Longhorn Usage Metrics"
	Description: "Enabling this setting will allow Longhorn to provide additional usage metrics to https://metrics.longhorn.io. This information will help us better understand how Longhorn is being used, which will ultimately contribute to future improvements."
	Category: SettingCategoryGeneral
	Type:     SettingTypeBool
	Required: true
	ReadOnly: false
	Default:  "true"
  ```
#### Extra Info Collection

##### Node Info
The following information is sent from each cluster node:
- Number of disks of different device (`longhorn_node_disk_<hdd/ssd/nvme/unknown>_count`).
  > Note: this value may not be accurate if the cluster node is a virtual machine.
- Host kernel release (`host_kernel_release`)
- Host Os distro (`host_os_distro`)
- Kubernetest node provider (`kubernetes_node_provider`)

##### Cluster Info
The following information is sent from one of the cluster node:
- Longhorn namespace UID (`longhorn_namespace_uid`).
- Number of nodes (`longhorn_node_count`).
- Number of volumes of different access mode (`longhorn_volume_access_mode_<rwo/rwx/unknown>_count`).
- Number of volumes of different data locality (`longhorn_volume_data_locality_<disabled/best_effort/strict_local/unknown>_count`).
- Number of volumes of different frontend (`longhorn_volume_frontend_<blockdev/iscsi>_count`).
- Average volume size (`longhorn_volume_average_size`).
- Average volume actual size (`longhorn_volume_average_actual_size`).
- Average number of snapshots per volume (`longhorn_volume_average_snapshot_count`).
- Average number of replicas per volume (`longhorn_volume_average_number_of_replicas`).
- Average Longhorn component CPU usage (`longhorn_<engine_image/instance_manager/manager/ui>_average_cpu_usage_core`)
- Average Longhorn component CPU usage (`longhorn_<engine_image/instance_manager/manager/ui>_average_memory_usage_mib`)
- Settings (`longhorn_setting_<name>`):
  - Settings to exclude:
    - SettingNameBackupTargetCredentialSecret
    - SettingNameDefaultEngineImage
    - SettingNameDefaultInstanceManagerImage
    - SettingNameDefaultShareManagerImage
    - SettingNameDefaultBackingImageManagerImage
    - SettingNameSupportBundleManagerImage
    - SettingNameCurrentLonghornVersion
    - SettingNameLatestLonghornVersion
    - SettingNameStableLonghornVersions
    - SettingNameDefaultLonghornStaticStorageClass
    - SettingNameDeletingConfirmationFlag
    - SettingNameDefaultDataPath
    - SettingNameUpgradeChecker
    - SettingNameAllowCollectingLonghornUsage
    - SettingNameDisableReplicaRebuild (deprecated)
    - SettingNameGuaranteedEngineCPU (deprecated)
  - Settings that requires processing to identify their general purpose:
    - SettingNameBackupTarget (the backup target type/protocol, ex: cifs, nfs, s3)
  - Settings that should be collected as boolean (true if configured, false if not):
    - SettingNameTaintToleration
    - SettingNameSystemManagedComponentsNodeSelector
    - SettingNameRegistrySecret
    - SettingNamePriorityClass
    - SettingNameStorageNetwork
  - Other settings that should be collected as it is.

Example:
```
name: upgrade_request
time                app_version host_kernel_release  host_os_distro kubernetes_node_provider kubernetes_version longhorn_engine_image_average_cpu_usage_core longhorn_engine_image_average_memory_usage_mib longhorn_instance_manager_average_cpu_usage_core longhorn_instance_manager_average_memory_usage_mib longhorn_manager_average_cpu_usage_core longhorn_manager_average_memory_usage_mib longhorn_namespace_uid               longhorn_node_count longhorn_node_disk_nvme_count longhorn_setting_allow_node_drain_with_last_healthy_replica longhorn_setting_allow_recurring_job_while_volume_detached longhorn_setting_allow_volume_creation_with_degraded_availability longhorn_setting_auto_cleanup_system_generated_snapshot longhorn_setting_auto_delete_pod_when_volume_detached_unexpectedly longhorn_setting_auto_salvage longhorn_setting_backing_image_cleanup_wait_interval longhorn_setting_backing_image_recovery_wait_interval longhorn_setting_backup_compression_method longhorn_setting_backup_concurrent_limit longhorn_setting_backup_target longhorn_setting_backupstore_poll_interval longhorn_setting_concurrent_automatic_engine_upgrade_per_node_limit longhorn_setting_concurrent_replica_rebuild_per_node_limit longhorn_setting_concurrent_volume_backup_restore_per_node_limit longhorn_setting_crd_api_version longhorn_setting_create_default_disk_labeled_nodes longhorn_setting_default_data_locality longhorn_setting_default_replica_count longhorn_setting_disable_revision_counter longhorn_setting_disable_scheduling_on_cordoned_node longhorn_setting_engine_replica_timeout longhorn_setting_failed_backup_ttl longhorn_setting_fast_replica_rebuild_enabled longhorn_setting_guaranteed_engine_manager_cpu longhorn_setting_guaranteed_instance_manager_cpu longhorn_setting_guaranteed_replica_manager_cpu longhorn_setting_kubernetes_cluster_autoscaler_enabled longhorn_setting_node_down_pod_deletion_policy longhorn_setting_node_drain_policy longhorn_setting_orphan_auto_deletion longhorn_setting_priority_class longhorn_setting_recurring_failed_jobs_history_limit longhorn_setting_recurring_successful_jobs_history_limit longhorn_setting_registry_secret longhorn_setting_remove_snapshots_during_filesystem_trim longhorn_setting_replica_auto_balance longhorn_setting_replica_file_sync_http_client_timeout longhorn_setting_replica_replenishment_wait_interval longhorn_setting_replica_soft_anti_affinity longhorn_setting_replica_zone_soft_anti_affinity longhorn_setting_restore_concurrent_limit longhorn_setting_restore_volume_recurring_jobs longhorn_setting_snapshot_data_integrity longhorn_setting_snapshot_data_integrity_cronjob longhorn_setting_snapshot_data_integrity_immediate_check_after_snapshot_creation longhorn_setting_storage_minimal_available_percentage longhorn_setting_storage_network longhorn_setting_storage_over_provisioning_percentage longhorn_setting_storage_reserved_percentage_for_default_disk longhorn_setting_support_bundle_failed_history_limit longhorn_setting_system_managed_components_node_selector longhorn_setting_system_managed_pods_image_pull_policy longhorn_setting_taint_toleration longhorn_ui_average_cpu_usage_core longhorn_ui_average_memory_usage_mib longhorn_volume_access_mode_rwo_count longhorn_volume_average_actual_size longhorn_volume_average_number_of_replicas longhorn_volume_average_size longhorn_volume_average_snapshot_count longhorn_volume_data_locality_disabled_count longhorn_volume_frontend_blockdev_count value
----                ----------- -------------------  -------------- ------------------------ ------------------ -------------------------------------------- ---------------------------------------------- ------------------------------------------------ -------------------------------------------------- --------------------------------------- ----------------------------------------- ----------------------               ------------------- ----------------------------- ----------------------------------------------------------- ---------------------------------------------------------- ----------------------------------------------------------------- ------------------------------------------------------- ------------------------------------------------------------------ ----------------------------- ---------------------------------------------------- ----------------------------------------------------- ------------------------------------------ ---------------------------------------- ------------------------------ ------------------------------------------ ------------------------------------------------------------------- ---------------------------------------------------------- ---------------------------------------------------------------- -------------------------------- -------------------------------------------------- -------------------------------------- -------------------------------------- ----------------------------------------- ---------------------------------------------------- --------------------------------------- ---------------------------------- --------------------------------------------- ---------------------------------------------- ------------------------------------------------ ----------------------------------------------- ------------------------------------------------------ ---------------------------------------------- ---------------------------------- ------------------------------------- ------------------------------- ---------------------------------------------------- -------------------------------------------------------- -------------------------------- -------------------------------------------------------- ------------------------------------- ------------------------------------------------------ ---------------------------------------------------- ------------------------------------------- ------------------------------------------------ ----------------------------------------- ---------------------------------------------- ---------------------------------------- ------------------------------------------------ -------------------------------------------------------------------------------- ----------------------------------------------------- -------------------------------- ----------------------------------------------------- ------------------------------------------------------------- ---------------------------------------------------- -------------------------------------------------------- ------------------------------------------------------ --------------------------------- ---------------------------------- ------------------------------------ ------------------------------------- ----------------------------------- ------------------------------------------ ---------------------------- -------------------------------------- -------------------------------------------- --------------------------------------- -----
1683598256887331729 v1.5.0-dev  5.3.18-59.37-default "sles"         k3s                      v1.23.15+k3s1      5m                                           11                                             4m                                               83                                                 22m                                     85                                        1b96b299-b785-468b-ab80-b5b5b12fbe00 3                   1                             false                                                       false                                                      true                                                              true                                                    true                                                               true                          60                                                   300                                                   lz4                                        5                                        none                           300                                        0                                                                   5                                                          5                                                                longhorn.io/v1beta2              false                                              disabled                               3                                      false                                     true                                                 8                                       1440                               true                                          12                                             12                                               12                                              false                                                  do-nothing                                     block-if-contains-last-replica     false                                 false                           1                                                    1                                                        false                            false                                                    disabled                              30                                                     600                                                  false                                       true                                             5                                         false                                          fast-check                               0 0 */7 * *                                      false                                                                            25                                                    false                            200                                                   30                                                            1                                                    false                                                    if-not-present                                         false                             0                                  4                                    3                                     79816021                            2                                          8589934592                   0                                      3                                            3                                       1
1683598257082240493 v1.5.0-dev  5.3.18-59.37-default "sles"         k3s                      v1.23.15+k3s1                                                                                                                                                                                                                                                                                                                                                 1                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    1
1683598257825718008 v1.5.0-dev  5.3.18-59.37-default "sles"         k3s                      v1.23.15+k3s1                                                                                                                                                                                                                                                                                                                                                 1                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    1
```

### Test plan

1. Set up the upgrade responder server.
1. Verify the database when the `Allow Collecting Longhorn Usage Metrics` setting is enabled or disabled.

### Upgrade strategy

`None`

## Note [optional]

`None`
