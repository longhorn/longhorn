#!/bin/bash

set -e

source ./common.sh

network=$1

if [ ${network} == "" ]; then
        echo Usage: $(basename $0) \<network\>
        exit 1
fi

ETCD_SERVER=longhorn-etcd-server
ETCD_IMAGE=quay.io/coreos/etcd:v3.1.5

cleanup $ETCD_SERVER

docker run -d \
        --name $ETCD_SERVER \
        --volume /etcd-data \
        --network ${network} \
        $ETCD_IMAGE \
        /usr/local/bin/etcd \
        --name longhorn-etcd-server \
        --data-dir /tmp/etcd-data:/etcd-data \
        --listen-client-urls http://0.0.0.0:2379 \
        --advertise-client-urls http://0.0.0.0:2379

etcd_ip=$(get_container_ip $ETCD_SERVER)
echo etcd server is up at ${etcd_ip}
echo
echo Use following command on each node to deploy longhorn
echo
echo ./longhorn-deploy-node.sh ${network} ${etcd_ip}
echo
