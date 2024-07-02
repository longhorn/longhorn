# Share Manager Scheduling

## Summary

In the Longhorn storage system, a share manager pod of an RWX volume is created on a random node, without the ability for users to specify a preferred locality. The purpose of this feature is to enhance the locality of an RWX volume and its share manager pod.

### Related Issues

https://github.com/longhorn/longhorn/issues/7872
https://github.com/longhorn/longhorn/issues/4863
https://github.com/longhorn/longhorn/issues/8255
https://github.com/longhorn/longhorn/issues/2335

## Motivation

### Goals

- Share manager pod respects the node selector specified in `storageClass.parameters["shareManagerNodeSelector"]`
- Share manager pod complies with the affinity rules defined in `storageClass.allowedTopologies`
- Share manager pod respects the newly introduced `storageClass.Parameters["shareManagerTolerations"]`

### Non-goals [optional]

`None`

## Proposal

### User Stories

A share manager pod of an RWX volume is unable to adhere to the specified node selector and affinity rules, leading to potential inefficiencies and performance issues. The feature aims to enhance this by ensuring share manager pods can be scheduled according to the given node selector and affinity rules.

### User Experience In Detail

The introduction of node selector and affinity rule capabilities in a storage class significantly enhances user control over the scheduling of share manager pods for RWX volumes.

- Node Selector:
  Users can define node selectors directly within the storage class configuration by setting `storageClass.parameters["shareManagerNodeSelector"]`. When a share manager pod is to be scheduled, Kubernetes evaluates the node selectors specified by the user. The scheduler then ensures that the pod is placed only on nodes that match all of the specified labels. This mechanism provides a straightforward way to guide pod placement towards nodes that meet certain criteria, such as hardware capabilities, geographical location, or any other user-defined characteristic.

- Allowed Topologies:
  Users can set specific rules for where share manager pods should go in the cluster by using `storageClass.allowedTopologies`. This setting is turned into affinity rules which are applied to a share manager pod. The affinity helps decide which nodes the pod can be placed on, based on the labels of those nodes.

- Tolerations:
  Users can define tolerations for share manager pods within the storage class by setting storageClass.parameters["shareManagerTolerations"]. These tolerations allow share manager pods to be scheduled on nodes with matching taints.

### API changes

`None`

## Design

### Implementation Overview

When the share manager controller is in the process of reconciling a share manager, it attempts to search the associated storage class from the `persistentVolume.spec.StorageClassName`. If the storage class is nonexistent, node selectors and allowed topologies will also be absent, leading to a neglect of the share manager pod's locality.

If the associated storage class is present, the system reads `storageClass.parameters["shareManagerNodeSelector"]` and `storageClass.allowedTopologies`. The node selectors specified in `storageClass.parameters["shareManagerNodeSelector"]` are combined with the global selectors from system-managed-components-node-selector and are applied to the share manager pod. Additionally, the system translates the `storageClass.allowedTopologies` into affinity rules, which are then applied to the configuration of the share manager pod as well.

For tolerations, users are able to to specify these in the storage class through `storageClass.parameters["shareManagerTolerations"]`. These specified tolerations are combined with global tolerations defined under the global setting `taint-toleration`, enabling share manager pods to be allocated to nodes that have compatible taints.

Once the share manager pod is allocated to a suitable node, the node's name is set to the volume attachment ticket.

### Test plan

1. Test RWX volumes from a storage class with `parameters["shareManagerNodeSelector"]`.
1. Test RWX volumes from a storage class with `storageClass.allowedTopologies`.
1. Test RWX volumes from a storage class with `storageClass.Parameters["shareManagerTolerations"]`.