# V2 Engine Level Backup Restore

## Summary

This proposal introduces **engine-level** backup restore for Longhorn V2 volumes.
The current restore workflow executes backup restore at the **replica level**, causing redundant data transfers when multiple replicas exist.

This redesign consolidates restore operations into the engine process, ensuring each backup is downloaded only once, while replicas receive synchronized, local copies of the restored data.This improves simplifies control flow, reduces network traffic.

### Related Issues

https://github.com/longhorn/longhorn/issues/9277

## Motivation

The current SPDK-based restore invocation chain is:

```
Users → longhorn-manager → longhorn-instance-manager → longhorn-spdk-engine → replica processes (Replica.BackupRestore)
```

In today’s implementation, each replica performs the backup restore independently

This means:
- An engine with **N replicas** produces **N network bandwidth consumption**
- Restore duration scales with the slowest replica
- Extra coordination logic is required in longhorn-manager and instance-manager

Moving restore logic into the engine consolidates data fetches and reduces redundant work.

### Goals

- Replace **replica-level** restore with **engine-level** restore
- Preserve exact functional results of the existing restore semantics

### Non-goals

- Changing backupstore logic or delta-block algorithms
- Changing backup metadata format
- Introducing new block formats or snapshot mechanisms
- Not modify Backup()

## Proposal

This proposal introduces a redesigned engine-level backup restore workflow for Longhorn V2 volumes.
Instead of delegating the restore operation to each replica, the Longhorn Engine will:

1. Fetch backup data once from the backupstore.
2. Apply restored blocks to the engine’s RAID bdev.
3. Synchronize block-level changes to all replicas through SPDK replication mechanisms.
4. Maintain full restore and incremental restore semantics across volume versions.

This eliminates redundant network transfer, removes replica-side restore logic, and centralizes restore control inside the engine.

## Design

New implementations for **Engine**:

- BackupRestore
- backupRestorePrepare
- backupRestore / backupRestoreIncrementally
- completeBackupRestore
- waitForRestoreComplete
- finishRestore

### Implementation Overview

BackupRestore Process:

```
Engine.BackupRestore()
│
├── Validate backup & volume size
│
├── backupRestorePrepare()
│   │
│   ├── Determine snapshot name
│   ├── Validate restore state
│   └── Decide full / incremental restore
│
├── Mark e.IsRestoring = true
│
├── Start restore
│   │
│   ├── If full restore:
│   │   └── backupRestore()
│   │
│   └── Else:
│       └── backupRestoreIncrementally()
│
└── Launch async goroutine:
    completeBackupRestore()
    │
    ├── waitForRestoreComplete()
    │   ├── If progress == 100 → success
    │   ├── If canceled → stop
    │   └── If error → return err
    │
    ├── Snapshot cleanup
    │   ├── Full restore → delete old snapshot (if exists)
    │   └── Incremental restore → always delete temp snapshot
    │
    ├── SnapshotCreate(restoreSnapshot)
    │
    └── finishRestore()
        ├── disconnectTarget()
        ├── StopExposeBdev()
        ├── Release ports
        └── Clear IsRestoring, reset engine fields
```

Engine Restore Open/Close Device:

```
OpenVolumeDev()
│
├── handleNvmeTcpFrontend()
│
├── os.OpenFile(endpoint, O_RDWR | O_DIRECT)
│       │
│       └── Return file handle + device path
│
└── RETURN (fh, endpoint)
```

```
CloseVolumeDev(volDev)
│
├── volDev.Sync()
│
├── volDev.Close()
│
├── disconnectTarget(targetAddress)
│
├── StopExposeBdev(Nqn)
│
├── releasePorts(superiorPortAllocator)
│
└── RETURN closeErr
```

### Replica-Level Errors During Restore

With **engine-level restore**, backup data is written directly to the RAID1 bdev.
If one replica fails to accept the data (e.g., I/O error, NVMe timeout):

The failure does not propagate to the other replicas

- The restore continues normally
- SPDK RAID1 automatically marks the failing replica as degraded
- Longhorn’s regular rebuild mechanism will later repair or replace the failed replica

Any replica-side write failure during restore results in the RAID1 bdev entering a degraded state, but does not interrupt the restore flow. Longhorn will later rebuild the failed replica through standard replica rebuilding logic.

### Longhorn Manager and Interface Behavior Remains Unchanged

The migration to **engine-level** backup restore is a backend-only architectural change.
It does not modify any frontend behaviors

All frontend semantics remain identical before and after this proposal.Only the internal restore execution path is redesigned.

### Backend I/O Path Shift from Replica-Level to Engine-Level

**Replica-level backup restore**

During restore, the RAID1 bdev was deleted, each replica lvol was individually exposed, and every replica independently pulled backup data from the backupstore. This resulted in duplicated network transfers and redundant restore operations—one per replica.

```
backupstore → each replica initiator → each replica lvol
```

**Engine-level backup restore**

Instead of exposing each replica, the engine exposes the RAID1 bdev directly through a temporary NVMe-TCP frontend. The restore pipeline writes to the RAID device once, and SPDK RAID1 automatically propagates all restored blocks to every underlying replica lvol.


```
backupstore → engine initiator → RAID1 bdev → SPDK → all replica lvols
```

This shifts the restore execution path from **N independent replica restores** to a **single engine-level restore**, eliminating per-replica data transfer while guaranteeing that all replicas remain fully synchronized through the RAID layer. In this design, the RAID1 bdev is no longer deleted before restore.


### Test plan

- Run e2e backup test
- Run e2e dr-volume test 
- Run regression backup test

## Note
