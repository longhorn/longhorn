# Multiple Backup Targets Support

## Summary

The current Longhorn only support a single backup target for all volumes. The feature aims to provide multiple backup targets.

### Related Issues

https://github.com/longhorn/longhorn/issues/2317
https://github.com/longhorn/longhorn/issues/5411

## Motivation

Users can choose backup targets to that they want to back up volumes.

### Goals

- There are different backup targets at the same time on Longhorn.
- Backups can be synchronized from different remote backup targets.
- Snapshots can be backed up to different remote backup targets.
- A backup can be restored from its remote backup targets to be a new volume.

### Non-goals [optional]

`None`

## Proposal

1. Allow users to create, delete or modify backup targets.
    - backup target controller needs to synchronize the backups information from the remote backup target and create `Backup` CR objects and `BackupVolume` CR objects in the cluster when the backup target is created.
    - When the backup target is deleted, backup target controller needs to delete the `Backup` CR and `BackupVolume` CR objects in the cluster related to the backup target.
2. Introduce new fields `ReadOnly` in `Spec` and `Default` in `Status` of BackupTarget CRD.
    - `ReadOnly` marks that the remote backup target is read-only and users can not create any backups on it.
    - `Default` in `Status` marks that the backup target is the default backup target now.
3. Introduce a new field `BackupTargetName` in `Spec` of the `Backup` CRD to keep backup target information.
    - `BackupTargetName:`: is used to get the backup target of the backup.
4. Introduce new fields `BackupTargetNames` in `Spec` and `BackupTargetsInfo` in `Status` of the `BackupVolume` and `BackupBackingImage` CRDs to keep the backup volume/ backup backing image information on multiple backup targets.
5. Introduce a new field `BackupTargetName` in `Spec` of the `RecurringJob` CRD to keep backup target information.
6. Introduce a new field `BackupTargetName` in `Spec` of the `Volume` CRD to mark the default backup target for storing the volume backups.
7. The system backup will handled by the default backup target.

### User Stories

User need to create/modify backup targets on the page `Setting/Backup Target` as `Setting/Backing Image` via the Longhorn UI or by the manifest. After backup targets are created and synchronized, users can start to create a backup on these remote backup targets.

### User Experience In Detail

#### Create Or Modify Backup Targets By UI

1. User can find the link `Backup Target` in drop down menu of `Setting`.
2. The page `Backup Target` would show backup target name, backup target url, secret name for this backup target (credential), poll interval, default and availability status.
3. User can create a new backup target on the page `Backup Target` by clicking the button `Create` and first backup target created will be the default backup target. User have to fill out the necessary items for backup target name and url, and secret name(listing the items in `Backup Target Credential`), poll interval, default and readOnly can be optional.
4. User can not create a new backup target with the `BackupTargetURL` that is the same to a existing backup target.
5. User can modify a backup target information by clicking the button `Edit`.
6. User can choose another backup target to be a default backup target and previous default backup target will become a common backup target automatically.
7. User can set the backup target `ReadOnly` true and then users can not create any backups on it.
8. User can delete a backup target by clicking the button `Delete`.
9. User can not delete or disable a default backup target directly.
10. User can not modify the backup target name.
11. User can not modify the `BackupTargetURL` of a backup target that is the same to another one in the cluster.

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
  default: true
  readOnly: false
EOF

kubectl apply -f new-backup-target.yaml
```

#### Create A Backup To Remote Backup Targets By UI

After users click the button `Create Backup` on the `Volume Details` page, they can choose a backup target by a dropdown list to create backups.

#### Create A Backup To Remote Backup Targets By CLI

1. Create a snapshot of the volume first
2. Create backups for each backup target you want to store the snapshot by the manifest as below:

```yaml
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  labels:
    backup-volume: pvc-xxxxxxxx-9ab9-4055-9eb4-558999b09a11
  name: backup-test-001
  namespace: longhorn-system
spec:
  backupTargetName: azure-blob-server-001
  labels:
    longhorn.io/volume-access-mode: rwo
  snapshotName: xxxxxxxx-9a69-4ede-ab88-c9853459462c
```

3. If the field `spec.backupTargetName` is empty, it will be replaced by the field `Spec.BackupTargetName` in the volume of the snapshot.

#### Create A Backup To Remote Backup Targets By Recurring Jobs

Users can choose a backup target when creating a recurring job and then it will store snapshots to the appointed backup target when the recurring job is running. It will be the default backup target if users did not assign a backup target when creating a recurring job.

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
    | Create | name, backupTargetURL, credentialSecret string, pollInterval time.Duration, default, readOnly boolean | err error | Create a new backup target and start to synchronize data | **POST** `/v1/backuptargets/` |
    | Delete | name string | err error | Remove a backup target and its related backup volume and backup CR objects in the cluster | **DELETE** `/v1/backuptargets/{backupTargetName}` |
    | Update | backupTargetURL, credentialSecret string, pollInterval time.Duration, default, readOnly boolean | err error | Update the backup targets information | **POST** `/v1/backuptargets/{backupTargetName}?action=backupTargetUpdate` |
    | Get    |  | backupTarget BackupTarget, err error | Get the backup targets information | **GET** `/v1/backuptargets/{backupTargetName}` |

- Introduce new APIs `SecretCreate`,`SecretDelete`, `SecretUpdate`, `SecretList` and `SecretGet`:

    | API | Input | Output | Comments | HTTP Endpoint |
    | --- | --- | --- | --- | --- |
    | Create | name, type string, data map[string][]byte{} | err error | Create a new secret | **POST** `/v1/secrets/` |
    | Delete | name string | err error | Remove a secret | **DELETE** `/v1/secret/{secretName}` |
    | Update | type string, data map[string][]byte{} | err error | Update the secret information | **PUT** `/v1/secrets/{secretName}` |
    | Get    |  | secret []SecretInput, err error | Read a list of Secret | **GET** `/v1/secrets/` |
    | Get    |  | secret SecretInput, err error | Get the secret information | **GET** `/v1/secrets/{secretName}` |

  ```golang
    type SecretInput struct {
      client.Resource

      Name       string            `json:"name"`
      SecretType string            `json:"secretType"`
      Data       map[string]string `json:"data"`
    }
  ```

- Modify the APIs `BackupVolumeGet`, `BackupVolumeList`:
  - Add a new field `BackupTargetsInfo` in returning `BackupVolume` information for all backup targets that have this backup volume.
- Modify the APIs `BackupGet`:
  - Add a new field `BackupTargetName` in returning `Backup` information.
- Modify the API `SnapshotBackup`:
  - Add a new field `BackupTargetName` in the input `SnapshotInput` and returning `Backup` information.
- Modify the API `BackupBackingImageCreate`, `BackupBackingImageGet` and `BackupBackingImageList`:
  - Add a new field `BackupTargetName` in the input `BackupBackingImage`.

  ```golang
    type BackupBackingImage struct {
      client.Resource

      Name             string `json:"name"`
      BackupTargetName string `json:"backupTargetName"`
      ...
    }
  ```

## Design

### Implementation Overview

#### CRDs

1. Modify the Backup CRD `backups.longhorn.io` to add a new field `BackupTargetName` in `Spec`. And add a label LonghornLabelBackupTarget `backup-target` for resource listing.

  ```golang
  type BackupSpec struct {
    ...
    // The backup target name.
    // +optional
    // +nullable
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

2. Modify the Backup Volume CRD `backupvolumes.longhorn.io` to add new fields `BackupTargetNames` in `Spec` and `BackupTargetsInfo` in `Status`.

  ```golang
    type BackupTargetInfo struct {
      LastModificationTime metav1.Time `json:"lastModificationTime"`
      LastSyncedAt         metav1.Time `json:"lastSyncedAt"`
      Size                 string `json:"size"`
      Labels               map[string]string `json:"labels"`
      CreatedAt            string `json:"createdAt"`
      LastBackupName       string `json:"lastBackupName"`
      LastBackupAt         string `json:"lastBackupAt"`
      DataStored           string `json:"dataStored"`
      Messages             map[string]string `json:"messages"`
      BackingImageName     string `json:"backingImageName"`
      BackingImageChecksum string `json:"backingImageChecksum"`
      StorageClassName     string `json:"storageClassName"`
      BackupTargetURL      string `json:"backupTargetURL"`
      ...
    }

    type BackupVolumeSpec struct {
      ...
      // The request synchronization time with the backup target name.
      // +optional
      // +nullable
      BackupTargetsSyncRequestedTime map[string]metav1.Time `json:"backupTargetsSyncRequestedTime"`
    }

    type BackupVolumeStatus struct {
      // The node ID on which the controller is responsible to reconcile this backup volume CR.
      // +optional
      OwnerID string `json:"ownerID"`
      ...
      // moving backup volume status from the backup target to BackupTargetsInfo.
      ...
      // The backup targets information that store the backup volume.
      // +optional
      // +nullable
      BackupTargetsInfo  map[string]*BackupTargetInfo{} `json:"backupTargetsInfo"`
    }
  ```

  ```yaml
  metadata:
    name: the backup volume name. (string)
  spec:
    backupTargetSyncRequestedTime: {"A": "2024-01-01T00:00:00Z", "B": ""2024-01-01T01:01:01Z""}
  status:
    backupTargetsInfo: {"backupTargetA":{...}, "backupTargetB":{...}} (map[string]BackupTargetInfo{})
    ...
  ```

3. Modify the Backup Backing Image CRD `backupbackingimages.longhorn.io` to add new fields `BackupTargetNames` in `Spec` and `BackupTargetsInfo` in `Status`.

  ```golang
  type BackupBackingImageSpec struct {
    ...
    // The request synchronization time with the backup target name.
    // +optional
    // +nullable
    BackupTargetsSyncRequestedTime map[string]metav1.Time `json:"backupTargetsSyncRequestedTime"`
  }

  type BackupBackingImageStatus struct {
    ...
    // Compression method
    // +optional
    CompressionMethod BackupCompressionMethod `json:"compressionMethod"`
    // The backup targets information that store the backup volume.
    // +optional
    // +nullable
    BackupTargetsInfo  map[string]*BackupTargetInfo{} `json:"backupTargetsInfo"`
  }
  ```

  ```yaml
  metadata:
    name: the backup backing image name. (string)
  spec:
    backupTargetSyncRequestedTime: {"A": "2024-01-01T00:00:00Z", "B": ""2024-01-01T01:01:01Z""}
  status:
    backupTargetsInfo: {"backupTargetA":{...}, "backupTargetB":{...}} (map[string]BackupTargetInfo{})
  ```

1. Modify the Backup Target CRD `backuptagets.longhorn.io` to add new fields `ReadOnly` in `Spec` and `Default` in `Status`.

  ```golang
  type BackupTargetSpec struct {
    ...
    // ReadOnly indicates if it can create a backup on the remote backup target or not.
    // +optional
    ReadOnly bool `json:"readOnly"`
    ...
  }

  // BackupTargetStatus defines the observed state of the Longhorn backup target
  type BackupTargetStatus struct {
    ...
    Default bool `json:"default"`
    ...
  }
  ```

  ```yaml
  metadata:
    name: the backup target name. (string)
  spec:
    readOnly: it is able to create a backup on this remote backup target or not. (boolean)
  ...
  status:
    default:  the backup target is default or not. (boolean)
  ```

5. Modify the RecurringJob CRD `recurringjobs.longhorn.io` to add a new field `BackupTargetName` in `Spec`.

  ```golang
  type RecurringJobSpec struct {
    ...
    // The backup target name for `backup*` job task.
    // +optional
    BackupTargetName string `json:"backupTargetName"`
  }
  ```

  ```yaml
  metadata:
    name: the recurring job name. (string)
  spec:
    backupTargetName: the backup target Name. (string)
  ```

6. Modify the Volume CRD `volumes.longhorn.io` to add a new field `BackupTargetName` in `Spec`.

  ```golang
  type VolumeSpec struct {
    // The default backup target name when a backup is created from the volume.
    // +optional
    BackupTargetName int64 `json:"backupTargetName"`
  }
  ```

  ```yaml
  metadata:
    name: the volume name. (string)
  spec:
    backupTargetName: the backup target Name. (string)
  ```

7. Remove `backup-target`, `backup-target-credential-secret`, and `backupstore-poll-interval` from the settings.

#### Backup Related Controllers

1. Not create the `default` backup target by the setting controller when the `longhorn-manager` daemon starts.

2. Modify the backup target controller to allow adding and deleting an extra backup target.

   - Create pulling backup volume CR objects from the backup target if not exist and fill in the `Spec.BackupTargetsSyncRequestedTime` with the backup target name and the request time.
   - Create pulling backup backing images from the backup target if not exist and fill in the `Spec.BackupTargetsSyncRequestedTime` with the backup target name and the request time .
   - Remove the backup target name in the `Spec.BackupTargetNames` of backup volume or backup backing image CR objects in the cluster when deleting the backup target or the `BackupTargetURL` of the backup target becomes empty.
   - Remove a backup volume or backup backing image CR object if the field `Spec.BackupTargetNames` is empty.
   - Set a backup target as a default backup target:
     1. Only `default` backup target upgrade from the old Longhorn will set the field `Status.Default` true.
     2. Users need to specify a backup target when creating a backup.
3. Modify backup volume controller to tell which backup volume belongs to which backup target and synchronize the backups of the backup volume from remote backup target.

   - Create pulling backups from the backup target with the field `Spec.backupTargetName` of the backup target.
   - Add a backup target entry in `Status.BackupTargetsInfo` with the backup target name and synchronize the remote backup volume information on the backup target into the `Status.BackupTargetsInfo`.
   - Clean up backup CR objects in the cluster by the backup volume name and backup target name when deleting a backup volume or the backup target url is empty.

4. Modify backup backing image controller
   - Start to backup a backup image by the backup target name that is not added into the `Status.BackupTargetsInfo`.
   - Add a backup target entry in `Status.BackupTargetsInfo` with the backup target name and synchronize the remote information on the backup target into the `Status.BackupTargetsInfo`.

#### Disaster Recovery Volume From A Remote Backup Target

Polling for the last backup of a backup volume from the status of the backup volume information map with the appointed backup target when creating the DR volume.

```golang
// Volume controller
  func (c *VolumeController) ReconcileBackupVolumeState(volume *longhorn.Volume) error {
    ...
    // Set last backup
    volume.Status.LastBackup = bv.Status.BackupTargetsInfo[volume.Spec.BackupTargetName].LastBackupName
    volume.Status.LastBackupAt = bv.Status.BackupTargetsInfo[volume.Spec.BackupTargetName].LastBackupAt
    return nil
  }
  ...
  func (c *VolumeController) updateRequestedBackupForVolumeRestore(v *longhorn.Volume, e *longhorn.Engine) (err error) {
    ...

    // For DR volume, we set RequestedBackupRestore to the LastBackup
    if v.Status.IsStandby {
      if v.Status.LastBackup != "" && v.Status.LastBackup != e.Spec.RequestedBackupRestore {
        e.Spec.RequestedBackupRestore = v.Status.LastBackup
      }
      return nil
    }
  }
```

### Mutating Webhook

- Fill in the `Spec.BackupTargetName` of the `Backup` CR object by `Spec.BackupTargetName` of the `Volume` CR object if the field `Spec.BackupTargetName` of the `Backup` CR object is empty.

### Test plan

1. Create a backup target A.
2. Create a backup to the backup target A and it succeeds.
3. Setup an extra backup target B which has some backups.
4. Backups of the backup target A will not be deleted.
5. Backups on the extra backup target B can be synchronized.
6. Create a backup to extra backup target B and it succeeds.
7. Restore a backup from remote backup target A, and it succeeds and data is correct.
8. Restore a backup from the extra remote backup target B, and it succeeds and data is correct.

### Upgrade strategy

For `default` backup target on old versions Longhorn, its BackupTarget CR object had been created.

- Fill in the field `BackupTargetName`  in `Spec` for existing Backup CR objects with corresponding values of `default` backup target.
- Fill in the field `BackupTargetsSyncRequestedTime` in `Spec` for existing BackupVolume CR objects with corresponding values of `default` backup target.
- Fill in the field `BackupTargetsSyncRequestedTime` in `Spec` for existing BackupBackingImage CR objects with corresponding values of `default` backup target.
- Old and obsolete backup-related settings (`backup-target`, `backup-target-credential-secret`, and `backupstore-poll-interval`) will be removed after upgrade.

## Note [optional]

`None`
