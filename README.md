# Longhorn

Longhorn is a distributed block storage system built using containers and microservices. Longhorn creates a dedicated storage controller for each block device volume and sychronously replicates the volume across multiple replicas stored on multiple hosts. The storage controller and replicas are implemented using containers and are managed using a container orchestration system.

Longhorn is lightweight, reliable, and easy-to-use. It is particularly suitable as persistent storage for containers. It supports snapshots, backups, and even allows you to schedule recurring snapshots and backups!

You can read more details of Longhorn and its design here: http://rancher.com/microservices-block-storage/.

Longhorn is experimental software. We appreciate your comments as we continue to work on it!

## Source Code
Longhorn is 100% open source software. Project source code is spread across a number of repos:

1. Longhorn engine -- core controller/replica logic https://github.com/rancher/longhorn-engine
1. Longhorn manager -- Longhorn orchestration https://github.com/rancher/longhorn-manager
1. Longhorn UI -- Dashboard https://github.com/rancher/longhorn-ui
1. Longhorn storage driver -- Docker driver. we're working on a PR to [Rancher Storage](http://github.com/rancher/storage), will update later.

# Deploy in Docker

### Build your own Longhorn 

In order to build your own longhorn, you need to build a couple of separate components as stated above.

Building process has been described in each component above.

Each component will produce a Docker image at the end of building process. You can use it to swap the correlated lines in the [deploying script](https://github.com/rancher/longhorn/blob/master/deploy/longhorn-deploy-node.sh#L5) to test your own build.

## Requirements

Longhorn requires one or more hosts running the following software:

1. We have tested with Ubuntu 16.04. Other Linux distros, including CentOS and RancherOS, will be tested in the future.
2. Make sure `open-iscsi` package is installed on the host. If `open-iscsi` package is installed, the `iscsiadm` executable should be available. Ubuntu Server install by default includes `open-iscsi`. Ubuntu Desktop doesn't.

## Single node setup

You can setup all the components required to run Longhorn on a single Linux host. In this case Longhorn will create multiple replicas for the same volume on the same host. This is therefore not a production-grade setup.

You can setup Longhorn by running a single script:
```
git clone https://github.com/rancher/longhorn
cd longhorn/deploy
./longhorn-setup-single-node-env.sh
```
The script will setup all the components required to run Longhorn, including the etcd server, longhorn-manager, and longhorn-ui automatically.

After the script completes, it produces output like this:
```
Longhorn is up at port 8080
```
Congratulations! Now you have Longhorn running on the host and can access the UI at `http://<host_ip>:8080`.

### Setup a simple NFS server for storing backups
Longhorn's backup feature requires an NFS server or an S3 endpoint. You can setup a simple NFS server on the same host and use that to store backups.
```
# Make sure you have nfs-kernel-server package installed.
sudo apt-get install nfs-kernel-server
./deploy-simple-nfs.sh
```
This NFS server won't save any data after you delete the container. It's for development and testing only.

After this script completes, you will see:
```
Use the following URL as the Backup Target in the Longhorn UI:
nfs://10.0.0.5:/opt/backupstore
```
Open Longhorn UI, go to `Setting`, fill the `Backup Target` field with the URL above, click `Save`. Now you should able to use the backup feature of Longhorn.

## Create a Longhorn volume from Docker CLI

You can now create a persistent Longhorn volume from Docker CLI using the Longhorn volume driver and use the volume in Docker containers.

Docker volume driver is `longhorn`.

You can run the following on any of the Longhorn hosts:
```
docker volume create -d longhorn vol1
docker run -it --volume-driver longhorn -v vol1:/vol1 ubuntu bash
```

## Multi-host setup

Single-host setup is not suitable for production use. You can find instructions for multi-host setup here: https://github.com/rancher/longhorn/wiki/Multi-Host-Setup-Guide


# Deploy in Kubernetes

## Requirements

1. Docker v1.13+
2. Kubernetes v1.8+
4. Make sure `jq` has been installed in all nodes of kubernetes.
5. Make sure those commands `findmnt`, `mount`, `umount`, `grep`, `awk` and `blkid` could work correctly in all nodes of kubernetes.
6. Make sure `curl` has been installed in all nodes of kubernetes.
7. Make sure `open-iscsi` has been installed in all nodes of kubernetes.

## Deployment
The deployment for longhorn in your kubernetes is very easy. You only need to execute this command `kubectl create -f deploy/deployment-in-k8s.yaml`.

when you see those pods has started correctly as follows, you deploy the longhorn successfully.

```
NAME                           READY     STATUS    RESTARTS   AGE
longhorn-driver-7b8l7          1/1       Running   0          3h
longhorn-driver-tqrlw          1/1       Running   0          3h
longhorn-manager-67mqs         1/1       Running   0          3h
longhorn-manager-bxfw9         1/1       Running   0          3h
longhorn-ui-76674c87b9-89swr   1/1       Running   0          3h
```

##  How to use the longhorn volume in your pod
There are serveral ways to use the longhorn volume.
### Pod with Longhorn volume
The following YAML file shows the definition of a pod that makes the Longhorn attach a volume to be used by the pod.

```
apiVersion: v1
kind: Pod
metadata:
  name: volume-test
  namespace: default
spec:
  containers:
  - name: volume-test
    image: nginx
    imagePullPolicy: IfNotPresent
    volumeMounts:
    - name: vol
      mountPath: /data
    ports:
    - containerPort: 80
  volumes:
  - name: vol
    flexVolume:
      driver: "rancher.io/longhorn"
      fsType: "ext4"
      options:
        size: "2G"
        numberOfReplicas: "2"
        staleReplicaTimeout: "20"
        fromBackup: ""
```

Notice this field in YAML file `flexVolume.driver "rancher.io/longhorn"`, this is the name of longhorn driver and it specifies which FlexVolume plug-in shoule be used. There are some
critical fields in `options` user should fill.
 
Option  | Description
------------- | -------------
size    |  Specify the capacity of the volume in longhorn and the unit should be `G` (Required)
numberOfReplicas | The number of replica (HA feature) for volume in longhorn (Required)
staleReplicaTimeout  | How long the longhorn controller will discover the replica is timeout (Optional)
fromBackup | Specify where user want to restore the volume from (Optional)

### Longhorn Persistent Volume

This example shows how to use a YAML definition to manage Persistent Volume(PV).

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-test
spec:
  capacity:
    storage: 2Gi 
  accessModes:
    - ReadWriteOnce
  flexVolume:
    driver: "rancher.io/longhorn"
    fsType: "ext4"
    options:
      size: "2G"
      numberOfReplicas: "2"
      staleReplicaTimeout: "20"
      fromBackup: ""
```

The next YAML shows a Persistent Volume Claim (PVC) that carves out 2Gi out of the PV defined above.

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pv-test
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
```
The claim can then be used by a pod in a YAML definition as shown below:

```
apiVersion: v1
kind: Pod
metadata:
  name: volume-test
  namespace: default
spec:
  containers:
  - name: volume-test
    image: nginx
    imagePullPolicy: IfNotPresent
    volumeMounts:
    - name: voll
      mountPath: /data
    ports:
    - containerPort: 80
  volumes:
  - name: voll
    persistentVolumeClaim:
      claimName: pv-test
```

## Setup a simple NFS server for storing backups

### Requirements

1. Make sure `nfs-kernel-server` has been installed in all nodes of kubernetes.

### Deployment

Longhorn's backup feature requires an NFS server or an S3 endpoint. You can setup a simple NFS server on the same host and use that to store backups.

The deployment for the simple nfs server is also very easy. 

```
kubectl creare -f deploy/deploy-simple-nfs.yaml
```

This NFS server won't save any data after you delete the Deployment. It's for development and testing only.

After this script completes, you will see:

Use the following URL as the Backup Target in the Longhorn UI:

```
nfs://longhorn-nfs:/opt/backupstore
```
Open Longhorn UI, go to Setting, fill the Backup Target field with the URL above, click Save. Now you should able to use the backup feature of Longhorn.

## License
Copyright (c) 2014-2017 [Rancher Labs, Inc.](http://rancher.com)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

