# Create Backing Image From Volume

## Summary
Longhorn can create a backing image from an existing Longhorn volume.

### Related Issues
https://github.com/longhorn/longhorn/issues/2403

## Motivation
### Goals
1. Longhorn should allow users to directly generate a backing image based on an existing volume.
2. We need to consider the compatibility with [the volume clone feature](https://github.com/longhorn/longhorn/issues/1815).   

### Non-goals:
1. A full design or implementation for feature "volume clone".
2. Download the volume content to a file.

## Proposal
1. Add a new gRPC API for the backing image that allow backing image managers fetch the backing file inside the disk.
2. Add a field for the backing image creation HTTP API that indicates the data sources is a volume.
    1. Automatically attach & detach the volume in the API call.
    2. Create a snapshot then ask the replica sync agent server to export the volume data to a file. This is similar to backup creation.
3. To export a file based on a replica. A new API is required for the sync agent server. This API can be reused later by feature "volume clone".

### User Stories
#### Rebuild replica for a large volume after network fluctuation/node reboot
Before the enhancement, users need to:
1. Manually attach the volume somewhere with block volume mode
2. Copy the volume data to a file.
3. Find a way to upload the file to a remote storage or download the file to the local.
4. Create a new backing image with the downloaded file or with URL.

After the enhancement, users can directly create a new backing image by specifying the volume name in UI.

### User Experience In Detail

### API Changes
- Add a new option for the backing image creation, which is actually a new field named `FromVolume`. This indicates a Longhorn volume as the data source.
- Add a new gRPC call `Load` for backing image manager service. This means loading a in-disk file as a new backing image.
- Add a new gRPC call `ExportDataToFile` for sync agent service. This means export volume content to a file based on snapshot files in a replica.

## Design
### Implementation Overview
#### longhorn-manager:
Add a new field for the backing image HTTP resource `FromVolume`. The followings will be applied when the backing image creation API finds this field not empty:
    1. Verify the selected volume is detached.
    2. Attach the volume without frontend in the API. Add a defer function to detach the volume.
    3. Create a system snapshot for the volume. Add a defer function to delete the snapshot.
    4. Call `ExportDataToFile` to the sync agent server of the volume via the engine binary.
    5. Create a backing image with the disk map set and field `FromFile` set.

Refactor CRD `BackingImage` spec by adding a new struct `Source` to indicate that how to get the file data for the backing image:
    - Field `Type` in the struct is an enum. Now there are 3 options: `DownloadFromURL`, `Upload`, `ExportFromVolume`. (Not sure if we can consider syncing from other nodes are a separate type.)
    - Field `Value` varies depends on `Type` value: For Type `DownloadFromURL`, the value means download URL; For Type `Upload`, the value means local file path; For Type `ExportFromVolume`, the value means volume name.
Then we can remove some fields like `ImageURL`, `RequireUpload`, `SenderAddress`...

Automatically recover the backing image only when there is still one ready disk file, or the backing image source type is `DownloadFromURL`.
If all disk files are failed and the source type is not `DownloadFromURL`, there is no way to recover the backing image. Since the source is not available after the 1st time creation.

#### longhorn-engine:
Add a new gRPC call `ExportDataToFile` for the sync agent service:
    - The file will be exported to path `<Disk Path>/tmp/export-<Volume Name>`
    - Similar to the backup creation, a ready only replica with given snapshot ID will be constructed. This replica object understands how to read data from replica files. Then sync agent server can copy the data from the replica to the path `<Disk Path>/tmp/export-<Volume Name>.tmp`.
    - After copy complete, rename `<Disk Path>/tmp/export-<Volume Name>.tmp` to `<Disk Path>/tmp/export-<Volume Name>`
   
#### backing-image-manager:
Add a new gRPC call `Load` for backing image manager gRPC service:
    - Create a new backing image.
    - When the file `<Disk Path>/tmp/export-<Volume Name>.tmp` exists, mark the state as `in_progress`
    - When the file `<Disk Path>/tmp/export-<Volume Name>` exists, mark the state as `ready`.
    - Notice that there is no way to calculate the progress here.

#### longhorn-ui:
Provide a new way to create backing image besides pulling and uploading: `Create from a detach volume`.

### Test Plan
#### Integration tests
TBD

#### Manual tests
TBD

### Upgrade strategy
N/A

