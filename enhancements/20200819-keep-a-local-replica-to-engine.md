# Data Locality - Option To Keep A Local Replica On The Same Node As The Engine

## Summary

A Longhorn volume can be backed by replicas on some nodes in the cluster and accessed by a pod running on any node in the cluster. 
In the current implementation of Longhorn, the pod which uses Longhorn volume could be on a node that doesn't contain any replica of the volume. 
In some cases, it is desired to have a local replica on the same node as the consuming pod. 
In this document, we refer to the property of having a local replica as having `data locality`

This enhancement gives the users option to have a local replica on the same node as the engine which means on the same node as the consuming pod. 

### Related Issues

https://github.com/longhorn/longhorn/issues/1045

## Motivation

### Goals

Provide users an option to try to migrate a replica to the same node as the consuming pod.

### Non-goals

Another approach to achieve data locality is trying to influence Kubernetes scheduling decision so that pods get scheduled onto the nodes which contain volume's replicas.
However, this is not a goal in this LEP. See https://github.com/longhorn/longhorn/issues/1045 for more discussion about this approach. 

## Proposal

We give user 2 options for data locality setting: `disabled` and `best-effort`. 
In `disabled` mode, there may be a local replica of the volume on the same node as the consuming pod or there may not be. 
Longhorn doesn't do anything.
In `best-effort` mode, if a volume is attached to a node that has no replica, the Volume Controller will start rebuilding the replica on the node after the volume is attached. 
Once the rebuilding process is done, it will remove one of the other replicas to keep the replica count as specified.

### User Stories

Sometimes, having `data locality` is critical. 
For example, when the network is bad or the node is temporarily disconnected, having local replica will keep the consuming pod running. 
Another case is that sometimes the application workload can do replication itself (e.g. database) and it wants to have a volume of 1 replica for each pod. 
Without the `data locality` feature, multiple replicas may end up on the same node which destroys the replication intention of the workload. See more in [Story 1](#story-2)
 
In the current implementation of Longhorn, the users cannot ensure that pod will have a local replica. 
After the enhancement implemented, users can have options to choose among `disabled` (default setting) or `best-effort`

#### Story 1

A user has three hyper-converged nodes and default settings with: `default-replica-count: 2`. 
He wants to ensure a pod always runs with at least one local replica would reduce the amount of network traffic needed to keep the data in sync. 
There does not appear to be an obvious way for him to schedule the pod using affinities.

#### Story 2

A user runs a database application that can do replication itself. 
The database app creates multiple pods and each pod uses a Longhorn volume with `replica-count = 1`. 
The database application knows how to schedule pods into different nodes so that they achieve HA. 
The problem is that replicas of multiple volumes could land on the same node which destroys the HA capability. 
With the `data locality` feature we can ensure that replicas are on the same nodes with the consuming pods and therefore they are on different nodes.

### User Experience In Detail

* Users create a new volume using Longhorn UI with `dataLocality` set to `best-effort`. 
* If users attach the volume a node which doesn't contain any replica, they will see that Longhorn migrate a local replica to the node.
* Users create a storageclass with dataLocality: best-effort set
* Users launch a statefulset with the storageclass.
* Users will find that there is always a replica on the node where the pod resides on
* Users update  `dataLocality` to `disable`, detach the volume, and attach it to a node which doesn't have any replica
* Users will see that Longhorn does not create a local replica on the new node.

### API changes

There are 2 API changes:
1. When creating a new volume, the body of the request sent to `/v1/volumes` has a new field `dataLocality` set to either `disabled` or `best-effort`.
1. Implement a new API for users to update `dataLocality` setting for individual volume.
The new API could be `/v1/volumes/<VOLUME_NAME>?action=updateDataLocality`. This API expects the request's body to have the form `{dataLocality:<DATA_LOCALITY_MODE>}`.

## Design

### Implementation Overview
There are 2 modes for `dataLocality`:
1. `disabled` is the default mode. 
   There may be a local replica of the volume on the same node as the consuming pod or there may not be. 
   Longhorn doesn't do anything.
1. `best-effort` mode instructs Longhorn to try to keep a local replica on the same node as the consuming pod. 
   If Longhorn cannot keep the local replica (due to not having enough disk space, incompatible disk tags, etc...), Longhorn does not stop the volume.

There are 3 settings the user can change for `data locality`:

1. Global default setting inside Longhorn UI settings.
   The global setting should only function as a default value, like replica count. 
   It doesn't change any existing volume's setting
1. specify `dataLocality` mode for individual volume upon creation using UI
1. specify `dataLocality` mode as a parameter on Storage Class.

Implementation steps:

1. Add a global setting `DefaultDataLocality`
1. Add the new field `DataLocality` to `VolumeSpec`
1. Modify the volume creation API so that it extracts, verifies, and sets the `dataLocality` mode for the new volume.
If the volume creation request doesn't have `dataLocality` field inside its body, we use the `DefaultDataLocality` for the new volume.
1. Modify the `CreateVolume` function inside the CSI package so that it extracts, verifies, and sets the `dataLocality` mode for the new volume.
This makes sure that Kubernetes can use CSI to create Longhorn volume with a specified `datLocality` mode.
1. Inside `volume controller`'s sync logic, we add a new function `ReconcileLocalReplica`.
1. When a volume enters the `volume controller`'s sync logic, function `ReconcileLocalReplica` checks the `dataLocality` mode of the volume.
   If the `dataLocality` is `disabled`, it will do nothing and return.
1. If the `dataLocality` is `best-effort`, `ReconcileLocalReplica` checks whether there is a local replica on the same node as the volume.
   1. If there is no local replica, we create an in-memory replica struct.
      We don't create a replica in DS using createReplica() directly because we may need to delete the new replica if it fails to ScheduleReplicaToNode.
   	  This prevents UI from repeatedly show creating/deleting the new replica.
      Then we try to schedule the replica struct onto the consuming pod's node.
      If the scheduling fails, we don't do anything. The replica struct will be collected by Go's garbage collector.
      If the scheduling success, we save the replica struct to the data store. This will trigger replica rebuilding on the consuming pod's node.
   1. If there already exists a local replica on the consuming pod's node, we check to see if there are more healthy replica than specified on the volume's spec.
      If there are more healthy replicas than specified on the volume's spec, we remove a replica on the other nodes. 
      We prefer to delete replicas on the same disk, then replicas on the same node, then replicas on the same zone.

UI modification:
1. On volume creation, add an input field for `dataLocality`
1. On volume detail page:
   * On the right volume info panel, add a <div> to display `selectedVolume.dataLocality`
   * On the right volume panel, in the Health row, add an icon for data locality status. 
     Specifically, if  `dataLocality=best-effort` but there is not a local replica then display a warning icon.
     Similar to the replica node redundancy warning [here](https://github.com/longhorn/longhorn-ui/blob/0a52c1f0bef172d8ececdf4e1e953bfe78c86f29/src/routes/volume/detail/VolumeInfo.js#L47)
   * In the volume's actions dropdown, add a new action to update `dataLocality`
1. In Rancher UI, add a parameter `dataLocality` when create storage class using Longhorn provisioner. 
   
### Test plan

#### Manually Test Plan
1. Create a cluster of 9 worker nodes and install Longhorn. 
Having more nodes helps us to be more confident because the chance of randomly scheduling a replica onto the same node as the engine is small.

##### Test volume creation with `dataLocality` is `best-effort`:

1. Create volume `testvol` with `Number of Replicas = 2` and `dataLocality` is `best-effort`
1. Attach `testvol` to a node that doesn't contain any replica.
1. Verify that Longhorn schedules a local replica to the same node as the consuming pod. 
   After finishing rebuilding the local replica. Longhorn removes a replica on other nodes to keep the number of replicas is 2.

##### Test volume creation with `dataLocality` is `disabled`:

1. Create another volume, `testvol2`  with `Number of Replicas = 2` and `dataLocality` is `disabled`
1. Attach `testvol2` to a node that doesn't contain any replica.
1. Verify that Longhorn doesn't move replica

##### Test volume creation with `dataLocality` is unspecified and `DefaultDataLocality` setting as `disabled`:
1. Leave the `DefaultDataLocality` setting as `disabled` in Longhorn UI.
1. Create another volume, `testvol3`  with `Number of Replicas = 2` and `dataLocality` is empty
1. Attach `testvol3` to a node that doesn't contain any replica.
1. Verify that the `dataLocality` of `testvol3` is `disabled` and that Longhorn doesn't move replica.

##### Test volume creation with `dataLocality` is unspecified and `DefaultDataLocality` setting as `best-effort`:
1. Set the `DefaultDataLocality` setting to `best-effort` in Longhorn UI.
1. Create another volume, `testvol4`  with `Number of Replicas = 2` and `dataLocality` is empty
1. Attach `testvol4` to a node that doesn't contain any replica.
1. Verify that the `dataLocality` of `testvol4` is `best-effort`.
1. Verify that Longhorn schedules a local replica to the same node as the consuming pod. 
   After finishing rebuilding the local replica. 
   Longhorn removes a replica on other nodes to keep the number of replicas is 2.

##### Test `updateDataLocality` from `disabled` to `best-effort`:
1. Change `dataLocality` to `best-effort` for `testvol2`
1. Verify that Longhorn schedules a local replica to the same node as the consuming pod. 
   After finishing rebuilding the local replica. 
   Longhorn removes a replica on other nodes to keep the number of replicas which is 2.
   
##### Test `updateDataLocality` from `best-effort` to `disabled` :
1. Change `dataLocality` to `disabled` for `testvol2`
1. Go to Longhorn UI, increase the `number of replicas` to 3. Wait until the new replica finishes rebuilding.
1. Delete the local replica on the same node as the consuming pod.
1. Verify that Longhorn doesn't move replica 

##### Test volume creation by using storage class with `dataLocality` parameter is `disabled`:
1. Create `disabled-longhorn` storage class with from this yaml file:
    ```yaml
    kind: StorageClass
    apiVersion: storage.k8s.io/v1
    metadata:
      name: disabled-longhorn
    provisioner: driver.longhorn.io
    allowVolumeExpansion: true
    parameters:
      numberOfReplicas: "1"
      dataLocality: "disabled"
      staleReplicaTimeout: "2880" # 48 hours in minutes
      fromBackup: ""
    ```
1. create a deployment of 1 pod using PVC dynamically created by `disabled-longhorn` storage class.
1. The consuming pod is likely scheduled onto a different node than the replica. 
   If this happens, verify that Longhorn doesn't move replica
   
##### Test volume creation by using storage class with `dataLocality` parameter is `best-effort`:
1. Create `best-effort-longhorn` storage class with from this yaml file:
    ```yaml
    kind: StorageClass
    apiVersion: storage.k8s.io/v1
    metadata:
      name: best-effort-longhorn
    provisioner: driver.longhorn.io
    allowVolumeExpansion: true
    parameters:
      numberOfReplicas: "1"
      dataLocality: "best-effort"
      staleReplicaTimeout: "2880" # 48 hours in minutes
      fromBackup: ""
    ```
1. create a shell deployment of 1 pod using the PVC dynamically created by `best-effort-longhorn` storage class.
1. The consuming pod is likely scheduled onto a different node than the replica. 
1. If this happens, verify that Longhorn schedules a local replica to the same node as the consuming pod. 
   After finishing rebuilding the local replica, Longhorn removes a replica on other nodes to keep the number of replicas which is 1.
1. verify that the volume CRD has `dataLocality` is `best-effort`

##### Test volume creation by using storage class with `dataLocality` parameter is unspecified`:
1. Create `unspecified-longhorn` storage class with from this yaml file:
    ```yaml
    kind: StorageClass
    apiVersion: storage.k8s.io/v1
    metadata:
      name: unspecified-longhorn
    provisioner: driver.longhorn.io
    allowVolumeExpansion: true
    parameters:
      numberOfReplicas: "1"
      staleReplicaTimeout: "2880" # 48 hours in minutes
      fromBackup: ""
    ```
1. create a shell deployment of 1 pod using PVC dynamically created by `unspecified-longhorn` storage class.
1. The consuming pod is likely scheduled onto a different node than the replica. 
1. If this happens, depend on `DefaultDataLocality` setting in Longhorn UI, verify that Longhorn does/doesn't migrate a local replica to the same node as the consuming pod.

#####  Tests for the volumes created in old versions:

1. The volumes created in old Longhorn versions don't have the field `dataLocality`. 
1. We treat those volumes the same as having `dataLocality` set to `disabled`
1. Verify that Longhorn doesn't migrate replicas for those volumes. 

### Upgrade strategy

No special upgrade strategy is required.

We are adding the new field, `dataLocality`, to volume CRD's spec.
Then we use this field to check whether we need to migrate a replica to the same node as the consuming pod.
When users upgrade Longhorn to this new version, it is possible that some volumes don't have this field.
This is not a problem because we only migrate replica when `dataLocality` is `best-effort`.
So, the empty `dataLocality` field is fine.
