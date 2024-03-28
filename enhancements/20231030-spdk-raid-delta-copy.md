# Implement a logical volume delta copy in RAID bdev module

## Summary

To implement different replicas of a Longhorn volume, inside SPDK we use a RAID1 bdev made of logical volumes stored in different nodes.
Actually, with shallow copy and set parent operations, we can perform a full rebuild of a logical volume. But we need another
rebuild functionality, called delta copy, that will be used to copy only a subset of the data that a logical volume is
made of. For example, we will use delta copy in case of temporary network disconnections or node restart, issues that can
lead to data loss in a replica of a Longhorn volume.

## Motivation

### Goals

Perform a fast rebuild of replicas that aren't full aligned with other replicas of the same volume.

## Proposal

The basic idea of delta copy is to maintain in memory, for the time a replica is unavailable, a bitmap of the data blocks over which a write operation has been performed. This bitmap will be used to realign this faulty
replica when it will become available again.

Actually inside SPDK, when a base bdev of a RAID1 becomes unavailable, we have the following process:
* base_bdev_N becomes unavailable.
* NVMe-oF tries to reconnect to the source of base_bdev_N.
* during the reconnection time, write operations over the block device connected via NVMe-oF to the RAID1 bdev remains stuck.
* after a configurable time, base_bdev_N is deleted by NVMe-oF layer.
* the deletion event arrives to the RAID1 which remove base_bdev_N as base bdev.
* write operations over the block device restart without error.

The proposal is:
* when the deletion event arrives to the RAID1, base_bdev_N should only be deconfigured from the RAID and not removed.
* when a base_bdev is deconfigured, I/O over it will be skipped but the write operations will update a bitmap containing all the data blocks over which a write operation has been performed.
* if the replica node from which base_bdev_N originate doesn't become available again within a certain amount of time, base_bdev_N is definitely removed from the RAID1 and its
  bitmap deleted. When the replica node will become available again, the replica volume will need a full rebuild.
* if the replica node from which base_bdev_N originate becomes available within a certain amount of time, we have the 2 options described below.

Whatever is the option we will implement, the important thing is that the new bdev that will be created must have the same name of the old base_bdev_N. In this way, when the 
creation event arrives to the RAID layer, it can reconfigure this base bdev and add it again to the RAID1.

### Option 1

Perform a rebuild in the same way the full rebuild operate:
* pause I/O.
* flush I/O.
* make a snapshot of the volume over all available replicas.
* retrieve from the RAID1, with a new RPC, the bitmap of base_bdev_N.
* create a clone of an external snapshot that is one of the healthy replica. The name of this clone must be the same as base_bdev_N.
* resume I/O.
* export via NVMe-oF the upper snapshot of an healthy replica, that is the volume which contain the missing data of the faulty one.
* export via NVMe-oF the upper volume of the faulty replica, that is the volume over which we were writing before the down of the replica.
* perform the copy between these 2 exported volumes of the data blocks contained in the bitmap.
* pause I/O.
* set the upper volume of the faulty replica, that now has all missing data, as the parent of the esnap clone that is a base bdev in the RAID1.
* resume I/O.

Advantages:
* this solution is very similar to the full rebuild, the only difference is that we write directly over the block device connected to the volume via NVMe-oF instead of calling
  shallow copy.
* this solution is quite similar to the delta copy with v1 engine.

Disadvantages:
* we need to implement a new RPC to retrieve the bitmap.
* the "driver" of the process is outside SPDK, so it has to export volumes, get bitmap, read and write blocks, align the snapshot chain ...

### Option 2

Make leverage on the RAID rebuild feature actually being reviewed in SPDK Gerrit (https://review.spdk.io/gerrit/c/spdk/spdk/+/18740/13): when a new base bdev is added to a RAID1, a rebuild process to copy all the data over the new base bdev starts automatically. We could modify this behaviour, making sure that when a faulty base bdev is available again and reconfigured inside the RAID, a rebuild process of only the blocks inside the bitmap would start.

Advantages:
* the rebuild is made entirely in RAID module, without any operation made outside SPDK. The only task to be made outside is to connect again to the replica, giving to the newly
  created bdev the same name of base_bdev_N.
* we don't need to make any snapshot over all the replicas before to start rebuilding, because the rebuild process works directly over the live data.

Disadvantages:
* during the rebuild process, the user can't make snapshots over the volume. This is because RAID, as we said before, has no knowledge of what its base bdevs are made of, so with logical volumes the RAID layer can works only over live data.
* to work over live data, the rebuild process must quiesce the ranges over which it has to operate, that in our case are the data blocks contained in the bitmap. This means that, during the
  rebuild, if the user writes data over these blocks, the writes operation can remain stuck until the rebuild of that block has finished.



## Note

I think the first option is better, because it is more similar to the full rebuild and to what Longhorn actually does with v1 engine. Moreover, it hasn't the limitation
of snapshotting not available during the rebuild, even if this process should be quite fast. Last but not least, we should rely on code still under review: in this case, unlike RAID1 read balancing feature (that we use despite it is still under review, but it is quite simple), the code is quite complex and so it could be more risky to use it directly before it will be merged in upstream main branch.
