# V2 Engine - Raid Grow and Delta Bitmap

## Summary

This proposal adds **RAID1 bdev grow** (adding a new base bdev to an existing RAID1) and a **delta bitmap** implementation to the SPDK RAID module. These features enable the Longhorn V2 engine to add a rebuilding replica to an existing RAID1 array and track which regions changed during the rebuild, supporting future incremental rebuild optimization.

### Related Issues

- TBD

## Motivation

### Goals

- Allow a RAID1 bdev to be created with a single base bdev (degraded mode) and grown by adding a second base bdev later
- Track dirty regions during RAID1 grow/reconstruct via a delta bitmap
- Support the `bdev_raid_grow_base_bdev` RPC for programmatic grow operations
- Enable WRITE_ZEROES forwarding to base bdevs for efficient space reclamation

### Non-goals

- RAID5/6 grow support
- Online resize of the RAID1 bdev itself (grow adds base bdevs, not capacity)
- Automatic delta bitmap consumption for incremental rebuild (scaffolded but not wired in — see the rebuild lvol reuse plan)

## Proposal

### Design Overview

#### RAID1 Single-Base Creation

Previously, RAID1 bdevs required at least two base bdevs at creation time. This enhancement allows creation with a single base bdev, enabling the Longhorn engine to create a RAID1 for a volume with only one healthy replica. The second base bdev is added later via `bdev_raid_grow_base_bdev` when a rebuild replica becomes available.

#### RAID1 Grow

The `bdev_raid_grow_base_bdev` RPC adds a new base bdev to an existing RAID1. The new base bdev starts in WO (Write-Only) mode — it receives writes but is not yet readable. The engine then drives a shallow copy from a healthy base bdev to synchronize the new base bdev.

#### Delta Bitmap

The delta bitmap tracks which regions of the RAID1 were modified during the grow/reconstruct window. It is captured at the SPDK raid bdev level using `bdev_raid_get_base_bdev_delta_bitmap`, which returns a base64-encoded bit array with a region size. Each set bit indicates a region that was written while the new base bdev was in WO mode.

**Current status:** The delta bitmap is captured and persisted across IM restarts via the engine record, but is **not yet consumed** by the rebuild path. The infrastructure is in place for a future enhancement that will use the delta bitmap to drive incremental (range-only) shallow copy instead of full rebuild.

#### WRITE_ZEROES Forwarding

The RAID module now advertises and forwards WRITE_ZEROES to base bdevs, enabling efficient space reclamation when the filesystem issues TRIM/UNMAP commands. A generic `bdev_write_zeroes` JSON-RPC is also added.

### User Stories

#### Story 1

As a v2 volume user, I want my volume to be available even when only one replica is healthy, so that a temporary replica failure doesn't cause my workload to stall.

#### Story 2

As a storage developer, I want the delta bitmap infrastructure in place so that future incremental rebuild optimization can be built on top of it, reducing rebuild time and space requirements for large volumes.

### Implementation Details

#### SPDK Changes

- `module/raid`: single-base-bdev creation support
- `module/raid`: `bdev_raid_grow_base_bdev` RPC
- `module/raid`: delta bitmap implementation (`bdev_raid_get_base_bdev_delta_bitmap`)
- `module/raid`: WRITE_ZEROES advertisement and forwarding
- `bdev`: `bdev_write_zeroes` JSON-RPC

#### Engine Changes

- `EngineReplicaAdd` uses `bdev_raid_grow_base_bdev` to add the rebuild destination
- Delta bitmap captured on RW→ERR transition via `captureBitmapsForFaultedReplicas`
- Delta bitmap persisted in `EngineRecord` across IM restarts

#### Helper Changes

- `go-spdk-helper`: `BdevRaidGrowBaseBdev` RPC wrapper
- `go-spdk-helper`: `BdevRaidGetBaseBdevDeltaBitmap` RPC wrapper
- `go-spdk-helper`: `BdevRaidClearBaseBdevFaultyState` RPC wrapper
- `go-spdk-helper`: delta bitmap flag on `BdevRaidCreate`

### Test Plan

- Unit tests: single-base creation, grow operation, delta bitmap capture
- Integration tests: degraded RAID1 → grow → full RAID1, WRITE_ZEROES forwarding
- Negative tests: grow with mismatched sizes, grow on non-RAID1

### Future Work

The delta bitmap infrastructure is scaffolded but not yet consumed during rebuild. A future enhancement will:
1. Check `Engine.ReplicaDirtyBitmaps[replicaName]` at rebuild start
2. Convert the bitmap to a cluster list
3. Feed the cluster list into `range_shallow_copy` to copy only dirty regions
4. Skip the head deletion + re-clone in `RebuildingDstStart`

This will eliminate the need for full-space duplication during rebuilds, particularly important for large volumes (e.g., 70TB+) that cannot fit a second copy on a single node.