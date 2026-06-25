# V2 Engine - Per-Engine QoS Limits

## Summary

This proposal introduces **per-engine Quality of Service (QoS)** limits for the Longhorn V2 data engine, allowing operators to cap aggregate I/O throughput (IOPS and bandwidth) on individual v2 volumes. QoS limits are applied at the SPDK raid bdev level via `bdev_set_qos_limit`, providing kernel-bypass enforcement without the overhead of cgroups or ionice.

The implementation adds:
- `QosLimits` protobuf message mapping to SPDK's `bdev_set_qos_limit` parameters
- `qos_limits` field on `InstanceSpec` and `EngineCreateRequest`
- `EngineSetQosLimit` RPC for live QoS updates without volume detach
- QoS limit propagation through the manager to the engine

### Related Issues

- TBD

## Motivation

### Goals

- Allow operators to cap IOPS and/or bandwidth on individual v2 volumes
- Support live QoS updates without detaching the volume
- Apply limits at the raid bdev level so rebuild traffic (engine→replica direct) is not subject to the cap

### Non-goals

- Per-replica QoS (limits are per-volume/engine, not per-replica)
- QoS for v1 data engine (v1 uses Linux block devices, not SPDK)
- Automatic QoS based on workload classification

## Proposal

### Design Overview

SPDK's `bdev_set_qos_limit` API provides token-bucket-based rate limiting at the bdev layer. By applying QoS limits to the raid bdev (the multipath device that the engine frontend exposes), we cap the I/O that the volume can generate to its replicas. Rebuild traffic, which flows directly from the engine to the rebuilding replica over NVMe-oF, bypasses the raid bdev and is therefore not throttled.

#### QoS Parameters

```protobuf
message QosLimits {
    int64 rw_ios_per_sec = 1;   // Total IOPS limit (read + write)
    int64 rw_mb_per_sec = 2;    // Total bandwidth limit in MB/s (read + write)
    int64 r_mb_per_sec = 3;     // Read bandwidth limit in MB/s
    int64 w_mb_per_sec = 4;     // Write bandwidth limit in MB/s
}
```

All-zero values mean unlimited (default).

### User Stories

#### Story 1

As a cluster operator, I want to cap a noisy neighbor v2 volume's IOPS so that it doesn't starve other volumes sharing the same storage nodes.

#### Story 2

As a cluster operator, I want to adjust QoS limits on a running volume without detaching it, so that I can respond to changing workload patterns without downtime.

### User Experience In Detail

1. **Set QoS on volume creation**: The `qos_limits` field in the `EngineCreateRequest` sets initial limits when the engine is created.
2. **Live QoS update**: The `EngineSetQosLimit` RPC updates limits on a running engine without detaching the volume.
3. **Limit scope**: Limits apply to the volume's aggregate I/O (all replicas). Rebuild traffic is not throttled.
4. **Verification**: The engine's status reports the current QoS limits.

### Implementation Details

#### Types (protobuf)
- `QosLimits` message with IOPS and bandwidth fields
- `qos_limits` field on `InstanceSpec` and `EngineCreateRequest`
- `EngineSetQosLimitRequest` message for live updates

#### SPDK Engine
- `EngineSetQosLimit` gRPC method calls `spdkClient.BdevSetQosLimit(raidBdevName, limits)`
- QoS limits are applied after raid bdev creation in `EngineCreate`
- Live updates acquire the engine lock, call `BdevSetQosLimit`, and update the in-memory state

#### Manager
- Volume spec carries `qosLimits` field
- Volume controller propagates limits to `EngineCreate` and `EngineSetQosLimit` RPCs
- QoS limits are included in the volume API model

### Test Plan

- Unit tests: QoS limit application on raid bdev, live update without detach
- Integration tests: QoS enforcement with synthetic workloads, rebuild traffic bypass
- Negative tests: invalid QoS values, QoS on non-existent engine