# Settings

## Customized Default Setting

To setup setting before installing Longhorn, see [Customized Default Setting](./customized-default-setting.md) for details.

## General
#### Backup Target
* Example: `s3://backupbucket@us-east-1/backupstore`
* Description: The target used for backup. Support NFS or S3. See [Snapshot and Backup](./snapshot-backup.md) for details.

#### Backup Target Credential Secret
* Example: `s3-secret`
* Description: The Kubernetes secret associated with the backup target. See [Snapshot and Backup](./snapshot-backup.md) for details.

#### Backupstore Poll Interval
* Example: `300`
* Description: In seconds. The interval to poll the backup store for updating volumes' Last Backup field. Set to 0 to disable the polling. See [Disaster Recovery Volume](./dr-volume.md) for details.

#### Create Default Disk on Labeled Nodes
* Example: `false`
* Description: Create default Disk automatically only on Nodes with the Kubernetes label `node.longhorn.io/create-default-disk=true` if no other Disks exist. If disabled, the default Disk will be created on all new Nodes when the node was detected for the first time.
* Note: It's useful if the user want to scale the cluster but doesn't want to use the storage on the new nodes.

#### Default Data Path
* Example: `/var/lib/rancher/longhorn`
* Description: Default path to use for storing data on a host
* Note: Can be used with `Create Default Disk on Labeled Nodes` option, to make Longhorn only use the nodes with specific storage mounted at e.g. `/opt/longhorn` directory when scaling the cluster.

#### Default Engine Image
* Example: `longhornio/longhorn-engine:v0.6.0`
* Description: The default engine image used by the manager. Can be changed on the manager starting command line only
* Note: Every Longhorn release will ship with a new Longhorn engine image. If the current Longhorn volumes are not using the default engine, a green arrow will show up, indicate this volume needs to be upgraded to use the default engine.

#### Enable Upgrade Checker
* Example: `true`
* Description: Upgrade Checker will check for new Longhorn version periodically. When there is a new version available, it will notify the user using UI

#### Latest Longhorn Version
* Example: `v0.6.0`
* Description: The latest version of Longhorn available. Update by Upgrade Checker automatically
* Note: Only available if `Upgrade Checker` is enabled.

#### Default Replica Count
* Example: `3`
* Description: The default number of replicas when creating the volume from Longhorn UI. For Kubernetes, update the `numberOfReplicas` in the StorageClass
* Note: The recommended way of choosing the default replica count is: if you have more than three nodes for storage, use 3; otherwise use 2. Using a single replica on a single node cluster is also OK, but the HA functionality wouldn't be available. You can still take snapshots/backups of the volume.

#### Guaranteed Engine CPU
* Example: `0.2`
* Description: (EXPERIMENTAL FEATURE) Allow Longhorn Engine to have guaranteed CPU allocation. The value is how many CPUs should be reserved for each Engine/Replica Manager Pod created by Longhorn. For example, 0.1 means one-tenth of a CPU. This will help maintain engine stability during high node workload. It only applies to the Instance Manager Pods created after the setting took effect. WARNING: Starting the system may fail or stuck while using this feature due to the resource constraint. Disabled (\"0\") by default.
* Note: Please set to **no more than a quarter** of what the node's available CPU resources, since the option would be applied to the two instance managers on the node (engine and replica), and the future upgraded instance managers (another two for engine and replica). 

#### Default Longhorn Static StorageClass Name
* Example: `longhorn-static`
* Description: The `storageClassName` is for PV/PVC when creating PV/PVC for an existing Longhorn volume. Notice that it's unnecessary for users to create the related StorageClass object in Kubernetes since the StorageClass would only be used as matching labels for PVC bounding purpose. By default 'longhorn-static'.

#### Kubernetes Taint Toleration
* Example: `nodetype=storage:NoSchedule`
* Description: By setting tolerations for Longhorn then adding taints for the nodes, the nodes with large storage can be dedicated to Longhorn only (to store replica data) and reject other general workloads.
Before modifying toleration setting, all Longhorn volumes should be detached then Longhorn components will be restarted to apply new tolerations. And toleration update will take a while. Users cannot operate Longhorn system during update. Hence it's recommended to set toleration during Longhorn deployment.
Multiple tolerations can be set here, and these tolerations are separated by semicolon. For example, "key1=value1:NoSchedule; key2:NoExecute"
* Note: See [Taint Toleration](./taint-toleration.md) for details.

## Scheduling
#### Replica Soft Anti-Affinity
* Example: `true`
* Description: Allow scheduling on nodes with existing healthy replicas of the same volume
* Note: If the users want to avoid temporarily node down caused replica rebuild, they can set this option to `false`. The volume may be kept in `Degraded` state until another node that doesn't already have a replica scheduled comes online.

#### Storage Over Provisioning Percentage
* Example: `500`
* Description: The over-provisioning percentage defines how much storage can be allocated relative to the hard drive's capacity.
* Note: The users can set this to a lower value if they don't want overprovisioning storage. See [Multiple Disks Support](./multidisk.md#configuration) for details. Also, a replica of volume may take more space than the volume's size since the snapshots would need space to store as well. The users can delete snapshots to reclaim spaces.

#### Storage Minimal Available Percentage
* Example: `10`
* Description: If one disk's available capacity to it's maximum capacity in % is less than the minimal available percentage, the disk would become unschedulable until more space freed up.
* Note: See [Multiple Disks Support](./multidisk.md#configuration) for details.
