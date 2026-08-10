# Dual-Stack Data Engine IP Family

## Summary

This proposal introduces the `data-engine-ip-family` setting so that users can choose which address family Longhorn uses for data-engine and backing-image traffic in a dual-stack Kubernetes cluster.

A dual-stack Pod can have both IPv4 and IPv6 addresses, but Kubernetes and the CNI still designate one address as primary. Without an explicit Longhorn setting, data-plane components inherit that local ordering. Different kubelet preferences can therefore cause some Longhorn Pods to publish IPv4 endpoints while others publish IPv6 endpoints. This is valid legacy behavior, but it does not provide the uniform family selection required by clusters that are migrating traffic to IPv6 or intentionally keeping storage traffic on IPv4.

The setting supports three values:

| Value | User-visible behavior |
| --- | --- |
| `""` (empty string) | Preserve pre-change address selection. Each component uses its legacy primary/default address behavior. In a mixed Pod-preference topology, Longhorn endpoints can be a mixture of IPv4 and IPv6. |
| `ipv4` | Require IPv4 for V1 and V2 data-engine endpoints, listeners, and backing-image management traffic. |
| `ipv6` | Require IPv6 for V1 and V2 data-engine endpoints, listeners, and backing-image management traffic. |

An explicit family is strict. If a configured storage network cannot provide the requested family, Longhorn does not silently use the opposite family or move traffic to the cluster network. The affected component remains unsynchronized or unavailable until the network or setting is corrected.

### Related Issues

- https://github.com/longhorn/longhorn/issues/13050

## Motivation

Longhorn supports Kubernetes cluster networking and an optional Multus storage network. Both can be dual-stack, but before this enhancement Longhorn generally used the Pod's primary address or an IPv4-oriented storage-network fallback. That behavior has several limitations:

- A cluster cannot explicitly move all Longhorn data traffic to IPv6 while retaining IPv4 as the Kubernetes primary family.
- An IPv6-primary cluster cannot explicitly keep Longhorn data traffic on IPv4.
- Nodes with different kubelet address preferences can publish a mixture of endpoint families.
- V1 engine and replica processes can advertise one family while listening without an explicit family contract.
- V2 SPDK objects need one immutable family for listener and callback address selection.
- Backing Image Manager and Backing Image Data Source Pods previously advertised their primary Pod address independently from the data-engine family.
- A configured storage network can hide a family mismatch until a component attempts to connect.

The enhancement provides one global family choice for Longhorn's backend data plane while preserving the legacy behavior when users configure the setting as the empty string.

## Goals

- Add one global `data-engine-ip-family` setting with exactly three allowed string values: `""`, `ipv4`, and `ipv6`.
- Preserve pre-change behavior when the setting is the empty string.
- Require the effective `defaultSettings.dataEngineIPFamily` chart value to be a non-null string; explicit `null` or a missing chart default is invalid.
- Select one consistent family for explicit V1 and V2 engine and replica traffic.
- Apply the same setting to Backing Image Manager and Backing Image Data Source transfer endpoints.
- Keep configured storage networks authoritative for backend traffic.
- Fail closed when the requested family is unavailable.
- Keep IPv6 host-port values syntactically valid.
- Roll out family changes only while all volumes are detached.
- Preserve existing backing-image files and metadata when backing-image management Pods restart.
- Avoid new protobuf or CRD schema fields.

## Non-goals

- Configuring Kubernetes, kubelet, CNI, Multus, NetworkAttachmentDefinition, routing, or firewall rules.
- Changing the cluster's primary `cluster-cidr` or `service-cidr` family.
- Giving different Longhorn data engines different global families.
- Selecting the workload-facing RWX NFS export family.
- Changing `endpoint-network-for-rwx-volume` semantics.
- Adding user-facing V2 BackingImage support. V2 BackingImage resources and BI-backed V2 volumes remain unsupported by the current manager validation contract.
- Automatically falling back from an explicit family to the opposite family.

## Terminology and Network Boundaries

### Cluster network

The Kubernetes Pod network used by Longhorn control-plane and data-plane Pods when no storage network is configured.

### Storage network

The optional Multus network configured by `storage-network`. Longhorn uses it for in-cluster backend data traffic. When configured, it is authoritative for explicit family selection.

### Primary Pod IP

The address in `pod.status.podIP`. In a dual-stack Pod, `pod.status.podIPs` contains both families, but the first address is the primary address selected by Kubernetes and the CNI.

### Explicit family

A non-empty `data-engine-ip-family` value. An explicit family requires a matching usable address.

### Legacy or unspecified family

An empty `data-engine-ip-family` value. Components preserve their pre-change selection and fallback behavior.

### Chart input contract

`defaultSettings.dataEngineIPFamily` is a required non-null string in the effective chart values. The only accepted values are `""`, `ipv4`, and `ipv6`. Users may omit an override and receive the chart default `""`; explicitly setting `null`, or removing the chart default so the effective value is nil, is invalid.

### RWX endpoint network

The workload-facing NFS network selected by `endpoint-network-for-rwx-volume`. This is independent from the backend data-engine family.

## Proposal

### New Global Setting

`data-engine-ip-family`:

- Type: `String`
- Default: `""`
- Category: `Danger Zone`
- Choices:
  - `""`
  - `ipv4`
  - `ipv6`
- Data-engine-specific: `false`

The setting applies to both V1 and V2 data engines and to BI management components shared by those data engines.

The Helm value is:

```yaml
defaultSettings:
  dataEngineIPFamily: ""
```

The chart always renders `data-engine-ip-family: ""` in the default-setting ConfigMap for the empty-string value, including when users provide no override. Manager registers the setting with the same empty default. Manager-side missing-setting autofill for an existing cluster is separate from chart validation and does not make an explicit `null` Helm value valid.

### User Experience

#### Fresh installation

Users normally set the value to the empty string to retain legacy behavior:

```yaml
defaultSettings:
  dataEngineIPFamily: ""
```

Users who require IPv4 set:

```yaml
defaultSettings:
  dataEngineIPFamily: ipv4
```

Users who require IPv6 set:

```yaml
defaultSettings:
  dataEngineIPFamily: ipv6
```

#### Runtime change

Users must detach all volumes before changing the setting. Longhorn rejects or defers application while any volume is attached because Instance Manager, Backing Image Manager, and Backing Image Data Source Pods may need replacement.

After the setting changes:

1. Instance Manager Pods converge to the desired family argument.
2. Backing Image Manager and active Backing Image Data Source Pods with stale arguments are deleted.
3. Existing controllers recreate the Pods.
4. Existing backing-image CRs, UUIDs, file maps, and disk files are reused; no backing-image copy migration is performed.
5. New V1 processes and V2 SPDK objects publish endpoints from the requested family.

### Value Semantics in a Dual-Stack Cluster

#### Empty

Empty means compatibility, not cluster-wide family enforcement.

- Manager omits `--ip-family` from Instance Manager, BIM, and BIDS Pod commands.
- V1 child processes retain the legacy `--listen :<port>` form.
- V2 uses `IPFamilyUnspecified` and the common resolver's legacy behavior.
- BIM sync advertisement retains its raw primary `POD_IP` behavior.
- Status endpoints use existing primary/CNI selection.

If worker Pods have different primary-family ordering, Longhorn can publish mixed IPv4 and IPv6 endpoints. Users who require uniform endpoints must select an explicit family.

#### IPv4

- Manager adds `--ip-family ipv4` to managed data-plane and BI management Pods.
- V1 engine and replica children listen on `0.0.0.0:<port>`.
- Manager publishes IPv4 engine, replica, BIM, and BIDS addresses.
- V2 SPDK objects use IPv4 listeners, expose addresses, and callbacks.
- BIM and BIDS transfer endpoints use IPv4.

#### IPv6

- Manager adds `--ip-family ipv6` to managed data-plane and BI management Pods.
- V1 engine and replica children listen on `[::]:<port>`.
- Manager publishes IPv6 engine, replica, BIM, and BIDS addresses.
- V2 SPDK objects use IPv6 listeners, expose addresses, and callbacks.
- BIM and BIDS transfer endpoints use bracket-safe IPv6 host-port values.

## Design

### End-to-End Control Flow

```text
Helm value
    |
    v
Default Setting ConfigMap
    |
    v
Setting: data-engine-ip-family
    |
    +--------------------------+---------------------------+
    |                          |                           |
    v                          v                           v
Instance Manager Pods          BIM Pods                    BIDS Pods
--ip-family                    --ip-family                 --ip-family
    |                          |                           |
    |                          +-------------+-------------+
    |                                        |
    v                                        v
named-container authority              typed BIM resolver
    |                                  sync/download/export
    |
    +--------------------------+
    |                          |
    v                          v
V1 PortArgs                   V2 SPDK Server
    |                          IPFamily
    v                          |
V1 engine/replica             v
--listen host:port            V2 objects/listeners/callbacks
```

### Named-Container Authority

Manager reads the family from the expected container, not from an arbitrary sidecar:

- `instance-manager`
- `backing-image-manager`
- `backing-image-data-source`

For BIM and BIDS, manager parses the combined container `command` and `args` because their flags are carried in `command`. For Instance Manager, the family is normally carried in `args`.

The parser distinguishes:

- flag absent;
- one valid split or equals-form flag;
- malformed or missing value;
- duplicate flags;
- unknown value.

Malformed, duplicated, unknown, mismatched, or missing authoritative-container observations do not synchronize.

### V1 Data Engine

Manager does not add a new V1 engine CLI family flag. It uses the existing `PortArgs` transport between manager and Instance Manager.

| Family | Manager PortArgs prefix | Completed child argument |
| --- | --- | --- |
| Empty | `--listen,:` | `--listen :<allocated-port>` |
| IPv4 | `--listen,0.0.0.0:` | `--listen 0.0.0.0:<allocated-port>` |
| IPv6 | `--listen,[::]:` | `--listen [::]:<allocated-port>` |

Instance Manager already appends the allocated port, splits the comma-delimited prefix, and forwards the result to the V1 process. Longhorn Engine already accepts these listen values.

The same mapping applies to:

- engine creation;
- replica creation;
- Instance Manager API versions below 4 through Process Manager;
- API version 4 and later through Instance Service;
- engine upgrade and replacement.

No Instance Manager protobuf or Longhorn Engine production change is required for V1.

### V2 Data Engine

Instance Manager parses `--ip-family` into `commonnet.IPFamily` and passes it to the SPDK server. The server stores one immutable family for its lifetime and passes it to new and recovered objects:

- Engine
- Replica
- Shard
- ShardGroup
- EngineFrontend
- internal SPDK BackingImage
- Backup

Family-aware V2 call sites use `commonnet.GetIPForPodByFamily`. Explicit IPv6 host-port values use `net.JoinHostPort` or an equivalent bracket-safe path.

Changing the family requires Instance Manager Pod replacement. Existing server objects are not mutated in place.

### Backing Image Manager and Data Source

BIM and BIDS consume the same `data-engine-ip-family` setting. No separate BI setting is introduced.

Both commands accept an optional family:

```text
backing-image-manager daemon --ip-family <family>
backing-image-manager data-source --ip-family <family>
```

The family is immutable for the process lifetime and is passed through canonical constructors to BIM and BIDS services.

Family-aware operations include:

- BIM receive addresses;
- BIM send addresses;
- `PrepareDownload` sync-server addresses;
- BIDS export-from-volume receiver addresses;
- manager-published BIM and BIDS status addresses.

The BIM implementation has one initializer per operation. The family is an explicit dependency, not mutable global state. Tests inject an address resolver through an internal function parameter.

An empty-string setting retains the legacy raw `POD_IP` behavior for the BIM sync advertisement. Explicit families use the typed common resolver and fail when the requested family is unavailable.

### BIM and BIDS Rollout

The setting controller first enforces the all-volumes-detached gate. It then compares the desired setting with each named BIM/BIDS container.

- Matching Pods are untouched.
- Missing, malformed, duplicate, or mismatched arguments cause Pod deletion.
- Already deleting or missing Pods are ignored.
- BIM and BIDS CRs are not replaced.
- BI UUIDs and file maps are not changed.
- Recreated BIM Pods detect and reuse existing disk files.

This uses the existing BIM Pod restart and upgrade path and avoids additional backing-image copy migration.

### Status Address Selection

Manager provides container-aware family selectors for:

- cluster Pod addresses;
- configured storage-network addresses.

For explicit families, selection is strict. A missing family returns `ErrorInvalidState`. BIM/BIDS status IP fields are cleared and persisted before returning a selector error so stale opposite-family endpoints cannot remain published.

Existing Instance Manager compatibility wrappers preserve their prior malformed/absent fallback behavior while new generic container-aware selectors remain strict for BIM/BIDS.

### Common Resolver

The common resolver supports:

- `IPFamilyUnspecified`;
- `IPFamilyIPv4`;
- `IPFamilyIPv6`.

Unspecified mode preserves legacy behavior. Explicit mode:

1. Checks `lhnet1` when present.
2. Requires the requested family on an authoritative storage interface.
3. Checks the Pod's owning interface when the primary Pod IP is the opposite family.
4. Rejects malformed, link-local, opposite-family, or unavailable addresses.
5. Does not silently fall back to the other family.

IPv6 selection accepts usable global-unicast addresses, including ULA addresses, and rejects link-local addresses that would require an interface zone.

### Storage Network Interaction

When `storage-network` is empty:

- explicit family selection uses the matching cluster Pod IP;
- the empty-string setting uses legacy primary Pod behavior.

When `storage-network` is configured:

- the configured network is authoritative;
- the Multus network-status annotation must contain the requested family;
- manager and runtime resolvers do not use the opposite family;
- manager does not move backend data traffic to the cluster network as a fallback.

Example:

```text
data-engine-ip-family = ipv6
storage-network = IPv4-only NAD
```

Result:

- the desired family remains IPv6;
- no usable backend family is selected;
- Instance Manager reports `SettingSynced=False`;
- affected status endpoints are cleared or withheld;
- V1, V2, BIM, and BIDS operations cannot converge until IPv6 becomes available or the setting changes.

The actual usable data-plane family is none, not IPv4.

### RWX Network Boundary

The setting affects the backend engine and replica traffic used by an RWX volume, but it does not select the workload-facing NFS export network.

The NFS endpoint remains owned by:

- the Kubernetes Share Manager Service when `endpoint-network-for-rwx-volume` is empty;
- the dedicated Multus endpoint network when that setting is configured.

Ganesha NFSv4 listens on available Pod interfaces. Coupling the NFS frontend to `data-engine-ip-family` would prevent valid configurations such as an IPv6 storage backend with an IPv4 workload-facing NFS network.

## Compatibility and Upgrade Strategy

### Empty default

The chart and manager defaults are both the empty string. A fresh chart installation always emits `data-engine-ip-family: ""` in the default-setting ConfigMap, including when users omit an override. An existing cluster may receive manager-side autofill when its setting is missing, but that behavior is separate from chart validation and does not make an explicit `null` Helm value valid. Existing clusters retain their pre-change behavior without an automatic family rollout.

### Existing Instance Manager Pods

Earlier development versions generated explicit IPv4 Instance Manager arguments by default. An empty-string setting accepts an existing explicit IPv4 IM Pod as synchronized to avoid an upgrade-only replacement. Newly generated Pods for the empty-string setting omit the flag.

BIM/BIDS did not previously receive an explicit family flag, so empty-string mode synchronizes only with an absent BIM/BIDS flag.

### Mixed component versions

- A new manager and old Instance Manager can still use V1 family-aware `PortArgs` because IM forwards them opaquely.
- V2 explicit family support requires the new Instance Manager and SPDK engine dependencies.
- BIM/BIDS explicit support requires a backing-image-manager image that accepts `--ip-family`.
- Manager must not generate the BIM/BIDS flag until the configured backing-image-manager image supports it.

### Rollout order

1. Publish the family-aware common library.
2. Update and publish SPDK engine with the common library.
3. Update and publish Instance Manager with the common library and SPDK engine.
4. Update and publish Backing Image Manager with the common library.
5. Update Manager with the new component image versions and orchestration.
6. Update the Longhorn chart.

## Failure Modes

| Failure | Behavior |
| --- | --- |
| Invalid setting value | Manager setting validation rejects it. |
| Explicit `null`, missing effective chart default, or unsupported Helm chart value | Chart rendering rejects the input; no default-setting ConfigMap is rendered. Omitting a user override uses the chart default `""`. |
| Invalid direct CLI family | IM or BIM/BIDS startup rejects it before server construction. |
| Setting changed with attached volumes | Setting remains unapplied; managed Pods are not replaced. |
| Explicit family missing from PodIPs | Endpoint selection returns `ErrorInvalidState`; stale status is cleared. |
| Explicit family missing from storage network | Component fails closed; no cluster-network or opposite-family fallback. |
| Malformed or duplicate named-container args | Pod is unsynchronized and replaced when safe. |
| Named container missing | Sidecar flags are ignored; no authority is inferred. |
| IPv6 link-local address encountered | Address is rejected as an unusable endpoint. |
| BIM/BIDS Pod family is stale | Setting controller deletes only the stale Pod; existing CR/file data is reused. |
| BIM/BIDS selector fails | Published IP and StorageIP are cleared before retry. |
| V1 engine upgrade | Replacement receives the same family-aware `PortArgs`. |
| Mixed Pod preference with the empty-string setting | Mixed IPv4/IPv6 endpoints are allowed as legacy behavior. |
| Mixed Pod preference with explicit setting | All usable endpoints converge to the selected family. |

## API Changes

No new Kubernetes CRD or protobuf field is required.

The existing generic Setting CR stores the new string value. Existing Instance Manager request fields carry V1 `PortArgs`. V2 family is an internal typed process value.

Backing Image Manager internal constructors now require `commonnet.IPFamily` explicitly. This is an internal component API change coordinated with the manager image update.

## Implementation

### go-common-libs

- Add typed IP-family parsing and family-aware Pod address resolution.
- Preserve the zero-argument resolver for existing consumers.
- Reject non-global-unicast IPv6 endpoint candidates.
- Preserve legacy unspecified fallback behavior.

### longhorn-spdk-engine

- Store one family on the SPDK server.
- Propagate it to all new and recovered V2 objects.
- Use bracket-safe host-port formatting.

### longhorn-instance-manager

- Add optional `--ip-family` to the daemon.
- Parse it before V2 server startup.
- Pass the typed family to the SPDK server.
- Continue forwarding V1 `PortArgs` opaquely.

### backing-image-manager

- Add optional family flags to daemon and data-source commands.
- Pass family as an immutable constructor dependency.
- Select family-aware transfer and export addresses.
- Preserve raw `POD_IP` sync advertisement for unspecified mode.

### longhorn-manager

- Register and validate the setting.
- Generate and observe Instance Manager, BIM, and BIDS family arguments.
- Select family-aware cluster/storage status endpoints.
- Generate V1 family-aware `PortArgs`.
- Restart stale managed Pods after the detachment gate.
- Reuse existing backing-image files without copy migration.

### longhorn chart

- Require `defaultSettings.dataEngineIPFamily` to be a non-null string with exactly three allowed values: `""`, `ipv4`, and `ipv6`; the default is `""`.
- Always render `data-engine-ip-family` in the default-setting ConfigMap, including the empty string.
- Reject explicit `null`, a missing effective chart default, and other unsupported values during template rendering; omitting a user override uses the empty-string default.

## Test Plan

All acceptance testing is end to end and follows user-visible installation, configuration, workload, and recovery workflows. Regular V1 and V2 volumes are covered. Backing-image-backed volume coverage is V1 only because user-facing V2 BackingImage support is not guaranteed.

### Fresh installation with the empty default

1. Install Longhorn without overriding `defaultSettings.dataEngineIPFamily`.
2. Verify the rendered default-setting ConfigMap contains `data-engine-ip-family: ""`.
3. Verify the Longhorn Setting value is the empty string and all managed Pods omit `--ip-family`.
4. Provision three-replica V1 and V2 volumes, write distinct data, detach, reattach, and verify exact readback.
5. Create a deterministic BackingImage, verify BIDS downloads it, verify BIM copies become ready on all workers, and create a V1 BI-backed volume that exposes the expected embedded data.
6. Verify an explicit Helm `null` value is rejected before installation.

### Select IPv6 on an IPv4-primary dual-stack cluster

1. Start with attached V1 and V2 volumes containing known data.
2. Attempt to set `data-engine-ip-family=ipv6` while volumes are attached and verify Longhorn defers the change without replacing managed Pods.
3. Detach all volumes, apply `ipv6`, and wait until Instance Managers, BIM, and BIDS have converged.
4. Verify V1 engine and replica listeners use `[::]:<port>`, V2 listeners use IPv6, and published endpoints are IPv6.
5. Verify existing BIM Pods restart through the normal upgrade path, retain the same BI UUID and file maps, and reuse existing files without copy migration.
6. Create a fresh BackingImage and verify BIDS download and BIM transfer endpoints use IPv6.
7. Reattach the original V1 and V2 volumes and verify exact data, then provision fresh V1 and V2 volumes and verify I/O.
8. Create a fresh V1 BI-backed volume and verify the embedded data.

### Select IPv4 on an IPv6-primary dual-stack cluster

1. Repeat the attached-volume gate and detachment workflow with `data-engine-ip-family=ipv4`.
2. Verify V1 engine and replica listeners use `0.0.0.0:<port>`, V2 listeners use IPv4, and published endpoints are IPv4 even when IPv6 is the primary Pod family.
3. Verify BIM/BIDS restart, existing-file reuse, fresh BackingImage download, and V1 BI-backed volume data.
4. Reattach original V1 and V2 volumes, verify exact data, and verify fresh V1 and V2 volume I/O.

### Mixed Pod address preference

1. On an IPv4-primary cluster, configure exactly two workers with kubelet `node-ip=::` preference while leaving the third worker IPv4-preferred.
2. Verify Node and cluster CIDR primary-family ordering does not change, while fresh PodIP ordering changes only on the selected workers.
3. With the empty-string setting, verify IM, BIM, and BIDS endpoints follow each Pod's legacy primary family and regular V1/V2 volumes remain healthy.
4. Set explicit IPv6 and verify every data-engine and BI management endpoint converges to IPv6.
5. Repeat on an IPv6-primary cluster with exactly two workers using kubelet `node-ip=0.0.0.0`, then verify explicit IPv4 convergence.
6. If kubelet restarts leave stale manager or CSI Service endpoints, verify safe Pod recreation restores provisioning without patching status or EndpointSlices.

### Storage-network mismatch

1. Configure an IPv4-only storage network and request `data-engine-ip-family=ipv6`.
2. Verify Instance Manager, BIM, and BIDS status endpoints are withheld or cleared, synchronization does not report success, and no component falls back to IPv4 or the cluster network.
3. Repeat with an IPv6-only storage network and an explicit IPv4 request.
4. Configure a dual-stack storage network and verify explicit IPv4 and IPv6 each select the requested storage-network family.

### RWX regression

1. Provision RWX workloads backed by regular V1 and V2 volumes under explicit IPv4 and IPv6 data-engine settings.
2. Mount each export from multiple workload Pods and verify shared read/write behavior.
3. Verify the workload-facing NFS endpoint remains controlled by the Kubernetes Service or `endpoint-network-for-rwx-volume`, independent from `data-engine-ip-family`.

## Risks and Limitations

- The cluster and CNI must actually assign the requested family to every relevant Pod/network.
- Mixed Pod preference can expose stale or asymmetric Kubernetes Service endpoints during kubelet restarts; controllers and endpoint health require operational monitoring.
- Setting `status.applied=true` does not by itself prove every Instance Manager endpoint is usable. Per-component synchronization and status remain important.
- A storage-network mismatch leaves components unavailable by design.
- Old BIM images do not understand `--ip-family`; rollout order must prevent a new manager from passing the flag to an old image.
- User-facing V2 BI-backed volumes remain unsupported independently from this enhancement.
