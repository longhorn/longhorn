# Enable Backing Image

## Summary
Longhorn can set a backing image of a Longhorn volume, which is designed for VM usage.

### Related Issues
https://github.com/longhorn/longhorn/issues/2006

## Motivation
### Goals
1. A qcow2 or raw image file can be used as the backing image of a volume.
2. The backing image works fine with backup or restore.  
3. Multiple replicas in the same disk can share one backing image.   

## Proposal
1. For `longhorn-manager`:
    1. The backing image of a Longhorn volume should be downloaded by someone before starting the related volume replicas.
        - Instance manager pods are only responsible for managing process, which implicitly means they are isolated from the data layer. Hence, Longhorn should not rely on instance manager to fetch backing images.  
        - Since a backing image can be shared by multiple replicas, using replica processes to download backing images is not a good idea. Otherwise, a backing image may be downloaded duplicately by multiple replica processes.
        - As a result, the only choice here is longhorn manager.
    2. Since a backing image is a kind of resource, it's better to use a new CRD to abstract it.
        - Similar to the CRD `engineimages.longhorn.io`, there is one CR for each backing image.
        - Longhorn can present this kind of resource with a separate UI page so that users are capable of operating the CRs manually. Then when users want to create a volume with a backing image, they need to choose one from the existing backing image list.
        - Since some disks won't be chosen by replicas with backing images, there should be a disk map in the CR spec to indicate in which disk/node a backing image should be downloaded.
        - Considering the disk migration and failed replica reusage features, there will be an actual backing image file for each disk rather than each node.
        - There will be a new controller to launch pods to download backing images based on the disk maps, as well as handling the backing image download status for each disk.
    3. Before sending requests to launch replica progresses, replica controller will check and wait for the backing image ready if a backing image is set for the related volumes.
        - This is a common logic that is available for not only normal volumes but also restoring/DR volumes. 
        - We need to make sure the backing image names as well as the URLs are stored in backup volumes. So users are able to re-specify the backing image when restoring a volume in case of the original image becoming invalid.
    4. There should be a cleanup timeout setting and a related timestamp that indicates when a backing image can be removed from a disk when no replica in the disk is using the backing image.  
2. For `longhorn-engine`:
    - Most of the backing image related logic is already in there.
    - The raw image support will be introduced.
    - Make sure the backing file path will be updated each time when the replica starts.

### User Stories
#### Rebuild replica for a large volume after network fluctuation/node reboot
Before the enhancement, users need to manually copy the backing image data to the volume in advance.

After the enhancement, users can directly specify the backing image during volume creation/restore with a click.

### User Experience In Detail
1. Users can modify the backing image cleanup timeout setting so that all non-used backing images will be cleaned up automatically from disks.
2. Create a volume with a backing image 
    2.1. via Longhorn UI 
        1. Users add a backing image, which is similar to add an engine image in the system.
        2. Users create/restore a volume with the backing image specified from the backing image list.
    2.2. via CSI (StorageClass)
       1. Users specify `backingImageName` and `backingImageURL` in a StorageClass.
       2. Users use this StorageClass to create a PVC. When the PVC is created, Longhorn will automatically create a volume as well as the backing image if not exists.
3. Users attach the volume to a node (via GUI or Kubernetes). Longhorn will automatically download the related backing image to the disks the volume replica are using. In brief, users don't need to do anything more for the backing image.   
4. When users backup a volume with a backing image, the backing image content won't be uploaded to the backupstore. Instead, the backing image will be re-downloaded from the original image once it's required.

### API Changes
- A bunch of RESTful APIs is required for the new CRD "backing image": `Create`, `Delete`, `List`, and `BackingImageCleanup`.
- Now the volume creation API receives parameter `BackingImage`.

## Design
### Implementation Overview
#### longhorn-manager:
1. Add a setting `BackingImageCleanupWaitInterval`.
2. Add a new CRD `backingimages.longhorn.io`.
    - Field `Spec.Disks` is designed for recording the disks that the backing images need to be downloaded to. And the map is empty when a backing image CR is just created.
    - A disk/corresponding download progress map should be in `status`. So that a replica can directly find and verify the corresponding backing image before launching the replica process. If the status is not `downloaded`, the replica controller needs to wait for the state before launching the replica process. 
3. Add a new controller `Backing Image Controller`.
    - By comparing field `Spec.Disks` with field `Status.DiskStatusMap`, the controller knows if a pod for downloading the backing image should be created.  
    - Field `BackingImageDownloadState` is the value of map `Status.DiskStatusMap`. It can be `downloaded`/`downloading`/`failed`/`terminating`.
    - Once a pod successfully downloads the file, a file that is used as the download success flag will be created, and the pod readiness probe will rely on the file existence to determine if the pod is available.
    - A timestamp will be set for a disk in `Status.DiskLastRefAtMap` once there is no replica in the disk using the backing image. And the timestamp will be unset if there is one replica in the disk using/reusing it. 
4. In Replica Controller:
    - Request downloading the image into a disk if a backing image used by a replica doesn't exist.
    - Check and wait for backing image disk map in the status before sending requests to replica instance managers.
5. In Node Controller:
    - Determine if the disk needs to be cleaned up if checking backing image `Status.DiskLastRefAtMap` and the wait interval `BackingImageCleanupWaitInterval`.
6. For the API volume creation:
    - Longhorn needs to verify the backing image if it's specified.
    - For restore/DR volumes, the backing image name stored in the backup volume will be used automatically if users do not specify the backing image name.
7. In CSI:
    - Check the backing image info during the volume creation.
    - The missing backing image will be created when both backing image name and url are provided.

#### longhorn-engine:
- Verify the existing implementation and the related integration tests.
- Add raw backing file support.
- Update the backing file info for replicas when a replica is created/opened.

#### longhorn-ui:
1. Launch a new page to present and operate backing images.
    1. Show the image (download) status for each disk based on `Status.DiskStatusMap` when users expand one backing image.
    2. Add the following operating list:
        - `Create`: The required field is `image`.
        - `Delete`: No field is required. It should be disabled when there is one replica using the backing image.
        - `CleanupDiskImages`: This allows users to manually clean up the images in some disks in advance. It's a batch operation.
2. Allow choosing a backing image for volume creation.
3. Allow choosing/re-specifying a new backing image for restore/DR volume creation.

### Test Plan
#### Integration tests
##### Backing image basic operation
1. Create a backing image.
2. Create and attach a Volume with the backing image set.
3. Verify that the all disk states in the backing image are "downloaded".
4. Try to use the API to manually clean up one disk for the backing image but get failed.
5. Try to use the API to directly delete the backing image but get failed.
6. Delete the volume.
7. Use the API to manually clean up one disk for the backing image
8. Delete the backing image.

##### Backing image auto cleanup
1. Set `BackingImageCleanupWaitInterval` to default value.
2. Create a backing image.
3. Create multiple volumes using the backing image.
4. Attach all volumes, Then:
    1. Wait for all volumes can become running.
    2. Verify the correct in all volumes.
    3. Verify the backing image disk status map.
    4. Verify the only backing image file in each disk is reused by multiple replicas. 
       The backing image file path is `<Data path>/<The backing image name>/backing`
5. Decrease the replica count by 1 for all volumes. 
6. Remove all replicas in the host node disk. Wait for 1 minute.
   Then verify nothing changes in the backing image disk state map 
   (before the cleanup wait interval is passed).
7. Modify `BackingImageCleanupWaitInterval` to a small value. Then verify:
    1. The download state of the disk containing no replica becomes 
       terminating first, and the entry will be removed from the map later.
    2. The related backing image file is removed.
    3. The download state of other disks keep unchanged. All volumes still work fine.
8. Delete all volumes. 
   Verify that all states in the backing image disk map will become terminating first, 
   and all entries will be removed from the map later.
9. Delete the backing image.

##### Backing image with disk migration
1. Update settings:
   1. Disable Node Soft Anti-affinity.
   2. Set Replica Replenishment Wait Interval to a relatively long value.
2. Create a new host disk.
3. Disable the default disk and add the extra disk with scheduling enabled for the current node.
4. Create a backing image.
5. Create and attach a 2-replica volume with the backing image set.
   Then verify:
   1. there is a replica scheduled to the new disk.
   2. there are 2 entries in the backing image download state map, and both are state `downloaded`.
6. Directly mount the volume (without making filesystem) to a directory.
   Then verify the content of the backing image by checking the existence of the directory `<Mount point>/guests/`.
7. Write random data to the mount point then verify the data.
8. Unmount the host disk. Then verify:
   1. The replica in the host disk will be failed.
   2. The disk state in the backing image will become failed.
   3. The related download pod named `<Backing image name>-<First 8 characters of disk UUID>` is removed.
9. Remount the host disk to another path. Then create another Longhorn disk based on the migrated path (disk migration).
10. Verify the followings.
    1. The disk added in step3 (before the migration) should be `unschedulable`.
    2. The disk added in step9 (after the migration) should become `schedulable`.
    3. The failed replica will be reused. And the replica DiskID as well as the disk path is updated.
    4. The 2-replica volume r/w works fine.
    5. The download state in the backing image will become `downloaded`.
    6. The related download pod will be recreated.
11. Do cleanup.

#### Manual tests
##### The backing image on a down node
1. Update the settings:
    1. Disable Node Soft Anti-affinity.
    2. Set Replica Replenishment Wait Interval to a relatively long value.
2. Create a backing image.
3. Create and 2 volumes with the backing image and attach them on different nodes.
4. Verify the backing image content then write random data in the volumes.
5. Power off a node containing one volume. Verify that 
   - the related disk download state in the backing image will become `failed` once the download pod is removed by Kubernetes.
   - the volume on the running node still works fine but is state `Degraded`, and the content is correct in the volume.
   - the volume on the down node become `Unknown`.
6. Power on the node. Verify 
   - the failed replica of the `Degraded` volume can be reused.
   - the volume on the down node will be recovered automatically.
   - the backing image will be recovered automatically.

##### The backing image works fine during system upgrade
1. Set `Concurrent Automatic Engine Upgrade Per Node Limit` to a positive value to enable volume engine auto upgrade.
2. Create a backing image.
3. Create and attach volumes with the backing image.
4. Verify the backing image content then write random data in the volumes.
5. Upgrade the whole Longhorn system with a new engine image.
6. Verify the volumes still work fine, and the content is correct in the volumes during/after the upgrade.

### Upgrade strategy
N/A

