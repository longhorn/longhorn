# Per-Node Settings via Node Groups

## Summary

A setting definition can already be `DataEngineSpecific`: the setting then holds one value per data engine, and readers ask for the value of a given engine. This enhancement adds `NodeSpecific` in the same way: the setting can hold one value per node group, and readers ask for the value on a given node. A Kubernetes Node declares its group with the label `node.longhorn.io/setting-group=<name>`; a node-specific setting may carry one override per group in a new `nodeGroupOverrides` field on the `Setting` CR, next to the global `value`.

### Related Issues

- https://github.com/longhorn/longhorn/issues/8332
- https://github.com/longhorn/longhorn/issues/13844
- https://github.com/longhorn/longhorn/issues/13202

## Motivation

[longhorn#8332](https://github.com/longhorn/longhorn/issues/8332) asks for one setting that bounds the resources of all system-managed components. [longhorn#13844](https://github.com/longhorn/longhorn/issues/13844) asks for per-node values of the v2 sizing settings and instance manager pod resources, proposed as new `Node.Spec` fields.

The current approach, adding such fields to the `Node` CR, has drawbacks: the same value can be set in a setting and in the `Node` CR with different precedence, every new per-node value is a `Node` CRD change, and every node is edited individually although nodes fall into a few groups.

### Goals

- One mechanism for per-node values of any setting, keyed by node group, without further `Node` CRD changes.
- One resource setting for all system-managed components that run on a node.
- One JSON setting for all SPDK startup options (iobuf small and large pool sizes, bdev options, and so on), instead of one setting per option as was done for `data-engine-iobuf-small-pool-size` and `data-engine-iobuf-large-pool-size`.

## Proposal

### User Stories

**Heterogeneous nodes.** Before: storage-dense and compute nodes get the same cores, hugepages and iobuf pools; the only per-node knob is `Node.Spec.instanceManagerCPURequest`, patched node by node. After: label nodes `storage` or `compute` and set one override per group on each setting.

**Bounded system pods.** Before: no CPU or memory request or limit can be set on instance manager, share manager or backing image pods, apart from the instance manager CPU request. After: one setting, with group overrides where nodes differ.

### User Experience In Detail

#### Per-node values via node groups

Label the nodes; a node belongs to at most one group:

```bash
kubectl label node storage-01 node.longhorn.io/setting-group=storage
```

Set one override per group on a node-specific setting. `value` stays the global value:

```yaml
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: guaranteed-instance-manager-cpu
value: '{"v1":"12","v2":"12"}'
nodeGroupOverrides:
  compute: '{"v2":"5"}'
  storage: '{"v1":"20","v2":"20"}'
```

Engine-specific settings merge per engine, so the effective values are:

| Node | v1 | v2 |
| --- | --- | --- |
| no label | 12 | 12 |
| `compute` | 12 (from `value`) | 5 |
| `storage` | 20 | 20 |

A node without a label, or a group without an override, uses `value`. Changes to a setting, an override or a node label are applied per node: the instance manager pod is recreated once it runs no instance.

#### Component resources

`system-managed-node-components-resource-requirements` is keyed by component. A group override is applied to the global value as a JSON merge patch ([RFC 7386](https://www.rfc-editor.org/rfc/rfc7386)): objects merge recursively, so a group may change one field of one component; `null` removes a key.

```yaml
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: system-managed-node-components-resource-requirements
value: |
  {
    "instance-manager-v1": {"requests": {"cpu": "1500m", "memory": "512Mi"}},
    "instance-manager-v2": {"requests": {"cpu": "2", "memory": "2Gi"},
                            "limits":   {"cpu": "2", "memory": "4Gi"}},
    "share-manager":       {"requests": {"cpu": "50m", "memory": "64Mi"},
                            "limits":   {"memory": "256Mi"}},
    "backing-image-manager":     {"requests": {"cpu": "50m", "memory": "64Mi"}},
    "backing-image-data-source": {"requests": {"cpu": "50m", "memory": "64Mi"}}
  }
nodeGroupOverrides:
  storage: |
    {"instance-manager-v2": {"requests": {"cpu": "6", "memory": "8Gi"},
                             "limits":   {"cpu": "6", "memory": "8Gi"}}}
```

The `instance-manager-<engine>` block, when present, replaces the CPU request derived from `guaranteed-instance-manager-cpu` and `Node.Spec.instanceManagerCPURequest`. The v2 hugepage limit and the dynamic CPU pinning constraints are applied on top. The share manager pod has no node at scheduling time, so its key is read from the global block only. Share manager and backing image pods pick up the value at their next creation.

#### SPDK startup options

`data-engine-spdk-startup-options` holds the SPDK options that can only be set before `spdk_tgt` starts, that is the JSON-RPC methods SPDK accepts only before its subsystems are initialized: [`iobuf_set_options`](https://spdk.io/doc/jsonrpc.html#rpc_iobuf_set_options), [`bdev_set_options`](https://spdk.io/doc/jsonrpc.html#rpc_bdev_set_options), etc. The value is a JSON object keyed by method name, rendered by the instance manager into the `subsystems` config passed to `spdk_tgt --json`. Longhorn checks only that shape; the parameters are passed through to SPDK, and an unknown method or parameter makes `spdk_tgt` exit during startup, so the instance manager pod fails its liveness probe and is restarted until the setting is fixed. Group overrides are applied as a JSON merge patch, like the resource setting.

```yaml
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: data-engine-spdk-startup-options
value: |
  {
    "iobuf_set_options": {"small_pool_count": 8192, "large_pool_count": 1024},
    "bdev_set_options":  {"bdev_io_pool_size": 65536, "bdev_io_cache_size": 256}
  }
nodeGroupOverrides:
  storage: |
    {"iobuf_set_options": {"small_pool_count": 32768, "large_pool_count": 4096}}
```

### API changes

```go
type Setting struct {
    Value string `json:"value"`
    // NodeGroupOverrides maps a node group to this setting's value on nodes of that group.
    NodeGroupOverrides map[string]string `json:"nodeGroupOverrides,omitempty"`
}
```

A new field on the setting definition, parallel to `DataEngineSpecific`:

```go
type SettingDefinition struct {
    // ...
    DataEngineSpecific bool `json:"dataEngineSpecific"`
    // NodeSpecific allows per-node-group overrides in Setting.NodeGroupOverrides.
    NodeSpecific bool `json:"nodeSpecific,omitempty"`
}
```

Overrides are rejected on settings that are not node-specific. A JSON override is applied to the global value as a JSON merge patch (RFC 7386); for an engine-specific setting the global value and the override are first expanded to their per-engine map, so a partial map changes only the engines it names. A plain override replaces the global value.

`Node.Spec.instanceManagerCPURequest` is marked deprecated; nothing is removed.

## Design

### Implementation Overview

- `types`: `GetSettingValueForNodeGroup` applies one override to the global value as a JSON merge patch (`gopkg.in/evanphx/json-patch.v4`, already vendored through apimachinery) before the existing engine parser. SPDK startup options are checked to be a JSON object of method name to parameter object and rendered into the `subsystems` config, one entry per method in sorted order, the subsystem named after the method prefix.
- `datastore`: `GetSetting{ValueExisted,AsInt,AsFloat,AsBool}ByDataEngineForNode` read the node's group label and resolve; the global accessors call them with an empty node name.
- `webhook`: the setting mutator normalizes overrides like `value`; the validator rejects overrides on non-node-specific settings, group names that are not valid label values, and merged values the setting's validator rejects.
- `controller`: the instance manager controller builds the node-resolved pod contract (resource block, else legacy node field, else `guaranteed-instance-manager-cpu`, plus v2 constraints), compares it and the rendered SPDK config with the pod, and recreates the pod when idle. Share manager and backing image controllers read their block through the same accessor. The setting controller reports pending nodes instead of the cluster-wide engines-stopped check.
- `longhorn-instance-manager`: the manager passes the rendered `subsystems` JSON in `SPDK_STARTUP_CONFIG`; the wrapper writes it to a file for `spdk_tgt --json`, and keeps the current iobuf-only config when the variable is absent.

### Test plan

Unit tests for the merge rules, override validation, resource and SPDK option parsing, and the instance manager pod contract.

New e2e tests cover the functionality introduced here: node group overrides, the component resource setting and the SPDK startup options, each verified against the running pods.

### Upgrade strategy

Upgrading needs no action. The `Setting` CRD gains the optional `nodeGroupOverrides` field; existing settings have no overrides, so every node keeps the global value and no instance manager pod is recreated by the upgrade itself. The two new settings default to empty.

To note after the upgrade:

- `Node.Spec.instanceManagerCPURequest` is deprecated and will be removed in favor of `system-managed-node-components-resource-requirements`.
- `data-engine-iobuf-small-pool-size` and `data-engine-iobuf-large-pool-size` are deprecated and will be removed in favor of `data-engine-spdk-startup-options`; until then their values feed `iobuf_set_options` unless the new setting sets them. An old instance manager image keeps the iobuf-only config, so manager and instance manager can be upgraded in either order.
- Downgrade is not supported. A downgraded CRD drops `nodeGroupOverrides` on the next write and every node falls back to the global value.
