#!/usr/bin/env sh
# Run this script with:
# env HOST=https://rancher-lab.home PASS=admin USER=admin CLUSTER=c-zlwr8 sh -x ./check_lh.sh
# $CLUSTER - cluster id of a cluster, where you want to deploy Longhorn
# List of required tools: kubectl, curl, jq, cat
CURL=${CURL:-curl}
JQ=${JQ:-jq}

CURL=$(command -v ${CURL})
JQ=$(command -v ${JQ})
# Helper functions to reduce the amount of args we pass in on each curl/jq call,
# note we are calling whatever command -v curl/jq/etc.. found directly to avoid
# recursion
curl() {
  ${CURL} --insecure --silent -H 'content-type: application/json' "$@"
}

jq() {
  ${JQ} -r "$@"
}
# Login to rancher so we can have our bearer token to do work, the user needs to be a cluster admin
LOGINJSON=$(curl --insecure --silent ${HOST}/v3-public/localProviders/local?action=login -H 'content-type: application/json' --data-binary "$(cat <<FIN
{
  "username":"${USER}",
  "password":"${PASS}"
}
FIN
)")
TOKEN=$(echo ${LOGINJSON} | jq -r '.token')

# Generate Kubeconfig and forward it into a file
curl --insecure --silent -H 'content-type: application/json' -X POST "${HOST}/v3/clusters/${CLUSTER}?action=generateKubeconfig" -H "Authorization: Bearer ${TOKEN}" -H 'Accept: application/json' | jq -r '.config' > cluster_config.yaml
export KUBECONFIG=./cluster_config.yaml

# Looping through all of the mustbe deployed resources during 5 minutes with 10 seconds intervals
count=0
while [ "$count" -lt 30 ]
do
    # Functions and variables to calculate the number of resource to determine the success of the deployment    
    DESIRED_RESORCE_NUMBER=0
    AVAILABLE_RESOURCE_NUMBER=0

    add_desired() {
        DESIRED_RESORCE_NUMBER=$(($DESIRED_RESORCE_NUMBER+$1))
    }

    add_available() {
        AVAILABLE_RESOURCE_NUMBER=$(($AVAILABLE_RESOURCE_NUMBER+$1))
    }

    # Use check_replicas "resource_type" "resorce_name" 
    # Ex. check_replicas "deployment" "longhorn-ui"
    check_replicas() {
        AVAILABLE_REPLICAS=$(kubectl get ${1} ${2} --namespace longhorn-system -o json | jq -r '.status.availableReplicas')
        DESIRED_REPLICAS=$(kubectl get ${1} ${2} --namespace longhorn-system -o json | jq -r '.spec.replicas')
        if [ -z "$DESIRED_REPLICAS" ] || [ -z "$AVAILABLE_REPLICAS" ]
        then
            echo "Longhorn ${1} ${2} replicas not deployed yet"
        elif [ "$DESIRED_REPLICAS" -eq "$AVAILABLE_REPLICAS" ]
        then
            echo "Longhorn ${1} ${2} replicas deployed successfully"
            add_desired "$DESIRED_REPLICAS"
            add_available "$AVAILABLE_REPLICAS"
        else
            echo "Longhorn ${1} ${2} replicas not fully deployed yet"
        fi
    }

    ### Kubernetes nodes check
    # Generate a list of nodes 
    NODE_LIST=$(kubectl get nodes -o json | jq -r '.items[].metadata.name')

    # Iterate through nodes and determine if each node has Kubelet in Ready status
    for node in $(echo $NODE_LIST)
    do
        NODE_STATUS=$(kubectl get nodes $node -o json | jq -r '.status.conditions[] | select(.reason == "KubeletReady") | .status')
        add_desired "1"
        if [ -z "$NODE_STATUS" ]
        then
            echo "Node $node is not ready yet"
            break
        elif [ $NODE_STATUS = "True" ]
        then
            echo "Node $node is ready"
            add_available "1"
        else
            echo "Node $node is not ready yet"
            add_available "-1"
        fi
    done

    ### DAEMONSETS
    # Check the number of Longhorn Manager daemonsets
    DESIRED_LH_MANAGER_DS_NUMBER=$(kubectl get daemonsets.apps longhorn-manager  -n longhorn-system -o json | jq -r '.status | .desiredNumberScheduled')
    READY_LH_MANAGER_DS_NUMBER=$(kubectl get daemonsets longhorn-manager  -n longhorn-system -o json | jq -r '.status | .numberReady')
    if [ -z "$DESIRED_LH_MANAGER_DS_NUMBER" ] || [ -z "$READY_LH_MANAGER_DS_NUMBER" ]
    then
        echo "Longhorn Manager deamonsets are not deployed yet"
    elif [ "$DESIRED_LH_MANAGER_DS_NUMBER" -eq "$READY_LH_MANAGER_DS_NUMBER" ]
    then
        echo "Longhorn Manager deamonsets are deployed"
        add_desired "$DESIRED_LH_MANAGER_DS_NUMBER"
        add_available "$READY_LH_MANAGER_DS_NUMBER"
    else
        echo "Longhorn Manager deamonsets are not fully deployed yet"
    fi


    ### CRDs
    # Compare the desired Longhorn manager number of daemonsets to a number of nodes in longhorn-system namespace
    # If numbers match, proceed with checking nodes and instance-managers statuses
    LONGHORN_NODE_LIST_NUMBER=$(kubectl get nodes.longhorn.io -n longhorn-system -o json | jq -r '.items[].spec.name' | wc -l)
    if [ "$LONGHORN_NODE_LIST_NUMBER" -eq 0 ] || [ "$DESIRED_LH_MANAGER_DS_NUMBER" -ne "$LONGHORN_NODE_LIST_NUMBER" ]
    then
        echo "Longhorn nodes CRDs are not deployed yet"
    else
        # Generate a list of nodes that Lonhorn is installed on
        LONGHORN_NODE_LIST=$(kubectl get nodes.longhorn.io -n longhorn-system -o json | jq -r '.items[].spec.name')
        # Iterate through Longhorn nodes and determine if each node has Kubelet in Ready status
        for node in $(echo $LONGHORN_NODE_LIST)
        do
            LONGHORN_NODE_STATUS=$(kubectl get nodes.longhorn.io/node1 -n longhorn-system -o json | jq -r '.status.conditions.Ready.status')
            add_desired "1"
            if [ -z "$LONGHORN_NODE_STATUS" ]
            then
                echo "Longhorn Node $node is not deployed yet"
                break
            elif [ $LONGHORN_NODE_STATUS = "True" ]
            then
                echo "Longhorn Node $node is deployed successfully"
                add_available "1"
            else
                echo "Longhorn Node $node is not deployed yet"
                add_available "-1"
            fi
        done

        # Iterate through nodes to see if instance-managers: engine and replica are deployed
        for node in $(echo $LONGHORN_NODE_LIST)
        do
            for manager in engine replica
            do
                STATUS=$(kubectl get instancemanagers -n longhorn-system -o json | jq -r ".items[] | select(.spec.nodeID == \"$node\") | select(.spec.type == \"$manager\") | .status.currentState")
                add_desired "1"
                # Variable STATUS will be empty when there are resources deployed yet, therefore break out of the loop
                if [ -z "$STATUS" ]
                then
                    echo "Node $node has instance manager $manager not deployed yet"
                    break
                elif [ "$STATUS" = "running" ]
                then
                    echo "Node $node has instance manager $manager deployed"
                    add_available "1"
                else
                    echo "Node $node has instance manager $manager not fully deployed yet"
                    add_available "-1"
                fi
            done
        done
    fi

    # Engine images status
    ENGINE_IMAGES_STATUS=$(kubectl get engineimages -n longhorn-system -o json | jq -r '.items[].status.state')
    add_desired "1"
    if [ "$ENGINE_IMAGES_STATUS" = "deployed" ]
    then
        echo "Longhorn Engine Images deployed successfully"
        add_available "1"
    else
        echo "Longhorn Engine Images are not deployed yet"
        add_available "-1"
    fi

    # Checking if Longhorn CSI Plugin is running on all nodes
    DESIRED_CSI_PLUGIN_NUMBER=$(kubectl get daemonsets longhorn-csi-plugin  -n longhorn-system -o json | jq -r '.status.desiredNumberScheduled')
    AVAILABLE_CSI_PLUGIN_NUMBER=$(kubectl get daemonsets longhorn-csi-plugin  -n longhorn-system -o json | jq -r '.status.numberAvailable')
    if [ -z "$DESIRED_CSI_PLUGIN_NUMBER" ] || [ -z "$AVAILABLE_CSI_PLUGIN_NUMBER" ]
    then
        echo "Longhorn CSI Plugin not deployed yet"
    elif [ "$DESIRED_CSI_PLUGIN_NUMBER" -eq "$AVAILABLE_CSI_PLUGIN_NUMBER" ]
    then
        echo "Longhorn CSI Plugin deployed successfully"
        add_desired "$DESIRED_CSI_PLUGIN_NUMBER"
        add_available "$AVAILABLE_CSI_PLUGIN_NUMBER"
    else
        echo "Longhorn CSI Plugin not fully deployed yet"
    fi

    # Longhorn UI deployment status
    check_replicas "deployment" "longhorn-ui"

    # Checking Longhorn CSI Attacher deployment status
    check_replicas "deployment" "csi-attacher"

    # Checking Longhorn CSI Provisioner deployment status
    check_replicas "deployment" "csi-provisioner"

    # Checking Longhorn CSI Resizer deployment status
    check_replicas "deployment" "csi-resizer"

    # Checking Longhorn CSI Snapshotter deployment status
    check_replicas "deployment" "csi-snapshotter"

    if [ "$DESIRED_RESORCE_NUMBER" -eq "$AVAILABLE_RESOURCE_NUMBER" ]
    then
        echo "All resources deployed successfully"
        break
    else
        echo "Not all resorces deployed yet"
    fi
    count=$(($count+1))
    sleep 10
done
