# Backing Image v2

## Summary
Longhorn can set a backing image of a Longhorn volume, which is designed for VM usage.

### Related Issues
https://github.com/longhorn/longhorn/issues/2006
https://github.com/longhorn/longhorn/issues/2295
https://github.com/longhorn/longhorn/issues/2530
https://github.com/longhorn/longhorn/issues/2404

## Motivation
### Goals
1. A qcow2 or raw image file can be used as the backing image of a volume.
2. The backing image works fine with backup or restore.  
3. Multiple replicas in the same disk can share one backing image.
4. The source of a backing image file can be remote downloading, upload, Longhorn volume, etc.
5. Once the first backing image file is ready, Longhorn can deliver it to other nodes.
6. Checksum verification for backing image.
7. HA backing image.

### Non-goals:
This feature is not responsible for fixing issue mentioned in [issue #1948](https://github.com/longhorn/longhorn/issues/1948#issuecomment-791641308).

## Proposal
1. Each backing image is stored as a object of a new CRD named `BackingImage`.
    - The spec/status records if a disk requires/contains the related backing image file. 
    - To meet backing image HA requirement, some ready disks are randomly picked. Besides, whether a disk requires the backing image file is determined by if there is replicas using it in the disk.
    - A file in a disk cannot be removed as long as there is a replica using it.
2. Longhorn needs to prepare the 1st backing image file based on the source type:
    - Typically, the 1st file preparation takes a short amount of time comparing with the whole lifecycle of BackingImage. Longhorn can use a temporary pod to handle it. Once the file is ready, Longhorn can stop the pod.
    - We can use a CRD named `BackingImageDataSource` to abstract the file preparation. The source type and the parameters will be in the spec.
    - To allow Longhorn manager query the progress of the file preparation, we should launch a service for this pod. Considering that multiple kinds of source like download or uploading involve HTTP, we can launch a HTTP server for the pod.
3. Then there should be a component responsible for monitoring and syncing backing image files with other nodes after the 1st file ready. 
    - Similar to `BackingImageDataSource`, we will use a new CRD named `BackingImageManager` to abstract this component.
    - The BackingImageManager pod is design to
        - take over the ownership when the 1st file prepared by the BackingImageDataSource pod is ready.
        - deliver the file to others if necessary.
        - monitor all backing image files for a specific disk: Considering the disk migration and failed replica reusage features, there will be an actual backing image file for each disk rather than each node.
    - BackingImageManager should support reuse existing backing image files. Since we will consider those files are immutable/read-only once ready. If there is an expected checksum for a BackingImage, the pod will compare the checksum before reusing.
    - Live upgrade is possible: Different from instance managers, BackingImageManagers manage files only. We can directly shut down the old BackingImageManager pods, then let new BackingImageManager pods rely on the reuse mechanism to take over the existing files.
    - If the disk is not available/gets replaced, the BackingImageManager cannot do anything or simply report all BackingImages failed.
    - Once there is a modification for an image, managers will notify callers via the gRPC streaming.
4. `longhorn-manager` will launch & update controllers for these new CRDs:
    - BackingImageController is responsible for:
        1. Generate a UUID for each new BackingImage.
        2. Sync with the corresponding BackingImageDataSource:
        3. Handle BackingImageManager life cycle.
        4. Sync download status/info with BackingImageDataSource status or BackingImageManager status.
        5. Set timestamp if there is no replica using the backing image file in a disk.  
   - BackingImageDataSourceController is responsible for:
       1. Sync with the corresponding BackingImage.
       3. Handle BackingImageManager life cycle.
       4. Sync download status/info with BackingImageDataSource status or BackingImageManager status.
       5. Set timestamp if there is no replica using the BackingImage in a disk
    - BackingImageManagerController is responsible for:
        1. Create pods to handle backing image files.
        2. Handle files based on the spec & BackingImageDataSource status:
            - Delete unused BackingImages.
            - Fetch the 1st file based on BackingImageDataSource. Otherwise, sync the files from other managers or directly reuse the existing files.
5. For `longhorn-engine`:
    - Most of the backing image related logic is already in there.
    - The raw image support will be introduced.
    - Make sure the backing file path will be updated each time when the replica starts.
    
- The lifecycle of the components:
    ```  
                           |Created by HTTP API.                                                                 |Set deletion timestamp, will delete BackingImageDataSource first.
    BackingImage:          |========|============================================================================|======================================================|
                                    |Create BackingImageManagers                                                                                                        |Deleted after cleanup.
                                    | base on HA or replica requirements.
    
                              |Created by HTTP API after                                                                |Set deletion timestamp when 
                              | BackingImage creation.                                                                  | BackingImage is being deleted.          
    BackingImageDataSource:   |===============|=========================================|=============|=================|=========================================|
                                              |Start a pod then                         |File ready.  |Stop the pod when                                          |Deleted.
                                              | file preparation immediately                          | BackingImageManager takes over the file.                           
    
                                                                                                   |Take over the 1st file from BackingImageDataSource.         |Do cleanup if required                                   
                                     |Created by BackingImageController                            | Or sync/receive files from peers.                          | then get deleted.
    BackingImageManager:             |===========|==============|==================================|===============================================|============|
                                                 |Start a pod.  |Keep file monitoring                                                              |Set deletion timestamp since 
                                                                | after pod running.                                                               | no BackingImage is in the disk.
    ```
     - BackingImage CRs and BackingImageDataSource CRs are one-to-one correspondence. 
       One backingImageDataSource CR is always created after the related BackingImage CR, but deleted before the BackingImage CR cleanup.  
     - The lifecycle of one BackingImageManager CR is not controlled by one single BackingImage. For a disk, the related BackingImageManager CR will be created as long as there is one BackingImage required. 
       However, it will be removed only if there is no BackingImage in the disk.

### User Stories
#### Rebuild replica for a large volume after network fluctuation/node reboot
Before the enhancement, users need to manually copy the backing image data to the volume in advance.

After the enhancement, users can directly specify the BackingImage during volume creation/restore with a click. And one backing image file can be shared among all replicas in the same disk.

### User Experience In Detail
1. Users can modify the backing image file cleanup timeout setting so that all non-used files will be cleaned up automatically from disks.
2. Create a volume with a backing image 
    2.1. via Longhorn UI 
        1. Users add a backing image, which is similar to add an engine image or set up the backup target in the system.
        2. Users create/restore a volume with the backing image specified from the backing image list.
    2.2. via CSI (StorageClass)
       - By specifying `backingImageName` in a StorageClass, all volumes created by this StorageClass will utilize this backing image.
       - If the optional fields `backingImageDataSourceType` and `backingImageDataSourceParameters` are set and valid, Longhorn will automatically create a volume as well as the backing image if the backing image does not exists.
3. Users attach the volume to a node (via GUI or Kubernetes). Longhorn will automatically prepare the related backing image to the disks the volume replica are using. In brief, users don't need to do anything more for the backing image. 
4. When users backup a volume with a backing image, the backing image info will be recorded in the backup but the actual backing image data won't be uploaded to the backupstore. Instead, the backing image will be re-downloaded from the original image once it's required.

### API Changes
- A bunch of RESTful APIs is required for the new CRD `BackingImage`: `Create`, `Delete`, `List`, and `BackingImageCleanup`.
- Now the volume creation API receives parameter `BackingImage`.

## Design
### Implementation Overview
#### longhorn-manager:
1. In settings:
    - Add a setting `Backing Image Cleanup Wait Interval`.
    - Add a read-only setting `Default Backing Image Manager Image`.
2. Add a new CRD `backingimages.longhorn.io`.
    ```goregexp
    type BackingImageSpec struct {
        Disks    map[string]struct{} `json:"disks"`
        Checksum string              `json:"checksum"`
    }

    type BackingImageStatus struct {
        OwnerID                     string                       `json:"ownerID"`
        UUID                        string                       `json:"uuid"`
        Size                        int64                        `json:"size"`
        Checksum                    string                       `json:"checksum"`
        DiskFileStatusMap           map[string]*BackingImageDiskFileStatus `json:"diskFileStatusMap"`
        DiskLastRefAtMap            map[string]string            `json:"diskLastRefAtMap"`
    }
   
    type BackingImageDiskFileStatus struct {
        State    BackingImageState `json:"state"`
        Progress int               `json:"progress"`
        Message  string            `json:"message"`
   }
    ```
    ```goregexp
    const (
        BackingImageStatePending    = BackingImageState("pending")
        BackingImageStateStarting   = BackingImageState("starting")
        BackingImageStateReady      = BackingImageState("ready")
        BackingImageStateInProgress = BackingImageState("in_progress")
        BackingImageStateFailed     = BackingImageState("failed")
        BackingImageStateUnknown    = BackingImageState("unknown")
    )
    ```
    - Field `Spec.Disks` records the disks that requires this backing image. 
    - Field `Status.DiskFileStatusMap` reflect the current file status for the disks. If there is anything wrong with the file, the error message can be recorded inside the status.
    - Field `Status.UUID` should be generated and stored in ETCD before other operations. Considering users may create a new BackingImage with the same name but different parameters after deleting an old one, to avoid the possible leftover of the old BackingImage disturbing the new one, the manager can use a UUID to generate the work directory.   
3. Add a new CRD `backingimagedatasources.longhorn.io`.
    ```goregexp
    type BackingImageDataSourceSpec struct {
        NodeID     string                     `json:"nodeID"`
        DiskUUID   string                     `json:"diskUUID"`
        DiskPath   string                     `json:"diskPath"`
        Checksum   string                     `json:"checksum"`
        SourceType BackingImageDataSourceType `json:"sourceType"`
        Parameters map[string]string          `json:"parameters"`
        Started    bool                       `json:"started"`
    }
    
    type BackingImageDataSourceStatus struct {
        OwnerID      string            `json:"ownerID"`
        CurrentState BackingImageState `json:"currentState"`
        Size         int64             `json:"size"`
        Progress     int               `json:"progress"`
        Checksum     string            `json:"checksum"`
    }
   
   type BackingImageDataSourceType string

    const (
        BackingImageDataSourceTypeDownload = BackingImageDataSourceType("download")
        BackingImageDataSourceTypeUpload   = BackingImageDataSourceType("upload")
    )
    
    const (
        DataSourceTypeDownloadParameterURL = "url"
    )
    ```
    - Field `Started` indicates if the BackingImageManager already takes over the file. Once this is set, Longhorn can stop the corresponding pod as well as updating the object itself.
4. Add a new CRD `backingimagemanagers.longhorn.io`.
    ```goregexp
    type BackingImageManagerSpec struct {
        Image         string            `json:"image"`
        NodeID        string            `json:"nodeID"`
        DiskUUID      string            `json:"diskUUID"`
        DiskPath      string            `json:"diskPath"`
        BackingImages map[string]string `json:"backingImages"`
    }
    
    type BackingImageManagerStatus struct {
        OwnerID             string                          `json:"ownerID"`
        CurrentState        BackingImageManagerState        `json:"currentState"`
        BackingImageFileMap map[string]BackingImageFileInfo `json:"backingImageFileMap"`
        IP                  string                          `json:"ip"`
        APIMinVersion       int                             `json:"apiMinVersion"`
        APIVersion          int                             `json:"apiVersion"`
    }
    ```
    ```goregexp
    type BackingImageFileInfo struct {
        Name                 string            `json:"name"`
        UUID                 string            `json:"uuid"`
        Size                 int64             `json:"size"`
        State                BackingImageState `json:"state"`
        CurrentChecksum      string            `json:"currentChecksum"`
        Message              string            `json:"message"`
        SendingReference     int               `json:"sendingReference"`
        SenderManagerAddress string            `json:"senderManagerAddress"`
        Progress             int               `json:"progress"`
    }
    ```
    ```goregexp
    const (
        BackingImageManagerStateError    = BackingImageManagerState("error")
        BackingImageManagerStateRunning  = BackingImageManagerState("running")
        BackingImageManagerStateStopped  = BackingImageManagerState("stopped")
        BackingImageManagerStateStarting = BackingImageManagerState("starting")
        BackingImageManagerStateUnknown  = BackingImageManagerState("unknown")
    )
    ```
    - Field `Spec.BackingImages` records which BackingImages should be monitored by the manager. the key is BackingImage name, the value is BackingImage UUID.
    - Field `Status.BackingImageFileMap` will be updated according to the actual file status reported by the related manager pod.
    - Struct `BackingImageFileInfo` is used to load the info from BackingImageManager pods.
5. Add a new controller `BackingImageDataSourceController`.
    1. Important notices:
        1. Once a BackingImageManager takes over the file ownership, the controller doesn't need to update the related BackingImageDataSource CR except for cleanup. 
        3. The state is designed to reflect the file state rather than the pod phase. Of course, the file state will be considered as failed if the pod somehow doesn't work correctly. e.g., the pod suddenly becomes failed or being removed. 
    2. Workflow:
        1. Check and update the ownership.
        2. Do cleanup if the deletion timestamp is set. Cleanup means stopping monitoring and kill the pod.
        3. Sync with the BackingImage:
             1. For in-progress BackingImageDataSource, Make sure the disk used by this BackingImageDataSource is recorded in the BackingImage spec as well.
             2. [TODO] Guarantee the HA by adding more disks to the BackingImage spec once BackingImageDataSource is started.
        4. Skip updating "started" BackingImageDataSource.
        5. Handle pod:
             1. Check the pod status.
             2. Update the state based on the previous state and the current pod phase:
                 1. If the pod is ready for service, do nothing.
                 2. If the pod is not ready, but the file processing already start. It means there is something wrong with the flow. This BackingImageDataSource will be considered as `error`.
                 3. If the pod is failed, the BackingImageDataSource should be `error` as well.
                 4. When the pod reaches an unexpected phase or becomes failed, need to record the error message or error log in the pod.
             3. Start or stop monitoring based on pod phase.
             4. Delete the errored pod.
             5. Create or recreate the pod, then update the backoff entry. Whether the pod can be recreated is determined by the backoff window and the source type. For the source types like upload, recreating pod doesn't make sense. Users need to directly do cleanup then recreate a new backing image instead.   
        6. For the monitor goroutine, it's similar to that in InstanceManagerController.
            - It will `Get` the file info via HTTP every 3 seconds.
            - If there are 10 continuous HTTP failures, the monitor goroutine will stop itself. Then the controller will restart it.
            - If the backing image is ready, clean up the entry in the backoff.
6. Add a new controller `BackingImageManagerController`.
    1. Important notices:
        1. Need to consider 2 kinds of managers: default manager, old manager(this includes all incompatible managers).
        2. All old managers will be removed immediately once there is the default image is updated. And old managers shouldn't operate any backing image files.
            - When an old manager is removed, the files inside in won't be gone. These files will be taken by the new one. By disabling old managers operating the files, the conflicts with the default manager won't happen.
            - The controller can directly delete old BackingImageManagers without affecting existing BackingImages. This simplifies the cleanup flow.
            - Ideally there should be a cleanup mechanism that is responsible for removing all failed backing image files as well as the images no longer required by the new BackingImageManagers. But due to lacking of time, it will be implemented in the future.
        3. In most cases, the controller and the BackingImageManager will avoid deleting backing images files.:
            - For example, if the pod is crashed or one image file becomes failed, the controller will directly restart the pod or re-download the image, rather than cleaning up the files only.
            - The controller will delete image files for only 2 cases: A BackingImage is no longer valid; A default BackingImageManager is deleted.
            - By following this strategy, we may risk at leaving some unused backing image files in some corner cases. 
              However, the gain is that, there is lower probability of crashing a replica caused by the backing image file deletion. Besides, the existing files can be reused after recovery. 
              And after introducing the cleanup mechanism, we should worry about the leftover anymore.
        4. With passive file cleanup strategy, default managers can directly pick up all existing files via `Fetch` requests when the old manager pods are killed. This is the essential of live upgrade.
        5. The pod not running doesn't mean all files handled by the pod become invalid. All files can be reused/re-monitored after the pod restarting.
    2. Workflow:
        1. If the deletion timestamp is set, the controller will clean up files for running default BackingImageManagers only. Then it will blindly delete the related pods.
        2. When the disk is not ready, the current manager will be marked as `unknown`. Then all not-failed file records are considered as `unknown` as well.
             - Actually there are multiple subcases here: node down, node reboot, node disconnection, disk detachment, longhorn manager pod missing etc. It's complicated to distinguish all subcases to do something special. Hence, I choose simply marking the state to `unknown`.
        3. Create BackingImageManager pods for.
            - If the old status is `running` but the pod is not ready now, there must be something wrong with the manager pod. Hence the controller need to update the state to `error`.
            - When the pod is ready, considering the case that the pod creation may succeed but the CR status update will fail due to conflicts, the controller won't check the previous state. Instead, it will directly update state to `running`.
            - Start a monitor goroutine for each running pods.
            - If the manager is state `error`, the controller will do cleanup then recreate the pod.
        4. Handle files based on the spec:
            - Delete invalid files:
                - The BackingImages is no longer in `BackingImageManager.Spec.BackingImages`.
                - The BackingImage UUID doesn't match.
            - Make files ready for the disk: 
                1. When BackingImageDataSource is not "started", it means BackingImageManager hasn't taken over the 1st file. Once BackingImageDataSource reports file ready, BackingImageManager can get the 1st file via API `Fetch`.
                2. Then if BackingImageDataSource is "started" but there is no ready record for a BackingImage among all managers, it means the pod someshow restarted (may due to upgrade). In this case, BackingImageManager can try to reuse the files via API `Fetch` as well.
                3. Otherwise, the current manager will try to sync the file with other managers:
                    - If the 1st file is not ready, do nothing.
                    - Each manager can send a ready file to 3 other managers simultaneously at max. When there is no available sender, do nothing.
                4. Before reusing or syncing files, the controller need to check the backoff entry for the corresponding BackingImageManager. And after the API call, the backoff entry will be updated.
        5. For the monitor goroutine, it's similar to that in InstanceManagerController.
            - It will `List` all backing image files once it receives the notification from the streaming.
            - If there are 10 continuous errors returned by the streaming receive function, the monitor goroutine will stop itself. Then the controller will restart it.
            - Besides, if a backing image is ready, the monitor should clean up the entry from the backoff of the BackingImageManager.
7. Add a new controller `BackingImageController`.
    1. Important notices:
        1. One main responsibility of this controller is creating, deleting, and update BackingImageManagers. It is not responsible for communicating with BackingImageManager pods or BackingImageDataSource pods.
        2. This controller can reset "started" BackingImageDataSource if all its backing image files are errored in the cluster and the source type is satisfied.
        3. The immutable UUID should be generated and stored in ETCD before any other update. This UUID can can be used to distinguish a new BackingImage from an old BackingImage using the same name. 
        4. Beside recording the immutable UUID, the BackingImage status is used to record the file info in the managers status and present to users.
        5. Always try to create default BackingImageManagers if not exist. 
        6. Aggressively delete non-default BackingImageManagers.
    2. Workflow:
        1. If the deletion timestamp is set, the controller need to do cleanup for all related BackingImageManagers as well as BackingImageDataSource.
        2. Generate a UUID for each new BackingImage. Make sure the UUID is stored in ETCD before doing anything others.
        3. Init fields in the BackingImage status.
        4. Sync with BackingImageDataSource:
            1. Mark BackingImageDataSource as started if the default BackingImageManager already takes over the file ownership.
            2. When all files failed, mark the BackingImageDataSource when the source type is downloaded. Then it can re-download the file and recover this BackingImage.
            3. Guarantee the disk info in BackingImageDataSources spec is correct if it's not started. (This can be done in Node Controller as well.)
        5. Handle BackingImageManager life cycle:
            - Remove records in `Spec.BackingImages` or directly delete the manager CR
            - Add records to `Spec.BackingImages` for the current BackingImage. Create BackingImageManagers with default image if not exist.
        6. Sync download status/info with BackingImageManager status:
            - If BackingImageDataSource is not started, update BackingImage status based on BackingImageDataSource status. Otherwise, sync status with BackingImageManagers.
            - Set `Status.Size` if it's 0. If somehow the size is not same among all BackingImageManagers, this means there is an unknown bug. Similar logic applied to `Status.CurrentChecksum`.
        7. Set timestamp in `Status.DiskLastRefAtMap` if there is no replica using the BackingImage in a disk. Later NodeController will do cleanup for `Spec.DiskDownloadMap` based on the timestamp.
           Notice that this clean up should not break the backing image HA.
            1. Try to set timestamps for disks in which there is no replica/BackingImageDataSource using this BackingImage first. 
            2. If there is no enough ready files after marking, remove timestamps for some disks that contain ready files.
            3. If HA requirement is not satisfied when all ready files are retained, remove timestamps for some disks that contain in-progress/pending files.
            4. If HA requirement is not unsatisfied, remove timestamps for some disks that contain failed files. Later Longhorn can try to do recovery for the disks contains these failed files.
6. In Replica Controller:
    - Request preparing the backing image file in a disk if a BackingImage used by a replica doesn't exist.
    - Check and wait for BackingImage disk map in the status before sending requests to replica instance managers.
7. In Node Controller:
    - Determine if the disk needs to be cleaned up if checking BackingImage `Status.DiskLastRefAtMap` and the wait interval `BackingImageCleanupWaitInterval`.
    - Update the spec for BackingImageManagers when there is a disk migration.
8. For the HTTP APIs 
    - Volume creation:
        - Longhorn needs to verify the BackingImage if it's specified.
        - For restore/DR volumes, the BackingImage name stored in the backup volume will be used automatically if users do not specify the BackingImage name. Verify the checksum before using the BackingImage.
    - Snapshot backup:
        - BackingImage name and checksum will be record into BackupVolume now.
    - BackingImage creation:
        - Need to create both BackingImage CR and the BackingImageDataSource CR. Besides, a random ready disk will be picked up so that Longhorn can prepare the 1st file for the BackingImage immediately.
    - BackingImage get/list:
        - Be careful about the BackingImageDataSource not found error. There are 2 cases that would lead to this error:
            - BackingImageDataSource has not been created. Add retry would solve this case.
            - BackingImageDataSource is gone but BackingImage has not been cleaned up. Longhorn can ignore BackingImageDataSource when BackingImage deletion timestamp is set.
    - BackingImage disk cleanup:
        - This cannot break the HA besides attaching replicas. The main idea is similar to the cleanup in BackingImage Controller.
9. In CSI:
    - Check the backing image during the volume creation.
    - The missing BackingImage will be created when both BackingImage name and data source info are provided.

#### longhorn-engine:
- Verify the existing implementation and the related integration tests.
- Add raw backing file support.
- Update the backing file info for replicas when a replica is created/opened.

#### backing-image-manager:
##### data source service:
- A HTTP server will be launched to prepare the 1st BackingImage file based on the source type.
- The server will download the file immediately once the type is `download` and the server is up.
    - A cancelled context will be put the HTTP download request. When the server is stopped/failed while downloading is still in-progress, the context can help stop the download.
    - The service will wait for 30s at max for download start. If time exceeds, the download is considered as failed.
    - The download file is in `<Disk path in container>/tmp/<BackingImage name>-<BackingImage UUID>`
    - Each time when the image downloads a chunk of data, the progress will be updated. For the first time updating the progress, it means the downloading starts and the state will be updated from `starting` to `in-progress`.    
- The server is ready for handling the uploaded data once the type is `upload` and the server is up.
    - The query `size` is required for the API `upload`.
    - The API `upload` receives a multi-part form request. And the body request is the file data streaming.
    - Similar to the download, the progress will be updated as long as the API receives and stores a chunk of data. For the first time updating the progress, it means the uploading starts and the state will be updated from `starting` to `in-progress`.
##### manager service:
- A gRPC service will be launched to monitor and sync BackingImages:
    - API `Fetch`: Register the image then move the file prepared by BackingImageDataSource server to the image work directory. The file is typically in a tmp directory
        - If the file name is not specified in the request, it means reusing the existing file only.
        - For a failed BackingImage, the manager will re-register then re-fetch it.
        - Before fetching the file, the BackingImage will check if there are existing files in the current work directory. It the files exist and the checksum matches, the file will be directly reused and the config file is updated.
        - Otherwise, the work directory will be cleaned up and recreated. Then the file in the tmp directory will be moved to the work directory.
    - API `Sync`: Register the image, start a receiving server, and ask another manager to send the file via API `Send`. For a failed BackingImage, the manager will re-register then re-sync it. This should be similar to replica rebuilding.
        - Similar to `Fetch`, the image will try to reuse existing files.
        - The manager is responsible for managing all port. The image will use the functions provided by the manager to get then release ports.
    - API `Send`: Send a backing image file to a receiver. This should be similar to replica rebuilding.
    - API `Delete`: Unregister the image then delete the image work directory. Make sure syncing or pulling will be cancelled if exists.
    - API `Get`/`List`: Collect the status of one backing image file/all backing image files.
    - API `Watch`: establish a streaming connection to report BackingImage file info.
- As I mentioned above, we will use BackingImage UUID to generate work directories for each BackingImage. The work directory is like:
  ```
  <Disk path in container>/backing-images/
  <Disk path in container>/backing-images/<Syncing BackingImage name>-<Syncing BackingImage UUID>/backing.tmp
  <Disk path in container>/backing-images/<Ready BackingImage name>-<Ready BackingImage UUID>/backing
  <Disk path in container>/backing-images/<Ready BackingImage name>-<Ready BackingImage UUID>/backing.cfg
  ```
- There is a goroutine periodically check the file existence based on the image file current state.
    - It will verify the disk UUID in the disk config file. If there is a mismatching, it will stop checking existing files. And the calls, longhorn manager pods, won't send requests since this BackingImageManager is marked as `unknown`. 
- The manager will provide one channel for all BackingImages. If there is an update in a BackingImage, the image will send a signal to the channel. Then there is another goroutine receive the channel and notify the longhorn manager via the streaming created by API `Watch`.

#### longhorn-ui:
1. Launch a new page to present and operate BackingImages.
    1. Add button `Create Backing Image` on the top right of the page:
        - Field `name` is required and should be unique.
        - Field `sourceType` is required and accept an enum value. This indicates how Longhorn can get the backing image file. Right now there are 2 options: `download`, `upload`. In the future, it can be value `longhorn-volume`.
        - Field `parameters` is a string map and is determined by `sourceType`. If the source type is `download`, the map should contain key `url`, whose value is the actual download address. If the source type is `upload`, the map is empty.
        - Field `expectedChecksum` is optional. The user can specify the SHA512 checksum of the backing image. When the backing image fetched by Longhorn doesn't match the non-empty expected value, the backing image won't be `ready`.
    2. If the source type of the creation API is `upload`, UI should send a `upload` request with the actual file data when the upload server is ready for receiving. The upload server ready is represented by first disk file state becoming `starting`. UI can check the state and wait for up to 30 seconds before sending the request.
    3. Support batch deletion: Allow selecting multiple BackingImages; Add button `Deletion` on the top left.
    4. The columns on BackingImage list page should be: Name, Size, Created From (field `sourceType`), Operation.
    5. Show more info for each BackingImage after clicking the name:
        - Present `Created From` (field `sourceType`) and the corresponding parameters `Parameters During Creation` (field `parameters`).
            - If `sourceType` is `download`, present `DOWNLOAD FROM URL` instead.
        - Show fields `expectedChecksum` and `currentChecksum` as `Expected SHA512 Checksum` and `Current SHA512 Checksum`. If `expectedChecksum` is empty, there is no need to show `Expected SHA512 Checksum`. 
        - Use a table to present the file status for each disk based on fields `diskFileStatusMap`:
            - `diskFileStatusMap[diskUUID].progress` will be shown only when the state is `in-progress`.
            - Add a tooltip to present `diskFileStatusMap[diskUUID].message` if it's not empty.
    6. Add the following operations under button `Operation`:
        - `Delete`: No field is required. It should be disabled when there is one replica using the BackingImage.
        - `Clean Up`: A disk file table will be presented. Users can choose the entries of this table as the input `disks` of API `CleanupDiskImages`. This API is dedicated for manually cleaning up the images in some disks in advance.
    7. When a BackingImage is being deleted (field `deletionTimestamp` is not empty), show an icon behind the name which indicates the deletion state.
    8. If the state of all disk records are `failed`, use an icon behind the name to indicates the BackingImage unavailable.
2. Allow choosing a BackingImage for volume creation.
3. Modify Backup page for BackingImage:
    - Allow choosing/re-specifying a new BackingImage for restore/DR volume creation:
        - If there is BackingImage info in the backup volume, an option `Use previous backing image` will be shown and checked by default.
        - If the option is unchecked by users, UI will show the BackingImage list so that users can pick up it.
    - Add a button `Backing Image Info` in the operation list:
        - If the backing image name of a BackupVolume is empty, gray out the button.
        - Otherwise, present the backing image name and the backing image checksum.

   | HTTP Endpoint                                                  | Operation                                                                |
   | -------------------------------------------------------------- | ------------------------------------------------------------------------ | 
   | **GET** `/v1/backingimages`                                    | Click button `Backing Image`                                             |
   | **POST** `/v1/backingimages/`                                  | Click button `Create Backing Image`                                      |
   | **DELETE** `/v1/backingimages/{name}`                          | Click button `Delete`                                                    |
   | **GET** `/v1/backingimages/{name}`                             | Click the `name` of a backing image                                      |
   | **POST** `/v1/backingimages/{name}?action=backingImageCleanup` | Click button`Clean Up`                                                   |
   | **POST** `/v1/backingimages/{name}?action=upload`              | Longhorn UI should call it automatically when the upload server is ready |

### Test Plan
#### Integration tests
1. Backing image basic operation
2. Backing image auto cleanup
3. Backing image with disk migration

#### Manual tests
1. The backing image on a down node
2. The backing image works fine with system upgrade & backing image manager upgrade
3. The incompatible backing image manager handling
4. The error presentation of a failed backing image

### Upgrade strategy
N/A

