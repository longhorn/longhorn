# Gateway API Filters

## Summary

This enhancement adds a `httproute.filters` field to the Helm chart, rendered onto the HTTPRoute's rule, so users can secure the Longhorn UI behind Gateway-API-native auth/middleware mechanisms.

### Related Issues

https://github.com/longhorn/longhorn/issues/12976

## Motivation

### Goals

- Allow users installing Longhorn via the Helm chart with `httproute.enabled=true` to attach one or more `HTTPRouteFilter` entries to the generated route rule.
- Preserve backward compatibility: existing httproute.* values and generated manifests must be unaffected when filters is unset.
- Document the new `httproute.filters` value in the Helm chart configuration reference, including its type, default, and description.

### Non-goals [optional]

- Longhorn will not implement or ship its own auth proxy, middleware, or ExtensionRef target resource. Users remain responsible for creating and managing the referenced ExtensionRef resource; Longhorn only wires the reference into the HTTPRoute.
- This proposal does not attempt to validate that the Gateway controller in use actually supports a given filter type.

## Proposal

Add a new Helm value, `httproute.filters`, accepting a list of objects that mirror the upstream Gateway API `HTTPRouteFilter` schema.

### User Stories
Currently, users can configure the Longhorn UI `HTTPRoute` through the Helm chart, but there is no way to configure additional `HTTPRoute filters` through `values.yaml`.
With this enhancement, users will be able to configure `HTTPRoute filters` directly through `values.yaml`. What this requires of the user, end to end:

- A working Gateway API installation.
- At least one Gateway resource already deployed, referenced via `httproute.parentRefs`.
- The referenced filter target created before enabling `httproute.filters`, in the same namespace as the generated HTTPRoute.
- `httproute.filters` populated in `values.yaml` pointing at that resource.

### User Experience In Detail

Users who want to place an authentication (or other traffic-policy) layer in front of the Longhorn UI configure this via a new `httproute.filters` list in `values.yaml`. The chart passes this list through into the generated HTTPRoute's `spec.rules[].filters` largely unmodified, so any filter type/shape supported by the user's Gateway controller is expressible without the chart needing to special-case specific auth providers.
1. Enable the HTTPRoute, setting `httproute.enabled`, `parentRefs`, and `hostnames` in `values.yaml` as today. 
2. Create the `filter` target the middleware/policy resource referenced by the filter (e.g. a Traefik Middleware), using whatever CRD the user's Gateway controller provides. Longhorn does not create this resource. 
3. Add `httproute.filters` in `values.yaml`, using the standard Gateway API HTTPRouteFilter schema:
```yaml
  httproute:
     enabled: true
     filters:
       - type: ExtensionRef
         extensionRef:
           group: traefik.io
           kind: Middleware
           name: oauth-forwardauth
```
4. Run `helm upgrade ...`. The chart renders filters onto `spec.rules[0].filters` of the generated HTTPRoute. 

### API changes
N/A

## Design
Helm chart template changes. `chart/templates/httproute.yaml` gains a conditional block rendering `filters` under the existing rule for `httproute`, guarded the same way other optional fields.

### Implementation Overview

### Test plan

### Upgrade strategy

Purely additive chart change, so no migration needed. Users on existing `httproute.enabled=true` deployments upgrade normally and opt into filters by setting the new value and running helm upgrade.

## Note [optional]

Additional notes.
