# Local Volume

## Summary
Longhorn can support local volume to provide better IO latencies and IOPS.

### Related Issues
https://github.com/longhorn/longhorn/issues/3957

## Motivation
### Goals
- Longhorn can support local volume (data locality=strict-local) for providing better IO latencies and IOPS.
- A local volume can only have one replica.
- A local volume supports the operations such as snapshot, backup and etc.

### Non-goals
- A local volume's data locality cannot be converted to other modes when volume is not detached.
- A local volume does not support multiple replicas in the first version. The local replication could be an improvement in the future.

## Proposal
1. Introduce a new type of volume type, a local volume with `strict-local` data locality.
   - Different than a volume with `best-effort` data locality, the engine and replica of a local volume have to be located on the same node.
2. Unix-domain socket are used instead of TCP between the replica process' data server and the engine.
3. A local volume supports the existing functionalities such as snapshotting, backup, restore, etc.

### User Stories
Longhorn is a highly available replica-based storage system. As the data path is designed for the replication, a volume with a single replica still suffers from high IO latency. In some cases, the distributed data workloads such as databases already have their own data replication, sharding, etc, so we should provide a volume type for these use cases while supporting existing volume functionalities like snapshotting, backup/restore, etc.

### User Experience In Detail
- The functionalities and behaviors of the volumes with `disabled` and `best-effort` data localities will not be changed.
- A volume with `strict-local` data locality
   - Only has one replica
   - The engine and replica have to be located on the same node
   - Cannot convert to `disabled` or `best-effort` data locality when the volume is not detached
   - Can convert to `disabled` or `best-effort` data locality when the volume is detached
   - Existing functionalities such as snapshotting, backup, restore, etc. are supported

### CLI Changes
- Add `--volume-name` in engine-binary `replica` command
   - The unix-domain-socket file will be `/var/lib/longhorn/unix-domain-socket/${volume name}.sock`
- Add `--data-server-protocol` in engine-binary `replica` command
   - Available options are `tcp` (default) and `unix` 
- Add `--data-server-protocol` in engine-binary `controller` command
   - Available options are `tcp` (default) and `unix` 

## Design
### Implementation Overview
#### CRDs
1. Add a new data locality `strict-local` in `volume.Spec.DataLocality`

#### Volume Creation and Attachment
- When creating and attaching a volume with `strict-local` data locality, the replica is scheduled on the node where the engine is located.
- Afterward, the replica process is created with the options `--volume-name ${volume name}` and `--data-server-protocol unix`.
- The data server in the replica process is created and listens on a unix-domain-socket file (`/var/lib/longhorn/unix-domain-socket/${volume name}.sock`).
- Then, the engine process of the volume is created with the option `--data-server-protocol unix`.
- The client in the engine process connects to the data server in the replica process via the unix-domain-socket file.

### Validating Webhook
- If a volume with `strict-local` data locality, the `numberOfReplicas` should be 1.
- If a local volume is attached, the conversion between `strict-local` and other data localities is not allowable.
- If a local volume is attached, the update of the replica count is not allowable.

### Test Plan
#### Integration tests
1. Successfully create a local volume with `numberOfReplicas=1` and `dataLocality=strict-local`.
2. Check the validating webhook can reject the following cases when the volume is created or attached
   - Create a local volume with `dataLocality=strict-local` but `numberOfReplicas>1`
   - Update a attached local volume's `numberOfReplicas` to a value greater than one
   - Update a attached local volume's `dataLocality` to `disabled` or `best-effort`
