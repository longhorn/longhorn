# Add PV encryption support

## Summary

This enhancement adds support for user configured (storage class, secrets) encrypted volumes,
this in return means that backups of that volume end up also being encrypted.

### Related Issues
- [RWO encryption support](https://github.com/longhorn/longhorn/issues/1859)
- [Backup encryption](https://github.com/longhorn/longhorn/issues/902)
- [RWX encryption support]() // TODO: create issue
- [Expansion support](https://github.com/longhorn/longhorn/issues/2794)
- [Restore support]() // TODO: create issue
- [VolumeMode Block support]() // TODO: create issue

## Motivation

### Goals
- user is able to create & use an encrypted volume with cipher customization options
- user is able to configure the keys that are used for encryption
- user is able to take backups from an encrypted volume
- user is able to restore an encrypted backup to a new encrypted volume

### Non-goals
- external key management support, currently keys utilize kubernetes secrets
- rotating key support, user can do this manually though as a workaround
- securing of secrets, user is responsible for cluster setup and security of the secrets

## Proposal

### User Stories
All regular longhorn operations should also be supported for encrypted volumes,
therefore the only user story that is mentioned is
how to create and use an encrypted volume.

#### Create and use an encrypted volume
- create a storage class with (encrypted=true) and either a global secret or a per volume secret
- create the secret for that volume in the configured namespace with customization options of the cipher for instance `cipher`, `key-size` and `hash`
- create a pvc that references the created storage class
- volume will be created then encrypted during first use
- afterwards a regular filesystem that lives on top of the encrypted volume will be exposed to the pod

### User Experience In Detail

Creation and usage of an encrypted volume requires 2 things:
- the storage class needs to specify `encrypted: "true"` as part of its parameters.
- secrets need to be created and reference for the csi operations need to be setup.
- see below examples for different types of secret usage.

The kubernetes sidecars are responsible for retrieval of the secret and passing it to the csi driver.
If the secret hasn't been created the PVC will remain in the Pending State.
And the side cars will retry secret retrieval periodically, once it's available the sidecar container will call
`Controller::CreateVolume` and pass the secret after which longhorn will create a volume.

#### Create storage class that utilizes a global secret (all volumes use the same key)
The below storage class uses a global secret named `longhorn-crypto` in the `longhorn-system` namespace.
```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: longhorn-crypto-global
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880" # 48 hours in minutes
  fromBackup: ""
  encrypted: "true"
  csi.storage.k8s.io/provisioner-secret-name: "longhorn-crypto"
  csi.storage.k8s.io/provisioner-secret-namespace: "longhorn-system"
  csi.storage.k8s.io/node-publish-secret-name: "longhorn-crypto"
  csi.storage.k8s.io/node-publish-secret-namespace: "longhorn-system"
  csi.storage.k8s.io/node-stage-secret-name: "longhorn-crypto"
  csi.storage.k8s.io/node-stage-secret-namespace: "longhorn-system"
```

The global secret reference by the `longhorn-crypto-global` storage class.
This type of setup means that all volumes share the same encryption key.
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: longhorn-crypto
  namespace: longhorn-system
stringData:
  CRYPTO_KEY_VALUE: "Simple passphrase"
  CRYPTO_KEY_PROVIDER: "secret" # this is optional we currently only support direct keys via secrets
  CRYPTO_KEY_CIPHER: "aes-xts-plain64" # this is optional
  CRYPTO_KEY_HASH: "sha256" # this is optional
  CRYPTO_KEY_SIZE: "256" # this is optional
```

#### Create storage class that utilizes per volume secrets
The below storage class uses a per volume secret, the name and namespace of the secret is based on the pvc values.
These templates will be resolved by the external sidecars and the resolved values end up as Secret refs on the PV.
```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: longhorn-crypto-per-volume
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880" # 48 hours in minutes
  fromBackup: ""
  encrypted: "true"
  csi.storage.k8s.io/provisioner-secret-name: ${pvc.name}
  csi.storage.k8s.io/provisioner-secret-namespace: ${pvc.namespace}
  csi.storage.k8s.io/node-publish-secret-name: ${pvc.name}
  csi.storage.k8s.io/node-publish-secret-namespace: ${pvc.namespace}
  csi.storage.k8s.io/node-stage-secret-name: ${pvc.name}
  csi.storage.k8s.io/node-stage-secret-namespace: ${pvc.namespace}
```


### API changes
add a `Encrypted` boolean to the `Volume` struct utilized by the http client,
this ends up being stored in `Volume.Spec.encrypted` of the volume cr.
Storing the `Encrypted` value is necessary to support encryption for RWX volumes.

## Design

### Implementation Overview
Host requires `dm_crypt` kernel module as well as `cryptsetup` installed.
We utilize the below parameters from a secret,
- `CRYPTO_KEY_PROVIDER` allows us in the future to add other key management systems
- `CRYPTO_KEY_CIPHER` allow users to choose the cipher algorithm when creating an encrypted volume by `cryptsetup`
- `CRYPTO_KEY_HASH` specifies the hash used in the LUKS key setup scheme and volume key digest
- `CRYPTO_KEY_SIZE` sets the key size in bits. The argument has to be a multiple of 8 and the maximum interactive passphrase length is 512 (characters)

```yaml
  CRYPTO_KEY_VALUE: "Simple passphrase"
  CRYPTO_KEY_PROVIDER: "secret" # this is optional we currently only support direct keys via secrets
  CRYPTO_KEY_CIPHER: "aes-xts-plain64" # this is optional
  CRYPTO_KEY_HASH: "sha256" # this is optional
  CRYPTO_KEY_SIZE: "256" # this is optional
```

- utilize host `dm_crypt` kernel module for device encryption
- utilize host installed `cryptsetup` for configuration of the crypto device
- add csi driver `NodeStageVolume` support to handle device global per node mounting,
  we skip mounting for volumes that are being used via `VolumeMode: Block`
- refactor csi driver NodePublishVolume to bind mount the `staging_path` into the `target_path`
  we utilize a bind mount for `VolumeMode: Mount` we do a regular device file creation for `VolumeMode: Block`
- during csi `NodeStageVolume` encrypt (first time use) / open regular longhorn device
  - this exposes a crypto mapped device (/dev/mapper/<volume-name>)
  - mount crypto device into `staging_path`
- during csi `NodeUnstageVolume` unmount `staging_path` close crypto device

### Test plan

#### Successful Creation of an encrypted volume
- create a storage class with (encrypted=true) and either a global secret or a per volume secret
- create the secret for that volume in the configured namespace
- create a pvc that references the created storage class
- create a pod that uses that pvc for a volume mount
- wait for pod up and healthy

#### Successful Creation of an encrypted volume with customization of the cipher
- create a storage class with (encrypted=true) and either a global secret or a per volume secret
- create the secret with customized options of the cipher for that volume in the configured namespace
- create a pvc that references the created storage class
- create a pod that uses that pvc for a volume mount
- wait for pod up and healthy
- check if the customized options of the cipher are correct

#### Missing Secret for encrypted volume creation
- create a storage class with (encrypted=true) and either a global secret or a per volume secret
- create a pvc that references the created storage class
- create a pod that uses that pvc for a volume mount
- verify pvc remains in pending state
- verify pod remains in creation state

#### Verify encryption of volume
- create a storage class with (encrypted=true) and either a global secret or a per volume secret
- create the secret for that volume in the configured namespace
- create a pvc that references the created storage class
- create a pod that uses that pvc for a volume mount
- wait for pod up and healthy
- write known test pattern into fs
- verify absence (grep) of known test pattern after reading block device content `/dev/longhorn/<volume-name>`

#### Verify wrong key failure
- create a storage class with (encrypted=true) and either a global secret or a per volume secret
- create the secret for that volume in the configured namespace
- create a pvc that references the created storage class
- create a pod that uses that pvc for a volume mount
- wait for pod up and healthy
- scale down pod
- change `CRYPTO_KEY_VALUE` of secret
- scale up pod
- verify pod remains in pending state (failure to mount volume)

### Upgrade strategy
- requires new pvc's since encryption would overwrite the previously created filesystem. (csi driver prevents this)

## Note
- Host requires `dm_crypt` kernel module as well as `cryptsetup` installed.
- [csi sidecars and secrets](https://kubernetes-csi.github.io/docs/secrets-and-credentials.html)
- supporting external key vaults is possible in the future with some additional implementation
- support rotating keys is possible in the future with some additional implementation
