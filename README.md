# Longhorn

Longhorn is a distributed block storage system built using containers and microservices. Longhorn creates a dedicated storage controller for each block device volume and sychronously replicates the volume across multiple replicas stored on multiple hosts. The storage controller and replicas are implemented using containers and are managed using a container orchestration system.

Longhorn is lightweight, reliable, and easy-to-use. It is particularly suitable as persistent storage for containers. It supports snapshots, backups, and even allows you to schedule recurring snapshots and backups!

Longhorn is experimental software. We appreciate your comments as we continue to work on it!

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

