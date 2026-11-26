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

- **Replica image file**: a file in a replica's data directory that holds volume data: the volume head or a snapshot (`volume-head-*.img`, `volume-snap-*.img`), or a temporary data file that a backup restore left behind (`volume-delta-*.img`, `*.img.snap_tmp`).
- **Data release**: the event in which replica data blocks leave Longhorn's control and return to the free space of the node's storage: the last name of a replica image file is unlinked, the file is truncated, or a hole is punched in it.
- **Whole-file release**: a data release that lets go of an entire replica image file: a snapshot file removed by a purge, the old volume head after a revert, or every file of a deleted replica.
- **Range release**: a data release that lets go of part of a replica image file that stays in use, by punching a hole in it: a filesystem trim, or the pruning of a snapshot.
- **Secure erase**: overwriting replica data before its data release.
- **Erase queue**: a directory on a node disk in which the replica image files of whole-file releases wait, under their own names, until they are overwritten and removed.
- **Reachable replica**: a replica whose data directory can be accessed by the Longhorn components on its node, whether or not its replica process is running.
- **Unerased release**: a data release, or data left behind on a disk, of a volume that has a data erase method, that happened without a completed overwrite.

### Goals

- Let a user choose a data erase method per volume, with a StorageClass parameter and a global default for new volumes.
- When a method is set, overwrite the data before these data releases of a reachable v1 replica:
  - replica deletion, including volume deletion, eviction, and cleanup of failed replicas;
  - snapshot purge, including coalesce and prune;
  - snapshot revert (the discarded volume head);
  - filesystem trim.
- Never let secure erase fail or hold up a volume operation, and never keep data on a disk because an overwrite failed.
- Never overwrite a replica image file that a replica still uses or that any process still has open.
- Do not lose a pending overwrite of a whole file when a replica process, an instance manager, or a node restarts.
- Bound the time secure erase adds to a trim request so that it does not, by itself, exceed the engine-replica timeout or the SCSI timeout of the volume's block device.
- Log every unerased release, raise a Warning event when the manager learns of one, and show what is still waiting to be overwritten.
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

Add a data erase method to the volume. It is empty (no overwrite, the default), `zero`, or `three-pass`. A new global setting gives the value that a new volume gets when nothing else is specified.

When a volume has a method, the data releases listed in the goals are preceded by an overwrite of exactly the data that is about to be released. The overwrite is done on the replica image files, below the volume's block device: writes through the block device only reach the volume head, cannot touch snapshot files, would allocate new blocks, and are not possible once the volume is detached.

The two kinds of data release are handled differently:

- A whole-file release does not overwrite inside the operation. The file is moved into an erase queue on the same disk, which is a rename, and the operation continues at once. The node's instance manager overwrites the queued files one after another and removes each when it is done. A queued file keeps a name until then, so the work survives a restart.
- A range release has to punch its hole during the operation, so the process that punches overwrites the range first, within a time budget.

Secure erase is best-effort. If an overwrite cannot be done, fails, or runs out of its time budget, the data is released anyway and Longhorn records an unerased release.

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

Global default, used when a volume is created without a method of its own:

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

Per volume, through the Longhorn UI or API (`updateDataEraseMethod`), or by editing `spec.dataEraseMethod` of the Volume. An empty value means no overwrite.

The global setting is only a default for new volumes: it is copied into a volume that is created through CSI from a StorageClass without the parameter, or through the Longhorn API without the field. Changing the setting later does not change existing volumes. A StorageClass that has to switch secure erase off while the global default is set carries `dataEraseMethod: ""`.

The method of a volume can be changed at any time. A change applies only to data releases that happen after it. Replica deletion, snapshot purge, and revert use the method that is current when the operation is requested. Trim uses the method that the running engine has been told, which is shown in `Engine.status.dataEraseMethod`; after a change, or after the engine starts, a trim may still run without an overwrite until that field shows the method. To cover the whole life of a volume, set the method when the volume is created.

#### What the user observes

- Deleting a volume or a replica, purging snapshots, and reverting to a snapshot take as long as they do without a method. The replica image files they let go of are moved into the erase queue of the disk and are overwritten afterwards.
- The disk space of queued files stays in use until they have been overwritten, so space is returned later than the operation reports. `InstanceManager.status.eraseQueue` shows, per replica, how many files are waiting and how many bytes they hold in total. While it overwrites, the instance manager logs its progress, the write rate, and an estimate of the time left once a minute.
- A queued file that is still open, for example by a backup that started before a purge, waits until it is closed and is overwritten then.
- Filesystem trim is slower. A trim request is acknowledged only after the overwrite and the hole punch, or after its time budget ran out. Other I/O of the volume waits for at most one 16 MiB segment of a trim.
- An unerased release is written to the log of the component that observed it. When the manager learns of one, it raises a Warning event. Examples: the replica's node was down when the replica was removed, the overwrite returned an I/O error, or a trim request ran out of its time budget.

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
- The overwrite never blocks a release and can be skipped. The log is the complete record of unerased releases. A Warning event is a notification, not an archive: it is raised only when the manager learns of the unerased releases, and Kubernetes keeps events for a limited time (one hour by default). For an audit, collect the logs.
- A queued file is overwritten only after it has been closed by every process. A process that keeps a queued file open, for example a replica process that could not be stopped, keeps that file, and its space, in the erase queue. The queue status names such files.
- A slow or failing disk delays the overwrite of its queued files for as long as it takes; there is no time limit. An overwrite that returns an error is not retried: the file is removed and an unerased release is recorded.
- Files in the erase queue are processed by the instance manager that the manager assigns. Deleting a replica, a volume, or an instance manager, and removing a disk from Longhorn, do not wait for the queue. Before removing a disk from Longhorn, check `InstanceManager.status.eraseQueue`; files that are left in the `erase` directory of a disk have to be overwritten and removed by hand. A Longhorn downgrade leaves queued files that nothing processes.
- A range release (trim, prune) is overwritten in place while the file stays in use, so it has no such protection: Longhorn only checks, at the moment before the overwrite, whether it knows of a backup, export, rebuild file send, or snapshot hash on that replica, and skips the overwrite if so. A reader that the check does not see, such as an operation that starts after the check, reads the overwrite pattern instead of the old content, without an error. For a prune, the volume does not read the pruned ranges; for a trim, the filesystem has given the ranges up.
- After the first failed overwrite of a purge on a replica, or of a trim request, the rest of that operation is released without an overwrite and recorded.
- Unerased releases are not stored anywhere but in the logs, apart from the short-lived failure list of the erase queue. The Warning event is raised from what the manager learns the next time it asks: a replica or engine process that ends before that, or a manager that stops between reading a failure and raising the event, means that the log entry is the only trace.
- A crash of a replica process or a node during the overwrite of a range releases what was not yet overwritten. The log then shows the start of the overwrite without a result. A whole-file release is not affected: the queued file is overwritten again from the start.
- The trim budgets apply to each unmap that reaches the engine. Linux sends one block descriptor per SCSI UNMAP command, so one command is one unmap. An initiator that sends several descriptors in one command, which is only possible with the `iscsi` frontend and an external initiator, gets a budget for each and can exceed the 60-second SCSI command timeout.
- Blocks released before the method was set are not covered.
- A replica that is unreachable when it is removed is not overwritten. Its data stays on the disk and later appears as orphaned replica data. Deleting that orphan neither overwrites it nor records anything until https://github.com/longhorn/longhorn/issues/14626 is implemented.
- A replica rebuild that reuses an existing replica directory releases stale data in that directory (files that the source replica does not have, and ranges that are holes in the source) without overwriting it. A backup restore removes and replaces files, and purges extra snapshots during an incremental restore, without overwriting them; the same holds for the revert at the end of a restore or a clone. None of this is recorded.
- Data outside the replica directory (backing images, backups) is not covered.
- Encrypted volumes are treated like any other volume. Note that trim does not reach an encrypted volume unless discards have been allowed on its dm-crypt mapping.
- The engine image of the volume and the instance manager of the engine must support secure erase. With an older engine image or instance manager the method is ignored without an error and without a record for snapshot purge, revert, and trim. The documentation requires upgrading both before relying on the feature. Replica deletion does not depend on them.
- Data within a trimmed range that is held by a snapshot the user keeps is not released and therefore not overwritten. It is overwritten when that snapshot is removed and purged.

### API changes

#### Setting

`data-erase-method`: data-engine-specific, string, default `{"v1":""}`. Allowed values: empty (no overwrite), `zero`, `three-pass`. Only the `v1` key exists; the v2 data engine adds its key in its own proposal. The setting is the method that a new v1 volume gets when it is created without one. It is not consulted for existing volumes. The Helm chart exposes it as `defaultSettings.dataEraseMethod`.

#### CRD

- `Volume.spec.dataEraseMethod`: empty (default, no overwrite), `zero`, `three-pass`.
- `Engine.spec.dataEraseMethod` and `Replica.spec.dataEraseMethod`: the volume's method, written by the volume controller.
- `Engine.status.dataEraseMethod`: the method that the running engine currently uses for trim. It is empty when the engine uses none, which is also the state of an engine that has just started.
- `InstanceManager.status.eraseQueue`: what waits in the erase queues of the disks that this instance manager processes: `replicas`, a map from replica data directory name to the number of files waiting, and `bytes`, the space these files hold in total.

The same three values are used everywhere. The admission webhook, and the CSI driver for a StorageClass parameter, reject a non-empty value for a v2 volume with an explicit "not supported by the v2 data engine" error.

#### StorageClass parameter

`dataEraseMethod`: same values as the volume field. A StorageClass without the parameter gives the volume the value of the global setting; a StorageClass with an empty value gives it no method.

#### Longhorn REST API

- Volume action `updateDataEraseMethod` with input `dataEraseMethod`.
- `dataEraseMethod` in the volume model and in the volume create input.

#### Instance manager disk service (`longhorn/types`, `imrpc`)

One new RPC for filesystem-type disks, `DiskEraseQueueSync`. The request lists the disks (name and path) whose erase queues this instance manager is to process. The reply gives, for each disk, the files and bytes waiting per replica, the file being overwritten with its progress, the files that wait and why, the failure list, and the time of the previous call. The call is both the assignment and the status: an instance manager works on the queue of a disk only while it keeps being called for that disk, and stops 5 minutes after the last call.

Block-type disks are not supported. The instance manager disk service API version is increased from 1 to 2.

#### Engine (`longhorn/types`, `longhorn/longhorn-engine`)

The method is handed to the component that releases the data at the time of the release. No engine, replica, or instance manager process gets a new start parameter.

- Snapshot purge and snapshot revert: the method is a string field of the existing requests, used for that operation only; empty means no overwrite. The messages are changed in place:
  - `SyncAgentService.SnapshotPurge` takes a new `SnapshotPurgeRequest` instead of `Empty`, and `SnapshotPurgeStatusResponse` gains `unerased_release_count` and `unerased_release_last_reason`;
  - `ControllerService.VolumeRevert`: `VolumeRevertRequest` gains the method; the reply is unchanged;
  - the replica's `ReplicaRevert`, `DiskRemove` (leaf removal), and `DiskReplace` (coalesce) requests gain the method, and their responses say whether a file that should have been queued was released without it, with the reason;
  - the instance manager proxy's `EngineSnapshotPurgeRequest` and `EngineSnapshotRevertRequest` gain the method, and the proxy's purge status passes the count and the last reason on.

  The engine command line takes `--data-erase-method` on `snapshot purge` and `snapshot revert` and rejects an unknown value. A purge or revert that is started without a method, for example from the engine command line without `--data-erase-method` or from inside a restore or a clone, does not overwrite and queues nothing.
- The count in the purge status is cumulative: it is the number of unerased releases since the replica's sync agent started, and a new purge does not reset it. The manager requests a purge more than once for one snapshot deletion, so a count per purge would be reset before the manager has read it.
- A new `SyncAgentService.ReaderStatus` answers the check for known readers that a range release makes: whether a reader is in progress and which one (`backup`, `export`, `file-send`, `snapshot-hash`).
- Trim is not requested by the manager; an unmap comes from the workload through the volume frontend. The engine therefore has to know the method while it runs: a new RPC, `ControllerService.VolumeDataEraseMethodSet`, forwarded by the instance manager proxy, sets it on a running engine, as `unmapMarkSnapChainRemoved` is set today but without a start flag. It accepts an empty value, `zero`, or `three-pass`. A newly started engine uses no method until the manager has set one. The engine reports `data_erase_method`, `trim_unerased_release_count` (since the engine started), and `trim_unerased_release_last_reason` in its `Volume`, which the proxy's `VolumeGet` returns. The v2 data engine and an older proxy answer `Unimplemented`.
- The unmap message from the engine controller to a replica carries a payload in its data, which an unmap and its response never had before. All values are little endian.
  - Request: byte 0 the version (1); byte 1 is 1 to overwrite before the punch, 0 not to; bytes 2 to 9 the time left for the overwrite in nanoseconds, 0 for no limit; the remaining bytes the method.
  - Response: byte 0 the version (1); byte 1 is 1 when the overwrite completed; byte 2 a reason code.

  The reason codes never change meaning: 0 none, 1 no overwrite requested, 2 backup in progress, 3 export in progress, 4 rebuild file send in progress, 5 snapshot hash in progress, 6 the sync agent cannot be asked, 7 the names of the inode cannot be counted, 8 the inode has another name, 9 overwrite failed, 10 incomplete overwrite, 11 the replica cannot decode the request, 14 the time left ran out. The engine sets three codes itself and never receives them: 12 the replica does not support secure erase on unmap, 13 the reply cannot be decoded, 15 the request budget is used up.

  An unmap without a payload keeps today's meaning. An older replica ignores the payload, punches, and responds without one; the engine records an unerased release with code 12. A replica sends a response payload only when the request had one, because the frontend (tgt through liblonghorn) sends unmaps without a payload and cannot take a response with one.
- New optional field `DataEraseMethod` in the replica's `volume.meta`, written by the replica when a running engine passes a newly set method on through a new `ReplicaService.DataEraseMethodSet`. A volume whose method is changed while it is detached has the old value there until it is attached again. A replica that a rebuild adds to a running engine gets the field only when the method is set again, at the next change of the method or the next engine start. Nothing in this proposal reads the field; it is there for the orphaned replica data follow-up.
- The engine CLI API version is increased from 12 to 13, and the instance manager proxy API version from 8 to 9. The manager passes the method with a purge or a revert, and calls the set RPC, only when the engine's running engine image reports CLI API version 13 or later and the engine's instance manager reports proxy API version 9 or later. An older proxy would drop the method without an error and has no set RPC. When the versions cannot be read, the manager logs a warning and sends the purge or revert without a method, so that it still runs.

## Design

### Implementation Overview

#### Erase primitive (`longhorn/sparse-tools`)

One implementation is shared by every path.

- `EraseRange(file, offset, length, method, deadline)` overwrites the allocated extents of an open file within a range. `EraseFile(file, method)` covers the whole file.
- The caller passes an open file. The primitive reopens the same inode through `/proc/self/fd/<fd>` with `O_WRONLY|O_DIRECT` and leaves the caller's descriptor unchanged. The allocated extents are listed with FIEMAP, which sparse-tools already uses with the sync flag, so delayed allocations have extents. Holes and unwritten (preallocated, never written) extents are skipped: they hold no volume data, and overwriting a hole would allocate new blocks and could fill the disk.
- The overwrite never writes outside the requested range or beyond the end of the file. Offsets and lengths are aligned to 4 KiB, the direct I/O alignment sparse-tools uses throughout. If a part of the range that holds allocated data cannot be written at that alignment, it is left as it is and the overwrite is reported as incomplete.
- Each pass writes its pattern over the extents in chunks of at most 1 MiB and ends with `fdatasync`. `zero` is one pass of `0x00`. `three-pass` is `0x00`, then `0xFF`, then random data.
- The deadline is checked before each chunk. Once it has passed, no further chunk is written, what was written is synced, the remaining passes are skipped, and the overwrite is reported as incomplete. It cannot interrupt a write or a sync that the kernel is already executing.
- The primitive reports its progress to the caller while it writes, returns the number of bytes written, summed over all passes (a three-pass overwrite of 4 MiB reports 12 MiB), and whether it completed. A write error is returned with the bytes written so far, after a best-effort sync of what was written. It never releases anything itself.

Only replica image files are overwritten. Metadata files (`*.meta`, `volume.meta`, `revision.counter`, `*.checksum`) hold no volume data and are removed as today.

#### Keeping the overwrite away from data in use

An overwrite changes the content of an inode in place. Today a file can be unlinked while something else still has it open, and that reader finishes with the old content. With an overwrite it would read the pattern instead. The design keeps an overwrite away from data in use with one rule for all releases, a queue with a kernel check for whole files, and a check for known readers for ranges.

**The last-name rule.** Removing a file name is a data release only when it is the last name of the inode. The replica links one inode under two names in two places: when a snapshot is created, the head file is linked under the new snapshot name and the head name is removed afterwards; and when a purge replaces a snapshot with the merged file. An inode with more than one link is never overwritten. A prune or an unmap punches ranges rather than removing a name: when the inode has more than one link, or its link count cannot be read, the range is punched without an overwrite and an unerased release is recorded.

**Whole files go to the erase queue.** The erase queue of a disk is the directory `<disk path>/erase`, next to `<disk path>/replicas` and on the same filesystem, so that a file is moved into it with a rename. A queued file has the path `erase/<replica data directory name>/<method>/<name>`, where the name is a new UUIDv7, so that names sort by the time they were queued. The path is all the instance manager needs to know: which replica the file belonged to and which method to use.

The paths that let go of a replica image file in a running replica are: removing a leaf snapshot in a purge, removing the old child after a coalesce, and removing the old head in a revert. With a method:

1. If the inode has more than one link, the replica removes the name as today. Nothing is released and nothing is queued.
2. Otherwise it creates the queue directory if it does not exist, logs the move, and renames the file into the queue. For a coalesce, where the old child is replaced by a rename of the merged file onto its name, the replica first links the old child into the queue and then switches the names as today, in one rename, so that the child's name never disappears.
3. If the file cannot be moved or linked into the queue, the replica removes it as today and records an unerased release.

For the replica a queued file is deleted: it is no longer part of the replica's disk chain or metadata, and nothing opens it by name again. The replica does not overwrite it and does not check for readers.

Other paths that remove replica image files are not data releases covered by this proposal and are unchanged: removing the old head name after creating a snapshot (the inode lives on as the snapshot), rollback of a failed snapshot creation, and the removal of extra files when a rebuild prepares a reused directory.

**The instance manager overwrites a queued file only when nobody uses it.** A file can enter the queue while it is still open: the replica's own disk chain still reads the old child until it has reopened the chain on the merged file, and a backup, an export, a rebuild file send, or a snapshot hash that started earlier keeps its descriptors until it ends. Before it overwrites a queued file, the instance manager therefore requires both of the following, and leaves the file for a later round otherwise:

- the inode has one link. When every link of an inode is in the erase queue, which happens when a coalesce was interrupted after the link and repeated later, the instance manager removes all but one of them first;
- a write lease (`fcntl` with `F_SETLEASE` and `F_WRLCK`) can be taken on the file. The kernel grants it only when no other descriptor of the inode is open, whichever process or pod holds it, so the check does not depend on what an instance manager can see of other processes. It is also what keeps two instance managers that work on the same disk off the same file.

A reader in progress therefore delays the overwrite; it does not cancel it. If the filesystem does not support leases, the instance manager cannot tell whether the file is in use: it removes the file without overwriting it and records an unerased release.

**A check for known readers, for range releases.** A prune and a trim punch holes in a file that stays in use, so they cannot wait. All operations that read a replica's snapshot files from within that replica run in its sync agent: backup, the source side of clone and export, the file sender of a rebuild over the network, and snapshot hashing. Before a prune or a trim overwrites a range, the replica asks its sync agent whether any of these is in progress at that moment, through the new `ReaderStatus` RPC; this needs a count of active exports and file sends in the sync agent, which has none today. The replica waits at most 1 second for the answer for an unmap, and never more than the segment's time left; a prune runs in the sync agent and checks its own state once before it prunes a file. If a reader is in progress, or the question cannot be answered, or the replica runs without a sync agent, the overwrite is skipped, the range is punched as today, and an unerased release is recorded. The check looks at the state at that moment and does not prevent a reader from starting afterwards.

#### Erase queue (`longhorn/longhorn-instance-manager`, `longhorn/longhorn-manager`)

The instance manager processes the erase queue of each disk it has been assigned through `DiskEraseQueueSync`. For one disk it handles one file at a time, in the order of the file names:

1. It checks the two conditions above. A file that fails one is noted with the reason (`open`, `linked`) and tried again in a later round.
2. It logs the start, overwrites the file with the method named in its path, logs the result with the bytes written and the duration, and removes the file. While it overwrites it logs, once a minute, the bytes done and to do in the queue of the disk, the write rate, and an estimate of the time left.
3. If the overwrite fails, or the method in the path is not known, it removes the file anyway, logs an unerased release, and adds the failure, with its time, to the failure list.
4. It removes a directory `erase/<replica data directory name>` that is empty when it runs no replica process for that directory. A replica that still exists creates the directory again when it needs it.

The instance manager keeps the state of a disk's queue in a status file, `erase/status.json`: the file being overwritten and its progress, the files that wait and why, the failure list, and the time of the last `DiskEraseQueueSync` call. The status file lets a restarted instance manager, or another one that takes the disk over, report where the queue stands; the queued files themselves are the only state that is needed to continue. A file whose overwrite was interrupted is overwritten again from the start.

In the manager, an erase queue monitor, modelled on the disk monitor of the node controller, calls `DiskEraseQueueSync` on the node's default v1 instance manager every 30 seconds with the filesystem-type disks of the node, and the instance manager controller writes the result to `InstanceManager.status.eraseQueue`. Only the default instance manager of a node is assigned; an older instance manager that is still running for existing processes is not called and has no erase queue support. After a later upgrade two instance managers that both support the queue can be assigned in turn; the first stops 5 minutes after its last call, and until then the write lease keeps them off the same file. The 30 seconds and the 5 minutes are estimates.

Failures reach the manager through the same call. Each failure carries the time, on the instance manager's clock, at which it was recorded, and the reply carries the time of the previous call. The manager raises a Warning event for every failure that is newer than the previous call, so it needs no memory of its own and does not repeat an event after a restart or an owner change. The instance manager drops a failure from the list at the call after the one that returned it.

Nothing waits for the erase queue: not the deletion of a Replica, a Volume, or an InstanceManager resource, and not the removal of a disk from a node. Files that are still queued when an instance manager stops are continued by the next instance manager that is assigned the disk.

#### Resolving and distributing the method (`longhorn/longhorn-manager`)

- A volume gets its method when it is created: from the StorageClass parameter or the create input, or, when neither is given, from the global setting. After that only `Volume.spec.dataEraseMethod` counts. The volume controller copies it to the specs of the volume's engines and replicas.
- For a v2 volume the method is always empty.
- Replica deletion: the replica controller uses `Replica.spec.dataEraseMethod` when it moves the replica image files into the erase queue.
- Snapshot purge and revert: the manager passes the method with the request. For a purge, the instance manager's proxy hands it to each replica's sync agent, which runs the purge; for a revert it goes through the engine to each replica. It is used for that operation only. Every request for a purge from the manager passes it: snapshot deletion, the API and recurring jobs, and the purge around a rebuild. A purge or revert that Longhorn starts internally as part of a backup restore or a clone gets no method.
- Trim: the engine monitor calls the set RPC when `Engine.spec.dataEraseMethod` differs from the method the engine reports. It does so in the poll in which it reads the engine's volume information, before it starts a frontend that is missing, and writes the reported method to `Engine.status.dataEraseMethod`. A failed set is retried at the next poll and logged once per distinct error. The engine puts the method into each unmap it sends to its replicas, so a replica needs no state of its own for trim.
- The engine passes a newly set method on to its replicas, which store it in `volume.meta`, without holding its lock; replicas in error are skipped, and a replica that cannot record the method does not fail the set.
- For snapshot purge, revert, and trim, all of this is skipped for a v2 engine and for an engine below the required versions; nothing is reported in that case. Replica deletion does not depend on the engine image.

#### Replica deletion

Today the manager pod on the replica's node stops the replica process and removes the data directory itself. It does so when the Replica resource is the active one, or when no other Replica resource of the volume refers to the same directory. The first half of that condition lets the directory go while an inactive Replica resource, created for live engine upgrade or migration, still refers to it.

The new flow, when `Replica.spec.dataEraseMethod` is not empty:

1. The replica controller stops the replica process, as today.
2. If another Replica resource of the volume that is not being deleted refers to the same node, disk, and data directory, the controller neither moves nor removes anything and releases the finalizer. The last Replica resource that refers to the directory does both. This is stricter than today's condition and applies only when a method is set.
3. Otherwise the controller moves every replica image file of the directory into the erase queue of the disk, under `erase/<replica data directory name>/<method>/`. An inode that has several names in the directory is moved under one of them and its other names are removed. It does not wait for the replica process to be gone: a file that is still open waits in the queue until it is closed.
4. It then removes the directory as today and releases the finalizer. It does not wait for the queue.
5. If a file cannot be moved, the controller records an unerased release and removes the directory as today.

The manager does this itself, in the pod that already removes the directory today; no instance manager is needed for the move. If the node has no running v1 instance manager, the files wait in the queue until one is assigned the disk.

A directory removal that fails is handled as today: the error is returned and the finalizer stays until a later attempt succeeds.

Cleanup of a failed replica, including the leftovers of a failed rebuild, goes through the same flow because it deletes the Replica resource.

A replica whose node is down is handled as today: the manager that takes over cannot reach the directory, logs this, and releases the finalizer. With a method set it now also records an unerased release. The same holds for a replica whose disk is not ready or not found on the node.

#### Snapshot purge (`longhorn/longhorn-engine`, `longhorn/sparse-tools`)

A removed snapshot's data is released in three ways.

- Remove (the snapshot is a leaf): the replica process moves the snapshot file into the erase queue.
- Coalesce and replace (the snapshot has one child that is not the head): the sync agent copies the child's data into the snapshot file, as today; data of the removed snapshot that the child shadowed is overwritten in place by that copy. The replica process then links the old child file into the erase queue, switches the child's name to the merged file, as today, and reopens its disk chain on the merged file. The old child has no name left in the replica directory, and the instance manager overwrites it once the replica and every other reader have closed it.
- Prune (the snapshot is directly under the head): the sync agent punches the ranges of the snapshot that the head shadows. This is a range release. With a method set, it overwrites each range with `EraseRange` right before that range is punched, through a new prune variant in sparse-tools that calls a function before each punch with exactly that range. The check for known readers and the link count are taken once per file before the prune starts. A range that holds no data in the file is not a data release: it is not overwritten and not recorded. The volume does not read the pruned ranges from the snapshot, because the head shadows them.

Leaf removal and coalesce take as long as they do today, and their requests keep their timeouts. A prune overwrites inline, without segmenting and without an extra timeout. Once an overwrite fails, or is skipped because of a reader, the rest of that purge on that replica overwrites nothing more: its ranges are punched as today, and its whole files are still moved into the erase queue, because overwriting a queued file is a separate step of the instance manager. The prune of one file is one data release: if any of its ranges was not overwritten, one unerased release is recorded, with the first reason, the number of ranges and bytes, and their span. Purge progress reporting is unchanged.

#### Snapshot revert

Revert creates a new head and removes the old one. With a method, the replica process moves the old head into the erase queue instead of removing it. The revert takes as long as it does today: no request waits for an overwrite, the timeouts are unchanged, and the engine controller holds its lock no longer than today. A volume can be detached right after the revert; the old head stays in the queue until it has been overwritten.

#### Filesystem trim

Three limits apply to an unmap today:

- the engine controller holds its lock for the whole unmap, which blocks all other I/O of the volume;
- the engine applies the engine-replica timeout (8 seconds by default, 30 at most) to an unmap as it does to reads and writes, and a replica that exceeds it is marked as failed;
- the block device of the volume has a SCSI command timeout of 60 seconds for the whole request.

One unmap message can cover close to 4 GiB, so an unbounded inline overwrite could exceed all three. When a method is set, the engine controller and the replica bound it as follows. Without a method the unmap path is unchanged.

1. Segments. The engine controller cuts the unmap at absolute offsets that are multiples of 16 MiB, sends the segments one after another, and releases its lock between segments so that other I/O can proceed. Because the cuts are at multiples of 16 MiB they are sector-aligned, so the replica's inward alignment applies only to the two ends of the original request, exactly as for an unsegmented unmap. The result returned to the frontend is the sum over the segments. Releasing the lock is not enough by itself, because a segment that takes the lock again at once can overtake a reader that was already waiting: the controller therefore lets the reads, writes, and status calls that are waiting take the lock before it starts the next segment (it waits at most 100 ms for them), and the segments of concurrent unmap requests take turns. Other I/O waits for at most the segment in progress. This costs two atomic operations on every acquisition of the controller's read lock, for every v1 volume, with or without a method. Before each segment, while holding its lock, the controller checks that the frontend is up, that no replica is rebuilding, and that the volume is not expanding. If the frontend is down, for example because a snapshot revert or a live upgrade shut it down between two segments, the rest of the unmap fails with an error to the frontend. If a replica is rebuilding the rest is dropped, and during an expansion it is rejected, as for an unsegmented unmap.
2. Segment budget. Each segment carries an overwrite request with the method and the time left for it: at most 4 seconds, half of the minimum engine-replica timeout, and never more than what is left of the request budget. The replica finds the files it is about to punch (the head, and the snapshots already marked as removed, exactly as today), runs `EraseRange` on each for the segment's range with that deadline, and then punches the hole. If the deadline passes, the replica does not overwrite further, punches the hole anyway, logs an unerased release, and says so in its reply.
3. Request budget. The whole unmap request has an overwrite budget of 30 seconds, half of the SCSI command timeout. It limits the time spent overwriting, not the duration of the request: the time counted is the time the replicas take for the segments sent with an overwrite, measured from the moment the controller holds its lock, including the punch. When the budget is used up, or as soon as a replica reports an overwrite that failed or was skipped, the controller sends the rest of the request with the explicit "do not overwrite" payload; the replicas punch it, and the engine logs one unerased release for the remaining range and counts it. Within one request, each replica that did not complete its overwrite counts as one unerased release with its last reason, and the rest sent without an overwrite counts as one more.

The budgets limit what secure erase adds. They do not make a slow disk fast: a write that the kernel has already accepted cannot be interrupted, so a disk that stalls a single 1 MiB write stalls the replica as it does for an ordinary write today.

The 16 MiB, 4 second, and 30 second values are estimates, not measurements. They assume a worst case of about 50 MB/s sequential write, at which three passes over 16 MiB take about one second. They are constants in the first version and are expected to be tuned from field reports, or turned into settings, if unerased releases caused by the budgets turn out to be common.

Not every trimmed byte is a data release:

- a range whose data is held by a snapshot that is kept is not released, so nothing is overwritten;
- the replica shrinks an unaligned request inward to its sector size, as today; the edges are not punched and not overwritten.
- a range of a file that holds no data, as `SEEK_DATA` reports it, releases nothing and is not recorded; when the replica cannot tell, it counts the range as data.

A snapshot marked as removed by `unmapMarkSnapChainRemoved` has only the trimmed ranges released at trim time. The rest of its data is released, and overwritten, when a purge removes it. This proposal does not change when that purge runs.

Existing behavior is kept for an unmap without a method: it is not segmented, it is dropped while a replica is rebuilding, and it is rejected during expansion.

#### Recording unerased releases

Every unerased release is written to the log of the component that observed it, with the operation, the replica, the file and range, and the reason. The log is the complete record.

An overwrite is not expected to fail, so the event only has to tell the operator to look at the log. The manager raises a Warning event with the reason `UnerasedRelease`, through the event recorder that Longhorn uses elsewhere, when it learns of unerased releases:

- Replica deletion: when a replica image file cannot be moved into the erase queue, and when the replica's node or disk is unavailable. The event is raised on the Volume, or on the Replica when the Volume is not found.
- Erase queue: for each failure that `DiskEraseQueueSync` returns and that is newer than the previous call. The event is raised on the Volume of the replica that the file belonged to, or on the Node when that replica or volume no longer exists.
- Snapshot purge: when the count in the purge status of a replica has increased since the manager last looked, the manager logs the increase, and once no replica of the engine is purging it raises one event that names those replicas, with the sum of the increases and the last reason.
- Trim: when the count that the engine reports has increased since the manager last looked; the event gives the increase.

A snapshot revert has no result of its own: its old head goes to the erase queue. For the two counts, the first value that a new engine monitor sees, after a manager restart or an owner change, is logged but raises no event, because the previous monitor may have raised it. A Volume that cannot be read gets no event for a purge or a trim; the log still has the record.

The event message is "<operation> left <count> unerased releases, last reason: <reason>; see <log location> for each release", where the log location is the instance manager log for the erase queue, the Longhorn logs on the replica's node for a replica deletion, the replica logs for a purge, and the engine log for trim.

A file that waits in the erase queue is not an unerased release. It is shown in `InstanceManager.status.eraseQueue` and, with the reason it waits, in the status file of the queue.

Nothing is recorded where no method is in effect: with an engine image or instance manager that does not support secure erase, for which the method is ignored for snapshot purge, revert, and trim, and for a purge or revert that is started without a method.

Each overwrite also logs its start and its result with the method, the number of bytes overwritten, and the duration.

#### Failure handling summary

| Situation | Behavior |
| --- | --- |
| Overwrite of a queued file returns an error (for example I/O error, no space) | File removed; unerased release recorded; not retried |
| Queued file is still open by a process, or has another link outside the queue | File waits in the queue; shown in the queue status; not an unerased release |
| Filesystem of the disk does not support leases | Queued file removed without overwrite; unerased release recorded |
| Disk is slow | Queued files wait; no time limit; no operation waits for them |
| Instance manager or node restarts during the overwrite of a queued file | The file is overwritten again from the start by the next instance manager that is assigned the disk |
| No running v1 instance manager on the node | Queued files wait until one is assigned the disk |
| File cannot be moved or linked into the erase queue | Removed as today; unerased release recorded |
| Replica's node or disk is unavailable at removal | Finalizer released as today; data stays; unerased release recorded |
| Replica directory is referred to by another Replica resource that is not being deleted | Nothing moved and nothing removed until the last one is deleted |
| Disk is removed from Longhorn, or Longhorn is downgraded, while files are queued | Files stay on the disk; the operator overwrites and removes them by hand |
| Overwrite of a pruned or trimmed range returns an error | Range punched; unerased release recorded; the rest of that purge or trim request is not overwritten |
| Trim segment or trim request exceeds its budget | Hole is punched; unerased release recorded |
| A backup, export, rebuild file send, or snapshot hash is in progress on the replica during a prune or a trim, the sync agent cannot be asked, or the replica runs without a sync agent | The overwrite is skipped; the range is punched; unerased release recorded |
| Inode with another name, during a prune or an unmap | Range punched without overwrite; unerased release recorded |
| The inode being removed by a purge or a revert has another name | The name is removed; nothing is queued |
| Replica answers an unmap without a result payload (older replica) | Range punched without overwrite; unerased release recorded |
| Frontend down between two segments of a trim | Rest of the unmap fails with an error to the frontend |
| Replica or engine process ends before the manager has learned of an unerased release, or the manager stops between reading a failure and raising the event | No event; the log entry is the only trace |
| Engine image or instance manager does not support secure erase | Method ignored for purge, revert, and trim; nothing recorded |

### Test plan

#### Unit tests

- Erase primitive: only allocated extents are written; holes stay holes and the allocated size does not grow; each method leaves the expected pattern; a range erase does not touch bytes outside the range; a passed deadline stops the overwrite before the next chunk and reports it; progress is reported while writing.
- Last-name rule: removing one of two names of an inode queues nothing, overwrites nothing, and leaves the content readable through the other name.
- Queueing in the replica: a leaf removal and a revert rename the file into `erase/<replica data directory name>/<method>/`; a coalesce links the old child into the queue before the switch, and the child's name exists at every step; a file that cannot be moved is removed and recorded.
- Erase queue worker: a file with one link and no other open descriptor is overwritten and removed; a file that another process holds open, or that has a link outside the queue, is left and reported with its reason, and is overwritten once the descriptor is closed or the link is gone; several links of one inode inside the queue are reduced to one; a failed overwrite removes the file and adds a failure; an interrupted overwrite is repeated from the start; the worker stops 5 minutes after the last call; an empty replica directory in the queue is removed.
- Failure delivery: the manager raises one Warning event per failure that is newer than the previous call and none for older ones, also after a manager restart.
- Reader check for range releases: with a backup, an export, a file send, or a snapshot hash in progress on the replica, or when the sync agent cannot be asked, the overwrite of a pruned or trimmed range is skipped and recorded; otherwise it runs.
- First failure: after a failed overwrite, the rest of the purge on that replica, or of the trim request, is released without an overwrite.
- Recording: for purge and trim, one Warning event per increase of the count that the manager sees, and none at the first poll of a new monitor.
- Method: a volume created without a method gets the global setting; a StorageClass parameter, also an empty one, wins over the setting; changing the setting does not change an existing volume; v2 volume; engine below the required versions.
- Admission webhook and CSI parameter: allowed values; rejection for v2 volumes.
- Trim segmenting: for an unaligned request that crosses at least two cuts, the punched range is identical to that of the unsegmented request.

Crash and error cases are covered by Go tests in the repositories, because the production binaries have no fault-injection hook and none is added.

#### Engine integration tests

Run on a replica directory on a dedicated loop device, so that the raw device can be searched for a marker pattern after each operation. An erase queue worker runs against the same disk. For each method:

- create a snapshot with a method set: the snapshot content is intact after the old head name is removed, and nothing is queued;
- remove a leaf snapshot, coalesce a snapshot, revert: the released file appears in the erase queue, the marker written to it is no longer on the device once the queue is empty, and the volume and the kept snapshots read back unchanged;
- prune the snapshot under the head: the marker is no longer on the device when the purge ends, and the volume reads back unchanged;
- a backup, an export, a rebuild file send, and a snapshot hash in progress on the replica while a snapshot is removed or coalesced: the reader finishes with the old content, the file stays queued until then, and it is overwritten afterwards;
- the same readers in progress while a snapshot is pruned or a range is trimmed: no overwrite is added, the release behaves as it does today, and an unerased release is recorded;
- rebuild preparation that removes extra files in a reused directory: nothing is queued and nothing is recorded;
- unmap: the marker in the trimmed range is no longer on the device; data held by a kept snapshot is still readable from that snapshot;
- the method passed with a purge or a revert is used for that operation only; a method set for trim is used by the next unmap, is reported by the engine, and is empty again after an engine restart until it is set again; `volume.meta` holds the method after it was set.

#### Integration and end-to-end tests

- Volume deletion with each method: the Volume and Replica resources are gone without waiting for the overwrite, `InstanceManager.status.eraseQueue` shows the files and then becomes empty, and after that the marker written to the volume cannot be found on the disk of any replica node.
- Replica deletion and eviction with a method set.
- Snapshot delete and purge, snapshot revert followed at once by a detach, and filesystem trim with a method set, including the recurring `filesystem-trim` job.
- A backup that is still running when the snapshot it reads is purged: the backup is intact, and the released file is overwritten after the backup ends.
- Changing the method on an attached volume takes effect without detaching, and `Engine.status.dataEraseMethod` follows.
- StorageClass parameter and global setting, including a StorageClass with an empty parameter while the setting has a method.
- Volume deletion while one replica node is down: the volume is deleted, a Warning event and a log entry name the replica that was not overwritten, and its directory later appears as orphaned replica data.
- Replica deletion while the instance manager on the node is not running: the directory is removed, the files wait in the erase queue, and they are overwritten after the instance manager is running again.
- Instance manager restart in the middle of an overwrite: the file is overwritten again and removed.
- Live engine upgrade and live migration with a method set: deleting the active Replica resource while an inactive one refers to the same directory neither moves nor removes anything; the volume stays healthy; the files are queued and the directory is removed with the last Replica resource.
- An incremental backup restore that purges snapshots, and a purge started from the engine command line without a method: nothing is queued, nothing is overwritten, and nothing is recorded.
- A trim right after the engine has started, before the manager has set the method: it runs without an overwrite, and `Engine.status.dataEraseMethod` is empty.
- A volume on an engine image without secure erase support: operations succeed without errors.
- The write lease check on the filesystems Longhorn supports for replica disks (ext4, XFS) and on the oldest supported kernel, with the reader in another pod.
- Regression: without a method, deletion, purge, revert, and trim behave and perform as before, and no `erase` directory is created.

### Upgrade strategy

- The setting defaults to an empty value, and existing volumes, engines, and replicas have an empty method, which means no overwrite. Nothing changes after an upgrade until a user sets a method, and no resource has to be changed by the upgrade.
- Snapshot purge, revert, and trim need an engine image with CLI API version 13 and an instance manager with proxy API version 9. Until both are in place for a volume's engine, the method is ignored for those operations without an error and without a record. The documentation tells users to upgrade engine images and instance managers before relying on the feature.
- Replica deletion is done by the manager, so it works for a volume on any engine image.
- A replica moves files into the erase queue only when a request carries a method, and only a manager with this feature sends one. Such a manager runs the node's default instance manager with this feature and assigns it the disks, so a queued file always has an instance manager that processes it.
- `volume.meta` gains an optional field. An older engine ignores it when reading. If an older engine rewrites `volume.meta`, the field is dropped and is written again by the next engine that supports it.
- No data migration is needed.
- A downgrade is not supported, as for Longhorn in general. Files that are queued at that time stay on the disk.

## Note

- The decision that secure erase never blocks a data release was made to avoid a deadlock in which space cannot be reclaimed, for example on a full or failing disk. On a filesystem that overwrites in place an overwrite of allocated extents needs no new space, but on copy-on-write or thin-provisioned storage it can.
- Prior art: OpenStack Cinder offers `volume_clear` (`zero`) for thick LVM volumes only and removed its `shred` option in 2016. Its security documentation states that writing over a volume "does not ensure that the data will be actually erased on the physical disks, as the storage solution could be doing copy-on-write or other optimizations".
- The orphaned replica data follow-up (https://github.com/longhorn/longhorn/issues/14626) reads the method from `volume.meta` and falls back to the global setting when the record is missing.
- When the v2 data engine adds its key to `data-erase-method`, the upgrade has to add that key to the stored setting value of existing clusters.
- An earlier revision of this proposal overwrote whole files inside the operation, after removing the file name. It was replaced by the erase queue because a snapshot revert, a purge, and a replica deletion then had to wait for the overwrite, and because a process that ended during the overwrite released the rest of the file without overwriting it.
- The write lease was chosen over looking at `/proc` because an instance manager cannot be assumed to see the processes of other pods, and over a reader check before queueing because a reader in progress would then cancel the overwrite instead of delaying it.
