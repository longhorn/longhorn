# Upgrade

Here we cover how to upgrade to Longhorn v0.3 from all previous releases.

## Backup Existing Volumes

It's recommended to create a recent backup of every volume to the backupstore
before upgrade.

If you don't have a on-cluster backupstore already, create one. Here we'll use NFS for example.
1. Execute following command to create the backupstore
```
kubectl apply -f https://raw.githubusercontent.com/rancher/longhorn/master/deploy/backupstores/nfs-backupstore.yaml
```
2. On Longhorn UI Settings page, set Backup Target to
`nfs://longhorn-test-nfs-svc.default:/opt/backupstore` and click `Save`.

Navigate to each volume detail page and click `Take Snapshot` (it's recommended to run `sync` in the host command line before `Take Snapshot`). Click the new
snapshot and click `Backup`. Wait for the new backup to show up in the volume's backup list before continuing.

## Check For Issues

Make sure no volume is in degraded or faulted state. Wait for degraded
volumes to heal and delete/salvage faulted volumes before proceeding.

## Detach Volumes

Shutdown all Kubernetes Pods using Longhorn volumes in order to detach the
volumes. The easiest way to achieve this is by deleting all workloads and recreate them later after upgrade. If
this is not desirable, some workloads may be suspended. We will cover how
each workload can be modified to shut down its pods.

### Deployment
Edit the deployment with `kubectl edit deploy/<name>`.
Set `.spec.replicas` to `0`.

### StatefulSet
Edit the statefulset with `kubectl edit statefulset/<name>`.
Set `.spec.replicas` to `0`.

### DaemonSet
There is no way to suspend this workload.
Delete the daemonset with `kubectl delete ds/<name>`.

### Pod
Delete the pod with `kubectl delete pod/<name>`.
There is no way to suspend a pod not managed by a workload controller.

### CronJob
Edit the cronjob with `kubectl edit cronjob/<name>`.
Set `.spec.suspend` to `true`.
Wait for any currently executing jobs to complete, or terminate them by
deleting relevant pods.

### Job
Consider allowing the single-run job to complete.
Otherwise, delete the job with `kubectl delete job/<name>`.

### ReplicaSet
Edit the replicaset with `kubectl edit replicaset/<name>`.
Set `.spec.replicas` to `0`.

### ReplicationController
Edit the replicationcontroller with `kubectl edit rc/<name>`.
Set `.spec.replicas` to `0`.

Wait for the volumes using by the Kubernetes to complete detaching.

Then detach all remaining volumes from Longhorn UI. These volumes were most likely
created and attached outside of Kubernetes via Longhorn UI or REST API.

## Uninstall the Old Version of Longhorn

Make note of `BackupTarget` on the `Setting` page. You will need to manually
set `BackupTarget` after upgrading from either v0.1 or v0.2.

Delete Longhorn components.

For Longhorn `v0.1` (most likely installed using Longhorn App in Rancher 2.0):
```
kubectl delete -f https://raw.githubusercontent.com/llparse/longhorn/v0.1/deploy/uninstall-for-upgrade.yaml
```

For Longhorn `v0.2`:
```
kubectl delete -f https://raw.githubusercontent.com/rancher/longhorn/v0.2/deploy/uninstall-for-upgrade.yaml
```

If both commands returned `Not found` for all components, Longhorn is probably
deployed in a different namespace. Determine which namespace is in use and
adjust `NAMESPACE` here accordingly:
```
NAMESPACE=<some_longhorn_namespace>
curl -sSfL https://raw.githubusercontent.com/rancher/longhorn/v0.1/deploy/uninstall-for-upgrade.yaml|sed "s#^\( *\)namespace: longhorn#\1namespace: ${NAMESPACE}#g" > longhorn.yaml
kubectl delete -f longhorn.yaml
```

## Backup Longhorn System

We're going to backup Longhorn CRD yaml to local directory, so we can restore or inspect them later.

### v0.1
User must backup the CRDs for v0.1 because we will change the default deploying namespace for Longhorn.
Check your backups to make sure Longhorn was running in namespace `longhorn`, otherwise change the value of `NAMESPACE` below.
```
NAMESPACE=longhorn
kubectl -n ${NAMESPACE} get volumes.longhorn.rancher.io -o yaml > longhorn-v0.1-backup-volumes.yaml
kubectl -n ${NAMESPACE} get engines.longhorn.rancher.io -o yaml > longhorn-v0.1-backup-engines.yaml
kubectl -n ${NAMESPACE} get replicas.longhorn.rancher.io -o yaml > longhorn-v0.1-backup-replicas.yaml
kubectl -n ${NAMESPACE} get settings.longhorn.rancher.io -o yaml > longhorn-v0.1-backup-settings.yaml
```
After it's done, check those files, make sure they're not empty (unless you have no existing volumes).

### v0.2
Check your backups to make sure Longhorn was running in namespace
`longhorn-system`, otherwise change the value of `NAMESPACE` below.
```
NAMESPACE=longhorn-system
kubectl -n ${NAMESPACE} get volumes.longhorn.rancher.io -o yaml > longhorn-v0.2-backup-volumes.yaml
kubectl -n ${NAMESPACE} get engines.longhorn.rancher.io -o yaml > longhorn-v0.2-backup-engines.yaml
kubectl -n ${NAMESPACE} get replicas.longhorn.rancher.io -o yaml > longhorn-v0.2-backup-replicas.yaml
kubectl -n ${NAMESPACE} get settings.longhorn.rancher.io -o yaml > longhorn-v0.2-backup-settings.yaml
```
After it's done, check those files, make sure they're not empty (unless you have no existing volumes).

## Delete CRDs in Different Namespace

This is only required for Rancher users running Longhorn App `v0.1`. Delete all
CRDs from your namespace which is `longhorn` by default.
```
NAMESPACE=longhorn
kubectl -n ${NAMESPACE} get volumes.longhorn.rancher.io -o yaml | sed "s/\- longhorn.rancher.io//g" | kubectl apply -f -
kubectl -n ${NAMESPACE} get engines.longhorn.rancher.io -o yaml | sed "s/\- longhorn.rancher.io//g" | kubectl apply -f -
kubectl -n ${NAMESPACE} get replicas.longhorn.rancher.io -o yaml | sed "s/\- longhorn.rancher.io//g" | kubectl apply -f -
kubectl -n ${NAMESPACE} get settings.longhorn.rancher.io -o yaml | sed "s/\- longhorn.rancher.io//g" | kubectl apply -f -
kubectl -n ${NAMESPACE} delete volumes.longhorn.rancher.io --all
kubectl -n ${NAMESPACE} delete engines.longhorn.rancher.io --all
kubectl -n ${NAMESPACE} delete replicas.longhorn.rancher.io --all
kubectl -n ${NAMESPACE} delete settings.longhorn.rancher.io --all
```

## Install Longhorn v0.3

### Installed with Longhorn App v0.1 in Rancher 2.x
For Rancher users who are running Longhorn v0.1, **do not click the upgrade button in the Rancher App.**

1. Delete the Longhorn App from `Catalog Apps` screen in Rancher UI.
2. Launch Longhorn App template version `0.3.0`.
3. Restore Longhorn System data. This step is required for Rancher users running Longhorn App `v0.1`.
Don't change the NAMESPACE variable below, since the newly installed Longhorn system will be installed in the `longhorn-system` namespace.

```
NAMESPACE=longhorn-system
sed "s#^\( *\)namespace: .*#\1namespace: ${NAMESPACE}#g" longhorn-v0.1-backup-settings.yaml | kubectl apply -f -
sed "s#^\( *\)namespace: .*#\1namespace: ${NAMESPACE}#g" longhorn-v0.1-backup-replicas.yaml | kubectl apply -f -
sed "s#^\( *\)namespace: .*#\1namespace: ${NAMESPACE}#g" longhorn-v0.1-backup-engines.yaml | kubectl apply -f -
sed "s#^\( *\)namespace: .*#\1namespace: ${NAMESPACE}#g" longhorn-v0.1-backup-volumes.yaml | kubectl apply -f -
```

### Installed without using Longhorn App v0.1

For Longhorn v0.2 users who are not using Rancher, follow
[the official Longhorn Deployment instructions](../README.md#deployment).


## Access UI and Set BackupTarget

Wait until the longhorn-ui and longhorn-manager pods are `Running`:
```
kubectl -n longhorn-system get pod -w
```

[Access the UI](../README.md#access-the-ui).

On `Setting > General`, set `Backup Target` to the backup target used in
the previous version. In our example, this is
`nfs://longhorn-test-nfs-svc.default:/opt/backupstore`.

## Upgrade Engine Images

Ensure all volumes are detached. If any are still attached, detach them now
and wait until they are in `Detached` state.

Select all the volumes using batch selection. Click batch operation button
`Upgrade Engine`, choose the only engine image available in the list. It's
the default engine shipped with the manager for this release.

## Attach Volumes

Now we will resume all workloads by reversing the changes we made to detach
the volumes. Any volume not part of a K8s workload or pod must be attached
manually.

## Note

Upgrade is always tricky. Keeping recent backups for volumes is critical. If anything goes wrong, you can restore the volume using the backup.

If you have any issues, please report it at
https://github.com/rancher/longhorn/issues and include your backup yaml files
as well as manager logs.
