# Longhorn System Backup/Restore

## Summary

This feature is to support the Longhorn system backup and restore. And also allows the user to rollback the Longhorn
system to the previous healthy state
after a failed upgrade.

Currently, we have documents to guide users on how to restore Longhorn:
- [Restore to a new cluster using Velero](https://longhorn.io/docs/1.3.0/advanced-resources/cluster-restore/restore-to-a-new-cluster-using-velero/)
- [Restore to a cluster contains data using Rancher snapshot](https://longhorn.io/docs/1.3.0/advanced-resources/cluster-restore/restore-to-a-cluster-contains-data-using-rancher-snapshot/)

However, the solution relies on third-party tools, not out-of-the-box, and involves tedious human intervention.

With this new feature, Longhorn's custom resources will be backed up and bundled into a single system backup file, then
saved to the remote backup target.

Later, users can choose a system backup to restore to a new cluster or restore to an existing cluster; nevertheless,
this allows for cluster rollback to fix the corrupted cluster state just after a failed upgrade.

### Related Issues

https://github.com/longhorn/longhorn/issues/1455

## Motivation
### Goals

- Support Longhorn system backup by backing up Longhorn custom resources, bundling them to a single file, and uploading
  it to the backup target.
- Support Longhorn system restore to a new/existing cluster from a system backup.
- Support Longhorn system restoration to the previous healthy state when encountering the failed upgrade.
- Support restoring volume from the `lastBackup` when the volume doesn't exist in the cluster during the system restore.
- Support not restoring volume from the `lastBackup` when the volume exists in the cluster during the system restore.

### Non-goals [optional]

- This feature does not deploy the Longhorn cluster. Users need to have a running Longhorn cluster to run the system
  restore.
- Do backup/restore the downstream workloads attached to Longhorn volumes. For example, if a cluster has a Pod with a
  PersistentVolumeClaim. Longhorn will restore the PersistentVolumeClaim, PersistentVolume, and Volume only. After a
  successful system restoration, the user can re-deploy the pod with the same manifest.
- Restore while there are volumes still attached.
- Automatically create a system backup before an upgrade and run the system restore when the Longhorn upgrade fails.
  Instead, the user needs to run a system backup and restore it manually.
- Delete resources none-existing in the system backup. We can probably enhance it later and make this an option for the
  users.
- Support restore from `BackingImage`. **Dependent on https://github.com/longhorn/longhorn/issues/4165**

## Proposal
### System Backup

```

        |------------ [[ longhorn-backup-target ]] ----------|
        |                     controller                     |
        |                                                    |
        v                                                    v
[ SystemBackup ] ---> [[ longhorn-system-backup ]] ---> [ object store ]
       CR                        controller                  |
                                                             |
                                    backupstore/system-backups/<longhorn-version>/<name>/
                                                             |
                                   [ system-backups.zip ] <--|--> [ system-backup.cfg ]
```

1. Introduce new [v1/systembackups](#longhorn-manager-http-api) HTTP APIs.
1. Introduce a new [SystemBackup](#manager-systembackup-custom-resource) custom resource definition.
    - A new custom resource triggers the creation of the system [resource](#system-backup-resources) backup.
    - Deleting the custom resource triggers deletion of the system backup in the backup target.
      This behavior is similar to the current backup resource handling.
    - The system backups stored in the backup target will get synced to the custom resources list.
1. Introduce new responsibility to `longhorn-backup-target` controller.
    - Responsible for syncing system backups in the backup target to the `SystemBackup` list.
1. Introduce a new `longhorn-system-backup` controller.
    - Responsible for generating the system backup file, bundling them to a single file, and uploading it to the backup
      target.
      1. Generates the Longhorn resources YAML files.
      1. Compress resources YAML files to a zip file.
      1. Upload to the backup target `backupstore/system-backups/<longhorn-version>/<system-backup-name>`.
      >**Note:** Do not create/upload the system backup when the `SystemBackup` is created by the backup target controller.

    - Responsible for deleting system backup in the backup target.
    - Responsible for updating `SystemBackup` status.
    - Responsible for updating the error message in the `SystemBackup` status condition.
      Reference [SystemRestore](#manager-systemrestore-custom-resource) condition as the example.
1. Introduce `SystemBackup` webhook validator for [condition validation](#validator-system-backup).

### System Restore

```

                                            [ system-backup.zip ]   [ backups ]]]
                                                            ^          ^
                                                            |          |
            [ system-backup.cfg ] <-- backupstore/system-backups/...   |
                                                            |          |
                                                            |       backupstore/volumes/
                                                            |          |
                                                            |          |
[ SystemRestore ] ---> [[ longhorn-system-restore ]] ---> [ object-store ]
        CR                      controller                  |          |
                                     |                      |          |
                                     |                      |          |
                                  [ Job ]                   |    [ system-backup.cfg: engine ]
                                     |                      |          |               
                                     v                      |          |               
                [ system-backup.cfg: manager ] ---> [[ longhorn-system-rollout ]]  
                                                             controller
                                                            |          |
                                                            |          v               
                                                            | <--- [ Volume: from backup ]
                                                            |
                                                           V
                                                    [ Resources ]]]]
```

1. Introduce new [v1/systemrestores](#longhorn-manager-http-api) HTTP APIs.
1. Introduce a new [SystemRestore](#manager-systemrestore-custom-resource) custom resource definition.
    - A new custom resource triggers the creation of a system restore job.
    - Deleting the custom resource triggers the deletion of the system restore job.
1. Introduce a new `longhorn-system-restore` controller.
    - Responsible for creating a new system restore job that runs a `longhorn-system-rollout` controller.
    - Responsible for deleting the system restore job.
1. Introduce a new `longhorn-system-rollout` controller. This controller is similar to the `uninstall controller`.
    - Run inside the pod created by the system restore job.
    - Responsible for downloading the system-backup from the backup target.
    - Responsible for restoring [resources](#system-backup-resources) from the system-backup file.
    - Responsible for updating `SystemRestore` status during system restore.
    - Responsible for adding `longhorn.io/last-system-restore`, and `longhorn.io/last-system-restore-at` annotation to the
    restored resources.
    - Responsible for adding `longhorn.io/last-system-restore-backup`annotation to the restored volume resources.
    - Responsible for updating the error message in the [SystemRestore](#manager-systemrestore-custom-resource) status
    condition.

    > **Note:** There are 2 areas covered for cross version restoration:
    > 1. The system restore will use the manager and engine image in the system backup config to run the `longhorn-system-rollout` so the controller is compatible with the restoring resources.
    > 1. When the CustomResourceDefinition is missing the version for the restoring resource, the system restore doesn't replace or remove the existing CustomResourceDefinitions. Instead, the controller adds to its versions. So system restoration doesn't break existing resources.
    >
    > See [Specify multiple versions](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning/#specify-multiple-versions) for details.

1. Introduce `SystemRestore` webhook validator for [condition validation](#validator-system-restore).


### User Stories

#### Longhorn system restore

Before the enhancement, the user can follow the [documents](#summary) to leverage external solutions to backup and
restore the Longhorn system.

After the enhancement, the user can backup/restore Longhorn system to/from the backup target using this Longhorn native
solution.

#### Upgrade rollback (downgrade)

Before the enhancement, the user cannot downgrade Longhorn.

After the enhancement, the user can downgrade Longhorn when there is a pre-upgrade system backup in the backup target.

> **Note:** For the Longhorn cluster version before v1.4.0, users still need to follow the Longhorn [documents](#summary)
            for backup and restore the Longhorn system.

### User Experience In Detail

### Longhorn UI

1. Go to `System Backup` from the Setting drop-down menu.
    ```
    | Dashboard | Node | Volume | Recurring Job | Backup | Setting v |
                                                           + ======================= +
                                                           | General                 |
                                                           | Engine Image            |
                                                           | Orphaned Data           |
                                                           | Backing Image           |
                                                           | Instance Manager Image  |
                                                           | System Backup           |
                                                           + ======================= +
    ```
1. View `System Backups` and `System Restores` on the same page.
    ```
    System Backups                                                                                      [Custom Column]
    ====================================================================================================================
    [Create] [Delete] [Restore]                                                       [Search Box   v ][__________][Go]
                                                                                          + ======= +
    ======================================================================================| Name    |===================
    [] | Version  | Name   | State   | Error                                              | State   |
    ---+----------+--------+--------+-----------------------------------------------------| Version |-------------------
    [] | 1.4.0    | demo-1 | Error   | error uploading system backup: failed to execute:  + ======= + /engine-binaries/c3y1huang-research-000-lh-ei/longhorn [system-backup
       :          :        :         : upload --source /tmp/demo-2.zip --dest s3://backupbucket@us-east-1/ --name demo-2 --manager-image c3y1huang/research:000-lh-manager
       :          :        :         : --engine-image c3y1huang/research:000-lh-ei], output , stderr, time=\"2022-08-16T03:52:09Z\" level=fatal msg=\"Failed to run upload
       :          :        :         : system-backup command\" error=\"missing required parameter --longhorn-version\"\n, error exit status 1
    [] | 1.4.0    | demo-2 | Ready   |
    ====================================================================================================================
                                                     [<] [1] [>]

    System Restores                                                                                     [Custom Column]
    ====================================================================================================================
    [Delete]                                                                           [Search Box   v ][_________][Go]
                                                                                           + ======= +
    ====================================================================================== | Name    |==================
    [] | Name           | Version   | State        | Age   | Error                         | State   |
    ---+----------------+-----------+--------------+-------+------------------------------ | Version |------------------
    [] | demo-1-restore | v1.4.0    | Completed    | 2m26s |                               + ======= +
    [] | demo-2-foobar  | v1.4.0    | Error        | 64s   | Download: sample error message
    [] | demo-2-restore | v1.4.0    | Initializing | 1s    |
    ===================================================================================================================
                                                     [<] [1] [>]
    ```

### System Backup
***Longhorn GUI***
  - The user can create system backups to the backup target.
  - The system backup will be uploaded to backup target `backupstore/system-backups/<longhorn-version>/<system-backup-name>`.
  - The user can view the system backup status.

***Command kubectl***
  - The user can create `SystemBackup` to backup Longhorn system to the backup target.
    ```yaml
    apiVersion: longhorn.io/v1beta2
    kind: SystemBackup
    metadata:
      name: demo-2
      namespace: longhorn-system
    ```
  - The user can view the system backups.
    ```
    > kubectl -n longhorn-system get lhsb
    NAMESPACE         NAME     VERSION   STATE   CREATED
    longhorn-system   demo-1   v1.4.0    Error   2022-08-23T00:25:29Z
    longhorn-system   demo-2   v1.4.0    Ready   2022-08-24T02:34:57Z
    ```

### System Restore
***Longhorn GUI***
  - The users can restore a system backup in the backup target.
  - The users can view the system restore status.
  - The users can restore from a different Longhorn version.

***Command kubectl***
  - The user can create `SystemRestore` to restore system backup in the backup target.
    ```yaml
    apiVersion: longhorn.io/v1beta2
    kind: SystemRestore
    metadata:
      name: demo-2-restore
      namespace: longhorn-system
    spec:
      systemBackup: demo-2
    ```
  - The users can view the system restores.
    ```
    > kubectl -n longhorn-system get lhsr
    NAME             STATE         AGE
    demo-1-restore   Completed     2m26s
    demo-2-foobar    Error         64s
    demo-2-restore   Initializing  1s
    ```

### API changes

#### Longhorn manager HTTP API

| Method     | Path                             | Description                                                            |
| ---------- | -------------------------------- | ---------------------------------------------------------------------- |
| **POST**   | `/v1/systembackups`              | Generates system backup file and upload to the backup target           |
| **GET**    | `/v1/systembackups`              | Get all system backups. Including ones already exist in the backup target and ones that are initialized but do not exist in the backup target |
| **DELETE** | `/v1/systembackups/{name}`       | Delete system backup saved in the backup target                        |
| **POST**   | `/v1/systemrestores`             | Download a system backup from the backup target and restore it         |
| **GET**    | `/v1/systemrestores`             | Get all system restores                                                |
| **DELETE** | `/v1/systemrestores/{name}`      | Delete a system restore                                                |
|            | `/v1/ws/{period}/systembackups`  | Websocket stream for system backups                                    |
|            | `/v1/ws/{period}/systemrestores` | Websocket stream for system restores                                   |

## Design
### Implementation Overview

#### Manager: SystemBackup custom resource
```yaml
apiVersion: longhorn.io/v1beta2
kind: SystemBackup
metadata:
  creationTimestamp: "2022-08-25T02:50:06Z"
  finalizers:
  - longhorn.io
  generation: 1
  labels:
    longhorn.io/version: v1.4.0
  name: demo-2
  namespace: longhorn-system
  resourceVersion: "420138"
  uid: 41aac4e1-4367-4e17-b4b6-cb7c19151442
spec: {}
status:
  conditions: null
  createdAt: "2022-08-24T04:44:32Z"
  gitCommit: 95292c60bb17b77591d6dde5c8636fe6bb4de60d-dirty
  lastSyncedAt: "2022-08-25T02:50:19Z"
  managerImage: "longhornio/longhorn-manager:v1.4.0"
  ownerID: ip-10-0-1-105
  state: Ready
  version: v1.4.0
```

#### Manager: sync system backups in the backup target

***longhorn-backup-target-controller***
1. Execute engine binary [system-backup list](#engine-commands).
1. Check for system backups in the backup target that are not in the `SystemBackup` list.
1. Create new `SystemBackup`s and label with `longhorn.io/version: <version>` for the non-existing system backups.
1. Check for system backups in the `SystemBackup` list that are not in the backup target.
1. Delete `SystemBackup` for the non-existing system backups.
1. Delete `SystemBackup` custom resources when the backup target is empty.

***longhorn-system-backup-controller***
1. For `SystemBackup` with the `longhorn.io/version: <version>` label, execute the engine binary
   [system-backup get-config](#engine-commands) using the `<version>`.
1. Update `SystemBackup` status from the [system backup config](#system-backup-cfg).

#### Manager: system backup to the backup target

***POST /v1/systembackups***
```golang
type SystemBackupInput struct {
	Name string `json:"name"`
}
```
1. Create `SystemBackup`.
   ```yaml
   apiVersion: longhorn.io/v1beta2
   kind: SystemBackup
   metadata:
     name: <name>
     namespace: longhorn-system
   ```
1. Return system backup resource.
   <a name="system-backup-resource"></a>
   ```golang
    type SystemBackup struct {
    	client.Resource
    	Name         string                     `json:"name"`
    	Version      string                     `json:"version,omitempty"`
    	ManagerImage string                     `json:"managerImage,omitempty"`
    	State        longhorn.SystemBackupState `json:"state,omitempty"`
    	CreatedAt    string                     `json:"createdAt,omitempty"`
    	Error        string                     `json:"error,omitempty"`
    }
   ```

***webhook validator*** <a name="validator-system-backup"></a>
1. Skip validation for `SystemBackup` created by the backup target controller.
1. Allow `SystemBackup` to create if met conditions.
   - The backup target is set.
   - System backup does not exist in the backup target.

***longhorn-system-backup-controller***
```none
system-backup.zip
+ metadata.yaml
|
+ yamls/
  + apiextensions/
  | + customresourcedefinitions.yaml
  |  
  + kubernetes/
  | + clusterrolebindings.yaml
  | + clusterroles.yaml
  | + configmaps.yaml
  | + daemonsets.yaml
  | + deployments.yaml
  | + persistentvolumeclaims.yaml
  | + persistentvolumes.yaml
  | + podsecuritypolicies.yaml
  | + rolebindings.yaml
  | + roles.yaml
  | + serviceaccounts.yaml
  | + services.yaml
  |
  + longhorn/
    + engineimages.yaml
    + recurringjobs.yaml
    + settings.yaml
    + volumes.yaml
```
1. Create metadata file.
    ```golang
    type SystemBackupMeta struct {
    	LonghornVersion        string      `json:"longhornVersion"`
    	LonghornGitCommit      string      `json:"longhornGitCommit"`
    	KubernetesVersion      string      `json:"kubernetesVersion"`
    	LonghornNamespaceUUID  string      `json:"longhornNamspaceUUID"`
    	SystemBackupCreatedAt  metav1.Time `json:"systemBackupCreatedAt"`
    	ManagerImage           string      `json:"managerImage"`
    }
    ```
1. Generated the resource YAML files:
   <a name="system-backup-resources"></a>
   1. Generate the API extension resource YAML file.
      - CustomResoureDefinitions with API group `longhorn.io`.
   1. Generate the Kubernetes resources YAML files.
      - ServiceAccounts in the Longhorn namespace.
      - ClusterRoleBinding with any Longhorn ServiceAccounts in the `subjects`.
      - ClusterRoles with any Longhorn ClusterRoleBindings in the `roleRef`.
      - Roles in Longhorn namespace.
      - PodSecurityPolicies with Longhorn Role in the `rules`.
      - RoleBindings in the Longhorn namespace.
      - DaemonSets in Longhorn namespace.
      - Deployments in Longhorn namespace.
      - `longhorn-storageclass` ConfigMap.
      - Services in Longhorn namespace. The ClusterIP and ClusterIPs will get removed before converting to the YAML.
      - StorageClasses with provisioner `driver.longhorn.io`.
      - PersistentVolumes with Longhorn StorageClass in spec.
      - PersistentVolumeClaims with Longhorn StorageClass in spec.
   1. Generate the Longhorn resources YAML files.
      - Longhorn Settings.
      - Longhorn EngineImages.
      - Longhorn Volumes.
      - Longhorn RecurringJobs.
1. Archive the files to a zip file.
1. Execute engine binary [system-backup upload](#engine-commands) to upload to the backup target
   `backupstore/system-backups/<longhorn-version>/<system-backup-name>`.

#### Manager: list system backups (GET /v1/systembackups)
1. List `SystemBackup`.
1. Return collection of [SystemBackup](#system-backup-resource) resource.

#### Manager: delete system backup in the backup target

***DELETE /v1/systembackups/{name}***
1. Deletes `SystemBackup`.

***longhorn-system-backup-controller***
1. Execute engine binary [system-backup delete](#engine-commands) to remove the system backup
   in the backup target.
1. Cleanup local generated system backup files and directory that has not been uploaded to the backup target.

#### Manager: SystemRestore custom resource
```yaml
apiVersion: longhorn.io/v1beta2
kind: SystemRestore
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"longhorn.io/v1beta2","kind":"SystemRestore","metadata":{"annotations":{},"name":"demo-2-restore","namespace":"longhorn-system"},"spec":{"systemBackup":"demo-2"}}
  creationTimestamp: "2022-08-24T04:44:51Z"
  finalizers:
  - longhorn.io
  generation: 1
  name: demo-2-restore
  namespace: longhorn-system
  resourceVersion: "283819"
  uid: ef93355d-3b73-4fdd-bed3-ec5016a6784d
spec:
  systemBackup: demo-2
status:
  conditions:
  - lastProbeTime: ""
    lastTransitionTime: "2022-08-24T04:44:59Z"
    message: sample error message
    reason: Download
    status: "True"
    type: Error
  ownerID: ip-10-0-1-113
  sourceURL: s3://backupbucket@us-east-1/backupstore/system-backups/v1.4.0/demo-2
  state: Error
```

#### Manager: restore system backup from the backup target 

***POST /v1/systemrestores***
```golang
type SystemRestoreInput struct {
	Name         string `json:"name"`
	Version      string `json:"version"`
	SystemBackup string `json:"systemBackup"`
}
```
1. Create `SystemRestore`.

***webhook validator*** <a name="validator-system-restore"></a>
1. Allow `SystemRestore` to create if met conditions.
   - All volumes are detached.
   - No other system restore is in progress.
   - The SystemBackup used in the SystemRestore `Spec.SystemBackup` must exist.

***longhorn-system-restore-controller***
1. Get system backup config from the backup target.
1. Create a system restore job with the manager image from the [system backup config](#system-backup-cfg).
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: <system-restore-name>
  namespace: longhorn-system
spec:
  backoffLimit: 3
  template:
    metadata:
      name: <system-restore-name>
    spec:
      containers:
      - command:
        - longhorn-manager
        - system-restore
        - <system-backup name>
        env:
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
        - name: NODE_NAME
          value: <controller-id>
        image: <manager-image-in-system-backup-config>
        imagePullPolicy: IfNotPresent
        name: <system-restore-name>
        volumeMounts:
        - mountPath: /var/lib/longhorn/engine-binaries/
          name: engine
      nodeSelector:
        kubernetes.io/hostname: <controller-id>
      restartPolicy: OnFailure
      serviceAccount: <longhorn-service-account>
      serviceAccountName: <longhorn-service-account>
      volumes:
      - hostPath:
          path: /var/lib/longhorn/engine-binaries/
          type: ""
        name: engine
```

***command: system-restore***
1. Start and run longhorn-system-rollout controller.

***longhorn-system-rollout-controller***
1. Get system backup config from the backup target.
1. Check and create the engine image in the [system backup config](#system-backup-cfg) if the engine image is not in the cluster.
1. Execute engine binary [system-backup download](#engine-commands).
1. Unzip system backup.
1. Decode the resources from files.
    ```golang
    type SystemBackupLists struct {
    	customResourceDefinitionList *apiextensionsv1.CustomResourceDefinitionList

    	clusterRoleList        *rbacv1.ClusterRoleList
    	clusterRoleBindingList *rbacv1.ClusterRoleBindingList
    	roleList               *rbacv1.RoleList
    	roleBindingList        *rbacv1.RoleBindingList

    	daemonSetList  *appsv1.DaemonSetList
    	deploymentList *appsv1.DeploymentList

    	configMapList             *corev1.ConfigMapList
    	persistentVolumeList      *corev1.PersistentVolumeList
    	persistentVolumeClaimList *corev1.PersistentVolumeClaimList
    	serviceAccountList        *corev1.ServiceAccountList

    	podSecurityPolicyList *policyv1beta1.PodSecurityPolicyList

    	engineImageList  *longhorn.EngineImageList
    	recurringJobList *longhorn.RecurringJobList
    	settingList      *longhorn.SettingList
    	volumeList       *longhorn.VolumeList
    }
    ```
    - Kubernetes resources from files in the `kubernetes` directory.
    - API extension resources from files in the `apiextensions` directory.
    - Longhorn resources from files in the `longhorn` directory.
1. Restore Setting resources and annotate with `longhorn.io/last-system-restore`, and `longhorn.io/last-system-restore-at`.
1. Restore resources asynchronously and annotate with `longhorn.io/last-system-restore`, and `longhorn.io/last-system-restore-at`.
    - ServiceAccounts.
    - ClusterRoles.
    - ClusterRoleBindings.
    - CustomResourceDefinitions.
      > **Note:** The controller will not replace the custom resource definitions for version compatibility purposes.
                  Instead, it will add to the existing one if the custom resource definition version is different. Or
                  create if missing.

    - PodSecurityPolicies.
    - Roles.
    - RoleBindings.
    - ConfigMaps.
    - Deployments.
    - DaemonSets.
    - EngineImages.
    - Volumes. Annotate with `longhorn.io/last-system-restore-backup` if the volume is restored from the backup.
    - StorageClasses.
    - PersistentVolumes.
    - PersistentVolumeClaims.
    - RecurringJobs.
1. Update [SystemRestore](#manager-systemrestore-custom-resource) status and error.
1. Shutdown longhorn-system-rollout controller.

#### Engine: commands
- [BackupStore: `system-backup upload`](#cmd-system-backup-upload)
- [BackupStore: `system-backup delete`](#cmd-system-backup-delete)
- [BackupStore: `system-backup download`](#cmd-system-backup-download)
- [BackupStore: `system-backup list`](#cmd-system-backup-list)
- [BackupStore: `system-backup get-config`](#cmd-system-backup-get-config)

#### BackupStore: commands

<a name="cmd-system-backup-upload"></a>

***Command: system-backup upload***
| Argument         | Usage                             |
| -----------------| --------------------------------- |
| 0                | the source local file path        |
| 1                | the destination system backup URL |

| Flag           | Usage                                                |
| -------------- | ---------------------------------------------------- |
| git-commit     | Longhorn manager git commit of the current cluster   |
| manager-image  | Longhorn Manager image of the current cluster        |
| engine-image   | Longhorn default Engine image of the current cluster |

1. Upload local file to the object store `backupstore/system-backups/<longhorn-version>/<system-backup-name>/system-backup.zip`.
1. Create system backup config.
    ```golang
    type SystemBackupConfig struct {
    	Name            string
    	Version         string
    	GitCommit       string
    	BackupTargetURL string
    	ManagerImage    string
    	EngineImage     string
    	CreatedAt       time.Time
    	Checksum        string // sha512
    }
    ```
1. Upload system backup config to the object store `backupstore/system-backups/<longhorn-version>/<system-backup-name>/system-backup.cfg`.
    <a name="system-backup-cfg"></a>
    ```json
    {
      "Name":"demo-2",
      "Version":"v1.4.0",
      "GitCommit":"95292c60bb17b77591d6dde5c8636fe6bb4de60d-dirty",
      "BackupTargetURL":"s3://backupbucket@us-east-1/",
      "ManagerImage":"c3y1huang/research:000-lh-manager",
      "EngineImage":"c3y1huang/research:000-lh-ei",
      "CreatedAt":"2022-08-24T04:44:32.463197176Z",
      "Checksum":"343b328f97f3ee7af6627eed0d9f42662633c0a2348d4eddaa8929a824452fdde0de6f5620c3ea309579bb58381e48bbb013e92492924fcd3dc57006147e2626"
    }
    ```

<a name="cmd-system-backup-download"></a>

***Command: system-backup download***
| Argument         | Usage                         |
| -----------------| ----------------------------- |
| 0                | the source system backup URL  |
| 1                | the destination local path    |

1. Download the system backup zip file from object store to the local path.
1. Verify the checksum of the system backup zip file. Delete the downloaded file when the checksum is mismatched.


<a name="cmd-system-backup-delete"></a>

***Command: system-backup delete***
| Argument         | Usage                   |
| -----------------| ----------------------- |
| 0                | the system backup URL   |

1. Delete a system backup in the object store.


<a name="cmd-system-backup-list"></a>

***Command: system-backup list***
| Argument         | Usage                                              |
| -----------------| -------------------------------------------------- |
| 0                | the backup target URL where system backup exists   |

1. List system backups in the object store.
    ```
    map[string]string{
      "demo-1": "backupstore/system-backups/v1.4.0/demo-1",
      "demo-2": "backupstore/system-backups/v1.4.0/demo-2",
    }
    ```

<a name="cmd-system-backup-get-config"></a>

***Command: system-backup get-config***
| Argument         | Usage                   |
| -----------------| ----------------------- |
| 0                | the system backup URL   |

1. Output the [system backup config](#system-backup-cfg) from the object store.

### Test plan

#### System Backup
- Test system backup to the backup target.
- Test system backup should fail when the backup target is empty.
- Test system backup should fail when the backup target is unreachable.

#### System Restore

***Same Version***
- Test system restore to the same cluster.
- Test system restore to a new cluster.
- Test system restore can restore volume data from the last backup.
- Test system restore should fail when the volume is attached.
- Test system restore when another one is in progress.
- Test system restore sync from the backup target.
- Test system restore each resource when exist in the cluster.
- Test system restore each resource when not exist in the cluster.
- Test system restore failed to unzip.
- Test system restore failed to restore resources.

***Version Jump***
- Test system restore to lower Longhorn version of each Longhorn installation method (kubectl/helm/Rancher).
- Test system restore to higher Longhorn version of each Longhorn installation method (kubectl/helm/Rancher).
- Test system restore to cluster with multiple engine images.

### Upgrade strategy

`None`

## Note [optional]

`None`
