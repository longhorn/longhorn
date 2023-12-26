# Engine Upgrade Enforcement

## Summary

The current Longhorn upgrade process lacks enforcement of the engine version, potentially leading to compatibility issues. To address this concern, we propose the implementation of an Engine Upgrade Enforcement feature.

### Related Issues

https://github.com/longhorn/longhorn/issues/5842

## Motivation

Longhorn needs to be able to upgrade safely without risking compatibility issue with older version engine images. Without this enhancement, we are facing various challenges like dealing with potential operation failures and increased maintenance overhead.

### Goals

The primary goal of this proposal is to enhance Longhorn's upgrade mechanism by introducing logic that prevents upgrading to Longhorn versions while there are incompatible engine images in use.
### Non-goals [optional]

`None`

## Proposal

This proposal focuses on preventing users from upgrading to unsupported or incompatible engine versions. This enhancement will build upon the existing pre-upgrade checks to include validation of engine version compatibility.

### User Stories

#### Story 1: Preventing Incompatible Upgrades

Previously, users had the freedom to continue using an older engine version after a Longhorn upgrade. With the proposed enhancement, the Longhorn upgrade process will be blocked if it includes an incompatible engine version. This will enforce users to manually upgrade the engine to a compatible version before proceeding with the Longhorn upgrade.

### User Experience In Detail

User will perform upgrade a usual. Longhorn will examine the compatibility of the current engine version. If the current engine version is incompatible with the target engine version for the upgrade, Longhorn will halt the upgrade process and prompt the user to address the engine version mismatch before proceeding.

### API changes

`None`

## Design

### Implementation Overview

The implementation approach for this feature will be similar to the [Upgrade Path Enforcement feature](https://github.com/longhorn/longhorn/blob/master/enhancements/20230315-upgrade-path-enforcement.md).

Key implementation steps include:

1. Enhance the function [CheckUpgradePathSupported(...)](https://github.com/longhorn/longhorn-manager/blob/v1.5.1/upgrade/util/util.go#L168) to include the new checks.
```
func CheckUpgradePathSupported(namespace string, lhClient lhclientset.Interface) error {
	if err := CheckLHUpgradePathSupported(namespace, lhClient); err != nil {
		return err
	}

	return CheckEngineUpgradePathSupported(namespace, lhClient, emeta.GetVersion())
}
```

1. Retrieve the current engine images being used and record the versions.
1. Prevent upgrades if the targeting engine version is detact to be downgrading.
1. Prevent upgrades if the engine image version is lower than [the minimum required version for the new engine image controller API](https://github.com/longhorn/longhorn-engine/blob/v1.5.1/pkg/meta/version.go#L10).

### Test plan

- Create unit test for the new logic.
- Run manual test to verify the handling of incompatible engine image versions (e.g., Longhorn v1.4.x -> v1.5.x -> v1.6.x.)

### Upgrade strategy

`None`

## Note [optional]

`None`
