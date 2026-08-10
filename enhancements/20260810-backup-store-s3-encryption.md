# Client-Side Encryption for S3 Volume Backups

## Summary

Longhorn currently supports volume encryption inside the Kubernetes cluster. When an encrypted volume is backed up, the backup data stored in the remote backup target is also protected because the source volume data is already encrypted.

However, this couples backup-at-rest encryption to in-cluster volume encryption. Users who do not need or do not want the runtime overhead and operational complexity of encrypted Longhorn volumes cannot independently protect their remote backups with client-side encryption.

This enhancement introduces **client-side encryption for Longhorn S3 backups**, independent of Longhorn in-cluster volume encryption.

When enabled, Longhorn encrypts backup data locally before sending it to the S3 or S3-compatible backup target and decrypts it locally while restoring. The S3 provider only receives encrypted data and does not receive the encryption key.

The feature is disabled by default to preserve the existing behavior.

The initial implementation supports:

* S3 and S3-compatible backup targets only.
* Client-side authenticated encryption using AES-256.
* Encryption keys stored in a Kubernetes Secret.
* Transparent backup, restore, backup listing, synchronization, and deletion.
* Existing unencrypted backups without migration.
* AWS S3 and MinIO interoperability.
* An extensible key-provider design so external KMS integration can be added later.

### Related Issues

* #5220 - Encrypt volume backup to remote backup store without in-cluster volume encryption
* #8453 - Backup encryption
* #12297 - Automated test coverage for backup encryption
* #4883 - Block volume encryption

---

## Motivation

Longhorn currently provides encryption at the volume level. This is useful when data must be encrypted on Longhorn storage nodes, but volume encryption and backup encryption serve different security requirements.

For example, a user might trust the storage nodes running inside their Kubernetes cluster but use an external S3-compatible provider for disaster-recovery backups.

In this case, enabling volume encryption solely to secure remote backups introduces unnecessary coupling.

Other applications commonly encrypt their backup data locally before sending it to object storage. Longhorn should provide the same option so users do not have to depend on storage-provider-specific server-side encryption or an additional encryption proxy.

Server-side encryption such as SSE-S3, SSE-KMS, or SSE-C does not completely address this use case because encryption is still implemented by the object-storage service. It may also differ between AWS S3 and other S3-compatible providers.

The intended security boundary for this enhancement is:

```text
Longhorn
   |
   | plaintext
   v
Compression
   |
   | compressed plaintext
   v
Client-side encryption
   |
   | ciphertext only
   v
S3 client
   |
   | ciphertext
   v
Remote S3 / S3-compatible storage
```

The remote backup provider must never need access to the plaintext backup payload or the Longhorn backup encryption key.

### Goals

1. Allow users to encrypt remote S3 backups without enabling Longhorn volume encryption.

2. Encrypt backup data before it leaves the Longhorn backup process.

3. Decrypt backup data only after it is downloaded from the remote backup target.

4. Use authenticated encryption so corruption or malicious modification of encrypted objects is detected.

5. Support a user-managed AES-256 key stored in a Kubernetes Secret.

6. Remain compatible with AWS S3 and S3-compatible storage such as MinIO.

7. Preserve Longhorn's existing incremental backup and block deduplication behavior.

8. Preserve compatibility with existing plaintext backups.

9. Keep encryption disabled by default.

10. Design the encryption metadata and key-provider abstraction so support for external KMS providers can be added without changing the encrypted data format unnecessarily.

11. Ensure encryption keys and plaintext key material are never written to backup-store objects, logs, events, Backup CRs, or support bundles.

### Non-goals

The following are outside the scope of the initial implementation:

* Client-side encryption for NFS, CIFS, Azure Blob, or other non-S3 backup targets.
* Changing Longhorn in-cluster volume encryption.
* SSE-S3, SSE-KMS, or SSE-C support as the implementation of this feature.
* Encrypting S3 object names, object sizes, timestamps, or other storage-provider-visible metadata.
* Automatic migration of existing plaintext backups to encrypted backups.
* Automatic migration of encrypted backups back to plaintext.
* In-place encryption-key rotation or re-encryption of existing backup data.
* Generic external KMS support in the first implementation.
* Recovering backups when the user has lost the encryption key.
* Allowing older Longhorn versions that do not understand this encryption format to restore encrypted backups.

---

## Proposal

### User Stories

#### User Story 1: Protect backups stored by an external provider

A user runs Longhorn on infrastructure they control and does not need encryption for the running Longhorn volume.

The user sends Longhorn backups to a third-party S3-compatible object-storage service.

The user wants Longhorn to encrypt the backup locally so the object-storage provider cannot access the original volume data.

The user enables client-side backup encryption on the BackupTarget and provides a Kubernetes Secret containing the encryption key.

Longhorn encrypts every new backup object before uploading it.

#### User Story 2: Separate volume and backup encryption policies

A user has different compliance requirements for production storage and disaster-recovery storage.

The Longhorn volume may be:

```text
unencrypted volume -> encrypted backup
```

or:

```text
encrypted volume -> independently encrypted backup
```

Backup encryption does not depend on whether Longhorn volume encryption is enabled.

#### User Story 3: Restore into another cluster

A disaster occurs and the original Kubernetes cluster is unavailable.

The administrator installs Longhorn in another cluster, configures the same S3 backup target, and creates the Kubernetes Secret containing the correct backup encryption key.

Longhorn discovers the encrypted backups and restores them transparently.

Without the correct encryption key, Longhorn reports that the backup is encrypted and cannot be restored.

#### User Story 4: Use MinIO or another S3-compatible provider

A user stores Longhorn backups in MinIO or another S3-compatible service.

Because encryption happens before data reaches the S3 API, the storage service does not need to implement Longhorn-specific encryption or SSE-C.

The existing S3 compatibility layer remains responsible only for storing and retrieving ciphertext objects.

---

## Analysis

### Existing Longhorn S3 implementation

Longhorn's `backupstore` already uses `aws-sdk-go-v2` for S3 operations. It also supports custom S3 endpoints using `AWS_ENDPOINTS` and configures path-style addressing when necessary for S3-compatible providers.

Therefore, this enhancement does not require replacing the existing S3 client.

The existing transport architecture should remain:

```text
Longhorn backupstore
        |
        +-- encryption/decryption layer
        |
        +-- existing aws-sdk-go-v2 S3 implementation
        |
        +-- AWS S3 / MinIO / S3-compatible provider
```

The current `BackupStoreDriver` exposes generic operations such as `Read`, `Write`, `Upload`, and `Download`, which makes it possible to place the encryption functionality between Longhorn's backup logic and the existing S3 implementation.

Longhorn's S3 implementation also already contains special compatibility handling for multipart uploads, single-part uploads, custom endpoints, path-style access, checksum behavior, and provider-specific S3 differences. The encryption feature should preserve this code rather than introduce another S3 transport implementation.

### Option 1: S3 server-side encryption

Examples include:

* SSE-S3
* SSE-KMS
* SSE-C

This is relatively simple to implement but does not satisfy the primary requirement.

With server-side encryption, Longhorn must trust the remote S3 implementation to correctly protect the data. It also introduces differences between S3 providers.

SSE-C additionally sends the customer-provided key to the storage server as part of each applicable request.

This option is therefore not selected as the solution for #5220.

Server-side encryption can be considered separately in the future.

### Option 2: `minio/sio`

`github.com/minio/sio` implements the Data At Rest Encryption (DARE) format.

The library provides streaming authenticated encryption and is explicitly intended for use cases including files, backups, and large object storage.

It supports authenticated encryption algorithms including AES-256-GCM and supports long streams without requiring the complete object to be held in memory.

Because the library operates on an `io.Reader`/`io.Writer` data stream rather than implementing the S3 protocol itself, the existing AWS SDK v2 S3 code remains unchanged.

The resulting architecture is:

```text
                    Longhorn backup logic
                             |
                             | compressed data
                             v
                    +------------------+
                    | Encryption layer |
                    |    minio/sio     |
                    +------------------+
                             |
                             | encrypted stream
                             v
                   Existing S3 backupstore
                    aws-sdk-go-v2
                             |
                  +----------+----------+
                  |                     |
                  v                     v
               AWS S3                MinIO
                                      / other
                                  S3-compatible
```

This is the proposed implementation approach.

---

## User Experience In Detail

### Enabling backup encryption

Encryption should be configured on the `BackupTarget`, because encryption is a property of the backup destination rather than of the running Longhorn volume.

A proposed configuration is:

```yaml
apiVersion: longhorn.io/v1beta2
kind: BackupTarget
metadata:
  name: default
  namespace: longhorn-system
spec:
  backupTargetURL: s3://backup-bucket@region/
  credentialSecret: longhorn-backup-credential
  clientSideEncryption: true
  encryptionSecret: longhorn-backup-encryption
```

The exact API field names can be adjusted during implementation.

When `clientSideEncryption` is false or omitted, Longhorn behaves exactly as it does today.

When `clientSideEncryption` is true:

1. The backup target must use the `s3` driver.
2. `encryptionSecret` must be specified.
3. The encryption Secret must exist and contain a valid 256-bit key.
4. Longhorn validates the configuration before allowing encrypted backup operations.

### Encryption Secret

Example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: longhorn-backup-encryption
  namespace: longhorn-system
type: Opaque
data:
  key: <base64-encoded-32-byte-key>
stringData:
  keyID: backup-key-2026-01
```

`key` contains exactly 32 bytes after base64 decoding.

`keyID` is a non-sensitive identifier used to identify which key was used for encryption. It can be stored with encrypted objects and exposed in Longhorn status information.

The actual key must never be stored in:

* BackupTarget status,
* Backup status,
* BackupVolume status,
* backup metadata,
* S3 object metadata in plaintext,
* logs,
* events,
* support bundles.

### BackupTarget-level configuration instead of per-volume configuration

The first version should configure encryption at the BackupTarget level.

This has several advantages:

* all backups written to the destination follow a consistent policy;
* key management is simpler;
* incremental backup blocks do not unexpectedly cross different encryption policies;
* disaster-recovery configuration is easier to understand;
* the BackupTarget is already responsible for the remote destination and its credential Secret.

A per-volume encryption override can be added in a later enhancement if there is sufficient demand.

---

## API Changes

### BackupTarget

Proposed additions to `BackupTargetSpec`:

```go
type BackupTargetSpec struct {
    BackupTargetURL      string
    CredentialSecret     string
    PollInterval         metav1.Duration

    // ClientSideEncryption enables encryption before data is uploaded
    // to the backup target.
    ClientSideEncryption bool

    // EncryptionSecret references the Secret containing the
    // backup encryption key.
    EncryptionSecret string
}
```

The actual Go structure must follow Longhorn API conventions.

### BackupTarget status

BackupTarget status should expose only non-sensitive information.

For example:

```yaml
status:
  available: true
  encryption:
    enabled: true
    algorithm: AES-256-GCM
    keyID: backup-key-2026-01
```

This allows users and support engineers to identify encryption configuration without exposing key material.

### Backup and BackupVolume

The backup status should indicate whether the remote backup is encrypted.

For example:

```yaml
status:
  encrypted: true
  encryptionKeyID: backup-key-2026-01
```

This information must also be persisted in the remote backup metadata so a new cluster can recognize encrypted backups.

---

## Design

### Encryption location

Encryption should be implemented inside the `backupstore` data path rather than in the S3 provider itself.

The order for backup processing should be:

```text
Volume data
    |
    v
Changed-block detection
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

Encryption must happen **after compression**.

Compressing ciphertext is ineffective and would increase backup size and processing cost.

Encryption must also happen after Longhorn has performed the calculations needed for incremental backup and block deduplication. Otherwise, randomized encryption could cause identical blocks to appear different and break the existing deduplication behavior.

Restore uses the reverse flow:

```text
S3 download
    |
    v
Client-side decryption/authentication
    |
    v
Decompression
    |
    v
Longhorn restore
```

### Encryption algorithm

The initial encrypted-object format uses:

```text
Content encryption: AES-256-GCM
Streaming format:    DARE
Key size:            256 bits
Implementation:      github.com/minio/sio
```

Authenticated encryption is required.

If ciphertext, authentication data, or block ordering has been modified, decryption must fail rather than return potentially corrupted plaintext.

### Key hierarchy

The Kubernetes Secret contains a Key Encryption Key (KEK).

Longhorn should not directly encrypt every backup object with the same key.

Instead, each encrypted object receives a randomly generated 256-bit Data Encryption Key (DEK).

Conceptually:

```text
Kubernetes Secret
      |
      | 256-bit KEK
      v
+------------------+
| Key wrapping     |
+------------------+
      |
      +-------------------------+
                                |
                     random 256-bit DEK
                                |
                                v
                      +------------------+
                      | AES-256-GCM/DARE |
                      +------------------+
                                |
                                v
                         Backup ciphertext
```

The plaintext DEK exists only in memory during encryption/decryption.

The DEK is wrapped using the KEK and the wrapped value is stored in the Longhorn encryption header.

This design provides a clean extension point for future KMS support.

For example:

```text
Secret provider:
    KEK from Kubernetes Secret
        -> wrap/unwrap DEK locally

Future KMS provider:
    External KMS
        -> generate/wrap/unwrap DEK
```

Both providers can produce the same encrypted backup payload format.

### Encrypted object format

Longhorn should add a small self-describing envelope before the DARE ciphertext.

Conceptually:

```text
+------------------------------------------------+
| Longhorn encryption magic                     |
| Format version                                 |
| Cipher / encryption format                    |
| Key provider                                   |
| Key ID                                         |
| Wrapped data-key length                        |
| Wrapped data key                               |
| Key-wrap nonce / required metadata             |
+------------------------------------------------+
|                                                |
| DARE encrypted data stream                     |
|                                                |
+------------------------------------------------+
```

For example:

```text
Magic:       LHBE
Version:     1
Algorithm:   AES-256-GCM-DARE
KeyProvider: secret
KeyID:       backup-key-2026-01
WrappedDEK:  ...
Ciphertext:  ...
```

The exact binary encoding should be defined in the implementation and documented so future Longhorn versions can maintain compatibility.

The header must contain no plaintext encryption key.

### Detecting encrypted and plaintext objects

Existing backup targets may contain plaintext objects.

Longhorn must therefore distinguish:

```text
Legacy plaintext object
```

from:

```text
Longhorn encrypted object
```

The encryption magic and format version provide this distinction.

On read:

1. Read enough bytes to inspect the Longhorn encryption header.
2. If the encryption magic is present, initialize the decrypting reader.
3. If the object is a known legacy plaintext object, process it using the existing path.
4. Never fall back to plaintext processing after authentication of an encrypted object fails.

Step 4 is important.

For example, if an encrypted object has been corrupted, Longhorn must return:

```text
failed to decrypt backup object: authentication failed
```

rather than attempting to interpret the corrupted ciphertext as a legacy plaintext object.

### Metadata encryption

Backup data blocks are not the only potentially sensitive information in the backup target.

Objects such as:

```text
volume.cfg
backup_*.cfg
```

can expose volume-related metadata.

Therefore, data written through the normal S3 `Write` path should also be encrypted when backup encryption is enabled.

Object names and directory/prefix structure remain visible. Encrypting S3 keys or directory layout is outside the scope of this enhancement.

### S3 integration

The encryption layer should wrap the existing input/output streams.

Conceptually:

```go
func (s *service) PutObject(...) {
    reader := originalReader

    if encryptionEnabled {
        reader = encryption.EncryptReader(originalReader)
    }

    // Existing aws-sdk-go-v2 upload path.
    upload(reader)
}
```

For read:

```go
func (s *service) GetObject(...) {
    reader := existingS3GetObject()

    if isEncrypted(reader) {
        return encryption.DecryptReader(reader)
    }

    return reader
}
```

The actual implementation needs to preserve the `io.ReadSeeker` requirements of the current `BackupStoreDriver.Write` and the retry behavior of the AWS SDK uploader.

If an encryption reader cannot provide seek semantics safely, the implementation can provide an encrypted temporary/spooled reader or introduce an encryption-aware wrapper before the final S3 call.

This must be covered by unit and S3 interoperability tests, especially multipart retry cases.

### Multipart uploads

Longhorn currently uses AWS SDK v2's uploader, which can switch to multipart upload for sufficiently large objects.

The encrypted stream must therefore continue to work through the existing multipart implementation.

Encryption is performed before the stream is divided into S3 multipart pieces:

```text
plaintext
   |
   v
compression
   |
   v
DARE encryption stream
   |
   v
+--------+--------+--------+
| part 1 | part 2 | part 3 |
+--------+--------+--------+
           |
           v
          S3
```

The remote provider only sees parts of one encrypted object.

The multipart boundary is an S3 transport detail and must not become part of the encryption format.

### Incremental backup compatibility

Longhorn backups reuse unchanged blocks between backup revisions.

Client-side encryption must not change the identity used by Longhorn to determine whether a block already exists.

For example:

```text
Backup 1:
    block A -> encrypt -> object A
    block B -> encrypt -> object B

Backup 2:
    block A unchanged -> reuse existing object A
    block C new       -> encrypt -> object C
```

Longhorn should not create a new randomized ciphertext object for block A merely because another backup references the same block.

This preserves the storage efficiency of incremental backups.

### Key changes

Changing the key while existing encrypted backups are present is dangerous because incremental backups can share blocks.

For the initial implementation, Longhorn should reject changing the effective encryption key for a BackupTarget containing encrypted backup data.

For example:

```text
Current target:
    encryption enabled
    keyID = key-A
    existing backups = yes

User changes:
    keyID = key-B

Result:
    reject configuration / mark BackupTarget unavailable
```

Users who need a new key can initially:

1. create/use another backup target or S3 prefix;
2. configure the new encryption key;
3. create new backups there;
4. retire the old target according to their retention policy.

Online key rotation and re-wrapping existing DEKs can be designed as a separate enhancement.

### Key loss

If the key is lost, encrypted backup data cannot be recovered.

The UI and documentation should clearly warn users about this.

For example:

> Losing the backup encryption key permanently prevents Longhorn from restoring backups encrypted with that key. Store the key securely outside the Longhorn cluster as part of the disaster-recovery plan.

Longhorn must not generate a replacement key automatically if the configured Secret disappears.

---

## External KMS Design

External KMS integration is not required for the first implementation, but the design must leave a clean extension point.

The encryption code should use a key-provider interface similar to:

```go
type DataKeyProvider interface {
    GenerateDataKey(ctx context.Context) (
        plaintextKey []byte,
        encryptedKey []byte,
        keyID string,
        err error,
    )

    DecryptDataKey(
        ctx context.Context,
        encryptedKey []byte,
        keyID string,
    ) ([]byte, error)
}
```

Initial implementation:

```text
DataKeyProvider
    |
    +-- KubernetesSecretKeyProvider
```

Possible future implementations:

```text
DataKeyProvider
    |
    +-- KubernetesSecretKeyProvider
    |
    +-- AWSKMSKeyProvider
    |
    +-- VaultKeyProvider
    |
    +-- other external KMS provider
```

This prevents the backup encryption format from being coupled directly to AWS KMS even though the backup destination is S3.

A user using MinIO should not be forced to use AWS KMS.

---

## Backup and Restore Behavior

### Backup

For every new object requiring encryption:

1. Load the effective backup-encryption configuration.
2. Validate the Secret and key.
3. Generate a cryptographically secure random DEK.
4. Wrap the DEK using the configured key provider.
5. Compress backup data using the existing Longhorn behavior.
6. Encrypt the compressed stream using the DEK.
7. Add the Longhorn encryption envelope.
8. Upload the encrypted object using the existing S3 implementation.
9. Clear temporary plaintext key material as soon as practical.
10. Record non-sensitive encryption information such as encryption version and key ID.

### Restore

For each object:

1. Download the object using the existing S3 client.
2. Inspect the object header.
3. Detect whether the object is encrypted.
4. Read the key provider and key ID.
5. Obtain the required KEK/KMS configuration.
6. Unwrap the DEK.
7. Authenticate and decrypt the encrypted stream.
8. Decompress the resulting backup data.
9. Restore the data using the existing Longhorn restore path.

A missing or incorrect key must result in a clear restore failure.

### Backup synchronization

BackupTarget synchronization must be able to discover encrypted backup volumes.

If reading backup configuration requires the encryption key and the Secret is unavailable, Longhorn should report the BackupTarget as unavailable or degraded with an explicit reason such as:

```text
BackupEncryptionKeyUnavailable
```

rather than reporting that the backup is corrupt or missing.

### Delete

Deletion is based primarily on S3 object keys and does not require plaintext object contents where possible.

Encrypted objects should be deleted using the existing S3 deletion implementation.

---

## Failure Handling

Longhorn must fail closed for encryption errors.

Examples include:

### Missing Secret

```text
backup encryption is enabled but Secret
"longhorn-backup-encryption" does not exist
```

### Invalid key length

```text
backup encryption key must contain exactly 32 bytes
```

### Wrong key

```text
failed to decrypt backup object:
authentication failed for encryption key "backup-key-2026-01"
```

### Corrupt object

```text
failed to decrypt backup object:
ciphertext authentication failed
```

### Unsupported encryption format

```text
backup uses unsupported encryption format version 2
```

### Unsupported backup target

```text
client-side backup encryption is supported only for S3 backup targets
```

Errors must never print:

* key contents;
* unwrapped DEKs;
* Secret data;
* KMS plaintext responses.

---

## Backward Compatibility

### Existing unencrypted backups

The feature is disabled by default.

Existing S3 backup targets and existing plaintext backups continue to work without modification.

Longhorn must continue to detect and restore legacy plaintext backup objects.

### Upgrade

Upgrading Longhorn does not automatically encrypt existing backups.

For example:

```text
Before upgrade:
    backup-1 -> plaintext

After upgrade and encryption enabled:
    backup-1 -> remains plaintext
    backup-2 -> encrypted
```

However, to avoid ambiguity and shared-block issues, enabling encryption for a BackupTarget containing existing backup data should initially require either:

* an empty/new S3 prefix, or
* explicit validation that the backup volume can safely use the selected policy.

The safest initial behavior is to recommend or require a new backup-target prefix when transitioning an existing target from plaintext to encrypted backups.

### Downgrade

Longhorn versions that predate this feature cannot restore the new encrypted backup format.

Documentation must clearly state this limitation.

Downgrading Longhorn does not decrypt existing backup objects.

---

## Security Considerations

### Threats addressed

The feature protects backup payloads against:

* unauthorized reading of objects from the S3 bucket;
* a compromised S3 storage provider reading Longhorn backup data;
* accidental exposure of backup objects;
* modification of encrypted backup data, because authenticated encryption detects tampering.

### Threats not addressed

The feature does not hide:

* bucket name;
* object names;
* Longhorn backup prefix layout;
* object sizes;
* modification timestamps;
* backup access patterns.

It also does not protect backup data if:

* the Kubernetes encryption Secret is compromised;
* the Longhorn process performing backup/restore is compromised;
* an attacker has access to both encrypted backup data and the encryption key.

### Key handling

Key material must:

* only be loaded when needed;
* never be logged;
* never be included in errors;
* never be persisted in CR status;
* never be included in support bundles as plaintext;
* be passed only to processes/components participating in backup or restore;
* use Kubernetes RBAC to restrict Secret access.

---

## Implementation Overview

### backupstore

Add a client-side encryption package, for example:

```text
backupstore/
    encryption/
        encryption.go
        header.go
        key_provider.go
        secret_key_provider.go
        reader.go
        writer.go
```

Responsibilities:

* define the encrypted object format;
* generate DEKs;
* wrap/unwrap DEKs;
* create streaming encryption readers;
* create streaming decryption readers;
* identify encrypted objects;
* validate encryption headers;
* validate authentication;
* return sanitized errors.

Add `github.com/minio/sio` as the streaming authenticated-encryption dependency.

### S3 driver

Modify the S3 driver to optionally insert encryption/decryption around object I/O.

Existing:

```text
Write -> PutObject
Read  -> GetObject
```

New:

```text
Write -> Encrypt -> PutObject
Read  -> GetObject -> Detect -> Decrypt
```

Similarly:

```text
Upload   -> Encrypt -> existing S3 upload
Download -> existing S3 download -> Decrypt
```

The existing AWS SDK v2 client remains responsible for:

* AWS authentication;
* S3-compatible endpoints;
* path-style addressing;
* custom CAs;
* retries;
* multipart upload;
* provider-specific compatibility workarounds.

### longhorn-manager

Longhorn Manager responsibilities include:

* validating BackupTarget encryption configuration;
* reading the encryption Secret;
* ensuring the S3 target uses a supported configuration;
* securely passing encryption information into the backup operation;
* exposing non-sensitive encryption status;
* rejecting unsafe key changes.

### longhorn-engine / backup process

Extend the existing backup credential/configuration plumbing so the process performing the backup can obtain the encryption configuration.

No persistent plaintext key should be written to disk as part of the configuration transfer.

### Longhorn UI

Add BackupTarget encryption configuration:

```text
Client-Side Backup Encryption
    [ ] Enable

Encryption Secret
    [ longhorn-backup-encryption ]
```

When enabled, show a warning:

```text
The encryption key is required to restore these backups.
Longhorn cannot recover the data if the key is lost.
```

Backup detail pages can show:

```text
Encryption: Client-side
Algorithm:  AES-256-GCM
Key ID:     backup-key-2026-01
```

The key itself is never displayed.

### Documentation

Documentation must cover:

* generating a secure 256-bit key;
* creating the Kubernetes Secret;
* enabling backup encryption;
* creating encrypted backups;
* restoring encrypted backups into another cluster;
* disaster-recovery handling of the Secret;
* key-loss consequences;
* upgrade/downgrade behavior;
* supported S3 providers;
* current key-rotation limitations.

---

## Test Plan

### Unit Tests

#### Encryption/decryption

Verify:

1. plaintext encrypts successfully;
2. ciphertext decrypts to the original plaintext;
3. ciphertext does not contain the original plaintext;
4. encrypting the same content multiple times results in different ciphertext because random key/nonce material is used;
5. zero-length input is supported;
6. small input is supported;
7. large streaming input is supported.

#### Authentication

Verify decryption fails when:

* ciphertext bytes are modified;
* ciphertext is truncated;
* encrypted chunks are reordered;
* header information is corrupted;
* the wrong DEK is supplied;
* the wrong KEK is supplied.

No unauthenticated plaintext should be returned.

#### Encryption header

Verify:

* correct magic is recognized;
* version 1 is parsed;
* unsupported versions are rejected;
* invalid field lengths are rejected;
* unknown algorithm identifiers are rejected;
* plaintext legacy objects are not incorrectly recognized as encrypted objects.

#### Key handling

Verify:

* 32-byte key succeeds;
* shorter keys fail;
* longer keys fail;
* missing Secret data fails;
* missing key ID behavior follows the API contract;
* wrong Secret fails during restore;
* sensitive values do not appear in returned errors.

#### S3 write/read

With encryption disabled:

```text
Write -> S3 object == original input
Read  -> original input
```

With encryption enabled:

```text
Write -> S3 object != original input
Read  -> original input
```

#### Multipart upload

Test encrypted objects large enough to trigger the current AWS SDK multipart uploader.

Verify:

* backup succeeds;
* retry succeeds;
* resulting object decrypts correctly;
* encryption boundaries are independent from multipart boundaries.

#### Existing single-part fallback

Test S3 provider paths that use `PutObjectAsSinglePart` or the existing single-part compatibility fallback.

Encryption must work with both multipart and single-part paths.

#### Legacy compatibility

Store an existing unencrypted backup object.

Enable the new encryption-capable Longhorn code.

Verify the plaintext object remains readable.

---

## Automated E2E Tests

Add or update automated test coverage associated with #12297.

## Manual Test Plan

### Security inspection

After creating an encrypted backup:

1. Download objects directly from S3 without using Longhorn.
2. Search for known filesystem/application contents.
3. Verify plaintext content cannot be found.
4. Verify backup configuration payloads protected by the encryption layer are not readable.
5. Confirm object keys and sizes remain visible as documented.

### Log inspection

Run backup and restore at normal and debug log levels.

Verify that none of the following appear:

* KEK;
* DEK;
* Secret `data.key`;
* plaintext backup data.

Generate a Longhorn support bundle and perform the same check.

### Performance test

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
* total object size;
* backup duration;
* restore duration.

The encryption implementation should remain streaming and must not buffer an entire backup object in memory.

### Failure/retry testing

Introduce network interruptions during encrypted S3 upload/download.

Verify:

* retry does not produce invalid ciphertext;
* failed partial uploads are cleaned up according to current backup behavior;
* retrying the backup produces a valid encrypted object.

---

## Performance Considerations

Client-side encryption introduces additional CPU usage during backup and restore.

Unlike in-cluster volume encryption, however, this cost exists only while backup or restore I/O is being processed.

The expected pipeline is:

```text
compression -> encryption -> network
```

so encryption does not prevent Longhorn from compressing the backup first.

The encryption library must operate in a streaming manner to avoid memory usage proportional to backup size.

Benchmarks should be collected before release to determine the performance impact on:

* small backups;
* large backups;
* highly compressible data;
* incompressible data;
* CPUs with AES hardware acceleration;
* CPUs without AES hardware acceleration.

---

## Risks and Mitigations

### Key loss

**Risk:** The user loses the encryption Secret.

**Impact:** Backups cannot be restored.

**Mitigation:** Strong UI/documentation warnings and disaster-recovery documentation.

### Incorrect key changes

**Risk:** A target contains blocks encrypted under multiple unexpected keys.

**Impact:** Some incremental backups may become unrestorable.

**Mitigation:** Disallow changing the effective key while encrypted backups exist in the target/prefix.

### S3 interoperability

**Risk:** Encryption integration changes stream behavior and exposes differences among S3-compatible providers.

**Mitigation:** Keep the existing AWS SDK v2 transport and make AWS S3 and MinIO E2E testing release-blocking.

### Ciphertext corruption

**Risk:** Remote objects are damaged or modified.

**Impact:** Restore failure.

**Mitigation:** Authenticated encryption detects corruption and Longhorn fails closed.

### Downgrade

**Risk:** User downgrades to a Longhorn release without backup encryption support.

**Impact:** Older Longhorn cannot restore encrypted backups.

**Mitigation:** Document the compatibility boundary and do not modify encrypted backups during downgrade.

### Encryption metadata compatibility

**Risk:** Future implementation changes make existing encrypted backups unreadable.

**Mitigation:** Use a versioned Longhorn encryption envelope and treat the encrypted-object format as a persistent compatibility contract.

---

## Rollout Plan

### Phase 1: Encryption format and POC

Implement a prototype in `backupstore` using `minio/sio`.

Validate:

* stream encryption/decryption;
* AWS SDK v2 multipart upload;
* existing single-part path;
* AWS S3;
* MinIO;
* existing S3-compatible custom endpoint behavior.

The POC should be completed before finalizing the on-disk/on-S3 encryption format.

### Phase 2: API and key management

Implement:

* BackupTarget fields;
* Secret validation;
* encryption configuration plumbing;
* key-provider abstraction;
* Backup/BackupTarget status.

### Phase 3: Backupstore integration

Implement:

* encrypted Write;
* decrypted Read;
* encrypted Upload;
* decrypted Download;
* legacy plaintext detection;
* integrity error handling.

### Phase 4: Manager/UI/documentation

Add:

* validation;
* status;
* UI controls;
* key-loss warnings;
* disaster-recovery documentation.

### Phase 5: E2E and interoperability

Complete #12297 and validate:

* AWS S3;
* MinIO;
* V1/V2 backup paths;
* incremental backup;
* upgrade;
* restore;
* corruption handling.

---

## Future Enhancements

### External KMS

Implement additional `DataKeyProvider` implementations such as:

```text
AWS KMS
Vault
other enterprise KMS providers
```

The backup format already contains:

```text
key provider
key ID
wrapped DEK
```

so these providers can be added without redesigning content encryption.

### Key rotation

Add a controlled process to rotate the KEK.

Because each object uses a DEK, a future implementation may be able to re-wrap DEKs where the storage format permits it rather than decrypting and re-encrypting the complete backup payload.

### Per-volume policy

Allow individual Longhorn volumes to override the BackupTarget encryption default.

For example:

```yaml
spec:
  backupEncryption: inherit
```

with possible values:

```text
inherit
enabled
disabled
```

This requires additional design around shared backup blocks and key consistency and is intentionally deferred from the first implementation.

### Server-side encryption

SSE-C or other S3 server-side encryption can be implemented independently for users who prefer provider-managed encryption.

It should be considered an additional protection option rather than a replacement for client-side encryption.

---

## Decision

The proposed first implementation is:

```text
Scope:
    S3 / S3-compatible backup targets only

Encryption location:
    Longhorn client side, before S3 upload

S3 library:
    Existing aws-sdk-go-v2 implementation

Streaming encryption:
    github.com/minio/sio

Content encryption:
    AES-256-GCM authenticated encryption

Configuration:
    BackupTarget level

Initial key source:
    Kubernetes Secret containing a 256-bit key

Key model:
    Per-object random DEK protected by the configured KEK

External KMS:
    Extensible interface, implementation deferred

Existing backups:
    Remain supported and are not automatically migrated

Key rotation:
    Not supported for existing backups in the initial release

Required interoperability:
    AWS S3 and MinIO

Default:
    Disabled
```

This design keeps S3-provider compatibility separate from encryption, avoids requiring trust in the remote object-storage service, preserves Longhorn's existing S3 transport implementation and incremental-backup architecture, and provides a path for future KMS and key-rotation support.
