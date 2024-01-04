# Snapshot Space Management

## Summary

This feature allows users to control the count and size of snapshots of a volume.

### Related Issues

https://github.com/longhorn/longhorn/issues/6563

## Motivation

### Goals

- A replica honors snapshot count and size limitations when it creates a new snapshot.
- Users can set snapshot count and size limitation on a Volume.
- Users can set a global default snapshot maximum count.

### Non-goals [optional]

- Snapshot space management on a node or disk level.
- Freeze disk before taking snapshot.
- Auto deleting snapshots if there is no space for creating a new system snapshot.

## Proposal

### User Stories

With snapshot space management, snapshot space usage is controllable. Users can set snapshot limitation on a Volume and evaluate maximum space usage.

### User Experience In Detail

Before snapshot space management:
The default maximum snapshot count for each volume is `250`. This is a constants value in the [source code](https://github.com/longhorn/longhorn-engine/blob/8b4c80ab174b4f454a992ff998b6cb1041faf63d/pkg/replica/replica.go#L33) and users don't have a way to control it. If a volume size is 1G, the maximum snapshot space usage will be 250G.

After snapshot space management:
There is a configurable default maximum snapshot count setting. Users can update it to overwrite the fixed value in the system.
Users can set different maximum snapshot count and size on each volume. A more important volume can have more snapshot space usage.

## Design

### Implementation Overview

#### Settings

Add a new setting definition:

```go
const (
    SettingNameSnapshotMaxCount = SettingName("snapshot-max-count")
)

var (
    SettingDefinitionSnapshotMaxCount = SettingDefinition{
		DisplayName: "Snapshot Maximum Count",
		Description: "Maximum snapshot count for a volume. The value should be between 2 to 250",
		Category:    SettingCategorySnapshot,
		Type:        SettingTypeInt,
		Required:    true,
		ReadOnly:    false,
        Default:     "250",
	}
)
```

#### Volume CRD

Add two fields to `VolumeSpec`:

```go
type VolumeSpec struct {
    // ...
    // +optional
    SnapshotMaxCount int `json:"snapshotMaxCount"`
    // +kubebuilder:validation:Type=string
    // +optional
    SnapshotMaxSize int64 `json:"snapshotMaxSize,string"`
}
```

- If `SnapshotMaxSize` is `0`, it means there is no snapshot size limit for a Volume.

#### Volume mutator

- If `SnapshotMaxCount` is `0`, using the `snapshot-max-count` setting value to update it.
- If a volume is expanded, checking whether `snapshot-max-size` is smaller than `size * 2`. If it is, using `size * 2` to update it.

#### Volume validator

- The `SnapshotMaxCount` should be between `2` to `250`. This limitation includes user and system snapshot. In LH, all snapshots can be merged to one snapshot, so at least one snapshot can't be delete. To create another snapshot, we need to have enough count for it. In conclusion, the minimum value for `SnapshotMaxCount` is `2`.
- If `SnapshotMaxSize` is't `0`. The minimum value for `SnapshotMaxSize` is same as `Size * 2` in a Volume, because a volume can have at least two snapshots.

#### Replica

- Add two fields to `Replica`:
    ```go
    type Replica struct {
        // ...
        snapshotMaxCount int
        snapshotMaxSize int64
    }
    ```
- Add a function `GetSnapshotCountUsage` to retrieve snapshot count usage. We should skip the volume head, backing disk, and removed disks.
- Add a function `GetSnapshotSizeUsage` to retrieve total snapshot size usage. We should skip the volume head, backing disk, and removed disks.

#### ReplicaServer

- Add the `remain_snapshot_size` field to `Replica` proto message:
    ```protobuf
    message Replica {
        // ...
        int64 remain_snapshot_size = 17;
    }
    ```
- Update the `getReplica` function to return `SnapshotCountUsage` and `SnapshotSizeUsage` fields.

#### Remote backend

- Add a `RemainSnapshotSize` field to `ReplicaInfo`:
    ```go
    type ReplicaInfo struct {
        // ...
        RemainSnapshotSize int `json:"remainsnapshotSize"`
    }
    ```
- Add a new function `GetSnapshotCountAndSizeUsage` to return current snapshot count and size usage.

#### Replicator

- Add a new function `GetSnapshotCountAndSizeUsage` to return current snapshot count and size usage. We should get the biggest value from all replicas, because replica data may be unsynced when the system is unsteady.

#### Controller engine

- Add a new function `canDoSnapshot` to check whether snapshot count and size usage is under limitation.

#### Manager API

- Add new action `updateSnapshotMaxCount` to `Volume` (`"/v1/volumes/{name}"`) 
- Add new action `updateSnapshotMaxSize` to `Volume` (`"/v1/volumes/{name}"`) 

### Test plan

Integration test plan.

1. `snapshot-max-count` setting
    - Validate the value should be between `2` to `250`.
    - Create a Volume with empty `SnapshotMaxCount` and mutator should replace the value with `snapshot-max-count` setting value.
    - Create a Volume with nonempty `SnapshotMaxCount` and mutator shouldn't update the value.

2. A volume with `1G` size, `2` snapshot max count, and `0` snapshot max size.
    - Create the first snapshot. It should be successful.
    - Create the second snapshot. It should be successful.
    - Create the third snapshot. It should be failed.
    - Delete a snapshot and create a new snapshot. It should be successful.

3. A volume with `1G` size, `250` snapshot max count, and `2.5G` snapshot max size.
    - Write `0.5G` data and create the first snapshot. It should be successful.
    - Write `1G` data and create the second snapshot. It should be successful.
    - Write `1G` data and create the third snapshot. It should be successful.
    - Write `1G` data and create the fourth snapshot. It should be failed.
    - Delete the second or third snapshot and create a new snapshot. It should be successful.

### Upgrade strategy

`None`
