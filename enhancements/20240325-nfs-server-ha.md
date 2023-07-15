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

Duplicate NFS servers providing Active/Active or Active/Passive redundancy.

## Proposal

Add a detection mechanism for the share-manager controller to know quickly about the failure of a share-manager pod.  The controller will need to delete or even force-delete the old one, rather than waiting to do so based on node state.  That will allow it to make a new pod much more quickly.  

The simplest way is for longhorn-manager to ping the share-manager pod via an RPC interface at some interval.  If it fails to reply, the pod can be considered functionally dead.  This requires a new interface into longhorn-share-manager, but no new CRD.  "Fails to reply" will be defined by a configurable threshold of ping interval and failure count, noting that the longer the overall duration, the slower the failover.  That will also require the addition of two new settings.

### User Stories

In the current code, failure of a container in the share-manager pod or the pod itself is quickly handled.  It takes about 20 seconds to restore write access, of which about half is spent restarting the workload pods and letting them remount.  Longhorn's recovery backend has the ability to shorten the grace period wait when all clients are accounted for.

The big problem happens when the node with the share-manager pod fails or restarts.  Just the time it takes for the node to go `NotReady` is already too long for share-manager failover.  We intend to make the NFS client recovery time for a failure of the node running the share-manager pod to be just as quick as for simple pod failure.

### User Experience In Detail

1. The changes and improvements should not impact the use of RWX volumes.  There will be no observable difference until a node failure occurs (for whatever reason - Kubernetes upgrade, eviction, injected error).
2. Operation of the recovery backend will be unchanged.
3. After the failure of the share-manager pod, the application on the client side’s IO operations will be stuck until the share-manager and NFS are recreated, but the interruption will be brief, within a specified limit TBD regardless of the cause.
4. There will be only a single interruption for a failure.
5. Changing `node-monitor-period` and `node-monitor-grace-period` values in the Kubelet should make no difference to RWX failover. The time to accomplish node NotReady processing and return to Ready state should be independent of RWX HA time. 

## Design

### Implementation Overview
  
- **share-manager**
    
    Implement an RPC handler for a "ping" command.
    
- **longhorn-manager**
    
    Add settings for
        `share-manager-ping-interval` (default, 1 second)
        `share-manager-ping-max-fail` (default, 5)
    
    Add code to share-manager controller to do RPC ping of each existing share-manager pod every ping interval.  If the ping fails, increment an in-memory failure count for that pod.  If the count exceeds the max-fail setting value, delete the pod.

    Which longhorn-manager is the right one to be calling this?  The one on the owning node of the pod is a poor choice, since it may also be out of commission.  Picking another one is difficult, but it isn't necessary.  Let each one do the ping.  That's not all that much network traffic for N nodes X M rwx volumes.  Whichever node reaches the threshold first is the one that pulls the trigger.

    Add a new "Suspicion" Condition on the Node CR, which defaults to "false".  Along with deleting the pod, the deciding controller will set that condition to true with reason "share-manager ping failed".  That will be useful for avoiding the same node if it has not reached NotReady state when a share-manager controller is choosing a new node.  The condition is time-stamped and is cleared when the node goes NotReady (we were right) or after some interval we decide on (at least a minute).  A node with that condition is not considered for share-manager pod creation.

- **nfs-ganesha (user-space NFS server)**

    No changes.
    

### Risks and Mitigation

- **Rescheduling on same node**
The replacement for a terminated share-manager pod will need to avoid being scheduled on the same node.  The node itself might not yet have transitioned to NotReady and thus appear to be schedulable according to Kubernetes.  To work around that, we add a "Suspicion" Condition on the node housing a failed share-manager pod and add that as another scheduling criterion.

- **Refusal to relinquish mount on dead pod.**
Hopefully this will not be a problem.  If testing shows that it is, it may be necessary to terminate an unresponsive pod more forcefully.

- **Possible delay due to image pull on the successor node**
With a pull policy of `IfNotPresent` this should not occur more than once per node.  If it appears to be a problem, Longhorn can add a pod to pre-pull, but it seems unlikely.

- **False positives**
The initial estimates for ping interval and failure count may prove to be too sensitive or not sensitive enough.  That is addressed by using configurable thresholds for sensitivity.  They might even be higher than necessary.  It will require some experience to tune the behavior.

### Test Plan

The Test Plan is essentially identical to [Dedicated Recovery Backend for RWX Volume's NFS Server](https://github.com/longhorn/longhorn/blob/master/enhancements/20220727-dedicated-recovery-backend-for-rwx-volume-nfs-server.md).

- Setup
    3 worker nodes for the Longhorn cluster
    Attach an RWO volume to each node.

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
            - Outage should be equivalent to simple pod failover, less than TBD seconds.
            - If locks cannot be reclaimed after a grace period, the locks are discarded and return IO errors to the client. The client reestablishes a new lock.

    2. Turn the deployment into a daemonset in [example]([https://github.com/longhorn/longhorn/blob/master/examples/rwx/rwx-nginx-deployment.yaml](https://github.com/longhorn/longhorn/blob/master/examples/rwx/rwx-nginx-deployment.yaml) ) and disable `Automatically Delete Workload Pod when The Volume Is Detached Unexpectedly`. Then, deploy the daemonset with a RWX volume.
        
        Turn off the node where share-manager is running. Once the share-manager pod is recreated on a different node, check
        
        - Expect
            - The other active clients should not run into the stale handle errors after the failover.
            - Lock reclaim process can be finished earlier than the 90-second configured grace period.
            - Outage should be equivalent to simple pod failover, less than TBD seconds.

    3. Multiple locks one single file tested by byte-range file locking

        Each client using [range_locking.c](https://github.com/longhorn/longhorn/files/9208112/range_locking.txt) in each app pod locks a different range of the same file. Afterwards, it writes data repeatedly into the file.
        
        Turn off the node where share-manager is running. Once the share-manager pod is recreated on a different node, check
        
        - Expect
            - The clients continue the tasks after the server's failover without IO or stale handle errors.
            - Lock reclaim process can be finished earlier than the 90-second configured grace period.
            - Outage should be equivalent to simple pod failover, less than TBD seconds.

### Upgrade Strategy

The only impact on upgrade is the creation of two new settings to define and default:  
- `share-manager-ping-interval` (default, 1 second)  
- `share-manager-ping-max-fail` (default, 5)

There could be a flood of share-manager failures during upgrade and difficulties rescheduling onto nodes that all have "Suspicion == true".  To avoid that, an RPC response of "unknown method" will be treated as not a failure, and it will wait for the share manager to be upgraded the normal way.

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
  2. Pick a leader pod, using [leader election](https://kubernetes.io/docs/concepts/architecture/leases/#leader-election) just as Longhorn upgrade package does.  That leader can mount the RWO volume and export it under the service's ClusterIP, just as at present.
  3. Weight or configure the ClusterIP mapping so that all traffic to that address is routed to the leader.

There are a couple of possibilities for the non-leader pod, while it stands by to become the leader.  Should it mount the volume as well?  If it does, then that mount has to be `AccessMode: ReadWriteMany` itself so that Kubernetes will permit it.  It won't actually ever be simultaneously written, since there will be no NFS client traffic to it.  It is more like the RWX mount used for migration.
If not, then it has to mount when the pod becomes the leader.  That is a quick operation, so it is probably not worth the complication to have it pre-mounted.  Either way, the volume attachments must also be updated when the leadership changes.

### Active/Fast-Failover

Referred to as "Active/Standby" in the S3GW discussion.  This document will use the term "Fast-failover" to emphasize that the pipeline is rebuilt entirely at the time of failure.  The focus of the implementation is to make the rebuild as quick as possible.  This is the option proposed.

Other options considered for quick failure detection of the share-manager pod, but discarded:
  - Apply a liveness probe to the share-manager pod.  But that is probed from `kubelet` on the same node, so that is ineffective when the node itself is down.
  - Use a Kubernetes Lease, which the pod can refresh in periodic updates and the controller can watch for failure to update.  Simple, but it does require the share-manager pod to add code for accessing etcd and using CRDs, which it does not currently need to do.  Plus, it might become a significant load on etcd, if there were hundreds of RWX volumes each updating every few seconds.

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

