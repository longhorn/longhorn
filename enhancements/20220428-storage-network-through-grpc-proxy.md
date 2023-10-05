# Storage Network Through gRPC Proxy

## Summary

Currently, Longhorn uses the Kubernetes cluster CNI network and share the network with the entire cluster resources. This makes network availability impossible to control.

We would like to have a global `Storage Network` setting to allow users to input an existing Multus `NetworkAttachmentDefinition` CR network in `<namespace>/<name>` format. Longhorn can use the storage network for in-cluster data traffics.

The segregation can achieve by replacing the engine binary calls in the Longhorn manager with gRPC connections to the instance manager. Then the instance manager will be responsible for handling the requests between the management network and storage network.

---
**_NOTE:_** There are other possible approaches we have considered to segregating the networks:

- Add Longhorn Manager to the storage network. The Manager needs to restart itself to get the secondary storage network IP, and there is no storage network segregation to the Longhorn data plane (engine & replica).

- Provide Engine/Replica with dual IPs. Code change around this approach is confusing and likely to increase maintenance complexity.
---

### Related Issues

https://github.com/longhorn/longhorn/issues/2285

https://github.com/longhorn/longhorn/issues/3546

## Motivation

### Goals

- Have a new `Storage Network` setting.

- Replace Manager engine binary calls with gRPC client to the instance manager.

- Keep using the management network for the communication between Manager and Instance Manager.

- Use the storage network for the data traffic of data plane components to the instance processes. Those are the engines and replicas in Instance Manager pods.

- Support backward compatibility of the communication between the new Manager and the old Instance Manager after the upgrade. Ensure existing engine/replicas work without issues.

### Non-goals [optional]

- Setup and configure the Multus `NetworkAttachmentDefinition` CRs.

- Monitor for `NetworkAttachmentDefintition` CRs. The user needs to ensure the traffic is reachable between pods and across different nodes. Without monitoring, Longhorn will not get notified of the update of the `NetworkAttachmentDefinition` CRs. Thus the user should create a new `NetworkAttachmentDefinition` CR and update the `storage-network` setting.

- Out-cluster data traffic. For example, backing image upload and download.


## Proposal

### Communication between Manager and Engine/Replica processes via Instance Manager gRPC proxy

- Introduce a new gRPC server in Instance Manager.

- Keep reusable connections between Manager and Instance Managers.

- Allow Manager to fall back to engine binary call when communicating with old Instance Manager.

### Storage Network

- Add a new `Storage Network` global setting.

- Add `k8s.v1.cni.cncf.io/networks` annotation to pods that involve data transfer. The annotation will use the value from the storage network setting. Multus will attach a secondary network to pods with this annotation.
  - Engine instance manager pods
  - Replica instance manager pods
  - Backing image data source pods. Data traffic between replicas and backing image data source.
  - Backing image manager pods. Data traffic in-between backing image managers.

- Add new `storageIP` to `Engine`, `Replica` and `BackingImageManager` CRD status. The storage IP will be use to communicate to the instance processes.

### User Stories

#### Story 1 - set up the storage network

As a Longhorn user / System administrator.

I have set up Multus `NetworkAttachmentDefinition` for additional network management.
And I want to segregate Longhorn in-cluster data traffic with an additional network interface.
Longhorn should provide a setting to input the `NetworkAttachmentDefinition` CR name for the storage network.

So I can guarantee network availability for Longhorn in-cluster data traffic.


#### Story 2 - upgrade

As a Longhorn user / System administrator.

When I upgrade Longhorn, the changes should support existing attached volumes.

So I can decide when to upgrade the Engine Image.


### User Experience In Detail

#### Story 1 - set up the storage network

1. I have a Kubernetes cluster with Multus installed.
1. I created `NetworkAttachmentDefinition` CR and ensured the configuration is correct.
1. I Added `<namespace>/<NetworkAttachmentDefinition name>` to Longhorn `Storage Network` setting.
1. I see setting update failed when volumes are attached.
1. I detach all volumes.
1. When updating the setting I see engine/replica instance manager pod and backing image manager pods is restarted.
1. I attach the volumes.
1. I describe Engine, Replica, and BackingImageManager, and see the `storageIP` in CR status is in the range of the `NetworkAttachmentDefinition` subnet/CIDR. I also see the `storageIP` is different from the `ip` in CR status.
1. I describe the Engine and see the `replicaAddressMap` in CR spec and status is using the storage IP.
1. I see pod logs indicate the network directions.

#### Story 2 - upgrade

1. I Longhorn v1.2.4 cluster.
1. I have healthy volumes attached.
1. I upgrade Longhorn.
1. I see volumes still attached and healthy with available engine image upgrade.
1. I cannot upgrade the volume engine image with the volume attached.
1. After I detach the volume, I can upgrade its engine image.
1. I attached the volumes.
1. I see the volumes are healthy.

### API changes

- The new global setting `Storage Network` will use the existing `/v1/settings` API.

## Design

### Overview gRPC Proxy Implementation

#### Instance Manager

- Start the gRPC proxy server with the next port to the process server. The default should be `localhost:8501`.
- The gRPC proxy service shares the same `imrpc` package name as the process server.
  ```
    Ping

    ServerVersionGet

    VolumeGet
    VolumeExpand
    VolumeFrontendStart
    VolumeFrontendShutdown

    VolumeSnapshot
    SnapshotList
    SnapshotRevert
    SnapshotPurge
    SnapshotPurgeStatus
    SnapshotClone
    SnapshotCloneStatus
    SnapshotRemove

    SnapshotBackup
    SnapshotBackupStatus
    BackupRestore
    BackupRestoreStatus
    BackupVolumeList
    BackupVolumeGet
    BackupGet
    BackupConfigMetaGet
    BackupRemove

    ReplicaAdd
    ReplicaList
    ReplicaRebuildingStatus
    ReplicaVerifyRebuild
    ReplicaRemove
  ```

#### Manager

- Create a _proxyHandler_ object to map the controller ID to an _EngineClient_ interface. The _proxyHandler_ object is shared between controllers.

- The Instance Manager Controller is responsible for the life cycle of the proxy gRPC client. For every enqueue:
  - Check for the existing gRPC client in the _proxyHandler_, and check the connection liveness with the `Ping` request.
  - If the proxy gRPC client connection is dead, stop the proxy gRPC client and error so it will re-queue.
  - If the proxy gRPC client doesn't exist in the _proxyHandler_, start a new gRPC connection and map it to the current controller ID.
  - Do not create the proxy gRPC connection when the instance manager version is less than the current version. We will provide the fallback interface caller provided when getting the client.

- The gRPC client will use the _EngineClient_ interface.
  - Provide a fallback interface caller when getting the gRPC client from the _proxyHandler_. The fallback callers are:
    -  the existing `Engine` client used for the binary call
    -  `BackupTargetClient`.
  - Use the fallback caller when the instance manager version is less than the current version.
  - Add new `BackupTargetBinaryClient` interface for fallback.
    ```
    type BackupTargetBinaryClient interface {
	    BackupGet(destURL string, credential map[string]string) (*Backup, error)
	    BackupVolumeGet(destURL string, credential map[string]string) (volume *BackupVolume, err error)
	    BackupNameList(destURL, volumeName string, credential map[string]string) (names []string, err error)
	    BackupVolumeNameList(destURL string, credential map[string]string) (names []string, err error)
	    BackupDelete(destURL string, credential map[string]string) (err error)
	    BackupVolumeDelete(destURL, volumeName string, credential map[string]string) (err error)
	    BackupConfigMetaGet(destURL string, credential map[string]string) (*ConfigMetadata, error)
    }
    ```
  - Introduce A new `EngineClientProxy` interface for the Proxy, which includes proxy-specific methods and implementation of the existing `EnglineClient` and `BackupTargetClient` interfaces. This will be adaptive when using the EngineClient interface for the proxy or non-proxy/fallback operations.
    ```
    type EngineClientProxy interface {
      EngineClient
      BackupTargetBinaryClient

      IsGRPC() bool
      Start(*longhorn.InstanceManager, logrus.FieldLogger, *datastore.DataStore) error
      Stop(*longhorn.InstanceManager) error
      Ping() error
    }
    ```

### Overview Storage Network Overview Implementation

#### Setting

Add a new global setting `Storage Network`.
- The setting is `string`.
- The default value is `""`.
- The setting should be in the `danger zone` category.
- The setting will be validated at admission webhook setting validator.
  - The setting should be in the form of `< NAMESPACE>/<NETWORK-ATTACHMENT-DEFINITION-NAME>`.
  - The setting cannot be updated when volumes are attached.

#### CRD

Engine:
- New `storageIP` in status.
- Use the replica `status.storageIP` instead of the replica `status.IP` for the replicaAddressMap.

Replica:
- New `storageIP` in status.

BackingImageManager:
- New `storageIP` in status.

#### Instance Manager Controller

1. When creating instance manager pods, add `k8s.v1.cni.cncf.io/networks` annotation with `lhnet1` as interface name. Use the `storage-network` setting value for the namespace and name.
    ```
    k8s.v1.cni.cncf.io/networks: '
      [
        {
          "namespace": "kube-system",
          "name": "demo-10-30-0-0",
          "interface": "lhnet1"
        }
      ]
    '
    ```

#### Instance Handler

1. Get the IP from instance manager Pod annotation `k8s.v1.cni.cncf.io/network-status`. Use the IP for `Engine` and `Replica` Storage IP. When the `storage-network` setting is empty, The Storage IP will be the pod IP.

#### Backing Image Manager Controller

1. When creating backing image manager pods, add `k8s.v1.cni.cncf.io/networks` annotation with `lhnet1` as interface name. Use the `storage-network` setting value for the namespace and name.
    ```
    k8s.v1.cni.cncf.io/networks: '
      [
        {
          "namespace": "kube-system",
          "name": "demo-10-30-0-0",
          "interface": "lhnet1"
        }
      ]
    '
    ```
1. Get the IP from backing image manager Pod annotation `k8s.v1.cni.cncf.io/network-status`. Use the IP for `BackingImageManager` Storage IP. When the `storage-network` setting is empty, The Storage IP will be the pod IP.

#### Backing Image Data Source Controller

1. When creating backing image data source pods, add `k8s.v1.cni.cncf.io/networks` annotation with `lhnet1` as interface name. Use the `storage-network` setting value for the namespace and name.
    ```
    k8s.v1.cni.cncf.io/networks: '
      [
        {
          "namespace": "kube-system",
          "name": "demo-10-30-0-0",
          "interface": "lhnet1"
        }
      ]
    '
    ```

#### Backing Image Manager - Export From volume

1. get the IPv4 of the `lhnet1` interface and use it as the receiver address. Use the pod IP if the interface doesn't exist.

#### Setting Controller

1. Do not update the `storage-network` setting and return an error when `Volumes` are attached.
1. Delete all backing image manager pods.
1. Delete all instance manager pods.


### Test plan

#### CI Pipeline

All existing tests should pass when the cluster has the storage network configured. We should consider having a new test pipeline for the storage network.

Infra Prerequisites:
- Secondary network interface added to each cluster instance.
- Multus deployed.
- Network-attachment-definition created.
- Routing is configured in all cluster nodes to ensure the network is accessible between instances.
- For AWS, disable network source/destination checks for each cloud-provider instance.

#### Test storage-network setting

Scenario: `Engine`, `Replica` and `BackingImageManager` should use IP in `storage-network` `NetworkAttachmentDefinition` subnet/CIDR range after setting update.

### Upgrade strategy

[Some old instance manager pods are still running after upgrade](https://longhorn.io/kb/troubleshooting-some-old-instance-manager-pods-are-still-running-after-upgrade/).
Old engine instance managers do not have the gRPC proxy server for Manager to communicate.
Hence, we need to support backward compatibility.

Manager communication:
- Bump instance manager API version.
- Manager checks for incompatible version and fall back to requests through the engine binary.

Volume/Engine live upgrade:
- Keep live upgrade. This will be a soft notice for users to know we will not enforce any change in 1.3, but it will happen in 1.4.

## Note [optional]

`None`
