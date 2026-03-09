# Orphaned V2 Volume Runtime Resource Cleanup

## Summary

This enhancement extends orphaned runtime cleanup to the v2 data engine. It identifies unmanaged v2 runtime resources on nodes after node offline or rejoin events, exposes them as `orphan` CRs, and supports manual or automatic cleanup through existing orphan workflows.

### Related Issues

[https://github.com/longhorn/longhorn/issues/10933](https://github.com/longhorn/longhorn/issues/10933)

## Motivation

### Goals

- Identify orphaned v2 runtime resources after node offline and rejoin.
- Reuse existing orphan control-plane model (`orphan` CR and orphan controller) to avoid introducing a new CRD family.
- Keep cleanup safe by preserving ownership and state validation before deletion.
- Support manual cleanup and global auto-deletion through existing settings.
- Keep behavior consistent with v1 user experience where possible.

### Non-goals

- Introduce a new host-level data-store scavenging pipeline that bypasses instance deletion.
- Introduce per-node orphan auto-deletion policies.
- Introduce TTL-based orphan deletion policy in this phase.
- Eliminate all race conditions between runtime transitions and control-plane reconciliation.

## Proposal

1. Extend orphan detection to include v2 runtime inventory on each Longhorn node.

2. Reuse `orphan` CR for v2 orphan runtime resources by using existing `orphanType` values (`engine-instance` and `replica-instance`) and `spec.dataEngine = v2`.

3. Extend orphan controller deletion handling to invoke v2 runtime cleanup when the orphan belongs to `dataEngine = v2`.

4. Keep setting behavior unchanged. The existing `orphan-resource-auto-deletion` item `instance` controls auto-deletion for both v1 and v2 runtime instances.

### User Stories

When a Longhorn node is disconnected, v2 volumes may continue lifecycle changes on other nodes. During this time, runtime resources previously created on the disconnected node can become stale. After the node rejoins, these stale runtime resources are no longer owned by active volume CRs and become orphaned.

Orphaned runtime resources consume node resources and can block operations such as node maintenance or runtime restarts. Users need a safe and observable way to detect and clean them up without disruptive manual host actions.

After this enhancement, Longhorn will detect v2 orphan runtime resources, list them as `orphan` CRs, and allow cleanup by UI or `kubectl`, with optional global auto-deletion.

### User Experience In Detail

- Via Longhorn GUI
    - Users can view orphaned runtime instances for `dataEngine = v2` in existing orphan views.
    - Users can delete selected orphan entries.
    - Users can enable global orphan auto-deletion by setting `orphan-resource-auto-deletion` to include `instance`.

- Via `kubectl`
    - Users can list orphan runtime instances by `kubectl -n longhorn-system get orphans`.
    - Users can inspect v2 orphan runtime details in `spec.dataEngine` and `spec.parameters`.
    - Users can delete orphan runtime resources by `kubectl -n longhorn-system delete orphan <name>`.
    - Users can enable or disable global auto-deletion through `kubectl -n longhorn-system edit settings orphan-resource-auto-deletion`.

## Design

### Implementation Overview

- Reuse existing orphan CR lifecycle for v2.
- Use InstanceManagerMonitor as the single inventory truth source for both v1 and v2 instances.
- Create or update orphan CRs when v2 runtime resources are determined to be orphaned.
- Extend orphan controller to clean up v2 runtime resources safely.
- Preserve node controller behavior to clear orphan CRs on node eviction or deletion.

**Settings**

  - Reuse existing setting `orphan-resource-auto-deletion`.
  - Reuse existing item `instance` to control both v1 and v2 runtime orphan auto-deletion.
  - No new setting is introduced in this phase.

**V2 runtime identity mapping**

  - Engine instance identity:
    - Source: RAID bdev UUID for the engine name on the local SPDK node.
    - Scope: valid for one local runtime lifecycle on one node.
    - Change conditions:
      - delete and recreate engine RAID bdev
      - snapshot revert flow that recreates RAID bdev
      - restore flow that recreates RAID bdev
      - expansion flow may preserve UUID only when recreate uses previous UUID explicitly
    - Implication: UUID is runtime identity, not a cross-node permanent volume identity.

  - Replica instance identity:
    - Source: head lvol UUID for the replica.
    - Scope: one replica runtime object (lvol) identity.
    - Requirement: map replica instance UUID from lvol UUID, not from lvstore UUID.
    - Rationale: one lvstore can contain multiple replica lvol objects, so lvstore UUID is not a 1:1 replica identity.

**V2 orphan judgement**

  - Compare each v2 runtime inventory item with corresponding engine or replica CR.
  - If no corresponding CR exists, mark as orphan candidate.
  - If corresponding CR exists:
    - If `status.currentState != spec.desireState`, skip judgement for now.
    - If CR owner is not current node, skip judgement.
    - If CR is `running` and instance manager does not match expected owner on this node, mark as orphan candidate.
    - If CR is `stopped` and runtime inventory still reports the runtime object, mark as orphan candidate.
      - Rationale: `stopped` does not guarantee runtime/SPDK resource deletion.
    - For transient states (`starting`, `stopping`, `unknown`, `error`), skip judgement in current cycle.
  - Convert orphan candidates to orphan CRs, and remove orphan CRs when candidate disappears.

**Orphan CR**

  - Reuse existing `orphan` CRD and finalizer flow.
  - Name format:
    - `orphan-${checksum}`
    - `$checksum = sha256("${runtime_name}-${instance_uuid}-${instance_manager_id}-${data_engine_type}")`
  - labels:
    - `longhorn.io/component`: `orphan`
    - `longhorn.io/managed-by`: `longhorn-manager`
    - `longhorn.io/orphan-type`: `engine-instance` or `replica-instance`
    - `longhornnode`: node ID
  - spec:
    - `spec.dataEngine = v2`
    - `spec.orphanType = engine-instance` or `replica-instance`
    - `spec.parameters["InstanceName"] = runtime name`
    - `spec.parameters["InstanceUUID"] = runtime instance UUID`
    - `spec.parameters["InstanceManager"] = local instance manager name`
  - status condition:
    - Reuse `InstanceState` style condition to track runtime liveness.

**UUID source requirement**

  This enhancement depends on a non-empty and stable v2 instance UUID so that orphan detection and deletion stay safe.

  - Required end-to-end source path:
    - SPDK service MUST populate top-level `Uuid` in `spdkrpc.Replica` and `spdkrpc.Engine` responses.
      - Replica `Uuid` MUST be head lvol UUID.
      - Engine `Uuid` MUST be RAID bdev UUID for the local engine runtime.
    - Instance manager MUST propagate that value to `rpc.InstanceStatus.Uuid` for v2 `InstanceList/Get`.
    - Longhorn manager MUST use `instance.Status.UUID` as `spec.parameters["InstanceUUID"]` when creating orphan CRs.
  - UUID quality requirement:
    - UUID MUST be non-empty for a deletable v2 instance.
    - UUID MUST be stable for the same runtime object lifecycle.
    - UUID MUST represent runtime identity used by delete safety checks.
  - Safety behavior when UUID is unavailable:
    - Skip orphan CR creation for that runtime item in current cycle.
    - Emit warning logs/events for observability.
    - Retry in later monitor cycles after runtime status refresh.
  - Delete-time validation requirement:
    - For v2 `InstanceDelete`, instance manager MUST verify UUID matches the current local runtime object before deletion.
    - Engine delete MUST compare request UUID with current RAID bdev UUID.
    - Replica delete MUST compare request UUID with current head lvol UUID.
    - On mismatch, return a deterministic error and skip deletion.
    - Orphan cleanup MUST request v2 instance deletion with `cleanupRequired = true`.
      - `cleanupRequired = false` is not sufficient for orphan runtime cleanup because it may keep SPDK runtime resources.
  - Release gate:
    - v2 orphan runtime cleanup is not considered complete unless UUID propagation is verified end-to-end.
    - v2 orphan runtime cleanup is not considered complete unless delete-time UUID match validation is implemented and tested.

**Orphan controller**

  Reconciles v2 orphan deletion requests by extending existing orphan controller flow.

  - When `deletionTimestamp` is set and controller owns the orphan CR:
    - If orphan node is not current controller node, remove finalizer.
    - If orphan node is current controller node:
      - Re-check deletability with corresponding engine/replica CR.
      - If runtime is deletable, call v2 runtime cleanup client to remove runtime instance with `cleanupRequired = true`.
      - If runtime no longer exists, remove finalizer directly.
      - If runtime is no longer deletable, remove finalizer and stop deletion flow.

**Longhorn node controller**

  Reuse existing node lifecycle handling:

  - Delete orphan runtime CRs on deleted or evicted node.
  - Behavior applies equally to v1 and v2 orphan runtime CRs.

**Upgrade and compatibility**

  - No CRD schema expansion is required for this phase.
  - Existing clusters can adopt this behavior without changing user workflow.
  - Existing setting `orphan-resource-auto-deletion` behavior remains backward compatible.

### Test Plan

**Integration tests**

- Node offline, v2 volume detached or deleted elsewhere, then node rejoins:
  - orphan CRs are created for stale v2 runtime instances.
  - v2 orphan CRs are created with non-empty `spec.parameters["InstanceUUID"]`.
  - deletion of orphan CR removes corresponding stale instances.
- v2 replica deleted while node offline:
  - stale instances on old node is detected as orphan.
- v2 CR reports `stopped` but stale runtime still exists on node:
  - stale runtime is still detected as orphan (no false assumption that `stopped` means resource deleted).
  - deleting orphan CR removes corresponding stale runtime object.
- Auto deletion enabled (`orphan-resource-auto-deletion` contains `instance`):
  - existing v2 orphan runtime CRs are deleted automatically.
  - newly appeared v2 orphan runtime CRs are deleted automatically.
- Auto deletion disabled:
  - orphan CRs persist until manual deletion.
- Node eviction or node down:
  - orphan runtime CRs on the node are removed following existing node controller behavior.
