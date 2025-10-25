# Replica Balance Scheduling

## Summary

When scheduling replicas, Longhorn currently selects a disk with the most usable storage. This simple heuristic can lead to unbalanced storage usage across nodes and disks, reducing flexibility for future scheduling and potentially concentrating replicas on fewer nodes.

This proposal introduces a `balance-aware` disk selection policy. Instead of always picking the disk with `maximum free space`, the scheduler simulates placing a replica and chooses the placement that results in the most balanced distribution of usable storage:

- First across nodes

- Then across disks within the selected node

This ensures that storage capacity remains evenly utilized, improving fault tolerance and long-term stability.

### Related Issues

- https://github.com/longhorn/longhorn/issues/10512

### Goals

- Improve disk selection by introducing a `balance-aware` scheduling algorithm, reducing uneven storage usage across nodes and disks.

### Non-goals

- Provide a **perfectly** balanced global scheduling strategy.
Replica scheduling in Longhorn involves multiple factors such as:

    - Tag matching
    - Replica anti-affinity rules
    - Node/disk readiness
    - Reserved/over-provisioned capacity

- This proposal only improves the disk selection stage once other filters are applied.
The new balance-aware method tries to pick the most balanced disk within the eligible candidates.

## Proposal Design

### Original

#### Max Usable Storage:
 - `Disk_Usable_Storage = (Disk.StorageAvailable - Disk.StorageReserved)`

### Formula 

#### 1. Balance Factor Formula by Usable Storage: 

- `Disk_Usable_Storage = (Disk.StorageAvailable - Disk.StorageReserved) - Disk.StorageScheduled`
- Lower score = more balanced distribution.

- Formula:

    $$\text{BalanceScore}(X) = \frac{\max(X) - \min(X)}{\text{mean}(X)}$$

    Where:
    - X = set of usable storage values (per node or per disk).


#### 2. Balance Factor Formula by Usable Storage Ratio: 

- `Disk_Usable_Storage = (Disk.StorageAvailable - Disk.StorageReserved) - Disk.StorageScheduled)`
- `Disk_Total = Disk.StorageMaximum - Disk.StorageReserved`
- Formula:

    $$\text{usableRatio}(\text{disk}) = \dfrac{\text{usable}(\text{disk})}{\text{totalCapacity}(\text{disk})}$$


    $$\text{BalanceScore}(X)  = \frac{\max(\text{usableRatio}(X)) - \min(\text{usableRatio}(X))}{\text{mean}(\text{usableRatio}(X))}$$

    Where:
    - X = set of usable storage ratio values (per node or per disk).

#### 3. Balance Factor Formula by Hybrid: 

- Formula:

    $$
    \text{Score} = \alpha \cdot \text{BalanceScore(Absolute)} + (1 - \alpha) \cdot \text{BalanceScore(Ratio)}
    $$

    Where $\alpha \in [0,1]$ controls the trade-off:
    - $\alpha = 1$: use absolute balance only  
    - $\alpha = 0$: use ratio balance only  
    - $\alpha = 0.5$: balanced mix (equal weight)

**Comparison Table**

- Disk A: 2 TB total, 200 GiB free → 10% free
- Disk B: 200 GiB total, 40 GiB free → 20% free

| Formula                | Pros                                                                 | Cons                                                                 |
|-------------------------|----------------------------------------------------------------------|----------------------------------------------------------------------|
| **Absolute Usable**     | - Ensures large absolute free space remains<br>- Prevents "out of space" errors | - Ignores disk size differences<br>- lead to very uneven utilization ratio across disks (Prefer A)  |
| **Usable Ratio (%)**  | - Fairness across heterogeneous disk sizes<br>- Keeps utilization percentages aligned | - May over-favor large disks<br>- May reduce absolute headroom on smaller disks (Prefer B) |
| **Hybrid (Weighted Mix)** | - Combines absolute and ratio awareness<br>- Tunable trade-off α | - More complex and computation<br>- Needs clear default α to avoid confusion  |


>Note: Currently, the first formula (α = 1) is selected. Each of the above formulas performs differently under various scenarios. In general, the first one should be suitable for most cases. If different requirements arise, we can easily switch to another formula by adjusting α in the future.

### Decision Tree Schema 

1. First balance across nodes,
2. Then balance across disks within that node.

```
getDiskWithMostBalanceScore(candidateDisks, replicaSize)
    ├── compute usable/total storage maps
    │   ├── nodeUsableStorage / nodeTotalStorage
    │   └── diskUsableStorage / diskTotalStorage
    ├── selectBestNode
    │   ├── simulate placing replica on each node
    │   ├── computeHybridBalanceScore()
    │   │   ├── computeBalanceScoreFromUsableStorage()
    │   │   └── computeBalanceScoreFromUsableStorageRatio()
    │   └── pick node with lowest imbalance score
    ├── selectBestDisk
    │   ├── simulate placing replica on each disk (within best node)
    │   ├── computeHybridBalanceScore()
    │   └── pick disk with lowest imbalance score
    └── return bestDisk

```

### Example Scenario 1

Using **Balance Factor Formula by Usable Storage** as sample

Suppose the cluster has two nodes, and each node contains two candidate disks that are eligible for replica scheduling.Replica size = 100 GiB.

| Node   | Disk | Usable Storage (GiB) |
| ------ | ---- | -------------------- |
| Node A | A1   | 900                  |
| Node A | A2   | 100                  |
| Node B | B1   | 600                  |
| Node B | B2   | 700                  |

**Old Algorithm (max usable space)**
- Picks Disk A1 (900 GiB).
- Before placement:
    - Node A total usable = 900 + 100 = 1000
    - Node B total usable = 600 + 700 = 1300
- After placement:
    - Disk A1 usable = 900 - 100 = 800 GiB
    - Disk A2 usable = 100
    - Node A total usable = 800 + 100 = 900
    - Node B total usable = 600 + 700 = 1300

So → Node A = 900, Node B = 1300 

**New Algorithm (balance first)**

***Step 1, Node Selection***
- Simulate placing on Node A
    - New totals:
        - Node A = (900 + 100) − 100 = 900
        - Node B = (600 + 700) = 1300
    - Node balance score:
$$
BalanceScore_{NodeA} = \frac{1300 - 900}{\tfrac{1300 + 900}{2}} 
            = \frac{400}{1100} 
            \approx 0.364
$$

- Simulate placing on Node B
    - New totals:
        - Node A = (900 + 100) = 1000
        - Node B = (600 + 700) - 1000 = 1200
    - Node balance score:
$$
BalanceScore_{NodeB} = \frac{1200 - 1000}{\tfrac{1200 + 1000}{2}} 
            = \frac{200}{1100} 
            \approx 0.182
$$

Choose Node B (lower score, more balanced).

***Step 2, Disk Selection***
- Simulate placing on B1 (600 → 500)
    - New disk usable: B1 = 500, B2 = 700
    - Disk balance score:
$$
BalanceScore_{NodeA} = \frac{700 - 500}{\tfrac{700 + 500}{2}} 
            = \frac{200}{600} 
            \approx 0.333
$$

- Simulate placing on B2 (700 → 600)
    - New disk usable: B1 = 600, B2 = 600
    - Disk balance score:
$$
BalanceScore_{NodeA} = \frac{600 - 600}{\tfrac{600 + 600}{2}} 
            = \frac{0}{600} 
            \approx 0
$$

Choose Disk B2 (perfect balance between B1 and B2).

### Example Scenario 2

| Node   | Disk | Usable Storage (GiB) | Total Capacity (GiB)* | Usable % |
| ------ | ---- | -------------------- | --------------------- | -------- |
| Node A | A1   | 900                  | 1000                  | 90%      |
| Node A | A2   | 100                  | 200                   | 50%      |
| Node B | B1   | 600                  | 800                   | 75%      |
| Node B | B2   | 700                  | 1000                  | 70%      |


**Comparison Table**
| Placement | Absolute Score | Ratio Score | Hybrid (α=0.5) |
| --------- | -------------- | ----------- | -------------- |
| B1    | 1.455          | 0.587       | 1.021          |
| B2    | 1.455          | 0.582       | 1.019          |

For this case, all three formulas, Disk B2 remains the best choice.


### Test plan

1. Prepare 2 Disks with size 40Gi and 25Gi
2. Create Volume 8Gi with 1 Replica
3. Create Volume 8Gi with 1 Replica
4. Create Volume 8Gi with 1 Replica
5. Create Volume 8Gi with 1 Replica
6. Check the replica distribution, comparing to the original one. The result should be more balanced.

### Upgrade strategy

No upgrade strategy is needed 

