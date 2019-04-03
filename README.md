# Longhorn

Longhorn is a distributed block storage system for Kubernetes.

Longhorn is lightweight, reliable, and powerful. You can install Longhorn on an existing Kubernetes cluster with one `kubectl apply` command or using Helm charts. Once Longhorn is installed, it adds persistent volume support to the Kubernetes cluster.

Longhorn implements distributed block storage using containers and microservices. Longhorn creates a dedicated storage controller for each block device volume and sychronously replicates the volume across multiple replicas stored on multiple nodes. The storage controller and replicas are themselves orchestrated using Kubernetes. Here are some notable features of Longhorn:

1. Enterprise-grade distributed storage with no single point of failure
2. Incremental snapshot of block storage
3. Backup to secondary storage (NFS or S3-compatible object storage) built on efficient change block detection
4. Recuring snapshot and backup
5. Automated non-disruptive upgrade. You can upgrade the entire Longhorn software stack without disrupting running volumes!
6. Intuitive GUI dashboard

You can read more technical details of Longhorn [here](http://rancher.com/microservices-block-storage/).

## Current status

Longhorn is alpha-quality software. We appreciate your willingness to deploy Longhorn and provide feedback.

The latest release of Longhorn is **v0.4.1**.

## Source code
Longhorn is 100% open source software. Project source code is spread across a number of repos:

1. Longhorn engine -- Core controller/replica logic https://github.com/rancher/longhorn-engine
1. Longhorn manager -- Longhorn orchestration, includes Flexvolume driver for Kubernetes https://github.com/rancher/longhorn-manager
1. Longhorn UI -- Dashboard https://github.com/rancher/longhorn-ui

![Longhorn UI](https://s3-us-west-1.amazonaws.com/rancher-longhorn/Longhorn_UI.png)

# Requirements

1.  Docker v1.13+
2.  Kubernetes v1.8+. Recommend v1.12+.
3.  `open-iscsi` has been installed on all the nodes of the Kubernetes cluster.
    1. For GKE, recommended Ubuntu as guest OS image since it contains open-iscsi already.
    2. For Debian/Ubuntu, use `apt-get install open-iscsi` to install.
    3. For RHEL/CentOS, use `yum install iscsi-initiator-utils` to install.

# Install

## On Kubernetes clusters Managed by Rancher 2.1 or newer

The easiest way to install Longhorn is to deploy Longhorn from Rancher Catalog.

1. On Rancher UI, select the cluster and project you want to install Longhorn. We recommended to create a new project e.g. `Storage` for Longhorn.
2. Navigate to the `Catalog Apps` screen. Select `Launch`, find Longhorn in the list. Select `View Details`, then click `Launch`. Longhorn will be installed in the `longhorn-system` namespace.
    
After Longhorn has been successfully installed, you can access the Longhorn UI by navigating to the `Catalog Apps` screen.

One benefit of installing Longhorn through Rancher catalog is Rancher provides authentication to Longhorn UI.

If there is a new version of Longhorn available, you will see an `Upgrade Available` sign on the `Catalog Apps` screen. You can click `Upgrade` button to upgrade Longhorn manager. See more about upgrade [here](#upgrade).

## On any Kubernetes cluster

You can install Longhorn on any Kubernetes cluster using following command:

```
kubectl apply -f https://raw.githubusercontent.com/rancher/longhorn/master/deploy/longhorn.yaml
```

Google Kubernetes Engine (GKE) requires additional setup in order for Longhorn to function properly. If your are a GKE user, read [this page](docs/gke.md) before proceeding.

Longhorn will be installed in the namespace `longhorn-system`

One of the two available drivers (CSI and Flexvolume) would be chosen automatically based on the version of Kubernetes you use. See [here](docs/driver.md) for details.

A successful CSI-based deployment looks like this:
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

### Accessing the UI

You can run `kubectl -n longhorn-system get svc` to get the external service IP for UI:

```
NAME                TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
longhorn-backend    ClusterIP      10.20.248.250   <none>           9500/TCP       58m
longhorn-frontend   LoadBalancer   10.20.245.110   100.200.200.123  80:30697/TCP   58m

```

If the Kubernetes Cluster supports creating LoadBalancer, you can use `EXTERNAL-IP`(`100.200.200.123` in the case above) of `longhorn-frontend` to access the Longhorn UI. Otherwise you can use `<node_ip>:<port>` (port is `30697`in the case above) to access the UI.

Noted that the UI is unauthenticated when you installed Longhorn using YAML file.

# Upgrade

Since v0.3.3, Longhorn is able to perform fully-automated non-disruptive upgrade, meaning the upgrade process won't disrupt  the access to existing volumes.

If you're upgrading from Longhorn v0.3.0 or newer:

1. Follow [the same steps for installation](#install) to upgrade Longhorn manager
2. After upgraded manager, follow [the steps here](docs/upgrade.md#upgrade-longhorn-engine) to upgrade Longhorn engine for existing volumes.
    1. For non distruptive upgrade, follow [the live upgrade steps here](./docs/upgrade.md#live-upgrade)

For more details about upgrade in Longhorn or upgrade from older versions, [see here](docs/upgrade.md).

# Create Longhorn Volumes 

Before you create Kubernetes volumes, you must first create a storage class. Use following command to create a StorageClass called `longhorn`.

```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/master/examples/storageclass.yaml
```

Now you can create a pod using Longhorn like this:
```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/master/examples/pvc.yaml
```

The above yaml file contains two parts:
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

# Documentation

### [Snapshot and Backup](./docs/snapshot-backup.md)
### [Volume operations](./docs/volume.md)
### [Multiple disks](./docs/multidisk.md)
### [iSCSI](./docs/iscsi.md)
### [Base image](./docs/base-image.md)

### [Restoring Stateful Set volumes](./docs/restore_statefulset.md)
### [Google Kubernetes Engine](./docs/gke.md)
### [Deal with Kubernetes node failure](./docs/node-failure.md)
### [Use CSI driver on RancherOS/CoreOS + RKE or K3S](./docs/csi-config.md)
### [Restore a backup to an image file](./docs/restore-to-file.md)

# Troubleshooting
You can click `Generate Support Bundle` link at the bottom of the UI to download a zip file contains Longhorn related configuration and logs.

See [here](./docs/troubleshooting.md) for the troubleshooting guide.

# Uninstall Longhorn

1. To prevent damaging the Kubernetes cluster, we recommend deleting all Kubernetes workloads using Longhorn volumes (PersistentVolume, PersistentVolumeClaim, StorageClass, Deployment, StatefulSet, DaemonSet, etc) first.

2. Create the uninstallation job to clean up CRDs from the system and wait for success:
  ```
  kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/master/uninstall/uninstall.yaml
  kubectl -n longhorn-system get job/longhorn-uninstall -w
  ```

Example output:
```
$ kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/master/uninstall/uninstall.yaml
job.batch/longhorn-uninstall created
$ kubectl -n longhorn-system get job/longhorn-uninstall -w
NAME                 DESIRED   SUCCESSFUL   AGE
longhorn-uninstall   1         0            3s
longhorn-uninstall   1         1            45s
^C
```

3. Remove remaining components:
  ```
  kubectl delete -f https://raw.githubusercontent.com/rancher/longhorn/master/deploy/longhorn.yaml
  ```

## License

Copyright (c) 2014-2019  [Rancher Labs, Inc.](http://rancher.com/)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
