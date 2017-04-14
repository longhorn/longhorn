#!/bin/bash

set -e

source ./common.sh

network=$1
etcd_ip=$2

if [ "$network" == "" -o "$etcd_ip" == "" ]; then
        echo usage: $(basename $0) \<network_name\> \<etcd_server_ip\>
        exit 1
fi

set +e
iscsiadm_check=`iscsiadm --version 2>&1`
if [ $? -ne 0 ]; then
        echo Cannot find \`iscsiadm\` on the host, please install \`open-iscsi\` package
        exit 1
fi
set -e

LONGHORN_ENGINE_BINARY_NAME="longhorn-engine-binary"
LONGHORN_ENGINE_IMAGE="rancher/longhorn-engine:046b5a5"

LONGHORN_MANAGER_NAME="longhorn-manager"
LONGHORN_MANAGER_IMAGE="rancher/longhorn-manager:31b613b"

LONGHORN_DRIVER_NAME="longhorn-driver"
LONGHORN_DRIVER_IMAGE="imikushin/storage-longhorn:8b1bb5c"

LONGHORN_UI_NAME="longhorn-ui"
LONGHORN_UI_IMAGE="rancher/longhorn-ui:5528110"

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
        --network ${network} \
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

host_port=8080

cleanup ${LONGHORN_UI_NAME}
docker run -d \
        --name ${LONGHORN_UI_NAME} \
        --network ${network} \
        -p ${host_port}:8000/tcp \
        -e LONGHORN_MANAGER_IP=http://${manager_ip}:9500 \
        ${LONGHORN_UI_IMAGE}
echo ${LONGHORN_UI_NAME} is ready

echo
echo Longhorn is up at port ${host_port}
