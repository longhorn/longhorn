# Secure Erase of Replica Data for V1 Data Engine

## Summary

Longhorn never overwrites v1 replica data when it lets go of it. Deleting a volume, a replica, or a snapshot unlinks files; trimming a filesystem punches holes. In both cases the old blocks go back to the free space of the node's filesystem with their content intact, and can be read back from the raw device until something else reuses them.

This proposal adds an optional data erase method for v1 volumes. When it is set, Longhorn overwrites replica data before releasing it, on the paths where a reachable replica releases data: replica deletion, snapshot purge, snapshot revert, and filesystem trim. Two methods are offered: a single pass of zeros, and a three-pass method (zeros, ones, random) for users whose audit checklist requires it.

The result is a NIST SP 800-88 Rev. 2 "Clear" on a best-effort basis. It is not a "Purge", and it is unrelated to device-level commands such as ATA Secure Erase or NVMe Sanitize.

### Related Issues

- https://github.com/longhorn/longhorn/issues/7699
- https://github.com/longhorn/longhorn/issues/7700 (test)
- https://github.com/longhorn/longhorn/issues/14621 (v2 data engine counterpart, out of scope here)
- https://github.com/longhorn/longhorn/issues/14626 (orphaned replica data, out of scope here)

## Motivation

Users who must follow a data sanitization policy need to show that volume data is not left readable on a node disk after it is removed. The request behind this feature came from an auditor asking for a three-round wipe (zeros, ones, random) of the files under the replica directory, with DoD and NIST named as the reference.

Two facts shape the design:

- The current standard does not ask for multiple passes. NIST SP 800-88 Rev. 2 (final 2025-09-26, supersedes Rev. 1) states that the "clear" method "was clarified such that multi-pass overwrite is not needed" and calls the DoD 5220.22-M pass-count language obsolete. It also notes that DoD removed overwriting specifications from NISPOM in 2006. A single pass is therefore the default here, and the three-pass method exists only for users bound to an older checklist.
- Data that has been released cannot be found again. Once a file is unlinked or a hole is punched, its blocks are no longer addressable through the file. Overwriting the remaining files at volume deletion does not reach blocks that an earlier snapshot deletion or trim already released. The overwrite therefore has to happen before each release, not once at the end.

### Terms

- **Replica image file**: a file in a replica's data directory that holds volume data: the volume head or a snapshot (`volume-head-*.img`, `volume-snap-*.img`).
- **Data release**: the event in which replica data blocks leave Longhorn's control and return to the free space of the node's storage: the last name of a replica image file is unlinked, the file is truncated, or a hole is punched in it.
- **Secure erase**: overwriting replica data before its data release.
- **Reachable replica**: a replica whose data directory can be accessed by the Longhorn components on its node, whether or not its replica process is running.
- **Unerased release**: a data release, or data left behind on a disk, of a volume whose erase method is not `disabled`, that happened without a completed overwrite.

### Goals

- Let a user choose a data erase method per volume, with a global default and a StorageClass parameter.
- When a method is set, overwrite the data before these data releases of a reachable v1 replica:
  - replica deletion, including volume deletion, eviction, and cleanup of failed replicas;
  - snapshot purge, including coalesce and prune;
  - snapshot revert (the discarded volume head);
  - filesystem trim.
- Never let secure erase block the release of space.
- Do not overwrite data that Longhorn knows to be in use, and never leave a replica image file that is reachable by name partly overwritten when a whole file is released.
- Bound the time secure erase adds to a trim request so that it does not, by itself, exceed the engine-replica timeout or the SCSI timeout of the volume's block device.
- Log every unerased release, and raise a Warning event when the manager learns that an operation left one.
- Record the erase method in the replica data directory so that a later feature can honor it for orphaned replica data.
- Keep the API data-engine neutral so that the v2 data engine can adopt it without an API change.

### Non-goals

- NIST SP 800-88 "Purge" or "Destroy". An in-place overwrite of a file on a host filesystem cannot guarantee that the original physical blocks are overwritten. See [Limitations](#limitations).
- The v2 data engine. Tracked in https://github.com/longhorn/longhorn/issues/14621.
- Orphaned replica data: neither overwriting it when the orphan is deleted nor recording that deletion as an unerased release. Tracked in https://github.com/longhorn/longhorn/issues/14626. This proposal only records the method on disk for it.
- Replicas that are not reachable when they are removed (node down, disk unavailable). Their data stays on the disk, as today.
- Data that a replica rebuild releases in a reused replica directory, and data that a backup restore or a clone releases internally. See [Limitations](#limitations).
- Data outside the replica data directory: backing image files, backing image manager temporary files, and backups in the backupstore.
- Detecting or blocking storage on which the overwrite is not effective.
- Read-back verification of the overwrite.
- Retroactively erasing blocks that were released before the method was set.

## Proposal

Add a data erase method with the values `disabled`, `zero`, and `three-pass`. It is resolved per volume from the volume's own field or, when the volume follows the global default, from a new global setting.

When the resolved method is not `disabled`, the data releases listed in the goals are preceded by an overwrite of exactly the data that is about to be released. The overwrite is done on the replica image files in the replica data directory, by the processes that already own those files. It is not done through the volume's block device: writes through the block device only reach the volume head, cannot touch snapshot files, would allocate new blocks, and are not possible once the volume is detached.

Secure erase is best-effort. If an overwrite cannot be done, fails, or runs out of its time budget, the release still proceeds and Longhorn records an unerased release.

### User Stories

#### Story 1: deleting a volume under a sanitization policy

An operator must show that data of a decommissioned application is not left on the node disks.

- **Before**: Deleting the volume unlinks the replica files. The operator has to log in to every node that held a replica and overwrite the files by hand before deleting the volume, and has no way to do this for snapshots that were deleted or blocks that were trimmed earlier.
- **After**: The volume is created from a StorageClass with `dataEraseMethod: "zero"`. Every snapshot deletion, trim, and finally the volume deletion overwrites the data before releasing it. The operator collects the Longhorn logs and events and checks them for unerased releases.

#### Story 2: an audit checklist that requires three passes

An auditor requires three rounds: zeros, ones, random.

- **Before**: Not possible within Longhorn.
- **After**: The operator sets `dataEraseMethod: "three-pass"` on the affected volumes. The documentation states that this adds no protection over a single pass on current media and costs three times the I/O.

#### Story 3: trimming a filesystem

A database volume has a large table dropped and the filesystem is trimmed.

- **Before**: The trimmed ranges are punched out of the volume head. The dropped table's blocks return to the node filesystem unchanged.
- **After**: With a method set, the replica overwrites the allocated blocks in the trimmed range and then punches the hole. Trim is slower.

### User Experience In Detail

#### Enabling

Global default, for volumes that do not choose a method themselves:

```yaml
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: data-erase-method
  namespace: longhorn-system
value: '{"v1":"zero"}'
```

Per StorageClass:

```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: longhorn-erase
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "3"
  dataEraseMethod: "zero"
```

Per volume, through the Longhorn UI or API (`updateDataEraseMethod`), or by editing `spec.dataEraseMethod` of the Volume. `ignored` means the volume follows the global setting.

The method can be changed at any time. A change applies only to data releases that happen after it. Replica deletion, snapshot purge, and revert use the method that is current when the operation is requested. Trim uses the method that the running engine has been told, which is shown in `Engine.status.dataEraseMethod`; after a change, or after the engine starts, a trim may still run without an overwrite until that field shows the method. To cover the whole life of a volume, set the method when the volume is created.

#### What the user observes

- Deleting a volume, or removing a replica, takes as long as overwriting the allocated data of that replica. The Replica resource stays in the deleting state and its disk space stays counted as used until the overwrite ends and the directory is removed. On one disk, replica directories are overwritten one at a time.
- Snapshot purge takes several times longer, because data is overwritten before it is released. Progress is reported through the existing purge status.
- Filesystem trim is slower. A trim request is acknowledged only after the overwrite and the hole punch, or after its time budget ran out.
- An unerased release is written to the log of the component that observed it. When the manager learns that an operation left unerased releases, it raises a Warning event. Examples: the replica's node was down when the replica was removed, the overwrite returned an I/O error, or a trim request ran out of its time budget.

#### Limitations

The documentation must state these clearly.

- Secure erase is a best-effort "Clear": it overwrites, through the filesystem, the blocks that the replica image file currently maps. It protects against reading released blocks back from the node disk with ordinary tools.
- It is not effective when the storage under the replica directory does not overwrite in place. In these cases the old content can survive the overwrite:
  - copy-on-write filesystems such as Btrfs and ZFS, and XFS files that share extents through reflink: an overwrite is written to new blocks and the old blocks are released unchanged;
  - ext4 mounted with `data=journal`: a copy of the data also lives in the journal;
  - thin-provisioned LVM with snapshots, or any snapshot taken below the filesystem;
  - flash storage: the flash translation layer may keep old content in blocks that are no longer mapped.
  Longhorn neither detects nor blocks these configurations.
- Users who need a "Purge" should use an encrypted volume and make its passphrase unrecoverable. The LUKS2 header with the wrapped volume key is stored inside the volume data, and therefore in every replica, snapshot, and backup; deleting the Kubernetes Secret alone does not remove those copies.
- The overwrite never blocks a release and can be skipped. The log is the complete record of unerased releases. A Warning event is a notification, not an archive: it is raised with a count, once per operation or, for trim, once each time the manager sees the count increase, and only when the manager learns of the unerased releases, and Kubernetes keeps events for a limited time (one hour by default). For an audit, collect the logs.
- Secure erase adds no locking of its own. Data that is being released is not expected to be read by anyone else, and Longhorn only checks, at the moment before an overwrite, whether it knows of a reader. Unlike an unlink, an overwrite changes what a reader sees, so a reader that the check does not see reads the overwrite pattern instead of the old content, without an error, and can carry it into a backup, a clone, or a rebuilt replica. The known cases are: an operation that starts after the check was made, such as an export or a rebuild that begins while a purge is already running; a rebuild on the same node, which reads another replica's files directly and is not visible to that replica; and an old replica process that is still running because it could not be stopped, for example while its instance manager is in an unknown state.
- Unerased releases are not stored anywhere but in the logs. The Warning event is raised from what the manager learns the next time it asks: a replica or engine process that ends before that, or a manager restart, means that the log entry is the only trace.
- A crash of a replica process, an instance manager, or a node while a removed file is being overwritten releases what was not yet overwritten. The log then shows the start of the overwrite without a result.
- Blocks released before the method was set are not covered.
- A replica that is unreachable when it is removed is not overwritten. Its data stays on the disk and later appears as orphaned replica data. Deleting that orphan neither overwrites it nor records anything until https://github.com/longhorn/longhorn/issues/14626 is implemented.
- A replica rebuild that reuses an existing replica directory releases stale data in that directory (files that the source replica does not have, and ranges that are holes in the source) without overwriting it. A backup restore removes and replaces files, and purges extra snapshots during an incremental restore, without overwriting them; the same holds for the revert at the end of a restore or a clone. None of this is recorded.
- Data outside the replica directory (backing images, backups) is not covered.
- Encrypted volumes are treated like any other volume. Note that trim does not reach an encrypted volume unless discards have been allowed on its dm-crypt mapping.
- The engine image of the volume must support secure erase. With an older engine image the method is ignored without an error and without a record for snapshot purge, revert, and trim. The documentation requires upgrading the engine image before relying on the feature.
- Data within a trimmed range that is held by a snapshot the user keeps is not released and therefore not overwritten. It is overwritten when that snapshot is removed and purged.

### API changes

#### Setting

`data-erase-method`: data-engine-specific, string, default `{"v1":"disabled"}`. Allowed values: `disabled`, `zero`, `three-pass`. Only the `v1` key exists; the v2 data engine adds its key in its own proposal.

#### CRD

- `Volume.spec.dataEraseMethod`: `ignored` (default), `disabled`, `zero`, `three-pass`.
- `Engine.spec.dataEraseMethod` and `Replica.spec.dataEraseMethod`: the resolved method (`disabled`, `zero`, `three-pass`), written by the volume controller.
- `Engine.status.dataEraseMethod`: the method that the running engine currently uses for trim. It is empty until the manager has set the method after an engine start.

A v2 volume gets `ignored` by default like a v1 volume. The admission webhook, and the CSI driver for a StorageClass parameter, accept only `ignored` or `disabled` for a v2 volume and reject other values with an explicit "not supported by the v2 data engine" error.

#### StorageClass parameter

`dataEraseMethod`: same values as the volume field.

#### Longhorn REST API

- Volume action `updateDataEraseMethod` with input `dataEraseMethod`.
- `dataEraseMethod` in the volume model and in the volume create input.

#### Instance manager disk service (`longhorn/types`, `imrpc`)

New RPCs for filesystem-type disks. The request identifies the directory by disk type, disk name, disk path, and replica data directory name.

- `DiskReplicaDataErase(..., method)`: starts a background job that removes the replica image files of one replica data directory, overwriting each after its last name is removed, and returns at once. The job does not remove the directory. Only one job runs per disk; while another directory of the same disk is being erased the call returns "busy" and the caller tries again later. Starting a job that is already running is a no-op.
- `DiskReplicaDataEraseStatus(...)`: returns state (`in-progress`, `complete`, `incomplete`), progress, bytes overwritten, and, for `incomplete`, how many files were not completely overwritten and why.

Block-type disks return `Unimplemented`. The instance manager disk service API version is increased.

#### Engine (`longhorn/types`, `longhorn/longhorn-engine`)

The method is handed to the component that releases the data at the time of the release. No engine, replica, or instance manager process gets a new start parameter.

- Snapshot purge and snapshot revert: the existing RPCs get a method parameter, which is passed down to each replica for that operation only. A purge or revert that is started without one, for example from the engine command line or from inside a restore or a clone, does not overwrite. The purge status and the revert reply report how many releases were not overwritten and the last reason.
- Trim is not requested by the manager; an unmap comes from the workload through the volume frontend. The engine therefore has to know the method while it runs: a new RPC sets it on a running engine, as `unmapMarkSnapChainRemoved` is set today but without a start flag. A newly started engine uses `disabled` and reports an empty method until the manager has set it, so the manager always sets it once after a start, also when the method is `disabled`. The engine reports the method it uses, a count of trim releases that were not overwritten, and the last reason.
- The unmap message from the engine controller to a replica gets a payload that says either "overwrite with this method, with this much time left" or "do not overwrite". An unmap without a payload keeps today's meaning. The reply tells the engine whether the overwrite completed and, if not, a reason code.
- New optional field `DataEraseMethod` in the replica's `volume.meta`, written by the replica when a running engine passes a newly set method on. A volume whose method is changed while it is detached has the old value there until it is attached again; the set after every engine start brings it up to date. Nothing in this proposal reads the field; it is there for the orphaned replica data follow-up.
- The engine CLI API version is increased; the manager passes the method and calls the new RPC only when the engine image reports the new version.

## Design

### Implementation Overview

#### Erase primitive (`longhorn/sparse-tools`)

One implementation is shared by every path.

- `EraseRange(file, offset, length, method, deadline)` overwrites the allocated extents of an open file within a range. `EraseFile(file, method)` covers the whole file.
- The file is opened with `O_DIRECT`. The allocated extents are listed with FIEMAP, which sparse-tools already uses with the sync flag, so delayed allocations have extents. Holes and unwritten (preallocated, never written) extents are skipped: they hold no volume data, and overwriting a hole would allocate new blocks and could fill the disk.
- The overwrite never writes outside the requested range. Offsets and lengths follow the alignment that direct I/O needs on the disk. If a part of the range that holds allocated data cannot be written with that alignment, it is left as it is and the overwrite is reported as incomplete.
- Each pass writes its pattern over the extents in chunks of at most 1 MiB and ends with `fdatasync`. `zero` is one pass of `0x00`. `three-pass` is `0x00`, then `0xFF`, then random data.
- The deadline is checked between chunks. It stops further writes; it cannot interrupt a write or a sync that the kernel is already executing.
- The primitive returns the number of bytes overwritten and whether it completed. It never releases anything itself.

Only replica image files are overwritten. Metadata files (`*.meta`, `volume.meta`, `revision.counter`, `*.checksum`) hold no volume data and are removed as today.

#### Keeping the overwrite away from data in use

An overwrite changes the content of an inode in place. Today a file can be unlinked while something else still has it open, and that reader finishes with the old content. With an overwrite it would read the pattern instead. Secure erase applies to data that Longhorn has already decided to release, which is not expected to be read by anyone else, so this proposal adds no locking mechanism. It relies on two rules and one check, none of which needs a new mechanism.

**The last-name rule.** Removing a file name is a data release only when it is the last name of the inode. The replica links one inode under two names in two places: when a snapshot is created, the head file is linked under the new snapshot name and the head name is removed afterwards; and when a purge replaces a snapshot with the merged file. An inode with more than one link is never overwritten.

**Remove the name first.** The paths that remove a replica image file as a data release in a running replica are: removing a leaf snapshot in a purge, removing the old child after a coalesce, and removing the old head in a revert. They follow the same sequence:

1. Open the file, or use the descriptor the replica already holds.
2. If the inode has more than one link, remove the name and stop. Nothing is released and nothing is overwritten.
3. Log the start.
4. Remove the name.
5. Overwrite through the open descriptor, log the result, and close the descriptor. The blocks are released when the last descriptor is closed.

Removing the name before overwriting means that nothing can open the file by name any more and that no failure, whether a write error or a crash, can leave a file in the replica's disk chain that is reachable by name but partly overwritten. The cost is that a crash during the overwrite releases the rest without overwriting it; the log then shows a start without a result.

Other paths that remove replica image files are not data releases covered by this proposal and are unchanged: removing the old head name after creating a snapshot (the inode lives on as the snapshot), rollback of a failed snapshot creation, and the removal of extra files when a rebuild prepares a reused directory.

**A check for known readers.** The engine already has some checks between operations: the purge task does not send a purge when its check before sending finds a replica rebuilding, a replica's sync agent refuses a second purge and refuses to start rebuilding itself while it is purging, which says nothing about the replicas it would copy from, and an unmap is dropped while a replica is rebuilding. These are checks made before an operation starts, not mutual exclusion across the volume: the engine does not keep a purge apart from a backup, and a rebuild can start on the volume while a purge is running. One check is added in the style of the existing ones. All operations that read a replica's snapshot files from within that replica run in its sync agent: backup, the source side of clone and export, the file sender of a rebuild over the network, and snapshot hashing. Before a purge, a revert, or a trim overwrites anything, the replica asks its sync agent whether any of these is in progress at that moment. This needs a count of active exports and file sends in the sync agent, which has none today. If one is in progress, or the question cannot be answered, the overwrite is skipped, the release proceeds as it does today, and an unerased release is recorded. The check looks at the state at that moment and does not prevent a reader from starting afterwards.

Replica directory deletion uses the same sequence as above for every replica image file. The replica process and its sync agent are stopped, so nothing in that replica reads the files, and the manager checks that no other Replica resource uses the directory, as described under [Replica deletion](#replica-deletion). The instance manager removes every name and overwrites each inode once, after its last name is gone, so that an overwritten file is never reachable by name here either. It does not remove the directory; the manager does that afterwards, as today.

#### Resolving and distributing the method (`longhorn/longhorn-manager`)

- The volume controller resolves the method from `Volume.spec.dataEraseMethod` and the global setting, and writes it to the specs of the volume's engines and replicas. Volumes that follow the global setting carry the follow-global label so that a setting change requeues only them.
- For a v2 volume the resolved method is always `disabled`.
- Replica deletion: the replica controller passes `Replica.spec.dataEraseMethod` to the instance manager with the erase request.
- Snapshot purge and revert: the manager passes the method with the request. For a purge, the instance manager's proxy hands it to each replica's sync agent, which runs the purge; for a revert it goes through the engine to each replica. It is used for that operation only. Every request for a purge from the manager passes it: snapshot deletion, the API and recurring jobs, and the purge around a rebuild. A purge or revert that Longhorn starts internally as part of a backup restore or a clone gets no method and does not overwrite.
- Trim: the engine monitor calls the set RPC when `Engine.spec.dataEraseMethod` differs from `Engine.status.dataEraseMethod`, which includes the time right after an engine has started. The engine puts the method into each unmap it sends to its replicas, so a replica needs no state of its own for trim.
- The engine passes a newly set method on to its replicas, which store it in `volume.meta`.
- For snapshot purge, revert, and trim, all of this is skipped for an engine image below the required CLI API version; nothing is reported in that case. Replica deletion does not depend on the engine image.

#### Replica deletion

Today the manager pod on the replica's node stops the replica process and removes the data directory itself. It does so when the Replica resource is the active one, or when no other Replica resource of the volume refers to the same directory. The first half of that condition lets the directory go while an inactive Replica resource, created for live engine upgrade or migration, still refers to it. That is not safe for an overwrite.

The new flow, when `Replica.spec.dataEraseMethod` is not `disabled`:

1. The replica controller stops the replica process, as today.
2. If another Replica resource of the volume refers to the same node, disk, and data directory, the controller neither erases nor removes the directory and releases the finalizer. The last Replica resource that refers to the directory erases and removes it. This is stricter than today's condition and applies only when a method is set.
3. Otherwise it calls `DiskReplicaDataErase` on the node's v1 instance manager. If the instance manager answers "busy" because another directory on the same disk is being erased, the controller keeps the finalizer and starts again from step 2 later, so the condition of step 2 is checked again right before the job starts.
4. When the job starts it first makes sure that the replica process of that directory has really exited, because a stop request returns before the process is gone. It then removes the replica image files by the sequence in [Keeping the overwrite away from data in use](#keeping-the-overwrite-away-from-data-in-use). It ends in `complete`, or in `incomplete` if any file was not completely overwritten.
5. The replica controller polls `DiskReplicaDataEraseStatus`. While the job is in progress the Replica resource keeps its finalizer. If the job is unknown, because the instance manager restarted, the controller starts again from step 2; the new job handles the files that still have names.
6. If the job ended in `incomplete`, the controller records an unerased release. It then removes the directory as today and releases the finalizer.
7. If the job cannot be run at all, the controller records an unerased release for the directory and continues with step 6. This covers a node without a running v1 instance manager and an instance manager that does not implement the RPC (an older version during an upgrade).

A directory removal that fails is handled as today: the error is returned and the finalizer stays until a later attempt succeeds.

Cleanup of a failed replica, including the leftovers of a failed rebuild, goes through the same flow because it deletes the Replica resource.

A replica whose node is down is handled as today: the manager that takes over cannot reach the directory, logs this, and releases the finalizer. With a method set it now also records an unerased release.

#### Snapshot purge (`longhorn/longhorn-engine`, `longhorn/sparse-tools`)

A removed snapshot's data is released in three ways.

- Remove (the snapshot is a leaf): the replica process removes the snapshot file by the sequence in [Keeping the overwrite away from data in use](#keeping-the-overwrite-away-from-data-in-use).
- Coalesce and replace (the snapshot has one child that is not the head): the sync agent copies the child's data into the snapshot file, as today; data of the removed snapshot that the child shadowed is overwritten in place by that copy. Before the replica process switches the child's name to the merged file, it makes sure it has a descriptor of the old child file: the one in its disk chain when the child is part of the chain, otherwise one it opens for this purpose. It logs the start, switches the name, as today, and reopens its disk chain on the merged file. Only after that does it overwrite the old child inode, which now has no name, and close it. The child is never overwritten while it can be read by name or through the disk chain.
- Prune (the snapshot is directly under the head): the sync agent punches the ranges of the snapshot that the head shadows. With a method set it runs `EraseRange` on each range before the punch, unless the check for known readers says otherwise. The volume does not read those ranges from the snapshot, because the head shadows them.

The overwrite runs inline in the existing purge flow, without segmenting and without an extra timeout. Purge progress reporting is unchanged.

#### Snapshot revert

Revert creates a new head and removes the old one. The replica process removes the old head by the sequence in [Keeping the overwrite away from data in use](#keeping-the-overwrite-away-from-data-in-use).

#### Filesystem trim

Three limits apply to an unmap today:

- the engine controller holds its lock for the whole unmap, which blocks all other I/O of the volume;
- the engine applies the engine-replica timeout (8 seconds by default, 30 at most) to an unmap as it does to reads and writes, and a replica that exceeds it is marked as failed;
- the block device of the volume has a SCSI command timeout of 60 seconds for the whole request.

One unmap message can cover close to 4 GiB, so an unbounded inline overwrite could exceed all three. When a method is set, the engine controller and the replica bound it as follows. Without a method the unmap path is unchanged.

1. Segments. The engine controller cuts the unmap at absolute offsets that are multiples of 16 MiB, sends the segments one after another, and releases its lock between segments so that other I/O can proceed. Because the cuts are at multiples of 16 MiB they are sector-aligned, so the replica's inward alignment applies only to the two ends of the original request, exactly as for an unsegmented unmap. The result returned to the frontend is the sum over the segments.
2. Segment budget. Each segment carries an overwrite request with the method and the time left for it: at most 4 seconds, half of the minimum engine-replica timeout, and never more than what is left of the request budget. The replica finds the files it is about to punch (the head, and the snapshots already marked as removed, exactly as today), runs `EraseRange` on each for the segment's range with that deadline, and then punches the hole. If the deadline passes, the replica does not overwrite further, punches the hole anyway, logs an unerased release, and says so in its reply.
3. Request budget. The whole unmap request has an overwrite budget of 30 seconds, half of the SCSI command timeout. It limits the time spent overwriting, not the duration of the request. When it is used up, the controller sends the rest of the request with the explicit "do not overwrite" payload; the replica punches it, and the engine logs one unerased release for the remaining range and counts it.

The budgets limit what secure erase adds. They do not make a slow disk fast: a write that the kernel has already accepted cannot be interrupted, so a disk that stalls a single 1 MiB write stalls the replica as it does for an ordinary write today.

The 16 MiB, 4 second, and 30 second values are estimates, not measurements. They assume a worst case of about 50 MB/s sequential write, at which three passes over 16 MiB take about one second. They are constants in the first version and are expected to be tuned from field reports, or turned into settings, if unerased releases caused by the budgets turn out to be common.

Not every trimmed byte is a data release:

- a range whose data is held by a snapshot that is kept is not released, so nothing is overwritten;
- the replica shrinks an unaligned request inward to its sector size, as today; the edges are not punched and not overwritten.

A snapshot marked as removed by `unmapMarkSnapChainRemoved` has only the trimmed ranges released at trim time. The rest of its data is released, and overwritten, when a purge removes it. This proposal does not change when that purge runs.

Existing behavior is kept: an unmap is dropped while a replica is rebuilding, and rejected during expansion.

#### Recording unerased releases

Every unerased release is written to the log of the component that observed it, with the operation, the replica, the file and range, and the reason. The log is the complete record. Nothing is stored on disk or in a custom resource for this purpose.

An overwrite is not expected to fail, so the event only has to tell the operator to look at the log. The manager raises one Warning event on the Volume, through the event recorder that Longhorn uses elsewhere, when it learns that an operation left unerased releases:

- Replica deletion: when the erase job ends in `incomplete`, when it could not be run, and when the replica's node or disk is unavailable. The event refers to the Replica when the Volume is already gone.
- Snapshot purge: when the purge status that the manager already polls reports unerased releases.
- Snapshot revert: when the reply reports unerased releases.
- Trim: when the count that the engine reports has increased since the manager last looked.

The event gives the operation, the number of unerased releases, and the last reason, and points to the log.

Nothing is recorded where no method is in effect: with an engine image that does not support secure erase, for which the method is ignored for snapshot purge, revert, and trim, and for a purge or revert that is started without a method.

Each overwrite also logs its start and its result with the method, the number of bytes overwritten, and the duration.

#### Failure handling summary

| Situation | Behavior |
| --- | --- |
| Overwrite returns an error (for example I/O error, no space) | Release proceeds; unerased release recorded |
| Trim segment or trim request exceeds its budget | Hole is punched; unerased release recorded |
| Replica's node or disk is unavailable at removal | Finalizer released as today; data stays; unerased release recorded |
| No running v1 instance manager on the node, or one without the erase RPC | Directory removed without overwrite; unerased release recorded |
| Instance manager restarts during a directory erase | The job is started again and handles the files that are left; the interrupted file has a start without a result in the log |
| Replica or engine process ends, or the manager restarts, before the manager has learned of an unerased release | No event; the log entry is the only trace |
| Replica process or node crashes during the overwrite of a removed file | The rest is released without overwrite; the log has a start without a result |
| Engine image does not support secure erase | Method ignored for purge, revert, and trim; nothing recorded |
| Replica directory is referred to by another Replica resource | No erase and no removal until the last one is deleted |
| A backup, export, rebuild file send, or snapshot hash is in progress on the replica during a purge, revert, or trim, or the sync agent cannot be asked | The overwrite is skipped; the release proceeds; unerased release recorded |
| The inode being removed has another name | The name is removed; nothing is overwritten |

### Test plan

#### Unit tests

- Erase primitive: only allocated extents are written; holes stay holes and the allocated size does not grow; each method leaves the expected pattern; a range erase does not touch bytes outside the range; a passed deadline stops the overwrite between chunks and reports it.
- Last-name rule: removing one of two names of an inode overwrites nothing and leaves the content readable through the other name.
- Reader check: with a backup, an export, a file send, or a snapshot hash in progress on the replica, or when the sync agent cannot be asked, the overwrite is skipped and recorded; otherwise it runs.
- Recording: one Warning event per operation that left unerased releases, with the count and the last reason; for trim, one event per increase that the manager sees.
- Method resolution: volume value, follow-global, v2 volume, engine image below the required version.
- Admission webhook and CSI parameter: allowed values; rejection for v2 volumes.
- Trim segmenting: for an unaligned request that crosses at least two cuts, the punched range is identical to that of the unsegmented request.

#### Engine integration tests

Run on a replica directory on a dedicated loop device, so that the raw device can be searched for a marker pattern after each operation. For each method:

- create a snapshot with a method set: the snapshot content is intact after the old head name is removed;
- remove a leaf snapshot, coalesce a snapshot, prune the snapshot under the head: the marker written to the released data is no longer on the device, and the volume and the kept snapshots read back unchanged;
- coalesce with a crash injected before the switch, after the switch, and during the overwrite, for a child inside and outside the replica's disk chain: after a restart the kept snapshots and the volume read back unchanged;
- a backup, an export, a rebuild file send, and a snapshot hash in progress on the replica while a snapshot is removed, coalesced, or pruned, or while a range is trimmed: no overwrite is added, the release behaves as it does today, and an unerased release is recorded;
- rebuild preparation that removes extra files in a reused directory: nothing is overwritten and nothing is recorded;
- revert: the marker written to the discarded head is no longer on the device;
- unmap: the marker in the trimmed range is no longer on the device; an unmap larger than one segment is split; data held by a kept snapshot is still readable from that snapshot;
- unmap budgets: with a slow overwrite injected, a segment that runs out of its budget is punched and recorded; a request that runs out of its budget punches the rest and records it; in both cases the replica stays read-write. A stalled write that is already submitted is a separate case and is expected to behave like a stalled ordinary write;
- injected overwrite error: the release proceeds, a log entry with the right operation, file, range, and reason is written, and the purge status, the revert reply, or the engine's trim count reports it;
- the method passed with a purge or a revert is used for that operation only; a method set for trim is used by the next unmap, is reported by the engine, and is back to `disabled` after an engine restart until it is set again; `volume.meta` holds the method after it was set.

#### Integration and end-to-end tests

- Volume deletion with each method: the marker written to the volume cannot be found on the disk of any replica node afterwards.
- Replica deletion and eviction with a method set.
- Snapshot delete and purge, snapshot revert, and filesystem trim with a method set, including the recurring `filesystem-trim` job.
- Changing the method on an attached volume takes effect without detaching, and `Engine.status.dataEraseMethod` follows.
- StorageClass parameter and global setting, including a volume that follows the global setting.
- Volume deletion while one replica node is down: the volume is deleted, a Warning event and a log entry name the replica that was not overwritten, and its directory later appears as orphaned replica data.
- Replica deletion while the instance manager on the node is not running, and with an instance manager that lacks the erase RPC: the directory is removed and an unerased release is recorded.
- Live engine upgrade and live migration with a method set: deleting the active Replica resource while an inactive one refers to the same directory neither erases nor removes the directory; the volume stays healthy; the directory is erased and removed with the last Replica resource.
- Instance manager restart in the middle of a directory erase: the job is started again, the remaining files are erased, the log has a start without a result for the interrupted file, and the directory is removed.
- An incremental backup restore that purges snapshots, and a purge started from the engine command line without a method: nothing is overwritten and nothing is recorded.
- Two replica deletions on one disk: the second waits; if a Replica resource that shares its directory appears while it waits, the directory is kept.
- Replica deletion when the replica process has not exited yet: the job waits for the process to exit before it changes anything.
- A trim right after the engine has started, before the manager has set the method: it runs without an overwrite, and `Engine.status.dataEraseMethod` shows that no method was in use.
- A volume on an engine image without secure erase support: operations succeed without errors.
- Regression: with the method `disabled`, deletion, purge, revert, and trim behave and perform as before.

### Upgrade strategy

- The setting defaults to `disabled` and existing volumes get `dataEraseMethod: ignored`, so nothing changes after an upgrade until a user sets a method.
- Snapshot purge, revert, and trim need an engine image with the new CLI API version. Until a volume's engine is upgraded, the method is ignored for those operations without an error and without a record. The documentation tells users to upgrade engine images before relying on the feature.
- Replica directory erase is done by the node's instance manager, not by the volume's engine, so it works for a volume on any engine image. It needs an instance manager with the new disk service API version. While a node still runs only an older instance manager, replica deletion on that node removes the directory without overwriting it and records an unerased release.
- `volume.meta` gains an optional field. An older engine ignores it when reading. If an older engine rewrites `volume.meta`, the field is dropped and is written again by the next engine that supports it.
- No data migration is needed.

## Note

- The decision that secure erase never blocks a data release was made to avoid a deadlock in which space cannot be reclaimed, for example on a full or failing disk. On a filesystem that overwrites in place an overwrite of allocated extents needs no new space, but on copy-on-write or thin-provisioned storage it can.
- Prior art: OpenStack Cinder offers `volume_clear` (`zero`) for thick LVM volumes only and removed its `shred` option in 2016. Its security documentation states that writing over a volume "does not ensure that the data will be actually erased on the physical disks, as the storage solution could be doing copy-on-write or other optimizations".
- The orphaned replica data follow-up (https://github.com/longhorn/longhorn/issues/14626) reads the method from `volume.meta` and falls back to the global setting when the record is missing.
- When the v2 data engine adds its key to `data-erase-method`, the upgrade has to add that key to the stored setting value of existing clusters.
