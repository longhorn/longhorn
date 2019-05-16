# Workload identification for volume
Now users can identify current workloads or workload history for existing Longhorn volumes.
```
PV Name: test1-pv
PV Status: Bound

Namespace: default
PVC Name: test1-pvc

Last Pod Name: volume-test-1
Last Pod Status: Running
Last Workload Name: volume-test
Last Workload Type: Statefulset
Last time used by Pod: a few seconds ago
```

## About historical status
There are a few fields can contain the historical status instead of the current status. 
Those fields can be used to help users figuring out which workload has used the volume in the past:

1. `Last time bound with PVC`: If this field is set, it indicates currently there is no bounded PVC for this volume. 
The related fields will show the most recent bounded PVC. 
2. `Last time used by Pod`: If these fields are set, they indicates currently there is no workload using this volume. 
The related fields will show the most recent workload using this volume.

# PV/PVC creation for existing Longhorn volume
Now users can create PV/PVC via our Longhorn UI for the existing Longhorn volumes. 
Only detached volume can be used by newly created pod.

## About special fields of PV/PVC
Since the Longhorn volume already exists while creating PV/PVC, StorageClass is not needed for dynamically provisioning 
Longhorn volume. However, the field `storageClassName` would be set in PVC/PV, to be used for PVC bounding purpose. And
it's unnecessary for users create the related StorageClass object. 

By default the StorageClass for Longhorn created PV/PVC is `longhorn-static`. Users can modified it in 
`Setting - General - Default Longhorn Static StorageClass Name` as they need.

Users need to manually delete PVC and PV created by Longhorn.

