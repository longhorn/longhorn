# Default Priority Class

## Summary

Pods can have priority which indicates the importance of a pod relative to other pods.
Longhorn pods will face unexpected eviction due to insufficient cluster resources or being preempted by higher-priority pods
A PriorityClass defines a mapping from a priority class name to the integer value of the priority, where a higher value signifies greater priority..

### Related Issues

[Have default priorityClass to prevent unexpected longhorn pods eviction.](https://github.com/longhorn/longhorn/issues/6528)

## Motivation

### Goals

- Reduce the opportunity of the unexpected eviction of Longhorn pods.

### Non-goals [optional]

`None`

## Proposal

Have a default priority class with the highest value to all Longhorn pods.

### User Stories

After a fresh installation or an upgrade, users will have Longhorn pods with the field `priorityClassName: longhorn-critical` in `spec` to prevent Longhorn pods from unexpected eviction.

- For install, the priority class will not be set using the default value if the value has been provided by users.
- For upgrade, the priority class will not be set using the default value if the settings already exists.

### User Experience In Detail

1. For a fresh install, the default priority class will be set if there is no priority class set by users. The setting of the priority class will be updated.
2. For an upgrade, if all volumes are detached and the setting of the priority class is empty, the setting should be applied including user-managed components. The setting of the priority class will be updated because the source of truth of settings is the config map (longhorn-default-setting).
3. For an upgrade, no matter weather all volumes are detached or not, if the setting of the priority class has been set, the setting should not be updated with the default priority class.
4. For an upgrade, if volumes are attached, the setting should be applied to the user-managed components only if they haven't been set. The setting of the priority class will not be updated.

NOTE: Before modifying the setting `priority-class`, all Longhorn volumes must be detached.

### API changes

`None`

## Design

### Implementation Overview

1. Adding a new template YAML file in the Longhorn chart/templates to create a default priority class.

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: longhorn-critical
# The example value of a production is 4000000 from https://kubernetes.io/blog/2023/01/12/protect-mission-critical-pods-priorityclass
# Most of the paragraph uses 1000000 for high priority class.
# system default priority classes:
#   """txt
#     NAME                      VALUE        GLOBAL-DEFAULT   AGE
#     system-node-critical      2000001000   false            5h30m
#     system-cluster-critical   2000000000   false            5h30m
#   """
# The maximum allowed value of a user defined priority is 1000000000
value: 1000000000
description: "Ensure Longhorn pods have the highest priority to prevent any unexpected eviction by the Kubernetes scheduler under node pressure"
globalDefault: false
preemptionPolicy: PreemptLowerPriority
```

2. Set the `defaultSettings.priorityClass` to `longhorn-critical` and `priorityClass` of Longhorn components in the value.yaml of Longhorn chart.

```yaml
...
defaultSettings:
  ...
  priorityClass: &defaultPriorityClassNameRef "longhorn-critical"
  ...
longhornManager:
  log:
    # -- Options: `plain`, `json`
    format: plain
  # -- Priority class for longhorn manager
  priorityClass: *defaultPriorityClassNameRef
longhornDriver:
  # -- Priority class for longhorn driver
  priorityClass: *defaultPriorityClassNameRef
longhornUI:
  # -- Priority class count for longhorn ui
  priorityClass: *defaultPriorityClassNameRef
```

### Test plan

1. Modify the test case `test_setting_priority_class` to check if there is a default priority class `longhorn-critical` existing.
2. Add a test case where the `defaultSettings.priorityClass` has been modified by users and the setting `priority-class` should be the same to the value provided by users after a fresh install.
3. Add a test case where the setting `priority-class` will be updated if all volumes are detached and the setting of the priority class is not set for an upgrade.
4. Add a test case where the setting `priority-class` will not be updated after the upgrade if any volume is attached.
5. Add a test case where the setting `priority-class` will not be updated if the setting of the priority class has been set for an upgrade.

### Upgrade strategy

When adding a priority class, all Longhorn volumes must be detached.
Therefore we will not change the setting `priority-class` if there is any volume attached to the node or the setting `priority-class` is set to a priority class.

## Note [optional]

`None`
