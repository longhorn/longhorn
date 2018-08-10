# Base Image Support

Longhorn supports creation of block devices backed by a base image. Longhorn
base images are packaged as Docker images. Public or private registries may
be used as a distribution mechanism for your Docker base images.

## Usage

Volumes backed by a base image can be created in three ways.

1. [UI](#ui) - Create Longhorn volumes exposed as block device or iSCSI target
2. [FlexVolume Driver](#flexvolume-driver) - Create Longhorn block devices and consume in Kubernetes pods
3. [CSI Driver](#csi-driver) - (Newer) Create Longhorn block devices and consume in Kubernetes pods

### UI

On the `Volume` tab, click the `Create Volume` button. The `Base Image` field
expects a Docker image name such as `rancher/vm-ubuntu:16.04.4-server-amd64`.

### FlexVolume Driver

The flexvolume driver supports volumes backed by base image. Below is a sample
FlexVolume definition including `baseImage` option.

```
name: flexvol
flexVolume:
  driver: "rancher.io/longhorn"
  fsType: "ext4"
  options:
    size: "32Mi"
    numberOfReplicas: "3"
    staleReplicaTimeout: "20"
    fromBackup: ""
    baseImage: "rancher/longhorn-test:baseimage-ext4"
```

You do not need to (and probably shouldn't) explicitly set filesystem type
`fsType` when base image is present. If you do, it must match the base image's
filesystem or the flexvolume driver will return an error.

Try it out for yourself. Make sure the Longhorn driver deployer specifies flag
`--driver flexvolume`, otherwise a different driver may be deployed. The 
following example creates an nginx pod serving content from a flexvolume with
a base image and is accessible from a service.

```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn-manager/v0.3-rc/examples/flexvolume/example_baseimage.yaml
```

Wait until the pod is running.

```
kubectl get po/flexvol-baseimage -w
```

Query for the service you created.

```
kubectl get svc/flexvol-baseimage
```

Your service should look similar.

```
NAME                        TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/flexvol-baseimage   LoadBalancer   10.43.153.186   <pending>     80:31028/TCP   2m
```

Now let's access something packaged inside the base image through the Nginx
webserver, exposed by the `LoadBalancer` service. If you have LoadBalancer
support and `EXTERNAL-IP` is set, navigate to the following URL.

```
http://<EXTERNAL-IP>/guests/hd/party-wizard.gif
```

Otherwise, navigate to the following URL where `NODE-IP` is the external IP
address of any Kubernetes node and `NODE-PORT` is the second port in the
service (`31028` in the example service above).

```
http://<NODE-IP>:<NODE-PORT>/guests/hd/party-wizard.gif
```

Finally, tear down the pod and service.

```
kubectl delete -f https://raw.githubusercontent.com/rancher/longhorn-manager/v0.3-rc/examples/flexvolume/example_baseimage.yaml
```

### CSI Driver

The CSI driver supports volumes backed by base image. Below is a sample
StorageClass definition including `baseImage` option.

```
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: example
provisioner: rancher.io/longhorn
parameters:
  numberOfReplicas: '3'
  staleReplicaTimeout: '30'
  fromBackup: ''
  baseImage: rancher/longhorn-test:baseimage-ext4
```

Let's walk through an example. First, ensure the CSI Plugin is deployed.

```
kubectl -n longhorn-system get daemonset.apps/longhorn-csi-plugin
```

The following example creates an nginx statefulset with two replicas serving
content from two csi-provisioned volumes backed by a base image. The
statefulset is accessible from a service.

```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn-manager/v0.3-rc/examples/provisioner_with_baseimage.yaml
```

Wait until both pods are running.

```
kubectl -l app=provisioner-baseimage get po -w
```

Query for the service you created.

```
kubectl get svc/csi-baseimage
```

Your service should look similar.

```
NAME            TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
csi-baseimage   LoadBalancer   10.43.47.129   <pending>     80:32768/TCP   4m
```

Now let's access something packaged inside the base image through the Nginx
webserver, exposed by the `LoadBalancer` service. If you have LoadBalancer
support and `EXTERNAL-IP` is set, navigate to the following URL.

```
http://<EXTERNAL-IP>/guests/hd/party-wizard.gif
```

Otherwise, navigate to the following URL where `NODE-IP` is the external IP
address of any Kubernetes node and `NODE-PORT` is the second port in the
service (`32768` in the example service above).

```
http://<NODE-IP>:<NODE-PORT>/guests/hd/party-wizard.gif
```

Finally, tear down the pod and service.

```
kubectl delete -f https://raw.githubusercontent.com/rancher/longhorn-manager/v0.3-rc/examples/provisioner_with_baseimage.yaml
```

## Building

Creating and packaging an empty base image is a very simple process.

1. [Install QEMU](https://en.wikibooks.org/wiki/QEMU/Installing_QEMU).
2. Create a qcow2 image.

```
qemu-img create -f qcow2 example.qcow2 4G
```

3. Create the `Dockerfile` file with the following contents:

```
FROM busybox
COPY example.qcow2 /base_image/example.qcow2
```

4. Build and publish the image:

```
DOCKERHUB_ACCT=rancher
docker build -t ${DOCKERHUB_ACCT}/longhorn-example:baseimage .
docker push ${DOCKERHUB_ACCT}/longhorn-example:baseimage
```

That's it! Your (empty) base image is ready for (no) use. Let's now explore
some use cases for a base image and what we should do to our `example.qcow2`
before building and publishing.

### Simple Filesystem

Suppose we want to store some static web assets in a volume. We have our qcow2
image and the web assets, but how to put the assets in the image? 

On a Linux machine, load the network block device module.

```
sudo modprobe nbd
```

Use `qemu-nbd` to expose the image as a network block device.

```
sudo qemu-nbd -f qcow2 -c /dev/nbd0 example.qcow2
```

The raw block device needs a filesystem. Consider your infrastructure and
choose an appropriate filesystem. We will use EXT4 filesystem.

```
sudo mkfs -t ext4 /dev/nbd0
```

Mount the filesystem.

```
mkdir -p example
sudo mount /dev/nbd0 example
```

Copy web assets to filesystem.

```
cp /web/assets/* example/
```

Unmount the filesystem, shutdown `qemu-nbd`, cleanup.

```
sudo umount example
sudo killall qemu-nbd
rmdir example
```

Optionally, compress the image.

```
qemu-img convert -c -O qcow2 example.qcow2 example.compressed.qcow2
```

Follow the build and publish image steps and you are done. [Example script](https://raw.githubusercontent.com/rancher/longhorn-tests/master/manager/test_containers/baseimage/generate.sh).

### Virtual Machine

See [this document](https://github.com/rancher/vm/blob/master/docs/images.md) for the basic procedure of preparing Virtual Machine images.
