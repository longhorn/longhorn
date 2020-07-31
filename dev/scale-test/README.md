## Overview
scale-test is a collection of developer scripts that are used for scaling a cluster to a certain amount of volumes
while monitoring the time required to complete these actions.
`sample.sh` can be used to quickly see how long it takes for the requested amount of volumes to be up and usable.
`scale-test.py` can be used to create the amount of requested statefulsets based on the `statefulset.yaml` template,
as well as retrieve detailed timing information per volume.


### scale-test.py
scale-test.py watches `pod`, `pvc`, `va` events (ADDED, MODIFIED, DELETED).
Based on that information we can calculate the time of actions for each individual pod.

In additional scale-test.py can also be used to create a set of statefulset deployment files.
based on the `statefulset.yaml` with the following VARIABLES substituted based on the current sts index.
`@NODE_NAME@` - schedule each sts on a dedicated node
`@STS_NAME@` - also used for the volume-name

make sure to set the correct CONSTANT values in scale-test.py before running.


### sample.sh
sample.sh can be used to scale to a requested amount of volumes based on the existing statefulsets 
and node count for the current cluster.

One can pass the requested amount of volumes as well as the node count of the current cluster.
example for 1000 volumes and 100 nodes: `./sample.sh 1000 100` 
this expects there to be a statefulset deployment for each node.
