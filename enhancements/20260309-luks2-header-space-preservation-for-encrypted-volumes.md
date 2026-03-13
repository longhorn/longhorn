# LUKS2 Header Space Reservation for Encrypted Volumes

## Summary

This enhancement addresses an issue in which the actual block device size presented to the user is 16 MiB smaller than the requested volume size when encryption is enabled. The missing 16 MiB is currently consumed by the LUKS2 encryption header. This proposal handles that overhead transparently at the backend layer, ensuring that users receive the exact usable capacity they requested while correctly managing the offset during volume rebuild, restore, and expansion operations.

### Related Issues

- https://github.com/longhorn/longhorn/issues/9205

## Motivation

When users create a volume of a specific size, for example `10 GiB`, with encryption enabled, Longhorn currently reserves 16 MiB of that space for the LUKS2 metadata header. As a result, the `lsblk` output and the usable filesystem size inside the pod appear as `10 GiB - 16 MiB`. This discrepancy is confusing and can trigger strict size validation checks in some workloads or database applications.

### Goals

- Abstract the 16 MiB LUKS2 header overhead from the user.
- Correctly propagate the calculated backend size (`Requested Size + 16 MiB`) through all core data paths: creation, rebuilding, restoring, and expansion.

### Non-goals

N/A

## Proposal

Add 16 MiB to `Engine.Spec.VolumeSize` and `Replica.Spec.VolumeSize` when `Volume.Spec.Encrypted` is `true`.

### User Stories

Before this enhancement, if a user requests a `10 GiB` PersistentVolumeClaim (PVC) backed by an encrypted Longhorn volume, the actual block device presented to the pod in Kubernetes is `10 GiB - 16 MiB`. This occurs because Longhorn uses 16 MiB internally to store the LUKS2 metadata header. The discrepancy can cause application deployment workflows, such as those used by strict database systems, to fail if they perform hard validation on block device sizes.

After this enhancement, when a user requests a `10 GiB` encrypted volume, they receive exactly `10 GiB` of usable decrypted storage space in the pod. The 16 MiB overhead is automatically added as hidden backend replica capacity and is managed entirely by Longhorn.

### User Experience In Detail

From the end user's perspective, this functionality is fully transparent and requires no configuration changes.

1. A user creates a standard PVC with a storage class name that points to an encrypted Longhorn `StorageClass` and specifies `size: 1GiB`.
2. Longhorn automatically creates a volume with `Size: 1073741824`, while internally adjusting the backend storage allocation to `1 GiB + 16 MiB`.
3. When the workload mounts the volume and the user runs `lsblk` or `df -h`, the reported partition size exactly matches `1G`, rather than the previous `1008M` equivalent.
4. Restoring a backup, taking a snapshot, and expanding a volume all respect this calculation implicitly. If the user expands the volume to `2 GiB`, the Longhorn UI and the Kubernetes PVC reflect `2 GiB`, while Longhorn automatically expands the encrypted backend replica to `2 GiB + 16 MiB`. Existing legacy volumes continue to behave as they did previously without disruption.

### API changes

N/A

## Design

### Implementation Overview

Introduce helper utilities to centralize backend size calculation.

```go
const LUKS2HeaderSize = 16 * 1024 * 1024 // 16 MiB

func getBackendSize(requestedVolumeSize int64, encrypted bool) int64 {
    // The default LUKS2 header size is 16 MiB, so it must be added to the replica size when the volume is encrypted. Otherwise, the device
    // presented to the user will be 16 MiB smaller than the requested size.
    // https://gitlab.com/cryptsetup/cryptsetup/-/wikis/FrequentlyAskedQuestions
    if encrypted {
        return requestedVolumeSize + LUKS2HeaderSize
    }
    return requestedVolumeSize
}
```

#### `controller/volume_controller.go`

When calculating engine and replica sizing, the volume controller will use the new utility.

```go
func (vc *VolumeController) createEngine(v *longhorn.Volume, ...) *longhorn.Engine {
    ...
    engine := &longhorn.Engine{
        Spec: longhorn.EngineSpec{
            VolumeSize: getBackendSize(v.Spec.Size, v.Spec.Encrypted),
            ...
        },
    }
    // ...
}
...
func newReplicaCR(v *longhorn.Volume, e *longhorn.Engine, hardNodeAffinity string) *longhorn.Replica {
    return &longhorn.Replica{
        ...
        Spec: longhorn.ReplicaSpec{
            InstanceSpec: longhorn.InstanceSpec{
                VolumeSize: getBackendSize(v.Spec.Size, v.Spec.Encrypted),
            ...
            }
        }
    }
}
```

#### `engineapi/backup_monitor` `backupstore/backupstore.go`

When backing up a volume snapshot, add the `lhbackup.LonghornBackupParameterEncrypted` parameter.

```go
lhbackup.LonghornBackupParameterEncrypted := `encrypted`

func getBackupParameters(backup *longhorn.Backup, volume *longhorn.Volume) map[string]string {
    parameters := map[string]string{}
    parameters[lhbackup.LonghornBackupParameterEncrypted] = string(volume.Spec.Encrypted)
    ...

    return parameters
}
```

Introduce a new `Encrypted` field in `Volume` in `backupstore.go` to indicate whether the volume is encrypted.

```go
type Volume struct {
    Name       string
    Size       int64 `json:",string"`
    Labels     map[string]string
    ...
    Encrypted  bool `json:",string"`
    ...
```

### Affected Operations

#### Rebuilding

During rebuilding, the volume controller instructs the new replica to provision the correct size. Data synchronization reconstructs the target blocks, and because the underlying block device file accommodates `VolumeSize + 16 MiB`, the snapshot tree and raw sync can safely contain both the LUKS metadata and the encrypted payload.

#### Backup and Restore

Send the `LonghornBackupParameterEncrypted` parameter to `backupstore` so that the volume encryption state is preserved when a backup is created.

When a user restores from a backup, the backup target reads the metadata and the controller provisions a new volume. The volume controller determines whether the backup originated from an encrypted volume, calculates the user-requested `Volume.Spec.Size`, and creates the engine and replicas with the correct `BackendSize`.

#### Expanding

When a user expands a volume:

1. The volume expansion request is received and updates `Volume.Spec.Size`.
2. The volume controller calculates the new `NewBackendSize = NewVolumeSize + 16 MiB`.
3. It updates `Engine.Spec.VolumeSize` and `Replica.Spec.VolumeSize` to the correct expanded size.

## Upgrade Plan

**Existing Encrypted Volumes:**

Update the `Spec.VolumeSize` and `Spec.VolumeEncryptedSize` fields of the engine and replica for existing encrypted volumes if necessary.  
When upgrading the engine, the volume controller creates new replicas with the correct replica size.

## Test Plans

### New Volume Creation

- Create a `1 GiB` encrypted volume.
- Attach it to a pod and run `lsblk` or `fdisk -l` inside the pod.
- **Expected:** The block device shows exactly `1G`, `1073741824 bytes` (not `1008M`, `1056964608 bytes`).
- On the node to which the volume is attached, verify that the backend replica file size is exactly `1 GiB + 16 MiB`.

### Volume Expansion

- Expand the `1 GiB` encrypted volume from Test 1 to `2 GiB`.
- Wait for expansion to complete.
- **Expected:** `lsblk` or `fdisk -l` inside the pod shows `2G`. The replica image file on the worker node shows `2 GiB + 16 MiB`.

### Replica Rebuild

- Delete a replica of the attached `2 GiB` encrypted volume.
- Allow Longhorn to automatically rebuild the degraded replica.
- **Expected:** Rebuild completes successfully. The new replica file size matches the existing replicas' `2 GiB + 16 MiB` size, and data integrity, for example the `md5sum` of a stored file, remains intact.

### Backup & Restore

- Write a 500 MiB payload to the `2 GiB` encrypted volume and calculate payload checksum.
- Create a backup to the remote backup server.
- Restore the backup to a new volume.
- Attach the restored volume to a workload.
- **Expected:** The restored volume presents exactly `2.0G` to the workload. The restored payload checksum matches.
