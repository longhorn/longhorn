#!/bin/bash

set -e

LONGHORN_ENGINE_IMAGE="rancher/longhorn-engine:046b5a5"
LONGHORN_MANAGER_IMAGE="rancher/longhorn-manager:e9ed45f"
LONGHORN_DRIVER_IMAGE="rancher/storage-longhorn:11a4f5a"
LONGHORN_UI_IMAGE="rancher/longhorn-ui:b09b215"

source ./common.sh

USAGE="Usage: $(basename $0) -e \<etcd_ip\> [-n \<network\> -p \<ui_port\>]"

while [[ $# -gt 1 ]]
do
        key="$1"

        case $key in
                -e|--etcd-ip)
                        etcd_ip="$2"
                        shift # past argument
                        ;;
                -n|--network)
                        network="$2"
                        shift # past argument
                        ;;
                -p|--ui-port)
                        port="$2"
                        shift # past argument
                        ;;
                *)
                        # unknown
                        # option
                        echo ${USAGE}
                        break
                        ;;
        esac
        shift
done

if [ "$etcd_ip" == "" ]; then
        echo ${USAGE}
        exit 1
fi

# will error out if fail since we have set -e
validate_ip ${etcd_ip}

network_option=
if [ "$network" != "" ]; then
        network_option="--network ${network}"
fi

ui_port=8080
if [ "$port" != "" ]; then
        ui_port=$port
fi

set +e
iscsiadm_check=`iscsiadm --version > /dev/null 2>&1`
if [ $? -ne 0 ]; then
        echo Cannot find \`iscsiadm\` on the host, please install \`open-iscsi\` package
        exit 1
fi
set -e

LONGHORN_ENGINE_BINARY_NAME="longhorn-engine-binary"
LONGHORN_MANAGER_NAME="longhorn-manager"
LONGHORN_DRIVER_NAME="longhorn-driver"
LONGHORN_UI_NAME="longhorn-ui"

# longhorn-binary first, provides binary to longhorn-manager
cleanup ${LONGHORN_ENGINE_BINARY_NAME}

docker run --name ${LONGHORN_ENGINE_BINARY_NAME} \
        --network none \
        ${LONGHORN_ENGINE_IMAGE} \
	/bin/bash
echo ${LONGHORN_ENGINE_BINARY_NAME} is ready

# now longhorn-manager
cleanup ${LONGHORN_MANAGER_NAME}

docker run -d \
        --name ${LONGHORN_MANAGER_NAME} \
        ${network_option} \
        --privileged \
        --uts host \
        -v /dev:/host/dev \
        -v /var/run:/var/run \
        -v /var/lib/rancher/longhorn:/var/lib/rancher/longhorn \
        --volumes-from ${LONGHORN_ENGINE_BINARY_NAME} \
        ${LONGHORN_MANAGER_IMAGE} \
        launch-manager -d \
        --orchestrator docker \
        --engine-image ${LONGHORN_ENGINE_IMAGE} \
        --etcd-servers http://${etcd_ip}:2379
echo ${LONGHORN_MANAGER_NAME} is ready

# finally longhorn-driver
cleanup ${LONGHORN_DRIVER_NAME}

docker run -d \
        --name ${LONGHORN_DRIVER_NAME} \
        --network none \
        --privileged \
        -v /run:/run \
        -v /var/run:/var/run \
        -v /dev:/host/dev \
        -v /var/lib/rancher/volumes:/var/lib/rancher/volumes:shared \
        ${LONGHORN_DRIVER_IMAGE}
echo ${LONGHORN_DRIVER_NAME} is ready

manager_ip=$(get_container_ip ${LONGHORN_MANAGER_NAME})

cleanup ${LONGHORN_UI_NAME}

docker run -d \
        --name ${LONGHORN_UI_NAME} \
        ${network_option} \
        -p ${ui_port}:8000/tcp \
        -e LONGHORN_MANAGER_IP=http://${manager_ip}:9500 \
        ${LONGHORN_UI_IMAGE}
echo ${LONGHORN_UI_NAME} is ready

echo
echo Longhorn is up at port ${ui_port}
