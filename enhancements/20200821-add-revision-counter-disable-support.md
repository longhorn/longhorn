# Add Revision Counter Disable Support

## Summary

This enhancement adds revision counter disable support globally and individually per each volume with a logic based on latest modified time and total block counts of volume-head image file to select the most updated replica rather than the biggest revision counter for salvage recovering.

### Related Issues

https://github.com/longhorn/longhorn/issues/508

## Motivation

### Goals

1. By default 'DisableRevisionCounter' is 'false', but Longhorn provides an optional for user to disable it.
2. Once user set 'DisableRevisionCounter' to 'true' globally or individually, this will improve Longhorn data path performance.
3. And for 'DisableRevisionCounter' is 'true', Longhorn will keep the ability to find the most suitable replica to recover the volume when the engine is faulted(all the replicas are in 'ERR' state).
4. Also during Longhorn Engine starting, with head file information it's unlikely to find out out of synced replicas. So will skip the check.

## Proposal

Currently Longhorn Replica will update revision counter to the 'revision.counter' file on every write operation, this impacts the performance a lot. And the main purpose of this revision counter is to pick the most updated replica to recover the volume.

Also every time when Longhorn Engine starts, it will check all the replicas' revision counter to make sure the consistency.

Having an option to disable the revision counter with a new logic which selects the most updated replica based on the last modified time and the head file size of the replica, and removing the revision counter mechanism. These can improve the Longhorn performance and keep the salvage feature as the same.

Longhorn Engine will not check the synchronization of replicas during the starting time.

### User Stories

Some user has concern about Longhorn's performance. And with this 'DisableRevisionCounter' option, Longhorn's performance will be improved a lot.

#### TODO Will update the performance data here later.

### User Experience In Detail

In Longhorn UI 'Setting' 'General', by default 'DisableRevisionCounter' is 'false', user can set 'DisableRevisionCounter' to 'true'. This only impacts the UI setting.

Or from StorageClass yaml file, user can set 'parameters' 'revisionCounterDisabled' to true. And all the volume created based on this storageclass will have the same 'revisionCounterDisabled' setting.

User can also set 'DisableRevisionCounter' for each individual volumes created by Longhorn UI this individual setting will over write the global setting.

Once the volume has 'DisableRevisionCounter' to 'true', there won't be revision counter file. And the 'Automatic salvage' is 'true', when the engine is faulted, the engine will pick the most suitable replica as 'Source of Truth' to recover the volume.

### API changes

1. Add 'DisableRevisionCounter' global setting in Longhorn UI 'Setting' 'General'.
2. Add 'DisableRevisionCounter' individual setting in Longhorn UI 'Volume' 'Create Volume' for each volume.
3. For CSI driver, need to update volume creation API.
4. Add new parameter to 'ReplicaProcessCreate' to disable revision counter. And new parameter to 'EngineProcessCreate' to indicate the salvage requested mode for recovering.
5. Update Longhorn Engine Replica proto 'message Replica' struct with two new fields 'last_modified_time' and 'head_file_size' of the head file. This is for Longhorn Engine Control to get these information from Longhorn Engine Replica.

## Design

### Implementation Overview

This enhancement has two phases, the first phase is to enable the setting to disable revision counter. The second phase is the implement the new gRPC APIs with new logic for salvage.

And for the API compatibility issues, always check the 'EngineImage.Statue.cliAPIVersion' before making the call.

#### Disable Revision Counter

1. Add 'Volume.Spec.RevisionCounterDisabled', 'Replica.Spec.RevisionCounterDisabled' and 'Engine.Spec.RevisionCounterDisabled' to volume, replica and engine objects.
2. Once 'RevisionCounterDisabled' is 'true', volume controller will set 'Volume.Spec.RevisionCounterDisabled' to true, 'Replica.Spec.RevisionCounterDisabled' and 'Engine.Spec.RevisionCounterDisabled' will set to true. And during 'ReplicaProcessCreate' and 'EngineProcessCreate' , this will be passed to engine replica process and engine controller process to start a replica and controller without revision counter.
3. During 'ReplicaProcessCreate' and 'EngineProcessCreate', if 'Replica.Spec.RevisionCounterDisabled' or 'Engine.Spec.RevisionCounterDisabled' is true, it will pass extra parameter to engine replica to start replica without revision counter or to engine controller to start controller without revision counter support, otherwise keep it the same as current and engine replica will use the default value 'false' for this extra parameter. This is the same as the engine controller to set the 'salvageRequested' flag.
4. Add 'RevisionCounterDisabled' in 'ReplicaInfo', when engine controller start, it will get all replica information.
4. For engine controller starting cases:
- If revision counter is not disabled, stay with the current logic.
- If revision counter is disabled, engine will not check the synchronization of the replicas.
- If unexpected case (engine controller has revision counter disabled but any of the replica doesn't, or engine controller has revision counter enabled, but any of the replica doesn't), engine controller will log this as error and mark unmatched replicas to 'ERR'.

#### Add New Logic for Salvage

Once the revision counter has been disabled.

1. Add 'SalvageRequested' in 'InstanceSpec' and 'SalvageExecuted' in 'InstanceStatus' to indicate salvage recovering status. If all replicas are failed, 'Volume Controller' will set 'Spec.SalvageRequested' to 'true'.
2. In 'Engine Controller' will pass 'Spec.SalvageRequested' to 'EngineProcessCreate' to trigger engine controller to start with 'salvageRequested' is 'true' for the salvage logic.
3. The salvage logic gets details of replicas to get the most suitable replica for salvage.
- Based on 'volume-head-xxx.img' last modified time, to get the latest one and any one within 5 second can be put in the candidate replicas for now.
- Compare the head file size for all the candidate replicas, pick the one with the most block numbers as the 'Source of Truth'.
- Only mark one candidate replica to 'RW' mode, the rest of replicas would be marked as 'ERR' mode.
4. Once this is done, set 'SalvageExecuted' to 'true' to indicate the salvage is done and change 'SalvageRequested' back to false.

### Test plan

#### Disable revision counter option test case

Disable revision counter option should return error if only Longhorn Manager got upgraded, not Longhorn Engine.

This is when user trying to disable revision counter with new Longhorn Manager but the Longhorn Engine is still the over version which doesn't have this feature support. In this case, UI will shows error message to user.

#### Disable revision counter options

Revision counter can be disabled globally via UI by set 'Setting' 'General' 'DisableRevisionCounter' to 'true'.

It can be set locally per volume via UI by set 'Volume' 'Create Volume''DisableRevisionCounter' to true.

It can be set via 'StorageClass', and every PV created by this 'StorageClass' will inherited the same setting:
```yaml
    kind: StorageClass
    apiVersion: storage.k8s.io/v1
    metadata:
      name: best-effort-longhorn
    provisioner: driver.longhorn.io
    allowVolumeExpansion: true
    parameters:
      numberOfReplicas: "1"
      disableRevisionCounter: "true"
      staleReplicaTimeout: "2880" # 48 hours in minutes
      fromBackup: ""
```

#### Integration Test Plan
1. Disable the revision counter.
2. Create a volume with 3 replicas.
3. Attach the volume to a node, and start to write data to the volume.
4. Kill the engine process during the data writing.
5. Verify the volume still works fine.
6. Repeat the above test multiple times.

### Upgrade strategy

Deploy Longhorn image with v1.0.2 and upgrade Longhorn Manager, salvage function should still work. And then update Longhorn Engine, the revision counter disabled feature should be available.
