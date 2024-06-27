# Pre-Pull Images

## Summary

We will pre-pull the share-manager image on every worker node to speed up the startup of share-managers.

### Related Issues

https://github.com/longhorn/longhorn/issues/8376

## Motivation

### Goals

- Pre-pull the share-manager image on all worker nodes.

### Non-goals [optional]

`None`

## Proposal

- Sidecar containers in the `longhorn-manager` DaemonSet to pre-pull images

### User Stories

With the pre-pull images mechanism, users can deploy RWX volume and start to use volumes faster. It's also useful for [Share manager HA mechanism](https://github.com/longhorn/longhorn/issues/6205).

There is the [garbage collection of unused containers and images feature](https://kubernetes.io/docs/concepts/architecture/garbage-collection/#containers-images) of kubernetes. The `kubelet` performs garbage collection on unused images every 2~5 minutes and on unused containers every minute so we have sidecar containers in the `longhorn-manager` DaemonSet to prevent the pre-pull images from being deleted by the garbage collection of unused containers and images.

### API changes

`None`

## Design

### Implementation Overview

- Add containers in the `longhorn-manager` DaemonSet:

  ```yaml
  spec:
    containers:
    - name: longhorn-manager
      ...
    - name: pre-pull-share-manager-image
        imagePullPolicy: IfNotPresent
        image: longhornio/longhorn-share-manager:master-head
        command: ["sh", "-c", "echo longhorn-share-manager image pulled && sleep infinity"]
  ```

### Test plan

- Fresh install/Upgrade:
  - After install or upgrade, the share-manager image are pulled on the each worker node.

### Upgrade strategy

`None`

## Note [optional]

`None`
