#  Improve Node Failure Handling By Automatically Force Delete Terminating Pods of StatefulSet/Deployment On Down Node

## Summary

Kubernetes never force deletes pods of StatefulSet or Deployment on a down node. Since the pod on the down node wasn't removed, the volume will be stuck on the down node with it as well. The replacement pods cannot be started because the Longhorn volume is RWO (see more about access modes [here](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes)), which can only be attached to one node at a time.  We provide an option for users to help them automatically force delete terminating pods of StatefulSet/Deployment on the down node. After force deleting, Kubernetes will detach Longhorn volume and spin up replacement pods on a new node.

### Related Issues

https://github.com/longhorn/longhorn/issues/1105

## Motivation

### Goals

The goal is to help the users to monitor node status and automatically force delete terminating pods on down nodes. Without this feature, users would have to manually force delete the pods so that new replacement pods can be started.


## Proposal

Implemented a mechanism to force delete pods in the Deployment/StatefulSet on a down node. There are 4 options for `NodeDownPodDeletionPolicy`:
* `DoNothing`
* `DeleteStatefulSetPod`
* `DeleteDeploymentPod`
* `DeleteBothStatefulsetAndDeploymentPod`

When the setting is enabled, Longhorn will monitor node status and force delete pods on the down node on the behalf of users.


### User Stories
Before this feature is implemented, the users would have to manually monitor and force delete pods when a node down so that Longhorn volume can be detached and a new replacement pod can start. 

This process should be automated. After this feature is implemented, the users can have the option to allow Longhorn to monitor and force delete the pods on their behalf.

### User Experience In Detail
To use this enhancement, users need to change the Longhorn setting `NodeDownPodDeletionPolicy`. The default setting is `DoNothing` which means Longhorn will not force delete any pods on a down node. 

As a side note, even when `NodeDownPodDeletionPolicy` is set to `do-nothing`, the [automatic VolumeAttachment removal](https://longhorn.io/docs/1.0.2/high-availability/node-failure/#volume-attachment-recovery-policy) still works so deployment pods are fine if users enable automatic `volumeattachment` removal.

### API changes
No API changes.

## Design
We created a new controller, `Kubernetes POD Controller`, to watch pods and nodes status and handle the force deletion. Force delete a pod when all of the below conditions are met:

1. The `NodeDownPodDeletionPolicy` and pods' owner are as in the below table:

    | Policy \ Kind |  `StatefulSet` | `ReplicaSet` | Other |
    | :------------- | :----------: | :----------: | :----------: |
    | `DoNothing` | Don't delete  | Don't delete  | Don't delete  |
    | `DeleteStatefulSetPod` | Force delete  | Don't delete  | Don't delete  |
    | `DeleteDeploymentPod` | Don't delete   | Force delete  | Don't delete  |
    | `DeleteBothStatefulsetAndDeploymentPod` | Force delete  | Force delete  | Don't delete  |

1. Node containing the pod is down which is determined by the [IsNodeDownOrDeleted](https://github.com/longhorn/longhorn-manager/blob/34c40abf2dabf5f25541a36917568c37e21af3ea/datastore/longhorn.go#L1015). The function `IsNodeDownOrDeleted` checks whether the node status is `NotReady`
1. The pod is terminating (which means the pod has deletionTimestamp set) and the DeletionTimestamp has passed.
1. Pod has a PV with provisioner `driver.longhorn.io`

### Implementation Overview
Same as the Design

### Test plan
1. Setup a cluster of 3 nodes
1. Install Longhorn and set `Default Replica Count = 2` (because we will turn off one node)
1. Create a StatefulSet with 2 pods using the command:
    ```
    kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/master/examples/statefulset.yaml
    ```
1. Create a volume + pv + pvc named `vol1` and create a deployment of default ubuntu named `shell` with the usage of pvc `vol1` mounted under `/mnt/vol1`
1. Find the node which contains one pod of the StatefulSet/Deployment. Power off the node

#### StatefulSet
##### if `NodeDownPodDeletionPolicy ` is set to `do-nothing ` | `delete-deployment-pod`
- wait till the `pod.deletionTimestamp` has passed
- verify no replacement pod generated, the pod is stuck at terminating forever.

##### if `NodeDownPodDeletionPolicy ` is set to `delete-statefulset-pod ` | `delete-both-statefulset-and-deployment-pod`
- wait till pod's status becomes `terminating` and the `pod.deletionTimestamp` has passed (around 7 minutes)
- verify that the pod is deleted and there is a new running replacement pod. 
- Verify that you can access/read/write the volume on the new pod

#### Deployment
##### if `NodeDownPodDeletionPolicy ` is set to `do-nothing ` | `delete-statefulset-pod` AND `Volume Attachment Recovery Policy` is `never`
- wait till the `pod.deletionTimestamp` has passed
- replacement pod will be stuck in `Pending` state forever
- force delete the terminating pod
- wait till replacement pod is running
- verify that you can access `vol1` via the `shell` replacement pod under `/mnt/vol1` once it is in the running state
##### if `NodeDownPodDeletionPolicy ` is set to `do-nothing ` | `delete-statefulset-pod` AND `Volume Attachment Recovery Policy` is `wait`
- wait till replacement pod is generated (default is around 6 minutes, kubernetes setting)
- wait till the `pod.deletionTimestamp` has passed
- verify that you can access `vol1` via the `shell` replacement pod under `/mnt/vol1` once it is in the running state
- verify that the original `shell` pod is stuck in `Pending` state forever
##### if `NodeDownPodDeletionPolicy ` is set to `do-nothing ` | `delete-statefulset-pod` AND `Volume Attachment Recovery Policy` is `immediate`
- wait till replacement pod is generated (default is around 6 minutes, kubernetes setting)
- verify that you can access `vol1` via the `shell` replacement pod under `/mnt/vol1` once it is in the running state
- verify that the original `shell` pod is stuck in `Pending` state forever
##### if `NodeDownPodDeletionPolicy ` is set to `delete-deployment-pod ` | `delete-both-statefulset-and-deployment-pod` AND `Volume Attachment Recovery Policy` is `never`| `wait`|`immediate`
- wait till the `pod.deletionTimestamp` has passed
- verify that the pod is deleted and there is a new running replacement pod. 
- verify that you can access `vol1` via the `shell` replacement pod under `/mnt/vol1`
#### Other kinds
- Verify that Longhorn never deletes any other pod on the down node.
#### Test example
One typical scenario when the enhancement has succeeded is as below. When a node (say `node-x`) goes down (assume using Kubernetes' default settings and user allows Longhorn to force delete pods):

| Time | Event | 
| :------------- | :----------: | 
| 0m:00s | `node-x`goes down and stops sending heartbeats to Kubernetes Node controller  |
| 0m:40s | Kubernetes Node controller reports `node-x` is `NotReady`.    |
| 5m:40s | Kubernetes Node controller starts evicting pods from `node-x` using graceful termination (set `DeletionTimestamp` and `deletionGracePeriodSeconds = 10s/30s`)  |
| 5m:50s/6m:10s | Longhorn forces delete the pod of StatefulSet/Deployment which uses Longhorn volume |


### Upgrade strategy
Doesn't impact upgrade.
