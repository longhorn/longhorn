# Automatically Evict Replicas While Draining

## Summary

Currently, Longhorn allows the choice between a number of behaviors (node drain policies) when a node is cordoned or
drained:

- `Block If Contains Last Replica` ensures the `instance-manager` pod cannot be drained from a node as long as it is the
  last node with a healthy replica for some volume.
  
  Benefits:

  - Protects data by preventing the drain operation from completing until there is a healthy replica available for each
    volume available on another node.
  
  Drawbacks:

  - If there is only one replica for the volume, or if its other replicas are unhealthy, the user may need to manually
    (through the UI) request the eviction of replicas from the disk or node.
  - Volumes may be degraded after the drain is complete. If the node is rebooted, redundancy is reduced until it is
    running again. If the node is removed, redundancy is reduced until another replica rebuilds.

- `Allow If Last Replica Is Stopped` is similar to the above, but only prevents an `instance-manager` pod from
  draining if it has the last RUNNING replica.

  Benefits:

  - Allows the drain operation to proceed in situations where the node being drained is expected to come back online
    (data will not be lost) and the replicas stored on the node's disks are not actively being used.

  Drawbacks:

  - Similar drawbacks to `Block If Contains Last Replica`.
  - If, for some reason, the node never comes back, data is lost.

- `Always Allow` never prevents an `instance-manager` pod from draining.

  Benefits:

  - The drain operation completes quickly without Longhorn getting in the way.

  Drawbacks:

  - There is no opportunity for Longhorn to protect data.

This proposal seeks to add a fourth and fifth behavior (node drain policy) with the following properties:

- `Block For Eviction` ensures the `instance-manager` pod cannot be drained from a node as long as it contains any
  replicas for any volumes. Replicas are automatically evicted from the node as soon as it is cordoned.

  Benefits:

  - Protects data by preventing the drain operation from completing until all replicas have been relocated.
  - Automatically evicts replicas, so the user does not need to do it manually (through the UI).
  - Maintains replica redundancy at all times.

  Drawbacks:

  - The drain operation is significantly slower than for other behaviors. Every replica must be rebuilt on another node
    before it can complete.
  - The drain operation is data-intensive, especially when replica auto balance is enabled, as evicted replicas may be
    moved back to the drained node when/if it comes back online.
  - Like all of these policies, it triggers on cordon, not on drain (it is not possible for Longhorn to distinguish
    between a node that is actively being drained and one that is cordoned for some other reason). If a user
    regularly cordons nodes without draining them, replicas will be rebuilt pointlessly.

- `Block For Eviction If Contains Last Replica` ensures the `instance-manager` pod cannot be drained from a node as long
  as it is the last node with a healthy replica for some volume. Replicas that meet this condition are automatically
  evicted from the node as soon as it is cordoned.

  Benefits:

  - Protects data by preventing the drain operation from completing until there is a healthy replica available for each
    volume available on another node.
  - Automatically evicts replicas, so the user does not need to do it manually (through the UI).
  - The drain operation is only as slow and data-intensive as is necessary to protect data.

  Drawbacks:

  - Volumes may be degraded after the drain is complete. If the node is rebooted, redundancy is reduced until it is
    running again. If the node is removed, redundancy is reduced until another replica rebuilds.
  - Like all of these policies, it triggers on cordon, not on drain (it is not possible for Longhorn to distinguish
    between a node that is actively being drained and one that is cordoned for some other reason). If a user
    regularly cordons nodes without draining them, replicas will be rebuilt pointlessly.

Given the drawbacks, `Block For Eviction` should likely not be the default node drain policy moving forward. However,
some users may find it helpful to switch to `Block For Eviction`, especially during cluster upgrade operations. See
[user stories](#user-stories) for additional insight.

`Block For Eviction If Contains Last Replica` is a more efficient behavior that may make sense as the long-term setting
in some clusters. It has largely the same benefits and drawbacks as `Block If Contains Last Replica`, except that it
doesn't require users to perform any manual drains. Still, when data is properly backed up and the user is planning to
bring a node back online after maintenance, it is costlier than other options.

### Related Issues

https://github.com/longhorn/longhorn/issues/2238

## Motivation

### Goals

- Add a new `Block For Eviction` node drain policy as described in the summary.
- Ensure that replicas automatically evict from a cordoned node when `Block For Eviction` is set.
- Ensure a drain operation can not complete until all replicas are evicted when `Block For Eviction` is set
- Document recommendations for when to use `Block For Eviction`.

### Non-goals

- Only trigger automatic eviction when a node is actively being drained. It is not possible to distinguish between a 
  node that is only cordoned and one that is actively being drained.

## Proposal

### User Stories

#### Story 1

I use Rancher to manage RKE2 and K3s Kubernetes clusters. When I upgrade these clusters, the system upgrade controller
attempts to drain each node before rebooting it. If a node contains the last healthy replica for a volume, the drain
never completes. I know I can manually evict replicas from a node to allow it to continue, but this eliminates the
benefit of the automation.

After this enhancement, I can choose to set the node drain policy to `Block For Eviction` before kicking off a cluster
upgrade. The upgrade may take a long time, but it eventually completes with no additional intervention.

#### Story 2

I am not comfortable with the reduced redundancy `Block If Contains Last Replica` provides while my drained node is
being rebooted. Or, I commonly drain nodes to remove them from the cluster and I am not comfortable with the reduced
redundancy `Block If Contains Last Replica` provides while a new replica is rebuilt. It would be nice if I could drain
nodes without this discomfort.

After this enhancement, I can choose to set the node drain policy to `Block For Eviction` before draining a node or
nodes. It may take a long time, but I know my data is safe when the drain completes.

### User Experience In Detail

### API changes

Add `block-for-eviction` and `block-for-eviction-if-last-replica` options to the `node-drain-policy` setting. The user
chooses these options to opt in to the new behavior.

Add a `status.autoEvicting` to the `node.longhorn.io/v1beta2` custom resource. This is not a field users can/should
interact with, but they can view it via kubectl.

NOTE: We originally experimented with a new `status.conditions` entry in the `node.longhorn.io/v1beta2` custom resource
with the type `Evicting`. However, this was a bit less natural, because:

- Longhorn node conditions generally describe the state a node is in, not what the node is doing.
- During normal operation, `Evicting` should be `False`. The Longhorn UI displays a condition in this state with a red
  symbol, indicating an error state that should be investigated.

Deprecate the `replica.status.evictionRequested` field in favor of a new `replica.spec.evictionRequested` field so that
replica eviction can be requested by the node controller instead of the replica controller.

## Design

### Implementation Overview

The existing eviction logic is well-tested, so there is no reason to significantly refactor it. It works as follows:

- The user can set `spec.evictionRequested = true` on a node or disk.
- When the replica controller sees `spec.evictionRequested == true` on the node or disk hosting a replica, it sets
  `status.evictionRequested = true` on that replica.
- The volume controller uses `replica.status.evictionRequested == true` to influence replica scheduling/deletion
  behavior (e.g. rebuild an extra replica to replace the evicting one or delete the evicting one once rebuilding is
  complete).
- The user can set `spec.evictionRequested = false` on a node or disk.
- When the replica controller sees `spec.evictionRequested == false` on the node or disk hosting a replica, it sets
  `replica.status.evictionRequested = false` on that replica.
- The volume controller uses `replica.status.evictionRequested == false` to influence replica scheduling/deletion
  behavior (e.g. don't start a rebuild for a previously evicting replica if one hasn't been started already).
- NOTE: If a new replica already started rebuilding as part of an eviction, it continues to rebuild and remains in the
  cluster even after eviction is canceled. It can be cleaned up manually if desired.

Make changes so that:

- The node controller (not the replica controller) sets `replica.spec.evictionRequested = true` when:
  - `spec.evictionRequested == true` on the replica's node (similar to existing behavior moved from the replica
    controller), OR
  - `spec.evictionRequested == true` on the replica's disk. (similar to existing behavior moved from the replica
    controller), OR
  - `status.Unschedulable == true` on the associated Kubernetes node object and the node drain policy is
    `block-for-eviction`, OR
  - `status.Unschedulable == true` on the associated Kubernetes node object, the node drain policy is
    `block-for-eviction-if-contains-last-replica`, and there are no other PDB-protected replicas for a volume.
- Much of the logic currently used by the instance manager controller to recognize PDB-protected replicas is moved to
  utility functions so both the node and instance manager controllers can use it.
- The volume controller uses `replica.spec.evictionRequested == true` in exactly the same way it previously used
  `replica.status.evictionRequested` to influence replica scheduling/deletion behavior (e.g. rebuild an extra replica
  to replace the evicting one or delete the evicting one once rebuilding is complete).
- The node controller sets `replica.spec.evictionRequested = false` when:
  - The user is not requesting eviction with `node.spec.evictionRequested == true` or
    `disk.spec.evictionRequested == true`, AND
  - The conditions aren't right for auto-eviction based on the node status and drain policy.
- The node controller sets `status.autoEvicting = true` when a node has evicting replicas because of the new drain
  policies and `status.autoEvicting == false` when it does not. This provides a clue to the user (and the UI) while auto
  eviction is ongoing.

### Test plan

Test normal behavior with `block-for-eviction`:

- Set `node-drain-policy` to `block-for-eviction`.
- Create a volume.
- Ensure (through soft anti-affinity, low replica count, and/or enough disks) that an evicted replica of the volume can
  be scheduled elsewhere.
- Write data to the volume.
- Drain a node one of the volume's replicas is scheduled to.
- While the drain is ongoing:
  - Verify that the volume never becomes degraded.
  - Verify that `node.status.autoEvicting == true`.
  - Verify that `replica.spec.evictionRequested == true`.
- Verify the drain completes.
- Uncordon the node.
- Verify the replica on the drained node has moved to a different one.
- Verify that `node.status.autoEvicting == false`.
- Verify that `replica.spec.evictionRequested == false`.
- Verify the volume's data.
- Verify the output of an appropriate event during the test (with reason `EvictionAutomatic`).

Test normal behavior with `block-for-eviction-if-contains-last-replica`:

- Set `node-drain-policy` to `block-for-eviction-if-contains-last-replica`.
- Create one volume with a single replica and another volume with three replicas.
- Ensure (through soft anti-affinity, low replica count, and/or enough disks) that evicted replicas of both volumes can
  be scheduled elsewhere.
- Write data to the volumes.
- Drain a node both volumes have a replica scheduled to.
- While the drain is ongoing:
  - Verify that the volume with one replica never becomes degraded.
  - Verify that the volume with three replicas becomes degraded.
  - Verify that `node.status.autoEvicting == true`.
  - Verify that `replica.spec.evictionRequested == true` on the replica for the volume that only has one.
  - Verify that `replica.spec.evictionRequested == false` on the replica for the volume that has three.
- Verify the drain completes.
- Uncordon the node.
- Verify the replica for the volume with one replica has moved to a different node.
- Verify the replica for the volume with three replicas has not moved.
- Verify that `node.status.autoEvicting == false`.
- Verify that `replica.spec.evictionRequested == false` on all replicas.
- Verify the the data in both volumes.
- Verify the output of two appropriate events during the test (with reason `EvictionAutomatic`).
- Verify the output of an appropriate event for the replica that ultimately wasn't evicted during the test (with reason
  `EvictionCanceled`).

Test unschedulable behavior with `block-for-eviction`:

- Set `node-drain-policy` to `block-for-eviction`.
- Create a volume.
- Ensure (through soft anti-affinity, high replica count, and/or not enough disks) that an evicted replica of the volume
  can not be scheduled elsewhere.
- Write data to the volume.
- Drain a node one of the volume's replicas is scheduled to.
- While the drain is ongoing:
  - Verify that `node.status.autoEvicting == true`.
  - Verify that `replica.spec.evictionRequested == true`.
- Verify the drain never completes.
- Uncordon the node.
- Verify that the volume is healthy.
- Verify that `node.status.autoEvicting == false`.
- Verify the volume's data.
- Verify the output of an appropriate event during the test (with reason `EvictionAutomatic`).
- Verify the output of an appropriate event during the test (with reason `EvictionCanceled`).

### Upgrade strategy

- Add `status.autoEvicting = false` to all `node.longhorn.io` objects during the upgrade.
- Add `spec.evictionRequested = status.evictionRequested` to all replica objects during the upgrade.
- The default node drain policy remains `Block If Contains Last Replica`, so do not make setting changes.

## Note

I have given some though to if/how this behavior should be reflected in the UI. In this draft, I have [chosen not to
represent auto-eviction as a node condition](#api-changes), which would have automatically shown it in the UI, but
awkwardly. I considered representing it in the `Status` column on the `Node` tab. Currently, the only status are
`Schedulable` (green), `Unschedulable` (yellow), `Down` (grey), and `Disabled` (red). We could add `AutoEvicting`
(yellow), but it would overlap with `Unschedulable`. This might be acceptable, as it could be read as, "This node is
auto-evicting in addition to being unschedulable."
