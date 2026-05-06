# V2 Engine Level Backup Restore

## Summary

This enhancement introduces **engine-level** backup restore for Longhorn V2 (SPDK-based) volumes.
The legacy restore workflow executes backup restore at the **replica level**, where each replica independently downloads the same backup data from the backupstore, causing N-fold redundant network transfers for N replicas.

This redesign consolidates restore operations into the engine process, ensuring each backup is downloaded only once and written directly to the RAID1 bdev. SPDK's RAID layer then automatically synchronizes the restored blocks to all underlying replica lvols. This eliminates redundant network traffic, simplifies control flow, and reduces restore duration.

### Related Issues

https://github.com/longhorn/longhorn/issues/9277

## Motivation

The legacy SPDK-based restore workflow operates at the replica level:

```
backupstore → replica-1 (independent download)
backupstore → replica-2 (independent download)
backupstore → replica-N (independent download)
```

Each replica independently connects to the backupstore, downloads the full backup data, and writes it to its own lvol. For an engine with **N replicas**, this produces:

- **N× network bandwidth consumption** — the same backup data is transferred N times
- **N concurrent backupstore connections** — each replica pulls data independently
- **Restore duration bounded by the slowest replica** — all replicas must complete before restore finishes
- **Complex coordination logic** — longhorn-manager and instance-manager must track per-replica restore state

Moving restore logic into the engine consolidates the download into a single operation. The engine fetches each backup block once, writes it to the RAID1 bdev, and SPDK automatically propagates it to all replica lvols. This reduces network traffic, simplifies state tracking, and accelerates restore completion.

### Goals

- **Consolidate backup restore into the engine**: Move restore execution from N independent replica operations to a single engine operation
- **Reduce network bandwidth consumption**: Download backup data once instead of N times
- **Preserve restore semantics**: Maintain full restore and incremental restore behavior; ensure restored data integrity
- **Simplify control flow**: Eliminate per-replica restore state tracking

### Non-goals

- Changing backupstore protocols or delta-block transfer algorithms
- Modifying backup metadata format or snapshot encoding
- Altering backup creation logic (`Engine.Backup` remains unchanged)
- Changing Longhorn Manager or Instance Manager APIs (frontend behavior unchanged)

## Proposal

This enhancement redesigns the backup restore workflow to operate at the **engine level** instead of the **replica level**.

### High-Level Flow

1. **Frontend Setup**: A temporary `EngineFrontend` is created to manage the restore I/O path
2. **Target Preparation**: A temporary NVMe-TCP target is created on the engine’s RAID1 bdev
3. **Initiator Connection**: The frontend creates an NVMe-TCP initiator that connects to the target, exposing a block device (e.g., `/dev/nvme1n1`)
4. **Engine Restore**: The engine’s `BackupRestore` method fetches backup data from the backupstore and writes it directly to the block device
5. **RAID Propagation**: SPDK RAID1 automatically replicates written blocks to all underlying replica lvols
6. **Snapshot Creation**: Upon completion, the engine creates a snapshot (e.g., `restore-<backupSnapshotName>`) to mark the restore point
7. **Cleanup**: The temporary NVMe-TCP target and initiator are torn down; the frontend is marked as stopped

This approach ensures backup data is downloaded **once** and written **once** to the RAID1 bdev, while SPDK handles synchronization to all replicas. Replica-level restore logic is completely removed.

## Design

### Component Architecture

#### New Types

**`EngineRestore`** (`pkg/spdk/restore_engine.go`)
- Implements `backupstore.DeltaRestoreOperations` interface
- Manages restore progress, state, and error tracking
- Handles block device I/O via `OpenVolumeDev` / `CloseVolumeDev`
- Tracks incremental restore state (`LastRestored`, `CurrentRestoringBackup`)

### Implementation Overview

**Server.EngineBackupRestore (RPC Handler)**
```
Server.EngineBackupRestore()
│
├── Lookup engine in engineMap
├── Validate no existing non-empty frontend for this engine
├── Create temporary EngineFrontend (ephemeral, not registered)
│   └── Frontend = FrontendSPDKTCPBlockdev
│   └── UpdateCh = buffered channel (discarded after restore)
│
└── EngineFrontend.BackupRestore()
    │
    ├── Validate: frontend has no active endpoint
    ├── Mark ef.IsRestoring = true
    │
    ├── Engine.ensureNvmeTcpTargetForRestore()
    │   └── Create temporary NVMe-TCP target on RAID1 bdev (if absent)
    │   └── Allocate port, expose bdev
    │
    ├── EngineFrontend.createNvmeTcpFrontend()
    │   └── Create NVMe-TCP initiator
    │   └── Connect to temporary target
    │   └── Discover block device (e.g., /dev/nvme1n1)
    │   └── Set ef.Endpoint
    │
    ├── Engine.BackupRestore()
    │   │
    │   ├── precheckBackupRestore() [with lock]
    │   │   ├── Ensure replicas exist
    │   │   ├── Ensure all replicas are RW
    │   │   └── Reject if IsRestoring == true
    │   │
    │   ├── InspectBackup() [without lock]
    │   │   └── Fetch backup metadata from backupstore
    │   │
    │   ├── precheckBackupRestore() again [with lock]
    │   │   └── Revalidate after releasing lock (state may have changed)
    │   │
    │   ├── backupRestorePrepare() [with lock held]
    │   │   ├── Setup credentials (butil.SetupCredential)
    │   │   ├── Decode backup URL
    │   │   ├── Initialize or reuse EngineRestore struct
    │   │   │   └── If e.restore == nil or failed: create new EngineRestore
    │   │   │   └── Else: check if incremental restore is possible
    │   │   ├── Mark e.IsRestoring = true
    │   │   └── Return isFullRestore flag
    │   │
    │   ├── Set e.restore.endpoint = ef.Endpoint [with lock]
    │   │
    │   ├── Start restore [with lock held]
    │   │   ├── Full restore:
    │   │   │   └── backupRestore()
    │   │   │       └── backupstore.RestoreDeltaBlockBackup()
    │   │   │           └── Calls EngineRestore.OpenVolumeDev()
    │   │   │           └── Writes blocks to RAID1 bdev via block device
    │   │   │           └── Updates EngineRestore.Progress
    │   │   │
    │   │   └── Incremental restore:
    │   │       └── backupRestoreIncrementally()
    │   │           └── backupstore.RestoreDeltaBlockBackupIncrementally()
    │   │
    │   ├── Launch background goroutine (completeBackupRestore)
    │   │   └── Closes doneCh when finished
    │   │
    │   └── Return (response, doneCh, nil)
    │
    └── Launch teardown goroutine [in EngineFrontend]
        └── <-doneCh (wait for restore completion)
        └── EngineFrontend.teardownRestoreInitiator()
            ├── Stop NVMe-TCP initiator
            ├── Clear ef.Endpoint
            ├── Clear frontend NQN/NGUID/IP/Port
            ├── Mark ef.State = InstanceStateStopped
            └── Mark ef.IsRestoring = false
```

**Background Goroutine: completeBackupRestore**
```
completeBackupRestore()
│
├── waitForRestoreComplete() [without engine lock]
│   └── Poll EngineRestore.Progress every restorePeriodicRefreshInterval
│       ├── Progress == 100 → success
│       ├── State == canceled → return error
│       └── Error != "" → return error
│
├── Acquire engine lock
├── Validate e.IsRestoring == true
├── Read e.restore.State (check if canceled)
├── Read oldSnapshotName from e.restore.SnapshotName
├── Clear e.Endpoint
│
├── cleanupTemporaryNvmeTcpTargetForRestoreLocked()
│   ├── StopExposeBdev(NvmeTcpTarget.Nqn)
│   ├── Clear NvmeTcpTarget fields
│   └── Release allocated port
│
├── Release engine lock
│
├── If waitErr != nil:
│   ├── Mark e.IsRestoring = false
│   ├── Update EngineRestore.State = error
│   └── Return error
│
├── Delete old snapshot (if exists) [SnapshotDelete acquires lock internally]
│   └── SnapshotDelete(oldSnapshotName)
│
├── Create new snapshot [SnapshotCreate acquires lock internally]
│   ├── Generate name: "restore-<backupSnapshotName>" or "restore-<uuid>"
│   ├── Avoid conflicts if name already exists
│   └── SnapshotCreate(newSnapshotName)
│
└── Finalize [with engine lock]
    ├── Mark e.IsRestoring = false
    ├── Update e.restore.SnapshotName = newSnapshotName
    ├── Update e.restore.State = ProgressStateComplete
    ├── Update e.restore.LastRestored = CurrentRestoringBackup
    └── Clear e.restore.CurrentRestoringBackup
```

**EngineRestore I/O Operations**

The `EngineRestore` struct implements the `backupstore.DeltaRestoreOperations` interface, which the backupstore library uses to write restored blocks:

```go
type EngineRestore struct {
    sync.RWMutex
    
    spdkClient *spdkclient.Client
    engine     *Engine
    endpoint   string  // NVMe block device path (e.g., /dev/nvme1n1)
    
    Progress  int
    Error     string
    BackupURL string
    State     btypes.ProgressState
    
    SnapshotName           string
    LastRestored           string
    CurrentRestoringBackup string
    
    stopChan chan struct{}
    stopOnce sync.Once
}
```

**OpenVolumeDev Implementation:**
```
EngineRestore.OpenVolumeDev(_ string)
│
├── Read r.endpoint (block device path set by Engine.BackupRestore)
│
├── os.OpenFile(endpoint, O_RDWR | O_DIRECT, 0666)
│   └── O_DIRECT: bypass page cache for direct I/O to device
│
└── RETURN (file handle, endpoint, error)
```

**CloseVolumeDev Implementation:**
```
EngineRestore.CloseVolumeDev(volDev *os.File)
│
├── volDev.Sync()
│   └── Flush any buffered writes to device
│
├── volDev.Close()
│   └── Close file descriptor
│
└── RETURN error
```

The backupstore library calls:
1. `OpenVolumeDev` once at restore start
2. Writes blocks directly to the file descriptor using `pwrite` with `O_DIRECT`
3. Updates `EngineRestore.Progress` periodically via `UpdateRestoreStatus`
4. `CloseVolumeDev` once at restore completion

This design eliminates intermediate buffering and writes restored blocks directly to the RAID1 bdev via the NVMe-TCP block device.

### Replica-Level Errors During Restore

With **engine-level restore**, backup data is written directly to the RAID1 bdev via a block device exposed by the NVMe-TCP target. SPDK RAID1 automatically replicates each write to all underlying replica lvols.

**Failure Handling:**

If one replica fails to accept a write during restore (e.g., I/O error, NVMe connection timeout, replica crash):

1. **SPDK RAID1 marks the replica as degraded** — the failed replica is removed from the RAID base_bdevs array
2. **The restore write succeeds** — the write operation returns success as long as at least one replica accepted the data
3. **Restore continues normally** — the engine does not detect the per-replica failure; `EngineRestore.Progress` continues to 100%
4. **Engine state reflects degradation** — `Engine.checkAndUpdateInfoFromReplicasNoLock()` eventually detects the replica mode change
5. **Longhorn orchestrates rebuild** — longhorn-manager triggers standard replica rebuilding logic to restore redundancy

This design isolates replica failures from the restore operation. A single replica failure does not block or restart the entire restore; it only triggers asynchronous repair through Longhorn’s existing rebuild mechanism.

### I/O Path Comparison

#### Legacy: Replica-Level Restore

```
┌──────────────┐
│ backupstore  │
└──────┬───────┘
       │
       ├───────────────────────────────────┐
       │                                   │
       v                                   v
┌──────────────┐                    ┌──────────────┐
│  Replica 1   │  (independent      │  Replica N   │
│  Initiator   │   download & I/O)  │  Initiator   │
└──────┬───────┘                    └──────┬───────┘
       │                                   │
       v                                   v
┌──────────────┐                    ┌──────────────┐
│ Replica 1    │                    │ Replica N    │
│ lvol         │                    │ lvol         │
└──────────────┘                    └──────────────┘

RAID1 bdev: DELETED before restore
Coordination: longhorn-manager tracks N replica restore states
Bandwidth: N × backup size
Duration: max(replica_1_time, ..., replica_N_time)
```

#### New: Engine-Level Restore

```
┌──────────────┐
│ backupstore  │
└──────┬───────┘
       │ (single download)
       v
┌──────────────────────────────────────────┐
│ Engine (backupstore.RestoreDeltaBlock...) │
│   EngineRestore.OpenVolumeDev()          │
└──────┬───────────────────────────────────┘
       │
       v
┌──────────────────────────────────────────┐
│ /dev/nvmeXnY (NVMe-TCP initiator)        │
│   connected to temporary target          │
└──────┬───────────────────────────────────┘
       │ (O_DIRECT writes)
       v
┌──────────────────────────────────────────┐
│ RAID1 bdev (NOT deleted; remains active) │
└──────┬────────────────────────────────┬──┘
       │                                │
       v                                v
┌──────────────┐              ┌──────────────┐
│ Replica 1    │ (SPDK RAID1  │ Replica N    │
│ lvol         │  auto-sync)  │ lvol         │
└──────────────┘              └──────────────┘

RAID1 bdev: REMAINS ACTIVE throughout restore
Coordination: Engine tracks single restore state
Bandwidth: 1 × backup size
Duration: single_download_time + RAID1_sync_overhead (minimal)
```

**Key Differences:**
1. **RAID bdev lifecycle**: Legacy flow deleted the RAID bdev before restore; new flow keeps it active and writes through it
2. **Network efficiency**: Single download vs. N downloads
3. **Synchronization**: Automatic via SPDK RAID1 vs. manual per-replica coordination
4. **Temporary frontend**: New flow uses an ephemeral `EngineFrontend` with NVMe-TCP initiator that is created for restore and discarded after completion

#### Temporary NVMe-TCP Target for Restore

Engines with `Frontend = FrontendEmpty` (e.g., detached volumes, DR volumes before activation) have no active NVMe-TCP target. To perform engine-level restore, a temporary target must be created:

**Target Creation** (`Engine.ensureNvmeTcpTargetForRestore`):
- **When**: Called by `EngineFrontend.BackupRestore` before creating the initiator
- **What**: Calls `createNVMeTCPTarget` to expose the RAID1 bdev via NVMe-TCP
- **Port allocation**: Allocates a port from `superiorPortAllocator` (shared bitmap across all engines in the instance-manager)
- **Idempotency**: If `e.NvmeTcpTarget.IP` and `e.NvmeTcpTarget.Port` are already set (e.g., from a prior partial restore attempt), the function returns early without creating a duplicate target
- **Storage**: Target address (IP, Port, NQN, NGUID) is stored in `Engine.NvmeTcpTarget` (distinct from `EngineFrontend.NvmeTcpFrontend`)

**Target Cleanup** (`Engine.cleanupTemporaryNvmeTcpTargetForRestore`):
- **When**: Called by `completeBackupRestore` after `waitForRestoreComplete` returns (success or failure)
- **What**: 
  1. Calls `spdkClient.StopExposeBdev(e.NvmeTcpTarget.Nqn)` to stop the SPDK NVMe-TCP subsystem
  2. Clears `e.NvmeTcpTarget` fields (IP, Port, NQN, NGUID)
  3. Calls `e.releasePorts(superiorPortAllocator)` to return the port to the pool
- **Preconditions**: Only runs if `e.Frontend == FrontendEmpty` (to avoid tearing down a legitimate user-facing frontend)

**Target Lifetime:**
```
ensureNvmeTcpTargetForRestore() → createNVMeTCPTarget()
                                       ↓
                    [target active, initiator connects, restore runs]
                                       ↓
completeBackupRestore() → cleanupTemporaryNvmeTcpTargetForRestore() → StopExposeBdev()
```

### Test Plan

**1. DR Volume - Normal Workflow**
- Create v2 volume and attach
- Write initial data and create backup
- Create DR volume from backup and wait for full restore completion
- Write additional data to source volume and create incremental backup
- Verify DR volume automatically restores incremental backup
- Activate DR volume and attach
- Validate data integrity: `sha256sum /dev/longhorn/v1` == `sha256sum /dev/longhorn/v1-dr`

**2. DR Volume - Volume Expansion**
- Create v2 volume and attach
- Write initial data and create backup
- Create DR volume from backup and wait for restore completion
- Expand source volume
- Write additional data to expanded volume and create backup
- Verify DR volume automatically expands and restores incremental backup
- Activate DR volume and attach
- Validate data integrity across expanded volume size

**3. Direct Backup Restore**
- Create v2 volume and attach
- Write data and create backup
- Restore backup to new volume (volume-1)
- Attach volume-1
- Validate data integrity: `sha256sum /dev/longhorn/v1` == `sha256sum /dev/longhorn/v1-restore`

