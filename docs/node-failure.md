# Node Failure Handling with Longhorn

## What to expect when a Kubernetes Node fails

When a Kubernetes node fails with CSI driver installed (all the following are based on Kubernetes v1.12 with default setup):
1. After **one minute**, `kubectl get nodes` will report `NotReady` for the failure node.
2. After about **five minutes**, the states of all the pods on the `NotReady` node will change to either `Unknown` or `NodeLost`.
3. If you're deploying using StatefulSet or Deployment, you need to decide is if it's safe to force deletion the pod of the workload
running on the lost node. See [here](https://kubernetes.io/docs/tasks/run-application/force-delete-stateful-set-pod/).
    1. StatefulSet has stable identity, so Kubernetes won't force deleting the Pod for the user. 
    2. Deployment doesn't have stable identity, but Longhorn is a Read-Write-Once type of storage, which means it can only attached
    to one Pod. So the new Pod created by Kubernetes won't be able to start due to the Longhorn volume still attached to the old Pod,
    on the lost Node.
    3. In both cases, Kubernetes will automatically evict the pod (set deletion timestamp for the pod) on the lost node, then try to 
    **recreate a new one with old volumes**. Because the evicted pod gets stuck in `Terminating` state and the attached Longhorn volumes 
    cannot be released/reused, the new pod will get stuck in `ContainerCreating` state. That's why users need to decide is if it's safe to force deleting the pod.
4. If you decide to delete the Pod manually (and forcefully), Kubernetes will take about another **six minutes** to delete the VolumeAttachment
object associated with the Pod, thus finally detach the Longhorn volume from the lost Node and allow it to be used by the new Pod. 
    - This another six-minute is [hardcoded in Kubernetes](https://github.com/kubernetes/kubernetes/blob/5e31799701123c50025567b8534e1a62dbc0e9f6/pkg/controller/volume/attachdetach/attach_detach_controller.go#L95): 
    If the pod on the lost node is forced deleting, the related volumes won't be unmounted correctly. Then Kubernetes will wait for this fixed timeout 
    to directly clean up the VolumeAttachment object.

## What to expect when recovering a failed Kubernetes Node
1. If the node is **back online within 5 - 6 minutes** of the failure, Kubernetes will restart pods, unmount then re-mount volumes without volume re-attaching and VolumeAttachment cleanup.
   Because the volume engines would be down after the node down, this direct remount won’t work since the device no longer exists on the node. 
   In this case, Longhorn will detach and re-attach the volumes to recover the volume engines, so that the pods can remount/reuse the volumes safely. 
2. If the node is **not back online within 5 - 6 minutes** of the failure, Kubernetes will try to delete all unreachable pods based on the pod eviction mechanism and these pods will become `Terminating` state. See [pod eviction timeout](https://kubernetes.io/docs/concepts/architecture/nodes/#condition) for details. 
   Then if the failed node is recovered later, Kubernetes will restart those terminating pods, detach the volumes, wait for the old VolumeAttachment cleanup, and reuse(re-attach & re-mount) the volumes. Typically these steps may take 1 ~ 7 minutes.
   In this case, detaching and re-attaching operations are already included in the Kubernetes recovery procedures. Hence no extra operation is needed and the Longhorn volumes will be available after the above steps. 
3. For all above recovery scenarios, Longhorn will handle those steps automatically with the association of Kubernetes. This section is aimed to inform users of what happens and what is expected during the recovery.