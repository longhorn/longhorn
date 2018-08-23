# Restoring Volumes for Kubernetes Stateful Sets

Longhorn supports restoring backups, and one of the use cases for this feature
is to restore data for use in a Kubernetes `Stateful Set`, which requires
restoring a volume for each replica that was backed up.

To restore, follow the below instructions based on which plugin you have
deployed. The example below uses a Stateful Set with one volume attached to
each Pod and two replicas.

- [CSI Instructions](#csi-instructions)
- [FlexVolume Instructions](#flexvolume-instructions)

### CSI Instructions
1. Connect to the `Longhorn UI` page in your web browser. Under the `Backup` tab,
select the name of the Stateful Set volume. Click the dropdown menu of the
volume entry and restore it. Name the volume something that can easily be
referenced later for the `Persistent Volumes`.
  - Repeat this step for each volume you need restored.
  - For example, if restoring a Stateful Set with two replicas that had
  volumes named `pvc-01a` and `pvc-02b`, the restore could look like this:  

| Backup Name | Restored Volume   |
|-------------|-------------------|
| pvc-01a     | statefulset-vol-0 |
| pvc-02b     | statefulset-vol-1 |

2. In Kubernetes, create a `Persistent Volume` for each Longhorn volume that was
created. Name the volumes something that can easily be referenced later for the
`Persistent Volume Claims`. `storage` capacity, `numberOfReplicas`,
`storageClassName`, and `volumeHandle` must be replaced below. In the example,
we're referencing `statefulset-vol-0` and `statefulset-vol-1` in Longhorn and
using `longhorn` as our `storageClassName`.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: statefulset-vol-0
spec:
  capacity:
    storage: <size> # must match size of Longhorn volume
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  csi:
    driver: io.rancher.longhorn # driver must match this
    fsType: ext4
    volumeAttributes:
      numberOfReplicas: <replicas> # must match Longhorn volume value
      staleReplicaTimeout: '30'
    volumeHandle: statefulset-vol-0 # must match volume name from Longhorn
  storageClassName: longhorn # must be same name that we will use later
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: statefulset-vol-1
spec:
  capacity:
    storage: <size>  # must match size of Longhorn volume
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  csi:
    driver: io.rancher.longhorn # driver must match this
    fsType: ext4
    volumeAttributes:
      numberOfReplicas: <replicas> # must match Longhorn volume value
      staleReplicaTimeout: '30'
    volumeHandle: statefulset-vol-1 # must match volume name from Longhorn
  storageClassName: longhorn # must be same name that we will use later
```

3. Go to [General Instructions](#general-instructions).

### FlexVolume Instructions
Because of the implementation of `FlexVolume`, creating the Longhorn volumes
from the `Longhorn UI` manually can be skipped. Instead, follow these
instructions:
1. Connect to the `Longhorn UI` page in your web browser. Under the `Backup` tab,
select the name of the `Stateful Set` volume. Click the dropdown menu of the
volume entry and select `Get URL`.
  - Repeat this step for each volume you need restored. Save these URLs for the
  next step.
  - If using NFS backups, the URL will appear similar to:
    - `nfs://longhorn-nfs-svc.default:/opt/backupstore?backup=backup-c57844b68923408f&volume=pvc-59b20247-99bf-11e8-8a92-be8835d7412a`.
  - If using S3 backups, the URL will appear similar to:
    - `s3://backupbucket@us-east-1/backupstore?backup=backup-1713a64cd2774c43&volume=longhorn-testvol-g1n1de`

2. Similar to `Step 2` for CSI, create a `Persistent Volume` for each volume you
want to restore. `storage` capacity, `storageClassName`, and the FlexVolume
`options` must be replaced. This example uses `longhorn` as the
`storageClassName`.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: statefulset-vol-0
spec:
  capacity:
    storage: <size> # must match "size" parameter below
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn # must be same name that we will use later
  flexVolume:
    driver: "rancher.io/longhorn" # driver must match this
    fsType: "ext4"
    options:
      size: <size> # must match "storage" parameter above
      numberOfReplicas: <replicas>
      staleReplicaTimeout: <timeout>
      fromBackup: <backup URL> # must be set to Longhorn backup URL
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: statefulset-vol-1
spec:
  capacity:
    storage: <size> # must match "size" parameter below
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn # must be same name that we will use later
  flexVolume:
    driver: "rancher.io/longhorn" # driver must match this
    fsType: "ext4"
    options:
      size: <size> # must match "storage" parameter above
      numberOfReplicas: <replicas>
      staleReplicaTimeout: <timeout>
      fromBackup: <backup URL> # must be set to Longhorn backup URL
```

3. Go to [General Instructions](#general_instructions).

### General Instructions
**Make sure you have followed either the [CSI](#csi-instructions) or
[FlexVolume](#flexvolume-instructions) instructions before following the steps
in this section.**

1. In the `namespace` the `Stateful Set` will be deployed in, create Persistent
Volume Claims **for each** `Persistent Volume`.
  - The name of the `Persistent Volume Claim` must follow this naming scheme:
  `<name of Volume Claim Template>-<name of Stateful Set>-<index>`. Stateful
  Set Pods are zero-indexed. In this example, the name of the `Volume Claim
  Template` is `data`, the name of the `Stateful Set` is `webapp`, and there
  are two replicas, which are indexes `0` and `1`.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-webapp-0
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 2Gi # must match size from earlier
  storageClassName: longhorn # must match name from earlier
  volumeName: statefulset-vol-0 # must reference Persistent Volume
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-webapp-1
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 2Gi # must match size from earlier
  storageClassName: longhorn # must match name from earlier
  volumeName: statefulset-vol-1 # must reference Persistent Volume
```

2. Create the `Stateful Set`:

```yaml
apiVersion: apps/v1beta2
kind: StatefulSet
metadata:
  name: webapp # match this with the pvc naming scheme
spec:
  selector:
    matchLabels:
      app: nginx # has to match .spec.template.metadata.labels
  serviceName: "nginx"
  replicas: 2 # by default is 1
  template:
    metadata:
      labels:
        app: nginx # has to match .spec.selector.matchLabels
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - name: nginx
        image: k8s.gcr.io/nginx-slim:0.8
        ports:
        - containerPort: 80
          name: web
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: data # match this with the pvc naming scheme
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: longhorn # must match name from earlier
      resources:
        requests:
          storage: 2Gi # must match size from earlier
```

The restored data should now be accessible from inside the `Stateful Set`
`Pods`.
