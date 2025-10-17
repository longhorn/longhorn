# RWX Volume Endpoint Network

## Summary

This proposal introduces the `endpoint-network-for-rwx-volume` setting, allowing users to assign a dedicated Network Attachment Definition (NAD) for RWX (ReadWriteMany) volume endpoints. This improves network isolation for RWX NFS traffic, keeping it separate from the primary Longhorn networks (cluster and storage networks).

### Related Issues

- https://github.com/longhorn/longhorn/issues/10269

## Motivation

In current versions (<=v1.10), RWX volume endpoints are limited to using either the cluster network or the storage network. Introducing a dedicated endpoint network enables:

- Isolation of RWX NFS server and client traffic from the primary Longhorn networks and other application workloads.
- Users have more control over network paths for RWX volumes.

### Goals

- Allow RWX volume NFS server endpoints to use a dedicated NAD.
- Preserve backward compatibility for existing Longhorn systems that use the storage network for RWX volume.

### Non-goals

- **Remote mount support:** Using the host network interface directly is outside Kubernetes network namespace. This means the relevant component pods loses cluster DNS resolution.
- **StorageClass/Volume-based networking:** Per-SC/volume network configuration is not supported, as the CSI plugin requires full network access to additional networks, and implementing per-SC/volume networking would be complicated.

## Proposal

### User Stories

#### Story 1: Improved Network Control And Isolation For RWX Volumes

- **Before:** RWX volume endpoints can only use the cluster or storage network.
- **After:** RWX volume endpoints can use a dedicated NAD, isolating traffic from the cluster and storage networks.

### User Experience

#### Fresh Install

- The user creates a dedicated NAD for RWX volume endpoints.
- The user sets the `endpoint-network-for-rwx-volume` global setting to the NAD (`<namespace>/<name>`), following the same convention as `storage-network`.
- When a workload pod is created, its RWX volume is mounted via the NFS endpoint using the NAD-assigned IP on the share-manager pod's `lhnet2` interface.
- If the `endpoint-network-for-rwx-volume` global setting is not set, Longhorn will default to using the Kubernetes cluster network, keeping the same behavior when `storage-network-for-rwx-volume-enabled=true`.

#### Upgrade

- If `storage-network-for-rwx-volume-enabled=true`, the manager migrates the setting to `endpoint-network-for-rwx-volume=storage-network`, preserving existing behavior.
- If `storage-network-for-rwx-volume-enabled=false`, the manager sets `endpoint-network-for-rwx-volume` to the default (empty) value, keeping behavior unchanged.

### API changes

`None`

## Design

### Implementation Overview

#### New Global Setting

`endpoint-network-for-rwx-volume`:
- **Type:** `String`
- **Default:** `""`
- **DataEngineSpecific**: `false`,

Specifies a dedicated network for mounting RWX (ReadWriteMany) volumes. Leave this field blank to use the default Kubernetes cluster network, which behaves the same as when the deprecated `storage-network-for-rwx-volume-enabled` setting is set to `false`.
 
Changing the value of `endpoint-network-for-rwx-volume` only takes effect when RWX volumes are DETACHED. The network interface/NAD is assigned when the share-manager pod is created, so changing the setting while the volume is attached does not update the existing pod. This behavior is identical to the deprecated `storage-network-for-rwx-volume-enabled` setting.

#### Deprecate Old Global Setting

- `SettingNameStorageNetworkForRWXVolumeEnabled` will be deprecated.
- During upgrade, if the storage network for RWX volumes was previously enabled, the new `endpoint-network-for-rwx-volume` setting will inherit the value of the `storage-network` setting to preserve existing behavior.

#### Component CNI

- Before this change, CSI plugin and share-manager pods were annotated with `k8s.v1.cni.cncf.io/networks` using the `lhnet1` interface (storage network).
- With this change, RWX NFS endpoints use a new interface, `lhnet2`, for network isolation.
- Other components unrelated to the NFS endpoint continue to use `lhnet1` for storage network.

#### Endpoint Slice

The endpoint controller updates the endpoint subset with the share-manager pod's `lhnet2` interface IP from the `k8s.v1.cni.cncf.io/network-status` annotation.

### Test plan

1. **Upgrade from v1.10.x:** Confirm that the `storage-network-for-rwx-volume-enabled` setting is replaced by `endpoint-network-for-rwx-volume`.
    - If the storage network was previously enabled (`true`), the new `endpoint-network-for-rwx-volume` setting inherits the `storage-network` value.
1. **Feature validation:** Verify that RWX volume mounts function correctly with the endpoint network setting.
    - Example scenarios:
        | storage-network | endpoint-network-for-rwx-volume |
        | --------------- | ------------------------------- |
        | NAD1            | NAD1                            |
        | NAD1            | NAD2                            |
        | NAD1            | -                               |

### Upgrade strategy

During upgrade, the manager detects the legacy `storage-network-for-rwx-volume-enabled` setting and performs a one-time migration:
- If `storage-network-for-rwx-volume-enabled=true`, `endpoint-network-for-rwx-volume` is set to the `storage-network` value.
- If the legacy setting is `false` or absent, `endpoint-network-for-rwx-volume` is created with the default (empty) value.

## Note

`None`
