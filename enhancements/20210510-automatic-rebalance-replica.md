# Automatic Replica Rebalance

Have a setting for global and volume-specific settings to enable/disable automatic distribution of the off-balanced replicas when a node is newly available to the cluster.

## Summary

When nodes are offline with setting `Replica Zone Level Soft Anti-Affinity` enabled, or `Replica Node Level Soft Anti-Affinity` enabled, the replicas could be duplicated and retained on the same zone/node if the remain cluster zone/node number is less than the replica number.

Currently, the user needs to be aware when nodes are offline and a new node is added back to the cluster to manually delete the replicas to rebalance onto the newly available node.

This enhancement proposes is to add a new Longhorn global setting `Replica Auto Balance` to enable detection and deletion of the unbalanced replica to achieve automatic rebalancing. And this enhancement also proposes to add a new setting in volume spec `replicaAutoBalance` to enable/disable automatic replica rebalancing for individual volume.

### Related Issues

- https://github.com/longhorn/longhorn/issues/587
- https://github.com/longhorn/longhorn/issues/570

## Motivation

### Goals

- Support global replica automatic balancing.
- Support individual volume replica automatic balancing.

### Non-goals [optional]
[Clean up old Data after node failure](https://github.com/longhorn/longhorn/issues/685#issuecomment-817121946).

## Proposal

Add a new global setting `Replica Auto Balance` to enable replica automatic balancing when a node is newly available to the cluster.

Add a new setting in volume spec `replicaAutoBalance` to enable/disable automatic replica rebalancing for individual volume.

### User Stories

Before this enhancement, the user needs to check and manually delete replicas to have deleted replicas reschedule to newly available nodes. If the user does not take action, this could lead to no redundancy volumes.

After this enhancement, the user does not need to worry about manually balancing replicas when there are newly available nodes.

#### Story 1 - node temporary offline
As a system administrator,

When a cluster node is offline and comes back online after some time, I want Longhorn to automatically detect and reschedule replicas evenly to all nodes.

So I do not have to worry and standby 24/7 to check and manually rebalance replicas when there are newly available nodes.

#### Story 2 - add new node

As a system administrator,

When a cluster node is offline and a new node is added, I want Longhorn to automatically detect and reschedule replicas evenly to all nodes

So I do not have to worry and standby 24/7 to check and manually rebalance replicas when there are newly available nodes.

#### Story 3 - zone temporary offline

As a system administrator,

When a cluster zone is offline and comes back online after some time, I want Longhorn to automatically detect and reschedule replicas evenly across zones.

So I do not have to worry and standby 24/7 to check and manually rebalance replicas when there are newly available nodes.

#### Story 4 - replica automatic rebalance for individual volume

As a system administrator,

When a cluster node is offline and a new node is added, I want Longhorn to automatically detect and reschedule replicas evenly to some volumes only.

So I do not have to worry and standby 24/7 to check and manually rebalance replicas when there are newly available nodes.

#### Story 5 - replica automatic rebalance for minimal redundancy

As a system administrator,

When multiple cluster node are offline and a new node is added, I want have an option to have Longhorn to automatically detect and reschedule only 1 replica to the new node to achieve minimal redundancy.

So I do not have to worry about over resource consumption during rebalancing and I do not have to worry and standby 24/7 to check and manually rebalance replicas when there are newly available nodes.

#### Story 6 - replica automatic rebalance for even redundancy

As a system administrator,

When multiple cluster node are offline and a new node is added, I want have an option to have Longhorn to automatically detect and reschedule replica to the new node to achieve even replica number redundancy.

So I do not end up with uneven number of replicas across cluster nodes and I do not have to worry and standby 24/7 to check and manually rebalance replicas when there are newly available nodes.

### User Experience In Detail

#### Story 1 - Replica Node Level Unbalanced

With an example of 3 nodes in cluster and default of 3 replicas volume:
1. When the user enables `replica-soft-anti-affinity` and deploys PVC and Pod on node-1. The replica is distributed evenly to all 3 nodes at this point.
2. In case of node-2 is offline, the user will see replica was on node-2 gets re-scheduled to node-1 or node-3. And also a warning icon and note will appear on UI `Limited node redundancy: at least one healthy replica is running at the same node as another`.

**Before enhancement**
3. Bring node-2 online, no change will be done automatically by Longhorn. The user will still see the same warning on UI.
4. To rebalance replicas, the user needs to find and delete the duplicated replica to trigger the schedule onto node-2. 

**After enhancement**
3. Longhorn automatically detects and deletes the duplicated replica so the replica will be scheduled onto node-2. User will see the duplicated replica get rescheduled back to node-2 and UI will see volume `Healthy` with the note `Limited node redundancy: at least one healthy replica is running at the same node as another` removed.

#### Story 2 - Replica Zone Level Unbalanced

With an example of cluster set for 2 zones and default of 2 replicas volume:
1. When the user enables `replica-soft-anti-affinity` and `replica-zone-soft-anti-affinity` and deploys PVC and deployment. The replica is distributed evenly to all 2 zones at this point.
2. In case of zone-2 is offline, the user will see replica was on zone-2 gets re-scheduled to zone-1.

**Before enhancement**
3. Bring zone-2 online, no change will be done automatically by Longhorn. The user will still see replicas all running in zone-1.
4. To rebalance replicas, the user needs to find and delete the duplicated replica to trigger the schedule to zone-2.

**After enhancement**
3. Longhorn automatically detects and deletes the duplicated replica so the replica will be scheduled to zone-2. The user will see the duplicated replica get rescheduled back to zone-2.

### API changes
- The new global setting `Replica Auto Balance` will use the same /v1/settings API.
- When creating a new volume, the body of the request sent to /v1/volumes has a new field `replicaAutoBalance` set to `ignored`, `disabled`, `least-effort`, or `best-effort`.
- Implement a new API for users to update `replicaAutoBalance` setting for individual volume. The new API could be /v1/volumes/<VOLUME_NAME>?action=updateReplicaAutoBalance. This API expects the request's body to have the form {replicaAutoBalance:<options>}.

## Design

### Implementation Overview

#### longhorn-manager
- Add new global setting `Replica Auto Balance`.
  - The setting is `string`.
  - Available values are: `disabled`, `least-effort`, `best-effort`.
      - `disabled`: no replica auto balance will be done.
      - `least-effort`: replica will be balanced to achieve minimal redundancy. For example, after adding node-2, a volume with 4 off-balanced replicas will only rebalance 1 replicas.
         ```
         node-1
         +-- replica-a
         +-- replica-b
         +-- replica-c
         node-2
         +-- replica-d
         ```
      - `best-effort`: replica will be balanced to achieve similar number of replicas redundancy. For example, after adding node-2, a volume with 4 off-balanced replicas will rebalance 2 replicas.
         ```
         node-1
         +-- replica-a
         +-- replica-b
         node-2
         +-- replica-c
         +-- replica-d
         ```
  - The default value is `disabled`.

- Add new volume spec `replicaAutoBalance`.
  - Available values are: `ignored`, `disabled`, `least-effort`, `best-effort`.
      - `ignored`: This will adopt to the value from global setting.
      - `disabled`: Same as global setting value `disabled`.
      - `least-effort`: Same as global setting value `least-effort`.
      - `best-effort`: Same as global setting value `best-effort`.
  - The default value is `ignored`.

- In Volume Controller `syncVolume` -> `ReconcileEngineReplicaState` -> `replenishReplicas`, calculate and add number of replicas to be rebalanced to `replenishCount`.
  > The logic ignores all `soft-anti-affinity` settings. This will always try to achieve zone balance then node balance. And creating for replicas will leave for ReplicaScheduler to determine for the candidates.
  1. Skip volume replica rebalance when volume spec `replicaAutoBalance` is `disabled`.
  2. Skip if volume `Robustness` is not `healthy`.
  3. For `least-effort`, try to get the replica rebalance count.
      1. For `zone` duplicates, get the replenish number.
            1. List all the occupied node zones with volume replicas running.
                  - The zone is balanced when this is equal to volume spec `NumberOfReplicas`.
            2. List all available and schedulable nodes in non-occupied zones.
                  - The zone is balanced when no available nodes are found.
            3. Get the number of replicas off-balanced:
                  - number of replicas in volume spec - number of occupied node zones.
            4. Return the number to replenish.
                  - number of non-occupied zones if less than off-balanced, or 
                  - number off-balanced.
      2. For `node` duplicates, try to balance `zone` first. Get the replica replenish number.
            1. List all occupied node IDs with volume replicas running.
                  - The node is balanced when this is equal to volume spec `NumberOfReplicas`.
            2. List all available and schedulable nodes.
                  - The nodes is balanced when number of occupied nodes equal to the number of nodes. This is to determine if balanced when the number of nodes is less then the volume spec `NumberOfReplicas`.
            3. Get the number of replicas off-balanced:
                  - number of replicas in volume spec - number of occupied node IDs.
            4. Return the number to replenish.
                  - number of non-occupied nodes if less than off-balanced, or
                  - number off-balanced.
  4. For `best-effort`, try `least-effort` first to achieve minimal redundancy, then,
      1. Try to get zone duplicates mapped by zoneID, continue to find duplicates on nodes if no duplicated found here.
      2. Try to get node duplicates mapped by nodeID.
      3. Return number to replenish when maximum replica names in duplicates mapping is 2 greater than the minimum replica names in duplicates mapping.
  5. Add the number to rebalance to `replenishCount` in `replenishReplicas`.

- Cleanup extra replicas for auto-balance in `cleanupExtraHealthyReplicas`.
  1. Get replica names.
      - For `best-effort`, use the replica names from duplicates in the most duplicated zones/nodes. 
      - For `least-effort`, use the replicas names from `getPreferredReplicaCandidatesForDeletion`.
  3. Delete one replicas from the replica names.


### Test plan

#### Integration tests - test_replica_auto_balance_node_least_effort

Scenario: replica auto-balance nodes with `least_effort`.

      Given set `replica-soft-anti-affinity` to `true`.
      And set `replica-auto-balance` to `least_effort`.
      And create a volume with 6 replicas.
      And attach the volume to node-1.
      And wait for the volume to be healthy.
      And write some data to the volume.
      And disable scheduling for node-2.
          disable scheduling for node-3.
      And And count replicas running on each nodes.
      And 6 replicas running on node-1.
          0 replicas running on node-2.
          0 replicas running on node-3.

      When enable scheduling for node-2.
      Then count replicas running on each nodes.
      And node-1 replica count != node-2 replica count.
          node-2 replica count != 0.
          node-3 replica count == 0.
      And sleep 10 seconds, to ensure no addition scheduling is happening.
      And count replicas running on each nodes.
      And number of replicas running should be the same.

      When enable scheduling for node-3.
      And count replicas running on each nodes.
      And node-1 replica count != node-3 replica count.
          node-2 replica count != 0.
          node-3 replica count != 0.
      And sleep 10 seconds, to ensure no addition scheduling is happening.
      And count replicas running on each nodes.
      And number of replicas running should be the same.

      When check the volume data.
      And volume data should be the same as written.

#### Integration tests - test_replica_auto_balance_node_best_effort

Scenario: replica auto-balance nodes with `best_effort`.

      Given set `replica-soft-anti-affinity` to `true`.
      And set `replica-auto-balance` to `best_effort`.
      And create a volume with 6 replicas.
      And attach the volume to node-1.
      And wait for the volume to be healthy.
      And write some data to the volume.
      And disable scheduling for node-2.
          disable scheduling for node-3.
      And And count replicas running on each node.
      And 6 replicas running on node-1.
          0 replicas running on node-2.
          0 replicas running on node-3.

      When enable scheduling for node-2.
      And count replicas running on each node.
      Then 3 replicas running on node-1.
           3 replicas running on node-2.
           0 replicas running on node-3.
      And sleep 10 seconds, to ensure no addition scheduling is  happening.
      And count replicas running on each node.
      And 3 replicas running on node-1.
          3 replicas running on node-2.
          0 replicas running on node-3.

      When enable scheduling for node-3.
      And count replicas running on each node.
      Then 2 replicas running on node-1.
           2 replicas running on node-2.
           2 replicas running on node-3.
      And sleep 10 seconds, to ensure no addition scheduling is  happening.
      And count replicas running on each node.
      And 2 replicas running on node-1.
          2 replicas running on node-2.
          2 replicas running on node-3.

      When check the volume data.
      And volume data should be the same as written.

#### Integration tests - test_replica_auto_balance_disabled_volume_spec_enabled

Scenario: replica should auto-balance individual volume when global setting `replica-auto-balance` is `disabled` and volume spec `replicaAutoBalance` is `least_effort`.

      Given set `replica-soft-anti-affinity` to `true`.
      And set `replica-auto-balance` to `least_effort`.
      And disable scheduling for node-2.
          disable scheduling for node-3.
      And create volume-1 with 3 replicas.
          create volume-2 with 3 replicas.
      And set volume-2 spec `replicaAutoBalance` to `least-effort`.
      And attach volume-1 to node-1.
          attach volume-2 to node-1.
      And wait for volume-1 to be healthy.
          wait for volume-2 to be healthy.
      And volume-1 replicas should be running on node-1.
          volume-2 replicas should be running on node-1.
      And write some data to volume-1.
          write some data to volume-2.

      When enable scheduling for node-2.
           enable scheduling for node-3.
      And count replicas running on each nodes for volume-1.
          count replicas running on each nodes for volume-2.

      Then volume-1 replicas should be running on node-1.
      And volume-1 should have 3 replicas running.
      And volume-2 replicas should be running on node-1, node-2, node-3.
      And volume-2 should have 3 replicas running.
      And volume-1 data should be the same as written.
      And volume-2 data should be the same as written.

#### Integration tests - test_replica_auto_balance_zone_least_effort

Scenario: replica auto-balance zones with least-effort.

      Given set `replica-soft-anti-affinity` to `true`.
      And set `replica-zone-soft-anti-affinity` to `true`.
      And set volume spec `replicaAutoBalance` to `least-effort`.
      And set node-1 to zone-1.
          set node-2 to zone-2.
          set node-3 to zone-3.
      And disable scheduling for node-2.
          disable scheduling for node-3.
      And create a volume with 6 replicas.
      And attach the volume to node-1.
      And 6 replicas running in zone-1.
          0 replicas running in zone-2.
          0 replicas running in zone-3.

      When enable scheduling for node-2.
      And count replicas running on each node.
      And zone-1 replica count != zone-2 replica count.
          zone-2 replica count != 0.
          zone-3 replica count == 0.

      When enable scheduling for node-3.
      And count replicas running on each node.
      And zone-1 replica count != zone-3 replica count.
          zone-2 replica count != 0.
          zone-3 replica count != 0.

#### Integration tests - test_replica_auto_balance_zone_best_effort

Scenario: replica auto-balance zones with best-effort.

      Given set `replica-soft-anti-affinity` to `true`.
      And set `replica-zone-soft-anti-affinity` to `true`.
      And set volume spec `replicaAutoBalance` to `best-effort`.
      And set node-1 to zone-1.
          set node-2 to zone-2.
          set node-3 to zone-3.
      And disable scheduling for node-2.
          disable scheduling for node-3.
      And create a volume with 6 replicas.
      And attach the volume to node-1.
      And 6 replicas running in zone-1.
          0 replicas running in zone-2.
          0 replicas running in zone-3.

      When enable scheduling for node-2.
      And count replicas running on each node.
      And 3 replicas running in zone-1.
          3 replicas running in zone-2.
          0 replicas running in zone-3.

      When enable scheduling for node-3.
      And count replicas running on each node.
      And 2 replicas running in zone-1.
          2 replicas running in zone-2.
          2 replicas running in zone-3.

#### Integration tests - test_replica_auto_balance_node_duplicates_in_multiple_zones

Scenario: replica auto-balance to nodes with duplicated replicas in the zone.

      Given set `replica-soft-anti-affinity` to `true`.
      And set `replica-zone-soft-anti-affinity` to `true`.
      And set volume spec `replicaAutoBalance` to `least-effort`.
      And set node-1 to zone-1.
          set node-2 to zone-2.
      And disable scheduling for node-3.
      And create a volume with 3 replicas.
      And attach the volume to node-1.
      And zone-1 and zone-2 should contain 3 replica in total.

      When set node-3 to the zone with duplicated replicas.
      And enable scheduling for node-3.
      Then count replicas running on each node.
      And 1 replica running on node-1
          1 replica running on node-2
          1 replica running on node-3.
      And count replicas running in each zone.
      And total of 3 replicas running in zone-1 and zone-2.

### Upgrade strategy
There is no upgrade needed.

## Note [optional]
`None`
