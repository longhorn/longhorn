# Upgrade

Here we would cover how to upgrade from Longhorn v0.2 to Longhorn v0.3 release.

## Backup your existing data
1. It's recommended to create a latest backup for every volume to the backupstore before upgrade.
2. Make sure no volume is in degraded or faulted state.
3. Shutdown related Kubernetes pods. Detach all the volumes. Make sure all the volumes are detached before proceeding.
4. Backup CRD yaml to local directory:
```
kubectl -n longhorn-system get volumes.longhorn.rancher.io -o yaml > longhorn-v0.2-backup-volumes.yaml
kubectl -n longhorn-system get engines.longhorn.rancher.io -o yaml > longhorn-v0.2-backup-engines.yaml
kubectl -n longhorn-system get replicas.longhorn.rancher.io -o yaml > longhorn-v0.2-backup-replicas.yaml
kubectl -n longhorn-system get settings.longhorn.rancher.io -o yaml > longhorn-v0.2-backup-settings.yaml
```
5. Noted the value of BackupTarget in the setting. The user would need to reset after upgrade.

## Upgrade from v0.2 to v0.3

Please be aware that the upgrade will incur API downtime.

### 1. Remove the old manager
```
kubectl delete -f https://raw.githubusercontent.com/rancher/longhorn/v0.2/deploy/uninstall-for-upgrade.yaml
```

### 2. Install the new manager

We will use `kubectl apply` instead of `kubectl create` to install the new version of the manager.

If you're using Rancher RKE, or other distro with Kubernetes v1.10+ and Mount Propagation enabled, you can just do:
```
kubectl apply -f https://raw.githubusercontent.com/rancher/longhorn/v0.3-rc/deploy/longhorn.yaml
```
If you're using Flexvolume driver with other Kubernetes Distro, replace the value of $FLEXVOLUME_DIR in the following command with your own Flexvolume Directory as specified above.
```
FLEXVOLUME_DIR="/home/kubernetes/flexvolume/"
curl -s https://raw.githubusercontent.com/rancher/longhorn/v0.3-rc/deploy/longhorn.yaml|sed "s#^\( *\)value: \"/var/lib/kubelet/volumeplugins\"#\1value: \"${FLEXVOLUME_DIR}\"#g" > longhorn.yaml
kubectl apply -f longhorn.yaml
```

For Google Kubernetes Engine (GKE) users, see  [here](../gke.md)  before proceed.

Longhorn Manager and Longhorn Driver will be deployed as daemonsets in a separate namespace called `longhorn-system`, as you can see in the yaml file.

When you see those pods has started correctly as follows, you've deployed the Longhorn successfully.

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
Or with Flexvolume driver
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

### 3. Upgrade Engine Images and set BackupTarget

1. Wait until the UI is up.
2. Set the BackupTarget in the setting to the same value as before upgrade.
3. Make all the volumes are all detached.
4. Select all the volumes using batch selection. Click batch operation button
   `Upgrade Engine`, choose the only engine image available in the list. It's
   the default engine shipped with the manager for this release.
5. Now attach the volume one by one, to see if the volume works correctly.

## Note

Upgrade is always tricky. Keep backups for the volumes are critical.

If you have any issues, please reported it at
https://github.com/rancher/longhorn/issues , with your backup yaml files as well
as manager logs.

