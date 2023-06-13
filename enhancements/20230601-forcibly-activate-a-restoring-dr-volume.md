# Forcibly Activate A Restoring/DR Volume

## Summary

When users try to activate a restoring/DR volume with some replicas failed for some reasons, the volume will be stuck in attaching state and users can not do anything except deleting the volume. However the volume still can be rebuilt back to be normal as long as there is a healthy replica.

To improve user experience, Longhorn should forcibly activate a restoring/DR volume if there is a healthy replica and users allow the creation of a degraded volume.
### Related Issues

https://github.com/longhorn/longhorn/issues/1512

## Motivation

### Goals

Allow users to activate a restoring/DR volume as long as there is a healthy replica and the volume works well.

### Non-goals [optional]

`None`

## Proposal

Forcibly activate a restoring/DR volume if there is a healthy replica and users enable the global setting `allow-volume-creation-with-degraded-availability`.

### User Stories

Users can activate a restoring/DR volume by the CLI `kubectl` or Longhorn UI and the volume could work well.

### User Experience In Detail

#### Prerequisites

Set up two Kubernetes clusters. These will be called cluster A and cluster B. Install Longhorn on both clusters, and set the same backup target on both clusters.

1. In the cluster A, make sure the original volume X has a backup created or has recurring backups scheduled.
2. In backup page of cluster B, choose the backup volume X, then create disaster recovery volume Y.

#### Kubectl

User set `volume.spec.Standby` to `false` by editing the volume CR or the manifest creating the volume to activate the volume.

#### Longhorn UI

UI has click `Activate Disaster Recovery Volume` button in `Volume` or `Volume Details` pages to activate the volume.

### API changes

`None`

## Design

### Implementation Overview

1. Check if `volume.Spec.Standby` is set to `false`
2. Get the global setting `allow-volume-creation-with-degraded-availability`
3. Activate the DR volume if `allow-volume-creation-with-degraded-availability` is set to `true` and there are one or more ready replicas.

### Test plan

#### Test Forcibly Activated A Restoring/DR Volume

1. Create a DR volume
2. Set the global setting `concurrent-replica-rebuild-per-node-limit` to be 0
3. Failed some replicas
4. Check if there is at least one healthy replica
5. Call the API `activate`
6. The volume could be activated
7. Attach the volume to a node and check if data is correct

### Upgrade strategy

`None`

## Note [optional]

`None`
