#!/bin/bash

dependencies() {
  local targets=($@)
  local allFound=true
  for ((i=0; i<${#targets[@]}; i++)); do
    local target=${targets[$i]}
    if [ "$(which $target)" == "" ]; then
      allFound=false
      echo Not found: $target
    fi
  done
  if [ "$allFound" == "false" ]; then
    echo "Please install missing dependencies."
    exit 2
  fi
}

create_ds() {
cat <<EOF > $TEMP_DIR/environment_check.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    app: longhorn-environment-check
  name: longhorn-environment-check
spec:
  selector:
    matchLabels:
      app: longhorn-environment-check
  template:
    metadata:
      labels:
        app: longhorn-environment-check
    spec:
      containers:
      - name: longhorn-environment-check
        image: busybox
        args: ["/bin/sh", "-c", "sleep 1000000000"]
        volumeMounts:
        - name: mountpoint
          mountPath: /tmp/longhorn-environment-check
          mountPropagation: Bidirectional
        securityContext:
          privileged: true
      volumes:
      - name: mountpoint
        hostPath:
            path: /tmp/longhorn-environment-check
EOF
  kubectl create -f $TEMP_DIR/environment_check.yaml
}

cleanup() {
  echo "cleaning up..."
  kubectl delete -f $TEMP_DIR/environment_check.yaml
  rm -rf $TEMP_DIR
  echo "clean up complete"
}

wait_ds_ready() {
  while true; do
    local ds=$(kubectl get ds/longhorn-environment-check -o json)
    local numberReady=$(echo $ds | jq .status.numberReady)
    local desiredNumberScheduled=$(echo $ds | jq .status.desiredNumberScheduled)

    if [ "$desiredNumberScheduled" == "$numberReady" ] && [ "$desiredNumberScheduled" != "0" ]; then
      echo "all pods ready ($numberReady/$desiredNumberScheduled)"
      return
    fi

    echo "waiting for pods to become ready ($numberReady/$desiredNumberScheduled)"
    sleep 3
  done
}

validate_ds() {
  local allSupported=true
  local pods=$(kubectl -l app=longhorn-environment-check get po -o json)

  local ds=$(kubectl get ds/longhorn-environment-check -o json)
  local desiredNumberScheduled=$(echo $ds | jq .status.desiredNumberScheduled)

  for ((i=0; i<desiredNumberScheduled; i++)); do
    local pod=$(echo $pods | jq .items[$i])
    local nodeName=$(echo $pod | jq -r .spec.nodeName)
    local mountPropagation=$(echo $pod | jq -r '.spec.containers[0].volumeMounts[] | select(.name=="mountpoint") | .mountPropagation')

    if [ "$mountPropagation" != "Bidirectional" ]; then
      allSupported=false
      echo "node $nodeName: MountPropagation DISABLED"
    fi
  done

  if [ "$allSupported" != "true" ]; then
    echo
    echo "  MountPropagation is disabled on at least one node."
    echo "  As a result, CSI driver and Base image cannot be supported."
    echo
    exit 1
  else
    echo -e "\n  MountPropagation is enabled!\n"
  fi
}

dependencies kubectl jq mktemp
TEMP_DIR=$(mktemp -d)
trap cleanup EXIT
create_ds
wait_ds_ready
validate_ds
exit 0
