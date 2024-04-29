# Fast Failover for RWX Volume's NFS Server

## Summary

In Longhorn, a ReadWriteMany volume (and at some point, a ReadOnlyMany volume) is handled by an NFS server located within the share-manager pod.  It mounts an RWO volume in the usual way, and then provides export and locking capabilities on top of it, which multiple workload pods can mount and write safely.  There is only one share-manager pod for a volume, so if the node on which the pod is running fails, the responsible controller must notice and start a new pod on another node.  After it starts, client pods can re-connect and resume I/O.  But first, they negotiate with the new server about what their state should be, and there is a grace period in which writes are refused while waiting for any other possible clients to show up.

In a previous enhancement, [Dedicated Recovery Backend for RWX Volume's NFS Server](https://github.com/longhorn/longhorn/blob/master/enhancements/20220727-dedicated-recovery-backend-for-rwx-volume-nfs-server.md), Longhorn incorporated a recovery backend that can speed up that process and guarantee that all the former clients have been accounted for.  But a node failure still takes minutes to recover from, as noted in the [Longhorn docs](https://longhorn.io/docs/1.6.0/high-availability/node-failure/).

In this enhancement, a mechanism is proposed to quickly detect and respond to share-manager pod failure independently of the Kubernetes node failure sequence and timing.

### Related Issues

[https://github.com/longhorn/longhorn/issues/6205](https://github.com/longhorn/longhorn/issues/6205)

## Motivation

The main goal is to minimize downtime on RWX workloads.  Having a demonstrable upper bound on the recovery time for most non-pathological situations may also enable adoption by customers with specific SLA requirements.

### Goals

Implement a fast failover mechanism that is not gated by Kubernetes' relatively slow detection and handling of node failure.  Recovery should be a matter of seconds rather than minutes.  Ideally, it would not require a restart of workload pods.

### Non-goals

Duplicate NFS servers running simultaneously, providing Active/Active or Active/Passive redundancy.

## Proposal

Fast failover needs several pieces.

1. Quick detection of failure
    - Use the Kubernetes `Lease` mechanism.  When an RWX volume is created, create the lease at the same time as the share-manager pod and service.  It should have the same lifetime as the service.
    - Update the lease periodically from ShareManager Run().
2. Quick removal of the failed/failing server
    - Check the lease from share-manager controller.  If it is expired, mark the share-manager CR as error and let it delete the pod.
    - May require force delete, if kubelet not responsive.
3. Quick creation of a replacement
    - This is already part of the Share Manager lifecycle.
    - But avoid former host.  Kubelet will not yet report it as down.
4. Avoid client workload pod restart, if possible.
    - Longhorn currently restarts the workload pods in volume controller when the share-manager pod restarts.  That may be necessary if the NFS mount is "hard", because the client can hang indefinitely, but not if it is "soft".
    - Longhorn defaults to "softerr", but the user can override NFS mount options, so it can't be assumed.  Volume controller can Look at the storage class parameters or PV volumeAttributes to decide whether a restart is necessary..

### User Stories

In the current code, failure of a container in the share-manager pod or the pod itself is quickly handled.  It takes about 20 seconds to restore write access, of which about half is spent restarting the workload pods and letting them remount.  Longhorn's recovery backend has the ability to shorten the grace period wait when all clients are accounted for.

The big problem happens when the node with the share-manager pod fails or restarts.  Just the time it takes for the node to go `NotReady` is already too long for share-manager failover.  We intend to make the NFS client recovery time for a failure of the node running the share-manager pod to be just as quick as for simple pod failure.

### User Experience In Detail

1. The changes and improvements should not impact the use of RWX volumes.  There will be no observable difference until a node failure occurs (for whatever reason - Kubernetes upgrade, eviction, injected error).
2. Operation of the recovery backend will be unchanged.
3. After the failure of the share-manager pod, the application on the client side’s IO operations will be stuck until the share-manager and NFS are recreated, but the interruption will be brief, within a specified limit **TBD** regardless of the cause.
4. There will be only a single interruption for a failure.
5. Changing `node-monitor-period` and `node-monitor-grace-period` values in the Kubelet should make no difference to RWX failover. The time to accomplish node NotReady processing and return to Ready state should be independent of RWX HA time. 

## Design

### Implementation Overview

- **share-manager**
    
    Add a constant, `share-manager-renew-interval`.  Should be often enough to detect failure quickly, but not so often that it overwhelms the network and API server with traffic.  Hard-code this to 3 seconds.

    Every `share-manager-renew-interval`, get the lease for the RWX volume (name it the same as the volume name) and update its `lease.spec.renewTime` to "now".  If the lease cannot be found, take no action.
    
- **longhorn-manager**
    
    - setting_manager_controller  
    Add a setting, `share-manager-stale-timeout`.  Use 5 seconds as a default value.  Make this overridable, but never less than 5 seconds.
    
    - share_manager_controller  
    Add creation logic to create a lease at the same time as the service.  Set `lease.spec.leaseDurationSeconds` to `share-manager-stale-timeout`.  Note that is informational only.  The timeout decision will use the global setting, not the spec value. In that way, we allow dynamic changes to behavior without re-creating volumes.  
    At creation, also set `lease.spec.acquireTime` and `lease.spec.renewTime` to "now".  
    Every sync, check the lease for each share-manager.  If acquireTime == renewTime, assume that the share-manager image does not know to update the lease, so take no action.  Otherwise, if status is StateRunning and renewTime + timeout is less than "now", mark the share-manager CR as `Error` to drive deletion and re-creation.  
    Add a "forceAnyway" flag to `cleanupShareManagerPod()` to have it not try to check `IsNodeDownOrDeleted` which may not be updated yet.

    - volume_controller  
    Add logic in `ReconcileShareManagerState()` to check the volume's storageclass for NFS mount options.  If `parameters.nfsOptions` contains "hard", then request remount to force a restart as in current code.  Otherwise, skip that (but make a similar event).  This code is aware that the default option is not to hard mount NFS.
    
- **nfs-ganesha (user-space NFS server)**

    No changes.
    
#### Implementation Order
The feature can be implemented and committed in the following increments.  Although incomplete, each step adds infrastructure that can exist without breaking current operation.
1. Workload pod restart check - applies even in current release.
2. Lease creation and update.
3. Add setting for stale timeout.
4. Lease expiration checking.


### Risks and Mitigation

- **Rescheduling on same node**
The replacement for a terminated share-manager pod will need to avoid being scheduled on the same node.  The node itself might not yet have transitioned to NotReady.  The expectation is that Kubernetes would notice a failure to respond during creation, but if it does not try to talk to the target node when scheduling, relying only on recorded state, then this might happen.  The size of the delay and a way to get around it if needed are **TBD**.

- **Possible delay due to image pull on the successor node**
The user should avoid a pull policy of `Always`.  If there are multiple RWX volumes, the failover node may already have the image.  There is also a ticket in development to pre-pull a variety of system-managed pod images: [[IMPROVEMENT] Pre-pull images (share-manager image and instance-manager image) on each Longhorn node](https://github.com/longhorn/longhorn/issues/8376).

- **Insufficient resources on any successor node**
We rely on Kubernetes scheduling to pick an appropriate successor node that meets all the usual constraints, if one exists.  If the pod can't be scheduled, there is little to be done immediately but to wait for the failed node to return.  For the user, the solution might be to add resources or decrease the cluster load in order to allow space for failover scheduling.  This design does not schedule the successor in advance (see Active/Passive below).

- **False positives**
The initial choice for timeout interval may prove to be too sensitive.  That is addressed by using a configurable setting.  Increasing the timeout will make it less likely to restart share-manager unnecessarily, but also increase the time to recovery.

- **Experimental feature**
If desired, the timeout setting can be set at a high value, such as 600 seconds, to guarantee that normal Kubernetes node-failure handling will take place first.  The (slight) overhead for Lease creation and update will still remain.  If RWX HA is released as an "experimental" feature in 1.7.0, the high value can be the default.

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
            - Outage should be equivalent to simple pod failover, less than **TBD** seconds.
            - If locks cannot be reclaimed after a grace period, the locks are discarded and return IO errors to the client. The client reestablishes a new lock.

    2. Turn the deployment into a daemonset in [example]([https://github.com/longhorn/longhorn/blob/master/examples/rwx/rwx-nginx-deployment.yaml](https://github.com/longhorn/longhorn/blob/master/examples/rwx/rwx-nginx-deployment.yaml) ) and disable `Automatically Delete Workload Pod when The Volume Is Detached Unexpectedly`. Then, deploy the daemonset with a RWX volume.
        
        Turn off the node where share-manager is running. Once the share-manager pod is recreated on a different node, check
        
        - Expect
            - The other active clients should not run into the stale handle errors after the failover.
            - Lock reclaim process can be finished earlier than the 90-second configured grace period.
            - Outage should be equivalent to simple pod failover, less than **TBD** seconds.

    3. Multiple locks one single file tested by byte-range file locking

        Each client using [range_locking.c](https://github.com/longhorn/longhorn/files/9208112/range_locking.txt) in each app pod locks a different range of the same file. Afterwards, it writes data repeatedly into the file.
        
        Turn off the node where share-manager is running. Once the share-manager pod is recreated on a different node, check
        
        - Expect
            - The clients continue the tasks after the server's failover without IO or stale handle errors.
            - Lock reclaim process can be finished earlier than the 90-second configured grace period.
            - Outage should be equivalent to simple pod failover, less than **TBD** seconds.

### Upgrade Strategy

The only impact on upgrade is the creation of a new setting to define and default:  `share-manager-stale-timeout` (default, 5).

The logic for creation and checking of Lease records ensures that all parties know and implement the lease strategy.  If some component doesn't, the behavior defaults to the same as current code.

## Alternatives

In the LEP for the recovery backend, it said, (bullets added for emphasis)
> To support NFS server's failover capability, we need to change both the client and server configurations. A dedicated recovery backend for Kubernetes and Longhorn is also necessary.
> In the implementation, we will not implement the active/active or active/passive server pattern:
>   - Longhorn currently supports local filesystems such as ext4 and xfs. Thus, any change in the node, which is providing service, cannot update to the standby node. The limitation will hinder the active/active design. 
>   - Currently, the creation of an engine process needs at least one replica and then exports the iSCSI frontend. That is, the standby engine process of the active/passive configuration is not allowable in current Longhorn architecture.

Those factors are still present.  But here are some possibilities that were considered.

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
  3. Weight or configure the ClusterIP mapping so that all traffic to that address is routed to the leader.

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

