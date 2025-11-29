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
- Ensure high availability of the cross-node atomic scheduler.

### Non-goals

- No resource allocation algorithm improvement, including disk selection and balancing.
- The new scheduler implementation does not reflect the disk usage change outside of Longhorn.
- CR validator-level allocation: even though a volume expansion request is submit by mutate the volume CR, there is still chance to reject the expansion by the scheduler.

## Proposal

Introduce a synchronous Disk Scheduling Controller that records allocated disk resources in Kubernetes Custom Resources (CRs). All controllers must allocate disk space via this DiskSchedule CR before instantiating replicas or backing image copies on a disk. The controller synchronizes operations using an internal mutex and updates allocation states in the Longhorn DiskSchedule CR, ensuring atomicity at the API level.

### User Stories

- **Concurrent PVC Creation**: Multiple PVCs can be created simultaneously in a resource-constrained cluster. Volume replica will not be scheduled if there is no sufficient space for a disk.
- **Concurrent Backing Image Copy Allocation**: Backing image copies will not be allocated to a disk if there is no sufficient space.
- **Volume Expansion**: The volume size expansion will not be proceeded if there is no sufficient space.

## design

### Architecture Overview

- **disk scheduler controller**: The controller to maintain the disk allocation status, and decide whether to allocate the space for resources.
- **Synchronization**: The disk allocation state is protected by mutexes inside the disk scheduler controller.
- **State management**: The disk space scheduling logic is computed from a new structure `DiskAllocation` stored in Longhorn CR spec. This structure is updated atomically only by the disk schedule controller.
- **Resource object creation**: Before resource controllers instantiate the corresponding data or process on given disk, including the volume replica instance and the backing image copy, the resource controller must first confirms whether the space is successfully allocated on target disk.

### Disk Scheduling Controller

#### Disk Scheduling

A new CRD `DiskSchedule` is created to store the current scheduling state for each disk, and is reconciled by the disk scheduling controller:

```go=
type DiskSchedulingResourcesStatus struct {
	// Scheduled status
	// +optional
	State DiskScheduleState `json:"state"`
	// Scheduled size
	// +optional
	Size int64 `json:"size"`
}

// NodeSpec defines the desired state of the Longhorn node
type DiskScheduleSpec struct {
	// Disk name from node CR
	// +optional
	Name string `json:"name"`
	// Node ID that the disk locates
	// +optional
	NodeID string `json:"nodeID"`
	// Scheduling requests for volume replicas
	// +optional
	SchedulingReplicas map[string]int64 `json:"schedulingReplicas"`
	// Scheduling requests for backing images
	// +optional
	SchedulingBackingImages map[string]int64 `json:"schedulingBackingImages"`
}

// NodeStatus defines the observed state of the Longhorn node
type DiskScheduleStatus struct {
	// Scheduled status of volume replicas
	// +optional
	ScheduledReplicaStatus DiskSchedulingResourcesStatus `json:"scheduledReplicaStatus"`
	// Scheduled status of backing images
	// +optional
	ScheduledBackingImageStatus DiskSchedulingResourcesStatus `json:"scheduledBackingImageStatus"`
	// Sum of successfully scheduled storage. Should not exceed the Node CR's `status.diskStatus[diskName].storageAvailable`.
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

And the possible schedule state for a resource:

```go=
type DiskScheduleState string

const (
    // resource is successfully scheduled to the disk
	DiskScheduledStatusScheduled = DiskScheduleState("scheduled")
    // resource is rejected by the disk
	DiskScheduledStatusRejected  = DiskScheduleState("rejected")
)
```

For example, to a disk named `example-disk` with UUID `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee` on node `example-node`:

- 2 volume replicas, `r1` (50GiB) and `r2` (50GiB), are already scheduled successfully.
- 1 volume replica, `r3` (500GiB), tried to be scheduled to this node, but have no sufficient space for it.
- 1 volume replica, `r4` (5GiB), is waiting for scheduling.
- 2 backing image copies, `b1` (50GiB) and `b2` (50GiB), are already scheduled successfully.
- Totally 200GiB (`214748364800` bytes) is already scheduled.

```yaml=
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
  schedulingReplicas:
    r1: 53687091200
    r2: 53687091200
    r3: 536870912000
    r4: 5368709120
  SchedulingBackingImages:
    b1: 53687091200
    b2: 53687091200
status:
  scheduledReplicaStatus:
    r1:
      state: scheduled
      size: 53687091200
    r2:
      state: scheduled
      size: 53687091200
    r3:
      state: rejected
      size: 0
  scheduledBackingImageStatus:
    b1:
      state: scheduled
      size: 53687091200
    b2:
      state: scheduled
      size: 53687091200
  storageScheduled: 214748364800
  conditions:
    - lastProbeTime: ""
      lastTransitionTime: "2006-01-02T15:04:05Z"
      message: Disk example-disk is ready for scheduling on node example-node
      reason: ""
      status: "True"
      type: Schedulable
```

The Node Controller creates or deletes DiskSchedule Custom Resources (CRs) corresponding to each entry in `Node.status.diskStatus`. Inside the disk schedule controller, the scheduling status is protected by a mutex.

### Disk Space Allocation

A resource to be scheduled is defined as:

- A resource recorded in `schedulingReplicas` or `schedulingBackingImages` of a DiskSchedule's spec that is acquiring space, and
- A resource not yet recorded in `scheduledReplicaStatus` or `scheduledBackingImageStatus` of a DiskSchedule's status, or whose scheduled size is less than its required space.

Before the scheduling controller allocates space to any resource, it first collects the maximum schedulable space from `Node.status.diskStatus[diskName].storageAvailable`. After each DiskSchedule reconciliation, the total allocated resource size must not exceed this value.

$$storageScheduled = \sum(scheduledReplicaStatus) + \sum(scheduledBackingImageStatus)$$

$$storageScheduled \le storageAvailable$$

In a single DiskSchedule reconciliation, if multiple resources require simultaneous scheduling, the scheduling controller does not guarantee the order of scheduling.

#### Replica Creation

When the Volume Controller replenishes replicas:

1. The volume controller creates a Replica CR without specifying the node or disk.
2. During volume CR status reconciliation, the Volume Controller evaluates the disk candidate across all DiskSchedule CRs, assigns the node and disk to the Replica CR, and submits a scheduling request by appending to `schedulingReplicas` in the target DiskSchedule CR spec.
3. The scheduling controller assesses whether the disk can accommodate the replica, then records the result in the DiskSchedule CR status.
4. If a replica in the DiskSchedule CR is marked as `rejected` with a zero size, the volume controller receives the DiskSchedule CR update event, removes the scheduling request from the DiskSchedule CR spec, and retries from step 2.
5. If a replica in the DiskSchedule CR transitions to `scheduled`, the Replica Controller proceeds with instance creation on the assigned disk.

#### Volume Expansion

When a volume expansion is requested:

1. The volume controller updates the required size in all DiskSchedule CRs for existing replicas before updating the `volumeSize` in instance spec.
2. For each disk, the Scheduling Controller evaluates whether the resize can be accommodated, records the result in the DiskSchedule CR status, and the Volume Controller holds the expansion until all replica expansion requests are reconciled in the DiskSchedule CRs.
3. After all DiskSchedule CRs are reconciled, if any replica is marked as `rejected` with an unchanged non-zero size, the Volume Controller receives the DiskSchedule CR update event and processes the expansion failure.
4. If all replicas transition to `scheduled` in the DiskSchedule CRs with the expanded size, the volume controller proceeds with the size expansion by updating `volumeSize` in the corresponding engine and replicas.

#### Backing Image Copy Creation

When the Backing Image Controller replenishes copies:

1. The backing image controller evaluates the disk candidates across all DiskSchedule CRs, adds the copy to `BackingImageSpec.DiskFileSpecMap`, and submits a scheduling request by appending to `schedulingBackingImages` in the target DiskSchedule CR spec.
2. The scheduling controller assesses whether the disk can accommodate the copy and records the result in the DiskSchedule CR status.
3. If a copy in the DiskSchedule CR is marked as `rejected` with a zero size, the backing image controller receives the DiskSchedule CR update event, removes the scheduling request from the DiskSchedule CR spec, and retries from step 1.
4. If a copy in the DiskSchedule CR transitions to `scheduled`, the Backing Image Controller proceeds with copy creation on the assigned disk.

### Resource Deallocation

Resource deallocation is requested by removing resource records in the DiskSchedule spec.

- **Replica**: deallocation is requested by the scheduler controller when a replica CR disappears from the cluster.
- **Backing image copy**: deallocation is requested by the scheduler controller when an image copy disappears from both the `BackingImageSpec.DiskFileSpecMap` and `BackingImageStatus.DiskFileStatusMap`

## test plan

### Concurrent Replica Allocation

### Concurrent Backing Image Copy Allocation

### Concurrent Disk Expansion
