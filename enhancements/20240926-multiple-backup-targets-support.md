# Multiple Backup Targets Support

## Summary

The current Longhorn only supports a single backup target for all volumes. The feature aims to provide multiple backup targets.

### Related Issues

https://github.com/longhorn/longhorn/issues/2317
https://github.com/longhorn/longhorn/issues/5411

## Motivation

Users can choose backup targets to that they want to back up volumes by setting the backup target name of the volumes.

### Goals

- There are different backup targets at the same time on Longhorn.
- Backups can be synchronized from different remote backup targets.
- Snapshots of a volume can be backed up to a specific remote backup target according to the backup target name of the volume.
- A backup can be restored from its remote backup target to be a new volume.

### Non-goals [optional]

- Snapshots of a volume can not be backed up to different remote backup targets concurrently.

## Proposal

1. Allow users to create, delete or modify backup targets.
    - The backup target controller needs to synchronize the backups' information from the remote backup target and create `Backup` CR objects and `BackupVolume` CR objects in the cluster when the backup target is created.
    - When the backup target is deleted, backup target controller needs to delete the `Backup` CR and `BackupVolume` CR objects in the cluster related to the backup target, and backup data will be kept on the remote backup target.
2. Introduce a new field `BackupTarget` in `Status` of the `Backup` CRD to keep backup target information.
    - The field `BackupTarget:` is used to specify the backup target of the backup for the backup information from the `kubectl get` command and Longhorn RESTful APIs.
3. Introduce new fields `BackupTargetName` and `VolumeName` in `Spec` of `BackupVolume` CRD to keep information of the remote backup target and volume name.
    - Different backup targets might have volumes with the same names. The `BackupVolume` object name will be a randomly generated UUID with a prefix. It uses the `BackupTargetName` and `VolumeName` fields to specify the volume on the remote backup target.
4. Introduce new fields `BackupTargetName` and `BackingImage` in `Spec` of `BackupBackingImage` CRD to keep information of the remote backup target and backing image name.
    - Different backup targets might have backing images with the same names. The `BackupBackingImage` object name will be a randomly generated UUID with a prefix. It uses the `BackupTargetName` and `BackingImage` fields to specify the backing image on the remote backup target.
5. Introduce a new field `BackupTargetName` in `Spec` of the `Volume` CRD to mark the default backup target for storing the volume backups.
6. The system backup will be handled by the default backup target.

### User Stories

#### Default Backup Target

The `default` backup target will be created by Longhorn after installing Longhorn, and it will be the default backup target when creating a volume and a system backup. Users need to set up the `default` backup target before creating a new backup target. The settings `backup-target`, `backup-target-credential-secret`, and `backupstore-poll-interval` are still used to set up the `default` backup target, and the setting will be reviewed and updated if the `default` backup target CR is modified.

The `default` backup target can not be deleted by users.

When creating a volume with an empty `BackupTargetName` filed, this filed will be populated with the default backup target name `default`.

#### Create a new backup target

Users need to create/modify backup targets on the page `Setting/Backup Target` as `Setting/Backing Image` via the Longhorn UI or by the manifest. After backup targets are created and synchronized, users can start to create a backup on these remote backup targets.

### User Experience In Detail

#### Create Or Modify Backup Targets By UI

1. There will be an empty default backup target created by Longhorn and users should set up the default backup target before creating a new backup target.
2. User can find the link `Backup Target` in drop down menu of `Setting`.
3. The page `Backup Target` would show backup target name, backup target URL, secret name (credential) for this backup target, poll interval, and availability status.
4. User can create a new backup target on the page `Backup Target` by clicking the button `Create`. User have to fill out the necessary item for the backup target name, and it can be optional for the backup target URL, secret name, and poll interval fields.
5. Users can modify a backup target information by clicking the button `Edit`.
6. Users can delete a backup target by clicking the button `Delete`.
7. Users can not create or modify a backup target with the `BackupTargetURL` that is the same to an existing backup target.
8. Users can not delete the default backup target directly.
9. Users can not modify the backup target name.
10. Users can not modify the `BackupTargetURL` of a backup target that is the same to another one in the cluster.

#### Create Or Modify Backup Targets By CLI

User can the bash command to create or modify a backup target such as below:

```bash
cat <<EOF >>new-backup-target.yaml
apiVersion: longhorn.io/v1beta2
kind: BackupTarget
metadata:
  name: azure-blob-server-001
  namespace: longhorn-system
spec:
  backupTargetURL: azblob://demo@core.windows.net/
  credentialSecret: azblob-secret
  pollInterval: 4m30s
EOF

kubectl apply -f new-backup-target.yaml
```

#### Backup Target Conditions

There is only one backup target condition and one reason now.

```golang
const (
	BackupTargetConditionTypeUnavailable = "Unavailable"
	BackupTargetConditionReasonUnavailable = "Unavailable"
)
```

The condition `BackupTargetConditionTypeUnavailable` will be set to true if the backup target URL is empty or if retrieving backup information from the remote backup target fails due to issues such as a timeout or an unreachable backup target.

#### Create A Backup To Remote Backup Targets By UI

After users click the button `Create Backup` on the `Volume Details` page, the backup will be stored on the remote backup target set in the `BackupTargetName` filed of the volume.

The backup volume will be created and displayed on the `Backup` page if it is the first backup of the volume.

On the `Backup` page, the backup targets are displayed first if one or more backup volumes exist. Clicking a backup target will expand or collapse the list to show the associated backup volumes.

#### Create A Backup To Remote Backup Targets By CLI

1. Create a snapshot of the volume.
2. Create a backup referring to store the snapshot by the manifest as below:

```yaml
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  labels:
    backup-volume: pvc-xxxxxxxx-9ab9-4055-9eb4-558999b09a11
  name: backup-test-001
  namespace: longhorn-system
spec:
  labels:
    longhorn.io/volume-access-mode: rwo
  snapshotName: xxxxxxxx-9a69-4ede-ab88-c9853459462c
```

3. The `status.backupTarget` field will be assigned to match the `spec.backupTargetName` field in the volume of the snapshot after the backup is completed.  
  The field `status.backupTarget` displays the backup target name in the column information of the backup when users run the `kubectl get` command, and populates the backup target name in the backup information returned by the Longhorn RESTful APIs.

#### Create A Backup To Remote Backup Targets By Recurring Jobs

It will store snapshots to the appointed backup target set in the `spec.backupTargetName` of the volume when the recurring job is running.

#### Restore From A Backup From A Remote Backup Target

Restoring from a backup will behave as before. Choose a backup and do the `Restore` operation in drop down menu on UI.

#### Create A Disaster Recovery Volume From A Remote Backup Target By UI

1. In the cluster A, make sure the original volume X has a backup created or has recurring backups scheduled.
2. In `Backup` page of cluster B, choose the backup volume X, then create disaster recovery volume Y with the backup target name.
3. Longhorn will automatically attach the DR volume Y to a random node. Then Longhorn will start polling for the last backup of volume X, and incrementally restore it to the volume Y.

### API changes

- Introduce new APIs `BackupTargetCreate`,`BackupTargetDelete`, `BackupTargetUpdate` and `BackupTargetGet`:

    | API | Input | Output | Comments | HTTP Endpoint |
    | --- | --- | --- | --- | --- |
    | Create | name, backupTargetURL, credentialSecret string, pollInterval time.Duration | err error | Create a new backup target and start to synchronize data | **POST** `/v1/backuptargets/` |
    | Delete | name string | err error | Remove a backup target and its related backup volume and backup CR objects in the cluster | **DELETE** `/v1/backuptargets/{backupTargetName}` |
    | Update | backupTargetURL, credentialSecret string, pollInterval time.Duration | err error | Update the backup targets information | **POST** `/v1/backuptargets/{backupTargetName}?action=backupTargetUpdate` |
    | Get    |  | backupTarget BackupTarget, err error | Get the backup targets information | **GET** `/v1/backuptargets/{backupTargetName}` |

- Modify the APIs `BackupVolumeGet`, `BackupVolumeList`:
  - Add a new field `BackupTargetName` and `VolumeName` in returning `BackupVolume` information for all backup targets that have this backup volume.
- Modify the APIs `BackupGet`:
  - Add a new field `BackupTargetName` in returning `Backup` information.
- Modify the API `SnapshotBackup`:
  - Add a new field `BackupTargetName` in the input `SnapshotInput` and returning `Backup` information.
- Modify the API `BackupBackingImageCreate`, `BackupBackingImageGet` and `BackupBackingImageList`:
  - Add new fields `BackingImage` and `BackupTargetName` in the input `BackupBackingImage`.

  ```golang
    type BackupBackingImage struct {
      client.Resource

      Name             string `json:"name"`
      BackingImage     string `json:"backingImage"`
      BackupTargetName string `json:"backupTargetName"`
      ...
    }
  ```

## Design

### Implementation Overview

#### Custom Resource Definitions

1. Modify the Backup CRD `backups.longhorn.io` to add a new field `BackupTarget` in `Status` for creating a backup. And add a label `LonghornLabelBackupTarget = "backup-target"` for resource listing.

  ```golang
  type BackupStatus struct {
    ...
    // The backup target name.
    BackupTarget string `json:"backupTarget"`
  }
  ```

  ```yaml
  metadata:
    labels:
      longhorn.io/backup-target: the backup target name (string)
      longhorn.io/backup-volume: the volume name (string)
    name: the backup name. (string)
  status:
    backupTarget: the backup target Name. (string)
    ...
  ```

2. Modify the Backup Volume CRD `backupvolumes.longhorn.io` to add new fields `BackupTargetName` and `VolumeName` in `Spec`, and add labels `LonghornLabelBackupTarget` and `LonghornLabelBackupVolume` for resource listing.

  ```golang
    type BackupVolumeSpec struct {
      ...
      SyncRequestedAt metav1.Time `json:"syncRequestedAt"`
      // The backup target name that the backup volume was synced.
      BackupTargetName string `json:"backupTargetName"`
      // The volume name that the backup volume was used to backup.
      VolumeName string `json:"volumeName"`
    }
  ```

  ```yaml
  metadata:
    labels:
      longhorn.io/backup-target: the backup target name (string)
      longhorn.io/backup-volume: the volume name (string)
    name: the backup volume name. (string)
  spec:
    backupTargetName: the backup target Name. (string)
    volumeName: the volume name (string)
    ...
  ```

3. Modify the Backup Backing Image CRD `backupbackingimages.longhorn.io` to add new fields `BackingImage` and `BackupTargetName` in `Spec`, and add labels `LonghornLabelBackupTarget = "backup-target"` and `LonghornLabelBackingImage = "backing-image"`.

  ```golang
  type BackupBackingImageSpec struct {
    ...
    // The backing image name.
    BackingImage string `json:"backingImage"`
    // The backup target name.
    BackupTargetName string `json:"backupTargetName"`
  }
  ```

  ```yaml
  metadata:
    labels:
      longhorn.io/backing-image: the backing image name (string)
      longhorn.io/backup-target: the backup target name (string)
    name: the backup backing image name. (string)
  spec:
    backingImage: the backing image name (string)
    backupTargetName: the backup target Name. (string)
    ...
  ```

4. Modify the Volume CRD `volumes.longhorn.io` to add a new field `BackupTargetName` in `Spec` for a default backup target.

  ```golang
  type VolumeSpec struct {
    // The default backup target name when a backup is created from the volume.
    BackupTargetName int64 `json:"backupTargetName"`
  }
  ```

  ```yaml
  metadata:
    name: the volume name. (string)
  spec:
    backupTargetName: the backup target Name. (string)
  ```

  The `Spec.BackupTargetName` field will default to the backup target when a volume is created with an empty backup target name, and volume backups will be stored in the default backup target. If the `Spec.BackupTargetName` field is updated to a new backup target, subsequent backups will be stored in the new target.

#### Backup Related Controllers

1. Modify the backup target controller to allow adding and deleting an extra backup target.
   - Create pulling backup volume CR objects with a random backup volume name, for example, `bv-xxxxxx-a12345-b12345-xxxxxx` and filling in the fields `Spec.BackupTargetName` and `Spec.VolumeName`, and corresponding labels from the backup target if it does not exist according to the fields `Spec.BackupTargetName` and `Spec.VolumeName`.
   - Create pulling backup backing images with a random backup volume name, for example, `bbi-xxxxxx-a12345-b12345-xxxxxx` from the backup target with filling in the fields `Spec.BackupTargetName` and `Spec.BackingImage`, and corresponding labels if not existing.
   - Remove a backup volume or backup backing image CR object if the corresponding backup target is deleting or the URL of the corresponding backup target is empty.
2. Modify the backup volume controller to tell the backup volume belongs to which backup target and synchronize the backups of the backup volume from remote backup target.
   - Create pulling backups from the backup target with the field `Status.BackupTarget` of the backup target.
   - Clean up backup CR objects in the cluster by the volume name and backup target name when deleting a backup volume or the backup target URL is empty.
3. Modify backup backing image controller
   - Start backing up a backing image with the given backup target name.

### Validating And Mutating Webhook

- If the `Spec.BackupTargetName` field of the Volume CR object is empty, populate it with the default backup target name.
- The volume validator will check if the backup target exists after the volume is created or the field `Spec.BackupTargetName` is updated.

### Test plan

#### Update The Default Backup Target

1. Update the setting `backup-target` with a valid URL of a remote backup target.
2. Update the setting `backup-target-credential-secret` if needed.
3. Check if the default backup target is available.
4. Update the setting `backupstore-poll-interval` and it succeeds.

#### Create And Restore A Backup

1. Set up the default backup target.
2. Create a backup to the default backup target, and it succeeds.
3. Create an extra backup target B which has existing backups.
4. Backups of the default backup target will not be deleted.
5. Existing backups on the extra backup target B can be synchronized back to the cluster.
6. Create a backup to extra backup target B (by setting the `Spec.BackupTargetName` field in the volume first), and it succeeds.
7. Restore a backup from the default backup target, and it succeeds and data is correct.
8. Restore a backup from the extra backup target B, and it succeeds and data is correct.

#### Create A DR Volume

1. Prepare two clusters A and B with Longhorn installed.
2. Set up the default backup target of two clusters with the same remote backup target.
3. Create the volume A and create a backup of the volume A in the cluster A.
4. In the cluster B, create a DR volume after the backup A is synchronized.
5. Write data to the volume A and create a new backup B in the cluster A.
6. Check if the DR volume will synchronize the data in the cluster B.

#### Create And Restore A System Backup

1. Set up the default backup target and an extra backup target A.
2. Create a volume A with the default backup target name and a volume B with the extra backup target name A.
3. Write some data to volume A and volume B.
4. Create a system backup, and it succeeds. (the system backup and the volume A is stored on the default backup target, and the volume B is stored on the backup target A)
5. Restore the system backup, and it succeeds.

### Upgrade strategy

The `default` backup target will not be deleted on old versions Longhorn

- Fill in the field `BackupTarget` in `Status` for existing Backup CR objects and labels with corresponding values of the `default` backup target.
- Fill in the fields `BackupTargetName` and `VolumeName` in `Spec` and labels for existing `BackupVolume` CR objects with corresponding values of the `default` backup target and volume.
- Fill in the fields `BackupTargetName` and `BackingImage` in `Spec` and labels for existing `BackupBackingImage` CR objects with corresponding values of the `default` backup target and backing image.
- Fill in the fields `BackupTargetName` in `Spec` for existing `Volume` CR objects with corresponding values of the `default` backup target.

## Note [optional]

`None`
