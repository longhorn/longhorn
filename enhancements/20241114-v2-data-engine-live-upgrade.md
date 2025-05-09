# V2 Data Engine Live Upgrade

## Summary

The document proposes a solution for upgrading Longhorn's v2 data engine. In contrast to the v1 data engine, which allows live upgrades on a per-volume basis, the v2 data engine only supports upgrades at the node level.

### Related Issues

## Motivation

### Goals

- Support v2 data engine upgrade at the node level
- No need to detach v2 volumes before upgrading v2 data engine

### Non-goals [optional]

- Support v2 data engine upgrade on a per-volume basis

## Proposal

### User Stories

As a Longhorn user, I want to upgrade the v2 data engine without needing to detach v2 volumes and interrupt services.

### User Experience In Detail

The steps to upgrade the v2 data engine of Longhorn nodes

1.  Upgrade the Longhorn system by helm upgrade, manifest or other method.
    
2.  After upgrading, an instance-manager resource with the default instance manager image is created on each node but remains in
    

- `stopped`: if the running instance-manager pod using an old instance manager image still contains running replicas or engines.
- `running`: if the old instance-manager is deleted because it does not contains running replicas and engines.

3.  Create a `DataEngineUpgradeManager` resource
    ```
    apiVersion: longhorn.io/v1beta2
    kind: DataEngineUpgradeManager
    metadata:
      name: upgrade
      namespace: longhorn-system
    spec:
      dataEngine: v2
    ```
    
4.  User can observe the nodes in the cluster being upgraded one by one. During the upgrade of a node’s v2 data engine, an `NodeDataEngineUpgrade` resource for the upgrading node is created. The old instance manager and its pod are deleted, causing the replicas to enter an `error` state. The default instance manager pod then starts and transitions to a `running` state, after which the replicas in the `error` state are automatically rebuilt and becomes `running`. If the upgrade process is stalled, users can check the status of the `NodeDataEngineUpgrade` resource to troubleshoot issues and resume the upgrade process.
    

## CRDs

### New CRDs

Two CRDs, `DataEngineUpgradeManager` and `NodeDataEngineUpgrade`, are introduced. The `DataEngineUpgradeManager` controls and oversees the overall v2 data engine upgrade process and provides a global view of the upgrade status, while the `NodeDataEngineUpgrade` manages the upgrade process at the node level.

- dataEngineUpgradeManager.longhorn.io

```
spec:
    DataEngine DataEngineType
    Nodes []string
status:
    OwnerID string
    InstanceManagerImage string
    State UpgradeState
    Message string
    UpgradingNode string
    UpgradeNodes map[string]*UpgradeNodeStatus
```

- nodeDataEngineUpgrade.longhorn.io

```
spec:
    NodeID string
    DataEngine DataEngineType
    InstanceManagerImage string
    DataEngineUpgradeManager string
status:
    OwnerID string
    Volumes map[string]*VolumeUpgradeStatus
    State UpgradeState
    Message string
```

### CRD Changes

- node.longhorn.io

```
spec:
	...
	// Request to upgrade the instance manager for v2 volumes on the node.
	// +optional
	DataEngineUpgradeRequested bool `json:"dataEngineUpgradeRequested"`
status:
	...
```

- volume.longhorn.io

```
spec:
	...
	// TargetNodeID is specifies the node where the volume's initiator instance should be scheduled during data engine live upgrade.
	// +optional
	TargetNodeID string `json:"targetNodeID"`
status:
	...
	// +optional
	CurrentTargetNodeID string `json:"currentTargetNodeID"`
```

- InstanceSpec

```
	...
	// TargetNodeID is specifies the node where the volume's initiator instance should be scheduled during data engine live upgrade.
	// +optional
	TargetNodeID string `json:"targetNodeID"`
```

- InstanceStatus

```
	...
	// +optional
	TargetIP string `json:"targetIP"`
	// +optional
	StorageTargetIP string `json:"storageTargetIP"`
	// +optional
	TargetPort int `json:"targetPort"`
	...
	// +optional
	CurrentTargetNodeID string `json:"currentTargetNodeID"`
	// +optional
	TargetInstanceReplacementCreated bool `json:"targetInstanceReplacementCreated"`
```

- InstanceProcessStatus

```
	...
    // +optional
	StandbyTargetPortEnd int32 `json:"standbyTargetPortEnd"`
	// +optional
	StandbyTargetPortStart int32 `json:"standbyTargetPortStart"`
	...
```

- InstanceState

```
const (
	...
	InstanceStateSuspended = InstanceState("suspended")
	...
)
```



### Webhook Validation

1.  When the v2 data engine of a node is being upgraded (i.e., `node.spec.dataEngineUpgradeRequested` is `true`), the volume attachment will be rejected, but detachment is allowed.

### Webhook Mutation

## Controllers

### DataEngineUpgradeManager Controller

- Create one `DataEngineUpgradeManager` CR for the whole cluster
- Monitor the `DataEngineUpgradeManager` CRs

### NodeDataEngineUpgrade Controller

- Perform the node upgrade process for the v2 data engine

## Design

### Work Flow and State Transition

![Architecture Diagram](image/v2-data-engine-live-upgrade/arch-diagram.svg)

1.  Create a `DataEngineUpgradeManager` resource
    
2.  According to `DataEngineUpgradeManager.Status.State`, `DataEngineUpgradeManager Controller` does
    
    - `undefined`
        1.  Update `status.instanceManagerImage` from `defaultInstanceManagerImage` setting
        2.  Check whether the default instance manager image has be pulled on each Longhorn node. If not, update `status.State` to `error` and `status.ErrorMessage`
        3.  Update `status.state` to `initializing`

    - `initializing`  
        1. Update `status.upgradeNodes`  
          - If `spec.nodes` is empty, list all nodes and add them to `status.upgradeNodes`  
          - If `spec.nodes` is not empty, list the nodes in the `spec.nodes` and add them to `status.upgradeNodes`  
        2. Then, update the `status.currentState` to `upgrading`
        
    - `upgrading`  
        1. Iterate `status.upgradeNodes`  
        2. Find a node that is not upgraded and create a `nodeDataEngineUpgrade` resource
        3. Set the node to `status.upgradingNode`
        4. Update the `status.currentState` to `completed` if all nodes are finished
        
    - `completed`
        
3.  According to `NodeDataEngineUpgrade.status.state`, `NodeDataEngineUpgrade controller` does
    
    - `undefined`
        1.  Update `status.currentState` to `initializing`

    - `initializing`        
        1.  Set upgrading node to **unscheduable** by setting `node.spec.upgradeRequested` to `true`
        2.  List volumes on upgrading node
        3.  Snapshot all volumes
        4.  Update `status.volumes`
        5.  Update `status.currentState` to `failing-replicas`

    - `failing-replicas`
        1. List the replicas on the upgrading node and delete them from its engines
        2. Make sure all the replicas are stopped or failed
        3. Delete the stopped these stopped or failed replicas. (Will be removed after supporting reusing failed replica)
        4. Update `status.currentState` to `switching-over`

    - `switching-over`        
        1.  Find a available node for target instance replacement creation
        2.  Update attached volumes: update `volume.spec.targetNodeID` and `volume.spec.image`
        3.  Waiting for the target instances of attached volumes are switched over

    - `upgrading-instance-manager`        
        1.  Delete old instance-manager
        2.  Waiting for the default instance-manager becomes running

    - `switching-back`        
        1.  Update attached volumes: update `volume.spec.targetNodeID` as `volume.spec.NodeID`
        2.  Waiting for the attached volumes are switched backup

    - `rebuilding-replica`        
        1.  Waiting for the volumes become `healthy`
        2.  Waiting for the replicas become `running`

	- `finalizing`
		1. Update the `volume.spec.image` of detached volumes to default instance manager image
 
    - `completed`

## Test Plan

1. Single-node Longhorn cluster is not allowed to performance v2 data engine live upgrade.

2.  Test the different setups that fail to upgrade
    
    - Case 1  
        Reason: single replica of vol-1
        
        | node 1 | node 2 | node 3 |
        | --- | --- | --- |
        | **vol-1-e** |     |     |
        | vol-1-r-1 |     |     |
        | **vol-2-e** |     |     |
        | vol-2-r-1 | vol-2-r-2 | vol-2-r-3 |
        | **vol-3-e** |     |     |
        | vol-3-r-1 | vol-3-r-2 | vol-3-r-3 |
        
    - Case 2  
        Reason: single replica of vol-1
        
        | node 1 | node 2 | node 3 |
        | --- | --- | --- |
        | **vol-1-e** |     |     |
        |     | vol-1-r-1 |     |
        | **vol-2-e** |     |     |
        | vol-2-r-1 | vol-2-r-2 | vol-2-r-3 |
        | **vol-3-e** |     |     |
        | vol-3-r-1 | vol-3-r-2 | vol-3-r-3 |
        
3.  Test the different setups that succeed to upgrade
    
    - Case 1
        
        | node 1 | node 2 | node 3 |
        | --- | --- | --- |
        | **vol-1-e** |     |     |
        | vol-1-r-1 | vol-1-r-2 | vol-1-r-3 |
        | **vol-2-e** |     |     |
        | vol-2-r-1 | vol-2-r-2 | vol-2-r-3 |
        | **vol-3-e** |     |     |
        | vol-3-r-1 | vol-3-r-2 | vol-3-r-3 |
        
    - Case 2
        
        | node 1 | node 2 | node 3 |
        | --- | --- | --- |
        | **vol-1-e** |     |     |
        |     | vol-1-r-1 | vol-1-r-2 |
        | **vol-2-e** |     |     |
        |     | vol-2-r-1 | vol-2-r-2 |
        | **vol-3-e** |     |     |
        |     | vol-3-r-1 | vol-3-r-2 |
        
    - Case 3
        
        | node 1 | node 2 | node 3 |
        | --- | --- | --- |
        | **vol-1-e** |     |     |
        | vol-1-r-1 | vol-1-r-2 | vol-1-r-3 |
        |     | **vol-2-e** |     |
        | vol-2-r-1 | vol-2-r-2 | vol-2-r-3 |
        |     |     | **vol-3-e** |
        | vol-3-r-1 | vol-3-r-2 | vol-3-r-3 |
        

## Note [optional]

- [ ] Handle replica replenishment (Volume is being upgraded, skip replenishReplicas)
- [ ] Upgrading node shouldn’t support backup (handled in the isResponsibleFor())