# Live Upgrade For Data Engine of V2 Volumes

## Summary

The LEP outlines the live upgrade process for the data engine of v2 volumes.

## Related Issues

[[FEATURE] v2 volume supports live upgrade for data plane · Issue #6001 · longhorn/longhorn (github.com)](https://github.com/longhorn/longhorn/issues/6001)

## Motivation

### Goals

- Support both destructive and live upgrades of the data engine for a v2 volume with multiple replicas.
- Upgrade volumes one node at a time.

### Non-goals [optional]

- Support live upgrades of the data engine for a v2 volume with a single replica.
- Support concurrent upgrades of nodes.

## Proposal

### User Stories

After upgrading the Longhorn system, users may want to upgrade the data engine of active v2 volumes to access new features or bug fixes without service interruption.

### API changes

## Design


Unlike v1 volumes, upgrading the data engine for individual v2 volumes is not possible. This exising limitations are

- Since there is metadata cached in the SPDK target daemon, each node disk can only be managed by a single spdk_tgt.
- The engine and replicas of a volume cannot be moved to a newly created instance-manager pod using a new (default) instance-manager image, so the existing instance-manager pod must be removed before deploying a new one with the new image.
- One SPDK instance manager may use up all the hugepages memory on a node, necessitating the removal of the existing instance-manager pod before deploying a new one with the new image.
- Stopping the old spdk_tgt or adding the existing disk in the new spdk_tgt may be time-consuming.

To achieve a non-disruptive upgrade of the data engine for a v2 volume on an upgraded node, the following steps are performed for each volume on the upgrading node:

- **Control Plane**
  TBD

- **Data Plane**
  - Switch Over Target
      - Create a target replacement for the volume on another non-upgrading node.
        ```
        InstanceCreate()
        |-> EngineCreate(): create an engine instance only with a target because targetAddress is different than initiatorAddress
        ```
      - Suspend the linear device mapper device on top of the NVMe disk of the volume to pause IO processing.
        ```
        InstanceSuspend()
        |-> EngineSuspend()
        ```
      - Update the table of the linear device mapper device to connect to the target replacement.
        ```
        InstanceSwitchOverTarget()
        |-> EngineSwitchOverTarget()
        ```
      - Delete the old target for the volume on the upgrading node.
        ```
        InstanceDeleteTarget()
        |-> EngineDeleteTarget()
        ```
      - Resume the linear device mapper and continue IO processing.
        ```
        InstanceResume()
        |-> EngineResume()
        ```
  - Instance Manager Upgrade
      - If the existing instance-manager pod does not have any running engines with targets, the instance-manager and its pod will be deleted by the node controller.
      - Replicas managed by the deleted instance-manager are marked as ERROR, causing any volume with replicas on the upgrading node to become degraded.
      - A new instance-manager is then created and starts running.
  - Switch Over Target Back
      - Create a target replacement on the upgrading node.
      - Suspend the linear device mapper device on top of the NVMe disk of the volume to pause IO processing.
      - Delete the target for the volume on the non-upgrading node.
      - Update the table of the linear device mapper device to connect to the target replacement.
      - Resume the linear device mapper and continue IO processing.
  - Replica Rebuilding
      - Rebuilding failed replicas

  Then, the upgrade process is complete once all volumes on the upgrading node are healthy.


  Here is an example for upgrading instance-manager for v2 engine on the upgrading node `node1`:

  ![An example for upgrading instance-manager for v2 engine on the upgrading node `node1`](image/v2-volume-upgrade.png)

### Changes in gRPC

- spdk.proto
  - Methods
    - `rpc EngineSuspend(EngineSuspendRequest) returns (google.protobuf.Empty)`
      - Suspends the linear device mapper layered on top of an NVMe device provisioned by SPDK.
    - `rpc EngineResume(EngineResumeRequest) returns (google.protobuf.Empty)`
      - Resume the linear device mapper device.
    - `rpc EngineSwitchOverTarget(EngineSwitchOverTargetRequest) returns (google.protobuf.Empty)`
      - Replace the current target with a specified target.
    - `rpc EngineDeleteTarget(EngineDeleteTargetRequest) returns (google.protobuf.Empty)`
      - Deletes the specified target, including its associated SPDK RAID block device. If the initiator does not exist, the engine instance is also removed.
  - Messages
    - Engine
      `ip:port` indicates the address of a target, either local or remote, that is currently connected to the local initiator. `target_ip:target_port` is the address through which the target can be accessed, allowing both local and remote initiators to establish a connection.
      ```
      message Engine {
        ...
        string target_ip = 15;
        int32 target_port = 16;
      }
      ```
    - EngineCreateRequest
      During an upgrade, the initiator and target reside on different nodes. `initiator_address` and `target_address` specify the respective addresses of the initiator and target.
      ```
      message EngineCreateRequest {
        ...
        bool upgrade_required = 7;
        string initiator_address = 8;
        string target_address = 9;
      }
      ```
    - EngineSuspendRequest
      `name` is the name of an engine that is requested to be suspended.
      ```
      message EngineSuspendRequest {
        string name = 1;
      }
      ```
    - EngineResumeRequest
      `name` is the name of an engine that is requested to be resumed.
      ```
      message EngineResumeRequest {
        string name = 1;
      }
      ```
    - EngineSwitchOverTargetRequest
      `name` is the name of an engine that is requested to switch over its target to `target_address`.
      ```
      message EngineSwitchOverTargetRequest {
        string name = 1;
        string target_address = 2;
      }
      ```
    - EngineDeleteTargetRequest
      `name` is the name of an engine that is requested to delete its target.
      ```
      message EngineDeleteTargetRequest {
        string name = 1;
      }
      ```

- instance.proto
  - Methods
  	- `rpc InstanceSuspend(InstanceSuspendRequest) returns (google.protobuf.Empty) {}`
  	- `rpc InstanceResume(InstanceResumeRequest) returns (google.protobuf.Empty) {}`
  	- `rpc InstanceSwitchOverTarget(InstanceSwitchOverTargetRequest) returns (google.protobuf.Empty) {}`
  	- `rpc InstanceDeleteTarget(InstanceDeleteTargetRequest) returns (google.protobuf.Empty) {}`

  - Messages
    - SpdkInstanceSpec
      During an upgrade, the initiator and target reside on different nodes. `initiator_address` and `target_address` specify the respective addresses of the initiator and target.
      ```
      message SpdkInstanceSpec {
        ...
	      bool upgrade_required = 10;
	      string initiator_address = 11;
	      string target_address = 12;
      }
      ```
    - InstanceStatus
      `port_start:port_end` indicates the port range of a target, either local or remote, that is currently connected to the local initiator. `target_port_start:target_port_end` is the port range allocated by the local target.
      ```
      message InstanceStatus {
        ...
	      string target_port_start = 11;
	      string target_port_end = 12;
      }
      ```
    - InstanceSuspendRequest
      ```
      message InstanceSuspendRequest {
	      DataEngine data_engine = 1;
	      string name = 2;
	      string type = 3;
      }
      ```
    - InstanceResumeRequest
      ```
      message InstanceResumeRequest {
	      DataEngine data_engine = 1;
	      string name = 2;
	      string type = 3;
      }
      ```
    - InstanceSwitchOverTargetRequest
      ```
      message InstanceSwitchOverTargetRequest {
      	DataEngine data_engine = 1;
      	string name = 2;
      	string type = 3;
      	string target_address = 4;
      }
      ```
    - InstanceDeleteTargetRequest
      ```
      message InstanceDeleteTargetRequest {
      	DataEngine data_engine = 1;
      	string name = 2;
      	string type = 3;
      }
      ```
### Changes in CRDs

- node.longhorn.io
    - `spec.upgradeRequested`: Request to upgrade the instance manager for v2 volumes on the node.
- volume.longhorn.io
    - `spec.targetNodeID`: Node ID where the target is desired to run
    - `status.currentNodeID`: Node ID where the target is running
- engine.longhorn.io
    - `spec.instanceSpec.targetNodeID`: Node ID where the target is desired to run
    - `status.instanceStatus.currentTargetNodeID`: Node ID where the target is running
    - `status.instanceStatus.targetCreated`: target is already created on the `spec.instanceSpec.targetNodeID`
- upgrade.longhorn.io


## Controllers

- Volume controller

- Upgrade controller

### Test plan