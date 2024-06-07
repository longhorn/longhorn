# Pre-Pull Images

## Summary

We will pre-pull the share-manager and instance-manager images on every worker node to speed up the startup of share-managers and instance-managers.

### Related Issues

https://github.com/longhorn/longhorn/issues/8376

## Motivation

### Goals

- Pre-pull the share-manager image on all worker nodes.
- Pre-pull the instance-manager image on all worker nodes.

### Non-goals [optional]

- Not convert the `EngineImage` to the `Image`.

## Proposal

- A DaemonSet to pre-pull images
- A global setting `start-pre-pull-manager-images`. Users can determine whether or not pre-pulling images. Default is `true`.

### User Stories

With the pre-pull images mechanism, users can deploy RWX volume and start to use volumes faster. It's also useful for [Share manager HA mechanism](https://github.com/longhorn/longhorn/issues/6205).

There is the [garbage collection of unused containers and images feature](https://kubernetes.io/docs/concepts/architecture/garbage-collection/#containers-images) of kubernetes. The `kubelet` performs garbage collection on unused images every two minutes and on unused containers every minute so the image controller will keep the DaemonSet to prevent the pre-pull images from being deleted by the garbage collection of unused containers and images.

#### Story 1: Users don not want pre-pull images

If users do not use RWX volumes, it will be unnecessary to pull the share manager image and occupy the disk usage.

- Users can set the global setting `start-pre-pull-manager-images` false to stop pre-pulling share/instance manager images. The pre-pulling images DaemonSets will then be deleted.

### User Experience In Detail

Users can edit this global setting by Longhorn UI or the `kubectl edit` command.
Example:
```bash
~# kubectl -n longhorn-system edit setting start-pre-pull-manager-images
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  ...
  name: start-pre-pull-manager-images
  namespace: longhorn-system
...
value: "true"
```

### API changes

`None`

## Design

### Implementation Overview

- New custom resource definition `Image`:

  ```golang
  type ImageState string

  ImageStateDeploying = ImageState("deploying")
  ImageStateDeployed  = ImageState("deployed")
  ImageStateError     = ImageState("error")
  ImageStateUnknown   = ImageState("unknown")

  // ImageSpec defines the desired state of the Longhorn image
  type ImageSpec struct {
    // ImageURL indicates the image URL.
    ImageURL string `json:"instanceManagerImage"`
  }

  // ImageStatus defines the observed state of the Longhorn image
  type ImageStatus struct {
    // OwnerID indicates the controller node that handles the image.
    OwnerID string `json:"ownerID"`
    // State indicates the Image state.
    State ImageState `json:"state"`
    // NodeDeploymentMap indicates the nodes that the image has been deployed on.
    NodeDeploymentMap map[string]bool `json:"nodeDeploymentMap"`
  }

  // Image is where Longhorn stores image objects.
  type Image struct {
    Spec   ImageSpec   `json:"spec,omitempty"`
    Status ImageStatus `json:"status,omitempty"`
  }
  ```

  - `ImageState`:
    - `ImageState` will be `ImageStateDeploying: deloying` when creating the DaemonSet. It will become `ImageStateDeployed: deployed` until the image controller detects that all worker nodes have the containers of the pod ready.
    - `ImageStateUnknown` will be used when users set the global setting `start-pre-pull-manager-images` false.

  - `NodeDeploymentMap` only synchronizes the containers status of the DaemonSet pod of the image; therefore, it can not detect if the share/instance manager images are deleted for some reason.
    - Add `KubeNodeInformer.AddEventHandlerWithResyncPeriod` in the image controller to handle cases where share/instance manager images deleted on nodes.
    - Add `SettingInformer.AddEventHandlerWithResyncPeriod` in the image controller to handle cases where the setting `start-pre-pull-manager-images` is changed.

- New controller that handles the resource `Image`:

  ```golang
  NewImageController(...) (*ImageController, error) { // others image URLs
    ic := &ImageController{
      baseController: newBaseController("longhorn-image", logger),

      namespace:      namespace,
      controllerID:   controllerID,
      serviceAccount: serviceAccount,

      ...,
    }

    // add ImageInformer.AddEventHandlerWithResyncPeriod
    // add SettingInformer.AddEventHandlerWithResyncPeriod
    // add KubeNodeInformer.AddEventHandlerWithResyncPeriod
    ...

    return ic, nil
  }

  syncImage(imageName string) error {
    // Check image owner
    ...
    // Check the global setting `start-pre-pull-manager-images`
    ...
    // Get the image DaemonSet and create the DaemonSet if not found or update the DaemonSet if the instance/share manager image URLs are upgraded.
      // A pod with containers in the DaemonSet to pull the instance and share manager images.
    ...
    // Synchronize the nodes map with images deployed on the nodes.
    ...
    // Keep the image DaemonSet around after the image state is `deployed`.
  }
  ```

### Test plan

1. Fresh install:
   1. The `Image` resources are created.
   2. An image DaemonSet for pulling share and instance manager images is created.
   3. The `Image` resources states are `deploying`.
   4. All pods of the image DaemonSet for share and instance managers are created and ready on worker nodes.
   5. The `Image` resources states are `deployed`.
2. Upgrade Longhorn:
   1. The old `Image` resources are deleted and the `Image` resources are created.
   2. An image DaemonSet for pulling share and instance manager images is re-created.
   3. The `Image` resources states are `deploying`.
   4. All pods of the image DaemonSet for new share and instance managers are created and ready on worker nodes.
   5. The `Image` resources states are `deployed`.

### Upgrade strategy

1. Delete old `Image` resources.
2. Create new `Image` resources with new instance and share manager image URLs and the image controller will update the DaemonSet to start to pre-pull the images.

## Note [optional]

`None`
