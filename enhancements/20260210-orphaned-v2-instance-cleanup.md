# Orphaned V2 Volume Runtime Resource Cleanup

## Summary

This enhancement extends orphaned runtime cleanup to two v2 data engine resource categories:

1. **V2 engine instances**: unmanaged SPDK RAID bdev engines on nodes after node offline or rejoin events.
2. **V2 engine frontend instances**: stale host-level initiator resources (NVMe/TCP sessions, dm-linear devices, ublk devices) left behind when an `EngineFrontend` CR is removed while the node is offline.

Both categories are exposed as `orphan` CRs and support manual or automatic cleanup through existing orphan workflows.

### Related Issues

[https://github.com/longhorn/longhorn/issues/10933](https://github.com/longhorn/longhorn/issues/10933)

## Motivation

### Goals

- Identify orphaned v2 engine instances after node offline and rejoin.
- Identify orphaned v2 engine frontend instances after node offline and rejoin.
- Reuse existing orphan control-plane model (`orphan` CR and orphan controller) to avoid introducing a new CRD family.
- Keep cleanup safe by preserving ownership and state validation before deletion.
- Support manual cleanup and global auto-deletion through existing settings.
- Keep behavior consistent with v1 user experience where possible.

### Non-goals

- **Orphaned v2 replica instances**: already covered by the existing disk monitoring mechanism. The `DiskMonitor` calls `DiskReplicaInstanceList` to enumerate all replicas tracked in the SPDK server's `replicaMap`, cross-references them against Replica CRs, and creates `OrphanTypeReplicaData` orphan CRs for any replica with no corresponding CR. Cleanup calls `DiskReplicaInstanceDelete` with `cleanupRequired=true`, which removes both the head lvol and all trackable snapshot lvols atomically. No additional handling is required in this design.
- **Orphaned v2 snapshot chains (untrackable lvols)**: snapshot lvols that remain in an lvstore after the replica head has already been removed are invisible to `ReplicaList()` because the SPDK server's `verify()` loop explicitly skips lvols with `Snapshot=true` during untracked-lvol discovery. Cleanup of these broken chains is deferred to a separate design.
- Introduce a new host-level data-store scavenging pipeline that bypasses instance deletion.
- Introduce per-node orphan auto-deletion policies.
- Introduce TTL-based orphan deletion policy in this phase.
- Eliminate all race conditions between runtime transitions and control-plane reconciliation.

## Proposal

1. Extend orphan detection to include v2 engine instance inventory on each Longhorn node.

2. Reuse `orphan` CR for v2 orphan engine instances by using the existing `orphanType` value `engine-instance` and `spec.dataEngine = v2`.

3. Extend orphan controller deletion handling to invoke v2 engine runtime cleanup when the orphan belongs to `dataEngine = v2`.

4. Extend instance-manager with two new RPCs: `EngineFrontendInstanceList` and `EngineFrontendInstanceDelete`, to enumerate and remove orphaned v2 engine frontend resources on the host.

5. Extend orphan detection in `InstanceManagerMonitor` to include v2 engine frontend instances using the new RPCs.

6. Introduce a new `orphanType` value `engine-frontend` in the `orphan` CRD for orphaned engine frontend instances.

7. Extend orphan controller deletion handling to invoke `EngineFrontendInstanceDelete` when the orphan type is `engine-frontend`.

8. Keep setting behavior unchanged. The existing `orphan-resource-auto-deletion` item `instance` controls auto-deletion for both engine instances and engine frontend instances.

### User Stories

**Engine instance orphan**: When a Longhorn node is disconnected, v2 volumes may continue lifecycle changes on other nodes. Engine instances previously created on the disconnected node can become stale. After the node rejoins, these stale engine instances are no longer owned by active volume CRs and become orphaned. They consume node resources and can block operations such as node maintenance or runtime restarts.

**Engine frontend orphan**: When a Longhorn node is disconnected while a v2 volume is attached, an `EngineFrontend` CR may be removed (or moved) on other nodes. After rejoin, the original node still holds live host-level initiator resources (NVMe/TCP controller sessions, dm-linear devices, or ublk devices). These resources are not reclaimed automatically and can prevent clean volume attach operations or consume kernel resources indefinitely.

After this enhancement, Longhorn will detect both categories of v2 orphans, list them as `orphan` CRs, and allow cleanup by UI or `kubectl`, with optional global auto-deletion.

### User Experience In Detail

- Via Longhorn GUI
  - Users can view orphaned engine instances and orphaned engine frontend instances for `dataEngine = v2` in existing orphan views.
  - Users can delete selected orphan entries.
  - Users can enable global orphan auto-deletion by setting `orphan-resource-auto-deletion` to include `instance`.
- Via `kubectl`
  - Users can list orphans by `kubectl -n longhorn-system get orphans`.
  - Users can inspect v2 engine orphan details in `spec.dataEngine` and `spec.parameters`.
  - Users can delete orphans by `kubectl -n longhorn-system delete orphan <name>`.
  - Users can enable or disable global auto-deletion through `kubectl -n longhorn-system edit settings orphan-resource-auto-deletion`.

## Design

### Implementation Overview

- Reuse existing orphan CR lifecycle for v2 engine instances (reuses `engine-instance` orphan type).
- Add new `engine-frontend` orphan type for v2 engine frontend instances.
- Use `InstanceManagerMonitor` as the single inventory truth source for both v2 engine instances and v2 engine frontend instances.
- Add two new RPCs to instance-manager for engine frontend inventory and deletion.
- Create or update orphan CRs when v2 instances or frontend instances are determined to be orphaned.
- Extend orphan controller to clean up v2 engine instances and v2 engine frontend instances safely.
- Preserve node controller behavior to clear orphan CRs on node eviction or deletion.

**Settings**

- Reuse existing setting `orphan-resource-auto-deletion`.
- Reuse existing item `instance` to control auto-deletion for engine instances and engine frontend instances.
- No new setting is introduced in this phase.

---

### Part 1: V2 Engine Instance Orphan

**V2 engine instance identity**

- Source: RAID bdev UUID for the engine name on the local SPDK node.
- Scope: valid for one local runtime lifecycle on one node.
- Change conditions:
  - delete and recreate engine RAID bdev
  - snapshot revert flow that recreates RAID bdev
  - restore flow that recreates RAID bdev
  - expansion flow may preserve UUID only when recreate uses previous UUID explicitly
- Implication: UUID is runtime identity, not a cross-node permanent volume identity.

**V2 orphan judgement**

- Compare each v2 engine instance in the runtime inventory with the corresponding Engine CR.
- If no corresponding Engine CR exists, mark as orphan candidate.
- If corresponding Engine CR exists:
  - If `status.currentState != spec.desireState`, skip judgement for now.
  - If CR owner is not current node, skip judgement.
  - If CR is `running` and instance manager does not match expected owner on this node, mark as orphan candidate.
  - If CR is `stopped` and runtime inventory still reports the engine instance, mark as orphan candidate.
    - Rationale: `stopped` does not guarantee SPDK RAID bdev deletion.
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
  - `longhorn.io/orphan-type`: `engine-instance`
  - `longhornnode`: node ID
- spec:
  - `spec.dataEngine = v2`
  - `spec.orphanType = engine-instance`
  - `spec.parameters["InstanceName"] = runtime name`
  - `spec.parameters["InstanceUUID"] = runtime instance UUID`
  - `spec.parameters["InstanceManager"] = local instance manager name`
- status condition:
  - Reuse `InstanceState` style condition to track runtime liveness.

**UUID source requirement**

This enhancement depends on a non-empty and stable v2 engine instance UUID so that orphan detection and deletion stay safe.

- Required end-to-end source path:
  - SPDK service MUST populate top-level `Uuid` in `spdkrpc.Engine` responses.
    - Engine `Uuid` MUST be the RAID bdev UUID for the local engine runtime.
  - Instance manager MUST propagate that value to `rpc.InstanceStatus.Uuid` for v2 `InstanceList/Get`.
  - Longhorn manager MUST use `instance.Status.UUID` as `spec.parameters["InstanceUUID"]` when creating orphan CRs.
- UUID quality requirement:
  - UUID MUST be non-empty for a deletable v2 engine instance.
  - UUID MUST be stable for the same runtime object lifecycle.
  - UUID MUST represent the runtime identity used by delete safety checks.
- Safety behavior when UUID is unavailable:
  - Skip orphan CR creation for that runtime item in current cycle.
  - Emit warning logs/events for observability.
  - Retry in later monitor cycles after runtime status refresh.
- Delete-time validation requirement:
  - For v2 `InstanceDelete`, instance manager MUST verify UUID matches the current local runtime object before deletion.
  - Engine delete MUST compare request UUID with current RAID bdev UUID.
  - On mismatch, return a deterministic error and skip deletion.
  - Orphan cleanup MUST request v2 instance deletion with `cleanupRequired = true`.
    - `cleanupRequired = false` is not sufficient for orphan engine cleanup because it may leave SPDK RAID bdev and NVMe frontend resources behind.
- Release gateki
  - v2 orphan engine instance cleanup is not considered complete unless UUID propagation is verified end-to-end.
  - v2 orphan engine instance cleanup is not considered complete unless delete-time UUID match validation is implemented and tested.

**Orphan controller**

Reconciles v2 orphan deletion requests by extending existing orphan controller flow.

- When `deletionTimestamp` is set and controller owns the orphan CR:
  - If orphan node is not current controller node, remove finalizer.
  - If orphan node is current controller node:
    - Re-check deletability with corresponding Engine CR.
    - If engine instance is deletable, call v2 runtime cleanup client to remove the engine instance with `cleanupRequired = true`.
    - If engine instance no longer exists, remove finalizer directly.
    - If engine instance is no longer deletable, remove finalizer and stop deletion flow.

---

### Part 2: V2 Engine Frontend Instance Orphan

**Background: V2 engine frontend types**

A v2 engine frontend is the host-side initiator that exposes the SPDK engine's RAID bdev as a block device to workloads. Three frontend types exist, each leaving distinct host resources when orphaned:

| Frontend type       | Constant                  | Host resources created                                                                     | Orphan footprint                                |
| ------------------- | ------------------------- | ------------------------------------------------------------------------------------------ | ----------------------------------------------- |
| `spdk-tcp-nvmf`     | `FrontendSPDKTCPNvmf`     | NVMe/TCP controller session. Endpoint = `nvmf://<ip>:<port>/<NQN>`. No dm device.          | Stale NVMe-TCP controller session keyed by NQN. |
| `spdk-tcp-blockdev` | `FrontendSPDKTCPBlockdev` | NVMe/TCP controller session + dm-linear device at `/dev/longhorn/<engine-name>`.           | Stale NVMe-TCP session and dm-linear device.    |
| `ublk`              | `FrontendUBLK`            | ublk device (integer ID) + dm-linear device at `/dev/longhorn/<engine-name>`. No NVMe/TCP. | Stale ublk device and dm-linear device.         |

NQN format: `nqn.2023-01.io.longhorn.spdk:<engine-name>` (from `types.GetNQN(engineName)` in `go-spdk-helper`). The engine name is directly embedded and is stable per engine lifecycle.

The `EngineFrontend` CRD (introduced in a companion design) represents the lifecycle of these frontend instances. Each `EngineFrontend` CR holds `spec.engineName`, `spec.nodeID`, and `spec.frontend`, which are the cross-reference keys for orphan judgement.

**Monitoring scope**

Engine frontend resources belong to the node, not to any specific IM. During a system upgrade, multiple v2 IMs may coexist on the same node sharing one SPDK daemon and observing the same set of kernel-level frontend resources. Because the orphan CR name checksum is node-scoped (node ID, not IM name), concurrent attempts by multiple IMs to create an orphan CR for the same resource produce at most one CR. Kubernetes create is atomic; subsequent creates from other IMs return "already exists" and are treated as no-ops by the monitor.

**New instance-manager RPCs**

Two new RPCs are required because instance-manager does not currently enumerate active v2 engine frontend resources on the host.

`EngineFrontendInstanceList`:

- Enumerates all active Longhorn v2 engine frontend instances on the local node by reading kernel-level state in the host namespace.
- SPDK-internal APIs such as `ublk_get_disks` are NOT used for detection. They reflect only the live SPDK process and cannot see resources left by a previous SPDK session after an IM pod restart.
- For NVMe-TCP frontends (`spdk-tcp-nvmf`, `spdk-tcp-blockdev`):
  - Parses `nvme list-subsys -o json` output (kernel NVMe subsystem state, persists across SPDK restarts).
  - Filters subsystems with NQN prefix `nqn.2023-01.io.longhorn.spdk:`.
  - Extracts engine name from NQN suffix.
  - Records transport address (IP) and transport service ID (port) for each session.
- For ublk frontends:
  - Scans `/sys/bus/ublk/devices/` in the host namespace (persists across SPDK restarts).
  - Matches the bdev name attribute of each ublk device against the Longhorn engine naming pattern.
- Returns a list of `EngineFrontendInstanceStatus` structs per active frontend:
  - `EngineName`: engine name (from NQN suffix or ublk bdev name attribute)
  - `Frontend`: frontend type constant
  - `NQN`: populated for NVMe-TCP frontends
  - `TargetIP`, `TargetPort`: populated for NVMe-TCP frontends
  - `UblkID`: populated for ublk frontends
  - `HasDmDevice`: whether a dm-linear device at `/dev/longhorn/<engine-name>` exists

`EngineFrontendInstanceDelete`:

- Removes a specific engine frontend instance from the host.
- Input: engine name, frontend type, NQN (for NVMe-TCP), UblkID (for ublk).
- For `spdk-tcp-nvmf`: runs `nvme disconnect --nqn <NQN>`.
- For `spdk-tcp-blockdev`: runs `dmsetup remove <engine-name>`, then `nvme disconnect --nqn <NQN>`.
- For `ublk`: stops the ublk device via the sysfs control interface or `ublk` CLI, then runs `dmsetup remove <engine-name>`.
- Deletion is idempotent: if the resource no longer exists, return success.

**V2 engine frontend instance identity and UUID**

The NQN embeds the engine name and is deterministic for the lifetime of the frontend session. UUID is computed in longhorn-manager from the inventory returned by `EngineFrontendInstanceList`. No new UUID propagation pipeline through SPDK or IM is required.

- For NVMe-TCP frontends:
  - Identity key: `NQN` = `nqn.2023-01.io.longhorn.spdk:<engine-name>`
  - UUID: `DeterministicUUID(NQN)` using the existing `util.DeterministicUUID` helper.
- For ublk frontends:
  - Identity key: `engineName` and `UblkID`.
  - UUID: `DeterministicUUID(engineName + "|" + strconv.Itoa(UblkID))`.

The orphan CR name checksum is node-scoped to prevent collisions when the same engine name exists on different nodes, and to allow any v2 IM on the node to create it without producing duplicates:

- `$checksum = sha256("${engine_name}-${instance_uuid}-${node_id}-v2")`

**V2 engine frontend orphan judgement**

Performed by every v2 IM monitor on the node after calling `EngineFrontendInstanceList`. Mirrors the stable-state guard from the v1 orphan runtime design to avoid false positives during state transitions. Because the orphan CR name checksum is node-scoped, multiple IMs racing to create the CR for the same resource produce at most one CR.

- For each active frontend instance returned:
  - Extract engine name from NQN suffix or ublk bdev name attribute.
  - Look up `EngineFrontend` CRs with `spec.nodeID == currentNode` and `spec.engineName == engineName`.
  - If no matching `EngineFrontend` CR exists: mark as orphan candidate.
  - If matching CR exists:
    - If `status.currentState != spec.desiredState`: skip (state is in transition; ownership may change).
    - If `status.currentState == running`:
      - If `spec.nodeID != currentNode`: skip (not owned by this node).
      - If `spec.instanceManager != currentIM`: skip (actively managed by a different IM on this node).
      - If `spec.nodeID == currentNode` and `spec.instanceManager == currentIM`: not orphaned.
    - If `status.currentState == stopped`: mark as orphan candidate.
      - Rationale: the frontend belongs to the host, not to any IM. Any v2 IM on the node may make this judgement. `stopped` does not guarantee host-level resource cleanup.
    - For other states (`starting`, `stopping`, `error`, `unknown`): skip (unstable state).
- Convert orphan candidates to orphan CRs, and remove orphan CRs when the candidate disappears from the inventory or when the corresponding `EngineFrontend` CR transitions back to a running state on this node.

**Orphan CR**

- New `orphanType` value: `engine-frontend` (add to `orphan.go` alongside `engine-instance`).
- Name format:
  - `orphan-${checksum}`
  - `$checksum = sha256("${engine_name}-${instance_uuid}-${node_id}-v2")` (see identity section above; node-scoped, no IM name)
- labels:
  - `longhorn.io/component`: `orphan`
  - `longhorn.io/managed-by`: `longhorn-manager`
  - `longhorn.io/orphan-type`: `engine-frontend`
  - `longhornnode`: node ID
- spec:
  - `spec.dataEngine = v2`
  - `spec.orphanType = engine-frontend`
  - `spec.parameters["InstanceName"] = engine name`
  - `spec.parameters["InstanceUUID"] = deterministic UUID`
  - `spec.parameters["Frontend"] = frontend type constant`
  - `spec.parameters["NQN"] = NQN` (populated for NVMe-TCP frontends)
  - `spec.parameters["TargetIP"] = IP` (populated for NVMe-TCP frontends)
  - `spec.parameters["TargetPort"] = port` (populated for NVMe-TCP frontends)
  - `spec.parameters["UblkID"] = integer string` (populated for ublk frontends)

**Orphan controller**

Extends the orphan controller to handle `engine-frontend` orphan type.

- When `deletionTimestamp` is set and controller owns the orphan CR:
  - If orphan node is not current controller node, remove finalizer.
  - If orphan node is current controller node:
    - Re-check whether the frontend resource still exists by calling `EngineFrontendInstanceList` and matching on `InstanceName` and `InstanceUUID`.
    - If frontend resource still exists and no running `EngineFrontend` CR owns it:
      - Look up the default v2 IM on `spec.nodeID`.
      - Call `EngineFrontendInstanceDelete` on that IM with the frontend parameters from the orphan CR.
      - Because `EngineFrontendInstanceDelete` performs host-level operations (`nvme disconnect`, `dmsetup remove`, sysfs writes) that are not scoped to a specific IM, any running v2 IM on the node is suitable for routing the call.
    - If frontend resource no longer exists, remove finalizer directly.
    - If a running `EngineFrontend` CR now owns the resource (transient ownership reclaim), remove finalizer and stop deletion flow.

**Longhorn node controller**

Reuse existing node lifecycle handling:

- Delete orphan runtime CRs (including `engine-frontend` type) on deleted or evicted node.
- Behavior applies equally to v1 and v2 orphan runtime CRs.

**Upgrade and compatibility**

- CRD schema expansion required: add `engine-frontend` constant to `OrphanType` in `orphan.go`.
- No change to existing `orphan` CRD structural schema.
- Existing clusters can adopt this behavior without changing user workflow.
- Existing setting `orphan-resource-auto-deletion` behavior remains backward compatible.

### Test Plan

**Integration tests: V2 engine instance**

- Node offline, v2 volume detached or deleted elsewhere, then node rejoins:
  - orphan CRs are created for stale v2 engine instances.
  - v2 orphan CRs are created with non-empty `spec.parameters["InstanceUUID"]`.
  - deletion of orphan CR removes corresponding stale engine instance.
- v2 engine moved or deleted while node offline:
  - stale engine RAID bdev on old node is detected as orphan after rejoin.
- v2 Engine CR reports `stopped` but stale RAID bdev still exists on node:
  - stale engine instance is still detected as orphan (no false assumption that `stopped` means SPDK resource deleted).
  - deleting orphan CR removes corresponding stale engine instance.
- Auto deletion enabled (`orphan-resource-auto-deletion` contains `instance`):
  - existing v2 orphan engine CRs are deleted automatically.
  - newly appeared v2 orphan engine CRs are deleted automatically.
- Auto deletion disabled:
  - orphan CRs persist until manual deletion.
- Node eviction or node down:
  - orphan runtime CRs on the node are removed following existing node controller behavior.

**Integration tests: V2 engine frontend instance**

- Node offline, corresponding `EngineFrontend` CR removed or moved elsewhere, then node rejoins:
  - orphan CRs of type `engine-frontend` are created for each stale frontend resource (`spdk-tcp-nvmf`, `spdk-tcp-blockdev`, `ublk`).
  - orphan CRs contain non-empty `spec.parameters["InstanceUUID"]`.
  - orphan CRs contain correct `spec.parameters["Frontend"]` and type-specific parameters (NQN, TargetIP, TargetPort, or UblkID).
  - deletion of orphan CR removes corresponding stale host resource (NVMe-TCP session, dm device, ublk device).
- `EngineFrontend` CR reports `stopped` but stale frontend resource still exists on node:
  - stale frontend resource is still detected as orphan.
  - deleting orphan CR removes corresponding stale host resource.
- Auto deletion enabled:
  - existing v2 engine frontend orphan CRs are deleted automatically.
  - newly appeared v2 engine frontend orphan CRs are deleted automatically.
- Auto deletion disabled:
  - engine frontend orphan CRs persist until manual deletion.
- Node eviction or node down:
  - engine frontend orphan CRs on the node are removed following existing node controller behavior.
- Active `EngineFrontend` ownership reclaim (transient):
  - if a `EngineFrontend` CR transitions to `running` before orphan deletion completes, orphan controller removes finalizer without calling delete and stops the deletion flow.
