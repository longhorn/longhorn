# Single Logical Volume Store Across Multiple Disks
## Summary

Enable Longhorn v2 data engine to aggregate multiple disks into a single logical volume store (LVS) using SPDK RAID Concat. This allows volumes to exceed the capacity of a single disk, while maintaining compatibility with both AIO and NVMe bdev drivers.

### Related Issues

https://github.com/longhorn/longhorn/issues/10260

## Motivation

The current v2 data engine restricts each disk to one logical volume store (LVS), making the maximum volume size limited by a single disk’s physical capacity. For setups where a node contains multiple small disks, this prevents users from provisioning larger volumes.

To remove this limitation, Longhorn should support creating a single LVS that spans multiple disks—while preserving the existing scheduling, data-path, and replica semantics.

### Goals

- Create one aggregated disk from multiple physical disks using SPDK RAID Concat.
- Support both AIO and NVMe bdev drivers.
- Expose the aggregated disk as a single LVS to Longhorn.
- Maintain the same replica creation and volume operations as before.

### Non-goals

- Dynamically adding or removing disks from the aggregated set after creation.
- Handling or tolerating disk failures within an aggregated disk.
- Supporting different type of disk drivers in one aggregate.

## Proposal

Today, the data-path is: `(physical NVMe disk) → NVMe bdev → LVS`
The new design becomes: `(multiple NVMe disks) → NVMe bdevs → RAID Concat bdev → LVS`

```
┌────────────────────────────────────────────┐
│               Physical Layer               │
└────────────────────────────────────────────┘
        ├── NVMe Disk 1
        └── NVMe Disk 2

┌────────────────────────────────────────────┐
│               SPDK Bdev Layer              │
└────────────────────────────────────────────┘
        ├── NVMe Bdev (from Disk 1)
        └── NVMe Bdev (from Disk 2)

┌────────────────────────────────────────────┐
│                 RAID Layer                 │
│            (SPDK RAID Concat Bdev)         │
└────────────────────────────────────────────┘
        └── Raid Bdev (Concat)
              ├── NVMe Bdev (Disk 1)
              └── NVMe Bdev (Disk 2)

┌────────────────────────────────────────────┐
│                 LVS Layer                  │
└────────────────────────────────────────────┘
        └── LVStore
```

## Design

- SPDK `RAID Concat` performs linear concatenation of disks. It does not stripe or relocate metadata.
- `LVS` metadata is created on top of the concat bdev, not on individual disks.
- All `LVOL` operations remain unchanged.

Formation Rules:
- All disks must use the same SPDK driver (all NVMe or all AIO).
- Minimum disk count = 1.
- Base bdev list is immutable after creation.
- RAID concat name is derived from Longhorn disk name.

**RAID Concat**:
- Purpose: capacity aggregation
- Data layout: linear / sequential
- strip_size_kb: not used
- Performance (1 bdev): same as raw disk; no overhead
- Performance (multiple bdevs): no improvement; just larger capacity
- Failure behavior: any base disk failure = data lost
- SPDK IO path: direct passthrough (minimal CPU usage)
- Typical overhead: very low
- Best use case: merge disks into one larger logical device
- Size: sum of all base disks (subject to strip-size alignment truncation)

The reason we choose `RAID Concat` instead of `RAID 0` is to aggregate disk capacity without wasting space and without adding performance overhead for a single-disk setup. Although our current design does not add a RAID layer when only one disk is present, using `RAID Concat` provides a clean path to unify the storage stack in the future.

### Implementation Overview

For a **single disk path**, the original storage stack is preserved. The `RAID Concat` layer is applied only when **multiple disk paths** are provided.

- **Block Device Construction**
Each disk path is validated and converted into an SPDK bdev using its corresponding driver.
Bdev names are generated based on the disk name and sanitized path to ensure uniqueness at the SPDK layer.

```go
// generateBdevDiskName returns a valid SPDK bdev name by combining the disk
// name with a sanitized version of the disk path. The disk path is cleaned so
// that only SPDK-safe characters remain (e.g., "0000:00:1e.0" → "<diskName>-0000-00-1e-0", "/dev/sda -> <diskName>-dev-sda'").
func generateBdevDiskName(diskName, diskPath string) string {
	return fmt.Sprintf("%s-%s", diskName, sanitizeBdevComponent(diskPath))
}

func sanitizeBdevComponent(s string) string {
	var allowed = func(r rune) bool {
		return (r >= 'a' && r <= 'z') ||
			(r >= 'A' && r <= 'Z') ||
			(r >= '0' && r <= '9') ||
			r == '-' || r == '_'
	}

	b := strings.Builder{}
	for _, r := range s {
		if allowed(r) {
			b.WriteRune(r)
		} else {
			b.WriteRune('-')
		}
	}
	// collapse repeated '-'
	result := regexp.MustCompile(`-+`).ReplaceAllString(b.String(), "-")
	return strings.Trim(result, "-")
}
```

Importantly, although Linux device names (e.g., /dev/nvme1n1) may change after a reboot due to kernel-level enumeration, SPDK bdevs are identified by persistent PCI-based naming (NvmeXnY), not by Linux device paths. Therefore, device renaming in the kernel does not affect existing SPDK bdevs.

- **RAID Aggregation**
All per-disk SPDK bdevs are aggregated into a single `RAID Concat` bdev.

Before creation, the base bdev names are sorted to enforce a deterministic and persistent ordering.This guarantees stable RAID layout construction across reboots and ensures that the resulting RAID bdev can reliably serve as the base device for the logical volume store.

- **LVStore Creation**
A single LVS is created on top of the RAID bdev. Existing LVStores are reused when possible; otherwise, a new one is created.

- **Metadata Management**
DiskID and driver information are generated from all disk paths and stored as part of the Disk object. DiskGet reconstructs state by querying the RAID bdev and refreshing metadata.

- **Cleanup Path**
Disk deletion removes the RAID bdev first, then deletes each underlying bdev, handling missing devices gracefully.

#### Entire Create Process

DiskCreate (gRPC → Engine SPDK)
├─ Check existing disk
│  ├─ If Ready → return DiskGet()
│  └─ Else create new Disk and store in diskMap
│
├─ Background goroutine
│  └─ Acquire diskCreateLock (serialize SPDK operations)
│     └─ Run SPDK disk creation pipeline:
│
│        Disk.DiskCreate()
│        ├─ Validate inputs (diskName, diskPaths)
│        ├─ Detect exact disk driver (ensure consistent across paths)
│        ├─ addBlockDevice()
│        │   ├─ Create bdev for each disk path
│        │   ├─ Build bdev list; create `RAID concat` if multiple paths
│        │   └─ Create or reuse `lvstore` mapped to base bdev
│        ├─ getDiskID() → Stable disk identifier from paths
│        ├─ Update Disk fields (driver, ID)
│        ├─ lvstoreToDisk() → Load `lvstore` metadata into Disk
│        └─ Mark Disk state = Ready
│     │
│     └─ If DiskCreate succeeded:
│         └─ Start scan loop (verify() until success/timeout)
│
└─ Return initial Disk state (creation proceeds asynchronously)

> Note: For cases where the creation of some base bdevs fails, no rollback is performed, consistent with the current disk creation behavior.

### RPC Update

The field `string path` is now updated to `repeated string path` in both `disk.proto` and `spdk.proto` to support multiple physical disk paths for a single logical disk.

```proto
message Disk {
    string id = 1;
    string uuid = 2;
    repeated string path = 3;
    string type = 4;
    int64 total_size = 5;
    string disk_name = 2;
    string disk_uuid = 3;
    repeated string disk_path = 4;
    int64 block_size = 5;
    string disk_driver = 6;
}
```

```proto
message DiskCreateRequest {
    string disk_name = 1;
    string disk_uuid = 2;
    repeated string disk_path = 3;
    int64 block_size = 4;
    string disk_driver = 5;
}
```

```proto
message DiskGetRequest {
    string disk_name = 1;
    string disk_driver = 2;
    repeated string disk_path = 3;
}
```
``` proto
message DiskDeleteRequest {
    string disk_name = 1;
    string disk_uuid = 2;
    repeated string disk_path = 3;
    string disk_driver = 4;
}
```

### Custom Resource Update

#### Method 1 - Direct Type Change

Changing `Disk.Spec.Path` and `Disk.Status.DiskPath` from `string` to `[]string` is a destructive update. Existing CRs store these fields as strings, so the informer cannot unmarshal them into a slice, causing controller failures during upgrade.
Therefore, we may need a non-breaking upgrade approach.

Pros:

- Clean schema
- No deprecated fields

Cons:

- Breaking change: old CRs fail to unmarshal
- Controller crashes; upgrade becomes impossible
- Requires CRD versioning + conversion webhook or any upgrade method

```go
type DiskSpec struct {
	// +kubebuilder:validation:Enum=filesystem;block
	// +optional
	Type DiskType `json:"diskType"`
	// +optional
	Path []string `json:"path"`
	// +kubebuilder:validation:Enum="";auto;aio;nvme
	// +optional
	DiskDriver DiskDriver `json:"diskDriver"`
	// +optional
	AllowScheduling bool `json:"allowScheduling"`
	// +optional
	EvictionRequested bool `json:"evictionRequested"`
	// +optional
	StorageReserved int64 `json:"storageReserved"`
	// +optional
	Tags []string `json:"tags"`
}

type DiskStatus struct {
	// +optional
	// +nullable
	Conditions []Condition `json:"conditions"`
	// +optional
	StorageAvailable int64 `json:"storageAvailable"`
	// +optional
	StorageScheduled int64 `json:"storageScheduled"`
	// +optional
	StorageMaximum int64 `json:"storageMaximum"`
	// +optional
	// +nullable
	ScheduledReplica map[string]int64 `json:"scheduledReplica"`
	// +optional
	// +nullable
	ScheduledBackingImage map[string]int64 `json:"scheduledBackingImage"`
	// +optional
	DiskUUID string `json:"diskUUID"`
	// +optional
	DiskName string `json:"diskName"`
	// +optional
	DiskPath []string `json:"diskPath"`
	// +optional
	Type DiskType `json:"diskType"`
	// +optional
	DiskDriver DiskDriver `json:"diskDriver"`
	// +optional
	FSType string `json:"filesystemType"`
	// +optional
	InstanceManagerName string `json:"instanceManagerName"`
	// +optional
	HealthData map[string]HealthData `json:"healthData,omitempty"`
	// +optional
	HealthDataLastCollectedAt metav1.Time `json:"healthDataLastCollectedAt,omitempty"`
}
```

#### Method 2 - Add New Fields and Keep Old Ones

We will keep `Disk.Spec.Path` and `Disk.Status.DiskPath` as `string` for backward compatibility.
To support multiple paths, we introduce new fields `Disk.Spec.Paths` and `Disk.Status.DiskPaths` with type `[]string`.

The original `Path` and `DiskPath` fields will remain solely for compatibility during upgrades, while all new logic will use `Paths` and `DiskPaths` for actual operations.

Pros:
- Fully backward compatible
- Safe upgrade; old CRs still valid
- No webhook needed

Cons:
- Temporary duplication of fields
- Having similar fields may cause confusion for users and developers.

```go
type DiskSpec struct {
	// +kubebuilder:validation:Enum=filesystem;block
	// +optional
	Type DiskType `json:"diskType"`
	// +optional
	Path string `json:"path"`
	// +kubebuilder:validation:Enum="";auto;aio;nvme
	Paths []string `json:"paths"`
	// +optional
	DiskDriver DiskDriver `json:"diskDriver"`
	// +optional
	AllowScheduling bool `json:"allowScheduling"`
	// +optional
	EvictionRequested bool `json:"evictionRequested"`
	// +optional
	StorageReserved int64 `json:"storageReserved"`
	// +optional
	Tags []string `json:"tags"`
}

type DiskStatus struct {
	// +optional
	// +nullable
	Conditions []Condition `json:"conditions"`
	// +optional
	StorageAvailable int64 `json:"storageAvailable"`
	// +optional
	StorageScheduled int64 `json:"storageScheduled"`
	// +optional
	StorageMaximum int64 `json:"storageMaximum"`
	// +optional
	// +nullable
	ScheduledReplica map[string]int64 `json:"scheduledReplica"`
	// +optional
	// +nullable
	ScheduledBackingImage map[string]int64 `json:"scheduledBackingImage"`
	// +optional
	DiskUUID string `json:"diskUUID"`
	// +optional
	DiskName string `json:"diskName"`
	// +optional
	DiskPath string `json:"diskPath"`
	// +optional
	DiskPaths []string `json:"diskPath"`	
	// +optional
	Type DiskType `json:"diskType"`
	// +optional
	DiskDriver DiskDriver `json:"diskDriver"`
	// +optional
	FSType string `json:"filesystemType"`
	// +optional
	InstanceManagerName string `json:"instanceManagerName"`
	// +optional
	HealthData map[string]HealthData `json:"healthData,omitempty"`
	// +optional
	HealthDataLastCollectedAt metav1.Time `json:"healthDataLastCollectedAt,omitempty"`
}
```

#### Method 3 - No Change (Current Choice)

Keep `Disk.Spec.Path` and `Disk.Status.DiskPath` as `string`.
To support multiple paths, store them in a single string separated by `;`, for example: `0000:00:1e.0;0000:00:1f.0`

Pros:
- Simplest approach with minimal schema changes
- No CRD or compatibility issues

Cons:
- Overloads a single field with multiple semantic values
- Requires manual parsing and joining in code

### User Experience In Detail

Users configure an aggregated disk by specifying multiple physical disk paths.

### Other Resource Impact

- **replica.spec.diskPath**

```yaml
"spec": {
	"active": true,
	"backingImage": "",
	"dataDirectoryName": "v1-702a737b",
	"dataEngine": "v2",
	"desireState": "running",
	"diskID": "d12b4c71-7544-47ad-b240-cabec1b94fbd",
	"diskPath": "0000:00:1e.0;0000:00:1f.0",
	"engineName": "v1-e-0",
	"evictionRequested": false,
	"failedAt": "",
	"hardNodeAffinity": "",
	"healthyAt": "2025-12-12T05:02:01Z",
	"image": "davidcheng0922/longhorn-instance-manager:1212-0",
	"lastFailedAt": "",
	"lastHealthyAt": "2025-12-12T05:02:01Z",
	"logRequested": false,
	"migrationEngineName": "",
	"nodeID": "ip-172-31-18-199.ap-southeast-2.compute.internal",
	"rebuildRetryCount": 0,
	"revisionCounterDisabled": false,
	"salvageRequested": false,
	"snapshotMaxCount": 250,
	"snapshotMaxSize": "0",
	"unmapMarkDiskChainRemovedEnabled": false,
	"volumeName": "v1",
	"volumeSize": "21474836480"
},
```

- **nodes.status.diskStatus**, healthData support multiple disks health data
```yaml
"healthData": {
	"0000:00:1e.0": {
		"attributes": [
			{
				"name": "Critical Warning",
				"rawValue": 0
			},
			{
				"name": "Temperature Celsius",
				"rawString": "unknown",
				"rawValue": 0
			},
			{
				"name": "Available Spare Percentage",
				"rawValue": 0
			},
			{
				"name": "Available Spare Threshold Percentage",
				"rawValue": 0
			},
			{
				"name": "Percentage Used",
				"rawValue": 0
			},
			{
				"name": "Data Units Read",
				"rawValue": 0
			},
			{
				"name": "Data Units Written",
				"rawValue": 0
			},
			{
				"name": "Host Read Commands",
				"rawValue": 0
			},
			{
				"name": "Host Write Commands",
				"rawValue": 0
			},
			{
				"name": "Controller Busy Time",
				"rawValue": 0
			},
			{
				"name": "Power Cycles",
				"rawValue": 0
			},
			{
				"name": "Power On Hours",
				"rawValue": 0
			},
			{
				"name": "Unsafe Shutdowns",
				"rawValue": 0
			},
			{
				"name": "Media Errors",
				"rawValue": 0
			},
			{
				"name": "Number of Error Log Entries",
				"rawValue": 0
			},
			{
				"name": "Warning Temperature Time Minutes",
				"rawValue": 0
			},
			{
				"name": "Critical Composite Temperature Time Minutes",
				"rawValue": 0
			}
		],
		"diskName": "disk-1",
		"diskType": "nvme",
		"firmwareVersion": "1.0",
		"healthStatus": "PASSED",
		"modelName": "Amazon Elastic Block Store",
		"serialNumber": "vol0ad2fd2942dfbf697",
		"source": "SPDK"
	},
	"0000:00:1f.0": {
		"attributes": [
			{
				"name": "Critical Warning",
				"rawValue": 0
			},
			{
				"name": "Temperature Celsius",
				"rawString": "unknown",
				"rawValue": 0
			},
			{
				"name": "Available Spare Percentage",
				"rawValue": 0
			},
			{
				"name": "Available Spare Threshold Percentage",
				"rawValue": 0
			},
			{
				"name": "Percentage Used",
				"rawValue": 0
			},
			{
				"name": "Data Units Read",
				"rawValue": 0
			},
			{
				"name": "Data Units Written",
				"rawValue": 0
			},
			{
				"name": "Host Read Commands",
				"rawValue": 0
			},
			{
				"name": "Host Write Commands",
				"rawValue": 0
			},
			{
				"name": "Controller Busy Time",
				"rawValue": 0
			},
			{
				"name": "Power Cycles",
				"rawValue": 0
			},
			{
				"name": "Power On Hours",
				"rawValue": 0
			},
			{
				"name": "Unsafe Shutdowns",
				"rawValue": 0
			},
			{
				"name": "Media Errors",
				"rawValue": 0
			},
			{
				"name": "Number of Error Log Entries",
				"rawValue": 0
			},
			{
				"name": "Warning Temperature Time Minutes",
				"rawValue": 0
			},
			{
				"name": "Critical Composite Temperature Time Minutes",
				"rawValue": 0
			}
		],
		"diskName": "disk-1",
		"diskType": "nvme",
		"firmwareVersion": "1.0",
		"healthStatus": "PASSED",
		"modelName": "Amazon Elastic Block Store",
		"serialNumber": "vol096627bbd6ef435c9",
		"source": "SPDK"
	}
},
```


### UI Support 

- Allow V2 disks to be created with multiple physical disk paths.
- Disallow multiple disk paths for V1 disks.

### Test plan

**Single Path Disk**
- Create / Delete V2 Block Disks with `single` disk path
- Create / Attach / Delete / IO the v2 volume

**Multiple Paths Disk**

- Create / Delete V2 Block Disks with `multiple` disk paths
- Disk capacity is aggregated across all paths.
- Create / Attach / Delete / IO the v2 volume
- Disk Heahlth data collect works fine

**Upgrade**
- Create v2 volume and attach with original version
- IO, `sudo dd if=/dev/urandom of=/dev/longhorn/v1 bs=1G count=1`
- Hash `sudo sha256sum /dev/longhorn/v1` record the hash
- Detach volume and upgrade the `longhorn-manager` and `instance-manager`
- Once upgrading complete, re-attach the volume and hash again for checking the result

**Negative Test**
- Create disk with the different kinds of driver(aio+nvme) -> Should fail, not support it

### Upgrade strategy

- A single V2 Disk will continue using the previous storage stack (bdev → lvs) instead of switching to the new one.


## Note

Custom Resource`ReplicaSpec`,`BackingImageManagerSpec` and `BackingImageDataSourceSpec` DiskPath stay type `string`
