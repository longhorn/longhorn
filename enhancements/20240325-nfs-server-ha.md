# Fast Failover for RWX Volume's NFS Server

## Summary

In Longhorn, a ReadWriteMany volume (and at some point, a ReadOnlyMany volume) is handled by an NFS server located within the share-manager pod.  It mounts an RWO volume in the usual way, and then provides export and locking capabilities on top of it, which multiple workload pods can mount and write safely.  There is only one share-manager pod for a volume, so if the node on which the pod is running fails, the responsible controller must notice and start a new pod on another node.  After it starts, client pods can re-connect and resume I/O.  But first, they negotiate with the new server about what their state should be, and there is a grace period in which writes are refused while waiting for any other possible clients to show up.

In a previous enhancement, [Dedicated Recovery Backend for RWX Volume's NFS Server](https://github.com/longhorn/longhorn/blob/master/enhancements/20220727-dedicated-recovery-backend-for-rwx-volume-nfs-server.md), Longhorn incorporated a recovery backend that can speed up that process and guarantee that all the former clients have been accounted for.  But a node failure still takes minutes to recover from, as noted in the [Longhorn docs](https://longhorn.io/docs/1.6.0/high-availability/node-failure/).

In this enhancement, a mechanism is proposed to quickly detect and respond to share-manager pod failure independently of the Kubernetes node failure sequence and timing.

### Related Issues

[https://github.com/longhorn/longhorn/issues/6205](https://github.com/longhorn/longhorn/issues/6205)

## Motivation

The main goal is to minimize downtime on RWX workloads.

In the current code, failure of a container in the share-manager pod or the pod itself is quickly handled.  It takes about 20 seconds to restore write access, of which about half is spent restarting the workload pods and letting them remount.  Longhorn's recovery backend has the ability to shorten the grace period wait when all clients are accounted for.

The big problem happens when the node with the share-manager pod fails or restarts.  Just the time it takes for the node to go `NotReady` - in Kubernetes, typically about 45 seconds - is already too long an outage for share-manager failover.  We intend to make the NFS client recovery time for a failure of the node running the share-manager pod to be just as quick as for simple pod failure.

### Goals

- Implement a fast failover mechanism that is not gated by Kubernetes' relatively slow detection and handling of node failure.  Recovery should be a matter of seconds rather than minutes.  
- Depending on NFS mount options, it should not require a restart of workload pods.  Specifically, "soft" or "softerr" mounts should not need it, although "hard" mounts do.
- Operation of the recovery backend will be unchanged.
- After the failure of the share-manager pod, the application on the client side’s IO operations will be stuck until the share-manager and NFS are recreated, but the interruption will be brief, within a specified limit of 20 seconds regardless of the cause.
- There will be only a single interruption for a failure.
- Changing Kubernetes behavior via `node-monitor-period` and `node-monitor-grace-period` values in the Kubelet should make no difference to RWX failover. The time to accomplish node NotReady processing and return to Ready state should be independent of RWX HA time.  

### Non-goals

Duplicate NFS servers running simultaneously, providing Active/Active or Active/Passive redundancy.  "True HA" with zero recovery time is a long-term desire but is extremely difficult to accomplish with NFS.  See the section on [Alternatives](#alternatives) below.  

## Proposal

Fast failover needs several pieces.

1. Quick detection of failure  
Use the Kubernetes `Lease` mechanism.  When an RWX volume is created, create the lease at the same time as the share-manager pod and service.  Just like the service, it will have the same name and lifetime as the volume itself.  The lease holder is not specified at the time of creation; it will be assigned when the pod is scheduled to a node and begins to run.  
This mimics Kubernetes' own internal mechanism for tracking node status, which is also lease-based.  Detection of an unresponsive server could also be done with a monitor that makes a recurring call to the server pod, but the lease has the advantage that it reflects the server's ability to make an API call, rather than the connectivity from an arbitrarily chosen monitor node.  
Longhorn will
    - Update the lease periodically from ShareManager pod.
    - Use a goroutine in the share-manager controller to schedule a check of the lease for expiration.

2. Quick removal of the failed/failing server  
If the lease is expired, we infer that the pod's node is dead and another controller needs to take over.  All other nodes will detect that.  Longhorn needs to pick one, and establish that choice so that multiple controllers don't all attempt to drive the recovery.  Longhorn will use the controller's `isResponsibleFor` method:  
    - If the lease is not expired, move on to normal handling.  
    - If it has, set the share-manager CR `Status.OwnerID` to this node, if another node hasn't already done so.  (We can tell by comparing the owner field to the lease holder.)  The new owner will act as an interim manager to do tear-down and recreation of the share manager pod.  It updates the CR and, if successful, then returns "true".
    - The new owner is logged, and then the reconcile can continue.  Mark the share-manager CR as error state and let it clean up the pod.  
    - In cleanup,  
        - Remember the old lease holder.  
        - Clear the lease.  
        - Delete the pod.  
        - If the node is down *OR* expired, do a force delete of the share-manager pod as well.  If it truly is down, this is the same as current code.  If it is not, then the first delete should have succeeded, but either way, even if the pod is still running, this will ensure that Kubernetes does not route service traffic to it.  Also, deletion allows reuse of the same standard pod name, avoiding one potential upgrade complication.
    - Other resources need to change ownership similarly.  Modify the usual rules to capture our suspicion that the expired node is dead:
        - Add a Condition named "Delinquent" to longhorn.node.io, set to "False" by default.  A node is set to Delinquent=true when a share manager lease for a pod on that node expires.  It is cleared by the node itself in node_controller when it starts operation again.
        - Change controller_manager's `IsNodeDownOrDeleted` to check `IsNodeDownOrDeletedOrDelinquent` for other RWX volume-related resources, as well as any resource-specific `isResponsibleFor` calls that don't use the base implementation.  

3. Quick creation of a replacement  
This is already a normal part of the Share Manager lifecycle.  But it does need an adjustment to avoid the former host, which Kubernetes will try to re-schedule to since Kubelet does not yet report it as down.  
    - Use the stored node identity, if found, to add a node anti-affinity into the existing set of selectors, tolerations, and affinities defined for share-manager pods.  Note that the node on which the pod is scheduled may not be the interim controller node, so ownership might change again.  
    - Including delinquency in the check for node status should allow the normal re-mount and new attachment creation to work as it does currently.

4. Avoid client workload pod restart  
Longhorn currently restarts the workload pods in volume controller when the share-manager pod restarts.  That may be necessary if the NFS mount is "hard", because the client can hang indefinitely if the server does not respond.  Clients will not hang if mounted as "soft" or "softerr".  (In either case, the client will retry I/O attempts to the unresponsive server and eventually return an error to the calling workload application.  The only difference is in the error returned: EIO or ETIMEDOUT.)  In that case, they will eventually reconnect to the new server and resume operation without having to restart the workload pod to kill the client process.  
    - Previous releases of Longhorn used "hard" NFS mounts as the default (and only) option.  That is likely why there is code to restart workloads unconditionally when the share manager pod is recreated.  Currently, Longhorn defaults to "softerr", but the user can override NFS mount options, so it can't be assumed.  Volume controller can Look at the storage class parameters or PV volumeAttributes to decide whether a restart is necessary.
    - This would also be affected by the `node-down-pod-deletion-policy` handler in kubernetes_pod_controller.

5. Shorten the recovery grace period  
Speak for the dead node's client, if any.  Without this step, workers may still be blocked for an NFS grace period after re-connection is possible, waiting for other clients to re-establish state with the new server.  The grace period is usually configured to 90 seconds.  If all workload pods are alive, it does not take the full grace period, but if a workload pod was on the failed node, it will not be able to clear its state.  Knowing its node ID, Longhorn should be able to send a recovery message on its behalf, avoiding the grace period timeout.

### User Experience

The changes should not alter the use of RWX volumes.  There will be no observable difference until a node failure occurs (for whatever reason - Kubernetes upgrade, eviction, injected error).

    *TODO - Put a time diagram of durations and state here.*

## Design

### Implementation Overview

- **share-manager**
    
    Add a constant, `share-manager-renew-interval`.  It should be often enough to detect failure quickly, but not so often that it overwhelms the network and API server with traffic.  Hard-code this to 3 seconds.

    Add a goroutine to keep the lease from expiring.  Every `share-manager-renew-interval`, get the lease for the RWX volume (name it the same as the volume name) and update its `lease.spec.renewTime` to "now".  If the lease cannot be found, take no action.
    
- **longhorn-manager**
    
    - setting
    Add a Boolean setting, `enable-share-manager-fast-failover`.  Because this is an experimental feature to begin with, default it to false.
    
    - share_manager_controller  
    Add code to create a lease at the same time as the service.  Set `lease.spec.leaseDurationSeconds` to a little over two lease renewal periods.  
    At creation, also set `lease.spec.acquireTime` and `lease.spec.renewTime` to "now".  
    Every sync, check the lease for each share-manager.  If acquireTime == renewTime, assume that the share-manager image does not know to update the lease, so take no action.  Otherwise, if status is StateRunning and renewTime + timeout is less than "now", mark the share-manager CR as `Error` to drive deletion and re-creation.  
    Add logic to `isResponsibleFor` to check for staleness first and take over ownership.
    Create or set the node's `Delinquent` condition to `true` and event it.
    Remove the admission webhook selector label from the delinquent node's longhorn-manager pod.
    Add staleness check to `cleanupShareManagerPod()` when deciding to force-delete.
    Add an anti-affinity to pod manifest creation to avoid the previous owner node.

    - node_controller  
    Add code to set `Delinquent` condition to `false` at startup.  Likewise, add back the admission webhook selector label.

    - datastore/longhorn  
    Revise `IsNodeDownOrDeleted` to `IsNodeDownOrDeletedOrDelinquent` (or add a new function) and check the node's condition.
    Also add the condition to `IsNodeSchedulable` (which is only called by share_manager_controller, and affects unmount/remount).

    - controller_manager  
    Revise `isControllerResponsibleFor` to use `IsNodeDownOrDeletedOrDelinquent`.  Also make that change in any controller's `isResponsibleFor` code that does more than use the base call.

    - volume_controller  
    Add logic in `ReconcileShareManagerState()` to check the volume's storageclass for NFS mount options.  If `parameters.nfsOptions` contains "hard", then request remount to force a restart as in current code.  Otherwise, skip that (but make a similar event).  This code is aware that the default option is not to hard mount NFS.
    
- **nfs-ganesha (user-space NFS server)**

    No changes.
    
### Proof of Concept
    
A lot of trial failovers have been executed, to test various aspects of the implementation.  In a run with the changes listed, including "global" application of delinquency check, running on a 3-worker node cluster with just a single, soft-mounted RWX volume (nginx RWX example) and forcing a node restart with `shutdown -r now` on the node console, Longhorn could destroy and re-create the share-manager pod in 16 seconds, as shown by the time for the new owner to take over and resume refreshing the lease.  Note that for the lease to be refreshed, the pod must be running, implying that the volume is mounted.  
The workload pods themselves failed to be able to write for about 2 minutes, but most of that time was waiting for the client grace period to elapse.  
Although there is a lot of work to do for production-ready quality, that gives an idea of the possible scale of improvement.

### Risks and Mitigation

- **Something goes not as expected**
For all code paths, the fallback is to resort to the normal "not ready" path.  So at worst, the failover time is the same as previous releases.  Every effort should be made to ensure that the logging is clear and sufficient to tell why an expedited failover was not accomplished in such cases.

- **Global impact of Delinquent condition**
Changing the meaning of `NodeDownOrDeleted` to use delinquency will have an effect on all volumes, not just RWX.  One expired lease would lead to the relocation of any resource owned by that node and the InstanceManager itself.  Even if that is accurate, that's a big step to take.  Some recovery actions might have to time out until the Kubernetes node status catches up.  
If it is not accurate, it would be short-lived.  The node_controller on the still-living node will promptly clear the `Delinquent` condition and restore the webhook selector labels.  But that has the potential to create a race with any cleanup actions that may have already started, leading to non-deterministic behavior.  
It would be better to find a way to confine the effects of a stale lease to the volume it applies to.  How might that be done?
    - For resources that map one-one with RWX volumes, use the resource controller's `isResponsibleFor()` method to check first whether the related share manager ownership has moved, and if so, change to match it.  That can work for the volume, volume attachment, and engine controllers.
    - For engine and replica instances, the handling depends on the instance manager's state, which in turn is controlled by its node's `DownOrDeleted` status.  If the instance manager is allowed to remain in "running" state, then every piece of code that checks instance manager state would need to have an added check of node delinquent condition, at least for instances that belong to RWX volumes, in situations where that can be determined.

- **Possible delay due to image pull on the successor node**
This is taken care of by the added feature to pre-pull the share-manager pod image: [[IMPROVEMENT] Pre-pull images (share-manager image and instance-manager image) on each Longhorn node](https://github.com/longhorn/longhorn/issues/8376).

- **Insufficient resources on any successor node**
We rely on Kubernetes scheduling to pick an appropriate successor node that meets all the usual constraints, if one exists.  If the pod can't be scheduled, there is little to be done immediately but to wait for the failed node to return.  For the user, the solution might be to add resources or decrease the cluster load in order to allow space for failover scheduling.  This design does not schedule the successor in advance (see [Active/Passive](#active-passive) below for notes on how that might work).  

- **False positives**
The initial choice for timeout interval may prove to be too sensitive.  Increasing the timeout will make it less likely to restart share-manager unnecessarily, but also increase the time to recovery.  
One open question is whether delays in lease renewal and false positives are more likely in a heavily loaded cluster.  That can probably only be resolved with copious testing, including high-load cases.

- **Webhook availability**
Testing with the PoC uncovered a snag.  Often, the share manager controller will get a failure when it updates the volume attachment. The error is a timeout while trying to call the admission webhook.  That repeats until the failed node actually goes to "not ready", and then it succeeds, usually about 20-30 seconds later.  It doesn't break anything, but it means that the failover takes as long as it would without this feature.  
In analysis with team members, we concluded that it is because the admission webhook is a service and one node of the cluster is picked to respond to the service IP address for any given request.  It can happen that it is the same node that hosted the share manager and has failed.  If so, calls to the webhook will time out until control is passed by Kubernetes to another node, which happens on its own timetable.  On the PoC test cluster of three worker nodes, that's about 1/3 of the time.  That means that failovers will intermittently and unpredictably take longer than they should.

We can avoid this by making a label on the longhorn-manager pod specific to each webhook and using that label as the webhook's selector.  If the node goes delinquent, remove the label to take that node's IP address out of the webhook service's endpoint slice.  That will prevent the unresponsive node from being selected.

### Upgrade Strategy

There are two changes that need to be handled in an upgrade:
- Creation of a new setting to define and default:  `enable-share-manager-fast-failover` (default, false).  
- Revision of webhook services to use dedicated labels as selectors.

After an upgrade, the share-manager pod would have to be restarted into the new share-manager image for lease management to work.  That could happen as part of the upgrade, or as nodes are restarted for other reasons.  The first restart would use the old, slow mechanism, but subsequent ones would use the new one.

The logic for creation and checking of Lease records ensures that all parties know and implement the lease strategy.  If some component doesn't, the behavior defaults to the same as current code.

> Old longhorn-manager + new share-manager: No lease is created, so the share-manager just skips the renewal loop.

> New longhorn-manager + old share-manager: Lease is created, but never claimed by a holder or renewed to advance the expiration time. Staleness check sees that there is no holder, so the lease is never expired. Failover is only based on reported K8s node state.

### Test Plan

The Test Plan is essentially identical to [Dedicated Recovery Backend for RWX Volume's NFS Server](https://github.com/longhorn/longhorn/blob/master/enhancements/20220727-dedicated-recovery-backend-for-rwx-volume-nfs-server.md).

- Setup
    3 worker nodes for the Longhorn cluster.  
    For each test repeat once with default NFS mount options, including "soft" or "softerr", and once with custom options including "hard" mount.

- Tests
    1. Create 1 RWX volume and then run an app pod with the RWX volume on each worker node.  Execute the command in each app pod
        
        `( exec 7<>/data/testfile-${i}; flock -x 7; while date | dd conv=fsync >&7 ; do sleep 1; done )`
        
        where ${i} is the node number.
        
        Turn off or restart the node where share-manager is running. Once the share-manager pod is recreated on a different node, check
        
        - Expect
            - In the client side, IO to the RWX volume will hang until a share-manager pod replacement is successfully created on another node.
            - During the outage, the server rejects READ and WRITE operations and non-reclaim locking requests (i.e., other LOCK and OPEN operations) with an error of NFS4ERR_GRACE.
            - The clients can continue working without IO error.
            - Lock reclaim process can be finished earlier than the 90-second configured grace period.
            - Outage should be equivalent to simple pod failover, less than 20 seconds.
            - If locks cannot be reclaimed after a grace period, the locks are discarded and return IO errors to the client. The client reestablishes a new lock.

    2. Turn the deployment into a daemonset in [example]([https://github.com/longhorn/longhorn/blob/master/examples/rwx/rwx-nginx-deployment.yaml](https://github.com/longhorn/longhorn/blob/master/examples/rwx/rwx-nginx-deployment.yaml) ) and disable `Automatically Delete Workload Pod when The Volume Is Detached Unexpectedly`. Then, deploy the daemonset with a RWX volume.
        
        Turn off the node where share-manager is running. Once the share-manager pod is recreated on a different node, check
        
        - Expect
            - The other active clients should not run into the stale handle errors after the failover.
            - Lock reclaim process can be finished earlier than the 90-second configured grace period.
            - Outage should be equivalent to simple pod failover, less than 20 seconds.

    3. Multiple locks one single file tested by byte-range file locking

        Each client using [range_locking.c](https://github.com/longhorn/longhorn/files/9208112/range_locking.txt) in each app pod locks a different range of the same file. Afterwards, it writes data repeatedly into the file.
        
        Turn off the node where share-manager is running. Once the share-manager pod is recreated on a different node, check
        
        - Expect
            - The clients continue the tasks after the server's failover without IO or stale handle errors.
            - Lock reclaim process can be finished earlier than the 90-second configured grace period.
            - Outage should be equivalent to simple pod failover, less than 20 seconds.

## Alternatives

In the LEP for the recovery backend, it said, (bullets added for emphasis)
> To support NFS server's failover capability, we need to change both the client and server configurations. A dedicated recovery backend for Kubernetes and Longhorn is also necessary.
> In the implementation, we will not implement the active/active or active/passive server pattern:
>   - Longhorn currently supports local filesystems such as ext4 and xfs. Thus, any change in the node, which is providing service, cannot update to the standby node. The limitation will hinder the active/active design. 
>   - Currently, the creation of an engine process needs at least one replica and then exports the iSCSI frontend. That is, the standby engine process of the active/passive configuration is not allowable in current Longhorn architecture.

Those factors are still present.  But here are some possibilities that have been considered.

### Active/Active with no interruption.

In order to do a more immediate failover, the [NFS-ganesha Wiki](https://github.com/nfs-ganesha/nfs-ganesha/wiki/NFS-Ganesha-and-High-Availability) advises 
> NFS-Ganesha does not provide its own clustering support, but HA can be achieved using Linux HA  

and points to several options for a Linux node clustering solution layered below ganesha, including Gluster or Ceph.

Some of the difficulties are discussed in the nfs-ganesha issue [Does the nfs client can do auto failover to another good nfs-ganesha server if one ganesha server is down.](https://github.com/nfs-ganesha/nfs-ganesha/issues/761).

There was a [proposal](https://www.snia.org/sites/default/files/Poornima_NFS_GaneshaForClusteredNAS.pdf) to extend nfs-ganesha with a Cluster Manager Abstraction Layer (CMAL) for the purpose, but it was abandoned.

Here are some more recent solutions for "NFS clusters".
 - SUSE SLE 15 [Highly Available NFS Storage with DRBD and Pacemaker](https://documentation.suse.com/sle-ha/15-SP5/html/SLE-HA-all/article-nfs-storage.html)
 - Ubuntu [HighlyAvailableNFS](https://help.ubuntu.com/community/HighlyAvailableNFS)
 - Highly Available NFS based Kerberos KDC [Ganesha + GlusterFS + HAProxy](https://www.loadbalancer.org/blog/highly-available-shared-nfs-server/)
 - A video on [How to create a HA NFS Cluster using Pacemaker, Corosync, & DRBD on RHEL / AlmaLinux 9](https://www.youtube.com/watch?v=IxFI0Ms0ULA).  Setup is far from trivial.
  
All of these methods use a distributed filesystem or block driver to keep the metadata synchronized between the HA cluster nodes.  They set up network access with a tool such as HAProxy to an IP address that will be handled by whichever node or nodes are alive, and use a tight synchronizer between the Linux server nodes.
In a Kubernetes setting, that would become a synchronizer between the NFS server containers in the paired share-manager pods.  That might be possible, but it would add a significant amount of configuration to the container, and traffic to the management network per volume.

### Active/Active as Load Balancer

  - [cephNFS](https://rook.io/docs/rook/latest/CRDs/ceph-nfs-crd/#example) can configure multiple active NFS servers, but it does not work quite the same way.  Clients connect to either server, but it relies on "sticky" client connection to stay with the same server.  It recommends setting active count to 1; otherwise a failover may block I/O for the grace period while clients move.
  - rook/ceph had a [ticket for the HA feature](https://github.com/rook/rook/issues/11526) which has been closed for lack of activity.

### Active/Passive

Also termed `Active/Warm Standby`.  There's a good discussion of the comparison in [this S3GW doc](https://github.com/s3gw-tech/s3gw/blob/main/docs/research/ha/RATIONALE.md).  The share-manager pod is the Longhorn SPOF analog of S3GW's `radosgw`.  Even though the feature has been de-prioritized, there is a residual Longhorn issue that still applies: [[FEATURE] Improving recovery times for non-graceful node failures #6803](https://github.com/longhorn/longhorn/issues/6803).

In this situation, the implementation could look something like this:
  1. Make the share-manager pod a Deployment of two pods.  Force them via hard anti-affinity to locate on different nodes.  (This might take some adjustment on single-node systems, but in that case, HA for node failure is impossible anyway.  Still, Longhorn would need to alter the deployment to 1 node to avoid an ever-present unshedulable pod.)
  2. Pick a leader pod, using [leader election](https://kubernetes.io/docs/concepts/architecture/leases/#leader-election) just as Longhorn upgrade package does.  That leader can mount the volume and export it under the service's ClusterIP, just as at present.
  3. Weight or configure the ClusterIP mapping so that all traffic to that address is routed to the leader.  One way to do this is to prevent the non-leader from reporting as "ready" in its readiness probe.

As mentioned, there are complications with the engine and attachments for the passive pod.  There would be a lot of changes to tolerate a second engine and ensure that it is not used until failover.  To attach the backup node, the mount has to be `AccessMode: ReadWriteMany` itself so that Kubernetes will permit it.  It won't actually ever be simultaneously written, since there will be no NFS client traffic to it.  It is more like the RWX mount used for migration.

### Active/Fast-Failover

Referred to as "Active/Standby" in the S3GW discussion.  This document will use the term "Fast-failover" to emphasize that the pipeline is rebuilt entirely at the time of failure.  The focus of the implementation is to make the rebuild as quick as possible.  This is the option proposed.

Other options considered for quick failure detection of the share-manager pod, but discarded:
  - Apply a liveness probe to the share-manager pod.  But that is probed from `kubelet` on the same node, so that is ineffective when the node itself is down.
  - Similar to [rook](https://github.com/rook/rook/pull/12845), implement a "ping" RPC call in share-manager to check that it is responsive.  But then, what entity pings and decides it is unresponsive?  One idea was let all worker nodes (longhorn-managers) ping all RWX volumes, but that doesn't scale very well as volumes and nodes increase in number.

## Other References
 
#### NFSv4 implementation

- [Network File System (NFS) Version 4 Protocol](https://datatracker.ietf.org/doc/html/rfc7530)
- [Client recovery in NFS Version 4](https://docs.oracle.com/cd/E19120-01/open.solaris/819-1634/6n3vrg2al/index.html)
- [Long client timeouts when failing over the NFS Ganesha IP resource](https://www.suse.com/support/kb/doc/?id=000019374)
- [Necessary NFS Server Cluster Design for NFS Client Lock Preservation](https://www.suse.com/support/kb/doc/?id=000020396)
- [How NFSv4 file delegations work](https://library.netapp.com/ecmdocs/ECMP1401220/html/GUID-DE6FECB5-FA4D-4957-BA68-4B8822EF8B43.html)

#### Nfs-ganesha

- https://github.com/nfs-ganesha/nfs-ganesha/wiki/NFS-Ganesha-and-High-Availability
- https://www.snia.org/sites/default/files/Poornima_NFS_GaneshaForClusteredNAS.pdf
- https://lists.nfs-ganesha.org/archives/list/devel@lists.nfs-ganesha.org/thread/MLI3DRZ5MR5MC4GBREO5OR2Q2SXYK47V/
- https://github.com/nfs-ganesha/nfs-ganesha/issues/761

#### Kubernetes

- [K8s non-graceful node shutdown](https://kubernetes.io/blog/2023/08/16/kubernetes-1-28-non-graceful-node-shutdown-ga)
- Poison-pill HA demo at [medik8s](https://www.medik8s.io)
    - Comparatively slow and focus is on ensuring against split-brain, not speed of recovery.

