#!/bin/bash

set -e

echo MAKE SURE you have \"nfs-kernel-common\" installed on the host before starting this NFS server
echo Press Ctrl-C to bail out in 3 seconds

sleep 3

echo WARNING: This NFS server won\'t save any data after you delete the container

sleep 1

source ./common.sh

NFS_SERVER=longhorn-nfs-server
NFS_IMAGE=docker.io/erezhorev/dockerized_nfs_server

BACKUPSTORE_PATH=/opt/backupstore

docker run -d \
        --name ${NFS_SERVER} \
        --privileged \
        ${NFS_IMAGE} ${BACKUPSTORE_PATH}

nfs_ip=$(get_container_ip ${NFS_SERVER})

echo NFS server is up
echo
echo Set following URL as the Backup Target in the Longhorn:
echo
echo nfs://${nfs_ip}:${BACKUPSTORE_PATH}
echo
