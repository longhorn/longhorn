# Synchronized Disk Scheduler

## Summary

Introduce a centralized disk scheduler to schedule replicas and backing images.

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

- Prevent race conditions in replica and backing image scheduling by centralizing allocation in a single active instance.
- Unify allocation logic for replicas and backing images to avoid duplicated code and inconsistent capacity checks.
- Support volume expansion by providing a reservation mechanism that checks and pre-allocates space across multiple disks atomically.
- Ensure high availability of the cross-node atomic scheduler.

### Non-goals

- No resource allocation algorithm improvement, including disk selection and balancing.
- The new scheduler implementation does not reflect the disk usage change outside of Longhorn.
- CR validator-level allocation: even though a volume expansion request is submit by mutate the volume CR, there is still chance to reject the expansion by the scheduler.

## Proposal

Introduce centralizing scheduling in a leader-elected gRPC server, recording the allocated disk resource in the Kubernetes CR. The controllers must allocate disk space via this scheduler server before schedule a replica or backing image copy to a disk. The server will synchronize operations using an internal mutex and update allocation state in the Longhorn Node CR's Spec. This ensures that all allocations atomic at the API level.

### User Stories

- **Concurrent PVC Creation**: Multiple PVCs can be created simultaneously in a resource-constrained cluster. Volume replica will not be scheduled if there is no sufficient space for a disk.
- **Concurrent Backing Image Copy Allocation**: Backing image copies will not be allocated to a disk if there is no sufficient space.
- **Volume Expansion**: The volume size expansion will not be proceeded if there is no sufficient space.

## design

### Architecture Overview

- **disk scheduler server**: The disk scheduler server is a gRPC service hosted by Longhorn manager daemonset replicas.
- **gRPC interface**: The methods for allocation, deallocation, reuse, and query the disk space resource.
- **Synchronization**: The disk allocation state is protected by mutexes inside the disk scheduler server.
- **State management**: The disk space scheduling logic is computed from a new structure `DiskAllocation` stored in Longhorn Node spec. This structure is updated atomically only by the disk scheduler.
- **Resource object creation**: Before the controllers assign a disk to a resource, including the volume replica and the backing image copy, the controller must first allocate the disk space via a gRPC call to the disk scheduler server.

### Disk Scheduler Service

Each Longhorn manager replicas join a `longhorn-manager-disk-scheduler-lock` lease election, and the lease leader hosts a disk scheduler gRPC server instance under a new service `longhorn-replica-scheduler` with port `9504`. 

#### Disk Scheduler API: gRPC Interface

```protobuf
service DiskScheduler {
  // Volume replica operations
  rpc ScheduleReplica(ScheduleReplicaRequest) returns (ScheduleReplicaReply);
  rpc ReuseFailedReplica(ReuseFailedReplicaRequest) returns (ScheduleReplicaReply);
  rpc ExpandVolume(ExpandVolumeRequest) returns (ExpandVolumeReply);
  rpc DeallocateReplica(DeallocateReplicaRequest) returns (DeallocateReplicaReply);

  // Backing image copy operations
  rpc ScheduleBackingImage(ScheduleBackingImageRequest) returns (ScheduleBackingImageReply);
  rpc DeallocateBackingImage(DeallocateBackingImageRequest) returns (DeallocateBackingImageReply);

  // Read-only queries
  rpc FindDiskCandidates(FindDiskCandidatesRequest) returns (DiskListReply);
}
```

The following original replica scheduler read-only information fetching methods won't be protected by the scheduler server, and can be computed from the CRs:

- `RequireNewReplica`: returns the time period before creating a new replica
- `FilterNodesSchedulableForVolume`: returns nodes that suitable for given volume
- `FindDiskCandidates`: return disks that suitable for given volume
- `GetDiskSchedulingInfo`: returns disk status from given disk spec & status
- `IsDiskUnderPressure`: utility function
- `IsSchedulableToDisk`: utility function
- `IsSchedulableToDiskConsiderDiskPressure`: utility function
- `ListSchedulableNodes`: list all nodes available to serve replica instances for given data engine type

#### Disk Scheduling

A new field in Longhorn node to store the current scheduling state for each node:

```go
type NodeSpec struct {
	...
	// map[diskName]DiskAllocation: allocation status for each disk
	DiskAllocations map[string]DiskAllocation `json:"diskAllocations,omitempty"`
}

type DiskAllocation struct {
	// (map[replicaName]size) disk space allocated for each replica
	Replicas map[string]int64 `json:"replicas,omitempty"`

	// (map[backingImageName]size) disk space allocated for each backing image copy
	BackingImages map[string]int64 `json:"backingImages,omitempty"`
}
```

For example, a 2-disk node, and there are 2 replicas and 2 backing image copies allocated to `disk1`:

```yaml
apiVersion: longhorn.io/v1beta2
kind: Node
...
spec:
  allowScheduling: true
  disks:
    disk1: ...
    disk2: ...
  diskAllocations:
    disk1:
      replicas:
        replica1: 12345
        replica2: 12345
      backingImages:
        image1: 12345
        image2: 12345
    disk2:
      ...
  ...
```

- All exposed gRPC are protected by single mutex.
- To allocate disk space for a resource, instead of `NodeStatus.DiskStatus[name].StorageScheduled`, scheduler calculate the schduled disk size from the sum of `NodeSpec.DiskAllocations[name]`

### Resource Allocation

#### Replica Creation

When volume controller replenishes replicas:

1. Replica CR is created without specifying the node and disk.
2. During reconciling the replica CR status stage, the controller asks disk scheduler server to schedule the replica CR to a proper disk.
    - If there's no disk that meets the requirement of this replica, returns an error.
    - If the scheduler successfully find a disk to schedule the replica, record the allocated replica in `DiskAllocations.Replicas`.
3. Volume controller then update the replica CR with the scheduling result.

#### Volume Expansion

When a volume expansion is requested:

1. The volume controller update the volume size in engine spec.
2. The engine controller confirms the expansion requirement.
3. The engine controller asks disk scheduler server to expand the size for all replicas of this volume:
    - If any disk of a replica does not meet the requirement for expansion, returns an error without touching `DiskAllocations`.
    - Otherwise to each expanded replica, update the `DiskAllocations.Replicas` for each disk.
4. After the scheduler successfully expand the replica size, the engine controller contitnues to issue the volume expansion RPC.

#### Backing Image Copy Creation

When backing image controller replenishes copies:

1. The controller asks disk scheduler server to schedule the image copy to a proper disk.
    - If there's no disk that meets the requirement of this copy, returns an error
    - If the scheduler successfully find a node disk to schedule the copy, record the allocated copy in `DiskAllocations.BackingImages`.
2. Backing image controller then update the backing image CR's `DiskFileSpecMap` for the successfully scheduling

### Resource Deallocation

Disk scheduler's deallocation RPC should be invoked by the controllers.

- **Replica**: `DeallocateReplica` is invoked by the node controller when a replica CR disapears from the cluster.
- **Backing image copy**: `DeallocateBackingImage` is invoked when the backing image controller removing a copy from both `BackingImageSpec.DiskFileSpecMap` and `BackingImageStatus.DiskFileStatusMap`

## test plan

### Concurrent Replica Allocation

### Concurrent Backing Image Copy Allocation

### Concurrent Disk Expansion
