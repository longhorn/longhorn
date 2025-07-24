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
Expand()
│
├── Lock engine
├── Log "Expanding engine"
├── getReplicaClients()
│   └── defer closeReplicaClients()
│
├── requireExpansion(size, replicaClients)
│   ├── Check: isExpanding → error
│   ├── Check: IsRestoring → error
│   ├── Check: SpecSize > size → error
│   ├── Check: SpecSize == size → return false
│   ├── RoundUp size to MiB → mismatch → error
│   ├── Check ReplicaStatusMap is not empty
│   ├── Check: all replicas are RW and same size
│   ├── Check: currentReplicaSize >= size → error or skip
│   └── Mark e.isExpanding = true
│
├── Check: requireExpansion == false
│   └── Log and return nil
│
├── prepareRaidForExpansion(spdkClient)
│   ├── BdevRaidGet()
│   ├── If RAID exists:
│   │   ├── If Frontend == SPDKTCP && Endpoint != "":
│   │   │   └── initiator.Suspend() → defer Resume()
│   │   ├── Else if Frontend == ublk → return error
│   │   ├── disconnectTarget(currentTargetAddress)
│   │   └── StopExposeBdev()
│   │       └── BdevRaidDelete()
│   │           ├── NoSuchDevice → log and continue
│   │           └── If !deleted → return error
│   └── Return suspendFrontend, bdevUUID
│
├── expandReplicas(replicaClients, spdkClient, size)
│   ├── For each replica in goroutine:
│   │   ├── ReplicaGet()
│   │   ├── If already at size → return
│   │   ├── disconnectNVMfBdev()
│   │   ├── ReplicaExpand()
│   │   └── connectNVMfBdev()
│   │       └── On any error → mark in failedReplica
│   ├── wg.Wait()
│   ├── If all replicas failed → return error
│   ├── If some failed → mark as ModeERR
│   └── Log partial failure, return nil
│
├── reconnectFrontend(spdkClient, bdevUUID, allocator)
│   ├── Build replicaBdevList (only healthy ModeRW replicas)
│   ├── If empty → return error
│   ├── BdevRaidCreate()
│   ├── retry.BdevRaidGet() with backoff
│   ├── If Frontend == SPDKTCP:
│   │   ├── get pod IP
│   │   ├── checkInitiatorAndTargetCreationRequirements()
│   │   └── handleNvmeTcpFrontend()
│   └── Else if ublk → return unsupported error
│
├── defer:
│   ├── If retErr:
│   │   ├── Log error
│   │   ├── Set lastExpansionError, lastExpansionFailedAt
│   │   ├── Set e.State = Error, e.ErrorMsg
│   │   └── UpdateLogger(replicaStatusMap)
│   └── finishExpansion(expanded, size, err)
│       ├── If expanded:
│       │   ├── Log success
│       │   └── Update SpecSize
│       └── Else:
│           └── Log failure
│
└── return nil or wrapped error
```

**Replica Expand**
```
Expand()
│
├── Lock replica
│
├── fetchClusterSize(spdkClient)
│   └── If error → return wrapped error
│
├── RoundUp(size, clusterSize)
│   └── If roundedSize ≠ size → return error
│
├── Check SpecSize:
│   ├── If SpecSize > size → return error
│   ├── If SpecSize == size → log and return
│
├── If IsExposed:
│   ├── StopExposeBdev(NQN)
│   ├── If error ≠ NoSuchDevice → return error
│   ├── Set IsExposed = false
│   └── reExposeBdev = true
│
├── BdevLvolResize(alias, size)
│   └── If !resized || err → verify actual lvol size
│       ├── BdevLvolGetByName(alias)
│       │   └── If error → return wrapped error
│       ├── If lvol.SpecSize ≠ size:
│       │   ├── If err → return wrapped error
│       │   └── If !resized → return error
│       └── Else → log success (despite earlier error)
│
├── If reExposeBdev:
│   ├── Generate random NGUID
│   ├── StartExposeBdev(NQN, UUID, NGUID, IP, Port)
│   └── If error → return
│       └── Set IsExposed = true
│
├── Cleanup:
│   ├── Set Head = nil
│   └── If last ActiveChain == r.Name → remove from chain
│
├── updateHeadCache(spdkClient)
│   └── If error → return
│
├── Log "Expanding replica complete"
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

