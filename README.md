# Longhorn

Longhorn is a distributed block storage system for Kubernetes. Longhorn is lightweight, reliable, and easy-to-use. You can deploy Longhorn on an existing Kubernetes cluster with one simple command. Once Longhorn is deployed, it adds persistent volume support to the Kubernetes cluster.

Longhorn implements distributed block storage using containers and microservices. Longhorn creates a dedicated storage controller for each block device volume and sychronously replicates the volume across multiple replicas stored on multiple nodes. The storage controller and replicas are themselves orchestrated using Kubernetes. Longhorn supports snapshots, backups, and even allows you to schedule recurring snapshots and backups!

You can read more details of Longhorn and its design [here](http://rancher.com/microservices-block-storage/).

Longhorn is a work in progress. We appreciate your comments as we continue to work on it!

## Source Code
Longhorn is 100% open source software. Project source code is spread across a number of repos:

1. Longhorn Engine -- Core controller/replica logic https://github.com/rancher/longhorn-engine
1. Longhorn Manager -- Longhorn orchestration, includes Flexvolume driver for Kubernetes https://github.com/rancher/longhorn-manager
1. Longhorn UI -- Dashboard https://github.com/rancher/longhorn-ui

# Demo

[![Longhorn v0.2 Demo](https://asciinema.org/a/172720.png)](https://asciinema.org/a/172720?autoplay=1&loop=1&speed=2)

# Requirements

## Minimal Requirements

1.  Docker v1.13+
2.  Kubernetes v1.8+
3.  Make sure open-iscsi has been installed in all nodes of the Kubernetes cluster. For GKE, recommended Ubuntu as guest OS image since it contains open-iscsi already.

## Kubernetes Driver Requirements

Longhorn can be used in Kubernetes to provide persistent storage through either Longhorn Container Storage Interface (CSI) driver or Longhorn Flexvolume driver. Longhorn will automatically deploy one of the drivers, depends on user's Kubernetes cluster's setup. User can also specify the driver in the deployment yaml file. CSI is preferred.

### Requirement for the CSI driver

1. Kubernetes v1.10+
   1. CSI is in beta release for this version of Kubernetes, and enabled by default.
2. Mount Propagation feature gate enabled.
   1. It's enabled by default in Kubernetes v1.10. But some early versions of RKE may not enable it.
3. If above conditions cannot be met, Longhorn will falls back to use Flexvolume driver.

### Requirement for the Flexvolume driver

1.  Kubernetes v1.8+
2.  Make sure `curl`, `findmnt`, `grep`, `awk` and `blkid` has been installed in the every node of the Kubernetes cluster.
3.  User need to know the volume plugin directory in order to setup the driver correctly.
    1.  Rancher RKE: `/var/lib/kubelet/volumeplugins`
    2.  Google GKE: `/home/kubernetes/flexvolume`
    3.  For other distro, please find the correct directory by running `ps aux|grep kubelet` on the host and check the `--volume-plugin-dir` parameter. If there is none, it would be the default value `/usr/libexec/kubernetes/kubelet-plugins/volume/exec/` .

# Deployment

Create the deployment of Longhorn in your Kubernetes cluster is easy.

If you're using Rancher RKE, or other distro with Kubernetes v1.10+ and Mount Propagation enabled, you can just do:
```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/v0.3-rc/deploy/longhorn.yaml
```
If you're using Flexvolume driver with other Kubernetes Distro, replace the value of $FLEXVOLUME_DIR in the following command with your own Flexvolume Directory as specified above.
```
FLEXVOLUME_DIR="/home/kubernetes/flexvolume/"
curl -s https://raw.githubusercontent.com/rancher/longhorn/v0.3-rc/deploy/longhorn.yaml|sed "s#^\( *\)value: \"/var/lib/kubelet/volumeplugins\"#\1value: \"${FLEXVOLUME_DIR}\"#g" > longhorn.yaml
kubectl create -f longhorn.yaml
```
For Google Kubernetes Engine (GKE) users, see  [here](#google-kubernetes-engine)  before proceed.

Longhorn Manager and Longhorn Driver will be deployed as daemonsets in a separate namespace called `longhorn-system`, as you can see in the yaml file.

When you see those pods has started correctly as follows, you've deployed the Longhorn successfully.

Deployed with CSI driver:
```
# kubectl -n longhorn-system get pod
NAME                                        READY     STATUS    RESTARTS   AGE
csi-attacher-0                              1/1       Running   0          6h
csi-provisioner-0                           1/1       Running   0          6h
engine-image-ei-57b85e25-8v65d              1/1       Running   0          7d
engine-image-ei-57b85e25-gjjs6              1/1       Running   0          7d
engine-image-ei-57b85e25-t2787              1/1       Running   0          7d
longhorn-csi-plugin-4cpk2                   2/2       Running   0          6h
longhorn-csi-plugin-ll6mq                   2/2       Running   0          6h
longhorn-csi-plugin-smlsh                   2/2       Running   0          6h
longhorn-driver-deployer-7b5bdcccc8-fbncl   1/1       Running   0          6h
longhorn-manager-7x8x8                      1/1       Running   0          6h
longhorn-manager-8kqf4                      1/1       Running   0          6h
longhorn-manager-kln4h                      1/1       Running   0          6h
longhorn-ui-f849dcd85-cgkgg                 1/1       Running   0          5d
```
Or with Flexvolume driver
```
# kubectl -n longhorn-system get pod
NAME                                        READY     STATUS    RESTARTS   AGE
engine-image-ei-57b85e25-8v65d              1/1       Running   0          7d
engine-image-ei-57b85e25-gjjs6              1/1       Running   0          7d
engine-image-ei-57b85e25-t2787              1/1       Running   0          7d
longhorn-driver-deployer-5469b87b9c-b9gm7   1/1       Running   0          2h
longhorn-flexvolume-driver-lth5g            1/1       Running   0          2h
longhorn-flexvolume-driver-tpqf7            1/1       Running   0          2h
longhorn-flexvolume-driver-v9mrj            1/1       Running   0          2h
longhorn-manager-7x8x8                      1/1       Running   0          9h
longhorn-manager-8kqf4                      1/1       Running   0          9h
longhorn-manager-kln4h                      1/1       Running   0          9h
longhorn-ui-f849dcd85-cgkgg                 1/1       Running   0          5d
```

## Access the UI

Use `kubectl -n longhorn-system get svc` to get the external service IP for UI:

```
NAME                TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
longhorn-backend    ClusterIP      10.20.248.250   <none>           9500/TCP       58m
longhorn-frontend   LoadBalancer   10.20.245.110   100.200.200.123   80:30697/TCP   58m

```

If the Kubernetes Cluster supports creating LoadBalancer, user can then use `EXTERNAL-IP`(`100.200.200.123` in the case above) of `longhorn-frontend` to access the Longhorn UI. Otherwise the user can use `<node_ip>:<port>` (port is `30697`in the case above) to access the UI.

Longhorn UI would connect to the Longhorn Manager API, provides the overview of the system, the volume operations, and the snapshot/backup operations. It's highly recommended for the user to check out Longhorn UI.

Notice the current UI is unauthenticated.

# Use the Longhorn with Kubernetes

Longhorn provides persistent volume directly to Kubernetes through one of the Longhorn drivers. No matter which driver you're using, you can use Kubernetes StorageClass to provision your persistent volumes.

Use following command to create a default Longhorn StorageClass named `longhorn`.

```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/v0.3-rc/examples/storageclass.yaml
```

Now you can create a pod using Longhorn like this:
```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/v0.3-rc/examples/pvc.yaml
```

The yaml contains two parts:
1. Create a PVC using Longhorn StorageClass.
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-volv-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 2Gi
```

2. Use it in the a Pod as a persistent volume:
```
apiVersion: v1
kind: Pod
metadata:
  name: volume-test
  namespace: default
spec:
  containers:
  - name: volume-test
    image: nginx:stable-alpine
    imagePullPolicy: IfNotPresent
    volumeMounts:
    - name: volv
      mountPath: /data
    ports:
    - containerPort: 80
  volumes:
  - name: volv
    persistentVolumeClaim:
      claimName: longhorn-volv-pvc
```
More examples are available at `./examples/`

# Feature Usage
### Snapshot
A snapshot in Longhorn represents a volume state at a given time, stored in the same location of volume data on physical disk of the host. Snapshot creation is instant in Longhorn.

User can revert to any previous taken snapshot using the UI. Since Longhorn is a distributed block storage, please make sure the Longhorn volume is umounted from the host when revert to any previous snapshot, otherwise it will confuse the node filesystem and cause corruption.
### Backup
A backup in Longhorn represents a volume state at a given time, stored in the BackupStore which is outside of the Longhorn System. Backup creation will involving copying the data through the network, so it will take time.

A corresponding snapshot is needed for creating a backup. And user can choose to backup any snapshot previous created.

A BackupStore is a NFS server or S3 compatible server.

A BackupTarget represents a BackupStore in the Longhorn System. The BackupTarget can be set at `Settings/General/BackupTarget`

If user is using a S3 compatible server as the BackupTarget, the BackupTargetSecret is needed for authentication informations. User need to manually create it as a Kubernetes Secret in the `longhorn-system` namespace. See below for details.

#### Setup a testing backupstore
We provides two testing purpose backupstore based on NFS server and Minio S3 server for testing, in `./deploy/backupstores`.

Use following command to setup a Minio S3 server for BackupStore after `longhorn-system` was created.
```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/v0.3-rc/deploy/backupstores/minio-backupstore.yaml
```

Now set `Settings/General/BackupTarget` to
```
s3://backupbucket@us-east-1/backupstore
```
And `Setttings/General/BackupTargetSecret` to
```
minio-secret
```
Click the `Backup` tab in the UI, it should report an empty list without error out.

The `minio-secret` yaml looks like this:
```
apiVersion: v1
kind: Secret
metadata:
  name: minio-secret
  namespace: longhorn-system
type: Opaque
data:
  AWS_ACCESS_KEY_ID: bG9uZ2hvcm4tdGVzdC1hY2Nlc3Mta2V5 # longhorn-test-access-key
  AWS_SECRET_ACCESS_KEY: bG9uZ2hvcm4tdGVzdC1zZWNyZXQta2V5 # longhorn-test-secret-key
  AWS_ENDPOINTS: aHR0cDovL21pbmlvLXNlcnZpY2UuZGVmYXVsdDo5MDAw # http://minio-service.default:9000
```
Notice the secret must be created in the `longhorn-system` namespace for Longhorn to access.

### Recurring Snapshot and Backup
Longhorn supports recurring snapshot and backup for volumes. User only need to set when he/she wish to take the snapshot and/or backup, and how many snapshots/backups needs to be retains, then Longhorn will automatically create snapshot/backup for the user at that time, as long as the volume is attached to a node.

User can find the setting for the recurring snapshot and backup in the `Volume Detail` page.

## Other topics

### [Upgrade from v0.2](./docs/upgrade.md)
### [Multiple disks support](./docs/multidisk.md)
### [iSCSI support](./docs/iscsi.md)
### [Google Kubernetes Engine](./docs/gke.md)
### [Troubleshotting](./docs/troubleshooting.md)
### [Restoring Stateful Set volumes](./docs/restore_statefulset.md)

## Uninstall Longhorn

Longhorn CRD has finalizers in them, so user should delete the volumes and related resource first, give manager a chance to clean up after them.

### 1. Clean up volume and related resources

```
kubectl -n longhorn-system delete volumes.longhorn.rancher.io --all

```

Check the result using:

```
kubectl -n longhorn-system get volumes.longhorn.rancher.io
kubectl -n longhorn-system get engines.longhorn.rancher.io
kubectl -n longhorn-system get replicas.longhorn.rancher.io

```

Make sure all reports `No resources found.` before continuing.

### 2. Clean up engine images and nodes

```
kubectl -n longhorn-system delete engineimages.longhorn.rancher.io --all
kubectl -n longhorn-system delete nodes.longhorn.rancher.io --all

```

Check the result using:

```
kubectl -n longhorn-system get engineimages.longhorn.rancher.io
kubectl -n longhorn-system get nodes.longhorn.rancher.io

```

Make sure all reports `No resources found.` before continuing.

### 3. Uninstall Longhorn System
```
kubectl delete -f https://raw.githubusercontent.com/rancher/longhorn/v0.3-rc/deploy/longhorn.yaml
```

## License

Copyright (c) 2014-2018  [Rancher Labs, Inc.](http://rancher.com/)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
