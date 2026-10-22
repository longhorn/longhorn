# V2 IO Control and Throttle for Volumes

## Summary

Longhorn volumes that use the V2 Data Engine share the CPU, disk, and network resources of the node they run on. Today a single busy volume can consume most of that capacity and starve the other volumes on the node. This enhancement lets users set per-volume limits on IOPS and bandwidth for V2 volumes.

### Related Issues

• https://github.com/longhorn/longhorn/issues/9265
• https://github.com/longhorn/longhorn/issues/10770 (replica rebuild QoS, prior art that this proposal builds on)

## Motivation

A V2 volume is served by one SPDK target (spdk_tgt) per node, shared by all engines and replicas on that node. Nothing currently stops one volume from using a disproportionate share of the node. Typical symptoms are a batch job or database saturating a shared NVMe disk while latency-sensitive volumes on the same node slow down.

SPDK already supports per-bdev rate limiting, and Longhorn already uses it for replica rebuilding. What is missing is a user-facing way to apply it to the application IO of a volume.

### Goals

- Users can set limits on a V2 volume for combined read/write IOPS, combined read/write bandwidth, read bandwidth, and write bandwidth. A value of 0 means unlimited. 
- Limits apply to the IO the respective application issues to the volume, regardless of the number of replicas. 
- Limits can be set at creation time, including through StorageClass parameters. 
- Limits can be changed or removed on an attached, running volume without detaching it. 
- Limits survive restarts of the instance manager, the SPDK target, and engine recreation. They are reapplied automatically. 
- The applied values are visible to the user in the engine status. 
- The feature is independent of replica rebuild QoS (issue 10770). The two do not overwrite each other. 
- Existing V2 volumes and V1 volumes see no behavior change. The default is unlimited.

### Non-goals [optional]

- Limits on V1 data engine volumes. 
- Throttling replica rebuild traffic. This is already covered by issue 10770. 
- Per-disk or per-node limits that cap the combined load of all volumes. This can be a separate enhancement with its own design. 
- Limits on individual replicas (see the discussion of attach points in the design section). 
- Guaranteed minimum performance, priorities, burst credits, or fairness between volumes. Only maximum limits are in scope.

## Proposal

- Add optional IO limit fields to the Volume spec for V2 volumes. 
- The engine controller copies them to the Engine spec and pushes them to the SPDK engine, which calls `bdev_set_qos_limit` on the volume RAID1 bdev. 
- A reconcile step in the engine monitor keeps the applied limits equal to the desired limits, which also covers restarts.

### User Stories

#### Story 1 - Protect other volumes from a noisy neighbor
Before this enhancement, an operator whose analytics volume saturates a shared disk can only move the workload or add hardware. After this enhancement, the operator sets a write bandwidth limit and an IOPS limit on that volume. The other volumes on the node keep their latency, and the operator does not need to detach or restart anything.

#### Story 2 - Offer performance classes through StorageClass
Before this enhancement, every V2 volume from a StorageClass is unlimited. After this enhancement, a platform team can define a StorageClass named `longhorn-v2-standard` with modest limits and another named `longhorn-v2-fast` with none. Tenants can choose the class when creating a PVC and the limits are applied automatically at provisioning time.

[//]: # (TODO: refinement needed)
### User Experience In Detail

#### Set/Remove limits on an existing volume
- Set the limit on an existing volume:
````shell
$ kubectl -n longhorn-system patch volumes.longhorn.io vol-0 --type=merge -p '{"spec": {"ioLimits": {"rwIopsLimit": 5000, "rwMbytesPerSecondLimit": 100}}}'
````

- Remove the limit from a volume:
```shell
$ kubectl -n longhorn-system patch volumes.longhorn.io vol-0 --type=merge -p '{"spec": {"ioLimits": {"rwIopsLimit": 0, "rwMbytesPerSecondLimit": 0}}}'
```

#### StorageClass - to be used for multiple volumes
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-v2-standard
provisioner: driver.longhorn.io
parameters:
  dataEngine: v2
  numberOfReplicas: 3
  rwIopsLimit: 5000
  rwMbytesPerSecondLimit: 100
```

### API changes

- `Volume CRD` (spec), optional, V2 only, int64, 0 means unlimited:
```yaml
spec:
  ioLimits:
    rwIopsLimit: 0
    rwMbytesPerSecondLimit: 0
    rMbytesPerSecondLimit: 0
    wMbytesPerSecondLimit: 0
```
- `Engine CRD`: the same ioLimits structure in ``spec`, copied from the volume by the volume controller. A new status.`appliedIoLimits` structure records the values last applied successfully.
- `StorageClass parameters`: rwIopsLimit, rwMbytesPerSecondLimit, rMbytesPerSecondLimit, wMbytesPerSecondLimit.
- `Longhorn REST API and UI`: the volume resource exposes the same fields, and updating them goes through the normal volume update path.
- `Validation (admission webhook)`:
  • Reject non-zero limits on volumes that are not V2.
  • Reject negative values.
  • Reject non-zero values below the minimum SPDK accepts (to be confirmed against the SPDK version Longhorn builds, see open questions).
- `Instance manager proxy gRPC`: a new method carrying the engine identity and the four values, alongside the existing proxy methods such as the rebuilding QoS one.
- `SPDK engine`: the engine creation spec gets the four values so limits can be applied before the frontend is exposed, and a runtime update method for live changes.
- `Global settings`: cluster-wide defaults, follow the same precedence as rebuild QoS:
  | Global Setting | `volume.spec.rebuildingQosLimit` | Behavior |
  |---|---|---|
  | Not `0` | `0` | Respect the global setting |
  | `0` | Not `0` | Respect the per-volume setting |
  | Not `0` | Not `0` | Respect the per-volume setting |
  | `0` | `0` | No limit |

## Design

### Implementation Overview

#### Where the limit is applied

- The limit is applied to the `RAID1 bdev` that the SPDK engine builds for each volume. 
- In the V2 architecture:
  - a remote replica is an NVMe-oF subsystem with an lvol behind it, 
  - a local replica is an lvol, 
  - and the engine backend is a RAID1 bdev over those. 
The frontend (NVMe-oF/kernel nvme-tcp, or ublk) consumes the RAID1 bdev, so a limit there covers every frontend.

#### Caveats

A write limit of `x` on the RAID1 bdev still results in `x` MB/s of writes to each replica, so cluster-wide write load is `x` multiplied by the `number of replicas`. Documentation must state this so administrators choose values accordingly.

#### Changes by repository

- **longhorn/longhorn-manager**:
  - Volume and Engine CRD fields and generated code, 
  - admission validation, 
  - StorageClass parameter parsing, 
  - volume controller copying `spec.ioLimits` to the engine, 
  - engine monitor reconcile step, 
  - REST API types, and handling of instance managers that do not implement the new RPC.
- **longhorn/longhorn-instance-manager**: 
  - proto definition and server handler for the new proxy method, and passing the four values in the engine creation spec.
- **longhorn/longhorn-spdk-engine**: 
  - store the limits on the Engine object, apply them right after the RAID1 bdev is created and before the frontend is exposed, expose a runtime update method, and reapply after any flow that recreates the RAID1 bdev.
- **longhorn/go-spdk-helper**: no change expected. 
  - BdevSetQosLimit(bdevName, rwIOsPerSec, rwMBPerSec, rMBPerSec, wMBPerSec) already exists.
[//]: # (TODO: Confirm its behavior when called with zeros.)
- **longhorn/longhorn-ui**: 
  - IO limits fields on the volume create and detail pages.

#### Keeping the limit in place

SPDK keeps QoS settings only in the memory of the running `spdk_tgt` process. The desired limits therefore live in the Volume and Engine CRs, and the manager reconciles them like it does for rebuild QoS:
1. On every engine monitor refresh, compare `spec.ioLimits` with `status.appliedIoLimits`. If they differ, call the set method and update the status on success.
2. At engine creation, pass the limits in the creation spec so the SPDK engine applies them before exposing the frontend. This removes the unthrottled window after an attach or restart.
3. In the SPDK engine, every code path that deletes and recreates the RAID1 bdev must reapply the limits. The restore flow is one such path (the V2 backup and restore design removes the raid bdev during restore).

#### Failure handling

- If applying a limit fails, the manager records a warning event, leaves status.appliedIoLimits unchanged, and retries on the next refresh. 
- Failure to apply a limit does not fail the attach of the volume, because data availability takes priority over throttling.

### Test plan

#### Unit tests

- Admission webhook: V2 only, negative values, minimum values, StorageClass parameter parsing. 
- Precedence and copy logic from volume spec to engine spec. 
- Engine monitor reconcile: apply when desired differs from applied, no call when equal, retry on failure.

#### Benchmarks

- Compare a volume without limits to one with a very high limit, to measure the cost of enabling QoS, and record the numbers in the PR.

#### Integration tests
TODO

### Upgrade strategy

- The new CRD fields are optional and default to 0, which means unlimited, so existing volumes keep their current behavior after upgrade.
- A V2 engine picks up its limits when it is next created by an instance manager that supports the feature, and the reconcile step applies them to running engines once the instance manager is upgraded.


## Note [optional]

Additional notes.
