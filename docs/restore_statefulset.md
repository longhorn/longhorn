# Restoring Volumes for Kubernetes StatefulSets

Longhorn supports restoring backups, and one of the use cases for this feature
is to restore data for use in a Kubernetes `StatefulSet`, which requires
restoring a volume for each replica that was backed up.

To restore, follow the below instructions.
The example below uses a StatefulSet with one volume attached to
each Pod and two replicas.


1. Connect to the `Longhorn UI` page in your web browser. Under the `Backup` tab,
select the name of the StatefulSet volume. Click the dropdown menu of the
volume entry and restore it. Name the volume something that can easily be
referenced later for the `Persistent Volumes`.
  - Repeat this step for each volume you need restored.
  - For example, if restoring a StatefulSet with two replicas that had
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
    driver: driver.longhorn.io # driver must match this
    fsType: ext4
    volumeAttributes:
      numberOfReplicas: <replicas> # must match Longhorn volume value
      staleReplicaTimeout: '30' # in minutes
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
    driver: driver.longhorn.io # driver must match this
    fsType: ext4
    volumeAttributes:
      numberOfReplicas: <replicas> # must match Longhorn volume value
      staleReplicaTimeout: '30'
    volumeHandle: statefulset-vol-1 # must match volume name from Longhorn
  storageClassName: longhorn # must be same name that we will use later
```


3. In the `namespace` the `StatefulSet` will be deployed in, create Persistent
Volume Claims **for each** `Persistent Volume`.
  - The name of the `Persistent Volume Claim` must follow this naming scheme:
  `<name of Volume Claim Template>-<name of StatefulSet>-<index>`. Stateful
  Set Pods are zero-indexed. In this example, the name of the `Volume Claim
  Template` is `data`, the name of the `StatefulSet` is `webapp`, and there
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

4. Create the `StatefulSet`:

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

The restored data should now be accessible from inside the `StatefulSet`
`Pods`.
