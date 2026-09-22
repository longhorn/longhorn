# Dual-Stack Data Engine IP Family

## Summary

This enhancement combines issue 13050 (data-engine IP-family rollout) with the
reusable Backing Image work in issue 13864. The implementation has one immutable
owner of data-engine family: the Instance Manager daemon process. The
`--ip-family` argument is selected when that process starts and applies to every
V1 and V2 data-engine object in the process. It is not selected independently by
an Engine, EngineFrontend, Replica, or Backup create request.

The `preferred-data-engine-ip-family` Danger Zone setting controls the desired
startup argument for Instance Manager Pods. Its values are `default`, `ipv4`,
and `ipv6`; `default` preserves the existing unspecified-family behavior. The
setting is applied only while all volumes are detached. A running Instance
Manager is not mutated in place: a pod whose argument differs is marked
unsynchronized and must be recreated through the normal pod lifecycle.

The data-engine network role and workload-facing network role remain separate.
An Engine chooses its backend target address from the selected process family
(`GetIPForPodByNetworkAndFamily`). An EngineFrontend normally exports the
backend Engine target address supplied by the manager; it does not invent a
second host-facing NVMe/TCP address. Its local family-based address fallback is
only for disabled frontends serving internal gRPC commands.
`endpoint-network-for-rwx-volume` continues to select the workload-facing NFS
network.
Issue 13864 provides the generic automatic BI address capability without
depending on the 13050 setting. Omitted-family internal BI transfers use the
common storage-first resolver: a usable `lhnet1` address is selected first,
and a primary Pod IP is used only when `lhnet1` is absent. A present but
unreadable or unusable `lhnet1` is an error. Explicit BI family selection is
independent of the Instance Manager process and is supplied by the BIM/BIDS
process startup family from the configured setting.
`PrepareDownload` is a separate manager HTTP-proxy path: it uses
`GetBackingImageDownloadAddress` and returns the primary `POD_IP`; it must not
use storage-network selection or the preferred data-engine family.

The setting covers data-plane traffic only. Kubernetes control-plane Services
and their Helm chart configuration remain unchanged. Dynamic Share Manager
Services retain their existing data-plane-specific reconciliation behavior.

### Related Issues

- https://github.com/longhorn/longhorn/issues/13050
- https://github.com/longhorn/longhorn/issues/13864

## Motivation

Longhorn may use the Kubernetes Pod network or an optional Multus storage
network, and either may be dual-stack. Before this enhancement, operators could
not consistently select one family for all data-engine processes when Pod
address ordering differed between nodes. A process-owned startup choice gives
all objects in that process the same family-selection policy and listener
constraints without changing the V1 `PortArgs` transport or persisted
Replica/Frontend metadata. With unspecified `default`, observed addresses may
still follow network/interface ordering; only an explicit family is strict.

Backing Image transfers also need deterministic network selection, but their
storage transfer path and manager-facing download proxy have different network
roles. A single rule for both would either send storage traffic over the wrong
network or make manager HTTP downloads unreachable. The implementation keeps
those paths distinct.

## Goals

- Add `default`, `ipv4`, and `ipv6` to the 13050 setting; omit the daemon
  `--ip-family` argument for `default` and pass `ipv4` or `ipv6` explicitly.
- Apply one immutable family to all V1 and V2 instances in each process.
- Keep `default` compatible with existing unspecified-family data-engine
  selection.
- Enforce an all-volumes-detached gate before applying a changed setting.
- Detect a running Pod whose `--ip-family` differs and report it unsynchronized;
  converge by normal Pod recreation, not in-place mutation.
- Keep storage-network selection authoritative for explicit backend traffic and
  fail closed when the requested family is unavailable.
- Preserve persisted Replica and EngineFrontend formats and existing recovery
  ownership rules.
- Keep Engine backend addressing separate from EngineFrontend host-facing
  export addressing and from the RWX endpoint network.
- Provide the 13864 generic BI automatic address capability independently of
  the 13050 setting; explicit selection remains process-owned.
- Use storage-first selection for internal BI transfers and primary Pod IP for
  the `PrepareDownload` manager HTTP-proxy path.
- Keep Kubernetes control-plane Service manifests and Helm values unchanged.
- Preserve existing Share Manager data-plane Service behavior.

## Non-goals

- Per-create or per-instance family fields in V2 APIs, CRDs, or SPDK metadata.
- A process-wide family RPC setter or live listener mutation.
- Adding a new API capability version for IP-family support.
- Adding family metadata to Replica xattrs, Replica Head metadata, or the
  EngineFrontend persisted record.
- Changing `endpoint-network-for-rwx-volume` or selecting the workload NFS
  family from the backend setting.
- Changing BI CR, UUID, file-map, or on-disk file reuse behavior.
- Falling back from an explicit family to the opposite family or to the cluster
  network.
- Adding user-facing V2 BackingImage, Shard, or ShardGroup manager lifecycles.
- Configuring Kubernetes, kubelet, CNI, Multus, routing, or firewall rules.
- Configuring IP families for Kubernetes control-plane Services.

## Terminology and Network Boundaries

### Process IP family

The family parsed from the Instance Manager daemon `--ip-family` argument. The
daemon accepts an empty value, `ipv4`, or `ipv6`; the setting's user-facing
`default` value is serialized as empty. It is immutable for the process and is
inherited by every V1 and V2 data-engine object hosted there.

### Backend data-engine address

The address selected by an Engine for its storage listener and target. With a
configured storage network, selection is authoritative to that network; without
one, the Pod network is used. `GetIPForPodByNetworkAndFamily` performs the
family-constrained selection.

### EngineFrontend host-facing address

The NVMe/TCP frontend exports the backend Engine target address supplied by the
manager (`TargetAddress`/`TargetIP`). It is not a separately selected local
frontend address. If the frontend is disabled and the target is empty, the
server uses its process-family Pod address only for local internal gRPC
commands.

### Storage network

The optional Multus network configured by `storage-network` is authoritative
for explicit backend data-engine and internal BI transfer selection. A present
but unusable `lhnet1` is an error for automatic storage-first BI selection.

### Primary Pod IP

The primary Pod IP is used by the manager-facing `PrepareDownload` proxy
address getter. For internal BI automatic selection it is used only when
`lhnet1` is absent and the primary value validates. For BIM and BIDS,
`Status.IP` is the manager-selected Pod-network control address, while
`Status.StorageIP` is the internal transfer address. Explicit family selection
can make the control address differ from the primary `POD_IP`; the download
helper still returns the primary address.

### Generic BI automatic resolver

The 13864 resolver used by BI Receive, Send, and internal transfer/status paths
when no family is supplied. It selects the first usable address on `lhnet1` in
interface/CNI order. If `lhnet1` is present but unreadable or has no usable
candidate, it returns an error and does not use `POD_IP`. If `lhnet1` is absent,
it validates and returns primary `POD_IP`. Explicit family selection is owned by
the 13050 process setting.

### PrepareDownload address

`PrepareDownload` is manager HTTP-proxy traffic, not a storage transfer address.
`GetBackingImageDownloadAddress` returns the primary `POD_IP` so the manager can
reach the backing-image HTTP endpoint. It does not consult storage-first BI
selection and does not inherit `preferred-data-engine-ip-family`.

### Applied setting

The manager's setting status indicates whether the desired startup family has
been safely applied to managed Instance Manager Pods. It is not per-process
runtime state and is not proof that every endpoint is currently reachable.

### Control-plane Services

Kubernetes control-plane Services and their Helm values are outside this
enhancement and remain unchanged.

## Proposal

### Runtime Setting contract

`Setting/preferred-data-engine-ip-family` is a Danger Zone string setting:

- Default: `default`.
- Choices: `default`, `ipv4`, `ipv6`.
- Invalid values are rejected by runtime Setting validation.
- The setting is changed through the Settings CR/API, not through a Helm value.

### Runtime application and observed-family state

Changing the setting requires all volumes to be detached. Admission rejects
the change while volumes are attached, leaving the setting, Instance Manager
Pod UIDs, startup arguments, and data-engine behavior unchanged.

The manager records the observed Pod argument in
`InstanceManager.status.ipFamily` during Pod status synchronization. The field
is a string: `""` means default address selection, while `ipv4` and `ipv6`
record an explicit family. It is not initialized from the desired Setting or
peer consensus. It describes Pod configuration, not readiness; current state
and usable endpoint addresses remain subject to their existing checks.

The manager compares the observed status family with the desired setting,
treating the empty status string as `default`. The existing `handlePod`
lifecycle recreates mismatched Pods, subject to its existing live-instance
and resource-safety checks. No separate IP-family reconciliation phase or
controller-side setting enum validator is needed. The replacement process
starts with the new argument; a live listener is not mutated in place.

BIM and BIDS reconcile their own Pod arguments against the same setting
through their existing Pod lifecycle. They do not require an Instance Manager
initialization marker or a separate peer-consensus barrier. BIM restart reuses
completed backing-image files and UUIDs.

Existing attached or attaching volumes continue using the family of their
current Instance Manager process. New objects inherit the process family after
that process has converged. A process cannot serve different V1/V2 families by
mixing create requests.

### Family propagation

The daemon parses an empty value, `ipv4`, or `ipv6` once at startup. Empty is
the transport representation of user-facing `default`. It passes the result to
its SPDK server and all hosted Engine, EngineFrontend, Replica, Backup, and
internal BackingImage objects. The SPDK and Instance Manager RPC create
contracts do not gain `ip_family` fields. There is no capability negotiation or
version bump for this feature.

V1 managers retain `PortArgs`. The process startup family constrains the
addresses used by the V1 engine and replica listeners; no new V1 family
transport is required. V2 Engine and Replica listeners, exposes, callbacks,
and Backup operations use the immutable process family.

The EngineFrontend manager supplies the backend Engine target address. On
reconnect, the persisted target address remains the source of the NVMe/TCP
endpoint, and the recovered frontend is constructed with the Instance Manager
process family. An explicitly configured family conflict in persisted target
addresses is logged as a warning; it does not introduce a new recovery
rejection or cleanup lifecycle. No family field is added to the persisted record.

Recovered and fresh Replica/Frontend objects are constructed with the hosting
process family. Replica recovery reconstructs logical state and selects its
bound address when preparing exposure; it has no persisted family/address
field to validate. The server passes its configured family explicitly to
`NewBackup`, including when no Replica exists. Backup does not infer its family
from Replica state. Restore retains the hosting Replica's process family; no
xattr or durable family metadata is invented.

### Address selection and strictness

For explicit `ipv4` or `ipv6` backend selection, a matching usable address must
exist on the authoritative storage network, or on the Pod network when no
storage network is configured. Missing, malformed, or opposite-family addresses
are errors. No opposite-family or cluster-network fallback is permitted.

The `default` data-engine family is unspecified and preserves legacy address
selection. It must not be described as an explicit raw-`POD_IP` path.
Internal BI Receive, Send, and storage transfer operations use the 13864
storage-first resolver when family is omitted. Explicit BI family selection is
independent of the data-engine process and comes from the BIM/BIDS process
startup family. `PrepareDownload` instead calls
`GetBackingImageDownloadAddress` and uses primary `POD_IP` for manager HTTP
proxy reachability; neither storage selection nor the 13050 setting changes
that address.

IPv6 host-port formatting remains bracket-safe. A wildcard listener must not be
characterized as IPv4-only: Go `net.Listen("tcp", ...)` may accept both
families on supported Linux configurations.

### Share Manager data-plane Services

Dynamic Share Manager selector and headless Services continue to use
`PreferDualStack`, with Kubernetes single-stack fallback. Existing objects are
updated in place, preserving their Service UID and existing primary ClusterIP
when present. Generic `DataStore.CreateService` remains policy-agnostic for
SystemRollout and system backup restore behavior.

## Compatibility and Upgrade Strategy

### Default compatibility

The runtime Setting default is `default`, and existing data-engine address selection is
preserved. Existing Pods keep their current startup family until a setting
change passes the detached-volume gate and normal Pod recreation occurs.

Issue 13864 BI operations are independently usable without the 13050 setting.
Their internal omitted-family operations use storage-first resolution, while
`PrepareDownload` uses primary `POD_IP` through its dedicated getter. Explicit
BI family selection follows the BIM/BIDS process startup family, and a present
unusable `lhnet1` is an internal BI resolution error, not a primary-IP fallback.

### Safe rollout

1. Deploy code and images that understand the setting and daemon argument.
2. Keep the setting at `default` while existing volumes remain attached.
3. Detach every volume before selecting `ipv4` or `ipv6`.
4. Wait for each Instance Manager Pod to be recreated with the desired
   `--ip-family` and for synchronization to become healthy.
5. Start or attach workloads only after the applied gate succeeds.
6. Validate BI internal transfers and `PrepareDownload` separately; the latter
   must reach the manager proxy through primary `POD_IP`.

A running old Instance Manager does not gain a new family through an API
request. Mixed-version operation is limited to the behavior supported by the
running daemon and must not be represented as per-instance family capability.

### Share Manager Service compatibility

`PreferDualStack` remains fallback-compatible for dynamic Share Manager
Services on single-stack clusters. This fixed data-plane policy does not alter
static control-plane Services or introduce a Helm value.

## Failure Modes

| Failure | Required behavior |
| --- | --- |
| Invalid setting | Runtime validation rejects it; no invalid setting is applied. |
| Attached volume during setting change | Admission rejects the change; the setting, process args, and Pod UIDs do not change. |
| Running Pod has a different `--ip-family` | Observed status differs from the setting; existing Pod lifecycle handles recreation. |
| Explicit backend family unavailable | Endpoint selection fails closed; no opposite-family or cluster fallback. |
| Present unusable `lhnet1` for internal BI automatic resolution | BI storage selection fails; primary `POD_IP` is not used. |
| Absent `lhnet1` with invalid primary `POD_IP` | Automatic internal BI resolution fails closed. |
| `PrepareDownload` request | `GetBackingImageDownloadAddress` supplies primary `POD_IP`; it is independent of storage selection and the preferred family. |
| Active listener family change requested | Listener is not mutated; process recreation is required. |
| Malformed or explicitly mismatched persisted EngineFrontend address | Warn and retain the existing recovery path; do not add an IP-family rejection. |
| Recovered Replica | Hosting process family remains authoritative; no family xattr or Head metadata is invented. |
| Backup/restore family | Backup receives the hosting server family explicitly; restore uses the hosting Replica's process family. |
| Existing Share Manager Service | Reconcile in place with `PreferDualStack`, preserving UID and primary ClusterIP when present. |

## API Changes

The public configuration/state changes are the
`preferred-data-engine-ip-family` runtime Setting and
`InstanceManager.status.ipFamily`. The Instance
Manager status field is a string with `""` as the default and `ipv4` or `ipv6`
for explicit Pod configuration. There is no pointer-based uninitialized state.
No family field is added to Engine, EngineFrontend, Replica, or Backup objects.

The Instance Manager daemon command accepts an empty `--ip-family` value,
`ipv4`, or `ipv6`; empty is the transport representation of user-facing
`default`. This is process startup configuration, not a request-level API.
Existing Instance Manager and SPDK protobuf create messages remain unchanged:
no per-instance `ip_family` field or IP-family capability version is added.

Manager-facing status reports retain separate `Status.IP` and `Status.StorageIP`
roles; neither is synonymous with raw primary `POD_IP`. The hosting server
passes the Backup family independently of the optional Replica address.
`GetBackingImageDownloadAddress` is the manager-facing download address
contract and returns primary `POD_IP`.

## Implementation

### longhorn/longhorn-instance-manager

- Parse and validate daemon `--ip-family` at startup.
- Initialize the SPDK server and hosted objects with that immutable family.
- Keep control services reachable through their existing listener contract.
- Do not add a family setter, per-instance create field, capability version, or
  in-place family mutation.

### longhorn/longhorn-spdk-engine

- Use process family for Engine backend address selection through
  `GetIPForPodByNetworkAndFamily`.
- Keep EngineFrontend NVMe/TCP export bound to the manager-supplied backend
  `TargetAddress`/`TargetIP`.
- Use local process-family Pod address only for disabled-frontend internal gRPC
  fallback.
- Preserve EngineFrontend persisted target addresses and construct recovered
  frontends with the process family. Warn about explicit family conflicts
  without adding a recovery rejection or deriving family from the record.
- Pass the server family explicitly to Backup; retain Replica process-family
  ownership for restore.
- Do not extend deprecated V2 backing-image behavior.
- Preserve V1 `PortArgs` and existing file, xattr, and Head metadata behavior.

### longhorn/backing-image-manager and longhorn/go-common-libs

- Implement the 13864 automatic BI address capability.
- Use storage-first `lhnet1` resolution for internal Receive, Send, and transfer
  paths; error when a present interface is unreadable or unusable.
- Use primary `POD_IP` only when `lhnet1` is absent for automatic internal BI
  resolution.
- Keep `GetBackingImageDownloadAddress` on the manager HTTP-proxy path using
  primary `POD_IP`, independently of storage selection and the preferred
  data-engine setting.
- Keep wildcard listeners and BIM/BIDS startup-family behavior; do not add a
  per-operation BI family API.

### longhorn/longhorn-manager

- Register and validate the Danger Zone setting and detached-volume gate.
- Render the desired daemon argument in managed Instance Manager Pod specs.
- Refresh observed `InstanceManager.status.ipFamily` from Pod arguments and
  compare that status with the desired setting without reparsing the arguments.
- Use the empty status string for default selection; keep readiness and
  endpoint/storage-network validation separate from observed configuration.
- Reconcile family changes through the existing `handlePod` lifecycle and
  preserve its live-instance and resource-safety checks.
- Let BIM and BIDS reconcile their own startup arguments without an
  Instance Manager initialization or peer-consensus barrier.
- Keep backend, EngineFrontend, BI internal-transfer, and download-proxy
  address roles separate, including `Status.IP` versus `Status.StorageIP`.
- Reconcile Share Manager Services with `PreferDualStack` without changing
  generic `DataStore.CreateService`.

The chart carries only the generated CRD schema for the runtime Setting and
Instance Manager status. It adds no IP-family Helm value and does not change
static control-plane Service templates.

## Test Plan

Tests must verify observable contracts, not merely flags. Run on a disposable
cluster with dual-stack or single-stack networks as appropriate.

### Generic BI capability (issue 13864)

1. With dual-stack `lhnet1`, run Receive and Send without a family and verify
   storage-first selection of the first usable address in interface order.
2. Make `lhnet1` present but unreadable or unusable and verify internal BI
   resolution fails without primary-IP fallback.
3. Remove `lhnet1`, provide valid primary `POD_IP`, and verify automatic
   internal BI operations use it; invalid primary values fail.
4. Run `PrepareDownload` and verify the manager HTTP proxy reaches the BI
   endpoint through raw primary `POD_IP`, independently of storage selection or
   the preferred family.
5. Verify explicit family behavior by using separate BIM/BIDS startup families,
   not independent per-operation BI request fields.

### Process family and lifecycle

1. Start an Instance Manager with empty, `ipv4`, and `ipv6` arguments and create
   V1/V2 Engine, EngineFrontend, Replica, and Backup objects; verify each uses
   the hosting process policy and no create request selects another family.
2. Under `default`, provision three-replica V1 and V2 volumes, write distinct
   data, detach and reattach, and verify exact readback.
3. With attached volumes, attempt to change the setting and verify admission
   rejects it; the setting, Pod UIDs, arguments, and workload family stay unchanged.
4. Detach all volumes, change the setting, and verify mismatched Pods are
   recreated through the normal lifecycle. Verify status reflects the new Pod
   arguments: `""` for default, or the explicit `ipv4`/`ipv6` value.
5. Verify a live listener is never mutated in place and a newly created object
   after recreation uses the new family.
6. Verify explicit storage-network mismatch fails closed without opposite-family
   or cluster-network fallback.
7. After each explicit-family rollout, reattach the existing V1 and V2 volumes
   and verify their pre-transition data exactly. Provision fresh V1, V2, and
   V1 BI-backed volumes, write new data, and verify exact readback.

### Address roles and recovery

1. Verify an Engine backend target uses the process family on the authoritative
   network.
2. Verify a host-facing EngineFrontend exports the manager-supplied backend
   target, not an independently selected local frontend address.
3. Disable the frontend and verify only its internal gRPC fallback uses the
   process-family Pod address.
4. Restart a Replica and verify recovery uses the hosting process family and
   existing physical state without writing family xattrs or Head metadata.
5. Restart an EngineFrontend with a persisted target address from another
   explicitly configured family; verify a warning and the unchanged recovery
   path, rather than a new family-specific rejection.
6. Verify Backup uses the server's configured family with or without a Replica;
   verify restore retains its hosting Replica's process family.

### Observed status and BI rollout

1. Verify `InstanceManager.status.ipFamily` reflects observed Pod arguments,
   using `""` for default. Changing only the desired setting must not copy it
   into status before the Pod arguments change.
2. Verify BIM/BIDS startup arguments follow the configured setting through
   their existing Pod lifecycle, without an Instance Manager initialization
   or peer-consensus barrier.
3. Verify a deterministic BIDS download, BIM copies ready on all workers, and a
   V1 BI-backed volume exposes exact embedded data. Verify BI download proxy
   reachability separately through primary `POD_IP`.
4. Verify existing BI CRs, UUIDs, file maps, and disk files are reused.
5. Verify Share Manager selector/headless Services reconcile in place to
   `PreferDualStack`, preserve UID and primary ClusterIP, and fall back safely
   on single-stack clusters.
6. Verify RWX NFS reachability remains controlled by the Service or
   `endpoint-network-for-rwx-volume`, independently of backend family.
7. Verify static control-plane Services and generic
   `DataStore.CreateService` callers used by SystemRollout and system backup
   restore remain unchanged.
8. On dual-stack workers with opposite primary Pod ordering, verify `default`
   preserves unspecified data-engine selection without forcing one observed
   family; verify explicit `ipv4` and `ipv6` remain strict.

## Risks and Limitations

- A process restart is required to change family; this is intentionally gated by
  volume detachment and can delay rollout.
- Process family consistency does not prove endpoint reachability. Network
  assignment, routing, CNI, and kube-proxy remain environmental requirements.
- EngineFrontend host-facing reachability depends on the manager-supplied
  backend target; it is not repaired by selecting a separate frontend address.
- Internal BI storage resolution fails on a present unusable `lhnet1`, whereas
  `PrepareDownload` intentionally uses primary `POD_IP`; these paths must not be
  conflated.
- `PreferDualStack` does not guarantee two Share Manager Service VIPs on
  single-stack infrastructure; Kubernetes fallback preserves availability.
- User-facing V2 BackingImage, Shard, and ShardGroup manager lifecycles remain
  outside this enhancement.
