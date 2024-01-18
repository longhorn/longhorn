# Support non-disruptive volume-related setting updates

## Summary

The volume-related settings can only be updated when no volumes are attached now. Users permitted to modify the volume-related settings and any changes will take effect only during volumes upgrade or reattachment.

### Related Issues

https://github.com/longhorn/longhorn/issues/7173

## Motivation

Longhorn must have the capability not to delete pods associated with running volumes when volume-related settings are updated. Without this enhancement, users are restricted to customizing the volume-related setting when all volumes are detached.

### Goals

- Users can update the volume-related settings immediately.
- The volume-related settings updated will take effect by Longhorn only when doing volume upgrade or volume reattachment.

### Non-goals [optional]

`None`

## Proposal

This proposal amis to enable users to update the volume-related settings while ensuring the uninterrupted operation of running volumes.

### User Stories

Previously, users can only update volume-related settings after manually detaching all volumes. With this enhancement, users can update the setting promptly and Longhorn will apply the setting to an instance manager only when no engine or replica processes on this instance manager.

### User Experience In Detail

Users can modify the volume-related settings as other general settings through the Longhorn UI or by applying the Kubernetes manifest file. Longhorn will carefully examine these settings to determine whether to proceed with the update process. If there are engine or replica processes on the instance manager, Longhorn will temporarily halt the update process and retry until all processes of the instance manager are gone.

Longhorn components except the instance manager will still check if all volumes are detached to apply the setting. When all volumes are detached, users might need to re-set the setting again to apply the setting to the other components.

### API changes

`None`

## Design

### Implementation Overview

1. Move `SettingNameV1DataEngine`, `SettingNameV2DataEngine`, and `SettingNameV2DataEngineGuaranteedInstanceManagerCPU` settings to the Category `SettingCategoryDangerZone`.

1. Remove all volumes attached examinations for volume-related settings from validations. Such as:

    ```golang
    case types.SettingNameTaintToleration:
        volumesDetached, err := s.AreAllVolumesDetachedState()
        if err != nil {
            return errors.Wrapf(err, "failed to list volumes before modifying toleration setting")
        }
        if !volumesDetached {
            return &types.ErrorInvalidState{Reason: "cannot modify toleration setting before all volumes are detached"}
        }
    ```

1. Separate the non-danger zone settings and danger zone setting in the setting controller.

    ```golang
    func (sc *SettingController) handleErr(err error, key interface{}) {
        ...
        _, name, err := cache.SplitMetaNamespaceKey(key)
        if err != nil {
            return err
        }
        err := sc.syncNonDangerZoneSettingsForManagedComponents(name)

        return sc.syncDangerZoneSettingsForManagedComponents(name)
    }
    ```

1. Block to apply the settings to system managed components if there are one or more volume attached:
    For settings:

    ```golang
    dangerSettingsRequiringAllVolumesDetached := []types.SettingName{
        types.SettingNameTaintToleration,
        types.SettingNameSystemManagedComponentsNodeSelector,
        types.SettingNamePriorityClass,
        types.SettingNameStorageNetwork,
    }
    ```

    ```golang
    if slices.Contains(dangerSettingsRequiringAllVolumesDetached, settingName) {
        detached, _, err := sc.ds.AreAllVolumesDetached(longhorn.DataEngineTypeAll)
        ...
        if !detached {
            return &types.ErrorInvalidState{Reason: fmt.Sprintf("failed to apply %v setting to Longhorn components when there are attached volumes. It will be eventually applied", settingName)}
        }
        // apply the setting to components.
        ...
    }
    ```

1. For the settings related to v1/v2 data engine volume, we will check if volumes are attached according to the data engine type.

    ```golang
    dangerSettingsRequiringSpecificDataEngineVolumesDetached := []types.SettingName{
        types.SettingNameV1DataEngine,
        types.SettingNameV2DataEngine,
        types.SettingNameGuaranteedInstanceManagerCPU,
        types.SettingNameV2DataEngineGuaranteedInstanceManagerCPU,
    }
    ```

    ```golang
    if slices.Contains(dangerSettingsRequiringSpecificDataEngineVolumesDetached, settingName) {
        switch settingName {
        case types.SettingNameV1DataEngine, types.SettingNameV2DataEngine:
            // the webhook validators will check if volumes are attached according to the data engine type.
        case types.SettingNameGuaranteedInstanceManagerCPU, types.SettingNameV2DataEngineGuaranteedInstanceManagerCPU:
            detached, _, err := sc.ds.AreAllVolumesDetached(dataEngine)
            if !detached {
                return &types.ErrorInvalidState{Reason: fmt.Sprintf("failed to apply %v setting to Longhorn components when there are attached volumes. It will be eventually applied", settingName)}
            }
            // apply the setting to components.
            ...
        }
    }
    ```

1. Handle pods of the instance manager in the instance controller and restart pods if the settings are not applied to pods and there is no instance running with the instance manager.

    ```golang
    func (imc *InstanceManagerController) handlePod(im *longhorn.InstanceManager) error {
        err := imc.annotateCASafeToEvict(im)
        if err != nil {
            return err
        }
        ...
        // check if pods of im *longhorn.InstanceManager needs to be restarted.
        isSettingSynced, isPodDeletedOrNotRunning, areInstancesRunningInPod, err := imc.areDangerZoneSettingsSyncedToIMPod(im)
        isPodSettingSynced := isSettingSynced || isPodDeletedOrNotRunning || areInstancesRunningInPod
        if im.Status.CurrentState != longhorn.InstanceManagerStateError && im.Status.CurrentState != longhorn.InstanceManagerStateStopped && isPodSettingSynced {
            return nil
        }

        // cleanup and recreate pods.
        ...
    }

    func (imc *InstanceManagerController) isSettingsSyncedToPod(im *longhorn.InstanceManager) (isSynced, isPodDeletedOrNotRunning, areInstancesRunningInPod bool, err error) {
        // check if instance manager is in running state.
        // check if instance manager has running instances.
        // check if the settings related to system managed components are applied to pods of the instance manager.

        return true, false, false err
    }
    ```

### Test plan

- Test no volume attached
    1. Fresh install Longhorn
    1. Customize a danger zone setting such as setting the value of `priority-class` to be `system-cluster-critical`
    1. The setting applies to all components managed by Longhorn.

- Test a volume attached with a replica on three node cluster.
    1. Fresh install Longhorn.
    1. Create a volume with a replica.
    1. Attach the volume to a node.
    1. Customize a danger zone setting such as setting the value of `priority-class` to be `system-cluster-critical`
    1. The setting only applies to pods of the instance manager without engine and replica processes.
    1. Detach the volume.
    1. The setting applies to all components managed by Longhorn.

### Upgrade strategy

- Add `spec.syncRequestedAt = now()` to all `settings.longhorn.io` objects during the upgrade.
- Check if settings related to system components should be applied to components managed by Longhorn.

## Note [optional]

`None`
