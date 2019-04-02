# Upgrade

Here we cover how to upgrade to latest Longhorn from all previous releases.

There are normally two steps in the upgrade process: first upgrade Longhorn manager to the latest version, then upgrade Longhorn engine to the latest version using latest Longhorn manager.

## Upgrade Longhorn manager from v0.3.0 or newer

### From Longhorn deployment yaml

If you didn't change any configuration during Longhorn v0.3.0 installation, follow [the official Longhorn Deployment instructions](../README.md#deployment) to upgrade.

Otherwise you will need to download the yaml file from [the official Longhorn Deployment instructions](../README.md#deployment), modify it to your need, then use `kubectl apply -f` to upgrade.

### From Longhorn App (Rancher Catalog App) 
On Rancher UI, navigate to the `Catalog Apps` screen and click the
`Upgrade available` button. Do not change any of the settings. *Do not change
any of the settings right now.* Click `Upgrade`.

Access Longhorn UI. Periodically refresh the page until the version in the
bottom left corner of the screen changes. Wait until websocket indicators in
bottom right corner of the screen turn solid green. Navigate to
`Setting> Engine Image` and wait until the new Engine Image is `Ready`.

## Upgrade Longhorn engine

**ALWAYS MAKE BACKUPS BEFORE UPGRADE THE ENGINE IMAGES.**

### Offline upgrade
If live upgrade is not available (e.g. from v0.1/v0.2 to v0.3), or the volume stuck in degraded state: 
1. Follow [the detach procedure for relevant workloads](upgrade.md#detach-volumes).
2.  Select all the volumes using batch selection. Click batch operation button
`Upgrade Engine`, choose the engine image available in the list. It's
the default engine shipped with the manager for this release.
3. Resume all workloads by reversing the [detach volumes procedure](upgrade.md#detach-volumes).
Any volume not part of a Kubernetes workload must be attached from Longhorn UI.

### Live upgrade

Live upgrade is a beta feature since v0.3.3.

Live upgrade should only be done with healthy volumes.

1. Select the volume you want to upgrade.
2. Click `Upgrade Engine` in the drop down.
3. Select the engine image you want to upgrade to.
    1. Normally it's the only engine image in the list, since the UI exclude the current image from the list.
4. Click OK.

During the live upgrade, the user will see double number of the replicas temporarily. After upgrade complete, the user should see the same number of the replicas as before, and the `Engine Image` field of the volume should be updated.

Notice after the live upgrade, Rancher or Kubernetes would still show the old version of image for the engine, and new version for the replicas. It's expected. The upgrade is success if you see the new version of image listed as the volume image in the Volume Detail page.

### Clean up the old image
After you've done upgrade for all the images, select `Settings/Engine Image` from Longhorn UI. Now you should able to remove the non-default image.

## Migrating Between Flexvolume and CSI Driver

Ensure your Longhorn App is up to date. Follow the relevant upgrade procedure
above before proceeding.

The migration path between drivers requires backing up and restoring each
volume and will incur both API and workload downtime. This can be a tedious
process; consider what benefit switching drivers will bring before proceeding.
Consider deleting unimportant workloads using the old driver to reduce effort.

### Flexvolume to CSI

CSI is the newest out-of-tree Kubernetes storage interface.

1. [Backup existing volumes](upgrade.md#backup-existing-volumes).
2. On Rancher UI, navigate to the `Catalog Apps` screen, locate the `Longhorn`
app and click the `Up to date` button. Under `Kubernetes Driver`, select
`flexvolume`. We recommend leaving `Flexvolume Path` empty. Click `Upgrade`.
3. Restore each volume by following the [CSI restore procedure](restore_statefulset.md#csi-instructions).
This procedure is tailored to the StatefulSet workload, but the process is
approximately the same for all workloads.

### CSI to Flexvolume

If you would like to migrate from CSI to Flexvolume driver, we are interested
to hear from you. CSI is the newest out-of-tree storage interface and we
expect it to replace Flexvolume's exec-based model.

1. [Backup existing volumes](upgrade.md#backup-existing-volumes).
2. On Rancher UI, navigate to the `Catalog Apps` screen, locate the `Longhorn`
app and click the `Up to date` button. Under `Kubernetes Driver`, select
`flexvolume`. We recommend leaving `Flexvolume Path` empty. Click `Upgrade`.
3. Restore each volume by following the [Flexvolume restore procedure](restore_statefulset.md#flexvolume-instructions).
This procedure is tailored to the StatefulSet workload, but the process is
approximately the same for all workloads.

## Upgrade Longhorn manager from v0.2 and older

The upgrade procedure for Longhorn v0.2 and v0.1 deployments is more involved.

### Backup Existing Volumes

It's recommended to create a recent backup of every volume to the backupstore
before upgrade. If you don't have a on-cluster backupstore already, create one.

We'll use NFS backupstore for this example.

1. Execute following command to create the backupstore
```
kubectl apply -f https://raw.githubusercontent.com/rancher/longhorn/master/deploy/backupstores/nfs-backupstore.yaml
```
2. On Longhorn UI Settings page, set Backup Target to
`nfs://longhorn-test-nfs-svc.default:/opt/backupstore` and click `Save`.

Navigate to each volume detail page and click `Take Snapshot` (it's recommended to run `sync` in the host command line before `Take Snapshot`). Click the new
snapshot and click `Backup`. Wait for the new backup to show up in the volume's backup list before continuing.

### Check For Issues

Make sure no volume is in degraded or faulted state. Wait for degraded
volumes to heal and delete/salvage faulted volumes before proceeding.

### Detach Volumes

Shutdown all Kubernetes Pods using Longhorn volumes in order to detach the
volumes. The easiest way to achieve this is by deleting all workloads and recreate them later after upgrade. If
this is not desirable, some workloads may be suspended. We will cover how
each workload can be modified to shut down its pods.

#### Deployment
Edit the deployment with `kubectl edit deploy/<name>`.
Set `.spec.replicas` to `0`.

#### StatefulSet
Edit the statefulset with `kubectl edit statefulset/<name>`.
Set `.spec.replicas` to `0`.

#### DaemonSet
There is no way to suspend this workload.
Delete the daemonset with `kubectl delete ds/<name>`.

#### Pod
Delete the pod with `kubectl delete pod/<name>`.
There is no way to suspend a pod not managed by a workload controller.

#### CronJob
Edit the cronjob with `kubectl edit cronjob/<name>`.
Set `.spec.suspend` to `true`.
Wait for any currently executing jobs to complete, or terminate them by
deleting relevant pods.

#### Job
Consider allowing the single-run job to complete.
Otherwise, delete the job with `kubectl delete job/<name>`.

#### ReplicaSet
Edit the replicaset with `kubectl edit replicaset/<name>`.
Set `.spec.replicas` to `0`.

#### ReplicationController
Edit the replicationcontroller with `kubectl edit rc/<name>`.
Set `.spec.replicas` to `0`.

Wait for the volumes using by the Kubernetes to complete detaching.

Then detach all remaining volumes from Longhorn UI. These volumes were most likely
created and attached outside of Kubernetes via Longhorn UI or REST API.

### Uninstall the Old Version of Longhorn

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

### Backup Longhorn System

We're going to backup Longhorn CRD yaml to local directory, so we can restore or inspect them later.

#### Upgrade from v0.1
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

#### Upgrade from v0.2
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

### Delete CRDs in Different Namespace

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

### Install Longhorn

#### Upgrade from v0.1
For Rancher users who are running Longhorn v0.1, **do not click the upgrade button in the Rancher App.**

1. Delete the Longhorn App from `Catalog Apps` screen in Rancher UI.
2. Launch Longhorn App template version `0.3.1`.
3. Restore Longhorn System data. This step is required for Rancher users running Longhorn App `v0.1`.
Don't change the NAMESPACE variable below, since the newly installed Longhorn system will be installed in the `longhorn-system` namespace.

```
NAMESPACE=longhorn-system
sed "s#^\( *\)namespace: .*#\1namespace: ${NAMESPACE}#g" longhorn-v0.1-backup-settings.yaml | kubectl apply -f -
sed "s#^\( *\)namespace: .*#\1namespace: ${NAMESPACE}#g" longhorn-v0.1-backup-replicas.yaml | kubectl apply -f -
sed "s#^\( *\)namespace: .*#\1namespace: ${NAMESPACE}#g" longhorn-v0.1-backup-engines.yaml | kubectl apply -f -
sed "s#^\( *\)namespace: .*#\1namespace: ${NAMESPACE}#g" longhorn-v0.1-backup-volumes.yaml | kubectl apply -f -
```

### Upgrade from v0.2

For Longhorn v0.2 users who are not using Rancher, follow
[the official Longhorn Deployment instructions](../README.md#deployment).

### Access UI and Set BackupTarget

Wait until the longhorn-ui and longhorn-manager pods are `Running`:
```
kubectl -n longhorn-system get pod -w
```

[Access the UI](../README.md#access-the-ui).

On `Setting > General`, set `Backup Target` to the backup target used in
the previous version. In our example, this is
`nfs://longhorn-test-nfs-svc.default:/opt/backupstore`.

## Note

Upgrade is always tricky. Keeping recent backups for volumes is critical. If
anything goes wrong, you can restore the volume using the backup.

If you have any issues, please report it at
https://github.com/rancher/longhorn/issues and include your backup yaml files
as well as manager logs.
