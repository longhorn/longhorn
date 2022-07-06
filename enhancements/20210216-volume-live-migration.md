# Volume live migration

## Summary

To enable Harvester to utilize Kubevirts live migration support, we need to allow for volume live migration,
so that a Kubevirt triggered migration will lead to a volume migration from the old node to the new node.

### Related Issues
- https://github.com/longhorn/longhorn/issues/2127
- https://github.com/rancher/harvester/issues/384
- https://github.com/longhorn/longhorn/issues/87

## Motivation

### Goals
- Support Harvester VM live migration

### Non-goals
- Using multiple engines for faster volume failover for other scenarios than live migration

## Proposal
We want to add volume migration support so that we can use the VM live migration support of Kubevirt via Harvester.
By limiting this feature to that specific use case we can use the csi drivers attach / detach flow to implement migration interactions.
To do this, we need to be able to start a second engine for a volume on a different node that uses matching replicas of the first engine.
We only support this for a volume while it is used with `volumeMode=BLOCK`, since we don't support concurrent writes and having kubernetes mount a filesystem even in read only
mode can potentially lead to a modification of the filesystem (metadata, access time, journal replay, etc).


### User Stories
Previously the only way to support live migration in Harvester was using a Longhorn RWX volume that meant dealing with NFS and it's problems, 
instead we want to add support for live migration for a traditional Longhorn volume this was previously implemented for the old RancherVM.
After this enhancement Longhorn will support a special `migratable` flag that allows for a Longhorn volume to be live migrated from one node to another.
The assumption here is that the initial consumer will never write again to the block device once the new consumer takes over.


### User Experience In Detail

#### Creating a migratable storage class
To test one needs to create a storage class with `migratable: "true"` set as a parameter.
Afterwards an RWX PVC is necessary since migratable volumes need to be able to be attached to multiple nodes.
```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: longhorn-migratable
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880" # 48 hours in minutes
  fromBackup: ""
  migratable: "true"
```

#### Testing Kubevirt VM live migration
We use CirOS as our test image for the live migration.
The login account is `cirros` and the password is `gocubsgo`.
To test with Harvester one can use the below example yamls as a quick start.

Deploy the below yaml so that Harvester will download the CirrOS image into the local Minio store.
NOTE: The CirrOS servers don't support the range request which Kubevirt importer uses, which is why we let harvester download the image first.
```yaml
apiVersion: harvester.cattle.io/v1alpha1
kind: VirtualMachineImage
metadata:
  name: image-jxpnq
  namespace: default
spec:
  displayName: cirros-0.4.0-x86_64-disk.img
  url: https://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
```

Afterwards deploy the `cirros-rwx-blk.yaml` to create a live migratable virtual machine.
```yaml
apiVersion: kubevirt.io/v1alpha3
kind: VirtualMachine
metadata:
  labels:
    harvester.cattle.io/creator: harvester
  name: cirros-rwx-blk
spec:
  dataVolumeTemplates:
  - apiVersion: cdi.kubevirt.io/v1alpha1
    kind: DataVolume
    metadata:
      annotations:
        cdi.kubevirt.io/storage.import.requiresScratch: "true"
      name: cirros-rwx-blk
    spec:
      pvc:
        accessModes:
        - ReadWriteMany
        resources:
          requests:
            storage: 8Gi
        storageClassName: longhorn-migratable
        volumeMode: Block 
      source:
        http:
          certConfigMap: importer-ca-none
          url: http://minio.harvester-system:9000/vm-images/image-jxpnq # locally downloaded cirros image
  running: true
  template:
    metadata:
      annotations:
        harvester.cattle.io/diskNames: '["cirros-rwx-blk"]'
        harvester.cattle.io/imageId: default/image-jxpnq
      labels:
        harvester.cattle.io/creator: harvester
        harvester.cattle.io/vmName: cirros-rwx-blk
    spec:
      domain:
        cpu:
          cores: 1
          sockets: 1
          threads: 1
        devices:
          disks:
          - disk:
              bus: virtio
            name: disk-0
          inputs: []
          interfaces:
          - masquerade: {}
            model: virtio
            name: default
        machine:
          type: q35
        resources:
          requests:
            memory: 128M
      hostname: cirros-rwx-blk
      networks:
      - name: default
        pod: {}
      volumes:
      - dataVolume:
          name: cirros-rwx-blk
        name: disk-0
```

Once the `cirros-rwx` virtual machine is up and running deploy the `cirros-rwx-migration.yaml` to initiate a virtual machine live migration.
```yaml
apiVersion: kubevirt.io/v1alpha3
kind: VirtualMachineInstanceMigration
metadata:
  name: cirros-rwx-blk
spec:
  vmiName: cirros-rwx-blk
```

### API changes
- volume detach call now expects a `detachInput { hostId: "" }` if `hostId==""` it will be treated as detach from all nodes same behavior as before.
- csi driver now calls volume attach/detach for all volume types: RWO, RWX (NFS), RWX (Migratable).
- the api volume-manager now determines, whether attach/detach is necessary and valid instead of the csi driver.

#### Attach changes
1. If a volume is already attached (to the requested node) we will return the current volume.
2. If a volume is mode RWO, 
   it will be attached to the requested node, 
   unless it's attached already to a different node.
3. If a volume is mode RWX (NFS), 
   it will only be attached when requested in maintenance mode.
   Since in other cases the volume is controlled by the share-manager.
4. If a volume is mode RWX (Migratable),
   will initially be attached to the requested node unless already attached,
   at which point a migration will be initiated to the new node.


#### Detach changes
1. If a volume is already detached (from all, from the requested node) we will return the current volume.
2. If a volume is mode RWO, 
   It will be detached from the requested node.
3. If a volume is mode RWX (NFS), 
   it will only be detached if it's currently attached in maintenance mode.
   Since in other cases the volume is controlled by the share-manager.
4. If a volume is mode RWX (Migratable)
   It will be detached from the requested node.
   if a migration is in progress then depending on the requested node to detach different migration actions will happen.
   A migration confirmation will be triggered if the detach request is for the first node.
   A migration rollback will be triggered if the detach request is for the second node.

## Design

### Implementation Overview

#### Volume migration flow
The live migration intention is triggered and evaluated via the attach/detach calls.
The expectation is that Kubernetes will bring up a new pod that requests attachment of the already attached volume.
This will initiate the migration start, after this there are two things that can happen. 
Either Kubernetes will terminate the new pod which is equivalent to a migration rollback, or
the old pod will be terminated which is equivalent to a migration complete operation.

1. Users launch a new VM with a new migratable Longhorn volume -> 
   A migratable volume is created then attached to node1. 
   Similar to regular attachment, Longhorn will set `v.spec.nodeID` to `node1` here.
2. Users launch the 2nd VM (pod) with the same Longhorn volume ->
    1. Kubernetes requests that the volume (already attached) be attached to node2. 
       Then Longhorn receives the attach call and set `v.spec.migrationNodeID` to `node2` with `v.spec.nodeID = node1`.
    2. Longhorn volume-controller brings up the new engine on node2, with inactive matching replicas (same as live engine upgrade)
    3. Longhorn CSI driver polls for the existence of the second engine on node2 before acknowledging attachment success.
3. Once the migration is started (running engines on both nodes), 
   the following detach decides whether migration is completed successfully, 
   or a migration rollback is desired:
    1. If succeeded: Kubevirt will remove the original pod on `node1`,
       this will lead to requesting detachment from node1, which will lead to longhorn setting 
       `v.spec.nodeID` to `node2` and unsetting `v.spec.migrationNodeID`
    2. If failed: Kubevirt will terminate the new pod on `node2`,
       this will lead to requesting detachment from node2, which will lead to longhorn keeping
       `v.spec.nodeID` to `node1` and unsetting `v.spec.migrationNodeID` 
4. Longhorn volume controller then cleans up the second engine and switches the active replicas to be the current engine ones.

In summary:
```
n1 | vm1 has the volume attached (v.spec.nodeID = n1)
n2 | vm2 requests attachment [migrationStart] -> (v.spec.migrationNodeID = n2) 
volume-controller brings up new engine on n2, with inactive matching replicas (same as live engine upgrade)
csi driver polls for existence of second engine on n2 before acknowledging attach

The following detach decides whether a migration is completed successfully, or a migration rollback is desired.
n1 | vm1 requests detach of n1 [migrationComplete] -> (v.spec.nodeID = n2, v.spec.migrationNodeID = "") 
n2 | vm2 requests detach of n2 [migrationRollback] -> (v.spec.NodeID = n1, v.spec.migrationNodeID = "")
The volume controller then cleans up the second engine and switches the active replicas to be the current engine ones.
```

### Test plan

#### E2E tests
- E2E test for migration successful
- E2E test for migration rollback

### Upgrade strategy
Requires using a storage class with `migratable: "true"` parameter for the harvester volumes 
as well as an RWX PVC to allow live migration in Kubernetes/Kubevirt.

