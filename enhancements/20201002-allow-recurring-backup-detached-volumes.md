# Title

Allow Recurring Backup Detached Volumes

## Summary

In the current Longhorn implementation, users cannot do recurring backup when volumes are detached.
This enhancement gives the users an option to do recurring backup even when volumes are detached.


### Related Issues

https://github.com/longhorn/longhorn/issues/1509

## Motivation

### Goals

1. Give the users an option to allow recurring backup to happen when the volume is detached.
1. Don't overwrite the old backups with new identical backups. 
   This happens when the volume is detached for a long time and has no new data.
1. Avoid conflict with the data locality feature if the automatically attach happens.

### Non-goals

1. The volume will not be available while the recurring backup process is happening.

## Proposal

Add new global boolean setting `Allow-Recurring-Backup-While-Volume-Detached`. When the users enable `Allow-Recurring-Backup-While-Volume-Detached`, allow recurring backup for detached volumes.

### User Stories

#### Story 1

Users use [OpenFaas framework](https://www.openfaas.com/). 
OpenFaaS (Functions as a Service) is a framework for building serverless functions with Docker and Kubernetes.
Users deploy serverless functions using Longhorn as persistent storage. 
Users also set up recurring backup for those Longhorn volumes.
OpenFaas has APIGateway that watches and manages request to serverless functions.
The nature of serverless functions is that the container that those functions run on are only created when APIGateway sees client requests to those functions.
When there is no demand (e.g there is no function calls because there is no users' request), OpenFaas will scale down the number of function replicas (similar to Pod concept in Kubernetes) to 0.
As the result, the Longhorn volumes are attached when the functions are called and detached when no one is calling the functions.
If the recurring backup can only apply to the attached volumes, there will be many miss backups.

#### Story 2

From the users' perspective, when they schedule a backup, they would expect that they can see the backup to be created automatically according to a certain schedule. 
The expectation is, the backup store should always have the latest data of the volume.

But in the case of a volume was changed then detached before the last backup was done, the expectation will not be met. 
Then if the volume is lost during the time that volume is detached, then we lost the changed part of data of volume since the last backup.

### User Experience In Detail

Users need to turn on the global setting `Allow-Recurring-Backup-While-Volume-Detached` to enable recurring backup for detached volumes.
Longhorn will automatically attaches volumes, disables volume's frontend, takes a snapshot, creates a backup, then detaches the volume.

During the time the volume was attached automatically, the volume is not ready for workload. 
Workload will have to wait until the recurring backup finish.

### API changes

There is no API change.
The new global setting `Allow-Recurring-Backup-While-Volume-Detached` will use the same `/v1/settings` API.

## Design

### Implementation Overview

1. Add new global boolean setting `Allow-Recurring-Backup-While-Volume-Detached`
1. In `volume-controller`, we don't suspend volume's recurring jobs when either of the following condition match:
   1. The volume is attached.
   1. The volume is detached but users `Allow-Recurring-Backup-While-Volume-Detached` is set to `true`.
  
   Other than that, we suspend volume's recurring jobs.
   
1. Modify the cronjob to do the following:
   1. Check to see if the volume is attached.
   1. If the volume is attached, we follow the same process as the current implementation.
   1. If the volume is detached, attach the volume to the node of the current Longhorn manager.
      Also, disable the volume's frontend in the attaching request.
      Disable the volume's frontend make sure that pod cannot use the volume during the recurring backup process.
      This is necessary so that we can safely detach the volume when finishing the backup. 
   1. Wait for the volume to be in attached state.
   1. Check the size of `VolumeHead`, if it is empty, skip the backup.
      We don't want to overwrite the old backups with new identical backups. 
      This happens when the volume is detached for a long time and has no new data.
   1. Detach the volume when finish backup.

### Test plan

#### Manual test

1. Set `Allow-Recurring-Backup-While-Volume-Detached` to `false`
1. Create a volume
1. Attach the volume, write some data to the volume
1. Detach the volume
1. Set the recurring backup for the volume on every minute
1. Wait for 2 minutes, verify that there is no new backup created

1. Set `Allow-Recurring-Backup-While-Volume-Detached` to `true`
1. Wait until the recurring job begins.
1. Verify that Longhorn automatically attaches the volume, and does backup, then detaches the volume.
1. On very subsequence minutes, verify that Longhorn automatically attaches the volume, but doesn't do backup, then detaches the volume.
   The reason that Longhorn does not do backup is there is no new data.
   
1. Delete the recurring backup
1. Create a PVC from the volume
1. Create a deployment of 1 pod using the PVC
1. Write 1GB data to the volume from the pod.
1. Scale down the deployment. The volume is detached.
1. Set the recurring backup for every 2 minutes.
1. Wait until the recurring backup starts, scale up the deployment to 1 pod.
1. Verify that pod cannot start until the recurring backup finishes.
1. On very subsequence 2 minutes, verify that Longhorn doesn't do backup.
   The reason that Longhorn does not do backup is there is no new data.

1. Delete the recurring job
1. Turn on data locality for the volume
1. Set the number of NumberOfReplicas to 1
1. Let say the volume is attaching to node-1. 
   Wait until there is a healthy replica on node-1 and there is no other replica.
1. Write 200MB data to the volume.
1. Detach the volume
1. Turn off data locality for the volume
1. Attach the volume to node-2
1. Detach the volume
1. Set the recurring backup for every 1 minutes.
1. Wait until the recurring backup starts.
   Verify that Longhorn automatically attaches the volume to node-2, does backup, then detaches the volume.
   However, Longhorn doesn't trigger the replica rebuild, and there is no new replica on node-2.
   
1. Set `Allow-Recurring-Backup-While-Volume-Detached` to `true`


### Upgrade strategy

This enhancement doesn't require an upgrade strategy.
