#!/bin/bash

set -e

source ./common.sh

USAGE="Usage: $(basename $0) [-p \<ui_port\>]"

while [[ $# -gt 1 ]]
do
        key="$1"

        case $key in
                -p|--ui-port)
                        port="$2"
                        shift # past argument
                        ;;
                -n|--network)
                        network="$2"
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

options=
if [ "$port" != "" ]; then
        options="${options} -p $port"
fi

network_option=
if [ "$network" != "" ]; then
        options="${options} -n ${network}"
        network_option="--network ${network}"
fi

ETCD_SERVER=longhorn-etcd-server
ETCD_IMAGE=quay.io/coreos/etcd:v3.1.5

cleanup $ETCD_SERVER

docker run -d \
        --name $ETCD_SERVER \
        --volume /etcd-data \
        ${network_option} \
        $ETCD_IMAGE \
        /usr/local/bin/etcd \
        --name longhorn-etcd-server \
        --data-dir /tmp/etcd-data:/etcd-data \
        --listen-client-urls http://0.0.0.0:2379 \
        --advertise-client-urls http://0.0.0.0:2379

etcd_ip=$(get_container_ip $ETCD_SERVER)
echo etcd server is up at ${etcd_ip}
echo

./longhorn-deploy-node.sh -e ${etcd_ip} ${options}
