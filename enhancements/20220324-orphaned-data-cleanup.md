# Orphaned Data Cleanup

## Summary

1. Orphaned replica directory cleanup identifies unmanaged replicas on the disks and provides a list of the orphaned replica directory on each node. Longhorn will not delete the replicas automatically, preventing deletions by mistake. Instead, it allows the user to select and trigger the deletion of the orphaned replica directory manually or deletes the orphaned replica directories automatically.

2. Orphaned backup identifies a failed backup on the remote backup target or not when making a backup to remote backup target failed. Longhorn will not delete the backups automatically either. Also it allows the user to select and trigger the deletion of the orphaned backups manually or automatically.

### Related Issues

[[FEATURE] Clean up orphaned unused volume replicas](https://github.com/longhorn/longhorn/issues/685)

[[IMPROVEMENT] Support failed/obsolete orphaned backup cleanup](https://github.com/longhorn/longhorn/issues/3898)

## Motivation

### Goals

- Identify the orphaned replica directories and orphaned backups
- The scanning process should not stuck the reconciliation of the controllers
- Provide user a way to select and trigger the deletion of the orphaned replica directories and backups
- Support the global auto-deletion of orphaned replica directories and backups

### Non-goals

- Clean up unknown files or directories in disk paths or on the remote backup target.
- Support the per-node auto-deletion of orphaned replica directories
- Support the auto-deletion of orphaned replica directories exceeded the TTL

## Proposal

1. Introduce a new CRD `orphan` and controller that represents and tracks the orphaned replica directories and backups. The controller deletes the physical data and the resource if receive a deletion request.

2. The monitor on each node controller is created to periodically collects the on-disk replica directories, compares them with the scheduled replica, and then finds the orphaned replica directories.

    The reconciliation loop of the node controller gets the latest disk status and orphaned replica directories from the monitor and update the state of the node. Additionally, `orphan` resources with type `OrphanTypeReplica` associated with the orphaned replica directories are created.

    ```

          queue           ┌───────────────┐             ┌──────────────────────┐
         ┌┐ ┌┐ ┌┐         │               │             │                      │
     ... ││ ││ ││ ──────► │   syncNode()  ├────────────►│     reconcile()      │
         └┘ └┘ └┘         │               │             │                      │
                          └───────────────┘             └───────────┬──────────┘
                                                                    │
                                                    syncWithMonitor │
                                                                    │
                                                        ┌───────────▼──────────┐
                                                        │                      │
                                                        │   per-node monitor   │
                                                        │                      |
                                                        ┤  collect information │
                                                        │                      │
                                                        └──────────────────────┘

    ```

3. The monitor for each backup is created to check the backup status and the `orphan` resource with type `OrphanTypeBackup` would be created if the backup status is `Error` or `Unknown`.

   The reconciliation procedure of the backup controller gets the latest backup status from the monitor and then according to the backup status, the `backup` type of `orphan` resources associated with the orphaned backup are created.

    ```

          queue           ┌───────────────┐             ┌──────────────────────┐
         ┌┐ ┌┐ ┌┐         │               │             │                      │
     ... ││ ││ ││ ──────► │ syncHandler() ├────────────►│     reconcile()      │
         └┘ └┘ └┘         │               │             │                      │
                          └───────────────┘             └───────────┬──────────┘
                                                                    │
                                                    syncWithMonitor │
                                                                    │
                                                        ┌───────────▼──────────┐
                                                        │                      │
                                                        │  per-backup monitor  │
                                                        │                      |
                                                        ┤  check backup status │
                                                        │                      │
                                                        └──────────────────────┘

    ```

### User Stories

#### Orphaned replica directory

When a user introduces a disk into a Longhorn node, it may contain replica directories that are not tracked by the Longhorn system. The untracked replica directories may belong to other Longhorn clusters. Or, the replica CRs associated with the replica directories are removed after the node or the disk is down. When the node or the disk comes back, the corresponding replica data directories are no longer tracked by the Longhorn system. These replica data directories are called orphaned.

Longhorn's disk capacity is taken up by the orphaned replica directories. Users need to compare the on-disk replica directories with the replicas tracked by the Longhorn system on each node and then manually delete the orphaned replica directories. The process is tedious and time-consuming for users.

#### Orphaned backup

When a user or recurring job tries to make a backup and store it in the remote backup target, many situations will cause the backup procedure failed. In some cases, there will be some failed backups still staying in the Longhorn system and this kind of backups are no longer tracked by the Longhorn system. These backups becomes orphaned as well.

After the enhancement, Longhorn automatically finds out the orphaned replica directories on Longhorn nodes and the orphaned backups of backup volumes. Users can visualize and manage the orphaned replica directories and backups via Longhorn GUI or command line tools. Additionally, Longhorn can deletes the orphaned replica directories and backups automatically if users enable the global auto-deletion option.

### User Experience In Detail

- Via Longhorn GUI
  - Users can check Node and Disk status then see if Longhorn already identifies orphaned replicas.
  - Users can choose the items in the orphaned replica directory and backup list then clean up them.
  - Users can enable the global auto-deletion on setting page. By default, the auto-deletion is disabled.

- Via `kubectl`
  - Users can list the orphaned replica directories by `kubectl -n longhorn-system get orphans`.
  - Users can delete the orphaned replica directories by `kubectl -n longhorn-system delete orphan <name>`.
  - Users can enable the global auto-deletion by `kubectl -n longhorn-system edit settings orphan-auto-deletion`

## Design

### Implementation Overview

**Settings**
  - Add setting `orphan-auto-deletion`. Default value is `""`.
    - replica
    - backup
  - Example: `replica` for deleting one type of orphaned data or `replica,backup` for all.

**Node controller**
  - Start the monitor during initialization.
  - Sync with the monitor in each reconcile loop.
  - Update the node/disk status.
  - Create the `orphan` CRs with type `OrphanTypeReplica` based on the information collected by the monitor.
  - Delete the `orphan` CRs with type `OrphanTypeReplica` if the node/disk is requested to be evicted.
  - Delete the `orphan` CRs with type `OrphanTypeReplica` if the corresponding directories disappear.
  - Delete the `orphan` CRs with type `OrphanTypeReplica` if the auto-deletion setting is enabled.

**Node monitor**
  - Struct
    ```go
    type NodeMonitor struct {
        logger logrus.FieldLogger

        ds *datastore.DataStore

        node longhorn.Node
        lock sync.RWMutex

        onDiskReplicaDirectories map[string][string]string

        syncCallback func(key string)

        ctx  context.Context
        quit context.CancelFunc
    }
    ```
  - Periodically detect and verify disk

    - Run `stat`
    - Check disk FSID
    - Check disk UUID in the metafile
  - Periodically check and identify orphan directories

    - List on-disk directories in `${disk_path}/replicas` and compare them with the last record stored in `monitor.onDiskDirectoriesInReplicas`.
    - If the two lists are different, iterate all directories in `${disk_path}/replicas` and then get the list of the orphaned replica directories.

      A valid replica directory has the properties:
      - The directory name format is `<disk path>/replicas/<replica name>-<random string>`
      - `<disk path>/replicas/<replica name>-<random string>/volume.meta` is parsible and follows the `volume.meta`'s format.

    - Compare the list of the orphaned replica directories with the `node.status.diskStatus.scheduledReplica` and find out the list of the orphaned replica directories. Store the list in `monitor.node.status.diskStatus.orphanedReplicaDirectoryNames`

**Backup Controller**
  - Start the monitor and sync the backup status with the monitor in each reconcile loop.
  - Update the backup status.
  - Create the `orphan` CRs with type `OrphanTypeBackup` if the backups status is longhorn.BackupStateError or longhorn.BackupStateUnknown.
  - Delete the `orphan` CRs with type `OrphanTypeBackup` if the auto-deletion setting is enabled.

**Backup monitor**
  - Start with an exponential backOff timer and set bakcup status failed if maximum retrying period was reached
  - Continue to update backup status with an linear timer after exponential backOff timer returned checking backup status completed

**Orphan controller**
  - Struct:

    ```go
    // OrphanSpec defines the desired state of the Longhorn orphaned data
    type OrphanSpec struct {
      // The node ID on which the controller is responsible to reconcile this orphan CR.
      // +optional
      NodeID string `json:"nodeID"`
      // The type of the orphaned data.
      // Can be "replica" and "backup".
      // +optional
      Type OrphanType `json:"type"`

      // The parameters of the orphaned data
      // +optional
      // +nullable
      Parameters map[string]string `json:"parameters"`
    }

    // OrphanStatus defines the observed state of the Longhorn orphaned data
    type OrphanStatus struct {
      // +optional
      OwnerID string `json:"ownerID"`
      // +optional
      // +nullable
      Conditions []Condition `json:"conditions"`
    }
    ```

    - If receive the deletion request for the `OrphanTypeReplica` type, delete the on-disk orphaned replica directory and the `orphan` resource.
    - If receive the deletion request for the `OrphanTypeBackup` type, delete the `orphan` resource.
    - If the auto-deletion is enabled, node controller will issues the orphans deletion requests.

**longhorn-ui**

  - Allow users to list the orphans on the node page by sending `OrphanList` call to the backend.
  - Allow users to select the orphans to be deleted. The frontend needs to send `OrphanDelete` call to the backend.

### Test Plan

**Integration tests**

- `orphan` CRs with `OrphanTypeReplica` type will be created correctly in the disk path. And they can be cleaned up with the directories.
- `orphan` CRs with `OrphanTypeReplica` type will be created correctly when there are multiple kinds of files/directories in the disk path. And they can be cleaned up with the directories.
- `orphan` CRs with `OrphanTypeReplica` type will be removed when the replica directories disappear.
- `orphan` CRs with `OrphanTypeReplica` type will be removed when the node/disk is evicted or down. The associated orphaned replica directories should not be cleaned up.
- `orphan` CRs with `OrphanTypeBackup` type will be created correctly when there are failed/unknown backups. And they can be cleaned up with the failed/unknown bakcups.
- `orphan` CRs with `OrphanTypeBackup` type will be removed when the backup volume is deleted.
- Auto-deletion setting.

## Note[optional]
