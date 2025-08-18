# Volume Offline Rebuilding With Resource Awareness and Retry Backoff

## Summary

After [[FEATURE] V1 and V2 volume offline replica rebuilding](https://github.com/longhorn/longhorn/issues/8443), users can rebuild replicas when degraded volumes are detached. But the original design did not consider the resources of the cluster including schedulable nodes and disks. This enhancement adds support with resource awareness and retry backoff functionalities of offline replica rebuild for Longhorn volumes.

### Related Issues

- https://github.com/longhorn/longhorn/issues/8443
- https://github.com/longhorn/longhorn/issues/11270

## Motivation

### Goals

- When resources are not sufficient, the offline rebuilding will not start.
- When the degraded volumes are attached by the offline rebuilding, Longhorn will detach the volume with a backoff mechanism if resources are not sufficient.

## Proposal

We will add a resource awareness mechanism into the offline rebuilding flow, so it will only mention the modified parts from the [previous proposal](./20250407-volume-offline-rebuilding#proposal).

### User Stories

- Users want to automatically rebuild replicas while a degraded volume is detached to ensure maintain data redundancy.
- A worker node is up with the offline rebuilding enabled. Longhorn will check if resources are sufficient to trigger the offline rebuilding for degraded volumes.
- A worker node is down during the offline rebuilding process. Longhorn will check if resources are sufficient for rebuilding to stop the offline rebuilding. Then users will not have volumes always stuck in attached for unfinishable rebuilding.

### User Experience In Detail

| `Volume.Spec.OfflineRebuilding` \ setting `offline-replica-rebuilding` | `true` | `false` |
| :---: | :---: | :---: |
| `ignored` | ✓ | X |
| `enabled` | ✓ | ✓ |
| `disabled` | X | X |

- ✓: The offline rebuilding is enabled.
- X: The offline rebuilding is disabled.

#### Enable Global Volumes Or An Individual Volume Offline Rebuilding

When offline rebuilding is enabled and volumes are degraded, the degraded volumes will be attached until the volume becomes healthy from the [previous design](./20250407-volume-offline-rebuilding#manually-enable-an-individual-volume-offline-rebuilding). It is not reasonable to keep repeating attaching degraded volumes if the resources are insufficient, for example, only 2 schedulable nodes or disks for 3 replicas.

Therefore, before the volume rebuild controller starts to attach the volume, it will check if there are the disk candidates. If there is no disk candidate, the replica rebuilding will not start until the resources are sufficient.

#### A Worker Node Down During Volume Offline Rebuilding

If a worker node goes down and resources become insufficient (the number of available nodes or disks are less than the number of the replica of volume), users must wait for an interval to confirm that the resources are indeed unavailable for rebuilding the replica. Longhorn will have a replica scheduler to check if there is a failed reusable replica or a disk candidate for rebuilding a replica. The maximum interval will be `replica-replenishment-wait-interval` if the replica scheduler tries to replenish a new replica and fails.
If the volume condition `Scheduled` becomes `false`, the volume will be detached automatically.

#### A Worker Node Up When Volume Offline Rebuilding Enabled

When the offline rebuilding is enabled and a worker node get ready in the cluster, Longhorn will immediately use the replica scheduler to check if the node and its disk are schedulable for degraded volumes. If yes, the degraded volumes will be attached to rebuild the replica. After the replica on this node is rebuilt, the volume will be detached if it is healthy or wait for an interval (the maximum interval will be `replica-replenishment-wait-interval`) to confirm that the resources are insufficient for rebuilding another replica and then the volume will be detached as well.

## Design

Add a resource awareness and a backoff retry mechanisms into the offline rebuilding flow, so here will only mention the modified parts from the [previous design](./20250407-volume-offline-rebuilding#design).

### Resource Awareness

Before creating the volume rebuild VA ticket to attach the volume, the volume rebuild controller will check if there is a reusable replica or a disk candidate:

```golang
import "github.com/longhorn/longhorn-manager/scheduler"
...
func NewVolumeRebuildingController(...) (*VolumeRebuildingController, error) {
  ...

  vbc := &VolumeRebuildingController{
    ...
  }
  vbc.scheduler = scheduler.NewReplicaScheduler(ds)
  ...
}
...
func (vbc *VolumeRebuildingController) syncLHVolumeAttachmentForOfflineRebuild(...) (...) {
  ...
  if !vbc.isVolumeReplicasHealthy(vol.Spec.NumberOfReplicas, replicas) {
    ...
    replicaReusableOrSchedulable, err := vbc.isVolumeReplicasReusableOrSchedulable(vol, replicas)
    ...
    if !replicaReusableOrSchedulable {
      // There is no reusable replica or disk candidate to schedule a new replica 
      return va, nil
    }
    createOrUpdateAttachmentTicket(va, attachmentID, vol.Status.OwnerID, longhorn.AnyValue, longhorn.AttacherTypeVolumeRebuildingController)
  }
  ...
}
...
func (vbc *VolumeRebuildingController) isVolumeReplicasReusableOrSchedulable(vol *longhorn.Volume, rs map[string]*longhorn.Replica) (bool, error) {
  reusableFailedReplica, err := vbc.scheduler.CheckAndReuseFailedReplica(rs, vol, "")
  ...
  if reusableFailedReplica != nil {
    // rebuild this reusable replica first
    return true, nil
  }
  ...
  replicaDiskCandidates, multiError, err := vbc.scheduler.FindDiskCandidates(replica, rs, vol)
  ...
  return len(replicaDiskCandidates) > 0, nil
}
```

### Backoff Retry

Use the volume condition `Scheduled` to check if a replica can be schedulabld to a node or a disk candidate for rebuilding.
When the volume condition `Scheduled` becomes `false`, it means a new replica failed to be scheduled to a disk candidate and resources are insufficient.

In general rebuilding process, the failed reusable replica will have a rebuild retry count and a backoff mechanism (initialized from 1 minute with maximum back off interval 3 minutes.)

```golang
func (c *VolumeController) replenishReplicas(...) ...{
  ...
    reusableFailedReplica, err := c.scheduler.CheckAndReuseFailedReplica(rs, v, hardNodeAffinity)
      ...
    if reusableFailedReplica != nil {
      if !c.backoff.IsInBackOffSinceUpdate(reusableFailedReplica.Name, time.Now()) {
        ...
        if datastore.IsReplicaRebuildingFailed(reusableFailedReplica) {
          reusableFailedReplica.Spec.RebuildRetryCount++
        }
        c.backoff.Next(reusableFailedReplica.Name, time.Now())
        continue
      }
      ...
    }
  ...
```

If there are no failed reusable replicas or rebuilding failed reused replicas failed, and the `replica-replenishment-wait-interval` is up (depend on the `Volume.Status.LastDegradedAt`), the volume controller will try to create a new replica to rebuild the volume.

```golang
func (c *VolumeController) replenishReplicas(...) ...{
  ...
    if checkBackDuration := c.scheduler.RequireNewReplica(rs, v, hardNodeAffinity); checkBackDuration == 0 {
      newReplica := c.newReplica(v, e, hardNodeAffinity)
      if hardNodeAffinity == "" {
        if multiError, err := c.precheckCreateReplica(newReplica, rs, v); err != nil {
          ...
          v.Status.Conditions = types.SetCondition(v.Status.Conditions,
            longhorn.VolumeConditionTypeScheduled, longhorn.ConditionStatusFalse,
            longhorn.VolumeConditionReasonReplicaSchedulingFailure, aggregatedReplicaScheduledError.Join())
            continue
        }
      }
      if err := c.createReplica(newReplica, v, rs, !newVolume); err != nil {
        return err
      }
    } else {
      // Couldn't create new replica. Add the volume back to the workqueue to check it later
      c.enqueueVolumeAfter(v, checkBackDuration)
    }
  }
  ...
}
```

When there is a volume rebuild VA ticket and the volume is attached, the volume rebuild controller will check if the rebuilding is starting by the volume condition `Scheduled`. Volume will be detached and if the volume condition `Scheduled` is `False`.

```golang
...
func (vbc *VolumeRebuildingController) reconcile (...) ... {
  ...
  if vbc.isVolumeReplicasRebuilding(vol, engine) {
    deleteVATicketRequired = types.GetCondition(vol.Status.Conditions, longhorn.VolumeConditionTypeScheduled).Status == longhorn.ConditionStatusFalse
    return nil
  }
}
...
```

### Test plan

- A worker node goes down after enabling offline rebuilding in the cluster with 3 worker nodes:
  1. Create a workload with Longhorn volume with 3 replicas.
  2. Write some data to the volume.
  3. Scale down the workload to detach the volume.
  4. Enable the offline rebuilding by the API `volume.offlineReplicaRebuilding`.
  5. Shutdown a worker node.
  6. Check if the volume offline rebuilding is not triggered.

- A worker node goes down during offline rebuilding in the cluster with 3 worker nodes:
  1. Create a workload with Longhorn volume with 3 replicas.
  2. Write some data to the volume.
  3. Scale down the workload to detach the volume.
  4. Delete a replica of the volume.
  5. Enable the offline rebuilding by the API `volume.offlineReplicaRebuilding`.
  6. Wait for volume rebuilding starts.
  7. Shutdown a worker node.
  8. Check if the volume is still attaching.
  9. The volume is detached and still degraded once volume condition `Scheduled` is false.

- A new worker node is up and added into the cluster with 3 worker nodes:
  1. Create a workload with Longhorn volume with 4 replicas.
  2. Write some data to the volume.
  3. Scale down the workload to detach the volume.
  4. Enable the offline rebuilding by the API `volume.offlineReplicaRebuilding`.
  5. Check if the volume is still detached.
  6. Bring up a new worker node and check if the volume is attached and rebuilding starts.
  7. The volume is detached after healthy replicas count of the volume equals to `Volume.Spec.NumberOfReplicas`.
