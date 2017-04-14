#!/bin/bash

cleanup(){
    name=$1
    set +e
    echo clean up ${name} if exists
    docker rm -vf ${name} > /dev/null 2>&1
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

validate_ip() {
    ip=$1
    rx='([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])'
    if [[ $ip =~ ^$rx\.$rx\.$rx\.$rx$ ]]; then
        return 0
    fi
    echo Invalid ip address ${ip}
    return 1
}
