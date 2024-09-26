# Multiple Backup Targets Support

## Summary

The current Longhorn only support a single backup target for all volumes. The feature aims to provide multiple backup targets.

### Related Issues

https://github.com/longhorn/longhorn/issues/2317
https://github.com/longhorn/longhorn/issues/5411

## Motivation

Users can choose backup targets to that they want to back up volumes by setting the backup target name of the volumes.

### Goals

- There are different backup targets at the same time on Longhorn.
- Backups can be synchronized from different remote backup targets.
- Snapshots of a volume can be backed up to a specific remote backup target according to the backup target name of the volume.
- A backup can be restored from its remote backup targets to be a new volume.

### Non-goals [optional]

- Snapshots of a volume can not be backed up to different remote backup targets concurrently.

## Proposal

1. Allow users to create, delete or modify backup targets.
    - The backup target controller needs to synchronize the backups' information from the remote backup target and create `Backup` CR objects and `BackupVolume` CR objects in the cluster when the backup target is created.
    - When the backup target is deleted, backup target controller needs to delete the `Backup` CR and `BackupVolume` CR objects in the cluster related to the backup target, and backup data will be kept on the remote backup target.
2. Introduce new fields `ReadOnly` in `Spec` of `BackupTarget` CRD.
    - `ReadOnly` marks that the remote backup target is read-only and users can not create any backups on it.
3. Introduce a new field `BackupTargetName` in `Spec` of the `Backup` CRD to keep backup target information.
    - `BackupTargetName:`: is used to get the backup target of the backup.
4. Introduce new fields `BackupTargetName` and `VolumeName` in `Spec` of `BackupVolume` CRD to keep information of the remote backup target and volume name.
    - Different backup targets might have volumes with the same names.
5. Introduce new fields `BackupTargetName` and `BackingImage` in `Spec` of `BackupBackingImage` CRD to keep information of the remote backup target and backing image name.
    - Different backup targets might have backing images with the same names.
6. Introduce a new field `BackupTargetName` in `Spec` of the `RecurringJob` CRD to keep backup target information.
7. Introduce a new field `BackupTargetName` in `Spec` of the `Volume` CRD to mark the default backup target for storing the volume backups.
8. The system backup will be handled by the default backup target.

### User Stories

User need to create/modify backup targets on the page `Setting/Backup Target` as `Setting/Backing Image` via the Longhorn UI or by the manifest. After backup targets are created and synchronized, users can start to create a backup on these remote backup targets.

### User Experience In Detail

#### Create Or Modify Backup Targets By UI

1. User can find the link `Backup Target` in drop down menu of `Setting`.
2. The page `Backup Target` would show backup target name, backup target URL, secret name (credential) for this backup target, poll interval, and availability status.
3. There will be an empty default backup target created by Longhorn.
4. User can create a new backup target on the page `Backup Target` by clicking the button `Create`. User have to fill out the necessary item for the backup target name, and it can be optional for the backup target URL, secret name, poll interval, and read-only fields.
5. Users can modify a backup target information by clicking the button `Edit`.
6. Users can set the backup target `ReadOnly` true and then users can not create any backups on it.
7. Users can delete a backup target by clicking the button `Delete`.
8. Users can not create or modify a backup target with the `BackupTargetURL` that is the same to an existing backup target.
9. Users can not delete the default backup target directly.
10. Users can not modify the backup target name.
11. Users can not modify the `BackupTargetURL` of a backup target that is the same to another one in the cluster.

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
status:
  readOnly: false
EOF

kubectl apply -f new-backup-target.yaml
```

#### Create A Backup To Remote Backup Targets By UI

After users click the button `Create Backup` on the `Volume Details` page, the backup will be stored on the remote backup target set in the `BackupTargetName` filed of the volume.

#### Create A Backup To Remote Backup Targets By CLI

1. Create a snapshot of the volume first.
2. Create backups to store the snapshot by the manifest as below:

```yaml
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  labels:
    backup-volume: pvc-xxxxxxxx-9ab9-4055-9eb4-558999b09a11
  name: backup-test-001
  namespace: longhorn-system
spec:
  backupTargetName: azure-blob-server-001 # If this field is assigned, it should be the same to the `spec.backupTargetName` field in the volume of the snapshot.
  labels:
    longhorn.io/volume-access-mode: rwo
  snapshotName: xxxxxxxx-9a69-4ede-ab88-c9853459462c
```

3. If the field `spec.backupTargetName` is empty, it will be replaced by the field `spec.backupTargetName` in the volume of the snapshot.
4. If the `spec.backupTargetName` field will be assigned, it should be the same to the `spec.backupTargetName` field in the volume of the snapshot.

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
    | Create | name, backupTargetURL, credentialSecret string, pollInterval time.Duration, readOnly boolean | err error | Create a new backup target and start to synchronize data | **POST** `/v1/backuptargets/` |
    | Delete | name string | err error | Remove a backup target and its related backup volume and backup CR objects in the cluster | **DELETE** `/v1/backuptargets/{backupTargetName}` |
    | Update | backupTargetURL, credentialSecret string, pollInterval time.Duration, readOnly boolean | err error | Update the backup targets information | **POST** `/v1/backuptargets/{backupTargetName}?action=backupTargetUpdate` |
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

1. Modify the Backup CRD `backups.longhorn.io` to add a new field `BackupTargetName` in `Spec` for creating a backup. And add a label `LonghornLabelBackupTarget = "backup-target"` for resource listing.

  ```golang
  type BackupSpec struct {
    ...
    // The backup target name.
    BackupTargetName string `json:"backupTargetName"`
  }
  ```

  ```yaml
  metadata:
    labels:
      longhorn.io/backup-target: the backup target name (string)
    name: the backup name. (string)
  spec:
    backupTargetName: the backup target Name. (string)
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

4. Modify the Backup Target CRD `backuptagets.longhorn.io` to add a new field `ReadOnly` in `Spec`.

  ```golang
  type BackupTargetSpec struct {
    ...
    // ReadOnly indicates if it can create a backup on the remote backup target or not.
    ReadOnly bool `json:"readOnly"`
    ...
  }
  ```

  ```yaml
  metadata:
    name: the backup target name. (string)
  spec:
    readOnly: it is able to create a backup on this remote backup target or not. (boolean)
  ...
  ```

5. Modify the Volume CRD `volumes.longhorn.io` to add a new field `BackupTargetName` in `Spec` for a default backup target.

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

#### Backup Related Controllers

1. Modify the backup target controller to allow adding and deleting an extra backup target.
   - Create pulling backup volume CR objects with a random backup volume name, for example, `bv-xxxxxx-a12345-b12345-xxxxxx` and filling in the fields `Spec.BacupTargetName` and `Spec.VolumeName`, and corresponding labels from the backup target if not exist according to the fields `Spec.BacupTargetName` and `Spec.VolumeName`.
   - Create pulling backup backing images from the backup target with filling in the fields `Spec.BackupTargetName` and `Spec.BackingImage`, and corresponding labels if not exist.
   - Remove a backup volume or backup backing image CR object if the corresponding backup target is deleting or the URL of the corresponding backup target is empty.
2. Modify the backup volume controller to tell the backup volume belongs to which backup target and synchronize the backups of the backup volume from remote backup target.
   - Create pulling backups from the backup target with the field `Spec.backupTargetName` of the backup target.
   - Clean up backup CR objects in the cluster by the volume name and backup target name when deleting a backup volume or the backup target URL is empty.
3. Modify backup backing image controller
   - Start backing up a backing image with the given backup target name.

### Validating And Mutating Webhook

- Fill in the `Spec.BackupTargetName` field of the `Backup` CR object by the `Spec.BackupTargetName` filed in the `Volume` CR object if empty.
- Validate the `Spec.BackupTargetName` field of the `Backup` CR object is the same to the `Spec.BackupTargetName` field in the `Volume` CR object
- Validate the backup target is read-only or not when creating a backup.

### Test plan

1. Create a backup target A.
2. Create a backup to the backup target A, and it succeeds.
3. Create an extra backup target B which has some backups.
4. Backups of the backup target A will not be deleted.
5. Backups on the extra backup target B can be synchronized back to the cluster.
6. Create a backup to extra backup target B (by setting the `Spec.BackupTargetName` field in the volume), and it succeeds.
7. Restore a backup from remote backup target A, and it succeeds and data is correct.
8. Restore a backup from the extra remote backup target B, and it succeeds and data is correct.

### Upgrade strategy

The `default` backup target will not be deleted on old versions Longhorn

- Fill in the field `BackupTargetName` in `Spec` for existing Backup CR objects and labels with corresponding values of the `default` backup target.
- Fill in the fields `BackupTargetName` and `VolumeName` in `Spec` and labels for existing `BackupVolume` CR objects with corresponding values of the `default` backup target and volume.
- Fill in the fields `BackupTargetName` and `BackingImage` in `Spec` and labels for existing `BackupBackingImage` CR objects with corresponding values of the `default` backup target and backing image.
- Fill in the fields `BackupTargetName` in `Spec` for existing `Volume` CR objects with corresponding values of the `default` backup target.

## Note [optional]

`None`
