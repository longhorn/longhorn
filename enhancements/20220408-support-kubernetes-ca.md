# Support Kubernetes Cluster Autoscaler

Longhorn should support Kubernetes Cluster Autoscaler.

## Summary

Currently, Longhorn pods are [blocking CA from removing a node](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#what-types-of-pods-can-prevent-ca-from-removing-a-node). This proposes to introduce a new global setting `kubernetes-cluster-autoscaler-enabled` that will annotate Longhorn components and also add logic for instance-manager PodDisruptionBudget management.

### Related Issues

https://github.com/longhorn/longhorn/issues/2203

## Motivation

### Goals

- Longhorn should block CA from scaling down if a node met ANY condition:
    - Any volume attached
    - Contains a backing image manager pod
    - Contains a share manager pod
- Longhorn should not block CA from scaling down if a node met ALL conditions:
    - All volume detached and there is another schedulable node with volume replica and replica IM PDB.
    - Not contain a backing image manager pod
    - Not contain a share manager pod

### Non-goals [optional]

- CA setup.
- CA blocked by kube-system components.
- CA blocked by backing image manager pod. (TODO)
- CA blocked by share manager pod. (TODO)

## Proposal
Set `kubernetes-cluster-autoscaler-enabled` adds `cluster-autoscaler.kubernetes.io/safe-to-evict` annotation to Longhorn pods that are not backed by a controller, or with local storage volume mounts. To avoid data loss, Longhorn does not annotate the backing image manager and share manager pods.

Currently, Longhorn creates instance-manager PDBs for replica/engine regardless of the volume state.
During scale down, CA tries to find a removable node but failed by those instance-manager PDBs.

We can add IM PDB handling to create and retained when the PDB is required:

- There are volumes/engines running on the node. We need to guarantee that the volumes won't crash.
- The only available/valid replica of a volume is on the node. Here we need to prevent the volume data from being lost.

### User Stories

#### CA scaling
Before the enhancement, CA will be blocked by
- Pods that are not backed by a controller (engine/replica instance manager).
- Pods with [local storage volume mounts](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/utils/drain/drain.go#L222) (longhorn-ui, longhorn-csi-plugin, csi-attacher, csi-provisioner, csi-resizer, csi-snapshotter).

After enhancement, instance manager PDB will be actively managed by Longhorn:
- Creates all engine/replica instance manager PDB when the volume is attached.
- Delete engine instance manager PDB when the volume is detached.
- Delete but keep 1 replica instance manager PDB when the volume is detached.

the user can set a new global setting `kubernetes-cluster-autoscaler-enabled` to unblock CA scaling. This allows Longhorn to annotate Longhorn-managed deployments and engine/replica instance manager pods with `cluster-autoscaler.kubernetes.io/safe-to-evict`.


### User Experience In Detail

- Configure the setting via Longhorn UI or kubectl.
- Ensure all volume replica count is set to more than 1.
- CA is not blocked by Longhorn components when the node doesn't contain volume replica, backing image manager pod, and share manager pod.
    - Engine/Replica instance-manager PDB will block the node if the volume is attached.
    - Replica instance-manager PDB will block the node when CA tries to delete the last node with the volume replica.

### API changes

`None`

## Design

### Implementation Overview

#### Global setting
- Add new global setting `Kubernetes Cluster Autoscaler Enabled (Experimental)`.
  - The setting is `boolean`.
  - The default value is `false`.

#### Annotations

When setting `kubernetes-cluster-autoscaler-enabled` is `true`, Longhorn will add annotation `cluster-autoscaler.kubernetes.io/safe-to-evict` for the following pods:
- The engine and replica instance-manager pods because those are not backed by a controller and use local storage mounts.
- The deployment workloads are managed by the longhorn manager and using any local storage mount. The managed components are labeled with `longhorn.io/managed-by: longhorn-manager`.

#### PodDisruptionBudget

- No change to the logic to cleanup PDB if instance-manager doesn't exist.

- Engine IM PDB:
    - Delete PDB if volumes are detached;
        - There is no instance process in IM (im.Status.Instance).
        - The same logic applies when a node is un-schedulable. Node is un-schedulable when marked in spec or with CA tainted `ToBeDeletedByClusterAutoscaler`;
    - Create PDB if volumes are attached; there are instance processes in IM (im.Status.Instance).

- Replica IM PDB:
    - Delete PDB if setting `allow-node-drain-with-last-healthy-replica` is enabled.
    - Delete PDB if volumes are detached;
        - There is no instance process in IM (im.Status.Instance)
        - There are other schedulable nodes with healthy volume replica and have replica IM PDB.
    - Delete PDB when a node is un-schedulable. Node is un-schedulable when marked in spec or with CA tainted `ToBeDeletedByClusterAutoscaler`;
        - Check if the condition is met to delete PDB (same check as to when volumes are detached).
        - Enqueue the replica instance-manager of another schedulable node with the volume replica.
        - Delete PDB.
    - Create PDB if volumes are attached:
        - There are instance processes in IM (im.Status.Instance).
    - Create PDB when volumes are detached;
        - There is no instance process in IM (im.Status.Instance)
        - The replica has been started. There are no other schedulable nodes with healthy volume replica and have replica IM PDB.

### Test plan

#### Scenario: test CA

    Given Cluster with Kubernetes cluster-autoscaler.
    And Longhorn installed.
    And Set `kubernetes-cluster-autoscaler-enabled` to `true`.
    And Create deployment with cpu request.
    ```
    resources:
      limits:
        cpu: 300m
        memory: 30Mi
      requests:
        cpu: 150m
        memory: 15Mi
    ```

    When Trigger CA to scale-up by increase deployment replicas.
         (double the node number, not including host node)
    ```
    10 * math.ceil(allocatable_millicpu/cpu_request*node_number/10)
    ```
    Then Cluster should have double the node number.

    When Trigger CA to scale-down by decrease deployment replicas.
         (original node number)
    Then Cluster should have original node number.

#### Scenario: test CA scale down all nodes containing volume replicas

    Given Cluster with Kubernetes cluster-autoscaler.
    And Longhorn installed.
    And Set `kubernetes-cluster-autoscaler-enabled` to `true`.
    And Create volume.
    And Attach the volume.
    And Write some data to volume.
    And Detach the volume.
    And Create deployment with cpu request.

    When Trigger CA to scale-up by increase deployment replicas.
         (double the node number, not including host node)
    Then Cluster should have double the node number.

    When Annotate new nodes with `cluster-autoscaler.kubernetes.io/scale-down-disabled`.
         (this ensures scale-down only the old nodes)
    And Trigger CA to scale-down by decrease deployment replicas.
        (original node number)
    Then Cluster should have original node number + 1 blocked node.

    When Attach the volume to a new node. This triggers replica rebuild.
    And Volume data should be the same.
    And Detach the volume.
    Then Cluster should have original node number.
    And Volume data should be the same.

#### Scenario: test CA should block scale down of node running backing image manager pod

Similar to `Scenario: test CA scale down all nodes containing volume replicas`.

### Upgrade strategy

`N/A`

## Note [optional]

`N/A`
