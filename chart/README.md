# Longhorn Chart

> **Important**: Please install the Longhorn chart in the `longhorn-system` namespace only.

> **Warning**: Longhorn doesn't support downgrading from a higher version to a lower version.

> **Note**: Use Helm 3 when installing and upgrading Longhorn. Helm 2 is [no longer supported](https://helm.sh/blog/helm-2-becomes-unsupported/).

## Source Code

Longhorn is 100% open source software. Project source code is spread across a number of repos:

1. Longhorn Engine -- Core controller/replica logic https://github.com/longhorn/longhorn-engine
2. Longhorn Instance Manager -- Controller/replica instance lifecycle management https://github.com/longhorn/longhorn-instance-manager
3. Longhorn Share Manager -- NFS provisioner that exposes Longhorn volumes as ReadWriteMany volumes. https://github.com/longhorn/longhorn-share-manager
4. Backing Image Manager -- Backing image file lifecycle management. https://github.com/longhorn/backing-image-manager
5. Longhorn Manager -- Longhorn orchestration, includes CSI driver for Kubernetes https://github.com/longhorn/longhorn-manager
6. Longhorn UI -- Dashboard https://github.com/longhorn/longhorn-ui

## Prerequisites

1. A container runtime compatible with Kubernetes (Docker v1.13+, containerd v1.3.7+, etc.)
2. Kubernetes >= v1.25
3. Make sure `bash`, `curl`, `findmnt`, `grep`, `awk` and `blkid` has been installed in all nodes of the Kubernetes cluster.
4. Make sure `open-iscsi` has been installed, and the `iscsid` daemon is running on all nodes of the Kubernetes cluster. For GKE, recommended Ubuntu as guest OS image since it contains `open-iscsi` already.

## Upgrading to Kubernetes v1.25+

Starting in Kubernetes v1.25, [Pod Security Policies](https://kubernetes.io/docs/concepts/security/pod-security-policy/) have been removed from the Kubernetes API.

As a result, **before upgrading to Kubernetes v1.25** (or on a fresh install in a Kubernetes v1.25+ cluster), users are expected to perform an in-place upgrade of this chart with `enablePSP` set to `false` if it has been previously set to `true`.

> **Note:**
> If you upgrade your cluster to Kubernetes v1.25+ before removing PSPs via a `helm upgrade` (even if you manually clean up resources), **it will leave the Helm release in a broken state within the cluster such that further Helm operations will not work (`helm uninstall`, `helm upgrade`, etc.).**
>
> If your charts get stuck in this state, you may have to clean up your Helm release secrets.
Upon setting `enablePSP` to false, the chart will remove any PSP resources deployed on its behalf from the cluster. This is the default setting for this chart.

As a replacement for PSPs, [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) should be used. Please consult the Longhorn docs for more details on how to configure your chart release namespaces to work with the new Pod Security Admission and apply Pod Security Standards.

## Installation

1. Add Longhorn chart repository.
```
helm repo add longhorn https://charts.longhorn.io
```

2. Update local Longhorn chart information from chart repository.
```
helm repo update
```

3. Use the following commands to create the `longhorn-system` namespace first, then install the Longhorn chart.

```
kubectl create namespace longhorn-system
helm install longhorn longhorn/longhorn --namespace longhorn-system
```

## Uninstallation

```
kubectl -n longhorn-system patch -p '{"value": "true"}' --type=merge lhs deleting-confirmation-flag
helm uninstall longhorn -n longhorn-system
kubectl delete namespace longhorn-system
```

## Values

The `values.yaml` contains items used to tweak a deployment of this chart.

### Cattle Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global.cattle.systemDefaultRegistry | string | `""` | Default system registry. |
| global.cattle.windowsCluster.defaultSetting.systemManagedComponentsNodeSelector | string | `"kubernetes.io/os:linux"` | Node selector for system-managed Longhorn components. |
| global.cattle.windowsCluster.defaultSetting.taintToleration | string | `"cattle.io/os=linux:NoSchedule"` | Toleration for system-managed Longhorn components. |
| global.cattle.windowsCluster.enabled | bool | `false` | Setting that allows Longhorn to run on a Rancher Windows cluster. |
| global.cattle.windowsCluster.nodeSelector | object | `{"kubernetes.io/os":"linux"}` | Node selector for Linux nodes that can run user-deployed Longhorn components. |
| global.cattle.windowsCluster.tolerations | list | `[{"effect":"NoSchedule","key":"cattle.io/os","operator":"Equal","value":"linux"}]` | Toleration for Linux nodes that can run user-deployed Longhorn components. |
| global.nodeSelector | object | `{}` | Node selector for nodes allowed to run user-deployed components such as Longhorn Manager, Longhorn UI, and Longhorn Driver Deployer. |
| global.tolerations | list | `[]` | Toleration for nodes allowed to run user-deployed components such as Longhorn Manager, Longhorn UI, and Longhorn Driver Deployer. |

### Network Policies

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| networkPolicies.enabled | bool | `false` | Setting that allows you to enable network policies that control access to Longhorn pods. |
| networkPolicies.type | string | `"k3s"` | Distribution that determines the policy for allowing access for an ingress. (Options: "k3s", "rke2", "rke1") |

### Image Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| image.csi.attacher.repository | string | `"longhornio/csi-attacher"` | Repository for the CSI attacher image. When unspecified, Longhorn uses the default value. |
| image.csi.attacher.tag | string | `"v4.8.1"` | Tag for the CSI attacher image. When unspecified, Longhorn uses the default value. |
| image.csi.livenessProbe.repository | string | `"longhornio/livenessprobe"` | Repository for the CSI liveness probe image. When unspecified, Longhorn uses the default value. |
| image.csi.livenessProbe.tag | string | `"v2.15.0"` | Tag for the CSI liveness probe image. When unspecified, Longhorn uses the default value. |
| image.csi.nodeDriverRegistrar.repository | string | `"longhornio/csi-node-driver-registrar"` | Repository for the CSI Node Driver Registrar image. When unspecified, Longhorn uses the default value. |
| image.csi.nodeDriverRegistrar.tag | string | `"v2.13.0"` | Tag for the CSI Node Driver Registrar image. When unspecified, Longhorn uses the default value. |
| image.csi.provisioner.repository | string | `"longhornio/csi-provisioner"` | Repository for the CSI Provisioner image. When unspecified, Longhorn uses the default value. |
| image.csi.provisioner.tag | string | `"v5.2.0"` | Tag for the CSI Provisioner image. When unspecified, Longhorn uses the default value. |
| image.csi.resizer.repository | string | `"longhornio/csi-resizer"` | Repository for the CSI Resizer image. When unspecified, Longhorn uses the default value. |
| image.csi.resizer.tag | string | `"v1.13.2"` | Tag for the CSI Resizer image. When unspecified, Longhorn uses the default value. |
| image.csi.snapshotter.repository | string | `"longhornio/csi-snapshotter"` | Repository for the CSI Snapshotter image. When unspecified, Longhorn uses the default value. |
| image.csi.snapshotter.tag | string | `"v8.2.0"` | Tag for the CSI Snapshotter image. When unspecified, Longhorn uses the default value. |
| image.longhorn.backingImageManager.repository | string | `"longhornio/backing-image-manager"` | Repository for the Backing Image Manager image. When unspecified, Longhorn uses the default value. |
| image.longhorn.backingImageManager.tag | string | `"v1.9.0"` | Tag for the Backing Image Manager image. When unspecified, Longhorn uses the default value. |
| image.longhorn.engine.repository | string | `"longhornio/longhorn-engine"` | Repository for the Longhorn Engine image. |
| image.longhorn.engine.tag | string | `"v1.9.0"` | Tag for the Longhorn Engine image. |
| image.longhorn.instanceManager.repository | string | `"longhornio/longhorn-instance-manager"` | Repository for the Longhorn Instance Manager image. |
| image.longhorn.instanceManager.tag | string | `"v1.9.0"` | Tag for the Longhorn Instance Manager image. |
| image.longhorn.manager.repository | string | `"longhornio/longhorn-manager"` | Repository for the Longhorn Manager image. |
| image.longhorn.manager.tag | string | `"v1.9.0"` | Tag for the Longhorn Manager image. |
| image.longhorn.shareManager.repository | string | `"longhornio/longhorn-share-manager"` | Repository for the Longhorn Share Manager image. |
| image.longhorn.shareManager.tag | string | `"v1.9.0"` | Tag for the Longhorn Share Manager image. |
| image.longhorn.supportBundleKit.repository | string | `"longhornio/support-bundle-kit"` | Repository for the Longhorn Support Bundle Manager image. |
| image.longhorn.supportBundleKit.tag | string | `"v0.0.55"` | Tag for the Longhorn Support Bundle Manager image. |
| image.longhorn.ui.repository | string | `"longhornio/longhorn-ui"` | Repository for the Longhorn UI image. |
| image.longhorn.ui.tag | string | `"v1.9.0"` | Tag for the Longhorn UI image. |
| image.openshift.oauthProxy.repository | string | `""` | Repository for the OAuth Proxy image. Specify the upstream image (for example, "quay.io/openshift/origin-oauth-proxy"). This setting applies only to OpenShift users. |
| image.openshift.oauthProxy.tag | string | `""` | Tag for the OAuth Proxy image. Specify OCP/OKD version 4.1 or later (including version 4.15, which is available at quay.io/openshift/origin-oauth-proxy:4.15). This setting applies only to OpenShift users. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy that applies to all user-deployed Longhorn components, such as Longhorn Manager, Longhorn driver, and Longhorn UI. |

### Service Settings

| Key | Description |
|-----|-------------|
| service.manager.nodePort | NodePort port number for Longhorn Manager. When unspecified, Longhorn selects a free port between 30000 and 32767. |
| service.manager.type | Service type for Longhorn Manager. |
| service.ui.nodePort | NodePort port number for Longhorn UI. When unspecified, Longhorn selects a free port between 30000 and 32767. |
| service.ui.type | Service type for Longhorn UI. (Options: "ClusterIP", "NodePort", "LoadBalancer", "Rancher-Proxy") |

### StorageClass Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| persistence.backingImage.dataSourceParameters | string | `nil` | Data source parameters of a backing image used in a Longhorn StorageClass. You can specify a JSON string of a map. (Example: `'{\"url\":\"https://backing-image-example.s3-region.amazonaws.com/test-backing-image\"}'`) |
| persistence.backingImage.dataSourceType | string | `nil` | Data source type of a backing image used in a Longhorn StorageClass. If the backing image exists in the cluster, Longhorn uses this setting to verify the image. If the backing image does not exist, Longhorn creates one using the specified data source type. |
| persistence.backingImage.enable | bool | `false` | Setting that allows you to use a backing image in a Longhorn StorageClass. |
| persistence.backingImage.expectedChecksum | string | `nil` | Expected SHA-512 checksum of a backing image used in a Longhorn StorageClass. |
| persistence.backingImage.name | string | `nil` | Backing image to be used for creating and restoring volumes in a Longhorn StorageClass. When no backing images are available, specify the data source type and parameters that Longhorn can use to create a backing image. |
| persistence.backupTargetName | string | `"default"` | Setting that allows you to specify the backup target for the default Longhorn StorageClass. |
| persistence.dataEngine | string | `"v1"` | Setting that allows you to specify the data engine version for the default Longhorn StorageClass. (Options: "v1", "v2") |
| persistence.defaultClass | bool | `true` | Setting that allows you to specify the default Longhorn StorageClass. |
| persistence.defaultClassReplicaCount | int | `3` | Replica count of the default Longhorn StorageClass. |
| persistence.defaultDataLocality | string | `"disabled"` | Data locality of the default Longhorn StorageClass. (Options: "disabled", "best-effort") |
| persistence.defaultDiskSelector.enable | bool | `false` | Setting that allows you to enable the disk selector for the default Longhorn StorageClass. |
| persistence.defaultDiskSelector.selector | string | `""` | Disk selector for the default Longhorn StorageClass. Longhorn uses only disks with the specified tags for storing volume data. (Examples: "nvme,sata") |
| persistence.defaultFsType | string | `"ext4"` | Filesystem type of the default Longhorn StorageClass. |
| persistence.defaultMkfsParams | string | `""` | mkfs parameters of the default Longhorn StorageClass. |
| persistence.defaultNodeSelector.enable | bool | `false` | Setting that allows you to enable the node selector for the default Longhorn StorageClass. |
| persistence.defaultNodeSelector.selector | string | `""` | Node selector for the default Longhorn StorageClass. Longhorn uses only nodes with the specified tags for storing volume data. (Examples: "storage,fast") |
| persistence.disableRevisionCounter | string | `"true"` | Setting that disables the revision counter and thereby prevents Longhorn from tracking all write operations to a volume. When salvaging a volume, Longhorn uses properties of the volume-head-xxx.img file (the last file size and the last time the file was modified) to select the replica to be used for volume recovery. |
| persistence.migratable | bool | `false` | Setting that allows you to enable live migration of a Longhorn volume from one node to another. |
| persistence.nfsOptions | string | `""` | Set NFS mount options for Longhorn StorageClass for RWX volumes |
| persistence.reclaimPolicy | string | `"Delete"` | Reclaim policy that provides instructions for handling of a volume after its claim is released. (Options: "Retain", "Delete") |
| persistence.recurringJobSelector.enable | bool | `false` | Setting that allows you to enable the recurring job selector for a Longhorn StorageClass. |
| persistence.recurringJobSelector.jobList | list | `[]` | Recurring job selector for a Longhorn StorageClass. Ensure that quotes are used correctly when specifying job parameters. (Example: `[{"name":"backup", "isGroup":true}]`) |
| persistence.removeSnapshotsDuringFilesystemTrim | string | `"ignored"` | Setting that allows you to enable automatic snapshot removal during filesystem trim for a Longhorn StorageClass. (Options: "ignored", "enabled", "disabled") |
| persistence.volumeBindingMode | string | `"Immediate"` | VolumeBindingMode controls when volume binding and dynamic provisioning should occur. (Options: "Immediate", "WaitForFirstConsumer") (Defaults to "Immediate") |

### CSI Settings

| Key | Description |
|-----|-------------|
| csi.attacherReplicaCount | Replica count of the CSI Attacher. When unspecified, Longhorn uses the default value ("3"). |
| csi.kubeletRootDir | kubelet root directory. When unspecified, Longhorn uses the default value. |
| csi.provisionerReplicaCount | Replica count of the CSI Provisioner. When unspecified, Longhorn uses the default value ("3"). |
| csi.resizerReplicaCount | Replica count of the CSI Resizer. When unspecified, Longhorn uses the default value ("3"). |
| csi.snapshotterReplicaCount | Replica count of the CSI Snapshotter. When unspecified, Longhorn uses the default value ("3"). |

### Longhorn Manager Settings

Longhorn consists of user-deployed components (for example, Longhorn Manager, Longhorn Driver, and Longhorn UI) and system-managed components (for example, Instance Manager, Backing Image Manager, Share Manager, CSI Driver, and Engine Image). The following settings only apply to Longhorn Manager.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| longhornManager.log.format | string | `"plain"` | Format of Longhorn Manager logs. (Options: "plain", "json") |
| longhornManager.nodeSelector | object | `{}` | Node selector for Longhorn Manager. Specify the nodes allowed to run Longhorn Manager. |
| longhornManager.priorityClass | string | `"longhorn-critical"` | PriorityClass for Longhorn Manager. |
| longhornManager.serviceAnnotations | object | `{}` | Annotation for the Longhorn Manager service. |
| longhornManager.tolerations | list | `[]` | Toleration for Longhorn Manager on nodes allowed to run Longhorn components. |

### Longhorn Driver Settings

Longhorn consists of user-deployed components (for example, Longhorn Manager, Longhorn Driver, and Longhorn UI) and system-managed components (for example, Instance Manager, Backing Image Manager, Share Manager, CSI Driver, and Engine Image). The following settings only apply to Longhorn Driver.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| longhornDriver.log.format | string | `"plain"` | Format of longhorn-driver logs. (Options: "plain", "json") |
| longhornDriver.nodeSelector | object | `{}` | Node selector for Longhorn Driver. Specify the nodes allowed to run Longhorn Driver. |
| longhornDriver.priorityClass | string | `"longhorn-critical"` | PriorityClass for Longhorn Driver. |
| longhornDriver.tolerations | list | `[]` | Toleration for Longhorn Driver on nodes allowed to run Longhorn components. |

### Longhorn UI Settings

Longhorn consists of user-deployed components (for example, Longhorn Manager, Longhorn Driver, and Longhorn UI) and system-managed components (for example, Instance Manager, Backing Image Manager, Share Manager, CSI Driver, and Engine Image). The following settings only apply to Longhorn UI.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| longhornUI.affinity | object | `{"podAntiAffinity":{"preferredDuringSchedulingIgnoredDuringExecution":[{"podAffinityTerm":{"labelSelector":{"matchExpressions":[{"key":"app","operator":"In","values":["longhorn-ui"]}]},"topologyKey":"kubernetes.io/hostname"},"weight":1}]}}` | Affinity for Longhorn UI pods. Specify the affinity you want to use for Longhorn UI. |
| longhornUI.nodeSelector | object | `{}` | Node selector for Longhorn UI. Specify the nodes allowed to run Longhorn UI. |
| longhornUI.priorityClass | string | `"longhorn-critical"` | PriorityClass for Longhorn UI. |
| longhornUI.replicas | int | `2` | Replica count for Longhorn UI. |
| longhornUI.tolerations | list | `[]` | Toleration for Longhorn UI on nodes allowed to run Longhorn components. |

### Ingress Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ingress.annotations | string | `nil` | Ingress annotations in the form of key-value pairs. |
| ingress.enabled | bool | `false` | Setting that allows Longhorn to generate ingress records for the Longhorn UI service. |
| ingress.host | string | `"sslip.io"` | Hostname of the Layer 7 load balancer. |
| ingress.ingressClassName | string | `nil` | IngressClass resource that contains ingress configuration, including the name of the Ingress controller. ingressClassName can replace the kubernetes.io/ingress.class annotation used in earlier Kubernetes releases. |
| ingress.path | string | `"/"` | Default ingress path. You can access the Longhorn UI by following the full ingress path {{host}}+{{path}}. |
| ingress.pathType | string | `"ImplementationSpecific"` | Ingress path type. To maintain backward compatibility, the default value is "ImplementationSpecific". |
| ingress.secrets | string | `nil` | Secret that contains a TLS private key and certificate. Use secrets if you want to use your own certificates to secure ingresses. |
| ingress.secureBackends | bool | `false` | Setting that allows you to enable secure connections to the Longhorn UI service via port 443. |
| ingress.tls | bool | `false` | Setting that allows you to enable TLS on ingress records. |
| ingress.tlsSecret | string | `"longhorn.local-tls"` | TLS secret that contains the private key and certificate to be used for TLS. This setting applies only when TLS is enabled on ingress records. |

### Private Registry Settings

You can install Longhorn in an air-gapped environment with a private registry. For more information, see the **Air Gap Installation** section of the [documentation](https://longhorn.io/docs).

| Key | Description |
|-----|-------------|
| privateRegistry.createSecret | Setting that allows you to create a private registry secret. |
| privateRegistry.registryPasswd | Password for authenticating with a private registry. |
| privateRegistry.registrySecret | Kubernetes secret that allows you to pull images from a private registry. This setting applies only when creation of private registry secrets is enabled. You must include the private registry name in the secret name. |
| privateRegistry.registryUrl | URL of a private registry. When unspecified, Longhorn uses the default system registry. |
| privateRegistry.registryUser | User account used for authenticating with a private registry. |

### Metrics Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| metrics.serviceMonitor.additionalLabels | object | `{}` | Additional labels for the Prometheus ServiceMonitor resource. |
| metrics.serviceMonitor.annotations | object | `{}` | Annotations for the Prometheus ServiceMonitor resource. |
| metrics.serviceMonitor.enabled | bool | `false` | Setting that allows the creation of a Prometheus ServiceMonitor resource for Longhorn Manager components. |
| metrics.serviceMonitor.interval | string | `""` | Interval at which Prometheus scrapes the metrics from the target. |
| metrics.serviceMonitor.metricRelabelings | list | `[]` | Configures the relabeling rules to apply to the samples before ingestion. See the [Prometheus Operator documentation](https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.Endpoint) for formatting details. |
| metrics.serviceMonitor.relabelings | list | `[]` | Configures the relabeling rules to apply the target’s metadata labels. See the [Prometheus Operator documentation](https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.Endpoint) for formatting details. |
| metrics.serviceMonitor.scrapeTimeout | string | `""` | Timeout after which Prometheus considers the scrape to be failed. |

### OS/Kubernetes Distro Settings

#### OpenShift Settings

For more details, see the [ocp-readme](https://github.com/longhorn/longhorn/blob/master/chart/ocp-readme.md).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| openshift.enabled | bool | `false` | Setting that allows Longhorn to integrate with OpenShift. |
| openshift.ui.port | int | `443` | Port for accessing the OpenShift web console. |
| openshift.ui.proxy | int | `8443` | Port for proxy that provides access to the OpenShift web console. |
| openshift.ui.route | string | `"longhorn-ui"` | Route for connections between Longhorn and the OpenShift web console. |

### Other Settings

| Key | Default | Description |
|-----|---------|-------------|
| annotations | `{}` | Annotation for the Longhorn Manager DaemonSet pods. This setting is optional. |
| defaultBackupStore | `{"backupTarget":null,"backupTargetCredentialSecret":null,"pollInterval":null}` | Setting that allows you to update the default backupstore. |
| defaultBackupStore.backupTarget | `nil` | Endpoint used to access the default backupstore. (Options: "NFS", "CIFS", "AWS", "GCP", "AZURE") |
| defaultBackupStore.backupTargetCredentialSecret | `nil` | Name of the Kubernetes secret associated with the default backup target. |
| defaultBackupStore.pollInterval | `nil` | Number of seconds that Longhorn waits before checking the default backupstore for new backups. The default value is "300". When the value is "0", polling is disabled. |
| enableGoCoverDir | `false` | Setting that allows Longhorn to generate code coverage profiles. |
| enablePSP | `false` | Setting that allows you to enable pod security policies (PSPs) that allow privileged Longhorn pods to start. This setting applies only to clusters running Kubernetes 1.25 and earlier, and with the built-in Pod Security admission controller enabled. |
| extraObjects | `[]` | Add extra objects manifests |
| namespaceOverride | `""` | Specify override namespace, specifically this is useful for using longhorn as sub-chart and its release namespace is not the `longhorn-system`. |
| preUpgradeChecker.jobEnabled | `true` | Setting that allows Longhorn to perform pre-upgrade checks. Disable this setting when installing Longhorn using Argo CD or other GitOps solutions. |
| preUpgradeChecker.upgradeVersionCheck | `true` | Setting that allows Longhorn to perform upgrade version checks after starting the Longhorn Manager DaemonSet Pods. Disabling this setting also disables `preUpgradeChecker.jobEnabled`. Longhorn recommends keeping this setting enabled. |

### System Default Settings

During installation, you can either allow Longhorn to use the default system settings or use specific flags to modify the default values. After installation, you can modify the settings using the Longhorn UI. For more information, see the **Settings Reference** section of the [documentation](https://longhorn.io/docs).

| Key | Description |
|-----|-------------|
| defaultSettings.allowCollectingLonghornUsageMetrics | Setting that allows Longhorn to periodically collect anonymous usage data for product improvement purposes. Longhorn sends collected data to the [Upgrade Responder](https://github.com/longhorn/upgrade-responder) server, which is the data source of the Longhorn Public Metrics Dashboard (https://metrics.longhorn.io). The Upgrade Responder server does not store data that can be used to identify clients, including IP addresses. |
| defaultSettings.allowEmptyDiskSelectorVolume | Setting that allows scheduling of empty disk selector volumes to any disk. |
| defaultSettings.allowEmptyNodeSelectorVolume | Setting that allows scheduling of empty node selector volumes to any node. |
| defaultSettings.allowRecurringJobWhileVolumeDetached | Setting that allows Longhorn to automatically attach a volume and create snapshots or backups when recurring jobs are run. |
| defaultSettings.allowVolumeCreationWithDegradedAvailability | Setting that allows you to create and attach a volume without having all replicas scheduled at the time of creation. |
| defaultSettings.autoCleanupRecurringJobBackupSnapshot | Setting that allows Longhorn to automatically clean up the snapshot generated by a recurring backup job. |
| defaultSettings.autoCleanupSnapshotAfterOnDemandBackupCompleted | Setting that automatically cleans up the snapshot after the on-demand backup is completed. |
| defaultSettings.autoCleanupSnapshotWhenDeleteBackup | Setting that automatically cleans up the snapshot when the backup is deleted. |
| defaultSettings.autoCleanupSystemGeneratedSnapshot | Setting that allows Longhorn to automatically clean up the system-generated snapshot after replica rebuilding is completed. |
| defaultSettings.autoDeletePodWhenVolumeDetachedUnexpectedly | Setting that allows Longhorn to automatically delete a workload pod that is managed by a controller (for example, daemonset) whenever a Longhorn volume is detached unexpectedly (for example, during Kubernetes upgrades). After deletion, the controller restarts the pod and then Kubernetes handles volume reattachment and remounting. |
| defaultSettings.autoSalvage | Setting that allows Longhorn to automatically salvage volumes when all replicas become faulty (for example, when the network connection is interrupted). Longhorn determines which replicas are usable and then uses these replicas for the volume. This setting is enabled by default. |
| defaultSettings.backingImageCleanupWaitInterval | Number of minutes that Longhorn waits before cleaning up the backing image file when no replicas in the disk are using it. |
| defaultSettings.backingImageRecoveryWaitInterval | Number of seconds that Longhorn waits before downloading a backing image file again when the status of all image disk files changes to "failed" or "unknown". |
| defaultSettings.backupCompressionMethod | Setting that allows you to specify a backup compression method. |
| defaultSettings.backupConcurrentLimit | Maximum number of worker threads that can concurrently run for each backup. |
| defaultSettings.backupExecutionTimeout | Number of minutes that Longhorn allows for the backup execution. The default value is "1". |
| defaultSettings.concurrentAutomaticEngineUpgradePerNodeLimit | Maximum number of engines that are allowed to concurrently upgrade on each node after Longhorn Manager is upgraded. When the value is "0", Longhorn does not automatically upgrade volume engines to the new default engine image version. |
| defaultSettings.concurrentReplicaRebuildPerNodeLimit | Maximum number of replicas that can be concurrently rebuilt on each node. |
| defaultSettings.concurrentVolumeBackupRestorePerNodeLimit | Maximum number of volumes that can be concurrently restored on each node using a backup. When the value is "0", restoration of volumes using a backup is disabled. |
| defaultSettings.createDefaultDiskLabeledNodes | Setting that allows Longhorn to automatically create a default disk only on nodes with the label "node.longhorn.io/create-default-disk=true" (if no other disks exist). When this setting is disabled, Longhorn creates a default disk on each node that is added to the cluster. |
| defaultSettings.defaultDataLocality | Default data locality. A Longhorn volume has data locality if a local replica of the volume exists on the same node as the pod that is using the volume. |
| defaultSettings.defaultDataPath | Default path for storing data on a host. The default value is "/var/lib/longhorn/". |
| defaultSettings.defaultLonghornStaticStorageClass | Default name of Longhorn static StorageClass. "storageClassName" is assigned to PVs and PVCs that are created for an existing Longhorn volume. "storageClassName" can also be used as a label, so it is possible to use a Longhorn StorageClass to bind a workload to an existing PV without creating a Kubernetes StorageClass object. "storageClassName" needs to be an existing StorageClass. The default value is "longhorn-static". |
| defaultSettings.defaultReplicaCount | Default number of replicas for volumes created using the Longhorn UI. For Kubernetes configuration, modify the `numberOfReplicas` field in the StorageClass. The default value is "3". |
| defaultSettings.deletingConfirmationFlag | Flag that prevents accidental uninstallation of Longhorn. |
| defaultSettings.detachManuallyAttachedVolumesWhenCordoned | Setting that allows automatic detaching of manually-attached volumes when a node is cordoned. |
| defaultSettings.disableRevisionCounter | Setting that disables the revision counter and thereby prevents Longhorn from tracking all write operations to a volume. When salvaging a volume, Longhorn uses properties of the "volume-head-xxx.img" file (the last file size and the last time the file was modified) to select the replica to be used for volume recovery. This setting applies only to volumes created using the Longhorn UI. |
| defaultSettings.disableSchedulingOnCordonedNode | Setting that prevents Longhorn Manager from scheduling replicas on a cordoned Kubernetes node. This setting is enabled by default. |
| defaultSettings.disableSnapshotPurge | Setting that temporarily prevents all attempts to purge volume snapshots. |
| defaultSettings.engineReplicaTimeout | Timeout between the Longhorn Engine and replicas. Specify a value between "8" and "30" seconds. The default value is "8". |
| defaultSettings.failedBackupTTL | Number of minutes that Longhorn keeps a failed backup resource. When the value is "0", automatic deletion is disabled. |
| defaultSettings.fastReplicaRebuildEnabled | Setting that allows fast rebuilding of replicas using the checksum of snapshot disk files. Before enabling this setting, you must set the snapshot-data-integrity value to "enable" or "fast-check". |
| defaultSettings.freezeFilesystemForSnapshot | Setting that freezes the filesystem on the root partition before a snapshot is created. |
| defaultSettings.guaranteedInstanceManagerCPU | Percentage of the total allocatable CPU resources on each node to be reserved for each instance manager pod when the V1 Data Engine is enabled. The default value is "12". |
| defaultSettings.kubernetesClusterAutoscalerEnabled | Setting that notifies Longhorn that the cluster is using the Kubernetes Cluster Autoscaler. |
| defaultSettings.logLevel | Log levels that indicate the type and severity of logs in Longhorn Manager. The default value is "Info". (Options: "Panic", "Fatal", "Error", "Warn", "Info", "Debug", "Trace") |
| defaultSettings.longGRPCTimeOut | Number of seconds that Longhorn allows for the completion of replica rebuilding and snapshot cloning operations. |
| defaultSettings.nodeDownPodDeletionPolicy | Policy that defines the action Longhorn takes when a volume is stuck with a StatefulSet or Deployment pod on a node that failed. |
| defaultSettings.nodeDrainPolicy | Policy that defines the action Longhorn takes when a node with the last healthy replica of a volume is drained. |
| defaultSettings.offlineRelicaRebuilding | Enables automatic rebuilding of degraded replicas while the volume is detached. This setting only takes effect if the individual volume setting is set to `ignored` or `enabled`. |
| defaultSettings.orphanResourceAutoDeletion | Enables Longhorn to automatically delete orphaned resources and their associated data or processes (e.g., stale replicas). Orphaned resources on failed or unknown nodes are not automatically cleaned up.  You need to specify the resource types to be deleted using a semicolon-separated list (e.g., `replica-data;instance`). Available items are: `replica-data`, `instance`. |
| defaultSettings.orphanResourceAutoDeletionGracePeriod | Specifies the wait time, in seconds, before Longhorn automatically deletes an orphaned Custom Resource (CR) and its associated resources. Note that if a user manually deletes an orphaned CR, the deletion occurs immediately and does not respect this grace period. |
| defaultSettings.priorityClass | PriorityClass for system-managed Longhorn components. This setting can help prevent Longhorn components from being evicted under Node Pressure. Notice that this will be applied to Longhorn user-deployed components by default if there are no priority class values set yet, such as `longhornManager.priorityClass`. |
| defaultSettings.recurringFailedJobsHistoryLimit | Maximum number of failed recurring backup and snapshot jobs to be retained. When the value is "0", a history of failed recurring jobs is not retained. |
| defaultSettings.recurringJobMaxRetention | Maximum number of snapshots or backups to be retained. |
| defaultSettings.recurringSuccessfulJobsHistoryLimit | Maximum number of successful recurring backup and snapshot jobs to be retained. When the value is "0", a history of successful recurring jobs is not retained. |
| defaultSettings.removeSnapshotsDuringFilesystemTrim | Setting that allows Longhorn to automatically mark the latest snapshot and its parent files as removed during a filesystem trim. Longhorn does not remove snapshots containing multiple child files. |
| defaultSettings.replicaAutoBalance | Setting that automatically rebalances replicas when an available node is discovered. |
| defaultSettings.replicaDiskSoftAntiAffinity | Setting that allows scheduling on disks with existing healthy replicas of the same volume. This setting is enabled by default. |
| defaultSettings.replicaFileSyncHttpClientTimeout | Number of seconds that an HTTP client waits for a response from a File Sync server before considering the connection to have failed. |
| defaultSettings.replicaReplenishmentWaitInterval | Number of seconds that Longhorn waits before reusing existing data on a failed replica instead of creating a new replica of a degraded volume. |
| defaultSettings.replicaSoftAntiAffinity | Setting that allows scheduling on nodes with healthy replicas of the same volume. This setting is disabled by default. |
| defaultSettings.replicaZoneSoftAntiAffinity | Setting that allows Longhorn to schedule new replicas of a volume to nodes in the same zone as existing healthy replicas. Nodes that do not belong to any zone are treated as existing in the zone that contains healthy replicas. When identifying zones, Longhorn relies on the label "topology.kubernetes.io/zone=<Zone name of the node>" in the Kubernetes node object. |
| defaultSettings.restoreConcurrentLimit | Maximum number of worker threads that can concurrently run for each restore operation. |
| defaultSettings.restoreVolumeRecurringJobs | Setting that restores recurring jobs from a backup volume on a backup target and creates recurring jobs if none exist during backup restoration. |
| defaultSettings.rwxVolumeFastFailover | Setting that allows Longhorn to detect node failure and immediately migrate affected RWX volumes. |
| defaultSettings.snapshotDataIntegrity | Setting that allows you to enable and disable snapshot hashing and data integrity checks. |
| defaultSettings.snapshotDataIntegrityCronjob | Setting that defines when Longhorn checks the integrity of data in snapshot disk files. You must use the Unix cron expression format. |
| defaultSettings.snapshotDataIntegrityImmediateCheckAfterSnapshotCreation | Setting that allows disabling of snapshot hashing after snapshot creation to minimize impact on system performance. |
| defaultSettings.snapshotMaxCount | Maximum snapshot count for a volume. The value should be between 2 to 250 |
| defaultSettings.storageMinimalAvailablePercentage | Percentage of minimum available disk capacity. When the minimum available capacity exceeds the total available capacity, the disk becomes unschedulable until more space is made available for use. The default value is "25". |
| defaultSettings.storageNetwork | Storage network for in-cluster traffic. When unspecified, Longhorn uses the Kubernetes cluster network. |
| defaultSettings.storageOverProvisioningPercentage | Percentage of storage that can be allocated relative to hard drive capacity. The default value is "100". |
| defaultSettings.storageReservedPercentageForDefaultDisk | Percentage of disk space that is not allocated to the default disk on each new Longhorn node. |
| defaultSettings.supportBundleFailedHistoryLimit | Maximum number of failed support bundles that can exist in the cluster. When the value is "0", Longhorn automatically purges all failed support bundles. |
| defaultSettings.systemManagedComponentsNodeSelector | Node selector for system-managed Longhorn components. |
| defaultSettings.systemManagedPodsImagePullPolicy | Image pull policy for system-managed pods, such as Instance Manager, engine images, and CSI Driver. Changes to the image pull policy are applied only after the system-managed pods restart. |
| defaultSettings.taintToleration | Taint or toleration for system-managed Longhorn components. Specify values using a semicolon-separated list in `kubectl taint` syntax (Example: key1=value1:effect; key2=value2:effect). |
| defaultSettings.upgradeChecker | Upgrade Checker that periodically checks for new Longhorn versions. When a new version is available, a notification appears on the Longhorn UI. This setting is enabled by default |
| defaultSettings.upgradeResponderURL | The Upgrade Responder sends a notification whenever a new Longhorn version that you can upgrade to becomes available. The default value is https://longhorn-upgrade-responder.rancher.io/v1/checkupgrade. |
| defaultSettings.v1DataEngine | Setting that allows you to enable the V1 Data Engine. |
| defaultSettings.v2DataEngine | Setting that allows you to enable the V2 Data Engine, which is based on the Storage Performance Development Kit (SPDK). The V2 Data Engine is an experimental feature and should not be used in production environments. |
| defaultSettings.v2DataEngineCPUMask | CPU cores on which the Storage Performance Development Kit (SPDK) target daemon should run. The SPDK target daemon is located in each Instance Manager pod. Ensure that the number of cores is less than or equal to the guaranteed Instance Manager CPUs for the V2 Data Engine. The default value is "0x1". |
| defaultSettings.v2DataEngineGuaranteedInstanceManagerCPU | Number of millicpus on each node to be reserved for each Instance Manager pod when the V2 Data Engine is enabled. The default value is "1250". |
| defaultSettings.v2DataEngineHugepageLimit | Setting that allows you to configure maximum huge page size (in MiB) for the V2 Data Engine. |
| defaultSettings.v2DataEngineLogFlags | Setting that allows you to configure the log flags of the SPDK target daemon (spdk_tgt) of the V2 Data Engine. |
| defaultSettings.v2DataEngineLogLevel | Setting that allows you to configure the log level of the SPDK target daemon (spdk_tgt) of the V2 Data Engine. |
| defaultSettings.v2DataEngineSnapshotDataIntegrity | Setting allows you to enable or disable snapshot hashing and data integrity checking for the V2 Data Engine. |

---
Please see [link](https://github.com/longhorn/longhorn) for more information.
