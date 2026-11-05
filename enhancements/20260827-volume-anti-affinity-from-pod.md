# Volume Anti-Affinity Inherited From Pods

## Summary

Many stateful applications spread their pods across nodes with pod anti-affinity or topology spread constraints. These rules do not apply to their volumes. When a replica is not placed on its pod's node, several volumes of the application can end up on the same node.

Applications that replicate their own data often use volumes with one replica. If several of these volumes share a node, one node failure makes them all unavailable at once, although their pods run on different nodes.

This enhancement adds volume anti-affinity. When a StorageClass sets `volumeAntiAffinity: enabled`, each volume inherits the node spreading rules of its pod. Longhorn then spreads the replicas of volumes that inherited the same rule across nodes. A required rule excludes the nodes that already hold one of these replicas. A preferred rule favors the nodes with the fewest of them and never blocks placement.

### Related Issues

- https://github.com/longhorn/longhorn/issues/6771

## Motivation

### Goals

- Place the volumes of one application on different nodes when its pods are required or preferred to run on different nodes.
- Reuse the rules that the pods already declare. The user sets one StorageClass parameter and writes no new rule.
- Keep the strength of pod anti-affinity rules. Required stays required, and preferred stays preferred.
- Never override data locality and never discard existing data.
- Change nothing for volumes that do not enable volume anti-affinity.

### Non-goals

- Volumes that keep data on more than one node: volumes with more than one replica, and EC volumes (`dataLayout.type: sharded`). They already stay available when one node fails. See [Future improvements](#future-improvements).
- Rules between different applications. Only volumes whose pods carry the same rule are related.
- Inheriting zone or region rules. With the existing `volumeTopology` StorageClass parameter, each volume stays in the zone or region of its pod, so the volumes already follow pods that spread across zones. See [Story 3](#story-3-spreading-across-zones-and-nodes).
- Moving replicas that already share a node.
- Serializing the placement of related volumes that are scheduled at the same moment.

## Proposal

### User Stories

#### Story 1: required spreading

A Kafka StatefulSet runs three brokers. Each broker has one volume with `numberOfReplicas: 1` and `dataLocality: disabled`, because Kafka replicates the data itself. The pods have a required pod anti-affinity rule on `kubernetes.io/hostname`.

Today the three volumes can land on one node. Losing that node takes down all three brokers, although their pods run on three different nodes.

With this enhancement, the StorageClass sets `volumeAntiAffinity: enabled`, and the three volumes are placed on three different nodes. If only two nodes can hold them, the third volume stays unscheduled until a third node can hold it. Its pod is scheduled but stays in `ContainerCreating` until then.

#### Story 2: preferred spreading

An OpenSearch StatefulSet uses a preferred pod anti-affinity rule, or a topology spread constraint, on `kubernetes.io/hostname`. Its volumes are placed on different nodes when possible. When every node that can hold the next volume already holds one of them, the volume goes to the node with the fewest. The rule never blocks placement.

#### Story 3: spreading across zones and nodes

A Kafka StatefulSet runs six brokers in a cluster with three zones. Its pods spread across zones with a topology spread constraint on `topology.kubernetes.io/zone`, and across nodes with a required pod anti-affinity rule on `kubernetes.io/hostname`.

The StorageClass sets `volumeTopology: zonal` together with `volumeAntiAffinity: enabled`. `volumeTopology: zonal` keeps each volume in the zone of its pod, so the volumes follow the pods across zones. Volume anti-affinity keeps the two volumes in each zone on different nodes. A zone failure takes down only the two brokers of that zone, and a node failure only one broker, as for the pods.

Longhorn does not inherit the zone rule or record an event for it.

### User Experience In Detail

1. Create a StorageClass that enables the feature.

    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: longhorn-spread
    provisioner: driver.longhorn.io
    volumeBindingMode: WaitForFirstConsumer
    parameters:
      numberOfReplicas: "1"
      dataLocality: "disabled"
      volumeAntiAffinity: "enabled"
    ```

    The Longhorn admission webhook validates the StorageClass when it is created. With `volumeAntiAffinity: enabled`, `volumeBindingMode` must be `WaitForFirstConsumer`, because Longhorn needs to know the pod before it places the first replica. `numberOfReplicas` must be `1`. `dataLayout.type` must not be `sharded`.

    In a cluster with zones, also set `volumeTopology: zonal`, as in [Story 3](#story-3-spreading-across-zones-and-nodes).

2. Create the workload as usual. The pod template does not change.

    ```yaml
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app: kafka
          topologyKey: kubernetes.io/hostname
    ```

3. Each volume records the rules it inherited from its pod. An inherited rule is called a term.

    ```yaml
    spec:
      volumeAntiAffinity: enabled
      volumeAntiAffinityFromPod:
        pod: prod/kafka-0
        requiredTerms:
        - namespaces: [prod]
          labelSelector:
            matchLabels:
              app: kafka
    ```

    The volumes of `kafka-1` and `kafka-2` carry the same term. The three volumes are therefore related, and Longhorn places them on different nodes.

4. When a related volume prevents placement, the volume's `Scheduled` condition is `False`, and its message names volume anti-affinity as a cause. For a detached volume whose eviction is blocked, Longhorn records an event instead. To place the volume anyway, set `spec.volumeAntiAffinity: disabled` on it. The volume then ignores its terms, and other volumes stop treating it as related.

5. When a pod rule is not inherited, Longhorn records an event on the volume that explains why. [Inheriting rules from the pod](#inheriting-rules-from-the-pod) lists the exceptions.

### API changes

- StorageClass parameter `volumeAntiAffinity`: `enabled` or `disabled`. The default is `disabled`.
- Volume `spec.volumeAntiAffinity`: `enabled` or `disabled`. The CSI driver copies it from the StorageClass. Users may change it on a volume.
- Volume `spec.volumeAntiAffinityFromPod`, maintained by Longhorn:
  - `pod`: the namespace and name of the pod that the terms come from.
  - `requiredTerms` and `preferredTerms`: lists of terms. A term has `namespaces` and `labelSelector`.
  - `pendingInheritance`: set while Longhorn waits for the pod. See [Holding the first placement](#holding-the-first-placement).

  The CSI driver sets only `pendingInheritance` when it creates a volume. Longhorn writes the rest and replaces anything a user writes there. The field is in `spec` because it is an input to replica scheduling, like `topologyRequirement`, which the CSI driver also derives from the workload.
- Validation:
  - StorageClass, on create: the rules in step 1 of [User Experience In Detail](#user-experience-in-detail).
  - Volume, on create and update: with `spec.volumeAntiAffinity: enabled`, `numberOfReplicas` must be `1`, and the volume must not be an EC volume.
- `Scheduled` condition: a new reason, `WaitingForVolumeAntiAffinityFromPod`. When volume anti-affinity causes a scheduling failure, the condition message says so.
- Volume events: `VolumeAntiAffinityNotInherited`, `VolumeAntiAffinityMultiplePods` and `ReplicaEvictionBlocked`.
- REST API: volume create and get include `volumeAntiAffinity` and `volumeAntiAffinityFromPod`. The UI does not change.

## Design

### Implementation Overview

Longhorn copies the node spreading rules of the pod to the volume, and spreads the replicas of volumes that carry the same rule across nodes. It holds the first placement of a volume until the rules are known.

#### Inheriting rules from the pod

Longhorn reads three kinds of pod rules.

| Pod rule | Inherited as |
|---|---|
| Required pod anti-affinity rule | required term |
| Preferred pod anti-affinity rule | preferred term |
| Topology spread constraint | preferred term |

A topology spread constraint is inherited as preferred, even with `whenUnsatisfiable: DoNotSchedule`. `DoNotSchedule` limits how uneven the spread may become, and it still lets two pods share a node when there are more pods than nodes. A required term would never let two related volumes share a node. A preferred term spreads the volumes evenly and never blocks placement.

A rule is inherited when all of the following hold:

- Its topology key is `kubernetes.io/hostname`.
- It has a `labelSelector` and no `namespaceSelector`.
- It selects the pod itself. Its namespaces include the pod's namespace, and its selector matches the pod's labels.

The last condition keeps the rules that spread the pods of one application. It drops the rules that keep a pod away from another application.

A rule without `namespaces` applies to the pod's namespace. `matchLabelKeys` and `mismatchLabelKeys` are merged into the selector before the conditions are checked, as kube-scheduler does. After the merge, a rule might no longer select the pod itself. Such a rule is not inherited. Weights, `maxSkew`, `minDomains`, `nodeAffinityPolicy` and `nodeTaintsPolicy` are not used.

A rule that is not inherited produces a `VolumeAntiAffinityNotInherited` event with the reason. Longhorn records it when the terms or the pods that use the PVC change, so a rule added to a recreated pod is reported, and a periodic resync does not repeat it.

Two kinds of rules produce no event. One is a rule without a `labelSelector`, which selects no pod. The other is a zone or region rule whose domain `volumeTopology` already handles: a zone rule with `volumeTopology: zonal`, and a region rule with `zonal` or `regional`. These settings keep the volume in its pod's zone or region, so the volumes follow the pods.

The `KubernetesPVController` writes the terms. It finds the pod through the PVC, as it already does for the volume's Kubernetes status, and it ignores pods that are being deleted or have finished.

When the pod or the PV changes, the controller recomputes the terms and replaces them if they differ. When no pod uses the volume anymore, it keeps the terms, because the data still exists. When several pods use the PVC, it keeps the terms unchanged and records a `VolumeAntiAffinityMultiplePods` event. A volume without a PVC has no pod, so the feature has no effect on it.

#### Related volumes

Two volumes are related when:

- both have `spec.volumeAntiAffinity: enabled`,
- they belong to different pods, and
- they carry the same term, which means the same namespaces and the same label selector.

Pods of one StatefulSet share the pod template, so their volumes carry the same terms. Volumes of one pod are not related to each other. The pod fails when any of its volumes fails, so placing them on different nodes does not help.

A related volume excludes nodes when the shared term is required for either volume, so the placement order does not matter. kube-scheduler treats pods the same way: a new pod avoids the nodes of existing pods whose required anti-affinity selects it. When the term is preferred for both volumes, the related volume only ranks nodes.

A node is occupied by a related volume when it holds a replica of that volume. Failed replicas and replicas being deleted do not count. For each placement, Longhorn finds the related volumes by scanning the volume and replica caches in memory.

#### Placing a replica

The rules apply when Longhorn chooses the node of a new replica. For a single-replica volume, this happens in two cases: the first placement, and the new replica created during eviction.

Data locality and existing data come first. The rules do not apply in these cases:

- `strict-local`: the replica always goes to the attached node.
- `best-effort`: when the attached node can hold the replica, the replica goes there, as today. The attached node can also be the node where Longhorn attaches a detached volume to move its replica. The rules apply only when the replica has to go to another node.
- A move within one node, such as replica auto-balance moving a replica to another disk of the same node.
- Reuse of a failed replica, which keeps the replica where its data is.

Today the scheduler collects candidate nodes, which are the nodes that could hold the replica, and tries them in groups, in a fixed order. The first group is the nodes in zones without a replica of this volume. Depending on the replica anti-affinity settings, later groups are the other nodes without a replica of this volume, and other disks of a node whose replica is being evicted. Longhorn uses the first group that has a candidate. The rules work inside this order.

1. From each group, Longhorn removes the nodes occupied by related volumes whose shared term is required for either volume. If a group becomes empty, the next group is tried, as it is today. If no group has a candidate left, the replica is not scheduled, and Longhorn retries later.
2. Within the chosen group, Longhorn keeps the nodes with the fewest replicas of volumes related only through preferred terms. A preferred term never moves the replica to a later group.
3. Longhorn picks the disk as it does today.

For example, when a disk is evicted and related volumes occupy every other node, the replica moves to another disk of the same node.

When step 1 leaves no candidate, the scheduling failure names volume anti-affinity as a cause. The `Scheduled` condition shows it, except for the eviction of a detached volume. In that case, the eviction controller does not attach the volume. It records a `ReplicaEvictionBlocked` event instead, and checks again later.

`volumeTopology` narrows the candidates before these steps, so related volumes spread across nodes within their zone.

#### Holding the first placement

The first replica of a volume with `dataLocality: disabled` is placed as soon as its Volume CR exists. At that point the PVC is not bound, and Longhorn does not know the pod.

When the StorageClass enables the feature, the CSI driver creates the volume with `pendingInheritance: true`. The volume controller does not place replicas while this flag is set, and the `Scheduled` condition shows `WaitingForVolumeAntiAffinityFromPod`. Setting `spec.volumeAntiAffinity: disabled` ends the hold.

When the PV is bound, the `KubernetesPVController` looks for the pod. With `WaitForFirstConsumer`, the pod exists before the volume is provisioned. If the controller finds one pod, it writes the terms and clears the flag in one update. If the pod is not visible yet, it retries until the pod appears. If several pods use the PVC, it clears the flag without terms and records an event. The `KubernetesPVController` runs in `longhorn-global-manager`, so the hold does not end while the global manager is down.

The hold does not block volume creation, because the CSI driver waits only for the volume state, and the state does not depend on replica placement. Attaching waits until the hold ends. The hold normally ends first, because the PVC is bound before the volume is attached.

#### Limits of `required`

A required term rejects any node that holds a replica of a related volume, as observed by the scheduler at that moment. Longhorn schedules the replicas of different volumes independently, so related volumes placed at the same moment can land on the same node. This can happen with `podManagementPolicy: Parallel`, or when a node drain evicts several related volumes at once. It can also happen when another Longhorn manager has just placed a related replica, and this manager has not seen it yet. With `podManagementPolicy: OrderedReady`, this is rare among the volumes of one StatefulSet.

A required term also needs enough nodes. With one volume per pod, the related volumes need one node per pod. The volumes of one pod are not related, so nothing keeps them on one node. A pod with several volumes can therefore occupy several nodes, and the application can need more nodes than it has pods. When no node is left, the volume waits, and so does a node drain that has to move its replica. Setting `spec.volumeAntiAffinity: disabled` on the volume lets it be placed.

### Test plan

Unit tests:

- Inheritance: each rule kind and its strength, each inheritance condition, `matchLabelKeys` and `mismatchLabelKeys`, namespaces, duplicate terms, and the not-inherited event with and without `volumeTopology` and after the pod changes.
- Relation: the same term, different terms, a term that only one of the two volumes requires, volumes of the same pod, and volumes with the feature disabled.
- Placement: required exclusion with fallback to the next group, preferred ordering, each data locality and existing data exception, `volumeTopology`, and the failure reason.
- First placement: one pod, no pod yet, several pods, the terms and the flag written in one update, and disabling the feature during the hold.
- Validation: StorageClass binding mode, replica count and data layout, and volume replica count and data layout on create and update.

End-to-end tests:

- A StatefulSet with a required rule places its volumes on different nodes.
- With more pods than nodes, the extra volume stays unscheduled with an anti-affinity message, and disabling the feature on it lets it be placed.
- A `DoNotSchedule` topology spread constraint, inherited as a preferred term, never blocks placement.
- A zone rule without `volumeTopology` produces a `VolumeAntiAffinityNotInherited` event.
- Eviction of an attached volume and of a detached volume, with and without a free node. Disabling the feature on a blocked volume lets its eviction finish.
- An existing volume opts in and gets its terms.
- A StorageClass with `Immediate` binding, without `numberOfReplicas: "1"`, or with the EC data layout is rejected, and so is a replica count change on an enabled volume.

### Upgrade strategy

No migration is needed. Existing StorageClasses and volumes do not have the parameter and keep their current behavior.

StorageClass parameters cannot be changed, so a workload opts in through a new StorageClass. An existing volume can opt in by setting `spec.volumeAntiAffinity: enabled`. Longhorn writes its terms on the next sync of its PV, which runs when the pod or the PV changes. The terms apply from the volume's next replica placement.

Create StorageClasses with the parameter after every Longhorn component is upgraded. A volume created through an older CSI plugin has no hold, so its first placement does not use the rules.

## Future improvements

The design has three parts: the terms that a volume inherits from its pod, the relation between volumes that carry the same term, and the node filter that replica placement applies. Each improvement below widens one part and keeps the others.

- **Volumes with data on several nodes.** Volumes with more than one replica and EC volumes are rejected today. Supporting them first needs a new definition of `required`, because the current one would need one node per replica or shard. One option is a limit on how many related volumes may share a node. The terms and the relation stay the same, and EC placement applies the same filter to its shards.
- **More rule shapes.** A custom topology key such as a rack label can be supported by filtering per label value instead of per node. A rule with `namespaceSelector` needs Longhorn to watch namespace labels.
- **A cap on strength.** A new StorageClass value can inherit required rules as preferred, for clusters with fewer nodes than related volumes.
- **Placement at the same moment.** Serializing the placement of related volumes, or checking the result after placement, would make `required` hold for volumes placed at once.
