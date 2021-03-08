# Backing Image

## Summary
Longhorn can set a backing image of a Longhorn volume, which is designed for VM usage.

### Related Issues
https://github.com/longhorn/longhorn/issues/2006
https://github.com/longhorn/longhorn/issues/2295

## Motivation
### Goals
1. A qcow2 or raw image file can be used as the backing image of a volume.
2. The backing image works fine with backup or restore.  
3. Multiple replicas in the same disk can share one backing image.
4. One backing image should be downloaded from remote once then delivered to other nodes by Longhorn. 

### Non-goals:
This feature is more responsible for fixing issue mentioned in [issue #1948](https://github.com/longhorn/longhorn/issues/1948#issuecomment-791641308).

## Proposal
1. Launch a new kind of workload `backing-image-manager` to handle all backing imges for each disk.
    1. Supports pulling a image file from remote URLs, or syncing a image file from other managers.
    2. Supports Live upgrade:
        1. The caller (longhorn-manager) will ask old managers to report all not-be-sent image files first.
        2. The new managers will take over the ownerships of these files.
        3. Then the old managers will give up the ownerships and unregister the files.
    3. All image files will be periodically checked by managers.
    4. Once there is a modification for an image, managers will notify callers via the gRPC streaming.
1. For `longhorn-manager`:
     1. Similar to engines/replicas vs instance managers, there will be 2 new CRDs `backingimages.longhorn.io` and `backingimagemanagers.longhorn.io`.
         - Since some disks won't be chosen by replicas using backing images, there should be a disk map in each `backingimages.longhorn.io` CR spec to indicate in which disk/node a backing image should be downloaded.
         - Considering the disk migration and failed replica reusage features, there will be an actual backing image file for each disk rather than each node.
         - As a result, CRs of `backingimages.longhorn.io` are responsible for recording some meta info of each backing images, e.g., URL, UUID, Size, DiskMap. Its status will record downloads status or cleanup infos for each disk, then be presented by UI, so that users are capable of operating the CRs manually. 
         - Then CRs of `backingimagemanagers.longhorn.io` should record disk info, backing image list, and backing image manager pod image in spec. And its status will be synced with the report from the pods, which reflects the actual status of the backing image files.
    2. The backing image of a Longhorn volume should be downloaded by someone before starting the related volume replicas. Before sending requests to launch replica progresses, replica controller will check and wait for the backing image ready if a backing image is set for the related volumes.
         - This is a common logic that is available for not only normal volumes but also restoring/DR volumes.
         - We need to make sure the backing image names as well as the download address are stored in backup volumes. So users are able to re-specify the backing image when restoring a volume in case of the original image becoming invalid.
    3. BackingImageController is responsible for:
        1. Generate a UUID for each new backing image.
        2. Handle backing image manager life cycle.
        3. Sync download status/info with backing image manager status.
        4. Set timestamp if there is no replica using the backing image in a disk.  
    4. BackingImageManagerController is responsible for:
        - Create pods to handle backing image files.
        - Handle files based on the spec:
            - Delete unused backing images.
            - Transfer ownership of not-be-sent files from old version managers to new version managers. This is live upgrade.
            - Download backing images: If there is no file among all managers, directly pull a file from the remote. Otherwise, the current manager will fetch the file from other managers.
    6. There should be a cleanup timeout setting and a related timestamp that indicates when a backing image can be removed from a disk when no replica in the disk is using the backing image.  
2. For `longhorn-engine`:
    - Most of the backing image related logic is already in there.
    - The raw image support will be introduced.
    - Make sure the backing file path will be updated each time when the replica starts.
3. As we mentioned above, there should be backing image manager pods managing all backing images.
    - One backing image pod for one disk. If there is no disk on a node, there is no need to launch a manager pod. In other words, this is similar to replica instance manager.
    - A gRPC service will be launched in order to communicate with longhorn managers.
    - These operations should be considered: `Pull` (download from remote), `Sync` (request a backing image file from other manager pods), `Send` (send a backing image file to other manager pods), `TransferOwnership`, `Watch`(notifying the manager that the status of a backing image is updated), and `VersionGet`.
    - The pulling/sync progress should be calculated and reported to the manager.
    - To notify the longhorn manager, a gRPC streaming will be used for API `Watch`
    - A monitor goroutine will periodically check all backing image files.

### User Stories
#### Rebuild replica for a large volume after network fluctuation/node reboot
Before the enhancement, users need to manually copy the backing image data to the volume in advance.

After the enhancement, users can directly specify the backing image during volume creation/restore with a click. And one backing image can be shared among all replicas in the same disk.

### User Experience In Detail
1. Users can modify the backing image cleanup timeout setting so that all non-used backing images will be cleaned up automatically from disks.
2. Create a volume with a backing image 
    2.1. via Longhorn UI 
        1. Users add a backing image, which is similar to add an engine image or set up the backup target in the system.
        2. Users create/restore a volume with the backing image specified from the backing image list.
    2.2. via CSI (StorageClass)
       1. Users specify `backingImageName` and `backingImageAddress` in a StorageClass.
       2. Users use this StorageClass to create a PVC. When the PVC is created, Longhorn will automatically create a volume as well as the backing image if not exists.
3. Users attach the volume to a node (via GUI or Kubernetes). Longhorn will automatically download the related backing image to the disks the volume replica are using. In brief, users don't need to do anything more for the backing image. 
4. When users backup a volume with a backing image, the backing image info will be recorded in the backup but the actual backing image data won't be uploaded to the backupstore. Instead, the backing image will be re-downloaded from the original image once it's required.

### API Changes
- A bunch of RESTful APIs is required for the new CRD "backing image": `Create`, `Delete`, `List`, and `BackingImageCleanup`.
- Now the volume creation API receives parameter `BackingImage`.

## Design
### Implementation Overview
#### longhorn-manager:
1. In settings:
    - Add a setting `BackingImageCleanupWaitInterval`.
    - Add a read-only setting `default-backing-image-manager-image`.
2. Add a new CRD `backingimages.longhorn.io`.
    - Field `Spec.Disks` records the disks that the backing images need to be downloaded to. 
    - Field `Status.DiskStatusMap` is designed to reflect the actual download status for the disks. And field `BackingImageDownloadState` is the value of map `Status.DiskStatusMap`. It can be `downloaded`/`downloading`/`pending`/`failed`/`unknown`.
    - Field `Status.DiskDownloadProgressMap` will report the pulling/syncing progress for downloading files.
3. Add a new CRD `backingimagemanagers.longhorn.io`.
    - Field `Spec.BackingImages` records which backing images should be downloaded by the manager. the key is backing image name, the value is backing image UUID.
    - Field `Status.BackingImageFileMap` will be updated according to the actual file status reported by the related manager pod.
4. Add a new controller `BackingImageManagerController`.
    1. Important notices:
        1. Need to consider 3 kinds of managers: default manager, old manager, incompatible manager.
        2. For incompatible managers, the controller can assume gRPC client is unavailable hence we won't apply any file handling operations or update file status for them. Furthermore, it's meaningless to create new pods if the related pods crash.
        3. For old managers, it shouldn't download or delete any files. 
            - This can avoid crashing files or leading conflicts with the default manager.
            - Once there is no file in an old manager, BackingImageController will clean up the manager CR. 
            - If the pod of an old manager crashes unexpectedly during or before transferring, there is no need to restart the pod. Since the controller won't ask the pod to re-download or re-sync the files, the file info map will be empty even if the pod is restarted.
        4. For default managers, the controller need to take over all files from all old managers. The default manager should take over the ownership even if a file is failed or not required. Then old managers don't need to worry about the cleanup.
        5. In most cases, the controller and the backing image manager will avoid deleting backing images files.:
            - For example, if the pod is crashed or one image file becomes failed, the controller will directly restart the pod or re-download the image, rather than cleaning up the files only.
            - The controller will delete image files for only 2 cases: A backing images is no longer valid; A default backing image manager CR is deleted.
            - By following this strategy, we may risk at leaving some unused backing image files in some corner cases. However, the gain is that, there is lower probability of crashing a replica caused by deleting the backing image file deletion. Besides, the existing files can be reused after recovery.
        6. The pod not running doesn't mean all files handled by the pod become invalid. All files can be reused/re-monitored after the pod restarting.
    2. Workflow:
        1. If the deletion timestamp is set, the controller will clean up files for running default backing image managers only. Then it will blindly delete the related pods.
        2. If there is no ready disk or node based on the disk & node info in backing image manager spec, the current manager will be marked as `unknown`. Then all records are considered as `unknown` as well.
             - Actually there are multiple subcases here: node down, node reboot, node disconnection, disk detachment, longhorn manager pod missing etc. It's complicated to distinguish all subcases to do something sepcific. Hence, I choose simply marking the state to `unknown`.
        3. Create backing image manager pods.
            - If the status is `running` but the pod is not ready, there must be something wrong with the manager pod. Hence the controller need to update the state to `error`.
            - When the pod is ready, considering the case that the pod creation succeeds but the CR status update will fail due to conflicts, the controller won't check the previous state. Instead, it will directly update state to `running`.
            - Start a monitor goroutine for each running pods.
            - If the manager is state `error`, the controller will do cleanup then recreate the pod.
        4. Handle files based on the spec:
            - Delete invalid backing images:
                - The backing images is no longer in `BackingImageManager.Spec.BackingImages`.
                - The backng image UUID is not matching.
            - Transfer ownership of not-be-sent files (we call this kind of file as transfer ready files) from old version managers to new version managers:
                1. Send `OwnershipTransferStart` call to the old pod. A list of transfer ready files will be returned.
                2. Send `OwnershipTransferConfirm` call with the above list as input to the new pod. The new manager pod will register and monitor these files.
                3. Send `OwnershipTransferConfirm` call with the empty input to the old pod. The old manager pod will unregister and stop monitoring these files.
            - Download backing images for default managers: 
                1. If there is no existing file in a manager pod (including pods not using the default image), the controller will sort all default managers with name, then send a `Pull` call to the first manager. This guarantees that the file will be downloaded only once among all manager pods. 
                2. Otherwise, the current manager will try to fetch the file from other managers:
                    - If the 1st file is still being downloaded, do nothing.
                    - Each manager can send a downloaded backing image file to 3 other managers simultaneously at max. When there is no available sender, do nothing. 
        5. For the monitor goroutine, it's similar to that in InstanceManagerController.
            - It will `List` all backing image files once it receives the notification from the streaming.
            - If there are 10 continuous errors returned by the streaming receive function, the monitor goroutine will stop itself. Then the controller will restart it.
5. Add a new controller `BackingImageController`.
    1. Important notices:
        1. The main responsibility of this controller is creating, deleting, and update backing image managers. There is no gRPC call with the related backing image manager pod in this controller.
        2. Besides recording the immutable UUID, the backing image status is used to record the file info in the managers status and present to users.
        3. Always try to create default backing image managers if not exist. 
        4. Aggressively delete non-default backing image managers:
            1. All incompatible managers.
            2. All old managers are state error or contain no file info. Since there won't be new files launched in the old managers, and the regular cleanup logic maybe not able to remove them.
    2. Workflow:
        1. If the deletion timestamp is set, the controller need to do cleanup for all related backing image managers.
        2. Generate a UUID for each new backing image. Make sure the UUID is stored in ETCD before doing anything others.
        3. Init the maps in the backing image status.
        4. Handle backing image manager life cycle:
            - Remove records in `Spec.BackingImages` or directly delete the manager CR
            - Add records to `Spec.BackingImages` for the current backing image. Create backing image manager CRs with default image if not exist.
        5. Sync download status/info with backing image manager status:
            - Blindly update `Status.DiskDownloadStateMap` and `Status.DiskDownloadProgressMap`
            - Set `Status.Size` if it's 0.
        6. Set timestamp in `Status.DiskLastRefAtMap` if there is no replica using the backing image in a disk. Later NodeController will do cleanup for `Spec.DiskDownloadMap` based on the timestamp.
6. In Replica Controller:
    - Request downloading the image into a disk if a backing image used by a replica doesn't exist.
    - Check and wait for backing image disk map in the status before sending requests to replica instance managers.
7. In Node Controller:
    - Determine if the disk needs to be cleaned up if checking backing image `Status.DiskLastRefAtMap` and the wait interval `BackingImageCleanupWaitInterval`.
8. For the API volume creation:
    - Longhorn needs to verify the backing image if it's specified.
    - For restore/DR volumes, the backing image name stored in the backup volume will be used automatically if users do not specify the backing image name.
9. In CSI:
    - Check the backing image info during the volume creation.
    - The missing backing image will be created when both backing image name and address are provided.

#### longhorn-engine:
- Verify the existing implementation and the related integration tests.
- Add raw backing file support.
- Update the backing file info for replicas when a replica is created/opened.

#### backing-image-manager:
- The work directory of the backing image manager is like:
  ```
  <Disk path in container>/backing-images/
  <Disk path in container>/backing-images/<Downloading backing image1 name>-<Downloading backing image1 UUID>/backing.tmp
  <Disk path in container>/backing-images/<Downloaded backing image1 name>-<Downloaded backing image UUID>/backing
  <Disk path in container>/backing-images/<Downloaded backing image1 name>-<Downloaded backing image UUID>/backing.cfg
  ```
- It will verify the disk UUID in the disk config file. If there is a mismatching, it won't do anything.
- There is a goroutine periodically check the file existence based on the image file current state.
- The manager will provide one channel for all backing images. If there is a update in a backing image, the image will send a signal to the channel. Then there is another goroutine receive the channel and notify the longhorn manager via streaming.
- Launch a gRPC service with the following APIs.
    - API `Pull`: Register the image then download the file from a URL. For a failed backing image, the manager will re-register then re-pull it.
        - Before starting download, the image will check if there is existing files in the current work directory. It the file exists and the info in the cfg file matches the current status, the file will be reused directly and the actual pulling will be skipped.
        - As the 1st step of download starting, a cancelled context will be created. Then the image will use a HTTP request with this context to download the file. When the image is removed during downloading, or the download gets stuck for a while(the timeout is 4s for now), we can directly cancel the context to stop the download.
        - The download file is named as `backing.tmp`. Once the download complete, the file will be renamed to `backing`, the meta info/status will be recorded in the config file `backing.cfg`, and the state will be updated.
        - Each time when the image downloads a chunk of data, the progress will be updated.
    - API `Sync`: Register the image, start a receiving server, and ask another manager to send the file via API `Send`. For a failed backing image, the manager will re-register then re-sync it. This should be similar to replica rebuilding. 
        - Similar to `Pull`, the image will try to reuse existing files.
        - The manager is responsible for managing all port. The image will use the functions provided by the manager to get then release ports.
    - API `Send`: Send a backing image file to a receiver. This should be similar to replica rebuilding.
    - API `Delete`: Unregister the image then delete the imge work directory.
    - API `Get`/`List`: Collect the status of one backing image/all backing images. 
    - API `OwnershipTransferStart`: Collect all transfer ready images and return the list.
    - API `OwnershipTransferConfirm`:
        - For the new backing image manager, the input should be a list of transfer ready images. The manager will directly register the backing images, as well as start to handle all subsequent requests.
        - For the old backing image manager, the input should be empty. The manager will directly unregister those backing images, as well as stop monitoring the files and status.

#### longhorn-ui:
1. Launch a new page to present and operate backing images.
    1. Show the image (download) status for each disk based on `Status.DiskStatusMap` and `Status.DiskDownloadProgressMap` when users Click `Detail` of one backing image.
        - If the state is `downloading`, the progress will be presented as well.
    2. Add the following operating list:
        - `Create`: The required field is `image`.
        - `Delete`: No field is required. It should be disabled when there is one replica using the backing image.
        - `CleanupDiskImages`: This allows users to manually clean up the images in some disks in advance. It's a batch operation.
2. Allow choosing a backing image for volume creation.
3. Allow choosing/re-specifying a new backing image for restore/DR volume creation:
    - If there is backing image info in the backup volume, an option `Use previous backing image` will be shown and checked by default.
    - If the option is unchecked by users, UI will show the backing image list so that users can pick up it.

### Test Plan
#### Integration tests
1. Backing image basic operation
2. Backing image auto cleanup
3. Backing image with disk migration

#### Manual tests
1. The backing image on a down node
2. The backing image works fine with system upgrade & backing image manager upgrade
3. The incompatible backing image manager handling

### Upgrade strategy
N/A

