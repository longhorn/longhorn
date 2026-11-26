# Secure Erase of Replica Data for V1 Data Engine

## Summary

Longhorn never overwrites v1 replica data when it lets go of it. Deleting a volume, a replica, or a snapshot unlinks files; trimming a filesystem punches holes. In both cases the old blocks go back to the free space of the node's filesystem with their content intact, and can be read back from the raw device until something else reuses them.

This proposal adds an optional data erase method for v1 volumes. It is chosen when the volume is created. A volume that has one never gives data back to the node disk piece by piece: every replica image file that it lets go of, in a replica deletion, a snapshot purge, or a snapshot revert, is overwritten before it is removed, and the two operations that release parts of a file, filesystem trim and the pruning of a snapshot, are not performed. Two methods are offered: a single pass of zeros, and a three-pass method (zeros, ones, random) for users whose audit checklist requires it.

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
- Data that has been released cannot be found again. Once a file is unlinked or a hole is punched, its blocks are no longer addressable through the file. Overwriting the remaining files at volume deletion does not reach blocks that an earlier snapshot deletion or trim already released. A volume therefore has to be covered from its creation, and for every release, not once at the end.

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

- Let a user choose a data erase method for a volume when it is created, with a StorageClass parameter and a global default.
- For a volume that has a method, overwrite the data of every whole-file release of a reachable v1 replica before the file is removed:
  - replica deletion, including volume deletion, eviction, and cleanup of failed replicas;
  - snapshot purge (leaf removal and coalesce);
  - snapshot revert (the discarded volume head).
- For such a volume, perform no range release at all: filesystem trim is ignored and snapshots are not pruned, so that nothing leaves the volume's files without going through a whole-file release.
- Never let secure erase fail or hold up a volume operation, and never keep data on a disk because an overwrite failed.
- Never overwrite a replica image file that a replica still uses or that any process still has open.
- Do not lose a pending overwrite when a replica process, an instance manager, or a node restarts.
- Log every unerased release, raise a Warning event when the manager learns of one, and show what is still waiting to be overwritten.
- Record the erase method in the replica data directory so that a later feature can honor it for orphaned replica data.
- Keep the API data-engine neutral so that the v2 data engine can adopt it without an API change.

### Non-goals

- NIST SP 800-88 "Purge" or "Destroy". An in-place overwrite of a file on a host filesystem cannot guarantee that the original physical blocks are overwritten. See [Limitations](#limitations).
- The v2 data engine. Tracked in https://github.com/longhorn/longhorn/issues/14621.
- Orphaned replica data: neither overwriting it when the orphan is deleted nor recording that deletion as an unerased release. Tracked in https://github.com/longhorn/longhorn/issues/14626. This proposal only records the method on disk for it.
- Replicas that are not reachable when they are removed (node down, disk unavailable). Their data stays on the disk, as today.
- Changing the method of an existing volume, including turning it on for a volume that was created without one.
- Reclaiming space by trim or prune on a volume that has a method. Overwriting ranges that are released from a file in use is left to a later proposal.
- Data that a replica rebuild releases in a reused replica directory, and files that a backup restore removes or replaces itself. See [Limitations](#limitations).
- Data outside the replica data directory: backing image files, backing image manager temporary files, and backups in the backupstore.
- Detecting or blocking storage on which the overwrite is not effective.
- Read-back verification of the overwrite.

## Proposal

Add a data erase method to the volume. It is empty (no overwrite, the default), `zero`, or `three-pass`. It is set when the volume is created and cannot be changed afterwards. A new global setting gives the value that a new volume gets when nothing else is specified.

A volume with a method differs from other volumes in two ways:

- A whole-file release does not remove the file. The file is moved into an erase queue on the same disk, which is a rename, and the operation continues at once. The node's instance manager overwrites the queued files one after another and removes each when it is done. A queued file keeps a name until then, so the work survives a restart. The overwrite is done on the replica image file, below the volume's block device: writes through the block device only reach the volume head, cannot touch snapshot files, would allocate new blocks, and are not possible once the volume is detached.
- No range release happens. The engine ignores unmap requests, so a filesystem trim releases nothing, and a purge does not prune the snapshot under the volume head. The data stays in the replica image files until a whole-file release lets go of the file.

Because the method is fixed at creation, the engine and replica processes are told the method when they start and need no new requests to learn it.

Secure erase is best-effort. If an overwrite cannot be done or fails, the data is released anyway and Longhorn records an unerased release.

### User Stories

#### Story 1: deleting a volume under a sanitization policy

An operator must show that data of a decommissioned application is not left on the node disks.

- **Before**: Deleting the volume unlinks the replica files. The operator has to log in to every node that held a replica and overwrite the files by hand before deleting the volume, and has no way to do this for snapshots that were deleted or blocks that were trimmed earlier.
- **After**: The volume is created from a StorageClass with `dataEraseMethod: "zero"`. Every file that a snapshot deletion, a revert, and finally the volume deletion let go of is overwritten before it is removed, and nothing leaves the volume's files in between. The operator collects the Longhorn logs and events and checks them for unerased releases.

#### Story 2: an audit checklist that requires three passes

An auditor requires three rounds: zeros, ones, random.

- **Before**: Not possible within Longhorn.
- **After**: The operator sets `dataEraseMethod: "three-pass"` on the affected volumes. The documentation states that this adds no protection over a single pass on current media and costs three times the I/O.

#### Story 3: trimming a filesystem

A database volume has a large table dropped and the filesystem is trimmed.

- **Before**: The trimmed ranges are punched out of the volume head. The dropped table's blocks return to the node filesystem unchanged.
- **After**: The volume has a method, so the trim releases nothing: the blocks stay in the replica image files, where the filesystem reuses them for new data. They are overwritten when the files that hold them are released, at the latest when the volume is deleted. The volume does not shrink on the node disk.

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

Per volume, in the create request of the Longhorn UI or API, or in `spec.dataEraseMethod` of a new Volume resource. An empty value means no overwrite.

The global setting is only a default for new volumes: it is copied into a volume that is created through CSI from a StorageClass without the parameter, or through the Longhorn API without the field. Changing the setting later does not change existing volumes. A StorageClass that has to switch secure erase off while the global default is set carries `dataEraseMethod: ""`.

The method cannot be changed after the volume is created. To put existing data under secure erase, create a new volume with a method and move the data to it. A volume that has a method has it for its whole life, so everything that was ever written to it is either still in its files or has gone through the erase queue.

#### What the user observes

- Deleting a volume or a replica, purging snapshots, and reverting to a snapshot take as long as they do without a method. The replica image files they let go of are moved into the erase queue of the disk and are overwritten afterwards.
- The disk space of queued files stays in use until they have been overwritten, so space is returned later than the operation reports. `InstanceManager.status.eraseQueue` shows, per replica, how many files are waiting and how many bytes they hold in total. While it overwrites, the instance manager logs its progress, the write rate, and an estimate of the time left once a minute.
- A queued file that is still open, for example by a backup that started before a purge, waits until it is closed and is overwritten then.
- A filesystem trim succeeds and frees nothing. The Longhorn trim action is rejected for the volume with a message that says why, and a recurring `filesystem-trim` job skips it.
- The volume's actual size on the node disks only grows, up to its nominal size. A snapshot that is deleted while it is directly under the volume head keeps its space until a later snapshot has been taken and a purge can merge it.
- An unerased release is written to the log of the component that observed it. When the manager learns of one, it raises a Warning event. Examples: the replica's node was down when the replica was removed, or the overwrite returned an I/O error.

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
- The method is fixed when the volume is created. A volume that was created without a method, which includes every volume that exists before the upgrade, cannot get one; its data has to be moved to a new volume.
- A volume with a method does not give space back through trim or prune. Its replicas grow up to the volume's nominal size and stay there until snapshots or the volume are removed. Workloads that rely on trim to keep thin-provisioned volumes small should not use a method.
- The overwrite never blocks a release and can be skipped. The log is the complete record of unerased releases. A Warning event is a notification, not an archive: it is raised only when the manager learns of the unerased release, and Kubernetes keeps events for a limited time (one hour by default). For an audit, collect the logs.
- A queued file is overwritten only after it has been closed by every process. A process that keeps a queued file open, for example a replica process that could not be stopped, keeps that file, and its space, in the erase queue. The queue status names such files.
- A slow or failing disk delays the overwrite of its queued files for as long as it takes; there is no time limit. An overwrite that returns an error is not retried: the file is removed and an unerased release is recorded.
- Files in the erase queue are processed by the instance manager that the manager assigns. Deleting a replica, a volume, or an instance manager, and removing a disk from Longhorn, do not wait for the queue. Before removing a disk from Longhorn, check `InstanceManager.status.eraseQueue`; files that are left in the `erase` directory of a disk have to be overwritten and removed by hand. A Longhorn downgrade leaves queued files that nothing processes.
- Unerased releases are not stored anywhere but in the logs, apart from the short-lived failure list of the erase queue. A manager that stops between reading a failure and raising the event leaves the log entry as the only trace. A replica that cannot move a file into the erase queue during a purge or a revert removes it as today and has only its own log to record it.
- A replica that is unreachable when it is removed is not overwritten. Its data stays on the disk and later appears as orphaned replica data. Deleting that orphan neither overwrites it nor records anything until https://github.com/longhorn/longhorn/issues/14626 is implemented.
- A replica rebuild that reuses an existing replica directory releases stale data in that directory (files that the source replica does not have, and ranges that are holes in the source) without overwriting it. A backup restore removes and replaces some files itself without overwriting them. None of this is recorded.
- Data outside the replica directory (backing images, backups) is not covered.
- Encrypted volumes are treated like any other volume.
- The engine image of the volume must support secure erase. Longhorn does not check this when the volume is created. On an engine image that does not know the start parameter, the engine and replica processes of a volume with a method fail to start, and the volume cannot be attached.

### API changes

#### Setting

`data-erase-method`: data-engine-specific, string, default `{"v1":""}`. Allowed values: empty (no overwrite), `zero`, `three-pass`. Only the `v1` key exists; the v2 data engine adds its key in its own proposal. The setting is the method that a new v1 volume gets when it is created without one. It is not consulted for existing volumes. The Helm chart exposes it as `defaultSettings.dataEraseMethod`.

#### CRD

- `Volume.spec.dataEraseMethod`: empty (default, no overwrite), `zero`, `three-pass`. Immutable: the admission webhook rejects a change.
- `Engine.spec.dataEraseMethod` and `Replica.spec.dataEraseMethod`: the volume's method, written by the volume controller when it creates the resource. Immutable.
- `InstanceManager.status.eraseQueue`: what waits in the erase queues of the disks that this instance manager processes: `replicas`, a map from replica data directory name to the number of files waiting, and `bytes`, the space these files hold in total.

The same three values are used everywhere. The admission webhook, and the CSI driver for a StorageClass parameter, reject a non-empty value for a v2 volume with an explicit "not supported by the v2 data engine" error.

#### StorageClass parameter

`dataEraseMethod`: same values as the volume field. A StorageClass without the parameter gives the volume the value of the global setting; a StorageClass with an empty value gives it no method.

#### Longhorn REST API

- `dataEraseMethod` in the volume model and in the volume create input. There is no action to change it.
- The volume action that trims the filesystem returns an error for a volume that has a method.

#### Instance manager disk service (`longhorn/types`, `imrpc`)

One new RPC for filesystem-type disks, `DiskEraseQueueSync`. The request lists the disks (name and path) whose erase queues this instance manager is to process. The reply gives, for each disk, the files and bytes waiting per replica, the file being overwritten with its progress, the files that wait and why, the failure list, and the time of the previous call. The call is both the assignment and the status: an instance manager works on the queue of a disk only while it keeps being called for that disk, and stops 5 minutes after the last call.

Block-type disks are not supported. The instance manager disk service API version is increased from 1 to 2.

#### Engine (`longhorn/longhorn-engine`)

No RPC of the engine, the replica, the sync agent, or the instance manager proxy changes.

- The engine controller and the replica take the method as a new start parameter, `--data-erase-method`. Without it, or with an empty value, they behave as today.
- The manager passes the parameter whenever the method is not empty, without checking the engine image. An engine image that does not know the parameter refuses to start the process with an unknown parameter error, so a volume with a method on such an image fails to attach instead of running without secure erase. No version gate is added.
- New optional field `DataEraseMethod` in the replica's `volume.meta`, written by the replica from its start parameter. Nothing in this proposal reads the field; it is there for the orphaned replica data follow-up.

## Design

### Implementation Overview

#### Erase primitive (`longhorn/sparse-tools`)

One implementation overwrites a file; only the erase queue worker uses it.

- `EraseFile(file, method)` overwrites the allocated extents of an open file.
- The caller passes an open file. The primitive reopens the same inode through `/proc/self/fd/<fd>` with `O_WRONLY|O_DIRECT` and leaves the caller's descriptor unchanged. The allocated extents are listed with FIEMAP, which sparse-tools already uses with the sync flag, so delayed allocations have extents. Holes and unwritten (preallocated, never written) extents are skipped: they hold no volume data, and overwriting a hole would allocate new blocks and could fill the disk.
- The overwrite never writes beyond the end of the file. Offsets and lengths are aligned to 4 KiB, the direct I/O alignment sparse-tools uses throughout. If a part that holds allocated data cannot be written at that alignment, it is left as it is and the overwrite is reported as incomplete.
- Each pass writes its pattern over the extents in chunks of at most 1 MiB and ends with `fdatasync`. `zero` is one pass of `0x00`. `three-pass` is `0x00`, then `0xFF`, then random data.
- The primitive reports its progress to the caller while it writes, returns the number of bytes written, summed over all passes (a three-pass overwrite of 4 MiB reports 12 MiB), and whether it completed. A write error is returned with the bytes written so far, after a best-effort sync of what was written. It never releases anything itself.

Only replica image files are overwritten. Metadata files (`*.meta`, `volume.meta`, `revision.counter`, `*.checksum`) hold no volume data and are removed as today.

#### Keeping the overwrite away from data in use

An overwrite changes the content of an inode in place. Today a file can be unlinked while something else still has it open, and that reader finishes with the old content. With an overwrite it would read the pattern instead. The design keeps an overwrite away from data in use in three ways: the replica never overwrites anything itself, the instance manager checks the link count and the open descriptors of a queued file right before it overwrites it, and a file that stays in use is never overwritten in part, because a volume with a method performs no range release.

**A file that still has another name is never overwritten.** One inode can have two names: when a snapshot is created, the head file is linked under the new snapshot name and the head name is removed afterwards; and when a coalesce replaces the child, the merged file is linked under the child's name and its own name is removed afterwards. If such an operation is interrupted, both names can stay. As long as an inode has more than one link, some replica may still use it under the other name, also when no process has it open, for example while the volume is detached. The instance manager therefore overwrites a queued file only when its inode has one link. The replica does not look at the link count when it queues a file.

**Whole files go to the erase queue.** The erase queue of a disk is the directory `<disk path>/erase`, next to `<disk path>/replicas` and on the same filesystem, so that a file is moved into it with a rename. A queued file has the path `erase/<replica data directory name>/<method>/<name>`, where the name is a new UUIDv7, so that names sort by the time they were queued. The path is all the instance manager needs to know: which replica the file belonged to and which method to use.

A running replica lets go of a replica image file at three points: when a purge removes a leaf snapshot, when a coalesce replaces the child, and when a revert removes the old head. With a method, at these three points and nowhere else, the replica moves the file into the queue instead of removing it:

1. It creates the queue directory if it does not exist, logs the move, and renames the file into the queue. It does not look at the link count and does not check for readers.
2. If the file cannot be moved, the replica removes it as today and records an unerased release.

A coalesce keeps today's sequence, and only its first step changes. Today the replica removes the child's file, links the merged file under the child's name, and removes the merged file's own name. With a method it moves the child's file into the queue instead of removing it. The name that the last step removes is the second name of the merged file, not a data release, and is removed as today.

For the replica a queued file is deleted: it is no longer part of the replica's disk chain or metadata, and nothing opens it by name again. The replica does not overwrite it.

Other paths that remove replica image files are not data releases covered by this proposal and are unchanged: removing the old head name after creating a snapshot (the inode lives on as the snapshot), removing the merged file's own name after a coalesce, rollback of a failed snapshot creation, and the removal of extra files when a rebuild prepares a reused directory.

**The instance manager overwrites a queued file only when nobody uses it.** A file can enter the queue while it is still open: the replica's own disk chain still reads the old child until it has reopened the chain on the merged file, and a backup, an export, a rebuild file send, or a snapshot hash that started earlier keeps its descriptors until it ends. Before it overwrites a queued file, the instance manager therefore requires both of the following:

- the inode has one link. A queued name of an inode with more than one link is not a data release, because the data is still reachable under another name: the instance manager removes that queued name and overwrites nothing. [Snapshot purge](#snapshot-purge-longhornlonghorn-engine) shows how such a name can get into the queue;
- a write lease (`fcntl` with `F_SETLEASE` and `F_WRLCK`) can be taken on the file. The kernel grants it only when no other descriptor of the inode is open, whichever process or pod holds it, so the check does not depend on what an instance manager can see of other processes. It is also what keeps two instance managers that work on the same disk off the same file.

A reader in progress therefore delays the overwrite; it does not cancel it. If the filesystem does not support leases, the instance manager cannot tell whether the file is in use: it removes the file without overwriting it and records an unerased release.

**No range release.** A filesystem trim and the pruning of a snapshot punch holes in a file that stays in use. Such a file is always open, so the two checks above cannot be applied to it, and the hole has to be punched during the operation, so it cannot wait in a queue either. An overwrite in place would have to guess whether a backup, an export, a rebuild, or a snapshot hash reads the file at that moment. A volume with a method therefore does not trim and does not prune; see [Filesystem trim and prune](#filesystem-trim-and-prune).

#### Erase queue (`longhorn/longhorn-instance-manager`, `longhorn/longhorn-manager`)

The instance manager processes the erase queue of each disk it has been assigned through `DiskEraseQueueSync`. For one disk it handles one file at a time, in the order of the file names:

1. It checks the two conditions above. A file whose inode has more than one link loses its queued name and is not overwritten. A file that is still open is noted as waiting and tried again in a later round.
2. It logs the start, overwrites the file with the method named in its path, logs the result with the bytes written and the duration, and removes the file. While it overwrites it logs, once a minute, the bytes done and to do in the queue of the disk, the write rate, and an estimate of the time left.
3. If the overwrite fails, or the method in the path is not known, it removes the file anyway, logs an unerased release, and adds the failure, with its time, to the failure list.
4. It removes a directory `erase/<replica data directory name>` that is empty when it runs no replica process for that directory. A replica that still exists creates the directory again when it needs it.

The instance manager keeps the state of a disk's queue in a status file, `erase/status.json`: the file being overwritten and its progress, the files that wait and why, the failure list, and the time of the last `DiskEraseQueueSync` call. The status file lets a restarted instance manager, or another one that takes the disk over, report where the queue stands; the queued files themselves are the only state that is needed to continue. A file whose overwrite was interrupted is overwritten again from the start.

In the manager, an erase queue monitor, modelled on the disk monitor of the node controller, calls `DiskEraseQueueSync` on the node's default v1 instance manager every 30 seconds with the filesystem-type disks of the node, and the instance manager controller writes the result to `InstanceManager.status.eraseQueue`. Only the default instance manager of a node is assigned; an older instance manager that is still running for existing processes is not called and has no erase queue support. After a later upgrade two instance managers that both support the queue can be assigned in turn; the first stops 5 minutes after its last call, and until then the write lease keeps them off the same file. The 30 seconds and the 5 minutes are estimates.

Failures reach the manager through the same call. Each failure carries the time, on the instance manager's clock, at which it was recorded, and the reply carries the time of the previous call. The manager raises a Warning event for every failure that is newer than the previous call, so it needs no memory of its own and does not repeat an event after a restart or an owner change. The instance manager drops a failure from the list at the call after the one that returned it.

Nothing waits for the erase queue: not the deletion of a Replica, a Volume, or an InstanceManager resource, and not the removal of a disk from a node. Files that are still queued when an instance manager stops are continued by the next instance manager that is assigned the disk.

#### Setting and distributing the method (`longhorn/longhorn-manager`)

- A volume gets its method when it is created: from the StorageClass parameter or the create input, or, when neither is given, from the global setting. The webhook rejects any later change. The volume controller copies the method to the specs of the volume's engines and replicas when it creates them.
- For a v2 volume the method is always empty.
- When the manager starts an engine or a replica process, it adds `--data-erase-method` with the value from the Engine or Replica spec to the process arguments whenever that value is not empty. It does not check the engine image first. A replica that a rebuild adds, and the processes of a live engine upgrade, get it the same way.
- Replica deletion: the replica controller uses `Replica.spec.dataEraseMethod` when it moves the replica image files into the erase queue.
- Snapshot purge and revert need nothing from the manager: the replica that lets go of a file knows its method. This also holds for a purge or a revert that Longhorn starts internally, for example as part of a backup restore or a clone, and for one started from the engine command line.
- The manager rejects the trim action for a volume with a method, and the recurring `filesystem-trim` job skips such a volume and logs it.

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

#### Snapshot purge (`longhorn/longhorn-engine`)

A purge handles a removed snapshot in one of three ways, depending on where it is in the snapshot chain.

- Remove (the snapshot is a leaf): the replica process moves the snapshot file into the erase queue.
- Coalesce and replace (the snapshot has one child that is not the head): the sync agent copies the child's data into the snapshot file, as today; data of the removed snapshot that the child shadowed is overwritten in place by that copy. The replica process then replaces the child with the merged file as today, except that it moves the old child file into the erase queue instead of removing it, and reopens its disk chain on the merged file. The instance manager overwrites the old child once the replica and every other reader have closed it.
- Prune (the snapshot is directly under the head): today the sync agent punches the ranges of the snapshot that the head shadows. With a method it does nothing; see [Filesystem trim and prune](#filesystem-trim-and-prune).

Leaf removal and coalesce take as long as they do today, and their requests keep their timeouts. Purge progress reporting is unchanged.

The coalesce of a removed snapshot `A` with its child `B`, with a method, step by step. `P` is the inode of `A`'s file and `C` the inode of `B`'s file; the columns show which inode each name refers to after the step.

| Step | Done by | `volume-snap-A.img` | `volume-snap-B.img` | Erase queue |
| --- | --- | --- | --- | --- |
| Start | | `P` | `C` | |
| 1. Copy `B`'s data into `A`'s file | sync agent | `P`, now merged | `C` | |
| 2. Move `B`'s file into the erase queue (today: remove it) | replica | `P` | none | `C` |
| 3. Link `A`'s file under `B`'s name | replica | `P` | `P` | `C` |
| 4. Remove `A`'s name and reopen the disk chain on `B`'s name | replica | none | `P` | `C` |
| 5. Overwrite `C` and remove it, once it has one link and nobody has it open | instance manager | none | `P` | empty |

Only step 2 differs from today, and step 5 is new. Between steps 2 and 3 `B`'s name does not exist, as today. Between steps 3 and 4 the inode `P` has two names; the name that step 4 removes is not a data release.

If the replica process ends between steps 3 and 4, both names stay and refer to `P`. A later purge repeats the coalesce: its step 2 moves `volume-snap-B.img`, now a name of `P`, into the erase queue, and after its step 4 `P` is named by `volume-snap-B.img` and by a queue entry. That queue entry is a second name of a file that is in use. This is the case the link count check exists for: the instance manager finds more than one link, removes the queued name without overwriting anything, and nothing is released. The open descriptor check alone would not catch it, because nobody has the file open while the volume is detached.

#### Snapshot revert

Revert creates a new head and removes the old one. With a method, the replica process moves the old head into the erase queue instead of removing it. The revert takes as long as it does today. A volume can be detached right after the revert; the old head stays in the queue until it has been overwritten.

#### Filesystem trim and prune

A volume with a method performs neither of the two range releases.

- Trim. An unmap comes from the workload through the volume frontend, not from the manager, so the engine has to deal with it. An engine controller that was started with a method does not pass an unmap on to its replicas: it does nothing and reports success, as it does today for an unmap that arrives while a replica is rebuilding. The request is not an error, so a filesystem mounted with the `discard` option keeps working. The blocks stay in the volume head; the filesystem in the volume reuses them for new data.
- Prune. A sync agent whose replica was started with a method skips the prune of a snapshot that is directly under the head. The snapshot stays marked as removed with all of its data, as a removed snapshot under the head did before Longhorn pruned. When a later snapshot has been taken, the next purge can coalesce it, and its file goes through the erase queue then.

Nothing is logged as an unerased release for either, because nothing is released. The cost is space: the replicas of the volume do not shrink.

Without a method both paths are unchanged.

#### Recording unerased releases

Every unerased release is written to the log of the component that observed it, with the operation, the replica, the file, and the reason. The log is the complete record.

An overwrite is not expected to fail, so the event only has to tell the operator to look at the log. The manager raises a Warning event with the reason `UnerasedRelease`, through the event recorder that Longhorn uses elsewhere, when it learns of an unerased release:

- Replica deletion: when a replica image file cannot be moved into the erase queue, and when the replica's node or disk is unavailable. The event is raised on the Volume, or on the Replica when the Volume is not found.
- Erase queue: for each failure that `DiskEraseQueueSync` returns and that is newer than the previous call. The event is raised on the Volume of the replica that the file belonged to, or on the Node when that replica or volume no longer exists.

A replica process that cannot move a file into the erase queue during a purge or a revert removes it as today and logs an unerased release. No request of the engine carries a result for this, so the replica log is its only record.

A file that waits in the erase queue is not an unerased release. It is shown in `InstanceManager.status.eraseQueue` and, when it waits because it is still open, in the status file of the queue.

Each overwrite also logs its start and its result with the method, the number of bytes overwritten, and the duration.

#### Failure handling summary

| Situation | Behavior |
| --- | --- |
| Overwrite of a queued file returns an error (for example I/O error, no space) | File removed; unerased release recorded; not retried |
| Queued file is still open by a process | File waits in the queue; shown in the queue status; not an unerased release |
| Queued file has another name (its inode has more than one link) | The queued name is removed; nothing is overwritten and nothing is released |
| Filesystem of the disk does not support leases | Queued file removed without overwrite; unerased release recorded |
| Disk is slow | Queued files wait; no time limit; no operation waits for them |
| Instance manager or node restarts during the overwrite of a queued file | The file is overwritten again from the start by the next instance manager that is assigned the disk |
| No running v1 instance manager on the node | Queued files wait until one is assigned the disk |
| Replica cannot move a file into the erase queue during a purge or a revert | Removed as today; unerased release in the replica log only |
| Manager cannot move a file into the erase queue during a replica deletion | Directory removed as today; unerased release recorded |
| Replica's node or disk is unavailable at removal | Finalizer released as today; data stays; unerased release recorded |
| Replica directory is referred to by another Replica resource that is not being deleted | Nothing moved and nothing removed until the last one is deleted |
| Disk is removed from Longhorn, or Longhorn is downgraded, while files are queued | Files stay on the disk; the operator overwrites and removes them by hand |
| Unmap reaches an engine that has a method | Ignored; success reported; nothing released |
| Snapshot directly under the head is purged on a volume that has a method | Not pruned; kept until a later purge can coalesce it |
| Manager stops between reading a failure and raising the event | No event; the log entry is the only trace |
| Volume with a method runs on an engine image that does not know the start parameter | The engine and replica processes fail to start with an unknown parameter error; the volume cannot be attached |

### Test plan

#### Unit tests

- Erase primitive: only allocated extents are written; holes stay holes and the allocated size does not grow; each method leaves the expected pattern; progress is reported while writing; a write error is reported with the bytes written.
- Queueing in the replica: with a method, a leaf removal, the replacement of the child in a coalesce, and a revert rename the file into `erase/<replica data directory name>/<method>/`; the name that a coalesce removes from the merged file is not queued; a file that cannot be moved is removed and logged; without a method nothing is queued and no `erase` directory is created.
- No range release: an engine started with a method reports success for an unmap and leaves every replica file unchanged; a sync agent whose replica has a method leaves a snapshot under the head unpruned, and a later purge coalesces it.
- Erase queue worker: a file with one link and no other open descriptor is overwritten and removed; a file that another process holds open is left and reported as waiting, and is overwritten once the descriptor is closed; a queued name of an inode with a second link is removed without an overwrite, and the content stays readable through the other name; two queued names of one inode end with one overwrite; a failed overwrite removes the file and adds a failure; an interrupted overwrite is repeated from the start; the worker stops 5 minutes after the last call; an empty replica directory in the queue is removed.
- Failure delivery: the manager raises one Warning event per failure that is newer than the previous call and none for older ones, also after a manager restart.
- Method: a volume created without a method gets the global setting; a StorageClass parameter, also an empty one, wins over the setting; changing the setting does not change an existing volume; a change of the method of an existing volume, engine, or replica is rejected; v2 volume.
- Start parameter: the manager adds it for a non-empty method and not for an empty one.
- Trim action and recurring trim job on a volume with a method: rejected and skipped.

Crash and error cases are covered by Go tests in the repositories, because the production binaries have no fault-injection hook and none is added.

#### Engine integration tests

Run on a replica directory on a dedicated loop device. The erase queue worker is not part of these tests: a whole-file release is checked by what is in the erase queue, and the overwrite of queued files is checked in the instance manager's tests and end to end. For each method:

- create a snapshot: the snapshot content is intact after the old head name is removed, and nothing is queued;
- remove a leaf snapshot, coalesce a snapshot, revert: the released file is in the erase queue under the right replica and method with its content intact, and the volume and the kept snapshots read back unchanged;
- a backup, an export, a rebuild file send, and a snapshot hash in progress on the replica while a snapshot is removed or coalesced: the file is queued and the reader finishes with the old content;
- purge with the removed snapshot directly under the head: nothing is punched and nothing is queued; after another snapshot the next purge coalesces it and the old child is queued;
- unmap: success is reported, the allocated size of the head does not change, and the data reads back unchanged;
- rebuild preparation that removes extra files in a reused directory: nothing is queued and nothing is recorded;
- `volume.meta` holds the method.

#### Integration and end-to-end tests

- Volume deletion with each method: the Volume and Replica resources are gone without waiting for the overwrite, `InstanceManager.status.eraseQueue` shows the files and then becomes empty, and after that the marker written to the volume cannot be found on the disk of any replica node.
- Replica deletion and eviction with a method.
- Snapshot delete and purge, and a snapshot revert followed at once by a detach: the marker in the released files is gone once the queue is empty.
- `fstrim` on a volume with a method, and the recurring `filesystem-trim` job: nothing is released, the actual size does not shrink, and the data deleted in the filesystem is gone from the node disks after the volume is deleted.
- A backup that is still running when the snapshot it reads is purged: the backup is intact, and the released file is overwritten after the backup ends.
- StorageClass parameter and global setting, including a StorageClass with an empty parameter while the setting has a method; an attempt to change the method of a volume is rejected.
- Volume deletion while one replica node is down: the volume is deleted, a Warning event and a log entry name the replica that was not overwritten, and its directory later appears as orphaned replica data.
- Replica deletion while the instance manager on the node is not running: the directory is removed, the files wait in the erase queue, and they are overwritten after the instance manager is running again.
- Instance manager restart in the middle of an overwrite: the file is overwritten again and removed.
- Live engine upgrade and live migration with a method: the new processes have the method; deleting the active Replica resource while an inactive one refers to the same directory neither moves nor removes anything; the files are queued and the directory is removed with the last Replica resource.
- Backup restore and clone into a volume with a method: the purges and reverts they run queue their files.
- The write lease check on the filesystems Longhorn supports for replica disks (ext4, XFS) and on the oldest supported kernel, with the reader in another pod.
- Regression: without a method, deletion, purge, revert, and trim behave and perform as before, and no `erase` directory is created.

### Upgrade strategy

- The setting defaults to an empty value, and existing volumes, engines, and replicas have an empty method, which means no overwrite. Nothing changes after an upgrade, and no resource has to be changed by the upgrade.
- An existing volume cannot get a method.
- A volume with a method needs an engine image that knows the start parameter, which the default engine image of the release does. On an older engine image its processes fail to start; see [Limitations](#limitations). Replica deletion is done by the manager and does not depend on the engine image.
- A replica moves files into the erase queue only when it was started with a method, and only a manager with this feature starts it that way. Such a manager runs the node's default instance manager with this feature and assigns it the disks, so a queued file always has an instance manager that processes it.
- `volume.meta` gains an optional field. An older engine ignores it when reading. If an older engine rewrites `volume.meta`, the field is dropped.
- No data migration is needed.
- A downgrade is not supported, as for Longhorn in general. Files that are queued at that time stay on the disk.

## Note

- The decision that secure erase never blocks a data release was made to avoid a deadlock in which space cannot be reclaimed, for example on a full or failing disk. On a filesystem that overwrites in place an overwrite of allocated extents needs no new space, but on copy-on-write or thin-provisioned storage it can.
- Prior art: OpenStack Cinder offers `volume_clear` (`zero`) for thick LVM volumes only and removed its `shred` option in 2016. Its security documentation states that writing over a volume "does not ensure that the data will be actually erased on the physical disks, as the storage solution could be doing copy-on-write or other optimizations".
- The orphaned replica data follow-up (https://github.com/longhorn/longhorn/issues/14626) reads the method from `volume.meta` and falls back to the global setting when the record is missing.
- When the v2 data engine adds its key to `data-erase-method`, the upgrade has to add that key to the stored setting value of existing clusters.
- An earlier revision of this proposal overwrote whole files inside the operation, after removing the file name. It was replaced by the erase queue because a snapshot revert, a purge, and a replica deletion then had to wait for the overwrite, and because a process that ended during the overwrite released the rest of the file without overwriting it.
- The write lease was chosen over looking at `/proc` because an instance manager cannot be assumed to see the processes of other pods, and over a reader check before queueing because a reader in progress would then cancel the overwrite instead of delaying it.
- An earlier revision also covered filesystem trim and the pruning of a snapshot by overwriting each range in place before its hole was punched. That needed time budgets against the engine-replica and SCSI timeouts, a split of each unmap into segments, a change to the engine's locking so that other I/O could run in between, and a check for known readers that could only skip the overwrite. It was replaced by not performing range releases on a volume with a method.
- Range releases could go through the erase queue as well on a filesystem that can move a range of blocks from one file to another without copying (reflink on XFS). That is left to a later proposal, because ext4 cannot do it.
- The method is fixed at creation so that the engine and replica processes can be told at start and no request has to carry it, and so that a volume with a method has never performed a range release.
