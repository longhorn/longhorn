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

In SPDK, we create a longhorn volume composing different logical volumes, which are the replicas, into a raid1 bdev. The raid1 bdev has the size equal to the minimum size of its base bdevs, so the raid1 can be composed also by base bdevs with different size. If a base bdev is resized, the raid size is increased when this minimum size increases, and so only when all its base bdevs has been correctly resized. When longhorn need to expand a volume, it makes a resize request over all logical volumes that are the replicas of the same longhorn volume.

Inside longhorn we use thinly provisioned logical volumes, i.e. logical volumes that will allocate new space only when it is needed. Therefore, the resize operation of such a volume is simply a realloc of the array that contains all the LBA allocated to the volume, and so the time to perform the operation is not affected by the size of the expand operation, which is a blocking call.

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

Basically, when the engine receive a volume expand request, first of all it routes the request to all available replicas of the volume. If one replica is not able to perform the expansion, the operation stop and come back to the caller with an error. The replica that have already been expanded don't need to be reverted, because thinly replicas don't reserve space, and the volume will appear with the new size only when all replicas are correctly expanded. If a further expand request will be done, these replicas that have already been expanded will simply reply success without doing anything. Using thinly replicas, we don't need any preliminary check to see if the volume can be expanded.

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
- Try to resize the PVC with a bigger size and get an error over one replica (how do we simulate this?)
- Resolve the problem that cause the error above
- Retry to resize
- If successful, check that the PVC has the new increased size
