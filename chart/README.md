# Rancher Longhorn Chart

Please install Longhorn chart in `longhorn-system` namespace only.

The following document pertains to running Longhorn from the Rancher 2.0 chart.

## Source Code

Longhorn is 100% open source software. Project source code is spread across a number of repos:

1. Longhorn Engine -- Core controller/replica logic https://github.com/longhorn/longhorn-engine
2. Longhorn Manager -- Longhorn orchestration, includes CSI driver for Kubernetes https://github.com/longhorn/longhorn-manager
3. Longhorn UI -- Dashboard https://github.com/longhorn/longhorn-ui

## Prerequisites

1. Rancher v2.1+
2. Docker v1.13+
3. Kubernetes v1.14+
4. Make sure `curl`, `findmnt`, `grep`, `awk` and `blkid` has been installed in all nodes of the Kubernetes cluster.
5. Make sure `open-iscsi` has been installed in all nodes of the Kubernetes cluster. For GKE, recommended Ubuntu as guest OS image since it contains `open-iscsi` already.

## Uninstallation

1. To prevent damage to the Kubernetes cluster, we recommend deleting all Kubernetes workloads using Longhorn volumes (PersistentVolume, PersistentVolumeClaim, StorageClass, Deployment, StatefulSet, DaemonSet, etc).

2. From Rancher UI, navigate to `Catalog Apps` tab and delete Longhorn app.

## Troubleshooting

### I deleted the Longhorn App from Rancher UI instead of following the uninstallation procedure

Redeploy the (same version) Longhorn App. Follow the uninstallation procedure above.

### Problems with CRDs

If your CRD instances or the CRDs themselves can't be deleted for whatever reason, run the commands below to clean up. Caution: this will wipe all Longhorn state!

```
# Delete CRD instances and definitions
curl -s https://raw.githubusercontent.com/longhorn/longhorn-manager/master/hack/cleancrds.sh |bash -s v062
curl -s https://raw.githubusercontent.com/longhorn/longhorn-manager/master/hack/cleancrds.sh |bash -s v070
```

---
Please see [link](https://github.com/longhorn/longhorn) for more information.
