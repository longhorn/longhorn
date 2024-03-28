# Reference Architecture and Sizing Guidelines

## Summary

As a Longhorn user, I need to know the reference architecture and sizing to ensure the best experience.
From these references, I may have a picture of how Longhorn would perform in a similar cluster spec.

### Related Issues

https://github.com/longhorn/longhorn/issues/2598

## Motivation

### Goals

#### Goal 1
For each supported environment, pick a cluster spec (small, medium, large) to run Longhorn and measure Longhorn performance/scalability with that cluster spec.

The supported environments are:
1. On-Prem (using Equinix Metal for testing)
1. Public Cloud (using AWS for testing)
1. Edge (Not sure where to test)

The cluster spec including the factors:
1. Node's CPU
1. Node's RAM
1. Node's Disk IOOPs/bandwidth/latency
1. Internode networking bandwidth/latency
1. OS distro 
1. Kernel
1. The number of nodes
1. Kubernetes version and distro 
1. Number of controller plane nodes
1. Number of ETCD nodes
1. Longhorn specific setting like:
   1. Priority class: stick to a high value as best practice
   1. Replica balancing: stick to enable best practice
1. There is volume rebuilding happens inside the cluster or not (we can trigger this by restarting certain number of nodes at a time)



The Longhorn performance/scalability including the factors:
1. Max/min/recommended volume size
1. Max/recommended number of Longhorn volumes inside the cluster 
1. Max/recommended number of Longhorn volumes attached to a node
1. Max/recommended number of Longhorn replicas on to a node
1. Longhorn volume IOOPs/bandwidth/latency

#### Goal 2
For the recommended cluster spec of each supported environments, figure out:
1. If we scale up the number of node, what is the max number of nodes and Longhorn volumes that Longhorn can support

#### Goal 3
Figure out Recommended backup target.

The factors to consider:
1. Backup target type (NFS/S3/SMB/CIFS/...)
1. Backup target latency


#### Goal 4
Develop some kind of automation for this test plan so that we can run this again for every new release.
This will help us to identify if there are improvement/regression 


### Non-goals

We are not planning to find the answer for the questions:
1. The exact formular to calculate minimum resource requirement (CPU/RAM/Network) for a specific amount of volumes 

## Proposal

This is where we get down to the nitty-gritty of what the proposal actually is.

### User Stories
Detail the things that people will be able to do if this enhancement is implemented. A good practice is including a comparison of what the user cannot do before the enhancement is implemented, why the user would want an enhancement, and what the user needs to do after, to make it clear why the enhancement is beneficial to the user.

The experience details should be in the `User Experience In Detail` later.

#### Story 1
#### Story 2

### User Experience In Detail

Detail what the user needs to do to use this enhancement. Include as much detail as possible so that people can understand the "how" of the system. The goal here is to make this feel real for users without getting bogged down.

## Design

### Payload design 
We are considering 5 types of payload:

1. 100% read, 100% RWO volumes
1. 100% read, 100% RWX volumes
1. 100% write, 100% RWO volumes
1. 100% write, 100% RWX volumes
1. No read/write and 100% RWO volumes (this will test the scalability of Longhorn control plane)

We are going to use fio to develop these payload since fio is a popular tool for testing storage. 
We are not going to select a particular application such as a SQL DB, Kafka, Prometheus for the payload as 
this might be too specific and many users might not be interested in the particular application we chose. 

More detailed about how to implement this payload:
* We can use our favorite [kbench](https://github.com/yasker/kbench) benchmarking tool with some modification:
  * Right now, it is having 2 modes: `quick` mode and `normal` mode. We can add 2 more modes: `readonly` and `writeonly` modes.
  * Then when deploying the workload pod, the yaml can select either `readonly` and `writeonly` modes according to the test's payload type
* Then test workload pod then run the kbench benchmarking tool continuously and record the result into a file after each run
* The workload pod can include a small webserver to export the test result as Prometheus metrics for data collection
* On the cluster level, we can deploy Rancher monitoring to collect this data and display it on the grafana graph for realtime monitoring  

### Testing passing criteria
How to decide if cluster is able to handle the payload? 
1. Workload pods are not crashing
1. Volumes, engines, and replicas are not crashing
1. IOOPs/bandwidth/latency result is not reduced. We need design a way to collect testing result data from the workload pods: 
   1. Maybe the workload pod exports the benchmark data as Prometheus metrics then we can collect them using Rancher monitoring
   1. Maybe another way is each pod calculate the result and output it at the end of pod's life. Then we can read and parse them using `kubectl logs`

### Test steps:


1. Pick one of the fixed cluster spec above
1. Pick one of the payload type above
1. Applied the payload with minimal scale (i.e., 1 pods). Make sure that pods are evenly distributed across the nodes
1. Scale up number of workload pods until the `Testing passing criteria` above break.
1. Publish the result:
   1. Max number of Longhorn volumes inside the cluster
   1. Max number of Longhorn volumes attached to a node
   1. Max number of Longhorn replicas on to a node
   1. Longhorn volume IOOPs/bandwidth/latency
   1. CPU/memory used by Longhorn processes
1. Try to scale the cluster's number of nodes and number of workload pods proportionally. 
At which point the workload become very slow to starts, crash, IO slow down significantly 
1. Publish the result:
   1. The number of cluster nodes Longhorn can support with this cluster spec
1. Scale the number of control plan node back to 1, worker nodes back to 3, workload back to 1
1. Increase the size of the volume, trigger rebuilding, perform regular volume snapshot backup operation
1. Publish the result:
   1. At which size, the volume rebuilding and other basic operation are broken?

## Note [optional]

Additional notes.
