
# Longhorn Snapshot CRD

## Summary

Supporting Longhorn snapshot CRD allows users to query/create/delete volume snapshots using kubectl. This is one step closer to making kubectl as Longhorn CLI. Also, this will be a building block for the future auto-attachment/auto-detachment refactoring for snapshot creation, deletion, volume cloning.

### Related Issues

https://github.com/longhorn/longhorn/issues/3144

## Motivation

### Goals

1. Support Longhorn snapshot CRD to allow users to query/create/delete volume snapshots using kubectl.
2. A building block for the future auto-attachment/auto-detachment refactoring for snapshot creation, deletion, volume cloning.
3. Pay attention to scalability problem. A cluster with 1k volumes might have 30k snapshots. We should make sure not to overload the controller work-queue as well as making too many grpc calls to engine processes.

## Proposal

Introduce a new CRD, snapshot CRD and the snapshot controller. The life cycle of a snapshot CR is as below:
1. Create (by engine monitor/kubectl)
    1. When user create a new snapshot CR, Longhorn try to create a new snapshot
    2. When there is a snapshot in the volume that isn't corresponding to any snapshot CR, Longhorn will generate snapshot CR for that snapshot
2. Update (by snapshot controller)
    1. Snapshot controller will reconcile the snapshot CR status with the snapshot info inside the volume engine
3. Delete (by engine monitor/kubectl)
    1. When a snapshot CR is deleted (by user or by Longhorn), snapshot controller will make sure that the snapshot are removed from the engine before remove the finalizer and allow the deletion
    2. Deleting volume should be blocked until all of its snapshot are removed
    3. When there is a system generated snapshot CR that isn't corresponding to any snapshot info inside engine status, Longhorn will delete the snapshot CR

### User Stories

Before this enhancement, users have to use Longhorn UI to query/create/delete volume snapshot. For user with only access to CLI,  another option is to use our [Python client](https://longhorn.io/docs/1.2.4/references/longhorn-client-python/). However, the Python client are not as intuitive and easy as using kubectl.

After this enhancement, users will be able to use kubectl to query/create/delete Longhorn snapshots just like what they can do with Longhorn backups. There is no additional requirement for users to use this feature.

The experience details should be in the `User Experience In Detail` later.

#### Story 1
User wants to limit the snapshot count to save space. Snapshot RecurringJobs set to Retain X number of snapshots do not touch unrelated snapshots, so if one ever changes the name of the RecurringJob, the old snapshots will stick around forever. These then have to be manually deleted in the UI.  There might be some kind of browser automation framework might also work for pruning large numbers of snapshots, but this feels janky. Having a CRD for snapshots would greatly simplify this, as one could prune snapshots using kubectl, much like how one can currently manage backups using kubectl due to the existence of the `backups.longhorn.io` CRD.

### User Experience In Detail

There is no additional requirement for users to use this feature.

### API changes

We don't want to have disruptive changes in this initial version of snapshot CR (e.g., snapshot API create/delete shouldn't change. Snapshot status is still inside the engine status).

We can wait for the snapshot CRD to be a bit more mature (no issue with scalability) and make the disruptive changes in the next version of snapshot CR (e.g., snapshot API create/delete changes to create/delete snapshot CRs. Snapshot status is removed from inside the engine status)

## Design

### Implementation Overview

Introduce a new CRD, snapshot CRD and the snapshot controller.
The snapshot CRD is:

```yaml
// SnapshotSpec defines the desired state of Longhorn Snapshot
  type SnapshotSpec struct {
  // the volume that this snapshot belongs to.
  // This field is immutable after creation.
  // Required
  Volume string `json:"volume"`
  // require creating a new snapshot
  // +optional
  CreateSnapshot bool `json:"createSnapshot"`
  // The labels of snapshot
  // +optional
  // +nullable
  Labels map[string]string `json:"labels"`
}

  // SnapshotStatus defines the observed state of Longhorn Snapshot
  type SnapshotStatus struct {
  // +optional
  Parent string `json:"parent"`
  // +optional
  // +nullable
  Children map[string]bool `json:"children"`
  // +optional
  MarkRemoved bool `json:"markRemoved"`
  // +optional
  UserCreated bool `json:"userCreated"`
  // +optional
  CreationTime string `json:"creationTime"`
  // +optional
  Size int64 `json:"size"`
  // +optional
  // +nullable
  Labels map[string]string `json:"labels"`
  // +optional
  OwnerID string `json:"ownerID"`
  // +optional
  Error string `json:"error,omitempty"`
  // +optional
  RestoreSize int64 `json:"restoreSize"`
  // +optional
  ReadyToUse bool `json:"readyToUse"`
}
```
The life cycle of a snapshot CR is as below:

1. **Create**
    1. When a snapshot CR is created, Longhorn mutation webhook will:
        1. Add a volume label `longhornvolume: <VOLUME-NAME>` to the snapshot CR. This allow us to efficiently find snapshots corresponding to a volume without having listing potentially thoundsands of snapshots.
        1. Add `longhornFinalizerKey` to snapshot CR to prevent it from being removed before Longhorn has change to clean up the corresponding snapshot
        1. Populate the value for `snapshot.OwnerReferences` to uniquely identify the volume of this snapshot. This field contains the volume UID to uniquely identify the volume in case  the old volume was deleted and a new volume was created with the same name.
    2. For user created snapshot CR, the field `Spec.CreateSnapshot` should be set to `true` indicating that Longhorn should provision a new snapshot for this CR.
        1. Longhorn snapshot controller will pick up this CR, check to see if there already is a snapshot inside the `engine.Status.Snapshots`.
           1. If there is there already a snapshot inside engine.Status.Snapshots, update the snapshot.Status with the snapshot info inside `engine.Status.Snapshots`
           2. If there isn't a snapshot inside `engine.Status.Snapshots` then:
               1.  making a call to engine process to check if there already a snapshot with the same name. This is to make sure we don't accidentally create 2 snapshots with the same name. This logic can be remove after [the issue](https://github.com/longhorn/longhorn/issues/3844) is resolved
               1. If the snapshot doesn't inside the engine process, make another call to create the snapshot
    3. For the snapshots that are already exist inside `engine.Status.Snapshots` but doesn't have corresponding snapshot CRs (i.e., system generated snapshots), the engine monitoring will generate snapshot CRs for them. The snapshot CR generated by engine monitoring with have `Spec.CreateSnapshot` set to `false`, Longhorn snapshot controller will not create a snapshot for those CRs. The snapshot controller only sync status for those snapshot CRs
2. **Update**
    1. Snapshot CR spec and label are immutable after creation. It will be protected by the admission webhook
    2. Sync the snapshot info from `engine.Status.Snapshots` to the `snapshot.Status`.
    3. If there is any error or if the snapshot is marked as removed, set `snapshot.Status.ReadyToUse` to `false`
    4. If there there is no snapshot info inside `engine.Status.Snapshots`, mark the `snapshot.Status.ReadyToUse` to `false`and populate the `snapshot.Status.Error` with the lost message. This snapshot will eventually be updated again when engine monitoring update `engine.Status.Snapshots` or it may be cleanup as the section below
4. **Delete**
    1. Engine monitor will responsible for removing all snapshot CRs that don't have a matching snapshot info and are in one of the following cases:
       1. The snapshot CRs with `Spec.CreateSnapshot: false` (snapshot CR that is auto generated by the engine monitoring)
       2. The snapshot CRs with `Spec.CreateSnapshot: true` and `snapCR.Status.CreationTime != nil` (snapshot CR that has requested a new snapshot and the snapshot has already provisioned before but no longer exist now)
    2. When a snapshot CR has deletion timestamp set, snapshot controller will:
        1. Check to see if the actual snapshot inside engine process exist.
            1. If it exist do:
                1. if has not been marked as removed, issue grpc call to engine process to remove the snapshot
                2. Check if the engine is in the purging state, if not issue a snapshot purge call to engine process
            2. If it doesn't exist, remove the `longhornFinalizerKey` to allow the deletion of the snapshot CR

### Test plan

Integration test plan.

For engine enhancement, also requires engine integration test plan.

### Upgrade strategy

Anything that requires if user want to upgrade to this enhancement

## Note [optional]

How do we address scalability issue?
1. Controller workqueue
    1. Disable resync period for snapshot informer
    1. Enqueue snapshot only when:
        1. There is a change in snapshot CR
        1. There is a change in `engine.Status.CurrentState` (volume attach/detach event), `engine.Status.PurgeStatus` (for snapshot deletion event), `engine.Status.Snapshots` (for snapshot creation/update event)
1. This enhancement proposal doesn't make additional call to engine process comparing to the existing design.

## Todo

For the special snapshot `volume-head`, we don't create a snapshot CR for this special snapshot because:
1. From the usecase perspective, user cannot delete this snapshot anyway so there is no need to generate this snapshot
1. The name `volume-head` is not globally uniquely, we might have to include volume name if we want to generate this snapshot CR
1. We would have to implement special logic to prevent user from deleting this special CR
1. On the flip side, if we generate this special CR, user will have a complete picture of the snapshot chain
2. The VolumeHead CR may suddenly point to another actual file during the snapshot creation.