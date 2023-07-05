#!/bin/bash

NAMESPACE=${NAMESPACE:-longhorn-system}

remove_and_wait() {
  local crd=$1
  out=`kubectl -n ${NAMESPACE} delete $crd --all 2>&1`
  if [ $? -ne 0 ]; then
    echo $out
    return
  fi
  while true; do
    out=`kubectl -n ${NAMESPACE} get $crd -o yaml | grep 'items: \[\]'`
    if [ $? -eq 0 ]; then
      break
    fi
    sleep 1
  done
  echo all $crd instances deleted
}

remove_crd_instances() {
  remove_and_wait volumes.longhorn.io
  # engines and replicas should be no-ops, already done by volume delete.  See https://github.com/rancher/longhorn/issues/273
  remove_and_wait engines.longhorn.io
  remove_and_wait replicas.longhorn.io
  remove_and_wait engineimages.longhorn.io
  remove_and_wait settings.longhorn.io
  # do this one last; manager crashes
  remove_and_wait nodes.longhorn.io
}

# Delete driver related workloads in specific order
remove_driver() {
  kubectl -n ${NAMESPACE} delete deployment.apps/longhorn-driver-deployer
  kubectl -n ${NAMESPACE} delete daemonset.apps/longhorn-csi-plugin
  kubectl -n ${NAMESPACE} delete statefulset.apps/csi-attacher
  kubectl -n ${NAMESPACE} delete service/csi-attacher
  kubectl -n ${NAMESPACE} delete statefulset.apps/csi-provisioner
  kubectl -n ${NAMESPACE} delete service/csi-provisioner
  kubectl -n ${NAMESPACE} delete daemonset.apps/longhorn-flexvolume-driver
}

# Delete all workloads in the namespace
remove_workloads() {
  kubectl -n ${NAMESPACE} get daemonset.apps -o yaml | kubectl delete -f -
  kubectl -n ${NAMESPACE} get deployment.apps -o yaml | kubectl delete -f -
  kubectl -n ${NAMESPACE} get replicaset.apps -o yaml | kubectl delete -f -
  kubectl -n ${NAMESPACE} get statefulset.apps -o yaml | kubectl delete -f -
  kubectl -n ${NAMESPACE} get pods -o yaml | kubectl delete -f -
  kubectl -n ${NAMESPACE} get service -o yaml | kubectl delete -f -
}

# Delete CRD definitions with longhorn.io in the name
remove_crds() {
  for crd in $(kubectl get crd -o jsonpath={.items[*].metadata.name} | tr ' ' '\n' | grep longhorn.io); do
    kubectl delete crd/$crd
  done
}

remove_crd_instances
remove_driver
remove_workloads
remove_crds

# Last, remove the namespace itself (and implicitly some remaining resource types such as events.)
# Note: this will still leave some items behind, such as persistentvolumeclaim (in default namespace)
#       and storageclass (not namespaced).
kubectl delete namespace ${NAMESPACE}

