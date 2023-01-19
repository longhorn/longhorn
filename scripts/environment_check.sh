#!/bin/bash

######################################################
# Log
######################################################
export RED='\x1b[0;31m'
export GREEN='\x1b[38;5;22m'
export CYAN='\x1b[36m'
export YELLOW='\x1b[33m'
export NO_COLOR='\x1b[0m'

if [ -z "${LOG_TITLE}" ]; then
  LOG_TITLE=''
fi
if [ -z "${LOG_LEVEL}" ]; then
  LOG_LEVEL="INFO"
fi

debug() {
  if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
    local log_title
    if [ -n "${LOG_TITLE}" ]; then
     log_title="(${LOG_TITLE})"
    else
     log_title=''
    fi
    echo -e "${GREEN}[DEBUG]${log_title} ${NO_COLOR}$1"
  fi
}

info() {
  if [[ "${LOG_LEVEL}" == "DEBUG" ]] ||\
     [[ "${LOG_LEVEL}" == "INFO" ]]; then
    local log_title
    if [ -n "${LOG_TITLE}" ]; then
     log_title="(${LOG_TITLE})"
    else
     log_title=''
    fi
    echo -e "${CYAN}[INFO] ${log_title} ${NO_COLOR}$1"
  fi
}

warn() {
  if [[ "${LOG_LEVEL}" == "DEBUG" ]] ||\
     [[ "${LOG_LEVEL}" == "INFO" ]] ||\
     [[ "${LOG_LEVEL}" == "WARN" ]]; then
    local log_title
    if [ -n "${LOG_TITLE}" ]; then
     log_title="(${LOG_TITLE})"
    else
     log_title=''
    fi
    echo -e "${YELLOW}[WARN] ${log_title} ${NO_COLOR}$1"
  fi
}

error() {
  if [[ "${LOG_LEVEL}" == "DEBUG" ]] ||\
     [[ "${LOG_LEVEL}" == "INFO" ]] ||\
     [[ "${LOG_LEVEL}" == "WARN" ]] ||\
     [[ "${LOG_LEVEL}" == "ERROR" ]]; then
    local log_title
    if [ -n "${LOG_TITLE}" ]; then
     log_title="(${LOG_TITLE})"
    else
     log_title=''
    fi
    echo -e "${RED}[ERROR]${log_title} ${NO_COLOR}$1"
  fi
}

######################################################
# Check logics
######################################################
set_packages_and_check_cmd()
{
  case $OS in
  *"debian"* | *"ubuntu"* )
    CHECK_CMD='dpkg -l | grep -w'
    PACKAGES=(nfs-common open-iscsi)
    ;;
  *"centos"* | *"fedora"* | *"rocky"* | *"ol"* )
    CHECK_CMD='rpm -q'
    PACKAGES=(nfs-utils iscsi-initiator-utils)
    ;;
  *"suse"* )
    CHECK_CMD='rpm -q'
    PACKAGES=(nfs-client open-iscsi)
    ;;
  *"arch"* )
    CHECK_CMD='pacman -Q'
    PACKAGES=(nfs-utils open-iscsi)
    ;;
  *"gentoo"* )
    CHECK_CMD='qlist -I'
    PACKAGES=(net-fs/nfs-utils sys-block/open-iscsi)
    ;;
  *)
    CHECK_CMD=''
    PACKAGES=()
    warn "Stop the environment check because '$OS' is not supported in the environment check script."
    exit 1
    ;;
   esac
}

detect_node_os()
{
  local pod="$1"

  OS=$(kubectl exec -i $pod -- nsenter --mount=/proc/1/ns/mnt -- bash -c 'grep -E "^ID_LIKE=" /etc/os-release | cut -d= -f2')
  if [[ -z "${OS}" ]]; then
    OS=$(kubectl exec -i $pod -- nsenter --mount=/proc/1/ns/mnt -- bash -c 'grep -E "^ID=" /etc/os-release | cut -d= -f2')
  fi
  echo "$OS"
}

check_local_dependencies() {
  local targets=($@)

  local all_found=true
  for ((i=0; i<${#targets[@]}; i++)); do
    local target=${targets[$i]}
    if [ "$(which $target)" == "" ]; then
      all_found=false
      error "Not found: $target"
    fi
  done

  if [ "$all_found" == "false" ]; then
    msg="Please install missing dependencies: ${targets[@]}."
    info "$msg"
    exit 2
  fi

  msg="Required dependencies '${targets[@]}' are installed."
  info "$msg"
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
      hostPID: true
      containers:
      - name: longhorn-environment-check
        image: alpine:3.12
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
  kubectl create -f $TEMP_DIR/environment_check.yaml > /dev/null
}

cleanup() {
  info "Cleaning up longhorn-environment-check pods..."
  kubectl delete -f $TEMP_DIR/environment_check.yaml > /dev/null
  rm -rf $TEMP_DIR
  info "Cleanup completed."
}

wait_ds_ready() {
  while true; do
    local ds=$(kubectl get ds/longhorn-environment-check -o json)
    local numberReady=$(echo $ds | jq .status.numberReady)
    local desiredNumberScheduled=$(echo $ds | jq .status.desiredNumberScheduled)

    if [ "$desiredNumberScheduled" == "$numberReady" ] && [ "$desiredNumberScheduled" != "0" ]; then
      info "All longhorn-environment-check pods are ready ($numberReady/$desiredNumberScheduled)."
      return
    fi

    info "Waiting for longhorn-environment-check pods to become ready ($numberReady/$desiredNumberScheduled)..."
    sleep 3
  done
}

check_mount_propagation() {
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
      error "node $nodeName: MountPropagation is disabled"
    fi
  done

  if [ "$allSupported" != "true" ]; then
    error "MountPropagation is disabled on at least one node. As a result, CSI driver and Base image cannot be supported."
    exit 1
  else
    info "MountPropagation is enabled."
  fi
}

check_package_installed() {
  local pods=$(kubectl get pods -o name -l app=longhorn-environment-check)

  local all_found=true

  for pod in ${pods}; do
    OS=$(detect_node_os $pod)
    if [ x"$OS" == x"" ]; then
      error "Unable to detect OS on node $node."
      exit 2
    fi

    set_packages_and_check_cmd "$OS"

    for ((i=0; i<${#PACKAGES[@]}; i++)); do
      local package=${PACKAGES[$i]}

      kubectl exec -i $pod -- nsenter --mount=/proc/1/ns/mnt -- timeout 30 bash -c "$CHECK_CMD $package" > /dev/null 2>&1
      if [ $? != 0 ]; then
        all_found=false
        node=$(kubectl get ${pod} --no-headers -o=custom-columns=:.spec.nodeName)
        error "$package is not found in $node."
      fi
    done
  done

  if [ "$all_found" == "false" ]; then
    error "Please install missing packages."
    exit 2
  fi

  info "Required packages are installed."
}

check_hostname_uniqueness() {
  hostnames=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')

  declare -A deduplicate_hostnames
  num_nodes=0
  for hostname in ${hostnames}; do
    num_nodes=$((num_nodes+1))
    deduplicate_hostnames["${hostname}"]="${hostname}"
  done

  if [ "${#deduplicate_hostnames[@]}" != "${num_nodes}" ]; then
    error "Nodes do not have unique hostnames."
    exit 2
  fi

  info "Hostname uniqueness check is passed."
}

check_multipathd() {
  local pods=$(kubectl get pods -o name -l app=longhorn-environment-check)
  local all_not_found=true

  for pod in ${pods}; do
    kubectl exec -t $pod -- nsenter --mount=/proc/1/ns/mnt -- bash -c "systemctl status --no-pager multipathd.service" > /dev/null 2>&1
    if [ $? = 0 ]; then
      all_not_found=false
      node=$(kubectl get ${pod} --no-headers -o=custom-columns=:.spec.nodeName)
      warn "multipathd is running on $node."
    fi
  done

  if [ "$all_not_found" == "false" ]; then
    warn "multipathd would probably result in the Longhorn volume mount failure. Please refer to https://longhorn.io/kb/troubleshooting-volume-with-multipath for more information."
  fi
}

check_iscsid() {
  local pods=$(kubectl get pods -o name -l app=longhorn-environment-check)
  local all_found=true

  for pod in ${pods}; do
    kubectl exec -t $pod -- nsenter --mount=/proc/1/ns/mnt -- bash -c "systemctl status --no-pager iscsid.service" > /dev/null 2>&1

    if [ $? != 0 ]; then
      all_found=false
      node=$(kubectl get ${pod} --no-headers -o=custom-columns=:.spec.nodeName)
      error "iscsid is not running on $node."
    fi
  done

  if [ "$all_found" == "false" ]; then
    exit 2
  fi
}

check_nfs_client_kernel_support() {
  local pods=$(kubectl get pods -o name -l app=longhorn-environment-check)
  local all_found=true
  local nfs_client_kernel_configs=("CONFIG_NFS_V4_1" "CONFIG_NFS_V4_2")

  for config in "${nfs_client_kernel_configs[@]}"; do
    declare -A nodes=()

    for pod in ${pods}; do
      node=$(kubectl get ${pod} --no-headers -o=custom-columns=:.spec.nodeName)
      res=$(kubectl exec -t $pod -- nsenter --mount=/proc/1/ns/mnt -- bash -c "grep -E \"^# ${config} is not set\" /boot/config-$(uname -r)" > /dev/null 2>&1)
      if [[ $? == 0 ]]; then
        all_found=false
        nodes["${node}"]="${node}"
      else
        res=$(kubectl exec -t $pod -- nsenter --mount=/proc/1/ns/mnt -- bash -c "grep -E \"^${config}=\" /boot/config-$(uname -r)" > /dev/null 2>&1)
        if [[ $? != 0 ]]; then
          all_found=false
          warn "Unable to check kernel config ${config} on node ${node}"
        fi
      fi
    done

    if [ ${#nodes[@]} != 0 ]; then
      warn ""${config}" kernel config is not enabled on nodes ${nodes[*]}."
    fi
  done

  if [[ ${all_found} == false ]]; then
    warn "NFS client kernel support, ${nfs_client_kernel_configs[*]}, is not enabled on Longhorn nodes. Please refer to https://longhorn.io/docs/1.4.0/deploy/install/#installing-nfsv4-client for more information."
  fi
}

######################################################
# Main logics
######################################################
DEPENDENCIES=("kubectl" "jq" "mktemp")
check_local_dependencies "${DEPENDENCIES[@]}"

# Check the each host has a unique hostname (for RWX volume)
check_hostname_uniqueness

# Create a daemonset for checking the requirements in each node
TEMP_DIR=$(mktemp -d)

trap cleanup EXIT
create_ds
wait_ds_ready

check_nfs_client_kernel_support
check_package_installed
check_iscsid
check_multipathd
check_mount_propagation

exit 0
