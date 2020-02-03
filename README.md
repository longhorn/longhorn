# Longhorn

### Status
* Engine: [![Build Status](https://drone-publish.rancher.io/api/badges/longhorn/longhorn-engine/status.svg)](https://drone-publish.rancher.io/longhorn/longhorn-engine) [![Go Report Card](https://goreportcard.com/badge/github.com/rancher/longhorn-engine)](https://goreportcard.com/report/github.com/rancher/longhorn-engine)
* Manager: [![Build Status](https://drone-publish.rancher.io/api/badges/longhorn/longhorn-manager/status.svg)](https://drone-publish.rancher.io/longhorn/longhorn-manager)[![Go Report Card](https://goreportcard.com/badge/github.com/rancher/longhorn-manager)](https://goreportcard.com/report/github.com/rancher/longhorn-manager)
* UI: [![Build Status](https://drone-publish.rancher.io/api/badges/longhorn/longhorn-ui/status.svg)](https://drone-publish.rancher.io/longhorn/longhorn-ui)
* Test: [![Build Status](http://drone-publish.rancher.io/api/badges/longhorn/longhorn-tests/status.svg)](http://drone-publish.rancher.io/longhorn/longhorn-tests)

Longhorn is a distributed block storage system for Kubernetes.

Longhorn is lightweight, reliable, and powerful. You can install Longhorn on an existing Kubernetes cluster with one `kubectl apply` command or using Helm charts. Once Longhorn is installed, it adds persistent volume support to the Kubernetes cluster.

Longhorn implements distributed block storage using containers and microservices. Longhorn creates a dedicated storage controller for each block device volume and synchronously replicates the volume across multiple replicas stored on multiple nodes. The storage controller and replicas are themselves orchestrated using Kubernetes. Here are some notable features of Longhorn:

1. Enterprise-grade distributed storage with no single point of failure
2. Incremental snapshot of block storage
3. Backup to secondary storage (NFS or S3-compatible object storage) built on efficient change block detection
4. Recurring snapshot and backup
5. Automated non-disruptive upgrade. You can upgrade the entire Longhorn software stack without disrupting running volumes!
6. Intuitive GUI dashboard

You can read more technical details of Longhorn [here](http://rancher.com/microservices-block-storage/).

## Current status

Longhorn is beta-quality software. We appreciate your willingness to deploy Longhorn and provide feedback.

The latest release of Longhorn is **v0.7.0**.

## Source code
Longhorn is 100% open source software. Project source code is spread across a number of repos:

1. Longhorn engine -- Core controller/replica logic https://github.com/longhorn/longhorn-engine
1. Longhorn manager -- Longhorn orchestration, includes Flexvolume driver for Kubernetes https://github.com/longhorn/longhorn-manager
1. Longhorn UI -- Dashboard https://github.com/longhorn/longhorn-ui

![Longhorn UI](./longhorn-ui.png)

# Requirements

1.  Docker v1.13+
2.  Kubernetes v1.14+.
3.  `open-iscsi` has been installed on all the nodes of the Kubernetes cluster.
    1. For GKE, recommended Ubuntu as guest OS image since it contains open-iscsi already.
    2. For Debian/Ubuntu, use `apt-get install open-iscsi` to install.
    3. For RHEL/CentOS, use `yum install iscsi-initiator-utils` to install.
4. A host filesystem supports `file extents` feature on the nodes to store the data. Currently we support:
    1. ext4
    2. XFS

# Install

## On Kubernetes clusters Managed by Rancher 2.1 or newer

The easiest way to install Longhorn is to deploy Longhorn from Rancher Catalog.

1. On Rancher UI, select the cluster and project you want to install Longhorn. We recommended to create a new project e.g. `Storage` for Longhorn.
2. Navigate to the `Catalog Apps` screen. Select `Launch`, find Longhorn in the list. Select `View Details`, then click `Launch`. Longhorn will be installed in the `longhorn-system` namespace.

After Longhorn has been successfully installed, you can access the Longhorn UI by navigating to the `Catalog Apps` screen.

One benefit of installing Longhorn through Rancher catalog is Rancher provides authentication to Longhorn UI.

If there is a new version of Longhorn available, you will see an `Upgrade Available` sign on the `Catalog Apps` screen. You can click `Upgrade` button to upgrade Longhorn manager. See more about upgrade [here](#upgrade).

## On any Kubernetes cluster

### Install Longhorn with kubectl
You can install Longhorn on any Kubernetes cluster using following command:

```
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml
```
Google Kubernetes Engine (GKE) requires additional setup in order for Longhorn to function properly. If your are a GKE user, read [this page](docs/gke.md) before proceeding.

### Install Longhorn with Helm
First, you need to initialize Helm locally and [install Tiller into your Kubernetes cluster with RBAC](https://helm.sh/docs/using_helm/#role-based-access-control).

Then download Longhorn repository:
```
git clone https://github.com/longhorn/longhorn.git
```

Now using following command to install Longhorn:
```
# Helm2
helm install ./longhorn/chart --name longhorn --namespace longhorn-system
# or Helm3
helm install longhorn ./longhorn/chart/ --namespace longhorn-system
```
---

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

[See here](docs/upgrade.md) for details.

## Upgrade Longhorn manager

##### On Kubernetes clusters Managed by Rancher 2.1 or newer
Follow [the same steps for installation](#install) to upgrade Longhorn manager

##### Using kubectl
```
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml
```

##### Using Helm
```
helm upgrade longhorn ./longhorn/chart
```

## Upgrade Longhorn engine
After Longhorn Manager was upgraded, Longhorn Engine also need to be upgraded using Longhorn UI. [See here](docs/upgrade.md) for details.

# Create Longhorn Volumes

Before you create Kubernetes volumes, you must first create a storage class. Use following command to create a StorageClass called `longhorn`.

```
kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/master/examples/storageclass.yaml
```

Now you can create a pod using Longhorn like this:
```
kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/master/examples/pvc.yaml
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
### [Settings](./docs/settings.md)
### [Multiple disks](./docs/multidisk.md)
### [iSCSI](./docs/iscsi.md)
### [Kubernetes workload in Longhorn UI](./docs/k8s-workload.md)
### [Storage Tags](./docs/storage-tags.md)
### [Customized default setting](./docs/customized-default-setting.md)
### [Taint Toleration](./docs/taint-toleration.md)

### [Restoring Stateful Set volumes](./docs/restore_statefulset.md)
### [Google Kubernetes Engine](./docs/gke.md)
### [Deal with Kubernetes node failure](./docs/node-failure.md)
### [Use CSI driver on RancherOS/CoreOS + RKE or K3S](./docs/csi-config.md)
### [Restore a backup to an image file](./docs/restore-to-file.md)
### [Disaster Recovery Volume](./docs/dr-volume.md)
### [Recover volume after unexpected detachment](./docs/recover-volume.md)

# Troubleshooting
You can click `Generate Support Bundle` link at the bottom of the UI to download a zip file contains Longhorn related configuration and logs.

See [here](./docs/troubleshooting.md) for the troubleshooting guide.

# Uninstall Longhorn

### Using kubectl
1. To prevent damaging the Kubernetes cluster, we recommend deleting all Kubernetes workloads using Longhorn volumes (PersistentVolume, PersistentVolumeClaim, StorageClass, Deployment, StatefulSet, DaemonSet, etc) first.

2. Create the uninstallation job to clean up CRDs from the system and wait for success:
  ```
  kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/master/uninstall/uninstall.yaml
  kubectl get job/longhorn-uninstall -w
  ```

Example output:
```
$ kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/master/uninstall/uninstall.yaml
serviceaccount/longhorn-uninstall-service-account created
clusterrole.rbac.authorization.k8s.io/longhorn-uninstall-role created
clusterrolebinding.rbac.authorization.k8s.io/longhorn-uninstall-bind created
job.batch/longhorn-uninstall created

$ kubectl get job/longhorn-uninstall -w
NAME                 COMPLETIONS   DURATION   AGE
longhorn-uninstall   0/1           3s         3s
longhorn-uninstall   1/1           20s        20s
^C
```

3. Remove remaining components:
  ```
  kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml
  kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/master/uninstall/uninstall.yaml
  ```
 
Tip: If you try `kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml` first and get stuck there, 
pressing `Ctrl C` then running `kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/master/uninstall/uninstall.yaml` can also help you remove Longhorn. Finally, don't forget to cleanup remaining components.

### Using Helm
```
helm delete longhorn --purge
```

## Community
Longhorn is an open source software, so contribution are greatly welcome. Please read [Code of Conduct](./CODE_OF_CONDUCT.md) and [Contributing Guideline](./CONTRIBUTING.md) before contributing.

Contributing code is not the only way of contributing. We value feedbacks very much and many of the Longhorn features are originated from users' feedback. If you have any feedbacks, feel free to [file an issue](https://github.com/longhorn/longhorn/issues/new?title=*Summarize%20your%20issue%20here*&body=*Describe%20your%20issue%20here*%0A%0A---%0AVersion%3A%20``) and talk to the developers at the [CNCF](https://slack.cncf.io/) [#longhorn](https://cloud-native.slack.com/messages/longhorn) slack channel.

## License

Copyright (c) 2014-2019 The Longhorn Authors

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

### Longhorn is a [CNCF Sandbox Project](https://www.cncf.io/sandbox-projects/)

![Longhorn is a CNCF Sandbox Project](https://github.com/cncf/artwork/blob/master/other/cncf/horizontal/color/cncf-color.png)
