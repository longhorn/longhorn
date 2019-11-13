# Upgrade from v0.6.2 to v0.7.0

The users need to follow this guide to upgrade from v0.6.2 to v0.7.0.
## Preparation

1. Make backups for all the volumes.
1. Stop the workload using the volumes.

## Upgrade
### Use Rancher App
1. Click the `Upgrade` button in the Rancher UI
2. Select `Force Recreate` option at the bottom of the screen.
3. Wait for the app to complete the upgrade.

### Use YAML file
Use `kubectl apply https://raw.githubusercontent.com/longhorn/longhorn/v0.7.0/deploy/longhorn.yaml`

And wait for all the pods to become running and Longhorn UI working.

```
$ kubectl -n longhorn-system get pod
NAME                                        READY   STATUS    RESTARTS   AGE
compatible-csi-attacher-69857469fd-rj5vm    1/1     Running   4          3d12h
csi-attacher-79b9bfc665-56sdb               1/1     Running   0          3d12h
csi-attacher-79b9bfc665-hdj7t               1/1     Running   0          3d12h
csi-attacher-79b9bfc665-tfggq               1/1     Running   3          3d12h
csi-provisioner-68b7d975bb-5ggp8            1/1     Running   0          3d12h
csi-provisioner-68b7d975bb-frggd            1/1     Running   2          3d12h
csi-provisioner-68b7d975bb-zrr65            1/1     Running   0          3d12h
engine-image-ei-605a0f3e-8gx4s              1/1     Running   0          3d14h
engine-image-ei-605a0f3e-97gxx              1/1     Running   0          3d14h
engine-image-ei-605a0f3e-r6wm4              1/1     Running   0          3d14h
instance-manager-e-a90b0bab                 1/1     Running   0          3d14h
instance-manager-e-d1458894                 1/1     Running   0          3d14h
instance-manager-e-f2caa5e5                 1/1     Running   0          3d14h
instance-manager-r-04417b70                 1/1     Running   0          3d14h
instance-manager-r-36d9928a                 1/1     Running   0          3d14h
instance-manager-r-f25172b1                 1/1     Running   0          3d14h
longhorn-csi-plugin-72bsp                   4/4     Running   0          3d12h
longhorn-csi-plugin-hlbg8                   4/4     Running   0          3d12h
longhorn-csi-plugin-zrvhl                   4/4     Running   0          3d12h
longhorn-driver-deployer-66b6d8b97c-snjrn   1/1     Running   0          3d12h
longhorn-manager-pf5p5                      1/1     Running   0          3d14h
longhorn-manager-r5npp                      1/1     Running   1          3d14h
longhorn-manager-t59kt                      1/1     Running   0          3d14h
longhorn-ui-b466b6d74-w7wzf                 1/1     Running   0          50m
```

#### Recreate StorageClass
If you've encounted following error during applying the yaml
```
The StorageClass "longhorn" is invalid: provisioner: Forbidden: updates to provisioner are forbidden.
```
You need to recreate the `longhorn` storageClass in order to make Kubernetes work with Longhorn v0.7.0, since we've changed the provisioner from `rancher.io/longhorn` to `driver.longhorn.io`.

Use the following command to recreate the default StorageClass:
```
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v0.7.0/examples/storageclass.yaml
kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/v0.7.0/examples/storageclass.yaml
```

Noticed the PVs created by the old storageClass will still use `rancher.io/longhorn` as provisioner. Longhorn v0.7.0 supports attach/detach/deleting of the PVs created by the previous version of Longhorn, but it doesn't support creating new PVs using the old provisioner name. Please use the new StorageClass for the new volumes.

#### Migrate the old PVs to use the new StorageClass

TODO

## Post upgrade
1. Bring back the workload online.
1. Make sure all the volumes are back online.
1. Check all the existing manager pods are running v0.7.0. No v0.6.2 pods is running.
1. Run the following script to clean up the v0.6.2 CRDs.
    1. Must make sure all the v0.6.2 pods HAVE BEEN DELETED, otherwise the data WILL BE LOST!
```
curl -s https://raw.githubusercontent.com/longhorn/longhorn-manager/master/hack/cleancrs.sh |bash -s v062
```
