# Enhanced CPU Reservation

## Summary
To make sure Longhorn system stable enough, we can apply the node specific CPU resource reservation mechanism to avoid the engine/replica engine crash due to the CPU resource exhaustion. 

### Related Issues
https://github.com/longhorn/longhorn/issues/2207

## Motivation
### Goals
1. Reserve CPU resource separately for engine manager pods and replica manager pods.
2. The reserved CPU count is node specific: 
    1. The more allocable CPU resource a node has, the more CPUs be will reserved for the instance managers in general.
    2. Allow reserving CPU resource for a specific node. This setting will override the global setting.

### Non-goals
1. Guarantee that the CPU resource is always enough, or the CPU resource reservation is always reasonable based on the volume numbers of a node.
2. Notify/Warn users CPU resource exhaustion on a node: https://github.com/longhorn/longhorn/issues/1930

## Proposal
1. Add new fields `node.Spec.EngineManagerCPURequest` and `node.Spec.ReplicaManagerCPURequest`. This allows reserving a different amount of CPU resource for a specific node.
2. Add two settings `Guaranteed Engine Manager CPU` and `Guaranteed Replica Manager CPU`:
    1. It indicates how many percentages of CPU on a node will be reserved for one engine/replica manager pod.
    2. The old settings `Guaranteed Engine CPU` will be deprecated:
        - This setting will be unset and readonly in the new version.
        - For the old Longhorn system upgrade, Longhorn will automatically set the node fields based on the old setting then clean up the old setting, so that users don't need to do anything manually as well as not affect existing instance manager pods. 

### User Stories
Before the enhancement, users rely on the setting `Guaranteed Engine CPU` to reserve the same amount of CPU resource for all engine managers and all replica managers on all nodes. There is no way to reserve more CPUs for the instance managers on node having more allocable CPUs.

After the enhancement, users can:
    1. Modify the global settings `Guaranteed Engine Manager CPU` and `Guaranteed Replica Manager CPU` to reserve how many percentage of CPUs for engine manager pods and replica manager pods, respectively.
    2. Set a different CPU value for the engine/replica manager pods on some particular nodes by `Node Edit`.

### API Changes
Add a new field `EngineManagerCPURequest` and `ReplicaManagerCPURequest` for node objects.

## Design
### Implementation Overview
#### longhorn-manager:
1. Add 2 new settings `Guaranteed Engine Manager CPU` and `Guaranteed Replica Manager CPU`.
    - These 2 setting values are integers ranging from 0 to 40.
    - The sum of the 2 setting values should be smaller than 40 (%) as well.
2. In Node Controller, The requested CPU resource when creating an instance manager pod:
    1. Ignore the deprecated setting `Guaranteed Engine CPU`.
    2. If the newly introduced node field `node.Spec.EngineManagerCPURequest`/`node.Spec.ReplicaManagerCPURequest` is not empty, the engine/replica manager pod requested CPU is determined by the field value. Notice that the field value is a milli value.
    3. Else using the formula based on setting `Guaranteed Engine Manager CPU`/`Guaranteed Replica Manager CPU`: 
       `The Reserved CPUs = The value of field "kubenode.status.allocatable.cpu" * The setting values * 0.01`.
3. In Setting Controller
    - The current requested CPU of an instance manager pod should keep same as `node.Spec.EngineManagerCPURequest`/`node.Spec.ReplicaManagerCPURequest`, 
      or the value calculated by the above formula. Otherwise, the pod will be killed then Node Controller will recreate it later.
4. In upgrade
    - Longhorn should update `node.Spec.EngineManagerCPURequest` and `node.Spec.ReplicaManagerCPURequest` based on setting `Guaranteed Engine CPU` then clean up `Guaranteed Engine CPU`.
      
The fields 0 means Longhorn will use the setting values directly. The setting value 0 means removing the CPU requests for instance manager pods.

#### longhorn-ui:
- Add 2 new arguments `Guaranteed Engine Manager CPU(Milli)` and `Guaranteed Replica Manager CPU(Milli)` in the node update page.
- Hide the deprecated setting `Guaranteed Engine CPU` which is type `Deprecated`. Type `Deprecated` is a newly introduced setting type.

### Test Plan
#### Integration tests
- Update the existing test case `test_setting_guaranteed_engine_cpu`:
    - Validate the settings `Guaranteed Engine Manager CPU` controls the reserved CPUs of engine manager pods on each node.
    - Validate the settings `Guaranteed Replica Manager CPU` controls the reserved CPUs of replica manager pods on each node. 
    - Validate that fields `node.Spec.EngineManagerCPURequest`/`node.Spec.ReplicaManagerCPURequest` can override the settings `Guaranteed Engine Manager CPU`/`Guaranteed Replica Manager CPU`.

#### Manual tests
##### The system upgrade with the deprecated setting.
1. Deploy a cluster that each node has different CPUs.
2. Launch Longhorn v1.1.0.
3. Deploy some workloads using Longhorn volumes.
4. Upgrade to the latest Longhorn version. Validate:
    1. all workloads work fine and no instance manager pod crash during the upgrade.
    2. The fields `node.Spec.EngineManagerCPURequest` and `node.Spec.ReplicaManagerCPURequest` of each node are the same as the setting `Guaranteed Engine CPU` value in the old version * 1000.
    3. The old setting `Guaranteed Engine CPU` is deprecated with an empty value.
5. Modify new settings `Guaranteed Engine Manager CPU` and `Guaranteed Replica Manager CPU`. Validate all workloads work fine and no instance manager pod restart.
6. Scale down all workloads and wait for the volume detachment.
7. Set `node.Spec.EngineManagerCPURequest` and `node.Spec.ReplicaManagerCPURequest` to 0 for some node. Verify the new settings will be applied to those node and the related instance manager pods will be recreated with the CPU requests matching the new settings.
8. Scale up all workloads and verify the data as well as the volume r/w.
9. Do cleanup.

##### Test system upgrade with new instance manager
1. Prepare 3 sets of longhorn-manager and longhorn-instance-manager images.
2. Deploy Longhorn with the 1st set of images.
3. Set `Guaranteed Engine Manager CPU` and `Guaranteed Replica Manager CPU` to 15 and 24, respectively.
   Then wait for the instance manager recreation.
4. Create and attach a volume to a node (node1).
5. Upgrade the Longhorn system with the 2nd set of images.
   Verify the CPU requests in the pods of both instance managers match the settings.
6. Create and attach one more volume to node1.
7. Upgrade the Longhorn system with the 3rd set of images.
8. Verify the pods of the 3rd instance manager cannot be launched on node1 since there is no available CPU for the allocation.
9. Detach the volume in the 1st instance manager pod.
   Verify the related instance manager pods will be cleaned up and the new instance manager pod can be launched on node1.

### Upgrade strategy
N/A
