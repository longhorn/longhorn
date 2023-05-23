# Set RecurringJob to PersistentVolumeClaims (PVCs)

Managing recurring jobs for Longhorn Volumes is challenging for users utilizing gitops. Primary because gitops operates at the Kubernetes resource level while recurring job labeling is specific to individual Longhorn Volumes.

## Summary

This document proposes the implementation of a solution that allows configuring recurring jobs directly on PVCs.

By adopting this approach, users will have the capability to manage Volume recurring jobs through the PVCs.

### Related Issues

https://github.com/longhorn/longhorn/issues/5791

## Motivation

### Goals

1. Support recurring job labeling on PVCs and reflect on the Volume.

### Non-goals [optional]

Sync Volume recurring job labels to PVC.

## Proposal

1. The existing behavior of recurring jobs will remain unchanged, with the Volume's recurring job labeling as the source of truth.
2. If the PVC has recurring job labels, they will override all recurring job labels of the associated Volume.

### User Stories

As a user, I want to be able to set the RecurringJob label on the PVC. I expect that any updates made to the RecurringJob labels on the PVC will automatically reflect on the associated Volume.

### User Experience In Detail

Whenever a user adds or removes a recurring job label on the PVC, Longhorn synchronize with the associated Volume. This ensures that any changes made to the PVC recurring job labels are reflected in its Volume.

### API changes

`None`

## Design

### Implementation Overview

#### Sync Volume recurring job labels to PVC ####

The volume controller checks and updates the Volume to ensure the recurring job labels stay synchronized with the PVC by detecting recurring job label differences.

### Test plan

1. Update PVC recurring job label should reflect on the Volume.
1. Delete RecurringJob custom resource should delete the recurring job labels on both Volume and PVC.

### Upgrade strategy

`None`

## Note [optional]

`None`
