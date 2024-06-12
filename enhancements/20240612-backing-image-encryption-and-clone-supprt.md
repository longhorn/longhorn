# BackingImage Encryption Support

## Summary

Longhorn supports encrypted volumes by utilizing a Linux kernel-based disk encryption solution (LUKS, Linux Unified Key Setup). If users want to use BackingImage with encrypted Volume, the BackingImage needs to be encrypted as well. This feature allows users to clone the existing BackingImage and encrypt the content during cloning.

### Related Issues

- https://github.com/longhorn/longhorn/issues/7051

## Motivation

### Goals

- Users can create a Encrypted Volume with the Encrypted BackingImage
- Users can clone a BackingImage
    - Users can encrypt a BackingImage during the cloning process
    - Users can decrypt an encrypted BackingImage during the cloning process
- For qcow2 image, if we want to encrypt it
    - We will temporarily create raw image from the qcow2 first and then encrypt it.
    - The result will be an encrypted raw image

### Non-goals [optional]

- Users can change the encryption key of the encrypted BackingImage
- Encrypt qcow2 image to a encrypted qcow2 image


## Proposal

### User Stories

#### Utilize encrypted Volume with BackingImage

Before this feature, users can not utilize an encrypted volume with an unencrypted BackingImage. Users will get `unsupported disk encryption format unknown data, probably partitions` error during mounting the device.
The content inside the BackingImage needs to be encrypted using the same key as the Volume before mounting to the workload.

Thus, we need to support users to encrypt the BackingImage in Longhorn.

#### Clone the BackingImage

With this feature, users can create an identical BackingImage by cloning another BackingImage.

#### Encryption and Decryption
With introducing cloning mechanism, we can encrypt and decrypt the content inside the BackingImage during the cloning process.

Noted that, it means it will cost additional space if users want to encrypt or decrypte the BackingImage. The encrypted or decrypted BackingImage will be a new BackingImager in the system.


## Design

### Implementation Overview

#### CRD

Add a field to the BackingImage
- Secret/SecretNamespace: 
    - Pointing to the k8s secret containing the key used for encryption and decryption
    - We use `Secret` to check if the BackingIamge is encrypted. If the BackingImage has `Secret` then it means it is encrypted.

```
type BackingImageSpec struct {
	Disks map[string]string `json:"disks"`
	Checksum string `json:"checksum"`
	SourceType BackingImageDataSourceType `json:"sourceType"`
	SourceParameters map[string]string `json:"sourceParameters"`
    
	Secret string `json:"secret"`
    SecretNamespace string `json:"secretNamespace"`
}
```

#### Backing Image Data Source

- Add a new source type: `clone`
    - parameters:
        - `source`: the source BackingImage
        - `encryption`: `encrypt`, `decrypt` and `ignore`
        - `secret`: the key used in the encryption and decryption.
- Encryption
    - `encrypt`: Longhorn copy the BackingImage and apply the encryption
    - `decrypt`: Longhorn copy the BackingImage and decrypt the content
    - `ignoe`: Longhorn simply copy the BackingImage
- If we are encrypting the BackingImage, copy the `Secret` and `SecretNamespace` from parameters to `BackingImage.Spec.Secret` and  `BackingImage.Spec.SecretNamespace`
- When choosing the node for the data source pod, we always choose one of the node and disk from the source BackingImage

#### Webhook
- If Source BackingImage has `Secret`, we don't allow to perform `"encrypt"`. (Forbid encrypted -> encrypted)
- If Source BackingImage doesn't have `Secret`, we don't allow to perform `"decrypt"`. (Forbid unencrypted -> decrypted)
- If the operation is to `"encrypt"` or `"decrypt"`, the `Secret` and `SecretNamespace` are needed.
- User cannot change the `Secret` and `SecretNamespace`.

#### Backing Image Manager - Data Source

- When init the service, if the type is clone, then clone from source BackingImage by requesting sync service in the same pod.
    ```golang
        requestURL := fmt.Sprintf("http://%s/v1/files", client.Remote)
        // credential contains the crypto secret
        req, err := http.NewRequest("POST", requestURL, bytes.NewReader(encodedCredential))
        if err != nil {
            return err
        }
        req.Header.Set("Content-Type", "application/json")
        q := req.URL.Query()
        q.Add("action", "cloneFromBackingImage")
        // the source backing image
        q.Add("backing-image", sourceBackingImage)
        // we need uuid to get the path
        q.Add("backing-image-uuid", sourceBackingImageUUID)
        // can be ignore, encrypt or decrypt
        q.Add("encryption", encryption)
        q.Add("file-path", filePath)
        q.Add("uuid", uuid)
        q.Add("disk-uuid", diskUUID)
        q.Add("expected-checksum", expectedChecksum)
    ```
- When doing the cloning
    - The source file is the source BackingImage file on the same disk
    - If the operation is `"encrypt"` and the source file is `qcow2`
        - We create a temp raw image from the qcow2 image and use it as source file
    - Truncate the target file with the source file size.
        - If the operation is `"encrypt"`, we `+16MB` for LUKS meta size
        - If the operation is `"decrypt"`, we `-16MB`
    - If the operation is `"encrypt"`
        - Setup the loop device with the target file
        - `cryptsetup luksFormat` and `luksOpen` the device
        - set the target to the LUKS device
    - If the operation is `"decrypt"`
        - Setup the loop device with the source file
        - `cryptsetup luksOpen` the device
        - set the source to the LUKS device
    - copy all the data from source to the target
        - Need to write zeros since zeros also need to be encrypted.
        - For other cases we can skip zero (ref to the below operation table)

#### LUKS related information

- LUKS2 metadata size is 16MB
    - release: v2.1.0-ReleaseNotes
    - reference: https://gitlab.com/cryptsetup/cryptsetup/-/blob/master/docs/v2.1.0-ReleaseNotes#L27

#### operation table

| - | unencrypted img | encrypted img |
| -------- | -------- | -------- |
| encrypt    |allow (write zero)|  x  |
| decrypt    | x  |     allow (skip zero)     |
| ignore     |   allow (skip zero)   | allow (skip zero)  |


#### UI
- When Create Backing Image, when the `Created From` is `clone`, add following fields
    - `Backing Image`: the source BackingImage.
    - `Encryption`: 3 options for selection, `ignore`, `encrypt` and `decrypt`.
    - `Secret`: the secret name for the encryption or decryption.
    - `Secret Namespace`: the namespace of the secret.
- If the BackingImage has `Secret` and `Secret Namespace` is not empty, show a "lock" icon besides it like encrypted volume.

### Test plan

#### Raw Image Encryption
- Create BackingImage
    - `https://longhorn-backing-image.s3-us-west-1.amazonaws.com/parrot.raw`
- Create Secret and StorageClass
    ```
    apiVersion: v1
    kind: Secret
    metadata:
      name: longhorn-crypto
      namespace: longhorn-system
    stringData:
      CRYPTO_KEY_VALUE: "Your encryption passphrase"
      CRYPTO_KEY_PROVIDER: "secret"
      CRYPTO_KEY_CIPHER: "aes-xts-plain64"
      CRYPTO_KEY_HASH: "sha256"
      CRYPTO_KEY_SIZE: "256"
      CRYPTO_PBKDF: "argon2i"
    ---
    kind: StorageClass
    apiVersion: storage.k8s.io/v1
    metadata:
      name: longhorn-crypto-global
    provisioner: driver.longhorn.io
    allowVolumeExpansion: true
    parameters:
      numberOfReplicas: "2"
      staleReplicaTimeout: "2880" # 48 hours in minutes
      fromBackup: ""
      encrypted: "true"
      backingImage: "parrot-cloned-encrypted"
      backingImageDataSourceType: "clone"
      csi.storage.k8s.io/provisioner-secret-name: "longhorn-crypto"
      csi.storage.k8s.io/provisioner-secret-namespace: "longhorn-system"
      csi.storage.k8s.io/node-publish-secret-name: "longhorn-crypto"
      csi.storage.k8s.io/node-publish-secret-namespace: "longhorn-system"
      csi.storage.k8s.io/node-stage-secret-name: "longhorn-crypto"
      csi.storage.k8s.io/node-stage-secret-namespace: "longhorn-system"
    ```
- Create PVC
    ```
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: longhorn-backing-image-pvc
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: longhorn-crypto-global
      resources:
        requests:
          storage: 1Gi
    ```
- Create Pod to use the encrypted Volume with the encrypted BackingImage
    ```
    apiVersion: v1
    kind: Pod
    metadata:
      name: longhorn-simple-pod
      namespace: default
    spec:
      nodeSelector:
        kubernetes.io/hostname: kworker1
      restartPolicy: Always
      containers:
        - name: ubuntu
          image: ubuntu:22.04
          imagePullPolicy: IfNotPresent
          command: [ "/bin/bash", "-c", "--" ]
          args: [ "while true; do sleep 30; done;" ]
          volumeMounts:
            - name: vol
              mountPath: /data
          ports:
            - containerPort: 80
      volumes:
        - name: vol
          persistentVolumeClaim:
            claimName: longhorn-backing-image-pvc
    ```
- Decrypt the Encrypted BackingImage
    ```
    apiVersion: longhorn.io/v1beta2
    kind: BackingImage
    metadata:
      name: parrot-cloned-decrypt
      namespace: longhorn-system
    spec:
      sourceType: clone
      sourceParameters:
        backing-image: parrot-cloned-encrypted
        encryption: decrypt
        secret: longhorn-crypto
        secret-namespace: longhorn-system
    ```
- The checksum of the `parrot-cloned-decrypt` should be the same as `parrot`

#### Qcow2 Image Encryption
- Follow the same process, but change the BackingImage to qcow2
    - `https://longhorn-backing-image.s3-us-west-1.amazonaws.com/parrot.qcow2`

### Upgrade strategy

No Need

## Note [optional]

Additional notes.
