# High-level LEP for Longhorn volume cloning and Harvester VM cloning

## Harvester VM cloning

Harvester will use the [CDI smart-cloning feature](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/smart-clone.md) to do VM cloning. The detailed flow is:
1. CDI controller only allows cloning if the source `datavolume` is not in used. So, Harvester should stop the source VM if it is currently running. Harvester should a warning message telling the user that VM will be stopped if the user selects to clone a running VM. The UI flow should be something similar to [this OKD UI flow](https://kubevirt.io/web-ui-design/ui-design/virtual-machines/clone-vm/clone-vm.html)
2. Once the VM stopped, Harvester generate a new manifest for the cloning VM with the spec identical to the source VM and the `dataVolumeTemplates` pointing to the source VM's data volume. For example:
    ```
      dataVolumeTemplates:
      - apiVersion: cdi.kubevirt.io/v1beta1
        kind: DataVolume
        metadata:
          name: dv-clone
        spec:
          pvc:
            accessModes:
            - ReadWriteMany
            resources:
              requests:
                storage: 10Gi
            storageClassName: longhorn-image-nctjw # the storageclass of the source's datavolume
            volumeMode: Block
          source:
            pvc:
              namespace: "default"
              name: "source-dv"
    ```
3. Once, the YAML manifest is applied, CDI controller will attempt to clone the source `datavolume` by using [CDI smart-cloning feature](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/smart-clone.md). In particular, CDI controller does:
    1. Create a CSI snapshot of the source PVC. Note: if there are multiple snapshot classes, I am currently not sure how CDI picks one. We will need more investigation on this because Longhorn is planning to allow users to specify the definition of the CSI snapshot in the snapshot class. Users can define CSI snapshots as Longhorn backups or Longhorn snapshots.
    2. Create a PVC from the created CSI snapshot
    3. Delete the CSI snapshot
4. Once the new cloning `datavolume` is ready, Kubevirt starts the cloning VM with the cloning `datavolume`

## Longhorn volume cloning

### Implement the ability to restore a Longhorn snapshot of a volume, into backing image/replica on any node.
1. If the source volume is not attached, the Longhorn manager automatically attaches the volume to a random node with the front end disabled.
2. Longhorn manager launches a backing image manager for a new backing image; or a replica process for the new volume on the corresponding node.
3. Longhorn manager asks the sender sync agent server on the source replica to build a read-only replica struct
4. Longhorn manager asks the receiver (backing image manager or the replica of the new volume) to start a sparse file receiving server
5. Longhorn manager ask the sender sync agent server to send the file via the sparse file API

## Use the previous feature to implement the ability to create a new volume from a snapshot of another volume

## Support mapping CSI snapshot to Longhorn snapshots
Before the LEP, CSI snapshot is mapped to Longhorn backup. Now that we have ability to create a new volume from a snapshot of another volume, we can also support mapping CSI snapshot to Longhorn snapshot. The idea is that user can specify the definition of the CSI snapshot in the snapshot class. Users can define CSI snapshots as Longhorn backups or Longhorn snapshots.

With this feature, Harvester doesn't need to have a backup target to do VM cloning.

## Implement CSI volume cloning
Now that we have the ability to create a volume from a Longhorn snapshot, we can implement CSI volume cloning by:
1.  If the source volume is not attached, automatically attaches the volume to a random node with the front end disabled.
3. Create a new volume from the volume head snapshot of the source volume
4. Detach both the source and the cloning volume





