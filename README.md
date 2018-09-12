# Longhorn

Longhorn is a distributed block storage system for Kubernetes. Longhorn is lightweight, reliable, and easy-to-use. You can deploy Longhorn on an existing Kubernetes cluster with one simple command. Once Longhorn is deployed, it adds persistent volume support to the Kubernetes cluster.

Longhorn implements distributed block storage using containers and microservices. Longhorn creates a dedicated storage controller for each block device volume and sychronously replicates the volume across multiple replicas stored on multiple nodes. The storage controller and replicas are themselves orchestrated using Kubernetes. Longhorn supports snapshots, backups, and even allows you to schedule recurring snapshots and backups!

You can read more details of Longhorn and its design [here](http://rancher.com/microservices-block-storage/).

## Current status

Longhorn is a work in progress. It's an alpha quality software at the moment. We appreciate your comments as we continue to work on it.

The latest release of Longhorn is v0.3.0.

## Source code
Longhorn is 100% open source software. Project source code is spread across a number of repos:

1. Longhorn engine -- Core controller/replica logic https://github.com/rancher/longhorn-engine
1. Longhorn manager -- Longhorn orchestration, includes FlexVolume driver for Kubernetes https://github.com/rancher/longhorn-manager
1. Longhorn UI -- Dashboard https://github.com/rancher/longhorn-ui

# Demo

[![Longhorn Demo](https://asciinema.org/a/PzzOcONC5tUPQpHifi2QmDR2J.png)](https://asciinema.org/a/PzzOcONC5tUPQpHifi2QmDR2J?autoplay=1&loop=1&speed=3)
# Requirements

## Minimal Requirements

1.  Docker v1.13+
2.  Kubernetes v1.8+
3.  Make sure open-iscsi has been installed in all nodes of the Kubernetes cluster. For GKE, recommended Ubuntu as guest OS image since it contains open-iscsi already.
    1. For Debian/Ubuntu, use `apt-get install open-iscsi` to install.
    2. For RHEL/CentOS, use `yum install iscsi-initiator-utils` to install.

## Kubernetes driver Requirements

Longhorn can be used in Kubernetes to provide persistent storage through either Longhorn Container Storage Interface (CSI) driver or Longhorn FlexVolume driver. Longhorn will automatically deploy one of the drivers, depending on the Kubernetes cluster configuration. User can also specify the driver in the deployment yaml file. CSI is preferred.

### Environment check script

We've wrote a script to help user to get enough information to configure the setup correctly.

Before installing, run:
```
curl -sSfL https://raw.githubusercontent.com/rancher/longhorn/master/scripts/environment_check.sh | bash
```
Example result:
```
daemonset.apps/longhorn-environment-check created
waiting for pods to become ready (0/3)
all pods ready (3/3)

  MountPropagation is enabled!

cleaning up...
daemonset.apps "longhorn-environment-check" deleted
clean up complete
```
Please make a note of `MountPropagation` feature gate status.

### Requirement for the CSI driver

1. Kubernetes v1.10+
   1. CSI is in beta release for this version of Kubernetes, and enabled by default.
2. Mount propagation feature gate enabled.
   1. It's enabled by default in Kubernetes v1.10. But some early versions of RKE may not enable it.
3. If above conditions cannot be met, Longhorn will fall back to the FlexVolume driver.

### Check if your setup satisfied CSI requirement
1. Use the following command to check your Kubernetes server version
```
kubectl version
```
Result:
```
Client Version: version.Info{Major:"1", Minor:"10", GitVersion:"v1.10.3", GitCommit:"2bba0127d85d5a46ab4b778548be28623b32d0b0", GitTreeState:"clean", BuildDate:"2018-05-21T09:17:39Z", GoVersion:"go1.9.3", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"10", GitVersion:"v1.10.1", GitCommit:"d4ab47518836c750f9949b9e0d387f20fb92260b", GitTreeState:"clean", BuildDate:"2018-04-12T14:14:26Z", GoVersion:"go1.9.3", Compiler:"gc", Platform:"linux/amd64"}
```
The `Server Version` should be `v1.10` or above.

2. The result of environment check script should contain `MountPropagation is enabled!`.

### Requirement for the FlexVolume driver

1.  Kubernetes v1.8+
2.  Make sure `curl`, `findmnt`, `grep`, `awk` and `blkid` has been installed in the every node of the Kubernetes cluster.

# Upgrading

For instructions on how to upgrade Longhorn App v0.1 or v0.2 to v0.3, [see this document](docs/upgrade.md#upgrade).

# Deployment

Create the deployment of Longhorn in your Kubernetes cluster is straightforward.

```
kubectl apply -f https://raw.githubusercontent.com/rancher/longhorn/master/deploy/longhorn.yaml
```

For Google Kubernetes Engine (GKE) users, see [here](#google-kubernetes-engine) before proceeding.

Longhorn manager and Longhorn driver will be deployed as daemonsets in a separate namespace called `longhorn-system`, as you can see in the yaml file.

When you see those pods have started correctly as follows, you've deployed Longhorn successfully.

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
Or with FlexVolume driver:
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

Longhorn UI would connect to the Longhorn manager API, provides the overview of the system, the volume operations, and the snapshot/backup operations. It's highly recommended for the user to check out Longhorn UI.

Noted that the current UI is unauthenticated.

# Use Longhorn with Kubernetes

Longhorn provides the persistent volume directly to Kubernetes through one of the Longhorn drivers. No matter which driver you're using, you can use Kubernetes StorageClass to provision your persistent volumes.

Use following command to create a default Longhorn StorageClass named `longhorn`.

```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/master/examples/storageclass.yaml
```

Now you can create a pod using Longhorn like this:
```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/master/examples/pvc.yaml
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

# Highlight features
### Snapshot
A snapshot in Longhorn represents a volume state at a given time, stored in the same location of volume data on physical disk of the host. Snapshot creation is instant in Longhorn.

User can revert to any previous taken snapshot using the UI. Since Longhorn is a distributed block storage, please make sure the Longhorn volume is umounted from the host when revert to any previous snapshot, otherwise it will confuse the node filesystem and cause filesystem corruption.

#### Note about the block level snapshot

Longhorn is a `crash-consistent` block storage solution.

It's normal for the OS to keep content in the cache before writing into the block layer. However, it also means if the all the replicas are down, then Longhorn may not contain the immediate change before the shutdown, since the content was kept in the OS level cache and hadn't transfered to Longhorn system yet. It's similar to if your desktop was down due to a power outage, after resuming the power, you may find some weird files in the hard drive.

To force the data being written to the block layer at any given moment, the user can run `sync` command on the node manually, or umount the disk. OS would write the content from the cache to the block layer in either situation.

### Backup
A backup in Longhorn represents a volume state at a given time, stored in the secondary storage (backupstore in Longhorn word) which is outside of the Longhorn system. Backup creation will involving copying the data through the network, so it will take time.

A corresponding snapshot is needed for creating a backup. And user can choose to backup any snapshot previous created.

A backupstore is a NFS server or S3 compatible server.

A backup target represents a backupstore in Longhorn. The backup target can be set at `Settings/General/BackupTarget`

#### Setup AWS S3 backupstore
1. Create a new bucket in AWS S3.

2. Follow the [guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html#id_users_create_console) to create a new AWS IAM user, with the following permissions set:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "GrantLonghornBackupstoreAccess0",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::<your-bucket-name>",
                "arn:aws:s3:::<your-bucket-name>/*"
            ]
        }
    ]
}
```


3. Create a Kubernetes secret with a name such as `aws-secret` in the namespace where longhorn is placed(`longhorn-system` by default). Put the following keys in the secret:

```
AWS_ACCESS_KEY_ID: <your_aws_access_key_id>
AWS_SECRET_ACCESS_KEY: <your_aws_secret_access_key>
```

4. Go to the Longhorn UI and set `Settings/General/BackupTarget` to
```
s3://<your-bucket-name>@<your-aws-region>/
```
Pay attention that you should have `/` at the end, otherwise you will get an error.

5.  Set `Settings/General/BackupTargetSecret` to
```
aws-secret
```
Your secret name with AWS keys from 3rd point.

#### Setup a local testing backupstore
We provides two testing purpose backupstore based on NFS server and Minio S3 server for testing, in `./deploy/backupstores`.

Use following command to setup a Minio S3 server for BackupStore after `longhorn-system` was created.
```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/master/deploy/backupstores/minio-backupstore.yaml
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

### Recurring snapshot and backup
Longhorn supports recurring snapshot and backup for volumes. User only need to set when he/she wish to take the snapshot and/or backup, and how many snapshots/backups needs to be retains, then Longhorn will automatically create snapshot/backup for the user at that time, as long as the volume is attached to a node.

User can find the setting for the recurring snapshot and backup in the `Volume Detail` page.

## Other features

### [Multiple disks](./docs/multidisk.md)
### [iSCSI](./docs/iscsi.md)
### [Restoring Stateful Set volumes](./docs/restore_statefulset.md)
### [Base image](./docs/base-image.md)

## Additional informations
### [Google Kubernetes Engine](./docs/gke.md)
### [Upgrade from v0.1/v0.2](./docs/upgrade.md)
### [Troubleshooting](./docs/troubleshooting.md)

## Uninstall Longhorn

Longhorn stores its data in the Kubernetes API server, in the format of CRD. Longhorn CRDs have finalizers; user should delete the volumes and related resource first to give the managers a chance to clean up.

Before uninstalling Longhorn, the user need to delete all the PVC and PV resources which refer to a Longhorn volume in Kubernetes. Otherwise, Kubernetes may get confused because the underlying storage is gone but the PV/PVC remains.

### 1. Run cleanup script
Note that you will lose all volume data after done this. If you intend on keeping any volume data, make backups (and test restoring a volume) before proceeding.

```
curl -sSfL https://raw.githubusercontent.com/rancher/longhorn-manager/master/deploy/scripts/cleanup.sh | bash
```

### 2. Delete remaining components

The cleanup script removes most components, but leaves RBAC related resources and the `longhorn-system` Namespace behind. Run this command to remove these resources.

```
kubectl delete -f https://raw.githubusercontent.com/rancher/longhorn/master/deploy/longhorn.yaml
```

## License

Copyright (c) 2014-2018  [Rancher Labs, Inc.](http://rancher.com/)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
