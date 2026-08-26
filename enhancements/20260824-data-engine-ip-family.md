# Dual-Stack Data Engine IP Family

## Summary

This proposal covers the data-engine family rollout in issue 13050 and depends
on the generic Backing Image IPv6 and dual-stack capability in issue 13864:

- Issue 13864 adds family-optional BI operations, wildcard listeners, and one
  automatic resolver. With no explicit family, the resolver selects the first
  usable global-unicast address from `lhnet1` in interface/CNI order, or the
  validated primary `POD_IP` when `lhnet1` is absent. A present but unusable
  or unreadable `lhnet1` is an error, not a fallback condition. Receive, Send,
  `PrepareDownload`, and BIDS export use this behavior consistently.
- Issue 13050 adds the explicit `preferred-data-engine-ip-family` setting,
  applied-family orchestration, safe BIM restart, and the active-BIDS gate.
  Its `default` mapping uses the 13864 automatic BI behavior; it does not
  reintroduce a special raw-`POD_IP` sync path.

The setting is a rollout policy and desired value for data-engine traffic. It
is not a process-wide family owned by an Instance Manager or by an SPDK
server. The generic BI capability is independently usable without the setting
or a manager family argument.

A dual-stack Pod can have both IPv4 and IPv6 addresses, while Kubernetes and
the CNI still designate one address as primary. Without an explicit
data-engine family choice, data-engine components retain their legacy
selection behavior. BI operations instead use the 13864 automatic resolver,
which provides deterministic storage-first selection without requiring a
preferred-family setting.
The proposal also defines Kubernetes Service IP-family behavior for Longhorn's
chart Services. The optional `service.ipFamilyPolicy` value accepts the exact
Kubernetes policies `SingleStack`, `PreferDualStack`, and `RequireDualStack`,
plus an empty value. Empty omits `spec.ipFamilyPolicy`, preserving the
Kubernetes default of `SingleStack`. Dynamic selector and headless Share
Manager Services always use `PreferDualStack`, with Kubernetes single-stack
fallback. Service IP-family policy is independent from the backend
`preferred-data-engine-ip-family` setting and from
`endpoint-network-for-rwx-volume`.

The static chart policy applies to `longhorn-backend`, `longhorn-frontend`,
the conditional OpenShift `longhorn-ui`, the admission webhook, and the
recovery backend Services. Existing Share Manager Services are reconciled
in place, preserving their Service UID and existing primary ClusterIP when
present. The generic `DataStore.CreateService` path remains policy-agnostic
for SystemRollout restore behavior.

The only family-bearing V2 create contracts are Engine, EngineFrontend, and
Replica. Each create request carries its own family. Backup has no independent
family request and inherits the current in-memory family of its owning Replica.
The manager-facing `InstanceManager.status.ipFamily` and
`InstanceProcessStatus.ipFamily` values are nil (uninitialized) or
`default`/`ipv4`/`ipv6`; they never publish an empty value. The Instance
Manager and SPDK server do not own a global family.

The data-engine setting supports three values:

| Value | User-visible behavior |
| --- | --- |
| `default` | Preserve pre-change data-engine address selection. BI operations use the 13864 automatic resolver. |
| `ipv4` | Require IPv4 for V1 and supported V2 data-engine endpoints, listeners, and callbacks, and for manager-directed BI traffic. |
| `ipv6` | Require IPv6 for V1 and supported V2 data-engine endpoints, listeners, and callbacks, and for manager-directed BI traffic. |

The 13864 BI API also permits an explicit family independently of the setting.
An explicit family is strict. If a configured storage network cannot provide
the requested family, Longhorn does not silently use the opposite family or
move backend traffic to the cluster network. The affected component remains
unsynchronized or unavailable until the network or setting is corrected.

### Related Issues

- https://github.com/longhorn/longhorn/issues/13050
- https://github.com/longhorn/longhorn/issues/13864

## Motivation

Longhorn supports the Kubernetes cluster network and an optional Multus
storage network. Both can be dual-stack, but before these enhancements
Longhorn generally used the Pod primary address or an IPv4-oriented
storage-network fallback. That behavior has several limitations:

- A cluster cannot explicitly move all Longhorn data traffic to IPv6 while
  retaining IPv4 as the Kubernetes primary family.
- An IPv6-primary cluster cannot explicitly keep Longhorn data traffic on IPv4.
- Nodes with different kubelet address preferences can publish mixed endpoints.
- V1 engine and replica processes need an explicit listener family while
  retaining the existing `PortArgs` transport.
- V2 Engine, EngineFrontend, and Replica instances need a family at creation
  time for listener, expose, and callback address selection.
- A family must remain recoverable without inventing durable SPDK metadata or
  changing the persisted EngineFrontend record format.
- BI operations need one generic IPv4/IPv6 capability that does not depend on
  a manager setting. A storage-first automatic resolver must be shared by
  Receive, Send, `PrepareDownload`, BIDS export, and status publication.
- BI listeners must remain wildcard/family-neutral so one Pod can serve
  automatic IPv4 or IPv6 address selection.
- A configured storage network can hide a family mismatch until a component
  attempts to connect.
- Kubernetes Service IP-family behavior is implicit unless the Service policy
  is declared, which makes dual-stack intent difficult to audit.
- Static Longhorn Services need one chart contract that works on standard
  Kubernetes and on the conditional OpenShift UI Service.
- Share Manager selector and headless Services are created dynamically, so
  their dual-stack behavior cannot be supplied by a static chart template.

Issue 13864 therefore supplies the reusable BI capability first. Issue 13050
uses it for `default` BI behavior and adds deterministic explicit-family
rollout for data-engine and manager-directed BI traffic. Kubernetes Service
policy is handled separately: it controls Service IP-family behavior, not the
addresses selected for backend listeners or workload-facing exports.

## Goals

- Add the generic BI IPv4/IPv6 capability from issue 13864 before the
  data-engine rollout. It requires no preferred-family setting or manager
  family argument.
- Use wildcard BI listeners and one automatic resolver: if `lhnet1` exists,
  return its first usable global-unicast address in interface/CNI order; if
  `lhnet1` is absent, return a validated primary `POD_IP`.
- Use the automatic resolver consistently for BI Receive, Send,
  `PrepareDownload`, BIDS export, and BI status address publication.
- Permit a generic BI API caller to request `ipv4` or `ipv6` explicitly;
  explicit family selection remains strict and never falls back.
- Add one global `preferred-data-engine-ip-family` setting for issue 13050
  with exactly three allowed string values: `default`, `ipv4`, and `ipv6`.
- Preserve pre-change behavior for data-engine traffic when the setting is
  `default`; map that value to automatic BI behavior.
- Require the effective `defaultSettings.preferredDataEngineIPFamily` chart value to be
  a non-null string; explicit `null` or a missing chart default is invalid, and the
  chart default is `default`.
- Select a family independently at V2 Engine, EngineFrontend, and Replica
  creation time.
- Return the effective family in those V2 responses and in the generic
  Instance Manager instance status.
- Keep `InstanceManager.status.ipFamily` as the only durable applied-family
  state. Distinguish nil (uninitialized) from a pointer to `default` (applied
  legacy selection). `InstanceProcessStatus.ipFamily` is a string with the
  `default`/`ipv4`/`ipv6` vocabulary.
- Apply an explicit family only after the all-volumes-detached gate, API
  capability checks, and per-component safety checks pass.
- Use durable applied-family consensus for manager BI/BIDS Pod manifests; never
  render or launch them from the pending Setting value.
- Restart BIM only through its existing safe restart path. Preflight
  transitions and block on a mismatched active BIDS; do not assume that every
  BIDS restart is safe.
- Recover stopped Replicas without guessing a family, then defer assignment
  until the next `default` (serialized as empty) or explicit-family Replica
  create request.
- Derive a recovered EngineFrontend family from its persisted target address,
  without adding a persisted family field.
- Keep configured storage networks authoritative for explicit backend traffic.
- Fail closed when a requested family is unavailable.
- Keep IPv6 host-port values syntactically valid.
- Preserve V1 `PortArgs` behavior and transport.
- Keep BI CR, UUID, file-map, and on-disk file reuse behavior unchanged.
- Keep the workload-facing RWX export network separate from backend family.
- Add optional `service.ipFamilyPolicy` with exactly four accepted string
  values: empty, `SingleStack`, `PreferDualStack`, and `RequireDualStack`.
- Omit `spec.ipFamilyPolicy` from static chart Services when the value is
  empty, retaining Kubernetes' `SingleStack` default.
- Apply the static policy to the five chart Service templates, including the
  conditional OpenShift `longhorn-ui` Service.
- Make dynamic selector and headless Share Manager Services use
  `PreferDualStack` and retain safe single-stack fallback.
- Reconcile existing Share Manager Services in place, preserving Service UID
  and the existing primary ClusterIP when present.
- Keep generic `DataStore.CreateService` policy-agnostic so SystemRollout
  restore behavior is not changed globally.

## Non-goals

- Configuring Kubernetes, kubelet, CNI, Multus,
  NetworkAttachmentDefinition, routing, or firewall rules.
- Changing the cluster's primary `cluster-cidr` or `service-cidr` family.
- Giving different V2 instances an implicit process-wide family.
- Adding a family field to the Setting CR or durable per-instance family
  metadata.
- Adding a Replica xattr or changing Replica Head metadata and Head-replacement
  paths to persist family.
- Adding an EngineFrontend family field to its persisted record.
- Selecting the workload-facing RWX NFS export family.
- Changing `endpoint-network-for-rwx-volume` semantics.
- Adding Shard or ShardGroup manager lifecycle support. Those control-plane
  paths are absent from the current manager contract.
- Adding a user-facing V2 BackingImage lifecycle. That path is unsupported by
  current manager validation. Internal SPDK BackingImage objects are not
  family-bearing create contracts and retain unspecified/default behavior.
- Automatically falling back from an explicit family to the opposite family.
- Mutating a live listener to change its family.
- Using `service.ipFamilyPolicy` to select backend listener, callback, Pod, or
  workload-facing NFS endpoint addresses.
- Applying the chart policy to arbitrary user Services or globally forcing a
  policy through every generic `DataStore.CreateService` caller.

## Terminology and Network Boundaries

### Cluster network

The Kubernetes Pod network used by Longhorn control-plane and data-plane Pods
when no storage network is configured.

### Storage network

The optional Multus network configured by `storage-network`. Longhorn uses it
for in-cluster backend data traffic. When configured, it is authoritative for
explicit family selection. For automatic BI resolution, `lhnet1` is the
storage-first interface when present.

### Primary Pod IP

The address in `pod.status.podIP`. In a dual-stack Pod,
`pod.status.podIPs` contains both families, but the first address is the
primary address selected by Kubernetes and the CNI. The automatic BI resolver
uses this address only when `lhnet1` is absent, and validates it before use.

### Automatic BI resolver

The generic resolver introduced by issue 13864 is independent of the
preferred-family setting and manager arguments. For an omitted BI family, it:

1. Reads `lhnet1` when that interface is present.
2. Returns the first usable global-unicast address in interface/CNI order.
3. Returns an error when `lhnet1` is present but cannot be read or has no
   usable global-unicast address; it does not fall back to `POD_IP`.
4. When `lhnet1` is absent, validates and returns the primary `POD_IP`.

BI Receive, Send, `PrepareDownload`, BIDS export, and BI status address
publication use this same automatic behavior. IPv4 and IPv6 may be selected
according to the observed interface/CNI order. IPv6 link-local addresses are
not usable endpoint candidates.

### Service IP family policy

`service.ipFamilyPolicy` controls the Kubernetes Service `spec.ipFamilyPolicy`
field and therefore the families of Service virtual IPs. Its exact accepted
values are the empty string, `SingleStack`, `PreferDualStack`, and
`RequireDualStack`. An empty Helm value omits the field; Kubernetes then uses
its default `SingleStack` behavior. This policy does not select Pod addresses,
data-engine listener families, or NFS endpoint networks.

### Static chart Services

The five chart-rendered Services covered by `service.ipFamilyPolicy` are
`longhorn-backend`, `longhorn-frontend`, the conditional OpenShift
`longhorn-ui`, the admission webhook, and the recovery backend. The OpenShift
Service is covered when its conditional chart template is rendered.

### Share Manager Service

A Share Manager exposes dynamic selector and headless Services for RWX
volumes. These Services always use `PreferDualStack`, regardless of the
static chart value. On a single-stack cluster, the selector Service safely
falls back to one VIP family and the headless Service remains compatible with
the available endpoint family. Existing Share Manager Services are updated
in place, preserving their UID and existing primary ClusterIP when present.

### Service IP-family behavior

For non-headless Services, `ipFamilyPolicy` controls the family or families of
the Service virtual IPs. Headless Services have no virtual IP, but the policy
still declares their single-stack or dual-stack Service behavior. Both are
control-plane networking concerns independent from the backend family selected
by `preferred-data-engine-ip-family` and from the workload-facing network
selected by `endpoint-network-for-rwx-volume`.

### Explicit family

An `ipv4` or `ipv6` value in the generic BI API, the
`preferred-data-engine-ip-family` setting, or a V2 create request. An explicit
family requires a matching usable address and never falls back to another
family.

### Default family

For data-engine requests, the user-facing `default` value maps to an empty V2
or V1 transport field, which maps to `commonnet.IPFamilyUnspecified` and
preserves legacy data-engine address behavior. For BI operations, `default`
maps to an omitted family and therefore to the issue 13864 automatic resolver.
It does not mean raw `POD_IP` or a special sync advertisement. Empty is a
transport/internal value, not a Setting or manager status value.

### Applied family

The value currently safe for new requests on a particular enabled Instance
Manager. The manager API field `InstanceManager.Status.IPFamily` is the only
durable applied-family state. It is a pointer: nil means uninitialized, a
pointer to `default` means applied legacy selection, and a pointer to `ipv4`
or `ipv6` means that explicit family is applied. The manager never publishes
an empty status value.

### Chart input contract

`defaultSettings.preferredDataEngineIPFamily` is a required non-null string in the
effective chart values. The only accepted values are `default`, `ipv4`, and
`ipv6`; the default is `default`. Users may omit an override and receive that
chart default. Explicitly setting `null`, or removing the chart default so the
effective value is nil, is invalid.
### Service policy chart contract

`service.ipFamilyPolicy` is an optional non-null string. The exact accepted
values are the empty string, `SingleStack`, `PreferDualStack`, and
`RequireDualStack`; the default is empty. An empty value omits
`spec.ipFamilyPolicy` and leaves Kubernetes' default `SingleStack` policy in
effect. Any other value, including `null`, is rejected during chart
validation.

### RWX endpoint network

The workload-facing NFS network selected by
`endpoint-network-for-rwx-volume`. This is independent from the backend
data-engine family.

## Proposal

### Setting and Chart Contract

`preferred-data-engine-ip-family` is a generic Danger Zone setting:

- Type: `String`
- Default: `default`
- Category: `Danger Zone`
- Choices: `default`, `ipv4`, and `ipv6`
- Data-engine-specific: `false`

The setting is issue 13050's manager desired rollout value for V1, V2, BIM,
and BIDS traffic. It is not required by the generic BI capability in issue
13864 and is not persisted as a family field on an individual Engine,
EngineFrontend, Replica, or Backup. The manager registers and validates the
setting with the `default` default. For data-engine requests it serializes
`default` as an empty family field. For BI requests, it maps `default` to the
13864 omitted-family automatic resolver.

The Helm value remains:

```yaml
defaultSettings:
  preferredDataEngineIPFamily: default
```

The chart always renders `preferred-data-engine-ip-family: default` in the
default-setting ConfigMap, including when users provide no override.
Manager-side missing-setting autofill for an existing cluster is separate from
chart validation and does not make an explicit `null` Helm value valid.

The chart also exposes the optional Service policy:

```yaml
service:
  ipFamilyPolicy: PreferDualStack
```

The policy is rendered only on the five static chart Services described below.
Dynamic Share Manager Services use their manager-owned policy instead.

### Kubernetes Service Policy Design

`service.ipFamilyPolicy` is a Helm-only Service contract. When non-empty, the
chart writes the exact value to `spec.ipFamilyPolicy`; when empty, the chart
omits the field so Kubernetes applies its normal `SingleStack` default. The
policy is applied to these static chart Services:

- `longhorn-backend`;
- `longhorn-frontend`;
- the conditional OpenShift `longhorn-ui` Service;
- the admission webhook Service; and
- the recovery backend Service.

The OpenShift UI entry is conditional because that Service is rendered only
by the OpenShift-specific chart path. The value does not change Service
selectors, Pod address selection, backend listener families, or the
workload-facing NFS network.

Share Manager selector and headless Services are dynamic and are not governed
by the static Helm value. The manager always reconciles them with
`spec.ipFamilyPolicy: PreferDualStack`. `PreferDualStack` uses both families
when the cluster supports them and safely falls back to one family on a
single-stack cluster. If a Share Manager Service already exists, reconciliation
updates it in place rather than deleting and recreating it; the Service UID
and existing primary ClusterIP, when present, are preserved.

The generic `DataStore.CreateService` helper remains agnostic to Service
family policy. The Share Manager reconciliation path sets its own policy
explicitly, while generic creation must remain unchanged for SystemRollout
and system backup restore workflows.

`RequireDualStack` is strict and must not be selected for a cluster or cloud
load balancer that cannot allocate both families. `PreferDualStack` is the
safe choice when a single-stack fallback is required. Service policy controls
Service IP-family behavior and, for non-headless Services, VIP allocation. It
does not couple Service behavior to `preferred-data-engine-ip-family` or
`endpoint-network-for-rwx-volume`.


### User Experience

#### Fresh installation

Users normally retain legacy data-engine behavior. BI operations use the
automatic capability from issue 13864 and do not require the setting:

```yaml
defaultSettings:
  preferredDataEngineIPFamily: default
```

Users who require IPv4 set:

```yaml
defaultSettings:
  preferredDataEngineIPFamily: ipv4
```

Users who require IPv6 set:

```yaml
defaultSettings:
  preferredDataEngineIPFamily: ipv6
```

Users may choose the static Service VIP policy during Helm installation or
upgrade:

```yaml
service:
  ipFamilyPolicy: PreferDualStack
```

The default is an empty string:

```yaml
service:
  ipFamilyPolicy: ""
```

With the empty value, static Service manifests omit `spec.ipFamilyPolicy` and
Kubernetes keeps its default `SingleStack` behavior. `SingleStack`,
`PreferDualStack`, and `RequireDualStack` are the only non-empty options.
`PreferDualStack` is suitable for clusters that may be either single-stack or
dual-stack. `RequireDualStack` is strict: installation or upgrade can fail,
or a Service can remain unavailable, when the cluster has no dual-stack
Service CIDR or when a LoadBalancer provider cannot provision both families.

The static Helm policy does not configure dynamic Share Manager Services.
Those selector and headless Services always use `PreferDualStack`, including
for existing RWX volumes, and reconcile in place while preserving the Service
UID and existing primary ClusterIP when present. Their policy is also
independent from the backend `preferred-data-engine-ip-family` setting and from
`endpoint-network-for-rwx-volume`.

#### Runtime change

Users must detach all volumes before changing the 13050 setting. While any
volume is attached, the setting remains unapplied, the applied family in
Instance Manager status is unchanged, and managed Instance Manager Pods are
not replaced. Recovery of an already attaching or attached volume continues
to use the old applied family. The generic 13864 omitted-family BI behavior
does not require this setting or this gate.

Before changing any applied family, the manager preflights the complete
transition:

1. It verifies every enabled Instance Manager has the required API capability
   and family-neutral control-plane reachability.
2. It verifies there are no Engine or EngineFrontend instances, every Replica
   is stopped and physically unexposed, and no rebuild or restore is active.
3. It checks manager-owned BIM and BIDS manifests against durable applied
   family consensus, never the pending Setting value. A mismatched active BIDS
   blocks the transition and is not deleted as a restart workaround.
4. It converges capable Instance Manager applied statuses without replacing
   their Pods or changing their UIDs.
5. It restarts BIM only through its existing safe restart path. It does not
   assume that a BIDS restart is safe; an inactive BIDS is handled through its
   normal lifecycle rather than blanket deletion and recreation.
6. It reuses existing backing-image CRs, UUIDs, file maps, and disk files; no
   backing-image copy migration is performed.
7. It marks the setting applied only after all enabled Instance Managers agree,
   their synchronization is true, and all required BI state has converged.
8. It supplies the applied family to new V1 `PortArgs` and each new V2 create
   request. For BI operations, `default` selects the 13864 automatic resolver
   and `ipv4`/`ipv6` are explicit strict requests. The pending desired value
   is never used for a request or Pod manifest.

If an Instance Manager status differs while the setting is marked applied,
the manager first persists `status.applied=false` and requeues before changing
that Instance Manager status. This prevents a partially applied transition
from being reported as complete.

### Applied-Family Initialization and Convergence

`InstanceManager.status.ipFamily` is manager-owned applied state. It is not
initialized from the raw desired Setting value. A nil status is initialized
only from enabled, initialized peer statuses:

- If all initialized peers agree, the manager copies their value.
- If no peer is initialized, the manager chooses applied `default`, which is
  represented by a pointer to the string `default`.
- If initialized peers disagree, the manager leaves the status nil and marks
  synchronization false until the disagreement is resolved.

For a capable V2 Instance Manager, an explicit family change updates status
and request behavior without Pod replacement. A V1 Instance Manager can have
its status updated for any API because V1 carries the family through
`PortArgs`. An old V2 Instance Manager can be used only when the applied and desired
user-facing value is `default`; the manager serializes that value as an empty
transport field. It cannot claim explicit-family support merely by being
restarted; an explicit desired value remains unapplied until a capable
Instance Manager is available.

The manager requires all of the following before advancing a V2 Instance
Manager's applied family:

- the advertised API capability for per-instance family requests;
- family-neutral gRPC reachability for the control services;
- no Engine or EngineFrontend instance;
- every Replica stopped and unexposed, including physical verification during
  recovery;
- no rebuild or restore operation; and
- no active Backup operation.

The manager updates capable V2 status and endpoint data without deleting the
Pod. It updates manager-owned BI/BIDS manifests from durable applied-family
consensus, never pending desired state. BIM may be restarted only through its
existing safe path; no blanket BIDS restart is implied. It reports the Setting
as applied only when every enabled Instance Manager status pointer equals the
desired value, synchronization is true, BIM has safely converged, and no
active BIDS mismatch remains. Endpoint selection remains strict and stale
endpoints are cleared on failure.

### Family-Free Instance Manager Process

The Instance Manager control listener is family-neutral. A V2 Instance
Manager started with `--listen :8500` derives `:<service-port>` for its
Instance, Proxy, Disk, Process, and SPDK services. The command line has no
IP-family option, and the SPDK server has no process-wide family. This allows
the same capable Pod and its control listeners to serve requests for the
`default`, IPv4, and IPv6 selections over the supported control network. The
`default` selection is transported as an empty family field.

The manager maps its applied `default`, `ipv4`, or `ipv6` value into V2
request fields for Engine, EngineFrontend, and Replica. It serializes `default`
as an empty transport field. The Instance Manager maps generic instance
specification and status fields to and from the transport API. Empty remains
`IPFamilyUnspecified` on the wire for compatibility with old managers and old
V2 Instance Managers; an empty response is deserialized by the manager as
`default`.

### V2 Request-Level Family Contracts

The only family-bearing V2 create contracts are:

- `EngineCreateRequest.ip_family`, with the effective family returned as
  `Engine.ip_family`.
- `EngineFrontendCreateRequest.ip_family`, with the effective family returned
  as `EngineFrontend.ip_family`.
- `ReplicaCreateRequest.ip_family`, with the effective family returned as
  `Replica.ip_family`.

An empty request field maps to `IPFamilyUnspecified`; `ipv4` and `ipv6` map
explicitly; any other value returns `InvalidArgument` before object creation.
Each request family is parsed and assigned independently. The server never
reads a process-wide family. The manager serializes user-facing `default` to
that empty request field and deserializes an empty response field to
user-facing `default`. Direct SPDK transport consumers may therefore observe
empty fields, while manager API responses use only `default`, `ipv4`, or
`ipv6`.

Backup has no independent family field. Its expose and launch operations use
the current in-memory family of its owning Replica and log that effective
value. The manager-facing value is `default` when that in-memory family is
unspecified; the raw SPDK value may remain empty. Shard, ShardGroup, and
internal BackingImage have no family request or response field and use
`IPFamilyUnspecified` and legacy/default address selection. They are not added
to the user-facing manager lifecycle.

#### Engine

Engines are volatile. Every create supplies the parsed family to the new
Engine, and recovery or recreation receives the current applied family from
the manager. No Engine family is persisted as independent metadata. A family
mismatch is therefore handled by creating the replacement with the current
request rather than mutating a live listener.

#### Replica

A fresh Replica receives its family immediately before exposure. Replica
family is held in memory only; SPDK does not write or read a Replica xattr for
it, and no Replica Head metadata or Head-replacement path changes.

When a Replica create finds an existing object, the Replica lock is held while
state and family are checked before changing `SpecSize`, `LvsName`, or
`LvsUUID`:

- Running with a different family returns `FailedPrecondition` and leaves all
  existing specification fields unchanged.
- Running with the same family returns the unchanged object, preserving
  `AlreadyExists` behavior.
- Pending or Stopped may accept request-field updates and family assignment.
- Any other state is left unchanged for the create path to reject.

Replica creation repeats the state and family precondition before assignment,
stores the family only for Pending or Stopped state, and then prepares IPs and
ports. Rebuilt Replicas start with no known family. During Pending `Replica.Sync`,
after logical-volume reconstruction, the server queries the physical NVMf
subsystem map. If the Replica NQN exists, it stops exposing the bdev and
verifies that the subsystem is absent before changing cached state to Stopped
and unexposed. A stop or query failure sets Replica Error and must not publish
Stopped or unexposed, and must not publish an empty recovered SPDK family.
Only after physical absence is verified may SPDK Get or List report Stopped,
unexposed, and an empty recovered SPDK family. The manager translates that
empty response to `default` in `InstanceProcessStatus`; the next Replica create
assigns the requested family before exposure.

This deliberately defers family assignment for recovered stopped Replicas.
After another restart, the same physical unexposure check is required; a
subsequent create may then select either family without xattr migration.

#### EngineFrontend

A fresh EngineFrontend receives its family in its in-memory constructor and
uses it for local address selection. The family is not added to
`EngineFrontendRecord` or any persisted JSON. During recovery, the server
derives the in-memory family from the persisted `TargetIP` or `EngineIP`
using IP parsing before selecting callback addresses. If the persisted
address is IPv4, the derived family is IPv4; if IPv6, it is IPv6; if empty,
the recovered SPDK family is unspecified; malformed data is an error. Callback
address selection uses this recovered in-memory family, while manager status
reports `default` for the empty recovered family.

### V1 Data Engine

Manager does not add a new V1 engine CLI family flag. It uses the existing
`PortArgs` transport between manager and Instance Manager.

| Family | Manager `PortArgs` prefix | Completed child argument |
| --- | --- | --- |
| `default` (transport empty) | `--listen,:` | `--listen :<allocated-port>` |
| IPv4 | `--listen,0.0.0.0:` | `--listen 0.0.0.0:<allocated-port>` |
| IPv6 | `--listen,[::]:` | `--listen [::]:<allocated-port>` |

Instance Manager already appends the allocated port, splits the
comma-delimited prefix, and forwards the result to the V1 process. Longhorn
Engine accepts these listen values. The same mapping applies to engine and
replica creation, Instance Manager API versions below 4 through Process
Manager, API version 4 and later through Instance Service, and engine upgrade
or replacement. V1 behavior remains independent of the V2 request fields.

### Instance Manager Transport and Capability

The transport adds generic instance fields so Instance Manager can pass the
request-level family and report applied state:

- `imrpc.InstanceSpec.ip_family = 14`;
- `imrpc.InstanceStatus.ip_family = 18`.

The SPDK transport adds only the six Engine, EngineFrontend, and Replica
request-response fields:

- `spdkrpc.ReplicaCreateRequest.ip_family = 7` and `spdkrpc.Replica.ip_family = 20`;
- `spdkrpc.EngineCreateRequest.ip_family = 15` and `spdkrpc.Engine.ip_family = 24`;
- `spdkrpc.EngineFrontendCreateRequest.ip_family = 10` and
  `spdkrpc.EngineFrontend.ip_family = 20`.

Existing protobuf tags remain unchanged. No Shard, ShardGroup, BackingImage,
Backup, or Setting CR family field is added. Backup inherits its Replica
family rather than receiving an independent create field.

The Instance Manager API capability is bumped from 7 to 8. If that version is
occupied when implementation starts, the next unused version is selected
consistently in all components and in this proposal. A new manager uses an old V2 Instance Manager only for `default` requests,
which it serializes as empty family fields. Explicit-family requests are
rejected or left unapplied until the capability is present.

### Backing Image Manager and Data Source

Issue 13864 provides the generic BI capability independently of
`preferred-data-engine-ip-family`. BIM and BIDS use wildcard listeners and
accept an optional family. When the family is omitted, they use the common
automatic resolver: `lhnet1` is preferred when present, and the first usable
global-unicast address is returned in interface/CNI order. If `lhnet1` is
present but unreadable or has no usable candidate, resolution errors. Only
when `lhnet1` is absent does the resolver validate and use primary `POD_IP`.

The same automatic or explicit strict family behavior is used consistently for
BIM Receive, BIM Send, `PrepareDownload`, BIDS export-from-volume, and
manager-published BI status addresses. The generic API can request `ipv4` or
`ipv6` explicitly, but an unavailable requested family is an error and never
falls back to the opposite family.

Issue 13050 supplies manager-directed family arguments only from durable
applied-family consensus. Its `default` value means omitted family and maps
to the 13864 automatic resolver. The pending Setting value is never used to
construct a BI/BIDS Pod manifest or operation request. BIM family changes use
the existing safe restart path. Before an applied-family transition, a
mismatched active BIDS blocks the transition; the manager does not delete it
or assume that a BIDS restart is safe.

BI CRs are not replaced; BI UUIDs, file maps, and on-disk files are reused.
Inactive BIDS objects follow their normal lifecycle. No backing-image copy
migration is performed.

### Effective-Family Launch and Recovery Logging

Every Engine, EngineFrontend, Replica, and Backup launch, expose, and recovery
log includes structured `ipFamily`. Manager-facing logs use `default`,
`ipv4`, or `ipv6`; raw SPDK transport/internal logs may use `""` for
`IPFamilyUnspecified`. Logs report the effective in-memory or request-derived
family, never a pending desired Setting value. BIM and BIDS retain their existing operation and status logging.

### Status Address Selection and Resolver

Manager-provided selectors for explicit data-engine families remain strict.
A missing family returns `ErrorInvalidState`; BIM/BIDS status IP fields are
cleared and persisted before returning a selector error so stale
opposite-family endpoints cannot remain published.

Existing `GetIPForPod` and `commonnet.IPFamilyUnspecified` behavior remains
unchanged for legacy data-engine `default` requests. Issue 13864 adds a
separate common automatic BI resolver rather than changing that compatibility
path. For an omitted BI family, the automatic resolver:

1. Reads `lhnet1` when it exists.
2. Returns the first usable global-unicast address in interface/CNI order.
3. Returns an error if `lhnet1` is unreadable or present but has no usable
   candidate; it does not fall back to `POD_IP`.
4. If `lhnet1` is absent, validates and returns the primary `POD_IP`.

All BI Receive, Send, `PrepareDownload`, BIDS export, and BI status address
selection uses this same automatic resolver when no family is supplied.
Automatic selection may produce IPv4 or IPv6 according to interface/CNI
ordering. IPv6 selection accepts usable global-unicast addresses, including
ULA addresses, and rejects link-local addresses that would require an
interface zone.

For an explicit BI or data-engine family, selection is strict. The requested
family must be available on the authoritative storage interface when one is
configured, or on the owning Pod interface when storage networking is not
configured. Malformed, opposite-family, or unavailable addresses are errors;
there is no silent fallback to another family. IPv6 host-port values use
bracket-safe formatting.

### Storage Network Interaction

When `storage-network` is empty:

- explicit data-engine family selection uses the matching cluster Pod IP;
- the data-engine `default` setting uses legacy primary Pod behavior; and
- omitted-family BI operations use the 13864 automatic resolver, preferring
  `lhnet1` when present and otherwise validating primary `POD_IP`.

Here the empty value is the storage-network setting, not the preferred family
Setting.

When `storage-network` is configured:

- the configured network is authoritative for explicit data-engine and BI
  family selection;
- the Multus network-status annotation must contain the requested family;
- automatic BI resolution errors if the present `lhnet1` has no usable address;
- manager and runtime resolvers do not use the opposite family; and
- manager does not move backend traffic to the cluster network as a fallback.

For example, with `preferred-data-engine-ip-family=ipv6` and an IPv4-only
storage network, the desired value remains IPv6, no usable backend family is
selected, Instance Manager reports unsynchronized, affected status endpoints
are cleared or withheld, and V1, V2, BIM, and BIDS operations cannot converge
until IPv6 is available or the setting changes. The actual usable family is
none, not IPv4.

### RWX Network Boundary

The setting affects backend Engine and Replica traffic used by an RWX volume,
but it does not select the workload-facing NFS export network. The NFS
endpoint remains owned by the Kubernetes Share Manager Service when
`endpoint-network-for-rwx-volume` is empty, or by the dedicated Multus
endpoint network when that setting is configured. Coupling the NFS frontend to
the backend family would prevent valid configurations such as an IPv6 storage
backend with an IPv4 workload-facing NFS network.

### Kubernetes Service Policies

Static chart Services use the optional Helm `service.ipFamilyPolicy` value.
The accepted values are the empty string, `SingleStack`, `PreferDualStack`,
and `RequireDualStack`. An empty value omits `spec.ipFamilyPolicy` and retains
Kubernetes' default `SingleStack` behavior. A non-empty value is rendered on
`longhorn-backend`, `longhorn-frontend`, the conditional OpenShift
`longhorn-ui` Service, the admission webhook Service, and the recovery backend
Service.

Dynamic Share Manager selector and headless Services do not inherit the Helm
value. The manager always reconciles them with
`spec.ipFamilyPolicy: PreferDualStack`, including existing Services.
Reconciliation updates each Service in place, preserves its UID and existing
primary ClusterIP when present, and permits Kubernetes to fall back to the
available family on a single-stack cluster. The generic
`DataStore.CreateService` path remains policy-agnostic.

## Compatibility and Upgrade Strategy

### Default compatibility

Issue 13864 is independently usable: BI callers that omit a family need no
preferred setting or manager family argument. They use wildcard listeners and
the automatic storage-first resolver, with validated primary `POD_IP` only
when `lhnet1` is absent. A present but unusable `lhnet1` remains an error.

For issue 13050, the chart and manager defaults are both `default`. A fresh
chart installation always emits
`preferred-data-engine-ip-family: default` in the default-setting ConfigMap,
including when users omit an override. Existing data-engine behavior is
preserved without an automatic explicit-family rollout. For BI operations,
13050 `default` maps to the 13864 omitted-family automatic behavior, not a
raw-`POD_IP` sync exception. An existing cluster may receive manager-side
autofill when its setting is missing, but that is separate from chart
validation and does not make an explicit `null` Helm value valid.

### Service policy compatibility

The empty `service.ipFamilyPolicy` default preserves the historical chart
behavior: static Service manifests omit the field and Kubernetes uses
`SingleStack`. Existing installations therefore do not receive an implicit
dual-stack VIP change. A Helm upgrade that selects a non-empty policy updates
the static Service specifications subject to the Kubernetes API and platform
capabilities.

The conditional OpenShift `longhorn-ui` Service receives the same selected
policy when its template is rendered. Dynamic Share Manager selector and
headless Services are independent of the chart value and always reconcile to
`PreferDualStack`. Existing objects are updated in place, preserving their
Service UID and existing primary ClusterIP when present rather than being
deleted and recreated. This behavior also preserves RWX Service continuity
across manager reconciliation.

`PreferDualStack` remains usable on a single-stack cluster through Kubernetes
fallback. `RequireDualStack` is not a compatibility-preserving choice for a
single-stack Service CIDR or an external LoadBalancer implementation that
cannot provide both families.

The generic `DataStore.CreateService` path remains policy-agnostic. Only the
Share Manager reconciliation path applies `PreferDualStack`, so SystemRollout
and system backup restore workflows retain their existing generic Service
creation behavior.


### Instance Manager versions

The capable API is version 8. A new manager with an old V2 Instance Manager
may create or recover only `default` V2 instances, serialized as empty
transport fields. It must not pass an explicit family to an API that cannot
carry it, and restarting that old Pod does not add capability. An old manager
talking to a new Instance Manager sends empty family fields and retains legacy
behavior. A new manager serializes its `default` value as those same empty
fields.

Capable V2 Instance Manager Pods use family-neutral listeners and remain
running during a family transition. Their Pod UIDs do not change. V1
Instance Managers continue to receive family-aware `PortArgs` for every API.

### Mixed component versions

- A new manager and old Instance Manager can still use V1 family-aware
  `PortArgs` because Instance Manager forwards them opaquely.
- V2 explicit family support requires the new transport, capable Instance
  Manager, and SPDK engine dependencies.
- Issue 13864 BI automatic behavior requires the common resolver and BI image
  implementation with wildcard listeners.
- Generic BI explicit-family support requires an image that accepts its
  optional family argument.
- Manager-directed BI family arguments are generated only from durable applied
  family consensus, and only when the configured images support them.
- `default` data-engine requests remain the compatibility path serialized as
  empty fields; `default` BI requests omit the family and use automatic
  resolution.

### Rollout order

1. Complete issue 13864: publish the common automatic BI resolver, wildcard
   BI listeners, consistent omitted-family operations, and optional explicit
   BI family API.
2. Verify issue 13864 behavior independently, including `lhnet1` error
   handling and primary `POD_IP` fallback only when `lhnet1` is absent.
3. Add the data-engine request and status transport fields and publish the
   types.
4. Publish SPDK with request-level family assignment and no process-wide
   family.
5. Publish Instance Manager with family-neutral listeners and forwarding.
6. Publish the 13050 manager with applied-family consensus, capability
   gating, BIM safe restart, active-BIDS preflight, and request propagation.
7. Run the CRD and Helm synchronization workflow and publish the chart.


## Failure Modes

| Failure | Behavior |
| --- | --- |
| Invalid setting value | Manager setting validation rejects it; this applies only to issue 13050. The issue 13864 BI API has no required setting. |
| Explicit `null`, missing effective chart default, or unsupported Helm value | Chart rendering rejects the input; no default-setting ConfigMap is rendered. Omitting a user override uses the chart default `default` value. |
| Invalid `service.ipFamilyPolicy` value, including `null` | Helm validation rejects the value and does not render the chart. |
| Empty `service.ipFamilyPolicy` | Static Service manifests omit `spec.ipFamilyPolicy`; Kubernetes uses its `SingleStack` default. |
| `SingleStack`, `PreferDualStack`, or `RequireDualStack` policy | The exact valid policy is rendered on each applicable static chart Service. |
| `RequireDualStack` on a single-stack Service CIDR | Kubernetes rejects creation or update, or the affected Service remains unavailable because both families cannot be assigned. |
| `RequireDualStack` with an incompatible LoadBalancer provider | The Service may remain Pending or lack a usable external address; `PreferDualStack` is the fallback-compatible choice. |
| Existing Share Manager selector or headless Service | The manager reconciles `PreferDualStack` in place, preserving the Service UID and any existing primary ClusterIP. |
| Single-stack cluster with Share Manager `PreferDualStack` | Kubernetes safely falls back to the available single Service family. |
| Generic `DataStore.CreateService` caller | No global Service policy is injected; SystemRollout and system backup restore behavior remains unchanged. |
| Invalid V2 create family | The request returns `InvalidArgument` before object lookup or creation. |
| Explicit family sent to an old V2 Instance Manager | The manager leaves the setting unapplied and does not restart the old Pod as a workaround. |
| Setting changed with attached volumes | The setting remains unapplied; applied Instance Manager status and Pod UIDs are unchanged. |
| Detached start during partial convergence | The start remains blocked until all enabled Instance Managers and manager-directed BI state converge. |
| Explicit family missing from Pod IPs | Endpoint selection returns `ErrorInvalidState`; stale status is cleared. |
| Explicit family missing from storage network | The component fails closed; no cluster-network or opposite-family fallback occurs. |
| BI family omitted | Issue 13864 uses the automatic resolver consistently for Receive, Send, `PrepareDownload`, BIDS export, and BI status addresses. |
| `lhnet1` present but unreadable | Automatic BI resolution fails and does not fall back to primary `POD_IP`. |
| `lhnet1` present without a usable global-unicast address | Automatic BI resolution fails and does not fall back to primary `POD_IP`. |
| `lhnet1` absent with invalid primary `POD_IP` | Automatic BI resolution fails closed. |
| Explicit BI family unavailable | The request fails strictly; no opposite-family or cluster-network fallback occurs. |
| Mismatched active BIDS during a preferred-family transition | Preflight blocks the transition; the manager does not delete the active BIDS as a restart workaround. |
| BIM family is stale | BIM is restarted only through its existing safe restart path; existing CR and file data are reused. |
| BIDS family is stale while inactive | The manager does not assume a safe restart or blanket-delete it; normal BIDS lifecycle handling is required. |
| BI status selector fails | Published BI IP and StorageIP are cleared before retry. |
| V1 engine upgrade | The replacement receives the same family-aware `PortArgs`. |
| Running Replica create with a different family | The request returns `FailedPrecondition`; family, `SpecSize`, `LvsName`, and `LvsUUID` remain unchanged. |
| Running Replica create with the same family | The object is unchanged and normal `AlreadyExists` behavior is retained. |
| Pending or Stopped Replica create | The request may update fields and assigns the requested family immediately before exposure. |
| Recovered Replica retains an NVMf subsystem | The server stops exposure and verifies physical absence before publishing Stopped/unexposed and a manager-visible `default` family. |
| Replica stop or subsystem query fails during recovery | The Replica enters Error; Stopped, unexposed, and manager-visible `default` status is not published. |
| Recovered stopped Replica has no family metadata | SPDK Get/List reports an empty recovered family only after physical unexposure; manager status reports `default`, and the next create chooses the family. |
| Persisted EngineFrontend target address is IPv4 or IPv6 | Recovery derives the in-memory family from that address before callback selection. |
| Persisted EngineFrontend address is empty or malformed | An empty persisted address derives an empty recovered SPDK family and manager-visible `default`; malformed data fails recovery rather than inventing a family. |
| Mixed Pod preference with `default` setting | Mixed IPv4/IPv6 data-engine endpoints remain allowed as legacy behavior; BI operations use 13864 automatic resolution. |
| Mixed Pod preference with explicit setting | All usable endpoints converge to the selected family. |

## API Changes

The Helm values API adds optional `service.ipFamilyPolicy`. Its exact accepted
values are `""`, `SingleStack`, `PreferDualStack`, and `RequireDualStack`.
An empty value omits `spec.ipFamilyPolicy`; non-empty values are rendered
verbatim on `longhorn-backend`, `longhorn-frontend`, the conditional
OpenShift `longhorn-ui`, the admission webhook, and the recovery backend
Services. This is a chart and rendered-manifest change, not a CRD or
protobuf field.

Dynamic Share Manager selector and headless Services are manager-owned and
always reconcile with `PreferDualStack`. Existing objects are updated in
place, preserving their Service UID and any existing primary ClusterIP. No
public API is added for changing that dynamic policy, and generic
`DataStore.CreateService` remains policy-agnostic for SystemRollout and system
backup restore paths.

The generic BI API from issue 13864 accepts an optional family for BI
operations. An omitted family selects the automatic resolver and wildcard
listener behavior; `ipv4` and `ipv6` request strict explicit selection.
Receive, Send, `PrepareDownload`, BIDS export, and BI status address
publication use the same resolver semantics. This API has no dependency on
`preferred-data-engine-ip-family` or on a manager family argument.

The generic transport adds `InstanceSpec.ip_family = 14` and
`InstanceStatus.ip_family = 18`. The SPDK transport adds exactly these
request-response pairs:

- `ReplicaCreateRequest.ip_family = 7` and `Replica.ip_family = 20`;
- `EngineCreateRequest.ip_family = 15` and `Engine.ip_family = 24`; and
- `EngineFrontendCreateRequest.ip_family = 10` and
  `EngineFrontend.ip_family = 20`.

Existing protobuf tags remain unchanged. No Shard, ShardGroup, BackingImage,
Backup, or Setting CR family field is added. Backup inherits its owning Replica's
current family.

At the manager API, `InstanceManagerStatus.IPFamily *string`
(`json:"ipFamily,omitempty"`) is placed immediately after `IP` and is the
durable applied state. Nil means uninitialized; a pointer to `default` means
applied legacy selection; and a pointer to `ipv4` or `ipv6` means that explicit
family is applied. `InstanceProcessStatus.IPFamily string`
(`json:"ipFamily,omitempty"`) reports the effective family for a process using
`default`, `ipv4`, or `ipv6`. Manager deserialization translates an empty
transport response to `default`.
Manager client request structures add `IPFamily string` only for Engine,
EngineFrontend, and Replica. Their status responses expose the effective
value. The manager API capability is bumped from 7 to 8, or the next unused
version if 8 is occupied.

## Implementation

### go-common-libs

- Keep existing `GetIPForPod` and `IPFamilyUnspecified` behavior unchanged
  for legacy data-engine default compatibility.
- Add the issue 13864 automatic BI resolver without requiring a preferred
  family setting or manager argument.
- When `lhnet1` exists, read it and return the first usable global-unicast
  address in interface/CNI order. Error on read failure or no usable
  candidate; do not fall back to `POD_IP`.
- When `lhnet1` is absent, validate and return primary `POD_IP`.
- Support strict explicit IPv4 and IPv6 selection without opposite-family
  fallback.
- Reject non-global-unicast IPv6 endpoint candidates and link-local addresses.
- Keep bracket-safe host-port formatting.

### longhorn-spdk-engine

- Remove process-wide family ownership from the SPDK server and constructors.
- Parse empty transport, `ipv4`, and `ipv6` request values strictly before
  creation; empty transport means the `default` selection.
- Pass the parsed family to Engine, EngineFrontend, and Replica create paths.
- Keep family only in the in-memory instance state needed for active
  listeners, exposes, callbacks, and Backup inheritance.
- Rebuild cached Replicas with an empty recovered SPDK family; enforce physical
  NVMf absence before reporting Stopped/unexposed. Manager status reports that
  empty recovered value as `default`.
- Derive recovered EngineFrontend family from persisted target or engine IP.
- Do not read or write Replica xattrs or add an EngineFrontend record field.
- Use `IPFamilyUnspecified`/default behavior for Shard, ShardGroup, and
  internal BackingImage; their empty value is internal only.
- Log effective `ipFamily` for every Engine, EngineFrontend, Replica, and
  Backup launch, expose, and recovery.

### longhorn-instance-manager

- Remove the Instance Manager process family option and any server-family
  constructor argument.
- Keep V2 control listeners family-neutral, including `--listen :8500` service
  derivation.
- Add family only to Engine, EngineFrontend, and Replica client requests.
- Map generic instance spec and status family fields to the transport.
- Forward V1 `PortArgs` unchanged and advertise API capability 8.
- Permit old-manager compatibility only for the user-facing `default` family,
  serialized as an empty transport field.

### backing-image-manager

- Implement the issue 13864 optional BI family API and wildcard listeners.
- Use the common automatic resolver for omitted-family Receive, Send,
  `PrepareDownload`, BIDS export, and status address selection.
- Keep explicit family handling strict and fail when the requested family is
  unavailable.
- Pass manager-directed family as an immutable constructor dependency, not
  mutable global state.
- Preserve BI restart, upgrade, CR, UUID, file-map, and on-disk file reuse
  behavior where the existing lifecycle is safe.
- Do not encode a special raw `POD_IP` sync advertisement for `default`.

### longhorn-manager

- Register and validate the 13050 Danger Zone setting and chart contract.
- Add applied `InstanceManager.status.ipFamily` pointer semantics.
- Initialize status and manager BI/BIDS manifests from durable peer consensus,
  never the pending desired Setting value.
- Enforce all-volumes-detached, capability, reachability, and stopped/unexposed
  gates before explicit-family convergence.
- Keep capable V2 Instance Manager Pods running and preserve their UIDs.
- Generate V1 family-aware `PortArgs` and V2 request-level family fields from
  applied Instance Manager status.
- Map 13050 `default` to empty data-engine transport fields and to omitted
  family for the 13864 automatic BI behavior.
- Keep old V2 explicit-family status unapplied without a restart workaround.
- Select strict cluster and storage-network endpoints and clear stale status
  on failure.
- Restart BIM only through its existing safe restart path.
- Preflight and block a transition on a mismatched active BIDS; do not delete
  active BIDS or assume that every BIDS restart is safe.
- Leave Shard, ShardGroup, and user-facing V2 BackingImage lifecycle absent.
- Reconcile dynamic Share Manager selector and headless Services with
  `spec.ipFamilyPolicy: PreferDualStack`, with Kubernetes single-stack
  fallback.
- Update existing Share Manager Services in place while preserving Service
  UID and any existing primary ClusterIP.
- Keep `DataStore.CreateService` agnostic; do not inject a global policy into
  generic Service creation used by SystemRollout or system backup restore.

### longhorn chart

- Require `defaultSettings.preferredDataEngineIPFamily` to be a non-null string with
  exactly three allowed values: `default`, `ipv4`, and `ipv6`; the default is
  `default`.
- Always render `preferred-data-engine-ip-family` in the default-setting ConfigMap,
  including the `default` value.
- Reject explicit `null`, a missing effective chart default, and unsupported
  values during template rendering.
- Add optional `service.ipFamilyPolicy` with exact values `""`, `SingleStack`,
  `PreferDualStack`, and `RequireDualStack`; the default is `""`.
- Omit `spec.ipFamilyPolicy` from all five static Service templates when the
  value is empty, and render the selected value when non-empty.
- Apply the policy to `longhorn-backend`, `longhorn-frontend`, conditional
  OpenShift `longhorn-ui`, admission webhook, and recovery backend Services.
- Retain the Danger Zone warning and all-volumes-detached requirement.
- Describe capable V2 Instance Manager transitions as in-place status
  convergence, BIM restart only through its safe path, and active-BIDS
  transition blocking rather than blanket BIDS restart.

## Test Plan

Acceptance testing is end to end and follows user-visible installation,
configuration, workload, and recovery workflows. Regular V1 and V2 volumes
are covered. Backing-image-backed volume coverage is V1 only because
user-facing V2 BackingImage support is not available in the current manager.

### Generic BI automatic capability (issue 13864)

1. Run BI Receive, Send, `PrepareDownload`, BIDS export, and BI status
   publication without a family argument and verify every operation uses the
   same automatic resolver.
2. On a dual-stack `lhnet1`, verify the first usable global-unicast address
   in interface/CNI order is selected, whether it is IPv4 or IPv6.
3. Make `lhnet1` present but unreadable and verify automatic BI resolution
   fails without falling back to primary `POD_IP`.
4. Make `lhnet1` present with only malformed, link-local, or otherwise
   unusable addresses and verify automatic BI resolution fails without
   falling back to primary `POD_IP`.
5. Remove `lhnet1`, provide a valid primary `POD_IP`, and verify it is used.
   Provide an invalid or missing primary `POD_IP` and verify resolution fails.
6. Verify BI listeners are wildcard/family-neutral and no preferred setting or
   manager family argument is required.
7. Submit explicit IPv4 and IPv6 BI family requests and verify matching
   addresses are selected strictly; an unavailable requested family fails
   without opposite-family fallback.

### Transport and capability

1. Verify generated transport APIs expose exactly the two generic instance
   fields and the six Engine, EngineFrontend, and Replica request-response
   fields with the planned tags.
2. Verify no Shard, ShardGroup, BackingImage, Backup, or Setting CR family
   field is generated.
3. Verify API capability 8 is advertised consistently and an old V2 Instance
   Manager accepts only `default` requests serialized as empty family fields.
4. Verify Instance Manager control services derived from `--listen :8500` are
   reachable over representative IPv4 and IPv6 control addresses.
5. Verify the Instance Manager command rejects an unknown family option and
   does not pass a family to SPDK server construction.

### Fresh installation with the default value

1. Install Longhorn without overriding `defaultSettings.preferredDataEngineIPFamily`.
2. Verify the rendered default-setting ConfigMap contains
   `preferred-data-engine-ip-family: default`.
3. Verify the Setting value is `default` and managed Instance Manager Pods use
   family-neutral listeners.
4. Provision three-replica V1 and V2 volumes, write distinct data, detach,
   reattach, and verify exact readback.
5. Create a deterministic BackingImage, verify BIDS downloads it, verify BIM
   copies become ready on all workers, and create a V1 BI-backed volume that
   exposes the expected embedded data. Verify the BI operations use the 13864
   automatic resolver and do not require a preferred setting argument.
6. Verify an explicit Helm `null` value is rejected before installation.
7. Submit default-family Engine, EngineFrontend, and Replica creates (the
   manager serializes their family as empty transport fields) and verify
   manager responses and logs use `ipFamily=default`; raw data-engine
   transport fields are empty.
8. Verify 13050's `default` mapping leaves BI family omitted, so BI operations
   use the 13864 automatic resolver rather than a raw-`POD_IP` exception.

### Kubernetes Service policy

1. Render the standard chart with the default empty
   `service.ipFamilyPolicy` value and verify its four static Service manifests
   omit `spec.ipFamilyPolicy`: `longhorn-backend`, `longhorn-frontend`,
   admission webhook, and recovery backend.
2. Render the standard chart with each of `SingleStack`, `PreferDualStack`,
   and `RequireDualStack` and verify the exact value appears on every
   applicable static Service.
3. Render the OpenShift-specific chart path and verify the conditional
   `longhorn-ui` Service receives the same selected value; verify it is absent
   when that conditional path is not rendered.
4. Render with an unsupported value and with `null` and verify Helm validation
   fails before any manifests are produced.
5. On a single-stack cluster, install with an empty policy and with
   `PreferDualStack`; verify static Services remain usable with one Service
   family and dynamic Share Manager selector and headless Services safely
   fall back to one family.
6. On a dual-stack cluster, install with `PreferDualStack` and verify the
   static and Share Manager Service family behavior. Verify
   `RequireDualStack` succeeds only when both Service families are available.
7. On a single-stack cluster, verify `RequireDualStack` is rejected or the
   affected Service remains unavailable, and verify a dual-stack
   `LoadBalancer` provider is required for an external dual-family address.
8. Create existing RWX Share Manager selector and headless Services with known
   UIDs, plus a known primary ClusterIP for the selector Service. Run
   reconciliation and verify the policy becomes `PreferDualStack` without
   deleting either object; verify the UIDs and selector primary ClusterIP remain
   unchanged.
9. Perform RWX read/write I/O from multiple workload Pods before and after
   Share Manager reconciliation on both single-stack and dual-stack clusters.
   Verify existing exports remain reachable and shared data remains exact.
10. Repeat RWX I/O with explicit backend `preferred-data-engine-ip-family`
    values and with each `endpoint-network-for-rwx-volume` mode to verify
    Service IP-family policy does not select or override either independent
    network.
11. Exercise SystemRollout and system backup restore and verify generic
    `DataStore.CreateService` creation remains policy-agnostic.

### Request-level V2 family lifecycle

1. Submit explicit IPv6 Engine, EngineFrontend, and Replica creates and verify
   IPv6 listeners, callbacks, responses, and structured logs without changing
   the Instance Manager Pod UID.
2. Submit an invalid family such as `ipv3` and verify `InvalidArgument` before
   object publication.
3. Submit a conflicting family to an active Replica and verify
   `FailedPrecondition` with unchanged family, `SpecSize`, `LvsName`, and
   `LvsUUID`.
4. Submit the same family to an active Replica and verify unchanged object and
   normal `AlreadyExists` behavior.
5. Submit a family to Pending and Stopped Replicas and verify assignment
   immediately before exposure.
6. Verify Backup exposes and logs exactly its owning Replica's in-memory
   family and has no independent family request.
7. Verify Shard, ShardGroup, and internal BackingImage use
   `IPFamilyUnspecified`/default address selection and have no family API.

### Replica restart and recovery

1. Seed an existing Replica logical volume and NVMf subsystem, run cache
   reconstruction, and verify the actual subsystem is stopped and absent
   before SPDK Get/List reports Stopped and unexposed with an empty recovered
SPDK family; manager status reports `default`.
2. Inject subsystem stop or query failure and verify Replica Error rather than
   Stopped or unexposed status.
3. Create the recovered Replica with IPv6 and verify IPv6 listener, response,
   and effective-family log.
4. Restart again, verify physical unexposure, then create with IPv4 and verify
   IPv4 without xattr migration or changed Head metadata.
5. Verify no Replica xattr is written or read and no persisted family is
   invented for a rebuilt Replica.

### EngineFrontend recovery

1. Verify fresh EngineFrontend responses expose the request family while its
   persisted record contains no family field.
2. Restart and verify the in-memory family is derived from persisted target or
   engine IP before callback address selection.
3. Verify IPv4, IPv6, empty, and malformed persisted addresses take the
   specified derivation or error path; empty is an address/internal value and
   manager status is `default`.
4. Verify Engine recreation receives the request family and does not depend on
   a process-wide SPDK family.

### Applied-family gate and rollout

1. Start with attached V1 and V2 volumes on IPv4, request IPv6, and verify
   `Setting.Status.Applied=false`, unchanged Instance Manager status family,
   unchanged Pod UIDs, and recovery requests still use IPv4.
2. Detach all volumes and verify detached-volume starts stay blocked during
   partial Instance Manager convergence.
3. Verify capable Instance Manager statuses converge to IPv6 without Pod
   replacement, BIM restarts only through its existing safe path, and no
   active BIDS with a mismatched family is deleted as a workaround. Verify
   existing BI files, UUIDs, and file maps are reused.
4. Verify Setting becomes applied only after every enabled Instance Manager
   and BIM converge and no active BIDS mismatch remains.
5. Reattach existing volumes and verify exact data, then provision fresh V1 and
   V2 volumes and verify I/O.
6. Repeat for IPv4 on an IPv6-primary dual-stack cluster.
7. Verify a status mismatch while Setting is applied first clears applied state
   and requeues before status mutation.
8. Verify nil status initializes from agreeing peers, `default` when no peer is
   initialized, and remains nil when peers disagree; verify it never copies a
   pending desired Setting value.

### Backing-image behavior

1. Create a mismatched active BIDS during a preferred-family transition and
   verify preflight blocks the transition without deleting or restarting the
   BIDS. Create a stale BIM and verify it is restarted only through the
   existing safe path after the detachment gate.
2. Verify manager-owned BI/BIDS Pod manifests use durable applied-family
   consensus and never the pending Setting value.
3. Verify existing BI UUIDs, CRs, file maps, and disk files are reused without
   copy migration.
4. Verify fresh BackingImage operations with no family argument use the
   automatic resolver for Receive, Send, `PrepareDownload`, BIDS export, and
   status addresses.
5. Verify explicit IPv4 and IPv6 BackingImage operations use strict matching
   family selection and fail when unavailable.
6. Verify V1 BI-backed volume data remains unchanged.

### Storage-network mismatch

1. Configure an IPv4-only storage network and issue an explicit IPv6
   manager-directed request.
2. Verify Instance Manager, BIM, and BIDS status endpoints are withheld or
   cleared, synchronization does not report success, and no component falls
   back to IPv4 or the cluster network.
3. Repeat with an IPv6-only storage network and an explicit IPv4 request.
4. Configure a dual-stack storage network and verify explicit IPv4 and IPv6
   each select the requested storage-network family.
5. With `lhnet1` present but unusable, omit the BI family and verify the
   automatic resolver fails rather than falling back to primary `POD_IP`.
6. With `lhnet1` absent, verify omitted-family BI operations use a validated
   primary `POD_IP`.

### Mixed versions and Pod preference
1. Verify API 7 Instance Manager plus `default` desired value (serialized as
   empty transport fields) remains usable in `default` mode with transport
   `IPFamilyUnspecified`.
2. Verify API 7 plus explicit desired value remains unapplied, creates no
   explicit-family V2 instance, and is not restarted as a workaround.
3. Verify a new manager sends empty fields to a new Instance Manager when the
   user-facing data-engine value is `default`, and deserializes empty
   responses as `default`; verify 13050 omits the BI family in this mode.
4. On a dual-stack cluster with workers using different Pod address ordering,
   verify the `default` setting retains mixed legacy data-engine endpoint
   families while BI operations use 13864 automatic resolution.
5. Verify explicit IPv4 or IPv6 converges every usable data-engine endpoint to
   the selected family without changing Node or cluster primary-family
   ordering.

### RWX regression

1. Provision RWX workloads backed by regular V1 and V2 volumes under explicit
   IPv4 and IPv6 settings.
2. Mount each export from multiple workload Pods and verify shared read/write
   behavior.
3. Verify the workload-facing NFS endpoint remains controlled by the
   Kubernetes Service or `endpoint-network-for-rwx-volume`, independent from
   the backend data-engine family.

## Risks and Limitations

- Issue 13864 BI behavior depends on the common resolver observing the actual
  CNI/interface ordering. A dual-stack `lhnet1` can therefore select either
  IPv4 or IPv6, but all omitted-family BI operations use that same choice.
- If `lhnet1` is present but unreadable or has no usable global-unicast
  address, automatic BI operations fail rather than falling back to primary
  `POD_IP`. If `lhnet1` is absent, an invalid primary `POD_IP` also fails.
- Wildcard BI listeners avoid binding one family, but they do not make an
  unavailable address reachable.
- The cluster, CNI, and configured storage network must actually assign the
  requested family to every relevant Pod or interface.
- A 13050 preferred-family transition can be delayed by the active-BIDS gate;
  this is intentional protection for workloads that cannot be safely
  restarted.
- The static Service policy controls VIP family allocation, not endpoint
  reachability. A Service can have the requested VIP families while a CNI,
  kube-proxy, or workload network still prevents traffic.
- `PreferDualStack` is fallback-compatible but does not guarantee two VIPs on
  a cluster whose Service CIDR or allocator is single-stack.
- `RequireDualStack` can make a static Service fail admission or become
  unavailable on a single-stack cluster. A LoadBalancer implementation that
  supports only one family can leave an external Service address Pending or
  unusable.
- Changing the static policy during a Helm upgrade can cause Kubernetes or a
  cloud provider to alter VIP or external LoadBalancer allocation; operators
  should validate provider support before selecting `RequireDualStack`.
- Share Manager reconciliation preserves an existing Service UID and existing
  primary ClusterIP when present by updating in place, but Kubernetes remains
  authoritative for whether the requested policy can be applied.
- Keeping `DataStore.CreateService` policy-agnostic avoids changing system
  restore behavior, but generic Services created through that path do not
  inherit the Share Manager `PreferDualStack` policy.
- `InstanceManager.status.ipFamily` records applied state, not proof that an
  individual endpoint is currently reachable. Per-component synchronization
  and strict status selection remain necessary.
- A storage-network mismatch leaves components unavailable by design.
- An old V2 Instance Manager cannot gain explicit-family capability through a
  restart; deployment of a capable API is required.
- A recovered Replica has no durable family identity. It must be physically
  unexposed before SPDK Get/List can report stopped with an empty recovered
  family; manager status reports `default`, and the next create must assign the
  family again.
- A persisted EngineFrontend address that is malformed cannot provide a safe
  family and causes recovery failure rather than an opposite-family fallback.
- BIM images that do not understand their optional family argument require
  rollout ordering that prevents a manager from passing it. BIDS restart
  safety is not assumed; an active mismatched BIDS blocks a transition rather
  than being deleted.
- Shard, ShardGroup, and user-facing V2 BackingImage paths remain outside this
  proposal because the current manager does not provide those lifecycles.
- User-facing V2 BI-backed volumes remain unsupported independently from this
  enhancement.
