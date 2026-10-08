# Application-Consistent Snapshot via Snapshot Hooks

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
## Table of Contents

- [Summary](#summary)
  - [Related Issues](#related-issues)
- [Motivation](#motivation)
  - [Goals](#goals)
  - [Non-goals](#non-goals)
- [Proposal](#proposal)
  - [User Stories](#user-stories)
    - [Story 1: one volume](#story-1-one-volume)
    - [Story 2: several volumes, paused in order](#story-2-several-volumes-paused-in-order)
    - [Story 3: a database whose lock ends with the session](#story-3-a-database-whose-lock-ends-with-the-session)
  - [User Experience In Detail](#user-experience-in-detail)
  - [API changes](#api-changes)
    - [New CRD: VolumeHookPolicy](#new-crd-volumehookpolicy)
    - [SnapshotGroup](#snapshotgroup)
    - [CSI](#csi)
    - [Longhorn REST API](#longhorn-rest-api)
    - [RBAC](#rbac)
- [Design](#design)
  - [Implementation Overview](#implementation-overview)
    - [Components](#components)
    - [Design rules](#design-rules)
  - [VolumeHookPolicy (longhorn.io/v1beta2)](#volumehookpolicy-longhorniov1beta2)
    - [Selecting volumes](#selecting-volumes)
    - [Which pods run the command](#which-pods-run-the-command)
    - [Hooks](#hooks)
    - [Container](#container)
    - [Validation](#validation)
    - [Credentials](#credentials)
    - [Rules for hook commands](#rules-for-hook-commands)
    - [A resource outside `longhorn-system`](#a-resource-outside-longhorn-system)
  - [SnapshotGroup (new fields)](#snapshotgroup-new-fields)
  - [Lifecycle of a hooked group](#lifecycle-of-a-hooked-group)
    - [Admission](#admission)
    - [RunningPreHooks: the pause walk](#runningprehooks-the-pause-walk)
    - [InProgress: what `Ready` means](#inprogress-what-ready-means)
    - [The identity gate before `Ready`](#the-identity-gate-before-ready)
    - [Release](#release)
    - [Release retry](#release-retry)
    - [After the release](#after-the-release)
    - [Deleting a hooked group](#deleting-a-hooked-group)
  - [The hook-executor](#the-hook-executor)
    - [Deployment](#deployment)
    - [Work queues](#work-queues)
    - [Restart and leader change](#restart-and-leader-change)
  - [Unhooked snapshots and backups](#unhooked-snapshots-and-backups)
  - [Failure handling](#failure-handling)
  - [Security and RBAC](#security-and-rbac)
    - [Who can define commands](#who-can-define-commands)
    - [Who can trigger a pause](#who-can-trigger-a-pause)
    - [What the API reveals](#what-the-api-reveals)
    - [Where the executor can exec](#where-the-executor-can-exec)
    - [What a compromised executor reaches](#what-a-compromised-executor-reaches)
    - [Manager and executor](#manager-and-executor)
    - [Pod hardening](#pod-hardening)
    - [What the executor records](#what-the-executor-records)
    - [RBAC objects](#rbac-objects)
  - [Longhorn UI](#longhorn-ui)
  - [Design decisions](#design-decisions)
    - [Why the executor is separate from the manager](#why-the-executor-is-separate-from-the-manager)
    - [Per-namespace scoping, not a chart toggle](#per-namespace-scoping-not-a-chart-toggle)
    - [Settings, not executor arguments](#settings-not-executor-arguments)
    - [No phase for the post-commands](#no-phase-for-the-post-commands)
    - [Why a failed pre-command fails the group](#why-a-failed-pre-command-fails-the-group)
    - [No long-lived session in the executor](#no-long-lived-session-in-the-executor)
  - [Settings](#settings)
  - [Observability](#observability)
    - [Events](#events)
    - [Metrics](#metrics)
  - [Upgrade strategy](#upgrade-strategy)
  - [Uninstall](#uninstall)
  - [Test plan](#test-plan)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Summary

Longhorn snapshots are crash-consistent. `freeze-filesystem-for-snapshot` goes one step further and flushes the filesystem, but the application's own buffers stay in memory. `SnapshotGroup` (longhorn/longhorn#13349) snapshots several volumes as one unit, but each member is still cut by its own engine at its own moment. None of these pauses the application, so none gives a multi-volume application one consistent point in time.

This LEP adds application consistency to `SnapshotGroup`. A group created with `hooks: command` runs a user-written pre-command in the application's pods before the member snapshots are taken, usually to stop the application from writing, and a post-command after, to let it write again. Both commands live in a new `VolumeHookPolicy` resource that the user creates in the application's own namespace. The pre-command is a phase of the group itself, `RunningPreHooks`, placed before `InProgress`, so no entry point that creates a group can skip it. The post-command has no phase: a separate executor runs it once the group finishes, whether or not the snapshots succeeded and even if longhorn-manager is down, and records each pod's result in `status.hooks[]`.

A `SnapshotGroup` is application-consistent only when `spec.hooks` is `command` and `status.phase` is `Ready`. If a pre-command fails, a pod restarts or is replaced during the window, or the group runs out of time, the group ends `Failed`. For a single volume, create a group with one member.

### Related Issues

- [#2128](https://github.com/longhorn/longhorn/issues/2128) (this feature)
- [#13349](https://github.com/longhorn/longhorn/issues/13349) (`SnapshotGroup`; this LEP extends it)
- [#13821](https://github.com/longhorn/longhorn/issues/13821) (recurring group snapshots; gets hooks by creating a group)

## Motivation

### Goals

- Application-consistent group snapshots and group backups from every entry point that creates a `SnapshotGroup`.
- One new resource, `VolumeHookPolicy`, that the user creates in their own namespace and that selects only PVCs there, so they never need to touch anything in `longhorn-system`.
- A hooked group either delivers application consistency or fails where the user can see it. Bad configuration is rejected when the group is created; a problem during the run ends the group `Failed`.
- The application is always resumed: when the group finishes, when the deadline passes, and after a Longhorn restart, even while longhorn-manager is down.
- Longhorn can run commands only in namespaces whose admin has allowed it, and nowhere else.

### Non-goals

- Hooks on a per-volume `Snapshot`. Hooks run only through `SnapshotGroup`. A snapshot or backup of a single volume still works as before, even when a policy covers that volume; it just runs no hooks ([Unhooked snapshots and backups](#unhooked-snapshots-and-backups)).
- Selecting pods instead of PVCs. A policy that picks pods by label and follows them to their volumes would leave any other pod on the same volume unpaused, and Longhorn could not tell that from a pod left out on purpose. This LEP goes the other way: the policy selects PVCs, so every pod that mounts one is found, and a pod no hook matches fails the group instead of being skipped. The `podSelector` inside a hook only chooses which commands a found pod runs.
- Built-in commands for specific applications. The user writes the commands.
- An agent mode, where something inside the user's pod pauses the application and Longhorn runs no command at all. It would remove the need for the exec grant, but it is a feature of its own.
- Taking the snapshots anyway when a pre-command fails, as Velero's `onError: Continue` does. A failed pre-command fails the group ([Why a failed pre-command fails the group](#why-a-failed-pre-command-fails-the-group)).
- Changing `freeze-filesystem-for-snapshot`. It still applies to each member volume, with or without hooks.
- Recurring application-consistent runs. They come with #13821, a recurring task that creates a `SnapshotGroup`. Until then, hooked groups are created on demand.
- Post-restore actions. A restore writes the blocks back and the application starts afterward, so there is nothing running to pause.

## Proposal

```
SnapshotGroup CR   hooks: command
        |
        |  admission: every member's PVC must match exactly one
        |             VolumeHookPolicy with a hook for the group's
        |             operation, and must have a running pod; otherwise
        |             the group is rejected and the error names the member
        v
phase: RunningPreHooks
        |          the executor runs each member's pre-command, one member
        |          at a time, in spec.volumes order; once every member is
        |          PreDone it writes status.preHooksDone=true
        |
        |          a pre-command fails, or the deadline
        |          (creationTimestamp + deadlineSeconds) passes -> Failed
        v
phase: InProgress
        |          the existing controller takes the member snapshots
        v
phase: Ready       every member snapshot was created in InProgress,
                   after preHooksDone, and before the deadline
       Failed      the deadline passed first (existing rule)
        |
        v
                   on Ready, Failed, or the deadline, the executor runs
                   each member's post-command, members in reverse order
```

### User Stories

#### Story 1: one volume

A single database on one volume. The user labels its PVC `app-group: demo` and writes one `VolumeHookPolicy` that selects that label, with `pause.sh` as the pre-command and `resume.sh` as the post-command. For an application-consistent snapshot, the user creates a one-member `SnapshotGroup` with `hooks: command`. For a backup, the user creates a `VolumeGroupSnapshot` whose class sets `type: bak` and `hooks: command`. Either way the run pauses writes, takes the snapshot, and resumes writes; a backup then uploads. If the pause fails or the deadline passes, the group ends `Failed` with an event and a metric, and the user creates a new one.

#### Story 2: several volumes, paused in order

A database that runs across several pods, each on its own volume. For example, one pod, the coordinator, takes every query and hands it to the pods that hold the data, the shards. The two kinds are paused with different commands, so the user writes one `VolumeHookPolicy` for each, selected by the label that marks it. The user then creates the `SnapshotGroup` with an explicit `volumes` list, coordinator first, so the coordinator is paused first and released last. This group is created with kubectl, the API, or the UI, not through CSI: a `VolumeGroupSnapshot` selects PVCs by label, and label selection has no order. Its members are sorted by volume name, which is `pvc-<uuid>`, so the order means nothing.

#### Story 3: a database whose lock ends with the session

Some databases hold a lock only as long as the session that took it. MySQL's `FLUSH TABLES WITH READ LOCK` works this way: it takes a global read lock that blocks client writes across every database, and the lock lasts until `UNLOCK TABLES` or until the session that holds it ends. A plain pre-command cannot use it: the command exits, its session closes, and the lock is gone before any snapshot is taken. Longhorn does not hold the session open itself ([No long-lived session in the executor](#no-long-lived-session-in-the-executor)).

MySQL documents the lock as the way to pair with a storage snapshot: ["This operation is a very convenient way to get backups if you have a file system such as Veritas or ZFS that can take snapshots in time. Use `UNLOCK TABLES` to release the lock."](https://dev.mysql.com/doc/refman/8.4/en/flush.html) The lock stops clients, not the storage engine: InnoDB may still write in the background, so a restored instance can run crash recovery on start. That recovery needs the data files and the redo log in one consistent point in time, so they must sit on the same member volume. Two member volumes do not give one point in time: each is cut by its own engine at its own instant, and InnoDB can write between the two.

Without extra tooling, the user falls back to a `hooks: none` group with `freeze-filesystem-for-snapshot`: the snapshots are filesystem-consistent, and the database replays its redo log on restore.

For application consistency, the user adds a small sidecar to the database pod to hold the session. The pre-command tells the sidecar to open a database connection, run `FLUSH TABLES WITH READ LOCK`, and keep the connection open. The post-command tells it to run `UNLOCK TABLES` and close the connection. The sidecar outlives both execs, so the session does too, and the lock holds for the whole window. The sidecar is the user's to ship and test, like every other hook command, and its two scripts follow the same [rules](#rules-for-hook-commands) as any other.

The hook targets the sidecar, not the database container:

```yaml
hooks:
- exec:
    container: mysql-hook              # the sidecar, not the database container
    preCommand:  ['/hooks/pause.sh']
    postCommand: ['/hooks/resume.sh']
```

One risk is specific to this setup. If the sidecar's database connection drops during the pause, MySQL releases the lock on its own, and Longhorn cannot see it: it checks for restarted containers, not for lost connections. The sidecar must exit when the connection drops, so that the loss becomes a container restart, which Longhorn does notice and fails the group on. `resume.sh` then runs in the restarted sidecar and must return cleanly when it finds no session to unlock.

### User Experience In Detail

1. Decide how the policy will find the application's PVCs. Label them, for example `app-group: demo`, or reuse a label they already carry. For a single database with a stable claim name, skip labels and name the PVC directly with `pvcNames: [data-demo-0]`. A policy uses one form or the other, not both.
2. Create one `VolumeHookPolicy` per set of PVCs, in the application's namespace:

```yaml
apiVersion: longhorn.io/v1beta2
kind: VolumeHookPolicy
metadata:
  name: demo
  namespace: default                   # the application's namespace
spec:
  pvcSelector:
    matchLabels: {app-group: demo}     # PVCs in this namespace with this label
  hooks:                               # commands to run in every running pod that uses a selected PVC
  - exec:                              # run a command inside the pod
      container: app                   # which container runs the commands; required if the pod has more than one
      preCommand:  ['sh', '-c', 'pause.sh -p "$DB_PASS"']
      postCommand: ['sh', '-c', 'resume.sh -p "$DB_PASS"']
```

   One hook, as above, is the common case: it runs the same two commands in every pod that mounts a selected PVC, for snapshots and backups alike. A policy needs more than one hook when pods that share a volume need different commands, or when a backup needs different commands than a snapshot. Each hook then gets a `name`, a `podSelector` that picks its pods, and, if it should run for only one operation, an `operations` list:

```yaml
  hooks:
  - name: demo
    exec:
      podSelector:
        matchLabels: {app: demo}
      container: app
      preCommand:  ['sh', '-c', 'pause.sh -p "$DB_PASS"']
      postCommand: ['sh', '-c', 'resume.sh -p "$DB_PASS"']
  - name: reporting-backup
    operations: [backup]               # runs only for a backup
    exec:
      podSelector:
        matchLabels: {app: reporting}
      container: app
      preCommand:  ['pause-for-backup.sh']
      postCommand: ['resume.sh']
  - name: reporting-snapshot
    operations: [snapshot]             # runs only for a snapshot
    exec:
      podSelector:
        matchLabels: {app: reporting}
      container: app
      preCommand:  ['pause-for-snapshot.sh']
      postCommand: ['resume.sh']
```

   Every pod must match exactly one hook for the operation being run; the rules are in [Hooks](#hooks).

   The `demo` commands go through `sh -c` so that `$DB_PASS` expands inside the pod, from the container's environment. The policy carries only the variable's name, and that is all Longhorn, the API server, and anyone who can read the policy ever see.

3. Allow Longhorn to run commands in the namespace. The namespace admin applies this RoleBinding next to the policy:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: longhorn-hook-executor
  namespace: default                   # the application's namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: longhorn-hook-executor
subjects:
- kind: ServiceAccount
  name: longhorn-hook-executor
  namespace: longhorn-system
```

   Without it, creating a hooked group that includes a volume from this namespace fails, and the error message carries this manifest to paste. Applying it needs the namespace `admin` role or higher; `edit` cannot create RoleBindings.

4. Create a `SnapshotGroup` with `hooks: command`. With kubectl:

```yaml
apiVersion: longhorn.io/v1beta2
kind: SnapshotGroup
metadata:
  name: demo
  namespace: longhorn-system
spec:
  volumes: [pvc-1f3a..., pvc-8c2e..., pvc-d904...]   # Longhorn volume names; list order = pause order
  hooks: command                       # none (default) | command
  hookOperation: snapshot              # snapshot (default) | backup (set by CSI for a bak class)
  deadlineSeconds: 60                  # bounds the pause and the snapshots together
```

   Through CSI, set `hooks: command` as a parameter on a `VolumeGroupSnapshotClass`. A `VolumeGroupSnapshot` that uses the class creates the `SnapshotGroup` with the same fields set:

```yaml
apiVersion: groupsnapshot.storage.k8s.io/v1
kind: VolumeGroupSnapshotClass
metadata:
  name: longhorn-group-bak-hooked
driver: driver.longhorn.io
deletionPolicy: Delete
parameters:
  type: bak                            # snap | bak; bak pauses for backup, snap for snapshot
  hooks: command                       # none (default) | command
  deadlineSeconds: "120"               # optional; 10 to 3600; default 60 with hooks, 300 without
```

   A CSI group selects PVCs by label, so its members pause in no particular order. When order matters, list the volumes explicitly, as in the kubectl manifest.

5. Watch the group. `kubectl -n longhorn-system get snapshotgroups` shows the phase, the hooks setting, and the hook progress. `kubectl get -o yaml` shows, per member, the policy, the pods, the phase, the exit code, and the reason, plus when the pre- and post-hooks finished.

The UI covers the same steps in the `Create Snapshot Group` dialog:

1. Select the member volumes and set `Hooks` to `command`.
2. The dialog previews the group. It lists the members in pause order and flags any member that has no policy and any namespace where Longhorn has not been granted exec access.
3. For each flagged namespace, a `Fix` panel generates the missing RoleBinding and `VolumeHookPolicy` as `kubectl apply -f -` blocks, the RoleBinding first. The UI does not apply them; the namespace admin applies them with kubectl.
4. Click `Re-check`. The `OK` button becomes available once every member passes.
5. After the group is created, the group list shows its phase and hook progress, and the group detail page shows the timing and the per-member hook status.

The screens are sketched in [Longhorn UI](#longhorn-ui).

### API changes

#### New CRD: VolumeHookPolicy

[`VolumeHookPolicy`](#volumehookpolicy-longhorniov1beta2) is a namespaced resource in `longhorn.io/v1beta2`, short name `lhvhp`. It lives in the application's namespace, next to the PVCs it selects.

#### SnapshotGroup

`SnapshotGroup` gains the fields below. The spec stays immutable after creation. A group that does not set the new fields behaves as before: `hooks` defaults to `none` and `deadlineSeconds` to 300.

```yaml
apiVersion: longhorn.io/v1beta2
kind: SnapshotGroup
spec:
  volumes: [pvc-a, pvc-b]           # list order is pause order
  hooks: command                    # none (default) | command
  hookOperation: snapshot           # snapshot (default) | backup; set by CSI from the class type
  deadlineSeconds: 60               # 10 to 3600; default 60 with hooks, 300 without; covers the pause and the snapshots
  members:
  - volumeName: pvc-a
    snapshotName: demo-5f2c9a1b
    hookPolicyRef:                  # the policy that matched the member, resolved at admission
      namespace: default            # the PVC's namespace, kept so the policy is still found after the PVC is deleted
      name: demo
      generation: 3                 # the policy's metadata.generation at admission
status:
  phase: Ready                      # gains RunningPreHooks, before InProgress
  hookProgress: post done           # one-line summary of status.hooks[] for kubectl get
  preHooksDone: true                # every member's pre-command finished; the controller moves the group to InProgress
  hooksStartedAt: ...               # the first pre-command started
  preHooksDoneAt: ...               # the last pre-command finished; used for the timing breakdown
  postHooksDoneAt: ...              # every recorded pod is PostDone or PostFailed; Longhorn's part of the resume is over
  error: ""                         # why a hooked group ended Failed
  hooks:                            # one entry per member, keyed by snapshotName
  - snapshotName: demo-5f2c9a1b
    phase: PostDone                 # Pending | PreRunning | PreDone | PreFailed | PostRunning | PostDone | PostFailed
    reason: ""                      # set only when the member failed before any command ran
    pvcRef: {namespace: default, name: demo}   # the member's PVC, recorded right before the first pre-command
    pods:                           # every running pod that mounted the member at pause time
    - namespace: default
      name: demo-1
      uid: ...
      containerIDs: [...]           # every container in the pod at pause time, not only the exec target
      hookName: demo                # the policy hook that ran in this pod
      phase: PostDone
      exitCode: 0
      reason: ""
      releaseAttempts: 1            # times the post-command ran in this pod
```

[SnapshotGroup (new fields)](#snapshotgroup-new-fields) describes each field in full.

#### CSI

Two new `VolumeGroupSnapshotClass` parameters, `hooks` and `deadlineSeconds`, set on the class as shown in [User Experience](#user-experience-in-detail). They map onto `spec.hooks` and `spec.deadlineSeconds`. A bad value for either fails the create with `InvalidArgument`, so the class author sees the mistake once, instead of a group that admission rejects on every retry.

- There is no `hookOperation` parameter. It follows from `type`: `bak` pauses for `backup`, `snap` for `snapshot`. A class cannot ask for a backup while pausing for a snapshot.
- `deadlineSeconds` is optional. When it is unset, the mutating webhook picks the default, which depends on `hooks`. When it is set, the CSI plugin checks the 10 to 3600 range itself. A class that pauses many members needs it, because a CSI group has no other place to set a deadline.
- A CSI retry can arrive after the group already exists. The retry then checks that the existing group was created with the same `hooks` value as the class, as it already does for `type`, and fails if not. Without this, a class changed from `none` to `command` while a retry is in flight would hand back a group that ran without hooks.
- `hooks` and `deadlineSeconds` join `type` and `backupMode` as reserved class parameters: the plugin consumes them and does not copy them onto the member snapshots as engine labels. A CSI plugin from before this release does not know the two keys and forwards them as labels, so the validating webhook rejects a CSI-created group whose `spec.labels` carries either key; a group not created by the plugin may still use them as labels, and a restored group is not checked ([Upgrade strategy](#upgrade-strategy)).

#### Longhorn REST API

One new read-only resource, `volumeHookPolicy`, and the `snapshotGroup` changes below. The policy resource exists so the UI can show which policies exist and which one a group member ran against ([Longhorn UI](#longhorn-ui)). It has no write operations. The Longhorn API has no per-user authorization, and once a namespace has bound the executor's role, writing a policy there is as good as running a command in its pods ([Who can define commands](#who-can-define-commands)). Writes therefore stay behind the namespace's own RBAC, with kubectl. No response from this resource carries command text.

| Method | Path | What changes |
|---|---|---|
| `GET` | `/v1/volumehookpolicies`, `/v1/volumehookpolicies?namespace=<ns>`, `/v1/volumehookpolicies/{namespace}/{name}` | New. Returns each policy's PVC selection and, for every hook, its name, operations, pod selector, and container. Commands are left out. |
| `GET` | `/v1/ws/volumehookpolicies`, `/v1/ws/{period}/volumehookpolicies` | New. The same collection as a stream, always across every namespace. |
| `POST` | `/v1/snapshotgroups` | The create body accepts `hooks` and `hookOperation`. |
| `GET` | `/v1/snapshotgroups`, `/v1/snapshotgroups/{name}`, `/v1/ws/{period}/snapshotgroups` | The resource gains the new status fields and `members[].hookPolicyRef`. `status.hooks[]` is returned as `hookStatuses[]`, since the REST object is flat and `hooks` already names the mode. |
| `POST` | `/v1/snapshotgroups?action=preview` | The request accepts `hooks` and `hookOperation`. With `hooks: command`, the response shows what admission would decide for each member and each namespace, and lists the policies that already exist in each member namespace. |

With `hooks: command`, the manager builds the preview by finding each member's policy, reading the member's pods from the API server, and checking the executor's permissions in each member namespace. Unlike admission, it reports every failure it finds rather than stopping at the first, so the Fix panel can show a missing RoleBinding and a missing policy together. Members come back in pause order, each with the policy that would apply and its running pods. For every pod, the response includes its labels, the containers a hook may name, and the hook and container that would be chosen for it. That choice is a prediction from the pod's current labels; the executor matches again against live pods when the run starts.

The response separates three kinds of finding, and the UI treats each differently ([Longhorn UI](#longhorn-ui)).

- Failures that block the create. A member's `validationFailure` carries the message admission would reject it with, and `validationFailureReason` names the check that failed. A namespace's `accessFailure` means the executor cannot exec there; it comes with the RoleBinding to apply in `accessFailureManifest`, the same text admission puts in its rejection. When the permission check itself could not complete, `accessFailure` is set without a manifest, and the right move is to run the preview again rather than paste anything.
- Warnings that do not block. `warnings[]` lists conditions admission accepts but the user should see first: a pod that no hook matches (`matchFailure`; the run would fail it with `HookNotMatched`), a pod that appears under more than one member, a pod a previous group left `PostFailed`, and `hookOperation: backup` on a group that only takes snapshots ([SnapshotGroup](#snapshotgroup)).
- A pod the manager could not read while building the preview. Its `readFailure` explains why. It does not fail the member, because admission does not read pods either.

Two more fields sit at the group level. `error` is #13349's field for refusing the whole group; it gains the manager-rollout refusal, which names no member and can clear without any change to the inputs. `namespaces[]` lists the `VolumeHookPolicy` objects already in each member namespace, so the UI can offer an existing policy to a member that has none.

#### RBAC

The user's RoleBinding refers to two names: ClusterRole `longhorn-hook-executor` and ServiceAccount `longhorn-hook-executor` in `longhorn-system`. The full list of RBAC objects Longhorn installs is in [RBAC objects](#rbac-objects).

## Design

### Implementation Overview

#### Components

- **VolumeHookPolicy** (new CRD). Written by the application's namespace admin. It names the PVCs to cover and the commands to run in the pods that mount them. See [VolumeHookPolicy](#volumehookpolicy-longhorniov1beta2).
- **SnapshotGroup**. Gains a hooks mode and operation in `spec`, a policy reference on each member, and a hook record in `status`. See [SnapshotGroup (new fields)](#snapshotgroup-new-fields).
- **longhorn-manager**. Admits the group and drives `status.phase`. Before it writes `Ready`, it checks that the pods the pre-commands ran in are still the pods running. It never runs a command. See [Lifecycle of a hooked group](#lifecycle-of-a-hooked-group).
- **hook-executor** (new Deployment, own ServiceAccount). Runs the pre- and post-commands and owns the hook record in `status`. It is the only component that can exec into a pod. See [The hook-executor](#the-hook-executor).
- **Longhorn UI**. Previews the policy match before a group is created, shows the hook record afterward, and lists policies read-only. See [Longhorn UI](#longhorn-ui).

#### Design rules

1. Before a pre-command runs in a pod, the executor records that pod in `status.hooks[].pods`. The release then runs the post-command in every recorded pod, including those where the pre-command failed or never returned, until each is `PostDone` or `PostFailed` ([Release](#release)).
2. Longhorn can stop waiting for a command, but it cannot stop the command. A command that outlives its time limit, or is still running when the group is released, keeps running in the pod until it exits on its own. It may therefore finish after the group has failed or after the post-command has run, and the user's commands must tolerate that ([Rules for hook commands](#rules-for-hook-commands)).
3. The release deadline is a fixed point in time: the group's creation time plus `deadlineSeconds`. It is derived from those two fields, never counted down in memory, so a restart or leader change cannot move it ([Release](#release)).
4. When the executor cannot tell whether a pre-command ran, it fails the member rather than retry ([RunningPreHooks: the pause walk](#runningprehooks-the-pause-walk)). The post-command is the opposite: it runs again in every recorded pod until a result is on record, because leaving an application paused is worse than resuming it twice ([Release retry](#release-retry)).
5. The pods are listed twice, once to pause them and once just before `Ready`, both times live from the API server. Any difference between the two lists is therefore a real pod change ([The identity gate before `Ready`](#the-identity-gate-before-ready)).
6. Longhorn never records the command text or its output: not in status, not in logs, not in events ([What the executor records](#what-the-executor-records)).
7. The executor records a pod `PostRunning` before its post-command runs, and the controller refuses `Ready` once any recorded pod has left `PreRunning` or `PreDone`. Both writes land on the same object, so the API server orders them without relying on clocks; a snapshot cut after the application resumed is never reported application-consistent ([The identity gate before `Ready`](#the-identity-gate-before-ready)).

### VolumeHookPolicy (longhorn.io/v1beta2)

A policy answers two questions: which PVCs, and what to run in the pods that mount them.

#### Selecting volumes

`pvcSelector` selects PVCs in the policy's namespace by label. `pvcNames` lists them by name, for PVCs that have no usable label. Exactly one of the two must be set.

The policy selects PVCs rather than Longhorn volumes because PVCs are what the user owns and can see, and because they are namespaced, so a policy can reach only its own namespace.

#### Which pods run the command

The policy does not name pods. Every running pod that mounts a selected PVC runs the command. The pods are found when the member is paused ([the pause walk](#runningprehooks-the-pause-walk)).

#### Hooks

`hooks` is a list of entries with this shape:

```yaml
- name: demo
  operations: [snapshot, backup]
  exec:
    podSelector: {matchLabels: {app: demo}}
    container: app
    preCommand:  [...]
    postCommand: [...]
```

It is a list because pods that share a volume are not always the same application, and each may need its own commands. `exec` is nested so another hook kind can be added beside it later.

For each pod, exactly one hook must match: its `operations` include the group's `hookOperation`, and its `podSelector` matches the pod's labels. If none or several match, the member fails with `HookNotMatched`. This is checked at run time against the live pods, not when the policy is written.

`operations` is `snapshot`, `backup`, or both; unset means every operation. `podSelector` is required on every hook when there is more than one; a single hook may omit it and then runs in every pod. `name` is likewise required for more than one hook and defaults to `default` for a single one. Longhorn records which hook ran in each pod by its `name`.

#### Container

`container` names the container the commands run in. It can be any container in the pod's `spec.containers`, or any init container with `restartPolicy: Always`. A container that is restarting still counts.

It may be left out only when every pod the hook matches has exactly one such container. A missing `container` is accepted when the policy is written; at run time, a matched pod with more than one fails the member with `HookNotMatched`.

#### Validation

A policy is checked at three points. Each point checks only what it can see.

The policy webhook checks the policy by itself when it is written: the rules above for `pvcSelector` and `pvcNames`, hook names, `operations`, `podSelector`, and commands. The CRD schema also requires exactly one of `pvcSelector` and `pvcNames`. The webhook rejects a policy in the Longhorn namespace too, since hooks never run there.

Group admission checks the policy against the cluster when a hooked group is created ([Admission](#admission)). Whether a policy applies is decided there, so the policy itself carries no status.

The executor checks the running pods when it claims a member: every pod must match exactly one hook, and that hook must name a `container` if the pod has more than one ([the pause walk](#runningprehooks-the-pause-walk), check 4). Admission cannot do this because it does not see pod labels.

#### Credentials

A policy must not carry credentials. Longhorn cannot enforce this: a validator cannot tell a password from any other word in a command. The `VolumeHookPolicy` documentation has to state the rule instead.

A password written in a policy is exposed in two places beyond the policy itself. The API audit log records the exec request's URL, and the command is part of that URL, so the password is logged even when the log keeps only request metadata. And the built-in `view` role, which this LEP lets read policies, cannot read Secrets, so the password is readable by exactly the people a Secret would hide it from.

Having Longhorn read a Secret and hand it to the command was considered and ruled out. The exec API gives Longhorn no way to set environment variables in the pod, so the only way to pass the Secret's value would be to write it into the command itself, and the audit log would record it there.

#### Rules for hook commands

Longhorn runs the commands but cannot verify what they do. It checks only that the command exited 0 and that the pods did not change afterward; whether the application actually stopped writing is up to the command. The rules below are the user's responsibility, and the `VolumeHookPolicy` documentation should state them.

- **The pause must outlive the pre-command.** The command runs as a process in the pod. If the pause ends when that process ends, as a MySQL session lock does, it is gone before the first snapshot is taken. See [Story 3](#story-3-a-database-whose-lock-ends-with-the-session).
- **Both commands must be safe to run more than once.** The same command can reach the same pod more than once: a pod that mounts several member volumes runs it once per member, and a post-command runs again in any pod whose result is not on record, after a failed attempt or an executor restart.
- **The post-command must work even if the pre-command never finished.** Longhorn gives up on a slow pre-command but cannot kill it ([design rule 2](#design-rules)), so the pre-command may still be running, or may finish, after the post-command has run. The two scripts need some way to tell each other what happened, for example a marker file that the post-command leaves behind and the pre-command checks before it commits the pause.
- **Both commands must finish their work before they exit.** Exit 0 tells Longhorn the pause is in place. A command that starts the pause in the background and exits right away returns before the application is actually paused, so the snapshots begin too early.
- **A restart undoes the pause.** A pause lives in a running process. If that container or pod restarts during the window, the restarted process is not paused and writes as usual. Longhorn notices the restart and fails the group.

#### A resource outside `longhorn-system`

Every other Longhorn resource lives in `longhorn-system`. A policy lives in the application's namespace, so the manager must find policies wherever they are. It watches them cluster-wide, which is why its ClusterRole gains read access on `volumehookpolicies` ([RBAC objects](#rbac-objects)). Admission, the preview, and the `volumeHookPolicy` REST resource all read from that watch.

### SnapshotGroup (new fields)

Each new field exists for one reason. They are listed by where they live: the spec, the group-level status, and then the per-member and per-pod records in `status.hooks[]`.

**Spec.**

- `spec.hooks: command` tells Longhorn to run the pre- and post-commands from each member's `VolumeHookPolicy`. Either the hooks run or the group fails, so `Ready` means application-consistent. The field is an enum so that another mode can be added later.
- `spec.hookOperation` picks which hooks run. A hook runs only if its `operations` list includes this value or is omitted, so a policy can give a backup different commands than a snapshot. It is valid only with `hooks: command` and defaults to `snapshot`. Group backups exist only through CSI (#13349 has no backup group object), so a group created directly, with kubectl, the REST API, or the UI, should leave it at `snapshot`. Setting `backup` there is accepted, and the validating webhook returns an admission warning: the group only takes snapshots, so the backup hooks run around snapshots that nothing backs up unless the user does so by hand. It is not rejected, because a user may want exactly that.
- `spec.deadlineSeconds` has to grow with the member count. Members are paused one at a time, then every member snapshot is created together in `InProgress`, so a run needs roughly the sum of the pre-command times plus the longest single snapshot time, and a group with many members (the cap is 64) should set the deadline explicitly rather than rely on the default. Two things make the run longer than that estimate. Hooks run once per member volume, not once per pod, so a pod that mounts two member volumes runs its pre-command twice. And a pod that is shutting down when its turn comes is waited for rather than skipped ([the pause walk](#runningprehooks-the-pause-walk)), so a rolling restart that overlaps the run can add a full termination grace period.
- `spec.members[].hookPolicyRef` is resolved once, at admission, and never again, so a restored group keeps the policies it was created with. If the policy is edited afterward, its generation no longer matches and the member fails with `PolicyChanged` rather than run a command the group was not created with. A member with no reference at all was admitted by a webhook from before this release; it fails with `PolicyNotFound` and a message that says so. In both cases the fix is to recreate the group.
- Every member snapshot of a hooked group is created with the label `longhorn.io/snapshot-group-hooked: "true"` on its `Snapshot` CR, next to the group label #13349 already sets. It marks a snapshot taken under the pause. A snapshot without it inside a hooked group was taken by a manager that did not know hooks ([Upgrade strategy](#upgrade-strategy)). The marker lives and dies with the group label: a system restore keeps both, and a `Snapshot` CR the engine controller rebuilds loses both, so a member that has lost the marker has already stopped counting as the group's own.

**Status, group level.**

- `status.preHooksDone` is the one bit the controller waits on. The executor sets it when every member is `PreDone`, and the controller then moves the group from `RunningPreHooks` to `InProgress`.
- `status.hooksStartedAt` is when the executor began the pre-commands. It can be well after the group's creation, because the deadline clock starts at creation and a group may wait in the executor's queue ([Work queues](#work-queues)). `HookDeadlineNearlyExceeded` uses it to separate queue wait from hook time.
- `status.preHooksDoneAt` is when the last pre-command finished. It is recorded for the timing breakdown in `HookDeadlineNearlyExceeded` and the UI; the phase order, not this timestamp, guarantees that snapshots come after the pause ([InProgress](#inprogress-what-ready-means)).
- `status.postHooksDoneAt` marks that Longhorn's release duty is over, whether every pod was released or some ended `PostFailed`.
- `status.hookProgress` exists because `kubectl get` prints a field as it is and cannot sum the records in `status.hooks[]`. The string is that sum, so a paused application is visible at a glance. It is empty for `hooks: none`; otherwise it is exactly one of `pre <done>/<members>`, `pre done`, `pre failed`, `post <done>/<pods>`, `post done`, or `post failed <n>/<pods>`. The `pre` values count members and the `post` values count pods, because only recorded pods are released. The string reports hook progress, not the group's result; `status.phase` says whether the group succeeded.
- `status.error` says what failed and where. A member is named by its `snapshotName` followed by its policy as `namespace/name`, and a pod is named when one is involved, for example `pre-hook failed on member demo-5f2c9a1b (default/demo) in pod default/demo-1: ExitNonZero (exit 1)`. When the failure happened before any command ran, the message ends with the reason alone; the detail behind it, such as which group holds the volume for `VolumeConflict`, is in the `PreHookFailed` event. Four failures are not hook failures and set no `reason`. The deadline passed before the walk reached a member: `(queued-past-deadline)`. The identity gate found a pod change: `(pod-changed)`. The release began before the group could be marked `Ready`: `(released-before-ready)`. An old manager moved the group past the pre-hooks during an upgrade: `(pre-hooks-skipped)`.

**Status, per member and per pod.**

- The member `phase` is the summary. Each pod keeps its own, because one pod of a member can be paused while another has failed, and the release must know each pod's state.
- `pvcRef` is recorded because the volume's `kubernetesStatus` also holds the PVC's name and namespace, but Longhorn clears them when the PVC is deleted, and that can happen while the group is running. The release and the identity gate both list pods by PVC and both can run after the PVC is gone, so they read `pvcRef`, never the volume.
- `hookName` lets the release look the hook up by name instead of matching the pod's labels again, so the post-command is the pair of the pre-command that ran ([Release](#release), step 3).
- `containerIDs` covers every container in the pod, including init and ephemeral containers, not only the one the command ran in, so a restart of any of them fails the group ([The identity gate before `Ready`](#the-identity-gate-before-ready)).
- `reason` is one short name from a fixed list. The same name appears in the `PreHookFailed` or `PostHookFailed` event and in the `reason` label of the command-failure metric, and a pre-hook failure carries it into `status.error`, so one name finds a failure everywhere.

| Reason | Level | Meaning |
|---|---|---|
| `VolumeConflict`, `PolicyNotFound`, `PolicyChanged`, `PodNotFound`, `HookNotMatched` | member | A check failed before any command ran. The member is `PreFailed` with no pod entries. `PodNotFound` here means no running pod mounts the member, or the member volume or its PVC is gone. |
| `ExitNonZero`, `Timeout` | pod | The outcome of the command itself. |
| `ExecFailed` | pod | The command never ran: the pod could not be read right before the exec, or the exec failed with something other than an exit code or a timeout. |
| `Interrupted` | pod | The executor stopped while the pre-command was running (a crash, a leader change, a cancelled reconcile), so its outcome was never recorded. |
| `PodNotFound` | pod | At release, the pod is gone. Nothing to release; the pod ends `PostDone`. |
| `PolicyChanged` | pod | At release, the policy's generation no longer matches the recorded one. The pod is released with the policy's current post-command and ends `PostDone`. |
| `PolicyNotFound`, `HookNotFound` | pod | At release, no post-command could be found, so none ran. The pod ends `PostFailed`. |

**Two writers share `status`.** The executor owns `status.hooks[]`, `hookProgress`, `preHooksDone`, `hooksStartedAt`, `preHooksDoneAt`, and `postHooksDoneAt`; the controller owns everything else. Each writer changes only its own fields and never writes the other's from a stale read: if the executor records a pod between the controller's read and its write, that pod would be erased from the record, never released, and the deletion hold would end while it is still paused. A write from a stale read is rejected by the API server, so the writer re-reads before deciding again.

### Lifecycle of a hooked group

A hooked group adds one phase, `RunningPreHooks`, before `InProgress`:

```
""               first reconcile, hooks: command        -> RunningPreHooks
""               first reconcile, hooks: none           -> InProgress (unchanged)
RunningPreHooks  status.preHooksDone                    -> InProgress
RunningPreHooks  a member PreFailed, or the deadline    -> Failed
InProgress       existing rules                         -> Ready | Failed
```

`Ready` and `Failed` mean what they did before, so everything #13349 built on them still holds. The controller moves the phase on what the executor writes to status; it runs nothing itself.

The post-commands have no phase of their own. They run once the group is `Ready` or `Failed`, is deleted, or passes its deadline, and each pod's result is recorded in `status.hooks[]` ([Release](#release), [No phase for the post-commands](#no-phase-for-the-post-commands)).

#### Admission

For `hooks: command`, admission adds the checks below. A rejection names the member, policy, pod, or namespace that failed.

1. **Each volume is listed once.** `volumes` must not name the same volume twice. A pod that mounts two member volumes is allowed (see [Rules for hook commands](#rules-for-hook-commands)).

2. **Each member has exactly one policy for the operation.** The member's PVC must match exactly one `VolumeHookPolicy` in its namespace, and that policy must have a hook whose `operations` cover the group's `hookOperation`. A volume with no PVC cannot be a member. A PVC in the Longhorn namespace is rejected as well ([What a compromised executor reaches](#what-a-compromised-executor-reaches)). This check runs in the mutating webhook, because the policy it finds is written into `members[].hookPolicyRef`; every other check runs in the validating webhook.

3. **The executor's grant is in place.** For each member PVC's namespace, admission checks with the API server that the executor's ServiceAccount has every permission of the `longhorn-hook-executor` ClusterRole (see [RBAC objects](#rbac-objects)). If any permission is missing, or the check itself fails, the group is rejected; for a missing permission the error message includes the RoleBinding to apply.

4. **Each member has a running pod.** At least one pod in the member's `workloadsStatus` has `podStatus: Running`. This is a fast check against the volume's cached workload status; the pause walk lists pods live and is the one that counts.

5. **No member is held by another hooked group.** A hooked group holds each of its volumes from creation until it is finished and every pod it recorded in `status.hooks[].pods` is `PostDone` or `PostFailed`. A group that is still `RunningPreHooks` or `InProgress` holds its volumes even when it has recorded no pod yet, so a group waiting in the executor's queue cannot be overtaken. While the hold lasts, no other hooked group may include that volume (except a `hooks: none` group, because it runs no commands). Because `PostFailed` also ends the hold, a new hooked group can be created while a pod from the earlier group is still paused by a post-command that never succeeded; admission and the preview warn that the pod ended `PostFailed` and may still be paused.

6. **The longhorn-manager rollout is complete.** Every manager pod must run the same image as the manager DaemonSet. A pod that is terminating still counts, because it can still claim a group until it exits; only pods that have exited are skipped. An old manager that claims a hooked group does not know `spec.hooks` and would report `Ready` without a pause. `hooks: none` groups are unaffected. The preview runs the same check and reports it as the group-level `error`. This check is the upgrade gate: it runs in the same new webhook that resolves `members[].hookPolicyRef` (check 2), so a group that can pause anything was admitted only after every old manager was gone ([Upgrade strategy](#upgrade-strategy)).

The validating webhook also rejects `hookOperation` on a `hooks: none` group, and rejects a CSI-created group whose `spec.labels` carries `hooks` or `deadlineSeconds` ([CSI](#csi)). The mutating webhook also fills the defaults listed under [SnapshotGroup](#snapshotgroup).

**Restored groups.** A group re-applied from an export or a system restore, carrying the terminal-phase annotation from #13349, arrives already finished. Admission skips the checks that look at the cluster (2 to 6) and the reserved-label check, since the group's labels were valid when it was first created, and keeps the checks on the group's own fields; `members[].hookPolicyRef` arrives already resolved and is kept as is. The executor runs nothing for it: it never paused anything in this cluster.

#### RunningPreHooks: the pause walk

The executor pauses members one at a time, in `spec.volumes` order. A group created with `volumeSelector` has no list, so its members are walked in volume-name order, which is repeatable but means nothing. Each member goes through three steps:

```
for each member, in pause order:

  1. check        can this member still be paused?  no -> PreFailed + reason, stop
        |
  2. claim        write PreRunning + pvcRef + pods in one update
        |         already decided by another writer? -> stop, write nothing
        |
  3. pre-command  run in every recorded pod, in parallel
        |         any pod failed? -> PreFailed, stop
        |
     PreDone, next member

all members PreDone -> preHooksDone=true, preHooksDoneAt, PreHooksSucceeded
```

**The check** confirms, in order, that the member can still be paused. A failed check writes the member `PreFailed` with the reason and records no pods.

1. No other hooked group holds the volume (`VolumeConflict`). "Held" is defined in [Admission](#admission) check 5. If two groups collide, the newer one fails: the one created later, or, if they were created at the same time, the one with the greater name.
2. The volume still exists and still has a bound PVC (`PodNotFound`, since a volume with no PVC has no pods). The PVC is recorded as the member's `pvcRef`. The policy recorded at admission still exists (`PolicyNotFound`) and has not been edited since (`PolicyChanged`). A PVC in the Longhorn namespace is treated as having no policy ([What a compromised executor reaches](#what-a-compromised-executor-reaches)).
3. At least one running pod mounts the PVC (`PodNotFound`). Pods are listed live from the API server ([design rule 5](#design-rules)). A member with no running pod fails rather than passes, because an application that starts during the window would write unpaused. A pod that is shutting down cannot safely run a command, so the executor waits, retrying until the pod is gone or the deadline passes.
4. Every listed pod matches exactly one hook for the group's `hookOperation`, and that hook names a `container` when the pod has more than one (`HookNotMatched`).

An API error during the check is not a failure. The member is retried with backoff, and the deadline rule fails the group if the error outlasts it.

**The claim** is a single status update. It writes the member `PreRunning` and, in the same update, its `pvcRef` and every pod the executor is about to pause. This puts the pods on record before any command runs, so the release always knows which pods to resume.

The claim refuses when the group's status says the pause is over: the group is `Ready` or `Failed`, has a `deletionTimestamp`, is past its deadline, or has any recorded pod at `PostRunning` or later. It also refuses when another writer already decided the member, because the controller failed the group or a second executor claimed it during a leader handover. In every case the executor stops the walk and writes nothing; the next reconcile picks up from the recorded phases. Because the claim is a write that fails on a stale read, a release that begins between the check and the claim is seen.

**The pre-command** runs in every recorded pod in parallel, bounded by the time left to the deadline. Right before each exec the pod's UID is checked against the record, so a command never lands in a replacement pod. The member becomes `PreDone` when every pod succeeds, or `PreFailed` on the first failure. A `PreFailed` member stops the walk. The controller then moves the group to `Failed`, and that is what starts the [release](#release).

Two cases sit outside the steps. If the deadline passes before the walk reaches a member, the group fails and `status.error` is marked `(queued-past-deadline)`. After a restart, the walk resumes from the recorded phases: a member already `PreDone` is skipped, `PreFailed` stops the walk, and a member found `PreRunning` fails `Interrupted` and stops the walk, since its pre-command's result was never recorded.

#### InProgress: what `Ready` means

`Ready` on a hooked group means every member snapshot was taken after the last pre-command finished and before the deadline. Longhorn checks that window; it cannot check what the commands did inside the pods. The upper bound is the existing member-creation check against the deadline. The lower bound needs no timestamp: the controller creates member snapshots only in `InProgress`, and the group enters `InProgress` only after `preHooksDone` is set, so every member snapshot is created after the last pre-command by construction. The member-creation check keeps `creationTimestamp` as its lower bound, as it does for `hooks: none`. `preHooksDoneAt` is not used as a bound: the executor stamps it from its own node's clock, and a few seconds of skew would reject a snapshot that was in fact taken under the pause.

#### The identity gate before `Ready`

Just before the controller writes `Ready`, it checks that the pods the pre-commands ran in are still the pods running. For every member, the pods recorded in `status.hooks[].pods` at pause time must match the live set: same pods, same UIDs, same container IDs. Any difference means a process the pre-command never reached was running during the window, and the group fails, with `(pod-changed)` in `status.error` naming the member and pod.

The check covers every container in the pod, not only the one the command ran in, because the pause and the writes can live in different containers ([Story 3](#story-3-a-database-whose-lock-ends-with-the-session)). This includes a `kubectl debug` session started mid-window.

**The release gate.** The same write checks that no recorded pod has left `PreRunning` or `PreDone`. If the executor has already begun releasing, because the deadline passed on its clock or the group was deleted, the group fails with `(released-before-ready)` in `status.error`. The two components share no clock, so this is the only check that proves the snapshots were cut while the application was still paused ([design rule 7](#design-rules)).

**What the gate can get wrong.** It can be wrong in both directions.

- **A writer it never sees.** A pod created and deleted entirely between the two lists is on neither, so the gate does not know it ran. If that pod wrote to the volume, the group is still reported `Ready` and the snapshot may not be application-consistent. Nothing in Longhorn detects this, but the window is a few seconds and such a pod is unlikely in practice.
- **A good run it fails.** Any pod or container change between the two lists ends the group `Failed` with `(pod-changed)` in `status.error`, even when the data is fine: a container that restarts after the last snapshot was taken, or a container unrelated to the pause. The post-commands run and the application resumes as normal. The snapshots are consistent, but Longhorn cannot prove it. Delete the failed group, which removes its snapshots, and create a new one. A group created through CSI needs no action: the CSI retry deletes the failed group and creates a new one.

#### Release

The release runs each member's post-command in every pod recorded in `status.hooks[].pods`, members in reverse pause order. The record drives it, not the member's phase: a member whose pre-command paused one pod and failed in another still has a paused pod on record, and that pod is released. Each pod moves to `PostRunning`, then `PostDone` or `PostFailed`.

**When it runs.** On the first of these:

- The group reaches `Ready` or `Failed`, or is deleted. A `bak` group is `Ready` once its snapshots are cut, before the upload, so the application resumes while the backup uploads.
- The deadline passes and the group is not yet terminal, whether because snapshots are still running or because a manager crashed before changing the phase. The executor does not wait for the controller to fail the group. The controller fails the group on the same deadline on its own schedule. The two do not coordinate on the trigger: the executor writes only `status.hooks[]` and the controller only `phase` and `error`, so either can go first. The controller cannot reach `Ready` after a release has begun, because the release gate sees the `PostRunning` record ([The identity gate before `Ready`](#the-identity-gate-before-ready)).
- A new executor finds a group in either state with an unreleased recorded pod ([Restart and leader change](#restart-and-leader-change)).

**What it does.**

1. Stops the pause walk and waits for it to return, so a pre-command and a post-command never run in the same pod at once. A pre-command still running is cut off as in [design rule 2](#design-rules); its pod stays `PreRunning` on record and is released like any other.
2. Marks the first pod `PostRunning` and gates the group in memory. From then on the claim refuses the group ([the pause walk](#runningprehooks-the-pause-walk)), so no pod can be paused after the release has read the record and then be left behind.
3. Re-reads the policy and releases each pod with the hook recorded at pause time, never re-matched by labels, because the release must undo what the pause did. If the policy was edited since the pause, the executor still runs the post-command it has now and records `PolicyChanged`: that command may not match the pre-command that ran, but refusing it would leave the application paused for certain. A policy, hook, or pod that is gone is handled as in the [reason table](#snapshotgroup-new-fields).
4. Runs the post-commands, one member at a time in reverse pause order, pods within a member in parallel. Each run is bounded by `hook-release-timeout` (default 60 seconds), not by the group deadline, which has usually passed. A pod whose post-command cannot start ([Release retry](#release-retry)) does not stop the walk: the executor moves on to the next member and comes back to the blocked pod on the next round, so one unreachable node delays only its own pods. Reverse order is kept whenever every pod can be reached; it is not a guarantee.
5. Requeues with backoff and repeats until every recorded pod is `PostDone` or `PostFailed`. What counts as a retry is in [Release retry](#release-retry).
6. Writes `postHooksDoneAt`, and emits `PostHooksSucceeded` only if no pod is `PostFailed`.

#### Release retry

The retry rule depends on whether the post-command started in the pod. A failure before that point cannot have started a process; anything after it may have.

**Could not start.** The API server cannot be reached, including for reading the policy; the RoleBinding was removed; the pod's node cannot be reached; or the pod exists but is not running. Nothing ran in the pod, so retrying is safe. The release is retried with backoff and no cap on attempts, until the post-command starts or the pod is confirmed gone (`PodNotFound`). Each retry round emits `HookReleaseBlocked` naming the pod and the cause, and for a missing RoleBinding the manifest to apply. The group keeps holding its volumes while it waits. The only thing that ends an uncapped wait is deleting the group: its deletion limit expires and the group is removed ([Deleting a hooked group](#deleting-a-hooked-group)).

While the API server is unreachable nothing can resume the application, because every command goes through it. The pause lasts as long as the outage.

**Ran and failed.** `ExitNonZero` or `Timeout`. Retried with backoff, capped at 32 seconds between attempts, up to `hook-release-attempts` (default 3) per pod. At the cap the pod is `PostFailed` and Longhorn stops: a command that keeps failing in the user's container is the user's to fix ([After the release](#after-the-release)). `Timeout` counts as ran because Longhorn can stop waiting for a post-command but cannot kill it ([design rule 2](#design-rules)). A post-command that timed out is still running in the pod, and each retry starts another one alongside it. Counting timeouts against the cap keeps that to at most `hook-release-attempts` post-commands per pod, rather than a new one on every retry with no end.

#### After the release

**A warning that the deadline is getting tight.** If a group ends `Ready` but used more than 80% of its deadline, the controller emits `HookDeadlineNearlyExceeded`. The event breaks the time down into queue wait, pre-commands, and snapshots, so the user can see which part to shorten, or raise the deadline, before a later run misses it. Without it, the first sign of a tight deadline would be a `Failed` run that kept the application paused for the whole budget.

**A pod that could not be released.** A pod left `PostFailed` gets a `PostHookFailed` event. The snapshots are valid, but the application may still be paused. The event names the policy, hook, pod, and container, and tells the user to run that hook's post-command by hand with `kubectl exec`.

#### Deleting a hooked group

**The release runs first.** Deleting a hooked group does not remove its member snapshots right away. The executor treats a group marked for deletion as finished and runs the post-commands, and the finalizer waits: it removes the group only once every recorded pod is `PostDone` or `PostFailed`. A group deleted before any pod was recorded has nothing to release and is removed at once.

The finalizer has to wait because the group's deadline cannot release the application once the group is gone. The deadline is a field of the group ([Release](#release)), so deleting the group also removes the trigger that would otherwise have run the post-commands. Without the wait, a paused application would be left with nothing to resume it.

**The wait has a limit.** The finalizer does not wait forever. It gives the release the most time it could possibly need, then lets the deletion proceed whether or not the release finished:

```
limit = start + attempts x members x timeout + (attempts - 1) x 32s

  start     the later of the deadline and the deletion time
  attempts  hook-release-attempts (default 3)
  members   members with a recorded pod: the ones the release walks
  timeout   hook-release-timeout (default 60s)
  32s       the longest backoff between two attempts

  with defaults, one member:  start + 3 x 60s + 2 x 32s = start + 4m 4s
  with defaults, two members: start + 3 x 2 x 60s + 2 x 32s = start + 7m 4s
```

Three points explain the formula.

The limit is clock time, not executor progress. The controller cannot tell whether the executor is alive. A limit that waited for the executor to use up its attempts would hang in exactly the case the limit exists for: a pod whose node cannot be reached is retried without using up any attempts ([Release retry](#release-retry)).

The clock starts at the later of the deadline and the deletion time. A release that started just before the deadline may still be on its first attempt when the deadline passes, so counting from the deadline alone could cut it short.

The formula multiplies by `members` because the release walks members one at a time, and each attempt in each member is bounded by `timeout`, so one round over every member can take `members x timeout`. Without this term, a group with several members whose post-commands keep timing out would be abandoned while a later member still had attempts left. The backoff is paid once per round, between rounds, not once per member, which is why it is not multiplied.

One case can run past the limit. The formula assumes a release worker is free when the release is due. When more hooked groups finish at once than there are workers ([Work queues](#work-queues)), the ones that wait start late and can still be releasing when the limit passes.

**What happens at the limit.** The controller emits `HookReleaseAbandoned` naming every recorded pod not yet `PostDone` or `PostFailed`, then lets the deletion proceed. The event is the only record left once the group is gone. It may name a pod that is released a few seconds later; it never misses a pod that stays paused. `PostFailed` pods are not named, since they already have a `PostHookFailed` event.

### The hook-executor

#### Deployment

**Two replicas, one leader.** The executor runs as a Deployment with two replicas by default. Only the leader does work; the other waits. The second replica covers node loss. With one replica, a pod on a lost node is not replaced until Kubernetes evicts it, about five minutes by default, longer than any default deadline. With two, the standby takes over about 20 seconds after the leader stops renewing its lease.

**Replicas prefer separate nodes but do not require them.** A hard requirement would leave the second replica Pending forever on a single-node cluster.

**A node drain can take both replicas.** Until one is rescheduled, no executor can release a paused application. The chart offers an optional PodDisruptionBudget, off by default, that keeps one replica up through a drain.

**A leader that loses its lease stops its workers and rejoins as a standby.** This is safe because the claim refuses on status, not on anything held in memory ([the pause walk](#runningprehooks-the-pause-walk)): a stale leader cannot pause a pod the new leader's release never sees. The in-memory gate in step 2 of [Release](#release) is only a fast path for the leader that set it.

**It runs the longhorn-manager image.** A separate image would add a build and release pipeline for no gain.

#### Work queues

**A release never waits behind a pause.** While an application is paused it is effectively down, so resuming it is more urgent than starting another pause. Release work therefore has its own queue, separate from pause work.

**Only a few groups pause at once.** By default five groups can be in their pause walk at the same time; the rest wait for a free worker. The number is a chart value, not a Setting, because only the executor reads it. The release pool is never smaller than the pause pool, so lowering the pause count never slows releases.

**Waiting in the queue counts against the deadline.** The deadline is fixed when the group is created, so a group that waits for a worker starts with less time left. If the deadline has already passed when its turn comes, the group fails at once, marked `(queued-past-deadline)`. The queue-wait split in `HookDeadlineNearlyExceeded` shows when the wait, not the commands, used up the time.

#### Restart and leader change

The design treats an executor restart and a leader change as the same event: a new process starts with no memory of what came before. It reads every hooked group and continues from the status it finds. A group still in `RunningPreHooks` resumes the pause walk from the recorded member phases ([the pause walk](#runningprehooks-the-pause-walk)). A group that is finished, or past its deadline, with a recorded pod not yet released is released ([Release](#release)).

longhorn-manager needs nothing extra: its phase changes and the identity gate read only status.

### Unhooked snapshots and backups

Hooks run only through a `SnapshotGroup`. A per-volume snapshot or backup of a volume that a policy covers runs no hook and works as before. Because the user may not know the policy exists, or may assume it applied, Longhorn emits a `HookPolicyBypassed` warning that names the volume and the policy. The data is crash-consistent only; a hooked group is the fix.

- The warning fires for a `Snapshot` or `Backup` that was requested directly, by a user, CSI, or a recurring job, naming every policy that covers the volume for that operation. Several matching policies are a misconfiguration a hooked group would reject, so the warning names all of them.
- Anything a `SnapshotGroup` created does not warn, including members of a `hooks: none` group. What matters is how the snapshot or backup was created, not whether the volume is also in a group at the time.
- Snapshots the engine creates on its own, such as rebuild snapshots, do not warn.
- It never blocks or delays the snapshot or backup.
- It lands on the `Snapshot` for a snapshot and on the `Volume` for a backup.
- A backup warns twice, once for its snapshot and once for the backup. A recurring job warns on every run.

### Failure handling

Each row says what happens to the application, what happens to the group, and where to look. In the Group column, `unchanged` means the group's phase is not affected.

| Situation | Application | Group | Where to look |
|---|---|---|---|
| Member has no policy or more than one, has no running pod, or its namespace has not allowed the executor | untouched | rejected | the create error |
| Volume already in another hooked group that has not finished | untouched | rejected; or `Failed` for the newer group, if both passed admission | the create error, or member `reason` `VolumeConflict` |
| Policy deleted or edited, or no running pod, before the pause starts | untouched | `Failed` | member `reason` `PolicyNotFound`, `PolicyChanged`, or `PodNotFound` |
| Policy edited after the pause | resumed with the policy's current post-command | unchanged | pod `reason` `PolicyChanged` |
| Pre-command fails or hangs | every recorded pod resumed | `Failed` | `PreHookFailed`, pod `reason` |
| Pod or container restarts, or pod is replaced, during the pause | the new process writes unpaused; recorded pods resumed | `Failed` | `(pod-changed)` in `status.error`, naming the pod |
| Snapshots take longer than the deadline | resumed at the deadline | `Failed` | `HookDeadlineExceeded` |
| Deadline passes on the executor's clock while the last snapshots are still being cut | resumed | `Failed` | `(released-before-ready)` in `status.error` |
| An old manager drives a hooked group during the upgrade | never paused | `Failed` if a new manager takes it over while it is still `InProgress` or finds a member snapshot without the hooked marker label; left `Ready` with a warning if the old manager already finished it | `(pre-hooks-skipped)` in `status.error`, or `PreHooksSkipped` |
| An old CSI plugin creates a group from a class with `hooks: command` during the upgrade | untouched | rejected; the CSI retry succeeds once a new plugin serves it | the create error, naming the plugin rollout |
| Executor restarts while a pre-command is running | that pod is failed; every recorded pod resumed | `Failed` | pod `reason` `Interrupted` |
| Executor restarts, or its node is lost, while the application is paused | resumed by the new leader | unchanged | `PostHooksSucceeded` |
| longhorn-manager restarts while the application is paused | resumed by the executor, at the deadline at the latest | unchanged | `PostHooksSucceeded` |
| Post-command fails or hangs | retried up to `hook-release-attempts` times, then left for the user to release by hand | unchanged | `PostHookFailed`, pod `PostFailed` |
| API server, node, or kubelet unreachable at release | stays paused until it is reachable; retried without limit | unchanged | `HookReleaseBlocked` |
| RoleBinding removed while the application is paused | stays paused until the admin reapplies it | unchanged | `HookReleaseBlocked`, with the RoleBinding to apply |
| Group deleted while the application is paused | resumed first; deletion waits, up to the limit in [Deleting a hooked group](#deleting-a-hooked-group) | removed after the release | `PostHooksSucceeded`, or `HookReleaseAbandoned` if the limit is reached |
| CSI group fails and is retried | each retry pauses again; it cannot start until the failed group has resumed | `Failed`, then deleted by the retry | the same events, once per attempt |

### Security and RBAC

#### Who can define commands

A `VolumeHookPolicy` belongs to one namespace and can only select PVCs there, so its commands can only reach pods in that namespace.

Once the namespace has bound the executor's role ([Where the executor can exec](#where-the-executor-can-exec)), anyone who can edit a policy can run commands in its pods. For the built-in `edit` and `admin` roles this changes nothing, because both already allow running commands in pods. A custom role that allows editing policies but not running commands in pods now allows both. Longhorn cannot prevent this, so anyone writing such a role needs to know.

#### Who can trigger a pause

Through CSI, a `VolumeGroupSnapshot` can only select PVCs in its own namespace, so a user can pause only their own application.

A `SnapshotGroup` created directly, with kubectl, the REST API, or the UI, lives in `longhorn-system`. Anyone who can create one can already snapshot any volume in the cluster (#13349). With hooks, they can also pause the application behind it, in any namespace that has bound the executor's role.

#### What the API reveals

The preview returns the labels and container names of the pods that mount the member volumes. The `volumeHookPolicy` resource returns more: every policy in every namespace, with its PVC selectors, pod selectors, and container names, streamed to any UI session on the Snapshot Groups page. The Longhorn API has no per-user authorization, so anyone with UI access sees all of it. That is accepted, because the same user already controls every volume in the cluster, and selectors and container names reveal nothing sensitive. Commands are never returned.

#### Where the executor can exec

The executor has no cluster-wide permission to run commands in pods. RBAC cannot limit `pods/exec` to pods that use Longhorn volumes, so a cluster-wide grant would reach every pod in every namespace, including `kube-system`.

Instead, Longhorn ships a ClusterRole and leaves it unbound. A namespace admin binds it to the executor's ServiceAccount in their own namespace, next to their policy. Longhorn never creates that binding, so until an admin does, the executor can run commands nowhere.

#### What a compromised executor reaches

A compromised executor can run commands in every namespace that bound the role, and nowhere else.

A command running in a pod can also read that pod's ServiceAccount token. For an ordinary application this adds nothing. For a pod whose ServiceAccount has cluster-wide permissions, the attacker gains those permissions too.

`longhorn-system` is always refused. Its pods are privileged, so a command in one of them is a command on the node. The policy webhook, group admission, and the executor's own check each refuse it independently, so a group that slipped past an older or missing webhook still runs nothing there.

#### Manager and executor

longhorn-manager cannot run commands in pods, and it cannot grant that permission to anyone else. Its two new permissions are listed in [RBAC objects](#rbac-objects).

Running the commands in a separate pod, under a separate ServiceAccount, protects in one direction only. A compromised executor cannot reach the manager, because it cannot run commands in `longhorn-system`. A compromised manager can reach the executor: the manager creates pods in `longhorn-system`, and a pod can run as any ServiceAccount in its own namespace, so the attacker can start a pod as the executor and use its token. This is accepted. The manager is already the most privileged part of Longhorn, so there is nothing left to protect the executor from.

#### Pod hardening

The executor pod meets the Kubernetes [restricted Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/) and runs with a read-only root filesystem. A network policy allows incoming traffic only from the metrics scraper. Outgoing traffic is left open, because a network policy cannot select the API server; the chart's existing network policies are incoming-only for the same reason.

#### What the executor records

The executor records only the policy name, the pod, the container, the exit code, and the reason. It never records the command or its output, in status, logs, or events.

This matters because the support bundle collects every Longhorn resource, pod log, and event in `longhorn-system`, and bundles are often attached to public issues. Anything the executor wrote there would ship with every bundle. The policy itself is not collected, because it lives in the application's namespace, which the bundle does not include.

#### RBAC objects

Longhorn installs the objects below. The only object the user adds is the per-namespace RoleBinding described in [Where the executor can exec](#where-the-executor-can-exec).

| Object | What it grants |
|---|---|
| ClusterRole `longhorn-hook-executor` (new) | `create` on `pods/exec`, `list` on `pods`, `get` on `volumehookpolicies`. Shipped unbound; it grants nothing until a namespace admin binds it. |
| ServiceAccount `longhorn-hook-executor` and its Role in `longhorn-system` (new) | `get/list/watch` on `snapshotgroups`, `volumes`, `settings`; `update` on `snapshotgroups/status`; `create/patch` on `events`; `create/get/update` on `leases`. No Secrets, no ConfigMaps. |
| ClusterRole `longhorn-role` (manager) | Adds `get/list/watch` on `volumehookpolicies` and `create` on `subjectaccessreviews`. |
| ClusterRoles `longhorn-volumehookpolicy-edit` and `longhorn-volumehookpolicy-view` (new) | Aggregated into the built-in `admin`, `edit`, and `view` roles. The first grants every verb on `volumehookpolicies`, the second `get/list/watch`. Without them a namespace admin could not bind `longhorn-hook-executor`: Kubernetes lets a user bind a ClusterRole only if they already hold every permission in it, including `get volumehookpolicies`. |

### Longhorn UI

The UI manages `SnapshotGroup` and shows `VolumeHookPolicy` read-only. It helps the user write a policy and the RoleBinding; the user applies both with kubectl. The UI must follow these rules:

- Before a hooked group is created, the UI runs the preview and blocks the create while any member reports a `validationFailure` or an `accessFailure`. A pod's `readFailure` does not block it: admission does not read pods, so the create would still be accepted.
- The RoleBinding is shown exactly as the manager returns it in `accessFailureManifest`. The UI never writes its own, because only the manager knows the executor's namespace. An `accessFailure` with no manifest means the check could not finish; the user re-runs the preview instead of pasting anything.
- The preview does not change the cluster, and it does not notice changes made with kubectl. After applying a RoleBinding or a policy, the user runs the preview again.
- Hook commands typed into a policy form never leave the browser. Wrapping them as `sh -c` is the form's convention, not the CRD's.
- A hook command is never displayed: not in the policy list, the group detail, or the hook status rows. Policy name, generation, pod, phase, exit code, and reason are enough to debug.

The sketches below show what each screen contains; layout is the UI team's call.

**Create dialog.** The preview runs before the create and blocks it while a member fails. Shown after a failed preview, with the Fix panel inside it:

```
+---------------------------- Create Snapshot Group --------------------------------+
| Name: [ demo ]                 Hooks: ( ) none  (o) command                       |
| Select members by: (o) Volumes  ( ) Label selector                                |
| Volumes: [ pvc-a1b2c3 x ] [ pvc-d4e5f6 x ]      (selection order = pause order)   |
| Engine snapshot labels: [ key ] [ value ] (+)                                     |
| Deadline seconds: [ 60 ]                                                          |
|                                                                                   |
| Preview (pause order)                                          [ Re-check ]       |
| +----+------------+---------------+----------+----------------+---------------+   |
| | #  | Volume     | Policy        | Pods     | Failure        | Exec grant    |   |
| +----+------------+---------------+----------+----------------+---------------+   |
| | 1  | pvc-a1b2c3 | default/demo  | demo-0   |                | denied        |   |
| | 2  | pvc-d4e5f6 | (none)        | shard0-0 | no hook policy | denied        |   |
| +----+------------+---------------+----------+----------------+---------------+   |
| ! pod demo-0 appears under 2 members; hooks run once per member                   |
|                                                                                   |
| Fix: namespace "default"                                                          |
| Exec grant denied; no policy covers PVC pvc-shard0. Apply the blocks below with   |
| kubectl, then Re-check. This dialog cannot change the cluster.                    |
| [ Step 1 and Step 2, shown in the next sketch ]                                   |
|                                                                                   |
| Members failing: pvc-d4e5f6                               [ Cancel ]   [ OK ]     |
+-----------------------------------------------------------------------------------+
```

**Fix panel.** Step 1 shows the RoleBinding exactly as the manager returned it, and appears only when the executor does not yet have permission in the namespace. Step 2 offers an existing policy first; if none fits, the new policy is built from the form:

```
+---------------------- Fix: namespace "default" (continued) -----------------------+
| Step 1: Grant the hook executor exec access (namespace admin)           [ copy ]  |
| +--------------------------------------------------------------------------+      |
| | kubectl apply -f - <<'EOF'                                               |      |
| | (the RoleBinding from User Experience step 3, namespace: default)        |      |
| | EOF                                                                      |      |
| +--------------------------------------------------------------------------+      |
|                                                                                   |
| Step 2: Cover the PVCs with a policy                                              |
| Cover with: ( ) Existing policy default/payments (PVC ledger, hook default)       |
|             (o) New policy for pvc-shard0 only                                    |
| Policy name: [ pvc-shard0 ]   PVCs: pvc-shard0                                    |
|                                                                                   |
| Hooks                                                           [ + Add hook ]    |
| +--------------------------------------------------------------------------+      |
| | Hook 1                                                        [ Remove ] |      |
| | Name:         [ demo        ]   Pod selector: [ app=demo         v ] (+) |      |
| | Container:    [ app        v ]   (required: shard0-0 has 2 containers)   |      |
| | Pre-command:  [ pause.sh -p "$DB_PASS"                                 ] |      |
| | Post-command: [ resume.sh -p "$DB_PASS"                                ] |      |
| +--------------------------------------------------------------------------+      |
| Commands run through sh -c, so $VARS expand inside the pod.                       |
| ! Use an env var or a mounted Secret for credentials; never a literal secret.     |
|                                                                                   |
| Apply the policy with kubectl                                           [ copy ]  |
| +--------------------------------------------------------------------------+      |
| | kubectl apply -f - <<'EOF'                                               |      |
| | apiVersion: longhorn.io/v1beta2                                          |      |
| | kind: VolumeHookPolicy                                                   |      |
| | metadata:                                                                |      |
| |   name: pvc-shard0                                                       |      |
| |   namespace: default                                                     |      |
| | spec:                                                                    |      |
| |   pvcNames: [pvc-shard0]                                                 |      |
| |   hooks:                                                                 |      |
| |   - name: demo                                                           |      |
| |     exec:                                                                |      |
| |       podSelector: {matchLabels: {app: demo}}                            |      |
| |       container: app                                                     |      |
| |       preCommand:  [sh, -c, 'pause.sh -p "$DB_PASS"']                    |      |
| |       postCommand: [sh, -c, 'resume.sh -p "$DB_PASS"']                   |      |
| | EOF                                                                      |      |
| +--------------------------------------------------------------------------+      |
+-----------------------------------------------------------------------------------+
```

**Group detail.** #13349's page gains the timing line, which splits queue wait, pre-hooks, and snapshots, and a Hooks table with one row per pod per member:

```
+---------------------------------------------------------------------------------------------------------------------+
| Snapshot Group: demo                                                                                                |
| Status: Ready          Deadline: 60s          Creation time: 2026-09-21 00:00:00                                    |
| Selection: Volumes                                                                                                  |
| Hooks: command (post done)    Timing: queued 9s, pre-hooks 22s, snapshots 21s, all paused 27s                       |
|                                                                                                                     |
| Members (pause order)                                                                                               |
| +------------+----------------------+-------+---------+-------+                                                     |
| | Volume     | Snapshot             | Ready | Created | Error |                                                     |
| +------------+----------------------+-------+---------+-------+                                                     |
| | pvc-a1b2c3 | demo-a1b2c3          | true  | 00:31   |       |                                                     |
| | pvc-d4e5f6 | demo-d4e5f6          | true  | 00:31   |       |                                                     |
| +------------+----------------------+-------+---------+-------+                                                     |
|                                                                                                                     |
| Hooks (one row per pod per member; demo-0 mounts both volumes)                                                      |
| +------------+-----------------------+------------------+------------+------+------------------------------+        |
| | Volume     | Policy / Hook         | Pod              | Hook phase | Exit | Reason                       |        |
| +------------+-----------------------+------------------+------------+------+------------------------------+        |
| | pvc-a1b2c3 | default/demo (gen 1)  | default/demo-0   | PostDone   | 0    |                              |        |
| | pvc-d4e5f6 | default/demo (gen 1)  | default/demo-0   | PostDone   | 0    |                              |        |
| | pvc-d4e5f6 | default/demo (gen 1)  | default/shard0-0 | PostDone   | 0    |                              |        |
| +------------+-----------------------+------------------+------------+------+------------------------------+        |
+---------------------------------------------------------------------------------------------------------------------+
```

**Hook Policies panel.** Beneath the group list on the Snapshot Groups page. The list on the left is the cluster-wide stream filtered by namespace in the browser; the detail on the right shows routing and coverage, never the commands:

```
+---------------------------------- Snapshot Groups --------------------------------+
| [ Create Snapshot Group ]                                Filter: [ Name v ] [   ] |
| +----------+---------+------------+-------------------------------------------+   |
| | Name     | Status  | Hooks      | Created                                   |   |
| +----------+---------+------------+-------------------------------------------+   |
| | demo     | Ready   | post done  | 2026-09-21 00:00:00                       |   |
| +----------+---------+------------+-------------------------------------------+   |
|                                                                                   |
| Hook Policies   Namespace: [ all namespaces v ]   Read-only; managed with kubectl |
| +-----------+--------+--------+---------+---------------------------------------+ |
| | Namespace | Name   | Covers | Used by | default/demo             generation 3 | |
| |-----------+--------+--------+---------| Covers:  PVCs pvc-config, pvc-shard0  | |
| | default   | demo   | 2 PVCs | 1 group | Volumes: pvc-config -> pvc-a1b2c3     | |
| | payments  | ledger | label  |    -    |          pvc-shard0 -> pvc-d4e5f6     | |
| |           |        |        |         | Used by: demo  [policy changed]       | |
| |           |        |        |         |                                       | |
| |           |        |        |         | Hooks                                 | |
| |           |        |        |         | demo: pods app=demo, container app    | |
| |           |        |        |         |   operations: snapshot, backup        | |
| |           |        |        |         | Commands are not shown; to read them: | |
| |           |        |        |         | kubectl get lhvhp -n default demo \   | |
| |           |        |        |         |   -o yaml                      [copy] | |
| +-----------+--------+--------+---------+---------------------------------------+ |
+-----------------------------------------------------------------------------------+
```

### Design decisions

#### Why the executor is separate from the manager

Permissions belong to a ServiceAccount, and a ServiceAccount belongs to a pod, so a component that needs different permissions from longhorn-manager has to run in its own pod.

| | Commands run by the manager | This design |
|---|---|---|
| Which account namespace admins allow to run commands in their pods | `longhorn-service-account`, which already reads every Secret, volume, and Longhorn resource in the cluster | `longhorn-hook-executor`, which can run commands only in namespaces that bound its role |
| What a bug or a break-in in that process can reach | The whole storage control plane | Only the namespaces that bound the role |
| Who resumes the application if that process dies | The same manager pod, once it restarts or Longhorn notices its node is down | The standby replica, within seconds |

In both designs a restart is safe, because the release works from what is saved in status. The CSI sidecar split (longhorn/longhorn#14020) makes the same choice for the same reason. If giving `pods/exec` to longhorn-manager is acceptable, the executor can move into the manager as a second controller without changing anything else. The separate Deployment is the cautious choice, not a required one.

#### Per-namespace scoping, not a chart toggle

The other option was a chart setting that turns the feature on or off for the whole cluster. That protects a cluster only while the feature is off; once it is on, every namespace is exposed. The per-namespace RoleBinding ([Where the executor can exec](#where-the-executor-can-exec)) keeps every namespace that has not bound the role out of reach, whether or not the feature is in use elsewhere. The cost is one manifest per namespace, and a binding Longhorn does not own: if an admin removes it, Longhorn cannot restore it and waits for the admin ([Release retry](#release-retry)).

#### Settings, not executor arguments

Two pods read `hook-release-attempts` and `hook-release-timeout`: the executor, to retry the post-commands, and the controller, to work out the deletion limit ([Deleting a hooked group](#deleting-a-hooked-group)). A Setting is visible to both. An argument on the executor's Deployment would reach only one of them.

#### No phase for the post-commands

`status.phase` answers one question: were the snapshots taken in time. Resuming the application afterwards does not change that answer, and backup, restore, CSI, and the UI all wait on `Ready`, so they should not wait for the post-commands as well. Each pod's release result is recorded in `status.hooks[]` instead ([Release](#release)).

#### Why a failed pre-command fails the group

Velero offers the other choice with [`onError: Continue`](https://velero.io/docs/main/backup-hooks/#specifying-hooks-as-pod-annotations). It can, because a `Backup` has a result for that case: [`PartiallyFailed`](https://github.com/velero-io/velero/blob/v1.18.0/pkg/apis/velero/v1/backup_types.go#L279-L287), meaning the backup ran to completion but some items had errors. A `SnapshotGroup` has no such result. It ends `Ready` or `Failed`, and the Kubernetes [`VolumeGroupSnapshot`](https://kubernetes-csi.github.io/docs/group-snapshot-restore-feature.html) it maps to has only [`readyToUse: true` or `false`](https://github.com/kubernetes-csi/external-snapshotter/blob/v8.6.0/client/apis/volumegroupsnapshot/v1/types.go#L95-L100). A group that skipped a failed pre-command would therefore have to end `Ready`, and `Ready` would then mean application-consistent only sometimes, with no way for a CSI user to tell which. This LEP keeps `Ready` unambiguous. A user who does not want hooks uses `hooks: none`. The option can be added later as a spec field such as `hookFailurePolicy: Continue` with a new terminal phase such as `PartiallyFailed`; nothing in this design is in the way, and `status.hooks[]` already records which pods failed. A failed post-command is a different case: the snapshots are already taken and valid, so it does not fail the group, and the pod is recorded as `PostFailed` ([After the release](#after-the-release)).

#### No long-lived session in the executor

The executor could hold a database session open for the pause, as MySQL's `FLUSH TABLES WITH READ LOCK` needs ([Story 3](#story-3-a-database-whose-lock-ends-with-the-session)). It does not. A pause that lives only in the executor's process is lost on an executor restart, with nothing recorded to detect it, so the group would still be reported `Ready`. The session has to live in the user's pod, where losing it shows up as a container restart that the identity gate catches.

#### No admission policy against old managers

An old manager that updates a hooked group writes the whole object from its own typed client, so the fields it does not know are dropped. A `ValidatingAdmissionPolicy` could refuse such writes. It is not added. A group can pause anything only when `members[].hookPolicyRef` is set, and only the new mutating webhook sets it, in the same request that refuses the create until the rollout is complete ([Admission](#admission) check 6). A pausable group therefore never exists while an old manager runs. The policy would guard one rollout, cost a permanent `failurePolicy: Fail` on every group write, and need its own RBAC and tests; the two controller guards under [Upgrade strategy](#upgrade-strategy) cover the remaining ways a group can reach a new manager without a pause.

### Settings

Two Longhorn Settings size the release. Both also appear in the deletion limit ([Deleting a hooked group](#deleting-a-hooked-group)).

| Setting | Default | Range | Used for |
|---|---|---|---|
| `hook-release-attempts` | 3 | 1 to 20 | How many times a post-command that ran and failed is retried per pod. |
| `hook-release-timeout` | 60 seconds | 5 to 600 | How long one post-command run may take before it is cut off and recorded as `Timeout`. |

### Observability

#### Events

Each event is described in the section where it fires.

| Event | Emitted by | On | When |
|---|---|---|---|
| `PreHooksSucceeded` | executor | group | Every member's pre-command finished. |
| `PreHookFailed` | executor | group | A member failed before or during its pre-command. Names the member and the reason, and the pod when there is one. |
| `PostHooksSucceeded` | executor | group | Every recorded pod was released. |
| `PostHookFailed` | executor | group | A pod's post-command used up its attempts. Says how to release the pod by hand. |
| `HookReleaseBlocked` | executor | group | A post-command could not start and is being retried. Names the pod and the cause. If the RoleBinding is missing, the event also carries the manifest to apply. |
| `HookDeadlineExceeded` | group controller | group | The deadline passed before the group was `Ready`. |
| `HookDeadlineNearlyExceeded` | group controller | group | A `Ready` group used over 80% of its deadline. Says where the time went. |
| `HookReleaseAbandoned` | group controller | group | A deleted group was removed with pods still unreleased. Names them. |
| `PreHooksSkipped` | group controller | group | A hooked group is `Ready` but the executor never claimed it: an older manager drove it during the upgrade and paused nothing. The snapshots are not application-consistent. Delete the group and create a new one. |
| `HookPolicyBypassed` | snapshot and backup controllers | `Snapshot` or `Volume` | A per-volume snapshot or backup ran on a volume a policy covers, outside any group, so no hook ran. See [Unhooked snapshots and backups](#unhooked-snapshots-and-backups). |

#### Metrics

The executor serves four Prometheus metrics. Each has an `operation` label, `snapshot` or `backup`. None has a group, pod, or policy label; that detail lives in status and events.

| Metric | Type | Labels | Measures |
|---|---|---|---|
| `longhorn_snapshot_group_hook_releases_total` | counter | `result`, `operation` | Hooked groups whose release finished. `result` is `released` when every recorded pod ended `PostDone`, `post_failed` when any pod ended `PostFailed`. |
| `longhorn_snapshot_group_hook_deadline_exceeded_total` | counter | `operation` | Groups whose release was triggered by the deadline rather than by a terminal phase. Counted by the executor, so it can be lower than the number of `HookDeadlineExceeded` events, which the controller emits as soon as the deadline passes. |
| `longhorn_snapshot_group_hook_command_failures_total` | counter | `step`, `reason`, `operation` | Hook commands that failed. `step` is `pre` or `post`; `reason` is the same fixed name status and events use. |
| `longhorn_snapshot_group_hook_window_seconds` | histogram | `operation` | Seconds between `hooksStartedAt` and `postHooksDoneAt`: how long Longhorn held at least one pod paused. A `PostFailed` pod can stay paused after `postHooksDoneAt`; that time is not counted. Not recorded when no pod was ever paused. |

### Upgrade strategy

- Existing groups are not affected. The new CRD, the new `SnapshotGroup` fields, and the executor Deployment are added alongside what is there. Existing groups default to `hooks: none` and run as before.
- While the manager pods are still being replaced, a hooked group cannot be created ([Admission](#admission) check 6). The create fails with a message saying so; retry once the rollout is done.
- That check is enough on its own. Only the new mutating webhook writes `members[].hookPolicyRef`, and without it the executor pauses nothing, so an old manager never owns a group that can pause ([No admission policy against old managers](#no-admission-policy-against-old-managers)). What an old manager can still own is a hooked group that cannot pause: one admitted by an old webhook, or one left behind when the manager is rolled back to the previous release, which is not supported. It moves the group to `InProgress` and takes the snapshots as if hooks did not exist. Two guards in the controller catch this.
  - If a new manager takes over while the group is still `InProgress` and `preHooksDone` is unset, or a member snapshot lacks the hooked marker label ([SnapshotGroup (new fields)](#snapshotgroup-new-fields)), the group fails with `(pre-hooks-skipped)` and its snapshots are deleted with it. `Ready` keeps its meaning because the group never reaches it.
  - If the group is already `Ready` with `preHooksDone` unset and a member snapshot without the marker, the executor never ran. The group is left `Ready`, because CSI or a user may already have acted on it, and gets a `PreHooksSkipped` warning naming the snapshot instead. A restored group also arrives `Ready` without `preHooksDone`, but its member snapshots carry the marker, and that is how the controller tells the two apart.
  - A hooked group admitted by an old webhook that a new manager picks up has no `members[].hookPolicyRef`. The executor fails it with `PolicyNotFound` and a message that names the cause: the group was admitted by a webhook that does not know hooks, recreate it.
- The CSI plugin DaemonSet rolls out on its own, after the managers, and check 6 does not see it. A plugin from before this release does not know the `hooks` and `deadlineSeconds` class parameters and forwards them as engine labels, so a `VolumeGroupSnapshot` it serves from a class with `hooks: command` would arrive with `spec.hooks` unset and go `Ready` without a pause. The validating webhook rejects a CSI-created group whose `spec.labels` carries either key, with a message naming the plugin rollout. The old plugin returns the error, external-snapshotter retries, and the retry succeeds once a new plugin serves it.
- A `VolumeGroupSnapshotClass` whose `parameters` already contain `hooks` or `deadlineSeconds` as free-form labels changes meaning: the keys are now read as settings and are no longer written as engine snapshot labels. A value that is not valid for the setting fails the create with `InvalidArgument`. Groups created from such a class before the upgrade keep their labels and restore unchanged.

### Uninstall

Uninstall removes groups before the executor, so a paused application is released first. The uninstaller waits only as long as its own grace period, then logs any pod still paused and continues. Removing the `VolumeHookPolicy` CRD deletes every policy in every namespace. These are user-owned resources, and a GitOps controller will try to recreate them until the CRD is gone; the uninstall documentation must say so and suggest exporting policies first. RoleBindings created by namespace admins are left in place; once the ClusterRole is gone they grant nothing.

### Test plan

- Happy path: a hooked group created through kubectl, the REST API, or a CSI `snap` or `bak` class ends `Ready`. Members are paused in list order and released in reverse, and every member snapshot is created in `InProgress` and before the deadline.
- Admission: every rejection listed under [Admission](#admission) and [Validation](#validation) fires on create. A missing RoleBinding is rejected with the manifest to apply.
- Identity gate: any change to a recorded pod during the window, such as a container restart, a pod recreated under the same name, or a `kubectl debug` session, ends the group `Failed` with `(pod-changed)` in `status.error`. Untouched pods pass.
- Failure handling: each row of [Failure handling](#failure-handling) ends with the application, group, and reason it states. No recorded pod is left paused.
- Restart and deletion: the executor killed at any step, a leader change, or the manager being down still leaves the application released by the deadline. Deleting a paused group releases it before any snapshot is removed. With the executor down, the finalizer waits out the limit and `HookReleaseAbandoned` names the pods that were never released.
- Release gate: a controller that is about to write `Ready` while the executor writes `PostRunning` for the same group loses the race and the group ends `Failed` with `(released-before-ready)`, never `Ready`.
- Load: a burst of groups wider than the worker count ends every group `Ready` or failed by the deadline rule, and no application stays paused past its deadline.
- Security: the executor cannot exec outside bound namespaces, read Secrets, or write group spec. Command text and output appear nowhere: not in status, events, logs, REST responses, or a support bundle.
- Upgrade and uninstall: `hooks: none` groups behave as before. Hooked creates are refused during the manager rollout, including while an old manager pod is still terminating, and accepted after it. A CSI-created group carrying `hooks` or `deadlineSeconds` in `spec.labels` is rejected; the same labels on a hand-written group, or on a restored group, are accepted. A hooked group found `InProgress` with `preHooksDone` unset, or with a member snapshot that lacks the hooked marker label, ends `Failed` with `(pre-hooks-skipped)`; one found `Ready` with a member snapshot that lacks the marker gets `PreHooksSkipped` and stays `Ready`, while a restored group whose members all carry the marker gets no warning. A hooked member with no `hookPolicyRef` fails `PolicyNotFound` with the old-webhook message. Uninstall releases a paused application and completes even with a stuck finalizer.
- Regression: every #13349 test passes unchanged with `hooks: none`.
