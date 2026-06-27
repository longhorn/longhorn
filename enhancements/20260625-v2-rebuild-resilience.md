# V2 Engine - Rebuild Resilience and Teardown Wedge Fixes

## Summary

This proposal documents a series of **rebuild resilience and teardown wedge fixes** for the Longhorn V2 SPDK engine. These fixes address issues where rebuild operations failed mid-flight due to source replica stalls, snapshot creation mismatches, and engine-target teardown wedges that left volumes in unrecoverable states.

### Related Issues

- TBD

## Motivation

### Problem

1. **Rebuild failure on stalled source**: When the source replica's SPDK process stalled during a rebuild, the rebuild destination hung indefinitely, consuming a rebuild slot and preventing other volumes from rebuilding.

2. **ActualSize mismatch on snapshot create**: When the rebuild destination's snapshot had a different ActualSize than the source (due to SPDK allocation differences), the `bdev_lvol_set_parent` call failed with "No such device", aborting the rebuild.

3. **Engine-target teardown wedge**: When deleting an engine that had a local NVMe-oF target, the local controller was not disconnected first, causing the teardown to wedge on a qpair that was still in use.

4. **Stale raid leftover EEXIST loop**: When a raid bdev was left over from a previous engine (e.g., after an IM restart), the engine's `bdev_get_bdevs` call returned EEXIST and looped forever instead of reconciling the stale state.

5. **EngineFrontend teardown orphan churn**: When an EF was torn down and recreated, orphaned NVMe-oF subsystems and bdev controllers accumulated, consuming memory and ports.

6. **EF rollout heal stuck on mount presence**: When an EF was healed after an IM rollout, the heal gated on mount presence rather than device health, causing heals to fail on nodes where the mount point was stale but the device was healthy.

7. **Expansion suspend on dead dm-linear**: When a volume expansion attempted to suspend a dm-linear device that was already dead (kernel D-state), the suspend hung indefinitely, wedging the expansion.

### Goals

- Harden rebuild against slow/stalled source replicas
- Tolerate ActualSize mismatches in rebuild snapshot creation
- Prevent engine-target teardown wedges by disconnecting local controllers first
- Self-heal stale raid leftovers instead of EEXIST-looping
- Prevent EF teardown orphan churn
- Gate EF heal on device health, not mount presence
- Skip expansion suspend on confirmed-dead dm-linear devices

### Non-goals

- Changing the rebuild algorithm itself (that is addressed by the rebuild lvol reuse plan)
- Eliminating all dm-linear D-state wedges (requires kernel-level fixes; node reboot is the only resolution for existing D-state)

## Proposal

### Fix 1: Rebuild hardening against stalled source

The rebuild destination now has bounded wait times for source replica responses. If the source stalls, the rebuild fails gracefully and cleans up, freeing the rebuild slot for other volumes.

### Fix 2: ActualSize mismatch tolerance

When `bdev_lvol_set_parent` fails during rebuild snapshot creation due to an ActualSize mismatch, the rebuild now falls back to range shallow copy instead of hard-failing. This allows the rebuild to proceed by copying only the mismatching clusters.

### Fix 3: Engine-target teardown wedge prevention

When an engine is deleted and it has a local NVMe-oF target, the local controller is disconnected first before proceeding with the teardown. This prevents the teardown from wedging on a qpair that is still in use by the local target.

### Fix 4: Stale raid leftover self-heal

When the engine encounters a stale raid bdev leftover (from a previous IM instance), instead of EEXIST-looping forever, it reconciles the leftover by adopting or removing it based on whether it matches the current engine state.

### Fix 5: EF teardown orphan churn prevention

EF teardown now properly cleans up NVMe-oF subsystems and bdev controllers, preventing orphan accumulation during rollout cycles.

### Fix 6: EF heal gated on device health

The EF heal (triggered after an IM rollout) now checks device health (dm-linear liveness probe) rather than mount presence. This allows heals to succeed on nodes where the mount point is stale but the underlying device is healthy.

### Fix 7: Expansion suspend skip on dead dm-linear

When a volume expansion encounters a dm-linear device that is confirmed dead (via the dm-linear liveness probe), the suspend step is skipped entirely. The expansion proceeds with a fresh dm-linear creation, avoiding the D-state wedge.

## Test Plan

- Unit tests: rebuild timeout handling, ActualSize mismatch fallback, teardown disconnect order, raid leftover reconciliation, desync counter state machine
- Integration tests: rebuild with stalled source, expansion on dead dm-linear, EF heal after rollout
- Negative tests: rebuild with healthy source (no timeout), expansion on healthy dm-linear (normal suspend)