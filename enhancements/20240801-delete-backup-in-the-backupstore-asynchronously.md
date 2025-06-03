# Delete backup in the backupstore asynchronously

## Summary

When deleting the backup, Longhorn deletes the backup in the backupstore using binary command synchrounosly. During the backup deletion, Longhorn creates a deletion lock in the backupstore to prevent other backups' creation. Backup creation fails immediately without retrying when encountering the deletion lock. This confuses and annoys users.

This feature refactors the code to execute the backup deletion command asynchronously and introduces a new `Deleting` state to notify other backups to wait until the deletion process is complete.

This feature aims to prevent creation failures caused by deletion lock issues.

### Related Issues

- https://github.com/longhorn/longhorn/issues/8742

## Motivation

### Goals

- Delete the backup in the backupstore asynchronously.
- When the Backup is being deleted, the state would be `Deleting`
- Creation of other backups should be delayed until the backup deletion is complete.

## Design

### Implementation Overview

#### Normal case

To make deletion asynchronously, we can simply run the command in another go routine.

Then we periodically check if the backup still exists in the backupstore before removing the finalizer.

However, since the command runs in another go routine, we need to handle the scenario of command failure.

Thus, we introduce an in-memory map as share memory for the go routine to notify the controller.

### Error handling

```
type DeletingStatus struct {
	State        longhorn.BackupState
	ErrorMessage string
}

type BackupController struct {
    ...
    // Use to track the result of the deletion command.
    // Also used to track if controller crashes after the deletion command is triggered.
    deletingMapLock       *sync.Mutex
    inProgressDeletingMap map[string]*DeletingStatus
    ...
}
```

Go routine can add the error message to the `inProgressDeletingMap` if the command fails. Controller then can retry the command in the next reconciliation.

### Deleting/Error State with BackOff

When a Backup is being deleted, indicated by the `DeletionTimestamp` in the CR, its state transitions should follow the diagram below.

```
# Normal Case
Completed => Deleting 
=> finalizer removed (CR isgone)

# Command failure Case
Completed => Deleting 
=> Error (found the error message in the map) 
=> Deleting (Retry the command) => finalizer removed (CR isgone)
```

Controller only triggers the deletion command if the state is not `Deleting`, and it updates the Backup's state to `Deleting` right after.

To prevent the deletion command from being executed too frequently and to avoid rapid changes in status between `Deleting` and `Error`, **we implement a backoff strategy** with an initial delay of 10 seconds and a maximum delay of 1 minute before triggering the deletion command.

### Controller Crashes

If controller crashes, the command doesn't finish and the  map is cleaned up, the Backup could stuck in `Deleting` state forever.
In this case, controller won't be able to aware the command is not running and won't even retry the command since the state is `Deleting`.
Moreover, controller won't be able to dinstinguish the case of command not running or command is still running when there is no record in the map. 

Thus, we add the record with `state=Deleting` when the command is triggered.

```
type DeletingStatus struct {
	State        longhorn.BackupState
	ErrorMessage string
}

type BackupController struct {
    ...
    // Use to track the result of the deletion command.
    // Also used to track if controller crashes after the deletion command is triggered.
    deletingMapLock       *sync.Mutex
    inProgressDeletingMap map[string]*DeletingStatus
    ...
}
```

**Controller further checks if there is a record in the map** when controller finds the Backup's state is `Deleting` and backup still exists in the backupstore. 

If there is no record in the map, it may indicate that the controller has crashed. In this case, the controller will update the status to `Error` and retry the command in the next reconciliation.

The state transition should follow the diagram below

```
# Command failure Case
Completed => Deleting 
=> Error (found the error message in the map) 
=> Deleting (Retry the command) => finalizer removed (CR isgone)

# Controller crashes
Completed => Deleting 
=> Error (failed to find the record in the map)
=> Deleting (Retry the command) => finalizer removed (CR isgone)
```

### Test plan

You can use following commands to monitor the status.
```
$ watch -n 1 "kubectl get lhb -n longhorn-system -oyaml | grep -A 20 "status:""

$ watch -n 1 kubectl get lhb -n longhorn-system
```

#### Normal Case

1. Create a Volume
2. Write small data and then create a BackupA
3. Write large data (~2G) and then create a BackupB
4. Write small data and then create a Snapshot
5. Delete the BackupB(large data), at the same time, create a BackupC from the Snapshot(you can click from UI)
6. BackupC will be in `Pending` state with message (`waiting for backupB to be deleted`)
7. After BackupB is deleted, BackupC should be in progress.

#### Error Case (use nfs)

1. Create a Volume
2. Write some data and then create a BackupA
3. Write some data and then create a sSnapshot
4. Exec into the backupstore pod and make the backup.cfg immutable
    ```
    $ chattr +i backups/backup_backup-5640dfd33a054f98.cfg`
    ```
5. Delete the BackupA, at the same time, create a BackupB from the Snapshot(you can click from UI)
6. BackupA will be in `Deleting` and `Error` state repeatedly to retry the deletion. When in `Error` state, it shows error message related to permission 
7. BackupB will be `InProgress` when BackupA is in `Error` state. BackupB should be complete after awhile.
8. Remove the immutable, after a while, the BackupA should be in `Deleting` again and should be deleted successfully.

#### Controller Crashes Case (use nfs)

1. Create a Volume
2. Write some data and then create a BackupA
3. Exec into the backupstore pod and make the backup.cfg immutable, example
    ```
    $ chattr +i backups/backup_backup-5640dfd33a054f98.cfg`
    ```
5. Delete the BackupA
6. BackupA will be in `Deleting` and `Error` state repeatedly to retry the deletion. When in `Error` state, it shows error message related to permission
7. When the BackupA is in `Deleting` state, delete the longhorn manager pod directly. (you can find the one doing the deleting with `Backup.Status.OwnerID`)
8. After the longhorn manager pod is recreated, the BackupA should turn into `Error` state with message `No deletion in progress record, retry the deletion command`
9. Then after a while the BackupA should be in `Deleting` again and should be deleted successfully after remove the immutable.

### Upgrade strategy

No Need

## Note [optional]

Additional notes.