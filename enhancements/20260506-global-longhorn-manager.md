# Global Longhorn Manager

## Summary

`longhorn-manager` runs as a DaemonSet — one pod per node, each hosting
every Longhorn control-plane reconciler alongside the node-local work
(replica/engine/instance-manager lifecycle, disk monitoring, environment
checks). As clusters have grown, two scaling issues stand out:

1. **`kube-apiserver` watch fan-out from the cluster-wide Pod informer.**
   Every Pod change in the cluster is re-delivered by `kube-apiserver` to
   every manager pod. The watch traffic — and the work `kube-apiserver`
   does to serve it — scales with both cluster Pod count and node count.

2. **Per-pod memory from informer caches.** Each manager pod caches every
   object its informers watch. The Pod cache size is determined by the
   cluster's Pod count, not the node's, so adding nodes multiplies the
   same large Pod cache N times across DaemonSet pods.

Both costs grow with the cluster even though the controllers driving them
are owner-elected — only one daemon pod does useful work at a time; the
other N − 1 carry the watch and cache cost just to be ready for failover.

This proposal introduces **`longhorn-global-manager`**, a leader-elected
`Deployment` that hosts the controllers requiring cluster-wide Pod
visibility. Its replicas keep their informer caches warm; the Lease gates
which replica runs the controllers. The DaemonSet's Pod informer is scoped
to the `longhorn-system` namespace. The cluster-wide Pod watch and cache
therefore collapse from one per node (O(node count)) to one per
global-manager replica (a small constant, e.g. 2).

This release covers the cluster-wide Pod informer consumers —
`KubernetesPVController` and `KubernetesPodController`. The framework can
host additional controllers later if a specific case justifies it, but no
further migration is committed by this enhancement.

### Related Issues

- https://github.com/longhorn/longhorn/issues/13059

## Motivation

### Goals

- Introduce `longhorn-global-manager` as a leader-elected Deployment that
  hosts Longhorn controllers requiring cluster-wide Pod visibility.
- In this release, host the cluster-wide Pod informer consumers —
  `KubernetesPVController` and `KubernetesPodController` — there, so the
  cluster-wide Pod watch and cache are held by a small constant number of
  replicas instead of one per node.
- Keep volume I/O uninterrupted across the upgrade: no volume detach and no
  downtime are required.

### Non-goals

- Migrating other controllers in this release. The framework can host
  additional controllers later, but any further migration is decided
  case-by-case (e.g. when a specific scaling need surfaces) and is not
  committed by this enhancement.
- Changing the CSI plugin DaemonSet (`longhorn-csi-plugin`). Mount/unmount
  must remain node-local and is unaffected.
- Eliminating the DaemonSet. Many Longhorn controllers (replica, engine,
  instance manager, backing-image manager, orphan, node-disk monitor)
  depend on host paths or unix-domain sockets that cannot be reached from a
  network-only Deployment. The DaemonSet remains the hosting model for
  those.
- Rewriting reconciliation algorithms. Each hosted controller's reconcile
  logic is unchanged; only its hosting process changes (see
  [Which controllers the global manager hosts](#which-controllers-the-global-manager-hosts)).
- Replacing the existing webhook/recovery-backend leader election. Those
  keep their current single-leader-among-DaemonSet scheme.

## Proposal

### User Story

A cluster admin running a 100+ node Longhorn cluster observes that:

- Restarting all `longhorn-manager` pods at once briefly spikes
  `kube-apiserver` to several hundred concurrent list-pods requests.
- Each manager pod's RSS climbs in step with the cluster's total Pod count,
  not the node's.
- Adding nodes inflates the `kube-apiserver` bill linearly even when the
  number of Longhorn volumes is unchanged.

With `longhorn-global-manager`, the cluster-wide Pod watch originates from a
small constant number of replicas instead of one per node. DaemonSet pod
RSS no longer scales with cluster Pod count.

### User Experience In Detail

#### Helm chart

The chart renders the `longhorn-global-manager` Deployment alongside the
existing components, with standard knobs in `chart/values.yaml`:

- `globalManager.replicas` (default 2) — one active leader plus warm
  standbys via leader election.
- `priorityClass`, `resources`, `tolerations`, `nodeSelector`, and pod
  annotations for the Deployment.

#### Topology

```
NAME                                       NODE
longhorn-global-manager-...-aaa            ip-10-0-1-105   # leader
longhorn-global-manager-...-bbb            ip-10-0-1-113   # warm standby
longhorn-manager-aaaaa                     ip-10-0-1-102
longhorn-manager-bbbbb                     ip-10-0-1-105
longhorn-manager-ccccc                     ip-10-0-1-113
```

Leader election uses a `coordination.k8s.io/v1` `Lease` named
`longhorn-global-manager` in the `longhorn-system` namespace (see Global
manager process model). The `longhorn-backend`, `longhorn-frontend`,
validating webhook, and metrics endpoints continue to point at the
DaemonSet — unchanged.

### API changes

None at the Longhorn CR or REST API level. Internally:

- A new `Lease` object (`longhorn-global-manager`) for leader election.
  Existing RBAC for the `Lease` resource already covers it.
- A new `Deployment` (`longhorn-global-manager`) in the chart.
- The Deployment runs with the existing `longhorn-service-account`. It does
  not need `privileged: true` and does not mount host paths.

## Design

### Which controllers the global manager hosts

For framing, Longhorn controllers fall into three categories with respect
to where they can be hosted:

| Category | Examples | Eligible for the global manager? |
| --- | --- | --- |
| **Node-local** — touch host paths, call IM gRPC over localhost, or have CR ownership keyed off `Spec.NodeID` | `Replica`, `Engine`, `InstanceManager`, `BackingImageManager`, `BackingImageDataSource`, `Orphan`, `Node` (disk monitor), `MetricsCollector`s | No — must stay in the DaemonSet |
| **Global-scope** — owner-elected across the cluster, no node-local dependency | `Volume` and Volume workflow controllers, `Snapshot`, Backup family, `BackingImage`, `EngineImage`, `RecurringJob`, `ShareManager`, `SystemBackup`, `SystemRestore`, `SupportBundle`, `Setting`, `KubernetesPV`, `KubernetesPod`, `KubernetesConfigMap`, `KubernetesSecret`, `KubernetesPDB`, `KubernetesEndpoint` | Yes — eligible to host when justified |
| **Coupled to the in-process REST API server** | `WebsocketController` | No — stays in the DaemonSet for routing reasons |

The middle category lists what *could* be hosted by the global manager.
Whether a particular controller actually moves is a separate decision per
controller. **This enhancement covers only the two below.**

#### This release: the cluster-wide Pod informer consumers

`KubernetesPVController` and `KubernetesPodController` are the only
controllers that need cluster-wide Pod visibility — they track workload Pods
across all namespaces to manage PV ↔ workload binding, node-down handling,
RWX remount, and CSI plugin Pod failure recovery.

Every other Pod consumer in the DaemonSet already restricts itself to the
`longhorn-system` namespace via its event-handler predicate, so a
namespace-scoped Pod informer is sufficient for them with no behavior
change:

| Controller | What it filters Pods by |
| --- | --- |
| `KubernetesEndpointController` | owner-ref `ShareManager` (share-manager pods) |
| `InstanceManagerController` | instance-manager pod label/owner |
| `BackingImageManagerController` | backing-image-manager pod label/owner |
| `BackingImageDataSourceController` | backing-image-data-source pod label/owner |
| `ShareManagerController` | share-manager pod label/owner |
| `NodeController` | manager-pod filter |

The two hosted controllers do not own a Longhorn CR — they read PV/Pod
(kube-native) objects and update `Volume.Status.KubernetesStatus`, while the
`Volume` CR stays owned by `VolumeController` in the DaemonSet. Their only
change when hosted in the global manager is the **removal of the per-node
sharding guards** that previously kept one DaemonSet pod (selected by node
identity) from racing the others on the same write; with a single active
leader those guards are unnecessary. The reconcile logic is otherwise
unchanged, and no `Status.OwnerID` semantics change.

### Alternatives considered

**Run the cluster-wide Pod informer only on the elected leader, inside the
DaemonSet.** Each DaemonSet pod runs node-local controllers unconditionally
(they depend on host paths and run on every node regardless of leadership).
Gating only the cluster-wide informer and the two controllers on leadership
would require starting and stopping that informer on every leader change
*within* a long-lived, privileged, host-mounting process — coupling informer
lifecycle to leader election in a mixed-purpose process. A dedicated
leader-gated Deployment instead isolates the informer-and-controller
lifecycle cleanly (the whole process is gated by the Lease) and runs without
`privileged` or host mounts. This is why a separate Deployment is preferred
over reusing the DaemonSet's process.

### Global manager process model

The global manager runs as a `Deployment` with leader election via a
`coordination.k8s.io/v1` `Lease`. Every replica starts the informers and
keeps its cache synced; the Lease gates which replica runs the controller
reconcile loops. The leader is the only writer. Because standbys keep warm
caches, on a leader change the new leader's controllers start against an
already-synced cache, so failover is near-instant and does not require a
fresh cluster-wide LIST.

The number of concurrent cluster-wide Pod watches is therefore the replica
count (a small constant, e.g. 2), independent of cluster node count.

### Upgrade and rollback

On upgrade, the cluster-wide Pod controllers come up in the
`longhorn-global-manager` Deployment, and the DaemonSet rolls to a build
that no longer starts them and whose Pod informer is namespace-scoped.

During the DaemonSet rollout there is a bounded window in which the rolling
DaemonSet pods and the global manager may both act on the same
`Volume.Status.KubernetesStatus`. This is safe because the value is a
**deterministic function of the PV/PVC/Pod state**, and the computation is
identical in both processes — so both writers compute the *same* target
state and converge rather than oscillate. Concurrent writes to the shared
`Volume.Status` are resolved by the existing optimistic-concurrency retry.
No CR `Status.OwnerID` flip is involved — the hosted controllers do not own
a Longhorn CR.

Because convergence (not rollout speed) is what makes this safe, even a
prolonged overlap (for example a slow or partially failed rollout) does not
corrupt state. As optional hardening, the global manager can defer starting
the hosted controllers until the prior-version managers that also ran them
have drained, removing the overlap entirely at the cost of a longer
controller-reconcile pause during the rollout.

Rollback is symmetric: a chart/image rollback removes the Deployment and the
DaemonSet resumes hosting the two controllers, with the same convergence
guarantee during the transition. There is no CRD, on-disk format, or REST
API change — the only new objects are the `Lease` and the `Deployment` — so
the CRs are compatible in both directions and no data migration is involved.

### Failure modes

During a leader transition there is a bounded gap (lease acquisition time;
short, since the new leader's cache is already warm) in which the hosted
controllers' actions — node-down force-delete, RWX remount, force-delete
cleanup, and `Volume.Status.KubernetesStatus` tracking — are deferred. These
are control-plane functions; the data plane (engine, replica,
instance-manager) keeps running in the DaemonSet, so in-flight volume I/O is
unaffected. The controllers are level-triggered, so no work is lost: on
resume the new leader reconciles current state.

The relevant network partitions are between processes and `kube-apiserver`,
since these controllers observe the cluster through informers:

- **Leader ↔ `kube-apiserver`.** The leader can no longer renew the Lease
  and steps down; a standby that can reach `kube-apiserver` acquires the
  Lease and takes over (near-instant, warm cache).
- **Node ↔ `kube-apiserver`.** The node's Pod/Node status goes stale from
  `kube-apiserver`'s view; the global manager observes it as down and the
  existing `IsNodeDownOrDeletedOrMissingManager` handling triggers.

This does change the failure domain: cluster-wide Pod observation for the
two hosted controllers now depends on the active leader's connectivity to
`kube-apiserver`, rather than being distributed across DaemonSet pods. Warm
standbys and fast lease failover bound the exposure.

Mitigations: run ≥ 2 replicas with hostname anti-affinity, and set a
`priorityClassName` equal to `longhorn-critical` so the Deployment is not
evicted before lower-priority workloads.

### Scheduling and operations

- **Small and single-node clusters.** Hostname anti-affinity is
  `preferred`, not `required`, so a single-node cluster still runs one
  replica (with reduced redundancy) rather than leaving a replica `Pending`.
- **Placement.** `tolerations`, `nodeSelector`, and `priorityClass` are
  exposed so the Deployment can be placed on the same nodes Longhorn already
  runs on, including tainted control-plane or storage-only layouts. A
  `PodDisruptionBudget` can be added to keep at least one replica during
  voluntary disruptions.
- **Observability.** The global manager exposes whether it currently holds
  the Lease, reconcile rate/errors for the hosted controllers, and informer
  cache-sync status, so operators can see leader identity and detect a
  prolonged leaderless or unschedulable state. The liveness probe reflects
  process liveness (not leader status) so standby replicas stay Ready.

### Test plan

Functional scenarios:

1. Volume create / attach to a workload Pod / write data / detach / delete
   (RWO and RWX).
2. Force-delete a workload Pod with a Longhorn volume on a downed node:
   verify VolumeAttachment cleanup.
3. Trigger a Volume remount by setting `Volume.Status.RemountRequestedAt`
   directly: verify the controller-owned workload Pod is force-deleted and
   recreated.
4. Trigger a remount through a real volume event — replica auto-salvage, or a
   share-manager entering an error state — which makes `VolumeController` set
   `Volume.Status.RemountRequestedAt`: verify the controller-owned workload Pod,
   in any namespace and on any node, is force-deleted by the global manager
   (exercises the cluster-wide Pod informer and the removed per-node guard).
5. Existing scenarios — snapshots, backups, recurring jobs, share-manager
   failover — continue to pass; they exercise controllers that stay in the
   DaemonSet.

Scale tests on a 200-node, 5,000-Pod simulated cluster (kwok or real):

- Restart the entire `longhorn-manager` DaemonSet at once and measure
  `kube-apiserver` concurrent Pod-watch count and Pod-LIST QPS during
  initial sync.
- Measure DaemonSet pod RSS at steady state. Expect the namespace-scoped Pod
  informer to drop RSS by an amount proportional to cluster Pod count.

Failure injection:

- Kill the `longhorn-global-manager` leader; verify a standby acquires the
  `Lease` and resumes the controllers without a fresh cluster-wide sync.
- Partition the global manager from `kube-apiserver`; verify the Lease
  transfers to a reachable standby and DaemonSet-side reconciliation
  (volume, engine, replica) is unaffected.

## Note

### Open questions

- **Could other controllers benefit from the same hosting model later?**
  The framework can host additional global-scope controllers, but moving any
  of them is a separate decision and out of scope here. If a particular
  controller's per-DaemonSet duplication later becomes a measurable issue, it
  can be migrated in its own focused enhancement with a per-controller audit.
- **Should the validating webhook move to the global Deployment one day?**
  It is leader-elected today and has no node-local dependency, but it is out
  of scope here because moving it would change the certificate-rotation flow.
- **Should the DaemonSet's Engine/Replica CR informers be narrowed by field
  selector?** An orthogonal optimization. The DaemonSet still needs *some*
  CR informer; the cluster-Pod-count-scaling watch is the Pod informer that
  this proposal already addresses.
