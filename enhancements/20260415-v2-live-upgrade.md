# V2 Live Upgrade

## Summary

Support for live upgrading v2 data engine instance managers across the cluster without volume downtime. This enables users to upgrade Longhorn v2 components while maintaining continuous I/O operations.

### Related Issues

- https://github.com/longhorn/longhorn/issues/9104

## Motivation

- Promote Longhorn Engine v2 from experimental to production-ready by implementing critical operational capabilities
- Enable zero-downtime upgrades for v2 volumes to support production workloads

### Goals

- Allow users to upgrade v2 instance managers without detaching volumes or interrupting I/O
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

Tracks the live upgrade of a single v2 instance manager on one node. Manages temporary engine relocation and restoration.

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
      snapshotName: "pre-upgrade-snapshot-abc123"  # Optional, based on settings
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

#### (1) Take Snapshot Before V2 Data Engine Upgrade

- **Name**: `take-snapshot-before-v2-data-engine-upgrade`
- **Type**: Boolean
- **Default**: `false`
- **Category**: General
- **Description**: If enabled, Longhorn takes a snapshot and waits for its checksum calculation to complete before relocating a v2 data engine to another node during the Instance Manager Upgrade. This helps minimize replica rebuild time if a failure occurs during the upgrade. This setting must be enabled to utilize the Fast Replica Rebuild feature (`fast-replica-rebuild-enabled`) during the upgrade process.


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
- **Engine Relocation Strategy**: Since v2 instance managers are tied to nodes, engines must be temporarily moved to other nodes during upgrade
- **NVMe-oF Initiator Persistence**: The kernel-level initiator remains on the source node and survives instance manager pod restarts
- **Replica-Aware Relocation**: Engines are only relocated to nodes that already host a healthy replica
- **Fast Replica Rebuild**: Pre-upgrade snapshots enable faster replica rebuilding when engines return to source nodes
- **Timeout Enforcement**: A single IMU-owned timeout timeline (default 60 minutes) prevents indefinite hangs during timed waiting and relocation/restore phases
- **Automatic Retry**: Failed nodes are retried up to 5 times before giving up
- **Old IM Preservation**: Old v2 instance managers are preserved while they still host the authoritative current engine or are protecting temporary live-upgrade placements

### State Machine

#### InstanceManagerUpgrade Per-Node State Machine

```
┌─────────┐
│ Pending │
└────┬────┘
     │ Validate spec, find source IM, build relocation plan
     │
     ├─> [No engines or already at target] ─→ Completed
     │
     ├─> [Source IM not found] ─→ WaitingForSourceIM
     │
     ├─> [Validation failed or relocation structurally unsupported] ─→ Failed
     │
     └─> [Source IM not Running or recoverable preconditions unmet] ─→ stay Pending
     │
     ▼
┌─────────────────────┐
│ RelocatingEngines   │  <- Move v2 engines to temporary nodes
└──────────┬──────────┘
           │ All engines running on temp nodes
           ▼
┌─────────────────────┐
│ WaitingForSourceIM  │  <- Wait for upgraded IM to appear on source node
└──────────┬──────────┘
           │ Target image IM detected on source node
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
| Pending | Completed | Source IM already running target image, or no engines on node |
| Pending | WaitingForSourceIM | Source IM not found and node is not already converged |
| Pending | RelocatingEngines | Engines running and relocation plan built successfully |
| Pending | Failed | Spec validation fails or relocation is structurally unsupported (for example, no alternate healthy replica node) |
| RelocatingEngines | WaitingForSourceIM | All engines running on temporary nodes |
| WaitingForSourceIM | RestoringEngines | Target image IM detected running on source node |
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
| `StartedAt` | string | RFC3339 timestamp when upgrade first entered a timed wait or active execution phase. Used for timeout enforcement. Never reset during the upgrade lifecycle. |
| `AbortRequested` | bool | Controller-managed flag indicating that an abort has been triggered due to timeout, target image change, or orphaned IMU detection |
| `AbortReason` | string | Explains why abort was requested: "timeout", "target-image-changed", "orphaned-imu", or "no-temporary-node" |
| `ErrorMsg` | string | Terminal error message if upgrade failed |

**EngineRelocation Nested Structure:**

| Field | Type | Description |
|-------|------|-------------|
| `OriginalNodeID` | string | Where the engine was originally running |
| `TemporaryNodeID` | string | Where the engine is temporarily relocated during upgrade |
| `SnapshotName` | string | Pre-upgrade snapshot for fast replica rebuild (optional) |

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

The core of live upgrade is temporarily moving engines to other nodes:

```
Initial State: Engine on Node-1 (source)
    │
    ├─ Step 1: Build Relocation Plan
    │   ├─ Find healthy replica on Node-2
    │   ├─ Verify Node-2 has running v2 IM
    │   └─ Choose Node-2 as temporary host
    │
    ├─ Step 2: Optional Pre-Upgrade Snapshot
    │   ├─ Create snapshot on source engine
    │   ├─ Wait for checksum computation
    │   └─ Store snapshot name in EngineRelocation
    │
    ├─ Step 3: Relocate Engine to Node-2
    │   ├─ IMU controller updates Volume CR: `Spec.EngineNodeID = "node-2"`
    │   ├─ Volume controller detects spec change and triggers engine relocation
    │   ├─ Wait for `Status.CurrentEngineNodeID = "node-2"` (relocation complete)
    │   ├─ Wait for replica rebuilding if needed
    │   └─ Verify engine Running state
    │
    ├─ Step 4: Upgrade Source Node
    │   ├─ Instance Manager pod deleted/recreated
    │   ├─ New pod starts with target image
    │   └─ Wait for new IM to report ready
    │
    ├─ Step 5: Restore Engine to Node-1
    │   ├─ IMU controller updates Volume CR: `Spec.EngineNodeID = "node-1"` (back to original)
    │   ├─ Volume controller detects spec change and triggers engine restoration
    │   ├─ Wait for `Status.CurrentEngineNodeID = "node-1"` (restore complete)
    │   ├─ Use pre-upgrade snapshot for fast rebuild (if enabled)
    │   └─ Verify engine Running state
    │
    └─ Step 6: Wait for Volume Health
        ├─ Monitor Volume.Status.Robustness
        └─ Transition to Completed when Healthy

Final State: Engine on Node-1 (source, upgraded IM)
```

**Frontend / Initiator Behavior:**
- The host-side initiator and block-device path remain on the attachment/source node throughout
- Engine relocation moves the backend engine target, not the attached workload's node
- Frontend switchover from the original source node to the first temporary engine placement requires the source IM to be running
- Once a volume has left the original source node, temporary-node-to-temporary-node re-planning can proceed without the source IM

**Operational Characteristics:**
- **Reconciliation Interval**: Both IMU and IMUC controllers re-check upgrade progress every **10 seconds** while upgrades are active
- **Timeout Granularity**: Timeout enforcement has ~10-second granularity (could be off by up to 10 seconds)
- **Volume Stabilization**: Engines don't stabilize faster than 10-second intervals
- **Impact**: For capacity planning, expect state transitions to be detected within 10 seconds of occurrence

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

**Scenario**: Source node's original IM becomes unavailable before relocation can safely begin.

**Behavior**:
- Frontend switchover from the original source node to a temporary node requires source IM to be `Running`
- If source IM is present but not `Running`, the IMU stays in `Pending`
- `StartedAt` is set so the IMU timeout covers this wait
- When the source IM recovers, the IMU either proceeds with relocation or detects that the node already converged to the target image

**Rationale**: Cannot safely relocate without coordinating with source IM for frontend handoff.

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

### Behavior and Limitations

#### Supported Behavior

✅ **No-detach rolling upgrades**: Volumes stay attached while engines are temporarily relocated and restored
✅ **Rolling upgrades**: One node at a time to minimize blast radius
✅ **Automatic retry**: Up to 5 retries per node on failure
✅ **Scheduled upgrades**: Start at a specific time via `v2-instance-manager-upgrade-start-time` (projected into `Spec.StartAt` before the cycle begins)
✅ **Mid-upgrade abort**: Controller sets `AbortRequested` on timeout or target image change to cancel gracefully
✅ **Load balancing**: Engines distributed across temporary nodes evenly
✅ **Health validation**: Waits for volumes to reach `Healthy` state before completing
✅ **Orphan recovery**: Automatically recovers from controller crashes
✅ **Fast rebuild**: Optional pre-upgrade snapshots for faster replica rebuilding

#### Limitations

❌ **Single-replica volumes**: Cannot be live-upgraded (no alternate node for relocation)
❌ **All replicas on same node**: Cannot be live-upgraded (no alternate node for relocation)
❌ **Structurally unsatisfiable relocation plans**: IMU fails fast instead of waiting for timeout when no alternate healthy replica node exists
❌ **V1 engines**: Only v2 data engine instance managers are upgraded
❌ **Concurrent node upgrades**: Strictly one node at a time (by design for safety)
❌ **Degraded volumes**: Upgrade waits until volume becomes healthy (doesn't fail, but blocks)

#### Recommended Pre-Upgrade Checklist

Before initiating a v2 live upgrade:

1. **Replica Distribution**: Ensure all volumes have at least one replica on a different node
2. **Cluster Health**: Verify all nodes and instance managers are in `Running` state
3. **Volume Health**: Confirm all volumes report `Robustness: Healthy`
4. **Disk Space**: Ensure sufficient space on all nodes for temporary replica rebuilding
5. **Monitoring**: Set up monitoring for upgrade progress and errors
6. **Backup**: Create backups of critical volumes as a precaution

### Test Plan

#### Prerequisites

- Cluster with at least 3 nodes
- Multiple v2 volumes with NVMe-oF frontend attached to various nodes
- At least 2 replicas per volume distributed across different nodes
- All volumes in `Healthy` state

#### Test Cases

**Basic Upgrade Flow**
1. Create InstanceManagerUpgradeControl CR with target image
2. Monitor upgrade progress via `kubectl get lhimuc -o yaml`
3. Verify nodes transition: Pending → InProgress → Completed
4. Verify only one node in InProgress state at any time
5. Verify all volumes remain attached and I/O functional throughout
6. Verify all instance managers running target image after completion

**Engine Relocation and Restoration**
1. During upgrade, monitor volume CR for `Spec.EngineNodeID` changes
2. Verify engine temporarily moves to different node (with replica)
3. Verify engine returns to original node after IM upgrade
4. Use `kubectl exec` into instance manager pod to verify engine running
5. Verify NVMe-oF initiator reconnects automatically

**Failure and Retry Testing**
1. Simulate node failure during upgrade (drain/cordon node mid-upgrade)
2. Verify IMU transitions to `Failed` state
3. Verify IMUC increments retry count
4. Verify automatic retry after failure
5. Verify max 5 retries before permanent failure

**Single-Replica Volume Limitation**
1. Create volume with 1 replica
2. Attempt to upgrade node hosting the replica
3. Verify IMU fails with "no healthy replica found on nodes other than source node"
4. Verify IMUC marks node as `Failed` after retries

**Degraded Volume Handling**
1. Delete a replica to make volume degraded
2. Attempt to upgrade node hosting engine
3. Verify IMU waits in Pending/RelocatingEngines (doesn't fail)
4. Restore replica to healthy state
5. Verify upgrade automatically proceeds

**Target Image Change Mid-Upgrade**
1. Start upgrade with image A
2. Update IMUC target image to B while node is upgrading
3. Verify active node's IMU aborted
4. Verify engines restored to source node
5. Verify node reset to Pending without consuming retry
6. Verify node retried with new image B

**Scheduled Upgrade**
1. Set `v2-instance-manager-upgrade-start-time` to a future time (RFC3339 format)
2. Trigger instance manager image change to create/update IMUC (controller reads start time from setting at IMUC creation/reconciliation)
3. Verify no nodes start upgrading before scheduled time
4. Verify upgrade begins at scheduled time
5. Verify normal rolling upgrade flow after start
6. Attempt to change start time after upgrade started (should be rejected)

**Timeout Setting Testing**
1. Set `v2-instance-manager-upgrade-timeout` to a low value (e.g., 5 minutes)
2. Simulate a slow/stuck upgrade (e.g., block network to temp node)
3. Verify `AbortRequested` set to `true` and `AbortReason` set to `"timeout"` after configured timeout
4. Verify IMU transitions to `RestoringEngines` state to gracefully restore engines
5. Verify IMU reaches `Failed` state after engine restoration completes
6. Verify IMUC retries the failed node
7. Restore to default timeout value for remaining tests

**Pre-Upgrade Snapshot Setting Testing**
1. Verify `take-snapshot-before-v2-data-engine-upgrade` defaults to `false`
2. Initiate upgrade with setting disabled
3. Verify no snapshots created in IMU status
4. Enable the setting and `fast-replica-rebuild-enabled`
5. Initiate another upgrade (different node)
6. Verify snapshot created and checksum computed before relocation
7. Verify faster rebuild when engine restored
8. Disable snapshot setting mid-upgrade (should not affect in-flight upgrades)

**Concurrent I/O During Upgrade**
1. Run sustained I/O workload (fio) against v2 volume
2. Initiate live upgrade on node hosting engine
3. Verify no I/O errors during entire upgrade process
4. Verify I/O latency remains acceptable (account for network hop)
5. Verify data integrity after upgrade (checksums)

### Upgrade Strategy

No upgrade strategy is needed for this feature itself. The v2 live upgrade capability is introduced as a new CRD-based feature and does not modify existing upgrade mechanisms.
