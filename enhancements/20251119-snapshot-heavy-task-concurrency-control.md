# Snapshot Heavy Task Concurrency Control

## Summary

This proposal introduces a new global setting, `snapshot-heavy-task-concurrent-limit`, which allows users to limit the number of concurrently running snapshot heavy tasks—specifically snapshot purge and snapshot clone operations for `v1`.

This proposal adds a centralized global concurrency limiter shared across all callers, including controllers, manual API calls, recurring jobs, and CR-based operations.

### Related Issues

https://github.com/longhorn/longhorn/issues/11635

## Motivation

Some snapshot operations (such as purge or clone) may trigger internal merge processes that temporarily consume extra disk space. Running many of these tasks concurrently increases the risk of disk exhaustion. A global concurrency limit helps prevent this by controlling how many heavy snapshot tasks can run at the same time.

### Goals

Introduce a centralized concurrency controller for snapshot heavy tasks.

### Non-goals

- Not intended to limit all snapshot-related actions (e.g., create, list).

- Not intended to limit general volume operations such as expansion, rebuild, or backup.

## Proposal

Introduce a new component: **SnapshotConcurrentLimiter**

This component:

- Tracks currently running snapshot heavy tasks (purge / clone).
- Enforces the global limit using the new setting.

The limiter collects real engine states (purging / cloning) and maintains a synchronized map of active tasks. If the number of active tasks ≥ limit, new tasks are rejected (or delayed by controllers).

## Design

### Implementation Overview

New Controller Component: `SnapshotConcurrentLimiter`
- Inspect real-time engine purge/clone status
- Reject new tasks when exceeding limit
- Allow forced bypass if needed

#### New Global Setting
```go
Name: snapshot-heavy-task-concurrent-limit
Type: int
Default: 5
Range: >= 0
Category: General
Description: Controls how many snapshot purge/clone operations can run concurrently.
```
### Test plan

1. Set `snapshot-heavy-task-concurrent-limit=1`
2. Set `disable-snapshot-purge=false`
3. Create and Attach a volume
4. IO
  - sudo ```dd if=/dev/urandom of=/dev/sdb bs=1G count=1 seek=0```
  - Take `snapshot 1`
  - sudo ```dd if=/dev/urandom of=/dev/sdb bs=1G count=20 seek=0``` 
  - Take `snapshot 2`
  - sudo ```dd if=/dev/urandom of=/dev/sdb bs=1G count=15 seek=10```
  - Take `snapshot 3`
5. Remove the snapshot `snapshot 2` -> trigger snapshot purge
6. During the snapshot deletion, try to execute snapshot purge manually

```
curl -X POST \
  'http://localhost:8080/v1/volumes/<volume-name>?action=snapshotPurge' \
  -H 'Accept: application/json'
```
it fails with an error: ```cannot start snapshot purge: concurrent snapshot purge limit reached```

7. Once the snapshot deletion is complete, execute the curl request again. It should succeed.

> If you want to increase the purging duration for testing, you can increase the IO workload in `snapshot 2` before triggering the purge operation.


### Upgrade strategy

`None`

## Note

### Known Limitation

When multiple SnapshotPurge operations are triggered at the same time (such as several CronJobs scheduled on the same interval), any request that exceeds the concurrency limit will be rejected. This can cause certain CronJobs to fail deterministically on every execution.

Users are recommended to:

- Increase the `snapshot-heavy-task-concurrent-limit` value, or
- Schedule snapshot purge CronJobs at different times so they don’t run together.