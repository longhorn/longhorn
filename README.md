# Longhorn

Longhorn is a distributed block storage system built using containers and microservices. Longhorn creates a dedicated storage controller for each block device volume and sychronously replicates the volume across multiple replicas stored on multiple hosts. The storage controller and replicas are implemented using containers and are managed using a container orchestration system.

Longhorn is lightweight, reliable, and easy-to-use. It is particularly suitable as persistent storage for containers. It supports snapshots, backups, and even allows you to schedule recurring snapshots and backups!

You can read more details of Longhorn and its design here: http://rancher.com/microservices-block-storage/.

Longhorn is an experimental software. We appreciate your comments as we continue to work on it!

## Source Code
Longhorn is 100% open source software. Project source code is spread across a number of repos:

1. Longhorn Engine -- Core controller/replica logic https://github.com/rancher/longhorn-engine
1. Longhorn Manager -- Longhorn orchestration, includes Flexvolume Driver for Kubernetes https://github.com/rancher/longhorn-manager
1. Longhorn UI -- Dashboard https://github.com/rancher/longhorn-ui

# Deploy in Kubernetes

## Requirements

1. Docker v1.13+
2. Kubernetes v1.8+
3. Make sure `jq`, `curl`, `findmnt`, `grep`, `awk` and `blkid` has been installed in all nodes of the Kubernetes cluster.
4. Make sure `open-iscsi` has been installed in all nodes of the Kubernetes cluster.

## Deployment
Create the deployment of Longhorn in your Kubernetes cluster is easy. For example, for GKE, you will only need to deploy the `deploy/example.yaml`. You may need to modify the yaml file a bit to match your own environment, e.g. the Flexvolume plugin directory.

The configuration yaml will be slight different for each environment. Here we take GKE as a example:

1. GKE requires user to manually claim himself as cluster admin to enable RBAC, using `kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=<name@example.com>` (in which `name@example.com` is the user's account name in GCE, and it's case sensitive). See [here](https://cloud.google.com/kubernetes-engine/docs/how-to/role-based-access-control) for details.
2. The default Flexvolume plugin directory is different in GKE 1.8+, which is at `/home/kubernetes/flexvolume`. You can find it by running `ps aux|grep kubelet` and check the `--flex-volume-plugin-dir` parameter. If there is none, the default `/usr/libexec/kubernetes/kubelet-plugins/volume/exec/` will be used.

Longhorn Manager and Longhorn Driver will be deployed as daemonset, as you can see in the yaml file.

When you see those pods has started correctly as follows, you've deployed the Longhorn successfully.

```
NAME                           READY     STATUS    RESTARTS   AGE
longhorn-driver-7b8l7          1/1       Running   0          3h
longhorn-driver-tqrlw          1/1       Running   0          3h
longhorn-driver-xqkjg          1/1       Running   0          3h
longhorn-manager-67mqs         1/1       Running   0          3h
longhorn-manager-bxfw9         1/1       Running   0          3h
longhorn-manager-5kj2f         1/1       Running   0          3h
longhorn-ui-76674c87b9-89swr   1/1       Running   0          3h
```

## Access the UI
Use `kubectl get svc` to get the external service IP for UI:

```
NAME                TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
kubernetes          ClusterIP      10.20.240.1     <none>           443/TCP        9d
longhorn-backend    ClusterIP      10.20.248.250   <none>           9500/TCP       58m
longhorn-frontend   LoadBalancer   10.20.245.110   100.200.200.123   80:30697/TCP   58m
```

Then user can use `EXTERNAL-IP`(`100.200.200.123` in the case above) of `longhorn-frontend` to access the Longhorn UI.

##  How to use the Longhorn Volume in your pod

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

Notice this field in YAML file `flexVolume.driver "rancher.io/longhorn"`. It specifies Longhorn FlexVolume plug-in shoule be used. There are some options fields in `options` user can fill.

Option  | Required | Description
------------- | ----|---------
size    |  Yes | Specify the capacity of the volume in longhorn and the unit should be `G`
numberOfReplicas | Yes | The number of replica (HA feature) for volume in this Longhorn volume
fromBackup | No | In Longhorn Backup URL. Specify where user want to restore the volume from (Optional)

### Persistent Volume

This example shows how to use a YAML definition to manage Persistent Volume(PV).

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: longhorn-volv-pv
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  flexVolume:
    driver: "rancher.io/longhorn"
    fsType: "ext4"
    options:
      size: "2G"
      numberOfReplicas: "2"
      staleReplicaTimeout: "20"
      fromBackup: ""
```

The next YAML shows a Persistent Volume Claim (PVC) that matched the PV defined above.
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
    - name: volv
      mountPath: /data
    ports:
    - containerPort: 80
  volumes:
  - name: volv
    persistentVolumeClaim:
      claimName: longhorn-volv-pvc
```

## Setup a simple NFS server for storing backups

Longhorn supports backing up to a NFS server. In order to use this feature, you need to have a NFS server running and accessible in the Kubernetes cluster. Here we provides a simple way help to setup a testing NFS server.

### Requirements

1. Make sure `nfs-kernel-server` has been installed in all nodes of kubernetes.

### Deployment

Longhorn's backup feature requires an NFS server or an S3 endpoint. You can setup a simple NFS server on the same host and use that to store backups.

The deployment for the simple nfs server is also very easy.

```
kubectl create -f deploy/example-backupstore.yaml
```

This NFS server won't save any data after you delete the Deployment. It's for development and testing only.

After this script completes, using the following URL as the Backup Target in the Longhorn setting:

```
nfs://longhorn-backupstore:/opt/backupstore
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
