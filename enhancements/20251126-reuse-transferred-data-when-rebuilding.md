# Reuse Transferred Data When Rebuilding

## Summary

This enhancement introduces a mechanism to reuse previously transferred data during the rebuilding process. By persisting checksums of transmitted data chunks in a local database, the system can identify and skip already synchronized data when retrying a failed rebuild. This feature is available only for the V1 data engine.

### Related Issues

- https://github.com/longhorn/longhorn/issues/8737

## Motivation

### Goals

- A global setting and per-volume setting to enable or disable this feature.
- Speed up failed delta replica rebuilding by calculating data interval checksums during rebuilding to skip transferred data when retrying the replica rebuilding process, and provide persistent records for the next replica rebuild as a source replica.

### Non-goals [optional]

- Calculate the data interval checksums and store them into the database when the snapshot is created.

## Proposal

### User Stories

Users will want the rebuilding process to skip transferring data chunks that have already been successfully synchronized in a previous attempt, rather than starting from scratch, to minimize the time the volume is in a degraded state and reduce network bandwidth usage and speed up recovery.

### User Experience In Detail

In some situations, for instance, environments with unstable network connections, replica rebuilding may frequently fail due to interruptions. Without this feature, each retry starts the rebuilding process from the beginning. If the network instability persists, the rebuilding process might never complete, leaving the volume in a degraded state. By enabling this feature, Longhorn calculates the checksums of transferred data of the snapshots and persists the records in the local database. This allows the rebuilding process to check if the data is transferred from the beginning to the point of failure, ensuring that the replica eventually becomes healthy even in poor environmental conditions.

#### Enable the Feature

Users can enable this feature globally or on a per-volume basis.

1. **Global Setting:**
   - **Longhorn UI:** Navigate to **Setting** > **General** > **Reuse Transferred Data When Rebuilding**. Select the checkbox and click the **Save** button to enable the feature.
   - **Kubectl:** Edit the setting using `kubectl edit settings.longhorn.io reuse-transferred-data-when-rebuilding -n longhorn-system` and set the value to `true`.

2. **Per-Volume Setting:**
   - **Longhorn UI:** Go to the volume detail page. In the **Volume Operation** list, select the **Reuse Transferred Data When Rebuilding**.
   - **Kubectl:** Edit the volume manifest. Set `Volume.spec.reuseTransferredDataWhenRebuilding` to `true`.

Each volume's individual `Spec` setting will override the global `Reuse Transferred Data When Rebuilding` setting.

| Global Setting (`reuse-transferred-data-when-rebuilding`) | Per-Volume Setting (`Volume.spec.reuseTransferredDataWhenRebuilding`) | Reusing Transferred Data Enabled |
| :-------------------------------------------: | :-------------------------------------------: | :------------------------: |
| `true`                                        | `ignored`                                     | Yes                        |
| `false`                                       | `ignored`                                     | No                         |
| `true`                                        | `enabled`                                     | Yes                        |
| `false`                                       | `enabled`                                     | Yes                        |
| `true`                                        | `disabled`                                    | No                         |
| `false`                                       | `disabled`                                    | No                         |

**Debugging:**

For developers and advanced users:

  On the client side:

- Healthy replica that does not have the database file.
  1. A new SQLite database file (e.g., `volume-snap-*.img.db`) will be created in the replica directory when a rebuild starts.
  2. Calculate the data chunk checksums and store them into the database.
- Healthy replica that does not have the database file. If a failure is encountered during rebuilding and the rebuild restarts.
  1. A new SQLite database file (e.g., `volume-snap-*.img.db`) will be created in the replica directory when a rebuild starts.
  2. Calculate the data chunk checksums and store them into the database.
  3. When the subsequent rebuild starts, open the database created in the previous failed rebuild.
  4. Get data chunk checksums from the database and check if the data chunks need to be transferred.
  5. If data chunk checksums do not exist in the database or data chunks need to be transferred,
     1. Calculate the data chunk checksums and store them into the database.
     2. Transfer the data chunks to the server.
- Healthy replica that has the database.
  1. When a rebuild starts, open the database created in the previous rebuild.
  2. Get data chunk checksums from the database and check if the data chunks need to be transferred.
  3. If data chunks need to be transferred,
     1. Calculate the data chunk checksums and store them into the database.
     2. Transfer the data chunks to the server.
- Healthy replica that has the database. If a failure is encountered during rebuilding and the rebuild restarts.
  1. When a rebuild starts, open the database created in the previous rebuild.
  2. Get data chunk checksums from the database and check if the data chunks need to be transferred.
  3. If data chunks need to be transferred,
     1. Calculate the data chunk checksums and store them into the database.
     2. Transfer the data chunks to the server.
  4. If a failure occurs during rebuilding, return to step 1.

### API changes

Introduce a new Volume Action API `reuseTransferredDataWhenRebuilding`:

  | API | Input | Output | Comments | HTTP Endpoint |
  | --- | --- | --- | --- | --- |
  | Update | N/A | err error | Enable/Disable reusing transferred data when rebuilding for the volume | **POST** `/v1/volumes/{VolumeName}?action=reuseTransferredDataWhenRebuilding` |

  ```go
  type UpdateReuseTransferredDataWhenRebuildingInput struct {
    ReuseTransferredDataWhenRebuilding bool `json:"reuseTransferredDataWhenRebuilding"`
  }
  ```

## Design

### Implementation Overview

#### Settings to Reuse Transferred Data

1. Add settings:

- Add a global setting `reuse-transferred-data-when-rebuilding` in `longhorn-manager/types/setting.go`:

  ```go
  const (
    SettingNameAllowRecurringJobWhileVolumeDetached = SettingName("allow-recurring-job-while-volume-detached")
    SettingNameCreateDefaultDiskLabeledNodes        = SettingName("create-default-disk-labeled-nodes")
    ...
    SettingNameReuseTransferredDataWhenRebuilding    = SettingName("reuse-transferred-data-when-rebuilding")
  )
  ...
  SettingDefinitionReuseTransferredDataWhenRebuilding = SettingDefinition{
    DisplayName:        "Reuse Transferred Data When Rebuilding",
    Description:        "When enabled, Longhorn will reuse transferred data chunks on the rebuilding replica node during a previous rebuild attempt. This improves rebuild efficiency and reduces unnecessary data transfer, but may increase disk usage and slightly impact performance due to checksum calculation and database storage.",
    Category:           SettingCategoryGeneral,
    Type:               SettingTypeBool,
    Required:           true,
    ReadOnly:           false,
    DataEngineSpecific: true,
    Default:            fmt.Sprintf("{%q:\"false\"}", longhorn.DataEngineTypeV1),
  }
  ```

- Add a new volume field `Volume.Spec.ReuseTransferredDataWhenRebuilding`:

  ```go
  type VolumeSpec struct {
    // +kubebuilder:validation:Type=string
    // +optional
    Size int64 `json:"size,string"`
    ...
    // +optional
    ReuseTransferredDataWhenRebuilding bool `json:"reuseTransferredDataWhenRebuilding"`
  }
  ```

2. Send the value of the setting `reuse-transferred-data-when-rebuilding` or `Volume.Spec.ReuseTransferredDataWhenRebuilding` from `longhorn-manager/engine_controller` through `longhorn-instance-manager` to `longhorn-engine`

#### Database Initialization and Life Cycle

##### Initialization

Longhorn will need to add a Go SQLite driver (e.g., pure Go libraries `modernc.org/sqlite`) to the `sparse-tools` go.mod file.

Before the synchronizing snapshot content loop begins, the client will initialize the database connection on client side and create tables if they don't exist. The database file name will be the snapshot image file name with a suffix `.db`, for example `volume-snap-de52a2e1-5267-4a50-a031-2ba273548c47.img.db`, and it will be stored in the replica directory of the worker node. Only the database on the client side will be saved after rebuilding.

Use the synchronous mode `NORMAL`:

  The SQLite database engine will still sync at the most critical moments, but less often than in FULL mode.  
  The default synchronous mode `NORMAL`: it will wait for all changes to be flushed to disk before continuing.

```sql
CREATE TABLE IF NOT EXISTS snapshot (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ctime TEXT NOT NULL,
    mtime TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    offset INTEGER NOT NULL,
    size INTEGER NOT NULL,
    checksum TEXT NOT NULL
);
```

##### Life Cycle

- Databases will be created if they do not exist, only on the client side (healthy replica node) when a rebuild starts.
- The system will keep the databases after rebuilding.
- When a snapshot is deleted or merged, Longhorn needs to delete its database for rebuilding if it exists.
- If a snapshot database cannot be accessed or is corrupted (opening or reading error), the database will be deleted and recreated when the rebuild starts.

#### Data Interval Size and Sending Data Chunk Size

![v1 snapshot image file data_interval and data chunk](./image/v1_snapshot_data_interval_and_chunk.png)

The entire blue area represents a data interval. The 2 MiB blocks A, B, and C are data chunks.

- The data interval size depends on the filesystem.

  A data interval is an extent retrieved from the snapshot image file using the system call `Syscall(syscall.SYS_IOCTL, f.Fd(), FS_IOC_FIEMAP, uintptr(extents))`

  Minimal Data Interval Size: 1 Block, 4 KiB.

  | Feature | EXT4 | XFS |
  | :---: | :---: | :---: |
  | Length Field | 16-bit (effectively 15-bit) | 21-bit |
  | Max Blocks | 32,768 (2^15) | 2,097,151 (2^21−1) |
  | Max Extent Size | 128 MiB | 8 GiB |

  Reference links: [EXT4](https://en.wikipedia.org/wiki/Ext4#Features), [XFS](https://android.googlesource.com/kernel/common/+/ecf61e4e1117/fs/xfs/libxfs/xfs_types.h#61)

- Data chunk size:

  The data chunk size determines the amount of data sent in each transmission and used for checksum calculation.

  ```go
  func (client *syncClient) syncDataInterval(dataInterval Interval) error {
    // Process data in chunks
    for offset := dataInterval.Begin; offset < dataInterval.End; {
      size := getSize(offset, client.syncBatchSize, dataInterval.End)
    ...
  }
  ```

  `client.syncBatchSize` is set to `defaultSyncBatchSize = 512 Blocks` (2 MiB) by default.

#### Skipping Transferred Data During Rebuilding

Get the snapshot image file information, `ctime` and `mtime`, before opening the snapshot file:

- **ctime**:
  Change time (inode change time), the last time the file’s metadata (inode) changed.
- **mtime**:
  Modification time, the last time the file’s content was modified.

```go
fileInfo, err := os.Stat(snapshotName)
mtime := fileInfo.ModTime().String()

stat := fileInfo.Sys().(*syscall.Stat_t)
ctime := time.Unix(int64(stat.Ctim.Sec), int64(stat.Ctim.Nsec)).String()
```

##### Full Rebuilding

1. Before transferring data, check if the snapshot record is created in the database.
   1. If not, create a record with the snapshot `ctime` and `mtime`, and send a flag indicating the snapshot is modified to the data transfer loop to jump to step 2-1.
2. Check if the `ctime` and `mtime` of the snapshot image file in its replica directory (where multiple replicas of a volume may exist on the same disk) differ from the record in the database.
   1. If yes, calculate and save the checksum into the database on the client side, and then send the data chunk to the server.
   2. If no, send data chunks to the server for each data interval.
3. Get the snapshot `ctime` and `mtime` after closing the snapshot file and update the snapshot `ctime` and `mtime` in the database on the client side. This record will be used to check if the snapshot image file has been modified and if the records in the database are valid when the next rebuild starts.

##### Delta Rebuilding

1. Before transferring data, check if the snapshot record is created in the database.
   1. If not, create a record with the snapshot `ctime` and `mtime`, and send a flag indicating the snapshot is modified to the data transfer loop to jump to step 2-1.
2. Check if the `ctime` and `mtime` of the snapshot image file in its replica directory (where multiple replicas of a volume may exist on the same disk) differ from the record in the database.
   1. If yes, revert to the original implementation: calculate the data chunk checksums on both sides and check if the two checksums are the same.
      1. Save the checksum into the database on the client side.
   2. If no, retrieve the checksum from the client database, read the data, calculate the data chunk checksum on the server side, and then check if the two checksums match.
      1. If yes, this data chunk will not be transferred; proceed to the next data chunk.
      2. If no, read the data, calculate the data chunk checksum on the client side, and check if the two checksums match.
         1. If yes, this data chunk will not be transferred; proceed to the next data chunk.
         2. If no, send the data chunk to the server.
         3. Save the checksum into the database on the client side.
3. Get the snapshot `ctime` and `mtime` after closing the snapshot file and update the snapshot `ctime` and `mtime` in the database on the client side. This record will be used to check if the snapshot image file has been modified and if the records in the database are valid when the next rebuild starts.

##### Database Concurrency Control

Longhorn uses 4 goroutines (as defined by the constant `defaultSyncWorkerCount = 4` in the codebase) to calculate the checksum and consume the data interval concurrently. To avoid race conditions when updating the database, a lock is required to ensure that database write operations are serialized.

Pseudocode modification for `sparse-tools/sparse/client.go` (client side):

```go
func (client *syncClient) syncDataInterval(dataInterval Interval) error {
  // Process data in chunks
  for offset := dataInterval.Begin; offset < dataInterval.End; {
    ...
    if client.fileAlreadyExistsOnServer {
      checksumFromDB, err := client.getChecksumFromDB(batchInterval, isSnapshotModified); 
      if err != nil {
        log.Warnf("Failed to get the checksum from database for data interval %+v: %v", batchInterval, err)
      }
      dataBuffer, err = client.CompareLocalAndRemoteInterval(batchInterval, checksumFromDB)
    }
    ...
    if dataBuffer != nil {
      // NEW: Checksum and Store, (e.g., sha256.Sum256(dataBuffer))
      checksum := calculateChecksum(dataBuffer)
      go func() {
        // Use RWMutex: acquire write lock for writing to shared resources (multiple reads, one write) 
        client.Lock()
        defer client.Unlock()
        err := sqliteStore.RecordChunk(client.sourceName, offset, size, checksum)
        if err != nil {
            // Decide whether to log error or fail the rebuild
            log.Warnf("Failed to record checksum for offset %v: %v", offset, err)
        }
      }()
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
```

### Test plan

- Retrying the replica rebuild should be faster than the initial attempt:
  1. Create a volume with 3 replicas and write some data to the volume.
  2. Attach the volume to a node.
  3. Delete a replica of the volume and wait for the replica rebuilding to start.
  4. Interrupt (or simulate a crash of) the replica rebuilding process when it reaches 60% progress.
  5. The subsequent rebuild, which reuses the failed replica, should quickly reach 60% completion.

- Rebuilding after a snapshot is deleted:
  1. Create a volume with 3 replicas and write some data.
  2. Take a snapshot A.
  3. Trigger a replica rebuild (e.g., by deleting a replica).
  4. Wait for the rebuilding to be completed.
  5. Delete the snapshot A.
  6. The database for snapshot A should be deleted.
  7. Trigger another replica rebuild.
  8. The subsequent rebuild should create a new database. The rebuilding must complete successfully.

- Rebuilding should succeed even if the checksum database is corrupted:
  1. Create a volume with 3 replicas and write some data.
  2. Trigger a replica rebuild (e.g., by deleting a replica).
  3. Wait for the rebuild to make some progress and the database file to be created.
  4. Corrupt the SQLite database file (e.g., `echo "garbage" > <path-to-db>`).
  5. Interrupt the rebuild process.
  6. The subsequent rebuild should detect the database file corruption (or fail to open the DB), log a warning, fall back to a delta rebuilding (recreating the DB), and proceed. The rebuilding must complete successfully.

- Performance overhead comparison:
  1. Create a volume with 2 replicas (A, B) and write a significant amount of data (e.g., 10 GiB).
  2. Disable the setting `reuse-transferred-data-when-rebuilding`.
  3. Delete one replica A and wait for the rebuilding to complete. Record the rebuilding time as `T1`.
  4. Delete one replica A and wait for the rebuilding to reach 90%.
  5. Crash the replica A process in the longhorn-instance-manager pod and wait for the subsequent rebuilding to complete. Record the rebuilding time as `T2`.
  6. Enable the setting `reuse-transferred-data-when-rebuilding`.
  7. Delete one replica A and wait for the rebuilding to complete. Record the rebuilding time as `T3`.
  8. Delete one replica A and wait for the rebuilding to complete. Record the rebuilding time as `T4`.
  9. Crash the replica A process in the longhorn-instance-manager pod and wait for the subsequent rebuilding to complete. Record the rebuilding time as `T5`.
  10. Compare `T1` and `T3`. `T3` is expected to be slightly larger than `T1` due to the overhead of checksum calculation and database operations.
  11. Compare `T1`, `T3`, and `T4`. `T4` is expected to be smaller than `T1` and `T3` because the checksums are already calculated and stored in the database.
  12. Compare `T2` and `T5`. `T5` is expected to be smaller than `T2` because the checksums are already calculated and stored in the database.

### Upgrade strategy

N/A
