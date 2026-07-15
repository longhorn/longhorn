# V2 Engine - RDMA Transport Support

## Summary

This proposal introduces **RDMA (Remote Direct Memory Access)** transport support for the Longhorn V2 data engine, complementing the existing NVMe/TCP transport. RDMA enables direct memory-to-memory data transfer between the SPDK NVMe-oF target (replica) and initiator (engine) without CPU involvement on either side, reducing latency and CPU overhead for high-throughput workloads.

Phase 1 keeps the design deliberately simple:

- The operator **explicitly** chooses the NVMe-oF transport per node (no automatic hardware detection as the primary UX).
- Each engine uses a **single** transport type to connect to **all** of its replicas for a given attachment.
- Focus is **RoCE v2**.

### Related Issues

- TBD (will be created with the PR)

## Motivation

### Goals

- Enable RDMA (RoCE v2) transport for v2 volumes on nodes with RDMA-capable hardware.
- Keep TCP as the default and fully supported path for clusters without RDMA.
- Let the operator opt a node into RDMA via an explicit node label.
- Ensure an engine uses one transport for all replica connections during an attachment (predictable behavior, fewer edge cases).
- Expose transport-qualified replica addresses and listener ports on CRDs so operators can verify which path is in use.

### Non-goals

- RDMA for the v1 data engine (v1 uses iSCSI, not NVMe-oF).
- iWARP or InfiniBand-native transports (RoCE v2 only for phase 1).
- Automatic RDMA hardware detection / auto-labeling as the primary configuration path (possible future improvement once the basic feature is stable).
- Mixed transports for a single engine within one attachment (e.g. RDMA to some replicas and TCP to others). Future work after the basic feature is stable.
- Mid-flight failover from RDMA to TCP (or vice versa) for a running connection. Transport changes require detach/reattach.
- Per-node SPDK resource overrides (CPU mask, memory size, interrupt mode, IM CPU request). Those are covered by a separate LEP: [20260715-v2-per-node-spdk-overrides](./20260715-v2-per-node-spdk-overrides.md).

## Proposal

### Design Overview

The V2 engine uses SPDK NVMe-oF for replica ↔ engine communication. Today only TCP is supported. This enhancement adds RDMA as an alternative transport selected explicitly by the operator.

#### Explicit transport selection

Node transport is set by the operator with the Kubernetes node label:

- `node.longhorn.io/nvmf-transport=rdma` — this node's V2 instance manager creates RDMA listeners and engines on this node dial replicas over RDMA.
- `node.longhorn.io/nvmf-transport=tcp` (or unset) — TCP only (current behavior).

There is **no** automatic labeling in phase 1. The operator is responsible for applying the label only on nodes that have working RDMA hardware and drivers.

#### Single transport per engine attachment

When an engine is created on a node, it uses that node's configured transport for **every** replica attach in that attachment. The manager does not build a mixed-transport attach set for one engine.

Practical implication for scheduling: for RDMA attachments, all replicas that the engine must dial should also be on RDMA-capable (RDMA-labeled) nodes, or the attach fails clearly rather than silently mixing transports.

#### Dual-listener on RDMA replicas (mixed *cluster* topology, not mixed *engine* dial)

Replicas on RDMA-labeled nodes may expose **both** an RDMA listener and a TCP listener (TCP on `port+1`). The CRD carries transport-qualified addresses (`tcp_address`, `rdma_address`).

This supports mixed *clusters* where some engines run on TCP-only nodes and some on RDMA nodes:

- An engine on an RDMA node dials every replica's `rdma_address`.
- An engine on a TCP node dials every replica's `tcp_address`.

That is **not** mid-flight failover and **not** per-replica transport mixing within one engine. Each engine still uses one transport for all of its replica connections.

#### hostNetwork for RDMA instance managers

V2 instance managers on RDMA-labeled nodes run with `hostNetwork: true` and mount `/dev/infiniband` so SPDK can bind the RDMA transport to the host NIC. Interrupt mode is forced off for RDMA (SPDK RDMA poll groups do not support fd-based interrupt wakeup); see the per-node SPDK overrides LEP for related labels.

### User Stories

#### Story 1

As a cluster operator with RoCE v2 hardware, I want to label storage and compute nodes for RDMA so that v2 volumes attached on those nodes use RDMA for replica I/O, reducing latency and CPU usage.

#### Story 2

As a cluster operator without RDMA hardware (or not ready to enable it), I want the default TCP path to remain unchanged so that upgrading Longhorn does not require RDMA configuration.

#### Story 3

As a cluster operator with a mixed cluster (some RDMA nodes, some TCP-only), I want TCP engines to keep working against replicas that also advertise a TCP listener, while RDMA engines use RDMA end-to-end for their attachments.

### User Experience In Detail

1. **Prepare nodes**: Install RDMA drivers, verify RoCE v2 connectivity, and size hugepages / CPU for SPDK as usual for v2.
2. **Opt in**: Label nodes that should use RDMA:
   ```bash
   kubectl label node <node-name> node.longhorn.io/nvmf-transport=rdma
   ```
3. **Instance managers**: Longhorn recreates V2 IM pods on labeled nodes with host networking and RDMA device access. Replicas on those nodes advertise RDMA (and TCP fallback) listener addresses.
4. **Attach**: When a volume's engine is scheduled on an RDMA-labeled node, it connects to all replicas via RDMA. When on a TCP node, it connects via TCP.
5. **Verify**: Inspect engine/replica status for the transport in use (transport-qualified addresses / per-path transport fields).
6. **Change transport**: Update the node label, then detach and reattach affected volumes (no live transport switch).

### API changes

- **types / gRPC**: `ReplicaTransportAddresses` (`tcp_address`, `rdma_address`); `replica_transport_address_map` on instance/engine create paths; dual listener ports where applicable.
- **CRD**: Engine/Replica fields for transport-qualified addresses and listener ports (`tcpPort` / `rdmaPort` as needed).
- **Node label**: `node.longhorn.io/nvmf-transport` = `tcp` | `rdma` (operator-set).

## Design

### Implementation Overview

#### SPDK / packaging

- Build `spdk_tgt` with RDMA (`--with-rdma`); assert RDMA libraries are linked in the instance-manager image when RDMA support is enabled.
- Create NVMf RDMA transport at IM startup when the node is configured for RDMA.
- Small RDMA-related SPDK fixes required for production RoCE (e.g. NULL-guard `rdma_qp` in memory-domain helpers; mlx5 CRC offload quirks) — tracked with the SPDK v26.05 bump LEP.

#### longhorn-spdk-engine

- Transport module: create RDMA (and TCP) NVMf transports with appropriate options.
- Replica expose: dual-listener when RDMA is enabled; report transport-qualified addresses.
- Engine create/attach/rebuild/snapshot-expose: honor the single transport selected for the engine; dial the matching address from the transport map.
- No runtime RDMA→TCP attach failover.

#### go-spdk-helper

- Transport-aware NVMe-oF initiator/client APIs (TCP + RDMA).
- NVMf transport option wrappers (including options needed on SPDK v26.05 iobuf-backed transports).

#### longhorn-instance-manager

- Plumb transport through instance create/status.
- Packaging: RDMA runtime libraries; wrapper rlimits / `--wait-for-rpc` as needed for RDMA bring-up.
- Minimal prestop: graceful listener drain and bounded flush to avoid stale mounts on IM shutdown.

#### longhorn-manager

- CRD + codegen for transport address maps and ports.
- Build and propagate a consistent replica transport address map into engine create (single transport per attachment).
- Honor `node.longhorn.io/nvmf-transport` for IM pod hostNetwork / device mounts.
- Do **not** auto-detect and label RDMA hardware in phase 1.

#### charts

- CRD field updates for transport address maps and ports.

### Test plan

- Unit tests: transport map construction, single-transport dial selection, dual-listener advertisement.
- Integration: RDMA-only cluster (all relevant nodes labeled); TCP-only cluster (no labels); mixed cluster where TCP engines dial TCP addresses of dual-listener replicas and RDMA engines dial RDMA addresses.
- Negative: engine on RDMA node with a replica that has no RDMA address → clear failure (no silent mixed dial).
- Failover / ops: IM restart on RDMA node; node reboot; label change + reattach.
- Rebuild and backup/restore snapshot expose over RDMA.

### Upgrade strategy

- Existing TCP-only clusters are unchanged until an operator sets `nvmf-transport=rdma`.
- Upgrading IM/manager images adds RDMA capability but does not change behavior without the label.
- No data migration — transport is a connection-layer property.

## Note

A production fork may currently auto-label nodes based on RDMA hardware presence for operational convenience. That behavior is intentionally **out of scope for upstream phase 1**, per review feedback favoring an explicit operator choice and a single transport per engine attachment before adding auto-detection or mixed-transport niceties.
