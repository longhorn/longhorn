#!/bin/bash

#set -x
set -e

username=$1

if [ "$username" == "" ]
then
	echo DockerHub username is required
	exit 1
fi

update=$2

project="longhorn-manager"
base="${GOPATH}/src/github.com/longhorn/longhorn-manager"
yaml=${base}"/deploy/install/02-components/01-manager.yaml"
driver_yaml=${base}"/deploy/install/02-components/04-driver.yaml"

latest=`cat ${base}/bin/latest_image`
private=`sed "s/longhornio/${username}/g" ${base}/bin/latest_image`

echo Latest image ${latest}
echo Latest private image ${private}
docker tag ${latest} ${private}
docker push ${private}

escaped_private=${private//\//\\\/}
sed -i "s/image\:\ .*\/${project}:.*/image\:\ ${escaped_private}/g" $yaml
sed -i "s/-\ .*\/${project}:.*/-\ ${escaped_private}/g" $yaml
sed -i "s/imagePullPolicy\:\ .*/imagePullPolicy\:\ Always/g" $yaml
sed -i "s/image\:\ .*\/${project}:.*/image\:\ ${escaped_private}/g" $driver_yaml
sed -i "s/-\ .*\/${project}:.*/-\ ${escaped_private}/g" $driver_yaml
sed -i "s/imagePullPolicy\:\ .*/imagePullPolicy\:\ Always/g" $driver_yaml

set +e

if [ "$update" == ""  ]
then
	kubectl delete -f $yaml
	kubectl create -f $yaml
	kubectl delete -f $driver_yaml
	kubectl create -f $driver_yaml
fi
