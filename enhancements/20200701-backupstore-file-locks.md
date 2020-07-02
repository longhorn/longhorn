# Backupstore File Locks

## Summary

This enhancement will address backup issues that are the result of concurrently running backup operations, 
by implementing a synchronisation solution that utilizes files on the backup store as Locks.

### Related Issues

https://github.com/longhorn/longhorn/issues/612
https://github.com/longhorn/longhorn/issues/1393
https://github.com/longhorn/longhorn/issues/1392
https://github.com/longhorn/backupstore/pull/37

## Motivation

### Goals

Identify and prevent backup issues caused as a result of concurrent backup operations.
Since it should be safe to do backup creation & backup restoration at the same time, 
we should allow these concurrent operations. 

## Proposal

The idea is to implement a locking mechanism that utilizes the backupstore, 
to prevent the following dangerous cases of concurrent operations.
1. prevent backup deletion during backup restoration
2. prevent backup deletion while a backup is in progress
3. prevent backup creation during backup deletion
4. prevent backup restoration during backup deletion

The locking solution shouldn't unnecessary block operations, so the following cases should be allowed.
1. allow backup creation during restoration
2. allow backup restoration during creation

The locking solution should have a maximum wait time for lock acquisition, 
which will fail the backup operation so that the user does not have to wait forever.

The locking solution should be self expiring, so that when a process dies unexpectedly, 
future processes are able to acquire the lock.

The locking solution should guarantee that only a single type of lock is active at a time.

The locking solution should allow a lock to be passed down into async running go routines.


### User Experience In Detail

Before this enhancement, it is possible to delete a backup while a backup restoration is in progress. 
This would lead to an unhealthy restoration volume.

After this enhancement, a backup deletion could only happen after the restoration has been completed.
This way the backupstore continues to contain all the necessary blocks that are required for the restoration.

After this enhancement, creation & restoration operations are mutually exclusive with backup deletion operations.

### API changes

## Design
### Implementation Overview

Conceptually the lock can be thought of as a **RW** lock, 
it includes a `Type` specifier where different types are mutually exclusive.

To allow the lock to be passed into async running go routines, we add a `count` field,
that keeps track of the current references to this lock. 

```go
type FileLock struct {
	Name         string
	Type         LockType
	Acquired     bool
	driver       BackupStoreDriver
	volume       string
	count        int32
	serverTime   time.Time
	refreshTimer *time.Ticker
}
```

To make the lock self expiring, we rely on `serverTime` updates which needs to be refreshed by a timer.
We chose a `LOCK_REFRESH_INTERVAL` of **60** seconds, each refresh cycle a locks `serverTime` will be updated.
A lock is considered expired once the current time is after a locks `serverTime` + `LOCK_MAX_WAIT_TIME` of **150** seconds.
Once a lock is expired any currently active attempts to acquire that lock will timeout.

```go
const (
	LOCKS_DIRECTORY       = "locks"
	LOCK_PREFIX           = "lock"
	LOCK_SUFFIX           = ".lck"
	LOCK_REFRESH_INTERVAL = time.Second * 60
	LOCK_MAX_WAIT_TIME    = time.Second * 150
	LOCK_CHECK_INTERVAL   = time.Second * 10
	LOCK_CHECK_WAIT_TIME  = time.Second * 2
)
```

Lock Usage
1. create a new lock instance via `lock := lock.New()`
2. call `lock.Lock()` which will block till the lock has been acquired and increment the lock reference count.
3. defer `lock.Unlock()` which will decrement the lock reference count and remove the lock once unreferenced.

To make sure the locks are **mutually exclusive**, we use the following process to acquire a lock.
1. create a lock file on the backupstore with a unique `Name`.
2. retrieve all lock files from the backupstore order them by `Acquired` then by `serverTime` 
   followed by `Name`
3. check if we can acquire the lock, we can only acquire if there is no unexpired(i) lock 
   of a different type(ii) that has priority(iii).
   1. Locks are self expiring, once the current time is after 
      `lock.serverTime + LOCK_MAX_WAIT_TIME` we no longer need to consider 
      this lock as valid.
   2. Backup & Restore Locks are mapped to compatible types while Delete
      Locks are mapped to a different type to be mutually exclusive with the
      others.
   3. Priority is based on the comparison order, where locks are compared by
      `lock.Acquired` then by `lock.serverTime` followed by `lock.Name`. Where
      acquired locks are always sorted before non acquired locks.
4. if lock acquisition times out, return err which will fail the backup operation.
5. once the lock is acquired, continuously refresh the lock (updates `lock.serverTime`) 
5. once the lock is acquired, it can be passed around by calling `lock.Lock()`
6. once the lock is no longer referenced, it will be removed from the backupstore.

It's very unlikely to run into lock collisions, since we use uniquely generated name for the lock filename.
In cases where two locks have the same `lock.serverTime`, we can rely on the `lock.Name` as a differentiator between 2 locks. 

### Test plan

A number of integration tests will need to be added for the `longhorn-engine` in order to test the changes in this proposal:
1. place an expired lock file into a backupstore, then verify that a new lock can be acquired.
2. place an active lock file of Type `Delete` into a backupstore, 
   then verify that backup/restore operations will trigger lock acquisition timeout.
3. place an active lock file of Type `Delete` into a backupstore, 
   then verify that a new `Delete` operation can acquire a lock.
4. place an active lock file of Type `Backup/Restore` into a backupstore, 
   then verify that delete operations will trigger lock acquisition timeout.
5. place an active lock file of Type `Backup/Restore` into a backupstore, 
   then verify that a new `Backup/Restore` operation can acquire a lock.   

### Upgrade strategy

No special upgrade strategy is necessary.
