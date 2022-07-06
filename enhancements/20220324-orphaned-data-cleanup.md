# Orphaned Replica Directory Cleanup

## Summary

Orphaned replica directory cleanup identifies unmanaged replicas on the disks and provides a list of the orphaned replica directory on each node. Longhorn will not delete the replicas automatically, preventing deletions by mistake. Instead, it allows the user to select and trigger the deletion of the orphaned replica directory manually or deletes the orphaned replica directories automatically.

### Related Issues

[https://github.com/longhorn/longhorn/issues/685](https://github.com/longhorn/longhorn/issues/685)

## Motivation

### Goals

- Identify the orphaned replica directories
- The scanning process should not stuck the reconciliation of the controller
- Provide user a way to select and trigger the deletion of the orphaned replica directories
- Support the global auto-deletion of orphaned replica directories
### Non-goals

- Clean up unknown files or directories in disk paths
- Support the per-node auto-deletion of orphaned replica directories
- Support the auto-deletion of orphaned replica directories exceeded the TTL

## Proposal

1. Introduce a new CRD `orphan` and controller that represents and tracks the orphaned replica directories. The controller deletes the physical data and the resource if receive a deletion request.


2. The monitor on each node controller is created to periodically collects the on-disk replica directories, compares them with the scheduled replica, and then finds the orphaned replica directories.

    The reconciliation loop of the node controller gets the latest disk status and orphaned replica directories from the monitor and update the state of the node. Additionally, the `orphan` resources associated with the orphaned replica directories are created.

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
   
### User Stories
When a user introduces a disk into a Longhorn node, it may contain replica directories that are not tracked by the Longhorn system. The untracked replica directories may belong to other Longhorn clusters. Or, the replica CRs associated with the replica directories are removed after the node or the disk is down. When the node or the disk comes back, the corresponding replica data directories are no longer tracked by the Longhorn system. These replica data directories are called orphaned.

Longhorn's disk capacity is taken up by the orphaned replica directories. Users need to compare the on-disk replica directories with the replicas tracked by the Longhorn system on each node and then manually delete the orphaned replica directories. The process is tedious and time-consuming for users.

After the enhancement, Longhorn automatically finds out the orphaned replica directories on Longhorn nodes. Users can visualize and manage the orphaned replica directories via Longhorn GUI or command line tools. Additionally, Longhorn can deletes the orphaned replica directories automatically if users enable the global auto-deletion option.

### User Experience In Detail

- Via Longhorn GUI
    - Users can check Node and Disk status then see if Longhorn already identifies orphaned replicas.
    - Users can choose the items in the orphaned replica directory list then clean up them.
    - Users can enable the global auto-deletion on setting page. By default, the auto-deletion is disabled.

- Via `kubectl`
    - Users can list the orphaned replica directories by `kubectl -n longhorn-system get orphans`.
    - Users can delete the orphaned replica directories by `kubectl -n longhorn-system delete orphan <name>`.
    - Users can enable the global auto-deletion by `kubectl -n longhorn-system edit settings orphan-auto-deletion`

## Design

### Implementation Overview
**Settings**
  - Add setting `orphan-auto-deletion`. Default value is `false`.

**Node controller**
  - Start the monitor during initialization.
  - Sync with the monitor in each reconcile loop.
  - Update the node/disk status.
  - Create `orphan` CRs based on the information collected by the monitor.
  - Delete the `orphan` CRs if the node/disk is requested to be evicted.
  - Delete the `orphan` CRs if the corresponding directories disappear.
  - Delete the `orphan` CRs if the auto-deletion setting is enabled.

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

**Orphan controller**
  - Struct:
    ```go
    // OrphanSpec defines the desired state of the Longhorn orphaned data
    type OrphanSpec struct {
      // The node ID on which the controller is responsible to reconcile this orphan CR.
      // +optional
      NodeID string `json:"nodeID"`
      // The type of the orphaned data.
      // Can be "replica".
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
    - If receive the deletion request, delete the on-disk orphaned replica directory and the `orphan` resource.

    - If the auto-deletion is enabled, node controller will issues the orphans deletion requests.

**longhorn-ui**
    
  - Allow users to list the orphans on the node page by sending `OrphanList` call to the backend. 
  - Allow users to select the orphans to be deleted. The frontend needs to send `OrphanDelete` call to the backend.
    

### Test Plan

**Integration tests**

- `orphan` CRs will be created correctly in the disk path. And they can be cleaned up with the directories.
- `orphan` CRs will be created correctly when there are multiple kinds of files/directories in the disk path. And they can be cleaned up with the directories.
- `orphan` CRs will be removed when the replica directories disappear.
- `orphan` CRs will be removed when the node/disk is evicted or down. The associated orphaned replica directories should not be cleaned up.
- Auto-deletion setting.


## Note[optional]