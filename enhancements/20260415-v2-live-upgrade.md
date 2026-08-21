# V2 Live Upgrade

## Summary

Support for live upgrading v2 data engine instance managers across the cluster without detaching volumes. This enables users to upgrade Longhorn v2 components while minimizing I/O interruption.

### Related Issues

- https://github.com/longhorn/longhorn/issues/9104

## Motivation

- Promote Longhorn Engine v2 from experimental to production-ready by implementing critical operational capabilities
- Enable rolling upgrades for v2 volumes without volume detachment

### Goals

- Allow users to upgrade v2 instance managers without detaching volumes while minimizing I/O interruption
- Orchestrate rolling upgrades across all cluster nodes one-at-a-time to minimize risk
- Automatically relocate engines to temporary nodes during upgrade and restore them afterward
- Provide clear visibility into upgrade progress, failures, and retry status
- Support both immediate and scheduled upgrades

### Non-goals

- Upgrading v1 engine instance managers (existing upgrade mechanism remains unchanged)
- Cross-version data engine upgrades (v1 ↔ v2 migration)
- Upgrading engine images for individual volumes (this focuses on instance manager infrastructure)

### Scope and Constraints

**What is upgraded:**
- Only **v2 data engine** instance managers of type **AllInOne** (not APIServer or share managers)
- Instance manager pod images are upgraded cluster-wide in a rolling fashion

**What is NOT upgraded:**
- V1 data engine instance managers (use existing v1 upgrade mechanism)
- Instance manager types other than AllInOne
- Engine images for individual volumes
- Share manager pods (NFS/SMB for RWX volumes)

## Proposal

### User Stories

As a Longhorn administrator, I want to:
- Upgrade v2 instance managers to a newer version without taking down volumes
- Schedule upgrades during maintenance windows to minimize risk
- Monitor upgrade progress and identify failed nodes
- Retry failed upgrades without manual intervention

As a workload owner, I want:
- My v2 volumes to remain available during Longhorn upgrades
- Upgrade orchestration to avoid detaching volumes and minimize I/O interruption during the upgrade process

### API changes

Two new Custom Resource Definitions are introduced:

#### (1) InstanceManagerUpgrade

Tracks the live upgrade of a single v2 instance manager on one node. Manages temporary engine relocation, planned replica detachment, and restoration.

```yaml
apiVersion: longhorn.io/v1beta2
kind: InstanceManagerUpgrade
metadata:
  name: node-1-upgrade-abc123
  namespace: longhorn-system
spec:
  nodeID: node-1
  targetImage: "longhornio/longhorn-instance-manager:v1.8.0"
status:
  state: "relocating-engines"  # pending, relocating-engines, waiting-for-source-im, restoring-engines, waiting-for-healthy-volumes, completed, failed
  engines:
    vol-1:
      originalNodeID: node-1
      temporaryNodeID: node-2
  plannedDetachedReplicas:
    vol-1:
      - name: "vol-1-r-abcd1234"
        address: "10.42.0.5:10000"  # Prefixed with "detached:" after ReplicaRemove is applied
  startedAt: "2026-04-15T10:00:00Z"
  abortRequested: false
  abortReason: ""
  errorMsg: ""
```

#### (2) InstanceManagerUpgradeControl

Singleton resource that orchestrates rolling upgrades across all cluster nodes. Ensures one-node-at-a-time progression.

```yaml
apiVersion: longhorn.io/v1beta2
kind: InstanceManagerUpgradeControl
metadata:
  name: longhorn-instance-manager-upgrade-control
  namespace: longhorn-system
spec:
  targetImage: "longhornio/longhorn-instance-manager:v1.8.0"
  startAt: "2026-04-15T22:00:00Z"  # RFC3339, optional scheduled start
status:
  currentNode: "node-1"  # Node actively being upgraded (only one at a time)
  nodes:
    node-1:
      state: "in-progress"  # pending, in-progress, completed, failed
      imuName: "node-1-upgrade-abc123"
      retryCount: 0
      startedAt: "2026-04-15T10:00:00Z"
      completedAt: null
      errorMsg: ""
    node-2:
      state: "pending"
      imuName: ""
      retryCount: 0
      startedAt: null
      completedAt: null
      errorMsg: ""
    # Note: node-3 already running target image, so it's not included in the upgrade cycle
```

### Settings

Three new settings are introduced to control the v2 live upgrade behavior:

#### (1) Allow V2 Instance Manager Automatic Upgrade

- **Name**: `allow-v2-instance-manager-automatic-upgrade`
- **Type**: Boolean
- **Default**: `false`
- **Category**: General
- **Description**: This setting allows Longhorn to automatically upgrade V2 instance managers after Longhorn manager is upgraded. During the live upgrade, Longhorn may temporarily relocate engines, detach replicas from engines, and trigger replica rebuilding. When disabled, Longhorn does not automatically upgrade V2 instance managers, and existing V2 instance managers remain on the current image. If this setting is disabled while an automatic V2 instance manager upgrade is in progress, Longhorn allows the current node upgrade to finish but does not start upgrades on additional nodes.

**Important**: This is the master toggle for the v2 live upgrade feature. The upgrade will only begin if this setting is enabled.

#### (2) V2 Instance Manager Upgrade Start Time

- **Name**: `v2-instance-manager-upgrade-start-time`
- **Type**: String (RFC3339 format)
- **Default**: `""` (empty - starts immediately)
- **Category**: General
- **Description**: Specifies when the rolling upgrade of V2 instance managers should begin. This provides flexibility for scheduling the upgrade at a preferred time. If empty, the upgrade starts immediately when the InstanceManagerUpgradeControl CR is reconciled. This setting is the supported scheduling input; `InstanceManagerUpgradeControl.Spec.StartAt` is reconciled from it until the upgrade starts. Updates to this setting are rejected while an upgrade is actively in progress.

**Format**: RFC3339 timestamp (e.g., `2026-04-20T15:00:00Z`)

#### (3) V2 Instance Manager Upgrade Timeout

- **Name**: `v2-instance-manager-upgrade-timeout`
- **Type**: Integer (minutes)
- **Default**: `60`
- **Minimum**: `1`
- **Category**: General
- **Description**: Since the V2 instance manager is upgraded node by node, an unexpected issue on one node could block upgrades on the remaining nodes. This timeout defines how long an upgrade process on a single node may remain in timed waiting or relocation/restore execution before it is aborted, allowing other nodes to continue their upgrade process. It applies while an IMU is waiting in `Pending`, relocating engines, waiting for the source instance manager, or restoring engines, but not while waiting for post-restore volume health.

## Design

### Implementation Overview

The v2 live upgrade implementation consists of two cooperating controllers:

1. **InstanceManagerUpgradeController**: Manages per-node upgrade lifecycle using a 7-state machine. Handles engine relocation, restoration, and volume health validation.

2. **InstanceManagerUpgradeControlController**: Orchestrates cluster-wide rolling upgrades. Enforces one-node-at-a-time execution, handles retry logic, and manages orphaned upgrades.

**Key Design Principles:**
- **In-Place Pod Image Patching**: Instance manager pod image is upgraded via Kubernetes strategic merge patch instead of pod deletion/recreation, preserving pod identity and reducing disruption
- **Planned Replica Detachment**: Replicas on the node being upgraded are detached from their engines before the IM upgrade to ensure engines don't maintain IO backends on the upgrading node
- **Engine Relocation Strategy**: Since v2 instance managers are tied to nodes, engines must be temporarily moved to other nodes during upgrade
- **NVMe-oF Initiator Persistence**: The kernel-level initiator remains on the source node and survives instance manager pod restarts
- **Replica-Aware Relocation**: Engines are only relocated to nodes that already host a healthy replica
- **Volume Controller Integration**: Volume controller suppresses rebuild/reuse races and error marking for planned detached replicas during the upgrade window
- **Timeout Enforcement**: A single IMU-owned timeout timeline (default 60 minutes) prevents indefinite hangs during timed waiting and relocation/restore phases
- **Automatic Retry**: Failed nodes are retried up to 5 times before giving up

### State Machine

#### InstanceManagerUpgrade Per-Node State Machine

```
┌─────────┐
│ Pending │
└────┬────┘
     │ Validate spec, find source IM, build relocation & detachment plans
     │
     ├─> [No engines AND no planned replicas, or already at target] ─→ Completed
     │
     ├─> [Source IM not found] ─→ WaitingForSourceIM
     │
     ├─> [Validation failed or relocation/detachment structurally unsupported] ─→ Failed
     │
     ├─> [Source IM not Running or recoverable preconditions unmet] ─→ stay Pending
     │
     ├─> [No engines but replicas to detach] ─→ Detach replicas, trigger IM upgrade, WaitingForSourceIM
     │
     ▼
┌─────────────────────┐
│ RelocatingEngines   │  <- Move v2 engines to temporary nodes
└──────────┬──────────┘
           │ All engines running on temp nodes
           │ Detach planned replicas from current engines
           │ Wait for detachment to be applied
           ▼
┌─────────────────────┐
│ WaitingForSourceIM  │  <- Wait for upgraded IM to appear on source node
└──────────┬──────────┘
           │ Target image IM and SPDK target ready on source node
           ▼
┌─────────────────────┐
│ RestoringEngines    │  <- Move engines back to original node
└──────────┬──────────┘
           │ All engines back on original node
           │
           ├─> [AbortRequested] ─→ Failed
           │
           ▼
┌──────────────────────────┐
│ WaitingForHealthyVolumes │  <- Wait for volumes to become Healthy
└──────────┬───────────────┘
           │ All volumes report Robustness == Healthy
           ▼
      ┌───────────┐
      │ Completed │
      └───────────┘

      ┌────────┐
      │ Failed │  ← Can transition from any active state via timeout/abort
      └────────┘
```

**State Transition Details:**

| From State | To State | Condition |
|-----------|----------|-----------|
| Pending | Completed | Source IM already running target image and no work remains, or no engines and no planned replicas on node |
| Pending | WaitingForSourceIM | Source IM not found and node is not already converged, or only planned replica detachment needed |
| Pending | RelocatingEngines | Engines running and relocation plan built successfully |
| Pending | Failed | Spec validation fails or relocation/detachment is structurally unsupported (e.g., no alternate healthy replica node, no other RW replica for detachment) |
| RelocatingEngines | WaitingForSourceIM | All engines running on temporary nodes AND all planned replicas detached and applied |
| WaitingForSourceIM | RestoringEngines | Target image IM detected running on source node (after in-place pod patch) AND engines to restore |
| WaitingForSourceIM | WaitingForHealthyVolumes | Target image IM detected running on source node AND only planned detached replicas (no engines to restore) |
| RestoringEngines | WaitingForHealthyVolumes | All engines back on original nodes |
| RestoringEngines | Failed | AbortRequested set during restore |
| WaitingForHealthyVolumes | Completed | All volumes report Robustness == Healthy |
| Pending / RelocatingEngines / WaitingForSourceIM / RestoringEngines | Failed | Unrecoverable error or timeout-triggered abort after restore completes |

#### InstanceManagerUpgradeControl Node States

The IMUC controller tracks each node's upgrade status independently:

- **Pending**: Node queued but not yet started
- **InProgress**: Currently being upgraded (only one node in this state at a time)
- **Completed**: Upgrade finished successfully
- **Failed**: Upgrade failed and retries exhausted (max 5 retries)

**Note:** Nodes that are already running the target image are not included in the upgrade cycle at all (no entry in `Nodes` map).

**Rolling Upgrade Sequence:**
1. IMUC detects a pending node in its list
2. Creates an InstanceManagerUpgrade CR for that node
3. Marks node as `InProgress` and sets as `CurrentNode` (ensures only one)
4. Monitors IMU state transitions via reconciliation loop
5. On IMU completion: marks node `Completed`, picks next pending node
6. On IMU failure: increments retry count, retries up to 5 times, then marks `Failed`

### Custom Resource Structure

#### InstanceManagerUpgrade (IMU)

**Spec Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `NodeID` | string | Source node where the instance manager is running |
| `TargetImage` | string | Desired instance manager image after upgrade |

**Status Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `State` | string | Current upgrade state (see state machine above) |
| `Engines` | map[string]EngineRelocation | Map of **volume names** → relocation details. |
| `PlannedDetachedReplicas` | map[string][]PlannedDetachedReplica | Map of **volume names** → list of replicas planned for detachment during upgrade. Volume controller suppresses rebuild/reuse races for these replicas during selected upgrade states. |
| `StartedAt` | string | RFC3339 timestamp when upgrade first entered a timed wait or active execution phase. Used for timeout enforcement. Never reset during the upgrade lifecycle. |
| `AbortRequested` | bool | Controller-managed flag indicating that an abort has been triggered due to timeout, target image change, or orphaned IMU detection |
| `AbortReason` | string | Explains why abort was requested: "timeout", "target-image-changed", "orphaned-imu", or "no-temporary-node" |
| `ErrorMsg` | string | Terminal error message if upgrade failed |

**PlannedDetachedReplica Nested Structure:**

| Field | Type | Description |
|-------|------|-------------|
| `Name` | string | Replica name to be detached |
| `Address` | string | Replica backend address. Prefixed with `detached:` after ReplicaRemove is applied to track detachment progress. |

**EngineRelocation Nested Structure:**

| Field | Type | Description |
|-------|------|-------------|
| `OriginalNodeID` | string | Where the engine was originally running |
| `TemporaryNodeID` | string | Where the engine is temporarily relocated during upgrade |

#### InstanceManagerUpgradeControl (IMUC)

**Spec Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `TargetImage` | string | Desired image for all instance managers |
| `StartAt` | string | RFC3339 timestamp for scheduled upgrade start (optional) |

**Status Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `CurrentNode` | string | Node actively being upgraded (enforces one-at-a-time) |
| `Nodes` | map[string]NodeUpgradeInfo | Map tracking upgrade state for every node |

**NodeUpgradeInfo Nested Structure:**

| Field | Type | Description |
|-------|------|-------------|
| `State` | string | Current state: `pending`, `in-progress`, `completed`, or `failed` |
| `IMUName` | string | Name of the InstanceManagerUpgrade CR created for this node |
| `RetryCount` | int | How many times upgrade has been attempted for this node |
| `StartedAt` | string | RFC3339 timestamp when this node's upgrade began (used for orchestration tracking; IMU timeout is enforced from IMU `StartedAt`) |
| `CompletedAt` | string | RFC3339 timestamp when this node's upgrade finished (completed or failed) |
| `ErrorMsg` | string | Last error message encountered while upgrading this node |

### Engine Relocation Flow

The core of live upgrade is temporarily moving engines to other nodes and detaching replicas from the node being upgraded:

**Temporary Node Selection Policy:**
- Engines are relocated only to nodes that can safely host the volume, meaning the node has a healthy running replica for the volume and a running v2 AllInOne instance manager.
- Among eligible nodes, the controller chooses the **least-loaded** node based on the number of current v2 engines plus engines already planned for relocation in this upgrade. This approximates selecting the node with the fewest attached v2 volumes during the rolling upgrade.
- Ties are resolved by node ID to keep the relocation plan deterministic.

**Node Upgrade Order Policy:**
- The control controller upgrades one node at a time.
- Nodes that still have v2 AllInOne instance managers not running the target image are tracked as pending upgrade nodes.
- Among pending nodes, the controller currently picks the **lexicographically smallest node ID** first to keep the rolling upgrade order deterministic.
- Future enhancement can support a user-specified node order or priority policy when operators need tighter control over the upgrade sequence.

```
Initial State: Engine on Node-1 (source), Replica-A on Node-1, Replica-B on Node-2
    │
    ├─ Step 1: Build Relocation & Detachment Plans
    │   ├─ Find healthy replica (Replica-B) on Node-2 for engine relocation
    │   ├─ Verify Node-2 has running v2 IM
    │   ├─ Choose Node-2 as temporary host for engine
    │   ├─ Identify replicas on source node (Replica-A) for planned detachment
    │   └─ Store both plans in IMU.Status
    │
    ├─ Step 2: Relocate Engine to Node-2
    │   ├─ IMU controller updates Volume CR: `Spec.EngineNodeID = "node-2"`
    │   ├─ Volume controller detects spec change and triggers engine relocation
    │   ├─ Wait for `Status.CurrentEngineNodeID = "node-2"` (relocation complete)
    │   └─ Verify engine Running state on the temporary node
    │
    ├─ Step 3: Detach Planned Replicas
    │   ├─ For each planned replica on Node-1:
    │   │   ├─ Call EngineClientProxy.ReplicaRemove() on current engine
    │   │   ├─ Mark address with "detached:" prefix in PlannedDetachedReplicas
    │   │   └─ Remove from Engine.Spec.ReplicaAddressMap
    │   ├─ Wait for replicas to be removed from Engine.Spec.ReplicaAddressMap,
    │   │   Engine.Status.CurrentReplicaAddressMap, and Engine.Status.ReplicaModeMap
    │   └─ Volume controller suppresses rebuild/reuse for planned detached replicas
    │
    ├─ Step 4: Upgrade Source Node
    │   ├─ IMU controller updates IM CR: `Spec.Image = targetImage`
    │   ├─ IM controller patches pod image in-place (NOT pod deletion)
    │   ├─ Kubernetes restarts container with new image
    │   └─ Wait for the target image IM and its SPDK target to become ready
    │
    ├─ Step 5: Restore Engine to Node-1
    │   ├─ IMU controller updates Volume CR: `Spec.EngineNodeID = "node-1"` (back to original)
    │   ├─ Volume controller detects spec change and triggers engine restoration
    │   ├─ Wait for `Status.CurrentEngineNodeID = "node-1"` (restore complete)
    │   └─ Verify engine Running state
    │
    └─ Step 6: Wait for Volume Health
        ├─ Monitor Volume.Status.Robustness for all volumes
        ├─ Standard volume reconciliation reuses or rebuilds replicas
        └─ Transition to Completed when all volumes Healthy

Final State: Engine on Node-1 (source, upgraded IM), replicas reused or rebuilt
```

**Frontend / Initiator Behavior:**
- The host-side initiator and block-device path remain on the attachment/source node throughout
- Engine relocation moves the backend engine target, not the attached workload's node
- Frontend switchover from the original source node to the first temporary engine placement requires the source IM to be running
- Once a volume has left the original source node, temporary-node-to-temporary-node re-planning can proceed without the source IM

**Replica Detachment Strategy:**
- Replicas on the source node are detached from their engines before the IM pod is patched
- Ensures engines don't maintain IO backends on the node being upgraded
- Volume controller suppresses rebuild/reuse races for planned detached replicas during the upgrade window
- Detachment only proceeds if volume has at least one other RW replica on a different node
- Replicas are reused or rebuilt naturally after the engine is restored to the source node and suppression is released

**Operational Characteristics:**
- **Reconciliation Interval**: Both IMU and IMUC controllers re-check upgrade progress every **10 seconds** while upgrades are active
- **Timeout Granularity**: Timeout enforcement has ~10-second granularity (could be off by up to 10 seconds)
- **Volume Stabilization**: Engines don't stabilize faster than 10-second intervals
- **Impact**: For capacity planning, expect state transitions to be detected within 10 seconds of occurrence

**Instance Manager Controller Integration:**
- **In-Place Pod Patching**: When IMU controller updates IM.Spec.Image, the IM controller detects the image change and patches the pod using Kubernetes strategic merge patch (`{"spec":{"containers":[{"name":"instance-manager","image":"<target>"}]}}`)
- **No Pod Deletion**: Unlike traditional upgrades, the pod is NOT deleted. Kubernetes restarts the container with the new image while preserving pod metadata and identity
- **Self-Heal Preservation**: If the pod is missing, deleting, or failed, the IM controller still recreates it normally (self-heal behavior unchanged)
- **Default IM Prevention**: Node controller is prevented from creating extra default v2 IMs during active upgrades to avoid conflicts

**Volume Controller Integration:**
- **Planned Replica Suppression**: Volume controller watches IMU resources and suppresses the following operations for replicas in `PlannedDetachedReplicas`:
  - Replica error marking when missing from engine mode map
  - Replica rebuild/replenishment attempts
  - Replica start and engine replica address map inclusion
- **Suppression Window**: Active only for attached v2 volumes. `Pending` suppresses only when no engines are recorded in the IMU, `RelocatingEngines` suppresses only volumes listed in `IMU.Status.Engines`, and `WaitingForSourceIM`/`RestoringEngines` suppress planned detached replicas unconditionally.
- **Natural Rebuild**: After the IMU enters `WaitingForHealthyVolumes`, suppression is released and standard volume reconciliation reuses or rebuilds replicas. The IMU completes after affected volumes become `Healthy`.

### Edge Cases and Handling

#### 1. Temporary Node Failure During Relocation

**Scenario**: Node hosting temporarily relocated engine becomes unavailable.

**Behavior**:
- During `RelocatingEngines` or `WaitingForSourceIM`: monitors temp node health via `CheckInstanceManagersReadiness()`
- If temp node's IM goes down: `maybeReplanVolume()` detects this
- Selects a new healthy temp node with a healthy replica
- Updates relocation plan and relocates engine to new node
- If NO alternative temp node exists: reverts volume to original node immediately (bypass timeout)

**Optimization**: Prevents waiting for timeout when failure is detected early.

#### 2. Volume Deletion During Upgrade

**Scenario**: User deletes a volume while its engine is being relocated.

**Behavior**:
- During relocation or restoration: checks for `ErrorIsNotFound` on volume lookups
- Removes deleted volume from relocation plan
- Continues upgrade with remaining volumes
- Logs warning event

**Safety**: Does not fail the entire node upgrade due to one volume deletion.

#### 3. Source Instance Manager Goes Down

**Scenario**: Source node's original IM becomes unavailable before relocation/detachment can safely begin.

**Behavior**:
- Frontend switchover from the original source node to a temporary node requires source IM to be `Running`
- Planned replica detachment also requires the current engine to be `Running`
- If source IM is present but not `Running`, the IMU stays in `Pending`
- `StartedAt` is set so the IMU timeout covers this wait
- When the source IM recovers, the IMU either proceeds with relocation/detachment or detects that the node already converged to the target image

**Rationale**: Cannot safely relocate engines or detach replicas without coordinating with a running source IM and engine.

#### 4. Target Image Change During Upgrade

**Scenario**: Administrator updates IMUC's `Spec.TargetImage` while nodes are upgrading.

**Behavior**:
- **For pending nodes**: IMUC controller resets their IMU references; they'll use new target image on next attempt
- **For active node**: `processCurrentNode()` detects mismatch and sets `IMU.Status.AbortRequested = true` and `AbortReason = "target-image-changed"`
- **IMU abort handling**: 
  - Engine restoration begins immediately
  - IMU transitions to `Failed` after restore completes
  - IMUC resets node to `Pending` WITHOUT consuming a retry
- **Result**: Node can be retried with new target image

**Safety**: Ensures partially-upgraded nodes don't end up in inconsistent state.

#### 5. Timeout Enforcement

**Scenario**: Node upgrade takes longer than the configured timeout (default: 60 minutes).

**Behavior**:
- **Timeout is enforced by the IMU controller**
- **Single continuous timeout** measured from `IMU.Status.StartedAt` (never reset between states)
- Applies while the IMU is in timed `Pending`, `RelocatingEngines`, `WaitingForSourceIM`, or `RestoringEngines`
- Does **not** apply while the IMU is in `WaitingForHealthyVolumes`
- **On timeout detection**:
  - Sets `IMU.Status.AbortRequested = true` and `AbortReason = "timeout"`
  - Transitions to `RestoringEngines` state to gracefully restore engines to original nodes
  - IMU transitions to `Failed` after all engines restored
  - IMUC can retry the node (up to 5 times)
- **No force-fail mechanism**: Controllers always attempt graceful engine restoration
- Logged at WARN/ERROR levels

**Protection**: Prevents one stuck node from blocking entire cluster upgrade indefinitely.

**Worst-case duration**: `timeout value + time to restore all engines` (engines are restored even after timeout)

#### 6. Orphaned In-Progress Nodes

**Scenario**: IMUC shows a node as `InProgress` but its IMU CR was deleted or controller crashed.

**Behavior**:
- `recoverOrphanedNodes()` detects nodes stuck in `InProgress` without being `CurrentNode`
- Resets them to `Pending` while preserving retry count
- Prevents infinite loops and enables automatic recovery

#### 7. Planned Replica Detachment Failure

**Scenario**: Replica detachment from current engine fails or replica continues to appear in engine status.

**Behavior**:
- IMU controller calls `EngineClientProxy.ReplicaRemove()` on current engine
- On error, checks whether the error indicates the replica is already detached
- Re-fetches latest engine status to verify replica actually removed
- If replica genuinely missing from status, continues (detachment succeeded despite error)
- If replica still present in status and not an "already detached" error, returns error for retry
- Marks replica address with `detached:` prefix to track progress
- Waits for replica to be removed from both `CurrentReplicaAddressMap` and `ReplicaModeMap`
- Volume controller suppresses rebuild attempts during this window
- After detachment applied, triggers IM pod patch

**Safety**: Ensures replicas are truly detached before patching IM pod, preventing IO backend conflicts during container restart.

#### 8. Volume With Only Replicas (No Engine) On Upgrading Node

**Scenario**: A volume has replicas on the node being upgraded, but its engine is running on a different node.

**Behavior**:
- IMU builds planned detachment plan for these replicas
- No engine relocation plan is needed (engine not on this node)
- In `Pending` state: persists planned detachment plan, then detaches replicas
- After replicas detached and applied, triggers IM pod patch
- Transitions directly to `WaitingForSourceIM` (skips `RelocatingEngines`)
- After IM upgraded, transitions to `WaitingForHealthyVolumes` (skips `RestoringEngines`)
- Waits for volume to become Healthy (replicas are reused or rebuilt by standard reconciliation)
- Transitions to `Completed`

**Rationale**: Volumes without engines on the upgrading node don't need relocation, only replica detachment and health validation.

### Behavior and Limitations

#### Supported Behavior

**No-volume-detach rolling upgrades**: Volumes stay attached while engines are temporarily relocated and restored
**In-place pod patching**: IM pod image upgraded via strategic merge patch instead of pod deletion/recreation
**Planned replica detachment**: Replicas on upgrading node are detached from engines before IM upgrade to prevent IO backends on upgrading node
**Volume controller suppression**: Automatic suppression of rebuild/reuse/error-marking races for planned detached replicas
**Rolling upgrades**: One node at a time to minimize blast radius
**Automatic retry**: Up to 5 retries per node on failure
**Scheduled upgrades**: Start at a specific time via `v2-instance-manager-upgrade-start-time` (projected into `Spec.StartAt` before the cycle begins)
**Mid-upgrade abort**: Controller sets `AbortRequested` on timeout or target image change to cancel gracefully
**Load balancing**: Engines distributed across temporary nodes evenly
**Health validation**: Waits for volumes to reach `Healthy` state before completing
**Orphan recovery**: Automatically recovers from controller crashes

#### Limitations

**Single-replica volumes**: Cannot be live-upgraded (no alternate node for relocation, no RW replica outside source node for detachment)
**All replicas on same node**: Cannot be live-upgraded (no alternate node for relocation, no RW replica outside source node for detachment)
**Structurally unsatisfiable relocation/detachment plans**: IMU fails fast instead of waiting for timeout when no alternate healthy replica node exists or no RW replica outside source node exists
**V1 engines**: Only v2 data engine instance managers are upgraded
**Concurrent node upgrades**: Strictly one node at a time (by design for safety)
**Degraded volumes**: Attached v2 volumes with replicas on the upgrade node must be `Healthy` before the node upgrade proceeds. Otherwise, the upgrade waits until they become healthy.

#### Recommended Pre-Upgrade Checklist

Before initiating a v2 live upgrade:

1. **Replica Distribution**: Ensure all volumes have at least one replica on a different node
2. **Cluster Health**: Verify all nodes and instance managers are in `Running` state
3. **Volume Health**: Confirm all volumes report `Robustness: Healthy`
4. **Disk Space**: Ensure sufficient space for replica rebuild fallback if reuse cannot complete
5. **Monitoring**: Set up monitoring for upgrade progress and errors
6. **Backup**: Create backups of critical volumes as a precaution


### Upgrade Strategy

No upgrade strategy is needed for this feature itself. The v2 live upgrade capability is introduced as a new CRD-based feature and does not modify existing upgrade mechanisms.
