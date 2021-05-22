# Backing Image Uplad

## Summary
Besides downloading backing image from remote URLs, Longhorn should allow users to upload a local file as a backing image.

### Related Issues
https://github.com/longhorn/longhorn/issues/2404

## Motivation
### Goals
Support upload large files as backing images.

## Proposal
1. During backing image creation, Longhorn can provide another option as the backing image data source: `Upload From Remote`.
2. Large file uploading is required. This means both backend and frontend should not load and transfer all data of a file with a single request. Instead, a large file should be sliced into small chunks. Then backend can coalesce all chunks at the last step of uploading.
3. If the files of an uploaded backing image in all disk are gone, this backing image is no longer recoverable. Unlike downloading from URLs, Longhorn can not actively and silently fetch local files again after the 1st upload.
   Hence, Longhorn cannot do cleanup for an uploaded backing image if there is only one ready file.

### User Stories
#### Rebuild replica for a large volume after network fluctuation/node reboot
Before the enhancement, users need to upload the local file to a public storage like S3, generate the URL, then use the URL to create a backing image.

After the enhancement, users can directly create a backing image by uploading a local file.

### User Experience In Detail
1. Users Click button `Create Backing Image`, choose `Upload From Local`, then select the file and start uploading.
2. Users wait for the uploading initialization and data transferring complete.  
3. Users can create volumes with the uploaded backing image.

### API Changes
- Add a new field to indicate that the data source is from local files rather than URLs for the backing image creation API.
- Add a bunch of backing image actions to support the actual uploading: `uploadServerStart`, `chunkPrepare`, `chunkUpload`, `chunkCoalesce`, and `uploadServerClose`.

## Design
### Implementation Overview
#### longhorn-manager:
1. In API:
    - Due to UI and the nginx limitation, the frontend cannot directly talk with other Longhorn workloads except for longhorn manager pods. Hence, the longhorn manager pod api layer should use reverse proxy to forward the upload related requests to the backing image manager pods, in which there is a upload server for each uploading backing image.
    - The upload-related backing image APIs/actions in longhorn manager pod are mentioned above.
    - Unlike the forwarding for other resources, which relies on the owner ID to figure out another longhorn manger pod IP, the upload request forwarding address is determined by a new field `backingImage.status.uploadAddress`.
      This means a simple refactoring for Longhorn forwarding part is required.
    - For downloading backing image, the actual file will be downloaded only when Longhorn tries to launch the 1st replica using the backing image. But for uploading backing image, the 1st file should be processed once the CR is created.
      Hence, Longhorn should pick up a random schedulable disk to store the uploaded file during the creation.
    - For the cleanup API, it should error out if users try to remove all ready files or the only in-progress file for an upload backing image.
2. Controller:
    - To upload a file for the backing image, BackingImageManagerController should ask the backing image manager pod to start a upload server rather than sending a pull request.  
    - For the backing image cleanup, BackingImageController should make sure, there is at least one ready file or the only in-progess file that is not marked for deletion.
3. Engine API:
    - Update the backing image manager gRPC client for the upload.
    - Bump up the API version and the Min API version. Since Longhorn manager will force shutting down all old backing image manager pods when there is a newer version. The Min API version bump won't affect the upgrade.
4. Types:
    - Rename some fields and consts. See below for details.

#### backing-image-manager:
- Add a new gRPC API: `LaunchUploadServer`:
    - The manager layer is responsible for initialing a backing image object.
    - The backing image layer is responsible for requesting and release a port, and starting a upload server.
- Update the gRPC struct fields.
- Modify the backing image cleanup mechanism: Before handling the data for a new backing image, we should remove 3 files only rather than all contents in the work directory: tmp file, the backing file, and the cfg file.
  If the current backing image launching is an uploading retry and there are already some uploaded chunks in the work directory. Without removing all contents, the backing image can reuse the existing chunks later. 
- Implement a HTTP server as the upload server. Here are the API description and the workflow:
    1. `start`: ask the upload server to create a tmp file and set the total size for the backing image. This means upload start.
    2. `prepareChunk`: check if each chunk is already uploaded first. If the chunk is correct, the frontend will skip the current chunk upload and go next. If the chunk is not correct, it will do clean up first. Then an empty chunk file will be created. This API will be called before uploading each chunk.
    3. `uploadChunk`: write the actual chunk data to the chunk file.
    4. `coalesceChunk`: copy all chunk data into the tmp file created by `start` then clean up all chunk files.
    5. `close`: indicate upload complete.
    
#### longhorn-ui:
1. Ask users to choose the data source in backing image creation page.
2. Add a new operation `Retry Upload` so that users can continue uploading then the previous upload is interrupted. 
3. Show the uploading progress.
4. Parallel chunk processing.

#### others
Since backing image data is not only from downloading now, we will rename some fields and consts to avoid misleading.:
    1. `BackingImageStatus.DiskDownloadStateMap` --> `BackingImageStatus.DiskFileStateMap`
    2. `BackingImageStatus.DiskDownloadProgressMap` --> `BackingImageStatus.DiskFileHandlingProgressMap`
    3. `BackingImageFileInfo.DownloadProgress` --> `BackingImageFileInfo.Progress`
    4. `BackingImageDownloadState` --> `BackingImageState`
Besides, there are some functions/interface renaming in backing image manager part. See the implementation for details.

#### Manual tests
Test the uploading with interruption.

### Upgrade strategy
N/A

