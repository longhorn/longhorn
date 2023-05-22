#!/bin/bash

UPGRADE_RESPONDER_REPO="https://github.com/longhorn/upgrade-responder.git"
UPGRADE_RESPONDER_VALUE_YAML="upgrade-responder-value.yaml"
UPGRADE_RESPONDER_IMAGE_REPO="longhornio/upgrade-responder"
UPGRADE_RESPONDER_IMAGE_TAG="master-head"

INFLUXDB_URL="http://influxdb.default.svc.cluster.local:8086"

APP_NAME="longhorn"

DEPLOYMENT_TIMEOUT_SEC=300
DEPLOYMENT_WAIT_INTERVAL_SEC=5

temp_dir=$(mktemp -d)
trap 'rm -r "${temp_dir}"' EXIT

cp -a ./* ${temp_dir}
cd ${temp_dir}

wait_for_deployment() {
  local deployment_name="$1"
  local start_time=$(date +%s)

  while true; do
    status=$(kubectl rollout status deployment/${deployment_name})
    if [[ ${status} == *"successfully rolled out"* ]]; then
      echo "Deployment ${deployment_name} is running."
      break
    fi

    elapsed_secs=$(($(date +%s) - ${start_time}))
    if [[ ${elapsed_secs} -ge ${timeout_secs} ]]; then
      echo "Timed out waiting for deployment ${deployment_name} to be running."
      exit 1
    fi

    echo "Deployment ${deployment_name} is not running yet. Waiting..."
    sleep ${DEPLOYMENT_WAIT_INTERVAL_SEC}
  done
}

install_influxdb() {
    kubectl apply -f ./manifests/influxdb.yaml
    wait_for_deployment "influxdb"
}

install_grafana() {
    kubectl apply -f ./manifests/grafana.yaml
    wait_for_deployment "grafana"
}

install_upgrade_responder() {
    cat << EOF > ${UPGRADE_RESPONDER_VALUE_YAML}
applicationName: ${APP_NAME}
secret:
  name: upgrade-responder-secrets
  managed: true
  influxDBUrl: "${INFLUXDB_URL}"
  influxDBUser: "root"
  influxDBPassword: "root"
image:
  repository: ${UPGRADE_RESPONDER_IMAGE_REPO}
  tag: ${UPGRADE_RESPONDER_IMAGE_TAG}
EOF

    git clone ${UPGRADE_RESPONDER_REPO}
    helm upgrade --install ${APP_NAME}-upgrade-responder upgrade-responder/chart -f ${UPGRADE_RESPONDER_VALUE_YAML}
    wait_for_deployment "${APP_NAME}-upgrade-responder"
}

output() {
    local upgrade_responder_service_info=$(kubectl get svc/${APP_NAME}-upgrade-responder --no-headers)
    local upgrade_responder_service_port=$(echo "${upgrade_responder_service_info}" | awk '{print $5}' | cut -d'/' -f1)
    echo  # a blank line to separate the installation outputs for better readability.
    printf "[Upgrade Checker]\n"
    printf "%-10s: http://${APP_NAME}-upgrade-responder.default.svc.cluster.local:${upgrade_responder_service_port}/v1/checkupgrade\n\n" "URL"

    printf "[InfluxDB]\n"
    printf "%-10s: ${INFLUXDB_URL}\n" "URL"
    printf "%-10s: ${APP_NAME}_upgrade_responder\n" "Database"
    printf "%-10s: root\n" "Username"
    printf "%-10s: root\n\n" "Password"

    local public_ip=$(curl -s https://ifconfig.me/ip)
    local grafana_service_info=$(kubectl get svc/grafana --no-headers)
    local grafana_service_port=$(echo "${grafana_service_info}" | awk '{print $5}' | cut -d':' -f2 | cut -d'/' -f1)
    printf "[Grafana]\n"
    printf "%-10s: http://${public_ip}:${grafana_service_port}\n" "Dashboard"
    printf "%-10s: admin\n" "Username"
    printf "%-10s: admin\n" "Password"
}

install_influxdb
install_upgrade_responder
install_grafana
output
