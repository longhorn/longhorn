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

create_pod() {
cat <<EOF > $TEMP_DIR/detect-flexvol-dir.yaml
apiVersion: v1
kind: Pod
metadata:
  name: detect-flexvol-dir
spec:
  containers:
  - name: detect-flexvol-dir
    image: busybox
    command: ["/bin/sh"]
    args:
    - -c
    - |
      find_kubelet_proc() {
        for proc in \`find /proc -type d -maxdepth 1\`; do
          if [ ! -f \$proc/cmdline ]; then
            continue
          fi
          if [[ "\$(cat \$proc/cmdline | tr '\000' '\n' | head -n1 | tr '/' '\n' | tail -n1)" == "kubelet" ]]; then
            echo \$proc
            return
          fi
        done
      }
      get_flexvolume_path() {
        proc=\$(find_kubelet_proc)
        if [ "\$proc" != "" ]; then
          path=\$(cat \$proc/cmdline | tr '\000' '\n' | grep volume-plugin-dir | tr '=' '\n' | tail -n1)
          if [ "\$path" == "" ]; then
            echo '/usr/libexec/kubernetes/kubelet-plugins/volume/exec/'
          else
            echo \$path
          fi
          return
        fi
        echo 'no kubelet process found, dunno'
      }
      get_flexvolume_path
    securityContext:
      privileged: true
  hostPID: true
  restartPolicy: Never
EOF
  kubectl create -f $TEMP_DIR/detect-flexvol-dir.yaml
}

cleanup() {
  kubectl delete -f $TEMP_DIR/environment_check.yaml &
  a=$!
  kubectl delete -f $TEMP_DIR/detect-flexvol-dir.yaml &
  b=$!
  wait $a
  wait $b
  rm -rf $TEMP_DIR
}

wait_pod_ready() {
  while true; do
    local pod=$(kubectl get po/detect-flexvol-dir -o json)
    local phase=$(echo $pod | jq -r .status.phase)

    if [ "$phase" == "Succeeded" ]; then
      echo "pod/detect-flexvol-dir completed"
      return
    fi

    echo "waiting for pod/detect-flexvol-dir to finish"
    sleep 3
  done
}

validate_pod() {
  flexvol_path=$(kubectl logs detect-flexvol-dir)
  echo -e "\n  FlexVolume Path: ${flexvol_path}\n"
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
  
  for ((i=0; i<1; i++)); do
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
    echo "  As a result, CSI Driver and Base Image aren't supported."
    echo
    exit 1
  else
    echo -e "\n  MountPropagation is enabled!\n"
  fi
}

dependencies kubectl jq mktemp
TEMP_DIR=$(mktemp -d)
trap cleanup EXIT
create_pod
create_ds
wait_pod_ready
wait_ds_ready
validate_pod
validate_ds
exit 0
