# Add Read Side Cache

## Summary
This enhancement adds a read side cache in the engine to lower the read latenty if the data was cached and improve the read performance.

## Related Issues
- [[FEATURE] Read side caching #3176](https://github.com/longhorn/longhorn/issues/3176)

## Motivation
### Goals
- The cache device is dedicated to read buffering, so there is no data loss concern if the cache device is lost.
- User is able to create a volume with a cache device.
- User is able to enable or disable the cache.
- Cache percentage
  - User is able to configure the global size of the cache device by setting the cache device to volume ratio, expressed as a percentage.
  - User is able to override the ratio in StorageClass.
- Cache block size
  - User is able to configure the global block size of the cache device.
  - User is able to override the block size in StorageClass.
- Cache disk path
  - User is able to configure the per-node cache disk path.
  
### Non-goals [optional]

## Proposal
### User Stories
We would like to add a read side cache in the engine to reduce the read latency. In current read I/O path, the data from a replica to the application suffers from storage and network latencies, shown in Figure 1.

```bash

      +-------+
      |  APP  |
      +-------+
          ▲  
          | read data
+--------------------+
|     filesystem     |
+--------------------+
|   iSCSI initiator  |
+--------------------+
|    iSCSI target    |
+--------------------+
|     controller     |
+--------------------+
|       replica      |
+--------------------+
|        disk        |
+--------------------+ 

       Figure 1
```

In the filesystem, the page cache caches frequently accessed data, but the limited memory capacity limits the size of the cache, and cache thrashing occurs when too many workloads compete for memory resources on a node. Those issues result in cache misses and extra data reads from the replicas. In addition, applications enabling direct I/O also suffer the long latencies to the disk on each read request.

To mitigate the long latency of the read I/O path, a per-volume cache being dedicated to read buffering is introduced shown in Figure 2. A cache device creating from an preallocated file and `dm-cache` on the host storage is added on top of the iSCSI initiator. The size and the block size of the cache device is configurable according to workload requirements [1]. Caching frequently accessed data on the cache device improves the read performance and reduces I/O latency.

```bash

      +-------+
      |  APP  |
      +-------+
          ▲  
          | read data
+--------------------+
|     filesystem     |
+--------------------+
|    cache device    |
+--------------------+
|   iSCSI initiator  |
+--------------------+
|    iSCSI target    |
+--------------------+
|     controller     |
+--------------------+
|       replica      |
+--------------------+
|        disk        |
+--------------------+ 

       Figure 2
```

### Cache Management

Cache allocation will be based on best effort. If there is no space, then the cache won't be allocated and the volume will function without cache.

The cache is disabled by default. User can enable it by set `CacheEnabled` to `"true"` in the StorageClass.
#### Cache Disk Path
The cache data can be stored in `node.cacheDisks` or in a per-node dedicated cache disk [2]. The `node.cacheDisks` can be deleted if the scheduled storage size is `0`.

#### Cache Size
A global cahe size setting `SettingNameDefaultCachePercentage` in terms of cache device to volume ratio, expressed as a percentage, is introduced. The default value is `0` which disables the cache by default.

In addition to the global setting, user is able to override the value in StorageClass. The cache size can be overridden by each volume.

#### Cache Block Size
A global cahe block size setting `SettingNameDefaultCacheBlockSize` is introduced. The default value is `128Ki` by default. User can modify the value for different applications.

In addition to the global setting, user is able to override the value in StorageClass.

### User Experience In Detail
#### Configure Per-Node Cache Disk
If the use would like to enable the read-side cache, the per-node cache disk needs to be specified.

#### Create A Volume With Cache
- Global Setting
    - SettingNameDefaultCachePercentage:
      - Type: int
      - Range: 0-100
      - Default: 0
    - SettingNameDefaultCacheBlockSize
      - Type: string
      - Range: 4K - 128Ki
      - Default: 32Ki
- To enable the read side cache, create a storageClass and set `cacheEnabled` to be `"true"`. `cachePercentage` are `cacheBlockSize` are overridable.
    - cacheEnabled: The read-side cache can be enabled or disabled by this flag. User can disable the read-side cache on the node who has a cache disk according to the application.
    - cachePercentage: the capacity of the cache device in terms of the percentage of the volume size
    - cacheBlockSize: the size of the cache device
    ```
    kind: StorageClass
    apiVersion: storage.k8s.io/v1
    metadata:
    name: longhorn-crypto-global
    provisioner: driver.longhorn.io
    allowVolumeExpansion: true
    parameters:
      numberOfReplicas: "3"
      staleReplicaTimeout: "2880" # 48 hours in minutes
      fromBackup: ""
      cacheEnabled: "true"
      cachePercentage: "20"
      cacheBlockSize: "64Ki"
    ```

- Create a pvc that references the created storage class.

#### Failure
If the cache disk is full or corrupted, Longhorn has the fallback to provide a volume in absence of the read-side cache.
### API changes
Add `cacheSize` string which is calculated from the `cachePercentage` and the volume size, `cacheBlockSize` string and `cachePath` string to the Volume struct utilized by the http client, this ends up with being stored in `Volume.Spec.cachePercentage`, `Volume.Spec.cacheBlockSize` and `Volume.Spec.cachePath`  of the volume CR.


## Design
### Implementation Overview
### Volume with a Read Side Cache
Host requires `dm-cache` kernel module as well as `dmsetup` and `losetup` userspace utilities.

The logics are implemented in longhorn-manager CSI `NodeStageVolume`.

1. Create a preallocated file under per-node cache disk.
2. Utilize the host installed `losetup` to mount the empty file as a loopback block device. The loopback device is represented by the files in the `/dev/longhorn/cache` as:
    ```
    $ ls /dev/longhorn/cache
    pvc-bb8582d5-eaa4-479a-b4bf-328d1ef1785d
    ```

3. Utilize the host installed `dmsetup` to create the `dm-cache` metadata and data cache devices using the loopback device and configure the block size of the cache device to match `cacheBlockSize`. The devices are represented by the files in the `/dev/mapper` directory on the host as:
    ```
    $ ls /dev/mapper/
    pvc-bb8582d5-eaa4-479a-b4bf-328d1ef1785d.cache.metadata
    pvc-bb8582d5-eaa4-479a-b4bf-328d1ef1785d.cache.data
    ```

4. Utilize the host installed `dmsetup` to add the metadata and data cache devices with `writethrough` mode on the top of the iSCSI block device. The final Longhorn volume is suffix with `.cached`
    ```
    $ ls /dev/mapper/
    pvc-bb8582d5-eaa4-479a-b4bf-328d1ef1785d.cache.metadata
    pvc-bb8582d5-eaa4-479a-b4bf-328d1ef1785d.cache.data
    pvc-bb8582d5-eaa4-479a-b4bf-328d1ef1785d.cached
    ```

### Incorporate with Volume Encryption
If the volume encryption is enabled, the cache device is added between the encryption (`dm-crypt`) and the iSCSI initiator as shown in Figure 3. The data in the cache device is ensured to be encrypted.

```bash

      +-------+
      |  APP  |
      +-------+
          ▲  
          | read data
+--------------------+
|     filesystem     |
+--------------------+
|     encryption     |
+--------------------+
|    cache device    |
+--------------------+
|   iSCSI initiator  |
+--------------------+
|    iSCSI target    |
+--------------------+
|     controller     |
+--------------------+
|       replica      |
+--------------------+
|        disk        |
+--------------------+ 

       Figure 3
```
### Test Plan
#### Successful Creation of a Volume With a Read Side Cache
1. Create a storage class with `cacheEnable` (true), `cachePercentage`(optional) and `cacheBlockSize`(optional).
2. Create a pvc that references the created storage class, and the volume size should be equal to or smaller than the cache size.
3. Create a pod that uses that pvc for a volume mount
4. wait for pod up and healthy

#### Benchmark the Storage Performance
Before benchmaring the cache performance, create the volume following the steps in `Successful Creation of a Volume With a Read Side Cache`. The cache should be warmed up first, and then `fio` is used to test the storage performance.

- Warm up
    ```
    fio --direct=1 --size=90% --filesize=20G --blocksize=4K --ioengine=libaio --rw=rw --rwmixread=100 --rwmixwrite=0 --iodepth=64 --filename=/data/file --name=WarmUp --output=/tmp/warm-up.txt
    ```
- Measure the performance
  We use zipfian distribution (`--random_distribution=zipf:1.2`). By default, `fio` will use pure random distribution. A pure random distribution has no “data hot spots” and is not good for caching. Many studies have found that a Zipfian distribution with 1.2 theta is representative of typical real-world workloads including web traffic, video-on-demand and live streaming media traffic.

    - Randread
    ```
    fio --direct=1 --size=100% --filesize=20G --blocksize=4K --ioengine=libaio --rw=randrw --rwmixread=0 --rwmixwrite=100 --iodepth=16 --numjob=4 --group_reporting --filename=/data/file --name=Measure --random_distribution=zipf:1.2 --output=/tmp/fio-result.txt
    ```
    - Randwrite
    ```
    fio --direct=1 --size=100% --filesize=20G --blocksize=4K --ioengine=libaio --rw=randrw --rwmixread=0 --rwmixwrite=100 --iodepth=16 --numjob=4 --group_reporting --filename=/data/file --name=Measure --random_distribution=zipf:1.2 --output=/tmp/fio-result.txt
    ```
  
#### Data Integrity
We cannot lose any data if we lose the whole volume attached node. All the data that are written into the disk via the cache layer must be persistent into the Longhorn data disk.

The stress test steps are
- Write data using direct io to volume via the cache layer,
- Stop (normal or abnormal shutdown) the volume,
- Attach the volume back,
- Verify the file checksum.

## Note [optional]
## Reference
1. [The Linux kernel user’s and administrator’s guide - Cache](https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/cache.html)
2. [Vault '20 - Introduction to Client side Caching in Ceph](https://www.youtube.com/watch?v=DKV0vDLijv0)
3. [Performance Comparison among EnhanceIO, bcache and dm-cache](https://lkml.org/lkml/2013/6/11/333)
4. [Intel® Cache Acceleration Software (Intel® CAS) for Linux](https://indico.cern.ch/event/524549/contributions/2203842/attachments/1290809/1922458/IntelR_Cache_Acceleration_Software_for_Linux_-_Technical_Training_v3.0.pdf)