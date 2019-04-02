# Kubernetes driver

## Background

Longhorn can be used in Kubernetes to provide persistent storage through either Longhorn Container Storage Interface (CSI) driver or Longhorn FlexVolume driver. Longhorn will automatically deploy one of the drivers, depending on the Kubernetes cluster configuration. User can also specify the driver in the deployment yaml file. CSI is preferred.

Noted that the volume created and used through one driver won't be recongized by Kubernetes using the other driver. So please don't switch driver (e.g. during upgrade) if you have existing volumes created using the old driver. If you really want to switch driver, see [here](upgrade.md#migrating-between-flexvolume-and-csi-driver) for instructions.

### Requirement for the CSI driver

1. Kubernetes v1.10+
   1. CSI is in beta release for this version of Kubernetes, and enabled by default.
2. Mount propagation feature gate enabled.
   1. It's enabled by default in Kubernetes v1.10. But some early versions of RKE may not enable it.
   2. You can check it by using [environment check script](#environment-check-script).
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

2. The result of [environment check script](#environment-check-script) should contain `MountPropagation is enabled!`.

### Requirement for the FlexVolume driver

1.  Kubernetes v1.8+
2.  Make sure `curl`, `findmnt`, `grep`, `awk` and `blkid` has been installed in the every node of the Kubernetes cluster.

#### Flexvolume driver directory

Longhorn now has ability to auto detect the location of Flexvolume directory.

If the Flexvolume driver wasn't installed correctly, there can be a few reasons:
1. If `kubelet` is running inside a container rather than running on the host OS, the host bind-mount path for the Flexvolume driver directory (`--volume-plugin-dir`) must be the same as the path used by the kubelet process.
1.1. For example, if the kubelet is using `/var/lib/kubelet/volumeplugins` as
the Flexvolume driver directory, then the host bind-mount must exist for that
directory, as e.g. `/var/lib/kubelet/volumeplugins:/var/lib/kubelet/volumeplugins` or any idential bind-mount for the parent directory.
1.2. It's because Longhorn would detect the directory used by the `kubelet` command line to decide where to install the driver on the host.
2. The kubelet setting for the Flexvolume driver directory must be the same across all the nodes.
2.1. Longhorn doesn't support heterogeneous setup at the moment.

### Environment check script

We've wrote a script to help user to gather enough information about the factors

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
