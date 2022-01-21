#!/usr/bin/env bash

NS="longhorn-system"

print_usage() {
    echo "Usage: ${0} [ |-h|--help]  [volume_name|--all]"
    echo ""
    echo "Examples:"
    echo "  ${0} test-vol"
    echo "  ${0} --all"
    echo ""
    echo "Note: Must have Longhorn installed in "longhorn-system" namespace"
    echo ""
    exit 0
}

exec_command() {
    COMMAND_ARG="${@}"
    LONGHORN_MANAGER=$(kubectl -n ${NS} get po -l "app=longhorn-manager" | tr '\000' '\n' | sed -n '2p' | awk '{print $1}')
    kubectl -n ${NS} exec -it ${LONGHORN_MANAGER} -- bash -c "longhorn-manager migrate-for-pre-070-volumes ${COMMAND_ARG}"
}


ARG=$1
case $ARG in
    "" | "-h" | "--help")
        print_usage
        ;;
    *)
        if [[ $# -ne 1 ]]; then
            echo "Command args number shouldn't be greater than 1"
        fi
        exec_command "${@}"
        ;;
esac
