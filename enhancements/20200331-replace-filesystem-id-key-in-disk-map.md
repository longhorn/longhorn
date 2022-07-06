# Replace Filesystem ID key in Disk map

## Summary

This enhancement will remove the dependency of filesystem ID in the DiskStatus, because we found there is no guarantee that filesystem ID won't change after the node reboots for e.g. XFS.

### Related Issues

https://github.com/longhorn/longhorn/issues/972

## Motivation

### Goals

1. Previously Longhorn is using filesystem ID as keys to the map of disks on the node. But we found there is no guarantee that filesystem ID won't change after the node reboots for certain filesystems e.g. XFS.
1. We want to enable the ability to configure CRD directly, prepare for the CRD based API access in the future
1. We also need to make sure previously implemented safe guards are not impacted by this change:
    1. If a disk was accidentally unmounted on the node, we should detect that and stop replica from scheduling into it.
    1. We shouldn't allow user to add two disks pointed to the same filesystem

### Non-goals

For this enhancement, we will not proactively stop replica from starting if the disk it resides in is NotReady. Lack of `replicas` directory should stop replica from starting automatically.

## Proposal
We will generate UUID for each disk called `diskUUID` and store it as a file `longhorn-disk.cfg` in the filesystem on the disk.

If the filesystem already has the `diskUUID` stored, we will retrieve and verify the `diskUUID` and make sure it doesn't change when we scan the disks.

The disk name can be customized by user as well.

### Background
Filesystem ID was a good identifier for the disk:
1. Different filesystems on the same node will have different filesystem IDs.
1. It's built-in in the filesystem. Only need one command(`stat`) to retrieve it.

But there is another assumption we had which turned out not to be true. We assumed filesystem ID won't change during the lifecycle of the filesystem. But we found that some filesystem ID can change after a remount. It caused an issue on XFS.

Besides that, there is another problem we want to address: currently API server is forwarding the request of updateDisks to the node of the disks, since only that node has access to the filesystem so it can fill in the FilesystemID(`fsid`). As long as we're using the `fsid` as the key of the disk map, we cannot create new disks without let the node handling the request. This become an issue when we want to allow direct editing CRDs as API.

### User Experience In Detail

Before the enhancement, if the users add more disks to the node, API gateway will forward the request to the responsible node, which will validate the input on the fly for cases like two disks point to the same filesystem.

After the enhancement, when the users add more disks to the node, API gateway will only validate the basic input. The other error cases will be reflected in the disk's Condition field.

1. If different disks point to the same directory, then:
    1. If all the disks are added new, both disks will get condition `ready = false`, with the message indicating that they're pointing to the same filesystem.
    1. If one of the disks already exists, the other disks will get condition `ready = false`, with the message indicating that they're pointing to the same filesystem as one of the existing disks.
1. If there is more than one disk exists and pointing to the same filesystem. Longhorn will identify which disk is the valid one using `diskUUID` and set the condition of other disks to `ready = false`.

### API changes
1. API input for the diskUpdate call will be a map[string]DiskSpec instead of []DiskSpec.
1. API no longer validates duplicate filesystem ID.

### UI changes
UI can let the user customize the disk name. By default UI can generate name like `disk-<random>` for the disks.

## Design

### Implementation Overview

The validation of will be done in the node controller `syncDiskStatus`.

syncDiskStatus process:

1. Scan through the disks, and record disks in the FSID to disk map
1. Check for each FSID after the scanning is done.
    1. If there is only one disk in for a FSID
        1. If the disk already has `status.diskUUID`
            1. Check for file `longhorn-disk.cfg`
                 1. file exists: parse the value. If it doesn't match status.diskUUID, mark the disk as NotReady
                     1. case: mount the wrong disk.
                 1. file doesn't exist: mark the disk as NotReady
                     1. case: Reboot and forget to mount.
        1. If the disk has empty `status.diskUUID`
             1. check for file `longhorn-disk.cfg`.
                 1. if exists, parse uuid.
                     1. If there is no duplicate UUID in the disk list, then record the uuid
                     1. Otherwise mark as NotReady `duplicate UUID`.
                 1. if not exists, generate the uuid, record it in the file, then fill in `status.diskUUID`.
                     1. Creating new disk.
    1. If there are more than one disks with the same FSID
        1. if the disk has `status.diskUUID`
            1. follow 2.i.a
        1. If the disk doesn't have `status.diskUUID`
            1. mark as NotReady due to duplicate FSID.

#### Note on the disk naming
The default disks of the node will be called `default-disk-<fsid>`. That includes the default disks created using node labels/annotations.

### Test plan

Update existing test plan on node testing will be enough for the first step, since it's already covered the case for changing filesystem.

### Upgrade strategy

No change for previous disks since they all used the FSID which is at least unique on the node.
Node controller will fill `diskUUID` field and create `longhorn-disk.cfg` automatically on the disk once it processed it.
