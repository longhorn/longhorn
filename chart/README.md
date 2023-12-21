# Longhorn Chart

> **Important**: Please install the Longhorn chart in the `longhorn-system` namespace only.

> **Warning**: Longhorn doesn't support downgrading from a higher version to a lower version.

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
2. Kubernetes >= v1.21
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

> **Note:**
> Helm 2 is not supported, [ref](https://helm.sh/blog/helm-2-becomes-unsupported/).
> Please use Helm 3 for Longhorn installation and upgrade. 

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
| global.cattle.systemDefaultRegistry | string | `""` | System default registry |
| global.cattle.windowsCluster.defaultSetting.systemManagedComponentsNodeSelector | string | `"kubernetes.io/os:linux"` | Node selector for Longhorn system managed components |
| global.cattle.windowsCluster.defaultSetting.taintToleration | string | `"cattle.io/os=linux:NoSchedule"` | Toleration for Longhorn system managed components |
| global.cattle.windowsCluster.enabled | bool | `false` | Enable this to allow Longhorn to run on the Rancher-deployed Windows cluster |
| global.cattle.windowsCluster.nodeSelector | object | `{"kubernetes.io/os":"linux"}` | Select Linux nodes to run Longhorn user deployed components |
| global.cattle.windowsCluster.tolerations | list | `[{"effect":"NoSchedule","key":"cattle.io/os","operator":"Equal","value":"linux"}]` | Tolerate Linux nodes to run Longhorn user deployed components |

### Network Policies

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| networkPolicies.enabled | bool | `false` | Enable NetworkPolicies to limit access to the Longhorn pods |
| networkPolicies.type | string | `"k3s"` | Create the policy based on your distribution to allow access for the ingress. Options: `k3s`, `rke2`, `rke1` |

### Image Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| image.csi.attacher.repository | string | `"longhornio/csi-attacher"` | Specify CSI attacher image repository. Leave blank to autodetect |
| image.csi.attacher.tag | string | `"v4.4.2"` | Specify CSI attacher image tag. Leave blank to autodetect |
| image.csi.livenessProbe.repository | string | `"longhornio/livenessprobe"` | Specify CSI liveness probe image repository. Leave blank to autodetect |
| image.csi.livenessProbe.tag | string | `"v2.11.0"` | Specify CSI liveness probe image tag. Leave blank to autodetect |
| image.csi.nodeDriverRegistrar.repository | string | `"longhornio/csi-node-driver-registrar"` | Specify CSI node driver registrar image repository. Leave blank to autodetect |
| image.csi.nodeDriverRegistrar.tag | string | `"v2.9.2"` | Specify CSI node driver registrar image tag. Leave blank to autodetect |
| image.csi.provisioner.repository | string | `"longhornio/csi-provisioner"` | Specify CSI provisioner image repository. Leave blank to autodetect |
| image.csi.provisioner.tag | string | `"v3.6.2"` | Specify CSI provisioner image tag. Leave blank to autodetect |
| image.csi.resizer.repository | string | `"longhornio/csi-resizer"` | Specify CSI driver resizer image repository. Leave blank to autodetect |
| image.csi.resizer.tag | string | `"v1.9.2"` | Specify CSI driver resizer image tag. Leave blank to autodetect |
| image.csi.snapshotter.repository | string | `"longhornio/csi-snapshotter"` | Specify CSI driver snapshotter image repository. Leave blank to autodetect |
| image.csi.snapshotter.tag | string | `"v6.3.0"` | Specify CSI driver snapshotter image tag. Leave blank to autodetect. |
| image.longhorn.backingImageManager.repository | string | `"longhornio/backing-image-manager"` | Specify Longhorn backing image manager image repository |
| image.longhorn.backingImageManager.tag | string | `"master-head"` | Specify Longhorn backing image manager image tag |
| image.longhorn.engine.repository | string | `"longhornio/longhorn-engine"` | Specify Longhorn engine image repository |
| image.longhorn.engine.tag | string | `"master-head"` | Specify Longhorn engine image tag |
| image.longhorn.instanceManager.repository | string | `"longhornio/longhorn-instance-manager"` | Specify Longhorn instance manager image repository |
| image.longhorn.instanceManager.tag | string | `"master-head"` | Specify Longhorn instance manager image tag |
| image.longhorn.manager.repository | string | `"longhornio/longhorn-manager"` | Specify Longhorn manager image repository |
| image.longhorn.manager.tag | string | `"master-head"` | Specify Longhorn manager image tag |
| image.longhorn.shareManager.repository | string | `"longhornio/longhorn-share-manager"` | Specify Longhorn share manager image repository |
| image.longhorn.shareManager.tag | string | `"master-head"` | Specify Longhorn share manager image tag |
| image.longhorn.supportBundleKit.repository | string | `"longhornio/support-bundle-kit"` | Specify Longhorn support bundle manager image repository |
| image.longhorn.supportBundleKit.tag | string | `"v0.0.33"` | Specify Longhorn support bundle manager image tag |
| image.longhorn.ui.repository | string | `"longhornio/longhorn-ui"` | Specify Longhorn ui image repository |
| image.longhorn.ui.tag | string | `"master-head"` | Specify Longhorn ui image tag |
| image.openshift.oauthProxy.repository | string | `"quay.io/openshift/origin-oauth-proxy"` | For openshift user. Specify oauth proxy image repository |
| image.openshift.oauthProxy.tag | float | `4.14` | For openshift user. Specify oauth proxy image tag. Note: Use your OCP/OKD 4.X Version, Current Stable is 4.14 |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy which applies to all Longhorn user-deployed components. E.g., Longhorn manager, Longhorn driver, Longhorn UI |

### Service Settings

| Key | Description |
|-----|-------------|
| service.manager.nodePort | NodePort port number (to set explicitly, chooses port between 30000-32767) |
| service.manager.type | Define the Longhorn manager service type. |
| service.ui.nodePort | NodePort port number (to set explicitly, chooses port between 30000-32767) |
| service.ui.type | Define the Longhorn UI service type. Options: `ClusterIP`, `NodePort`, `LoadBalancer`, `Rancher-Proxy` |

### StorageClass Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| persistence.backingImage.dataSourceParameters | string | `nil` | Specify the data source parameters for the backing image used in Longhorn StorageClass. This option accepts a json string of a map. E.g., `'{\"url\":\"https://backing-image-example.s3-region.amazonaws.com/test-backing-image\"}'`. |
| persistence.backingImage.dataSourceType | string | `nil` | Specify the data source type for the backing image used in Longhorn StorageClass. If the backing image does not exist, Longhorn will use this field to create a backing image. Otherwise, Longhorn will use it to verify the selected backing image. |
| persistence.backingImage.enable | bool | `false` | Set backing image for Longhorn StorageClass |
| persistence.backingImage.expectedChecksum | string | `nil` | Specify the expected SHA512 checksum of the selected backing image in Longhorn StorageClass |
| persistence.backingImage.name | string | `nil` | Specify a backing image that will be used by Longhorn volumes in Longhorn StorageClass. If not exists, the backing image data source type and backing image data source parameters should be specified so that Longhorn will create the backing image before using it |
| persistence.defaultClass | bool | `true` | Set Longhorn StorageClass as default |
| persistence.defaultClassReplicaCount | int | `3` | Set replica count for Longhorn StorageClass |
| persistence.defaultDataLocality | string | `"disabled"` | Set data locality for Longhorn StorageClass. Options: `disabled`, `best-effort` |
| persistence.defaultFsType | string | `"ext4"` | Set filesystem type for Longhorn StorageClass |
| persistence.defaultMkfsParams | string | `""` | Set mkfs options for Longhorn StorageClass |
| persistence.defaultNodeSelector.enable | bool | `false` | Enable Node selector for Longhorn StorageClass |
| persistence.defaultNodeSelector.selector | string | `""` | This selector enables only certain nodes having these tags to be used for the volume. E.g. `"storage,fast"` |
| persistence.migratable | bool | `false` | Set volume migratable for Longhorn StorageClass |
| persistence.reclaimPolicy | string | `"Delete"` | Define reclaim policy. Options: `Retain`, `Delete` |
| persistence.recurringJobSelector.enable | bool | `false` | Enable recurring job selector for Longhorn StorageClass |
| persistence.recurringJobSelector.jobList | list | `[]` | Recurring job selector list for Longhorn StorageClass. Please be careful of quotes of input. E.g., `[{"name":"backup", "isGroup":true}]` |
| persistence.removeSnapshotsDuringFilesystemTrim | string | `"ignored"` | Allow automatically removing snapshots during filesystem trim for Longhorn StorageClass. Options: `ignored`, `enabled`, `disabled` |

### CSI Settings

| Key | Description |
|-----|-------------|
| csi.attacherReplicaCount | Specify replica count of CSI Attacher. Leave blank to use default count: 3 |
| csi.kubeletRootDir | Specify kubelet root-dir. Leave blank to autodetect |
| csi.provisionerReplicaCount | Specify replica count of CSI Provisioner. Leave blank to use default count: 3 |
| csi.resizerReplicaCount | Specify replica count of CSI Resizer. Leave blank to use default count: 3 |
| csi.snapshotterReplicaCount | Specify replica count of CSI Snapshotter. Leave blank to use default count: 3 |

### Longhorn Manager Settings

Longhorn system contains user deployed components (e.g, Longhorn manager, Longhorn driver, Longhorn UI) and system managed components (e.g, instance manager, engine image, CSI driver, etc.).
These settings only apply to Longhorn manager component.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| longhornManager.log.format | string | `"plain"` | Options: `plain`, `json` |
| longhornManager.nodeSelector | object | `{}` | Select nodes to run Longhorn manager |
| longhornManager.priorityClass | string | `"longhorn-critical"` | Priority class for longhorn manager |
| longhornManager.serviceAnnotations | object | `{}` | Annotation used in Longhorn manager service |
| longhornManager.tolerations | list | `[]` | Tolerate nodes to run Longhorn manager |

### Longhorn Driver Settings

Longhorn system contains user deployed components (e.g, Longhorn manager, Longhorn driver, Longhorn UI) and system managed components (e.g, instance manager, engine image, CSI driver, etc.).
These settings only apply to Longhorn driver component.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| longhornDriver.nodeSelector | object | `{}` | Select nodes to run the Longhorn CSI driver |
| longhornDriver.priorityClass | string | `"longhorn-critical"` | Priority class for the Longhorn CSI driver |
| longhornDriver.tolerations | list | `[]` | Tolerate nodes to run the Longhorn CSI driver |

### Longhorn UI Settings

Longhorn system contains user deployed components (e.g, Longhorn manager, Longhorn driver, Longhorn UI) and system managed components (e.g, instance manager, engine image, CSI driver, etc.).
These settings only apply to Longhorn UI component.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| longhornUI.nodeSelector | object | `{}` | Select nodes to run Longhorn UI |
| longhornUI.priorityClass | string | `"longhorn-critical"` | Priority class count for Longhorn UI |
| longhornUI.replicas | int | `2` | Replica count for longhorn UI |
| longhornUI.tolerations | list | `[]` | Tolerate nodes to run Longhorn UI |

### Ingress Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ingress.annotations | string | `nil` | Ingress annotations done as key:value pairs |
| ingress.enabled | bool | `false` | Set to true to enable ingress record generation |
| ingress.host | string | `"sslip.io"` | Layer 7 Load Balancer hostname |
| ingress.ingressClassName | string | `nil` | Add ingressClassName to the Ingress Can replace the kubernetes.io/ingress.class annotation on v1.18+ |
| ingress.path | string | `"/"` | If ingress is enabled, you can set the default ingress path then you can access the UI by using the following full path {{host}}+{{path}} |
| ingress.secrets | string | `nil` | If you're providing your own certificates, please use this to add the certificates as secrets |
| ingress.secureBackends | bool | `false` | Enable this to enable that the backend service will be connected at port 443 |
| ingress.tls | bool | `false` | Set this to true to enable TLS on the ingress record |
| ingress.tlsSecret | string | `"longhorn.local-tls"` | If TLS is set to true, you must declare what secret will store the key/certificate for TLS |

### Private Registry Settings

Longhorn can be installed in an air gapped environment with private registry settings. Please refer to **Air Gap Installation** in our official site [link](https://longhorn.io/docs)

| Key | Description |
|-----|-------------|
| privateRegistry.createSecret | Set `true` to create a new private registry secret |
| privateRegistry.registryPasswd | Password used to authenticate to private registry |
| privateRegistry.registrySecret | If create a new private registry secret is true, create a Kubernetes secret with this name; else use the existing secret of this name. Use it to pull images from your private registry |
| privateRegistry.registryUrl | URL of private registry. Leave blank to apply system default registry |
| privateRegistry.registryUser | User used to authenticate to private registry |

### OS/Kubernetes Distro Settings

#### Opensift Settings

Please also refer to this document [ocp-readme](https://github.com/longhorn/longhorn/blob/master/chart/ocp-readme.md) for more details

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| openshift.enabled | bool | `false` | Enable when using openshift |
| openshift.ui.port | int | `443` | UI port in openshift environment |
| openshift.ui.proxy | int | `8443` | UI proxy in openshift environment |
| openshift.ui.route | string | `"longhorn-ui"` | UI route in openshift environment |

### Other Settings

| Key | Default | Description |
|-----|---------|-------------|
| annotations | `{}` | Annotations to add to the Longhorn Manager DaemonSet Pods. Optional. |
| enableGoCoverDir | `false` | Enable this to allow Longhorn to generate code coverage profiles |
| enablePSP | `false` | For Kubernetes < v1.25, if your cluster enables Pod Security Policy admission controller, set this to `true` to ship a built-in longhorn-psp PodSecurityPolicy which allow privileged Longhorn pods to start |
| helmPreUpgradeCheckerJob.enabled | `true` |  |
| metrics.serviceMonitor.enabled | `false` |  |

### System Default Settings

For system default settings, you can first leave blank to use default values which will be applied when installing Longhorn.
You can then change them through UI after installation.
For more details like types or options, you can refer to **Settings Reference** in our official site [link](https://longhorn.io/docs)

| Key | Description |
|-----|-------------|
| defaultSettings.allowCollectingLonghornUsageMetrics | Enabling this setting will allow Longhorn to provide additional usage metrics to https://metrics.longhorn.io/. This information will help us better understand how Longhorn is being used, which will ultimately contribute to future improvements. |
| defaultSettings.allowEmptyDiskSelectorVolume | Allow Scheduling Empty Disk Selector Volumes To Any Disk |
| defaultSettings.allowEmptyNodeSelectorVolume | Allow Scheduling Empty Node Selector Volumes To Any Node |
| defaultSettings.allowRecurringJobWhileVolumeDetached | If this setting is enabled, Longhorn will automatically attach the volume and takes snapshot/backup when it is the time to do recurring snapshot/backup. |
| defaultSettings.allowVolumeCreationWithDegradedAvailability | This setting allows user to create and attach a volume that doesn't have all the replicas scheduled at the time of creation. |
| defaultSettings.autoCleanupRecurringJobBackupSnapshot | This setting enables Longhorn to automatically cleanup the snapshot generated by a recurring backup job. |
| defaultSettings.autoCleanupSystemGeneratedSnapshot | This setting enables Longhorn to automatically clean up the system-generated snapshot after replica rebuild is done. |
| defaultSettings.autoDeletePodWhenVolumeDetachedUnexpectedly | If enabled, Longhorn will automatically delete the workload pod managed by a controller (e.g., Deployment, StatefulSet, DaemonSet, etc...) when Longhorn volume is detached unexpectedly (e.g., during Kubernetes upgrade, Docker reboot, or network disconnect). By deleting the pod, its controller restarts the pod and Kubernetes handles volume reattachment and remount. |
| defaultSettings.autoSalvage | If enabled, volumes will be automatically salvaged when all the replicas become faulty, e.g., due to network disconnection. Longhorn will try to figure out which replica(s) are usable, then use them for the volume. By default, true. |
| defaultSettings.backingImageCleanupWaitInterval | This interval in minutes determines how long Longhorn will wait before cleaning up the backing image file when there is no replica in the disk using it. |
| defaultSettings.backingImageRecoveryWaitInterval | This interval in seconds determines how long Longhorn will wait before re-downloading the backing image file when all disk files of this backing image become failed or unknown. |
| defaultSettings.backupCompressionMethod | This setting allows users to specify backup compression method. |
| defaultSettings.backupConcurrentLimit | This setting controls how many worker threads per backup concurrently. |
| defaultSettings.backupTarget | The endpoint used to access the backupstore. Available: NFS, CIFS, AWS, GCP, AZURE. |
| defaultSettings.backupTargetCredentialSecret | The name of the Kubernetes secret associated with the backup target. |
| defaultSettings.backupstorePollInterval | In seconds. The backup store poll interval determines how often Longhorn checks the backup store for new backups. Set to 0 to disable the polling. By default, 300. |
| defaultSettings.concurrentAutomaticEngineUpgradePerNodeLimit | This setting controls how Longhorn automatically upgrades volumes' engines to the new default engine image after upgrading Longhorn manager. The value of this setting specifies the maximum number of engines per node that are allowed to upgrade to the default engine image at the same time. If the value is 0, Longhorn will not automatically upgrade volumes' engines to the default version of engine image. |
| defaultSettings.concurrentReplicaRebuildPerNodeLimit | This setting controls how many replicas on a node can be rebuilt simultaneously. |
| defaultSettings.concurrentVolumeBackupRestorePerNodeLimit | This setting controls how many volumes on a node can restore the backup concurrently. Set the value to **0** to disable backup restore. |
| defaultSettings.createDefaultDiskLabeledNodes | Create default Disk automatically only on Nodes with the label "node.longhorn.io/create-default-disk=true" if no other disks exist. If disabled, the default disk will be created on all new nodes when each node is first added. |
| defaultSettings.defaultDataLocality | Longhorn volume has data locality if there is a local replica of the volume on the same node as the pod which is using the volume. |
| defaultSettings.defaultDataPath | Default path to use for storing data on a host. By default, "/var/lib/longhorn/" |
| defaultSettings.defaultLonghornStaticStorageClass | The 'storageClassName' is given to PVs and PVCs that are created for an existing Longhorn volume. The StorageClass name can also be used as a label, so it is possible to use a Longhorn StorageClass to bind a workload to an existing PV without creating a Kubernetes StorageClass object. By default, 'longhorn-static'. |
| defaultSettings.defaultReplicaCount | The default number of replicas when a volume is created from the Longhorn UI. For Kubernetes configuration, update the `numberOfReplicas` in the StorageClass. By default, 3. |
| defaultSettings.deletingConfirmationFlag | This flag is designed to prevent Longhorn from being accidentally uninstalled which will lead to data lost. |
| defaultSettings.detachManuallyAttachedVolumesWhenCordoned | Automatically detach volumes that are attached manually when the node is cordoned. |
| defaultSettings.disableRevisionCounter | This setting is only for volumes created by UI. By default, this is false, meaning there will be a revision counter file to track every write to the volume. During salvage-recovering, Longhorn will pick the replica with the largest revision counter as a candidate to recover the whole volume. If the revision counter is disabled, Longhorn will not track every write to the volume. During the salvage recovering, Longhorn will use the 'volume-head-xxx.img' file last modification time and file size to pick the replica candidate to recover the whole volume. |
| defaultSettings.disableSchedulingOnCordonedNode | Disable Longhorn manager to schedule replica on Kubernetes cordoned node. By default, true. |
| defaultSettings.disableSnapshotPurge | Temporarily prevent all attempts to purge volume snapshots. |
| defaultSettings.engineReplicaTimeout | In seconds. The setting specifies the timeout between the engine and replica(s), and the value should be between 8 and 30 seconds. The default value is 8 seconds. |
| defaultSettings.failedBackupTTL | In minutes. This setting determines how long Longhorn will keep the backup resource that was failed. Set to 0 to disable the auto-deletion. |
| defaultSettings.fastReplicaRebuildEnabled | This feature supports the fast replica rebuilding. It relies on the checksum of snapshot disk files, so setting the snapshot-data-integrity to **enable** or **fast-check** is a prerequisite. |
| defaultSettings.guaranteedInstanceManagerCPU | This integer value indicates how many percentages of the total allocatable CPU on each node will be reserved for each instance manager Pod. You can leave it with the default value, which is 12%. |
| defaultSettings.kubernetesClusterAutoscalerEnabled | Enabling this setting will notify Longhorn that the cluster is using Kubernetes Cluster Autoscaler. |
| defaultSettings.logLevel | The log level Panic, Fatal, Error, Warn, Info, Debug, Trace used in longhorn manager. Default to Info. |
| defaultSettings.nodeDownPodDeletionPolicy | Defines the Longhorn action when a Volume is stuck with a StatefulSet/Deployment Pod on a node that is down. |
| defaultSettings.nodeDrainPolicy | Define the policy to use when a node with the last healthy replica of a volume is drained. |
| defaultSettings.offlineReplicaRebuilding | This setting allows users to enable the offline replica rebuilding for volumes using v2 data engine. |
| defaultSettings.orphanAutoDeletion | This setting allows Longhorn to delete the orphan resource and its corresponding orphaned data automatically like stale replicas. Orphan resources on down or unknown nodes will not be cleaned up automatically. |
| defaultSettings.priorityClass | priorityClass for Longhorn system-managed components This setting can help prevent Longhorn components from being evicted under Node Pressure. Notice that this will be applied to Longhorn user-deployed components by default if there are no priority class values set yet, such as `longhornManager.priorityClass`. |
| defaultSettings.recurringFailedJobsHistoryLimit | This setting specifies how many failed backup or snapshot job histories should be retained. History will not be retained if the value is 0. |
| defaultSettings.recurringJobMaxRetention | Maximum number of snapshots or backups to be retained. |
| defaultSettings.recurringSuccessfulJobsHistoryLimit | This setting specifies how many successful backup or snapshot job histories should be retained. History will not be retained if the value is 0. |
| defaultSettings.removeSnapshotsDuringFilesystemTrim | This setting allows Longhorn filesystem trim feature to automatically mark the latest snapshot and its ancestors as removed and stops at the snapshot containing multiple children. |
| defaultSettings.replicaAutoBalance | Enable this setting automatically re-balances replicas when discovered an available node. |
| defaultSettings.replicaDiskSoftAntiAffinity | Allow scheduling on disks with existing healthy replicas of the same volume. By default, true. |
| defaultSettings.replicaFileSyncHttpClientTimeout | In seconds. The setting specifies the HTTP client timeout to the file sync server. |
| defaultSettings.replicaReplenishmentWaitInterval | The interval in seconds determines how long Longhorn will at least wait to reuse the existing data on a failed replica rather than directly creating a new replica for a degraded volume. |
| defaultSettings.replicaSoftAntiAffinity | Allow scheduling on nodes with existing healthy replicas of the same volume. By default, false. |
| defaultSettings.replicaZoneSoftAntiAffinity | Allow scheduling new Replicas of Volume to the Nodes in the same Zone as existing healthy Replicas. Nodes don't belong to any Zone will be treated as in the same Zone. Notice that Longhorn relies on label `topology.kubernetes.io/zone=<Zone name of the node>` in the Kubernetes node object to identify the zone. By default, true. |
| defaultSettings.restoreConcurrentLimit | This setting controls how many worker threads per restore concurrently. |
| defaultSettings.restoreVolumeRecurringJobs | Restore recurring jobs from the backup volume on the backup target and create recurring jobs if not exist during a backup restoration. |
| defaultSettings.snapshotDataIntegrity | This setting allows users to enable or disable snapshot hashing and data integrity checking. |
| defaultSettings.snapshotDataIntegrityCronjob | Unix-cron string format. The setting specifies when Longhorn checks the data integrity of snapshot disk files. |
| defaultSettings.snapshotDataIntegrityImmediateCheckAfterSnapshotCreation | Hashing snapshot disk files impacts the performance of the system. The immediate snapshot hashing and checking can be disabled to minimize the impact after creating a snapshot. |
| defaultSettings.storageMinimalAvailablePercentage | If the minimum available disk capacity exceeds the actual percentage of available disk capacity, the disk becomes unschedulable until more space is freed up. By default, 25. |
| defaultSettings.storageNetwork | Longhorn uses the storage network for in-cluster data traffic. Leave this blank to use the Kubernetes cluster network. |
| defaultSettings.storageOverProvisioningPercentage | Percentage of storage that can be allocated relative to hard drive capacity. The default is 100. |
| defaultSettings.storageReservedPercentageForDefaultDisk | The reserved percentage specifies the percentage of disk space that will not be allocated to the default disk on each new Longhorn node. |
| defaultSettings.supportBundleFailedHistoryLimit | This setting specifies how many failed support bundles can exist in the cluster. Set this value to **0** to have Longhorn automatically purge all failed support bundles. |
| defaultSettings.systemManagedComponentsNodeSelector | nodeSelector for Longhorn system-managed components |
| defaultSettings.systemManagedPodsImagePullPolicy | This setting defines the Image Pull Policy of Longhorn system managed pod. E.g. instance manager, engine image, CSI driver, etc. The new Image Pull Policy will only apply after the system-managed pods restart. |
| defaultSettings.taintToleration | taintToleration for Longhorn system-managed components |
| defaultSettings.upgradeChecker | Upgrade Checker will check for a new Longhorn version periodically. When there is a new version available, a notification will appear in the UI. By default, true. |
| defaultSettings.v2DataEngine | This allows users to activate v2 data engine based on SPDK. Currently, it is in the preview phase and should not be utilized in a production environment. |

---
Please see [link](https://github.com/longhorn/longhorn) for more information.
