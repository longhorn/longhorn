# V2 Engine - SPDK Crash-Consistency and Teardown Hardening

## Summary

This proposal documents a series of **crash-consistency and teardown hardening fixes** for the SPDK NVMe-oF subsystem used by the Longhorn V2 data engine. These fixes address use-after-free (UAF) bugs, reset/disconnect recursion, reconnect storms, and orphaned controller leaks that caused SPDK reactor CPU saturation, spdk_tgt crashes, and wedged instance managers during storage node restarts in production.

The fixes span the SPDK `bdev_nvme`, `nvme`, `nvmf`, `bdev`, `bdev/raid`, and `util/sock` modules.

### Related Issues

- TBD

## Motivation

### Problem

During mass storage-node restarts (e.g., Talos upgrades, node reboots), the V2 engine experienced:

1. **Reset/disconnect recursion**: `bdev_nvme_reset_ctrlr_complete(false)` → `nvme_ctrlr_disconnect()` → EBUSY → `spdk_thread_send_msg(bdev_nvme_reset_ctrlr_complete_failed)` → no-op (resetting already cleared) → controller stuck in limbo, adminq poller re-drives failover at ~1Hz per controller, 4 SPDK reactors at 100% CPU.

2. **Reconnect-storm teardown UAF**: The async-connect poller was owned by the NVMe controller, not the qpair. When the controller was torn down during a reconnect storm, the poller fired against freed memory.

3. **bdev iteration UAF**: `spdk_for_each_bdev` iterated a linked list that could be modified during iteration by a concurrent `spdk_bdev_unregister`, causing use-after-free.

4. **RAID faulty-state teardown UAF**: When a raid bdev entered faulty state, channel iteration could access channels that were already torn down.

5. **NVMf controller leak**: Stranded/superseded controllers (e.g., from keep-alive timeout) were not reaped, accumulating in the subsystem and leaking memory.

6. **NVMf TCP QUIESCING PDU leak**: In-flight PDUs were not drained when a QUIESCING command was received, causing the connection to hang.

7. **fd_group_remove abort**: Removing a closed file descriptor from an fd_group triggered an abort and reactor spin.

### Goals

- Eliminate all known UAF and crash paths in the NVMe-oF subsystem under reconnect storms
- Bound CPU usage during storage-node restarts (no reactor saturation)
- Clean up orphaned controllers and stale connections automatically
- Preserve data integrity during teardown races

### Non-goals

- Changing the NVMe-oF protocol implementation
- Adding new transport types (RDMA transport is a separate enhancement)
- Rewriting the bdev framework

## Proposal

### Fix 1: EBUSY disconnect retry spacing

When `spdk_nvme_ctrlr_disconnect()` returns `-EBUSY` during the OP_DELAYED_RECONNECT path (after `resetting` has been cleared), the retry is now spaced by `reconnect_delay_sec` via a one-shot SPDK poller (`ebusy_retry_timer`) instead of `spdk_thread_send_msg` (which fired every reactor tick). The `reconnect_is_delayed` flag gates the adminq poller from re-driving failover during the delay.

When `resetting` is still true (the reset sequence's own disconnect failed), the original `send_msg` path is used to complete the failed reset.

### Fix 2: Reset/disconnect recursion break

The `bdev_nvme_reset_ctrlr_complete_failed` deferred callback is now idempotent: if `resetting` has already been cleared by the time the callback fires, it does nothing (no double-completion, no spurious failover re-drive).

The adminq poller's failover re-drive is guarded by `!resetting && !reconnect_is_delayed` and rate-limited to ~1Hz per controller via `failover_redrive_tsc`.

### Fix 3: Async-connect poller ownership

The async-connect poller is now owned by the qpair (not the controller) and is unregistered when the qpair is disconnected. This prevents the poller from firing against freed memory during controller teardown.

### Fix 4: bdev iteration UAF

`spdk_for_each_bdev` and `spdk_for_each_bdev_leaf` now safely handle concurrent `spdk_bdev_unregister` by deferring list removal until any in-flight reset completes, completing QoS unregister outside the manager lock, and dropping missing name entries.

### Fix 5: RAID faulty-state teardown UAF

RAID bdev free is deferred until `bdev_destruct` completes. Faulty-state channel iteration guards against concurrent teardown.

### Fix 6: NVMf controller reap

Stranded/superseded controllers (e.g., from keep-alive timeout during a reconnect storm) are now reaped automatically, preventing memory leaks and stale subsystem entries.

### Fix 7: NVMf TCP QUIESCING PDU drain

In-flight PDUs are drained from any receive state when a QUIESCING command is received, preventing connection hangs.

### Fix 8: fd_group_remove safety

`fd_group_remove` now handles closed file descriptors gracefully, preventing aborts and reactor spins during teardown.

### Fix 9: nvme_detach_poller timeout

The `nvme_detach_poller` now has a 10-second timeout, preventing it from spinning forever if the detach never completes.

### Fix 10: nvme/tcp delete_io_qpair UAF

The `needs_poll`/`timeout_enabled` check in `nvme_tcp_qpair` deletion now safely handles the case where the qpair is being torn down concurrently.

### Fix 11: bdev-name use-after-free from reconnect resurrection

When a controller reconnects after its bdev was unregistered, the bdev name was accessed after free. The fix null-guards the name access and prevents reconnect resurrection of unregistered bdevs.

### Fix 12: mlx5/rdma fixes

- Force `crc32c_supported=false` in mlx5 to skip sig mkey pool allocation (not needed for NVMe-oF, saves memory)
- NULL-guard `rdma_qp` in `nvme_ctrlr_get_memory_domains` to prevent NPE during RDMA teardown

### Fix 13: NVMf listener add error handling

`nvmf_subsystem_add_listener` now handles `listen_associate` failure gracefully, uses a common error path, and only traces the listener after it was successfully added.

## Test Plan

Each fix includes unit test coverage:
- `test_ebusy_retry_respects_reconnect_delay` — EBUSY timer spacing
- `test_start_reconnect_delay_cancels_ebusy_timer` — timer cancellation
- `test_failover_not_redriven_while_resetting` — adminq guard
- `test_race_between_ctrlr_loss_timeout_and_pending_failover` — ctrlr_loss interaction
- bdev iteration tests — `for_each_bdev` continuing past unregistering bdev
- NVMf TCP QUIESCING PDU drain tests — all receive states
- Raid faulty-state teardown tests

## Production Validation

These fixes were developed and validated on running large Longhorn clusters with mixed TCP and RDMA v2 volumes. Before the fixes, storage-node restarts caused:
- SPDK reactor CPU saturation on consumer instance managers
- spdk_tgt crashes (core dumps)
- Wedged instance manager pods requiring manual force-delete
- Faulted volumes requiring manual salvage

After the fixes:
- Reactor CPU remains bounded during storage-node restarts
- No spdk_tgt crashes observed across multiple restart events
- No wedged instance manager pods
- No faulted volumes from restart events