# Synchronized Disk Schedule Controller

## Summary

Introduce a Disk Scheduling Controller to synchronously schedule replicas and backing images.

### Related Issues

- https://github.com/longhorn/longhorn/issues/10422

## Motivation

### Problem Statement

The current Longhorn architecture has a critical race condition in disk space allocation:

- Distributed Scheduling: Each node runs a multi-thread volume controller, all independently scheduling replicas
- No Synchronization: The replica scheduler is stateless, querying current CR status without any locking mechanism
- Time-of-Check to Time-of-Use Gap: Between checking available space and creating replica CRs, other controllers may allocate to the same disk
- Separate Backing Image Logic: Backing image allocation bypasses the replica scheduler entirely, checking node CRs directly

### Real-World Impact:

- Multiple volumes simultaneously scheduling replicas can exhaust disk space.
- Disk pressure causes I/O failure.
- Manual intervention required to rebalance resources.

### Goals

- Prevent race conditions in replica and backing image scheduling.
- Unify allocation logic for replicas and backing images to avoid duplicated code and inconsistent capacity checks.
- Support volume expansion by providing a reservation mechanism that checks and pre-allocates space across multiple disks atomically.
- Ensure high availability of cross-node atomic scheduler.

### Non-goals

- No resource allocation algorithm improvement, including disk selection and balancing.
- The new scheduler implementation does not reflect disk usage change outside of Longhorn.
- CR validator-level allocation: even though a volume expansion request is submitted by mutating volume CR, there is still a chance to reject expansion by scheduler.

## Proposal

Introduce a synchronous Disk Scheduling Controller that records allocated disk resources in Kubernetes Custom Resources (CRs). All controllers must allocate disk space via this DiskSchedule CR before instantiating replicas or backing image copies on a disk. The controller synchronizes operations using Kubernetes optimistic concurrency (resource version conflicts trigger requeue) and updates allocation states in the DiskSchedule CR, ensuring atomicity at the API level.

### User Stories

- **Concurrent PVC Creation**: Multiple PVCs can be created simultaneously in a resource-constrained cluster. Volume replicas will not be scheduled if there is no sufficient space for a disk.
- **Concurrent Backing Image Copy Allocation**: Backing image copies will not be allocated to a disk if there is no sufficient space.
- **Volume Expansion**: The volume size expansion will not be proceeded if there is no sufficient space.

## design

### Architecture Overview

- **DiskScheduleController**: Maintains disk allocation status and decides whether to allocate space for resources. Reconciles `DiskSchedule.Status` based on `DiskSchedule.Spec` allocation requests.
- **VolumeController**: The sole owner of replica disk allocation decisions. Writes `DiskSchedule.Spec.Replicas` requirements, reads `DiskSchedule.Status.Replicas` to determine if replicas can start, and sets `VolumeConditionTypeDiskAllocation`.
- **ReplicaController**: Cleanup-only for disk allocation. Releases disk allocation when a replica is being deleted (`DeletionTimestamp != nil`). No other DiskSchedule operations are performed by ReplicaController.
- **BackingImageController**: Handles backing image disk allocation and cleanup. Writes `DiskSchedule.Spec.BackingImages` requirements and releases allocation when a backing image is being deleted.
- **Synchronization**: The disk allocation state is protected by DiskScheduleController's reconciliation loop. Concurrent updates are handled via Kubernetes optimistic concurrency (resource version conflicts trigger requeue).
- **State management**: The disk space scheduling logic is computed from `DiskSchedule.Spec` and recorded in `DiskSchedule.Status`.

### Disk Scheduling Controller

#### Disk Scheduling

A new CRD `DiskSchedule` is created to store current scheduling state for each disk, and is reconciled by the disk scheduling controller:

```go
type DiskScheduledResourcesStatus struct {
    // Scheduled state
    // +kubebuilder:validation:Enum=scheduled;rejected
    State DiskScheduleState `json:"state"`
    // Scheduled size in bytes
    // +optional
    ScheduledSize int64 `json:"scheduledSize"`
}

// DiskScheduleSpec defines desired state of a disk's allocation requests.
type DiskScheduleSpec struct {
    // Disk name from node CR
    // +optional
    Name string `json:"name"`
    // Node ID that the disk locates
    // +optional
    NodeID string `json:"nodeID"`
    // Scheduling requests for volume replicas. Key is replica name, value is required size in bytes.
    // +optional
    Replicas map[string]int64 `json:"replicas"`
    // Scheduling requests for backing images. Key is backing image name, value is required size in bytes.
    // +optional
    BackingImages map[string]int64 `json:"backingImages"`
}

// DiskScheduleStatus defines observed state of disk allocations.
type DiskScheduleStatus struct {
    // Scheduled status of volume replicas. Key is replica name.
    // +optional
    Replicas map[string]*DiskScheduledResourcesStatus `json:"replicas"`
    // Scheduled status of backing images. Key is backing image name.
    // +optional
    BackingImages map[string]*DiskScheduledResourcesStatus `json:"backingImages"`
    // Sum of successfully scheduled storage in bytes. Should not exceed Node CR's `status.diskStatus[diskName].storageAvailable`.
    // +optional
    StorageScheduled int64 `json:"storageScheduled"`
    // +optional
    // +nullable
    Conditions []Condition `json:"conditions"`
}

// DiskSchedule is where Longhorn stores disk scheduling status.
type DiskSchedule struct {
    metav1.TypeMeta   `json:",inline"`
    metav1.ObjectMeta `json:"metadata,omitempty"`

    Spec   DiskScheduleSpec   `json:"spec,omitempty"`
    Status DiskScheduleStatus `json:"status,omitempty"`
}
```

And possible schedule states for a resource:

```go
type DiskScheduleState string

const (
    // resource is successfully scheduled to disk
    DiskScheduledStateScheduled = DiskScheduleState("scheduled")
    // resource is rejected by the disk
    DiskScheduledStateRejected  = DiskScheduleState("rejected")
)
```

For example, to a disk named `example-disk` with UUID `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee` on node `example-node`:

- 2 volume replicas, `r1` (50GiB) and `r2` (50GiB), are already scheduled successfully.
- 1 volume replica, `r3` (500GiB), tried to be scheduled to this node, but has no sufficient space for it.
- 1 volume replica, `r4` (5GiB), is waiting for scheduling.
- 2 backing image copies, `b1` (50GiB) and `b2` (50GiB), are already scheduled successfully.
- Totally 200GiB (`214748364800` bytes) is already scheduled.

```yaml
apiVersion: longhorn.io/v1beta2
kind: DiskSchedule
metadata:
  finalizers:
    - longhorn.io
  name: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
  namespace: longhorn-system
  ...
spec:
  name: example-disk
  nodeID: example-node
  replicas:
    r1: 53687091200
    r2: 53687091200
    r3: 536870912000
    r4: 5368709120
  backingImages:
    b1: 53687091200
    b2: 53687091200
status:
  replicas:
    r1:
      state: scheduled
      scheduledSize: 53687091200
    r2:
      state: scheduled
      scheduledSize: 53687091200
    r3:
      state: rejected
      scheduledSize: 0
    # r4 is pending - present in spec but not yet in status
  backingImages:
    b1:
      state: scheduled
      scheduledSize: 53687091200
    b2:
      state: scheduled
      scheduledSize: 53687091200
  storageScheduled: 214748364800
  conditions:
    - lastProbeTime: ""
      lastTransitionTime: "2006-01-02T15:04:05Z"
      message: Disk example-disk is ready for scheduling on node example-node
      reason: ""
      status: "True"
      type: Schedulable
```

The Node Controller creates or deletes DiskSchedule Custom Resources (CRs) corresponding to each entry in `Node.status.diskStatus`.

### Disk Space Allocation

A resource to be scheduled is defined as:

- A resource recorded in `Replicas` (spec JSON: `replicas`) or `BackingImages` (spec JSON: `backingImages`) of a DiskSchedule's spec that is acquiring space, and
- A resource not yet recorded in `Replicas` (status JSON: `replicas`) or `BackingImages` (status JSON: `backingImages`) of a DiskSchedule's status, or whose scheduled size is less than its required space.

Before the scheduling controller allocates space to any resource, it first collects the maximum schedulable space from `Node.status.diskStatus[diskName].storageAvailable`. After each DiskSchedule reconciliation, the total allocated resource size must not exceed this value.

$$storageScheduled = \sum(Replicas) + \sum(BackingImages)$$

$$storageScheduled \le storageAvailable$$

In a single DiskSchedule reconciliation, if multiple resources require simultaneous scheduling, the scheduling controller does not guarantee the order of scheduling.

#### Replica Creation

When the Volume Controller replenishes replicas:

1. The Volume Controller creates a Replica CR without specifying a node or disk.
2. During volume CR status reconciliation, the Volume Controller evaluates disk candidates across all DiskSchedule CRs, assigns a node and disk to the Replica CR, and submits a scheduling request by calling `DiskSchedule.SetReplicaRequirement(replicaName, volumeSize)` on the target DiskSchedule CR.
3. The DiskScheduleController assesses whether the disk can accommodate the replica, then records the result in `DiskSchedule.Status.Replicas[replicaName]`.
4. If a replica's status is `rejected`, the Volume Controller receives the DiskSchedule CR update event (via `enqueueDiskScheduleChange`), removes the scheduling request by calling `SetReplicaRequirement(replicaName, 0)`, and retries from step 2 with a different disk.
5. If a replica's status is `scheduled` with the correct size, the Replica Controller proceeds with instance creation on the assigned disk.

#### Volume Expansion

When a volume expansion is requested:

1. The Volume Controller updates the required size in all DiskSchedule CRs for existing replicas by calling `SetReplicaRequirement(replicaName, expandedSize)` before updating the `volumeSize` in the instance spec.
2. For each disk, the DiskScheduleController evaluates whether the resize can be accommodated, records the result in the DiskSchedule CR status, and the Volume Controller holds the expansion until all replica expansion requests are reconciled in the DiskSchedule CRs.
3. After all DiskSchedule CRs are reconciled, if any replica is marked as `rejected` with an unchanged non-zero size, the Volume Controller receives the DiskSchedule CR update event and processes the expansion failure.
4. If all replicas transition to `scheduled` in the DiskSchedule CRs with the expanded size, the Volume Controller proceeds with the size expansion by updating `volumeSize` in the corresponding engine and replicas.

#### Backing Image Copy Creation

When the Backing Image Controller replenishes copies:

1. The Backing Image Controller evaluates disk candidates across all DiskSchedule CRs, adds the copy to `BackingImageSpec.DiskFileSpecMap`, and submits a scheduling request by calling `DiskSchedule.SetBackingImageRequirement(backingImageName, imageSize)` on the target DiskSchedule CR.
2. The DiskScheduleController assesses whether the disk can accommodate the copy and records the result in `DiskSchedule.Status.BackingImages[backingImageName]`.
3. If a copy's status is `rejected`, the Backing Image Controller receives the DiskSchedule CR update event, removes the scheduling request by calling `SetBackingImageRequirement(backingImageName, 0)`, and retries from step 1 with a different disk.
4. If a copy's status is `scheduled`, the Backing Image Controller proceeds with copy creation on the assigned disk.

Note: The key for backing images is `BackingImage.Name` (not per-copy), as the backing image size is the same across all copies.

### Resource Deallocation

Resource deallocation is requested by setting the requirement to 0, which removes the map entry from `DiskSchedule.Spec`.

#### Replica Deallocation

The **ReplicaController** is responsible for releasing replica disk allocation during deletion:

1. When `replica.DeletionTimestamp != nil` in `syncReplica`:
2. If `replica.Spec.DiskID != ""` (the replica was scheduled to a disk):
   - Get the DiskSchedule CR for the disk
   - Call `DiskSchedule.SetReplicaRequirement(replica.Name, 0)` to release the allocation
   - Update the DiskSchedule CR
3. Proceed with removing the replica finalizer

The ReplicaController does NOT perform any other DiskSchedule operations (no requirement sync, no status checks, no condition updates).

#### Backing Image Deallocation

The **BackingImageController** is responsible for releasing backing image disk allocation during deletion:

1. When `backingImage.DeletionTimestamp != nil` in `syncBackingImage`:
2. Collect all disk IDs from the union of:
   - `backingImage.Spec.DiskFileSpecMap` keys
   - `backingImage.Status.DiskFileStatusMap` keys
3. For each disk ID:
   - Get the DiskSchedule CR for the disk
   - Call `DiskSchedule.SetBackingImageRequirement(backingImage.Name, 0)` to release the allocation
   - Update the DiskSchedule CR
4. Proceed with removing the backing image finalizer

### VolumeController Watch Behavior

The VolumeController watches DiskSchedule CRs to receive allocation status updates:

1. **Watch scope**: Only `Status.Replicas` changes are relevant to volumes. Changes to `BackingImages` do not trigger a volume requeue.
2. **Enqueue logic** (`enqueueDiskScheduleChange`):
   - For each replica name in `curDs.Status.Replicas` that differs from `oldDs.Status.Replicas`:
     - Look up the Replica CR by name
     - Enqueue the replica's volume for reconciliation
3. **Volume condition**: The VolumeController sets `VolumeConditionTypeDiskAllocation` based on DiskSchedule status, not on replica conditions.

## test plan

### Concurrent Replica Allocation

### Concurrent Backing Image Copy Allocation

### Concurrent Disk Expansion
