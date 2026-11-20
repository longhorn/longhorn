# Volume Group Snapshot

## Summary

Many applications store state on more than one volume (a database with data and WAL on separate PVs, a sharded database across StatefulSets). Longhorn snapshots one volume at a time: nothing ties the per-volume snapshots together, at restore time nothing says which belong to the same attempt, and restoring them together can be inconsistent.

This LEP adds volume group snapshot support: snapshot a set of volumes as one group, through CSI VolumeGroupSnapshot, kubectl, and the Longhorn UI.

A new `SnapshotGroup` CRD and controller turn a group request into one normal `Snapshot` per member volume through the existing per-volume path; the group reports ready when every member snapshot is taken within a bounded deadline. The change is scoped to the control plane.

Consistency boundary: Longhorn snapshots each volume independently, so a group snapshot is crash-consistent per volume and only loosely aligned across volumes. True cross-volume application consistency comes from pausing the application around the group snapshot - the separate snapshot-hook work in [#2128](https://github.com/longhorn/longhorn/issues/2128) that builds on top of this.

### Related Issues

- longhorn/longhorn#13349 (this feature)
- longhorn/longhorn#2128 (application-consistent snapshot/backup; builds on this)
- kubernetes/enhancements#3476 (upstream VolumeGroupSnapshot KEP)

## Motivation

### Goals

- Implement the CSI VolumeGroupSnapshot API (GroupController service) for in-cluster group snapshots (class `type: snap`) and backup-type group snapshots (class `type: bak`): the same group snapshot, followed by a per-member upload through the existing backup path.
- Offer the same grouping through the Longhorn UI, backed by new REST endpoints: create, inspect, and delete snapshot groups, and make group membership visible on the volume's snapshot list.
- Reuse the existing per-volume snapshot path unchanged.
- Report status that cannot be misread: an explicit phase (InProgress, Ready, Failed), per-member snapshot creation times, and a completion deadline that forces an unfinished group to Failed. A group that failed or snapshotted only some members never passes for a consistent one.
- Provide the foundation #2128 builds on: check whether group snapshot is available, request a group snapshot, learn when it finishes, and verify every member snapshot was taken inside the pause window.

### Non-goals

- Application-level consistency (pausing the application). Future work in #2128.
- A dedicated group-backup object (a `BackupGroup` CRD) and scheduled group backups. Consistency is decided when the snapshots are taken, not when they are uploaded, so no group-level backup machinery is needed; CSI `type: bak` groups reuse the existing per-volume backup path.
- Recurring group snapshots: a RecurringJob that creates a `SnapshotGroup` on a schedule. Follow-up work that needs its own design. Existing per-volume recurring jobs are unaffected, except the `snapshot-delete` task: its retain count applies to every snapshot on the volume, so it can age out a member and degrade the group like any other out-of-band member deletion. This is deliberate. `snapshot-delete` enforces a hard retention limit on the volume; skipping group members would let a forgotten group hold snapshots until the volume reaches `snapshot-max-count` and new snapshots start failing. A visibly Degraded group is the safer failure. Future work if protection is ever wanted.

## Proposal

One layer above the existing per-volume Snapshot CR path. Nothing below it changes:

```
CSI VolumeGroupSnapshot | UI | kubectl
        |
        |  every entry point creates the same CR
        v
SnapshotGroup CR
        |
        |  the group controller creates one Snapshot CR per member
        v
member Snapshot CRs
  (the existing per-volume path, unchanged)
        |
        |  the group controller mirrors each member's status into the group
        v
group status
  (phase: InProgress -> Ready | Failed)
```

### User Stories

#### Story 1: snapshot a multi-volume application

Today an operator running a database with data and WAL on two PVs must create two `VolumeSnapshot`s separately. The snapshots are taken at uncoordinated times, nothing ties them together, and at restore time nothing says which two snapshots belong to the same attempt.

After this enhancement the operator creates one `VolumeGroupSnapshot` selecting both PVCs. Kubernetes returns one `VolumeSnapshot` per PVC, all bound to the same group, created by one request. Restoring both from the same group is one clear decision.

#### Story 2: application-consistent group snapshot (#2128)

An operator wants backups that a database can actually recover from. With #2128, a pre-hook pauses the application, this feature snapshots all member volumes, and a post-hook resumes it.

#2128 needs from this LEP only: a way to detect group support, a way to request a group snapshot of a fixed set, a signal when it finished or failed, and per-member creation times to verify every member snapshot was taken inside the pause window.

### User Experience In Detail

Prerequisites (documentation only):

- The group CRDs installed (`VolumeGroupSnapshot`, `VolumeGroupSnapshotContent`, `VolumeGroupSnapshotClass`), from external-snapshotter v8.6.0 or later so they serve the `v1` API - and installed before any component's feature gate is enabled anywhere.
- snapshot-controller from [external-snapshotter](https://github.com/kubernetes-csi/external-snapshotter/releases) v8.6.0 or later, with the `CSIVolumeGroupSnapshot` feature gate enabled. It verifies the CRDs at startup and crash-loops loudly when they are missing.
- The Longhorn deploy-time toggle for CSI group snapshot support enabled (default off). When the toggle is on without the CRDs served at `v1`, the Longhorn driver deployer fails fast with an error naming the missing kinds.

There is no new Kubernetes version requirement: the group API is CRD-based, and external-snapshotter v8.6.0 requires only Kubernetes 1.25, below Longhorn's existing minimum.

CSI flow:

1. The user labels the PVCs to use for snapshot grouping (for example `app-group: demo`).
2. The user creates a class:

   ```yaml
   # v1 since the API's Kubernetes GA (v1.36), served by the pinned
   # csi-snapshotter v8.6.0 or later; older releases serve v1beta2
   apiVersion: groupsnapshot.storage.k8s.io/v1
   kind: VolumeGroupSnapshotClass
   metadata:
     name: longhorn-group-snap
   driver: driver.longhorn.io
   deletionPolicy: Delete
   parameters:
     type: snap
   ```

   A class with `type: bak` requests a group backup instead: the same group snapshot is taken, then every member snapshot is uploaded through the existing per-volume backup path.

3. The user creates a `VolumeGroupSnapshot` (upstream kind) in the application namespace with a selector matching the PVC labels. The snapshot-controller and csi-snapshotter call `CreateVolumeGroupSnapshot` on Longhorn, which creates one `SnapshotGroup` CR in `longhorn-system`.
4. When every member snapshot is taken, the group reports ready and the snapshot-controller creates one `VolumeSnapshot` per member PVC. Each is a normal `VolumeSnapshot`: the user restores it on its own as a PVC `dataSource`, like any per-volume snapshot.
5. `kubectl -n longhorn-system get snapshotgroups` shows the group phase, per-member state, and creation times. User can also create `SnapshotGroup` CRs directly with kubectl; the behavior is identical.

Longhorn UI flow (works even when `csi.volumeGroupSnapshotEnabled` is off):

1. A new Snapshot Groups page lists the groups and their status, kept live by the watch stream. Selecting a group shows its members and errors.
2. Create opens a dialog matching the CRD spec: name, exactly one selection mode (explicit volumes or a label selector), optional engine snapshot labels, and the deadline. If the webhook rejects the create, the dialog shows the rejection message. In selector mode, a live preview (the preview action) shows the resolved member set before submit. Selecting volumes on the volume list page opens the same dialog pre-filled.
3. The UI offers create, inspect, and delete only - no edit, the same shape as the API. Failed and Degraded groups offer a Recreate action that opens the create dialog pre-filled from the old group's spec; it creates a new group and never mutates the old one.
4. Delete asks for confirmation and states that the member snapshots are deleted with the group.
5. On the volume detail page, a member snapshot shows a group badge, and deleting it warns that the group becomes Degraded and offers deleting the entire group.

The sketches below show the intended surfaces. Visual layout is the UI team's call.

The Snapshot Groups page:

```
+--------------------------------------------------------------------+
|  Snapshot Groups                                                   |
|                                                                    |
|  [ Filter: Name v ] [ search text ]  [ Status v ]  [ Create Group ]|
|                                                                    |
|  [ ] | Name              | Status             | Members | Created  |
|  ----+-------------------+--------------------+---------+----------|
|  [ ] | group-a           | Degraded           | 1/2     | 10:00:12 |
|  [ ] | group-b           | InProgress         | 2/3     | 10:02:44 |
|  [ ] | group-c           | Failed             | 3/5     | 09:41:03 |
|  [ ] | group-d           | Ready              | 2/2     | 09:12:07 |
|                                                                    |
|  [ Delete ]  (bulk, enabled on selection)                          |
+--------------------------------------------------------------------+
```

Group detail:

```
+-----------------------------------------------------------------------------------+
| Snapshot Group: group-a                                          Phase: Ready     |
|                                                                                   |
| ! Degraded: member snapshot "group-a-5e6f7a8b" was deleted                        |
|   after the group became Ready. The group no longer represents a complete set.    |
|                                                                                   |
| Selection: explicit volumes          Deadline: 300s                               |
| Engine labels: app-group=demo                                                     |
| Creation time: 2026-07-29 10:00:12 (latest member snapshot)                       |
|                                                                                   |
| Members                                                                           |
| +------------------+---------------------------------+-------+----------+-------+ |
| | Volume           | Snapshot                        | Ready | Created  | Error | |
| +------------------+---------------------------------+-------+----------+-------+ |
| | pvc-6c30f5a5-... | group-a-1a2b3c4d                | true  | 10:00:11 |       | |
| | pvc-8a1e22b7-... | group-a-5e6f7a8b                | false | 10:00:12 | lost  | |
| +------------------+---------------------------------+-------+----------+-------+ |
|                                                                                   |
|                                                              [ Delete Group ]     |
+-----------------------------------------------------------------------------------+
```

The create dialog (identical from both entry points):

```
+---------------------------- Create Snapshot Group --------------------------------+
| Name:               [ group-a                            ]                        |
|                                                                                   |
| Select members by:  (o) Volumes         ( ) Label selector                        |
|                                                                                   |
|   Volumes: [ pvc-6c30f5a5-... x ] [ pvc-8a1e22b7-... x ]  [ + add ]               |
|                                                                                   |
|   (Label selector mode instead shows:                                             |
|      key [ app-group ]  value [ demo ]   [ + add rule ] )                         |
|                                                                                   |
| Engine snapshot labels (optional):  key [ ____ ] value [ ____ ]  [ + ]            |
| Deadline seconds:   [ 300 ]                                                       |
|                                                                                   |
| ! webhook rejection shown inline, for example:                                    |
|   "volume pvc-9d41... is a standby volume and cannot be a member"                 |
|                                                                                   |
|                                                      [ Cancel ]   [ OK ]          |
+-----------------------------------------------------------------------------------+
```

The volume list entry point:

```
+-----------------------------------------------------------------------------------+
| Volume                                                                            |
|                                                                                   |
| [x] pvc-6c30f5a5-...    Attached    Healthy    ...                                |
| [x] pvc-8a1e22b7-...    Attached    Healthy    ...                                |
| [ ] pvc-1f77c0aa-...    Detached    -          ...                                |
|                                                                                   |
| Bulk: [ Attach ] [ Detach ] [ Create Backup ] [ Create Snapshot Group ] ...       |
|                                                       |                           |
|            checked volumes pre-fill the dialog <------+                           |
+-----------------------------------------------------------------------------------+
```

The volume detail snapshot list, with the group badge and the delete warning:

```
Volume: pvc-6c30f5a5-...  >  Snapshots

+---------------------------------+---------+----------+--------------------------+
| Name                            | Size    | Created  | Group                    |
+---------------------------------+---------+----------+--------------------------+
| group-a-1a2b3c4d                | 120 MiB | 10:00:11 | [group-a] link           |
| manual-snap-01                  |  80 MiB | 18:22:40 |                          |
+---------------------------------+---------+----------+--------------------------+

Deleting a member snapshot:
+----------------------------- Confirm delete --------------------------------+
| Snapshot "group-a-1a2b3c4d" belongs to snapshot group                       |
| "group-a". Deleting only this snapshot marks the group Degraded;            |
| it will no longer represent a complete point-in-time set.                   |
|                                                                             |
|    [ Cancel ]   [ Delete snapshot only ]   [ Delete entire group... ]       |
+-----------------------------------------------------------------------------+
```

### API changes

- New CRD `SnapshotGroup` (`longhorn.io/v1beta2`), detailed below. The name avoids clashing with the upstream `groupsnapshot.storage.k8s.io` kind `VolumeGroupSnapshot`. The `Snapshot` CRD is unchanged.
- New CSI GroupController service with `CreateVolumeGroupSnapshot`, `DeleteVolumeGroupSnapshot`, `GetVolumeGroupSnapshot`.
- A new deploy-time toggle, `csi.volumeGroupSnapshotEnabled` (default off), enables CSI group snapshot support.
- Longhorn REST API: a new top-level `snapshotGroup` collection, plus one new field on the existing snapshot resources. The existing `snapshot*` operations are actions on a single volume; a group covers several volumes at once, so it does not belong under any single volume and is a top-level resource instead.

  | Method | Path | Behavior |
  |---|---|---|
  | `GET` | `/v1/snapshotgroups` | List groups. |
  | `GET` | `/v1/snapshotgroups/{name}` | Get one group. |
  | `POST` | `/v1/snapshotgroups` | Create a group. Fields: `name`, exactly one of `volumes` / `volumeSelector`, optional `labels`, optional `deadlineSeconds`. |
  | `DELETE` | `/v1/snapshotgroups/{name}` | Delete the group and its members - the same path kubectl deletion takes. |
  | `POST` | `/v1/snapshotgroups?action=preview` | Preview a create without creating anything: runs the same resolver admission uses and returns the volumes the spec would select and, when a volume cannot be a member, the reason why. Failures that would reject the create are reported in the response body, not as HTTP errors. |
  | `GET` | `/v1/ws/snapshotgroups`, `/v1/ws/{period}/snapshotgroups` | Watch stream. Both forms are registered like every existing resource stream; the UI uses the `{period}` form (for example `/v1/ws/1s/snapshotgroups`). |

  There is no update endpoint: the spec is immutable.

  The preview action backs the UI's selector-mode live preview. The input takes the create fields that affect membership (`volumes` / `volumeSelector`). The preview shows no member snapshot names, since admission generates them at creation. The preview is advisory: admission re-resolves the membership, so the final member set can differ from the preview.

  The group resource returns the CR's create fields (`volumes` / `volumeSelector`, `labels`, `deadlineSeconds`) and status fields unchanged, plus `created` (from `metadata.creationTimestamp`) and `degraded`, derived from the Degraded condition so clients do not parse conditions.

- Existing snapshot REST resources: one new field, `snapshotGroup`, naming the group the snapshot belongs to (from its `longhorn.io/snapshot-group` label; empty for non-members). It is set on both the snapshot CR resource (`snapshotCRList` / `snapshotCRGet`) and the engine snapshot resource (`snapshotList` / `snapshotGet`); the volume detail page lists engine snapshots, so the UI reads it from there.

## Design

### Implementation Overview

#### How a snapshot works today

Three entry points already converge on the Snapshot CR path, and this LEP layers on that convergence point:

```
CSI CreateSnapshot (class type "snap") --\
recurring job                           ---> Snapshot CR -> snapshot_controller -> engineClientProxy.SnapshotCreate
v1 API snapshotCRCreate                --/                  (resolves the engine, applies freezeFilesystem)
```

The group controller creates one Snapshot CR per member, so everything downstream - engine resolution, freezeFilesystem, auto-attach of detached volumes - is reused unchanged.

Two other paths exist and stay untouched: the v1 `snapshotCreate` API calls the engine directly with no Snapshot CR, so there is nothing a controller could group; and a per-volume CSI CreateSnapshot with class type empty or `bak` takes the backup path.

#### New CRD: SnapshotGroup (longhorn.io/v1beta2)

```yaml
apiVersion: longhorn.io/v1beta2
kind: SnapshotGroup
metadata:
  name: group-a
  namespace: longhorn-system
spec:
  # The user sets exactly one of volumes / volumeSelector; setting both or neither fails
  # admission. The mutating webhook resolves it into members at admission; after that the
  # whole spec is immutable.
  volumes:
    - "pvc-6c30f5a5-..."
    - "pvc-8a1e22b7-..."
  # volumeSelector:
  #   matchLabels:
  #     app-group: demo
  labels:                               # engine snapshot labels for every member (Snapshot spec.labels)
    app-group: demo
  deadlineSeconds: 300                  # defaulted by the webhook when unset
  members:                              # stamped by the webhook at admission; a restore keeps them
    - volumeName: "pvc-6c30f5a5-..."
      snapshotName: "group-a-1a2b3c4d"
    - volumeName: "pvc-8a1e22b7-..."
      snapshotName: "group-a-5e6f7a8b"
status:
  ownerID: ""              # the node whose controller reconciles this group
  phase: InProgress        # InProgress -> Ready | Failed; empty until the first reconcile
  members:
    - volumeName: "pvc-6c30f5a5-..."
      snapshotName: "group-a-1a2b3c4d"
      readyToUse: false
      creationTime: ""     # engine snapshot creation time, mirrored from the member Snapshot
      error: ""
  readyToUse: false        # the AND of member readiness; can drop after Ready if a member is lost
  creationTime: ""         # latest member creation time, set when the group becomes Ready
  error: ""                # set when the group fails (deadline, collision)
  conditions: []           # Degraded: a Ready group whose member set is no longer complete
                           # (deleted out-of-band, or lost in a restore)
```

Spec rules, all enforced at admission (mutating and validating webhooks under `webhook/resources/snapshotgroup/`):
- Exactly one of `volumes` or `volumeSelector` is set by the user; `members` is never user-settable. The mutating webhook resolves the selection into `spec.members`, sets `deadlineSeconds` when unset (default 300, valid range 10 to 3600, measured from the group's `metadata.creationTimestamp`), and adds the `longhorn.io` finalizer. The one exception is the restore of a finished group, marked by the terminal-phase annotation: it keeps its stamped members instead of resolving the selection again.
- An empty `volumes` list, a selector matching zero volumes, and duplicate entries in `volumes` all fail admission.
- Every member volume must be eligible for a snapshot at admission: standby (DR), restoring, faulted, and legacy linked-clone volumes are rejected. Admission checks this once, at creation time: if a volume later becomes ineligible (it faults, for example), its member snapshot cannot be taken, the error is recorded on that member's status entry, and the group fails when the deadline passes.
  - Migrating volumes are deliberately not checked. A migration only delays the member snapshot: it is reported as a transient member error, the snapshot completes once the migration finishes, and the deadline bounds the wait.
  - Detached volumes are eligible; the existing snapshot controller auto-attaches them.
- Member count is capped at 64, a fixed constant in the initial release. The cap bounds the simultaneous attach fan-out (a group of detached volumes auto-attaches all of them at once), not the status size. If a real workload ever needs more, the cap can become a setting without an API change.
- `labels` are validated with the same rules as Snapshot `spec.labels`, so a bad label fails the group at admission instead of failing some members mid-fan-out. Admission also rejects the reserved recurring-job label key, which would enroll every member into a job's retention cleanup.
- The group name is at most 54 characters and must be a valid label value, since it becomes the value of the `longhorn.io/snapshot-group` label on every member. The 54 is the member name budget: the group name plus a 1-character separator plus an 8-character random suffix must fit 63 characters, so member names never truncate. CSI-generated names (`groupsnapshot-<uuid>`, 50 characters; Longhorn configures no name prefix) fit; longer names from any source fail admission.
- After creation the whole spec is immutable: a group is a point-in-time request, so changing members later has no meaning.

Member snapshot names are the group name plus a random suffix, generated once at admission and stamped into `spec.members`:

```
snapshotName = <groupName> + "-" + 8 random characters
```

The suffix is random, not derived from the volume name, so a reused group name never reproduces the names of an earlier group: deleting a group and creating a new one with the same name must not let the new group adopt a leftover member snapshot of the old one. Member backups are named the same way.

The volume name is deliberately absent: including it would force truncation - a 50-character CSI group name would leave it 4 characters, a "pvc-" fragment identical for every member. The volume is instead carried next to the name everywhere it appears: `spec.volume`, the kubectl Volume column, `status.members`, and the `longhornvolume` label. The cost: members of one group differ only in their suffix, so a bare name in a log line needs the volume field beside it.

Staying within 63 characters keeps the name safe everywhere it is used: as a Kubernetes object name, an engine snapshot name, a replica on-disk filename component (`volume-snap-<name>.img.meta`), and a label value.

Two label namespaces, deliberately distinct:

- `metadata.labels` on member Snapshots: the controller sets `longhorn.io/snapshot-group: <groupName>`. This is what listing, watching, adoption, and cleanup key on, so the snapshot webhook makes it immutable.
- `Snapshot spec.labels`: the group's `spec.labels` are copied here per member. These are applied to the engine snapshot as labels and are not visible to Kubernetes label selectors.

#### New controller: snapshot_group_controller

Sits next to `snapshot_controller.go`, registered the same way. It is a reconcile loop guarded by the phase:

1. On the first reconcile, initialize `status.members` from `spec.members` and set the phase to InProgress. The phase is empty before this; there is no Pending phase because it would carry no information a watcher could act on.
2. InProgress: for each member whose Snapshot CR does not exist, create it with the name from `spec.members`, `spec.volume` set to the member volume, `CreateSnapshot=true`, engine labels from group `spec.labels`, and the `longhorn.io/snapshot-group` metadata label.
   - The group takes no ownerReference on members; they keep the Volume ownerReference the existing snapshot mutator sets. A group ownerReference would not give cleanup anyway: Kubernetes GC deletes an object only when all of its owners are gone, so deleting the group would leave every member behind under its Volume owner. Cleanup is therefore explicit (step 5).
   - A Snapshot CR with a member's name may already exist. If it carries this group's metadata label and its `spec.volume` is the member volume, the controller created it on an earlier reconcile: it is adopted as the member, which makes fan-out retryable. Otherwise it is an unrelated snapshot that happens to collide on the name: the controller fails the group with a name-collision error and leaves it untouched, because adopting it would put a snapshot the group never took into the set and destroy it at group cleanup.
3. Mirror every member Snapshot's `readyToUse`, `error`, and creation time into `status.members`.
   - Mirroring writes the member's current state: an error that clears on the member clears in the group too. Per-volume errors routinely resolve on their own (a detached volume being auto-attached, an engine upgrade in flight, a live migration), so an error becomes a group failure only when it is still present at the step 4 deadline. The existing CSI wait behaves the same: it watches only `readyToUse` and ignores errors until its timeout.
   - Mirroring continues after the group is Ready. A member Snapshot later deleted or unusable flips its entry to `readyToUse: false`, keeping the recorded creation time. A deleted CR has no status left to mirror, so the controller sets that member's `error` in `status.members` to say the snapshot was deleted; an unrelated snapshot that later takes the member's name is never adopted.
4. Phase transitions. The deadline is the group's `metadata.creationTimestamp` plus `deadlineSeconds`.
   - All members ready, each with a creation time between the group's creation and the deadline -> phase Ready, `readyToUse: true`, `creationTime` = latest member creation time. Terminal for snapshot creation. The lower bound rejects a survivor of an earlier same-named group: a member snapshot taken before this group was requested can never make it Ready.
   - Otherwise, once the deadline passes -> phase Failed; `error` names the unready members and their last errors. Terminal.
     - The controller requeues itself on the deadline, so the transition does not wait for the next resync.
     - Member snapshots already taken are kept as valid per-volume snapshots until the group is deleted.
     - Ready checks member creation times, not just readiness, to stay correct across controller downtime. If the controller is down when the deadline passes and the member snapshots complete late, it wakes to find every member ready - but the snapshots were taken after the deadline, so the group goes Failed, not Ready. The check compares engine-reported creation times with the API server's `creationTimestamp`, so it assumes synchronized node clocks.
   - After Ready or Failed the controller never creates another member snapshot. If a member of a Ready group is later deleted out-of-band (UI, cleanup, purge) or becomes unusable, the controller sets a Degraded condition and takes no replacement: a snapshot taken later would silently break the point-in-time set the group exists to represent.
     - The group's `status.readyToUse` follows the members: it is the AND of member readiness, so a lost or unusable member drops it to false. A group with a missing member is not restorable as a set. The phase stays Ready - phases are terminal and record how creation ended; the Degraded condition names the affected members.
     - Degraded is not permanent by itself: when an unusable member recovers, its `status.members[].readyToUse` returns to true, and the condition clears and `status.readyToUse` returns to true once every member is usable again. Only a member deleted out-of-band cannot recover, so its Degraded stays for good.
5. Deletion: the group carries the `longhorn.io` finalizer. When the group is deleted, the controller requests deletion of every member Snapshot CR in `spec.members` through the existing per-volume deletion path; only a snapshot carrying the group's metadata label is deleted, so a foreign snapshot that took a member's name stays. Once every member has its DeletionTimestamp set, the finalizer comes off and the group is gone; the controller does not wait for the member CRs to disappear.
   - Waiting for the CRs to disappear could block group deletion indefinitely: the v1 engine cannot purge a volume's latest snapshot, so a member that is the latest snapshot stays until a newer snapshot exists. The wait is also unnecessary: a requested deletion cannot be undone, and the existing snapshot controller finishes the purge later. Per-volume CSI `DeleteSnapshot` already returns on the same signal.
   - Deleting a volume is unchanged by groups: Kubernetes garbage-collects that volume's member CR through its Volume ownerReference, and the group reports the loss like any other member deletion (steps 3 and 4).

The controller calls no engine code: every member snapshot goes through the existing per-volume Snapshot CR path.

Because the member set lives in `spec`, a status-stripping re-apply or restore of the group CR (GitOps, Velero) never re-resolves the selector: the members and their names are fixed in the object.

On entering Ready or Failed, the controller records the outcome in the `longhorn.io/snapshot-group-terminal-phase` annotation. This annotation is the restore guard: when the annotation carries a terminal phase the status does not show, the controller restores that phase and never creates members. Restores that strip status still preserve annotations (Velero, a re-applied live-object export), so a restored group can never silently auto-attach member volumes and take fresh snapshots in the middle of a disaster recovery. For a restored Ready group whose `status.creationTime` was stripped, the controller re-derives it from the latest re-mirrored member creation time; for a restored Failed group whose `status.error` was stripped, it records that the original failure reason was not preserved. Two details make the guard hold in edge cases:
- The guard never checks whether member CRs exist. This protects a restored Failed group whose member snapshots all survived: if the guard skipped such a group, normal reconciliation would find every member ready, compare against the fresh creationTimestamp, and flip the group to Ready - silently reversing the recorded Failed outcome.
- The guard runs when the phase is empty (a restored copy of a finished group) or still InProgress (a crash landed between the two writes of the terminal transition: the annotation first, then the status). Either half-written state recovers on the next reconcile:
  - An annotation without the phase is what a crash leaves, since the annotation is written first; the guard applies the annotated phase.
  - A phase without the annotation can only come from the annotation being removed by hand; the terminal reconcile re-stamps it.

Hand-edited group YAML also behaves predictably:
- Hand-adding the annotation to a new group's YAML before creating it produces a group that never takes any snapshots, and hand-adding it to a group still InProgress ends the group the same way: the guard applies the annotated phase directly. To get a working group, delete it and recreate it without the annotation.
- A full-object replace that drops `spec.members` (for example `kubectl replace` from the original manifest) is rejected by spec immutability. The failure is explicit; the selector is never silently re-resolved.

Longhorn's system backup archives an explicit list of Longhorn resources, not every `longhorn.io` CRD. `Snapshot` is not in that list: snapshot data lives on replica disks, and archiving or restoring the CR cannot bring the data back. `SnapshotGroup` stays out for the same reason: with no restorable members, an archived group record would have nothing useful in it.

Observability: the controller emits a Kubernetes event on the group for every phase transition and for setting the Degraded condition; the Failed event names the reason. For per-member detail, `status.members` is the primary debugging signal.

#### CSI: GroupController service

The controller today advertises (in `csi/controller_server.go`): `CREATE_DELETE_VOLUME`, `PUBLISH_UNPUBLISH_VOLUME`, `EXPAND_VOLUME`, `CREATE_DELETE_SNAPSHOT`, `CLONE_VOLUME`, `GET_CAPACITY`, `SINGLE_NODE_MULTI_WRITER`.

Add the GroupController service (capability `CREATE_DELETE_GET_VOLUME_GROUP_SNAPSHOT`), advertised only when `csi.volumeGroupSnapshotEnabled` is on:

- `CreateVolumeGroupSnapshot`: idempotent by group name - create the `SnapshotGroup` CR if absent, then wait on its phase. The created group is a record of the request: the volume set in its immutable spec, the type in an immutable `longhorn.io/snapshot-group-csi-type` label, and the remaining class parameters in an annotation. A sidecar retry whose arguments still match the record reports the group's current state. A retry whose arguments changed (for example, edited PVC labels now select a different volume set) is a different request on a taken name and fails with AlreadyExists, the CSI response for an existing name with incompatible arguments. A group without the type label was not created through CSI: Create refuses the name, Get reports it not found, and Delete leaves it alone.
  - InProgress: poll until Ready, Failed, or the RPC deadline.
  - Ready: return the group with one snapshot entry per member. The group handle is `snap://<group>`. Each member `snapshot_id` uses the existing `snap://<volume>/<snapshot>` encoding, so the per-PVC `VolumeSnapshotContent`s delete and restore through the existing per-volume CSI code. Per-member `creation_time` is the engine snapshot creation time; the group `creation_time` is the latest member creation time.
  - Failed: delete the `SnapshotGroup` CR, then return a terminal error. An error response records no handle, so the sidecar could never reach `DeleteVolumeGroupSnapshot` to clean the group up; deleting it in the Create handler removes its member snapshots with it and leaves nothing orphaned, and the next sidecar retry starts fresh with a new deadline window. The retries end when a create succeeds or the user deletes the Kubernetes `VolumeGroupSnapshot`.
- `DeleteVolumeGroupSnapshot`: delete the CR and wait for the finalizer to come off. The RPC honors its deadline, and the sidecar retries on timeout. Deleting an already-missing group returns OK.
- `GetVolumeGroupSnapshot`: report live state while the group is still working, and the outcome it ended with once it is done. A `snap` group is done at its terminal phase; a `bak` group only when every member backup completes (backup-type section). A missing group returns NotFound, and a Failed group returns its failure as an error; only statically provisioned content can reach a Failed group, since Create deletes the groups it fails.
  - Before the group is done, the handler reports the live member state, the same signal the create-time poll watches.
  - Once a `snap` group is Ready, the handler reports every member `ready_to_use` true with its preserved creation time: a lost member's mirrored entry is a loss marker, and CSI must not report a finished snapshot as still in progress. The group-level `ready_to_use` mirrors `status.readyToUse`, so it drops to false when a member is lost after Ready.
  - In practice the sidecar stops polling a content once it is ready, so the Kubernetes `VolumeGroupSnapshot` keeps reporting ready and a post-Ready loss is visible only on the Longhorn side (condition, REST, UI). The per-volume path goes stale the same way: a bound `VolumeSnapshotContent` is not re-reported after an out-of-band deletion.
- `VolumeGroupSnapshotClass` parameters: `parameters.type` accepts `snap` (group snapshot) and `bak` (group snapshot, then a per-member backup upload). Empty and `bi` are rejected with InvalidArgument naming the valid values.
  - Rejecting empty is deliberate: the per-volume path defaults empty to backup only for backward compatibility, and group classes have no old classes to stay compatible with.
  - `parameters.backupMode` is also reserved: it sets the backup mode for a `bak` group's member backups (default incremental), and a `snap` group ignores it.
  - All other class parameters become the group's engine snapshot labels (`spec.labels`); only the two reserved keys stay out, unlike the per-volume path, which forwards them too. They go through the same webhook validation, so a reserved or malformed key fails the create with InvalidArgument.

#### CSI: backup-type groups (class `type: bak`)

A class with `type: bak` produces a group backup: the same group snapshot is taken first, then each member snapshot is uploaded through the existing per-volume backup path. Everything `bak`-specific lives in the CSI handlers - the `SnapshotGroup` CRD, webhooks, controller, REST API, and UI are unchanged, and the member backups are normal `Backup` CRs.

```
CreateVolumeGroupSnapshot (type: bak)
        |
        v
same SnapshotGroup CR, same admission, same deadline
        | phase Ready
        v
one Backup CR per member snapshot, existing backup path
        |
        v
group ready_to_use when every backup completes
```

- The group handle carries the type: `bak://<group>` versus `snap://<group>`. `GetVolumeGroupSnapshot` and `DeleteVolumeGroupSnapshot` receive only the handle, never the class parameters, and both behave differently for a `bak` group (delete must also remove the member backups), so the handle is what tells them the type. Each member's `snapshot_id` uses the existing `bak://<volume>/<backup>` format, so restoring or deleting a single member runs through the per-volume backup CSI code unchanged.
- Create behaves exactly as for `snap` up to phase Ready. After Ready, it finds or creates one `Backup` per `spec.members` entry, looked up by the member snapshot name, so a retried Create only fills in missing Backup CRs and reports progress; the uploads themselves run independently. Retries racing across plugin processes can briefly duplicate a member backup; the fan-out deletes the extras, keeping one per member. A member backup error returns Internal naming the failed members; deleting the failed Backup CR lets the next retry replace it. The backup mode comes from the record stamped at creation; a `bak` group whose record is missing or unreadable returns an error rather than a guessed mode, since a guess could mix upload modes within one group.
- Member Backup CRs carry two labels: `longhorn.io/snapshot-group: <group>` and the group's UID. The fan-out matches both, so a group never adopts backups left by an earlier group with the same name; deletion matches the name alone, so it sweeps every member backup a failed run left behind, including an earlier same-named group's leftovers. The group label is also set in each member Backup's `spec.labels`, which the existing backup path stores in the backup metadata on the backup target; there it identifies which backups belong to the same group, so a restore from another cluster can find the whole set.
- When the fan-out first sees every member backup Completed, it records completion in a backups-completed annotation whose value maps each member snapshot to its backup. Until then, group `ready_to_use` is computed live from the member backups; afterwards it stays true even if a backup is later deleted - the same rule the `snap` type applies to its phase - and each member handle keeps its recorded backup name. A member whose backup does not exist yet is omitted from the response: it has no handle to report, and only a not-ready view can be missing members.
- Times are snapshot creation times, never upload times, so #2128's pause-window verification would work identically for both types. The deadline also bounds only taking the snapshots; uploads run unbounded, like any per-volume backup.
- Degraded is unchanged: the condition still tracks only the member snapshots, exactly as for `snap`, because the controller knows nothing about backups. A member snapshot lost after its upload completed still marks the group Degraded, but the backup stays restorable - a completed backup is a self-contained copy on the target.
- Deletion order: member backups first (found by the group label), then the group CR, whose finalizer deletes the member snapshots before it releases. Backups go first so that each member snapshot stays alive until its upload has been stopped through its Backup CR - a snapshot is never deleted under an in-flight upload.

The csi-snapshotter polls in two stages: it retries `CreateVolumeGroupSnapshot` until a response records the group handle on the `VolumeGroupSnapshotContent`, then polls `GetVolumeGroupSnapshot` until the group reports ready. The upload fan-out therefore runs in both RPCs: each call finds or creates the missing member backups, surfaces failed uploads, and stamps completion, so a `bak` group reaches completed backups in either stage. See csi-snapshotter v8.6.0 ([`pkg/sidecar-controller/groupsnapshot_helper.go`](https://github.com/kubernetes-csi/external-snapshotter/blob/v8.6.0/pkg/sidecar-controller/groupsnapshot_helper.go#L199-L208)).

#### Longhorn REST API and UI

The REST handlers and the UI implement what the API summary and User Experience In Detail already describe. The one decision to record here is that the generated Go REST client gains no `snapshotGroup` resource, because nothing would consume it. The UI speaks HTTP directly. The CSI group server writes `SnapshotGroup` CRs with a typed Kubernetes clientset, while the other CSI servers call the Longhorn REST API through the generated client. Not following that pattern loses nothing: the REST layer has no validation of its own, and the admission webhook checks every `SnapshotGroup` write no matter which client sends it. Add the client resource only when a real consumer appears.

#### Deployment and activation

VolumeGroupSnapshot support lives in external-snapshotter v8+, behind the `CSIVolumeGroupSnapshot` feature gate in the existing csi-snapshotter sidecar and in the user-deployed snapshot-controller; there is no separate sidecar to deploy. On the Longhorn side, longhorn-manager already depends on CSI spec v1.12.0, which defines the GroupController service, and the CSI driver requirements did not change when the Kubernetes API reached GA, so no dependency upgrade is needed on the driver side. This feature bumps the pinned csi-snapshotter to v8.6.0 or later, which serves the GA `v1` group API; v8.5.x serves only `v1beta2`.

Activation is an explicit deploy-time toggle, default off. For Helm installs it is the chart value `csi.volumeGroupSnapshotEnabled`; for kubectl installs, the generated deploy manifests carry the same variable commented out, with the CRD prerequisite noted next to it. When enabled, it sets `CSI_VOLUME_GROUP_SNAPSHOT_ENABLED` on the driver deployer, which adds the feature-gate flag to the csi-snapshotter it deploys, and the CSI plugin advertises the GroupController capability.

RBAC for `groupsnapshot.storage.k8s.io` and `snapshotgroups.longhorn.io` is not gated by the toggle; it ships statically in the chart clusterrole and the deploy manifests. The static rules also cover the wider access the `bak` flavor needs: create, list, and delete of `Backup` CRs, and annotation writes on `SnapshotGroup` CRs.

The toggle must never be enabled without the group CRDs installed, because the failure is silent. With the gate on and the CRDs missing, the sidecar's startup waits forever for group informer caches that can never sync, so the workers that serve normal per-volume snapshots never start. Every VolumeSnapshot in the cluster then hangs Pending while the pod reports Running: no crash, no event, only reflector errors in the sidecar log (csi-snapshotter v8.6.0 [`pkg/sidecar-controller/snapshot_controller_base.go`, `Run()`](https://github.com/kubernetes-csi/external-snapshotter/blob/v8.6.0/pkg/sidecar-controller/snapshot_controller_base.go#L173-L188); the sidecar has no CRD preflight). The driver deployer therefore guards the precondition: with the toggle on, it verifies the group CRDs are served at the API version the sidecar consumes (`v1`) and fails fast with an error naming the missing ones. This is the same check the snapshot-controller implements ([`cmd/snapshot-controller/main.go`, `ensureCustomResourceDefinitionsExist`](https://github.com/kubernetes-csi/external-snapshotter/blob/v8.6.0/cmd/snapshot-controller/main.go#L94)).

Why activation is a toggle instead of autodetecting the upstream CRDs. Autodetection would mean: at startup, check whether the group CRDs exist, and enable group support if they do. But that check could run only at startup: the driver deployer picks the sidecar's flags when it starts, and the CSI plugin fixes its capability list when its controller server is constructed. Neither revisits the decision while running. Longhorn is usually installed before the group CRDs, so the startup check would find nothing, and group support would silently stay off until someone restarts both pods. A toggle avoids this: activation is an explicit request with a visible result.

The toggle is deploy-time configuration rather than a Longhorn Setting: changing it takes effect by redeploying the deployer and plugin pods, which a Helm upgrade or reapplying the manifests does and a live setting cannot.

The CRD guard is not autodetection in disguise. It runs only when the toggle is already on, and it can only fail the deploy or let it proceed: it confirms that an explicit request can work, and it never turns group support on by itself. Its answer also cannot go stale, because changing the toggle redeploys the deployer and plugin pods, which re-runs the check.

The toggle is also not temporary. Upstream kept the sidecar feature gate default-off even after the API reached GA, so the toggle remains the activation surface until upstream flips that default.

#### How application consistency composes (#2128)

This section is the initial idea of how #2128 would build on this feature. The final design belongs to #2128's own LEP; what this LEP commits to is only the interface listed at the end of this section.

Member snapshots are taken by separate calls to separate engines, so they are only loosely aligned in time. That is enough once writes are paused:

```
#2128 pre-command: pause the application (writes stop)
        v
this feature: create the group, snapshot all members (bounded by deadlineSeconds)
        v
group Ready - and every member creation time in status is inside the pause window
        v
#2128 post-command: resume the application
```

The deadline bounds how long a slow member can keep the application paused: if the group cannot finish in time, it fails while the pause still holds, instead of succeeding after writes have resumed. The default of 300 seconds is sized for standalone use, where it leaves room to auto-attach detached members. #2128 should not inherit that default; it should set `deadlineSeconds` to match its own pause tolerance, typically tens of seconds.

Interface #2128 depends on:

- Is group snapshot available? The GroupController capability is advertised.
- Snapshot this set and tell me when it is done: create a `SnapshotGroup`, watch `status.phase` and `status.error`.
- Were the snapshots taken inside my pause window? Compare `status.members[].creationTime` against the window, so consistency is verified rather than assumed before the set is labeled application-consistent.

#### Failure handling

| Situation | Result |
|---|---|
| Empty member resolution | Rejected at admission. |
| Standby (DR), restoring, or faulted member volume | Rejected at admission. A volume that reaches such a state after admission is a persistent member error: the group fails at the deadline. |
| A member errors while snapshotting | The error shows on that member's `status.members` entry for as long as it exists on the member, and disappears when the member recovers. A member error never fails the group by itself; if it persists, the deadline fails the group. |
| Member volume at `snapshot-max-count` | That member's snapshot fails per existing behavior, surfaces as a member error, and the group fails at the deadline. |
| Member volume detached | Auto-attached by the existing snapshot controller, exactly as for a single snapshot. |
| Member volume in live migration | The two-engine state is a transient member error; the snapshot completes after migration settles, or the group fails at the deadline. |
| Member volume deleted mid-flight | The member can never become ready; the group fails at the deadline. The Volume ownerReference garbage-collects that member CR, as today. |
| Member name collides with an existing snapshot | The group fails with an explicit collision error instead of adopting the snapshot. |
| Controller restarts partway | Members and their names are in `spec.members`; existing Snapshot CRs are matched by name and adopted only with the group label. Missing ones are created only while InProgress. No member is snapshotted twice. |
| Deadline expires before every member is ready | Phase Failed (terminal); `error` names the unready members and their last errors. Member snapshots already taken are kept as valid per-volume snapshots until the group is deleted. For a CSI-created group that happens immediately: the Create handler deletes the failed group, and the next sidecar retry starts fresh. |
| Member snapshot deleted after Ready | Degraded condition on the group; no replacement snapshot is taken. |
| Group deleted | Finalizer-driven: the controller deletes the group-labeled members through the existing deletion path and releases the finalizer once every member deletion is requested; members whose purge is deferred (for example a volume's latest snapshot) finish under the snapshot controller. CSI delete of an already-missing group returns OK. |
| Group deleted while member volumes are detached | Requesting member deletion needs no engine, so the group finishes Terminating immediately. Each member CR then completes deletion under the snapshot controller, which auto-attaches its volume for the purge (bounded by the member cap); a member that cannot attach (node down) or an enabled `disable-snapshot-purge` setting defers that member's purge, not the group deletion. |
| Group CR restored with a terminal-phase annotation | Takes no snapshots, regardless of member survival: the phase is restored from the annotation. Degraded is set only when the annotated phase is Ready and members are missing or unusable; a restored Failed group stays Failed. A manifest with stamped members but no annotation (an export of a group that never finished) is rejected at admission: re-running it could auto-attach and re-snapshot mid-recovery. A manifest without members is a new request, resolved and run against its own deadline. |
| Toggle enabled while the group CRDs are missing | The driver deployer fails fast naming the missing CRDs; the gated sidecar is never deployed into its silent startup hang, so per-volume snapshots keep working. Installing the CRDs (or disabling the toggle) and re-running the upgrade recovers. |
| Member backup errors during upload (`bak`) | The fan-out RPC (Create or Get) returns Internal naming the failed members; the sidecar retries; deleting the failed Backup CR lets the next retry recreate it, matching per-volume behavior. |
| Backup target unreachable during upload (`bak`) | Uploads stall and the group never reports ready. No deadline applies, because the deadline bounds only taking the snapshots; the behavior matches a stalled per-volume backup. |
| Backup target unreachable during delete (`bak`) | Deletion follows the existing per-volume behavior: with the target unavailable, each member Backup CR is removed without touching the backup store, so the delete completes immediately. The backup data stays on the target and resurfaces as ungrouped Backup CRs once the target recovers. Member backups are still swept before the group CR, so a retried Delete picks up any survivors. |
| Plugin restart between the group snapshot and upload completion (`bak`) | Nothing is lost, because the plugin keeps no state of its own: the handle records the group type, a retried Create or Get creates only the member Backup CRs that are still missing, and readiness is recomputed by listing the group-labeled backups. |
| `GetVolumeGroupSnapshot` on a `bak` group before uploads complete | `ready_to_use` is computed live from the member backups: false while any upload is in flight, true once every member backup completes, even before the fan-out stamps the backups-completed annotation. Once the annotation is written, it stays true. |

### Test plan

- Deployment: the toggle defaults to off; enabling it without the group CRDs fails the deploy while per-volume CSI snapshots keep working; uninstall deletes groups before snapshots and force-clears a stuck finalizer.
- Admission: every rejection listed in the CRD section, plus class validation for `parameters.type`.
- Creation paths: explicit list and selector, through kubectl, the REST API (including the preview action and the snapshot resource's `snapshotGroup` field), and CSI; `bak` groups through a `type: bak` class. Existing per-volume behaviors (filesystem freeze, detached-volume auto-attach) still apply per member.
- Consistency: with writes paused around the group snapshot, simulating the #2128 pause, all members restore to the same application state; or simply check every member creation time in `status.members` is accurate and falls inside the pause window.
- Idempotency: controller restarts, repeated reconciles, and retried CSI RPCs never duplicate a member snapshot or backup.
- Terminal phases: a group failed at the deadline stays Failed; the restore-guard annotation prevents re-snapshotting; deleting a member snapshot after Ready degrades the group and drops `status.readyToUse` to false, while the Kubernetes `VolumeGroupSnapshot` keeps `READYTOUSE=true` because the sidecar stops polling a ready content - a divergence that needs a guarding test.
- Restore: a member PVC restores from its handle, for both types.
- Deletion paths: through each entry point; a member that is its volume's latest snapshot (deferred purge), detached member volumes, a missing group, and `bak` deletion against an unreachable backup target: the CRs delete immediately without remote cleanup, and the remote backups reappear after the target recovers, matching per-volume behavior.

### Upgrade strategy

There is no upgrade risk.

- The new CRD, webhooks, RBAC, and GroupController capability are additive, and the deploy-time toggle defaults to off: an upgrade changes nothing until the toggle is enabled.
- Members are normal `Snapshot`s, so existing tooling, listing, and cleanup keep working.
- Uninstall: the uninstaller deletes `SnapshotGroup` CRs before `Snapshot` CRs, and force-removes a group's finalizer after a grace period so a stuck group can never block CRD removal. The standalone uninstall manifest carries its own RBAC, so it adds the `snapshotgroups` rule; the chart uninstall job reuses the main clusterrole.

## Note

This LEP snapshots a group by fan-out: the controller creates one normal snapshot per member volume, so the snapshots are taken close together but not at the same instant. The alternative is a barrier: freeze I/O on every member engine and snapshot all volumes at one shared instant.

Fan-out was chosen because a barrier costs more than it gives. Its cost is real: freezes must be coordinated across nodes, and a freeze that hangs stalls application I/O, a worse failure than a late snapshot. Its benefit is redundant: workloads that need cross-volume consistency pause the application through #2128, and while writes are stopped, snapshots taken at slightly different times capture the same application state.

If a barrier is ever needed, it should only replace how the snapshots are taken. The `SnapshotGroup` API stays the same, so its consumers, including #2128, are unaffected.
