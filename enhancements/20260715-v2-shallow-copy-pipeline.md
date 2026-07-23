# V2 Engine - Shallow Copy Pipeline Depth

## Summary

This proposal adds a configurable **pipeline depth** for SPDK shallow copy (and range shallow copy) used during V2 replica rebuilds. Depth `1` preserves today's sequential cluster-walker behavior. Depth `N > 1` keeps up to N cluster copies in flight, improving rebuild throughput on fast backends (including NVMe-oF/RDMA) without changing the rebuild control-plane protocol.

### Related Issues

- TBD

## Motivation

### Goals

- Make shallow-copy rebuild I/O depth configurable.
- Default to `1` so behavior and memory use match current Longhorn/SPDK.
- Expose the knob safely to operators (setting and/or env on the V2 IM) with clear memory-cost guidance.
- Keep the wire format backward compatible: depth <= 1 omits the new RPC field so unpatched SPDK continues to work.

### Non-goals

- Changing *what* is copied (allocated clusters / range lists) — only *how concurrently* clusters are copied.
- Delta-bitmap based incremental rebuild redesign (separate discussion; not required for this knob).
- Guaranteeing a specific GB/s number across all hardware; results depend on fabric, disk, and cluster size.

## Proposal

### User Stories

#### Story 1

As an operator on a high-bandwidth fabric, I want rebuilds to use multiple in-flight shallow-copy operations so rebuild time is limited by storage/network capacity rather than a queue depth of one.

#### Story 2

As an operator on a memory-constrained node, I want the default depth of 1 so enabling the feature in a release does not increase SPDK memory use until I opt in.

### User Experience In Detail

1. Leave the default (`1`) for unchanged behavior after upgrade.
2. Raise depth on clusters that have validated headroom, e.g. via a data-engine setting such as:
   ```json
   {"v2": "4"}
   ```
   or an equivalent IM env (`LONGHORN_V2_SHALLOW_COPY_PIPELINE_DEPTH`) during bring-up.
3. Monitor IM/SPDK memory: cost scales roughly with `depth x cluster_size` per in-flight copy path.
4. Lower depth again if memory pressure or instability appears.

### API changes

- **SPDK**: `pipeline_depth` on shallow-copy / range-shallow-copy RPC paths (blob -> lvol -> vbdev); schema/CLI updates; depth <= 1 = legacy sequential path.
- **go-spdk-helper**: optional `pipeline_depth` parameter on shallow-copy helpers (omit on wire when <= 1).
- **longhorn-spdk-engine**: read configured depth; pass through on full and range shallow-copy call sites used by rebuild.
- **Setting** (charts/manager): `data-engine-shallow-copy-pipeline-depth` (v2), default `1`.

## Design

### Implementation Overview

SPDK's shallow copy today walks clusters with effective QD1. The pipelined implementation maintains an N-slot pipeline of cluster allocate/copy completions. Longhorn threads the depth from a setting/env into the existing rebuild shallow-copy calls without changing snapshot selection or rebuild state machines.

### Test plan

- SPDK unit/functional: depth 1 matches prior results; depth > 1 completes correctly under load; abort/teardown mid-pipeline is safe.
- Engine unit: depth omitted when <= 1; depth forwarded when > 1.
- Integration: rebuild correctness (checksum / filesystem) at depth 1 and depth > 1; memory observation under concurrent rebuilds.

### Upgrade strategy

- Default depth 1 -> no behavioral change.
- Requires SPDK build that understands `pipeline_depth` before raising the setting above 1.
- Safe to roll IM first with depth left at 1.

## Note

Measured rebuild throughput improvements are environment-specific. Treat higher depths as a tuned operational knob after validation, not as a universal default.
