# Multiple disks support
Longhorn supports to use more than one disk on the nodes to store the volume data.

To add a new disk for a node, heading to `Node` tab, select one of the node, and click the edit disk icon.

By default, `/var/lib/rancher/longhorn` on the host will be used for storing the volume data.

To add any additional disks, user needs to:
1. Mount the disk on the host to a certain directory.
2. Add the path of the mounted disk into the disk list of the node.

Longhorn will detect the storage information (e.g. maximum space, available space) about the disk automatically, and start scheduling to it if it's possible to accomodate the volume in there. A path mounted by the existing disk won't be allowed.

User can reserve a certain amount of space of the disk to stop Longhorn from using it. It can be set in the `Space Reserved` field for the disk. It's useful for the non-dedicated storage disk on the node.

Nodes and disks can be excluded from future scheduling. Notice any scheduled storage space won't be released automatically if the scheduling was disabled for the node.

There are two global settings affect the scheduling of the volume as well.

`StorageOverProvisioningPercentage` defines the upper bound of `ScheduledStorage / (MaximumStorage - ReservedStorage)` . The default value is `500` (%). That means we can schedule a total of 750 GiB Longhorn volumes on a 200 GiB disk with 50G reserved for the root file system. Because normally people won't use that large amount of data in the volume, and we store the volumes as sparse files.

`StorageMinimalAvailablePercentage` defines when a disk cannot be scheduled with more volumes. The default value is `10` (%). The bigger value between `MaximumStorage * StorageMinimalAvailablePercentage / 100` and `MaximumStorage - ReservedStorage` will be used to determine if a disk is running low and cannot be scheduled with more volumes.

Notice currently there is no guarantee that the space volumes used won't exceed the `StorageMinimalAvailablePercentage`, because:
1. Longhorn volume can be bigger than specified size, due to the snapshot contains the old state of the volume
2. And Longhorn is doing over-provisioning by default.
