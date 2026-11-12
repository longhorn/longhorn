# V2 Volumes IO Control and Throttle

## Summary

Longhorn V2 volumes share node-level CPU, disk, and network resources, allowing a busy volume to starve others. This enhancement introduces per-volume IOPS and bandwidth limits.

### Related Issues

• https://github.com/longhorn/longhorn/issues/9265
• https://github.com/longhorn/longhorn/issues/10770 (replica rebuild QoS, prior fix that this proposal builds on)
• https://github.com/spdk/spdk/issues/3768 (upstream SPDK issue: QoS limits of an idle bdev cannot be changed after the first set, the reason limits can only be changed while a volume is detached, see `Known Limitations`)

## Motivation

A V2 volume is served by one SPDK target (spdk_tgt) per node, shared by all engines and replicas on that node. Nothing currently stops one volume from using a disproportionate share of the node. Typical symptoms are a batch job or database saturating a shared NVMe disk while latency-sensitive volumes on the same node slow down.

SPDK already supports per-bdev rate limiting, and Longhorn already uses it for replica rebuilding. What is missing is a user-facing way to apply it to the application IO of a volume.

### Goals

- Users can set limits on a V2 volume for combined read/write IOPS, combined read/write bandwidth. A value of 0 means unlimited. 
- Limits apply to the IO the respective application issues to the volume, regardless of the number of replicas. 
- Limits can be set at creation time, including through StorageClass parameters. 
- Limits of an existing volume can be changed or removed while the volume is detached. The new limits are applied when the volume is next attached.
- Updating limits for an attached volume are rejected by webhook.
- Limits survive restarts of the instance manager, the SPDK target, and engine recreation. They are reapplied automatically. 
- The applied values are visible to the user in the engine status. 
- The feature is independent of replica rebuild QoS (issue 10770). The two do not overwrite each other. 
- Existing V2 volumes and V1 volumes see no behavior change. The default is unlimited.

### Non-goals [optional]

- Separate read and write bandwidth limits for V2 volumes. Only combined read/write limits are in scope.
- Changing the limits of an attached volume. Changes are rejected until the volume is detached, because of an SPDK issue (see Known limitation). This can be revisited once it is fixed upstream.
- Limits on V1 data engine volumes. 
- Throttling replica rebuild traffic. This is already covered by issue 10770. 
- Per-disk or per-node limits that cap the combined load of all volumes. This can be a separate enhancement with its own design. 
- Limits on individual replicas. 
- Guaranteed minimum performance, priorities, burst credits, or fairness between volumes. Only maximum limits are in scope.

## Proposal

- Add optional IO limit fields to the Volume and StorageClass spec for V2 volumes. 
- The volume controller copies them to the Engine spec, and they are passed to the SPDK engine, which applies them to the volume RAID1 bdev using SPDK's bdev QoS. 
- The limits are applied when the engine is created at attach, before the frontend is exposed. The SPDK engine reapplies them whenever it recreates the RAID1 bdev.
- The limits of an existing volume can only be changed while the volume is detached. The admission webhook rejects a change to an attached volume.

### User Stories

#### Story 1 - Protect other volumes from a noisy neighbor
Before this enhancement, an operator whose analytics volume saturates a shared disk can only move the workload or add hardware. After this enhancement, the operator detaches the volume (for example by scaling the workload down), sets a read-write bandwidth limit and an IOPS limit on it, and attaches it again. From then on, the other volumes on the node keep their latency.

#### Story 2 - Offer performance classes through StorageClass
Before this enhancement, every V2 volume from a StorageClass is unlimited. After this enhancement, a platform team can define a StorageClass named `longhorn-v2-standard` with modest limits and another named `longhorn-v2-fast` with none. Tenants can choose the class when creating a PVC and the limits are applied automatically at provisioning time.

[//]: # (TODO: refinement needed)
### User Experience In Detail

#### Set/Remove limits on an existing volume
The volume must be detached. A change to an attached volume is rejected:
```shell
$ kubectl -n longhorn-system patch volumes.longhorn.io vol-0 --type=merge -p '{"spec": {"qosLimit": {"rwIopsLimit": 5000}}}'
Error from server: admission webhook "validator.longhorn.io" denied the request: spec.qosLimit: qosLimit can only be changed while volume vol-0 is detached
```

- Set the limit on a detached volume:
```shell
$ kubectl -n longhorn-system patch volumes.longhorn.io vol-0 --type=merge -p '{"spec": {"qosLimit": {"rwIopsLimit": 5000, "rwMbytesPerSecondLimit": 100}}}'
```

- Remove the limit from a volume:
```shell
$ kubectl -n longhorn-system patch volumes.longhorn.io vol-0 --type=merge -p '{"spec": {"qosLimit": {"rwIopsLimit": 0, "rwMbytesPerSecondLimit": 0}}}'
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
  qosLimit:
    rwIopsLimit: 0
    rwMbytesPerSecondLimit: 0
```
- `Engine CRD`: the same qosLimit structure in `spec`, copied from the volume by the volume controller. A new `status.appliedQosLimit` structure reflects the limits the SPDK engine reports as enforced on the volume. It is 0 while the engine is not running.
- `StorageClass parameters`: rwIopsLimit, rwMbytesPerSecondLimit.
- `Longhorn REST API and UI`: the volume resource exposes the same fields. Updating them goes through the normal volume update path, so it is subject to the same validation, and the UI only allows editing them while the volume is detached.
- `Validation (admission webhook)`:
  • Reject non-zero limits on volumes that are not V2.
  • Reject negative values.
  • Reject `rwIopsLimit` values that are not a multiple of 1000. SPDK does not reject such values but rounds them up, so the enforced limit would never match the requested one.
  • Reject a change to `spec.qosLimit` on an existing volume unless the volume is detached. This includes adding limits to a volume created without them, and removing limits by setting them to 0. Setting the limits when the volume is created is always allowed.
- `Instance manager gRPC`: the engine instance creation spec carries the two values, and the instance status reports the limits the engine enforces.
- `SPDK engine`: the engine creation spec gets the two values so limits can be applied before the frontend is exposed, and the engine status reports the limits enforced.
- `Global settings`: cluster-wide defaults, follow the same precedence as rebuild QoS. Precedence is resolved per field, so `rwIopsLimit` and `rwMbytesPerSecondLimit` are each resolved independently against their own global setting:
  | Global Setting | Field in `volume.spec.qosLimit` | Behavior |
  |---|---|---|
  | Not `0` | `0` | Respect the global setting |
  | `0` | Not `0` | Respect the per-volume setting |
  | Not `0` | Not `0` | Respect the per-volume setting |
  | `0` | `0` | No limit |

  Because `0` means "not set" on the volume, a volume cannot opt out of a non-zero global setting. It can only override it with its own non-zero value. A global setting cannot be tied to the state of individual volumes, so a change to it is allowed at any time and applies to each volume when it is next attached. Until then, an attached volume keeps the limits it was attached with, visible in `status.appliedQosLimit`.

## Design

### Implementation Overview

#### Where the limit is applied

- The limit is applied to the `RAID1 bdev` that the SPDK engine builds for each volume. 
- In the V2 architecture:
  - a remote replica is an NVMe-oF subsystem with an lvol behind it, 
  - a local replica is an lvol, 
  - and the engine backend is a RAID1 bdev over those. 
The frontend (NVMe-oF/kernel nvme-tcp, or ublk) consumes the RAID1 bdev, so a limit there covers every frontend.
- Volumes using the sharded (erasure coded) data layout are covered the same way, as their engine also builds a RAID1 bdev, over the shard group.

#### Caveats

The limits count the IO the application issues to the volume, not the IO that reaches the replicas. Every write is sent to all replicas, while a read is served by one, so a bandwidth limit of `x` MB/s can still result in up to `x` multiplied by the `number of replicas` MB/s of writes across the cluster. Documentation must state this so administrators choose values accordingly.

#### Known limitation: changing limits on an idle RAID1 bdev

Changing the QoS limits of a bdev that already has limits, but has no open IO channel on it, is refused by SPDK with `Failed to configure rate limit: Resource temporarily unavailable`. This is reported upstream as [spdk/spdk#3768](https://github.com/spdk/spdk/issues/3768) (open as of 2026-11-03).

Observed behavior:
- In the `longhorn-spdk-engine` integration test, on an engine without a frontend:
  - the limits applied when the RAID1 bdev is created succeed, both at engine creation and after a snapshot revert recreates the RAID1 bdev;
  - every later change is refused, including retries by the SPDK engine's periodic validation over about 15 seconds. The engine stays running and the RAID1 bdev is not recreated in that time.
- The upstream issue reproduces the same with a plain SPDK malloc bdev on SPDK 25.09: the first `bdev_set_qos_limit` succeeds and the second fails. It also reports that the change succeeds while the bdev is in use by a client.

Impact on this enhancement:
- Because the limits of an existing RAID1 bdev cannot be changed reliably, the limits are applied only when the RAID1 bdev is created: at engine creation, and when the SPDK engine recreates the RAID1 bdev (snapshot revert, volume expansion). Both are the first set on a new bdev, which works.
- The limits of an existing volume can only be changed while it is detached, so the new limits are again the first set on the RAID1 bdev created at the next attach. The upstream report observes that a change succeeds while the bdev is in use, so changes to attached volumes can be revisited once the SPDK behavior is fixed or confirmed safe for this case.

The fix belongs in SPDK. Longhorn tracks the upstream issue, and can carry a patch in its SPDK fork if the fix is not available upstream in time.

#### Changing limits only while detached

Allowing changes only while a volume is detached affects the components as follows:
- **Admission webhook**: rejects a change to `spec.qosLimit` on an existing volume unless `status.state` is `detached`, whether it adds, changes, or removes (sets to 0) a limit. A volume that is attaching or detaching is treated as attached. Setting the limits at volume creation, including from StorageClass parameters, is not affected.
- **UI and REST API**: the IO limit fields are editable at volume creation and while the volume is detached. For an attached volume, the UI shows them as read-only with a hint to detach the volume first, and the REST API returns the webhook error.
- **Volume and engine controllers**: there is no runtime update. The volume controller copies `spec.qosLimit` to the engine spec, and the limits reach the SPDK engine only in the engine instance creation request at attach.
- **Instance manager and SPDK engine**: no runtime update method is needed. The proxy method and the SPDK engine runtime update method for QoS limits are not part of this enhancement.
- **Global settings**: cannot be gated on individual volumes, so a change applies at each volume's next attach, as described in the API changes.
- **Documentation**: states that limits are set at creation or while detached, and how to apply a change to a running workload (detach, change, attach).

#### Changes by repository

- **longhorn/longhorn-manager**:
  - Volume and Engine CRD fields and generated code, 
  - admission validation, including rejecting changes to `spec.qosLimit` unless the volume is detached, 
  - StorageClass parameter parsing, 
  - volume controller copying `spec.qosLimit` to the engine, 
  - passing the limits in the engine instance creation request, 
  - reading the applied limits from the instance status into `status.appliedQosLimit`, 
  - REST API types.
- **longhorn/types**: 
  - gRPC definitions for the limits in the engine creation spec and in the engine and instance status.
- **longhorn/longhorn-instance-manager**: 
  - passing the values in the engine creation spec, and reporting the applied limits in the instance status.
- **longhorn/longhorn-spdk-engine**: 
  - store the limits on the Engine object, apply them right after the RAID1 bdev is created and before the frontend is exposed, and reapply them after any flow that recreates the RAID1 bdev.
- **longhorn/go-spdk-helper**: no change. 
  - The wrapper for SPDK's bdev QoS already exists. Setting every limit to 0 disables QoS on the bdev.
- **longhorn/longhorn-ui**: 
  - IO limits fields on the volume create page, and on the volume detail page editable only while the volume is detached.

#### Keeping the limit in place

SPDK keeps QoS settings only in the memory of the running `spdk_tgt` process. The desired limits therefore live in the Volume and Engine CRs, and are applied to every new RAID1 bdev:
1. At engine creation, pass the limits in the creation spec so the SPDK engine applies them before exposing the frontend. This covers every attach, and restarts of the instance manager or the SPDK target, since both recreate the engine.
2. In the SPDK engine, every code path that deletes and recreates the RAID1 bdev must reapply the limits. Today these paths are snapshot revert and volume expansion.
3. As a safety net for those paths, the SPDK engine periodically compares the limits enforced on the RAID1 bdev with the requested ones, and reapplies them when they differ. This periodic validation is the only place the SPDK engine retries; no other path retries inline.
4. The engine status reports the limits enforced, which the manager copies to `status.appliedQosLimit`. The manager never changes the limits of a running engine; the webhook keeps `spec.qosLimit` of an attached volume unchanged.

#### Failure handling

- At engine creation, a failure to apply the limits fails the engine creation. The RAID1 bdev is not exposed yet, so failing is safer than serving IO without the requested limits. Invalid values are rejected earlier by the admission webhook.
- The exception is SPDK still processing a previous QoS change on the new RAID1 bdev. This is temporary and does not fail the engine creation. The SPDK engine's periodic validation applies the limits shortly after, so the volume can briefly serve IO without them.
- After the RAID1 bdev is recreated (snapshot revert, volume expansion), a failure to reapply the limits does not fail the operation. The volume stays usable, and the SPDK engine's periodic validation retries.

### Test plan

#### Unit tests

- Admission webhook: V2 only, negative values, IOPS multiple of 1000, StorageClass parameter parsing, limits accepted at volume creation, changes accepted on a detached volume, and changes rejected on an attached, attaching, or detaching volume. 
- Precedence and copy logic from volume spec to engine spec. 
- Engine instance creation request carries the limits, and `status.appliedQosLimit` follows the instance status.

#### Benchmarks

- Compare a volume without limits to one with a very high limit, to measure the cost of enabling QoS, and record the numbers in the PR.

#### Integration tests

- `longhorn-spdk-engine`: create an engine with limits and verify they are enforced on the RAID1 bdev and reported in the engine status, then verify they are still enforced after a snapshot revert recreates the RAID1 bdev.
- `longhorn-spdk-engine`: recreate the engine with different limits, and with no limits, and verify the new limits are enforced, as happens when a volume changed while detached is attached again.
- `longhorn-tests` (end to end): change the limits of a detached volume, attach it, and verify the new limits in `status.appliedQosLimit`; verify the change is rejected while the volume is attached.

### Upgrade strategy

- The new CRD fields are optional and default to 0, which means unlimited, so existing volumes keep their current behavior after upgrade.
- Limits can be added to an existing volume after upgrade while it is detached, and are applied when it is next attached by an instance manager that supports the feature. Engines already running at upgrade keep running without limits.


## Note [optional]

Additional notes.
