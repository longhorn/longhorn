# Consolidate Volume Attach/Detach Implementation

## Summary

There are several cases related to (auto) volume attach/detach, right now we leverage the volume attributes to achieve that, but it's better to introduce a new resource (longhorn volumeattachement) to have complete context for each scenario.


### Related Issues

https://github.com/longhorn/longhorn/issues/3715

## Motivation

### Goals

Introduce a new resource (Longhorn volumeattachement) to cover the following scenarios for Longhorn volume's AD:
1. Traditional CSI attachment (pod -> csi-attacher -> Longhorn API)
1. Traditional UI attachment (Longhorn UI -> Longhorn API)
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

#### Story 1

Before this feature there are race conditions between Longhorn auto-reattachment logic and CSI volume attachment that sometimes
result in the volume CR in a weird state that volume controller can nerve resolve. Ref https://github.com/longhorn/longhorn/issues/2527#issuecomment-966597537

After this feature, the race condition should not exist 

#### Story 2

Before this feature, the user cannot take a CSI snapshot for detached Longhorn volume.

After this feature, user should be able to do so 

Ref: https://github.com/longhorn/longhorn/issues/3726


#### Story 3
Make the attaching/detaching more resilient and transparent.

User will see clearly who is requesting the volume to be attached in the AD ticket. 
Also, volume controller will be able to reconcile the volume in any combination value of (volume.Spec.NodeID, volume.Status.CurrentNodeID, and
volume.Status.State). See the [volume-controller-ad-logic](./assets/images/longhorn-volumeattachment/volume-controller-ad-logic.png)

## Design & Implementation Overview

1. Create a new CRD called VolumeAttachment with the following structure:
```go
type AttachmentTicket struct {
	// The unique ID of this attachment. Used to differentiate different attachments of the same volume.
	// +optional
	ID string `json:"id"`
	// +optional
	Type AttacherType `json:"type"`
	// The node that this attachment is requesting
	// +optional
	NodeID string `json:"nodeID"`
	// Optional additional parameter for this attachment
	// +optional
	Parameters map[string]string `json:"parameters"`
	// A sequence number representing a specific generation of the desired state.
	// Populated by the system. Read-only.
	// +optional
	Generation int64 `json:"generation"`
}

type AttachmentTicketStatus struct {
	// The unique ID of this attachment. Used to differentiate different attachments of the same volume.
	// +optional
	ID string `json:"id"`
	// Indicate whether this attachment ticket has been satisfied
	Satisfied bool `json:"satisfied"`
	// Record any error when trying to fulfill this attachment
	// +nullable
	Conditions []Condition `json:"conditions"`
	// A sequence number representing a specific generation of the desired state.
	// Populated by the system. Read-only.
	// +optional
	Generation int64 `json:"generation"`
}

type AttacherType string

const (
	AttacherTypeCSIAttacher                      = AttacherType("csi-attacher")
	AttacherTypeLonghornAPI                      = AttacherType("longhorn-api")
	AttacherTypeSnapshotController               = AttacherType("snapshot-controller")
	AttacherTypeBackupController                 = AttacherType("backup-controller")
	AttacherTypeVolumeCloneController            = AttacherType("volume-clone-controller")
	AttacherTypeSalvageController                = AttacherType("salvage-controller")
	AttacherTypeShareManagerController           = AttacherType("share-manager-controller")
	AttacherTypeVolumeRestoreController          = AttacherType("volume-restore-controller")
	AttacherTypeVolumeEvictionController         = AttacherType("volume-eviction-controller")
	AttacherTypeVolumeExpansionController        = AttacherType("volume-expansion-controller")
	AttacherTypeBackingImageDataSourceController = AttacherType("bim-ds-controller")
	AttacherTypeVolumeRebuildingController       = AttacherType("volume-rebuilding-controller")
)

const (
	AttacherPriorityLevelVolumeRestoreController          = 2000
	AttacherPriorityLevelVolumeExpansionController        = 2000
	AttacherPriorityLevelLonghornAPI                      = 1000
	AttacherPriorityLevelCSIAttacher                      = 900
	AttacherPriorityLevelSalvageController                = 900
	AttacherPriorityLevelShareManagerController           = 900
	AttacherPriorityLevelSnapshotController               = 800
	AttacherPriorityLevelBackupController                 = 800
	AttacherPriorityLevelVolumeCloneController            = 800
	AttacherPriorityLevelVolumeEvictionController         = 800
	AttacherPriorityLevelBackingImageDataSourceController = 800
	AttachedPriorityLevelVolumeRebuildingController       = 800
)

const (
	TrueValue  = "true"
	FalseValue = "false"
	AnyValue   = "any"

	AttachmentParameterDisableFrontend = "disableFrontend"
	AttachmentParameterLastAttachedBy  = "lastAttachedBy"
)

const (
	AttachmentStatusConditionTypeSatisfied = "Satisfied"

	AttachmentStatusConditionReasonAttachedWithIncompatibleParameters = "AttachedWithIncompatibleParameters"
)

// VolumeAttachmentSpec defines the desired state of Longhorn VolumeAttachment
type VolumeAttachmentSpec struct {
	// +optional
	AttachmentTickets map[string]*AttachmentTicket `json:"attachmentTickets"`
	// The name of Longhorn volume of this VolumeAttachment
	Volume string `json:"volume"`
}

// VolumeAttachmentStatus defines the observed state of Longhorn VolumeAttachment
type VolumeAttachmentStatus struct {
	// +optional
	AttachmentTicketStatuses map[string]*AttachmentTicketStatus `json:"attachmentTicketStatuses"`
}

// VolumeAttachment stores attachment information of a Longhorn volume
type VolumeAttachment struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   VolumeAttachmentSpec   `json:"spec,omitempty"`
	Status VolumeAttachmentStatus `json:"status,omitempty"`
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
   1. When AD controller sees a newly created ticket in `VolumeAttachment.Spec.AttachmentTickets` object.
      1. If `volume.Spec.NodeID` is non-empty
         1. Do nothing. It will wait for the volume to be fully detached first before setting `volume.Spec.NodeID` 
      1. If `volume.Spec.NodeID` is empty
         1. Wait for `volume.Status.State` to be `detached`
         1. Then select an attachment ticket from `va.Spec.AttachmentTickets` based on priority level
            of the tickets. If 2 ticket has same priority, select the ticket with shorter name.
         2. Set the `vol.Spec.NodeID = attachmentTicket.NodeID` to attach the volume
   1. When AD controller check the list of tickets in `VolumeAttachment.Spec.AttachmentTickets`.
      If no ticket is requesting the `volume.Spec.NodeID`, Ad controller set `volume.Spec.NodeID` to empty
   1. AD controller watch volume CR and set ticket status accordingly in the `va.Status.AttachmentTicketStatuses` 
   1. If the VolumeAttachment object is pending deletion,
      There is no special resource need to be cleanup, directly remove the finalizer for the VolumeAttachment

> Note that the priority of ticket is determine in the order: volume data restoring > user workload > snapshot/backup operations

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

1. Traditional UI attachment (Longhorn UI -> Longhorn API)
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

   We create a new controller to check if the volume is faulted and detach the volume for detach.
   After the volume is auto detach and replica is auto-salvaged by the volume controller, the AD 
   controller will check the VolumeAttachment object and reattach the volume to the correct node
   
   With this design, we no longer need the volume.Status.PendingNodeID which was the source of some 
   race conditions

1. Refactor RWX mechanism's volume attachment/detachment (in share manager lifecycle)

   Each pod that use the RWX volume will directly request a CSI ticket.
   The share-manager controller watch the csi ticket and create share-manager ticket
   when there are one or more csi ticket exist.
   
   Then AD controller will attach the volume to the node that is being requested by share-manager
   ticket. AD controller ignore the CSI ticket for RWX volume.

### API changes

We are adding new APIs to operate on Snapshot CRD directly
```go
"snapshotCRCreate": s.SnapshotCRCreate,
"snapshotCRList":   s.SnapshotCRList,
"snapshotCRGet":    s.SnapshotCRGet,
"snapshotCRDelete": s.SnapshotCRDelete,
```

### Test plan

Refer to the test plan https://github.com/longhorn/longhorn/issues/3715#issuecomment-1563637861

### Upgrade strategy

In the upgrade path, list all volume and create VolumeAttachment for the them.
For the volume that currently being used by CSI workload/Longhorn UI we create CSI ticket/Longhorn UI ticket to keep them being attached

