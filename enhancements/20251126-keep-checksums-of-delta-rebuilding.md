# Keep Checksums Of Delta Rebuilding

## Summary

This enhancement outlines a method to persist checksums of transmitted data chunks during the Longhorn volume delta rebuilding process. By integrating SQLite into the sparse-tools client, we can store checksums immediately after data is successfully sent. This feature is currently supported only for the V1 data engine.

### Related Issues

- https://github.com/longhorn/longhorn/issues/8737

## Motivation

### Goals

- A global setting to enable or disable this feature.
- Integrate a lightweight SQLite database into the sparse-tools client.
- Calculate and store checksums (e.g., CRC64 or SHA-256) for every data interval sent during the delta rebuilding process.
- Provide persistent records of the replica's data intervals for future verification.
- Skip transferred data when retrying the replica rebuilding process.

### Non-goals [optional]

- This enhancement does not cover the logic for verifying the data against these checksums on the server side (receiver).
- Calculate the data interval checksums and store checksums into the database when the snapshot is created.

## Proposal

### User Stories

- Integrity: It ensures that the data sent during a rebuild matches the source data by cross-referencing the stored checksums.
- Resume-like functionality: Longhorn will skip re-sending chunks that have already been confirmed as sent during a previous rebuild attempt, using the local checksum database as a state tracker.

### User Experience In Detail

The user experience remains largely unchanged for the end-user operating Longhorn via the UI or kubectl. However, for developers and advanced users debugging the system:

1. A new SQLite database file (e.g., rebuild_tracking.db) will be created in the Longhorn working directory (`/var/lib/longhorn/`).
2. During sync operations, a rebuilding starts, a slight performance degradation may be noticeable due to checksum calculation.
3. If a rebuild fails, the database file can be retrieved by Longhorn to analyze the progress and data integrity state.

### API changes

N/A

## Design

### Implementation Overview

The core logic changes will occur in `longhorn-engine/pkg/sync/rpc/server.go`, `sparse-tools/sparse/client.go` and `sparse-tools/sparse/rest/handlers.go`.

#### A Global Setting `skip-transferred-data-when-rebuilding`

This enhancement will increase the rebuilding time and disk usage for calculating the data interval checksums and inserting the records into the database.
Therefore, users can disable the feature via this setting if they don't want to waste time building the checksum database for rebuilding.

1. Add the setting in `longhorn-manager/types/setting.go`:

```go
const (
  SettingNameAllowRecurringJobWhileVolumeDetached = SettingName("allow-recurring-job-while-volume-detached")
  SettingNameCreateDefaultDiskLabeledNodes        = SettingName("create-default-disk-labeled-nodes")
  ...
  SettingNameSkipTransferredDataWhenRebuilding    = SettingName("skip-transferred-data-when-rebuilding")
)
...
var (
  settingDefinitions = map[SettingName]SettingDefinition{
    SettingNameAllowRecurringJobWhileVolumeDetached: SettingDefinitionAllowRecurringJobWhileVolumeDetached,
    SettingNameCreateDefaultDiskLabeledNodes:        SettingDefinitionCreateDefaultDiskLabeledNodes,
    ...
    SettingNameSkipTransferredDataWhenRebuilding:    SettingDefinitionSkipTransferredDataWhenRebuilding,
)
...
  SettingDefinitionSkipTransferredDataWhenRebuilding = SettingDefinition{
    DisplayName:        "Skip Transferred Data When Rebuilding",
    Description:        ...,
    Category:           SettingCategoryGeneral,
    Type:               SettingTypeString,
    Required:           true,
    ReadOnly:           false,
    DataEngineSpecific: true,
    Default:            fmt.Sprintf("{%q:\"true\"}", longhorn.DataEngineTypeV1),
  }
```

2. Send the value of the setting `skip-transferred-data-when-rebuilding` from `longhorn-manager/engine_controller` through `longhorn-instance-manager` to `longhorn-engine`

#### Database Initialization

Longhorn will need to add a Go SQLite driver (e.g., pure Go libraries `modernc.org/sqlite`) to the `sparse-tools` go.mod file.

Before the synchronizing snapshot content loop begins, the client and server will initialize SQLite database connections and create tables if they don't exist. The database file name will be the snapshot image file name with a suffix `.db`, for example `volume-snap-de52a2e1-5267-4a50-a031-2ba273548c47.img.db` and will be stored in the replica directory of the worker node. The database will be saved after rebuilding.

```sql
CREATE TABLE IF NOT EXISTS snapshot (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ctime DATETIME NOT NULL,
    mtime DATETIME NOT NULL
);
CREATE TABLE IF NOT EXISTS sent_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    begin INTEGER NOT NULL,
    end INTEGER NOT NULL,
    checksum INTEGER NOT NULL
);
```

#### Skip Transferred Data During Rebuilding

Calculate and store data checksum if the data interval is not transferred.

##### Full Rebuilding

- Whether snapshot image file is modified
  - Check if the `ctime` and `mtime` of snapshot image file in its directory (multiple replicas of a volume on the same disk) on the client and server sides are different from the record in the database.
- If yes, calculate the checksum of the data interval and save the checksum into the database (on client side), and send data buffer with the checksum to the server.
  - Write the data to the image file and store the checksum into the database (on server side).
- If no, compare the checksums in both databases (client and server sides) for each data interval.
  - Check if checksums for the data interval in both databases exist and are the same
    - If yes, skip transferring this data interval, and handle next data interval.
    - If no, calculate the checksum of the data interval and save the checksum into the database (on client side), and send data buffer with the checksum to the server.

##### Delta Rebuilding

- Whether snapshot image file is modified
  - Check if the `ctime` and `mtime` of snapshot image file in its directory (multiple replicas of a volume on the same disk) on the client and server sides are different from the record in the database.
- If yes, back to the original implementation, it will calculate the checksum of the data interval on both sides and check if two checksums are the same.
  - Save these checksums into the database on both sides.
- If no, compare the checksums in both databases (client and server sides) for each data interval.
  - Check if checksums for the data interval in both databases exist and are the same
    - If yes, skip transferring this data interval, and handle next data interval.
    - If no, back to the original implementation, it will calculate the checksum of the data interval on both sides and check if two checksums are the same.
      - Save these checksums into the database on both sides.

Pseudocode modification for `sparse-tools/sparse/client.go` (client side):

```go
func (client *syncClient) syncDataInterval(dataInterval Interval) error {
  // Process data in chunks
  for offset := dataInterval.Begin; offset < dataInterval.End; {
    ...
    if client.fileAlreadyExistsOnServer {
      if isTheSame, err := client.compareLocalAndRemoteIntervalFromDB(batchInterval); !isTheSame || err != nil {
        dataBuffer, err = client.CompareLocalAndRemoteInterval(batchInterval)
      }
    } else {
      ...
    }
    ...
    if dataBuffer != nil {
      // NEW: Checksum and Store, (e.g., sha256.Sum256(dataBuffer))
      checksum := calculateChecksum(dataBuffer)
      go func() {
        // Here needs a Lock or a channel to ensure the records are not written simultaneously 
        err := sqliteStore.RecordChunk(client.sourceName, offset, size, checksum)
        if err != nil {
            // Decide whether to log error or fail the rebuild
            log.Warnf("Failed to record checksum for offset %v: %v", currentOffset, err)
        }
      }
      log.Tracef("Sending dataBuffer size: %d", len(dataBuffer))
      if err := client.writeData(batchInterval, dataBuffer, checksum); err != nil {
        return errors.Wrapf(err, "failed to write data interval %+v", batchInterval)
      }
    }
    ...
  }
  return nil
}
...
func (client *syncClient) compareLocalAndRemoteIntervalFromDB(batchInterval Interval) (bool, error) {
  var serverChecksum, localChecksum []byte
  var serverChecksumErr, localChecksumErr error

  wg := sync.WaitGroup{}
  wg.Add(2)
  go func() {
    defer wg.Done()
    serverChecksum, serverChecksumErr = client.getServerChecksumFromDB(batchInterval)
    if serverChecksumErr != nil {
      log.WithError(serverChecksumErr).Errorf("Failed to get checksum of interval %+v from database of server", batchInterval)
      return
    }
  }()
  go func() {
    defer wg.Done()
    localChecksum, localChecksumErr = client.getLocalChecksumFromDB(batchInterval)
    if localChecksumErr != nil {
      log.WithError(localChecksumErr).Errorf("Failed to get checksum of interval %+v from database of local", batchInterval)
      return
    }
  }()
  wg.Wait()


  if len(serverChecksum) == 0 {
    return false, nil
  }

  // Compare server checksum with localChecksum
  return bytes.Equal(serverChecksum, localChecksum), nil
}
...
func (client *syncClient) getLocalChecksumDB(batchInterval Interval) (checksum []byte, err error) {
  // read checksum from local database
  checksum, err := sqliteStore.GetRecordChecksum(client.sourceName, batchInterval.Begin, batchInterval.Len())
  if err != nil {
    // Decide whether to log error or fail the rebuild
    log.Warnf("Failed to get checksum record for offset %v: %v", remoteDataInterval.Begin, err)
    return nil, err
  }

  return checksum, nil
}
```

Pseudocode modification for `sparse-tools/sparse/rest/handlers.go` (server side):

```go
func (server *SyncServer) doWriteData(request *http.Request) error {
  ...
  // Write file with received data into the range
  err = sparse.WriteDataInterval(server.fileIo, remoteDataInterval, data)
  if err != nil {
    return errors.Wrapf(err, "failed to write data interval %+v", remoteDataInterval)
  }

  // New: Get checksum and Store.
  go func() {
    queryParams := request.URL.Query()
    snapshotName := queryParams["snapshotName"]
    checksum := queryParams["checksum"]
    if checksum != "" {
      err := sqliteStore.RecordChunk(snapshotName, remoteDataInterval.Begin, remoteDataInterval.End, checksum)
      if err != nil {
        // Decide whether to log error or fail the rebuild
        log.Warnf("Failed to record checksum for offset %v: %v", remoteDataInterval.Begin, err)
      }
      err := sqliteStore.UpdateSnapshot(snapshotName)
      if err != nil {
        // Decide whether to log error or fail the rebuild
        log.Warnf("Failed to update snapshot %v: %v", snapshotName, err)
      }
    }
  }()
  ...
  return nil
}
```

#### Cleanup Old Records In The Database

After Longhorn finishes the rebuilding process, it should update the snapshot list in the database and clean up old or obsolete records in the snapshots and sent_chunks tables on both sides.

Pseudocode modification for `longhorn-engine/pkg/sync/rpc/server.go`:

```go
func (s *SyncAgentServer) fileSyncRemote(ctx context.Context, req *enginerpc.FilesSyncRequest) error {
  // We generally don't know the from replica's instanceName since it is arbitrarily chosen from candidate addresses
  // stored in the controller. Don't modify FilesSyncRequest to contain it, and create a client without it.
  fromClient, err := replicaclient.NewReplicaClient(req.FromAddress, s.volumeName, "")
  ..

  for _, info := range req.SyncFileInfoList {
    ..
  }
  // New: Update the snapshot list (delete obsolete snapshots, such as those that have been deleted or merged) 
  err := fromClient.UpdateSnapshotList(s.volumeName, req.SyncFileInfoList)
  err := updateSnapshotList(s.volumeName, req.SyncFileInfoList)
  ...
  return nil
}
```

### Test plan

- Retrying the replica rebuild should be faster than the initial attempt:
  1. Create a volume with 3 replicas and write some data to the volume.
  2. Attach the volume to a node.
  3. Delete a replica of the volume and wait for the replica rebuilding to start.
  4. Interrupt (or simulate a crash of) the replica rebuilding process when it reaches 60% progress.
  5. The subsequent rebuild, which reuses the failed replica, should quickly reach 60% completion.

### Upgrade strategy

N/A
