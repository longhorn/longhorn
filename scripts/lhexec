#!/usr/bin/env bash

NS="longhorn-system"

print_usage() {
    echo "Usage: ${0} [|-h|--help]  volume_name longhorn_commands_arguments"
    echo ""
    echo "Examples:"
    echo "  ${0} test-vol snapshot ls"
    echo "  ${0} test-vol info"
    echo ""
    echo "Note: Must have Longhorn installed in "longhorn-system" namespace and have access to "kubectl" and the namespace"
    echo ""
    exit 0
}

check_volume_exist(){
    VOLUME_NAME=${1}
    kubectl -n ${NS} get lhv ${VOLUME_NAME} > /dev/null 2>&1
    if [[ ${?} -ne 0 ]]; then
        echo "Err: Volume ${VOLUME_NAME} not found"
        exit 1
    fi
}

check_engine_state(){
    VOLUME_NAME=${1}
    LHE_STATE_FILTER="{.items[?(@.spec.volumeName==\"${VOLUME_NAME}\")].status.currentState}"
    LHE_STATE=`kubectl -n ${NS} get lhe --output=jsonpath="${LHE_STATE_FILTER}"`

    if [[ ${LHE_STATE} != "running" ]]; then
        echo "Err: Longhorn engine for volume ${VOLUME_NAME} is not running"
        exit 1
    fi
    
}

exec_command() {
    VOLUME_NAME=${1}
    COMMAND_ARGS="${@:2}"

    INSTANCE_MANAGER_NAME_FILTER="{.items[?(@.spec.volumeName==\"${VOLUME_NAME}\")].status.instanceManagerName}"
    INSTANCE_MANAGER_NAME=`kubectl -n ${NS} get lhe --output=jsonpath="${INSTANCE_MANAGER_NAME_FILTER}"`

    ENGINE_PORT_FILTER="{.items[?(@.spec.volumeName==\"${VOLUME_NAME}\")].status.port}"
    ENGINE_PORT=`kubectl -n ${NS} get lhe --output=jsonpath="${ENGINE_PORT_FILTER}"`

    LONGHORN_BIN_PATH=`kubectl -n ${NS} exec -it ${INSTANCE_MANAGER_NAME} -- bash -c "ps -eo command | grep \" ${VOLUME_NAME} \" | grep -v grep | awk '{ printf(\"%s\", \\$1)}'"`

    kubectl -n ${NS} exec -it ${INSTANCE_MANAGER_NAME} -- bash -c "${LONGHORN_BIN_PATH} --url localhost:${ENGINE_PORT} ${COMMAND_ARGS}"
}


ARG=$1
case $ARG in
    "" | "-h" | "--help")
        print_usage
        ;;
    *)
        VOLUME_NAME=${ARG}
        shift
        COMMAND_ARGS="${@}"
        if [[ ${COMMAND_ARGS} == "" ]]; then
            COMMAND_ARGS="help"
        fi
        check_volume_exist ${VOLUME_NAME}
        check_engine_state ${VOLUME_NAME}
        exec_command ${VOLUME_NAME} ${COMMAND_ARGS}
        ;;
esac
