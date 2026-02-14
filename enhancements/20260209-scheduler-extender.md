# Longhorn Scheduler Extender

## Summary

Kubernetes native storage capacity tracking cannot fully solve several scheduling issues for storage-aware workloads. This enhancement integrates a Scheduler Extender into longhorn-manager to address race conditions between kube-scheduler and external-provisioner, multi-PVC pod scheduling, and pod rescheduling.

A Scheduler Framework plugin was considered but rejected because it requires maintaining a separate container image and replacing the default scheduler image, which is impractical for general Longhorn users. Instead, the extender is embedded in longhorn-manager and can be enabled via a Longhorn setting.

### Related Issues

https://github.com/longhorn/longhorn/issues/12591

## Motivation

Kubernetes native storage capacity tracking cannot solve the following problems:

### Race condition between kube-scheduler and external-provisioner

kube-scheduler might make decisions based on stale data because it relies on `CSIStorageCapacity` objects which are maintained by external-provisioner and not guaranteed to be up to date. Even if the update period of external-provisioner is made very short (e.g. 1s), it does not help because external-provisioner itself gets capacity data from Longhorn, which relies on the Longhorn Node CR that is only updated when volume replicas are actually scheduled by Longhorn.

### Pod with multiple PVCs

The current Kubernetes storage capacity tracking model processes each pod PVC separately and does not take into account that a node may have several disks. The scheduler should evaluate all pod volumes together against all available disks on the node to determine whether they actually fit.

### Pod rescheduling

When a node is drained, the pod needs to be rescheduled to a node where there is enough capacity and replicas can be recreated. When a pod is simply restarted or has failed, it should stay on the same node.

### Goals

1. Resolve the race condition between kube-scheduler and external-provisioner.
2. Support pods with multiple PVCs.
3. Support pod rescheduling when a node is drained:
   - Follow the same process as when a pod is first created. Account for cases when a node already has the pod's volume replicas, since when a node is drained the pod's volume replicas may move to another node before the pod is rescheduled.
   - When a pod is restarted or has failed, restart the pod where it was previously running.

## Proposal

### User Stories

TODO

### User Experience In Detail

The scheduler extender is enabled by setting `scheduler-extender-enabled` to `true` in Longhorn settings. When enabled, one longhorn-manager pod is elected as the leader to run the extender HTTP service. If the leader fails, another pod takes over via leader election.

The cluster administrator must also update the kube-scheduler configuration to register the extender:

```yaml
# /etc/kubernetes/config/kube-scheduler-config.yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: /etc/kubernetes/scheduler.conf  # Path may vary depending on the cluster setup
leaderElection:
  leaderElect: true
extenders:
  - urlPrefix: "http://longhorn-scheduler-extender.longhorn-system.svc:9504"
    filterVerb: "filter"
    enableHTTPS: false
    nodeCacheCapable: false
    ignorable: false   # Note: this prevents scheduling of pods that request the longhorn.io/scheduler-extender resource if the extender is down or unreachable. Set to true if this is not acceptable.
    httpTimeout: 10s
    managedResources:
      - name: "longhorn.io/scheduler-extender"
        ignoredByScheduler: true
```

The kube-scheduler static pod manifest must be updated to use this configuration file via the `--config` flag:

```yaml
# /etc/kubernetes/manifests/kube-scheduler.yaml
spec:
  containers:
    - command:
        - kube-scheduler
        - --config=/etc/kubernetes/config/kube-scheduler-config.yaml
```

kube-scheduler runs as a static pod with `hostNetwork: true`, which means it uses the host's `/etc/resolv.conf` instead of the cluster DNS (CoreDNS). Kubernetes service DNS names (e.g. `longhorn-scheduler-extender.longhorn-system.svc`) will not resolve unless the kube-scheduler pod's `dnsPolicy` is set to `ClusterFirstWithHostNet`. The cluster administrator must add this to the kube-scheduler static pod manifest:

```yaml
# /etc/kubernetes/manifests/kube-scheduler.yaml
spec:
  hostNetwork: true
  dnsPolicy: ClusterFirstWithHostNet
```

Without this change, the extender URL will fail with a DNS lookup error.

Pods that should use the extender must request the `longhorn.io/scheduler-extender` extended resource:

```yaml
resources:
  requests:
    longhorn.io/scheduler-extender: "1"
  limits:
    longhorn.io/scheduler-extender: "1"
```

Only pods with this resource request are sent to the extender. Other pods are unaffected.

### API changes

No CRD changes. No Longhorn REST API changes.

New internal HTTP endpoints on port 9504 (consumed by kube-scheduler):

| Method | Path | Description |
|--------|------|-------------|
| POST | `/filter` | Remove nodes that cannot fit the pod's volumes |
| GET | `/healthz` | Health check |

## Design

### Implementation Overview

A new `scheduler/extender` package is added to longhorn-manager. The HTTP service runs on port 9504 and is started via leader election so that only one longhorn-manager pod serves requests at a time, with automatic failover.

### Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `scheduler-extender-enabled` | bool | false | Enable/disable the scheduler extender. When disabled, the HTTP service does not start. |
| `scheduler-extender-pod-scheduling-timeout` | int | 5 | Seconds to wait for the pod to be scheduled (`spec.nodeName` populated) after returning the filter result. During this time, the extender holds a write lock to prevent stale capacity reads. Set to 0 to disable waiting — the extender returns immediately after filtering. |
| `scheduler-extender-node-reservation-timeout` | int | 5 | Seconds to wait for volume replicas to appear as scheduled on the node. The node is reserved (excluded from scheduling) until replicas are confirmed or the timeout expires. Set to 0 to disable node reservation. |

### Filter

1. Resolve the pod's Longhorn volumes: walk the pod's volumes → PVC → PV → check that the CSI driver is Longhorn → look up the Longhorn Volume. Skip non-Longhorn PVCs. For unbound PVCs with a Longhorn StorageClass, estimate size from the PVC request.
2. If no Longhorn volumes, return all nodes immediately.
3. Pod restart detection: if a node already has replicas for every volume, return only that node. No new capacity is needed, so bin packing is skipped and the pod watch is not started. The extender is called after built-in scheduler plugins (NodeAffinity, TaintToleration, NodeResourcesFit, VolumeZone, etc.), so the node has already been validated for schedulability, taints, affinity, topology, and other constraints.
4. For each candidate node, check if the node can fit the pod's volumes:
   - If the node is currently reserved by a previous scheduling decision, reject it immediately.
   - Get the Longhorn node and verify it allows scheduling, is not being evicted, and is ready and schedulable.
   - For each volume, if the node already has a replica for that volume, skip that volume. Check node selector constraints.
   - Use backtracking bin packing to assign remaining volumes to disks, respecting over-provisioning percentage and disk selectors.
   - Reject the node if the volumes do not fit.
5. **(Optional — controlled by `scheduler-extender-pod-scheduling-timeout`)** After returning the filter result, watch the pod until `spec.nodeName` is populated (i.e. the pod is scheduled to a node) or the timeout elapses. If the pod is scheduled, reserve the node and launch a background goroutine that watches the Longhorn Node CR until all volume replicas appear in `DiskStatus.ScheduledReplica` on that node, then unreserves the node. The replica watch timeout is controlled by `scheduler-extender-node-reservation-timeout`. Skip this step for pod restarts (step 3), since no new capacity is consumed. If `scheduler-extender-pod-scheduling-timeout` is 0, the extender returns immediately after filtering — this is useful for users who only need multi-PVC or pod rescheduling support and do not need the race condition resolution.

### Metrics

The extender exposes Prometheus metrics on the longhorn-manager `/metrics` endpoint to track scheduling performance:

| Metric | Type | Label | Description                                                                   |
|--------|------|-------|-------------------------------------------------------------------------------|
| `longhorn_scheduler_extender_heartbeat` | Gauge | `node` | 1 when the leader is up, 0 otherwise. The `node` label identifies the leader. |
| `longhorn_scheduler_extender_filter_duration_seconds` | Histogram | — | Time from request decode to response sent                                     |
| `longhorn_scheduler_extender_pod_scheduling_wait_duration_seconds` | Histogram | `pod_scheduled` (true/false) | Time waiting for pod `spec.nodeName` to be populated                          |
| `longhorn_scheduler_extender_node_reservation_duration_seconds` | Histogram | `replicas_scheduled` (true/false) | Time waiting for replicas to appear as scheduled on the reserved node         |

### Leader Election and Service Routing

The scheduler extender uses the same leader election pattern as the webhook server (`webhook/webhook.go`). Only the leader pod starts the HTTP service. When the leader fails, another pod acquires the lease and starts serving.

A dedicated Service `longhorn-scheduler-extender` is created without a selector. The leader pod updates the EndpointSlice for this Service to point to its own pod IP. When leadership changes, the new leader updates the EndpointSlice to its own IP. This ensures kube-scheduler always reaches the active leader.

### Test plan

- **Goal 1: Race condition**

  Cluster setup: 4 nodes, each with 1 disk of 400Gi capacity (1600Gi total).

  - Deploy a StatefulSet with 16 replicas in parallel mode (`podManagementPolicy: Parallel`), each requesting a 100Gi PVC with `best-effort` data locality and replica count 1. Pods request the `longhorn.io/scheduler-extender` extended resource. Verify that each node receives exactly 4 pods. Repeat 10 times.
  - Deploy the same StatefulSet but without the `longhorn.io/scheduler-extender` extended resource, so it skips the scheduler extender. Confirm that in this case some nodes receive more than 4 pods and some less (kube-scheduler over-provisions nodes because it relies on stale `CSIStorageCapacity` data). Repeat 10 times.
  - Compare time until StatefulSet becomes ready in both cases to measure scheduling performance and latency.

- **Goal 2: Pod with multiple PVCs**

  Cluster setup: 4 nodes with asymmetric disk configuration — node 1 has 1 disk, node 2 has 2 disks, node 3 has 3 disks, node 4 has 4 disks. Each disk is 100Gi.

  - Create a pod with 4 PVCs of 100Gi each (`best-effort` data locality, replica count 1), requesting the `longhorn.io/scheduler-extender` extended resource. Confirm that the pod is placed on node 4 (the only node with enough disks to fit all 4 volumes). Repeat 10 times.
  - Create the same pod but without the `longhorn.io/scheduler-extender` extended resource. Confirm that the pod can be scheduled on any node (kube-scheduler is unaware of per-disk capacity).

- **Goal 3: Pod rescheduling**

  - **Case A: Node drain**

    Cluster setup: 4 nodes, each with 1 disk. Two nodes have 400Gi disks, two nodes have 99Gi disks.

    - Create a StatefulSet with 4 replicas, each requesting a 100Gi PVC (`best-effort` data locality, replica count 1) with the `longhorn.io/scheduler-extender` extended resource. Cordon all nodes except one 400Gi node. Create the StatefulSet — all pods land on that single node. Uncordon all nodes, then drain the node with the StatefulSet. Confirm all pods move to the other 400Gi node (not the 99Gi nodes which cannot fit them). Repeat 3 times.
    - Same setup but without the `longhorn.io/scheduler-extender` extended resource. Drain the node and confirm that pods can go anywhere, including the 99Gi nodes.

  - **Case B: Pod restart**

    Cluster setup: 4 nodes, each with 1 disk of 400Gi.

    - Create a StatefulSet with 16 replicas, each requesting a 100Gi PVC (`best-effort` data locality, replica count 1) with the `longhorn.io/scheduler-extender` extended resource. PVC reclaim policy set to Retain. Record which node each pod was on. Delete the StatefulSet and recreate it. Confirm each pod goes back to the same node as before. Repeat 3 times.
    - Same setup but without the `longhorn.io/scheduler-extender` extended resource. Delete and recreate the StatefulSet. Confirm that pods may go to different nodes than before.

### Upgrade strategy

No upgrade strategy needed.

## Note

### Volume parameters

This proposal is designed for volumes with `best-effort` data locality and replica count of 1. For other volume setups this proposal doesn't work well.

### Why Scheduler Extender instead of Scheduler Framework

Kubernetes Scheduler Framework plugins are compiled into the scheduler binary. Using a framework plugin would require:
- Maintaining a separate container image for the custom scheduler
- Replacing the default kube-scheduler image in the cluster
- Updating the image on every Kubernetes version upgrade

This is impractical for general Longhorn users. Additionally, users who already run a custom scheduler would need to include Longhorn's plugin code when compiling their scheduler, making integration even harder. A Scheduler Extender works with the existing kube-scheduler (or any custom scheduler) without image changes, since it is invoked as an external HTTP callback. By embedding it in longhorn-manager, there is no additional component to deploy or maintain.

### Managed Kubernetes limitation

Scheduler Extenders require modifying the kube-scheduler configuration, which is not possible on managed Kubernetes offerings such as GKE and EKS where users do not have access to the control plane. This feature is therefore limited to self-managed clusters where the administrator can configure kube-scheduler. A possible workaround for managed clusters is to deploy a secondary scheduler with the extender configured and set schedulerName on the pod to use it instead of the default kube-scheduler, but this largely defeats the purpose of choosing a scheduler extender over a scheduler framework.
