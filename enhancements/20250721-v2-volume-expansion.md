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

### Non-goals [optional]

- Support for online expansion of v2 volumes with the `ublk` frontend.
- Support for v2 volume clone.

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

### V1 Expansion Result
| Scenario                             | expansionSuccess | outOfSyncErrs | Behavior                                                                |
|--------------------------------------|------------------|---------------|-------------------------------------------------------------------------|
| All replicas succeed                 | true             | nil           | Expand frontend                                                         |
| Partial replicas succeed             | true             | present       | Set failed replicas to `ERR`, continue with frontend expansion          |
| All fail but rollback succeeds       | false            | nil           | Do not expand frontend, no replicas marked `ERR`                        |
| All fail and rollback also fails     | false            | present       | Some replicas marked `ERR`, do not expand frontend                      |

### V2 Expansion Result
| Scenario                             | expansionSuccess | outOfSyncErrs | Behavior                                                                |
|--------------------------------------|------------------|---------------|-------------------------------------------------------------------------|
| All replicas succeed                 | true             | nil           | Expand frontend                                                         |
| Partial replicas succeed             | true             | present       | Set failed replicas to `ERR`, continue with frontend expansion, only contain the expanded replica         |
| All fail                             | false            | nil           | Recover frontend, no replicas marked `ERR`                              |


> **Note:** The engine uses RAID 1, which requires all base lvols to be the same size.  
> To allow partial replica expansion success, the engine will exclude any failed replicas when recreating the RAID bdev.

### Implementation Overview

- Current design :
    - Delete the RAID bdev before expansion because:
        - SPDK RAID1 requires equal-sized base bdevs.
        - If not detach the controller, SPDK's synchronize RPCs during lvol resize may hang due to active frontend references.
    - During expansion, the engine is locked and I/O is suspended. Once the expansion completes, I/O is resumed.
    - NVMe-oF allows a grace period during which the device can temporarily disappear without triggering a disconnect on the host side. （`--ctrl-loss-tmo` controller loss timeout, current 30 sec）
    - In practice, `bdev_lvol_resize` for thin-provisioned volumes is fast.
    - As a result, from the user's perspective, the device remains connected, and the expansion is transparent — they will not notice that the underlying bdev was recreated and reconnected.
    - In the case of rebuilding frontend faild, the Longhorn manager will continue to retry the expansion process. During the next reconciliation loop, the engine service will attempt to re-establish the frontend connection again.

- Snapshot:
    - Currently, V2 clone volumes are not supported.
    - When a snapshot is taken, it retains the original size, even if the parent lvol is later resized.
    - As a result, performing a `bdev_lvol_clone` from such a snapshot will create a new logical volume with the size of the snapshot, not the expanded size of the original lvol.

**Engine Expand**

```
EngineExpand()
│
├── startExpansion(size) → Validate expansion size & Status
|
├── Check Replicas
│   ├── If no healty replica, return err
│   └── If at least one of replica is rebuilding, return err
│
├── Check if RAID bdev exists
│   ├── If error (not NoSuchDevice) → return error
│   └── If exists:
│       ├── Suspend I/O → if error, return 
│       └── BdevRaidDelete() → if error and ≠ NoSuchDevice, return error
│
├── expandReplicas() 
│   ├── For each replica (in parallel):
│   │   ├── If ReplicaGet() fails → record error
│   │   ├── If replica already at target size → skip
│   │   └── Else:
│   │       ├── disconnectNVMfBdev() → if error, record it
│   │       └── ReplicaExpand() → if error, record it
│   └── Classify the expansion results:
│       ├── All success → log success, return true
│       ├── All failed → log warning, return false
│       └── Partial success → mark failed replica as ModeERR, return true
│
├── recreateBdevRaid() // with same UUID
│   ├── For each healthy replica (not ModeERR):
│   │   └── connectNVMfBdev() → if error, mark replica as ModeERR
│   ├── BdevRaidCreate(...) create bdev raid with original UUID → if error, return 
│   └── Backoff + wait for BdevRaidGet // make sure the raid is created
│
├── reconnectNvmeTcpFrontend()
│   └── If error → return
│
├── Resume I/O if needed
├── finishExpansion(expanded, size) → verify if expand success
└── Return nil or captured error
```

**Replica Expand**
```
Replica.Expand(spdkClient, size)
│
├── Check if size is valid
│   ├── If new size < current: return error
│   ├── If new size == current: log and return (already expanded)
│
├── spdkClient.BdevLvolResize()
│   ├── If error: return wrapped error
│   ├── If resized == false: return error ("not resized")
│
├── BackoffRetry (wait for lvol to reflect new size)
│   └── Retry up to multiple times with exponential backoff
│       ├── Call spdkClient.BdevLvolGetByName()
│       └── Check if size is expanded
│           └── If not: return error ("lvol not yet updated")
│
├── Update head cache
└── Return nil 
```


### Test plan

1. Create a volume via the UI
    - Use at least 2 replicas
    - Select V2 Data Engine
    - Choose Block Device as the frontend (NVMe-oF)
    - Attach the volume to a node
2. Perform I/O on the volume 
3. Trigger live volume expansion
    - Expand the volume to a larger size via the Longhorn UI or API
    - Ensure expansion happens while I/O is ongoing
4. Verify expected behavior
    - No I/O interruption or filesystem error occurs during or after expansion
    - Volume size is updated correctly inside the guest OS
    - All healthy replicas remain online
    - Use `go-spdk-helper` in the container to verify the bdev information

### Upgrade strategy

No upgrade strategy is needed 

