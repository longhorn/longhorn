# Consolidate Volume Attach/Detach Implementation

## Summary

There are several cases related to (auto) volume attach/detach, right now we leverage the volume attributes to achieve that, but it's better to introduce a new resource (longhorn volumeattachement) to have complete context for each scenario.


### Related Issues

https://github.com/longhorn/longhorn/issues/3715

## Motivation

### Goals

Introduce a new resource (Longhorn volumeattachement) to cover the following scenarios for Longhorn volume's AD:
1. Traditional CSI attachment (pod -> csi-attacher -> Longhorn API)
1. Tradditional UI attachment (Longhorn UI -> Longhorn API)
1. Auto attach/detach volume for K8s CSI snapshot
1. Auto attach/detach volume for recurring jobs
1. Auto attach/detach volume for volume cloning 
1. Auto attach/detach volume for auto salvage feature
1. Refactor RWX mechanism's volume attachment/detachment (in share manager lifecycle)
1. Volume live migration
1. Consider how to upgrade from previous Longhorn version which doesn't have VA resource yet

### Non-goals [optional]

NA

## Proposal

This is where we get down to the nitty-gritty of what the proposal actually is.

### User Stories
Detail the things that people will be able to do if this enhancement is implemented. A good practice is including a comparison of what the user cannot do before the enhancement is implemented, why the user would want an enhancement, and what the user needs to do after, to make it clear why the enhancement is beneficial to the user.

The experience details should be in the `User Experience In Detail` later.

#### Story 1
#### Story 2

### User Experience In Detail

1. Create a new CRD called VolumeAttachment with the following structure:
```go

type Attacher struct {
	// The node ID on which the controller is responsible to reconcile this orphan CR.
	// +optional
	ID   string       `json:"id"`
	Type AttacherType `json:"type"`
}

type AttacherType string

const (
	AttacherTypeCSIAttacher             = AttacherType("csi-attacher")
	AttacherTypeLonghornAPI             = AttacherType("longhorn-api")
	AttacherTypeSnapshotController      = AttacherType("snapshot-controller")
	AttacherTypeBackupController        = AttacherType("backup-controller")
	AttacherTypeCloningController       = AttacherType("cloning-controller")
	AttacherTypeSalvageController       = AttacherType("salvage-controller")
	AttacherTypeShareManagerController  = AttacherType("share-manager-controller")
	AttacherTypeLiveMigrationController = AttacherType("live-migration-controller")
	AttacherTypeLonghornUpgrader        = AttacherType("longhorn-upgrader")
)

const (
	AttacherPriorityLevelLonghornAPI             = 1000
	AttacherPriorityLevelCSIAttacher             = 900
	AttacherPriorityLevelSalvageController       = 900
	AttacherPriorityLevelShareManagerController  = 900
	AttacherPriorityLevelLonghornUpgrader        = 900
	AttacherPriorityLevelLiveMigrationController = 800
	AttacherPriorityLevelSnapshotController      = 800
	AttacherPriorityLevelBackupController        = 800
	AttacherPriorityLevelCloningController       = 800
)

// VolumeAttachmentSpec defines the desired state of Longhorn VolumeAttachment
type VolumeAttachmentSpec struct {
	Attachers map[AttacherType]map[string]Attacher `json:"attachers"`
	Volume    string                               `json:"volume"`
	NodeID    string                               `json:"nodeID"`
}

// SnapshotStatus defines the observed state of Longhorn Snapshot
type VolumeAttachmentStatus struct {
	// +optional
	Attached    bool         `json:"attached"`
	AttachError *VolumeError `json:"attachError,omitempty"`
	DetachError *VolumeError `json:"detachError,omitempty"`
}

// VolumeError captures an error encountered during a volume operation.
type VolumeError struct {
	// Time the error was encountered.
	// +optional
	Time metav1.Time `json:"time,omitempty"`

	// String detailing the error encountered during Attach or Detach operation.
	// This string may be logged, so it should not contain sensitive
	// information.
	// +optional
	Message string `json:"message,omitempty"`
}

```
1. Modify volume controller
   1. Repurpose the field `volume.Status.CurrentNodeID` so that `volume.Status.CurrentNodeID` is only set once we are 
   fully attached and is only unset once we are fully detached. 
   See this state flow for full detail: [volume-controller-ad-logic](./assets/images/longhorn-volumeattachment/volume-controller-ad-logic.png)
   2. Deprecate `volume.Status.PendingNodeID` and the auto-salvage logic. We will have a dedicated `salvage-controller` as describe 
   in the below section.
1. Create a controller, VolumeAttachment controller (AD controller).
This controller watches the VolumeAttachment objects of a volume.
   1. When AD controller sees a newly created VolumeAttachment object.
      1. If `volume.Spec.NodeID` is non-empty
         1. If `volumeAttachment.Spec.NodeID` != `volume.Spec.NodeID`, set an error in `volumeAttachment.Status.AttachError`
         indicating that the volume is already attached to a different node.
         1. If `volumeAttachment.Spec.NodeID` == `volume.Spec.NodeID` and `volume.Status.State` is `attached`, clear the error `volumeAttachment.Status.AttachError`
         if needed and set `volumeAttachment.Status.Attached` to `true`
      1. If `volume.Spec.NodeID` is empty
         1. Wait for `volume.Status.State` to be `detached`
         1. Then set `volume.Spec.NodeID` to be `volumeAttachment.Spec.NodeID`.
         1. Then wait for `volume.Status.State` to be `attached`
         1. Then set `volumeAttachment.Status.Attached` to `true`
   1. If the VolumeAttachment object is pending deletion,
      1. If `volumeAttachment.Spec.NodeID` == `volume.Spec.NodeID`.
      AD controller try to unset `volume.Spec.NodeID` to trigger volume detachment.
      Then AD controller waits for the `volume.Status.State` to become detached. 
      Then AD controller sets `volumeAttachment.Status.Attached` to `false`.
      Finally, remove the `longhorn.io` finalizer to allow the deletion.
      1. If `volumeAttachment.Spec.NodeID` != `volume.Spec.NodeID`.
      AD controller sets `volumeAttachment.Status.Attached` to `false`.
      Finally, remove the `longhorn.io` finalizer to allow the deletion.
   1. If there are multiple VolumeAttachment objects of the same volume (with different `volumeAttachment.Spec.NodeID`),
   calculate the max(AttacherPriorityLevel) of attachers for each VolumeAttachment.
   Give higher priority for the VolumeAttachment object with bigger max(AttacherPriorityLevel).
   The other VolumeAttachment object will be stuck with `volumeAttachment.Status.Attached: false` and error in `volumeAttachment.Status.AttachError`
   indicating that there is a higher priority VolumeAttachment object.

1. Traditional CSI attachment (pod -> csi-attacher -> Longhorn API)
   1. csi-attacher send attaching request to longhorn-csi-plugin
   1. longhorn-csi-plugin sends attaching request to longhorn-manager with pod-id and attacherType `csi-attacher`
   1. longhorn manager create a VolumeAttachment object with this spec:
      ```yaml
      metadata:
         finalizers:
            - longhorn.io
         labels:
            longhornvolume: <volume-name>
            nodeID: <node-name>
      spec:
         attachers:
            csi-attacher:
               <pod-id>: 
                  id: <pod-id>
                  type: "csi-attacher"
         volume: <volume-name>
         nodeID: <node-name>
      status:
         attached: false
      ```
   1. longhorn-csi-plugin watch the `volumeAttachment.Status.Attached` and `volumeAttachment.Status.AttachError`
   and return corresponding respond to csi-attacher

1. Tradditional UI attachment (Longhorn UI -> Longhorn API)
   1. Longhorn UI send attaching request to longhorn-manager with attacherType `longhorn-api`
   1. longhorn manager create a VolumeAttachment object with this spec:
      ```yaml
      metadata:
         finalizers:
            - longhorn.io
         labels:
            longhornvolume: <volume-name>
            nodeID: <node-name>
      spec:
         attachers:
            longhorn-api:
               "": 
                  id: ""
                  type: "longhorn-api"
         volume: <volume-name>
         nodeID: <node-name>
      status:
         attached: false
      ```
   1. Longhorn UI watches the `volumeAttachment.Status.Attached` and `volumeAttachment.Status.AttachError`
      and display the correct message
1. Auto attach/detach volume Longhorn snapshot
   1. Snapshot controller watches the new Longhorn snapshot CR.
      If the snapshot CR request a new snapshot,
      snapshot controller create a new VolumeAttachment object with the content:
      ```yaml
      metadata:
         finalizers:
            - longhorn.io
         labels:
            longhornvolume: <volume-name>
            nodeID: <node-name>
      spec:
         attachers:
            snapshot-controller:
               <snapshot-name>: 
                  id: <snapshot-name>
                  type: "snapshot-controller"
         volume: <volume-name>
         nodeID: <node-name>
      status:
         attached: false
      ```
   1. Snapshot controller wait for volume to be attached and take the snapshot
1. Auto attach/detach volume Longhorn backup
   1. Backup controller watches the new Longhorn backup CR.
      If the backup CR request a new backup,
      backup controller create a new VolumeAttachment object with the content:
      ```yaml
      metadata:
         finalizers:
            - longhorn.io
         labels:
            longhornvolume: <volume-name>
            nodeID: <node-name>
      spec:
         attachers:
            backup-controller:
               <backup-name>: 
                  id: <backup-name>
                  type: "backup-controller"
         volume: <volume-name>
         nodeID: <node-name>
      status:
         attached: false
      ```
   1. Backup controller wait for volume to be attached and take the backup
1. Auto attach/detach volume for K8s CSI snapshot
   1. csi-snappshotter send a request to longhorn-csi-plugin to with snapshot name and volume name
   1. longhorn-csi-plugin send snapshot request to Longhorn manager
   1. Longhorn manager create a snapshot CR
   1. longhorn-csi-plugin watches different snapshot CR status and respond to csi-snapshotter
1. Auto attach/detach volume for recurring jobs
   1. recurring job deploys backup/snapshot CR
   1. recurring job watch the status of backup/snapshot CR for the completion of the operation
1. Auto attach/detach volume for volume cloning
   1. Create a new controller: cloning-controller
   1. This controller will watch new volume that need to be cloned
   1. For a volume that needs to be cloned, cloning controller deploy a VolumeAttachment for both target volume and old volume:
      ```yaml
      # target volume
      metadata:
         finalizers:
            - longhorn.io
         labels:
            longhornvolume: <target-volume-name>
            nodeID: <node-name>
      spec:
         attachers:
            cloning-controller:
               <target-volume-name>: 
                  id: <target-volume-name>
                  type: "cloning-controller"
         volume: <target-volume-name>
         nodeID: <node-name>
      status:
         attached: false
      
      # source volume
      metadata:
         finalizers:
            - longhorn.io
         labels:
            longhornvolume: <source-volume-name>
            nodeID: <node-name>
      spec:
         attachers:
            cloning-controller:
               <target-volume-name>: 
                  id: <target-volume-name>
                  type: "cloning-controller"
         volume: <source-volume-name>
         nodeID: <node-name>
      status:
         attached: false
      ```
      1. Cloning controller watch for the cloning status and delete the VolumeAttachment upon completed   
1. Auto attach/detach volume for auto salvage feature
TODO
1. Refactor RWX mechanism's volume attachment/detachment (in share manager lifecycle)
TODO
1. Volume live migration
TODO
1. Consider how to upgrade from previous Longhorn version which doesn't have VA resource yet
TODO


Detail what the user needs to do to use this enhancement. Include as much detail as possible so that people can understand the "how" of the system. The goal here is to make this feel real for users without getting bogged down.

### API changes

## Design

Introducing a new VolumeAttachment resource as the 

### Implementation Overview

Overview of how the enhancement will be implemented.

### Test plan

Integration test plan.

For engine enhancement, also requires engine integration test plan.

### Upgrade strategy

Anything that requires if the user wants to upgrade to this enhancement.

## Note [optional]

Additional notes.
