# Google Kubernetes Engine

The configuration yaml will be slight different for Google Kubernetes Engine (GKE):

1.  GKE requires user to manually claim himself as cluster admin to enable RBAC. User need to execute following command before create the Longhorn system using yaml files.

```
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=<name@example.com>

```

In which `name@example.com` is the user's account name in GCE, and it's case sensitive. See [here](https://cloud.google.com/kubernetes-engine/docs/how-to/role-based-access-control)  for details.

2.  The default Flexvolume plugin directory is different with GKE 1.8+, which is at `/home/kubernetes/flexvolume`. User need to use following command instead:

```
FLEXVOLUME_DIR="/home/kubernetes/flexvolume/"
curl -s https://raw.githubusercontent.com/rancher/longhorn/v0.3-rc/deploy/longhorn.yaml|sed "s#^\( *\)value: \"/var/lib/kubelet/volumeplugins\"#\1value: \"${FLEXVOLUME_DIR}\"#g" > longhorn.yaml
kubectl create -f longhorn.yaml
```

See [Troubleshooting](./troubleshooting.md) for details.

