# V2 Engine - RDMA Transport Support

## Summary

This proposal introduces **RDMA (Remote Direct Memory Access)** transport support for the Longhorn V2 data engine, complementing the existing NVMe/TCP transport. RDMA enables direct memory-to-memory data transfer between the SPDK NVMe-oF target (replica) and initiator (engine frontend) without CPU involvement on either side, significantly reducing latency and CPU overhead for high-throughput workloads.

The implementation adds:
- Transport-aware replica addressing with dual-listener support (TCP + RDMA)
- Automatic transport negotiation based on node hardware capabilities
- Per-path NVMe-oF transport reporting on engine and replica CRDs
- Node-label-based transport selection (`node.longhorn.io/nvmf-transport`)

### Related Issues

- TBD (will be created with the PR)

## Motivation

### Goals

- Enable RDMA transport for v2 volumes on nodes with RDMA-capable hardware (Mellanox ConnectX, etc.)
- Maintain full backward compatibility with TCP-only nodes
- Allow mixed clusters where some nodes use RDMA and others use TCP
- Automatic transport detection without requiring user configuration for basic operation

### Non-goals

- RDMA for v1 data engine (v1 uses iSCSI, not NVMe-oF)
- iWARP or other non-InfiniBand RDMA protocols (focus on RoCE v2)
- Dynamic transport switching for running volumes (requires reattach)

## Proposal

### Design Overview

The V2 engine uses SPDK's NVMe-oF (NVMe over Fabrics) for replica-to-engine communication. Previously, only TCP transport was supported. This enhancement adds RDMA transport alongside TCP, with the engine automatically selecting the best available transport per replica connection.

#### Dual-Listener Architecture

Each replica exposes two NVMe-oF listeners:
1. **TCP listener** — always active, provides baseline connectivity
2. **RDMA listener** — active only when the node has RDMA hardware and the `nvmf-transport` label is set to `rdma`

The engine's `EngineCreate` RPC accepts a `replica_transport_address_map` that carries both `tcp_address` and `rdma_address` for each replica. The engine picks whichever address matches its own node's transport.

#### Transport Detection

Node transport is determined by the `node.longhorn.io/nvmf-transport` label:
- `rdma` — node has RDMA hardware, engine uses RDMA for connections
- `tcp` (default) — node uses TCP for all connections
- No label — auto-detect based on RDMA hardware presence (future)

### User Stories

#### Story 1

As a cluster operator with RDMA-capable hardware, I want my v2 volumes to use RDMA transport automatically so that I get lower latency and reduced CPU usage without any application changes.

#### Story 2

As a cluster operator with a mixed cluster (some nodes with RDMA, some without), I want v2 volumes to use RDMA where available and fall back to TCP otherwise, so that I don't need homogeneous hardware.

### User Experience In Detail

1. **Enable RDMA on a node**: Apply the node label `node.longhorn.io/nvmf-transport=rdma` and ensure RDMA hardware + drivers are present.
2. **Automatic selection**: When a v2 volume's engine is created on an RDMA-labeled node, it connects to replicas via RDMA. When on a TCP node, it uses TCP.
3. **Mixed clusters**: A volume's engine on an RDMA node connects to all replicas via RDMA if the replica's node also supports RDMA. If a replica is on a TCP-only node, the engine falls back to TCP for that specific replica.
4. **Transport reporting**: The `Engine` and `Replica` CRDs expose the transport type in their status, allowing operators to verify which transport is in use.

### Configurable Settings

#### Node Label: `node.longhorn.io/nvmf-transport`

- **Values**: `rdma`, `tcp` (default: `tcp`)
- **Scope**: Per-node
- **Effect**: Controls which NVMe-oF transport the engine on that node uses for replica connections
- **Auto-detection**: The longhorn-manager automatically detects RDMA hardware and applies the label. Manual override is supported.

#### Additional Per-Node Labels

The V2 data engine supports several per-node labels that override cluster-wide settings. These are documented in the user-facing docs under [Per-Node V2 Configuration Labels](https://longhorn.io/docs/advanced-resources/v2-data-engine/node-labels/).

| Label | Values | Description |
|-------|--------|-------------|
| `node.longhorn.io/nvmf-transport` | `tcp`, `rdma` | NVMe-oF transport type (auto-detected) |
| `node.longhorn.io/spdk-cpu-mask` | Hex string (e.g. `0xFF`) | CPU mask for SPDK reactor threads. Overrides `data-engine-cpu-mask`. |
| `node.longhorn.io/spdk-memory-size` | Decimal MiB (e.g. `16384`) | Hugepage memory size for SPDK. Overrides `data-engine-memory-size`. |
| `node.longhorn.io/spdk-interrupt-mode` | `true`, `false` | Enable/disable interrupt mode. Overrides `data-engine-interrupt-mode-enabled`. Forced `false` when `nvmf-transport=rdma`. |
| `node.longhorn.io/v2-im-cpu-request` | Cores or millicores (e.g. `4`, `4000m`) | CPU request for the V2 instance manager pod. |

Per-node labels take precedence over cluster-wide settings, enabling heterogeneous configurations where different nodes have different CPU, memory, or transport requirements.

### Implementation Details

#### SPDK Changes

- `bdev_nvme` module: allow global NVMe transport type overwrite
- `nvmf` module: RDMA transport creation via `nvmf_create_transport(rdma)`
- `mlx5` driver: force `crc32c_supported=false` to skip sig mkey pool allocation (RDMA-specific optimization)

#### Engine Changes

- Replica attach: dual-listener creation (TCP + RDMA) on `ReplicaCreate`
- Engine create: accept `replicaTransportAddressMap` in the gRPC request
- Rebuild: transport-aware rebuild destination attach
- Snapshot expose: transport-aware snapshot exposure for backup/restore/backing-image
- EngineFrontend: per-path transport reporting on CRD status

#### Manager Changes

- Replica CRD: `TcpPort` and `RdmaPort` fields in status
- Engine CRD: transport type in `ReplicaStatusMap`
- Node controller: auto-label nodes with RDMA hardware
- Instance manager: sync pod `hostNetwork` with transport label
- Pod controller: honor per-node `spdk-memory-size` override

### Risks and Mitigations

1. **RDMA hardware compatibility**: Different RDMA hardware may have driver-level quirks. Mitigation: tested with Mellanox ConnectX-5/6/7; `mlx5_dv` provider explicitly used.

2. **Mixed-transport complexity**: A volume with replicas on both RDMA and TCP nodes requires the engine to manage two transport types simultaneously. Mitigation: per-replica transport selection based on the replica's reported addresses.

3. **Failover between transports**: If an RDMA connection fails, the engine does not automatically fall back to TCP for that replica. Mitigation: the engine reconnects using the same transport; if the RDMA path is permanently down, the replica is marked ERR and rebuilt.

### Test Plan

- Unit tests: transport-aware replica attach, dual-listener creation, transport selection logic
- Integration tests: mixed TCP+RDMA cluster, RDMA-only cluster, TCP-only cluster
- Failover tests: RDMA connection failure, node reboot with RDMA, IM restart

### Upgrade Strategy

- Existing TCP-only clusters are unaffected — no RDMA listeners are created unless the node label is set
- Upgrading the IM image adds RDMA capability but does not change behavior until node labels are applied
- No data migration needed — transport is a connection-layer property, not a data format