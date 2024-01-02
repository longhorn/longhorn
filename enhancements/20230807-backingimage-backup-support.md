# BackingImage Backup Support

## Summary
This feature enables Longhorn to backup the BackingImage to backup store and restore it.

### Related Issues

- [FEATURE] Restore BackingImage for BackupVolume in a new cluster [#4165](https://github.com/longhorn/longhorn/issues/4165)

## Motivation

### Goals

- When a Volume with a BackingImage being backed up, the BackingImage will also be backed up.
- User can manually back up the BackingImage.
- When restoring a Volume with a BackingImage, the BackingImage will also be restored.
- User can manually restore the BackingImage.
- All BackingImages are backed up in blocks.
- If the block contains the same data, BackingImages will reuse the same block in backup store instead of uploading another identical one.


## Proposal

### User Stories

With this feature, there is no need for user to manually handle BackingImage across cluster when backing up and restoring the Volumes with BackingImages.

### User Experience In Detail

Before this feature:
The BackingImage will not be backed up automatically when backing up a Volume with the BackingImage. So the user needs to prepare the BackingImage again in another cluster before restoring the Volume back.

After this feature:
A BackingImage will be backed up automatically when a Volume with the BackingImage is being backed up. User can also manually back up a BackingImage independently.
Then, when the Volume with the BackingImage is being restored from backup store, Longhorn will restore the BackingImage at the same time automatically. User can also manually restore the BackingImage independently.

This improve the user experience and reduce the operation overhead.


## Design

### Implementation Overview

#### Backup BackingImage - BackupStore

- Backup `BackingImage` is not the same as backup `Volume` which consists of a series of `Snapshots`. Instead, a `BackingImage` already has all the blocks we need to backup. Therefore, we don't need to find the delta between two `BackingImages` like what we do for`Snapshots` which delta might exist in other `Snapshots` between the current `Snapshot` and the last backup `Snapshot`.
- All the `BackingImages` share the same block pools in backup store, so we can reuse the blocks to increase the backup speed and save the space. This can happen when user create v1 `BackingImage`, use the image to add more data and then export another v2 `BackingImage`.
- For restoration, we still restore fully on one of the ready disk.
- Different from `Volume` backup, `BackingImage` does not have any size limit. It can be less than 2MB or not a multiple of 2MB. Thus, the last block might not be 2MB.

- When backing up `BackingImage`
    1. `preload()`: the BackingImage to get the all the sectors that have data inside.
    2. `createBackupBackingMapping()`: to get all the blocks we need to backup
        - Block: offset + size (2MB for each block, last block might less than 2MB)
    3. `backupMappings()`: write the block to the backup store
        - if the block is already in the backup store, skip it.
    4. `saveBackupBacking()`: save the metadata of the `BackupBackingImage` including the block mapping to the backup store. Mapping needs to include block size.

- When restoring `BackingImage`
    - `loadBackupBacking()`: load the metadata of the `BackupBackingImage` from the backup store
    - `populateBlocksForFullRestore() + restoreBlocks()`: based on the mapping, write the block data to the correct offset.

- We backup the blocks in async way to increase the backup speed.
- For qcow2 `BackingImage`, the format is not the same as raw file, we can't detect the hole and the data sector. So we back up all the blocks.


#### Backup BackingImage - Controller

1. Add a new CRD `backupbackingimage.longhorn.io`
    ```go
    type BackupBackingImageSpec struct {
        SyncRequestedAt metav1.Time `json:"syncRequestedAt"`
        UserCreated bool `json:"userCreated"`
        Labels map[string]string `json:"labels"`
    }

    type BackupBackingImageStatus struct {
        OwnerID           string                  `json:"ownerID"`
        Checksum          string                  `json:"checksum"`
        URL               string                  `json:"url"`
        Size              string                  `json:"size"`
        Labels            map[string]string       `json:"labels"`
        State             BackupBackingImageState `json:"state"`
        Progress          int                     `json:"progress"`
        Error             string                  `json:"error,omitempty"`
        Messages          map[string]string       `json:"messages"`
        ManagerAddress    string                  `json:"managerAddress"`
        BackupCreatedAt   string                  `json:"backupCreatedAt"`
        LastSyncedAt      metav1.Time             `json:"lastSyncedAt"`
        CompressionMethod BackupCompressionMethod `json:"compressionMethod"`
    }
    ```
    ```go
    type BackupBackingImageState string

    const (
        BackupBackingImageStateNew        = BackupBackingImageState("")
        BackupBackingImageStatePending    = BackupBackingImageState("Pending")
        BackupBackingImageStateInProgress = BackupBackingImageState("InProgress")
        BackupBackingImageStateCompleted  = BackupBackingImageState("Completed")
        BackupBackingImageStateError      = BackupBackingImageState("Error")
        BackupBackingImageStateUnknown    = BackupBackingImageState("Unknown")
    )
    ```
    - Field `Spec.UserCreated` indicates whether this Backup is created by user to create the backup in backupstore or it is synced from backupstrore.
    - Field `Status.ManagerAddress` indicates the address of the backing-image-manager running BackingImage backup.
    - Field `Status.Checksum` records the checksum of the BackingImage. Users may create a new BackingImage with the same name but different content after deleting an old one or there is another BackingImage with the same name in another cluster. To avoid the confliction, we use checksum to check if they are the same.
    - If cluster already has the `BackingImage` with the same name as in the backup store, we still create the `BackupBackingImage` CR. User can use the checksum to check if they are the same. Therefore we don't use `UUID` across cluster since user might already prepare the same BackingImage with the same name and content in another cluster.

2. Add a new controller `BackupBackingImageController`.
    - Workflow
        - Check and update the ownership.
        - Do cleanup if the deletion timestamp is set.
            - Cleanup the backup `BackingImage` on backup store
            - Stop the monitoring
        - If `Status.LastSyncedAt.IsZero() && Spec.BackingImageName != ""` means **it is created by the User/API layer**, we need to do the backup
            - Start the monitor
            - Pick one `BackingImageManager`
            - Request `BackingImageManager` to backup the `BackingImage` by calling `CreateBackup()` grpc
        - Else it means the `BackupBackingImage` CR is created by `BackupTargetController` and the backup `BackingImage` already exists in the remote backup target before the CR creation.
            - Use `backupTargetClient` to get the info of the backup `BackingImage`
            - Sync the status

3. In `BackingImageManager - manager(backing_image.go)`
    - Implement `CreateBackup()` grpc
        - Backup `BackingImage` to backup store in blocks

4. In controller `BackupTargetController`
    - Workflow
        - Implement `syncBackupBackingImage()` function
            - Create the `BackupBackingImage` CRs whose name are in the backup store but not in the cluster
            - Delete the `BackupBackingImage` CRs whose name are in the cluster but not in the backup store
            - Request `BackupBackingImageController` to reconcile those `BackupBackingImage` CRs

5. Add a backup API for `BackingImage`
    - Add new action `backup` to `BackingImage` (`"/v1/backingimages/{name}"`)
        - create `BackupBackingImage` CR to init the backup process
        - if `BackupBackingImage` already exists, it means there is already a `BackupBackingImage` in backup store, user can check the checksum to verify if they are the same.
    - API Watch: establish a streaming connection to report BackupBackingImage info.

6. Trigger
    - Back up through `BackingImage` operation manually
    - Back up `BackingImage` when user back up the volume
        - in `SnapshotBackup()` API
            - we get the `BackingImage` of the `Volume`
            - back up `BackingImage` if the `BackupBackingImage` does not exist


#### Restoring BackingImage - Controller

2. Add new data source type `restore` for `BackingImageDataSource`
    ```go
    type BackingImageDataSourceType string

    const (
        BackingImageDataSourceTypeDownload         = BackingImageDataSourceType("download")
        BackingImageDataSourceTypeUpload           = BackingImageDataSourceType("upload")
        BackingImageDataSourceTypeExportFromVolume = BackingImageDataSourceType("export-from-volume")
        BackingImageDataSourceTypeRestore          = BackingImageDataSourceType("restore")

        DataSourceTypeRestoreParameterBackupURL    = "backup-url"
    )

    // BackingImageDataSourceSpec defines the desired state of the Longhorn backing image data source
    type BackingImageDataSourceSpec struct {
        NodeID          string                     `json:"nodeID"`
        UUID            string                     `json:"uuid"`
        DiskUUID        string                     `json:"diskUUID"`
        DiskPath        string                     `json:"diskPath"`
        Checksum        string                     `json:"checksum"`
        SourceType      BackingImageDataSourceType `json:"sourceType"`
        Parameters      map[string]string          `json:"parameters"`
        FileTransferred bool                       `json:"fileTransferred"`
    }
    ```
3. Create BackingImage APIs
    - No need to change
        - Create BackingImage CR with `type=restore` and `restore-url=${URL}`
        - If BackingImage already exists in the cluster, user can use checksum to verify if they are the same.
4. In `BackingImageController`
    - No need to change, it will create the `BackingImageDataSource` CR
5. In `BackingImageDataSourceController`
    - No need to change, it will create the `BackingImageDataSourcePod` to do the restore.
6. In `BackingImageManager - data_source`
    - When init the service, if the type is `restore`, then restore from `backup-url` by requesting sync service in the same pod.
        ```go
        requestURL := fmt.Sprintf("http://%s/v1/files", client.Remote)
        req, err := http.NewRequest("POST", requestURL, nil)
        q := req.URL.Query()
        q.Add("action", "restoreFromBackupURL")
        q.Add("url", backupURL)
        q.Add("file-path", filePath)
        q.Add("uuid", uuid)
        q.Add("disk-uuid", diskUUID)
        q.Add("expected-checksum", expectedChecksum)
        ````
    - In `sync/service` implement `restoreFromBackupURL()` to restore the `BackingImage` from backup store to the local disk.
7. In `BackingImageDataSourceController`
    - No need to change, it will take over control when `BackingImageDataSource` status is `ReadyForTransfer`.
    - If it failed to restore the `BackingImage`, the status of the `BackingImage` will be failed and  `BackingImageDataSourcePod` will be cleaned up and retry with backoff limit like `type=download`. The process is the same as other `BackingImage` creation process.
8. Trigger
    - Restore through `BackingImage` operation manually
    - Restore when user restore the `Volume` with `BackingImage`
        - Restoring a Volume is actually requesting `Create` a Volume with `fromBackup` in the spec
        - In `Create()` API we check if the `Volume` has `fromBackup` parameters and has `BackingImage`
        - Check if `BackingImage` exists
        - Check and restore `BackupBackingImage` if `BackingImage` does not exist
        - Restore `BackupBackingImage` by creating `BackingImage` with type `restore` and `backupURL`
        - Then Create the `Volume` CR so the admission webhook won't failed because of missing `BackingImage` ([ref](https://github.com/longhorn/longhorn-manager/blob/master/webhook/resources/volume/validator.go#L86))
    - Restore when user create `Volume` through `CSI`
        - In `CreateVolume()` we check if the `Volume` has `fromBackup` parameters and has `BackingImage`
        - In `checkAndPrepareBackingImage()`, we restore `BackupBackingImage` by creating `BackingImage` with type `restore` and `backupURL`

#### API and UI changes In Summary

1. `longhorn-ui`:
    - Add a new page of `BackupBackingImage` like `Backup`
        - The columns on `BackupBackingImage` list page should be: `Name`, `Size`, `State`, `Created At`, `Operation`.
        - `Name` can be clicked and will show `Checksum` of the `BackupBackingImage`
        - `State`: `BackupBackingImageState` of the `BackupBackingImage` CR
        - `Operation` includes
            - `restore`
            - `delete`
    - Add a new operation `backup` for every `BackingImage` in the `BackingImage` page

2. `API`:
    - Add new action `backup` to `BackingImage` (`"/v1/backingimages/{name}"`)
        - create `BackupBackingImage` CR to init the backup process
    - `BackupBackingImage`
        - `GET "/v1/backupbackingimages"`: get all `BackupBackingImage`
        - API Watch: establish a streaming connection to report `BackupBackingImage` info change.

### Test plan

Integration tests

1. `BackupBackingImage` Basic Operation
    - Setup
        - Create a `BackingImage`
            ```
            apiVersion: longhorn.io/v1beta2
            kind: BackingImage
            metadata:
            name: parrot
            namespace: longhorn-system
            spec:
            sourceType: download
            sourceParameters:
                url: https://longhorn-backing-image.s3-us-west-1.amazonaws.com/parrot.raw
            checksum: 304f3ed30ca6878e9056ee6f1b02b328239f0d0c2c1272840998212f9734b196371560b3b939037e4f4c2884ce457c2cbc9f0621f4f5d1ca983983c8cdf8cd9a
            ```   
        - Setup the backup target
    - Back up `BackingImage` by applying the yaml
        - yaml
            ```yaml
            apiVersion: longhorn.io/v1beta2
            kind: BackupBackingImage
            metadata:
            name: parrot
            namespace: longhorn-system
            spec:
            userCreated: true
            labels:
                usecase: test
                type: raw
            ```
        - `BackupBackingImage` CR should be complete
        - You can get the backup URL from `Status.URL`
    - Delete the `BackingImage` in the cluster
    - Restore the `BackupBackingImage` by applying the yaml
        ```yaml
        apiVersion: longhorn.io/v1beta2
        kind: BackingImage
        metadata:
        name: parrot-restore
        namespace: longhorn-system
        spec:
        sourceType: restore
        sourceParameters:
            # change to your backup URL
            # backup-url: nfs://longhorn-test-nfs-svc.default:/opt/backupstore?backingImage=parrot
            backup-url: s3://backupbucket@us-east-1/?backingImage=parrot
            concurrent-limit: "2"
        checksum: 304f3ed30ca6878e9056ee6f1b02b328239f0d0c2c1272840998212f9734b196371560b3b939037e4f4c2884ce457c2cbc9f0621f4f5d1ca983983c8cdf8cd9a
        ```
    - Checksum should be the same

2. Back up `BackingImage` when backing up and restoring Volume
    - Setup
        - Create a `BackingImage`
        - Setup the backup target
        - Create a Volume with the `BackingImage`
    - Back up the `Volume`
    - `BackupBackingImage` CR should be created and complete
    - Delete the `BackingImage`
    - Restore the Volume with same `BackingImage`
    - `BackingImage` should be restored and the `Volume` should also be restored successfully
    - `Volume` checksum is the same

Manual tests

1. `BackupBackingImage` reuse blocks
    - Setup
        - Create a `BackingImage` A
        - Setup the backup target
    - Create a `Volume` with `BackingImage` A, write some data and export to another `BackingImage` B
    - Back up `BackingImage` A
    - Back up `BackingImage` B
    - Check it reuses the blocks when backing up `BackingImage` B (by trace log)
