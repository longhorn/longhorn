# V2 Backing Image Support 

## Summary

This feature enables users to create and manage v2 backing images based on SPDK. With this feature, users can create a v2 volume with a v2 backing image to utilize the data stored in the backing image. 

### Related Issues

https://github.com/longhorn/longhorn/issues/6341

## Motivation

### Goals

#### V2 Backing Image Management

- Users are able to `create` a v2 backing image with `raw` or `qcow2` image.
- Each backing image copy is stored in a disk as a spdk lvol snapshot.
- Users are able to `sync` the backing image copy from one disk to another.
- Users are able `get` and monitor the information of the current backing image copy status.
- Users are able to `delete` the backing image copy which is a lvol snapshot in the disk.

#### With v2 Volume

- Users are able to create a v2 volume with a v2 backing image copy.
- The volume can be backed up and restored with the backing image.
- The replicas of the volume can be rebuilt with the backing image.
- The volume can be auto salvaged with the backing image.

### Non-goals
- Fix the issue of inconsistent checksum led by skipping zero when dumping the data to the backing image lvol.
    - issue: https://github.com/longhorn/longhorn/issues/9876 
- Allow users to backup a v2 backing image
    - https://github.com/longhorn/longhorn/issues/9992
- Allow users to export a v2 volume to a backing image
    - https://github.com/longhorn/longhorn/issues/9994
- Allow users to clone a v2 backing image.
    - https://github.com/longhorn/longhorn/issues/9996

## Proposal

### User Stories

#### V2 backing image management

Users are able to create a v2 backing image through specifying a `dataEngine` field in the spec of the CRD.
Longhorn will then automatically create the backing image copy on one of the disk with the source.

Users can update the `diskFileSpecMap` in the backing image CRD spec to `sync` the backing image copy to other disks or to `delete` the backing image copy on other disks.

Users can delete the backing image CR and all the backing image copies on every disks will be deleted.

Like v1 backing image, Longhorn maintains the number `minNumberOfCopies` of copies in the cluster to reduce the possibility of the data loss.

Like v1 backing image, Longhorn automatically cleans up the copies that are not used for a while to improve the space efficiency.


#### With the v2 volume

When the replicas require the backing image during the volume creation, the replica head lvol will be cloned from the backing image snapshot lvol. That backing image will become the first snapshot in the snapshot chain and the volume can read the data from it.

This v2 volume should contain the same data as a v1 volume with a v1 backing image.

This feature won't effect other volume's functionality. Volumes can still be rebuilt, backed up, restored and auto salvaged.

Note that when backing up a v1 volume with a v1 backing image, Longhorn automatically backs up the backing image. However, for v2, the v2 backing image is not backed up, as this feature has not yet been implemented. Therefore, users must create the v2 backing image in the new cluster in advance if they wish to restore the v2 volume there.

### Implementation Overview

#### CRD

- Add `DataEngine` to the Spec and each disk spec and status of the backing image
```
type BackingImageDiskFileStatus struct {
	DataEngine DataEngineType `json:"dataEngine"`
	...
}

type BackingImageDiskFileSpec struct {
	...
	DataEngine DataEngineType `json:"dataEngine"`
}

type BackingImageSpec struct {
	DiskFileSpecMap map[string]*BackingImageDiskFileSpec `json:"diskFileSpecMap"`
	...
	DataEngine DataEngineType `json:"dataEngine"`
}

type BackingImageStatus struct {
	DiskFileStatusMap map[string]*BackingImageDiskFileStatus `json:"diskFileStatusMap"`
	...
	V2FirstCopyStatus BackingImageState `json:"v2FirstCopyStatus"`
	V2FirstCopyDisk string `json:"v2FirstCopyDisk"`
}
```

- Add `BackingImage` to the instance manager CRD.

```
type InstanceManagerStatus struct {
	InstanceEngines map[string]InstanceProcess `json:"instanceEngines,omitempty"`
	InstanceReplicas map[string]InstanceProcess `json:"instanceReplicas,omitempty"`
	BackingImages map[string]BackingImageV2CopyInfo `json:"backingImages"`
	...
}

type BackingImageV2CopyInfo struct {
	Name string `json:"name"`
	UUID string `json:"uuid"`
	DiskUUID string `json:"diskUUID"`
	Size int64 `json:"size"`
	Progress int `json:"progress"`
	State BackingImageState `json:"state"`
	CurrentChecksum string `json:"currentChecksum"`
	Message string `json:"message"`
}
```


#### BackingImage Controller

- We break the V2 backing image life cycle into 2 parts
    - Prepare first v2 backing image copy.
    - Manage v2 backing image copy in each disk periodically.

1. V2 Backing Image Preparation
    - Prepare first v1 backing image file
        - Same as the original flow
        - Utilize `backing-image-data-source` and `backing-image-manager` to prepare first v1 backing image copy with the source.
    - Prepare first v2 backing image copy
        - With field: `V2FirstCopyStatus` and `V2FirstCopyDisk`
        - Wait until there is a v1 backing image file and is transferred to `backing-image-manager`
        - The state transition of the  `V2FirstCopyStatus` will be: `pending -> inProgress -> ready/failed/unknown`
            - Step1: Choose a v2 disk and create the backing image with the download url from the `backing-image-manager`
            - Step2: If the copy is `failed` or `unknown`, delete the copy and set the status to `pending` to restart the process. It will retry with a backoff.
            - Step3: If the copy is ready, clean up the v1 file disk. 

2. Manage v2 backing image copy in each disk periodically
    - deleteInvalidV2Copy:
        - Delete the copy in the disk if the disk is removed from the spec.
        - If there is a ready copy
            - Delete the unknown copies if **there is no status and lvol** on the disk
            - Delete the failed copies
    - prepareV2Copy:
        - If there is a ready copy
            - Create a copy on the disk specified in the CR spec but does not have a status yet.
            - Only create one at a time.
    - syncV2StatusWithInstanceManager:
        - V2 backing image is managed in the spdk server in the instance manager
        - The status of the snapshot lvol will be monitored and stored in the CR status of the instance manager
        - We iterate all the instance manager to get the status of the backing image on each disk and update the backing image CR status.
        - If the copy has status before but fails to ge t the status from the instance manager this time, we mark it as `Unknown` 

Noted, if the node is rebooted, the in-memory status of the lvol in the spdk server will temporarily disappear. The status will become `Unknown`. However, the spdk server can pick up the backing image lvol and reconstruce the in-memory status. Thus, we only delete the `Unknown` copies when the lvol is also missing.

#### Backing Image Manager

- Data Source: Add a new parameter `DataEngine`. If it a is v2 backing image and the file format is qcow2, we convert it to raw when preparing the backing image file. So the checksum and the size can be consistent to the final v2 backing image lvol snapshot.
- Backing Image Manager: Add a parameter to the download backing image endpoint. The SPDK Server will use this endpoint to download the backing image data and store it in an lvol to create a v2 backing image. In this case, the endpoint does not need to compress the data.

#### Instance Manager Controller
- Add a backing image monitor utilizing engine proxy client to get the backing image lvol snapshot status from the spdk server.
- Add a set of spdk backing image APIs in engine proxy so controller can operate the backing image through the engine proxy.

```
SPDKBackingImageCreate(name, backingImageUUID, diskUUID, checksum, fromAddress, srcDiskUUID string, size uint64) (*imapi.BackingImage, error)
SPDKBackingImageDelete(name, diskUUID string) error
SPDKBackingImageGet(name, diskUUID string) (*imapi.BackingImage, error)
SPDKBackingImageList() (map[string]longhorn.BackingImageV2CopyInfo, error)
SPDKBackingImageWatch(ctx context.Context) (*imapi.BackingImageStream, error)
```

#### SPDK server

- Add a set of backing image APIs
```
BackingImageCreate
BackingImageDelete
BackingImageGet
BackingImageList
BackingImageWatch
BackingImageExpose
BackingImageUnexpose
```
- Backing Image Create
    1. Create a temp head `bi-${biName}-disk-${lvsUUID}-temp-head` lvol
    2. Expose the temp head and create a target device
    3. If `download` from the backing-image-manager URL
        - HTTP request the data and copy into the lvol
    4. If `sync` from other spdk server lvol snapshot
        - Request the source to expose the backing image snapshot by `BackingImageExpose`
        - Connect the external snapshot and setup a source device
        - Copy the data from the source device to the target device
        - Request the source to unexpose the backing image.
    5. Create a snapshot `bi-${biName}-disk-${lvsUUID}` from the temp head and stored the following info to the xattr
        - `backingImageUUID`.
        - `state`. So we know if this prepation is ready or failed.
        - `checksum`.
- Verify
    - For records already existing, we check if the lvol exists.
        - If lvol is missing, we mark the status to `Failed`, so the controller can recreate the backing image copy on this disk.

    - For records missing, we reconstruct the record from the info stored in the xattr: `backingImageUUID`, `state` and `checksum`.

- For replica creation
    - If it is created from a backing image, we clone the replica head from the backing image lvol snapshot and resize the head.
    - We put the backing image to the `r.ActiveChain[0]`
    - We add a new field `r.BackingImage` to stored the backing image lvol.

- For replica reconstructing `ActiveChain`
    - It check the **parent of the ancestor** of the replica to see if it has a backing image.
    - It gets backing image lvol and put it to the `r.ActiveChain[0]` and set the `r.BackingImage`

- For replica rebuilding
    - Since backing image name is `bi-${biName}-disk-${lvsUUID}`
    - When rebuilding the snapshot which is after the backing image, we need to rename the backing image name from the source replica from `bi-${biName}-disk-${srclvsUUID}` to `bi-${biName}-disk-${dstlvsUUID}` so the dst replica can find the backing image on its disk.

---

### Test plan

1. V2 Backing Image Creation
    - Create the backing images from the following YAML.
    - Create 3 volumes with the following 3 backing images.
    - Attach the volumes to the node.
    - They should have the same checksum.
```
# v1 
apiVersion: longhorn.io/v1beta2
kind: BackingImage
metadata:
  name: parrot-v1-raw
  namespace: longhorn-system
spec:
  dataEngine: v1
  minNumberOfCopies: 1
  sourceType: download
  sourceParameters:
    url: https://longhorn-backing-image.s3-us-west-1.amazonaws.com/parrot.raw
---
# raw
apiVersion: longhorn.io/v1beta2
kind: BackingImage
metadata:
  name: parrot-v2-raw
  namespace: longhorn-system
spec:
  dataEngine: v2
  minNumberOfCopies: 1
  sourceType: download
  sourceParameters:
    url: https://longhorn-backing-image.s3-us-west-1.amazonaws.com/parrot.raw
---
# qcow2
apiVersion: longhorn.io/v1beta2
kind: BackingImage
metadata:
  name: parrot-v2-qcow2
  namespace: longhorn-system
spec:
  dataEngine: v2
  minNumberOfCopies: 1
  sourceType: download
  sourceParameters:
    url: https://longhorn-backing-image.s3-us-west-1.amazonaws.com/parrot.qcow2
```
2. V2 Backing Image Creation
    - Create the v2 backing image with all kind of the sources
        - Upload
        - Download
        - Export
        - Clone
        - Backup a v1 BackingImage and restore it to v2

3. Regression1 - Replica Rebuilding
    - Create a v2 volume with the v2 backing image
    - Delete one of the replica
    - The volume should become healthy again after replica rebuilding

4. Regression1 - Auto Salveage
    - Create a v2 volume with the v2 backing image
    - Delete all of the instance-manager
    - The volume should become healthy again after all instance manager come back.

5. Regression1 - Backup/Restore
    - Create a v2 volume with the v2 backing image
    - Attach it and write some data and get the checksum
    - Backup the volume
    - Restore the volume with the same v2 backing image
    - Attach it and get the checksum to see if the data is correct.

### Upgrade strategy

- All backing images before v1.8.0 should be `DataEngine=v1`
- All disks' spec and status of backing images before v1.8.0 should be `DataEngine=v1`

## Note [optional]

Additional notes.