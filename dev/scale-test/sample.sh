#!/bin/bash

requested=${1:-0}
node_count=${2:-1}
required_scale=$((requested / node_count))

now=$(date)
ready=$(kubectl get pods -o custom-columns=NAMESPACE:metadata.namespace,POD:metadata.name,PodIP:status.podIP,READY:status.containerStatuses[*].ready | grep -c true)
echo "$ready -- $now - start state"

cmd=$(kubectl scale --replicas="$required_scale" statefulset --all)
echo "$cmd"
while [ "$ready" -ne "$requested" ]; do
  sleep 60
  now=$(date)
  ready=$(kubectl get pods -o custom-columns=NAMESPACE:metadata.namespace,POD:metadata.name,PodIP:status.podIP,READY:status.containerStatuses[*].ready | grep -c true)
  echo "$ready -- $now - delta:"
done
echo "$requested -- $now - done state"