# Multiple disks support
Longhorn supports to use more than one disk on the nodes to store the volume data.

By default, `/var/lib/rancher/longhorn` on the host will be used for storing the volume data. You can avoid using the default directory by adding a new disk, then disable scheduling for `/var/lib/rancher/longhorn`.

## Add a disk

To add a new disk for a node, heading to `Node` tab, select one of the node, and select `Edit Disks` in the drop down menu.

To add any additional disks, user needs to:
1. Mount the disk on the host to a certain directory.
2. Add the path of the mounted disk into the disk list of the node.

Longhorn will detect the storage information (e.g. maximum space, available space) about the disk automatically, and start scheduling to it if it's possible to accomodate the volume in there. A path mounted by the existing disk won't be allowed.

User can reserve a certain amount of space of the disk to stop Longhorn from using it. It can be set in the `Space Reserved` field for the disk. It's useful for the non-dedicated storage disk on the node. 

The kubelet needs to preserve node stability when available compute resources are low. This is especially important when dealing with incompressible compute resources, such as memory or disk space. If such resources are exhausted, nodes become unstable. To avoid kubelet `Disk pressure` issue after scheduling several volumes, by default, longhorn reserved 30% of root disk space (`/var/lib/rancher/longhorn`) to ensure node stability.

## Remove a disk
Nodes and disks can be excluded from future scheduling. Notice any scheduled storage space won't be released automatically if the scheduling was disabled for the node.

In order to remove a disk, two conditions need to be met:
1. The scheduling for the disk must be disabled
2. There is no existing replica using the disk, include the replica in error state.

Once those two conditions are met, you should be allowed to remove the disk.

## Configuration
There are two global settings affect the scheduling of the volume.

`StorageOverProvisioningPercentage` defines the upper bound of `ScheduledStorage / (MaximumStorage - ReservedStorage)` . The default value is `500` (%). That means we can schedule a total of 750 GiB Longhorn volumes on a 200 GiB disk with 50G reserved for the root file system. Because normally people won't use that large amount of data in the volume, and we store the volumes as sparse files.

`StorageMinimalAvailablePercentage` defines when a disk cannot be scheduled with more volumes. The default value is `10` (%). The bigger value between `MaximumStorage * StorageMinimalAvailablePercentage / 100` and `MaximumStorage - ReservedStorage` will be used to determine if a disk is running low and cannot be scheduled with more volumes.

Notice currently there is no guarantee that the space volumes used won't exceed the `StorageMinimalAvailablePercentage`, because:
1. Longhorn volume can be bigger than specified size, due to the snapshot contains the old state of the volume
2. And Longhorn is doing over-provisioning by default.
