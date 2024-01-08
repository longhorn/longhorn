# Replica Auto-Balance Pressured Disks On Same Node

## Summary

This proposal enhances Longhorn's replica auto-balancing feature to address disk space pressure caused by growing volumes. It introduces a new setting, `replica-auto-balance-disk-pressure-percentage`, allowing users to define a percentage threshold for automatic action.

### Related Issues

https://github.com/longhorn/longhorn/issues/4105

## Motivation

### Goals

- **Reduced Manual Intervention:** Automatic rebalances replicas during disk pressure, minimizing manual effort.
- **Improved Performance:** Potentially faster replica rebuilds within the same node using local file copy.

### Non-goals [optional]

- This proposal does not address auto-balancing replicas across different nodes. Longhorn prioritizes balancing across nodes and zones before disks within a node.
- Performance evaluation of local file copy is outside the scope of this proposal.

## Proposal

### User Stories

#### Story 1: Reduced Manual Intervention

- **As a Longhorn user:** I want Longhorn to automatically handle replica movement based on disk pressure, minimizing manual intervention.
- **Before:** I need to regularly check disk space and manually trigger replica movement to address pressure situations.
- **After:** Longhorn automatically rebalances replica when disk pressure threshold percentage is reached, freeing me up for other tasks.

#### Story 2: Improved Replica Rebuild Performance

- **As a Longhorn user:** I want Longhorn to leverage local file copy for replica rebuilding within the same node, potentially improving rebuild speed.
- **Before:** Replica rebuild relies on TCP transfer, which can be slower than local file copy.
- **After:** When rebuilding replicas on the same node, Longhorn uses local file copy for data transfer.

### User Experience In Detail

1. **Setup:**
	- You have a Longhorn cluster with multiple nodes, each containing multiple schedulable disks.
	- Configure via Longhorn UI or Kubernetes CRD.
		- Set `replica-auto-balance` to `best-effort`.
		- Define the `replica-auto-balance-disk-pressure-percentage` (e.g., 90% used space triggers disk rebalancing).
		- Set `replica-soft-anti-affinity` to `enabled` to allow replicas on the same node.
1. **Deploy Workload:** Deploy workload utilizing Longhorn volumes.
1. **Replica Disk Reaches Pressured Threshold:**
	- Longhorn automatically find another disk on the same node with more available disk space.
	- Longhorn rebuild replica on the same node using the local file copy for data transfer.


## Design

### New Setting: `replica-auto-balance-disk-pressure-percentage`

This setting allows defining the disk pressure threshold (percentage of used space) that triggers automatic rebalancing. Its only functional when:
- `replica-auto-balance` is set to `best-effort`.
- `replica-soft-anti-affinity` is set to `enabled`.
```go
SettingDefinitionReplicaAutoBalanceDiskPressurePercentage = SettingDefinition{
	DisplayName: "Replica Auto Balance Disk Pressure Threshold (%)",
	Description: "Sets the threshold percentage of disk space utilization that triggers replica auto-balance.\n\n" +
		"When the threshold percentage is reached, Longhorn automatically rebuilds replicas under disk pressure onto another disk within the same node.\n\n" +
		"**Note:** This setting is effective only under the following conditions:\n" +
		"- **Replica Auto Balance** is set to **best-effort**.\n" +
		"- **Replica Node Level Soft Anti-Affinity** is set to **enabled**.\n" +
		"- There must be at least one other disk on the node with sufficient available space.\n\n" +
		"To disable this feature for replica auto-balance (best-effort), set the value to 0.",
	Category:    SettingCategoryScheduling,
	Type:        SettingTypeInt,
	Required:    true,
	ReadOnly:    false,
	Default:     "90",
}
```

#### Balancing Replicas In Disk Pressure

1. **Auto-Balance Check** The volume controller checks if replicas are node and zone balanced and then verifies if any are under the disk pressure threshold percentage.

	```golang
	func (rcs *ReplicaScheduler) IsDiskUnderPressure(diskPressurePercentage int64, info *DiskSchedulingInfo) bool {
		storageUnusedPercentage := int64(0)
		storageUnused := info.StorageAvailable - info.StorageReserved
		if storageUnused > 0 && info.StorageMaximum > 0 {
			storageUnusedPercentage = storageUnused * 100 / info.StorageMaximum
		}
		return storageUnusedPercentage < 100 - int64(diskPressurePercentage)
	}
	```

1. **Replica Candidate Selection:** The volume controller prioritizes replicas under pressure by selecting the first on from the sorted list of `node.Status.DiskStatus.ScheduledReplica`. This approach prevents overwhelming a single disk with all pressured replicas.

1. **Candidate Disk Search:** The controller searches for a suitable candidate disk on the same node. This disk must have sufficient available storage to accommodate the replica after the rebuild without exceeding the pressure threshold itself.

	```go
	func (rcs *ReplicaScheduler) IsSchedulableToDiskConsiderDiskPressure(diskPressurePercentage, size, requiredStorage int64, info *DiskSchedulingInfo) bool {
		newDiskUsagePercentage := (requiredStorage + info.StorageScheduled + info.StorageReserved) * 100 / info.StorageMaximum
		logrus.WithFields(logrus.Fields{
			"diskUUID":               info.DiskUUID,
			"diskPressurePercentage": diskPressurePercentage,
			"requiredStorage":        requiredStorage,
			"storageScheduled":       info.StorageScheduled,
			"storageReserved":        info.StorageReserved,
			"storageMaximum":         info.StorageMaximum,
		}).Debugf("Evaluated new disk usage percentage after scheduling replica: %v%%", newDiskUsagePercentage)

		return rcs.IsSchedulableToDisk(size, requiredStorage, info) &&
			newDiskUsagePercentage < int64(diskPressurePercentage)
	}
	```

1. **Replenish Replica With Local File Copy:** Once a candidate replica and disks are identified, the volume controller proceeds with the current replica replenish flow and leverage local file copy for replica rebuilding.


### Local Disk Replica Rebuild

#### Longhorn Manager

During replica rebuilding, if another replica exists on the same node, add the source and target file directories to the `rpc.EngineReplicaAddRequest.LocalSync` for local file copy.

```go
localSync = &etypes.FileLocalSync{
	Source: filepath.Join(nodeReplica.Spec.DiskPath, "replicas", nodeReplica.Spec.DataDirectoryName),
	Target: filepath.Join(targetReplica.Spec.DiskPath, "replicas", targetReplica.Spec.DataDirectoryName),
}
```

#### Longhorn instance manager

1. Introduce `EngineReplicaLocalSync` to `EngineReplicaAddRequest` message in `proxy.proto`.
	```go
	message EngineReplicaAddRequest {
		ProxyEngineRequest proxy_engine_request = 1;

		string replica_address = 2;
		bool restore = 3;
		int64 size = 4;
		int64 current_size = 5;
		bool fast_sync = 6;
		int32 file_sync_http_client_timeout = 7;
		string replica_name = 8;
		int64 grpc_timeout_seconds = 9;
		EngineReplicaLocalSync local_sync = 10;
	}

	message EngineReplicaLocalSync{
		string source = 1;
		string target = 2;
	}
	```

1. Receive Local Sync Information: The proxy server received the `EngineReplicaAddRequest` containing the `FileLocalSync` message.
1. Forward Local Sync Information: The proxy server forwards it to the Longhorn engine's `FilesSyncRequest.FileLocalSync`.

#### Longhorn Engine
1. Introduce `FileLocalsync` to `FileSyncRequest` message in `synagent.proto`.
	```go
	message FilesSyncRequest {
	  string from_address = 1;
	  string to_host = 2;
	  repeated SyncFileInfo sync_file_info_list = 3;
	  bool fast_sync = 4;
	  int32 file_sync_http_client_timeout = 5;
	  FileLocalSync local_sync = 6;
	}

	message FileLocalSync{
		string source = 1;
		string target = 2;
	}
	```

1. Identify Local Sync Request: The sync-agent received the `FileSyncRequest` containing the `FileLocalSync` message.
1. Perform Local File Copy: If the `FileLocalSync` messaage is provided, the sync-agent uses the provided source and target paths to directly copy the replica data within the same node using [CopyFile](https://github.com/longhorn/go-common-libs/blob/2133a7e73771ecdd26494a9c1ed2b31495ffd4f2/io/file.go#L102) function in the go-common-libs repository. The `CopyFile` should work with sparse file, additional unit test should be added to verify the behavior of `CopyFile` with spare files.
1. Fallback to TCP Transfer (if needed): In case of errors during local file copy, the sync-agent removed file created to the target directory and falls back to the approach of transferring data using TCP.

### Test Plan

- Validate this feature alleviates disk pressure within the same node.
- Validate this feature does not attempt to rebuild replica to another disk if the disk will fall below the pressure threshold percentage after replica is rebuilt on it.
- Confirm this feature does not attempt to rebuild all replicas to a the same disk simultaneously, which could cause a rebuilding loop.

### Upgrade strategy

This feature introduces a new setting and is non-disruptive to existing Longhorn system. User can continue using exiting volumes as before and the feature will automatically apply if the cluster have `replica-auto-balance` set to `best-effort` and `replica-soft-anti-affinity` is set to `enabled` during the upgrade process.

### Limitations

In the current Longhorn version, There can be a delay up to 30 seconds for the disk storage usage to reflect after a replica is removed from the disk. This can cause additional replica to be rebuilt before the node controller's disk monitor detects the space change.
