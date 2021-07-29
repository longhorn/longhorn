# Async Pull/Push Backups From/To The Remote Backup Target

## Summary

Currently, Longhorn uses a blocking way for communication with the remote backup target, so there will be some potential voluntary or involuntary factors (ex: network latency) impacting the functions relying on remote backup target like listing backups or even causing further [cascading problems](###related-issues) after the backup target operation.

This enhancement is to propose an asynchronous way to pull backup volumes and backups from the remote backup target (S3/NFS) then persistently saved via cluster custom resources.

This can resolve the problems above mentioned by asynchronously querying the list of backup volumes and backups from the remote backup target for final consistent available results. It's also scalable for the costly resources created by the original blocking query operations.

### Related Issues

- https://github.com/longhorn/longhorn/issues/1761
- https://github.com/longhorn/longhorn/issues/1955
- https://github.com/longhorn/longhorn/issues/2536
- https://github.com/longhorn/longhorn/issues/2543

## Motivation

### Goals

Decrease the query latency when listing backup volumes _or_ backups in the circumstances like lots of backup volumes, lots of backups, or the network latency between the Longhorn cluster and the remote backup target.

### Non-goals

- Automatically adjust the backup target poll interval.
- Supports multiple backup targets.
- Supports API pagination for listing backup volumes and backups.

## Proposal

1. Change the [longhorn/backupstore](https://github.com/longhorn/backupstore) _list_ command behavior, and add _inspect-volume_ and _head_ command.
   - The `backup list` command includes listing all backup volumes and the backups and read these config.
     We'll change the `backup list` behavior to perform list only, but not read the config.
   - Add a new `backup inspect-volume` command to support read backup volume config.
   - Add a new `backup head` command to support get config metadata.
2. Create a BackupTarget CRD _backuptargets.longhorn.io_ to save the backup target URL, credential secret, and poll interval.
3. Create a BackupVolume CRD _backupvolumes.longhorn.io_ to save to backup volume config.
4. Create a Backup CRD _backups.longhorn.io_ to save the backup config.
5. At the existed `setting_controller`, which is responsible creating/updating the default BackupTarget CR with settings `backup-target`, `backup-target-credential-secret`, and `backupstore-poll-interval`.
6. Create a new controller `backup_target_controller`, which is responsible for creating/deleting the BackupVolume CR.
7. Create a new controller `backup_volume_controller`, which is responsible:
   1. deleting Backup CR and deleting backup volume from remote backup target if delete BackupVolume CR event comes in.
   2. updating BackupVolume CR status.
   3. creating/deleting Backup CR.
8. Create a new controller `backup_controller`, which is responsible:
   1. deleting backup from remote backup target if delete Backup CR event comes in.
   2. calling longhorn engine/replica to perform snapshot backup to the remote backup target.
   3. updating the Backup CR status, and deleting backup from the remote backup target.
9.  The HTTP endpoints CRUD methods related to backup volume and backup will interact with BackupVolume CR and Backup CR instead interact with the remote backup target.

### User Stories

Before this enhancement, when the user's environment under the circumstances that the remote backup target has lots of backup volumes _or_ backups, and the latency between the longhorn manager to the remote backup target is high.
Then when the user clicks the `Backup` on the GUI, the user might hit list backup volumes _or_ list backups timeout issue (the default timeout is 1 minute).

We choose to not create a new setting for the user to increase the list timeout value is because the browser has its timeout value also.
Let's say the list backups needs 5 minutes to finish. Even we allow the user to increase the longhorn manager list timeout value, we can't change the browser default timeout value. Furthermore, some browser doesn't allow the user to change default timeout value like Google Chrome.

After this enhancement, when the user's environment under the circumstances that the remote backup target has lots of backup volumes _or_ backups, and the latency between the longhorn manager to the remote backup target is high.
Then when the user clicks the `Backup` on the GUI, the user can eventually list backup volumes _or_ list backups without a timeout issue.

#### Story 1

The user environment is under the circumstances that the remote backup target has lots of backup volumes and the latency between the longhorn manager to the remote backup target is high. Then, the user can list all backup volumes on the GUI.

#### Story 2

The user environment is under the circumstances that the remote backup target has lots of backups and the latency between the longhorn manager to the remote backup target is high. Then, the user can list all backups on the GUI.

#### Story 3

The user creates a backup on the Longhorn GUI. Now the backup will create a Backup CR, then the backup_controller reconciles it to call Longhorn engine/replica to perform a backup to the remote backup target.

### User Experience In Detail

None.

### API changes

1. For [longhorn/backupstore](https://github.com/longhorn/backupstore)

   The current [longhorn/backupstore](https://github.com/longhorn/backupstore) list and inspect command behavior are:
   - `backup ls --volume-only`: List all backup volumes and read it's config (`volume.cfg`). For example:
     ```json
     $ backup ls s3://backupbucket@minio/ --volume-only
     {
       "pvc-004d8edb-3a8c-4596-a659-3d00122d3f07": {
         "Name": "pvc-004d8edb-3a8c-4596-a659-3d00122d3f07",
         "Size": "2147483648",
         "Labels": {},
         "Created": "2021-05-12T00:52:01Z",
         "LastBackupName": "backup-c5f548b7e86b4b56",
         "LastBackupAt": "2021-05-17T05:31:01Z",
         "DataStored": "121634816",
         "Messages": {}
       },
       "pvc-7a8ded68-862d-4abb-a08c-8cf9664dab10": {
         "Name": "pvc-7a8ded68-862d-4abb-a08c-8cf9664dab10",
         "Size": "10737418240",
         "Labels": {},
         "Created": "2021-05-10T02:43:02Z",
         "LastBackupName": "backup-432f4d6afa31481f",
         "LastBackupAt": "2021-05-10T06:04:02Z",
         "DataStored": "140509184",
         "Messages": {}
       }
     }
     ```
   - `backup ls --volume <volume-name>`: List all backups and read it's config (`backup_backup_<backup-hash>.cfg`). For example:
     ```json
     $ backup ls s3://backupbucket@minio/ --volume pvc-004d8edb-3a8c-4596-a659-3d00122d3f07
     {
       "pvc-004d8edb-3a8c-4596-a659-3d00122d3f07": {
         "Name": "pvc-004d8edb-3a8c-4596-a659-3d00122d3f07",
         "Size": "2147483648",
         "Labels": {},
         "Created": "2021-05-12T00:52:01Z",
         "LastBackupName": "backup-c5f548b7e86b4b56",
         "LastBackupAt": "2021-05-17T05:31:01Z",
         "DataStored": "121634816",
         "Messages": {},
         "Backups": {
           "s3://backupbucket@minio/?backup=backup-02224cb26b794e73\u0026volume=pvc-004d8edb-3a8c-4596-a659-3d00122d3f07": {
             "Name": "backup-02224cb26b794e73",
             "URL": "s3://backupbucket@minio/?backup=backup-02224cb26b794e73\u0026volume=pvc-004d8edb-3a8c-4596-a659-3d00122d3f07",
             "SnapshotName": "backup-23c4fd9a",
             "SnapshotCreated": "2021-05-17T05:23:01Z",
             "Created": "2021-05-17T05:23:04Z",
             "Size": "115343360",
             "Labels": {},
             "IsIncremental": true,
             "Messages": null
            },
           ...
           "s3://backupbucket@minio/?backup=backup-fa78d89827664840\u0026volume=pvc-004d8edb-3a8c-4596-a659-3d00122d3f07": {
             "Name": "backup-fa78d89827664840",
             "URL": "s3://backupbucket@minio/?backup=backup-fa78d89827664840\u0026volume=pvc-004d8edb-3a8c-4596-a659-3d00122d3f07",
             "SnapshotName": "backup-ac364071",
             "SnapshotCreated": "2021-05-17T04:42:01Z",
             "Created": "2021-05-17T04:42:03Z",
             "Size": "115343360",
             "Labels": {},
             "IsIncremental": true,
             "Messages": null
           }
         }
       }
     }
     ```
   - `backup inspect <backup>`: Read a single backup config (`backup_backup_<backup-hash>.cfg`). For example:
     ```json
     $ backup inspect s3://backupbucket@minio/?backup=backup-fa78d89827664840\u0026volume=pvc-004d8edb-3a8c-4596-a659-3d00122d3f07
     {
       "Name": "backup-fa78d89827664840",
       "URL": "s3://backupbucket@minio/?backup=backup-fa78d89827664840\u0026volume=pvc-004d8edb-3a8c-4596-a659-3d00122d3f07",
       "SnapshotName": "backup-ac364071",
       "SnapshotCreated": "2021-05-17T04:42:01Z",
       "Created": "2021-05-17T04:42:03Z",
       "Size": "115343360",
       "Labels": {},
       "IsIncremental": true,
       "VolumeName": "pvc-004d8edb-3a8c-4596-a659-3d00122d3f07",
       "VolumeSize": "2147483648",
       "VolumeCreated": "2021-05-12T00:52:01Z",
       "Messages": null
     }
     ```

   After this enhancement, the [longhorn/backupstore](https://github.com/longhorn/backupstore) list and inspect command behavior are:
   - `backup ls --volume-only`: List all backup volume names. For example:
     ```json
     $ backup ls s3://backupbucket@minio/ --volume-only
     {
       "pvc-004d8edb-3a8c-4596-a659-3d00122d3f07": {},
       "pvc-7a8ded68-862d-4abb-a08c-8cf9664dab10": {}
     }
     ```
   - `backup ls --volume <volume-name>`: List all backup names. For example:
     ```json
     $ backup ls s3://backupbucket@minio/ --volume pvc-004d8edb-3a8c-4596-a659-3d00122d3f07
     {
       "pvc-004d8edb-3a8c-4596-a659-3d00122d3f07": {
         "Backups": {
           "backup-02224cb26b794e73": {},
           ...
           "backup-fa78d89827664840": {}
         }
       }
     }
     ```
   - `backup inspect-volume <volume>`: Read a single backup volume config (`volume.cfg`). For example:
     ```json
     $ backup inspect-volume s3://backupbucket@minio/?volume=pvc-004d8edb-3a8c-4596-a659-3d00122d3f07
     {
       "Name": "pvc-004d8edb-3a8c-4596-a659-3d00122d3f07",
       "Size": "2147483648",
       "Labels": {},
       "Created": "2021-05-12T00:52:01Z",
       "LastBackupName": "backup-c5f548b7e86b4b56",
       "LastBackupAt": "2021-05-17T05:31:01Z",
       "DataStored": "121634816",
       "Messages": {}
     }
     ```
   - `backup inspect <backup>`: Read a single backup config (`backup_backup_<backup-hash>.cfg`). For example:
     ```json
     $ backup inspect s3://backupbucket@minio/?backup=backup-fa78d89827664840\u0026volume=pvc-004d8edb-3a8c-4596-a659-3d00122d3f07
     {
       "Name": "backup-fa78d89827664840",
       "URL": "s3://backupbucket@minio/?backup=backup-fa78d89827664840\u0026volume=pvc-004d8edb-3a8c-4596-a659-3d00122d3f07",
       "SnapshotName": "backup-ac364071",
       "SnapshotCreated": "2021-05-17T04:42:01Z",
       "Created": "2021-05-17T04:42:03Z",
       "Size": "115343360",
       "Labels": {},
       "IsIncremental": true,
       "VolumeName": "pvc-004d8edb-3a8c-4596-a659-3d00122d3f07",
       "VolumeSize": "2147483648",
       "VolumeCreated": "2021-05-12T00:52:01Z",
       "Messages": null
     }
     ```
   - `backup head <config>`: Get the config metadata. For example:
     ```json
     {
       "ModificationTime": "2021-05-17T04:42:03Z",
     }
     ```

   Generally speaking, we want to separate the **list**, **read**, and **head** commands.

2. The Longhorn manager HTTP endpoints.

   | HTTP Endpoint                                                | Before                                                | After                                                                                                                                                |
   | ------------------------------------------------------------ | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
   | **GET** `/v1/backupvolumes`                                  | read all backup volumes from the remote backup target | read all the BackupVolume CRs                                                                                                                        |
   | **GET** `/v1/backupvolumes/{volName}`                        | read a backup volume from the remote backup target    | read a BackupVolume CR with the given volume name                                                                                                    |
   | **DELETE** `/v1/backupvolumes/{volName}`                     | delete a backup volume from the remote backup target  | delete the BackupVolume CR with the given volume name, `backup_volume_controller` reconciles to delete a backup volume from the remote backup target |
   | **POST** `/v1/volumes/{volName}?action=snapshotBackup`       | create a backup to the remote backup target           | create a new Backup, `backup_controller` reconciles to create a backup to the remote backup target                                                   |
   | **GET** `/v1/backupvolumes/{volName}?action=backupList`      | read a list of  backups from the remote backup target | read a list of Backup CRs with the label filter `volume=<backup-volume-name>`                                                                        |
   | **GET** `/v1/backupvolumes/{volName}?action=backupGet`       | read a  backup from the remote backup target          | read a Backup CR with the given backup name                                                                                                          |
   | **DELETE** `/v1/backupvolumes/{volName}?action=backupDelete` | delete a backup from the remote backup target         | delete the Backup CR, `backup_controller` reconciles to delete a backup from reomte backup target                                                    |

## Design

### Implementation Overview

1. Create a new BackupTarget CRD `backuptargets.longhorn.io`.

   ```yaml
   metadata:
     name: the backup target name (`default`), since currently we only support one backup target.
   spec:
     backupTargetURL: the backup target URL. (string)
     credentialSecret: the backup target credential secret. (string)
     pollInterval: the backup target poll interval. (metav1.Duration)
     syncRequestAt: the time to request run sync the remote backup target. (*metav1.Time)
   status:
     ownerID: the node ID which is responsible for running operations of the backup target controller. (string)
     available: records if the remote backup target is available or not. (bool)
     lastSyncedAt: records the last time the backup target was running the reconcile process. (*metav1.Time)
   ```

2. Create a new BackupVolume CRD `backupvolumes.longhorn.io`.

   ```yaml
   metadata:
     name: the backup volume name.
   spec:
     syncRequestAt: the time to request run sync the remote backup volume. (*metav1.Time)
     fileCleanupRequired: indicate to delete the remote backup volume config or not. (bool)
   status:
     ownerID: the node ID which is responsible for running operations of the backup volume controller. (string)
     lastModificationTime: the backup volume config last modification time. (Time)
     size: the backup volume size. (string)
     labels: the backup volume labels. (map[string]string)
     createAt: the backup volume creation time. (string)
     lastBackupName: the latest volume backup name. (string)
     lastBackupAt: the latest volume backup time. (string)
     dataStored: the backup volume block count. (string)
     messages: the error messages when call longhorn engine on list or inspect backup volumes. (map[string]string)
     lastSyncedAt: records the last time the backup volume was synced into the cluster. (*metav1.Time)
   ```

3. Create a new Backup CRD `backups.longhorn.io`.

   ```yaml
   metadata:
     name: the backup name.
     labels:
       longhornvolume=<backup-volume-name>`: this label indicates which backup volume the backup belongs to.
   spec:
     fileCleanupRequired: indicate to delete the remote backup config or not (and the related block files if needed). (bool)
     snapshotName: the snapshot name. (string)
     labels: the labels of snapshot backup. (map[string]string)
     backingImage: the backing image. (string)
     backingImageURL: the backing image URL. (string)
   status:
     ownerID: the node ID which is responsible for running operations of the backup controller. (string)
     backupCreationIsStart: to indicate the snapshot backup creation is start or not. (bool)
     url: the snapshot backup URL. (string)
     snapshotName: the snapshot name. (string)
     snapshotCreateAt: the snapshot creation time. (string)
     backupCreateAt: the snapshot backup creation time. (string)
     size: the snapshot size. (string)
     labels: the labels of snapshot backup. (map[string]string)
     messages: the error messages when calling longhorn engine on listing or inspecting backups. (map[string]string)
     lastSyncedAt: records the last time the backup was synced into the cluster. (*metav1.Time)
   ```

4. At the existed `setting_controller`.

   Watches the changes of Setting CR `settings.longorn.io` field `backup-target`, `backup-target-credential-secret`, and `backupstore-poll-interval`. The setting controller is responsible for creating/updating the default BackupTarget CR. The setting controller creates a timer goroutine according to `backupstore-poll-interval`. Once the timer up, updates the BackupTarget CR `spec.syncRequestAt = time.Now()`. If the `backupstore-poll-interval = 0`, do not updates the BackupTarget CR `spec.syncRequestAt`.

5. Create a new `backup_target_controller`.

   Watches the change of BackupTarget CR. The backup target controller is responsible for creating/updating/deleting BackupVolume CR metadata+spec. The reconcile loop steps are:
   1. Check if the current node ID == BackupTarget CR spec.responsibleNodeID. If no, skip the reconcile process.
   2. Check if the `status.lastSyncedAt < spec.syncRequestAt`. If no, skip the reconcile process.
   3. Call the longhorn engine to list all the backup volumes `backup ls --volume-only` from the remote backup target `backupStoreBackupVolumes`. If the remote backup target is unavailable:
      1. Updates the BackupTarget CR `status.available=false` and `status.lastSyncedAt=time.Now()`.
      2. Skip the current reconcile process.
   4. List in cluster BackupVolume CRs `clusterBackupVolumes`.
   5. Find the difference backup volumes `backupVolumesToPull = backupStoreBackupVolumes - clusterBackupVolumes` and create BackupVolume CR `metadata.name`.
   6. Find the difference backup volumes `backupVolumesToDelete = clusterBackupVolumes - backupStoreBackupVolumes` and delete BackupVolume CR.
   7. List in cluster BackupVolume CRs `clusterBackupVolumes` again and updates the BackupVolume CR `spec.syncRequestAt = time.Now()`.
   8. Updates the BackupTarget CR status:
      1. `status.available=true`.
      2. `status.lastSyncedAt = time.Now()`.

6. For the Longhorn manager HTTP endpoints:

   - **DELETE** `/v1/backupvolumes/{volName}`:
     1. Update the BackupVolume CR `spec.fileCleanupRequired=true` with the given volume name.
     2. Delete a BackupVolume CR with the given volume name.

7. Create a new controller `backup_volume_controller`.

   Watches the change of BackupVolume CR. The backup volume controller is responsible for deleting Backup CR and deleting backup volume from remote backup target if delete BackupVolume CR event comes in, and updating BackupVolume CR status field, and creating/deleting Backup CR. The reconcile loop steps are:
   1. Check if the current node ID == BackupTarget CR spec.responsibleNodeID. If no, skip the reconcile process.
   2. If the delete BackupVolume CR event comes in:
      1. updates Backup CRs `spec.fileCleanupRequired=true` if BackupVolume CR `spec.fileCleanupRequired=true`.
      2. deletes Backup CR with the given volume name.
      3. deletes the backup volume from the remote backup target `backup rm --volume <volume-name> <url>` if `spec.fileCleanupRequired=true`.
      4. remove the finalizer.
   3. Check if the `status.lastSyncedAt < spec.syncRequestAt`. If no, skip the reconcile process.
   4. Call the longhorn engine to list all the backups `backup ls --volume <volume-name>` from the remote backup target `backupStoreBackups`.
   5.  List in cluster Backup CRs `clusterBackups`.
   6.  Find the difference backups `backupsToPull = backupStoreBackups - clusterBackups` and create Backup CR `metadata.name` + `metadata.labels["longhornvolume"]=<backup-volume-name>`.
   7.  Find the difference backups `backupsToDelete = clusterBackups - backupStoreBackups` and delete Backup CR.
   8.  Call the longhorn engine to get the backup volume config's last modification time `backup head <volume-config>` and compares to `status.lastModificationTime`. If the config last modification time not changed, updates the `status.lastSyncedAt` and return.
   9.  Call the longhorn engine to read the backup volumes' config `backup inspect-volume <volume-name>`.
   10. Updates the BackupVolume CR status:
       1.  according to the backup volumes' config.
       2.  `status.lastModificationTime` and `status.lastSyncedAt`.
   11. Updates the Volume CR `status.lastBackup` and `status.lastBackupAt`.

8.  For the Longhorn manager HTTP endpoints:

   - **POST** `/v1/volumes/{volName}?action=snapshotBackup`:
     1. Generate the backup name <backup-name>.
     2. Create a new Backup CR with
        ```yaml
        metadata:
          name: <backup-name>
          labels: 
            longhornvolume: <backup-volume-name>
        spec:
          snapshotName: <snapshot-name>
          labels: <snapshot-backup-labels>
          backingImage: <backing-image>
          backingImageURL: <backing-image-URL>
        ```
   - **DELETE** `/v1/backupvolumes/{volName}?action=backupDelete`:
     1. Update the Backup CR `spec.fileCleanupRequired=true` with the given volume name.
     2. Delete a Backup CR with the given backup name.

9.  Create a new controller `backup_controller`.

    Watches the change of Backup CR. The backup controller is responsible for updating the Backup CR status field and creating/deleting backup to/from the remote backup target. The reconcile loop steps are:
    1. Check if the current node ID == BackupTarget CR spec.responsibleNodeID. If no, skip the reconcile process.
    2. If the delete Backup CR event comes in:
        1.  delete the backup from the remote backup target `backup rm <url>` if Backup CR `spec.fileCleanupRequired=true`.
        2.  update the BackupVolume CR `spec.syncRequestAt=time.Now()`.
        3.  remove the finalizer.
    3. Check if the Backup CR `spec.snapshotName != ""` and `status.backupCreationIsStart == false`. If yes:
        1.  call longhorn engine/replica for backup creation.
        2.  updates Backup CR `status.backupCreationIsStart = true`.
        3.  fork a go routine to monitor the backup creation progress. After backup creation finished (progress = 100):
            1.  update the BackupVolume CR `spec.syncRequestAt = time.Now()` if BackupVolume CR exist.
            2.  create the BackupVolume CR `metadata.name` if BackupVolume CR not exist.
    4. If Backup CR `status.lastSyncedAt != nil`, the backup config had be synced, skip the reconcile process.
    5. Call the longhorn engine to read the backup config `backup inspect <backup-url>`.
    6. Updates the Backup CR status field according to the backup config.
    7. Updates the Backup CR `status.lastSyncedAt`.

10. For the Longhorn manager HTTP endpoints:

   - **GET** `/v1/backupvolumes`: read all the BackupVolume CRs.
   - **GET** `/v1/backupvolumes/{volName}`: read a BackupVolume CR with the given volume name.
   - **GET** `/v1/backupvolumes/{volName}?action=backupList`: read a list of Backup CRs with the label filter `volume=<backup-volume-name>`.
   - **GET** `/v1/backupvolumes/{volName}?action=backupGet`: read a Backup CR with the given backup name.

### Test plan

With over 1k backup volumes and over 1k backups under pretty high network latency (700-800ms per operation)
from longhorn manager to the remote backup target:

- Test basic backup and restore operations.
   1. The user configures the remote backup target URL/credential and poll interval to 5 mins.
   2. The user creates two backups on vol-A and vol-B.
   3. The user can see the backup volume for vol-A and vol-B in Backup GUI.
   4. The user can see the two backups under vol-A and vol-B in Backup GUI.
   5. When the user deletes one of the backups of vol-A on the Longhorn GUI, the deleted one will be deleted after the remote backup target backup be deleted.
   6. When the user deletes backup volume vol-A on the Longhorn GUI, the backup volume will be deleted after the remote backup target backup volume is deleted, and the backup of vol-A will be deleted also.
   7. The user can see the backup volume for vol-B in Backup GUI.
   8. The user can see two backups under vol-B in Backup GUI.
   9.  The user changes the remote backup target to another backup target URL/credential, the user can't see the backup volume and backup of vol-B in Backup GUI.
   10. The user configures the `backstore-poll-interval` to 1 minute.
   11. The user changes the remote backup target to the original backup target URL/credential, after 1 minute later, the user can see the backup volume and backup of vol-B.
   12. Create volume from the vol-B backup.

- Test DR volume operations.
   1. Create two clusters (cluster-A and cluster-B) both points to the same remote backup target.
   2. At cluster A, create a volume and run a recurring backup to the remote backup target.
   3. At cluster B, after `backupstore-poll-interval` seconds, the user can list backup volumes or list volume backups on the Longhorn GUI.
   4. At cluster B, create a DR volume from the backup volume.
   5. At cluster B, check the DR volume `status.LastBackup` and `status.LastBackupAt` is updated periodically.
   6. At cluster A, delete the backup volume on the GUI.
   7. At cluster B, after `backupstore-poll-interval` seconds, the deleted backup volume does not exist on the Longhorn GUI.
   8. At cluster B, the DR volume `status.LastBackup` and `status.LastBackupAt` won't be updated anymore.

- Test Backup Target URL clean up.
   1. The user configures the remote backup target URL/credential and poll interval to 5 mins.
   2. The user creates one backup on vol-A.
   3. Change the backup target setting setting to empty.
   4. Within 5 mins the poll interval triggered:
      1. The default BackupTarget CR `status.available=false`.
      2. The default BackupTarget CR `status.lastSyncedAt` be updated.
      3. All the BackupVolume CRs be deleted.
      4. All the Backup CRs be deleted.
      5. The vol-A CR `status.lastBackup` and `status.lastBackupAt` be cleaned up.
   5. The GUI displays the backup target not available.

- Test switch Backup Target URL.
   1. The user configures the remote backup target URL/credential to S3 and poll interval to 5 mins.
   2. The user creates one backup on vol-A to S3.
   3. The user changes the remote backup URL/credential to NFS and poll interval to 5 mins.
   4. The user creates one backup on vol-A to NFS.
   5. The user changes the remote backup target URL/credential to S3.
   6. Within 5 mins the poll interval triggered:
      1. The default BackupTarget CR `status.available=true`.
      2. The default BackupTarget CR `status.lastSyncedAt` be updated.
      3. The BackupVolume CRs be synced as the data in S3.
      4. The Backup CRs be synced as the data in S3.
      5. The vol-A CR `status.lastBackup` and `status.lastBackupAt` be synced as the data in S3.

- Test Backup Target credential secret changed.
   1. The user configures the remote backup target URL/credential and poll interval to 5 mins.
   2. The user creates one backup on vol-A.
   3. Change the backup target credential secret setting to empty.
   4. Within 5 mins the poll interval triggered:
      1. The default BackupTarget CR `status.available=false`.
      2. The default BackupTarget CR `status.lastSyncedAt` be updated.
   5. The GUI displays the backup target not available.

### Upgrade strategy

None.

## Note

With this enhancement, the user might want to trigger run synchronization immediately. We could either:
- have a button on the `Backup` to update the BackupTarget CR `spec.syncRequestAt = time.Now()` _or_ have a button on the `Backup` -> `Backup Volume` page to have a button to update the BackupVolume CR `spec.syncRequestAt = time.Now()`.
- updates the `spec.syncRequestAt = time.Now()` when the user clicks the `Backup` _or_ updates the `spec.syncRequestAt = time.Now()` when the user clicks `Backup` -> `Backup Volume`.
