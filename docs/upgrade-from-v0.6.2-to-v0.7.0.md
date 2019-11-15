# Upgrade from v0.6.2 to v0.7.0

The users need to follow this guide to upgrade from v0.6.2 to v0.7.0.

## Preparation

1. Make backups for all the volumes.
1. Stop the workload using the volumes.
    1. Live upgrade is not supported from v0.6.2 to v0.7.0

## Upgrade
### Use Rancher App
1. Run the following command to avoid [this error](#error-the-storageclass-longhorn-is-invalid-provisioner-forbidden-updates-to-provisioner-are-forbidden):
```
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v0.7.0/examples/storageclass.yaml
```
2. Click the `Upgrade` button in the Rancher UI
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

## TroubleShooting
### Error: `"longhorn" is invalid: provisioner: Forbidden: updates to provisioner are forbidden.`
- This means you need to clean up the old `longhorn` storageClass for Longhorn v0.7.0 upgrade, since we've changed the provisioner from `rancher.io/longhorn` to `driver.longhorn.io`.

- Noticed the PVs created by the old storageClass will still use `rancher.io/longhorn` as provisioner. Longhorn v0.7.0 supports attach/detach/deleting of the PVs created by the previous version of Longhorn, but it doesn't support creating new PVs using the old provisioner name. Please use the new StorageClass for the new volumes.

#### If you are using YAML file:
1. Clean up the deprecated StorageClass:
```
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v0.7.0/examples/storageclass.yaml
```
2. Run
```
kubectl apply https://raw.githubusercontent.com/longhorn/longhorn/v0.7.0/deploy/longhorn.yaml
```

#### If you are using Rancher App:
1. Clean up the default StorageClass:
```
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v0.7.0/examples/storageclass.yaml
```
2. Follow [this error instruction](#error-kind-customresourcedefinition-with-the-name-xxx-already-exists-in-the-cluster-and-wasnt-defined-in-the-previous-release) 

### Error: `kind CustomResourceDefinition with the name "xxx" already exists in the cluster and wasn't defined in the previous release...`
- This is [a Helm bug](https://github.com/helm/helm/issues/6031).
- Please make sure that you have not deleted the old Longhorn CRDs via the command `curl -s https://raw.githubusercontent.com/longhorn/longhorn-manager/master/hack/cleancrds.sh | bash -s v062` or executed Longhorn uninstaller before executing the following command. Otherwise you MAY LOSE all the data stored in the Longhorn system.

1. Clean up the leftover:
```
kubectl -n longhorn-system delete ds longhorn-manager
curl -s https://raw.githubusercontent.com/longhorn/longhorn-manager/master/hack/cleancrds.sh | bash -s v070
```

2. Re-click the `Upgrade` button in the Rancher UI.

## Rollback

Since we upgrade the CSI framework from v0.4.2 to v1.1.0 in this release, rolling back from Longhorn v0.7.0 to v0.6.2 or lower means backward upgrade for the CSI plugin. 
But Kubernetes does not support the CSI backward upgrade. **Hence restarting kubelet is unavoidable. Please be careful, check the conditions beforehand and follow the instruction exactly.**

Prerequisite: 
* To rollback from v0.7.0 installation, you must haven't executed [the post upgrade steps](#post-upgrade).

Steps to roll back:

1. Clean up the components introduced by Longhorn v0.7.0 upgrade
```
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v0.7.0/examples/storageclass.yaml
curl -s https://raw.githubusercontent.com/longhorn/longhorn-manager/master/hack/cleancrds.sh | bash -s v070
```

2. Restart the Kubelet container on all nodes or restart all the nodes. This step WILL DISRUPT all the workloads in the system.

Connect to the node then run
```
docker restart kubelet
```

3. Rollback
Use `kubectl apply` or Rancher App to rollback the Longhorn.

#### Migrate the old PVs to use the new StorageClass

TODO

## Post upgrade
1. Bring back the workload online.
1. Make sure all the volumes are back online.
1. Check all the existing manager pods are running v0.7.0. No v0.6.2 pods is running.
    1. Run `kubectl -n longhorn-system get pod -o yaml|grep "longhorn-manager:v0.6.2"` should yield no result.
1. Run the following script to clean up the v0.6.2 CRDs.
    1. Must make sure all the v0.6.2 pods HAVE BEEN DELETED, otherwise the data WILL BE LOST!
```
curl -s https://raw.githubusercontent.com/longhorn/longhorn-manager/master/hack/cleancrs.sh |bash -s v062
```
