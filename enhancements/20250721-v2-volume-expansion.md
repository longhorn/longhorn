# V2 Volume Expansion (Nvmf frontend)

## Summary

Support for user to expand v2 volumes with nvmf frontend.

### Related Issues

- https://github.com/longhorn/longhorn/issues/8022

## Motivation

- Promote Longhorn Engine v2 from experimental to production-ready by implementing missing features, improving stability, and achieving functional parity with Engine v1.

### Goals

- Allow users to perform online expansion of Engine v2 volumes with the NVMe-oF frontend.
- Ensure the expansion workflow and logic are aligned with Engine v1.

### Non-goals

- Support for online expansion of v2 volumes with the `ublk` frontend.

## Proposal

### User Stories

- V2 volume expansion is needed for  general users

### API changes

Introduce new SPDK rpc call 

(1) EngineExpand
```proto
rpc EngineExpand(EngineExpandRequest) returns (google.protobuf.Empty);

message EngineExpandRequest{
    string name = 1;
    uint64 size = 2;
}
```

(2) ReplicaExpand

```proto
rpc ReplicaExpand(ReplicaExpandRequest) returns (google.protobuf.Empty);

message ReplicaExpandRequest{
    string name = 1;
    uint64 size = 2;
}
```

## Design

### Implementation Overview
- **RAID Deletion Before Expansion**
    - SPDK RAID1 requires equal-sized base bdevs.
    - If not detach the controller, SPDK's synchronize RPCs during lvol resize may hang due to active frontend references.
- **I/O Suspension During Expansion** 
    - During expansion, the engine is locked and I/O is suspended. 
    - Once the expansion completes, I/O is resumed.
- **Partial Replica Expansion Handling**
    - If only some replicas succeed in expansion, the failed replicas are marked as ERR, and the RAID is recreated with the successfully resized replicas. 
    - The expansion still proceeds to ensure minimal disruption, and Longhorn's replica rebuilding mechanism can later recover redundancy.
- **Transparent User Experience via NVMe-oF Grace Period**  
    - NVMe-oF allows a grace period during which the device can temporarily disappear without triggering a disconnect on the host side. （`--ctrl-loss-tmo` controller loss timeout, current 30 sec）
    - In practice, `bdev_lvol_resize` for thin-provisioned volumes is fast. As a result, from the user's perspective, the device remains connected, and the expansion is transparent — they will not notice that the underlying bdev was recreated and reconnected.
- **Frontend Recovery Retry on Failure** 
    - In the case of rebuilding frontend failed, the Longhorn manager will continue to retry the expansion process. During the next reconciliation loop, the engine service will attempt to re-establish the frontend connection again.
- **Replica State Awareness**
    - Expansion is skipped if any replica is `rebuilding` or `expanding`.
- **Snapshot**
    - When a snapshot is taken, it retains the original size, even if the parent lvol is later resized.
    - As a result, performing a `bdev_lvol_clone` from such a snapshot will create a new logical volume with the size of the snapshot, not the expanded size of the original lvol.
    - For example, if the current volume size is 1GiB and a snapshot named `snapshot-1` is taken, the snapshot will reflect a size of 1GiB. If the volume is then expanded to 2GiB and another snapshot named `snapshot-2` is taken, this snapshot will reflect the new size of 2GiB.


**Engine Expand**

```
EngineExpand
││
├── startExpansion(size)
│   ├── Check isExpanding → error if true
│   ├── Check IsRestoring → error if true
│   ├── Check SpecSize > size → error
│   ├── Round size to MiB → mismatch → error
│   ├── Validate all replicas are RW
│   └── Mark isExpanding = true
│
├── getReplicaClients()
│   └── If error → return
│
├── prepareRaidForExpansion(spdkClient)
│   ├── BdevRaidGet()
│   ├── If RAID exists:
│   │   ├── If Frontend == SPDKTCP:
│   │   │   └── initiator.Suspend()
│   │   ├── Else if ublk → error (unsupported)
│   │   └── BdevRaidDelete()
│   │       ├── If NoSuchDevice → log and continue
│   │       └── If !deleted → error
│   └── Return suspendFrontend + RAID UUID
│
├── Defer (on suspendFrontend):
│   └── initiator.Resume()
│       └── If error → wrap into engineErr
│
├── expandReplicas(replicaClients, spdkClient, size)
│   ├── For each replica (in goroutine):
│   │   ├── ReplicaGet()
│   │   ├── If already at size → return
│   │   ├── disconnectNVMfBdev()
│   │   └── ReplicaExpand()
│   │       └── On any error → record in failedReplica map
│   ├── WaitGroup.Wait()
│   ├── For each failed replica:
│   │   ├── Retry ReplicaGet()
│   │   └── If SpecSize == size → remove from failure list
│   ├── Classify result:
│   │   ├── All success → return nil
│   │   ├── All failed → return error
│   │   └── Partial:
│   │       ├── Mark failed as ModeERR
│   │       └── return nil
│   └── return nil or error
│
├── reconnectFrontend(spdkClient, bdevRaidUUID)
│   ├── For each healthy replica:
│   │   ├── connectNVMfBdev()
│   │   ├── If error → mark ModeERR
│   │   └── Else → update ModeRW, BdevName
│   ├── If no healthy bdevs → return error
│   ├── BdevRaidCreate(name, RAID1, bdev list, uuid)
│   ├── BackoffRetry:
│   │   └── BdevRaidGet() until success
│   ├── If Frontend == SPDKTCP:
│   │   └── reconnectNvmeTcpFrontend()
│   └── Else if ublk → return unsupported error
│
├── Defer block
│   ├── If retErr:
│   │   ├── Log error
│   │   ├── Set lastExpansionError
│   │   └── Set lastExpansionFailedAt
│   ├── If engineErr (non-recoverable):
│   │   ├── Set State = Error
│   │   ├── Set ErrorMsg
│   │   └── UpdateLogger with ReplicaStatusMap
│   └── finishExpansion(expanded, size)
│       ├── If expanded:
│       │   ├── Log success
│       │   └── Update SpecSize
│       └── Else:
│           └── Log failure
│
└── Return nil or wrapped error
```

**Replica Expand**
```
│
├── fetchClusterSize(spdkClient)
│   └── If error → return
│
├── RoundUp(size, clusterSize)
│   ├── If roundedSize ≠ size → return error
│
├── If SpecSize > roundedSize → return error
├── Else if SpecSize == roundedSize → log and return
│
├── BdevLvolGetByName(r.Alias)
│   └── If error → return
│
├── If bdevLvol.SpecSize ≠ size
│   ├── If IsExposed
│   │   ├── StopExposeBdev(NQN)
│   │   ├── If error ≠ NoSuchDevice → return error
│   │   ├── Set IsExposed = false
│   │   └── reExposeBdev = true
│   │
│   ├── BdevLvolResize(alias, size)
│   │   ├── If error → return
│   │   └── If !resized → return error
│   │
│   └── If reExposeBdev
│       ├── Generate new NGUID
│       └── StartExposeBdev(NQN, Head.UUID, NGUID, IP, Port)
│           └── If error → return
│           └── Set IsExposed = true
│
├── Cleanup Head and ActiveChain
│   ├── Set Head = nil
│   └── If last ActiveChain == r.Name → remove last element
│
├── updateHeadCache(spdkClient)
│   └── If error → return
│
├── Log success
├── Set SpecSize = size
└── Return nil
```
### V1 Expansion Result
| Scenario                             | expansionSuccess | outOfSyncErrs | Behavior                                                                |
|--------------------------------------|------------------|---------------|-------------------------------------------------------------------------|
| All replicas succeed                 | true             | nil           | Expand frontend                                                         |
| Partial replicas succeed             | true             | present       | Set failed replicas to `ERR`, continue with frontend expansion          |
| All fail but rollback succeeds       | false            | nil           | Do not expand frontend, no replicas marked `ERR`                        |
| All fail and some rollback also fails     | false            | present       | Some replicas marked `ERR`, do not expand frontend                      |

### V2 Expansion Result
| Scenario                             | expansionSuccess | outOfSyncErrs | Behavior                                                                |
|--------------------------------------|------------------|---------------|-------------------------------------------------------------------------|
| All replicas succeed                 | true             | nil           | Expand frontend                                                         |
| Partial replicas succeed             | true             | present       | Set failed replicas to `ERR`, continue with frontend expansion, only contain the expanded replica         |
| All fail                             | false            | nil           | Recover frontend, no replicas marked `ERR`                              |


> **Note:** The engine uses RAID 1, which requires all base lvols to be the same size.  
> To allow partial replica expansion success, the engine will exclude any failed replicas when recreating the RAID bdev.


### Test plan

Prepare

- Create a volume via the UI
    - Use at least 2 replicas
    - Select V2 Data Engine
    - Choose Block Device as the frontend (NVMe-oF)
    - Attach the volume to a node

**Live Expansion**
1. Perform I/O on the volume (fio to the dm directly)
2. Trigger live volume expansion during the  I/O
    - Expand the volume to a larger size via the Longhorn UI or API
    - Ensure expansion happens while I/O is ongoing
3. Verify expected behavior
    - No I/O interruption or filesystem error occurs during or after expansion
    - Volume size is updated correctly inside the guest OS
    - All healthy replicas remain online
    - Use `go-spdk-helper` in the container to verify the bdev information

**Snapshot Behavior**
Suppose the original size is 1GiB, and it is expanded to 2GiB:
1. Take a snapshot before the expansion.
2. Perform the expansion.
3. Take another snapshot after the expansion.
4. Create clones from both snapshots.
5. The first clone should be 1GiB, and the second one should be 2GiB.

**Rebuilding Replica + Expand**
1. Perform some I/O on the device-mapper (dm) volume.
2. Force a rebuild to occur.
3. After the rebuild completes, perform the expansion.
4. Perform additional I/O on the volume.
5. Take a snapshot of the engine, which triggers snapshots of the underlying bdev lvols.
6. Compute and get the checksums of these snapshots — they should be identical.

### Upgrade strategy

No upgrade strategy is needed 

