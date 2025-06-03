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

- Existing workload will continue using the cluster network without disruption.
- New RWX volumes also user the cluster network.
- User can enable the `storage-network-for-rwx-volume-enabled` setting to apply the storage network to re-attached RWX volumes.
- Once the storage network is applied to the RWX volumes, the workload pod need to be restart when the CSI plugin pod restarts. User can automate this by enabling the `auto-delete-pod-when-volume-detached-unexpectedly` setting.

### Story 3: Using Storage Network For RWO Volume Workload Only

As a Longhorn user, I want to use the storage network for only RWO volumes to avoid restarting my RWO volume workload pods when the CSI plugin pod restarts.
- User can control the application of the storage network to RWX volues by using the `storage-network-for-rwx-volume-enabled` setting.

### User Experience In Detail

Users will be able to create RWX volumes that uses the storage network for data traffic. Key user-facing changes include:

- **CSI Annotations:** Share manager pods and CSI plugin pods will be annotated with the storage network for NFS client mounting when the `storage-network-for-rwx-volume-enabled` setting is enabled. This annotation will only be applied once all RWX volumes have been detached.
- **Headless Service:** storage network enabled RWX volume will use a headless service and a custom endpoint, removing dependency on ClusterIP, which is not suitable for Multus networking.
- **Workload Pod Restart:** When a CSI plugin pod restarts, the NFS share mountpoint becomes unavailable, rendering any attempt to access it unresponsive. User can manually restart the workload pod, or they can enable the `auto-delete-pod-when-volume-detached-unexpectedly` setting. This allows Longhorn to delete the associated workload pod when it is using the storage-network enabled RWX volume. If the pod is managed by a controller, the kubelet will create a new pod. This allows the CSI controller to handle volume remounting through the CSI node server.
- **Upgrade to Longhorn v1.7.0:** Existing RWX volumes remain unchanged if the storage network is configured before the upgrade. To apply the storage network for RWX volumes, detach all RWX volumes, enable the `storage-network-for-rwx-volume-enabled` setting, and reattach the volumes.

### API changes

No API changes are required for this proposal.

## Design

### Storage Network For RWX Volume Enabled Setting.

A new setting, `storage-network-for-rwx-volume-enabled`, allows controlling the application of the storage network for RWX volumes.

When the CSI plugin pod of a workload using the storage network enabled RWX volume restarts, the workload pod also needs a restart to re-establish the NFS client mount connection. This setting enabled user to manage whether the storage network should be applied to the RWX volumes. For RWX volumes using the cluster network, no restart is required during the CSI plugin pod restarts.

```golang
	SettingDefinitionStorageNetworkForRWXVolumeEnabled = SettingDefinition{
		DisplayName: "Storage Network for RWX Volume Enabled",
		Description: "This setting allows Longhorn to use the storage network for in-cluster data traffic for RWX (Read-Write-Many) volume. \n\n" +
			"To apply this setting to existing RWX volumes, they need to be reattached. \n\n" +
			"WARNING: \n\n" +
			"  - Enabling this setting will allow the CSI plugin pod to restart with the storage network annotatation if all RWX volumes are detached. \n\n" +
			"  - The RWX volumes will be mounted with the storage network within the CSI plugin pod container network namespace. \n\n" +
			"  - Consequently, restarting the CSI plugin pod may lead to unresponsive RWX volume mounts. If this occurs, you will need to restart the workload pod to re-establish the mount connection. \n\n" +
			"  - Alternatively, you can enable the 'Automatically Delete Workload Pod when The Volume Is Detached Unexpectedly' setting. \n\n",
		Category: SettingCategoryDangerZone,
		Type:     SettingTypeBool,
		Required: false,
		ReadOnly: false,
		Default:  "false",
	}
```

### CNI Annotation

Introduce CSI annotation for RWX volume pod stack to enable NFS client mounting over the storage network:
	- Share manager pod
	- CSI plugin pod

The setting controller will apply these annotations once `storage-network-for-rwx-volume-enabled` setting is enabled and all RWX volumes are detached.

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

The share manager of the storage network enabled RWX volume will use the service FQDN for its endpoint instead of the value from service `ClusterIP` field.

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

Currently, the CSI plugin pod uses `HostPID` and mounts the host `proc` directory to be used by the custom mounter. This custom mounter wraps the commands (e.g., mount and umount) with `nsenter` to access the host namespaces, ensuring that the Kernel NFS client is tied to the host network namespace. This design ensures the NFS share mount persists after the CSI plugin pod restarts.

A difference approach is required when the storage network is configured. Multus networks exist only in the Kubernetes network space. Therefore, for RWX volumes with a storage-network, the CSI plugin pod cannot run in the host network. When a RWX volume uses the storage network, the CSI plugin operate in its own network namespace. Since the NFS mount is managed by the Kernel module, the client is unaware of the client namespace is tied to the CSI plugin pod, resulting in a dangling mount after the CSI plugin pod restart. To workaround this, Longhorn will delete the workload pod (triggering its controller to restart the pod) to allow the CSI controller to handle the remount through the CSI node server's *NodeUnpublishVolume* and *NodePublishVolume*.

### Kubernetes Pod Controller

Introduce a new responsibility to the Kubernetes pod controller: deleting workload pods that use the storage network enabled RWX volume when the CSI plugin pod restarts (during *Delete* operations). When a workload pod is deleted, its owning controller should create a new pod, initiating the normal volume attachment process. This process involves the CSI controller requesting the node server to unmount and mount the mount points, re-establishing the connection of the dangling mount. However, this approach results in a temporary disruption to the workload pod. Therefore, users can control this behavior using the `auto-delete-pod-when-volume-detached-unexpectedly` setting.

The controller will not trigger RWX volume workload pod deletion in the following scenarios:
- Storage network setting is not configured.
- Storage network for RWX volume setting is disabled.

### Test plan

1. **Feature Testing:** Verify that the storage network supports RWX volumes and ensure the functionality of new settings.
1. **Regression Testing:** Cover both cluster network and storage network scenarios to ensure all functionalities work as expected.
1. **Resilience Testing:** Verify data accessibility after CSI plugin pod restarts for both cluster network and storage network scenarios.
1. **Cross-platform Testing:** Ensure RWX volume functionality on non-traditional operating systems such as Talos Linux and Container-Optimized OS for compatibility.
1. **Upgrade Testing:** Validate that existing RWX volumes function correctly after an upgrade.

### Upgrade strategy

- **Existing RWX Volumes:** RWX volumes will not use the storage network unless the `storage-network-for-rwx-volume-enabled` setting is enable. Therefore, upgrading to Longhorn v1.7.0 will not affect existing RWX volume workloads even if the storage network was already configured before the upgrade. To enable the storage network for both pre-upgrade-existing and new RWX volumes after the upgrade, user needs to:
	1. Detach all RWX volumes.
	1. Enable the `storage-network-for-rwx-volume-enabled` setting.
	1. Reattach the RWX volumes.

- **Future Version Upgrades (v1.7.1, v1.7.2, etc.):** Given the storage network is enabled for RWX volumes, upgrading to a future version will cause the Longhorn NFS data mounts in associated workload pods to become unresponsive after the CSI plugin pod restarts.

To resolve this issue, user have two options:
1. Enable the `auto-delete-pod-when-volume-detached-unexpectedly` setting before the upgrade. This allows Longohrn automatically restart the workload pod after the CSI plugin pod restart, re-establish the NFS client mount connection.
1. Manually restart the workload pods after the upgrade.

> **Note:** Both options resolves the unresponsiveness issue, however, it will cause a brief interruption to the workload pod.

## Note [optional]

- The [original issue](https://github.com/longhorn/longhorn/issues/8184) includes discussions about the workload data directory becoming unresponsive after the CSI plugin pod restarts. To address this, there is an initial consensus on a solution that involves deleting the workload pod. This approach effectively re-establish the mount point, ensuring continued data accessibility.
- The [[BUG] Networking between longhorn-csi-plugin and longhorn-manager is broken after upgrading Longhorn to 1.7.0-rc3](https://github.com/longhorn/longhorn/issues/9223) includes reason for retaining the custom mounter and the use of *ClusterIP* for the regular RWX volume share manager endpoint.
