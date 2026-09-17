# Client-Side Backup Encryption

## Summary

Longhorn can encrypt a volume inside the cluster, but it cannot encrypt only the backup of that volume. Users who trust their cluster but not their backup destination currently have to enable in-cluster volume encryption just to protect remote backup data, which costs CPU on the data path and changes the volume lifecycle.

This enhancement adds client-side backup encryption: Longhorn encrypts backup data locally, after compression and before handing it to the backup store, so the backup target only ever receives ciphertext. It is configured independently of volume encryption, applies to every backup target the `backupstore` package supports (S3, NFS, CIFS), and uses a Kubernetes Secret as the key source.

The configuration model has two levels. `Volume.Spec.BackupEncryptionSecret` takes precedence over the global `backup-encryption-secret` setting, and if neither is set, backups are created exactly as they are today.

### Related Issues

- https://github.com/longhorn/longhorn/issues/5220 - Encrypt volume backup to remote backup store without in-cluster volume encryption
- https://github.com/longhorn/longhorn/issues/8453 - Backup encryption
- https://github.com/longhorn/longhorn/issues/12297 - Backup encryption automated test

## Motivation

### Goals

- Encrypt backup data on the Longhorn side, before it reaches the backup target.
- Keep backup encryption independent of in-cluster volume encryption, so a plaintext volume can produce encrypted backups.
- Support all backup targets implemented by `backupstore`, by placing encryption above `BackupStoreDriver` rather than inside any driver.
- Provide a global default encryption Secret and allow an individual volume to use a different one.
- Use authenticated encryption, so a wrong key, tampering, corruption, or truncation is detected instead of producing garbage.
- Persist enough non-sensitive metadata in the backup target that an encrypted backup can be identified and restored by a different cluster.
- Preserve existing behavior: existing unencrypted backups stay restorable, and nothing changes when no Secret is configured.
- Preserve incremental backup block reuse within a compatible encryption context.
- Never write a plaintext key into a CR, backup metadata, log, event, or support bundle.
- Fail closed: if encryption is configured but cannot be performed, the backup fails rather than silently writing plaintext.

### Non-goals

- Server-side encryption of any kind (SSE-S3, SSE-KMS, SSE-C). Tracked separately in `longhorn/longhorn#14037`.
- External KMS integration. The design keeps room for it, but the first version only reads Kubernetes Secrets.
- Changing in-cluster volume encryption in any way.
- Encrypting, migrating, or re-encrypting backups that already exist.
- Online key rotation of already-written encrypted backup data.
- Recovering an encrypted backup whose key has been lost.
- Hiding backup paths, object names, file names, object sizes, or timestamps. Backup metadata (`volume.cfg`, `backup_*.cfg`) stays in plaintext so that backup synchronization can work without the encryption key.
- An explicit per-volume opt-out when the global setting is configured. See [Note](#note).

## Proposal

Encryption is added as one layer in the existing backup pipeline:

```text
volume data -> changed-block detection -> compression -> encryption -> BackupStoreDriver -> S3 / NFS / CIFS
```

Encryption must come after compression, because compressing ciphertext does not work.

Restore reverses the order, and decides whether to decrypt based on metadata stored with the backup, never based on the current volume or global configuration.

```text
S3 / NFS / CIFS -> BackupStoreDriver -> decryption -> decompression -> restore
```

Key material uses envelope encryption. The referenced Kubernetes Secret holds a key-encryption key (KEK). Longhorn generates a random data-encryption key (DEK) that actually encrypts backup data, wraps the DEK with the KEK, and stores only the wrapped DEK in the backup target.

### User Stories

#### Story 1 - Encrypt every backup with one key

An administrator wants all backups leaving the cluster to be encrypted. Today the only option is to enable volume encryption on every volume, which encrypts in-cluster data they did not need to encrypt and cannot be turned on for existing volumes.

After this enhancement they create one Secret, set `backup-encryption-secret` to its name, and every subsequent backup of every volume is encrypted. Volumes themselves are untouched.

#### Story 2 - Encrypt backups for one volume only

A user has one volume holding regulated data among many that do not. Today there is no way to encrypt just that volume's backups without encrypting the volume itself.

After this enhancement they leave the global setting empty and set `backupEncryptionSecret` on that one volume (or on its StorageClass). Its backups are encrypted; every other volume keeps its current behavior.

#### Story 3 - Use a different key for one volume

An administrator has a global key but needs one tenant's backups encrypted under a key that tenant controls. They set `backupEncryptionSecret` on that volume, and the volume-level Secret wins over the global setting.

#### Story 4 - Restore into a new cluster after losing the original

A cluster producing encrypted backups is lost. The administrator installs Longhorn in a new cluster, points it at the same backup target, and recreates the Secret with the same name and the same key bytes. During backup synchronization Longhorn reads each backup's encryption metadata, learns which Secret name each one needs, and restores it. If the Secret is absent or holds different key material, Longhorn reports a specific encryption-key error instead of failing obscurely.

### User Experience In Detail

#### 1. Create the encryption Secret

The Secret lives in the Longhorn namespace, next to the backup target credential Secrets, and holds a 32-byte key under `LONGHORN_BACKUP_ENCRYPTION_KEY`:

```bash
kubectl -n longhorn-system create secret generic longhorn-backup-encryption \
    --from-literal=LONGHORN_BACKUP_ENCRYPTION_KEY="$(openssl rand -base64 32)"
```

The value is base64-encoded 32 random bytes. Longhorn validates the length and rejects the Secret otherwise. A human-chosen passphrase must not be used directly as a key; documentation will say so explicitly.

#### 2. Enable encryption globally

```yaml
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: backup-encryption-secret
  namespace: longhorn-system
value: longhorn-backup-encryption
```

The default is an empty string, meaning encryption is off.

#### 3. Enable encryption for a single volume

Either directly on the volume:

```yaml
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: database-volume
  namespace: longhorn-system
spec:
  backupEncryptionSecret: database-backup-encryption
```

or, for CSI-provisioned volumes, through the StorageClass, which is how most users will reach the field:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-encrypted-backup
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "3"
  backupEncryptionSecret: "database-backup-encryption"
```

#### 4. Effective Secret resolution

Longhorn resolves the Secret once, when the `Backup` CR is created, and records the result in `Backup.Spec.BackupEncryptionSecret` so that the rest of the operation cannot be affected by a concurrent configuration change:

| `Volume.Spec.BackupEncryptionSecret` | `backup-encryption-secret` | Effective |
| --- | --- | --- |
| `""` | `""` | no encryption |
| `""` | `global-key` | `global-key` |
| `volume-key` | `""` | `volume-key` |
| `volume-key` | `global-key` | `volume-key` |

```go
func resolveBackupEncryptionSecret(volumeSecret, globalSecret string) string {
	if volumeSecret != "" {
		return volumeSecret
	}
	return globalSecret
}
```

#### 5. Restore an encrypted backup

Restore requires no extra user input. Longhorn reads the required Secret name from the backup's metadata and loads it. The user only has to make sure the Secret exists with the original key bytes.

#### 6. Change the encryption key

Changing the configured Secret affects future backups only. Backups already in the target still require the key they were written with, so the old Secret must be kept as long as those backups exist.

Overwriting the key material inside an existing Secret, while keeping its name, makes every backup written with the previous key unrestorable. Longhorn detects this rather than silently corrupting data, because the encryption context includes a key fingerprint (see [Encryption context](#encryption-context-and-incremental-backups)). Documentation will recommend creating a new Secret name when rotating keys.

### API changes

#### Global setting

A new setting in `longhorn-manager`, `types/setting.go`:

```go
SettingNameBackupEncryptionSecret = SettingName("backup-encryption-secret")

SettingDefinitionBackupEncryptionSecret = SettingDefinition{
	DisplayName: "Backup Encryption Secret",
	Description: "The name of the Kubernetes Secret in the Longhorn namespace holding the key used to " +
		"encrypt backup data before it is written to the backup target. The Secret must contain a " +
		"32-byte key, base64-encoded, under the `LONGHORN_BACKUP_ENCRYPTION_KEY` field.\n\n" +
		"An empty value disables client-side backup encryption by default. " +
		"`Volume.Spec.BackupEncryptionSecret` overrides this setting for an individual volume.\n\n" +
		"Losing the key permanently prevents restoring backups encrypted with it.",
	Category:           SettingCategoryBackup,
	Type:               SettingTypeString,
	Required:           false,
	ReadOnly:           false,
	DataEngineSpecific: false,
	Default:            "",
}
```

The setting stores only a Secret name. The key is never stored in the `Setting` CR.

#### Volume CRD

`k8s/pkg/apis/longhorn/v1beta2/volume.go`:

```go
type VolumeSpec struct {
	...
	// BackupEncryptionSecret is the name of the Kubernetes Secret in the Longhorn namespace whose key is
	// used to encrypt this volume's backup data. It overrides the global `backup-encryption-secret` setting.
	// An empty value means the global setting applies.
	// +optional
	BackupEncryptionSecret string `json:"backupEncryptionSecret,omitempty"`
}
```

The field is mutable, since it only affects backups created after the change. It is not added to `VolumeStatus`; the effective value is computed on demand for the API and UI.

#### Backup CRD

`k8s/pkg/apis/longhorn/v1beta2/backup.go`:

```go
type BackupSpec struct {
	...
	// BackupEncryptionSecret is the Secret name resolved from the volume and global configuration when this
	// backup was requested. An empty value means the backup is not encrypted. It is immutable, and it holds
	// a Secret name only, never key material.
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="BackupEncryptionSecret is immutable"
	// +optional
	BackupEncryptionSecret string `json:"backupEncryptionSecret,omitempty"`
}

type BackupStatus struct {
	...
	// BackupEncryptionSecret is the Secret name recorded in the backup's metadata in the backup target.
	// It is populated during backup synchronization and is the authoritative value for restore.
	// +optional
	BackupEncryptionSecret string `json:"backupEncryptionSecret,omitempty"`
}
```

`BackupStatus` needs no separate `Enabled` field: a non-empty Secret name means the backup is encrypted. It also does not expose the encryption format version, because that describes the persistent backup format and belongs in the backup metadata, not in a Kubernetes CR.

`BackupStatus.BackupEncryptionSecret` is populated from the backup target during synchronization rather than copied from `BackupSpec`, so that a backup created by another cluster reports the Secret it actually needs.

#### CSI StorageClass parameter

`csi/util.go` already translates StorageClass parameters into volume fields for `encrypted`, `backupTargetName`, and `backupBlockSize`. A `backupEncryptionSecret` parameter is added the same way, so PVC users can reach the field.

#### Longhorn REST API

`api/model.go` gains `backupEncryptionSecret` on the volume resource, plus a read-only `effectiveBackupEncryptionSecret` and its source (`volume` or `global`) so the UI can show what will actually be used. The backup resource gains `backupEncryptionSecret`. No endpoint ever returns Secret contents.

#### UI

- Settings: a "Backup Encryption Secret" text field under the Backup category, with a warning that losing the key makes backups unrestorable.
- Volume create and volume detail: a "Backup Encryption Secret" field, showing the effective value and its source when the volume's own field is empty.
- Backup list and backup detail: an indication that a backup is encrypted and which Secret name it needs.
- A visible warning when a backup's required Secret is missing from the cluster.

Secret contents are never displayed.

## Design

### Implementation Overview

#### Where encryption happens

Encryption sits above `BackupStoreDriver` and below the backup logic, so no driver needs to know about it:

```text
              backup logic
                    |
             encryption layer
                    |
             BackupStoreDriver
             /      |       \
           S3      NFS     CIFS
```

In `backupstore`, block upload today is:

```go
rs, err := util.CompressData(deltaBackup.CompressionMethod, block)
...
err = bsDriver.Write(blkFile, rs)
```

The encryption layer is a sibling of `util.CompressData` with the same shape, inserted between compression and `Write`:

```go
rs, err := util.CompressData(deltaBackup.CompressionMethod, block)
if err != nil {
	return err
}
if deltaBackup.Encryption != nil {
	rs, err = deltaBackup.Encryption.EncryptData(rs)
	if err != nil {
		return err
	}
}
...
err = bsDriver.Write(blkFile, rs)
```

Restore inserts the matching `DecryptData` before `util.DecompressAndVerifyWithFallback`.

#### Streaming and the driver interface

The driver interface is:

```go
Write(dst string, rs io.ReadSeeker) error
```

`Write` takes an `io.ReadSeeker`, not an `io.Reader`, because drivers need the size up front and need to rewind on retry. A fully streaming encryption reader therefore cannot be passed to `Write` as-is, regardless of backup target. This is an interface constraint, not an S3, NFS, or CIFS limitation.

For block data this does not matter: a block is 2 MiB or 16 MiB, `CompressData` already buffers it in memory and returns a `bytes.Reader`, so encryption can do the same and stay in memory.

For the whole-file paths (`singlefile.go`, used by backing image and system backup) the payload can be large. Those encrypt into a temporary file and then call `Write` or `Upload`, which is the approach agreed in review. Temporary files hold ciphertext only; no plaintext backup payload is written to local disk.

#### Key hierarchy

```text
Kubernetes Secret
      |  KEK
      v
   wrap DEK  <--- random DEK ---> encrypt backup data
      |
      v
 wrapped DEK -> stored in the backup target
```

- The Secret holds the KEK. It never leaves the cluster.
- The DEK is generated with `crypto/rand`, one per (backup volume, encryption context).
- The DEK is wrapped with AES-256-GCM under the KEK. Only the wrapped DEK is persisted.
- The plaintext DEK exists only in memory.

One DEK per encryption context rather than one per object is deliberate: a per-object DEK would give every block a distinct key, so identical plaintext blocks would produce different ciphertext and incremental block reuse would stop working entirely.

#### Encryption algorithm

Backup data is encrypted with AES-256 in the DARE streaming format, via `github.com/minio/sio`. DARE is chosen because it is authenticated, chunked, and already used elsewhere in the storage ecosystem, so a wrong key, a modified chunk, a reordered chunk, corruption, and truncation are all detected. Unauthenticated modes such as plain AES-CTR are not acceptable here.

The exact library version and the on-disk layout are confirmed in the POC before the format is frozen.

#### Encrypted object format

Rather than a custom binary envelope, per-context key material is a JSON object stored once per backup volume, and encrypted payloads are plain DARE streams.

```text
backupstore/volumes/<xx>/<yyyy>/<volume>/
    volume.cfg                              # plaintext, gains an "encryption" field
    backups/backup_<name>.cfg               # plaintext, gains an "encryption" field
    encryption/<contextID>.json             # wrapped DEK and crypto metadata
    blocks/<c0c1>/<c2c3>/<checksum>.blk     # unencrypted blocks (legacy and unencrypted volumes)
    blocks-enc/<contextID>/<c0c1>/<c2c3>/<checksum>.blk
```

`encryption/<contextID>.json`:

```json
{
  "formatVersion": 1,
  "algorithm": "AES-256-GCM-DARE",
  "keyProvider": "secret",
  "secret": "database-backup-encryption",
  "keyFingerprint": "9f2b...",
  "keyWrapAlgorithm": "AES-256-GCM",
  "keyWrapNonce": "...",
  "wrappedDEK": "..."
}
```

`backup_<name>.cfg` gains:

```json
{
  "encryption": {
    "formatVersion": 1,
    "secret": "database-backup-encryption",
    "contextID": "a1b2c3d4e5f60718"
  }
}
```

Backup metadata stays in plaintext on purpose. Backup synchronization has to list and inspect backups in a target without holding any key, and a cluster must be able to report "this backup needs Secret X" before it has Secret X. The cost is that block checksums, sizes, and layout remain visible, which is already covered under non-goals.

Metadata that affects cryptographic processing is authenticated rather than merely stored: `formatVersion`, `algorithm`, `keyProvider`, `secret`, `keyFingerprint`, and `keyWrapAlgorithm` are passed as additional authenticated data to the AES-256-GCM DEK wrap. Editing any of them in the backup target makes DEK unwrapping fail instead of silently changing behavior.

The metadata never contains the KEK, the plaintext DEK, or Secret contents.

#### Encryption context and incremental backups

Block file names are content checksums, and a block is reused when a file with that checksum already exists. Blocks encrypted under different keys cannot be mixed, so reuse has to be scoped.

An encryption context identifies a key and format combination:

```text
keyFingerprint = HMAC-SHA256(KEK, "longhorn-backup-kek-fingerprint-v1")
contextID      = first 16 hex chars of SHA-256(secretName || keyFingerprint || formatVersion || algorithm)
```

Encrypted blocks live under `blocks-enc/<contextID>/...`, so:

- Within one context, dedup and incremental backup work exactly as today.
- Across contexts, no reuse can happen, because the paths do not overlap.
- Unencrypted backups keep using `blocks/`, untouched.
- Rotating the key inside an existing Secret changes `keyFingerprint`, so it changes `contextID`. Longhorn starts a fresh block namespace instead of writing blocks that cannot be decrypted alongside the old ones.

Block deletion and the existing block garbage collection must be made context-aware: a block under `blocks-enc/<contextID>/` is only collectable when no remaining backup in that context references it.

Block file names stay the checksum of the **plaintext** block, so that dedup survives. This means an attacker with access to the backup target and a guess at the plaintext can confirm the guess from the checksum. Given that the alternative is losing incremental backups entirely, the first version accepts this and documents it. Using a keyed checksum, `HMAC-SHA256(DEK, plaintext)`, would remove the leak while keeping dedup inside a context, at the cost of a metadata format that older versions cannot read; the POC evaluates it.

#### Getting the key to the code that encrypts

`longhorn-engine` and the instance manager have no RBAC to read Kubernetes Secrets, and should not get it. `longhorn-manager` resolves and reads the Secret, then passes the key to the backup process the same way the volume-encryption passphrase is already passed: as an environment variable, not as a command-line argument, so it cannot be read from `/proc/<pid>/cmdline` or a process listing.

- `longhorn-manager`: resolve the Secret, validate it, read it, pass the key to the backup process, populate `Backup.Spec.BackupEncryptionSecret`, surface sanitized errors, synchronize encryption metadata into `BackupStatus`.
- `longhorn-engine` and the backup process: receive the key, generate and wrap DEKs, encrypt and authenticate data, write and read encryption metadata, keep incremental semantics within a context.
- `backupstore`: hold the encryption layer above `BackupStoreDriver`, the context-scoped block layout, and context-aware block deletion.

#### Backup flow

1. Read `Volume.Spec.BackupEncryptionSecret`; if empty, read the `backup-encryption-secret` setting.
2. Write the result to `Backup.Spec.BackupEncryptionSecret`.
3. If it is empty, take the existing unencrypted path and stop here.
4. Load the Secret and validate that `LONGHORN_BACKUP_ENCRYPTION_KEY` decodes to 32 bytes. Fail the backup if not.
5. Compute `keyFingerprint` and `contextID`.
6. If `encryption/<contextID>.json` exists, unwrap the existing DEK. Otherwise generate a DEK, wrap it, and write the file.
7. Back up as usual, with encryption between compression and `Write`, and blocks under `blocks-enc/<contextID>/`.
8. Write the `encryption` field into `backup_<name>.cfg`.

#### Restore flow

Restore decides from metadata, never from current configuration.

1. Read the `encryption` field from `backup_<name>.cfg`. If absent, restore as an unencrypted backup.
2. Read `encryption/<contextID>.json` and take the required Secret name.
3. Load the Secret, verify `keyFingerprint`, and unwrap the DEK with the metadata as additional authenticated data.
4. Read, authenticate and decrypt each block, then decompress.
5. Restore the volume.

If the key is wrong or the ciphertext was modified, restore fails. Longhorn never retries an encrypted backup as plaintext.

The same applies to every read path, not just volume restore: backup synchronization, `Inspect`, `List`, DR volume incremental restore, and backing image and system backup restore.

#### Backup synchronization

A single target can hold backups written by different clusters under different keys:

```text
backup-1  unencrypted (legacy)
backup-2  secret-A
backup-3  secret-B
```

Each backup's requirement is read from its own metadata. The current global setting is never treated as the truth for an existing backup. Synchronization succeeds for all three even when no key is present in the cluster, because the metadata it reads is plaintext; `BackupStatus.BackupEncryptionSecret` then tells the user which Secret each one needs.

#### Failure handling

Client-side encryption fails closed. Longhorn never downgrades to an unencrypted backup because encryption did not work.

| Condition | Result |
| --- | --- |
| Secret named in the configuration does not exist | backup does not start: `backup encryption secret "X" was not found` |
| Secret exists but the key is missing, malformed, or the wrong length | backup does not start: `invalid backup encryption key in secret "X"` |
| Secret for an encrypted backup is missing at restore | restore fails: `required backup encryption secret "X" is unavailable` |
| Key material no longer matches the recorded fingerprint | restore fails: `backup encryption key in secret "X" does not match the key used for this backup` |
| Ciphertext or authenticated metadata was modified | restore fails: `failed to decrypt backup: authentication failed` |
| `formatVersion` or `algorithm` is newer than this Longhorn version | restore fails: `unsupported backup encryption format version N` |

Errors may name the Secret. They must never include key material.

#### Secret handling

Secret contents must never be written to `VolumeStatus`, `BackupStatus`, backup metadata, logs, Kubernetes events, REST API responses, the UI, or a support bundle. Only the Secret name is persisted, and only where it is needed to find the key again.

#### Security considerations

The trust boundary moves: without this feature the backup target receives plaintext backup data; with it, the target receives ciphertext and never has access to the key. Authenticated encryption also means that modification of backup data in the target is detected at restore time.

The feature does not hide backup paths, object or file names, object sizes, timestamps, access patterns, or, in the first version, plaintext block checksums.

#### Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| The Secret is lost | Backups encrypted with it can never be restored. Longhorn cannot reconstruct the key. | Warn in the UI and document preserving encryption Secrets as part of the disaster-recovery procedure. |
| The key inside an existing Secret is replaced | Backups written with the previous key can no longer be restored. | `keyFingerprint` detects it and produces a clear error rather than a corrupt restore. Documentation recommends a new Secret name per key. |
| A block from one key is reused by a backup under another | Restore would fail. | Context-scoped block paths make cross-context reuse structurally impossible. |
| Changing the global setting silently re-keys all volumes | New backups start a new context, so incremental chains restart and target usage grows. | Document it; surface the effective Secret and its source in the UI so the blast radius is visible before the change. |
| The driver interface cannot consume a streaming reader | Memory or temp-space pressure on large payloads. | In-memory for block-sized data, encrypted temp files for whole-file paths. |
| A future format change makes existing encrypted backups unreadable | Data loss. | `formatVersion` in the metadata, treated as a persistent compatibility contract, with an explicit unsupported-version error. |

### Test plan

#### Unit tests

Secret resolution: the four combinations in the [resolution table](#4-effective-secret-resolution).

CRD and API: both new fields serialize and round-trip; empty values are valid; existing CRs stay valid; `Backup.Spec.BackupEncryptionSecret` is immutable; the StorageClass parameter reaches `VolumeSpec`; Secret contents never appear in a CR or an API response.

Encryption: round-trip for zero-length, small, block-sized, and multi-block input; ciphertext does not contain the plaintext; two encryptions of the same plaintext under the same DEK are byte-identical, so dedup holds; modified, reordered, and truncated ciphertext all fail authentication; a wrong key fails; an invalid wrapped DEK fails; modifying any authenticated metadata field fails the unwrap; an unsupported `formatVersion` or `algorithm` fails.

Encryption context: `contextID` is stable for the same key and changes when the key material, `formatVersion`, or `algorithm` changes; blocks from two contexts never share a path; context-aware deletion does not remove a block still referenced within its context.

Secret handling: a valid Secret works; a missing Secret, a missing field, a malformed value, and a wrong key length each fail with the documented message; no error string or log line contains key material.

`backupstore` integration, exercised through the generic abstraction rather than per driver: with encryption off, write and read behave as today; with encryption on, what lands in the target is ciphertext and the read path returns the original bytes. Covering `Read`, `Write`, `Upload`, `Download`, `List`, deletion, retry, and the encrypted-temp-file path.

#### Integration and E2E tests

1. Encryption unconfigured: backup and restore behave exactly as before, checksum verified.
2. Global Secret only: backup is encrypted in the target, restores, checksum verified.
3. Volume Secret only: same, with the global setting empty.
4. Volume overrides global: the volume's Secret is used.
5. Incremental backup under one Secret: unchanged blocks are reused; both backups restore.
6. Two Secrets: backup A under `secret-A`, then switch to `secret-B` and take backup B; A still needs `secret-A`, blocks are not shared, and both restore under their own Secret.
7. Missing Secret at restore: fails with the missing-Secret error.
8. Replaced key material: fails with the fingerprint-mismatch error, no plaintext fallback.
9. Corrupted ciphertext in the target: authenticated decryption detects it.
10. Disaster recovery: encrypted backups from cluster A are synchronized and restored in cluster B after recreating the Secret.
11. Mixed history in one target (unencrypted, `secret-A`, `secret-B`): synchronization works with no key present, each backup reports the right requirement, each restores with its own Secret.
12. Upgrade: an unencrypted backup taken before the upgrade is still listed and restorable afterwards, and an encrypted backup can then be created and restored.
13. Deletion: deleting an encrypted backup removes its blocks without affecting other contexts or other backups in the same context.
14. Per target, for S3, NFS, and CIFS: encrypted backup, restore, incremental backup, synchronization, deletion, and the streaming or temp-file path that target exercises.

#### Security verification

Write a known plaintext pattern into a volume, back it up encrypted, then inspect the backup target directly and confirm the pattern does not appear in any block. Then inspect `longhorn-manager` logs, engine logs, Kubernetes events, the `Volume` CR, the `Backup` CR, and a support bundle, and confirm the key never appears in any of them.

#### Performance

Compare encrypted against unencrypted backup and restore on S3, NFS, and CIFS, measuring throughput, duration, CPU, memory, temporary storage use, and resulting backup size. Also measure the incremental case, to confirm that dedup within a context performs like the unencrypted case.

### Upgrade strategy

Upgrading adds the `backup-encryption-secret` setting with an empty default, adds `Volume.Spec.BackupEncryptionSecret`, adds `Backup.Spec.BackupEncryptionSecret` and `Backup.Status.BackupEncryptionSecret`, and regenerates CRDs, clients, and deepcopy functions.

Nothing is enabled by default and no backup data is rewritten. Existing volumes have an empty field, existing backups have no `encryption` metadata and are treated as unencrypted, and existing behavior is unchanged until an administrator sets a Secret.

Downgrading is one-way with respect to data: a Longhorn version without this feature does not understand the encrypted format and cannot restore backups created with it, and downgrading does not decrypt anything. This needs to be stated in the release notes.
