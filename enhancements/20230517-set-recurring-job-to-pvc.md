# Set RecurringJob to PersistentVolumeClaims (PVCs)

Managing recurring jobs for Longhorn Volumes is challenging for users utilizing gitops. Primary because gitops operates at the Kubernetes resource level while recurring job labeling is specific to individual Longhorn Volumes.

## Summary

This document proposes the implementation of a solution that allows configuring recurring jobs directly on PVCs.

By adopting this approach, users will have the capability to manage Volume recurring jobs through the PVCs.

### Related Issues

https://github.com/longhorn/longhorn/issues/5791

## Motivation

### Goals

1. Introduce support for enabling/disabling PVCs as a recurring job label source for the corresponding Volume.
1. The recurring job labels on PVCs are reflected on the associated Volume when the PVC is set as the recurring job label source.

### Non-goals [optional]

Sync Volume recurring job labels to PVC.

## Proposal

1. The existing behavior of recurring jobs will remain unchanged, with the Volume's recurring job labeling as the source of truth.
2. When the PVC is enabled as the recurring job label source, its recurring job labels will override all recurring job labels of the associated Volume.

### User Stories

As a user, I want to be able to set the RecurringJob label on the PVC. I expect that any updates made to the RecurringJob labels on the PVC will automatically reflect on the associated Volume.

### User Experience In Detail

To enable or disable the PVC as the recurring job label source, users can manage it by adding or removing the `recurring-job.longhorn.io/source: enable` label to the PVC.

Once the PVC is set as the recurring job label source, any recurring job labels added or removed from the PVC will be automatically synchronized by Longhorn to the associated Volume.

### API changes

`None`

## Design

### Implementation Overview

#### Sync Volume recurring job labels to PVC ####

If the PVC is labeled with `recurring-job.longhorn.io/source: enable`, the volume controller checks and updates the Volume to ensure the recurring job labels stay synchronized with the PVC by detecting recurring job label differences.

#### Remove PVC recurring job of the deleting RecurringJob ####

As of now, Longhorn includes a feature that automatically removes the Volume recurring job label associated with a deleting RecurringJob. This is also applicable to the PVC.

### Test plan

1. Update PVC recurring job label should reflect on the Volume.
1. Delete RecurringJob custom resource should delete the recurring job labels on both Volume and PVC.

### Upgrade strategy

`None`

## Note [optional]

`None`
