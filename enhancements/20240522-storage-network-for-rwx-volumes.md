# Storage Network For Read-Write-Many (RWX) Volume

## Summary

This proposal outlines extending Longhorn's storage network feature to support Read-Write-Many (RWX) volumes. Having graduated from experimental status, RWX volumes should now be able to use storage network for data traffic, similar to Read-Write-Once (RWO) volumes. The enhancement enables data network isolation and potentially improve performance in specific network configuration that utilize storage network.

### Related Issues

https://github.com/longhorn/longhorn/issues/8184

## Motivation

### Goals

Enable users to utilize a dedicated network interface for RWX volume data traffic with Multus, similar to Read-Write-Once (RWO) volumes. This provides data network isolation and possibly can enhance performance in specific configurations.

### Non-goals [optional]

- This proposal does not involve performance evaluation of RWX volumes between storage networks and cluster networks.

## Proposal

### User Stories

#### Story 1: RWX Volume Data Network Segregation

As a Longhorn user, I want to use a dedicated network interface for RWX volume data traffic.

- Before: Data network segregation was unavailable for RWX volumes. The data network segregation only works in the RWO volumes, and the data traffic between the mount point (client) and the share manager pod still goes through the cluster network.
- After: User can use the storage network for RWX volumes, enabling network segregation.

#### Story 2: Pre-existing and New RWX Volume Workload

As a Longhorn user, I have storage network configured, and existing RWX volume workload before the v1.7.0 upgrade.

- Pre-existing Workloads: There will be no disruption to pre-existing RWX volume workload pods since NFS mount point remains accessible in the host network namespace.
- New Workloads: Newley created RWX volume workloads will be applied with the storage network.

### User Experience In Detail

Users will be able to create RWX volumes that uses the storage network for data traffic. Key user-facing changes include:

- **CSI Annotations:** Share manager pods and CSI plugin pods will be annotated with the storage network for NFS client mounting. This annotation will only be applied once all volumes have been detached.
- **Headless Service:** RWX volume will use a headless service and a custom endpoint, removing dependency on ClusterIP, which is not suitable for Multus networking.
- **Custom Mounter Replacement:** The custom mounter uses `hostPID` and host `proc` namespace will be replaced with running the CSI plugin with `hostNetwork: true`.
- **Workload Pod Restart:** When a CSI plugin pod restarts, the NFS share mountpoint becomes unavailable, rendering any attempt to access it unresponsive. User can manually restart the workload pod, or they can enable the `auto-delete-pod-when-volume-detached-unexpectedly` setting. This allows Longhorn to delete the associated workload pod when it is using the storage-network. If the pod is managed by a controller, the kubelet will create a new pod. This allows the CSI controller to handle volume remounting through the CSI node server.
- **Upgrade to Longhorn v1.7.0:** If the storage network is configured before the upgrade, the CSI plugin pod will be annotated accordingly. The **Workload Pod Restart** does not apply to pre-existing RWX volume workload pods after upgrading to Longhorn v1.7.0, as the NFS share mountpoint remains accessible in the host network namespace.

### API changes

No API changes are required for this proposal.

## Design

### CNI Annotation

Introduce CSI annotation for RWX volume pod stack to enable NFS client mounting over the storage network:
	- Share manager pod
	- CSI plugin pod

The setting controller will apply these annotations once all volumes are detached.

### Service

Currently, Longhorn creates a share manager service auto-assigned with a cluster IP by the selector. The cluster IP is used for the share manager endpoint.

However, the service selector is unaware of the Multus networking when the storage network is configured. Hence, for the RWX volumes, Longhorn will create a headless service and custom endpoint for the RWX volume resource stack.

```golang
// Service
service.Spec.ClusterIP = "None"
```
```golang
// Endpoint
	newObj := &corev1.Endpoints{
		ObjectMeta: metav1.ObjectMeta{
			Name:            sm.Name,
			Namespace:       sm.Namespace,
			OwnerReferences: datastore.GetOwnerReferencesForShareManager(sm, false),
			Labels:          labels,
		},
		Subsets: []corev1.EndpointSubset{},
	}
```

The share manager will use the service FQDN for its endpoint instead of the value from service `ClusterIP` field.

```yaml
endpoint: nfs://pvc-117d3553-1a2c-4b42-aa49-2b221dfb5cd9.longhorn-system.svc.cluster.local/pvc-117d3553-1a2c-4b42-aa49-2b221dfb5cd9
```

### Kubernetes Endpoint Controller

Introduce a new Kubernetes Endpoint controller to watch over share manager pod resources during *Add* and *Update* operations to sync the share manager details with the endpoint subset.

```golang
		desireSubset := corev1.EndpointSubset{
			Addresses: []corev1.EndpointAddress{
				{
					IP:       storageIP,
					NodeName: &pod.Spec.NodeName,
					TargetRef: &corev1.ObjectReference{
						Kind:      types.KubernetesKindPod,
						Name:      pod.Name,
						Namespace: pod.Namespace,
						UID:       pod.UID,
					},
				},
			},
			Ports: []corev1.EndpointPort{
				{
					Name:     "nfs",
					Port:     2049,
					Protocol: corev1.ProtocolTCP,
				},
			},
		}
```

### Share Manager Process Namespaces

Currently, the CSI plugin pod uses `HostPID` and mounts the host `proc` directory to be used by the custom mounter. This custom mounter wraps the commands (e.g., mount and umount) with `nsenter` to access the host namespaces, ensuring that the Kernel NFS client is tied to the host network namespace.

This design ensures the NFS share mount persists after the CSI plugin pod restarts. However, this can be achieved without `HostPID` and the `nsenter` in the custom mounter, as long as the NFS client connection is established within the host network namespace. Therefore, the custom mounter will be removed and replaced with `hostNetwork:true` in the CSI plugin pod for RWX volumes without the storage network configured.

A difference approach is required when the storage network is configured. Multus networks exist only in the Kubernetes network space. Therefore, for RWX volumes with a storage-network, the CSI plugin pod cannot run in the host network. When a RWX volume uses the storage network, the CSI plugin operate in its own network namespace. Since the NFS mount is managed by the Kernel module, the client is unaware of the client namespace is tied to the CSI plugin pod, resulting in a dangling mount after the CSI plugin pod restart. To workaround this, Longhorn will delete the workload pod (triggering its controller to restart the pod) to allow the CSI controller to handle the remount through the CSI node server's *NodeUnpublishVolume* and *NodePublishVolume*.

### Kubernetes Pod Controller

Introduce a new responsibility to the Kubernetes pod controller: deleting workload pods that use the RWX volume and storage network when the CSI plugin pod restarts (during *Delete* operations). When a workload pod is deleted, its owning controller should create a new pod, initiating the normal volume attachment process. This process involves the CSI controller requesting the node server to unmount and mount the mount points, re-establishing the connection of the dangling mount. However, this approach results in a temporary disruption to the workload pod. Therefore, users can control this behavior using the `auto-delete-pod-when-volume-detached-unexpectedly` setting.

If the RWX volume does not use the storage network, or the healess service, workload pod deletion will not be invoked.

### Test plan

1. **Regression Testing:** Cover both cluster network and storage network scenarios to ensure all functionalities work as expected.
1. **Resilience Testing:** Verify data accessibility after CSI plugin pod restarts for both cluster network and storage network scenarios.
1. **Cross-platform Testing:** Ensure RWX volume functionality on non-traditional operating systems such as Talos Linux and Container-Optimized OS for compatibility.
1. **Upgrade Testing:** Validate that existing RWX volumes function correctly after an upgrade.

### Upgrade strategy

- **CSI Plugin Pod:** If the storage network is configured before upgrading, the CSI plugin pod will be annotated accordingly after the upgrade.

- **Existing RWX Volumes:** Upgrading from previous version with existing volumes will be unaffected since the NFS client mount was established in the host network namespace that is not affected by the CSI plugin pod restart. When the workload pod restarts, the Kubelet will automatically reuse the existing client connection.

- **New RWX Volumes:** When the storage network is configured before upgrading, New RWX volumes created after the upgrade will be applied with the storage network.

- **Future Version Upgrades:** The Longhorn Kubernetes pod controller will trigger the deletion of workload pods, causing Kubelet to restart the workload pod. This process will remount NFS entries when the workload uses RWX volumes with the storage network.

## Note [optional]

The [original issue](https://github.com/longhorn/longhorn/issues/8184) includes discussions about the workload data directory becoming unresponsive after the CSI plugin pod restarts. To address this, there is an initial consensus on a solution that involves deleting the workload pod. This approach effectively re-establish the mount point, ensuring continued data accessibility.
