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
