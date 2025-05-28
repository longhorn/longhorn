# V2 Engine - Interrupt Mode

## Summary

This proposal introduces **interrupt mode** support for the Longhorn V2 engine to reduce CPU usage, especially in cluster with idle or low I/O workloads. The current V2 engine relies on SPDK's polling mode, which continuously consumes CPU resources (~100%) even when no I/O is occurring.

In the initial phase, interrupt mode will be implemented for the SPDK NVMe/TCP transport using a **hybrid approach**:
- The NVMe-oF **target** will use `epoll` to wait for socket readiness events.
- The NVMe-oF **initiator** will continue to poll periodically to flush I/O completions.

In future iteration, we may explore `epoll` with `eventfd` to detect queue push events and forward I/O commands directly to the socket file descriptor, enabling a more fully even-driven design.

### Related Issues

- https://github.com/longhorn/longhorn/issues/9834
- ~https://github.com/longhorn/longhorn/issues/9419~

## Motivation

Offer users a setting to enable interrupt mode in the Longhorn V2 engine, allowing instance managers to operate with lower CPU consumption.

### Problem

The SPDK's polling mode in V2 engine causes near-constant CPU utilization even when volumes are idle, leading to inefficient resource usage.

### Goals

- Provide users the ability to **opt-in** to interrupt mode to reduce CPU usage.
- Offer configuration for the initiator’s polling interval, balancing CPU consumption with I/O latency (phase 2).

### Non-goals [optional]

- Interrupt mode support for other transport protocols (e.g., RDMA) is out of scope.
- Switch from `spdk_tgt` to `nvmf_tgt`, see GitHub issue [comment](https://github.com/longhorn/longhorn/issues/9419#issuecomment-3101365564).

## Proposal

### Design Overview

The initial interrupt mode implementation adopts a **hybrid approach**:
- The SPDK NVMe-oF **target** waits on socket readiness using `epoll`.
- The SPDK NVMe-oF **initiator** periodically call `bdev_nvme_poll` at an interval to process pending I/O completions.

This hybrid approach provides immediate CPU savings while maintaining responsiveness.

**Future Investigate**

We plan to explore `eventfd` with `epoll` to detect queue push events more precisely and forward I/O command directly to the socket file descriptor. This approach could enable a fully event-driven architecture, potentially reducing CPU overhead further.

### Configurable Settings

- `data-engine-interrupt-mode-enabled`: Enables interrupt mode for V2 engine volumes (phase 1).
- `data-engine-nvme-ioq-poll-period-us`: Polling interval (microseconds) for initiator I/O queue polling (phase 2).

### User Stories

#### Story 1: Reduce CPU Usage

**Before:** V2 instance manager uses ~100% CPU even when idle.

**After:** With interrupt mode, CPU usage drops dramatically under low or no I/O.

#### Story 2: Configurable Performance

**Before:** Users can't adjust I/O command polling frequency.

**After:** Users can tune `data-engine-nvme-ioq-poll-period-us` setting to balance between CPU consumption and I/O responsiveness.

### User Experience In Detail

User enable interrupt mode via global settings:
```yaml
defaultSetting:
    data-engine-interrupt-mode-enabled: true
    data-engine-nvme-ioq-poll-period-us: 100    # in microseconds (1ms)
```

When enabled:
- The NVMe-oF **target** waits on `epoll` for I/O readiness.
- The NVMe-oF **initiator** polls periodically to flush I/O completions.
- CPU usage decreases, especially in idle or light workload scenarios.

### API changes

None.

## Design

### Key Changes

1. **Enable interrupt mode** for the SPDK NVMe-oF TCP target.
1. **Replace busy-wait loops** with pollers to complete TCP connections asynchronously and enable the target to respond to epoll events.
1. **Update the SPDK NVMe bdev module** to:
    - Periodically poll I/O queues to flush pending initiator commands.
    - Periodically poll the admin queue to issue keep-alive commands.
1. **Introduce global settings** for the feature support.

### Phased Rollout

#### Phase 1: Basic Interrupt Mode
- Set a fixed I/O queue polling interval of `100ms` (`nvme_ioq_poll_period_us = 100`), based on [benchmark results](#benchmark-results).
- Utilize `g_opts.nvme_adminq_poll_period_us`, set in `longhorn-spdk-engine`, to ensure timely keep-alive command completion.
- Introduce `data-engine-interrupt-mode-enabled` global setting to toggle interrupt mode.
- Benchmark I/O performance in polling vs. interrupt mode scenarios.

##### Dependencies

- Requires `SPDK v25.x` for foundational change of bdev NVMe interrupt-mode support.
- Rebase Longhorn’s SPDK fork on `SPDK v25.x`.

##### SPDK

1. **Enable interrupt mode for NVMe/TCP** in the SPDK bdev NVMe module.
1. **Enable periodic polling** of `bdev_nvme_poll` to flush `sock->queued_reqs` into the TCP stack.
1. **Replace busy-wait loop** with asynchronous poller in the TCP connection handling path. This will be removed once the I/O queue state changed from connecting state.
1. Remove `event_iscsi` from `SPDK_LIB_LIST` to prevent unnecessary iSCSI subsystem initialization in `spdk_tgt`.

##### New Global Setting

`data-engine-interrupt-mode-enabled`:
- **Type:** Boolean
- **Default:** `false` (polling mode is the default)

##### Custom Resource Definition (CRD)

Add `InterruptModeEnabled` field to `InstanceManager.status.dataEngineStatus.v2` to indicate whether the V2 data engine is running in **interrupt mode** (`true`) or **polling mode** (`false`). This field is managed and updated by the Longhorn Manager.

#### Phase 2: Configurable Polling Interval

Support dynamic polling interval configuration in the SPDK engine.

##### New Global Setting

`data-engine-nvme-ioq-poll-period-us`:
- **Type:** Integer
- **Range:** >= 1
- **Default:** `100` (microseconds)

##### SPDK Engine

Expose `nvme_ioq_poll_period_us` as an externally configurable parameter.

### Test Plan

1. **Performance Testing:**
    - Compare performance in polling vs interrupt mode.
    - Evaluate performance for various polling intervals.
1. **Functional Testing:**
    - Verify volume creation ensure I/O operations functions correctly with interrupt mode enabled.
    - Compare CPU usage between polling mode and interrupt mode.
1. **Regression Testing:**
    - Ensure all V2 volume features behave correctly in both modes.

### Benchmark Results

**Environment**
- Cloud: AWS
- OS: SLES 15 SP7 (AMI: ami-05cf3966cddeb5037)
- Kubernetes: k3s v1.32.0+k3s1
- Nodes: t2.2xlarge
- Disks: 3× 200GiB EBS gp2

**Interrupt Mode (nvme_ioq_poll_period_us = 1000)**
```
TEST_FILE: /volume/test
TEST_OUTPUT_PREFIX: ./test_device
TEST_SIZE: 10G
MODE: full
Benchmarking random read iops
Benchmarking random write iops
Benchmarking sequential read bandwidth
Benchmarking sequential write bandwidth
Benchmarking random read latency
Benchmarking random write latency

=========================
FIO Benchmark Summary
For: ./test_device
CPU Idleness Profiling: disabled
Size: 10G
Mode: full
=========================
IOPS (Read/Write)
        Random:            9,077 / 3,000

Bandwidth in KiB/sec (Read/Write)
    Sequential:         248,535 / 61,601

Latency in ns (Read/Write)
        Random:    2,010,330 / 3,651,041
```

**Interrupt Mode (nvme_ioq_poll_period_us = 100)**
```
TEST_FILE: /volume/test
TEST_OUTPUT_PREFIX: ./test_device
TEST_SIZE: 10G
MODE: full
Benchmarking random read iops
Benchmarking random write iops
Benchmarking sequential read bandwidth
Benchmarking sequential write bandwidth
Benchmarking random read latency
Benchmarking random write latency

=========================
FIO Benchmark Summary
For: ./test_device
CPU Idleness Profiling: disabled
Size: 10G
Mode: full
=========================
IOPS (Read/Write)
        Random:            5,308 / 2,999

Bandwidth in KiB/sec (Read/Write)
    Sequential:         248,579 / 61,583

Latency in ns (Read/Write)
        Random:      980,071 / 2,476,177
```

**Polling Mode**
```
TEST_FILE: /volume/test
TEST_OUTPUT_PREFIX: ./test_device
TEST_SIZE: 10G
MODE: full
Benchmarking random read iops
Benchmarking random write iops
Benchmarking sequential read bandwidth
Benchmarking sequential write bandwidth
Benchmarking random read latency
Benchmarking random write latency

=========================
FIO Benchmark Summary
For: ./test_device
CPU Idleness Profiling: disabled
Size: 10G
Mode: full
=========================
IOPS (Read/Write)
        Random:            6,996 / 3,007

Bandwidth in KiB/sec (Read/Write)
    Sequential:         370,937 / 59,414

Latency in ns (Read/Write)
        Random:    1,288,569 / 2,065,952
```

**V1 Engine**
```
TEST_FILE: /volume/test
TEST_OUTPUT_PREFIX: ./test_device
TEST_SIZE: 10G
MODE: full
Benchmarking random read iops
Benchmarking random write iops
Benchmarking sequential read bandwidth
Benchmarking sequential write bandwidth
Benchmarking random read latency
Benchmarking random write latency

=========================
FIO Benchmark Summary
For: ./test_device
CPU Idleness Profiling: disabled
Size: 10G
Mode: full
=========================
IOPS (Read/Write)
        Random:            5,900 / 1,973

Bandwidth in KiB/sec (Read/Write)
    Sequential:         161,421 / 60,279

Latency in ns (Read/Write)
        Random:    1,821,355 / 2,468,884
```

##### 🔍 Performance Comparison

| Mode                           | Rand Read IOPS | Rand Write IOPS | Seq Read BW (KiB/s) | Seq Write BW (KiB/s) | Rand Read Latency (ns) | Rand Write Latency (ns) |
|--------------------------------|----------------|------------------|----------------------|-----------------------|--------------------------|---------------------------|
| **V2 (Interrupt, 1000ms)**     | **9,077**      | 3,000            | 248,535              | **61,601**            | 2,010,330                | 3,651,041                 |
| **V2 (Interrupt, 100ms)**      | 5,308          | 2,999            | 248,579              | 61,583                | **980,071**              | 2,476,177                 |
| **V2 (Polling)**               | 6,996          | **3,007**        | **370,937**          | 59,414                | 1,288,569                | **2,065,952**             |
| **V1 Engine**                  | 5,900          | 1,973            | 161,421              | 60,279                | 1,821,355                | 2,468,884                 |


---

Setting `nvme_ioq_poll_period_us` to 100ms (0.1s) seems to offer the best balance between performance and CPU efficiency. It achieves the **lowest read latency** while maintaining reasonable IOPS, making it suitable for general-purpose workloads.

By contrast, setting `nvme_ioq_poll_period_us` to 1000ms (1s) increases the wait time before polling for I/O completions. This can allow more I/Os to accumulate and be processed in batches, potentially increasing IOPs. However, it comes at the cost of **higher latency**, making it less suitable for latency-sensitive workloads.

### Upgrade strategy

No migration required. Interrupt mode is opt-in and disabled by default, preserving current behavior.

## Note [optional]

- https://github.com/longhorn/longhorn/issues/9834#issuecomment-2914384232
