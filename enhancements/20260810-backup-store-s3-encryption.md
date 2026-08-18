# Backup Store Encryption for S3 Targets

## Summary

Longhorn currently supports encryption for in-cluster volumes. When an encrypted Longhorn volume is backed up, the backup data is also protected because the source volume data is already encrypted.

However, this couples backup-at-rest encryption with in-cluster volume encryption.

Some users want to keep Longhorn volumes unencrypted inside the Kubernetes cluster while independently encrypting backup data before sending it to a remote S3 backup store.

This enhancement introduces **client-side encryption for Longhorn backups stored in S3 or S3-compatible backup targets**, independently of Longhorn in-cluster volume encryption.

When client-side backup encryption is enabled:

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
Existing S3 backupstore
    |
    v
Remote S3-compatible storage
```

The remote object-storage provider receives ciphertext instead of plaintext backup data.

The feature supports encryption configuration at three levels:

1. Global
2. BackupTarget
3. Volume

The configuration precedence is:

```text
Volume > BackupTarget > Global
```

The feature is disabled by default for backward compatibility.

The initial implementation applies only to S3 and S3-compatible backup targets.

### Related Issues

* #5220 - Encrypt volume backup to remote backup store without in-cluster volume encryption
* #8453 - Backup encryption
* #12297 - Backup encryption automated test
* #4883 - Block volume encryption

---

# Motivation

Longhorn volume encryption and backup encryption address different security requirements.

A user may trust the Kubernetes cluster and the Longhorn storage nodes but store disaster-recovery backups in external object storage.

For example:

```text
Kubernetes cluster
    |
    | trusted
    v
Longhorn volume
    |
    | unencrypted
    v
Longhorn backup
    |
    | encrypted locally
    v
External S3 provider
```

Without independent backup encryption, users need to enable in-cluster volume encryption even if their only requirement is protecting data stored outside the cluster.

This introduces unnecessary coupling between two separate security policies.

Client-side backup encryption allows users to define:

```text
Volume encryption:
    disabled

Backup encryption:
    enabled
```

The S3 provider receives encrypted data and does not need to implement any Longhorn-specific encryption capability.

This is also useful when users do not fully trust an external storage provider or when encryption must happen before data leaves the Kubernetes cluster.

---

# Goals

The goals of this enhancement are:

* Support client-side encryption for Longhorn S3 backups.
* Make backup encryption independent of Longhorn volume encryption.
* Encrypt backup data before it leaves Longhorn.
* Support AWS S3 and S3-compatible backup targets through the existing Longhorn S3 implementation.
* Keep the encryption layer independent from the S3 provider.
* Allow encryption to be configured globally.
* Allow a BackupTarget to override the global configuration.
* Allow a Volume to override the BackupTarget and global configuration.
* Use the following configuration precedence:

```text
Volume > BackupTarget > Global
```

* Allow users to explicitly disable encryption for a specific BackupTarget or Volume.
* Use authenticated encryption to provide both confidentiality and integrity protection.
* Store encryption keys in Kubernetes Secrets for the initial implementation.
* Design key handling so external KMS providers can be supported in the future.
* Preserve Longhorn incremental backup behavior where encryption contexts are compatible.
* Preserve support for existing unencrypted backups.
* Ensure existing configurations remain unchanged after upgrade.
* Persist enough non-sensitive encryption information with every backup so existing backups remain restorable after configuration changes.
* Never store plaintext encryption keys in backup metadata, CR status, logs, events, or support bundles.
* Fail closed when encryption cannot be performed.

---

# Non-Goals

The following are outside the scope of this enhancement:

* Server-side encryption.
* SSE-S3.
* SSE-KMS.
* SSE-C.
* Combining client-side encryption with server-side encryption.
* Backup encryption for NFS or CIFS backup targets.
* Backup encryption for non-S3 backupstore drivers.
* Changing Longhorn in-cluster volume encryption.
* Automatically encrypting existing plaintext backups.
* Automatically decrypting existing encrypted backups.
* Automatically re-encrypting existing backups when the key changes.
* Online key rotation for existing backup objects.
* Recovering data after the encryption key is lost.
* Hiding S3 object names, sizes, timestamps, or access patterns.
* Implementing external KMS integration in the initial implementation.

Server-side encryption can be discussed and implemented separately in a future enhancement if required.

---

# User Stories

## User Story 1 - Encrypt all backups globally

A user requires all Longhorn backups to use client-side encryption.

The administrator enables backup encryption globally.

BackupTargets and Volumes that do not explicitly override the configuration inherit the global policy.

Example:

```text
Global:
    enabled

BackupTarget:
    inherit

Volume:
    inherit

Effective:
    enabled
```

---

## User Story 2 - Encrypt backups for one BackupTarget

A user has multiple backup destinations but only one requires encryption.

Example:

```text
Global:
    disabled

BackupTarget A:
    enabled

BackupTarget B:
    inherit
```

Backups written to BackupTarget A are encrypted.

Backups using BackupTarget B remain unencrypted.

---

## User Story 3 - Encrypt backups for specific volumes

A user requires encryption only for volumes containing sensitive data.

Example:

```text
Global:
    disabled

BackupTarget:
    inherit

Database Volume:
    enabled

Log Volume:
    inherit
```

The database backup is encrypted while the log-volume backup remains unencrypted.

---

## User Story 4 - Opt out from globally enabled encryption

A user enables backup encryption globally but wants a particular Volume to remain unencrypted.

Example:

```text
Global:
    enabled

BackupTarget:
    inherit

Volume:
    disabled
```

The explicit Volume configuration overrides the inherited encryption policy.

---

## User Story 5 - Use different encryption keys

A user wants different encryption keys for different BackupTargets or Volumes.

Example:

```text
Production BackupTarget:
    enabled
    keyID: production-key

Development BackupTarget:
    enabled
    keyID: development-key
```

Or:

```text
Global:
    enabled
    keyID: default-key

Database Volume:
    enabled
    keyID: database-key
```

The higher-priority configuration provides the complete effective encryption policy.

---

## User Story 6 - Disaster recovery

A user creates encrypted backups in cluster A.

Cluster A is lost.

The administrator installs Longhorn in cluster B and configures the same S3 backup target.

The administrator also restores the Kubernetes Secret containing the required backup encryption key.

Longhorn synchronizes the remote backups and determines from the backup metadata which key is required.

The backup is restored successfully.

If the required encryption key is unavailable, Longhorn reports a clear encryption-related error.

---

# Configuration Model

Client-side backup encryption can be configured at three levels:

```text
+-------------------+
|      Volume       |
+---------+---------+
          |
          | inherit
          v
+-------------------+
|   BackupTarget    |
+---------+---------+
          |
          | inherit
          v
+-------------------+
|      Global       |
+-------------------+
```

The precedence is:

```text
Volume > BackupTarget > Global
```

---

# Encryption States

Because this LEP covers only client-side encryption, the configuration can use three states:

```text
inherit
disabled
enabled
```

`inherit` is valid only for Volume and BackupTarget.

The global configuration supports:

```text
disabled
enabled
```

The default global state is:

```text
disabled
```

This ensures existing installations preserve their current behavior after upgrade.

---

# Global Configuration

The global configuration defines the default backup encryption policy.

Example:

```text
backup-encryption = enabled
backup-encryption-secret = longhorn-backup-encryption
```

If encryption is disabled globally:

```text
backup-encryption = disabled
```

No key is required.

The exact Longhorn setting names should follow existing naming conventions.

Conceptually, the required settings are:

```text
backup-encryption

backup-encryption-key-provider

backup-encryption-secret
```

The initial key provider is:

```text
secret
```

The encryption key itself is never stored in a Setting CR.

Only the Secret name and non-sensitive configuration are stored.

---

# BackupTarget Configuration

A BackupTarget may:

```text
inherit
disabled
enabled
```

Example:

```yaml
apiVersion: longhorn.io/v1beta2
kind: BackupTarget
metadata:
  name: default
  namespace: longhorn-system
spec:
  backupTargetURL: s3://backup-bucket@region/
  credentialSecret: backup-credential

  backupEncryption:
    state: enabled
    keyProvider: secret
    secretName: longhorn-backup-encryption
```

To inherit the global configuration:

```yaml
backupEncryption:
  state: inherit
```

To explicitly disable encryption:

```yaml
backupEncryption:
  state: disabled
```

If the field is omitted, the behavior is equivalent to:

```text
state = inherit
```

---

# Volume Configuration

A Volume may also:

```text
inherit
disabled
enabled
```

Example:

```yaml
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: database-volume
  namespace: longhorn-system
spec:
  backupEncryption:
    state: enabled
    keyProvider: secret
    secretName: database-backup-encryption
```

A Volume can explicitly opt out:

```yaml
spec:
  backupEncryption:
    state: disabled
```

If the field is omitted:

```text
state = inherit
```

---

# Complete Policy Inheritance

Encryption configuration is inherited as a complete policy.

It is not inherited field by field.

For example:

```text
Global:
    state: enabled
    secret: global-key

BackupTarget:
    state: inherit
```

The BackupTarget inherits:

```text
enabled
+
global-key
```

However:

```text
Global:
    state: enabled
    secret: global-key

BackupTarget:
    state: enabled
```

does not automatically reuse `global-key`.

Once the BackupTarget explicitly enables encryption, it owns the complete encryption configuration and must specify its own valid key configuration.

The same rule applies to Volume.

This avoids ambiguous configurations where the encryption state comes from one level and the key configuration comes from another.

---

# Effective Configuration Resolution

Before a backup starts, Longhorn resolves the effective encryption policy.

Conceptually:

```go
func resolveBackupEncryption(
    volumePolicy *BackupEncryptionSpec,
    backupTargetPolicy *BackupEncryptionSpec,
    globalPolicy BackupEncryptionSpec,
) BackupEncryptionSpec {

    if volumePolicy != nil &&
        volumePolicy.State != BackupEncryptionStateInherit {
        return *volumePolicy
    }

    if backupTargetPolicy != nil &&
        backupTargetPolicy.State != BackupEncryptionStateInherit {
        return *backupTargetPolicy
    }

    return globalPolicy
}
```

Example:

```text
Global:
    enabled / global-key

BackupTarget:
    inherit

Volume:
    inherit
```

Effective:

```text
enabled / global-key
```

Another example:

```text
Global:
    enabled / global-key

BackupTarget:
    enabled / target-key

Volume:
    inherit
```

Effective:

```text
enabled / target-key
```

Another example:

```text
Global:
    enabled

BackupTarget:
    enabled

Volume:
    disabled
```

Effective:

```text
disabled
```

---

# API and CRD Changes

## Common API Type

Introduce a reusable configuration structure.

Conceptually:

```go
type BackupEncryptionState string

const (
    BackupEncryptionStateInherit  BackupEncryptionState = "inherit"
    BackupEncryptionStateDisabled BackupEncryptionState = "disabled"
    BackupEncryptionStateEnabled  BackupEncryptionState = "enabled"
)
```

And:

```go
type BackupEncryptionSpec struct {
    State BackupEncryptionState `json:"state,omitempty"`

    KeyProvider string `json:"keyProvider,omitempty"`

    SecretName string `json:"secretName,omitempty"`
}
```

The exact Go naming should follow Longhorn API conventions.

---

# BackupTarget CRD Changes

Add:

```go
type BackupTargetSpec struct {
    BackupTargetURL  string `json:"backupTargetURL"`
    CredentialSecret string `json:"credentialSecret,omitempty"`

    ...

    BackupEncryption *BackupEncryptionSpec `json:"backupEncryption,omitempty"`
}
```

Existing BackupTarget resources do not contain this field.

They are interpreted as:

```text
state = inherit
```

This preserves backward compatibility.

---

# Volume CRD Changes

Add:

```go
type VolumeSpec struct {
    ...

    BackupEncryption *BackupEncryptionSpec `json:"backupEncryption,omitempty"`
}
```

Existing Volume resources are interpreted as:

```text
state = inherit
```

---

# Backup CRD Changes

The Backup CR needs to record the effective encryption information used when that backup was created.

Current Volume, BackupTarget, or Global configuration must not be treated as the source of truth for an existing backup because those settings may change later.

Conceptually:

```go
type BackupEncryptionStatus struct {
    Enabled       bool   `json:"enabled,omitempty"`
    FormatVersion string `json:"formatVersion,omitempty"`
    Algorithm     string `json:"algorithm,omitempty"`
    KeyProvider   string `json:"keyProvider,omitempty"`
    KeyID         string `json:"keyID,omitempty"`
}
```

Add it to Backup status:

```go
type BackupStatus struct {
    ...

    Encryption *BackupEncryptionStatus `json:"encryption,omitempty"`
}
```

Example:

```yaml
status:
  encryption:
    enabled: true
    formatVersion: "1"
    algorithm: AES-256-GCM-DARE
    keyProvider: secret
    keyID: production-backup-key
```

Only non-sensitive information is stored.

The encryption key is never included in Backup status.

---

# BackupVolume CRD

Encryption configuration must not be inferred only from `BackupVolume`.

Different backups belonging to the same backup volume may have different encryption histories.

For example:

```text
backup-1:
    unencrypted

backup-2:
    key-A

backup-3:
    key-B
```

Therefore, the individual Backup metadata is authoritative.

If useful for the UI, BackupVolume may expose summary information such as whether encrypted backups exist, but it must not represent one encryption configuration as applying to all backups.

---

# Admission and Validation Changes

The admission webhook and controllers must validate the new configuration.

## Global Validation

When global encryption is enabled:

* the key provider must be supported;
* a Secret must be configured;
* the Secret must contain valid key information.

---

## BackupTarget Validation

Valid states:

```text
inherit
disabled
enabled
```

When explicitly enabled:

* the BackupTarget must use the S3 backupstore driver;
* the key provider must be supported;
* the configured Secret must be valid.

If encryption is enabled for a non-S3 target:

```text
client-side backup encryption is currently supported only for S3 backup targets
```

The effective policy must also be validated before backup execution because inherited global configuration can change after the BackupTarget was created.

---

## Volume Validation

The Volume webhook validates the encryption-policy structure.

For example:

```text
state = enabled
```

requires valid key-provider configuration.

The S3 BackupTarget compatibility is validated when an actual backup operation resolves the target.

---

# Client-Side Encryption Design

## Backup Flow

The backup pipeline is:

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
Existing S3 backupstore
    |
    v
Remote object storage
```

Encryption happens after compression.

Compressing ciphertext would provide little or no useful compression.

---

# Restore Flow

Restore performs the reverse processing:

```text
Remote object storage
    |
    v
Existing S3 backupstore
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

The encrypted data must be authenticated before it is accepted.

Modified or corrupted encrypted data must result in a restore failure.

---

# Encryption Algorithm

The implementation must use authenticated encryption.

The current candidate is:

```text
Content encryption:
    AES-256 authenticated encryption

Streaming format:
    DARE

Candidate library:
    github.com/minio/sio
```

The exact implementation should be validated through a POC before the persistent encryption format is finalized.

Authenticated encryption is required so Longhorn can detect:

* ciphertext modification;
* corruption;
* truncation;
* incorrect keys;
* invalid encrypted chunks.

AES-CTR without an authentication mechanism is not sufficient.

---

# Why Streaming Encryption

Backup objects can be large.

The encryption implementation must not require Longhorn to load an entire backup object into memory.

The desired processing model is:

```text
Reader
   |
   v
Compression
   |
   v
Streaming encryption
   |
   v
S3 upload
```

And for restore:

```text
S3 download
   |
   v
Streaming decryption
   |
   v
Decompression
   |
   v
Writer
```

The POC must verify compatibility with the existing backupstore reader/writer requirements.

---

# Key Management

## Initial Key Provider

The initial key provider is a Kubernetes Secret.

Example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: longhorn-backup-encryption
  namespace: longhorn-system
type: Opaque
stringData:
  keyID: backup-key-2026-01
data:
  key: <base64-encoded-key>
```

`keyID` is non-sensitive.

It identifies the encryption context used for a backup.

The actual encryption key is sensitive and must never be exposed.

---

# Envelope Encryption

The design uses envelope encryption.

The Kubernetes Secret contains a Key Encryption Key, or KEK.

For each encrypted object, Longhorn generates a random Data Encryption Key, or DEK.

The DEK encrypts the backup payload.

The KEK wraps the DEK.

Conceptually:

```text
Kubernetes Secret
       |
       | KEK
       v
+------------------+
|    Wrap DEK      |
+------------------+
       ^
       |
Random DEK
       |
       +----------------------------+
       |                            |
       v                            v
Encrypt backup data           Wrapped DEK
                                   |
                                   v
                             Backup metadata
```

The plaintext KEK is never stored in the backup store.

The plaintext DEK is never persisted either.

Only the wrapped DEK is stored with the encrypted object.

---

# Key Provider Abstraction

Although the initial implementation uses a Kubernetes Secret, key management should use an abstraction so a future enhancement can support an external KMS.

Conceptually:

```go
type DataKeyProvider interface {
    GenerateDataKey(
        ctx context.Context,
    ) (
        plaintextKey []byte,
        encryptedKey []byte,
        keyID string,
        err error,
    )

    DecryptDataKey(
        ctx context.Context,
        encryptedKey []byte,
        keyID string,
    ) (
        []byte,
        error,
    )
}
```

Initial implementation:

```text
DataKeyProvider
    |
    +-- KubernetesSecretKeyProvider
```

Possible future providers:

```text
AWS KMS
Vault
other KMS providers
```

External KMS implementation itself is outside the scope of this LEP.

---

# Encrypted Object Format

To avoid creating an unnecessary Longhorn-specific binary container, the encrypted object can use a standard archive/container format together with explicit JSON metadata.

A possible representation is:

```text
encrypted-object.tar
|
+-- metadata.json
|
+-- data.enc
```

Example `metadata.json`:

```json
{
  "version": 1,
  "algorithm": "AES-256-GCM-DARE",
  "keyProvider": "secret",
  "keyID": "backup-key-2026-01",
  "wrappedDEK": "...",
  "keyWrapAlgorithm": "...",
  "keyWrapMetadata": {}
}
```

`data.enc` contains the encrypted data stream.

The metadata may include:

* encryption-format version;
* algorithm;
* key-provider identifier;
* key ID;
* wrapped DEK;
* key-wrapping algorithm;
* non-sensitive information required to unwrap the DEK.

The metadata must not contain:

* plaintext KEK;
* plaintext DEK;
* Kubernetes Secret contents.

The exact archive format should be finalized only after validating its interaction with:

* streaming;
* multipart uploads;
* retries;
* backupstore Read/Write APIs;
* incremental backup data paths.

---

# Encryption Metadata Authentication

Encryption metadata affects how ciphertext is decrypted.

Therefore, metadata that affects cryptographic processing must not be silently modifiable.

The implementation must ensure that security-sensitive metadata is either:

* cryptographically authenticated together with the encrypted content; or
* included as authenticated associated data where supported.

For example, changing:

```text
algorithm
key ID
wrapped DEK
format information
```

must not allow encrypted data to be accepted incorrectly.

---

# S3 Integration

Longhorn should continue using the existing S3 backupstore implementation.

The encryption layer should sit above the S3 transport.

Conceptually:

```text
Longhorn backup logic
        |
        v
Client-side encryption
        |
        v
Existing S3 backupstore
        |
        v
AWS S3 / MinIO / S3-compatible storage
```

There should not be another S3 SDK introduced specifically for encryption.

The existing S3 implementation remains responsible for:

* credentials;
* endpoint configuration;
* path-style access;
* retries;
* multipart uploads;
* provider compatibility;
* object operations.

The encryption layer only transforms plaintext into ciphertext and back.

---

# S3-Compatible Providers

Client-side encryption is intentionally implemented independently from the provider.

Conceptually:

```text
                 Client-side encryption
                           |
                           v
                  Existing S3 client
                           |
          +----------------+----------------+
          |                |                |
          v                v                v
       AWS S3           MinIO          GCS S3
                                      compatible
                                       endpoint
```

The remote storage service sees ordinary object data, but that object data is encrypted before upload.

Therefore, the provider does not need to understand Longhorn's encryption format.

Provider-specific S3 compatibility concerns such as multipart behavior and checksums remain the responsibility of the existing S3 backupstore.

AWS S3 and MinIO should be included in the primary E2E test matrix.

Existing supported S3-compatible providers should be regression-tested where practical.

---

# Backup Metadata

The effective encryption information used when creating the backup must be recorded with the remote backup metadata.

For example:

```json
{
  "encryption": {
    "enabled": true,
    "formatVersion": "1",
    "algorithm": "AES-256-GCM-DARE",
    "keyProvider": "secret",
    "keyID": "backup-key-2026-01"
  }
}
```

The effective policy is persisted because the current configuration can later change.

For example:

```text
Backup 1:
    key-A

Configuration changed

Backup 2:
    key-B
```

Backup 1 must continue to identify that it requires key-A.

Backup 2 identifies key-B.

Restore must not infer this information from the current Volume or BackupTarget configuration.

---

# Backup Creation Behavior

Before starting a backup:

1. Determine the BackupTarget.
2. Read the global backup-encryption policy.
3. Read the BackupTarget policy.
4. Read the Volume policy.
5. Resolve:

```text
Volume > BackupTarget > Global
```

6. Validate the effective configuration.
7. If encryption is enabled, verify the target uses the S3 backupstore.
8. Load the required key configuration.
9. Perform the backup.

---

## Encryption Disabled

The current backup behavior is unchanged:

```text
Backup data
    |
    v
Compression
    |
    v
S3 upload
```

---

## Encryption Enabled

The backup flow becomes:

```text
Backup data
    |
    v
Compression
    |
    v
Client-side encryption
    |
    v
S3 upload
```

Longhorn records the encryption metadata with the backup.

---

# Restore Behavior

Restore uses the encryption metadata belonging to the backup.

It does not use the current effective backup-encryption policy to determine whether the backup is encrypted.

Conceptually:

```text
Backup metadata
      |
      v
Encrypted?
   /     \
 no       yes
 |         |
 v         v
Normal    Resolve key
restore       |
              v
          Decrypt
              |
              v
           Restore
```

For an encrypted backup:

1. Read the encryption metadata.
2. Determine the encryption format and key ID.
3. Locate the required key-provider configuration.
4. Load the required key.
5. Unwrap the DEK.
6. Authenticate and decrypt the encrypted data.
7. Decompress the result.
8. Restore the volume.

If the required key is unavailable:

```text
required backup encryption key "backup-key-2026-01" is unavailable
```

If authentication fails:

```text
failed to decrypt backup data: authentication failed
```

Longhorn must not attempt to interpret authentication-failed ciphertext as plaintext.

---

# Backup Synchronization

A single BackupTarget may contain backups created using different policies over time.

For example:

```text
Backup 1:
    unencrypted

Backup 2:
    encrypted with key-A

Backup 3:
    encrypted with key-B
```

During synchronization, Longhorn must use each backup's remote metadata to determine its encryption requirements.

The current BackupTarget encryption configuration does not describe historical backups.

---

# Incremental Backup and Encryption Context

This is an important design consideration.

Longhorn incremental backups reuse unchanged blocks where possible.

Different client-side encryption keys create different encryption contexts.

For example:

```text
Backup A:
    keyID = key-A

Backup B:
    keyID = key-B
```

A block encrypted under key-A must not be assumed to be reusable by a backup that only has access to key-B.

Therefore, Longhorn must ensure backup-block reuse only occurs when the encryption contexts are compatible.

One possible design is to isolate blocks by encryption context.

Conceptually:

```text
backup blocks
    |
    +-- encryption-context-key-A/
    |       |
    |       +-- block-1
    |       +-- block-2
    |
    +-- encryption-context-key-B/
            |
            +-- block-1
            +-- block-3
```

The exact object-path or identity mechanism should be determined during the POC.

The required behavior is:

> A backup object encrypted with one client-side encryption context must not be reused by another backup unless that backup can correctly decrypt the same encryption context.

Backups using the same encryption context can continue to benefit from block reuse.

---

# Encryption Key Changes

Changing the configured key does not modify existing backups.

Example:

```text
Backup 1:
    key-A

Backup 2:
    key-A

Change configuration to key-B

Backup 3:
    key-B
```

Backup 1 and Backup 2 still require key-A.

Backup 3 requires key-B.

Users must retain key-A as long as backups depending on key-A remain in the backup store.

Automatic re-encryption of existing backups is outside the scope of this enhancement.

Changing the actual key material while keeping the same key ID is unsupported and should be documented as unsafe.

A new encryption key should use a new key ID.

---

# Key Loss

If a client-side encryption key is lost, backups encrypted using that key cannot be recovered.

Longhorn cannot generate a replacement key for those existing backups.

The UI and documentation must clearly warn users:

> Losing the backup encryption key permanently prevents Longhorn from restoring backups encrypted with that key. Keep backup encryption keys securely as part of the disaster-recovery procedure.

---

# Secret Handling

Encryption Secret data must never be:

* logged;
* written to Backup CR status;
* written to Volume status;
* written to BackupTarget status;
* stored as plaintext in remote backup metadata;
* emitted in Kubernetes Events;
* exposed by UI APIs;
* included as plaintext in support bundles.

Errors may identify:

* Secret name;
* key ID;
* key provider.

They must not include the key contents.

For example:

```text
failed to load backup encryption key "backup-key-2026-01"
from Secret "longhorn-backup-encryption"
```

---

# Failure Handling

Encryption must fail closed.

If encryption is enabled and Longhorn cannot satisfy the encryption requirement, the backup must fail.

Longhorn must never silently fall back to plaintext backup.

---

## Missing Secret

Example:

```text
client-side backup encryption is enabled but
Secret "longhorn-backup-encryption" was not found
```

The backup does not start.

---

## Invalid Key

Example:

```text
invalid client-side backup encryption key
```

The backup does not start.

---

## Non-S3 BackupTarget

Example:

```text
client-side backup encryption is currently supported only for S3 backup targets
```

---

## Incorrect Restore Key

Example:

```text
failed to decrypt backup object:
authentication failed
```

No plaintext fallback occurs.

---

## Corrupted Ciphertext

Example:

```text
failed to decrypt backup object:
ciphertext authentication failed
```

---

## Unsupported Format

Example:

```text
unsupported Longhorn backup encryption format version
```

---

# Backward Compatibility

## Existing Global Configuration

The new global setting defaults to:

```text
disabled
```

Therefore, upgrading does not automatically enable encryption.

---

## Existing BackupTarget CRs

Existing BackupTarget CRs do not contain the new encryption field.

They behave as:

```text
state = inherit
```

---

## Existing Volume CRs

Existing Volume CRs also behave as:

```text
state = inherit
```

---

## Existing Backups

Legacy backup metadata does not contain client-side encryption information.

Such backups are treated as:

```text
encryption disabled
```

No existing backup data is automatically changed.

---

# Mixed Backup History

After encryption is enabled, a backup target may contain:

```text
backup-1:
    legacy plaintext

backup-2:
    encrypted / key-A

backup-3:
    encrypted / key-A

backup-4:
    encrypted / key-B
```

Longhorn must correctly synchronize and restore each supported format.

---

# Upgrade

During an upgrade:

* add the new Setting definitions;
* add BackupTarget CRD fields;
* add Volume CRD fields;
* add Backup status fields;
* update generated CRD YAML;
* update deep-copy and generated client code;
* preserve existing CR behavior through inheritance;
* leave global encryption disabled;
* do not rewrite existing backups.

No backup data migration is required.

---

# Downgrade

Longhorn versions released before this feature will not understand the new client-side encrypted backup format.

Therefore, encrypted backups created by a newer Longhorn version may not be restorable after downgrade.

Downgrading does not automatically decrypt encrypted backup objects.

This limitation must be documented in release notes.

---

# Implementation Overview

## longhorn-manager

Responsibilities:

* introduce global backup-encryption settings;
* validate the global configuration;
* handle BackupTarget encryption configuration;
* handle Volume encryption configuration;
* resolve effective encryption policy using:

```text
Volume > BackupTarget > Global
```

* load the required Secret securely;
* validate S3 compatibility;
* pass the effective configuration to the backup process;
* expose non-sensitive encryption information;
* synchronize encrypted backups;
* return sanitized errors.

---

## longhorn-engine / Backup Process

Responsibilities:

* receive the resolved encryption configuration;
* perform encryption/decryption;
* generate DEKs;
* wrap/unwrap DEKs;
* generate/read encryption metadata;
* preserve incremental backup semantics;
* prevent incompatible encryption-context block reuse;
* fail restore when the required key is unavailable.

---

## backupstore

The S3 backupstore continues to handle S3 operations.

Conceptually:

```text
Current:

Backup data
    |
    v
S3 backupstore


New:

Backup data
    |
    v
Encryption layer
    |
    v
S3 backupstore
```

For restore:

```text
S3 backupstore
    |
    v
Decryption layer
    |
    v
Backup data
```

The POC must validate the interaction with:

* `Read`;
* `Write`;
* `Upload`;
* `Download`;
* reader seek requirements;
* retries;
* multipart uploads.

---

# UI Changes

## Global Setting

Add:

```text
Client-Side Backup Encryption

Enabled:
    Yes / No

Key Provider:
    Kubernetes Secret

Encryption Secret:
    <secret-name>
```

---

## BackupTarget

Add:

```text
Client-Side Backup Encryption

State:
    Inherit Global
    Disabled
    Enabled
```

When enabled:

```text
Key Provider:
    Kubernetes Secret

Encryption Secret:
    <secret-name>
```

---

## Volume

Add:

```text
Client-Side Backup Encryption

State:
    Inherit
    Disabled
    Enabled
```

When enabled, the Volume can specify its own encryption key configuration.

The UI should show both configured and effective policies.

Example:

```text
Configured:
    Inherit

Effective:
    Enabled

Source:
    BackupTarget/default

Key ID:
    production-key
```

The actual key must never be displayed.

---

# Test Plan

## Unit Tests - Configuration Resolution

Test:

```text
Volume:
    inherit

BackupTarget:
    inherit

Global:
    disabled
```

Expected:

```text
disabled
```

Test:

```text
Volume:
    inherit

BackupTarget:
    inherit

Global:
    enabled
```

Expected:

```text
enabled
```

Test:

```text
Volume:
    inherit

BackupTarget:
    enabled

Global:
    disabled
```

Expected:

```text
enabled
```

Test:

```text
Volume:
    disabled

BackupTarget:
    enabled

Global:
    enabled
```

Expected:

```text
disabled
```

Test:

```text
Volume:
    enabled

BackupTarget:
    disabled

Global:
    disabled
```

Expected:

```text
enabled
```

Verify:

```text
Volume > BackupTarget > Global
```

---

# Unit Tests - CRDs

Verify valid states:

```text
inherit
disabled
enabled
```

Verify:

* omitted Volume field behaves as inherit;
* omitted BackupTarget field behaves as inherit;
* Global defaults to disabled;
* enabled state requires key configuration;
* unsupported key providers are rejected;
* non-S3 effective configuration is rejected before backup;
* CRD serialization/deserialization preserves the new fields.

---

# Unit Tests - Encryption

Verify:

* plaintext can be encrypted;
* ciphertext decrypts to the original plaintext;
* ciphertext does not contain the original plaintext;
* encrypting the same plaintext multiple times uses appropriate randomness;
* zero-length input is handled;
* small input is handled;
* large streaming input is handled;
* modified ciphertext fails authentication;
* truncated ciphertext fails;
* reordered encrypted data fails where applicable;
* incorrect DEK fails;
* incorrect KEK fails;
* invalid wrapped DEK fails;
* unsupported format version fails;
* unsupported algorithm fails.

---

# Unit Tests - Key Handling

Verify:

* valid key succeeds;
* malformed key fails;
* missing Secret fails;
* invalid Secret data fails;
* missing key ID fails if required;
* old key and new key are distinguishable;
* key material never appears in errors;
* key material never appears in logs.

---

# Unit Tests - S3 Integration

With encryption disabled:

```text
Write -> normal S3 object
Read  -> original data
```

With encryption enabled:

```text
Write -> encrypted S3 object
Read  -> original data after decryption
```

Verify:

* normal upload;
* multipart upload;
* retries;
* read;
* deletion;
* backup metadata operations;
* existing provider-specific fallback paths.

---

# Automated E2E Tests

## Test 1 - Existing Behavior

1. Install Longhorn.
2. Leave global backup encryption disabled.
3. Create a Volume.
4. Write known data.
5. Create backup.
6. Restore.
7. Verify checksum.

Expected:

Existing behavior is unchanged.

---

## Test 2 - Global Encryption

1. Enable global backup encryption.
2. Configure encryption Secret.
3. Leave BackupTarget as inherit.
4. Leave Volume as inherit.
5. Create backup.
6. Inspect remote data.
7. Restore.
8. Verify checksum.

Expected:

The remote backup payload is encrypted.

---

## Test 3 - BackupTarget Override

Configure:

```text
Global:
    disabled

BackupTarget:
    enabled

Volume:
    inherit
```

Verify the backup is encrypted.

---

## Test 4 - Volume Override

Configure:

```text
Global:
    disabled

BackupTarget:
    disabled

Volume:
    enabled
```

Verify the backup is encrypted.

---

## Test 5 - Volume Opt-Out

Configure:

```text
Global:
    enabled

BackupTarget:
    inherit

Volume:
    disabled
```

Verify the backup remains unencrypted.

---

## Test 6 - Incremental Backup

1. Create initial data.
2. Create backup A.
3. Modify a small amount of data.
4. Create backup B.
5. Verify unchanged blocks are reused when the encryption context matches.
6. Restore backup A.
7. Verify data.
8. Restore backup B.
9. Verify data.

---

## Test 7 - Different Encryption Keys

1. Create backup A using key-A.
2. Change the effective configuration to key-B.
3. Create backup B.
4. Verify backup A remains associated with key-A.
5. Verify backup B is associated with key-B.
6. Verify blocks are not incorrectly reused across incompatible encryption contexts.
7. Restore both backups using the corresponding keys.

---

## Test 8 - Missing Key

1. Create encrypted backup.
2. Remove the encryption Secret.
3. Attempt restore.

Expected:

Restore fails with a clear missing-key error.

---

## Test 9 - Incorrect Key

1. Create encrypted backup with key-A.
2. Replace configuration with key-B.
3. Attempt restore without key-A.

Expected:

Authentication/decryption fails.

No plaintext fallback occurs.

---

## Test 10 - Corrupted Ciphertext

1. Create encrypted backup.
2. Modify encrypted object data directly in S3.
3. Attempt restore.

Expected:

Authenticated decryption detects corruption and restore fails.

---

## Test 11 - Disaster Recovery

1. Create encrypted backups in cluster A.
2. Remove cluster A.
3. Install Longhorn in cluster B.
4. Configure the same S3 BackupTarget.
5. Restore the required encryption Secret.
6. Synchronize backups.
7. Restore the Volume.
8. Verify checksum.

---

## Test 12 - AWS S3

Verify:

* encrypted backup;
* encrypted restore;
* multipart upload;
* incremental backup;
* backup synchronization;
* backup deletion.

---

## Test 13 - MinIO

Repeat the applicable E2E tests using MinIO.

Verify:

* encrypted backup;
* encrypted restore;
* multipart behavior;
* incremental backup;
* synchronization;
* deletion.

---

## Test 14 - Other Existing S3-Compatible Providers

Regression-test currently supported S3-compatible providers where practical.

Client-side encryption should not introduce provider-specific encryption requirements because the provider only stores ciphertext.

---

## Test 15 - Upgrade

1. Install an older Longhorn release.
2. Create an unencrypted backup.
3. Upgrade Longhorn.
4. Verify the old backup remains visible.
5. Restore it.
6. Enable client-side encryption.
7. Create a new encrypted backup.
8. Restore it.

---

## Test 16 - Mixed Backup History

Create:

```text
backup-1:
    unencrypted

backup-2:
    encrypted / key-A

backup-3:
    encrypted / key-B
```

Verify:

* all backups are synchronized;
* each backup reports the correct encryption status;
* each backup can be restored with its required configuration.

---

# Manual Security Test

Write a known plaintext pattern into a Volume.

Create a client-side encrypted backup.

Download the remote S3 backup data without using Longhorn.

Verify the known plaintext cannot be found.

Inspect:

* longhorn-manager logs;
* engine logs;
* Kubernetes Events;
* Volume CR;
* BackupTarget CR;
* Backup CR;
* support bundle.

Verify encryption keys are not exposed.

---

# Performance Test

Compare:

```text
Unencrypted backup
vs.
Client-side encrypted backup
```

And:

```text
Unencrypted restore
vs.
Client-side encrypted restore
```

Measure:

* throughput;
* CPU usage;
* memory usage;
* backup duration;
* restore duration;
* remote object size.

The implementation should remain streaming and must not require memory proportional to the size of the entire backup object.

---

# Security Considerations

Client-side encryption changes the trust boundary.

Without client-side encryption:

```text
Longhorn
   |
   v
S3 provider receives backup payload
```

With client-side encryption:

```text
Longhorn
   |
   v
Encrypt locally
   |
   v
S3 provider receives ciphertext
```

This protects backup payload confidentiality from the remote object-storage provider.

Authenticated encryption also protects integrity by detecting modified ciphertext.

The feature does not hide:

* bucket names;
* object names;
* object sizes;
* timestamps;
* access patterns.

The feature also cannot protect data if both the encryption key and encrypted backup data are compromised.

---

# Risks and Mitigations

## Key Loss

### Risk

The user loses the encryption key.

### Impact

Encrypted backups cannot be restored.

### Mitigation

Provide clear UI and documentation warnings.

Document key backup as part of disaster-recovery procedures.

---

## Different Keys and Incremental Backups

### Risk

A block encrypted under one encryption context is incorrectly reused by another backup.

### Impact

The backup may not be restorable.

### Mitigation

Make encryption context part of the block-reuse decision or backup-block namespace.

Validate the final design during the POC.

---

## Configuration Complexity

### Risk

Users may not know which configuration is effective because the feature has three configuration levels.

### Mitigation

Use explicit:

```text
inherit
disabled
enabled
```

states.

Show configured value, effective value, and policy source in the UI.

Use complete-policy inheritance rather than field-level inheritance.

---

## Secret Replacement

### Risk

The encryption Secret is overwritten with another key while old backups still depend on the original key.

### Impact

Old backups may become unrestorable.

### Mitigation

Use a key ID.

Require a new key ID for a new key.

Document that users must retain old keys until dependent backups are removed.

---

## Persistent Format Compatibility

### Risk

Future changes to encryption implementation make existing encrypted backups unreadable.

### Mitigation

Use a versioned encryption format.

Treat the encrypted backup format as a persistent compatibility contract.

---

# Documentation

Documentation must cover:

* purpose of client-side backup encryption;
* difference from Longhorn volume encryption;
* configuration hierarchy;
* Global configuration;
* BackupTarget configuration;
* Volume configuration;
* `Volume > BackupTarget > Global` precedence;
* `inherit`, `disabled`, and `enabled`;
* creating the encryption Secret;
* key requirements;
* key ID requirements;
* disaster recovery;
* restoring into another cluster;
* key-loss consequences;
* key-change behavior;
* incremental backup considerations;
* S3-compatible provider support;
* upgrade behavior;
* downgrade limitation.

The documentation must clearly state:

> Server-side encryption is outside the scope of this enhancement.

---

# Rollout Plan

## Phase 1 - POC

Validate:

* streaming encryption/decryption;
* selected encryption library;
* encrypted-object format;
* JSON metadata/container approach;
* metadata authentication;
* multipart upload;
* retry behavior;
* backupstore `Read` and `Write`;
* incremental backup block reuse;
* multiple encryption contexts;
* AWS S3;
* MinIO.

The POC should resolve the backup-block encryption-context design before the persistent format is finalized.

---

## Phase 2 - API and CRDs

Implement:

* common backup-encryption API types;
* Volume CRD changes;
* BackupTarget CRD changes;
* Backup status changes;
* global settings;
* admission validation;
* generated clients;
* deep-copy changes;
* CRD YAML changes.

---

## Phase 3 - Key Management

Implement:

* key-provider abstraction;
* Kubernetes Secret key provider;
* key validation;
* DEK generation;
* DEK wrapping and unwrapping;
* key ID handling;
* secure Secret handling.

---

## Phase 4 - Encryption Integration

Implement:

* streaming encryption;
* streaming authenticated decryption;
* encryption metadata;
* backupstore integration;
* backup synchronization;
* restore behavior;
* incremental backup encryption-context isolation.

---

## Phase 5 - Manager and UI

Implement:

* effective-policy resolution;
* Global configuration;
* BackupTarget configuration;
* Volume configuration;
* effective-policy display;
* error handling;
* key-loss warnings.

---

## Phase 6 - Tests and Documentation

Complete:

* unit tests;
* E2E tests;
* AWS S3 validation;
* MinIO validation;
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

Backup store scope:
    S3 and S3-compatible targets only

Server-side encryption:
    Out of scope

Configuration levels:
    Global
    BackupTarget
    Volume

Precedence:
    Volume > BackupTarget > Global

Configuration states:
    inherit
    disabled
    enabled

Global supported states:
    disabled
    enabled

Global default:
    disabled

BackupTarget default:
    inherit

Volume default:
    inherit

Inheritance:
    Complete encryption policy
    Not field-by-field

Encryption location:
    Longhorn client side
    Before S3 upload
    After compression

Encryption requirement:
    Authenticated encryption

Streaming encryption candidate:
    minio/sio / DARE

Initial key provider:
    Kubernetes Secret

Future key providers:
    External KMS providers
    Separate follow-up enhancement

Key design:
    User KEK
       |
       v
    wrapped per-object DEK
       |
       v
    encrypted backup payload

Plaintext KEK in backup:
    Never

Plaintext DEK in backup:
    Never

Backup metadata:
    Versioned encryption information
    Key ID
    Wrapped DEK where required

S3 transport:
    Existing Longhorn S3 implementation

Existing backups:
    Supported unchanged

Existing Volume CR:
    inherit

Existing BackupTarget CR:
    inherit

Effective encryption:
    Resolved when backup is created

Restore:
    Uses the encryption metadata of the backup
    rather than the current policy

Incremental backups:
    Reuse blocks only across compatible
    encryption contexts

Key changes:
    Do not modify existing backups

Failure behavior:
    Fail closed
    Never silently create plaintext backup

Primary interoperability tests:
    AWS S3
    MinIO
```
