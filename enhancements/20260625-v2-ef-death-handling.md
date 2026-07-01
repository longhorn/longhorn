# V2 Engine - EngineFrontend Death Handling and Pod Recovery

## Summary

This proposal improves the Longhorn V2 engine's handling of **EngineFrontend (EF) death events** — situations where the NVMe-oF frontend serving a volume's I/O becomes unavailable due to an instance manager restart, SPDK crash, or node reboot. The enhancement adds automatic pod recovery: when a v2 EngineFrontend transitions to Error state, the longhorn-manager force-deletes the workload pod so that Kubernetes reschedules it onto a healthy node with a working frontend.

### Related Issues

- TBD

## Motivation

### Problem

When a v2 instance manager pod restarts (e.g., during a rollout or node reboot), all EngineFrontends on that node die. The volume transitions to a faulted state, but the workload pod (StatefulSet, ReplicaSet) remains running on the same node, holding a stale mount point. The pod cannot serve I/O (the block device is gone), but Kubernetes does not restart it because the pod is still technically "Running."

Before this fix, recovery required manual intervention: an operator had to force-delete the workload pod so that Kubernetes rescheduled it onto a node with a healthy EngineFrontend.

### Goals

- Automatically recover workload pods when their v2 EngineFrontend dies
- Force-delete the workload pod when the EF is in Error state, allowing Kubernetes to reschedule
- Kick the workload pod when the EF dies while still attached, triggering reattachment on a healthy node
- Preserve workload pod data (the volume's data is safe on the replicas; only the frontend is down)

### Non-goals

- Force-deleting workload pods for v1 data engine (v1 uses a different frontend mechanism)
- Preventing EF death in the first place (that is addressed by the crash-consistency fixes)
- Changing Kubernetes pod eviction semantics

## Proposal

### Design Overview

The longhorn-manager's pod controller watches for v2 EngineFrontend state transitions. When an EF transitions to Error:

1. **EF dies while attached**: The volume controller kicks the workload pod by deleting it with grace period 0, forcing Kubernetes to reschedule the pod. The pod's new node will have a healthy EF, and the volume reattaches there.

2. **EF in Error state during pod startup**: The pod controller detects that the pod's volume has an EF in Error state and force-deletes the pod, preventing it from starting on a node with a dead frontend.

3. **EF missing entirely**: If the pod's volume has no EngineFrontend at all (the EF CR was deleted), the pod controller force-deletes the pod as a fallback.

### User Stories

#### Story 1

As a cluster operator, I want my workload pods to automatically recover when a v2 instance manager restarts, without manual intervention.

#### Story 2

As a cluster operator, I want workload pods to be force-deleted (not gracefully drained) when their v2 EngineFrontend is in Error, because the graceful drain path hangs on a dead block device.

### Implementation Details

#### Manager Changes

- **Volume controller**: When a v2 EF dies while the volume is attached, kick the workload pod
- **Pod controller**: When a v2 EF is in Error state, force-delete the workload pod (grace period 0)
- **Pod controller**: When a v2 EF is missing, force-delete the workload pod as a fallback
- Test coverage for the EF-missing force-delete fallback

### Test Plan

- Unit tests: pod-controller force-delete on EF Error, volume-controller pod kick on EF death
- Integration tests: EF death during IM restart, pod recovery timeline
- Negative tests: EF in healthy state (no force-delete), v1 volumes (no force-delete)