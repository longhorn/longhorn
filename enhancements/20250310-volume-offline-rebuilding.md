# Volume Offline Rebuilding

## Summary

This enhancement adds support for offline replica rebuild functionality for Longhorn volumes. It will allow rebuilding replicas while the volume is detached, enhancing the volume availability and reliability.

### Related Issues

- https://github.com/longhorn/longhorn/issues/8443

## Motivation

### Goals

- Users can perform volume offline rebuilding when volumes are detached by a global setting `offline-replica-rebuilding`.
- Users can perform volume offline rebuilding when an individual volume is detached by the API or the `kubectl` command.
- Users can cancel the offline replica rebuild process for an individual volume.

## Proposal

### API changes

Introduce new volume Action APIs `offlineRebuilding` and `cancelOfflineRebuilding`, and a new field `Volume.Spec.OfflineRebuild`:

  | API | Input | Output | Comments | HTTP Endpoint |
  | --- | --- | --- | --- | --- |
  | Update | N/A | err error | Trigger volume offline rebuilding | **POST** `/v1/volumes/{VolumeName}?action=offlineRebuilding` |
  | Update | N/A | err error | Cancel volume offline rebuilding | **POST** `/v1/volumes/{VolumeName}?action=cancelOfflineRebuilding` |

```golang
type VolumeSpec struct {
  ...
  // The backup target name that the volume will be backed up to or is synced.
  // +optional
  BackupTargetName string `json:"backupTargetName"`
  // The flag that trigger the offline replica rebuilding when volume is detached.
  // +optional
  OfflineRebuild bool `json:"offlineRebuild"`
}
```

### User Stories

- Users want to rebuild replicas while the volume is offline to ensure maintain data redundancy.
- Users want to start a workload with the volume when the volume is in offline replica rebuild process.
- The offline rebuilding process will still work after the cluster goes down and comes back up.

### User Experience In Detail

#### Trigger An Individual Volume Offline Rebuilding

When users want to rebuild a volume detached:

- By the Longhorn GUI
  1. Access the Longhorn GUI and navigate to the `Volume` page.
  2. Select the volume that needs offline replica rebuilding.
  3. Click on the `Operation` dropdown and choose `Offline Replica Rebuild`.
  4. The rebuilding volume process will be triggered, and the volume will be attached.
  5. After all replicas are health, the volume will be detached.

- By the CLI with the `kubectl` command:
  1. Use the command `kubectl -n longhorn-system edit volume [volume-name]`
  2. Set the field `Volume.spec.offlineRebuild` `true`.

  ```yaml
  apiVersion: longhorn.io/v1beta2
  kind: Volume
  metadata:
    ...
    name: [volume-name]
    namespace: longhorn-system
    ...
  spec:
    ...
    numberOfReplicas: 3
    offlineRebuild: true
    replicaAutoBalance: ignored
    ...
  ```

  3. The rebuilding volume process will be triggered, and the volume will be attached.
  4. After all replicas are health, the volume will be detached.

#### Trigger Volumes Offline Rebuilding

When users want to rebuild volumes detached:

- By the Longhorn GUI
  1. Access the Longhorn GUI and navigate to the `Setting` > `General` page.
  2. Check the checkbox `Automatically Offline Replica Rebuilding`.
  3. Click the bottom `Save` button.

- By the CLI with the `kubectl` command:

  ```shell
  kubectl -n longhorn patch setting offline-replica-rebuilding --type=merge -p '{"value": "true"}'
  ```

#### The CSI Attach Request During Volume Offline Rebuilding

When the offline rebuilding process is triggered or in progress:

1. Users try to start the workload with the Longhorn volume that is in offline rebuilding process.
2. The CSI attaching volume request is received, and canceling offline rebuilding process request will be sent and return an error.
3. After the offline rebuilding process is canceled, the volume will be detached.
4. When receiving the CSI attaching volume request again, the volume will be attached to the request node.

#### Cluster Goes Down And Comes Back Up During Volume Offline Rebuilding

Users should be aware that the rebuilding process will restart if it does not finish before the cluster goes down.

## Design

### Implementation Overview

The offline replica rebuild process involves the following steps:

- The global setting `offline-replica-rebuilding` is `true`:
  1. Identify replicas needed to rebuild in the detached volumes and the field `Spec.OfflineRebuild` of the volume will be set `true` at the setting controller.
  2. The volume rebuild controller will update the volume attachment ticket for attaching the volume that `Spec.OfflineRebuild` is set `true` at the setting controller.
  3. The rebuilding process will be started automatically by the volume controller.
  4. The volume rebuild controller will check the volume and replicas of the volume status when the volume is updated.
  5. If the rebuilt replicas are healthy, the volume rebuild controller will update the volume attachment ticket to detach the volume and the process is done.  
    <img src="./image/volume-offline-rebuild-setting-controller-flow.png" alt="volume offline rebuilding states flow" width="35%" />

- The field `Spec.OfflineRebuild` of the detached volume is set `true` by the Longhorn GUI, API or CLI:
  1. The volume rebuild controller will update the volume attachment ticket for attaching the volume if rebuilding is necessary.
  2. The rebuilding process will be started automatically by the volume controller.
  3. The volume rebuild controller will check the volume and replicas of the volume status when the volume is updated.
  4. If the rebuilt replicas are healthy (healthy replica count is equal to `Volume.Spec.NumberOfReplica` or healthy replica count is equal to ready worker nodes if it is less than `Volume.Spec.NumberOfReplica`), the volume rebuild controller will update the volume attachment ticket to detach the volume and the process is done.  
![volume offline rebuilding volume rebuild controller flow](./image/volume-offline-rebuild-vrb-controller-flow.png)

- The CSI attach request during volume offline rebuilding
  1. The canceling volume offline rebuilding will be sent by the API (set `Volume.Spec.OfflineRebuild` `false`).
  2. The volume rebuild controller will remove the volume rebuild volume attachment ticket if there is a CSI volume attachment ticket or the field `Volume.Spec.OfflineRebuild` is false.
  3. The volume will be detached when the volume rebuild volume attachment ticket is removed, then the volume will be attached when the CSI volume attachment ticket is added.

- Handle the cluster goes down and comes back up during offline rebuilding
  - The setting controller will check the value of the `offline-replica-rebuilding` setting and identify detached volumes that need to be rebuilt when the cluster comes back up.
  - The volume rebuild controller will examine all volumes:
    - If `Volume.Spec.OfflineRebuild` is `false`, remove the volume rebuild VA ticket for the volume.
    - If `Volume.Spec.OfflineRebuild` is `true` and there is no CSI VA ticket:
      - Add the volume rebuild VA ticket of the volume if it does not exist.
      - Monitor the volume rebuilding status if the volume rebuild VA ticket exists.

### Test plan

- The replica count is less than the number of replicas in the `Volume.Spec`:
  - Set the field `Volume.Spec.OfflineRebuild` `true`
    1. Create a volume with 3 replicas in a 3 worker nodes cluster and write some data to the volume.
    2. Detach the volume.
    3. Delete a replica of the volume.
    4. Trigger the offline rebuilding by the API `volume.offlineRebuilding`.
    5. Wait for the volume detached.
    6. Check if the replica count of the volume is as the number of replicas in the `Volume.Spec`.
    7. Check if the `Volume.Spec.OfflineRebuild` is `false`.

  - Set the global setting `offline-replica-rebuilding` `true`
    1. Create a volume with 3 replicas in a 3 worker nodes cluster and write some data to the volume.
    2. Detach the volume.
    3. Delete a replica of the volume.
    4. Set the global setting `offline-replica-rebuilding` `true` to trigger the offline rebuilding.
    5. Wait for the volume detached.
    6. Check if the replica count of the volume is as the number of replicas in the `Volume.Spec`.
    7. Check if the `Volume.Spec.OfflineRebuild` is `false`.
    8. Set the global setting `offline-replica-rebuilding` `false`.

- The CSI attaching request should cancel the offline rebuilding process:
  1. Create a workload with Longhorn volume having 3 replicas in a 3 worker nodes cluster
  2. Write some data to the volume.
  3. Scale down the workload to detach the volume.
  4. Delete a replica of the volume.
  5. Trigger the offline rebuilding by the API `volume.offlineRebuilding`.
  6. When the rebuilding is in progress, scale up the workload.
  7. Check if the offline rebuilding process is canceled.
  8. Check if the workload is working well.

### Upgrade strategy

No upgrade strategy is needed.
