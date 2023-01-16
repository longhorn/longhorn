# SMB/CIFS Backup Store Support

## Summary

Longhorn supports SMB/CIFS share as a backup storage.

### Related Issues

https://github.com/longhorn/longhorn/issues/3599

## Motivation

### Goals

- Support SMB/CIFS share as a backup storage.

## Proposal

- Introduce SMB/CIFS client for supporting SMB/CIFS as a backup storage.

## User Stories

Longhorn already supports NFSv4 and S3 servers as backup storage. However, certain users may encounter compatibility issues with their backup servers, particularly those running on Windows, as the protocols for NFSv4 and S3 are not always supported. To address this issue, the enhancement will enhance support for backup storage options with a focus on the commonly used SMB/CIFS protocol, which is compatible with both Linux and Windows-based servers.

### User Experience In Details
- Check each Longhorn node's kernel supports the CIFS filesystem by
    ```
    cat /boot/config-`uname -r` | grep CONFIG_CIFS
    ```
- Install the CIFS filesystem user-space tools `cifs-utils` on each Longhorn node
- Users can configure a SMB/CIFS share as a backup storage
    - Set **Backup Target**. The path to a SMB/CIFS share is like
        
        ```bash
        cifs://${IP address}/${share name}
        ```
        
    - Set **Backup Target Credential Secret**
        - Create a secret and deploy it
            
            ```yaml
            apiVersion: v1
            kind: Secret
            metadata:
              name: cifs-secret
              namespace: longhorn-system
            type: Opaque
            data:
              CIFS_USERNAME: ${CIFS_USERNAME}
              CIFS_PASSWORD: ${CIFS_PASSWORD}
            ```
            
        - Set the setting **Backup Target Credential Secret** to `cifs-secret`

## Design

### Implementation Overview

- longhorn-manager
    - Introduce the fields `CIFS_USERNAME` and `CIFS_PASSWORD` in credentials. The two fields are passed to engine and replica processes for volume backup and restore operations.
- backupstore
    - Implement SMB/CIFS register/unregister and mount/unmount functions

### Test Plan

### Integration Tests

1. Set a SMB/CIFS share as backup storage.
2. Back up volumes to the backup storage and the operation should succeed.
3. Restore backups and the operation should succeed.