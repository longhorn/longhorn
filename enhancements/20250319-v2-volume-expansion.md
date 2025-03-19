# V2 Volume Expansion

## Summary

This enhancement enable the possibility to expand volume's size also for v2 engine.

### Related Issues

https://github.com/longhorn/longhorn/issues/8022

## Motivation

### Goals

User will be able to increase the size of a volume created with v2 engine, in the same way it is possible for v1 engine.

### Non-goals

Make an additional step in v2 feature parity with v1.

## Proposal

The work will involve 5 different Longhorn components:
- `longhorn-instance-manager`, where `V2DataEngineProxyOps` have to implement the `VolumeExpand` proxy operation
- `longhorn-spdk-engine`, where `Engine` and `Replica` have to implement the expand operation on both client and server side
- `types`, where new RPCs for the expand operation have to be created
- `go-spdk-helper`, where we have to change a json parameter's name, as requested by SPDK
- `SPDK`, where we have to make some changes to the NVMe controller, in order to let the logical volume resize event to be correctly handled by nvmf and nvme layers in SPDK.

What about `RWX` volumes, no change is needed because the `NFS` filesystem resize action is taken at upper level in `longhorn-manager`.

### API changes

In `go-spdk-helper`, the json's name of the `Size` parameter inside `BdevLvolResizeRequest` struct will be changed from `size` to `size_in_mib`.

In `types`, the new proto message `ExpandRequest` will be created and also the following APIs into the `SPDKService` service:
- `ReplicaVolumeExpand`
- `EngineVolumeExpand`

`ExpandRequest` contains the name and the (new) size of the volume, it is used as parameter in the new APIs `ReplicaVolumeExpand` and `EngineVolumeExpand`.

In `longhorn-spdk-engine`, the following new APIs will be created:
- `VolumeExpand` in the `Engine` struct
- `VolumeExpand` in the `Replica` struct

## Design

### Implementation Overview

Let's see in detail the implementations for `longhorn-spdk-engine` and `SPDK`, the other ones are quite trivial.

#### SPDK

In SPDK, we create a longhorn volume composing different logical volumes, which are the replicas, into a raid1 bdev. The raid1 bdev has the size equal to the minimum size of its base bdevs, so the raid1 can be composed also by base bdevs with different size. If a base bdev is resized, the raid size is increased when this minimum size increases, and so only when all its base bdevs has been correctly resized. When longhorn need to expand a volume, it makes a resize request over all logical volumes that are the replicas of the same longhorn volume. Blob layer, before to resize the blob, freeze I/O and resume it after having completed the operation.

Inside Longhorn we use thinly provisioned logical volumes, i.e. logical volumes that will allocate new space only when it is needed. The resize operation of such a volume is so a simpe `realloc` of the array that contains all the LBA allocated to the volume, and as consequences of this we have:
- lvol resize don't reserve any new space
- the time to perform the resize is not affected by the size of the expand operation

The RPC `bdev_lvol_resize` is a blocking call and the only one reason why it can fail is basically lack of memory; and if the SPDK process can't allocate new memory, its functionality is seriously compromised and so the process and maybe the entire node must be restarted.

Actually, when creating a raid1 bdev, as base bdevs we use nvme bdevs created attaching to logical volume exported via nvmf; this is true also for local logical volume, i.e. volumes that reside on the same tgt of the raid1. The simplest solution would has been to add directly the logical volume to the raid, but we have to do otherwise principally to support the live upgrade but also to threat all base bdevs in the same way.

Inside SPDK, the operations for the nvmf exported logical volume and for the attached nvme bdev are executed by the same poller; let's follow the flow when we resize a logical volume:
- the `bdev_lvol_resize` RPC is called by `go-spdk-helper`
- the RPC is received by SPDK and lvol/blob layers operate the resize
- a notification about the bdev block count change is raised
- nvmf layer handle the notification and send an event over nvmf to notify the attribute change in the namespace, waiting for the reply (the logical volume is added to the nvmf subsystem as a nvme namespace)
- nvme controller receive the event and start to process it, executing the operations needed to update the attributes of the changed namespace; only after having completed these operations it will send back a response to the event caller
- these operation send commands synchronously to the other side of the communication channel, but the nvmf layer is waiting for a response and so the resize operation get stuck

The solution is to handle all the operations needed to handle the namespace attribute change in the nvme controller asynchronously.
The 3 operations that actually are executed synchronously inside the function `nvme_ctrlr_process_async_event`, which handle the namespace attribute change event, are:
- update the namespace list, by the function `nvme_ctrlr_clear_changed_ns_log`
- identify active namespaces, by the function `nvme_ctrlr_identify_active_ns`
- update every active namespace, by the function `nvme_ctrlr_update_namespaces`

The development simply makes the execution of these operations asynchronous, i.e. one function is executed only after the previous one has completed. This completely solve the expand issue.

#### longhorn-spdk-engine

First of all, we must consider that a device mapper I/O suspend is not needed before to start with the expand operation. The reasons are:
- as mentioned above, SPDK blob layer freezes I/O before to proceed with the resize operation 
- the raid bdev will have the new size only after all base bdevs has this new size, and so the raid will accept I/O on the added space only at that time.

Using thinly replicas, we also don't need any preliminary check to see if the volume can be expanded.

Basically, when the engine receive a volume expand request, first of all it routes the request to all available replicas of the volume. In v1 engine, the expand operation is considered correctly executed if at least one replica is able to perform the expansion: replicas that return an error are marked as error and so they will be removed by the engine and later resynced with other healthy replicas. But in v2 engine this can't be done because, as mentioned above, raid1 is expanded only when all its base bdevs are correctly expanded. A temporary network interruption, or a memory outage, can make the replica expansion to fail but not to remove it from the raid, so in this case we can't threat the volume as expanded because we should have a different size between engine's size and raid1's size. Then for the v2 engine we must design a different flow: if one replica is not able to resize, the engine expansion stop, rollback all the replicas that have previously been expanded and come back to the caller with an error.

After having correctly expanded all replicas, the engine will perform a device mapper reload to update the volume information inside device mapper volume table.

### Test plan

#### Success case

- Create a storage class with v2 engine
- Create a PVC that references the created storage class
- Successfully resize the PVC with a bigger size
- Check the PVC has the new increased size

#### Failed case

- Create a storage class with v2 engine
- Create a PVC that references the created storage class
- Try to resize the PVC with a bigger size and get an error over one replica
	- If the error is due to a network issue, we can have 2 scenarios
		- the expand request isn't received from the replica due to e temporary network issue. In this case the replica is still part of the engine, so we can proceed with further step
		- the replica has gone offline during the expansion, so in this case we must wait for the replica to be removed from the engine
	- If the error is due to a memory outage in SPDK process, try to restart the SPDK process. If the node memory is still completely used, restart the node where the process run. In both cases, we must wait for the replica to be online again
- Retry to resize
- If successful, check that the PVC has the new increased size
