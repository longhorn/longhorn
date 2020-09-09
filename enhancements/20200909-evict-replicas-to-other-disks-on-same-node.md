# Evict Replicas to Other Disks on the same Node

## Summary
This enhancement is for nodes with multiple disks and user prefer to evict a disk and relocate the replicas to other disks on the same node.

### Related Issues

https://github.com/longhorn/longhorn/issues/1400

## Motivation

### Goals
Allow user to evict replicas on a disk to other disks on the same node.

### Non-goals [optional]

What is out of scope for this enhancement? Listing non-goals helps to focus discussion and make progress.

## Proposal

This is where we get down to the nitty gritty of what the proposal actually is.

### User Stories
Cases need to think about:

1. One of the main reason taking this as a separate feature or enhancement is this behavior is not align with our current scheduling policy. Currently with 'Node level soft anti-affinity' disabled, Longhorn scheduler alway try to schedule new replicas on different nodes. However in this case, Longhorn need to schedule it on the same node but different disks. Need to think about the consequences about it.

2. On a multi disks node, user prefer to evict a disk, and reloate the replicas on the other disks on the same node. E.g. 3 nodes cluster (node-1,2,3), and node-1 has disk-1,2. User would like to evict node-1 disk-1, the replicas on disk-1 should be related to disk-2 on node-1. Since there is no extra node for scheduling the replica, current Longhorn will display 'Failed to Schedule' error message with 'Node level soft anti-affinity' disabled.

3. One good thing about scheduling the replica on the same node on the other disk is this can avoid extra data-locality operation. E.g. a volume is attached to node-1, and has replicas on node-1,2,3. And node-1 has disk-1,2. Since the engine is running on node-1. During the eviction for node-1 disk-1, if the scheduler can schedule the new replica on node-1 disk-2, this will avoid the extra data-locality operation (if schedue the replica on node-4, and data-locality finds it needs one replica on node-1, it will trigger a rebuild on node-1 disk-2, once it success, it will cleanup one replica from node-2 or node-3 or node-4).

4. Need to improve Longhorn rebuild part, if Longhorn scheduler can schedule the new replica on node-1 disk-2, Longhorn should use the local replica to rebuild the local replica which is to use the replicas node-1 disk-1 to build the replicas for node-1 disk-2.

#### Story 1
#### Story 2

### User Experience In Detail

Detail what user need to do to use this enhancement. Include as much detail as possible so that people can understand the "how" of the system. The goal here is to make this feel real for users without getting bogged down.

### API changes

## Design

### Implementation Overview

Overview on how the enhancement will be implemented.

### Test plan

Integration test plan.

For engine enhancement, also requires engine integration test plan.

### Upgrade strategy

Anything that requires if user want to upgrade to this enhancement

## Note [optional]

Additional nodes.
