# Auto-salvage Support For V2 Volumes

## Summary

This document proposes extending Longhorn's auto-salvage feature to support v2 volumes. Currently, auto-salvage automatically recovers v1 volumes when all its replicas fail. This proposal aims to provide the same functionality for v2 volumes, improving data availability and reducing operational overhead.

### Related Issues

https://github.com/longhorn/longhorn/issues/8430

## Motivation

### Goals

- **Improve Data Availability For V2 Volumes:** Auto-salvage ensures v2 volumes automatically recovers from replica failures, minimize downtime.
- **Reduce Operational Overhead:** Automating recovery, freeing user from manual intervention during failures.

### Non-goals [optional]

- `None`

## Proposal

### User Stories

#### Story 1: Auto-salvage V2 Volumes When All Replicas Failed

As a Longhorn user, I want Longhorn to automatically salvage a v2 volume when all its replicas fail, similar to the existing functionality for v1 volumes.

- **Before:** Manual intervention was required to recover a faulted v2 volume when all replicas failed.
- **After:** With auto-salvage enabled, Longhorn will attempt to salvage usable replicas and bring the v2 volume back online automatically.

### User Experience In Detail

- **Auto-salvage:** When the setting is enabled, if all replicas for a volume fail, Longhorn attempts salvage usable replicas to recover the volume state.
- **Volume Trim Operation Blocking:** For degraded v2 volumes, filesystem trim operation will be blocked to preserve a reliable volume head size for identifying usable replica candidates.

### API changes

#### SPDK RPC Protobuf

- Introduce `salvage_requested` boolean field in the `SpdkInstanceSpec` message. which is passed to the instance GRPC server during engine instance creation.
  ```go
  message SpdkInstanceSpec {
  	map<string, string> replica_address_map = 1;
  	string disk_name = 2;
  	string disk_uuid = 3;
  	uint64 size = 4;
  	bool expose_required = 5;
  	string frontend = 6;
  	bool salvage_requested = 7;
  }
  ```

- Introduce `salvage_requested` boolean field in the `EngineCreateRequest` message to pass to the SPDK server during engine creation.
  ```go
  message EngineCreateRequest {
      string name = 1;
      string volume_name = 2;
      uint64 spec_size = 3;
      map<string, string> replica_address_map = 4;
      string frontend = 5;
      int32 port_count = 6;
      bool upgrade_required = 7;
      string initiator_address = 8;
      string target_address = 9;
      bool salvage_requested = 10;
  }
  ```

## Design

> **Note:**
> The design applies only to v2 volumes. The v1 volume candidate selection remains unchange.

### Failed Usable Replica Filtering

When `EngineCreate()` is called with `salvage_requested` set to `true`, the SPDK server retrieves `Replica` from SPDK server cache. We assume that all remaining replicas' lvols are identical and their lvol heads contain that latest data. The lvol head with the largest size is assumed to hold the most recent, valid data since larger size should indicates that it includes the latest writes or updates. Therefore, the head sizes of all replicas are sorted, and replicas with head sizes different from the largest in the sorted list are excluded from the candidate list.

### Engine Creation

During SPDK replica creation, if the replica already exists, the lvol bdev creation process is skipped. Instead, `Replica.construct()` is called to build the `Replica` object with existing lvol.

### Volume Filesystem Trim Operation Blocking

Block filesystem trim operation on degraded v2 volumes to preserve the lvol head size, ensuring reliable salvage replica candidate selection.

### Test plan

1. **Feature Testing:**
   1. Use existing robot/integration test cases (cluster reboot, node powerdown, network disconnection, etc.) to verify auto-salvage functionality for v2 volumes after replica failures.
   1. Introduce new robot test cases to verify that trim operations are blocked for degraded v2 volumes.
1. **Regression Testing:** Ensure v1 volume auto-salvage and volume trim operation remains unaffected by the this extended feature implementation.

### Upgrade strategy

No specific upgrade strategy is required for this feature extension.

## Note [optional]

None
