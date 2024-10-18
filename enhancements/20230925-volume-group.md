# Volume Group

## Summary

In certain scenarios, a single application can be composed of multiple volumes. However, Longhorn presently lacks the support to create application-consistent snapshots and backups.

This proposal aims to address this limitation by introducing a volume group feature. This feature enables user to group the volumes based on the application Pod. User can define commands to temporarily pause the application before Longhorn proceeds with taking snapshots or backups of its associated volumes. Sebsequently, the application can be resumed with another command execution. This process ensures that application, such as databases, can achieve application-consistent snapshots and backups.

### Related Issues

https://github.com/longhorn/longhorn/issues/2128

## Motivation

### Goals

The primary goals of this enhancement are as follows:

- Enable users to create snapshots and backups through volume groupings.
- Provide users with the ability to execute commands to quiesce and unquiesce applications as needed before and after the volume group snapshot and backup operations.
- Enable users to revert to previously created volume group snapshots.
- Enable user to restore from the previous volume group backups to new PersistentVolumeClaims (PVC) with their original names.

### Non-goals [optional]

- Detaching volumes from application workloads, such as deleting bare Pods or DaemonSets.
- Detaching volumes from controlled replica sets, such as scaling Deployments or StatefulSets.
- Attach volumes in maintenance mode when reverting snapshots.

## Proposal

### User Stories

#### Story 1: Application-Consistent Snapshots/Backups

As a user, I need the capability to temporarily pause my application (quiesce) prior to taking snapshot/backup for all volumes attached to my application workload. This ensures that the the snapshots/backups are application-consistent.

Once the snapshots/backups are complete, I should be able to resume normal application operation (unquiesce).

#### Story 1: Revert From The Volume Group Snapshot

As a user, I need the ability to revert from a previously created volume group snapshots. This enable me to revert my application data to the snapshotted time.

#### Story 2: Restore From The Volume Group Backup

As a user, I need the ability to restore from a previously created volume group backups to PVCs with original names. This enables me to remount my application data to the same PersistentVolumeClaim at the backed-up time.

### User Experience In Detail

To achieve application-consistent snapshots and backups, users will need to follow these steps:

#### Create VolumeGroup Custom Resource

1. Create a VolumeGroup Custom Resource with `PreAction` and `PostAction` fields for snapshot and backup operations.

```yaml
apiVersion: longhorn.io/v1beta2
kind: VolumeGroup
metadata:
  name: demo-0
  namespace: longhorn-system
spec:
  group:
    kind: Pod
    names:
    - demo-0
    namespace: default
  snapshot:
    preActions:
    - name: pre-snapshot-lock
      action: execute
      args:
      - "/bin/sh"
      - "-c"
      - "mysql -e 'FLUSH TABLES WITH READ LOCK;' demo"
    postActions:
    - name: post-snapshot-unlock
      action: execute
      args:
      - "/bin/sh"
      - "-c"
      - "mysql -e 'UNLOCK TABLES;' demo"

  backup:
    preActions:
    - name: pre-backup-lock
      action: execute
      args:
      - "/bin/sh"
      - "-c"
      - "mysql -e 'FLUSH TABLES WITH READ LOCK;' demo"
    postActions:
    - name: post-backup-unlock
      action: execute
      args:
      - "/bin/sh"
      - "-c"
      - "mysql -e 'UNLOCK TABLES;' demo"
```

#### Snapshot

**Create:**

1. User create [a VolumeGroup custom resource](#create-volumegroup-custom-resource)
1. User add the `longhornio.volume-group-action=snapshot` label to the VolumeGroup.
1. Longhorn created a new VolumeGroupAction custom resource.
1. User observes a VolumeGroupAction started.
1. Longhorn creates snapshots.
1. Longhorn change VolumeGroupAction state to completed or error.
1. Longhorn change VolumeGroup state to completed or error.

**Revert:**
1. User detach the volumes from application workload, for example: scale down deployment.
1. User attach the volumes in maintenance mode.
1. User add the `longhornio.volume-group-action=revert` label to the VolumeGroupAction.
1. Longhorn reverts snapshots to volumes.
1. Longhorn change VolumeGroupAction state to completed or error.
1. User detach the volumes.
1. User attach the volumes to application.
1. User sees the reverted data in the application.

#### Backup

**Create:**
1. The user creates a [VolumeGroup custom resource](#create-volumegroup-custom-resource).
1. The user adds the `longhornio.volume-group-action=backup` label to the VolumeGroup.
1. Longhorn creates a new VolumeGroupAction custom resource.
1. The user observes a VolumeGroupAction started.
1. Longhorn creates snapshots.
1. Longohrn creates backups.
1. Longhorn updates the state of the VolumeGroupAction to either completed or error.
1. Longhorn updates the state of the VolumeGroup to either completed or error.

**Restore:**
1. Then user deletes the application workload stack, such as Pods, PVs, and PVCs.
1. Then user adds the `longhornio.volume-group-action=restore` label to the VolumeGroupAction.
1. Longhorn creates Volumes from Backups.
1. Longhorn creates PersistentVolume from the newly generated Volumes.
1. Longhorn creates PersistentVolumeClaim (PVC) for these Volumes, maintaining the original PVC names.
1. Longhorn updates the state of the VolumeGroupAction to either completed or error.
1. The user re-create the application workload with the restored PVC.
1. Then user sees the restored data within the application.

### API changes

## Design

### VolumeGroup Custom Resource Definition

The VolumeGroup custom resource (CR) allows user to define the pre/post-actions for supported operations, along with their restoration actions.

When a VolumeGroup CR is created, the associated actions are not triggered automatically. To initiate the action, users need to apply the label `longhornio.volume-group-action: <action>` to the VolumeGroup.

Once the label is applied, the volume group controller will generated a VolumeGroupAction CR.

#### Supported Actions

The following `longhornio.volume-group-action` label values are supported:
- snapshot
- backup

#### Controller

Introduce new volume-group controller to handle VolumeGroup changes.

The newly introduced volume-group controller is responsible for managing changes in the VolumeGroup custom resource. It orchestrates operations based on the VolumeGroup state. And log events and update the VolumeGroup to the next state when the current state logic is completed.

##### VolumeGroup Initial State (" ")

This is the initial state when a new VolumeGroup custom resource is created, no specific actions are performed.

At the end of this state, the controller updates VolumeGroup to the [Pending State](#volumegroup-pending-state).

##### VolumeGroup Pending State

In this state, the controller checks for the presence of the `longhornio.volume-group-action` label.

If the label is not found, no further actions are taken.

However, if the label is present, the controller proceeds to create a VolumeGroupAction custom resource and records the name of the newly created VolumeGroupAction in the VolumeGroup status.

At the end of this state, the controller updates VolumeGroup to the [Started state](#volumegroup-completed-state).

##### VolumeGroup Started State

The Started State does not trigger state changes directly; instead, it relies on the volume group action controller to manage the state based on the ongoing action results.

##### VolumeGroup Error State

This state behaves similarly to the [Completed state](#volumegroup-completed-state).

##### VolumeGroup Completed State

This state is reached when actions are completed or errored. In this state, the controller removed the `longhornio.volume-group-action` label and the VolumeGroupAction name from the status. It also records a timestamp indicating when the action is stopped.

When then VolumeGroup's status that it is no longer running (VolumeGroup.Status.Running is empty) and the `longhornio.volume-group-action` label exists, the controller interprets this as an indication that the user intends to retrigger the actions. Consequently, the controller updates the VolumeGroup to the [Pending state](#volumegroup-pending-state).

### VolumeGroupAction Custom Resource Definition

The VolumeGroupAction custom resource (CR) serves the purpose of breaking up the VolumeGroup action, pre/post-action into sequential steps. These steps are automatically initiated. And created resources are record in the status (VolumeGroupAction.Status.Triggered.References).

The restore actions can be triggered once the VolumeGroupAction has completed and with the `longhornio.volume-group-action: restore` label.

#### Support Action

- triggered: this is the primary action automatically initiated when the VolumeGroupAction is created, and cannot be retriggered.
- restore: this is the restore action, can be re-triggered with the "longhornio.volume-group-action: restore" label.

#### Controller

Introduce of the new volume-group-action controller to handle VolumeGroupAction changes.

The newly introduced volume-group-action controller is responsible for managing changes in the VolumeGroupAction custom resource. It orchestrates operations based on the VolumeGroupAction state. And log events and update the VolumeGroupAction to the next state when the current state logic is completed.

##### VolumeGroupAction Initial State (" ")

This is the initial state when a new VolumeGroupAction custom resource is created.

In this state, no specific actions are taken, serving as a starting point for the process.

At the end of this state, controller updates VolumeGroup CR to Pending State.

##### VolumeGroupAction Pending State

In this state, the controller checks for the presence of the `longhornio.volume-group-action` label. If the label is not found, no further actions are taken. However, if the label exists, the controller proceed to:

- Update the runtime status (VolumeGroupAction.status.Runtime) from the (triggered or restore) steps.
- Mark the state as Pending.
  ```golang
  type VolumeGroupActionStepStatus struct {
	// The name of the action.
	Name string `json:"name"`

	// The state of the action.
	State VolumeGroupActionState `json:"state"`

	// The error message of the action.
	// +optional
	// +nullable
	Error string `json:"error,omitempty"`
  }
  ```
  ```yaml
  status:
    # The triggered action status
    triggered:
      running:
      - name: pre-backup-lock
        state: Pending
      - name: backup
        state: Pending
      - name: post-backup-lock
        state: Pending
    restored:
      last:
      - name: restore
        state: Pending
  ```

At the end of this state, controller updates VolumeGroup to the [Started state](#volumegroupaction-started-state).

##### VolumeGroupAction Started State

In this state, the controller iterates through each triggered step, and run the step action if it have not been completed. After each step is ran, the controller update the state with the result and any associated reference resources. It then returns to the queue to allow the execution of the next incompleted step.
```yaml
  status:
    triggered:
      running:
      - name: pre-backup-lock
        state: Completed
      - name: backup
        state: Completed
      - name: post-backup-lock
        state: Started
      references:
        resources:
        - items:
            backup:
            - volume-group-action-192cfc2a268b4037
            snapshot:
            - volume-group-action-25c0e4d2adac4379
            volume:
            - pvc-0948f808-4fd3-4d82-beca-7ea21dc64f7f
          kind: PersistentVolumeClaim
          name: demo-1
          namespace: default
        - items:
            backup:
            - volume-group-action-5c71b8da13144267
            snapshot:
            - volume-group-action-57f67983722a4aed
            volume:
            - pvc-a5a370e5-cfc8-4aee-8554-f0f3a50ed463
          kind: PersistentVolumeClaim
          name: demo-0
          namespace: default
    # The restored action status
    restored:
      last:
      - name: restore
        state: Pending
```

Once all the steps are completed, the runtime status (VolumeGroupAction.status.Runtime) will transition to the last status (VolumeGroupAction.status.Last) and the controller updates the VolumeGroup to the [Completed state](#volumegroup-completed-state) and the VolumeGroupAction to the [Completed state](#volumegroupaction-completed-state).

```yaml
  status:
    triggered:
      last:
      - name: pre-backup-lock
        state: Completed
      - name: backup
        state: Completed
      - name: post-backup-lock
        state: Completed
      references:
        resources:
        - items:
            backup:
            - volume-group-action-192cfc2a268b4037
            snapshot:
            - volume-group-action-25c0e4d2adac4379
            volume:
            - pvc-0948f808-4fd3-4d82-beca-7ea21dc64f7f
          kind: PersistentVolumeClaim
          name: demo-1
          namespace: default
        - items:
            backup:
            - volume-group-action-5c71b8da13144267
            snapshot:
            - volume-group-action-57f67983722a4aed
            volume:
            - pvc-a5a370e5-cfc8-4aee-8554-f0f3a50ed463
          kind: PersistentVolumeClaim
          name: demo-0
          namespace: default
    # The restored action status
    restored:
      last:
      - name: restore
        state: Pending
    state: Completed
```

##### VolumeGroupAction Restoring State

This state is similar to the [Started state](#volumegroupaction-started-state), but iterating through the restoration steps rathen then then triggered steps.

##### Error State

This state behaves similarly to the [Completed state](#volumegroupaction-completed-state).

##### VolumeGroupAction Completed State

When actions are successfully completed, this state is reached.

In this state, the controller removes the `longhornio.volume-group-action` label and record a timestamp indicating when the action was stopped.

When the runtime status (VolumeGroupAction.Status.Triggered is empty and VolumeGroupAction.Status.Stopped is empty) and the `longhornio.volume-group-action=restore` label exists, controller interprets this as an signal that the user intends to initiate the restore action. As a result, the controller updated the VolumeGroupAction to the [Pending state](#volumegroupaction-pending-state).

### Action Run

Iteracte through the resources, run the actions asynchronously and update the referenced resource if applicable.
```golang
type VolumeGroupActionReferenceResource struct {
	// The kind of the resource object.
	Kind string `json:"kind"`
	// The name of the resource object.
	Name string `json:"name"`
	// Then namespace of the resource objects.
	Namespace string `json:"namespace"`

  // A map containing the resource and its referencing resource names.
	Items map[string][]string `json:"items,omitempty"`
}
```

#### PersistentVolumeClaim

##### Backup

Perform a sequence of actions including taking a [Snapshot](#snapshot), creating a backup and record them in the resource reference (VolumeGroupAction.Status.Triggered.Reference.Resources.Items["backup"]).

##### Snapshot

Create a snapshot and record in the resource reference (VolumeGroupAction.Status.Triggered.Reference.Resources.Items["snapshot"]).

#### Pod

##### Execute

Execute command within the pod.

#### Snapshot

##### Revert

Revert to snapshots from the referenced resource (VolumeGroupAction.Status.Triggered.Reference.Resources.Items["snapshot"]).

#### Backup

##### Restore
  - create a new Volume from the referenced resource (VolumeGroupAction.Status.Triggered.Reference.Resources.Items["backup"]).
  - Wait for volume to be restored.
  - Create a new PersistentVolume (PV) for the restored Volume.
  - Create a new PersistentVolumeClaim (PVC) with original name.
  - Record the PV in resource reference (VolumeGroupAction.Status.Restored.Reference.Resources.Items["persistentVolume"]).
  - record the PVC in resource reference (VolumeGroupAction.Status.Restored.Reference.Resources.Items["persistentVolumeClaim"]).

### Test plan

`TBU`

### Upgrade strategy

`None`

## Note [optional]

`None`
