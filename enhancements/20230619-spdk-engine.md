# SPDK Engine

## Summary
Longhorn will take advantage of SPDK to launch the second version engine with higher performance.

### Related Issues
https://github.com/longhorn/longhorn/issues/5406
https://github.com/longhorn/longhorn/issues/5282
https://github.com/longhorn/longhorn/issues/5751

## Motivation
### Goals
1. Have a set of APIs that talks with spdk_tgt to operate SPDK components.
2. Launch a control panel that manage and operate SPDK engines and replica.

## Proposal
1. The SPDK engine architecture is different from the legacy engine: 
   1. Unlike the legacy engine, the data flow will be taken over by SPDK. The new engine or replica won't directly touch the data handling. The new engine or replica is actually one or a set of SPDK components handled by spdk_tgt.
   2. Since the main task is to manage SPDK components and abstract them as Longhorn engines or replicas, we can use a single service rather than separate processes to launch and manage engine or replicas.
   3. As SPDK handles the disks by itself, the disk management logic should be moved to SPDK engine service as well. 
2. The abstraction of SPDK engine and replica:
   1. A data disk will be abstracted as an aio bdev + a lvstore. 
   2. Each snapshot or volume head file is a logical volume (lvol) inside a lvstore.
   3. A remote replica is finally exposed as a NVMe-oF subsystem, in which the corresponding SPDK lvol stand behind. While a local replica is just a lvol.
   4. An engine backend is actually a SPDK RAID1 bdev, which may consist of multiple attached replica NVMe-oF subsystems and local lvol.
   5. An engine frontend is typically a NVMe-oF initiator plus a NVMe-oF subsystem of the RAID bdev.
3. Do spdk_tgt initializations during instance manager startup.


### User Stories
#### Launch SPDK volumes
Before the enhancement, users need to launch a RAID1 bdev then expose it as a NVMe-oF initiator as the Longhorn SPDK engine manually by following [the doc](https://github.com/longhorn/longhorn-spdk-engine/wiki/How-to-setup-a-RAID1-block-device-with-SPDK). Besides, rebuilding replicas would be pretty complicated.

After the enhancement, users can directly launch and control Longhorn SPDK engine via the gRPC SPDK engine service. And the rebuilding can be triggered and handled automatically.

### API Changes
- The new gRPC SPDK engine service:
  - Replica:
    | API | Caller | Input | Output | Comments |
    | --- | --- | --- | --- | --- |
    | Create | Instance manager proxy | name, lvsName, lvsUUID string, specSize uint64, exposeRequired bool | err error | Create a new replica or start an existing one |
    | Delete | Instance manager proxy | name string, cleanupRequired bool | err error | Remove or stop an existing replica |
    | List   | Instance manager proxy |  | replicas map\[string\]Replica, err error | Get all abstracted replica info from the cache of the SPDK engine service |
    | Get    | Instance manager proxy |  | replica Replica, err error | Get the abstracted replica info from the cache of the SPDK engine service |
    | Watch  | Instance manager proxy |  | ReplicaStream, err error | Establish a streaming for the replica update notification |
    | SnapshotCreate | Instance manager proxy | name, snapshotName string | err error | |
    | SnapshotDelete | Instance manager proxy | name, snapshotName string | err error | |
    | Rebuilding APIs | The engine inside one gRPC SPDK engine service | | | This set of APIs is responsible for starting and finishing the rebuilding for source replica or destination replica. And it help start data transmission from src to dst |
  - Engine:
    | API | Caller | Input | Output | Comments |
    | --- | --- | --- | --- | --- |
    | Create | Instance manager proxy | name, lvsName, lvsUUID string, specSize uint64, exposeRequired bool | err error | Start a new engine and connect it with corresponding replicas |
    | Delete | Instance manager proxy | name string, cleanupRequired bool | err error | Stop an existing engine |
    | List   | Instance manager proxy |  | engines map\[string\]Engine, err error | Get the abstracted engine info from the cache of the SPDK engine service |
    | Get    | Instance manager proxy |  | engine Engine, err error | Get the abstracted engine info from the cache of the SPDK engine service |
    | Watch  | Instance manager proxy |  | EngineStream, err error | Establish a streaming for the engine update notification |
    | SnapshotCreate | Instance manager proxy | name, snapshotName string | err error | |
    | SnapshotDelete | Instance manager proxy | name, snapshotName string | err error | |
    | ReplicaAdd    | Instance manager proxy | engineName, replicaName, replicaAddress string | err error | Find a healthy RW replica as source replica then rebuild the destination replica. To rebuild a replica, the engine will call rebuilding start and finish APIs for both replicas and launch data transmission |
    | ReplicaDelete | Instance manager proxy | engineName, replicaName, replicaAddress string | err error | Remove a replica from the engine |
  - Disk:
    | API | Caller | Input | Output | Comments |
    | --- | --- | --- | --- | --- |
    | Create | Instance manager proxy | diskName, diskUUID, diskPath string, blockSize int64 | disk Disk, err error | Use the specified block device as blob store |
    | Delete | Instance manager proxy | diskName, diskUUID string | err error | Remove a store from spdk_tgt |
    | Get    | Instance manager proxy | diskName string | disk Disk, err error | Detect the store status and get the abstracted disk info from spdk_tgt |

## Design
### Implementation Overview
#### [Go SPDK Helper](https://github.com/longhorn/go-spdk-helper):
- The SPDK Target is exposed as a [JSON-RPC service](https://spdk.io/doc/jsonrpc.html). 
- Instead of using the existing sample python script [rpc_http_proxy](https://spdk.io/doc/jsonrpc_proxy.html), we will have a helper repo similar to [longhorn/go-iscsi-helper](https://github.com/longhorn/go-iscsi-helper) to talk with spdk_tgt over Unix domain socket `/var/tmp/spdk.sock`..
  - The SPDK target config and launching. Then live upgrade, and shutdown if necessary/possible.
  - The JSON RPC client that directly talks with spdk_tgt.
  - The exposed Golang SPDK component operating APIs. e.g., lvstore, lvol, RAID creation, deletion, and list.
  - The NVMe initiator handling Golang APIs (for the engine frontend).

#### [SPDK Engine](https://github.com/longhorn/go-spdk-helper):
- Launch a gRPC server as the control panel.
- Have a goroutine that periodically check and update engine/replica caches.
- Implement the engine/replica/disk APIs listed above.
- Notify upper layers about the engine/replica update via streaming.

#### Instance Manager:
- Start spdk_tgt on demand.
- Update the proxy service so that it forwards SPDK engine/replica requests to the gRPC service.

### Test Plan
#### Integration tests
1. Starting and stopping related tests: If Longhorn can start or stop one engine + multiple replicas correctly. 
2. Basic IO tests: If Data can be r/w correctly. And if data still exists after restart.
3. Basic snapshot tests: If snapshots can be created and keeps identical among all replicas. If a snapshot can be deleted from all replicas. If snapshot revert work.

#### Manual tests
1. SPDK volume creation/deletion/attachment/detachment tests.
2. Basic IO tests: If Data can be r/w correctly when volume is degraded or healthy. And if data still exists after restart.
3. Basic offline rebuilding tests.

### Upgrade strategy
This is an experimental engine. We do not need to consider the upgrade or compatibility issues now.
