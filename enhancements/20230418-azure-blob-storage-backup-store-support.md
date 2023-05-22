# Azure Blob Storage Backup Store Support

## Summary

Longhorn supports Azure Blob Storage as a backup storage.

### Related Issues

https://github.com/longhorn/longhorn/issues/1309

## Motivation

### Goals

- Support Azure Blob Storage as a backup storage.

## Proposal

- Introduce Azure Blob Storage client for supporting Azure Blob Storage as a backup storage.

## User Stories

Longhorn already supports NFSv4, CIFS and S3 servers as backup storage. However, certain users may still want to be able to utilize Azure blob storage to push/pull backups to/from.

### User Experience In Details

- Users can configure a Azure Blob Storage as a backup storage
  - Set **Backup Target**. The path to a Azure Blob Storage is like

    ```bash
    azblob://${container}@blob.core.windows.net/${path name}
    ```

- Set **Backup Target Credential Secret**
  - Create a secret and deploy it

    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
    name: azblob-secret
      namespace: longhorn-system
    type: Opaque
    data:
      AZBLOB_ACCOUNT_NAME: ${AZBLOB_ACCOUNT_NAME}
      AZBLOB_ACCOUNT_KEY: ${AZBLOB_ACCOUNT_KEY}
    ```

  - Set the setting **Backup Target Credential Secret** to `azblob-secret`

## Design

### Implementation Overview

- longhorn-manager
  - Introduce the fields `AZBLOB_ACCOUNT_NAME` and `AZBLOB_ACCOUNT_KEY` in credentials. The two fields are passed to engine and replica processes for volume backup and restore operations.
- backupstore
  - Implement Azure Blob Storage register/unregister and basic CRUD functions.

## Test Plan

### Integration Tests

1. Set a Azure Blob Storage as backup storage.
2. Create volumes and write some data.
3. Back up volumes to the backup storage and the operation should succeed.
4. Restore backups and operations should succeed.
5. All data is not corrupted.
