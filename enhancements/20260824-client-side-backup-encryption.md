# Client-Side Backup Encryption

## Summary

Longhorn currently supports encryption for in-cluster volumes. However, users may want to keep a Longhorn volume unencrypted inside the cluster while encrypting its backup before the backup data is stored in a remote backup target.

This enhancement introduces **client-side encryption for Longhorn backups**, independently of Longhorn in-cluster volume encryption.

When backup encryption is enabled, Longhorn encrypts backup data before passing it to the backup store.

Conceptually:

```text
Volume data
    |
    v
Backup processing
    |
    v
Compression
    |
    v
Client-side encryption
    |
    v
Backup Store
    |
    +-- S3
    +-- NFS
    +-- CIFS
```

The backup target receives encrypted data and does not need to understand or implement Longhorn's encryption format.

The initial version uses a simple configuration model with two levels:

1. `volume.spec.backupEncryptionSecret`
2. Global `backup-encryption-secret` setting

The Volume-level Secret takes precedence over the global setting.

If neither specifies a Secret, client-side backup encryption is disabled.

### Related Issues

* #5220 - Encrypt volume backup to remote backup store without in-cluster volume encryption
* #8453 - Backup encryption
* #12297 - Backup encryption automated test
* #4883 - Block volume encryption

---

# Motivation

Longhorn volume encryption and backup encryption protect data in different locations.

Volume encryption protects data stored on Longhorn storage nodes.

Backup encryption protects data stored in a backup target.

A user may trust the Kubernetes cluster and its storage nodes but use an external backup destination that has different security requirements.

For example:

```text
Kubernetes Cluster
    |
    | trusted
    v
Longhorn Volume
    |
    | plaintext inside cluster
    v
Backup Processing
    |
    | encrypt locally
    v
Encrypted Backup
    |
    v
Remote Backup Target
```

Without independent backup encryption, users may need to enable volume encryption even when their only requirement is protecting remote backups.

This enhancement separates these two policies.

A user can therefore configure:

```text
Volume encryption:
    disabled

Backup encryption:
    enabled
```

The backup target only receives encrypted backup payloads.

---

# Goals

The goals of this enhancement are:

* Support client-side encryption for Longhorn backups.
* Make backup encryption independent from Longhorn in-cluster volume encryption.
* Encrypt backup data before it reaches the backup target.
* Support all Longhorn backup target types supported by the backupstore implementation, including S3, NFS, and CIFS.
* Keep client-side encryption independent from the individual backup-store driver.
* Use a simple first-version configuration model.
* Support a global default encryption Secret.
* Allow an individual Volume to specify a different encryption Secret.
* Use authenticated encryption to provide confidentiality and integrity.
* Use Kubernetes Secrets as the encryption-key source in the first version.
* Keep the design extensible for future external KMS integration.
* Preserve existing unencrypted backups.
* Preserve existing backup behavior when encryption is not configured.
* Preserve incremental backup behavior when the encryption context is compatible.
* Persist enough non-sensitive encryption metadata to restore encrypted backups later.
* Never persist plaintext encryption keys in Longhorn CRs, backup metadata, logs, events, or support bundles.
* Fail closed if encryption or decryption cannot be completed.

---

# Non-Goals

The following are outside the scope of the initial implementation:

* Server-side encryption.
* SSE-S3.
* SSE-KMS.
* SSE-C.
* Combining client-side and server-side encryption.
* Changing Longhorn in-cluster volume encryption.
* External KMS implementation.
* Automatically encrypting existing plaintext backups.
* Automatically decrypting existing encrypted backups.
* Automatically re-encrypting existing backups after changing the key.
* Online key rotation of existing encrypted backup objects.
* Recovering an encrypted backup after the encryption key is lost.
* Encrypting backup-target paths, object names, file names, sizes, or timestamps.
* Explicitly opting a Volume out of encryption when the global `backup-encryption-secret` setting is configured.

The last limitation is intentional for the first version in order to keep the configuration model simple.

---

# User Stories

## User Story 1 - Encrypt all backups

A user wants all Longhorn backups to use the same encryption key.

The administrator configures:

```text
backup-encryption-secret = global-backup-key
```

A Volume does not configure its own Secret.

The effective encryption Secret is:

```text
global-backup-key
```

All backups are encrypted using the global configuration.

---

## User Story 2 - Encrypt only a specific Volume

The global setting is empty:

```text
backup-encryption-secret = ""
```

A Volume specifies:

```yaml
spec:
  backupEncryptionSecret: database-backup-key
```

Backups for this Volume are encrypted using `database-backup-key`.

Volumes without `backupEncryptionSecret` remain unencrypted.

---

## User Story 3 - Override the global key for a Volume

Global configuration:

```text
backup-encryption-secret = default-backup-key
```

Volume configuration:

```yaml
spec:
  backupEncryptionSecret: database-backup-key
```

The Volume-level Secret takes precedence.

The effective encryption Secret is:

```text
database-backup-key
```

---

## User Story 4 - No encryption

Global configuration:

```text
backup-encryption-secret = ""
```

Volume configuration:

```text
backupEncryptionSecret = ""
```

No encryption Secret is resolved.

Longhorn uses the existing unencrypted backup behavior.

---

## User Story 5 - Disaster recovery

Cluster A creates encrypted backups.

The original cluster is lost.

The administrator deploys Longhorn in cluster B, configures the original backup target, and recreates the required Kubernetes Secret.

During backup synchronization, Longhorn reads the encryption metadata associated with the backup and determines which Secret name is required.

Longhorn can then restore the encrypted backup.

If the required Secret is unavailable, Longhorn reports a clear encryption-key error.

---

# Configuration

## Global Setting

Introduce a new global Longhorn setting:

```text
backup-encryption-secret
```

The value is the name of a Kubernetes Secret containing the backup encryption key.

Default:

```text
backup-encryption-secret = ""
```

An empty value means that backup encryption is not enabled globally.

For example:

```text
backup-encryption-secret = longhorn-backup-encryption
```

means backups use `longhorn-backup-encryption` unless the Volume specifies another Secret.

The encryption key itself is never stored in the Setting CR.

Only the Secret name is stored.

---

# Volume Configuration

Add a field to `VolumeSpec`:

```go
type VolumeSpec struct {
    ...

    BackupEncryptionSecret string `json:"backupEncryptionSecret,omitempty"`
}
```

Example:

```yaml
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: database-volume
  namespace: longhorn-system
spec:
  backupEncryptionSecret: database-backup-encryption
```

An empty value means Longhorn falls back to the global setting.

No explicit `inherit`, `enabled`, or `disabled` state is required.

---

# Effective Encryption Secret Resolution

Before creating a backup, Longhorn resolves the encryption Secret using the following logic:

```go
func resolveBackupEncryptionSecret(
    volumeSecret string,
    globalSecret string,
) string {
    if volumeSecret != "" {
        return volumeSecret
    }

    return globalSecret
}
```

Conceptually:

```text
volume.spec.backupEncryptionSecret
                |
        non-empty?
         /     \
       yes      no
       |         |
       v         v
 use Volume   read global
   Secret      setting
                  |
               non-empty?
                /     \
              yes      no
              |         |
              v         v
         use Global    encryption
            Secret     disabled
```

---

# Configuration Examples

## Global encryption

```text
Global:
    backup-encryption-secret = global-key

Volume:
    backupEncryptionSecret = ""
```

Effective:

```text
global-key
```

---

## Per-Volume encryption

```text
Global:
    backup-encryption-secret = ""

Volume:
    backupEncryptionSecret = volume-key
```

Effective:

```text
volume-key
```

---

## Per-Volume override

```text
Global:
    backup-encryption-secret = global-key

Volume:
    backupEncryptionSecret = volume-key
```

Effective:

```text
volume-key
```

---

## Encryption disabled

```text
Global:
    backup-encryption-secret = ""

Volume:
    backupEncryptionSecret = ""
```

Effective:

```text
no encryption
```

---

# Explicit Per-Volume Opt-Out

The simplified model intentionally does not provide an explicit per-Volume opt-out from globally configured encryption.

For example:

```text
Global:
    backup-encryption-secret = global-key

Volume:
    backupEncryptionSecret = ""
```

means:

```text
use global-key
```

rather than:

```text
disable encryption
```

Supporting an explicit opt-out would require another configuration state or field.

That capability can be added later if required.

---

# API and CRD Changes

## Volume CRD

Add:

```go
type VolumeSpec struct {
    ...

    BackupEncryptionSecret string `json:"backupEncryptionSecret,omitempty"`
}
```

No additional encryption policy structure is required.

---

# Backup CRD

The resolved Secret should be recorded with the Backup request so that the backup operation uses a stable resolved configuration.

Add:

```go
type BackupSpec struct {
    ...

    BackupEncryptionSecret string `json:"backupEncryptionSecret,omitempty"`
}
```

Before creating the Backup CR:

```text
Volume Secret
      |
      | empty?
      v
Global Setting
      |
      v
Resolved Secret
      |
      v
Backup.Spec.BackupEncryptionSecret
```

This avoids re-resolving the global or Volume configuration after the Backup has already been requested.

An empty `BackupEncryptionSecret` means that backup encryption is disabled.

The field contains only the Secret name.

It never contains the encryption key.

---

# Backup Status

A separate `Enabled` field is not required.

Encryption state can be inferred from whether the backup was created with a non-empty encryption Secret.

A Kubernetes CR also does not need to expose the encryption-format version.

The encryption format version belongs to the encrypted backup metadata because it describes the persistent backup format rather than Kubernetes configuration.

If useful for UI or troubleshooting, Backup status may expose only non-sensitive information such as the Secret name used for the backup.

For example:

```yaml
status:
  backupEncryptionSecret: database-backup-encryption
```

The actual key is never stored.

---

# Backup Metadata

Encrypted backups must contain enough metadata for Longhorn to determine:

* whether the backup is encrypted;
* which encryption format is used;
* which encryption Secret is required;
* how to decrypt the encrypted payload.

For example:

```json
{
  "encryption": {
    "version": 1,
    "algorithm": "AES-256-GCM-DARE",
    "secret": "database-backup-encryption"
  }
}
```

The Secret name is not the key itself and can be persisted.

The metadata must never contain:

* plaintext encryption key;
* plaintext KEK;
* plaintext DEK;
* Kubernetes Secret contents.

---

# Secret Format

The initial implementation uses a Kubernetes Secret as the key source.

For example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: database-backup-encryption
  namespace: longhorn-system
type: Opaque
data:
  key: <base64-encoded-key>
```

The exact required key size and encoding must be validated by Longhorn.

The Secret must contain sufficient entropy for the selected encryption algorithm.

Human-readable passwords should not be used directly as encryption keys.

---

# Client-Side Encryption Design

## Backup Flow

The encryption layer is placed above the backupstore driver.

Conceptually:

```text
Volume data
    |
    v
Changed-block processing
    |
    v
Compression
    |
    v
Client-side encryption
    |
    v
Backupstore abstraction
    |
    +-- S3
    +-- NFS
    +-- CIFS
```

Encryption happens after compression.

Compressing ciphertext is ineffective, so the backup must be compressed before it is encrypted.

---

# Restore Flow

Restore reverses the processing:

```text
Backup Target
    |
    v
Backupstore abstraction
    |
    v
Client-side decryption
    |
    v
Decompression
    |
    v
Restore
```

The decryption layer is independent from the underlying backup target.

---

# Encryption Algorithm

The encryption format must provide both confidentiality and integrity.

The current candidate is authenticated streaming encryption using:

```text
Algorithm:
    AES-256 authenticated encryption

Streaming format:
    DARE

Candidate library:
    github.com/minio/sio
```

The exact library and persistent format should be confirmed during the POC.

Authenticated encryption must detect:

* incorrect encryption keys;
* ciphertext modification;
* corruption;
* truncation;
* invalid encrypted chunks.

Plain AES-CTR without authentication is not sufficient.

---

# Streaming Encryption

The preferred implementation performs encryption as a stream.

Conceptually:

```text
Reader
   |
   v
Compression
   |
   v
Encryption Reader
   |
   v
Backupstore
```

Restore:

```text
Backupstore
   |
   v
Decryption Reader
   |
   v
Decompression
   |
   v
Writer
```

Streaming avoids loading an entire backup object into memory.

---

# Backup Targets Without Suitable Streaming APIs

Client-side encryption must support all backup target types.

If a backupstore path cannot directly consume a streaming encrypted reader, Longhorn may use temporary storage as an intermediate step.

For example:

```text
Backup data
    |
    v
Encryption
    |
    v
Temporary encrypted file
    |
    v
NFS / CIFS / other backupstore operation
```

Restore can use the reverse process:

```text
Backup Target
    |
    v
Temporary encrypted file
    |
    v
Decryption
    |
    v
Restore
```

The POC should determine which backupstore operations can remain fully streaming and where temporary files are required.

Temporary files must contain only encrypted backup payloads where possible.

Plaintext temporary backup data should be avoided.

---

# Envelope Encryption

The design uses envelope encryption.

The Secret contains a Key Encryption Key, or KEK.

For each encrypted backup object, Longhorn generates a random Data Encryption Key, or DEK.

The DEK encrypts the backup payload.

The KEK protects the DEK.

Conceptually:

```text
Kubernetes Secret
       |
       | KEK
       v
+------------------+
|     Wrap DEK     |
+------------------+
       ^
       |
Random DEK
       |
       +--------------------------+
       |                          |
       v                          v
Encrypt payload              Wrapped DEK
                                  |
                                  v
                         Encryption metadata
```

The plaintext KEK must never be stored in the backup target.

The plaintext DEK must never be persisted.

Only the wrapped DEK is stored with the encrypted backup.

---

# Encrypted Object Format

Rather than defining an unnecessary custom binary format, the encrypted object can use a standard container together with JSON metadata.

One possible representation is:

```text
encrypted-object
|
+-- metadata.json
|
+-- data.enc
```

For example:

```json
{
  "version": 1,
  "algorithm": "AES-256-GCM-DARE",
  "secret": "database-backup-encryption",
  "wrappedDEK": "...",
  "keyWrapAlgorithm": "..."
}
```

`data.enc` contains the encrypted backup payload.

The exact container format should be finalized after validating:

* streaming behavior;
* backupstore Read and Write;
* Upload and Download;
* temporary-file fallback;
* retry behavior;
* incremental backup behavior.

---

# Encryption Metadata Authentication

Encryption metadata that affects cryptographic processing must be authenticated.

For example:

```text
algorithm
format version
wrapped DEK
```

must not be silently modifiable.

The implementation should either:

* authenticate the metadata together with the ciphertext; or
* use it as authenticated associated data where supported.

Changing security-sensitive metadata must result in decryption failure.

---

# Backup Store Integration

Client-side encryption is implemented above the backupstore abstraction.

Conceptually:

```text
                 Backup Logic
                      |
                      v
               Encryption Layer
                      |
                      v
               BackupStoreDriver
                  /    |    \
                 /     |     \
                v      v      v
               S3     NFS    CIFS
```

The individual backupstore drivers continue to handle their normal responsibilities.

The encryption layer is responsible only for converting:

```text
plaintext -> ciphertext
```

and:

```text
ciphertext -> plaintext
```

The design does not introduce a second S3 client or provider-specific encryption implementation.

---

# Backup Creation

Before starting a backup:

1. Read `volume.spec.backupEncryptionSecret`.
2. If it is non-empty, use it.
3. Otherwise, read the global `backup-encryption-secret` setting.
4. Store the resolved Secret name in `Backup.Spec.BackupEncryptionSecret`.
5. If the resolved Secret is empty, use the existing backup path.
6. If the resolved Secret is non-empty, validate the Secret.
7. Load the encryption key securely.
8. Create the encrypted backup.
9. Store required non-sensitive encryption metadata with the backup.

Conceptually:

```text
Volume Secret
      |
      | empty
      v
Global Secret
      |
      v
Resolved Secret
      |
      +---- empty ----> normal backup
      |
      +---- set ------> encrypted backup
```

---

# Restore Behavior

Restore must determine encryption requirements from the backup metadata.

It must not use the current Volume or global configuration to determine whether an existing backup is encrypted.

Conceptually:

```text
Backup metadata
      |
      v
Encrypted?
   /      \
 no        yes
 |          |
 v          v
Normal    Read required
restore   Secret name
              |
              v
         Load Secret
              |
              v
          Decrypt
              |
              v
           Restore
```

For an encrypted backup:

1. Read the encryption metadata.
2. Determine the required Secret name.
3. Load the Kubernetes Secret.
4. Unwrap the DEK.
5. Authenticate and decrypt the backup.
6. Decompress the data.
7. Restore the Volume.

If the Secret is missing:

```text
required backup encryption Secret
"database-backup-encryption" is unavailable
```

If authentication fails:

```text
failed to decrypt backup data:
authentication failed
```

Longhorn must not retry the encrypted backup as plaintext.

---

# Backup Synchronization

Backup synchronization must use the encryption metadata stored in the backup target.

A backup target may contain:

```text
backup-1:
    unencrypted

backup-2:
    encrypted with secret-A

backup-3:
    encrypted with secret-B
```

Longhorn must identify the encryption requirement for each backup independently.

The current global setting must not be treated as the source of truth for historical backups.

---

# Incremental Backups

Longhorn incremental backups may reuse unchanged backup blocks.

Different encryption keys create different encryption contexts.

For example:

```text
Backup A:
    secret-A

Backup B:
    secret-B
```

A block encrypted under `secret-A` must not be reused in a backup that cannot decrypt the same encryption context.

Therefore, block reuse must account for the encryption context.

One possible implementation is to isolate encrypted backup blocks by encryption context.

For example:

```text
blocks/
    |
    +-- encryption-context-A/
    |      |
    |      +-- block-1
    |      +-- block-2
    |
    +-- encryption-context-B/
           |
           +-- block-1
           +-- block-3
```

The exact object/file path format should be determined during the POC.

The required rule is:

> Backup blocks can only be reused when the encryption contexts are compatible.

---

# Changing the Encryption Secret

Changing the configured Secret does not modify existing backups.

For example:

```text
Backup 1:
    secret-A

Backup 2:
    secret-A

Volume configuration changed to secret-B

Backup 3:
    secret-B
```

Backup 1 and Backup 2 still require `secret-A`.

Backup 3 requires `secret-B`.

Users must preserve old Secrets while backups depending on them remain in the backup target.

Automatic re-encryption of existing backups is outside the scope of this enhancement.

Replacing the key material inside an existing Secret can also make previous backups unrestorable.

Documentation should recommend creating a new Secret name when changing encryption keys.

---

# Key Loss

If the encryption Secret or its original key is permanently lost, backups encrypted with that key cannot be recovered.

Longhorn cannot recreate the key.

The UI and documentation must clearly warn:

> Losing the client-side backup encryption key permanently prevents restoration of backups encrypted with that key. Preserve encryption Secrets as part of the disaster-recovery procedure.

---

# Secret Handling

Encryption Secret contents must never be:

* written to Volume status;
* written to Backup status;
* written to backup metadata;
* logged;
* emitted in Kubernetes Events;
* exposed through UI APIs;
* included in support bundles as plaintext.

Only the Secret name may be persisted where required.

Errors may reference the Secret name.

For example:

```text
failed to load backup encryption Secret
"database-backup-encryption"
```

Errors must never include the key contents.

---

# Failure Handling

Client-side backup encryption must fail closed.

If encryption is configured but cannot be performed, the backup must fail.

Longhorn must never silently create an unencrypted backup.

---

## Missing Secret

```text
backup encryption Secret
"database-backup-encryption"
was not found
```

The backup does not start.

---

## Invalid Secret

```text
invalid backup encryption key in Secret
"database-backup-encryption"
```

The backup does not start.

---

## Incorrect Restore Key

```text
failed to decrypt backup:
authentication failed
```

No plaintext fallback occurs.

---

## Corrupted Ciphertext

```text
failed to decrypt backup:
ciphertext authentication failed
```

---

## Unsupported Encryption Format

```text
unsupported backup encryption format version
```

---

# Backward Compatibility

## Existing Global Configuration

The new global setting defaults to an empty value:

```text
backup-encryption-secret = ""
```

Therefore, backup encryption remains disabled after upgrade unless explicitly configured.

---

## Existing Volume CRs

Existing Volume CRs do not contain `backupEncryptionSecret`.

The field is therefore empty.

If the global setting is also empty, existing behavior remains unchanged.

No explicit `inherit` state is required.

---

## Existing Backups

Existing backup metadata does not contain encryption information.

These backups are treated as unencrypted legacy backups.

No existing backup data is automatically modified.

---

# Mixed Backup History

A backup target may contain both unencrypted and encrypted backups.

For example:

```text
backup-1:
    legacy plaintext

backup-2:
    secret-A

backup-3:
    secret-B
```

Longhorn must be able to synchronize and restore all supported backup formats.

---

# Upgrade

During upgrade:

* add the new global `backup-encryption-secret` Setting;
* add `Volume.Spec.BackupEncryptionSecret`;
* add `Backup.Spec.BackupEncryptionSecret`;
* update generated CRDs and clients;
* leave the global Secret setting empty by default;
* leave existing Volume fields empty;
* preserve existing backup behavior;
* do not rewrite existing backups.

No backup payload migration is required.

---

# Downgrade

Older Longhorn versions that do not understand the encrypted backup format will not be able to restore newly encrypted backups.

Downgrading Longhorn does not decrypt existing encrypted backup data.

This limitation must be documented in the release notes.

---

# Implementation Overview

## longhorn-manager

Responsibilities include:

* introduce the `backup-encryption-secret` global setting;
* add `Volume.Spec.BackupEncryptionSecret`;
* resolve the effective Secret;
* populate `Backup.Spec.BackupEncryptionSecret`;
* validate the referenced Secret;
* securely load Secret data when required;
* pass the encryption configuration to the backup process;
* expose sanitized errors;
* synchronize encrypted backup metadata.

---

## longhorn-engine / Backup Process

Responsibilities include:

* receive the resolved backup encryption Secret;
* perform client-side encryption;
* perform authenticated decryption;
* generate DEKs;
* wrap and unwrap DEKs;
* generate encryption metadata;
* read encryption metadata during restore;
* preserve incremental backup semantics;
* isolate incompatible encryption contexts.

---

## backupstore

The encryption layer should be implemented above the backupstore driver.

Conceptually:

```text
Current:

Backup data
    |
    v
BackupStoreDriver


New:

Backup data
    |
    v
Encryption Layer
    |
    v
BackupStoreDriver
```

Restore:

```text
BackupStoreDriver
    |
    v
Decryption Layer
    |
    v
Backup data
```

The implementation must validate interaction with:

* `Read`;
* `Write`;
* `Upload`;
* `Download`;
* seek requirements;
* streaming operations;
* temporary-file fallback;
* retries.

---

# UI Changes

## Global Setting

Add:

```text
Backup Encryption Secret

<secret-name>
```

An empty value means global client-side backup encryption is disabled.

---

## Volume

Add:

```text
Backup Encryption Secret

<secret-name>
```

If empty, the global setting is used.

The UI can show the effective Secret name.

For example:

```text
Volume Backup Encryption Secret:
    <empty>

Effective Backup Encryption Secret:
    longhorn-backup-encryption

Source:
    Global Setting
```

The actual Secret contents must never be displayed.

---

# Test Plan

## Unit Tests - Secret Resolution

### Global empty and Volume empty

```text
Volume:
    ""

Global:
    ""
```

Expected:

```text
encryption disabled
```

---

### Global configured

```text
Volume:
    ""

Global:
    global-key
```

Expected:

```text
global-key
```

---

### Volume configured

```text
Volume:
    volume-key

Global:
    ""
```

Expected:

```text
volume-key
```

---

### Volume overrides Global

```text
Volume:
    volume-key

Global:
    global-key
```

Expected:

```text
volume-key
```

---

# Unit Tests - CRDs

Verify:

* `Volume.Spec.BackupEncryptionSecret` serializes correctly;
* empty Volume field is valid;
* `Backup.Spec.BackupEncryptionSecret` serializes correctly;
* existing CRs remain valid;
* Secret names are passed correctly;
* Secret contents are never written into CRs.

---

# Unit Tests - Encryption

Verify:

* plaintext encrypts successfully;
* ciphertext decrypts to original plaintext;
* ciphertext does not expose original plaintext;
* encryption uses appropriate randomness;
* zero-length input is handled;
* small input is handled;
* large streaming input is handled;
* modified ciphertext fails authentication;
* truncated ciphertext fails;
* incorrect key fails;
* invalid wrapped DEK fails;
* unsupported format version fails;
* unsupported algorithm fails.

---

# Unit Tests - Secret Handling

Verify:

* valid Secret succeeds;
* missing Secret fails;
* malformed key fails;
* invalid key size fails;
* replacing the key results in authentication failure for old backups;
* Secret contents do not appear in errors;
* Secret contents do not appear in logs.

---

# Unit Tests - Backup Store Integration

Client-side encryption should be tested through the generic backupstore abstraction.

With encryption disabled:

```text
Write -> normal backup data
Read  -> original data
```

With encryption enabled:

```text
Write -> encrypted backup data
Read  -> original data after decryption
```

Test applicable operations for:

* S3;
* NFS;
* CIFS.

Verify:

* Write;
* Read;
* Upload;
* Download;
* deletion;
* retries;
* temporary-file path where required;
* streaming path where supported.

---

# Automated E2E Tests

## Test 1 - Existing Behavior

1. Install Longhorn.
2. Leave `backup-encryption-secret` empty.
3. Create a Volume without `backupEncryptionSecret`.
4. Write known data.
5. Create a backup.
6. Restore it.
7. Verify checksum.

Expected:

Existing backup behavior remains unchanged.

---

## Test 2 - Global Encryption

1. Configure the global encryption Secret.
2. Leave the Volume Secret empty.
3. Create a backup.
4. Verify remote backup data is encrypted.
5. Restore the backup.
6. Verify checksum.

---

## Test 3 - Volume Encryption

1. Leave the global Secret empty.
2. Configure `volume.spec.backupEncryptionSecret`.
3. Create a backup.
4. Verify backup data is encrypted.
5. Restore.
6. Verify checksum.

---

## Test 4 - Volume Override

Configure:

```text
Global:
    global-key

Volume:
    volume-key
```

Verify the Volume uses `volume-key`.

---

## Test 5 - Incremental Backup

1. Create initial data.
2. Create backup A.
3. Modify part of the Volume.
4. Create backup B using the same Secret.
5. Verify compatible unchanged blocks are reused.
6. Restore both backups.
7. Verify data.

---

## Test 6 - Different Encryption Secrets

1. Create backup A using `secret-A`.
2. Change the Volume configuration to `secret-B`.
3. Create backup B.
4. Verify backup A remains associated with `secret-A`.
5. Verify backup B uses `secret-B`.
6. Verify incompatible encrypted blocks are not reused.
7. Restore both using their corresponding Secrets.

---

## Test 7 - Missing Secret

1. Create an encrypted backup.
2. Remove its Secret.
3. Attempt restore.

Expected:

Restore fails with a missing-Secret error.

---

## Test 8 - Incorrect Key

1. Create a backup.
2. Replace the Secret contents with another key.
3. Attempt restore.

Expected:

Authentication fails.

No plaintext fallback occurs.

---

## Test 9 - Corrupted Ciphertext

1. Create an encrypted backup.
2. Modify the encrypted backup data.
3. Attempt restore.

Expected:

Authenticated decryption detects corruption.

---

## Test 10 - Disaster Recovery

1. Create encrypted backups in cluster A.
2. Remove cluster A.
3. Install Longhorn in cluster B.
4. Configure the same backup target.
5. Recreate the required encryption Secret.
6. Synchronize backups.
7. Restore.
8. Verify checksum.

---

## Test 11 - S3

Verify:

* encrypted backup;
* restore;
* incremental backup;
* synchronization;
* deletion;
* streaming/multipart behavior.

---

## Test 12 - NFS

Verify:

* encrypted backup;
* restore;
* incremental backup;
* synchronization;
* deletion;
* streaming or temporary-file behavior.

---

## Test 13 - CIFS

Verify:

* encrypted backup;
* restore;
* incremental backup;
* synchronization;
* deletion;
* streaming or temporary-file behavior.

---

## Test 14 - Upgrade

1. Install a Longhorn release without this feature.
2. Create an unencrypted backup.
3. Upgrade Longhorn.
4. Verify the old backup is still available.
5. Restore the old backup.
6. Configure encryption.
7. Create an encrypted backup.
8. Restore the encrypted backup.

---

## Test 15 - Mixed Backup History

Create:

```text
backup-1:
    unencrypted

backup-2:
    secret-A

backup-3:
    secret-B
```

Verify:

* synchronization works;
* encryption requirements are identified correctly;
* each backup restores with the expected Secret.

---

# Manual Security Test

Write a known plaintext pattern into a Volume.

Create an encrypted backup.

Inspect the backup target directly.

Verify the known plaintext cannot be found in encrypted payloads.

Inspect:

* longhorn-manager logs;
* engine logs;
* Kubernetes Events;
* Volume CR;
* Backup CR;
* support bundle.

Verify the encryption key is never exposed.

---

# Performance Test

Compare:

```text
unencrypted backup
vs.
encrypted backup
```

and:

```text
unencrypted restore
vs.
encrypted restore
```

Measure:

* throughput;
* CPU usage;
* memory usage;
* backup duration;
* restore duration;
* temporary storage usage where applicable;
* backup size.

Run applicable performance tests for S3, NFS, and CIFS.

---

# Security Considerations

Client-side encryption changes the trust boundary.

Without client-side encryption:

```text
Longhorn
    |
    v
Backup Target receives backup payload
```

With client-side encryption:

```text
Longhorn
    |
    v
Encrypt locally
    |
    v
Backup Target receives ciphertext
```

The backup target does not need access to the plaintext encryption key.

Authenticated encryption also detects modification of encrypted backup data.

The feature does not hide:

* backup paths;
* S3 object names;
* filesystem names;
* object/file size;
* timestamps;
* access patterns.

---

# Risks and Mitigations

## Key Loss

### Risk

The encryption Secret is lost.

### Impact

Encrypted backups cannot be restored.

### Mitigation

Document Secret backup as part of disaster recovery and provide clear UI warnings.

---

## Secret Replacement

### Risk

The same Kubernetes Secret name is updated with a different key.

### Impact

Existing backups using the previous key can no longer be restored.

### Mitigation

Recommend creating a new Secret name when rotating the key and retaining old Secrets while dependent backups exist.

---

## Incremental Backups with Different Keys

### Risk

An encrypted block created with one key is incorrectly reused by another backup using another key.

### Impact

Backup restore may fail.

### Mitigation

Include encryption context in the block-reuse decision or isolate block namespaces by encryption context.

Validate the final mechanism during the POC.

---

## Backup Target Differences

### Risk

Different backupstore drivers have different streaming, seek, or file-handling requirements.

### Mitigation

Place encryption above the backupstore abstraction.

Use streaming where possible.

Use encrypted temporary files where the driver requires a seekable file or cannot consume a streaming reader directly.

---

## Persistent Format Compatibility

### Risk

Future changes make existing encrypted backups unreadable.

### Mitigation

Use a versioned encrypted-backup format and treat that format as a persistent compatibility contract.

---

# Documentation

Documentation should cover:

* client-side backup encryption;
* difference from Longhorn volume encryption;
* global `backup-encryption-secret`;
* `Volume.Spec.BackupEncryptionSecret`;
* Volume-over-global precedence;
* empty Secret behavior;
* lack of explicit per-Volume opt-out in the first version;
* supported backup targets;
* Secret format;
* Secret management;
* disaster recovery;
* consequences of losing the key;
* changing keys;
* incremental backups;
* upgrade behavior;
* downgrade limitations.

---

# Rollout Plan

## Phase 1 - POC

Validate:

* encryption library;
* authenticated streaming encryption;
* encrypted-object format;
* JSON metadata;
* metadata authentication;
* DEK wrapping;
* S3 streaming behavior;
* NFS behavior;
* CIFS behavior;
* encrypted temporary-file fallback;
* retries;
* backupstore Read/Write;
* Upload/Download;
* incremental backup reuse;
* multiple encryption contexts.

The POC should resolve the encryption-context and backup-target I/O details before finalizing the persistent format.

---

## Phase 2 - API and Settings

Implement:

* `backup-encryption-secret` global Setting;
* `Volume.Spec.BackupEncryptionSecret`;
* `Backup.Spec.BackupEncryptionSecret`;
* generated CRD changes;
* generated clients;
* deep-copy updates;
* validation.

---

## Phase 3 - Encryption

Implement:

* Secret validation;
* DEK generation;
* DEK wrapping;
* streaming encryption;
* authenticated decryption;
* metadata generation;
* metadata parsing.

---

## Phase 4 - Backupstore Integration

Implement:

* encryption layer above BackupStoreDriver;
* streaming path;
* encrypted temporary-file fallback;
* S3 integration;
* NFS integration;
* CIFS integration;
* synchronization;
* restore.

---

## Phase 5 - UI

Implement:

* global Backup Encryption Secret setting;
* Volume Backup Encryption Secret field;
* effective Secret display;
* missing-key warnings;
* disaster-recovery warnings.

---

## Phase 6 - Tests and Documentation

Complete:

* unit tests;
* E2E tests;
* S3 tests;
* NFS tests;
* CIFS tests;
* upgrade tests;
* disaster-recovery tests;
* performance tests;
* documentation;
* release notes.

---

# Final Design Decision

```text
Feature:
    Client-side backup encryption

Backup targets:
    All supported Longhorn backup targets

Initial targets to validate:
    S3
    NFS
    CIFS

Server-side encryption:
    Out of scope

Configuration:
    Global backup-encryption-secret
    Volume.Spec.BackupEncryptionSecret

BackupTarget.Spec configuration:
    Not introduced in the first version

Configuration states:
    No explicit enabled / disabled / inherit state

Resolution:
    if Volume.Spec.BackupEncryptionSecret != "":
        use Volume Secret
    else:
        use global Secret

Encryption disabled:
    both Secret values are empty

Per-Volume opt-out when global is configured:
    Not supported in the first version

Backup.Spec:
    stores the resolved Secret name

Encryption location:
    Above BackupStoreDriver

Processing order:
    backup processing
    compression
    encryption
    backupstore

Encryption requirement:
    Authenticated encryption

Candidate:
    minio/sio / DARE

Initial key source:
    Kubernetes Secret

Future KMS:
    Out of scope for this LEP

Key model:
    Secret contains KEK
    random DEK encrypts backup payload
    KEK wraps DEK

Plaintext encryption key in backup:
    Never

Backup metadata:
    versioned encryption metadata
    Secret name
    wrapped DEK
    required non-sensitive crypto metadata

Streaming:
    preferred

Non-streaming backupstore paths:
    encrypted temporary-file fallback

Existing backups:
    supported unchanged

Existing Volumes:
    empty backupEncryptionSecret

Upgrade default:
    global Secret empty

Restore:
    uses backup metadata to identify
    the required Secret

Incremental backups:
    reuse only across compatible
    encryption contexts

Key changes:
    do not modify existing backups

Failure behavior:
    fail closed
    never silently create an
    unencrypted backup
```

This first-version design intentionally keeps the configuration and API small while keeping the encryption layer independent of S3, NFS, CIFS, or any individual backup-store implementation.
