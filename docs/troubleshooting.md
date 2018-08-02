## Troubleshooting

### Volume can be attached/detached from UI, but Kubernetes Pod/StatefulSet etc cannot use it

Check if volume plugin directory has been set correctly.

By default, Kubernetes use `/usr/libexec/kubernetes/kubelet-plugins/volume/exec/` as the directory for volume plugin drivers, as stated in the  [official document](https://github.com/kubernetes/community/blob/master/contributors/devel/flexvolume.md#prerequisites).

But some vendors may choose to change the directory due to various reasons. For example, GKE uses `/home/kubernetes/flexvolume`, and RKE uses `/var/lib/kubelet/volumeplugins`.

User can find the correct directory by running `ps aux|grep kubelet` on the host and check the `--volume-plugin-dir`parameter. If there is none, the default `/usr/libexec/kubernetes/kubelet-plugins/volume/exec/` will be used.

