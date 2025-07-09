# Configurable Backup Block Size

## Summary

This enhancement adds support for user configured (storage class, volumes) backup block size.

### Related Issues

- https://github.com/longhorn/longhorn/issues/5215

## Motivation

### Goals

User is able to configure the backup block size other than the default size 2MiB.

### Non-goals

- There are pre-defined options of the valid backup block size. User cannot set the size other than the defined size.
- The backup block size is configurable only when creating new volumes. This is immutable after volume is created.
- The backup block size is not configurable for backup restore and disaster recovery (DR) volumes.
- To the existing backups, the block size is immutable.
- If a backup is created using a non-default block size, this backup cannot be restored by the engine that supports only the default block size.

## Proposal

Provides two available backup block size to be set in the volume CR:

- 2MiB, the default size, and backward compatible with the older version
- 16MiB

Benchmark:

- 3-node K3s cluster locally hosted by Vagrant-libvirt
- 5GB v1 volume with 4GB random content single file, v2 engine is disabled in this cluster
- Backup target minio is also locally hosted inside the same cluster.

| Block Size | Num. of Blk files | Accumulate size on bkup target | Avg Transmission Time |
|:----------:|:-----------------:|:------------------------------:|:---------------------:|
|    2MiB    |       2063        |            4211852             |        29 sec         |
|   16MiB    |        266        |            4197748             |        19 sec         |

### User Stories

Users can select an appropriate backup block size when creating a volume for their application, based on both the application requirements and the evaluation results regarding the characteristics of the backup target. The larger block size will improve the compression but further also reduce the number of block files, which will potentially lower the cost for the lookups of backup targets.

#### Configure The Default Backup Block Size

Users can configure global default backup block size setting `default-backup-block-size`. This configuration applies to newly created volumes.

#### Configure The Block Size In Storage Class

Users can specify the desired backup block size as a parameter in the storage class. This parameter is used when creating volumes. If no backup block size is specified, the system uses the globally configured default value.

#### Configure The Block Size In Volume CR

A field is available to specify the backup block size when creating a volume CR. This field becomes immutable once the CR is created. If no backup block size is specified, the system uses the globally configured default value.

#### Configure The Block Size In Volume Creation UI

Users specify the backup block size during the volume creation. It provides the available options to the user, and sets to 2MiB by default. The backup block size is listed in the volume details.

While creating the volume form a backup, it also provides the available backup block size options to the user. This option affects the new backup creation for this restored volume.

While creating the disaster recovery volume, the backup block size is fixed to the existing backups.

#### View The Block Size In Backup List UI

Users can check the size from backup list UI, so that they can confirm the backup block size.

## Design

### Setting

A new setting `default-backup-block-size` is introduced as the default backup block size for volume creation. The setting is an integer to specify the block size in MB, , one of `2` (2 MiB) or `16` (16 MiB). 

### CSI

A new parameter `backupBlockSize` is introduced to the storage class.

```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: pvc-larger-backup-block-size
provisioner: driver.longhorn.io
parameters:
  ...
  backupBlockSize: 16Mi
```

- A string of quantity.
- Longhorn accepts only the value of `2Mi` and `16Mi`

### Longhorn Manager

- The new string field `BackupBlockSize` is configured in the volume CR and accepts a size integer in bytes, one of `2097152` (2 MiB) or `16777216` (16 MiB).
    ```go
    type VolumeSpec struct {
        ...
        // BackupBlockSize indicate the block size to create backups. The block size is immutable.
        // +kubebuilder:validation:Type=string
        // +kubebuilder:validation:Enum="2097152";"16777216"
        // +optional
        BackupBlockSize int64 `json:"backupBlockSize,string"`
        ...
    }
    ```
  - If the `BackupBlockSize` is set to `0`, it means to set to the global default block size.
- While creating a new backup CR, the new field `BackupBlockSize` is copied from the volume CR.
    ```go
    type BackupSpec struct {
        ...
        // The backup block size. 0 means the legacy default size 2MiB, and -1 indicate the block size is invalid.
        // +kubebuilder:validation:Type=string
        // +kubebuilder:validation:Enum="-1";"2097152";"16777216"
        // +optional
        BackupBlockSize int64 `json:"backupBlockSize,string"`
        ...
    }
    ```
  - To a backup is fetch from a remote backup store:
    - If the block size information is unset, it will fall back to legacy 2 MiB size
    - If the backup is somehow broken and the block size is invalid, the new backup CR will be still created to represent the existence, but a special block size `-1` is used to mark this backup is unusable.
- Backup controller creates monitor for the backup CR, and passes the block size to the sync agent by set a new parameter `backup-block-size` in the volume descriptor.

#### Webhooks

- The volume mutator assigns the global default value specified in setting `default-backup-block-size` when the specified value is `0`.
- The volume validator ensures the validity of the new string field `backupBlockSize`, and prohibits modifications.
  - The block size must be `2097152` (2 MiB) or `16777216` (16 MiB).
  - The size of the volume must be an integer multiple of the backup block size.
  - When updating the volume size for expansion, the new size must be an integer multiple of the backup block size.
- The backup validator also prohibits modifications to the field `backupBlockSize`, except the original block size is not set.

#### Upgrade

To the existing volume and backup CRs, the `backupBlockSize` will be set to `2097152` (2 MiB).

### Longhorn Engine / Replica

While a sync agent is creating a new backup:

- For request initiation, both to the `backup create` CLI subcommand and the gRPC interface, accept the new parameter to specify the backup block size. If the parameter `backup-block-size` is not set or invalid, fallback the block size to the default size `2,097,152` (2 MiB).
- The engine then calculates the blocks from the sections using the given backup block size.
- While uploading the backup to the target, the engine records the backup block size in number of bytes inside the metadata file (`${volume_name}/backups/backup_*.cfg`)
    ```json
    {
      "Name": "backup-1e0f6f32f3a24aac",
      "VolumeName": "vol",
      "SnapshotName": "1853016f-de97-4bc3-b506-22f4a509820b",
      ...
      "BlockSize": 2097152,
      ...
    }
    ```

While a replica is restored from a backup:

- During the initialization, load the block size from the backup metadata file, and validate the size. The volume size must be an integer multiple of the block size.
- To incremental restoring, accept the block size of the new backup that is identical with the last one.
- During the restoring, load the blocks in the configured block size.

### Longhorn Manager RESTful API

- Add a new field, `BackupBlockSize`, to the volume and backup spec.
- While Longhorn manager handles volume creation request, it set the backup block size to the new volume CR.
- Don't provide any method to edit the backup block size on existing volume.

### Longhorn UI

- Provide option to select the backup block size for volume creation, includes:
  - Creating a new volume.
  - Restoring from a backup.
- In the backup list page, add a new column for backup block size.

### Test plan

#### Longhorn Upgrade

While upgrading the Longhorn from v1.9 to v1.10, all existing volume and backup CRs should be updated to use 2 MiB backup block size.

#### Global Default Backup Block Size

- When a volume is created without specifying the backup block size, the backup block size should be set to the value configured in `default-backup-block-size`.
- The change of `default-backup-block-size` does not affect to the existing volumes.

#### Create A Volume Using Large Backup Block Size Via Longhorn API

The volume's backup block size can be specified while creating it via Longhorn volume creation API.

#### Create A Volume Using Large Backup Block Size Via PVC

The volume's backup block size can be specified in the storage class, and the volumes in this class should respect the backup block size.

#### Volume Backup Creation

While creating a backup from a volume, the backup's block size should be identical with the one specified in the volume.

#### Remote Backup Fetching

Generate a backup on the remote backup store, and specify the block size in the backup's metadata.

- The backup CR of the fetched backup should be the one specified in the remote backup metadata.
- If the block size is not set in the remote backup metadata, the backup CR's block size should be 2 MiB.
- If the block size is invalid in the remote backup metadata, the backup CR's block size should be `-1`.

#### Prevent Updating The Block Size

- Given a volume, the mutation of the back block size is rejected.
- Given a backup, the mutation of the back block size is rejected.

## References

- Some reference design by other backup systems: https://github.com/longhorn/longhorn/issues/5215#issuecomment-3051943659
