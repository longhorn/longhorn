# Orphaned Engine And Replica Runtime Instance Cleanup

## Summary

Orphaned runtime instance cleanup identifies unmanaged engine and replica runtime instances on the nodes, and provides a list of the orphan instances on each node. Longhorn by default keeps the instance. Also, it provides a configurable way to clean up such resources automatically.

### Related Issues

[https://github.com/longhorn/longhorn/issues/6764](https://github.com/longhorn/longhorn/issues/6764)

## Motivation

### Goals

- Identify the orphaned engine and replica processes
- The scanning process should not stick to the reconciliation of the controller
- Provide the user a way to select and trigger the deletion of the orphaned runtime
- Support the global auto-deletion of orphaned runtime

### Non-goals

- Clean up orphaned data stores on the nodes
- Support the per-node auto-deletion of orphaned runtime
- Support the auto-deletion of orphaned runtime exceeding the TTL

## Proposal

1. Introduce some new type of existing CRD `orphan` and controller that represents and tracks the orphaned runtime instances. The controller deletes the runtime instance if receives a deletion request. The orphan object reflects the existence of the runtime instance.

2. The monitor on each instance manager controller keeps watching the runtime instances managed by instance manager, compares them with the scheduled engine and replica, and then finds the orphaned runtime instances.

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

- Orphan objects track the liveness of corresponding orphaned runtime instance
- Orphan objects are created by instance manager monitor
- Orphan objects are deleted by
  - instance manager controller: when auto deletion is enabled
  - engine and replica controller: when runtime instance is rescheduled back to the node
  - Longhorn node controller: when node is deleted or evicted
  - Instance manager monitor: when runtime instance disappear

**Settings**

  - Add setting `orphan-engine-intstance-auto-deletion`. Default value is `false`.
  - Add setting `orphan-replica-intstance-auto-deletion`. Default value is `false`.

**Instance manager controller**

  - Start the instance monitor during initialization.
  - Reconciles the settings events and orphan events.
    - When auto deletion enabled, delete the orphan runtime instance objects on this node.

**Instance manager monitor**

  - Establishes a GRPC stream with instance manager to watch the status of runtime instances.
  - Receives engine instance status update events from GRPC stream
  - Update runtime instance status on the list in instance manager object's `status.instanceEngines` and `status.instanceReplicas`
  - Compare the known engine/replica runtime instances with corresponding engine/replica objects:
    - If there's no such object, mark this instance as orphaned.
    - If there's an object:
      - If the current state is not the desired state, ignore it.
      - If the object is in running state:
        - If the owner ID is not node ID, ignore it.
        - Mark the instance orphaned if and only if the node ID is not the current controller ID.
      - If the object is in stopped state:
        - Mark the instance orphaned if and only if the node ID is not the current controller ID.
      - To other object states, ignore it because of unstable state.
  - Compare the orphaned engine/replica runtime instances with the exist orphan objects
    - Create a corresponding orphan object for each orphaned instance if missing.
    - Delete the exist orphan runtime instance objects if the runtime instance disappeared from instance manager

  ```
                        ┌─────────────────────┐                                      
                        │                     │                                      
                        │ an engine/replica   │                                      
                        │ instance listed by  │                                      
                        │  instance manager   │                                      
                        │                     │                                      
                        └──────────┬──────────┘                                      
                                   │                                                 
                                   │                                                 
                       ┌───────────▼───────────┐                                     
                       │                       │                                     
                       │      compare the      │                                     
                       │     corresponding     │                                     
                       │ engine/replica object │                                     
                       │                       │                                     
                       └───────────┬───────────┘                                     
                                   │                                                 
                                   │                                                 
                           ┌───────▼───────┐                                         
                           │               │ not exist                               
                           │ object exist? ├────────────────────────────┐            
                           │               │                            │            
                           └───────┬───────┘                            │            
                                   │ exist                              │            
                                   │                                    │            
  no, object state ┌───────────────▼───────────────┐                    │            
     will change   │                               │                    │            
        ┌──────────┤ object state == desired state │                    │            
        │          │                               │                    │            
        │          └───────────────┬───────────────┘                    │            
        │                          │ yes, stable state                  │            
        │                          │                                    │            
        │                  ┌───────▼───────┐                            │            
        │                  │               │                            │            
        │                  │ object state? │                            │            
        │                  │               │                            │            
        │                  └───────┬───────┘                            │            
        │                          │                                    │            
        │           ┌──────────────┼──────────────┐                     │            
        │           │              │              │                     │            
        │     ┌─────▼────┐    ┌────▼────┐    ┌────▼────┐                │            
        │     │  other   │    │         │    │         │                │            
        │     │(starting,│    │         │    │         │                │            
        │     │ stopping,│    │ running │    │ stopped │                │            
        │     │ error   )│    │         │    │         │                │            
        │     └─┬────────┘    └────┬────┘    └────┬────┘                │            
        │       │                  │              │                     │            
     ┌──▼───────▼──┐      ┌────────▼────────┐     │                     │            
     │             │      │                 │     │                     │            
     │ no decision │   no │ object owner == │     │                     │            
     │             ◄──────┤  desired node ? │     │                     │            
     └──────▲──────┘      │                 │     │                     │            
            │             └────────┬────────┘     │                     │            
            │                  yes │              │                     │            
            │                      │              │                     │            
            │              ┌───────▼──────────────▼───────┐  ┌──────────▼───────────┐
            │              │                              │  │                      │
            │              │ object node == current node? │  │ instance is orphaned │
            │              │                              │  │                      │
            │              └───────┬──────────────┬───────┘  └──────────▲───────────┘
            └──────────────────────┘              └─────────────────────┘            
               object on this node                  object on other node             
  ```

**Orphan object**

  - The object ID is calculated from engine/replica ID.
    - To engine instance: `orphan-engine-${checksum}`
    - To replica instance: `orphan-replica-${checksum}`
    - `$checksum = sha256("${engine_replica_id}-${node_id}-${data_engine_type}")`
  - labels:
    - `longhorn.io/component`: `orphan`
    - `longhorn.io/managed-by`: `longhorn-manager`
    - `longhorn.io/orphan-type`: `engine-instance` or `replica-instance`
    - `longhornnode`: node ID
    - `longhornengine`: the instance name. Set only when it is an engine instance
    - `longhornreplica`: the instance name. Set only when it is a replica instance
  - The `OrphanType` is `engine-instance` or `replica-instance`.
  - Record the data engine type in `Parameters["dataEngine"]`.

**Orphan controller**

  Reconciles the orphan events.

  - If the `deletionTimestamp` is non-zero, and the current controller is responsible for this orphan object, proceed with deletion request.
    - If the orphan's node ID is the current controller ID:
      - Check with the corresponding engine or replica object before deleting the runtime instance.
        - if the engine / replica object not exists, ask instance manager to delete the runtime instance directly.
        - if the engine / replica object exists, and the node ID is not the current controller ID, then ask instance manager to delete the runtime instance.
      - If the instance disappears from the instance manager, remove the finalizer to delete the orphan object.
    - Otherwise, the orphan runtime instance lives on another node, but the controller loses its ownership because of disconnection. Remove the finalizer to complete deletion.

**Engine and replica controller**

  - Once an engine or replica object's node ID is assigned, delete the corresponding orphan runtime instance object if exists on assigned node.

**Longhorn node controller**

  Reconcile the Longhorn node events.

  - Delete orphan runtime instance objects on a deleted or evicted node

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
