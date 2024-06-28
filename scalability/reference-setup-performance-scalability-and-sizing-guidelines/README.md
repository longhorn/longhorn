# Reference Setup, Performance, Scalability, and Sizing Guidelines

In this document, we present the reference setup, performance, scalability, and sizing guidelines when using the Longhorn storage system. 
In practice, users deploy Longhorn in a vast array of different cluster specifications, making it impossible for us to test all potential setups. 
Therefore, we will select and test some typical environments for users' reference. 
By providing these references, users can gain insight into how Longhorn would perform in a similar cluster specification.


In summary, in the reports, we will perform various tests against Longhorn data plane and control plane to explore the Longhorn capability.
We adjust the parameter like: number of workload pods, IO pattern, number of Longhorn volumes, number of nodes in the cluster, the size of Longhorn volumes, ...
Then we measure the Longhorn data plane performance (read/write performance) and Longhorn control plane performance (speed of volume provisioning/attaching/detaching/mounting/unmounting)

We are building the reports for 2 type of environments: `public cloud` and `on-prem`. 
The reason that we want to separate `public cloud` and `on-prem` is that they are 2 popular usecases with typically different configurations. 
For example, `public cloud` usually does not offer fast disk and network for small/medium instances while this configuration is possible in the on-prem environment.

## Public Cloud 
1. [Medium Node Spec](./public-cloud/medium-node-spec.md)
1. [Big Node Spec](./public-cloud/big-node-spec.md) (targeted for `v1.7.0`)

## On-Prem 
1. [Medium Node Spec](./on-prem/medium-node-spec.md) (targeted for `v1.7.0`)
1. [Big Node Spec](./on-prem/big-node-spec.md) (targeted for `v1.7.0`)