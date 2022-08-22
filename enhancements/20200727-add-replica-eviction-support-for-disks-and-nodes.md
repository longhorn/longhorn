# Replica Eviction Support for Disks and Nodes

## Summary
This enhancement is to simplify and automatically evict the replicas on the selected disabled disks or nodes to other suitable disks and nodes per user's request. Meanwhile keep the same level of fault tolerance during this eviction period of time.

### Related Issues
https://github.com/longhorn/longhorn/issues/292
https://github.com/longhorn/longhorn/issues/298

## Motivation

### Goals
1. Allow user easily evict the replicas on the selected disks or nodes to other disks or nodes without impact the user defined `Volume.Spec.numberOfReplicas` and keep the same level of fault tolerance. This means we don't change the user defined replica number.
2. Report any error to user during the eviction time.
3. Allow user to cancel the eviction at any time.

## Proposal
1. Add `Eviction Requested` with `true` and `false` selection buttons for disks and nodes. This is for user to evict or cancel the eviction of the disks or the nodes.
2. Add new `evictionRequested` field to `Node.Spec`, `Node.Spec.disks` Spec and `Replica.Status`. These will help tracking the request from user and trigger replica controller to update `Replica.Status` and volume controller to do the eviction. And this will reconcile with `scheduledReplica` of selected disks on the nodes.
3. Display `fail to evict` error message to `Dashboard` and any other eviction errors to the `Event log`.

### User Stories
### Disks and Nodes Eviction
For disk replacement or node replacement, the eviction needs to be done successfully in order to guarantee Longhorn volume function properly.

Before, when user wants to evict a disk or a node they need to do the following steps:

1. User needs to disable the disk or the node.
2. User needs to scale up the replica count for the volume which has replica on disabled disks or nodes, and wait for the rebuild complete, scale down the replica count, then delete the replicas on this disk or node.

After this enhancement, user can click `true` to the `Eviction Requested` on scheduling disabled disks or nodes. Or select `Disable` for scheduling and `true` to the `Eviction Requested` at the same time then save this change. The backend will take care of the eviction for the disks or nodes and cleanup for all the replicas on disks or nodes.

### User Experience In Detail
#### Disks and Nodes Eviction
1. User can select `true` to the `Eviction Requested` from `Longhorn UI` for disks or nodes. And user has to make sure the selected disks or nodes have been disabled, or select the `Disable` Scheduling at the same time of `true` to the `Eviction Requested`.
2. Once `Eviction Requested` has been set to `true` on the disks or nodes, they can not be enabled for `Scheduling`.
3. If the disks or the nodes haven't been disabled for `Scheduling`, there will be error message showed in `Dashboard` immediately to indicate that user need to disable the disk or node for eviction.
4. And user will wait for the replica number for the disks or nodes to be 0.
5. If there is any error e.g. no space or couldn't find other schedulable disk, the error message will be logged in the `Event log`. And the eviction will be suspended until either user sets the `Eviction Requested` to `false` or cleanup more disk spaces for the new replicas.
6. If user cancel the eviction by setting the `Eviction Requested` to `false`, the remaining replicas on the selected disks or nodes will remain on the disks or nodes.

### API changes
From an API perspective, the call to set `Eviction Requested` to `true` or `false` on the `Node` or `Disk` eviction should look the same. The logic for handling the new field `Eviction Requested` `true` or `false` should to be in the `Node Controller` and `Volume Controller`.

## Design

### Implementation Overview

1. On `Longhorn UI` `Node` page, for nodes eviction, adding `Eviction Requested` `true` and `false` options in the `Edit Node` sub-selection, next to `Node Scheduling`. For disks eviction, adding `Eviction Requested` `true` and `false` options in `Edit node and disks` sub-selection under `Operation` column next to each disk `Scheduling` options. This is for user to evict or cancel the eviction of the disks or the nodes.
2. Add new `evictionRequested` field to `Node.Spec`, `Node.Spec.disks` Spec and `Replica.Status`. These will help tracking the request from user and trigger replica controller to update `Replica.Status` and volume controller to do the eviction. And this will reconcile with `scheduledReplica` of selected disks on the nodes.
3. Add a informer in `Replica Controller` to get these information and update `evictionRequested` field in `Replica.Status`.
4. Once `Eviction Requested` has been set to `true` for disks or nodes, the `evictionRequested` fields for the disks and nodes will be set to `true` (default is `false`).
5. `Replica Controller` will update `evictionRequested` field in `Replica.Status` and `Volume Controller` to get these information from it's replicas.
6. During reconcile the engine replica, based on `Replica.Status.EvictionRequested` of the volume replicas to trigger rebuild for different volumes' replicas. And remove one replica with `evictionRequested` `true`.
7. Logged the errors to `Event log` during the reconcile process.
8. By the end from `Longhorn UI`, the replica number on the eviction disks or nodes should be 0, this mean eviction is success.
9. If the volume is 'Detached', Longhorn will 'Automatically Attach' the volume and do the eviction, after eviction success, the volume will be 'Automatically detach'. If there is any error during the eviction, it will get suspended, until user solve the problem, the 'Auto Detach' will be triggered at the end.

### Test plan

#### Manual Test Plan For Disks and Nodes Eviction
Positive Case:

For both `Replica Node Level Soft Anti-Affinity` has been enabled and disabled. Also the volume can be 'Attached' or 'Detached'.
1. User can select one or more disks or nodes for eviction. Select `Eviction Requested` to `true` on the disabled disks or nodes, Longhorn should start rebuild replicas for the volumes which have replicas on the eviction disks or nodes, and after rebuild success, the replica number on the evicted disks or nodes should be 0. E.g. When there are 3 nodes in the cluster, and with `Replica Node Level Soft Anti-Affinity` is set to `false`, disable one node, and create a volume with replica count 2. And then evict one of them, the eviction should get stuck, then set `Replica Node Level Soft Anti-Affinity` to `true`, the eviction should go through.

Negative Cases:
1. If user selects the disks or nodes have not been disabled scheduling, Longhorn should display the error message on `Dashboard` immediately. Or during the eviction, the disabled disk or node can not be re-enabled again.
2. If there is no enough disk spaces or nodes for disks or nodes eviction, Longhorn should log the error message in the `Event Log`. And once the disk spaces or nodes resources are good enough, the eviction should continue. Or if the user selects `Eviction Requested` to `false`, Longhorn should stop eviction and clear the `evictionRequested` fields for nodes, disks and volumes crd objects. E.g. When there are 3 nodes in the cluster, and the volume replica count is 3, the eviction should get stuck when the `Replica Node Level Soft Anti-Affinity` is `false`.

#### Integration Test Plan
For `Replica Node Level Soft Anti-Affinity` is enabled, create 2 replicas on the same disk or node, and then evict this disk or node, the 2 replicas should goto another disk of node.

For `Replica Node Level Soft Anti-Affinity` is disabled, create 1 replica on a disk, and evict this disk or node, the replica should goto the other disk of node.

For node eviction, Longhorn will process the eviction based on the disks for the node, this is like disk eviction. After eviction success, the replica number on the evicted node should be 0.

#### Error Indication
During the eviction, user can click the `Replicas Number` on the `Node` page, and set which replicas are left from eviction, and click the `Replica Name` will redirect user to the `Volume` page to set if there is any error for this volume. If there is any error during the rebuild, Longhorn should display the error message from UI. The error could be `failed to schedule a replica` due to disk space or based on schedule policy, can not find a valid disk to put the replica.

### Upgrade strategy
No special upgrade strategy is necessary. Once the user upgrades to the new version of `Longhorn`, these new capabilities will be accessible from the `longhorn-ui` without any special work.

