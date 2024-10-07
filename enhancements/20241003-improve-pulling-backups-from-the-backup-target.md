# Improve Pulling Backups From The Remote Backup Target

## Summary

If the NFS server experiences a brief downtime, the backup data stored on the NFS backup target may be deleted. This occurs because, when the NFS server comes back online, attempts to access the backup target might initially return an empty response. This situation indicates potential instability or delay in data availability following the server's recovery, which could impact the reliability of the related backup resources (`BackupVolume`, `BackupBackingImage`, `SystemBackup` and `Backup`) management in the backup target and backup volume controllers. Proper data management should be taken to handle the initial empty responses until full data access is restored.

### Related Issues

https://github.com/longhorn/longhorn/issues/9530

## Motivation

### Goals

Delete only the backup-related resources in the cluster and do not delete anything on the backup target if there is a discrepancy between the backup information in the cluster and that on the backup target.

### Non-goals [optional]

`None`

## Proposal

- Modify the backup target controller to add the label `DeleteCustomResourceOnly` to the `BackupVolume`, `BackupBackingImage`, and `SystemBackup` resources when no such corresponding backups' data on the remote backup target.

- `BackupVolume`:
  1. Modify the backup volume controller to check whether the label `DeleteCustomResourceOnly` is set when deleting the `BackupVolume` resource.
  2. Modify the backup volume controller to add the label `DeleteCustomResourceOnly` to the `Backup` resource when no such backup on the remote backup target.
- `BackupBackingImage`:
  - Modify the backup backing image controller to check whether the label `DeleteCustomResourceOnly` is set when deleting the `BackupBackingImage` resource.
- `SystemBackup`:
  - Modify the system backup controller to check whether the label `DeleteCustomResourceOnly` is set when deleting the `SystemBackup` resource.
- `Backup`:
  - Modify the backup controller to check whether the label `DeleteCustomResourceOnly` is set when deleting the `Backup` resource.

### User Stories

#### Empty Response from Remote NFS Backup Target

The remote NFS server might initially return an empty response after a short downtime. Therefore, the backup data on the remote NFS server will be deleted unexpectedly with the synchronization mechanism of the backup target controller if the response is empty and the remote backup target is available.

After this enhancement, only the related backup resources will be deleted and the remote backup data will not be deleted with the synchronization mechanism.

#### Race Condition between Related Backup Controllers

A race condition which will unexpectedly delete the backup data on the remote backup target exists not only between backup target and backup volume controllers but also between backup volume and backup controllers.  
It will happen when:

    1. Users empty the backup target URL.
    2. The backup target controller start to reconcile the backup target and try to delete the backup volume resources of the backup target.
    3. The backup volume resources are marked as deleted.
    4. Users set the backup target URL as the previous one.
    5. The backup volume controller start to reconcile the deleting backup volumes and the backup target becomes available.
    6. Because the backup target is available, the backup volume controller will delete the backup volume resources with the backups' data on the remote backup target.

What users expect will be:

    1. Emptying the backup target URL will only delete related backups' resources in the cluster
    2. Re-set the backup target URL as the previous one and the related backups' resource will be re-created in the cluster
    3. The backup data on the remote backup target will not be deleted.

After this enhancement, the race condition is not eliminated, but it will not delete the backup data on the remote backup target.

### User Experience In Detail

The user experience will be the same after this enhancement.

- Set up and unset a backup target URL (and the corresponding credential)
  - When a backup target is not available, Longhorn will try to clean up all related backup resources (`BackupVolume`, `BackupBackingImage`, `SystemBackup` and `Backup`) of the backup target in the cluster.
  - When a backup target is available, Longhorn will try to compare related backup resources to the remote backup target:
    - Create related backup resources if they exist on the remote backup target and does not exist in the cluster.
    - Delete related backup resources if they exist in the cluster and does not exist on the remote backup target, and Longhorn will not delete remote backups' data on the backup tart.
- Create and delete a backup:
  - Users can create a backup with the `kubectl` command or Longhorn UI, and creating a corresponding backup volume will be triggered if it is the first backup in the cluster.
  - Users can delete a backup with the `kubectl` command or Longhorn UI,
    - The `Backup` resource in the cluster will be deleted.
    - The backup data on the remote backup target will be deleted when the backup target and corresponding backup volume are available, and the backup is not used for restoring a volume.
- Create and delete a backup backing image or a system backup:
  - Users can create a backup backing image or a system backup with the `kubectl` command or Longhorn UI.
  - Users can delete a backup backing image or a system backup with the `kubectl` command or Longhorn UI,
    - The `BackupBackingImage` or `SystemBackup` resource in the cluster will be deleted.
    - The related backup data on the remote backup target will be deleted when the backup target is available
- Delete a backup volume:
  - Users can delete a backup volume with the `kubectl` command or Longhorn UI,
    - The `BackupVolume` resource in the cluster will be deleted.
    - The related backups' data on the remote backup target will be deleted when the backup target is available.

### API changes

`None`

## Design

### Implementation Overview

These labels will only be added when the backup target is reconciled and the synchronization of related backup resources begins. In other words, when the corresponding data is not found in the remote backup target, or the backup target is no longer available, Longhorn will try to remove the CR and skip the actual data deletion as the aggressive data cleanup is too dangerous.

1. Add labels `DeleteCustomResourceOnly` in the file `types/types.go`:

    ```golang
    ...
    ConfigMapResourceVersionKey = "configmap-resource-version"
    UpdateSettingFromLonghorn   = "update-setting-from-longhorn"

    DeleteCustomResourceOnly = "delete-custom-resource-only"
    ...
    ```

2. At the existed `backup_target_controller`:

    Add corresponding labels for cleaning up the resources when synchronizing the backups' information to the remote backup target.

    - For `BackupVolume`:

      ```golang
      ...
      func (btc *BackupTargetController) syncBackupVolume(backupStoreBackupVolumeNames []string, syncTime metav1.Time, log logrus.FieldLogger) error {
          ...
          for backupVolumeName := range backupVolumesToDelete {

             // Add the label `DeleteCustomResourceOnly` and update the `BackupVolume` resource

            if err = btc.ds.DeleteBackupVolume(backupVolumeName); err != nil {
              return errors.Wrapf(err, "failed to delete backup volume %s from cluster", backupVolumeName)
            }
          }
        ...
      }
      ...
      func (btc *BackupTargetController) cleanupBackupVolumes() error {
        ...
        for backupVolumeName := range clusterBackupVolumes {

          // Add the label `DeleteCustomResourceOnly` and update the `BackupVolume` resource

          if err = btc.ds.DeleteBackupVolume(backupVolumeName); err != nil && !apierrors.IsNotFound(err) {
            errs = append(errs, err.Error())
            continue
          }
        }
        ...
      }
      ...
      ```

    - For `BackupBackingImage`:

      ```golang
      ...
      func (btc *BackupTargetController) syncBackupBackingImage(backupStoreBackingImageNames []string, syncTime metav1.Time, log logrus.FieldLogger) error {
        ...
          for backupBackingImageName := range backupBackingImagesToDelete {

             // Add the label `DeleteCustomResourceOnly` and update the `BackupBackingImageName` resource

            if err = btc.ds.DeleteBackupBackingImage(backupBackingImageName); err != nil {
              return errors.Wrapf(err, "failed to delete backup backing image %s from cluster", backupBackingImageName)
            }
          }
        ...
      }
      ...
      func (btc *BackupTargetController) cleanupBackupBackingImages() error {
        ...
        for backupBackingImageName := range clusterBackupBackingImages {
          
          // Add the label `DeleteCustomResourceOnly` and update the `BackupBackingImage` resource
          
          if err = btc.ds.DeleteBackupBackingImage(backupBackingImageName); err != nil && !apierrors.IsNotFound(err) {
            errs = append(errs, err.Error())
            continue
          }
        }
        ...
      }
      ...
      ```

    - For `SystemBackup`:

      ```golang
      ...
      func (btc *BackupTargetController) syncSystemBackup(backupStoreBackingImageNames []string, syncTime metav1.Time, log logrus.FieldLogger) error {
        ...
        delSystemBackupsInCluster := clusterReadySystemBackupNames.Difference(backupstoreSystemBackupNames)
        for name := range delSystemBackupsInCluster {

          // Add the label `DeleteCustomResourceOnly` and update the `SysytemBackup` resource

          if err = btc.ds.DeleteSystemBackup(name); err != nil {
            return errors.Wrapf(err, "failed to delete SystemBackup %v not exist in backupstore", name)
          }
        }
        ...
      }
      ...
      func (btc *BackupTargetController) cleanupSystemBackups() error {
        ...
        for systemBackup := range systemBackups {

          // Add the label `DeleteCustomResourceOnly` and update the `SystemBackup` resource

          if err = btc.ds.DeleteSystemBackup(systemBackup); err != nil && !apierrors.IsNotFound(err) {
            errs = append(errs, err.Error())
            continue
          }
        }
        ...
      }
      ...
      ```

3. At the existed `backup_volume_controller`:

    - Add the label `DeleteCustomResourceOnly` for cleaning up the backup resource when synchronizing the backups' information to the remote backup target
    - Check if it needs to delete the remote backup volume data when a `BackupVolume` resource is deleting.

        ```golang
        func (bvc *BackupVolumeController) reconcile(backupVolumeName string) (err error) {
          ...
          if !backupVolume.DeletionTimestamp.IsZero() {

            // Get the flag `needCleanupRemoteData` from the label `DeleteCustomResourceOnly` to check if it needs to delete remote backup volume data 
            // if the flag `needCleanupRemoteData` is false, add the label `DeleteCustomResourceOnly` to all backups of the backup volume and update the `Backup` resource

            if err := bvc.ds.DeleteAllBackupsForBackupVolume(backupVolumeName); err != nil {
              return errors.Wrap(err, "failed to delete backups")
            }

            // Modify the judgement to `if needCleanupRemoteData && backupTarget.Spec.BackupTargetURL != "" {`
            if backupTarget.Spec.BackupTargetURL != "" {
              ...
              if err := backupTargetClient.BackupVolumeDelete(backupTargetClient.URL, backupVolumeName, backupTargetClient.Credential); err != nil {
                return errors.Wrap(err, "failed to delete remote backup volume")
              }
            }
            ...
          }
          ...
          backupsToDelete := clustersSet.Difference(backupStoreBackups)
          for backupName := range backupsToDelete {

            // Add the label `DeleteBackupResourceOnly` and update the `Backup` resource

            if err = bvc.ds.DeleteBackup(backupName); err != nil {
              return errors.Wrapf(err, "failed to delete backup %s from cluster", backupName)
            }
          }
          ...
        }
        ```

4. At the existed `backup_controller`:

    - Check if it needs to delete the remote backup data when a `Backup` resource is deleting.

        ```golang
        func (bc *BackupController) reconcile(backupName string) (err error) {
          ...
          if !backup.DeletionTimestamp.IsZero() {
            ...
            // Get the flag `needCleanupRemoteData` from the label `DeleteCustomResourceOnly` to check if it needs to delete remote backup data 
            // Modify the judgement to `if needCleanupRemoteData && backupTarget.Spec.BackupTargetURL != "" &&`
            if backupTarget.Spec.BackupTargetURL != "" &&
              backupVolume != nil && backupVolume.DeletionTimestamp == nil {
              ...
              if err := backupTargetClient.BackupDelete(backupURL, backupTargetClient.Credential); err != nil {
                return errors.Wrap(err, "failed to delete remote backup")
              }
            }
          }
          ...
        }
        ```

5. At the existed `backup_backing_image_controller`:

    - Check if it needs to delete the remote backup backing image data when a `BackupBackingImage` resource is deleting.

        ```golang
        func (bc *BackupBackingImageController) reconcile(backupBackingImageName string) (err error) {
          ...
          if !bbi.DeletionTimestamp.IsZero() {

            // Get the flag `needCleanupRemoteData` from the label `DeleteCustomResourceOnly` to check if it needs to delete remote backup backing image data 
            // Modify the judgement to `if needCleanupRemoteData && backupTarget.Spec.BackupTargetURL != "" {'
            if backupTarget.Spec.BackupTargetURL != "" {
              ...
              if err := backupTargetClient.BackupBackingImageDelete(backupURL); err != nil {
                return errors.Wrap(err, "failed to delete remote backup backing image")
              }
            }
          ...
        }
        ```

6. At the existed `system_backup_controller`:

    - Check if it needs to delete the remote system backup data when a `SystemBackup` resource is deleting.

        ```golang
        func cleanupRemoteSystemBackupFiles(systemBackup *longhorn.SystemBackup, backupTargetClient engineapi.SystemBackupOperationInterface, log logrus.FieldLogger) {
          ...
          // Get the flag `needCleanupRemoteData` from the label `DeleteCustomResourceOnly` to check if it needs to delete remote system backup data 
          if !needCleanupRemoteData {
            return
          }
        }
        ```

### Test plan

1. Preparing a Linux host with NFS service
1. Set the backup target URL with this NFS service.
1. Creating three volume backups.
1. Setting `Backupstore Poll Interval` as 10 seconds
1. On the Linux host with NFS service, pointing `KUBECONFIG` to the Longhorn control plane IP address.
1. On the Linux host with NFS service, executing [monitor_nfs_longhorn_twice.sh](https://github.com/WebberHuang1118/misc-tools/blob/main/backups/monitor_nfs_longhorn_twice.sh), which will perform:
    1. Stopping the NFS Service
    1. Checking Failed to get info from backup store is shown twice on LH manager log
    1. Starting the NFS Service around 59 seconds later
    1. Checking if all LH backups are deleted (both in the backup target and the LH backup CR)

### Upgrade strategy

`None`

## Note [optional]

`None`
