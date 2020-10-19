#!/bin/bash

NS=longhorn-system
KINDS="daemonset deployments"

function patch_kind {
	kind=$1
	list=$(kubectl -n $NS get $kind -o name)
	for obj in $list
	do
		echo Updating $obj to imagePullPolicy: Always
		name=${obj##*/}
		kubectl -n $NS patch $obj -p '{"spec": {"template": {"spec":{"containers":[{"name":"'$name'","imagePullPolicy":"Always"}]}}}}'
	done
}

for kind in $KINDS
do
	patch_kind $kind
done

echo "Warning: Make sure check and wait for all pods running again!"
echo "Current status: (CTRL-C to exit)"
kubectl get pods -w -n longhorn-system
