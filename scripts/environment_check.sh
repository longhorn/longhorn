#!/bin/bash

NVME_CLI_VERSION="1.12"
LONGHORN_CLI_VERSION="v1.7.0-rc2"

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
check_local_dependencies() {
  local targets=($@)

  local all_found=true
  for ((i=0; i<${#targets[@]}; i++)); do
    local target=${targets[$i]}
    if [ "$(which $target)" = "" ]; then
      all_found=false
      error "Not found: $target"
    fi
  done

  if [ "$all_found" = "false" ]; then
    msg="Please install missing dependencies: ${targets[@]}."
    info "$msg"
    exit 2
  fi

  msg="Required dependencies '${targets[@]}' are installed."
  info "$msg"
}

check_hostname_uniqueness() {
  hostnames=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')

  if [ $? -ne 0 ]; then
    error "kubectl get nodes failed - check KUBECONFIG setup"
    exit 1
  fi

  if [[ ! ${hostnames[@]} ]]; then
    error "kubectl get nodes returned empty list - check KUBECONFIG setup"
    exit 1
  fi

  deduplicate_hostnames=()
  num_nodes=0
  for hostname in ${hostnames}; do
    num_nodes=$((num_nodes+1))
    if ! echo "${deduplicate_hostnames[@]}" | grep -q "\<${hostname}\>"; then
      deduplicate_hostnames+=("${hostname}")
    fi
  done

  if [ "${#deduplicate_hostnames[@]}" != "${num_nodes}" ]; then
    error "Nodes do not have unique hostnames."
    exit 2
  fi

  info "All nodes have unique hostnames."
}

get_arch() {
  local callback=$1
  shift

  ARCH=$(uname -m)
  case $ARCH in
    armv5*) ARCH="armv5";;
    armv6*) ARCH="armv6";;
    armv7*) ARCH="arm";;
    aarch64) ARCH="arm64";;
    arm64) ARCH="arm64";;
    x86) ARCH="386";;
    x86_64) ARCH="amd64";;
    i686) ARCH="386";;
    i386) ARCH="386";;
  esac

  if [ $ARCH != "amd64" ] && [ $ARCH != "arm64" ]; then
    error "Unsupported architecture $ARCH"
    return 1
  fi

  eval "${callback} ${ARCH} $@"
}

cli_preflight() {
  local arch=$1
  local spdk=$2
  local version=$3
  local opt=""

  if [ "$version" == ""  ]; then
    version=$LONGHORN_CLI_VERSION
    info "Use default Longhorn CLI version: $version"
  fi

  curl -sSfL -o $TEMP_DIR/longhornctl https://github.com/longhorn/cli/releases/download/$version/longhornctl-linux-$arch
  chmod +x $TEMP_DIR/longhornctl

  if [ "$spdk" = "true" ]; then
    opt="--enable-spdk"
  fi

  $TEMP_DIR/longhornctl check preflight $opt
}

function show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
    -s, --enable-spdk           Enable checking SPDK prerequisites
    -v, --version               Specify the version of Longhorn CLI to use
    -h, --help                  Show this help message and exit
EOF
    exit 0
}

enable_spdk=false
cli_version=""
while [[ $# -gt 0 ]]; do
    opt="$1"
    case $opt in
        -s|--enable-spdk)
            enable_spdk=true
            ;;
        --enable-spdk=*)
            enable_spdk_flag="${1#*=}"
            if [[ "$enable_spdk_flag" == "true" ]]; then
                enable_spdk=true
            elif [[ "$enable_spdk_flag" == "false" ]]; then
                enable_spdk=false
            else
                error "--enable-spdk requires a boolean option argument."
                show_help
                exit 1
            fi
            ;;
        -v|--version)
            if [[ -n "$2" && "$2" != -* ]]; then
                cli_version="$2"
                shift
            else
                error "--version requires a non-empty option argument."
                show_help
                exit 1
            fi
            ;;
        --version=*)
            cli_version="${1#*=}"
            ;;
        -h|--help)
            show_help
            ;;
        *)
            ;;
    esac
    shift
done

######################################################
# Main logics
######################################################
DEPENDENCIES=("kubectl" "mktemp")
check_local_dependencies "${DEPENDENCIES[@]}"

# Check the each host has a unique hostname (for RWX volume)
check_hostname_uniqueness

TEMP_DIR=$(mktemp -d)

get_arch cli_preflight $enable_spdk $cli_version

exit 0
