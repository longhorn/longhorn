# Rebuild replica with existing data

## Summary
Longhorn could reuse the existing data of failed replicas to speed up rebuild progress as well as save bandwidth. 

### Related Issues
https://github.com/longhorn/longhorn/issues/1304

## Motivation
### Goals
1. The (data of) failed replicas can be reused during the replica rebuild.
2. The rebuild won't be blocked when the data of failed replicas are completely corrupted, or there is no existing replica.  
3. With the existing data, some of the data transferring can be skipped, and replica rebuild may speed up.  

## Proposal
1. Add a new setting `ReplicaReplenishmentWaitInterval` to delay the replica rebuild.
    - If the failed replica currently is unavailable but it may be able to be reused later(we call it potential reusable failed replica), Longhorn may need to delay the new replica replenishment so that there is a chance to reuse this kind of replica.
    - For eviction/data locality/new volume cases, a new replica should be recreated immediately hence this setting won't be applied.
2. In order to reuse the existing data, Longhorn can directly reuse the failed replica objects for the rebuild. 
3. Add max retry count for the replica rebuild with failed replicas. Otherwise, the rebuild will get stuck of the reusing the failed replicas there if the data of failed replicas are completely corrupted.
4. Add backoff interval for the retry of the failed replica reuse.

### User Stories
#### Rebuild replica for a large volume after network fluctuation/node reboot
Before the enhancement, there is no chance to reuse the failed replicas on the node, and the rebuild can take a long time with heavy bandwidth usage.

After the enhancement, the replica rebuild won't start until the new worker nodes with old disks are up. Then the failed replicas will be reused during the rebuild, and the rebuild can be pretty fast.

### User Experience In Detail
Users don't need to do anything except for setting `ReplicaReplenishmentWaitInterval`

### API Changes
No API change is required.

## Design
### Implementation Overview
#### longhorn-manager:
1. Add a setting `ReplicaReplenishmentWaitInterval`.
    - This will block the rebuilding when there is a failed replica that is temporarily unavailable in the volume.
    - Add a field `volume.Status.LastDegradedAt` so that we can determine if `ReplicaReplenishmentWaitInterval` is passed. 
2. Add field `Replica.Spec.RebuildRetryCount` to indicate how many times Longhorn tries to reuse this failed replica for the rebuild.
3. In Volume Controller && Replica Scheduler:
    1. Check if there is a reusable failed replica and if the replica reuse is not in the backoff window. If YES, directly try to reuse the failed replica.
    2. Otherwise, replenish a new replica is required for one of the following cases:
        1. the volume is a new volume (volume.Status.Robustness is Empty)
        2. data locality is required (hardNodeAffinity is not Empty and volume.Status.Robustness is Healthy)
        3. replica eviction happens (volume.Status.Robustness is Healthy)
        4. there is no potential reusable replica
        5. there is a potential reusable replica but the replica replenishment wait interval is passed.
    3. Reuse the failed replica by cleaning up `ReplicaSpec.HealthyAt` and `ReplicaSpec.FailedAt`. And `Replica.Spec.RebuildRetryCount` will be increased by 1. 
    4. Clean up the related record in `Replica.Spec.RebuildRetryCount` when the rebuilding replica becomes mode `RW`.
    5. Guarantee the reused failed replica will be stopped before re-launching it.

### Test Plan
#### Manually Test Plan
##### Rebuild replica for a large volume after network fluctuation/node reboot
1. Set `ReplicaReplenishmentWaitInterval`. Make sure it's longer than the node recovery interval. 
2. Create and attach a large volume. Set a short `staleReplicaTimeout` for the volume, e.g., 1 minute. 
3. Write a large amount of data then take a snapshot. 
4. Repeat step 3 several times.
5. Reboot/Temporarily disconnect a node contains replica only. 
6. According to the `ReplicaReplenishmentWaitInterval` and the node recovery interval:
    - Verify the failed replica is reused and there is no new replica for the rebuild after the node recovery.
    - Verify the replica rebuild only takes a relatively short time. 

##### Replenish replicas when failed replicas cannot be reused
1. Create and attach a large volume. 
2. Write data then take snapshots.
3. Hack into one replica directory and make the directory and files read-only.
4. Crash the related replica process and wait for the replica failure.
5. Wait and check if Longhorn tries to reuse the corrupted replica but always fail. Since there is backoff mechanism, this will take a long time(8 ~ 10min).
6. Check if Longhorn will create a new replica and succeeds to finish the rebuild when the max retry count is reached.
7. Verify the data content. And check if the volume still works fine.

##### Replenish replicas when failed there is a potential replica and the replenishment wait interval is passed
1. Set `ReplicaReplenishmentWaitInterval` to 60s.
2. Create and attach a large volume.  
3. Write data then take snapshots.
4. Shut down a node containing replica only for 60s.
5. Wait and check if Longhorn tries to reuse the failed replica for 2~3 times but always fail. 
6. Check if Longhorn will create a new replica once the replenishment wait interval is passed.
7. Verify the data content. And check if the volume still works fine.

#### Reuse failed replicas for an old degraded volume after live upgrade:
1. Deploy Longhorn v1.0.2.
2. Create and attach a volume. Write data to the volume.
3. Disable scheduling for 1 node.
4. Crash the replica on the node.
5. Upgrade Longhorn to the latest. Verify the volume robustness `Degraded`.
6. Enable scheduling for the node. Verify the failed replica of the existing degraded volume will be reused.
7. Verify the data content, and the volume r/w still works fine.

#### Failed replicas reusage backoff won't block replica replenishment
1. Deploy the latest Longhorn.
2. Create and attach a volume. Write data to the volume.
3. Update `Replica Replenishment Wait Interval` to 60s.
4. Crash a replica: removing the volume head file and creating a directory with the volume head file name. Then the replica reuse will continuously fail. e.g., `rm volume-head-001.img && mkdir volume-head-001.img`
5. Verify:
    1. There is a backoff interval for the failed replica reuse.
    2. A new replica will be created after (around) 60s despite the failed replica reuse is in backoff.
    3. the data content.
    4. the volume r/w still works fine.

#### Integration Test Plan
##### Reuse the failed replicas when the replica data is messed up
1. Set a long wait interval for setting `replica-replenishment-wait-interval`.
2. Disable the setting soft node anti-affinity.
3. Create and attach a volume. Then write data to the volume.
4. Disable the scheduling for a node.
5. Mess up the data of a random snapshot or the volume head for a replica. Then crash the replica on the node.
   --> Verify Longhorn won't create a new replica on the node for the volume.
6. Update setting `replica-replenishment-wait-interval` to a small value.
7. Verify Longhorn starts to create a new replica for the volume.
   Notice that the new replica scheduling will fail.
8. Update setting `replica-replenishment-wait-interval` to a large value.
9. Delete the newly created replica.
   --> Verify Longhorn won't create a new replica on the node
       for the volume.
10. Enable the scheduling for the node.
11. Verify the failed replica (in step 5) will be reused.
12. Verify the volume r/w still works fine.

#### Reuse the failed replicas with scheduling check
1. Set a long wait interval for setting `replica-replenishment-wait-interval`.
2. Disable the setting soft node anti-affinity.
3. Add tags for all nodes and disks.
4. Create and attach a volume with node and disk selectors. Then write data to the volume.
5. Disable the scheduling for the 2 nodes (node1 and node2).
6. Crash the replicas on the node1 and node2.
   --> Verify Longhorn won't create new replicas on the nodes.
7. Remove tags for node1 and the related disks.
8. Enable the scheduling for node1 and node2.
9. Verify the only failed replica on node2 is reused.
10. Add the tags back for node1 and the related disks.
11. Verify the failed replica on node1 is reused.
12. Verify the volume r/w still works fine.

### Upgrade strategy
Need to update `volume.Status.LastDegradedAt` for existing degraded volumes during live upgrade.

