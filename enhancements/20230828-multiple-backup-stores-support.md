# Multiple Backup Stores Support

## Summary

The current Longhorn only support a single backup store for all volumes. The feature aims to provide multiple backup stores.

### Related Issues

https://github.com/longhorn/longhorn/issues/2317
https://github.com/longhorn/longhorn/issues/5411

## Motivation

Users can choose backup stores to that they want to back up volumes.

### Goals

- There are different backup targets at the same time on Longhorn.
- Backups can be synchronized from different remote backup targets.
- Snapshots can be backed up to different remote backup targets.
- A backup can be restored from its remote backup targets to be a new volume.

### Non-goals [optional]

`None`

## Proposal

1. Allow users to create, delete or modify backup targets.
     - backup target controller needs to synchronize the backups information from the remote backup target and create Backup CR objects and BackupVolume CR objects in the cluster when the backup target is created.
     - When the backup target is deleted, backup target controller needs to delete the Backup CR and BackupVolume CR objects in the cluster related to the backup target.
2. Introduce new fields `Labels` in `Spec` and `Default` and `ReadOnly` in `Status` of BackupTarget CRD.
3. Introduce new fields `BackupTargetURL` and `BackupTargetName` in `Spec` of both BackupVolume and Backup CRDs to keep backup target information.
4. Introduce a new field `BackupTargetName` in `Spec` of RecurringJob CRDs to keep backup target information.

### User Stories

User need to create/modify backup targets on the page `Settings/Backup Target` or by the manifest. After backup targets are created and synchronized, users can start to create a backup on these remote backup targets.

### User Experience In Detail

#### Create Or Modify Backup Targets By UI

1. User can find the link `Backup Target Credential` in drop down menu of `Setting`.
2. The page `Backup Target Credential` would show the credential name, backup target type(such as s3, nfs, cifs and ablob), account name, account key and other parameters.
3. User can create a new secret(credential) on the page `Backup Target Credential` by clicking the button `Create`.
4. User can modify a new secret(credential) on the page `Backup Target Credential` by clicking the button `Edit`
5. User can delete a new secret(credential) on the page `Backup Target Credential` by clicking the button `Delete`
6. User can find the link `Backup Target` in drop down menu of `Setting`.
7. The page `Backup Target` would show backup target name, backup target url, secret name for this backup target (credential), poll interval, default and availability status.
8. User can create a new backup target on the page `Backup Target` by clicking the button `Create` and first backup target created will be the default backup target. User have to fill out the necessary items for backup target name and url, and secret name(listing the items in `Backup Target Credential`), poll interval, default and readOnly can be optional.
9. User can not create a new backup target with the `BackupTargetURL` that is the same to a existing backup target.
10. User can modify a backup target information by clicking the button `Edit`.
11. User can choose another backup target to be a default backup target and previous default backup target will become a common backup target automatically.
12. User can delete a backup target by clicking the button `Delete`.
13. User can not delete or disable a default backup target directly.
14. User can not modify the backup target name.
15. User can not modify the `BackupTargetURL` of a backup target that is the same to another one in the cluster.

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
  labels: {}
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

After users click the button `Create Backup` on the `Volume Details` page, they can choose multiple backup targets by checkboxes to create backups on backup targets.

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
  backupTarget: azure-blob-server-001
  labels:
    longhorn.io/volume-access-mode: rwo
  snapshotName: xxxxxxxx-9a69-4ede-ab88-c9853459462c
```

#### Create A Backup To Remote Backup Targets By Recurring Jobs

Users can choose a backup target when creating a recurring job and then it will store snapshots to the appointed backup target when the recurring job is running. It will be the default backup target if users did not assign a backup target when creating a recurring job.

#### Restore From A Backup From A Remote Backup Target

Restoring from a backup will behave as before. Choose a backup and do the `Restore` operation in drop down menu on UI.

### API changes

- Introduce new APIs `BackupTargetCreate`,`BackupTargetDelete`, `BackupTargetUpdate` and `BackupTargetGet`:

    | API | Input | Output | Comments | HTTP Endpoint |
    | --- | --- | --- | --- | --- |
    | Create | name, backupTargetURL, credentialSecret string, pollInterval time.Duration, default, readOnly boolean | err error | Create a new backup target and start to synchronize data | **POST** `/v1/backuptargets/` |
    | Delete | name string | err error | Remove a backup target and its related backup volume and backup CR objects in the cluster | **DELETE** `/v1/backuptargets/{backupTargetName}` |
    | Update | backupTargetURL, credentialSecret string, pollInterval time.Duration, default, readOnly boolean | err error | Update the backup targets information | **PUT** `/v1/backuptargets/{backupTargetName}` |
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
  - Add new fields `BackupTargetName` and `VolumeName` in returning `BackupVolume` information.
- Modify the APIs `BackupCreate`, `BackupGet`:
  - Add a new field `BackupTargetName` in returning `Backup` information.
- Modify the API `SnapshotBackup`:
  - Add a new field `BackupTargetName` in the input `SnapshotInput`.

## Design

### Implementation Overview

#### CRDs

1. Modify the Backup CRD `backups.longhorn.io` to add new fields `BackupTargetURL` and `BackupTargetName` in `Spec`. And add a label LonghornLabelBackupTarget `backup-target` for resource listing.

  ```yaml
  metadata:
    labels:
      backup-target: the backup target name (string)
    name: the backup name. (string)
  spec:
    backupTargetName: the backup target Name. (string)
    backupTargetURL: the backup target URL. (string)
  ```

2. Modify the Backup Volume CRD `backupvolumes.longhorn.io` to add new fields `BackupTargetURL` and `VolumeName` and `BackupTargetName` in `Spec`. And add a label LonghornLabelBackupTarget `backup-target` for resource listing.

  ```yaml
  metadata:
    labels:
      backup-target: the backup target name (string)
    name: the backup name. (string)
  spec:
    backupTargetName: the backup target Name. (string)
    backupTargetURL: the backup target URL. (string)
    volumeName:  the volume name for backups. (string)
  ```

3. Modify the Backup Target CRD `backuptagets.longhorn.io` to add a new fields `Default` and `ReadOnly` in `Status`.

  ```yaml
  metadata:
    name: the backup name. (string)
  ...
  status:
    default:  the backup target is default or not. (boolean)
    readOnly: it is able to create a backup on this remote backup target or not. (boolean)
  ```

4. Modify the RecurringJob CRD `recurringjobs.longhorn.io` to add a new fields `BackupTargetName` in `Spec`.

  ```yaml
  metadata:
    name: the recurring job name. (string)
  spec:
    backupTargetName: the backup target Name. (string)
  ```

5. Remove `backup-target` and `backup-target-credential-secret` from the settings.

#### Backup Related Controllers

1. Remove `default` backup target from the setting controller.

2. Modify backup target controller to allow to add and delete a extra backup target.

   - Clean up backup volume CR objects in the cluster by label `backup-target` when deleting a backup target or the `BackupTargetURL` of the backup target becomes empty.
   - Create backup volume CR objects existing on the backup target by the backup volume name `volumeName` + `-` + `backupTarget.Name` and adding a label `backup-target` with the backup target URL.
   - Get backup volume CR objects in the cluster by label `backup-target` with the backup target URL.
   - Set a backup target as a default backup target:
     1. The first backup target created will become the default backup target.
     2. Setting another backup target as default will automatically set `Status.Default` of the previous default backup target `false` in a single transaction.
     3. It is not allowed to delete or disable a default backup target directly.

3. Modify backup volume controller to tell which backup volume belongs to which backup target and synchronize the backups of the backup volume from remote backup target.

   - Clean up backup CR objects in the cluster by the volume name `backupVolume.Spec.volumeName` and `backupVolume.Spec.backupTargetURL` when deleting a backup volume.
   - Create a pulling backup from the backup target by the volume name `backupVolume.Spec.volumeName` and `backupVolume.Spec.backupTargetURL`.

### Validating Webhook

1. A backup target set as default is not allowed to be deleted directly.
2. A backup target set as default is not allowed to be disabled directly.

### Test plan

1. Create an backup target as default.
2. Create a backup to default backup target and it succeeds.
3. Setup an extra backup target which has some backups.
4. Backups of default backup target will not be deleted.
5. Backups on the extra backup target can be synchronized.
6. Create a backup to extra backup target and it succeeds.
7. Restore a backup from default remote backup target, and it succeeds and data is correct.
8. Restore a backup from the extra remote backup target, and it succeeds and data is correct.

### Upgrade strategy

For `default` backup target on old versions Longhorn, its BackupTarget CR object had been created.

1. Fill in fields `BackupTargetURL` and `BackupTargetName`  in `Spec` for existing Backup CR objects with corresponding values of `default` backup target.
2. Fill in fields `BackupTargetURL`, `BackupTargetName`  and `VolumeName` in `Spec` for existing BackupVolume CR objects with corresponding values of `default` backup target.

## Note [optional]

`None`
