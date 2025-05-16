# Orphaned Engine And Replica Runtime Instance Cleanup

## Summary

Orphaned runtime instance cleanup identifies unmanaged engine and replica runtime instances on the nodes, and provides a list of the orphan instances on each node. Longhorn by default keeps the instance. Also, it provides a configurable way to clean up such resources automatically.

### Related Issues

[https://github.com/longhorn/longhorn/issues/6764](https://github.com/longhorn/longhorn/issues/6764)

## Motivation

### Goals

- Identify the orphaned engine and replica processes
- The scanning process should not stick to the reconciliation of the controller
- Provide the user a way to select and trigger the deletion of the orphaned runtime instance
- Support the global auto-deletion of orphaned runtime
- Compatible with existing cluster, and is able to clean up the existing orphaned runtime in the acceptable previous versions.

### Non-goals

- Clean up orphaned data stores on the nodes
- Support the per-node auto-deletion of orphaned runtime
- Support the auto-deletion of orphaned runtime exceeding the TTL
- Prevent the process deletion race between CRs (see the design note below)

## Proposal

1. Introduce new types of existing CRD `orphan` that represents and tracks the orphaned runtime instances. This new type of orphan CR is reconciled by existing orphan controller. The orphan controller deletes the runtime instance if receives a deletion request. The orphan CR reflects the existence of the runtime instance.

2. The monitor on each instance manager controller keeps watching the runtime instances managed by instance manager, compares them with the scheduled engine and replica, and then finds the orphaned runtime instances. Once a runtime instance is considered to be orphaned, create a corresponding orphan CR, and keep update the instance state on this orphan CR. The monitor will delete the orphan CR when an instance disappears from the node, or, the corresponding engine/replica is scheduled back.

3. The node controller keeps tracking the node status. When a node is evicted or disconnects from the cluster, node controller initiates the deletion on orphan CRs belongs to this node.

### User Stories

When a network outage occurs to some Longhorn node, it may contain multiple engine or replica runtime instances not tracked by the Longhorn System. The corresponding engine and replica CRs may be removed or relocated to another node during the outage. When the node comes back, the corresponding runtime resources are no longer tracked by the Longhorn system. These runtime resources, including the processes, are called orphaned.

Orphaned runtime resources continue to consume CPU and memory. Users have no way to clean up such resources except forcibly restarting the entire instance manager pod on the node, which will unnecessarily increase the chance of a system outage.

After the enhancement, Longhorn automatically finds out the orphaned runtime instances on Longhorn nodes. Users can visualize and manage the orphaned replica runtime instances via Longhorn GUI or command line tools. Additionally, Longhorn can delete the orphaned runtime resources automatically if users enable the global auto-deletion option.

### User Experience In Detail

- Via Longhorn GUI
    - Users can check instance status and see if Longhorn already identifies orphaned engines/replicas.
    - Users can choose the items in the orphaned replica directory list and clean up them.
    - Users can enable the global auto-deletion on setting page. By default, the auto-deletion is disabled.

- Via `kubectl`
    - Users can list the orphaned runtime instances directories by `kubectl -n longhorn-system get orphans`.
    - Users can delete the orphaned runtime instances directories by `kubectl -n longhorn-system delete orphan <name>`.
    - Users can enable or disable the global auto-deletion by `kubectl -n longhorn-system edit settings orphan-engine-instance-auto-deletion`
    - Users can enable or disable the global auto-deletion by `kubectl -n longhorn-system edit settings orphan-replica-instance-auto-deletion`

## Design

### Implementation Overview

- Orphan CRs track the liveness of corresponding orphaned runtime instance
- Orphan CRs are created by instance manager monitor
- Orphan CRs are deleted by
  - Longhorn node controller: when node is deleted or evicted
  - Instance manager monitor:
    - When runtime instance disappear, delete the corresponding orphan runtime instance CR.
    - When auto deletion is enabled, delete all orphan runtime instance CRs in this instance manager.
    - When runtime instance is rescheduled back to the instance manager, delete the corresponding orphan runtime instance CR since it is no longer orphaned.

**Settings**

  - Add setting `orphan-resource-auto-deletion`.
    - This is a string of semicolon-seperated list. Possible items:
      - `replica-data` to enable auto deletion on replica data store. This replaces the old setting `orphan-auto-deletion`.
      - `instance` to enable auto deletion on engine and replica runtime instance.
    - Default value is empty, which means to disable auto deletion for all kinds of orphaned resources.
    - While upgrade Longhorn to v1.9.0, default set to `replica-data` if old setting `orphan-auto-deletion` is enabled.
  - Delete `orphan-auto-deletion`

**Instance manager controller**

  - Start the instance monitor during initialization.
  - Reconciles the settings events and orphan events.
    - When auto deletion enabled, delete the orphan runtime instance CRs in this instance manager.
    - When the instance manager is no longer running, delete the orphan runtime instance CRs in this instance manager.
    - Delete the exist orphan runtime instance CRs if the runtime instance disappeared from instance manager.
    - Delete the exist orphan runtime instance CRs if the corresponding engine/replica is scheduled back to this instance manager.

**Instance manager monitor**

  - Establishes a GRPC stream with instance manager to watch the status of runtime instances.
  - Receives engine instance status update events from GRPC stream
  - Update runtime instance status on the list in instance manager CR's `status.instanceEngines` and `status.instanceReplicas`
  - Compare the known engine/replica runtime instances with corresponding engine/replica CRs:
    - If there's no such CR, this instance is considered to be orphaned.
    - If there's a corresponding CR:
      - If the `status.currentState` is different from `spec.desireState`, ignore it because the state and ownership may change.
      - If the corresponding CR is in running state:
        - If the owner ID is not node ID, ignore it.
        - The instance is considered to be orphaned if and only if the instance manager is not the current instance manager.
      - If the corresponding CR is in stopped state:
        - The instance is considered to be orphaned if and only if the instance manager is not the current instance manager.
      - To other corresponding CR states, ignore it because of unstable state.
  - Compare the orphaned engine/replica runtime instances with the exist orphan CRs
    - Create an orphan CR for each orphaned instance if missing.

  ```
                     ┌────────────────────┐
                     │                    │
                     │ an engine/replica  │
                     │ instance listed by │
                     │  instance manager  │
                     │                    │
                     └──────────┬─────────┘
                                │
                      ┌─────────▼─────────┐
                      │                   │
                      │    compare the    │
                      │   corresponding   │
                      │ engine/replica CR │
                      │                   │
                      └─────────┬─────────┘
                                │
                          ┌─────▼─────┐
                          │           │ not exist
                          │ CR exist? ├──────────────────────────────┐
                          │           │                              │
                          └─────┬─────┘                              │
                                │ exist                              │
   no, CR state ┌───────────────▼─────────────────────────┐          │
   will change  │                                         │          │
      ┌─────────┤ status.currentState == spec.desireState │          │
      │         │                                         │          │
      │         └───────────────┬─────────────────────────┘          │
      │                         │ yes, stable state                  │
      │                 ┌───────▼────────┐                           │
      │                 │                │                           │
      │                 │ currentState ? │                           │
      │                 │                │                           │
      │                 └───────┬────────┘                           │
      │                         │                                    │
      │          ┌──────────────┼──────────────┐                     │
      │          │              │              │                     │
      │    ┌─────▼────┐    ┌────▼────┐    ┌────▼────┐                │
      │    │  other   │    │         │    │         │                │
      │    │(starting,│    │ running │    │ stopped │                │
      │    │ stopping,│    │         │    │         │                │
      │    │ error   )│    └────┬────┘    └────┬────┘                │
      │    └─┬────────┘         │              │                     │
      │      │                  │              │                     │
  ┌───▼──────▼──┐       ┌───────▼────────┐     │                     │
  │             │       │                │     │                     │
  │ no decision │    no │  CR owner ==   │     │                     │
  │             ◄───────┤ desired node ? │     │                     │
  └──────▲──────┘       │                │     │                     │
         │              └───────┬────────┘     │                     │
         │                  yes │              │                     │
         │                ┌─────▼──────────────▼─────┐    ┌──────────▼───────────┐
         │                │                          │    │                      │
         │                │   CR IM == current IM?   │    │ instance is orphaned │
         │                │                          │    │                      │
         │                └─────┬──────────────┬─────┘    └──────────▲───────────┘
         └──────────────────────┘              └─────────────────────┘
       CR in this instance manager            CR in other instance manager
  ```

**Orphan CR**

  - The orphan CR name is calculated from engine/replica ID.
    - To engine instance: `orphan-${checksum}`
    - To replica instance: `orphan-${checksum}`
    - `$checksum = sha256("${engine_replica_name}-${instance_manager_id}-${data_engine_type}")`
  - labels:
    - `longhorn.io/component`: `orphan`
    - `longhorn.io/managed-by`: `longhorn-manager`
    - `longhorn.io/orphan-type`: `engine-instance` or `replica-instance`
    - `longhornnode`: node ID
    - `longhorninstancemanager`: instance manager ID
    - `longhornengine`: the instance name. Set only when it is an engine instance
    - `longhornreplica`: the instance name. Set only when it is a replica instance
  - The `OrphanType` is `engine-instance` or `replica-instance`.
  - Record the instance name in `Parameters["InstanceName"]`.
  - Record the instance manager in `Parameters["InstanceManager"]`.
  - Record the data engine type in `DataEngine`.
  - Record the runtime instance's state in `status.conditions[].Reason` with type `"InstanceState"`
    - If instance state is `terminated`, the condition's status will be `False`, indicates that the orphan CR is no longer needed to track this instance.
    - To other instance states, the condition's status will be `True`. The instance is present in instance manager.

**Orphan controller**

  Reconciles the orphan events.

  - If the `deletionTimestamp` is non-zero, and the current controller is responsible for this orphan CR, proceed with deletion request.
    - If the orphan's node ID is the current controller ID:
      - If the instance state is deleted, remove the finalizer to complete deletion directly.
      - Otherwise, check with the corresponding engine or replica CR before deleting the runtime instance.
        - If the engine / replica CR not exists, this runtime instance is deletable.
        - If the engine / replica CR exists, and the instance manager ID is not the one in orphan CR, then the runtime instance is deletable.
        - Once the runtime instance is deletable, create an instance manager client from the instance manager CR, and delete the runtime instance. The finalizer will be removed in the future when the instance state got into deleted, or the runtime instance became not deletable.
        - If the runtime instance is not deletable, remove the finalizer to delete the orphan CR.
    - Otherwise, the orphan runtime instance lives on another node, but the controller loses its ownership because of disconnection. Remove the finalizer to complete deletion.

**Longhorn node controller**

  Reconcile the Longhorn node events.

  - Delete orphan instance CRs on a deleted or evicted node

**longhorn-ui**

  - Allow users to list the orphans on the node page by sending `OrphanList` call to the backend.
  - Allow users to select the orphans to be deleted. The frontend needs to send `OrphanDelete` call to the backend.

### Test Plan

**Integration tests**

- `orphan` CRs will be created correctly while the process instance created unexpectedly. And they can be cleaned up without touching the data store.
- `orphan` CRs will be created correctly to a re-connected node. And they can be cleaned up without touching the data store.
- `orphan` CRs will be removed when an engine / replica is relocated back to the node.
- `orphan` CRs will be removed when the node is evicted or down.
- Auto-deletion setting.

## Note[optional]

The orphan CR and the orphan controller was designed for orphaned data store in LEP ["Orphaned Replica Directory Cleanup"](https://github.com/longhorn/longhorn/blob/master/enhancements/20220324-orphaned-data-cleanup.md).

There's very little chance of deleting the instance process accidentally due to the race condition when an engine/replica is rescheduled back to the node. In this situation, after orphan controller sending delete request to instance manager, the engine/replica controller can still recover the instance process. As a future work, consider a breaking change to add some tags on instance processes to sync the status between the orphan CR and the corresponding engine/replica CR.
