# Global Longhorn Manager

## Summary

`longhorn-manager` runs as a DaemonSet — one pod per node. Each pod
hosts every Longhorn control-plane reconciler alongside the genuinely
node-local work (replica/engine/instance-manager lifecycle, disk
monitoring, environment checks). This worked well when Longhorn was
small but, as the project and target cluster sizes have grown, two
scaling issues now stand out:

1. **`kube-apiserver` watch fan-out from the cluster-wide Pod
   informer.** A few Longhorn controllers need to observe workload
   Pods across all namespaces — for example, to force-delete a
   workload pod when a node goes down, or to track which workload is
   using a Longhorn PV. Because every DaemonSet pod runs these
   controllers, the cluster pays for one cluster-wide Pod watch per
   node. On a 200-node cluster with 5,000 pods, that is 200
   concurrent watches and ~1 million Pod objects served on every
   rolling restart of the DaemonSet (200 LISTs × 5,000 pods).

2. **Per-pod memory from informer caches.** Each manager pod caches
   every object its informers watch. Pod cache size is determined by
   the cluster's pod count, not the node's, so adding nodes
   multiplies the same large Pod cache N times across DaemonSet
   pods.

Both costs grow linearly with the cluster, even though the
controllers driving them are owner-elected — only one daemon pod is
doing useful work for any given resource at any moment. The other
N − 1 daemon pods carry the full watch and cache cost only to be
ready in case ownership transfers.

This proposal introduces **`longhorn-global-manager`**, a
leader-elected `Deployment` that runs as a single active pod (with
hot standbys) and hosts the controllers requiring cluster-wide Pod
visibility. The DaemonSet's Pod informer narrows from cluster-wide
to namespace-scoped (`longhorn-system`), since the remaining Pod
consumers in the DaemonSet only ever look at Pods in that namespace.

This release **focuses on the cluster-wide Pod informer consumers**
— `KubernetesPVController` and `KubernetesPodController`. They are
the source of the two scaling issues above, so moving them captures
the bulk of the resource savings in a single, well-bounded change.
The framework introduced here can host additional controllers in
the future if a specific case justifies the move, but no further
migration is committed by this enhancement.

The change is **opt-in and default-off**: the chart toggle
`globalManager.enabled` defaults to `false`, so existing operators
see no behavioral change on upgrade. Operators who want the new
topology set the toggle to `true`; the chart then deploys the global
manager alongside the DaemonSet and the DaemonSet runs in node-local
mode.

### Related Issues

- TBD (filed against `longhorn/longhorn`)

## Motivation

### Goals

- Introduce `longhorn-global-manager` as a leader-elected Deployment
  capable of hosting Longhorn controllers that don't need node-local
  context.
- In this release, migrate the cluster-wide Pod informer consumers —
  `KubernetesPVController` and `KubernetesPodController` — so the
  cluster-wide Pod watch and cache are held by a single active pod
  instead of every DaemonSet pod.
- Preserve existing operator behavior on upgrade. Operators who do
  not opt in see no behavioral change. Operators who opt in see no
  volume detach or downtime during the toggle flip.

### Non-goals

- Migrating other controllers in this release. The framework supports
  hosting additional controllers in the global manager later, but
  any further migration is decided case-by-case (e.g. when a
  specific scaling need surfaces) and is not committed by this
  enhancement.
- Changing the CSI plugin DaemonSet (`longhorn-csi-plugin`).
  Mount/unmount must remain node-local and is unaffected.
- Eliminating the DaemonSet. Many Longhorn controllers (replica,
  engine, instance manager, backing-image manager, orphan, node-disk
  monitor) depend on host paths or unix-domain sockets that cannot be
  reached from a network-only Deployment. The DaemonSet remains the
  hosting model for those.
- Rewriting reconciliation algorithms. Each migrated controller's
  core flow stays as-is; only its hosting process changes. Narrow
  adjustments may be required where `controllerID` was being used
  beyond ownership election (e.g. as a node identifier), but no
  algorithmic redesign.
- Replacing the existing webhook/recovery-backend leader election.
  Those keep their current single-leader-among-DaemonSet scheme.

## Proposal

### User Story

A cluster admin running a 100+ node Longhorn cluster observes that:

- Restarting all `longhorn-manager` pods at once briefly spikes
  `kube-apiserver` to several hundred concurrent list-pods requests.
- Each manager pod's RSS climbs in step with the cluster's total pod
  count, not the node's.
- Adding nodes inflates the kube-apiserver bill linearly even when
  the number of Longhorn volumes is unchanged.

After enabling `globalManager.enabled=true` in the chart, cluster-wide
Pod watches originate from a single active `longhorn-global-manager`
pod instead of one per node. DaemonSet pod RSS no longer scales with
cluster pod count. No volume detachment or downtime is required to
flip the toggle.

### User Experience In Detail

#### Helm chart

A new `globalManager` block in `chart/values.yaml`:

- `globalManager.enabled` (default `false`) — when true, the chart
  renders the `longhorn-global-manager` Deployment and adds a flag to
  the DaemonSet so it skips the migrated controllers.
- Standard knobs for the Deployment: replicas (default 2), priority
  class, resource requests, tolerations, node selector.

Existing operators do nothing on upgrade and see no behavioral
change. Operators who opt in run `helm upgrade --set globalManager.enabled=true`.

#### Topology after opt-in

```
NAME                                       NODE
longhorn-global-manager-...-aaa            ip-10-0-1-105   # leader
longhorn-global-manager-...-bbb            ip-10-0-1-113   # standby
longhorn-manager-aaaaa                     ip-10-0-1-102
longhorn-manager-bbbbb                     ip-10-0-1-105
longhorn-manager-ccccc                     ip-10-0-1-113
```

Leader election uses a `coordination.k8s.io/v1` `Lease` named
`longhorn-global-manager` in the longhorn-system namespace, mirroring
the convention of the existing webhook lease. The
`longhorn-backend`, `longhorn-frontend`, validating webhook, and
metrics endpoints continue to point at the DaemonSet — unchanged.

### API changes

None at the Longhorn CR or REST API level. Internally:

- A new Lease object (`longhorn-global-manager`) for global manager
  leader election. Existing RBAC for the Lease resource already
  covers it.
- A new Deployment (`longhorn-global-manager`) added to the chart,
  rendered only when the toggle is enabled.
- The global manager runs with the existing
  `longhorn-service-account`. It does not need `privileged: true` and
  does not mount host paths.

## Design

### Which controllers are eligible for the global manager

For framing, Longhorn controllers fall into three categories with
respect to where they can be hosted:

| Category | Examples | Eligible for global manager? |
| --- | --- | --- |
| **Node-local** — touch host paths, call IM gRPC over localhost, or have CR ownership keyed off `Spec.NodeID` | `Replica`, `Engine`, `InstanceManager`, `BackingImageManager`, `BackingImageDataSource`, `Orphan`, `Node` (disk monitor), `MetricsCollector`s | No — must stay in DaemonSet |
| **Global-scope** — owner-elected across the cluster, no node-local dependency | `Volume` and Volume workflow controllers, `Snapshot`, Backup family, `BackingImage`, `EngineImage`, `RecurringJob`, `ShareManager`, `SystemBackup`, `SystemRestore`, `SupportBundle`, `Setting`, `KubernetesPV`, `KubernetesPod`, `KubernetesConfigMap`, `KubernetesSecret`, `KubernetesPDB`, `KubernetesEndpoint` | Yes — eligible to move when justified |
| **Coupled to the in-process REST API server** | `WebsocketController` | No — stays in DaemonSet for routing reasons |

The middle category lists what *could* potentially be hosted by the
global manager. Whether a particular controller actually moves is a
separate decision per controller — most have their own reconciliation
invariants and some have cross-controller data dependencies that need
careful analysis. **This enhancement does not propose a migration
plan for any of them beyond the two below.**

#### This release: the cluster-wide Pod informer consumers

The two controllers in scope this release are
`KubernetesPVController` and `KubernetesPodController`. Of all
controllers that watch Pods, only these two need cluster-wide
visibility (they track workload Pods across all namespaces). The
other Pod consumers in the DaemonSet — `InstanceManagerController`,
`BackingImageManagerController`, `BackingImageDataSourceController`,
`ShareManagerController`, `KubernetesEndpointController`, the
manager-pod filter inside `NodeController` — only observe Pods in
the longhorn-system namespace and work identically against a
namespace-scoped Pod informer.

This is what makes the PV/Pod migration well-bounded: it lets the
DaemonSet's Pod informer narrow from cluster-wide to
namespace-scoped without changing how any other controller behaves.
The remaining DaemonSet-hosted controllers continue to function
unchanged, and cluster-wide Pod watches collapse from one per
DaemonSet pod (O(node count)) to one per active global-manager
leader — directly addressing both scaling issues from the Summary.

### How upgrade and opt-in are kept safe

The change is **default-off** and **opt-in**, with three layers of
protection:

1. **Helm value default `globalManager.enabled=false`.** Existing
   operators upgrading via `helm upgrade` keep their previous value
   (Helm preserves user values across upgrades). They see no
   topology change.
2. **Chart conditionally adds the daemon flag.** A new daemon flag
   (`--node-local-only`) is added to the DaemonSet's command-line only
   when the helm value is `true`. With default values, the flag is
   absent and the daemon binary's flag default keeps the consolidated
   single-process model.
3. **Daemon binary default preserves consolidated mode.** Even if the
   binary is invoked directly (without helm), the absence of
   `--node-local-only` means the daemon hosts all controllers
   in-process — exactly as today.

Each layer independently maintains backward compatibility. Removing
the toggle, dropping the chart conditional, or changing the binary
default are each blocked by the others.

#### Three operator scenarios

| Scenario | What the operator sees | What happens |
| --- | --- | --- |
| **Existing operator, doesn't change anything** | No change at all | Helm value stays `false`. Daemonset has no new flag. Daemon runs in consolidated mode (all controllers in one process per node). Identical to pre-upgrade. |
| **Operator wants to keep the old behavior explicitly** | Same as above; no action needed | The default is the safe path. |
| **Operator wants to opt into split topology** | `helm upgrade --set globalManager.enabled=true` | Chart deploys `longhorn-global-manager` Deployment. DaemonSet rolls with `--node-local-only` added. Migrated controllers move to the new leader-elected pod. No volume detach or downtime is required. |

#### What happens during the opt-in toggle flip

1. The new `longhorn-global-manager` Deployment is created. Its
   leader acquires the Lease and starts the migrated controllers.
2. Helm rolls the DaemonSet, replacing each pod with one started
   under `--node-local-only`. During the rollout window, the old
   DaemonSet pods (still running migrated controllers) and the global
   manager may briefly race on the same `Volume.Status.KubernetesStatus`
   updates. The race resolves via the existing
   `apierrors.IsConflict` retry path that already handles concurrent
   writers in today's owner-election model. No CR `Status.OwnerID`
   flip is involved — the migrated controllers don't own a Longhorn
   CR — so steady-state values are unchanged from before the upgrade.
3. After the rollout, cluster-wide Pod watches originate from the
   global manager only.

### Sharding behavior preservation

Migrated controllers contain per-node sharding guards that gate work
on the controller's node identity. These guards exist to avoid
duplicate work across the N DaemonSet pods.

Under the global manager, the singleton leader is the only writer, so
sharding is unnecessary. Inside the DaemonSet's consolidated mode
(default for non-opted-in operators), the same guards must remain
active to preserve existing behavior.

The guards therefore become **mode-aware**: the controllers receive a
flag indicating whether they are hosted by the global manager
Deployment, and skip the guards only in that case. Operators who
don't opt in see exactly the same per-node sharded behavior as
today.

### Global manager process model

The global manager runs as a `Deployment` with leader election via
`coordination.k8s.io/v1` Lease. Only the elected leader runs informers
and controllers; standby pods block on the leader-election library
and start their controllers when leadership is acquired.

When the leader loses the lease (renewal failure or process signal),
the process exits, mirroring the convention used by
`kube-controller-manager`. The Deployment recreates the pod, and the
new pod joins as a standby. A surviving standby acquires the lease
within the lease duration window (~20 s).

### Failure modes

| Failure | Behavior |
| --- | --- |
| Global manager leader crash | A standby acquires the Lease in ≤ 20 s, then warms its informer caches before reconciling — actual reconcile resume includes a few seconds of cluster-wide Pod cache sync time on large clusters (200+ nodes / 5000+ pods); the Lease itself is held throughout. Node-local controllers in the DaemonSet are unaffected. |
| All global manager replicas evicted | PV/Pod handling pauses (force-delete on node-down, RWX remount, force-delete cleanup, KubernetesStatus tracking) until rescheduled. Volume reconciliation continues in the DaemonSet. |
| Network partition between global manager and a node | The global manager treats the partitioned node as down via the existing `IsNodeDownOrDeletedOrMissingManager` path. Node-local controllers continue acting on local CRs only. |

In-flight volume I/O is independent of the control plane in either
configuration — the data plane lives in the engine/replica processes
spawned by InstanceManager.

Mitigations: run ≥ 2 replicas with hostname anti-affinity, and set a
`priorityClassName` equal to `longhorn-critical` so the Deployment is
not evicted before lower-priority workloads.

### Test plan

Run the following scenarios in **both** consolidated mode (toggle
off, default) and split mode (toggle on):

1. Volume create / attach to a workload Pod / write data / detach /
   delete (RWO and RWX).
2. Force-delete a workload Pod with a Longhorn volume on a downed
   node: verify VolumeAttachment cleanup.
3. Trigger a Volume remount via `Volume.Status.RemountRequestedAt`:
   verify the workload Pod is recreated.
4. Kill a CSI plugin Pod while an RWX volume is mounted: verify the
   workload Pod on that node is force-deleted.
5. Existing scenarios — snapshots, backups, recurring jobs,
   share-manager failover — continue to pass; they exercise
   controllers that stay in the DaemonSet.
6. Toggle flip on a populated cluster: verify no volume re-attach
   occurs and PV/Pod handling continues across the rollout.

Scale tests on a 200-node, 5,000-pod simulated cluster (kwok or
real):

- Restart the entire `longhorn-manager` DaemonSet at once and measure
  `kube-apiserver` concurrent Pod-watch count and Pod-LIST QPS during
  initial sync, before and after the toggle is on.
- Measure DaemonSet pod RSS at steady state. Expect removal of the
  cluster-wide Pod informer to drop RSS by an amount proportional to
  cluster pod count.

Failure-injection:

- Kill the `longhorn-global-manager` leader; verify a standby
  acquires the Lease within ~20 s and resumes the controllers.
- Partition the global manager from `kube-apiserver`; verify
  DaemonSet-side reconciliation (volume, engine, replica) is
  unaffected.

## Note

### Open questions

- **Could other controllers benefit from the same hosting model
  later?** The framework introduced here can host additional
  global-scope controllers in the Deployment, but moving any of them
  is a separate decision and explicitly out of scope here. If a
  particular controller's per-DaemonSet duplication later turns into
  a measurable issue, it can be migrated in its own focused
  enhancement with a per-controller audit (covering things like
  `controllerID` reads outside ownership election, or cross-controller
  `Status.OwnerID` assumptions).
- **Should the validating webhook move to the global Deployment one
  day?** It is leader-elected today and has no node-local dependency,
  but out of scope here because it would change the certificate-
  rotation flow.
- **Should the DaemonSet's Engine/Replica CR informers be narrowed
  by field selector?** An orthogonal optimization. The DaemonSet
  still needs *some* CR informer, and the cluster-pod-count-scaling
  watch is the Pod informer that this proposal already removes.
