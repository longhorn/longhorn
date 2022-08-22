# Prometheus Support

## Summary


We currently do not have a way for users to monitor and alert about events happen in Longhorn such as volume is full, backup is failed, CPU usage, memory consumption. 
This enhancement exports Prometheus metrics so that users can use Prometheus or other monitoring systems to monitor Longhorn.

### Related Issues

https://github.com/longhorn/longhorn/issues/1180

## Motivation

### Goals

We are planing to expose 22 metrics in this release:
1. longhorn_volume_capacity_bytes
1. longhorn_volume_actual_size_bytes
1. longhorn_volume_state
1. longhorn_volume_robustness

1. longhorn_node_status
1. longhorn_node_count_total
1. longhorn_node_cpu_capacity_millicpu
1. longhorn_node_cpu_usage_millicpu
1. longhorn_node_memory_capacity_bytes
1. longhorn_node_memory_usage_bytes
1. longhorn_node_storage_capacity_bytes
1. longhorn_node_storage_usage_bytes
1. longhorn_node_storage_reservation_bytes

1. longhorn_disk_capacity_bytes
1. longhorn_disk_usage_bytes
1. longhorn_disk_reservation_bytes

1. longhorn_instance_manager_cpu_usage_millicpu
1. longhorn_instance_manager_cpu_requests_millicpu
1. longhorn_instance_manager_memory_usage_bytes
1. longhorn_instance_manager_memory_requests_bytes

1. longhorn_manager_cpu_usage_millicpu
1. longhorn_manager_memory_usage_bytes




See the [User Experience In Detail](#user-experience-in-detail) section for definition of each metric.

### Non-goals

We are not planing to expose 6 metrics in this release:
1. longhorn_backup_stats_number_failed_backups 
1. longhorn_backup_stats_number_succeed_backups
1. longhorn_backup_stats_backup_status (status for this backup (0=InProgress,1=Done,2=Failed))
1. longhorn_volume_io_ops
1. longhorn_volume_io_read_throughput
1. longhorn_volume_io_write_throughput

## Proposal

### User Stories

Longhorn already has a great UI with many useful information. 
However, Longhorn doesn't have any alert/notification mechanism yet. 
Also, we don't have any dashboard or graphing support so that users can have overview picture of the storage system.
This enhancement will address both of the above issues.

#### Story 1
In many cases, a problem/issue can be quickly discovered if we have a monitoring dashboard. 
For example, there are many times users ask us for supporting and the problems were that the Longhorn engines were killed due to over-use CPU limit.
If there is a CPU monitoring dashboard for instance managers, those problems can be quickly detected.

#### Story 2
User want to be notified about abnormal event such as disk space limit approaching. 
We can expose metrics provide information about it and user can scrape the metrics and setup alert system.

### User Experience In Detail

After this enhancement is merged, Longhorn expose metrics at end point `/metrics` in Prometheus' [text-based format](https://prometheus.io/docs/instrumenting/exposition_formats/).
Users can use Prometheus or other monitoring systems to collect those metrics by scraping the end point `/metrics` in longhorn manager.
Then, user can display the collected data using tools such as Grafana.
User can also setup alert by using tools such as Prometheus Alertmanager.

Below are the descriptions of metrics which Longhorn exposes and how users can use them:

1. longhorn_volume_capacity_bytes

    This metric reports the configured size in bytes for each volume which is managed by the current longhorn manager.
     
    This metric contains 2 labels (dimensions): 
    * `node`: the node of the longhorn manager which is managing this volume
    * `volume`: the name of this volume
    
    Example of a sample of this metric could be: 
    ```
    longhorn_volume_capacity_bytes{node="worker-2",volume="testvol"} 6.442450944e+09
    ```
    Users can use this metrics to draw graph about and quickly see the big volumes in the storage system.

1. longhorn_volume_actual_size_bytes

    This metric reports the actual space used by each replica of the volume on the corresponding nodes
    
    This metric contains 2 labels (dimensions): 
    * `node`: the node of the longhorn manager which is managing this volume
    * `volume`: the name of this volume
     
    Example of a sample of this metric could be: 
    ```
    longhorn_volume_actual_size_bytes{node="worker-2",volume="testvol"} 1.1917312e+08
    ```
    Users can use this metrics to the actual size occupied on disks of Longhorn volumes

1. longhorn_volume_state

   This metric reports the state of the volume. The states are: 1=creating, 2=attached, 3=Detached, 4=Attaching, 5=Detaching, 6=Deleting.
   
   This metric contains 2 labels (dimensions): 
   * `node`: the node of the longhorn manager which is managing this volume
   * `volume`: the name of this volume
   
   Example of a sample of this metric could be: 
   ```
   longhorn_volume_state{node="worker-3",volume="testvol1"} 2
   ```
    
1. longhorn_volume_robustness

   This metric reports the robustness of the volume. Possible values are: 0=unknown, 1=healthy, 2=degraded, 3=faulted
   
   This metric contains 2 labels (dimensions): 
   * `node`: the node of the longhorn manager which is managing this volume
   * `volume`: the name of this volume
   
   Example of a sample of this metric could be: 
   ```
   longhorn_volume_robustness{node="worker-3",volume="testvol1"} 1
   ```
   
1. longhorn_node_status

    This metric reports the `ready`, `schedulable`, `mountPropagation` condition for the current node.
    
    This metric contains 3 labels (dimensions): 
    * `node`
    * `condition`: the name of the condition (`ready`, `schedulable`, `mountPropagation`)
    * `condition_reason`
    
    Example of a sample of this metric could be: 
    ```
    longhorn_node_status{condition="allowScheduling",condition_reason="",node="worker-3"} 1
    longhorn_node_status{condition="mountpropagation",condition_reason="",node="worker-3"} 1
    longhorn_node_status{condition="ready",condition_reason="",node="worker-3"} 1
    longhorn_node_status{condition="schedulable",condition_reason="",node="worker-3"} 1
    ```
    Users can use this metrics to setup alert about node status.
    
1. longhorn_node_count_total

   This metric reports the total nodes in Longhorn system.
   
   Example of a sample of this metric could be: 
   ```
   longhorn_node_count_total 3
   ```   
   Users can use this metric to detect the number of down nodes
   
1. longhorn_node_cpu_capacity_millicpu

   Report the maximum allocatable cpu on this node
   
   Example of a sample of this metric could be: 
   ```
   longhorn_node_cpu_capacity_millicpu{node="worker-3"} 2000
   ```   

1. longhorn_node_cpu_usage_millicpu

   Report the cpu usage on this node
   
   Example of a sample of this metric could be: 
   ```
   longhorn_node_cpu_usage_millicpu{node="worker-3"} 149
   ```  
   
1. longhorn_node_memory_capacity_bytes

   Report the maximum allocatable memory on this node
   
   Example of a sample of this metric could be: 
   ```
   longhorn_node_memory_capacity_bytes{node="worker-3"} 4.031217664e+09
   ``` 
    
1. longhorn_node_memory_usage_bytes

   Report the memory usage on this node
   
   Example of a sample of this metric could be: 
   ```
   longhorn_node_memory_usage_bytes{node="worker-3"} 1.643794432e+09
   ```  
   
1. longhorn_node_storage_capacity_bytes

   Report the storage capacity of this node
   
   Example of a sample of this metric could be: 
   ```
   longhorn_node_storage_capacity_bytes{node="worker-3"} 8.3987283968e+10
   ```  

1. longhorn_node_storage_usage_bytes

   Report the used storage of this node
   
   Example of a sample of this metric could be: 
   ```
   longhorn_node_storage_usage_bytes{node="worker-3"} 9.060212736e+09
   ```  
      
1. longhorn_node_storage_reservation_bytes

   Report the reserved storage for other applications and system on this node
   
   Example of a sample of this metric could be: 
   ```
   longhorn_node_storage_reservation_bytes{node="worker-3"} 2.519618519e+10
   ```  
   
1. longhorn_disk_capacity_bytes

   Report the storage capacity of this disk.
   
   Example of a sample of this metric could be: 
   ```
   longhorn_disk_capacity_bytes{disk="default-disk-8b28ee3134628183",node="worker-3"} 8.3987283968e+10
   ```  
   
1. longhorn_disk_usage_bytes

   Report the used storage of this disk
   
   Example of a sample of this metric could be: 
   ```
   longhorn_disk_usage_bytes{disk="default-disk-8b28ee3134628183",node="worker-3"} 9.060212736e+09
   ```  
   
1. longhorn_disk_reservation_bytes

   Report the reserved storage for other applications and system on this disk
   
   Example of a sample of this metric could be: 
   ```
   longhorn_disk_reservation_bytes{disk="default-disk-8b28ee3134628183",node="worker-3"} 2.519618519e+10
   ```  
   
1. longhorn_instance_manager_cpu_requests_millicpu

    This metric reports the requested CPU resources in Kubernetes of the Longhorn instance managers on the current node. 
    The unit of this metric is milliCPU. See more about the unit at https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/#cpu-units
    
    This metric contains 3 labels (dimensions): 
    * `node`
    * `instance_manager`
    * `instance_manager_type`
    
    Example of a sample of this metric could be: 
    ```
    longhorn_instance_manager_cpu_requests_millicpu{instance_manager="instance-manager-r-61ffe369",instance_manager_type="replica",node="worker-3"} 250
    ```
   
1. longhorn_instance_manager_cpu_usage_millicpu

    This metric reports the CPU usage of the Longhorn instance managers on the current node. 
    The unit of this metric is milliCPU. See more about the unit at https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/#cpu-units
    
    This metric contains 3 labels (dimensions): 
    * `node`
    * `instance_manager`
    * `instance_manager_type`
    
    Example of a sample of this metric could be: 
    ```
    longhorn_instance_manager_cpu_usage_millicpulonghorn_instance_manager_memory_requests_bytes{instance_manager="instance-manager-r-61ffe369",instance_manager_type="replica",node="worker-3"} 0
    ```

1. longhorn_instance_manager_memory_requests_bytes

    This metric reports the requested memory in Kubernetes of the Longhorn instance managers on the current node. 
    
    This metric contains 3 labels (dimensions): 
    * `node`
    * `instance_manager`
    * `instance_manager_type`
        
    Example of a sample of this metric could be: 
    ```
    longhorn_instance_manager_memory_requests_bytes{instance_manager="instance-manager-e-0a67975b",instance_manager_type="engine",node="worker-3"} 0
    ```
    
1. longhorn_instance_manager_usage_memory_bytes

    This metrics reports the memory usage of the Longhorn instance managers on the current node. 
    
    This metric contains 3 labels (dimensions): 
    * `node`
    * `instance_manager`
    * `instance_manager_type`
        
    Example of a sample of this metric could be: 
    ```
    longhorn_instance_manager_memory_usage_bytes{instance_manager="instance-manager-e-0a67975b",instance_manager_type="engine",node="worker-3"} 1.374208e+07
    ```

1. longhorn_manager_cpu_usage_millicpu

    This metric reports the CPU usage of the Longhorn manager on the current node. 
    The unit of this metric is milliCPU. See more about the unit at https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/#cpu-units
    
    This metric contains 2 labels (dimensions): 
    * `node`
    * `manager`
    
    Example of a sample of this metric could be: 
    ```
    longhorn_manager_cpu_usage_millicpu{manager="longhorn-manager-x5cjj",node="phan-cluster-23-worker-3"} 15
    ```

1. longhorn_manager_memory_usage_bytes

    This metric reports the memory usage of the Longhorn manager on the current node. 
        
    This metric contains 2 labels (dimensions): 
    * `node`
    * `manager`
    
    Example of a sample of this metric could be: 
    ```
    longhorn_manager_memory_usage_bytes{manager="longhorn-manager-x5cjj",node="worker-3"} 2.7979776e+07
    ```
    
### API changes
We add a new end point `/metrics` to exposes all longhorn Prometheus metrics.
## Design

### Implementation Overview
We follow the [Prometheus best practice](https://prometheus.io/docs/instrumenting/writing_exporters/#deployment), each Longhorn manager reports information about the components it manages.
Prometheus can use service discovery mechanism to find all longhorn-manager pods in longhorn-backend service.

We create a new collector for each type (volumeCollector, backupCollector, nodeCollector, etc..) and have a common baseCollector. 
This structure is similar to the controller package: we have volumeController, nodeController, etc.. which have a common baseController.
The end result is a structure like a tree:
```
a custom registry <- many custom collectors share the same base collector <- many metrics in each custom collector
```
When a scrape request is made to endpoint `/metric`, a handler gathers data in the Longhorn custom registry, which in turn gathers data in custom collectors, which in turn gathers data in all metrics.

Below are how we collect data for each metric:

1. longhorn_volume_capacity_bytes

    We get the information about volumes' capacity by reading volume CRD from datastore.
    When volume move to a different node, the current longhorn manager stops reporting the vol.
    The volume will be reported by a new longhorn manager.

1. longhorn_actual_size_bytes

    We get the information about volumes' actual size by reading volume CRD from datastore.
    When volume move to a different node, the current longhorn manager stops reporting the vol.
    The volume will be reported by a new longhorn manager.

1. longhorn_volume_state

   We get the information about volumes' state by reading volume CRD from datastore.
   
1. longhorn_volume_robustness

   We get the information about volumes' robustness by reading volume CRD from datastore.
    
1. longhorn_node_status

    We get the information about node status by reading node CRD from datastore.
    Nodes don't move likes volume, so we don't have to decide which longhorn manager reports which node.
    
1. longhorn_node_count_total

   We get the information about total number node by reading from datastore
   
1. longhorn_node_cpu_capacity_millicpu

   We get the information about the maximum allocatable cpu on this node by reading Kubernetes node resource

1. longhorn_node_cpu_usage_millicpu

   We get the information about the cpu usage on this node from metric client
   
1. longhorn_node_memory_capacity_bytes

   We get the information about the maximum allocatable memory on this node by reading Kubernetes node resource
   
1. longhorn_node_memory_usage_bytes

   We get the information about the memory usage on this node from metric client
   
1. longhorn_node_storage_capacity_bytes

   We get the information by reading node CRD from datastore
   
1. longhorn_node_storage_usage_bytes

   We get the information by reading node CRD from datastore
  
1. longhorn_node_storage_reservation_bytes

   We get the information by reading node CRD from datastore
    
1. longhorn_disk_capacity_bytes

   We get the information by reading node CRD from datastore
   
1. longhorn_disk_usage_bytes

   We get the information by reading node CRD from datastore
   
1. longhorn_disk_reservation_bytes

   We get the information by reading node CRD from datastore
   
1. longhorn_instance_manager_cpu_requests_millicpu

   We get the information by reading instance manager Pod objects from datastore. 
   
1. longhorn_instance_manager_cpu_usage_millicpu

   We get the information by using kubernetes metric client.

1. longhorn_instance_manager_memory_usage_bytes

   We get the information by using kubernetes metric client.
 
1. longhorn_instance_manager_memory_requests_bytes

   We get the information by reading instance manager Pod objects from datastore. 
      
1. longhorn_manager_cpu_usage_millicpu

    We get the information by using kubernetes metric client.

1. longhorn_manager_memory_usage_bytes

    We get the information by using kubernetes metric client.

    
### Test plan

The manual test plan is detailed at [here](https://github.com/longhorn/longhorn-tests/blob/master/docs/content/manual/release-specific/v1.1.0/prometheus_support.md)

### Upgrade strategy

This enhancement doesn't require any upgrade.
