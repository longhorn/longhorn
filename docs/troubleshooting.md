# Troubleshooting

## Common issues
### Volume can be attached/detached from UI, but Kubernetes Pod/StatefulSet etc cannot use it

Check if volume plugin directory has been set correctly. This is automatically detected unless user explicitly set it.

By default, Kubernetes uses `/usr/libexec/kubernetes/kubelet-plugins/volume/exec/`, as stated in the [official document](https://github.com/kubernetes/community/blob/master/contributors/devel/flexvolume.md#prerequisites).

Some vendors choose to change the directory for various reasons. For example, GKE uses `/home/kubernetes/flexvolume` instead.

User can find the correct directory by running `ps aux|grep kubelet` on the host and check the `--volume-plugin-dir` parameter. If there is none, the default `/usr/libexec/kubernetes/kubelet-plugins/volume/exec/` will be used.

## Troubleshooting guide

There are a few compontents in the Longhorn. Manager, Engine, Driver and UI. All of those components runnings as pods in the `longhorn-system` namespace by default inside the Kubernetes cluster.

### UI
Make use of the Longhorn UI is a good start for the troubleshooting. For example, if Kubernetes cannot mount one volume correctly, after stop the workload, try to attach and mount that volume manually on one node and access the content to check if volume is intact.

Also, the event logs in the UI dashboard provides some information of probably issues. Check for the event logs in `Warning` level.

### Manager and engines
You can get the log from Longhorn Manager and Engines to help with the troubleshooting. The most useful logs are from `longhorn-manager-xxx`, and the log inside Longhorn Engine, e.g. `<volname>-e-xxxx` and `<volname>-r-xxxx`.

Since normally there are multiple Longhorn Manager running at the same time, we recommend using [kubetail](https://github.com/johanhaleby/kubetail) which is a great tool to keep track of the logs of multiple pods. You can use:
```
kubetail longhorn-system -n longhorn-system
```
To track the manager logs in real time.

### CSI driver

For CSI driver, check the logs for `csi-attacher-0` and `csi-provisioner-0`, as well as containers in `longhorn-csi-plugin-xxx`.

### Flexvolume driver

For Flexvolume driver, first check where the driver has been installed on the node. Check the log of `longhorn-driver-deployer-xxxx` for that information.

Then check the kubelet logs. Flexvolume driver itself doesn't run inside the container. It would run along with the kubelet process.

If kubelet is running natively on the node, you can use the following command to get the log:
```
journalctl -u kubelet
```

Or if kubelet is running as a container (e.g. in RKE), use the following command instead:
```
docker logs kubelet
```

For even more detail logs of Longhorn Flexvolume, run following command on the node or inside the container (if kubelet is running as a container, e.g. in RKE):
```
touch /var/log/longhorn_driver.log
```
