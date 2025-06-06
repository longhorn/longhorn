# V2 Engine - Interrupt Mode

## Summary

This proposal introduces **interrupt mode** support for Longhorn V2 engine to reduce CPU usage, especially in clusters with idle or low I/O workloads. Instead of relying on polling mode, interrupt mode uses an **event-driven approach** for the SPDK target (via `epoll`) and a periodic polling for the initiator to achieve interrupt-like behavior over NVMe TCP transport, reducing CPU usage compared to pure polling.

Currently, Longhorn V2 engine use SPDK's polling-based model because SPDK does not support interrupt mode for the NVMe/TCP transport. As a result, the V2 instance manager consumes nearly 100% even under minimal workloads. By introducing interrupt mode with a configurable NVMe/TCP I/O completion polling interval, Longhorn can reduce unnecessary CPU consumption.

### Related Issues

- https://github.com/longhorn/longhorn/issues/9834
- https://github.com/longhorn/longhorn/issues/9419

## Motivation

Provide users with the option to enable interrupt mode for Longhorn V2 engine SPDK processes, allowing the V2 instance manager to operate with reduced CPU usage.

### Problem

The Longhorn V2 engine currently runs in polling mode. This means it repeatedly spins a tight loop for queue handlings, leading to excessive CPU consumptions even during inactive periods.

### Goals

- Provide a **global setting** that allow users to **enable interrupt mode** for Longhorn V2 volume creation to reduce CPU usage in idle or low I/O scenarios.
- Introduce a global setting for configuring the `nvme_ioq_poll_period_us` parameter for the initiator to balance CPU usage and I/O responsiveness.
- Use the SPDK `nvmf_tgt` instead of `spdk_tgt` to further reduce CPU and resource overheads.

### Non-goals [optional]

- Interrupt mode support for other transports such as RDMA is out of scope.

## Proposal

Interrupt mode for Longhorn V2 engine will be implemented using a hybrid approach:
- The **SPDK target** uses `epoll` to wait for socket readiness events.
- The **SPDK initiator** periodically invokes `bdev_nvme_poll` at a configurable interval to flush pending I/O completions, simulating interrupt-driven behavior over NVMe/TCP.

To further reduce CPU usage, the engine will use `nvmf_tgt` instead of `spdk_tgt`, which is designed for NVMe-oF and supports event-based handling.

Two global settings will be introduced:
- `v2-data-engine-interrupt-mode-enabled`: Enables or disables interrupt mode, allowing users to switch between polling and interrupt modes.
- `v2-data-engine-nvme-ioq-poll-period-us`: Specifies the polling interval (in microseconds) for the initiator to handle I/O completions. Lower values increase responsiveness but consume more CPU.

### User Stories

#### Story 1: Lower CPU Usage

**Before:** V2 instance manager consistently runs at ~100% CPU.

**After:** Enabling interrupt mode reduces CPU usage significantly for cluster with idle volumes.

#### Story 2: Customizable Performance Tuning

**Before:** No control over initiator polling frequency.

**After:** Users configure the `v2-data-engine-nvme-ioq-poll-period-us` setting to balance CPU consumption and I/O responsiveness.

### User Experience In Detail

Interrupt mode is configured through global settings:
```yaml
defaultSetting:
    v2-data-engine-interrupt-mode-enabled: true     # Enable/disables interrupt mode
    v2-data-engine-nvme-ioq-poll-period-us: 1000    # Poll interval in microseconds (1ms)
```

When enabled:
- The **target** waits for I/O readiness using `epoll`.
- The **initiator** periodically flushes pending I/O via polling.
- CPU usage decreases, especially for idle or light workload scenarios.

### API changes

None.

## Design

### Implementation Overview

SPDK currently lacks upstream support for interrupt-mode on NVMe/TCP Bdev initiator. The initiator must periodically flush internal socket queues (`sock->queued_reqs`) to the OS TCP stack.
1. **Replace `spdk_tgt` with `nvmf_tgt`** to further reduce CPU overhead.
1. **Enable interrupt mode** for the SPDK NVMf target.
1. **Modify SPDK Bdev NVMe module** to allow initiator to support interrupt-mode and periodic polling for I/O completion via `bdev_nvme_poll`.

### Phased Implementation

#### Phase 1: Basic Interrupt Mode
- Hardcode `nvme_ioq_poll_period_us` = 1000 µs (1 millisecond).
- Introduce `v2-data-engine-interrupt-mode-enabled` global setting.
- Benchmark CPU usage in polling vs. interrupt modes.

##### Dependency

- **SPDK v25.x** required for foundational of Bdev NVMe interrupt-mode support.
- Rebase Longhorn’s SPDK fork (`longhorn/spdk`) onto upstream SPDK (`spdk/spdk`) v25.x release.

##### SPDK

1. **Enable Interrupt Mode for NVMe/TCP:**
    Modify SPDK's bdev NVMe module to support interrupt mode over TCP transport, which currently is restricted.
1. **Enable Periodic Polling via `bdev_nvme_poll`:**
    Ensure the initiator periodically invokes `bdev_nvme_poll` to flush pending I/O requests from `sock->queued_reqs` into the OS TCP stack, maintaining proper I/O completion handling in interrupt mode.

##### Longhorn V2 Instance Manager

- Use `nvmf_tgt` instead of `spdk_tgt`.

##### New Global Setting

`v2-data-engine-interrupt-mode-enabled`:
- **Type:** Boolean
- **Default:** `false` (polling mode remains default)

#### Phase 2: Expose Configurable Polling Interval

Allow users to configure polling interval.

##### New Global Setting

`v2-data-engine-nvme-ioq-poll-period-us`:
- **Type:** Integer
- **Range:** >= 1
- **Default:** `1000` (1 millisecond)

##### SPDK Engine

Support `nvme_ioq_poll_period_us` parameter to be configured externally (to be designed in detail during Phase 2).

### Test plan

1. **Performance Testing:**
    - Phase 1: Benchmark CPU usage in polling vs. interrupt mode.
    - Phase 2: Benchmark different values for `v2-data-engine-nvme-ioq-poll-period-us` (`nvme_ioq_poll_period_us`) setting (e.g., 10, 100, 1000 µs).
1. **Functional Testing:**
    - Phase 1:
        - Verify volumes create and operate correctly with interrupt mode enabled.
    - Phase 2:
        - Confirm `v2-data-engine-nvme-ioq-poll-period-us` setting changes are respected.
1. **Regression Testing:**
    - Test all V2 volume features under both polling and interrupt modes.

### Upgrade strategy

No migration required. The interrupt mode feature is controlled via a new global setting, defaulting to `false` to maintain current behavior. Since the V2 engine does not yet support live upgrades, this feature will not require in-place upgrade support.

## Note [optional]

- https://github.com/longhorn/longhorn/issues/9834#issuecomment-2914384232

