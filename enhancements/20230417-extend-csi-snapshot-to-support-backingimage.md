# Title

Extend CSI snapshot to support Longhorn BackingImage

## Summary

In Longhorn, we have BackingImage for VM usage. We would like to extend the CSI Snapshotter to support BackingImage management.


### Related Issues

[BackingImage Management via VolumeSnapshot #5005](https://github.com/longhorn/longhorn/issues/5005)

## Motivation

### Goals

Extend the CSI snapshotter to support:
- Create Longhorn BackingImage
- Delete Longhorn BackingImage
- Creating a new PVC from CSI snapshot that is associated with a Longhorn BackingImage


### Non-goals [optional]

- Can support COW over each relative base image for delta data transfer for better space efficiency. (Will be in next improvement)
- User can backup a BackingImage based volume and restore it in another cluster without manually preparing BackingImage in a new cluster.

## Proposal
### User Story
With this improvement, users can use standard CSI VolumeSnapshot as the unified interface for BackingImage creation, deletion and restoration of a Volume.

### User Experience In Detail

To use this feature, users need to deploy the CSI snapshot CRDs and related Controller

1. The instructions are already on our document: https://longhorn.io/docs/1.4.1/snapshots-and-backups/csi-snapshot-support/enable-csi-snapshot-support/
2. Create a VolumeSnapshotClass with type `bi` which refers to BackingImage
    ```yaml
    kind: VolumeSnapshotClass
    apiVersion: snapshot.storage.k8s.io/v1
    metadata:
      name: longhorn-snapshot-vsc
    driver: driver.longhorn.io
    deletionPolicy: Delete
    parameters:
      type: bi
      export-type: qcow2 # default to raw if it is not provided
    ```

#### BackingImage creation via VolumenSnapshot resource

Users can create a BackingImage of a Volume by creation of VolumeSnapshot. Example below for a Volume named `test-vol`

```yaml
apiVersion: snapshot.storage.k8s.io/v1beta1
kind: VolumeSnapshot
metadata:
  name: test-snapshot-backing
spec:
  volumeSnapshotClassName: longhorn-snapshot-vsc
  source:
    persistentVolumeClaimName: test-vol
```

Longhorn will create a BackingImage **exported** from this Volume.

#### Restoration via VolumeSnapshot resource

Users can create a volume based on a prior created VolumeSnapshot. Example below for a Volume named `test-vol-restore`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-vol-restore
spec:
  storageClassName: longhorn
  dataSource:
    name: test-snapshot-backing
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

Longhorn will create a Volume based on the BackingImage associated with the VolumeSnapshot.

#### Restoration of an existing BackingImage (pre-provisioned)

Users can request the creation of a Volume based on a prior BackingImage which was not created via the CSI VolumeSnapshot.

With the BackingImage already existing, users need to create the VolumeSnapshotContent with an associated VolumeSnapshot. The `snapshotHandle` of the VolumeSnapshotContent needs to point to an existing BackingImage. Example below for a Volume named `test-restore-existing-backing` and an existing BackingImage `test-bi`

- For pre-provisioning, users need to provide following query parameters:
    - `backingImageDataSourceType`: `sourceType` of existing BackingImage, e.g. `export-from-volume`, `download`
    - `backingImage`: Name of the BackingImage
    - you should also provide the `sourceParameters` of existing BackingImage in the `snapshotHandle` for validation.
      - `export-from-volume`: you should provide
        - `volume-name`
        - `export-type`
      - `download`: you should proviide
        - `url`
        - `checksum`: optional

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotContent
metadata:
  name: test-existing-backing
spec:
  volumeSnapshotClassName: longhorn-snapshot-vsc
  driver: driver.longhorn.io
  deletionPolicy: Delete
  source:
    # NOTE: change this to point to an existing BackingImage in Longhorn
    snapshotHandle: bi://backing?backingImageDataSourceType=export-from-volume&backingImage=test-bi&volume-name=vol-export-src&export-type=qcow2
  volumeSnapshotRef:
    name: test-snapshot-existing-backing
    namespace: default
```

```yaml
apiVersion: snapshot.storage.k8s.io/v1beta1
kind: VolumeSnapshot
metadata:
  name: test-snapshot-existing-backing
spec:
  volumeSnapshotClassName: longhorn-snapshot-vsc
  source:
    volumeSnapshotContentName: test-existing-backing
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-restore-existing-backing
spec:
  storageClassName: longhorn
  dataSource:
    name: test-snapshot-existing-backing
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

Longhorn will create a Volume based on the BackingImage associated with the VolumeSnapshot and the VolumeSnapshotContent.


#### Restoration of a non-existing BackingImage (on-demand provision)

Users can request the creation of a Volume based on a BackingImage which was not created yet with following 2 kinds of data sources.

1. `download`: Download a file from a URL as a BackingImage.
2. `export-from-volume`: Export an existing in-cluster volume as a backing image.

Users need to create the VolumeSnapshotContent with an associated VolumeSnapshot. The `snapshotHandle` of the VolumeSnapshotContent needs to provide the parameters for the data source. Example below for a volume named `test-on-demand-backing` and an non-existing BackingImage `test-bi` with two different data sources.

1. `download`: Users need to provide following parameters
    - `backingImageDataSourceType`: `download` for on-demand download.
    - `backingImage`: Name of the BackingImage
    - `url`: The file from a URL as a BackingImage.
    - `backingImageChecksum`: Optional. Used for checking the checksum of the file.
    - example yaml:
        ```yaml
        apiVersion: snapshot.storage.k8s.io/v1
        kind: VolumeSnapshotContent
        metadata:
            name: test-on-demand-backing
        spec:
            volumeSnapshotClassName: longhorn-snapshot-vsc
            driver: driver.longhorn.io
            deletionPolicy: Delete
            source:
              # NOTE: change this to provide the correct parameters
              snapshotHandle: bi://backing?backingImageDataSourceType=download&backingImage=test-bi&url=https%3A%2F%2Flonghorn-backing-image.s3-us-west-1.amazonaws.com%2Fparrot.qcow2&backingImageChecksum=bd79ab9e6d45abf4f3f0adf552a868074dd235c4698ce7258d521160e0ad79ffe555b94e7d4007add6e1a25f4526885eb25c53ce38f7d344dd4925b9f2cb5d3b
        volumeSnapshotRef:
            name: test-snapshot-on-demand-backing
            namespace: default
        ```

2. `export-from-volume`: Users need to provide following parameters
    - `backingImageDataSourceType`: `export-form-volume` for on-demand export.
    - `backingImage`: Name of the BackingImage
    - `volume-name`: Volume to be exported for the BackingImage
    - `export-type`: Currently Longhorn supports `raw` or `qcow2`
    - example yaml:
        ```yaml
        apiVersion: snapshot.storage.k8s.io/v1
        kind: VolumeSnapshotContent
        metadata:
        name: test-on-demand-backing
        spec:
        volumeSnapshotClassName: longhorn-snapshot-vsc
        driver: driver.longhorn.io
        deletionPolicy: Delete
        source: 
            # NOTE: change this to provide the correct parameters
            snapshotHandle: bi://backing?backingImageDataSourceType=export-from-volume&backingImage=test-bi&volume-name=vol-export-src&export-type=qcow2
        volumeSnapshotRef:
            name: test-snapshot-on-demand-backing
            namespace: default
        ```

Users then can create corresponding VolumeSnapshot and PVC

```yaml
apiVersion: snapshot.storage.k8s.io/v1beta1
kind: VolumeSnapshot
metadata:
  name: test-snapshot-on-demand-backing
spec:
  volumeSnapshotClassName: longhorn-snapshot-vsc
  source:
    # NOTE: change this to point to the prior VolumeSnapshotContent
    volumeSnapshotContentName: test-on-demand-backing
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-restore-on-demand-backing
spec:
  storageClassName: longhorn
  dataSource:
    name: test-snapshot-on-demand-backing
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

### API changes
No changes necessary

## Design

### Implementation Overview

We add a new type `bi` to the parameter `type` in the VolumeSnapshotClass. It means that the CSI VolumeSnapshot created with this VolumeSnapshotClass is associated with a Longhorn BackingImage.

#### CreateSnapshot function

When the users create VolumeSnapshot and the volumeSnapshotClass `type` is `bi`
```yaml
apiVersion: snapshot.storage.k8s.io/v1beta1
kind: VolumeSnapshot
metadata:
  name: test-snapshot-backing
spec:
  volumeSnapshotClassName: longhorn-snapshot-vsc
  source:
    persistentVolumeClaimName: test-vol
```

We do:
- Get the name of the Volume
- The name of the BackingImage will be same as the VolumeSnapshot `test-snapshot-backing`.
- Check if a BackingImage with the same name as the requested VolumeSnapshot already exists. Return success without creating a new BackingImage.
- Create a BackingImage.
    - Get `export-type` from VolumeSnapshotClass parameter `export-type`, default to `raw.`
    - Encode the `snapshotId` as `bi://backing?backingImageDataSourceType=export-from-volume&backingImage=test-snapshot-backing&volume-name=${VolumeName}&export-type=raw`
    - This `snaphotId` will be used in the later CSI CreateVolume and DeleteSnapshot call.

#### CreateVolume function

- If VolumeSource type is `VolumeContentSource_Snapshot`, decode the `snapshotId` to get the parameters.
    - `bi://backing?backingImageDataSourceType=${TYPE}&backingImage=${BACKINGIMAGE_NAME}&backingImageChecksum=${backingImageChecksum}&${OTHER_PARAMETES}`
- If BackingImage with the given name already exists, create the volume.
- If BackingImage with the given name does not exists, we prepare it first. There are 2 kinds of types which are `export-from-volume` and `download`.
    - For `download`, it means we have to prepare the BackingImage before creating the Volume. We first decode other parameters from `snapshotId` and create the BackingImage. 
    - For `export-from-volume`, it means we have to prepare the BackingImage before creating the Volume. We first decode other parameters from `snapshotId` and create the BackingImage.

NOTE: we already have related code for preparing the BackingImage with type `download` or `export-from-volume` before creating a Volume, [here](https://github.com/longhorn/longhorn-manager/blob/master/csi/controller_server.go#L195)

#### DeleteSnapshot function

- Decode the `snapshotId` to get the name of the BackingImage. Then we delete the BackingImage directly.

### Test plan

Integration test plan.

#### Prerequisite
1. Deploy the csi snapshot CRDs, Controller as instructed at
https://longhorn.io/docs/1.4.1/snapshots-and-backups/csi-snapshot-support/enable-csi-snapshot-support/
2. Create a VolumeSnapshotClass with type `bi`
    ```yaml
    # Use v1 as an example
    kind: VolumeSnapshotClass
    apiVersion: snapshot.storage.k8s.io/v1
    metadata:
      name: longhorn-snapshot-vsc
    driver: driver.longhorn.io
    deletionPolicy: Delete
    parameters:
      type: bi
    ```

#### Scenerios 1: Create VolumeSnapshot from a Volume

- Success
    1. Create a Volume `test-vol` of 5GB. Create PV/PVC for the Volume.
    2. Create a workload using the Volume. Write some data to the Volume.
    3. Create a VolumeSnapshot with following yaml:
        ```yaml
        apiVersion: snapshot.storage.k8s.io/v1beta1
        kind: VolumeSnapshot
        metadata:
          name: test-snapshot-backing
        spec:
          volumeSnapshotClassName: longhorn-snapshot-vsc
          source:
            persistentVolumeClaimName: test-vol
        ```
    4. Verify that BacingImage is created.
        - Verify the properties of BackingImage
            - `sourceType` is `export-from-volume`
            - `volume-name` is `test-vol`
            - `export-type` is `raw`
    5. Delete the VolumeSnapshot `test-snapshot-backing`
    6. Verify the BacingImage is deleted

#### Scenerios 2: Create new Volume from CSI snapshot

1. Create a Volume `test-vol` of 5GB. Create PV/PVC for the Volume.
2. Create a workload using the Volume. Write some data to the Volume.
3. Create a VolumeSnapshot with following yaml:
    ```yaml
    apiVersion: snapshot.storage.k8s.io/v1beta1
    kind: VolumeSnapshot
    metadata:
      name: test-snapshot-backing
    spec:
      volumeSnapshotClassName: longhorn-snapshot-vsc
      source:
        persistentVolumeClaimName: test-vol
    ```
4. Verify that BacingImage is created.
5. Create a new PVC with following yaml:
    ```yaml
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: test-restore-pvc
    spec:
      storageClassName: longhorn
      dataSource:
        name: test-snapshot-backing
        kind: VolumeSnapshot
        apiGroup: snapshot.storage.k8s.io
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 5Gi
    ```
5. Attach the PVC `test-restore-pvc` to a workload and verify the data
6. Delete the PVC

#### Scenerios 3: Restore pre-provisioned BackingImage

1. Create a BackingImage `test-bi` using longhorn test raw image `https://longhorn-backing-image.s3-us-west-1.amazonaws.com/parrot.qcow2`
2. Create a VolumeSnapshotContent with `snapshotHandle` pointing to BackingImage `test-bi` and provide the parameters.
    ```yaml
    apiVersion: snapshot.storage.k8s.io/v1
    kind: VolumeSnapshotContent
    metadata:
      name: test-existing-backing
    spec:
      volumeSnapshotClassName: longhorn-snapshot-vsc
      driver: driver.longhorn.io
      deletionPolicy: Delete
      source:
        snapshotHandle: bi://backing?backingImageDataSourceType=download&backingImage=test-bi&url=https%3A%2F%2Flonghorn-backing-image.s3-us-west-1.amazonaws.com%2Fparrot.qcow2&backingImageChecksum=bd79ab9e6d45abf4f3f0adf552a868074dd235c4698ce7258d521160e0ad79ffe555b94e7d4007add6e1a25f4526885eb25c53ce38f7d344dd4925b9f2cb5d3b
      volumeSnapshotRef:
        name: test-snapshot-existing-backing
        namespace: default
    ```
3. Create a VolumeSnapshot associated with the VolumeSnapshotContent
    ```yaml
    apiVersion: snapshot.storage.k8s.io/v1beta1
    kind: VolumeSnapshot
    metadata:
      name: test-snapshot-existing-backing
    spec:
      volumeSnapshotClassName: longhorn-snapshot-vsc
      source:
        volumeSnapshotContentName: test-existing-backing
    ```
4. Create a PVC with the following yaml
    ```yaml
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: test-restore-existing-backing
    spec:
      storageClassName: longhorn
      dataSource:
        name: test-snapshot-existing-backing
        kind: VolumeSnapshot
        apiGroup: snapshot.storage.k8s.io
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 5Gi
    ```
5. Attach the PVC `test-restore-existing-backing` to a workload and verify the data

#### Scenerios 4: Restore on-demand provisioning BackingImage

- Type `download`
    1. Create a VolumeSnapshotContent with `snapshotHandle` providing the required parameters and BackingImage name `test-bi`
        ```yaml
        apiVersion: snapshot.storage.k8s.io/v1
        kind: VolumeSnapshotContent
        metadata:
          name: test-on-demand-backing
        spec:
          volumeSnapshotClassName: longhorn-snapshot-vsc
          driver: driver.longhorn.io
          deletionPolicy: Delete
          source:
            snapshotHandle: bi://backing?backingImageDataSourceType=download&backingImage=test-bi&url=https%3A%2F%2Flonghorn-backing-image.s3-us-west-1.amazonaws.com%2Fparrot.qcow2&backingImageChecksum=bd79ab9e6d45abf4f3f0adf552a868074dd235c4698ce7258d521160e0ad79ffe555b94e7d4007add6e1a25f4526885eb25c53ce38f7d344dd4925b9f2cb5d3b
          volumeSnapshotRef:
            name: test-snapshot-on-demand-backing
            namespace: default
        ```
    2. Create a VolumeSnapshot associated with the VolumeSnapshotContent
        ```yaml
        apiVersion: snapshot.storage.k8s.io/v1beta1
        kind: VolumeSnapshot
        metadata:
          name: test-snapshot-on-demand-backing
        spec:
          volumeSnapshotClassName: longhorn-snapshot-vsc
          source:
            volumeSnapshotContentName: test-on-demand-backing
        ```
    3. Create a PVC with the following yaml
        ```yaml
        apiVersion: v1
        kind: PersistentVolumeClaim
        metadata:
          name: test-restore-on-demand-backing
        spec:
          storageClassName: longhorn
          dataSource:
            name: test-snapshot-on-demand-backing
            kind: VolumeSnapshot
            apiGroup: snapshot.storage.k8s.io
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi
        ```
    4. Verify BackingImage `test-bi` is created
    5. Attach the PVC `test-restore-on-demand-backing` to a workload and verify the data

- Type `export-from-volume`
    - Success 
        1. Create a Volme `test-vol` and write some data to it.
        2. Create a VolumeSnapshotContent with `snapshotHandle` providing the required parameters and BackingImage name `test-bi`
            ```yaml
            apiVersion: snapshot.storage.k8s.io/v1
            kind: VolumeSnapshotContent
            metadata:
              name: test-on-demand-backing
            spec:
              volumeSnapshotClassName: longhorn-snapshot-vsc
              driver: driver.longhorn.io
              deletionPolicy: Delete
              source:
                snapshotHandle: bi://backing?backingImageDataSourceType=export-from-volume&backingImage=test-bi&volume-name=test-vol&export-type=qcow2
              volumeSnapshotRef:
                name: test-snapshot-on-demand-backing
                namespace: default
            ```
        2. Create a VolumeSnapshot associated with the VolumeSnapshotContent
            ```yaml
            apiVersion: snapshot.storage.k8s.io/v1beta1
            kind: VolumeSnapshot
            metadata:
              name: test-snapshot-on-demand-backing
            spec:
              volumeSnapshotClassName: longhorn-snapshot-vsc
              source:
                volumeSnapshotContentName: test-on-demand-backing
            ```
        3. Create a PVC with the following yaml
            ```yaml
            apiVersion: v1
            kind: PersistentVolumeClaim
            metadata:
              name: test-restore-on-demand-backing
            spec:
              storageClassName: longhorn
              dataSource:
                name: test-snapshot-on-demand-backing
                kind: VolumeSnapshot
                apiGroup: snapshot.storage.k8s.io
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 5Gi
            ```
        4. Verify BackingImage `test-bi` is created
        5. Attach the PVC `test-restore-on-demand-backing` to a workload and verify the data

### Upgrade strategy

No upgrade strategy needed

## Note [optional]

We need to update the docs and examples to reflect the new type of parameter `type` in the VolumeSnapshotClass.

