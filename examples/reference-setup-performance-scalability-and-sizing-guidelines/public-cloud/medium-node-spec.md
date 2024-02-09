# Reference Setup, Performance, Scalability, and Sizing Guidelines: Public Cloud - Medium Node Spec

## Table of contents
1. [Cluster Spec](#cluster-spec)
   1. [Node Spec](#node-spec)
   1. [Network Spec](#network-spec)
   1. [Disk Spec](#disk-spec)
   1. [Kubernetes Spec](#kubernetes-spec)
   1. [Longhorn Config](#longhorn-config)
   1. [Additional Components](#additional-components)
1. [Workload design](#workload-design)
   1. [Read and Write Tests Design](#read-and-write-performance)
   1. [Longhorn Control Tests Design](#longhorn-control-plane-performance)
   1. [Maximum Volume Size Tests Design](#maximum-volume-size-tests-design)
   1. [Backup and Restore Tests Design](#backup-and-restore-tests-design)
   1. [Load Balancing](#load-balancing)
1. [Read Performance](#read-performance)
   1. [Random Read IOPs - Stress Tests](#random-read-iops---stress-tests)
   1. [Random Read IOPs - Rate Limited](#random-read-iops---rate-limited)
   1. [Sequential Read IOPs - Stress Tests](#sequential-read-iops---stress-tests)
   1. [Sequential Read IOPs - Rate Limited](#sequential-read-iops---rate-limited)
   1. [Random Read Bandwidth - Stress Tests](#random-read-bandwidth---stress-tests)
   1. [Random Read Bandwidth - Rate Limited](#random-read-bandwidth---rate-limited)
   1. [Sequential Read Bandwidth - Stress Tests](#sequential-read-bandwidth---stress-tests)
   1. [Sequential Read Bandwidth - Rate Limited](#sequential-read-bandwidth---rate-limited)
   1. [Random Read Latency - Stress Tests](#random-read-latency---stress-tests)
   1. [Sequential Read Latency - Stress Tests](#sequential-read-latency---stress-tests)
1. [Write Performance](#write-performance)
   1. [Random Write IOPs - Stress Tests](#random-write-iops---stress-tests)
   1. [Random Write IOPs - Rate Limited](#random-write-iops---rate-limited)
   1. [Sequential Write IOPs - Stress Tests](#sequential-write-iops---stress-tests)
   1. [Sequential Write IOPs - Rate Limited](#sequential-write-iops---rate-limited)
   1. [Random Write Bandwidth - Stress Tests](#random-write-bandwidth---stress-tests)
   1. [Random Write Bandwidth - Rate Limited](#random-write-bandwidth---rate-limited)
   1. [Sequential Write Bandwidth - Stress Tests](#sequential-write-bandwidth---stress-tests)
   1. [Sequential Write Bandwidth - Rate Limited](#sequential-write-bandwidth---rate-limited)
   1. [Random Write Latency - Stress Tests](#random-write-latency---stress-tests)
   1. [Sequential Write Latency - Stress Tests](#sequential-write-latency---stress-tests)
1. [Longhorn Control Plane Performance](#longhorn-control-plane-performance)
1. [Volume Maximum Size](#volume-maximum-size)
1. [Backup and Restore Speed](#backup-and-restore-speed)


## Cluster Spec
### Node Spec
* EC2 instance type: ec2 m5zn.2xlarge
* 8vCPUs, 32GB RAM
* Root disk
  * Size 50GB 
  * Type EBS gp3
* OS: Ubuntu 22.04.3 LTS (Jammy Jellyfish)
* Kernel version: 6.2.0-1017-aws

**Comment:**
We choose m5zn.2xlarge ec2 instance because it has consistent EBS performance unlike other similar (in terms of CPU and memory) instances which has baseline and bust EBS performance. 
Consistent EBS performance is important because we are using dedicated EBS disk for Longhorn storage. 
If the EBS performance is inconsistent, we will see inconsistent test result overtime.
See more at https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-optimized.html

### Network Spec
* Network bandwidth: 
  * Baseline bandwidth 10 Gbps
  * Burst bandwidth: Up to 25 Gbps in short time 
* Network latency: ~0.3ms RTT via ping command

### Disk Spec
* We are using dedicated disk for Longhorn volumes' replicas on the nodes. 
We select a typical EBS volume with average IOPs and bandwidth performance:
  * Single EC2 EBS gp3
  * 1TB 
  * IOPs set to 10000 
  * Throughput set to 360MiB/s 
  * Formatted as ext4 filesystem

**Comment:**
* We choose 10000 for EBS disk's IOPs simply because it is a middle value between minimum value 3000 and maximum value 16000 of the gp3 EBS disk
* We choose 360MiB/s for EBS disk's bandwidth because the m5zn.2xlarge EC2 instance has EBS bandwidth 396.25 MiB/s. 
  If we choose a bigger value than 396.25 MiB/s for EBS disk's bandwidth, the ec2 instance would not be able to push EBS disk to that value.

### Kubernetes Spec
* Kubernetes Version: v1.27.10+rke2r1
* CNI plugin: Calico
* Control plane nodes are separated from worker nodes

### Longhorn Config
* Longhorn version: v1.6.0
* Settings:
  * Using dedicated disk for Longhorn instead of root disk
  * The number of replicas per volume is 3
  * Storage Minimal Available Percentage setting: 10%
    * As we are using dedicated disk, we don't need big reserve storage as mentioned in best practice https://longhorn.io/docs/1.6.0/best-practices/#minimal-available-storage-and-over-provisioning
  * Storage Over Provisioning Percentage setting: 110%
    * We are planning to fill 15GB for each 20GB volume.
      If we schedule maximum amount, it would be 1100 GiB and actual usage will be (15/20)*1200 = 825GiB. This leaves 100GiB as 10% Storage Minimal Available Percentage setting plus some volumes' filesystem space overhead.

### Additional Components
* We deployed [Rancher monitoring](https://ranchermanager.docs.rancher.com/integrations-in-rancher/monitoring-and-alerting) which is a downstream version of [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).
  Note that this monitoring system generally consume certain amount of CPU, memory, and disk space on the node. We are deploying it with:
  * CPU request: 750m
  * CPU limit: 1000m
  * Memory request: 750Mi
  * Memory limit: 3000Mi
  * Data retention size: 25GiB
* We deployed [Local Path Provisioner](https://github.com/rancher/local-path-provisioner) to test baseline storage performance when using  local storage in each node directly.

## Workload design

### Read and Write Tests Design
We use [Kbench](https://github.com/yasker/kbench) which a tool to test Kubernetes storage.
The idea of Kbench is that it deploys a pod with a Longhorn volume.
Then it run various `fio` job (specified by user) to test multiple performance aspects of the volume (IOPs, bandwidth, latency).
The pod runs the test repeatedly and exposes the result as Prometheus metrics.
We then collect and visualize the data using Grafana.

Traditionally, kbench only deploy 1 single pod to test 1 volume. 
However, in this report, we will gradually scale up the number of Kbench pods.
Since each pod stress-tests its Longhorn volume, as the number of Kbench pods go up,
we can simulate the situation in which the cluster has many pods doing IO aggressively. 
From there we can see the performance characteristic of Longhorn storage system as there are more and more IO intensive workloads.

We also perform the tests in which Kbench pods are rate-limited. 
From the rate-limited tests, we can further verify the result from the stress tests.

### Longhorn Control Tests Design
The read and write performance tests above mostly care about Longhorn data plane. 
In order to discover the scalability of Longhorn control plane, we also run tests that has non-IO workloads. 
These tests will help us to answer questions such as:
1. Maximum number of Longhorn volumes inside the cluster
1. Maximum number of Longhorn volumes attached to a node
1. Maximum number of Longhorn replicas on to a node

### Maximum Volume Size Tests Design
From the experience and code analysis, the maximum Longhorn volume size is limited by the replica rebuilding time.
In this report, we will measure the replica rebuilding time as the size of Longhorn volume is getting bigger.
From there user can estimate the maximum volume size they can set given the information about how Longhorn it would take if Longhorn need to rebuild replicas for that volume.

### Backup and Restore Tests Design
In this report, we will measure the time it take to create and restore a backup of various size.
We will also show the space usage inside backup target.

### Load Balancing
In this report, we will distribute the load evenly across worker nodes:

1. Each worker nodes will have relative similar number of Kbench pods
2. Each worker nodes will have relative similar number of Longhorn replicas

This setup optimize efficiency of the cluster and Longhorn system. In practice, this balance is also what users usually strive for.

## Read Performance

### Random Read IOPs - Stress Tests

#### 1 control plane node + 3 worker nodes

We start with the cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-read-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
          - metric-exporter
          - -d
          - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-read-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
          - metric-exporter
          - -d
          - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: random-read-iops`: specify that we are running random read iops job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result: 
> * Local Path Provisioner: 10000
> * Longhorn: 22180

<img src="assets/medium-node-spec/read-performance/random-read-iops-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comment**: 
* Because Longhorn has 3 replicas, it can read from 3 replicas concurrently thus may produce better read performance

Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how random read IOPs is effected when there are more and more IO intensive pods.

Scaling workload from 1 to 3 pods.
> Result:
> * Each Kbench pod is able to achieve 10639 random read IOPs on its Longhorn volume
> * Total random IOPs can be achieved by all 3 Longhorn volumes is 31917

<img src="assets/medium-node-spec/read-performance/random-read-iops-1-3.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Since each EBS volume on the host is provisioned with 10000 IOPs. Total IOPs of 3 EBS volumes is around 30000
* It looks like Longhorn system is able to reach the maximum IOPs capacity of the 3 host EBS volumes. 

Scaling workload from 3 to 6, then 6 to 9, then 9 to 12, then 12 to 15
> Result:
> * At 6 pods, the average random read IOPs per Longhorn volume is 5320. Total random IOPs is 31920
> * At 9 pods, the average random read IOPs per Longhorn volume is 3541. Total random IOPs is 31869
> * At 12 pods, the average random read IOPs per Longhorn volume is 2633. Total random IOPs is 31596
> * At 15 pods, the average random read IOPs per Longhorn volume is 2116. Total random IOPs is 31740

<img src="./assets/medium-node-spec/read-performance/random-read-iops-6-9-12-15.png" alt="drawing" style="width:600px;"/>

Note: the areas with the while background in the graph are transition periods. We can ignore the data in these areas. 

**Comment**:
* From the scaling test so far, we can see that the total random read IOPs of all Longhorn volumes remain relative same around 31500 when the number of Kbench pods increase.
  If we call the average random read IOPs each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 31500. 
  Users can use this information to make some prediction for this cluster:
  * The upper bound limit that Longhorn system can achieve in this cluster is The value 31500 random read IOPs
  * If each of your workload pod is doing 1000 random IOPs in average, you can have estimatedly 31 pods
* When the user keeps scaling up number of pods eventually, this reciprocal relation (x * y = 31500) might no longer hold as the CPU contention and other factors kick in (i.e. x*y will be less and less)
* The bottleneck in this cluster seems to be the IOPs performance of the EBS volumes on host instead of CPU, memory, or network bandwidth.

#### 1 control plane node + 6 worker nodes
We double the number worker nodes (from 3 to 6) and double the number of Kbench pods (from 15 to 30)

> Result:
> * The average random read IOPs per Longhorn volume is the same 2127
> * The total random IOPs can be achieved by all Longhorn volumes is doubled 63810

<img src="./assets/medium-node-spec/read-performance/random-read-iops-with-6-nodes-30-pods.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Since the load is evenly distributed, we can see a linear relationship between total random IOPs and number of nodes: when the number of nodes is doubled, total random IOPs is doubled 
* From this reference, users can estimate how many worker nodes with the specified spec they need to achieve their target total random read IOPs

### Random Read IOPs - Rate Limited
In this test, we use 1 control plane node + 3 worker nodes. 
We add a rate limit to Kbench so that each Kbench pod is only doing 617 IOPs and observe the performance of Longhorn volumes.
Then we scale up the number of Kbench pod to 51 to see if the system is able to achieve 31467 random read IOPs.

<details>
<summary>We use this yaml manifest for the Kbench workload: </summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-read-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
            - name: RATE_IOPS
              value: "617"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

> Result:
> * The average random read IOPs per Longhorn volume is 616
> * The total random IOPs can be achieved by all 51 Longhorn volumes is 31416

<img src="./assets/medium-node-spec/read-performance/random-read-iops-rate-limited-617.png" alt="drawing" style="width:600px;"/>

**Comments:**
* As discussed in the [Random Read IOPs - Stress Tests](#random-read-iops---stress-tests) section above, we come up with the conclusion that
`If we call the average random read IOPs each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 31500.`
* The test result here further confirm this conclusion as x * y = 616*51 = 31416 (slightly lower than 31467 but it is insignificant difference)


### Sequential Read IOPs - Stress Tests

#### 1 control plane node + 3 worker nodes

We start with the cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-read-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
          - metric-exporter
          - -d
          - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-read-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE_IOPS
          #              value: "617"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: sequential-read-iops`: specify that we are running sequential read iops job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result:
> * Local Path Provisioner: 10000
> * Longhorn: 39772

<img src="./assets/medium-node-spec/read-performance/sequential-read-iops-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comments:**
* We observe Longhorn volume achieves much bigger sequential read IOPs compares to the local path volume. 
  This can be explained by 2 factors:
  * Longhorn volume has 3 replicas so it can read concurrently from multiple replicas (each replica is on a different EBS disk) while the local path volume is reading from single EBS disk.
  * When running Kbench with Longhorn volume, there is IO merging happens at both kernel layer and EBS layer. 
    The IO merging can cause multiple Kbench IOs to be submitted as 1 therefore increasing the IOPs.
    This IO merging effect doesn't happen when running Kbench with local path volume.
    See more detailed explanation at https://github.com/longhorn/longhorn/pull/7905#issuecomment-1945463272

Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how sequential read IOPs is effected when there are more and more IO intensive pods.

Scaling workload from 1 to 3 pods.

> Result:
> * Each Kbench pod is able to achieve 19840 sequential read IOPs on its Longhorn volume
> * Total random IOPs can be achieved by all 3 Longhorn volumes is: 59520

<img src="./assets/medium-node-spec/read-performance/sequential-read-iops-1-3.png" alt="drawing" style="width:600px;"/>

Scaling workload from 3 to 6, then 6 to 9, then 9 to 12, then 12 to 15

> Result:
> * At 6 pods, the average sequential read IOPs per Longhorn volume is 10132. Total sequential read IOPs is 60792
> * At 9 pods, the average sequential read IOPs per Longhorn volume is 6875. Total sequential read IOPs is 61875
> * At 12 pods, the average sequential read IOPs per Longhorn volume is 5210. Total sequential read IOPs is 62520
> * At 15 pods, the average sequential read IOPs per Longhorn volume is 4159. Total sequential read IOPs is 62385

<img src="./assets/medium-node-spec/read-performance/sequential-read-iops-6-9-12-15.png" alt="drawing" style="width:600px;"/>

Note: the areas with the while background in the graph are transition periods. We can ignore the data in these areas.

**Comment**:
* From the scaling test so far, we can see that the total sequential read IOPs of all Longhorn volumes remain relative same around 61500 when the number of Kbench pods increase.
  If we call the average sequential read IOPs each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 61500.
  Users can use this information to make some prediction for this cluster:
    * The upper bound limit that Longhorn system can achieve in this cluster is The value 61500 sequential read IOPs
    * If each of your workload pod is doing 1205 sequential IOPs in average, you can have estimatedly 51 pods
* When the user keeps scaling up number of pods eventually, this reciprocal relation (x * y = 61500) might no longer hold as the CPU contention and other factors kick in (i.e. x*y will be reduced)
* The bottleneck in this cluster seems to be the IOPs performance of the EBS volumes on host instead of CPU, memory, or network bandwidth.


#### 1 control plane node + 6 worker nodes

We double the number worker nodes (from 3 to 6) and double the number of Kbench pods (from 15 to 30)

> Result:
> * The average sequential read IOPs per Longhorn volume is relatively the same around 4150 
> * The total sequential IOPs can be achieved by all Longhorn volumes is doubled to 124500

<img src="./assets/medium-node-spec/read-performance/sequential-read-iops-with-6-nodes-30-pods.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Since the load is evenly distributed, we can see a linear relationship between total sequential IOPs and number of nodes: when the number of nodes is doubled, total sequential IOPs is doubled
* From this reference, users can estimate how many worker nodes with the specified spec they need to achieve their target total sequential read IOPs

### Sequential Read IOPs - Rate Limited

In this test, we use 1 control plane node + 3 worker nodes. 
We add a rate limit to Kbench so that each Kbench pod is only doing 1205 sequential read IOPs and observe the performance of Longhorn volumes. 
Then we scale up the number of Kbench pods to 51 to see if the system is able to achieve 61455 sequential read IOPs.

<details>
<summary>We use this yaml manifest for the Kbench workload: </summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-read-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
            - name: RATE_IOPS
              value: "1205"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

> Result:
> * The sequential read IOPs per Longhorn volume is 1190
> * The total sequential read IOPs can be achieved by all 51 Longhorn volumes is 60690

<img src="./assets/medium-node-spec/read-performance/sequential-read-iops-rate-limited-1205.png" alt="drawing" style="width:600px;"/>

**Comments:**
* As discussed in the [Sequential Read IOPs - Stress Tests](#sequential-read-iops---stress-tests) section above, we come up with the conclusion that
  `If we call the sequential read IOPs each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 61500.`
* The test result here further confirm this conclusion as x * y = 1190*51 = 60690 (slightly lower than 61500 but it is insignificant difference)



### Random Read Bandwidth - Stress Tests

#### 1 control plane node + 3 worker nodes

We start with the cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-read-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE_IOPS
          #              value: "1000"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-read-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE_IOPS
          #              value: "1000"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: random-read-bandwidth`: specify that we are running random read bandwidth job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result:
> * Local Path Provisioner: 362 MiB/s
> * Longhorn: 874 MiB/s

<img src="./assets/medium-node-spec/read-performance/random-read-bandwidth-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Because Longhorn has 3 replicas, it can read from 3 replicas concurrently thus may produce better read performance

Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how random read bandwidth is effected when there are more and more IO intensive pods.

Scaling workload from 1 to 3 pods.

> Result:
> * Each Kbench pod is able to achieve 386 MiB/s random read bandwidth on its Longhorn volume 
> * Total random read bandwidth can be achieved by all 3 Longhorn volumes is 1158

<img src="./assets/medium-node-spec/read-performance/random-read-bandwidth-1-3.png" alt="drawing" style="width:600px;"/>

**Comment:**
* Since each EBS volume on the host is provisioned with 360 MiB/s. Total IOPs of 3 EBS volumes is around 1080 MiB/s
It looks like Longhorn system is able to reach the maximum IOPs capacity of the 3 host EBS volumes. 
Longhorn is able to achieve slightly above 1080 MiB/s maybe due to small number of IO mergings or EBS actual bandwidth might be a bit higher the specified limit. 

Scaling workload from 3 to 6, then 6 to 9, then 9 to 12, then 12 to 15

> Result:
> * At 6 pods, the average random read bandwidth per Longhorn volume is 196 MiB/s. Total random bandwidth is 1176 MiB/s
> * At 9 pods, the average random read bandwidth per Longhorn volume is 131 MiB/s. Total random bandwidth is 1179 MiB/s
> * At 12 pods, the average random read bandwidth per Longhorn volume is 97.5 MiB/s. Total random bandwidth is 1170 MiB/s
> * At 15 pods, the average random read bandwidth per Longhorn volume is 77.5 MiB/s. Total random bandwidth is 1162 MiB/s

<img src="./assets/medium-node-spec/read-performance/random-read-bandwidth-6-9-12-15.png" alt="drawing" style="width:600px;"/>

**Comment:**
* From the scaling test so far, we can see that the total random read bandwidth of all Longhorn volumes remain relative same around 1160 MiB/s when the number of Kbench pods increase. 
  If we call the average random read bandwidth each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 1160. 
  Users can use this information to make some prediction for this cluster:
  * The upper bound limit that Longhorn system can achieve in this cluster is The value 1160 MiB/s random read bandwidth
  * If each of your workload pod is doing 22.7 MiB/s random read bandwidth in average, you can have estimatedly 51 pods
* When the user keeps scaling up number of pods eventually, this reciprocal relation (x * y = 1160) might no longer hold as the CPU contention and other factors kick in (i.e. x*y will be less and less)
* The bottleneck in this cluster seems to be the IOPs performance of the EBS volumes on host instead of CPU, memory, or network bandwidth.

#### 1 control plane node + 6 worker nodes

We double the number worker nodes (from 3 to 6) and double the number of Kbench pods (from 15 to 30)

> Result:
> * The average random read bandwidth per Longhorn volume is the same around 77.3 MiB/s
> * The total random bandwidth can be achieved by all Longhorn volumes is doubled 2319 MiB/s

<img src="./assets/medium-node-spec/read-performance/random-read-bandwidth-with-6-nodes-30-pods.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Since the load is evenly distributed, we can see a linear relationship between total random read bandwidth and number of nodes: when the number of nodes is doubled, total random read bandwidth is doubled
* From this reference, users can estimate how many worker nodes with the specified spec they need to achieve their target total random read bandwidth.


### Random Read Bandwidth - Rate Limited

In this test, we use 1 control plane node + 3 worker nodes.
We add a rate limit to Kbench so that each Kbench pod is only doing 22.7 MiB/s random read bandwidth and observe the performance of Longhorn volumes.
Then we scale up the number of Kbench pods to 51 to see if the system is able to achieve 1157 MiB/s random read bandwidth.

<details>
<summary>We use this yaml manifest for the Kbench workload: </summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-read-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
            - name: RATE
              value: "23244k,"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

> Result:
> * The random read bandwidth per Longhorn volume is 22.3 MiB/s
> * The total random read bandwidth can be achieved by all 51 Longhorn volumes is 1137 MiB/s

<img src="./assets/medium-node-spec/read-performance/random-read-bandwidth-rate-limited.png" alt="drawing" style="width:600px;"/>

**Comments:**
* As discussed in the [Random Read Bandwidth - Stress Tests](#random-read-bandwidth---stress-tests) section above, we come up with the conclusion that
  `If we call the random read bandwidth each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 1160.`
* The test result here further confirm this conclusion as x * y = 22.3*51 = 1137 (slightly lower than 1160 as the CPU contention and other factors kick in)

### Sequential Read Bandwidth - Stress Tests
#### 1 control plane node + 3 worker nodes
We start with the cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-read-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE
          #              value: "23244k,"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-read-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE
          #              value: "23244k,"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: sequential-read-bandwidth`: specify that we are running sequential read bandwidth job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result:
> * Local Path Provisioner: 362 MiB/s
> * Longhorn: 669 MiB/s

<img src="./assets/medium-node-spec/read-performance/sequential-read-bandwidth-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Because Longhorn has 3 replicas, it can read from 3 replicas concurrently thus may produce better read performance
* Note that the sequential read bandwidth is smaller than the random read bandwidth when testing against a single Longhorn volume of 3 replicas.
  We observed that this behavior happen when there is IO merging happen at kernel level and when the Longhorn volume has multiple replicas on different nodes.
  We don't understand the root cause of this behavior yet so we created a GitHub ticket to investigate it later https://github.com/longhorn/longhorn/issues/8108 .

Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how sequential read bandwidth is effected when there are more and more IO intensive pods.

Scaling workload from 1 to 3 pods.

> Result:
> * Each Kbench pod is able to achieve 378 MiB/s sequential read bandwidth on its Longhorn volume
> * Total sequential read bandwidth can be achieved by all 3 Longhorn volumes is 1134

<img src="./assets/medium-node-spec/read-performance/sequential-read-bandwidth-1-3.png" alt="drawing" style="width:600px;"/>

**Comment:**
* Since each EBS volume on the host is provisioned with 360 MiB/s. Total IOPs of 3 EBS volumes is around 1080 MiB/s
  It looks like Longhorn system is able to reach the maximum bandwidth capacity of the 3 host EBS volumes.
  Longhorn is able to achieve slightly above 1080 MiB/s maybe due to small number of IO mergings or EBS actual bandwidth might be a bit higher the specified limit.

Scaling workload from 3 to 6, then 6 to 9, then 9 to 12, then 12 to 15

> Result:
> * At 6 pods, the average sequential read bandwidth per Longhorn volume is 192 MiB/s. Total sequential read bandwidth is 1152 MiB/s
> * At 9 pods, the average sequential read bandwidth per Longhorn volume is 126 MiB/s. Total sequential read bandwidth is 1179 MiB/s
> * At 12 pods, the average sequential read bandwidth per Longhorn volume is 94 MiB/s. Total sequential read bandwidth is 1128 MiB/s
> * At 15 pods, the average sequential read bandwidth per Longhorn volume is 74 MiB/s. Total sequential read bandwidth is 1110 MiB/s

<img src="./assets/medium-node-spec/read-performance/sequential-read-bandwidth-6-9-12-15.png" alt="drawing" style="width:600px;"/>

**Comment:**
* From the scaling test so far, we can see that the total sequential read bandwidth of all Longhorn volumes remain relative same around 1110 MiB/s when the number of Kbench pods increase.
  If we call the average sequential read bandwidth each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 1110.
  Users can use this information to make some prediction for this cluster:
    * The upper bound limit that Longhorn system can achieve in this cluster is The value 1110 MiB/s sequential read bandwidth
    * If each of your workload pod is doing 21.7 MiB/s sequential read bandwidth in average, you can have estimatedly 51 pods
* When the user keeps scaling up number of pods eventually, this reciprocal relation (x * y = 1160) might no longer hold as the CPU contention and other factors kick in (i.e. x*y will be less and less)
* The bottleneck in this cluster seems to be the IOPs performance of the EBS volumes on host instead of CPU, memory, or network bandwidth.

#### 1 control plane node + 6 worker nodes


We double the number worker nodes (from 3 to 6) and double the number of Kbench pods (from 15 to 30)


> Result:
> * The average sequential read bandwidth per Longhorn volume is the same around 74 MiB/s
> * The total sequential read bandwidth can be achieved by all Longhorn volumes is doubled 2220 MiB/s


<img src="./assets/medium-node-spec/read-performance/sequential-read-bandwidth-with-6-nodes-30-pods.png" alt="drawing" style="width:600px;"/>


**Comment**:

* Since the load is evenly distributed, we can see a linear relationship between total sequential read bandwidth and number of nodes: when the number of nodes is doubled, total sequential read bandwidth is doubled

* From this reference, users can estimate how many worker nodes with the specified spec they need to achieve their target total sequential read bandwidth.

### Sequential Read Bandwidth - Rate Limited

In this test, we use 1 control plane node + 3 worker nodes.
We add a rate limit to Kbench so that each Kbench pod is only doing 21.7 MiB/s sequential read bandwidth and observe the performance of Longhorn volumes.
Then we scale up the number of Kbench pods to 51 to see if the system is able to achieve 1107 MiB/s sequential read bandwidth.

<details>
<summary>We use this yaml manifest for the Kbench workload: </summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-read-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
            - name: RATE
              value: "22220k,"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

> Result:
> * The sequential read bandwidth per Longhorn volume is 21.7 MiB/s
> * The total sequential read bandwidth can be achieved by all 51 Longhorn volumes is 1107 MiB/s

<img src="./assets/medium-node-spec/read-performance/sequential-read-bandwidth-rate-limited.png" alt="drawing" style="width:600px;"/>

**Comments:**
* As discussed in the [Sequential Read Bandwidth - Stress Tests](#sequential-read-bandwidth---stress-tests) section above, we come up with the conclusion that
  `If we call the sequential read bandwidth each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 1110.`
* The test result here further confirm this conclusion as x * y = xxx*51 = 1107 (relatively same as 1110) 


### Random Read Latency - Stress Tests
In this test, we use a cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-read-latency"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-read-latency"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: random-read-latency`: specify that we are running random read latency job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result:
> * Local Path Provisioner: 500 microsecond
> * Longhorn: 750 microsecond

<img src="./assets/medium-node-spec/read-performance/random-read-latency-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Because IO path of Longhorn volume is longer than local path provisioner, it is expected that Longhorn volume has bigger random read latency 

Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how random read latency is effected when there are more and more pods.

> Result:

| Number of Kbench pods | Average Random Read Latency (ns) | 
|-----------------------|----------------------------------|
| 1                     | 742955                           |
| 3                     | 750170                           | 
| 6                     | 774555                           | 
| 9                     | 790714                           |
| 12                    | 810890                           |
| 15                    | 832421                           |
| 18                    | 858495                           |
| 21                    | 876277                           |
| 24                    | 902481                           |
| 27                    | 934727                           |
| 30                    | 972684                           |
| 33                    | 1014888                          |
| 36                    | 1117489                          |
| 39                    | 1212721                          |
| 42                    | 1304671                          |
| 45                    | 1391987                          |
| 48                    | 1488104                          |
| 51                    | 1581291                          |

<img src="./assets/medium-node-spec/read-performance/random-read-latency-1-51.png" alt="drawing" style="width:600px;"/>

**Comment**:
* As the number of kbench pods increase, the average random read latency of each Longhorn volume increase in non-linear fashion. 


### Sequential Read Latency - Stress Tests
In this test, we use a cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-read-latency"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-read-latency"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: read-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: sequential-read-latency`: specify that we are running sequential read latency job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result:
> * Local Path Provisioner: 480 microsecond
> * Longhorn: 740 microsecond

<img src="./assets/medium-node-spec/read-performance/sequential-read-latency-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Because IO path of Longhorn volume is longer than local path provisioner, it is expected that Longhorn volume has bigger sequential read latency

Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how sequential read latency is effected when there are more and more pods.

> Result:

| Number of Kbench pods | Average Random Read Latency (ns) | 
|-----------------------|----------------------------------|
| 1                     | 736699                           |
| 3                     | 745284                           | 
| 6                     | 766109                           | 
| 9                     | 790306                           |
| 12                    | 808654                           |
| 15                    | 827570                           |
| 18                    | 847532                           |
| 21                    | 869385                           |
| 24                    | 898042                           |
| 27                    | 926866                           |
| 30                    | 959980                           |
| 33                    | 1029409                          |
| 36                    | 1122368                          |
| 39                    | 1211142                          |
| 42                    | 1306095                          |
| 45                    | 1397748                          |
| 48                    | 1493102                          |
| 51                    | 1582556                          |

<img src="./assets/medium-node-spec/read-performance/sequential-read-latency-1-51.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Sequential read latency result is similar to random read latency.
* As the number of kbench pods increase, the average sequential read latency of each Longhorn volume increase in non-linear fashion.


## Write Performance

### Random Write IOPs - Stress Tests
#### 1 control plane node + 3 worker nodes

We start with the cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-write-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
          - metric-exporter
          - -d
          - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-write-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
          - metric-exporter
          - -d
          - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: random-write-iops`: specify that we are running random write iops job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result:
> * Local Path Provisioner: 9980
> * Longhorn: 1150

<img src="assets/medium-node-spec/write-performance/random-write-iops-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Longhorn write speed is slower than local path volume because of several factors:
  * Because Longhorn has 3 replicas, it has to write to 3 replicas for each IO.
  * By default, Longhorn has revision counter enabled which means that for each write IO, Longhorn has to do an additional write IO to write the revision counter.
  * Longhorn v1 tgt-iscsi stack introduces some overhead.

Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how random write IOPs is effected when there are more and more IO intensive pods.

Scaling workload from 1 to 3 pods.
> Result:
> * Each Kbench pod is able to achieve 1180 random write IOPs on its Longhorn volume
> * Total random write IOPs can be achieved by all 3 Longhorn volumes is 3540

<img src="assets/medium-node-spec/write-performance/random-write-iops-1-3.png" alt="drawing" style="width:600px;"/>

Scaling workload from 3 to 6, then 6 to 9, then 9 to 12, then 12 to 15
> Result:
> * At 6 pods, the average random write IOPs per Longhorn volume is 852. Total random write IOPs is 5112
> * At 9 pods, the average random write IOPs per Longhorn volume is 576. Total random write IOPs is 5184
> * At 12 pods, the average random write IOPs per Longhorn volume is 436. Total random write IOPs is 5232
> * At 15 pods, the average random write IOPs per Longhorn volume is 350. Total random write IOPs is 5250

<img src="./assets/medium-node-spec/write-performance/random-write-iops-6-9-12-15.png" alt="drawing" style="width:600px;"/>

**Comment**:
* From the scaling test so far, we can see that the total random write IOPs of all Longhorn volumes remain relative same around 5250 when the number of Kbench pods increase.
* Since each EBS volume on the host is provisioned with 10000 IOPs. It looks like Longhorn system is able to reach half of the IOPs capacity of the host EBS volumes.
* If we call the average random write IOPs each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 5250.
  Users can use this information to make some prediction for this cluster:
    * The upper bound limit that Longhorn system can achieve in this cluster is the value 5250 random write IOPs
    * If each of your workload pod is doing 102 random write IOPs in average, you can have estimatedly 51 pods
* When the user keeps scaling up number of pods eventually, this reciprocal relation (x * y = 5250) might no longer hold as the CPU contention and other factors kick in (i.e. x*y will be less and less)
* The bottleneck in this cluster seems to be the IOPs performance of the EBS volumes on host instead of CPU, memory, or network bandwidth.

#### 1 control plane node + 6 worker nodes

We double the number worker nodes (from 3 to 6) and double the number of Kbench pods (from 15 to 30)


> Result:
> * The average random write IOPs per Longhorn volume is the same around 350
> * The total random write IOPs can be achieved by all Longhorn volumes is doubled 10500


<img src="./assets/medium-node-spec/write-performance/random-write-iops-with-6-nodes-30-pods.png" alt="drawing" style="width:600px;"/>


**Comment**:
* Since the load is evenly distributed, we can see a linear relationship between total random write IOPs and number of nodes: when the number of nodes is doubled, total random write IOPs is doubled
* From this reference, users can estimate how many worker nodes with the specified spec they need to achieve their target total random write IOPs

### Random Write IOPs - Rate Limited
In this test, we use 1 control plane node + 3 worker nodes.
We add a rate limit to Kbench so that each Kbench pod is only doing 102 random write IOPs and observe the performance of Longhorn volumes.
Then we scale up the number of Kbench pod to 51 to see if the system is able to achieve 102 * 51=5202 random write IOPs.

<details>
<summary>We use this yaml manifest for the Kbench workload: </summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-write-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
            - name: RATE_IOPS
              value: "102"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 5
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

> Result:
> * The average random write IOPs per Longhorn volume is 102
> * The total random write IOPs can be achieved by all 51 Longhorn volumes is 5202

<img src="./assets/medium-node-spec/write-performance/random-write-iops-rate-limited.png" alt="drawing" style="width:600px;"/>

**Comments:**
* As discussed in the [Random Write IOPs - Stress Tests](#random-write-iops---stress-tests) section above, we come up with the conclusion that
  `If we call the average random write IOPs each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 5250.`
* The test result here further confirm this conclusion as 102 * 51 = 5202

### Sequential Write IOPs - Stress Tests

We start with the cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-write-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
          - metric-exporter
          - -d
          - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-write-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 30
            periodSeconds: 10
          command:
          - metric-exporter
          - -d
          - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: sequential-write-iops`: specify that we are running sequential write iops job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result:
> * Local Path Provisioner: 10100
> * Longhorn: 2340

<img src="assets/medium-node-spec/write-performance/sequential-write-iops-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Longhorn write speed is slower than local path volume because of several factors:
    * Because Longhorn has 3 replicas, it has to write to 3 replicas for each IO.
    * By default, Longhorn has revision counter enabled which means that for each write IO, Longhorn has to do an additional write IO to write the revision counter.
    * Longhorn v1 tgt-iscsi stack introduces some overhead.

Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how sequential write IOPs is effected when there are more and more IO intensive pods.

Scaling workload from 1 to 3 pods.
> Result:
> * Each Kbench pod is able to achieve 2350 sequential write IOPs on its Longhorn volume
> * Total sequential write IOPs can be achieved by all 3 Longhorn volumes is 7050

<img src="assets/medium-node-spec/write-performance/sequential-write-iops-1-3.png" alt="drawing" style="width:600px;"/>

Scaling workload from 3 to 6, then 6 to 9, then 9 to 12, then 12 to 15
> Result:
> * At 6 pods, the average sequential write IOPs per Longhorn volume is 1745. Total sequential write IOPs is 10470
> * At 9 pods, the average sequential write IOPs per Longhorn volume is 1165. Total sequential write IOPs is 10485
> * At 12 pods, the average sequential write IOPs per Longhorn volume is 871. Total sequential write IOPs is 10452
> * At 15 pods, the average sequential write IOPs per Longhorn volume is 695. Total sequential write IOPs is 10425

<img src="./assets/medium-node-spec/write-performance/sequential-write-iops-6-9-12-15.png" alt="drawing" style="width:600px;"/>

**Comment**:
* From the scaling test so far, we can see that the total sequential write IOPs of all Longhorn volumes remain relative same around 10400 when the number of Kbench pods increase.
* Since each EBS volume on the host is provisioned with 10000 IOPs. It looks like Longhorn system is able to reach the IOPs capacity of the host EBS volumes.
* If we call the average sequential write IOPs each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 10400.
  Users can use this information to make some prediction for this cluster:
    * The upper bound limit that Longhorn system can achieve in this cluster is the value 10400 sequential write IOPs
    * If each of your workload pod is doing 203 sequential write IOPs in average, you can have estimatedly 51 pods
* When the user keeps scaling up number of pods eventually, this reciprocal relation (x * y = 10400) might no longer hold as the CPU contention and other factors kick in (i.e. x*y will be less and less)
* The bottleneck in this cluster seems to be the IOPs performance of the EBS volumes on host instead of CPU, memory, or network bandwidth.

#### 1 control plane node + 6 worker nodes

[//]: # (We double the number worker nodes &#40;from 3 to 6&#41; and double the number of Kbench pods &#40;from 15 to 30&#41;)

[//]: # ()
[//]: # ()
[//]: # (> Result:)

[//]: # (> * The average random write IOPs per Longhorn volume is the same around xxx)

[//]: # (> * The total random write IOPs can be achieved by all Longhorn volumes is doubled yyy)

[//]: # ()
[//]: # ()
[//]: # (<img src="./assets/medium-node-spec/write-performance/random-write-iops-with-6-nodes-30-pods.png" alt="drawing" style="width:600px;"/>)

[//]: # ()
[//]: # ()
[//]: # (**Comment**:)

[//]: # (* Since the load is evenly distributed, we can see a linear relationship between total random write IOPs and number of nodes: when the number of nodes is doubled, total random write IOPs is doubled)

[//]: # (* From this reference, users can estimate how many worker nodes with the specified spec they need to achieve their target total random write IOPs)

[//]: # ()

### Sequential Write IOPs - Rate Limited

In this test, we use 1 control plane node + 3 worker nodes.
We add a rate limit to Kbench so that each Kbench pod is only doing 203 sequential write IOPs and observe the performance of Longhorn volumes.
Then we scale up the number of Kbench pod to 51 to see if the system is able to achieve 203 * 51=10353 sequential write IOPs.

<details>
<summary>We use this yaml manifest for the Kbench workload: </summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-write-iops"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
            - name: RATE_IOPS
              value: "203"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 5
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

> Result:
> * The average sequential write IOPs per Longhorn volume is 201
> * The total sequential write IOPs can be achieved by all 51 Longhorn volumes is 10251

<img src="./assets/medium-node-spec/write-performance/sequential-write-iops-rate-limited.png" alt="drawing" style="width:600px;"/>

**Comments:**
* As discussed in the [Sequential Write IOPs - Stress Tests](#sequential-write-iops---stress-tests) section above, we come up with the conclusion that
  `If we call the average sequential write IOPs each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 10400.`
* The test result here further confirm this conclusion as 201 * 51 = 10251 (slightly lower than 10400)

### Random Write Bandwidth - Stress Tests
#### 1 control plane node + 3 worker nodes

We start with the cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-write-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE
          #              value: "22220k,"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-write-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE
          #              value: "22220k,"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: random-write-bandwidth`: specify that we are running random write bandwidth job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result:
> * Local Path Provisioner: 362 MiB/s
> * Longhorn: 159 MiB/s

<img src="./assets/medium-node-spec/write-performance/random-write-bandwidth-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Longhorn write speed is slower than local path volume because of several factors:
    * Because Longhorn has 3 replicas, it has to write to 3 replicas for each IO.
    * By default, Longhorn has revision counter enabled which means that for each write IO, Longhorn has to do an additional write IO to write the revision counter.
    * Longhorn v1 tgt-iscsi stack introduces some overhead.


Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how random write bandwidth is effected when there are more and more IO intensive pods.


Scaling workload from 1 to 3 pods.


> Result:
> * Each Kbench pod is able to achieve 118 MiB/s random write bandwidth on its Longhorn volume
> * Total random write bandwidth can be achieved by all 3 Longhorn volumes is 354 MiB/s


<img src="./assets/medium-node-spec/write-performance/random-write-bandwidth-1-3.png" alt="drawing" style="width:600px;"/>


**Comment:**
* Since each EBS volume on the host is provisioned with 360 MiB/s. 
  It looks like Longhorn system is able to reach the maximum bandwidth capacity of the host EBS disks.

Scaling workload from 3 to 6, then 6 to 9, then 9 to 12, then 12 to 15

> Result:
> * At 6 pods, the average random write bandwidth per Longhorn volume is 63.2 MiB/s. Total random write bandwidth is 379.2 MiB/s
> * At 9 pods, the average random write bandwidth per Longhorn volume is 42.2 MiB/s. Total random write bandwidth is 379.8 MiB/s
> * At 12 pods, the average random write bandwidth per Longhorn volume is 31.4 MiB/s. Total random write bandwidth is 376.8 MiB/s
> * At 15 pods, the average random write bandwidth per Longhorn volume is 25.1 MiB/s. Total random write bandwidth is 376.5 MiB/s


<img src="./assets/medium-node-spec/write-performance/random-write-bandwidth-6-9-12-15.png" alt="drawing" style="width:600px;"/>


**Comment:**

* From the scaling test so far, we can see that the total random write bandwidth of all Longhorn volumes remain relative same around 376.5 MiB/s when the number of Kbench pods increase.
  If we call the average random write bandwidth each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 376.5.
  Users can use this information to make some prediction for this cluster:
    * The upper bound limit that Longhorn system can achieve in this cluster is The value 376.5 MiB/s random write bandwidth
    * If each of your workload pod is doing 7.38 MiB/s random read bandwidth in average, you can have estimatedly 51 pods
* When the user keeps scaling up number of pods eventually, this reciprocal relation (x * y = 376.5) might no longer hold as the CPU contention and other factors kick in (i.e. x*y will be less and less)
* The bottleneck in this cluster seems to be the IOPs performance of the EBS volumes on host instead of CPU, memory, or network bandwidth.


#### 1 control plane node + 6 worker nodes

[//]: # ()
[//]: # (We double the number worker nodes &#40;from 3 to 6&#41; and double the number of Kbench pods &#40;from 15 to 30&#41;)

[//]: # ()
[//]: # (> Result:)

[//]: # (> * The average random read bandwidth per Longhorn volume is the same around 77.3 MiB/s)

[//]: # (> * The total random bandwidth can be achieved by all Longhorn volumes is doubled 2319 MiB/s)

[//]: # ()
[//]: # (<img src="./assets/medium-node-spec/read-performance/random-read-bandwidth-with-6-nodes-30-pods.png" alt="drawing" style="width:600px;"/>)

[//]: # ()
[//]: # (**Comment**:)

[//]: # (* Since the load is evenly distributed, we can see a linear relationship between total random read bandwidth and number of nodes: when the number of nodes is doubled, total random read bandwidth is doubled)

[//]: # (* From this reference, users can estimate how many worker nodes with the specified spec they need to achieve their target total random read bandwidth.)

### Random Write Bandwidth - Rate Limited Tests

In this test, we use 1 control plane node + 3 worker nodes.
We add a rate limit to Kbench so that each Kbench pod is only doing 7.38 MiB/s random write bandwidth and observe the performance of Longhorn volumes.
Then we scale up the number of Kbench pods to 51 to see if the system is able to achieve 376.38 MiB/s random write bandwidth.

<details>
<summary>We use this yaml manifest for the Kbench workload: </summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-write-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
            - name: RATE
              value: ",7559k"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

> Result:
> * The random write bandwidth per Longhorn volume is 7.38 MiB/s
> * The total random write bandwidth can be achieved by all 51 Longhorn volumes is 376.38 MiB/s

<img src="./assets/medium-node-spec/write-performance/ramdom-write-bandwidth-rate-limited.png" alt="drawing" style="width:600px;"/>

**Comments:**
* As discussed in the [Random Write Bandwidth - Stress Tests](#random-write-bandwidth---stress-tests) section above, we come up with the conclusion that
  `If we call the random write bandwidth each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 376.5.`
* The test result here further confirm this conclusion as x * y = 7.38*51 = 376.38 


### Sequential Write Bandwidth - Stress Tests

We start with the cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-write-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE
          #              value: "22220k,"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-write-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE
          #              value: "22220k,"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: sequential-write-bandwidth`: specify that we are running sequential write bandwidth job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result:
> * Local Path Provisioner: 362 MiB/s
> * Longhorn: 291 MiB/s

<img src="./assets/medium-node-spec/write-performance/sequential-write-bandwidth-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Longhorn write speed is slower than local path volume because of several factors:
    * Because Longhorn has 3 replicas, it has to write to 3 replicas for each IO.
    * By default, Longhorn has revision counter enabled which means that for each write IO, Longhorn has to do an additional write IO to write the revision counter.
    * Longhorn v1 tgt-iscsi stack introduces some overhead.


Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how sequential write bandwidth is effected when there are more and more IO intensive pods.

Scaling workload from 1 to 3 pods.

> Result:
> * Each Kbench pod is able to achieve 127 MiB/s sequential write bandwidth on its Longhorn volume
> * Total sequential write bandwidth can be achieved by all 3 Longhorn volumes is 381 MiB/s


<img src="./assets/medium-node-spec/write-performance/sequential-write-bandwidth-1-3.png" alt="drawing" style="width:600px;"/>


**Comment:**
* Since each EBS volume on the host is provisioned with 360 MiB/s.
  It looks like Longhorn system is able to reach the maximum bandwidth capacity of the host EBS disks.

Scaling workload from 3 to 6, then 6 to 9, then 9 to 12, then 12 to 15

> Result:
> * At 6 pods, the average sequential write bandwidth per Longhorn volume is 63.3 MiB/s. Total sequential write bandwidth is 379.8 MiB/s
> * At 9 pods, the average sequential write bandwidth per Longhorn volume is 42.6 MiB/s. Total sequential write bandwidth is 383.4 MiB/s
> * At 12 pods, the average sequential write bandwidth per Longhorn volume is 31.8 MiB/s. Total sequential write bandwidth is 381.6 MiB/s
> * At 15 pods, the average sequential write bandwidth per Longhorn volume is 25.4 MiB/s. Total sequential write bandwidth is 381 MiB/s


<img src="./assets/medium-node-spec/write-performance/sequential-write-bandwidth-6-9-12-15.png" alt="drawing" style="width:600px;"/>


**Comment:**

* From the scaling test so far, we can see that the total sequential write bandwidth of all Longhorn volumes remain relative same around 380 MiB/s when the number of Kbench pods increase.
  If we call the average sequential write bandwidth each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 380.
  Users can use this information to make some prediction for this cluster:
    * The upper bound limit that Longhorn system can achieve in this cluster is The value 380 MiB/s sequential write bandwidth
    * If each of your workload pod is doing 7.45 MiB/s random read bandwidth in average, you can have estimatedly 51 pods
* When the user keeps scaling up number of pods eventually, this reciprocal relation (x * y = 380) might no longer hold as the CPU contention and other factors kick in (i.e. x*y will be less and less)
* The bottleneck in this cluster seems to be the IOPs performance of the EBS volumes on host instead of CPU, memory, or network bandwidth.


#### 1 control plane node + 6 worker nodes

[//]: # ()
[//]: # (We double the number worker nodes &#40;from 3 to 6&#41; and double the number of Kbench pods &#40;from 15 to 30&#41;)

[//]: # ()
[//]: # (> Result:)

[//]: # (> * The average random read bandwidth per Longhorn volume is the same around 77.3 MiB/s)

[//]: # (> * The total random bandwidth can be achieved by all Longhorn volumes is doubled 2319 MiB/s)

[//]: # ()
[//]: # (<img src="./assets/medium-node-spec/read-performance/random-read-bandwidth-with-6-nodes-30-pods.png" alt="drawing" style="width:600px;"/>)

[//]: # ()
[//]: # (**Comment**:)

[//]: # (* Since the load is evenly distributed, we can see a linear relationship between total random read bandwidth and number of nodes: when the number of nodes is doubled, total random read bandwidth is doubled)

[//]: # (* From this reference, users can estimate how many worker nodes with the specified spec they need to achieve their target total random read bandwidth.)


### Sequential Write Bandwidth - Rate Limited

In this test, we use 1 control plane node + 3 worker nodes.
We add a rate limit to Kbench so that each Kbench pod is only doing 7.45 MiB/s sequential write bandwidth and observe the performance of Longhorn volumes.
Then we scale up the number of Kbench pods to 51 to see if the system is able to achieve 379.9 MiB/s sequential write bandwidth.

<details>
<summary>We use this yaml manifest for the Kbench workload: </summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-write-bandwidth"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
            - name: RATE
              value: ",7629k"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

> Result:
> * The sequential write bandwidth per Longhorn volume is 7.48 MiB/s
> * The total sequential write bandwidth can be achieved by all 51 Longhorn volumes is 381.5 MiB/s

<img src="./assets/medium-node-spec/write-performance/sequential-write-bandwidth-rate-limited.png" alt="drawing" style="width:600px;"/>

**Comments:**
* As discussed in the [Sequential Write Bandwidth - Stress Tests](#sequential-write-bandwidth---stress-tests) section above, we come up with the conclusion that
  `If we call the sequential write bandwidth each volume can achieve (x) and the number of volumes (y), they form a reciprocal function: x * y = 380.`
* The test result here further confirm this conclusion as x * y = 7.48*51 = 381.5


### Random Write Latency - Stress Tests

In this test, we use a cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-write-latency"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE
          #              value: ",7559k"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "random-write-latency"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE
          #              value: ",7559k"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: random-write-latency`: specify that we are running random write latency job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result:
> * Local Path Provisioner: 810 microsecond
> * Longhorn: 2040 microsecond

<img src="./assets/medium-node-spec/write-performance/random-write-latency-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Because IO path of Longhorn volume is longer than local path provisioner, it is expected that Longhorn volume has bigger random write latency

Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how random write latency is effected when there are more and more pods.

> Result:

| Number of Kbench pods | Average Random Write Latency (ns) | 
|-----------------------|-----------------------------------|
| 1                     | 2039519                           |
| 3                     | 2056904                           | 
| 6                     | 2091819                           | 
| 9                     | 2135070                           |
| 12                    | 2253089                           |
| 15                    | 2807773                           |
| 18                    | 3373824                           |
| 21                    | 3938172                           |
| 24                    | 4503630                           |
| 27                    | 5071816                           |
| 30                    | 5640033                           |
| 33                    | 6208153                           |
| 36                    | 6771033                           |
| 39                    | 7341914                           |
| 42                    | 7905373                           |
| 45                    | 8480925                           |
| 48                    | 9040640                           |
| 51                    | 9609189                           |

<img src="./assets/medium-node-spec/write-performance/random-write-latency-1-51.png" alt="drawing" style="width:600px;"/>

**Comment**:
* As the number of kbench pods increase:
  * From 0 to 12 pods, the average random write latency of each Longhorn volume increase in linear fashion with smaller rate
  * From 12 to 51 pods, the average random write latency of each Longhorn volume increase in linear fashion with bigger rate

### Sequential Write Latency - Stress Tests

In this test, we use a cluster that has 1 control plane node + 3 worker nodes.

First, we do a comparison between a single RWO Longhorn PVC against a single Local Path Provisioner volume.
We deploy 1 Kbench pod which attached a Local Path Provisioner PVC.
Then we delete the above Kbench pod and PVC and repeat the test with Longhorn PVC instead.

We use this yaml manifest for the Kbench workload:
<details>
<summary>With local path provisioner storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-write-latency"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE
          #              value: ",7559k"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "local-path"
        resources:
          requests:
            storage: 20Gi
```
</details>

<details>
<summary>With longhorn storageclass</summary>
<br>

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: test-sts
  namespace: default
spec:
  serviceName: test-sts
  replicas: 1
  selector:
    matchLabels:
      app: test-sts
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: test-sts
    spec:
      containers:
        - name: kbench
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          env:
            - name: MODE
              value: "sequential-write-latency"
            - name: OUTPUT
              value: /test-result/device
            - name: FILE_NAME
              value: "/volume/test"
            - name: SIZE
              value: "15G"
            - name: CPU_IDLE_PROF
              value: "disabled"
            - name: SKIP_PARSE
              value: "true"
            - name: LONG_RUN
              value: "true"
          #            - name: RATE
          #              value: ",7559k"
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
        - name: metric-exporter
          image: phanle1010/kbench:dev
          imagePullPolicy: Always
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - '[ "$(ls -A /test-result)" ]'
            initialDelaySeconds: 22
            periodSeconds: 10
          command:
            - metric-exporter
            - -d
            - start
          env:
            - name: DATA_DIR
              value: /test-result
            - name: VOLUME_ACCESS_MODE
              value: rwo
            - name: TEST_MODE
              value: write-only
            - name: RATE_LIMIT_TYPE
              value: no-rate-limit
          ports:
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: vol
              mountPath: /volume/
            - name: shared-data
              mountPath: /test-result
      volumes:
        - name: shared-data
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: vol
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "longhorn"
        resources:
          requests:
            storage: 20Gi
```
</details>

Some of the important Kbench parameters we would like to call out are:
* `MODE: sequential-write-latency`: specify that we are running sequential write latency job. # TODO add the link to the job here
* `SIZE: 15G`: the `fio` test size is 15G, this will avoid cache effect.
* PVC size is 20G.

> Result:
> * Local Path Provisioner: 803 microsecond
> * Longhorn: 2028 microsecond

<img src="./assets/medium-node-spec/write-performance/sequential-write-latency-local-path-vs-longhorn.png" alt="drawing" style="width:600px;"/>

**Comment**:
* Because IO path of Longhorn volume is longer than local path provisioner, it is expected that Longhorn volume has bigger sequential write latency

Next, we use Kbench with Longhorn PVCs and scale up the number of Kbench pods to see how sequential write latency is effected when there are more and more pods.

> Result:

| Number of Kbench pods | Average Sequential Write Latency (ns) | 
|-----------------------|---------------------------------------|
| 1                     | 2027403                               |
| 3                     | 2064941                               | 
| 6                     | 2101946                               | 
| 9                     | 2135524                               |
| 12                    | 2256725                               |
| 15                    | 2812809                               |
| 18                    | 3377877                               |
| 21                    | 3942233                               |
| 24                    | 4503992                               |
| 27                    | 5078192                               |
| 30                    | 5640632                               |
| 33                    | 6204730                               |
| 36                    | 6770942                               |
| 39                    | 7343912                               |
| 42                    | 7906260                               |
| 45                    | 8475788                               |
| 48                    | 9035704                               |
| 51                    | 9611938                               |

<img src="./assets/medium-node-spec/write-performance/sequential-write-latency-1-51.png" alt="drawing" style="width:600px;"/>

**Comment**:
* As the number of kbench pods increase:
    * From 0 to 12 pods, the average sequential write latency of each Longhorn volume increase in linear fashion with smaller rate
    * From 12 to 51 pods, the average sequential write latency of each Longhorn volume increase in linear fashion with bigger rate

## Longhorn Control Plane Performance

## Volume Maximum Size

## Backup and Restore Speed


