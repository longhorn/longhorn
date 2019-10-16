# Node Failure Handling with Longhorn

## What to expect when a Kubernetes Node fails

When a Kubernetes node fails with CSI driver installed (all the following are based on Kubernetes v1.12 with default setup):
1. After **one minute**, `kubectl get nodes` will report `NotReady` for the failure node.
2. After about **five minutes**, the states of all the pods on the `NotReady` node will change to either `Unknown` or `NodeLost`.
3. If you're deploying using StatefulSet or Deployment, you need to decide is if it's safe to force deletion the pod of the workload
running on the lost node. See [here](https://kubernetes.io/docs/tasks/run-application/force-delete-stateful-set-pod/).
    1. StatefulSet has stable identity, so Kubernetes won't delete the Pod for the user.
    2. Deployment doesn't have stable identity, but Longhorn is a Read-Write-Once type of storage, which means it can only attached
    to one Pod. So the new Pod created by Kubernetes won't be able to start due to the Longhorn volume still attached to the old Pod,
    on the lost Node.
4. If you decide to delete the Pod manually (and forcefully), Kubernetes will take about another **six minutes** to delete the VolumeAttachment
object associated with the Pod, thus finally detach the Longhorn volume from the lost Node and allow it to be used by the new Pod.

## What to expect when recovering a failed Kubernetes Node
1. If the node is **back online within 5 - 6 minutes** of the failure, Kubernetes will restart pods, unmount then re-mount volumes without volume re-attaching and VolumeAttachment cleanup.
   Because the volume engines would be down after the node down, the direct remount won’t work since the device no longer exists on the node. In this case, Longhorn needs to detach and re-attach the volumes to recover the volume engines, so that the pods can remount/reuse the volumes safely. 
2. If the node is **not back online within 5 - 6 minutes** of the failure, Kubernetes will try to delete all unreachable pods and these pods will become `Terminating` state. See [pod eviction timeout](https://kubernetes.io/docs/concepts/architecture/nodes/#condition) for details. 
   Then if the failed node is recovered later, Kubernetes will restart those terminating pods, detach the volumes, wait for the old VolumeAttachment cleanup, and reuse(re-attach & re-mount) the volumes. Typically these steps may take 1 ~ 7 minutes.
   In this case, detaching and re-attaching operations are included in the recovery procedures. Hence no extra operation is needed and the Longhorn volumes will be available after the above steps. 