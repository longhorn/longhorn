#!/bin/bash

cleanup(){
    name=$1
    set +e
    docker rm -vf ${name}
    set -e
}

get_container_ip() {
    container=$1
    for i in `seq 1 5`
    do
        ip=`docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $container`
        if [ "$ip" != "" ]
        then
            break
        fi
        sleep 10
    done

    if [ "$ip" == "" ]
    then
        echo cannot find ip for $container
        exit -1
    fi
    echo $ip
}
