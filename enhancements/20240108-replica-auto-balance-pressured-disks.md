# Replica Auto-Balance Pressured Disks On Same Node

## Summary

This proposal aims to enhance Longhorn's replica auto-balance feature, specifically addressing the challenge of growing volumes causing pressure on available disk space. By introducing the `replica-auto-balance-disk-pressure-percentage`setting, users will have the ability to allow Longhorn to automatically rebuild replica to another disk on the same node with more available storage when disk pressure reaches the user defined threshold. This enhancement active when the `replica-auto-balance` setting is configured as `best-effort`.


### Related Issues

https://github.com/longhorn/longhorn/issues/4105

## Motivation

In typical scenarios, disk space tends to be increasingly occupied over time, especially when volumes replicas are unevenly scheduled across disks. This enhancement triggers volume replica to another disk on the same node when the disk pressure reaches the user-defined threshold, improves space utilization and achieving a more balanced disk load.

### Goals

Introduce the `replica-auto-balance-disk-pressure-percentage` setting for automatic disk rebalancing when reaching a user-defined pressure threshold. This feature is effective when `replicas-auto-balance` is set to `best-effort`.

Introduce file local sync to copy the file when there is another running replica on the same node so the data transfer doesn't need to go through TCP.

### Non-goals [optional]

This enhancement does not encompass auto-balance replicas across disks on different nodes.

## Proposal

### User Stories

#### Story 1

Before: User manually balance replicas when disk space pressures arise due to volume growth.

After: User can set a disk pressure threshold, enabling Longhorn to automatically rebuild replicas to another disk with more available storage on the same node.

### User Experience In Detail

1. Cluster nodes have multiple schedulable disks.
1. Set `replica-auto-balance` to `best-effort`.
1. Set `replica-soft-anti-affinity` to `enabled`.
1. Define the threshold triggering automatic disk rebalance with `replica-auto-balance-disk-pressure-percentage`.
1. Create a workload with Longhorn volume.
1. When the disk reaches the threshold percentage, observe replicas being rebuild to other disks with more available storage on the same node.

### API changes

## Design

### Introduce `replicas-auto-balance-disk-pressure-percentage` setting

```go
SettingDefinitionReplicaAutoBalanceDiskPressurePercentage = SettingDefinition{
	DisplayName: "Replica Auto Balance Disk Limit Percentage",
	Description: "The disk pressure percentage specifies the percentage of disk space used on a node that will trigger a replica auto-balance.",
	Category:    SettingCategoryScheduling,
	Type:        SettingTypeInt,
	Required:    true,
	ReadOnly:    false,
	Default:     "90",
}
```

#### Determine replica count for best-effort auto-balancing

- Balance replicas on node and zones before proceeding to node disk balancing.
- Check if the disk is in pressure and if there is another disk with more actual available storage on the same node, then return the adjustment count and the same node in the candidate node list.
- Select the first node from the candidate node list for schedulinga new replica.
- The scheduler allocates replica to the disk with the most actual available storage, following the current implementation.

#### Cleanup auto-balanced replicas

- Maintain the current implementation to identify preferred replica candidates for deletion.
- With the preferred replica candidates, sort them by actual available storage. If multiple disks have the same actual available storage, further sort by name.
  ```
  storage available - storage reserved
  ```
- Delete the first replica from the sorted list.

### Local disk replica migration

#### Longhorn manager

During the replica rebuilding, check if there is another running volume replica on the same node. If there is, record the source file directory and the target file directory into the `rpc.EngineReplicaAddRequest.LocalSync`.
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
		EngineReplicaLocalSync local_sync = 9;
	}

	message EngineReplicaLocalSync{
		string source = 1;
		string target = 2;
	}
	```
1. Then the proxy server is responsible for proxying the `EngineReplicaAddRequest.LocalSync` to the sync-agent's `FilesSyncRequest.LocalSync`.

#### Longhorn engine
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
1. Then the sync-agent server is responsible for copying the files using `req.SyncFileInfoList` from source to the target directory when `req.FilesSyncRequest.LocalSync` is provided.
1. When the files fails to sync locally, the sync-agent server removes file created to the target directory, then fall back to syncing the files via the TCP transfer.

### Test plan

- Validate automatic replica balance to alleviate disk pressure within the same node.
- Verify that disk auto-balancing does not occur when all disks on the replica nodes are under pressure.

### Upgrade strategy

`N/A`

## Note [optional]

`None`
