# V2 Engine - Per-Node SPDK Configuration Overrides

## Summary

This proposal adds Kubernetes **node labels** that override cluster-wide V2 data-engine SPDK settings on a per-node basis. Operators can pin CPU masks, hugepage memory size, interrupt mode, and V2 instance-manager CPU requests differently across heterogeneous nodes (for example dedicated storage workers vs general compute).

Transport selection (`node.longhorn.io/nvmf-transport`) is specified in the [RDMA transport LEP](./20260625-v2-rdma-transport-support.md) and is only cross-referenced here where it forces interrupt mode off or requires host networking.

### Related Issues

- TBD

## Motivation

### Goals

- Allow per-node overrides of V2 SPDK CPU mask, memory size, and interrupt mode without changing cluster-wide settings.
- Allow per-node V2 instance-manager CPU requests for nodes that host many engines/replicas.
- Document precedence: node label > IM/spec override > cluster setting.
- Document that RDMA forces interrupt mode off (SPDK RDMA poll groups cannot use fd-based interrupt wakeup).

### Non-goals

- Defining the RDMA transport feature itself (see the RDMA LEP).
- Auto-tuning or recommending specific masks/sizes for hardware vendors.
- Changing the meaning of existing cluster-wide settings (`data-engine-cpu-mask`, `data-engine-memory-size`, `data-engine-interrupt-mode-enabled`).

## Proposal

### User Stories

#### Story 1

As an operator with dedicated high-memory storage nodes, I want those nodes to run SPDK with a larger hugepage allocation than the cluster default so replica I/O and rebuilds have enough iobuf / reactor memory.

#### Story 2

As an operator with heterogeneous CPU topologies, I want to pin SPDK reactors to a node-specific CPU mask without forcing the same mask on every node.

### User Experience In Detail

Apply labels to the Kubernetes node, then allow Longhorn to recreate the V2 instance manager so the new values take effect (same danger-zone sync semantics as existing cluster-wide SPDK settings where applicable):

```bash
kubectl label node <node-name> node.longhorn.io/spdk-cpu-mask=0xFF
kubectl label node <node-name> node.longhorn.io/spdk-memory-size=16384
kubectl label node <node-name> node.longhorn.io/spdk-interrupt-mode=false
kubectl label node <node-name> node.longhorn.io/v2-im-cpu-request=4
```

Remove a label to fall back to the cluster-wide setting:

```bash
kubectl label node <node-name> node.longhorn.io/spdk-cpu-mask-
```

### API changes

| Label | Values | Overrides |
|-------|--------|-----------|
| `node.longhorn.io/spdk-cpu-mask` | Hex mask (e.g. `0xFF`) | `data-engine-cpu-mask` |
| `node.longhorn.io/spdk-memory-size` | Decimal MiB (e.g. `16384`) | `data-engine-memory-size` |
| `node.longhorn.io/spdk-interrupt-mode` | `true` / `false` | `data-engine-interrupt-mode-enabled` |
| `node.longhorn.io/v2-im-cpu-request` | Cores or millicores (e.g. `4`, `4000m`) | V2 IM pod CPU request |

Related (documented in the RDMA LEP, not redefined here): `node.longhorn.io/nvmf-transport`. When it is `rdma`, interrupt mode is forced to `false` regardless of other overrides, and the V2 IM uses host networking / InfiniBand device mounts.

## Design

### Implementation Overview

- **longhorn-manager**: Read node labels when reconciling V2 InstanceManager pods; inject effective CPU mask, memory size, interrupt mode, and CPU request into the pod spec / env as today for cluster settings; force interrupt-mode off when transport is RDMA; sync hostNetwork with RDMA transport label.
- **instance-manager wrapper**: Honor exported cpumask / memory-size env (already used for `spdk_tgt` and for engine-side iobuf budgeting on SPDK v26.05).
- Precedence: node label > existing IM/spec override > cluster setting.

### Test plan

- Unit: label resolution and RDMA interrupt-mode force-off.
- Integration: heterogeneous labels across nodes; IM recreation picks up new values; removing a label restores cluster default.
- Negative: invalid mask / non-numeric memory size rejected or logged without wedging reconcile.

### Upgrade strategy

- Additive. Unlabeled nodes keep cluster-wide behavior.
- No volume data migration.
