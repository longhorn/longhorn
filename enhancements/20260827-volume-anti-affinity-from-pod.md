# Volume Anti-Affinity Derived From Pod Spread Declarations

## Summary

Longhorn schedules the replicas of each volume independently. The volumes of one application can therefore land on the same node even when the application spreads its pods across nodes with `podAntiAffinity` or `topologySpreadConstraints`. As a result, the spread stops at the pod level: a single node failure can still take down the data of every pod, defeating the application's spread policy.

This enhancement adds a soft cross-volume anti-affinity to the replica scheduler and derives it from the pod that uses the volume. Volumes of pods that declare node-level spread prefer storage nodes that hold no replica of a sibling volume. The preference never blocks scheduling and never overrides data locality. A global setting controls the feature, with a per-StorageClass override. The derived rule is stored on the Volume CR.

### Related Issues

- https://github.com/longhorn/longhorn/issues/6771

## Motivation

### Goals

- Spread the replicas of related volumes across storage nodes so that one node failure does not take down every volume of one workload.
- Derive the relationship between volumes from the pod declarations already made by the workload. No per-application configuration is added.
- Keep the rule a soft preference. It must not make a volume unschedulable and must not change where data locality places a replica.
- Apply the rule to every placement in the existing scheduler: initial placement, rebuild, auto-balance, and eviction.

### Non-goals

- Hard cross-volume anti-affinity. The Volume field is shaped so that an enforcement mode can be added later.
- Zone or region spread. Failure-domain placement across zones is the role of the `volumeTopology` StorageClass parameter.
- Inter-volume affinity, asymmetric anti-affinity, and rules derived from `namespaceSelector`.
- Rebalancing existing volumes that already violate the preference. The rule is evaluated only when a replica is placed.
- Serializing concurrent placements. Sibling volumes scheduled at the same time may still land on the same node. This is an existing limitation of the replica scheduler and is left to a separate proposal.

## Proposal

### User Stories

#### Story 1 — StatefulSet with one replica per volume

A Kafka StatefulSet with three brokers uses a StorageClass with `numberOfReplicas: 1` and `dataLocality: disabled`, because the application replicates its own data. The pods carry a required `podAntiAffinity` on `kubernetes.io/hostname` and run on three nodes. Today, the three volumes may still share one storage node, so losing that node can make all three brokers' data unavailable. With this enhancement, the three volumes prefer three different storage nodes without any change to the StatefulSet.

#### Story 2 — Enabling the behavior per StorageClass

An operator wants the behavior for stateful applications but not for a general-purpose class. They can enable `volumeAntiAffinityFromPod` on selected StorageClasses while leaving the global setting off, or enable the global setting and disable it on StorageClasses that should not follow pod declarations.

### User Experience In Detail

1. The operator enables the `volume-anti-affinity-from-pod` setting or sets the StorageClass parameter `volumeAntiAffinityFromPod: "enabled"`.
2. A StatefulSet is created with a pod template that spreads its pods across nodes:

   ```yaml
   affinity:
     podAntiAffinity:
       requiredDuringSchedulingIgnoredDuringExecution:
       - labelSelector: {matchLabels: {app: kafka}}
         topologyKey: kubernetes.io/hostname
   ```

   or equivalently:

   ```yaml
   topologySpreadConstraints:
   - maxSkew: 1
     topologyKey: kubernetes.io/hostname
     whenUnsatisfiable: DoNotSchedule
     labelSelector: {matchLabels: {app: kafka}}
   ```

3. When each volume's PV is bound, Longhorn derives the rule from the pod and stores it on the Volume CR:

   ```yaml
   spec:
     volumeAntiAffinityFromPod: ignored        # ignored | enabled | disabled; ignored follows the setting
     volumeAntiAffinity:
       labels:                                 # identity of this volume
         pod.longhorn.io/namespace: prod
         pod.longhorn.io/instance: kafka-0
         app: kafka
       selectors:                              # volumes this volume avoids
       - matchLabels:
           pod.longhorn.io/namespace: prod
           app: kafka
         matchExpressions:
         - key: pod.longhorn.io/instance
           operator: NotIn
           values: [kafka-0]
   ```

   `labels` contain the pod labels referenced by its own selectors, plus the pod's namespace and name. `selectors` contain the pod's selectors copied verbatim, scoped to the namespace and excluding the pod itself. This allows multiple volumes used by the same pod to share a node.

4. When a replica is placed, the scheduler first prefers nodes with no replica of a matched volume. If no such node can take the replica, it prefers nodes with the fewest matching replicas. The existing balancing logic then selects a node within that group. The first placement waits until the PV is bound and the rule has been derived. Until then, the volume reports `Scheduled=False` with reason `WaitingForVolumeAntiAffinityFromPod`.
5. The preference never blocks placement. When every node already holds a sibling replica, the manager logs the fallback.

The following behavior is unchanged:

- Data locality wins. A replica pinned to a node by `strict-local`, or the local replica of a `best-effort` volume, is placed there regardless of sibling replicas.
- Existing data wins. A reusable failed replica stays on its existing node.
- Placement is unchanged when the pod declares no node-level spread, declares spread only on other topology keys, or uses `namespaceSelector`. The same applies when the volume is created with `volumeBindingMode: Immediate` before a pod exists. In that case, the rule is derived once a pod appears and applies from the next placement.
- The rule follows the pod. When the pod's declarations change, the rule is updated on the next sync. When the pod stops declaring spread, the rule is removed.

### API changes

- New setting `volume-anti-affinity-from-pod` (bool, default `false`, category Scheduling).
- New StorageClass parameter `volumeAntiAffinityFromPod` with values `enabled` and `disabled`. When absent, the value is `ignored`, following the `replicaSoftAntiAffinity` pattern.
- Volume CRD `spec`:
  - `volumeAntiAffinityFromPod` (enum `ignored|enabled|disabled`, default `ignored`).
  - `volumeAntiAffinity` (optional): `labels` (map), `selectors` (list of `metav1.LabelSelector`, OR-ed), and `pendingInheritance` (bool).
- Volume REST resource exposes both fields.
- New `Scheduled` condition reason `WaitingForVolumeAntiAffinityFromPod`.

## Design

### Implementation Overview

The change touches four places in longhorn-manager.

**CSI driver.** `CreateVolume` resolves the effective value from the StorageClass parameter, falling back to the setting. When the feature is enabled, it creates the volume with `pendingInheritance: true`. The driver reads neither the pod nor any extra CSI metadata.

**Volume controller.** While `pendingInheritance` is set, replica scheduling is held with the reason above, at the same point where `best-effort` volumes wait for `spec.nodeID`. Volume state still progresses `creating → detached`, so `CreateVolume` and PV binding are not delayed. There is no timeout. The PV controller releases the hold when the PV is bound. A volume whose PV never appears is unusable anyway.

**PV controller.** `syncKubernetesStatus` already resolves the pods that use the PVC when the PV is bound. When the feature is enabled and exactly one non-terminating pod uses the PVC, the rule is derived from that pod and written to `spec.volumeAntiAffinity`. If the pod declares no eligible spread, the field is cleared.

When several live pods use the PVC, as during a rolling update of a Deployment with an RWO PVC, the existing value is kept and an event is recorded. `pendingInheritance` is cleared whenever the PV is bound, including when no pod is present or the feature is disabled, so the volume never remains unschedulable because of it. The same logic runs on later pod changes.

Derivation is a pure function of the pod:

- Sources: every required or preferred `podAntiAffinity` term, and every `topologySpreadConstraints` entry with `topologyKey: kubernetes.io/hostname`. A source is eligible only if its `labelSelector` matches the pod's own labels and its namespace scope includes the pod's namespace. Sources using `namespaceSelector` are excluded. `matchLabelKeys` and `mismatchLabelKeys` are folded into the selector as kube-scheduler does. Duplicate selectors are kept only once.
- Strength fields (`required`/`preferred`, `weight`, `maxSkew`, `whenUnsatisfiable`, `minDomains`) are not read. The presence of the declaration is what is inherited.
- Labels: the pod labels referenced by eligible selectors, plus `pod.longhorn.io/namespace` and `pod.longhorn.io/instance`. The instance value is the pod name, shortened deterministically if it exceeds the label value limit.
- Selectors: each eligible selector is copied verbatim and scoped with `pod.longhorn.io/namespace` and `pod.longhorn.io/instance`. The namespace matches the pod's namespace, or the term's `namespaces` list when specified. The instance selector excludes the pod itself with `NotIn [pod name]`.

**Replica scheduler.** Within each existing anti-affinity tier of `getDiskCandidates` (unused zone → unused node → used node), candidate nodes are grouped by the number of matching sibling replicas. A sibling replica is counted if it is placed, non-failed, and belongs to a volume whose `labels` match this volume's `selectors`. The scheduler takes the group with the fewest matching replicas that still yields a schedulable disk, then applies the existing balancing within it. For a `best-effort` volume, the attached node is excluded from the count so that the local replica keeps its priority. Replicas with a hard node affinity have one candidate, so the grouping is a no-op. The failed-replica reuse path skips the grouping.

**Why one soft rule covers both pod declarations.** `podAntiAffinity` and `topologySpreadConstraints` on `kubernetes.io/hostname` carry the same information this feature needs: who the siblings are and that they should not share a node. In their soft forms, kube-scheduler scores both by the number of matching pods on each node. Both therefore mean "prefer the node with the fewest siblings," which is also the volume rule. Their hard forms differ, and this proposal defines no hard form. A required pod term is intentionally inherited as a soft volume rule. The storage pool is often smaller than the compute pool, and a hard rule that the user never declared for volumes could leave volumes pending.

### Test plan

Unit tests in longhorn-manager cover derivation (sources, gates, `namespaces`, `matchLabelKeys`, duplicate selectors, long pod names), the PV controller (derive on bind, release without a pod or with the feature off, several live pods, terminating pods, rule removal, per-volume override), the scheduler (prefer empty nodes, fewest when all are taken, never block, same-pod volumes, `best-effort` local node, failed and reused replicas), and the CSI parameter and REST fields.

End-to-end tests in longhorn-tests, on a StatefulSet with one replica per volume and `dataLocality: disabled`:

- With the setting on, `podAntiAffinity` on `kubernetes.io/hostname` places sibling volumes on distinct nodes. The same with `topologySpreadConstraints` as the only declaration.
- With the setting off, without node-level spread, or with a zone-keyed declaration only, no rule is derived and placement is unchanged.
- The StorageClass parameter overrides the setting in both directions.
- With more sibling volumes than storage nodes, all volumes are scheduled.

### Upgrade strategy

No action is required. The setting defaults to `false`, the new fields default to empty or `ignored`, and the scheduler is a no-op for volumes without a rule. Turning the setting on affects placements made afterwards; existing volumes receive a rule on their next sync with the pod. Turning it off stops deriving rules; rules already on volumes stay until the volume is updated or deleted. The CRD change is additive.

## Note

- **Soft only:** a hard rule requires decisions on concurrent placements, discarding reusable data on a sibling node, and its StorageClass expression. The field is an object so that an enforcement mode can be added later without migration.
- **Asymmetric anti-affinity:** only self-matching declarations are derived, so a volume's labels are stamped only when its own pod declares spread.
- **Same-pod volumes:** volumes used by the same pod are neither repelled from nor attracted to each other.
