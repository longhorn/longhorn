# V2-only installations without host iSCSI

## Summary

Allow an explicitly configured V2-only Longhorn installation to operate without host iSCSI tools or services. Preserve the existing prerequisite checks for installations that can run V1. An installation-wide capability limit must prevent V1 from being enabled or used until an administrator deliberately restores the prerequisites and changes the installation configuration.

This proposal covers manager startup, admission, reconciliation, upgrades, periodic environment checks, and preflight tooling. It does not migrate data or remove host packages.

### Related Issues

https://github.com/longhorn/longhorn/issues/14438

## Motivation

Longhorn 1.13.0 runs `iscsiadm --version` during manager startup and pre-upgrade even when the V1 engine is disabled. Periodic checks also expect iSCSI packages or services. A V2-only administrator therefore cannot safely remove that host dependency. The installation documentation already distinguishes V1 and V2 prerequisites; the implementation needs a consistent engine capability contract.

Reading only the mutable `v1-data-engine` setting is insufficient. Startup checks precede settings initialization, Helm upgrade hooks run before ordinary resources are replaced, and a later setting update could re-enable V1 on nodes without its prerequisites.

### Goals

- Install, upgrade, restart, and monitor V2-only deployments without `iscsiadm` or `iscsid`.
- Keep default and V1-capable prerequisite behavior unchanged.
- Reject V1 enablement and runtime creation in V2-only mode through both admission and controllers.
- Fail closed on contradictory configuration, unreadable state, or incompatible existing storage.
- Keep common and V2-specific prerequisite failures visible.

### Non-goals

- Automatically migrate, delete, detach, or rewrite V1 volumes or snapshots.
- Remove packages or extensions from an operating system.
- Change the V2 data path, performance guarantees, or remaining host requirements.
- Provide a per-node mixed-capability scheduling model in this first change.

## Proposal

Introduce an immutable process configuration, provisionally named `dataEngineMode`, with two values:

| Mode | Capability | Mutable settings |
| --- | --- | --- |
| `v1-capable` (default) | Existing V1 and optional V2 support | Existing engine enablement rules |
| `v2-only` | V2 only | Requires `v1-data-engine=false` and `v2-data-engine=true` |

The mode is installation intent, not a mutable Longhorn Setting. Managers, global managers, pre-upgrade checks, and preflight tooling receive the same intent directly. Unknown values and conflicting intent must be errors rather than warnings followed by a fallback.

### User Stories

#### Story 1: A new V2-only installation

An administrator prepares hosts with all common and V2 requirements, omits iSCSI, and selects V2-only mode with the required engine settings. Startup and ongoing checks validate the requirements that this installation can actually use.

#### Story 2: Retiring iSCSI after migration

An administrator finishes a separately verified V1-to-V2 migration, disables V1, and deploys V2-only mode while iSCSI remains available. After every manager has accepted the mode and V1 storage/runtime checks pass, the administrator can remove iSCSI through the host configuration owner. A later request to enable V1 is rejected.

### User Experience In Detail

The following illustrates proposed chart configuration; it is not supported configuration for an existing release:

```yaml
dataEngineMode: v2-only
defaultSettings:
  v1DataEngine: false
  v2DataEngine: true
persistence:
  dataEngine: v2
```

Chart validation rejects contradictions. Generated StorageClasses and provisioning defaults must select V2 in this mode. Existing StorageClass parameters are not rewritten automatically; administrators prepare and select V2 classes before changing modes. Diagnostics identify the effective mode, bootstrap phase, and any incompatible setting or V1 object. Webhook reachability and validated storage readiness are distinct states. Selecting this mode never makes another failed prerequisite healthy.

Changing back requires restoring and verifying V1 host prerequisites first, deploying `v1-capable` mode while V1 remains disabled, and only then enabling V1. No package installation or data conversion occurs automatically.

### API changes

- Add a manager/global-manager/pre-upgrade process option, provisionally `--data-engine-mode`, and the corresponding chart value.
- Add equivalent explicit mode selection to `longhornctl` preflight. V2-only mode always includes V2 checks; existing SPDK selection alone must not silently remove V1 checks.
- Keep the existing engine Settings, but validate them against the immutable capability limit on create/update and restoration paths.
- No storage CRD format change is proposed. Final option names and diagnostics should be agreed during review.

## Design

### Implementation Overview

1. Parse and validate the mode before any engine-specific host check. In default mode, retain the existing iSCSI check. In V2-only mode, omit only the V1-specific check.
2. Apply the immutable capability limit before admission can accept requests. Keep conversion/admission reachable during bootstrap, including compatible Setting creation, while separately gating storage-facing API operations and storage reconciliation until intended and stored engine settings are consistent. Do not gate the existing admission Service's endpoints on the final settings validation: its current Pod readiness is needed to admit those Settings. Expose the bootstrap/operational phase in diagnostics. An absent Setting during a genuine first installation is distinct from a failed read or an incompatible existing installation.
3. Reuse and extend the existing V1-disable validation to reject incompatible V1 volumes and runtime state. Inventory failures or unresolved state hold the transition. Do not delete objects to make validation pass. A backup catalog alone does not authorize activating V1 storage.
4. Enforce the limit in Setting validation and every volume/engine/instance-manager reconciliation path that could create or activate V1 runtime. Direct CR writes, system restore, and controller retries must not bypass it. Provisioning defaults must be mode-compatible, and generated StorageClasses must emit the selected engine independently of revision-counter options. Preserve the existing meaning of legacy/omitted engine fields on stored objects; never reinterpret V1 storage as V2 to pass validation.
5. Pass chart intent directly to the pre-upgrade Job. The hook must validate existing state without depending on a newly rendered default-settings ConfigMap, which Helm has not applied yet.
6. Make periodic environment checks engine-aware across supported distributions. Keep NFS, encryption, device-mapper, and V2 checks as applicable. On Talos, skip the entire iSCSI namespace-executor phase when V1 is unavailable; merely removing an executable from a check map still tries to locate `iscsid`.
7. Apply the same contract to `longhornctl` package, executable, and service checks. Update installation and upgrade documentation to describe the supported transition and remaining requirements.

The manager, chart, and preflight implementation must share the mode semantics. Customized-setting loading must not silently filter out an invalid value and continue with a capability mismatch.

### Test plan

| Scenario | Required result |
| --- | --- |
| Default/V1-capable mode, missing `iscsiadm` | Existing startup and pre-upgrade failures remain |
| V2-only, no `iscsiadm` or `iscsid`, other requirements satisfied | Startup, upgrade, restart, and repeated environment checks succeed |
| Unknown mode, contradictory settings, failed state read, or remaining incompatible V1 state | Transition fails without changing storage |
| Fresh installation with no Settings yet | Guarded admission is reachable, compatible Settings can be created, then storage operations become ready |
| Bootstrap needs CRD conversion | Conversion/admission remains reachable without enabling storage operations or V1 |
| V1-enable Setting create/update, system restore, direct V1 CR write, or reconciliation retry | Admission/controller limit prevents V1 runtime |
| Supported distribution package/service checks | Only V1-specific iSCSI checks are omitted |
| Talos without the iSCSI extension | No `iscsid` namespace lookup; common and V2 checks still run |
| Missing common/V2 prerequisites | Existing failure conditions remain observable |
| Helm hook sees an old default-settings ConfigMap | New intent is passed directly and incompatible old state is rejected |
| New V2-only installation provisions through the chart class, with either revision-counter option | StorageClass explicitly selects V2 and the volume uses V2 |
| Existing StorageClass or legacy volume has implicit/explicit V1 semantics | No automatic parameter rewrite or V1-to-V2 reinterpretation |
| Mixed-version manager rollout | Keep iSCSI installed; do not permit dependency removal before all managers are ready in the new mode |
| Deliberate return to V1-capable mode | Restore prerequisites first; enable V1 only after all managers accept the capability |

In isolated installation and upgrade tests, verify V2 checksums across attach/detach, replica rebuild, node reboot, and backup/restore while hosts lack iSCSI. Negative controls must show that disabling common or V2 prerequisites still fails. No performance multiplier is an acceptance condition for this prerequisite change.

### Upgrade strategy

Keep the default mode backward compatible. Do not infer V2-only intent from a temporarily disabled engine.

For existing installations, finish migration and V1 retirement before selecting V2-only mode. Keep iSCSI installed throughout the manager/chart rollout. Require all manager roles to report validated operational mode/settings and no incompatible V1 storage or runtime before removing host dependencies. Pod readiness that proves webhook reachability alone is insufficient. A partially upgraded installation is not evidence that removal is safe.

Returning to an older release that unconditionally requires iSCSI also requires restoring its host prerequisites first. Document supported upgrade/downgrade combinations with the release that implements this proposal; an unreleased build is not a supported retirement path.

## Note

A conditional startup skip alone does not implement this proposal: it leaves later V1 enablement, pre-upgrade hooks, Talos monitoring, and preflight behavior inconsistent. Dynamic per-node capability detection is an alternative, but requires a broader scheduling and mixed-capability design than this installation-wide mode.
