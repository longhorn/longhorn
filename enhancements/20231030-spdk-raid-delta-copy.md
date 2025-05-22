# Implement a logical volume delta copy in RAID bdev module

## Summary

To implement different replicas of a Longhorn volume, inside SPDK we use a RAID1 bdev made of logical volumes stored in different nodes.
Actually, with shallow copy and set parent operations, we can perform a full rebuild of a logical volume. But we need another
rebuild functionality, called delta copy, that will be used to copy only a subset of the data that a logical volume is
made of. For example, we will use delta copy in case of temporary network disconnections or node restart, issues that can
lead to data loss in a replica of a Longhorn volume.
We must also deal with the failure of the node where the RAID1 bdev reside, ensuring data consistency between different replicas.

## Motivation

### Goals

Perform a fast rebuild of replicas that aren't full aligned with other replicas of the same volume and ensure data consistency
in every type of node failure.

## Proposal for delta copy

The basic idea of delta copy is to maintain in memory, for the time a replica is unavailable, a bitmap of the "regions" over which a write operation has been performed. We will talk about the dimension of this regions later, keep in mind that a region could be a cluster (typically 4Mb) or a wider region of the Gb order.

Actually inside SPDK, when a base bdev of a RAID1 becomes unavailable, we have the following process:
* base_bdev_N becomes unavailable.
* NVMe-oF tries to reconnect to the source of base_bdev_N.
* during the reconnection time, write operations over the block device connected via NVMe-oF to the RAID1 bdev remains stuck.
* after a configurable time, base_bdev_N is deleted by NVMe-oF layer.
* the deletion event arrives to the RAID1 which remove base_bdev_N as base bdev.
* write operations over the block device restart without error.

The proposal is:
* when the deletion event arrives to the RAID1, the base_bdev_N is removed from the RAID and enter in a new state called faulty state.
  At this point a new bitmap for this base bdev is created inside the RAID.
* every write operation will update all the regions of the bitmap where the write operation has been performed.
* if the replica node from which base_bdev_N originate doesn't become available again within a certain amount of time, base_bdev_N's
  bitmap is deleted. When the replica node will become available again, the replica volume will need a full rebuild.
* if the replica node from which base_bdev_N originate becomes available within a certain amount of time, we can use the following
  procedure to perform a fast rebuild.

### Fast rebuild with delta bitmap

We can perform a rebuild in a similar way the full rebuild operate.  
Suppose we have 3 nodes, node1 with lvol1, node2 with lvol2 and node0 with the raid bdev; the raid is composed by the bdev created attaching to the NVMe-oF exported lvol1 and lvol2. We will call these 2 base bdevs replica1n1 and replica2n1.
Node1 goes offline for a while and then come back online again:
* pause I/O.
* stop the updating of the delta bitmap with the new RPC `bdev_raid_stop_base_bdev_delta_bitmap`
* retrieve from the RAID1, with the new RPC `bdev_raid_get_base_bdev_delta_bitmap`, the bitmap of replica1n1
* perform a snapshot of lvol2 called snap2
* export via NVMe-oF snap2 and attach to it on node1, creating the bdev esnap2n1
* on node1 create a clone of esnap2n1 called lvol1_new
* export lvol1_new via NVMe-oF and attach to it on node0 creating the bdev replica1n1
* clear the faulty state of replica1n1 inside the raid with the new API `bdev_raid_clear_base_bdev_faulty_state` (if the faulty state
  timeout is already expired, this operation is performed automatically inside SPDK)
* grow the raid adding replica1n1 as base bdev
* resume I/O.
* on node0 (but we can make this operation on every node) we connect to lvol1 and to snap2 with `nvme connect`
* copy over lvol1 all the clusters contained in the bitmap, reading the data from snap2
* make a snapshot of lvol1, snap1
* delete lvol1
* pause I/O
* rename lvol1_new to lvol1
* set snap1 as parent of lvol1
* resume I/O

Special case: if during the offline period one or more snapshots are made over the volume, we can stop to update the bimap after the creation of the first snapshot with the API `bdev_raid_stop_base_bdev_delta_bitmap`. When the replica comes back again, the bitmap will be used, as above, to update lvol1. For all the following snapshots that have been made, we can perform a copy of all data: to know what clusters the source snapshot contains, i.e. what clusters to copy, we can retrieve the fragmap of such a snapshot.

The usage of delta bitmap must be enabled when creating the raid with the new option `-d` of the RPC `bdev_raid_create`, by default it is disabled because in some environments the increased usage of memory to handle the bitmap could be an issue.

## Proposal for data consistency handling

We must also deal with the crash/power off/reboot of the node where the RAID1 resides. The point is: before to create again the raid, we must ensure that all the replicas have the same data, so we must elect an healthy replica and align all others to this one.

We have two main scenarios:
* when RAID node goes offline, not all the replica were online or fully aligned
* when RAID node goes offline, all the replica were online and fully aligned

What about the first scenario, the solution is to use the RAID superblock. In this way, when a replica goes offline, it is removed from the RAID and this change is stored in the superblock. So, when the RAID node come back online again and the RAID is recreated from the 
superblock, that replica is not part of the RAID even if it is online again.

So, how can we elect an healthy replica between the ones that are part of the RAID? We can have different solutions.

### Revision Counter
In Longhorn v1 engine we have a revision counter, which means the counter of block write operations received by a replica. The replica with
the greater revision counter contain newer data and so can be elected as the healthy replica.
But this operations is too costly, because it means an additional write for every write operation. Moreover, the write of the data and the update of the revision counter aren't atomic, so an inconsistency can still happen.

### Write to one replica first
We could achieve the same result of the revision counter always writing to one replica first, then the others (once the first replica has ended). This will have the same latency as adding an extra metadata write (the revision counter), but you don't need any metadata.

### Pick up anyone
If we don't use neither the revision counter nor the write to one replica first, which healthy replica should we use? We can pick up anyone. Since neither Longhorn nor users should expect that the in-fly IO data is already in any healthy replicas.

### Align the replicas
Once the healthy replica is chosen, it may contain a crashed filesystem. So we have to mount it and, after the fsck repair, the partially written data may get removed. Now we can do the sync-up for all other healthy replicas, rebuilding the entire live volume of the faulty replicas. To do this, we must retrieve the snapshot checksum for all the replicas, make a comparison and finally copy from the healthy replica in case the checksums differ.
A new API will be available to calculate the checksum of a previously created snapshot and to store it as an xattr. To enable the
addition of new xattrs to an existing snapshot, a new option will be available in the `bdev_lvol_snapshot` API.
The new option and the snapshot checksum will be available in lvol infos shown in `bdev_get_bdevs`.

### Boost the sync-up?
If we could persist the delta copy bitmap, for example in the raid superblock, then we could make this process faster: in this way we should rebuild only the regions not aligned with the healthy replica ones. But to do this, we will have to store the bitmap on disk for every write operations (possibly in atomic way), and this is too costly as we have seen for the revision counter.

There is an optimal solution to do this: storing some metadata in the LBA of the disk, for example a revision counter of every block. Doing so, it doesn't need an additional write, because the write of block data and metadata is done with an unique operation; it also makes the sync-up faster, because we should have to align only the blocks with a different revision counter.  
We can think to couple the storing of block metadata with the storing of the bitmap on disk, because in this case we could write the bitmap not for every write operations but for example every ms.  
The bad part is that not always we can have block metadata support:
* not every NVMe disks support metadata
* not every bdev inside SPDK support metadata, for example AIO bdev doesn't
* if we handle SATA disks with AIO bdev, we can't have metadata with this kind of drives

So this is an optimal solution but it is not always available.

## Bitmap regions
If we use the bitmap only in memory, then we can use the blob cluster as region to be tracked in the bitmap.
But if we decide to store the bitmap on the disk, and so to write the bitmap with every write operation (or every ms), probably we will have to track larger regions on it, regions of the Gb order. Because the bandwidth needed to write such a bitmap would be pretty large.

## Conclusions
What about the delta copy, I think the first option is better, because it is more similar to the full rebuild and to what Longhorn actually does with v1 engine. Moreover, it hasn't the limitation of snapshotting not available during the rebuild, even if this process should be quite fast.  
What about the data consistency, probably the best solution is to pick up any replica as the healthy one and then rebuild the entire live
volume of other replicas. Because other solutions haven't big advantages or aren't always available.

## Notes on the use of RAID superblock
* Using RAID superblock, when we export via NVMe-oF the different lvols to become replicas in the RAID bdev, we must assign to this replica a different UUID respect to the UUID of the original lvol. We can do this using the option `nguid` of the RPC `nvmf_subsystem_add_ns`.
The reason is the following: in the node where the the lvol reside, when the lvolstore is loaded, the superblock contained in the lvol
is read. If the superblock contains a base bdev with a valid UUID, the RAID is created also in this node. The creation of the RAID claims the lvol, so when we try to add this lvol as namespace to the NVMe-oF subsystem we get an error. The solution is to assign to the exported lvol a different UUID, which will not be found inside the local lvstore and so the RAID will not be created.
* When we create a RAID bdev, if we retrieve information about the base bdevs that compose the raid, we can get both base bdev
name and uuid. But RAID superblock store on disk only base bdev uuid, so if we stop SPDK tgt and then restart it, when
the RAID will be recreated, every base bdev will not have anymore its original name inside the RAID. The stored uuid will be used
to fill both the uuid and the name. So, to retrieve base bdev name, we have to execute a new RPC `bdev_get_bdevs -b <uuid>` the get the name.
