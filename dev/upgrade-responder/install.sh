#!/bin/bash

UPGRADE_RESPONDER_REPO="https://github.com/longhorn/upgrade-responder.git"
UPGRADE_RESPONDER_REPO_BRANCH="master"
UPGRADE_RESPONDER_VALUE_YAML="upgrade-responder-value.yaml"
UPGRADE_RESPONDER_IMAGE_REPO="longhornio/upgrade-responder"
UPGRADE_RESPONDER_IMAGE_TAG="longhorn-head"

INFLUXDB_URL="http://influxdb.default.svc.cluster.local:8086"

APP_NAME="longhorn"

DEPLOYMENT_TIMEOUT_SEC=300
DEPLOYMENT_WAIT_INTERVAL_SEC=5

temp_dir=$(mktemp -d)
trap 'rm -rf "${temp_dir}"' EXIT # -f because packed Git files (.pack, .idx) are write protected.

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
flags:
  scarfEndpoint: "https://longhorn.gateway.scarf.sh/{version}"
configMap:
  responseConfig: |-
    {
      "versions": [{
        "name": "v1.0.0",
        "releaseDate": "2020-05-18T12:30:00Z",
        "tags": ["latest"]
      }]
    }
  requestSchema: |-
    {
      "appVersionSchema": {
        "dataType": "string",
        "maxLen": 200
      },
      "extraTagInfoSchema": {
        "hostArch": {
          "dataType": "string",
          "maxLen": 200
        },
        "hostKernelRelease": {
          "dataType": "string",
          "maxLen": 200
        },
        "hostOsDistro": {
          "dataType": "string",
          "maxLen": 200
        },
        "kubernetesNodeProvider": {
          "dataType": "string",
          "maxLen": 200
        },
        "kubernetesVersion": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornImageRegistry": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingAllowRecurringJobWhileVolumeDetached": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingAllowVolumeCreationWithDegradedAvailability": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingAutoCleanupSystemGeneratedSnapshot": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingAutoDeletePodWhenVolumeDetachedUnexpectedly": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingAutoSalvage": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingBackupCompressionMethod": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingBackupTarget": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingCrdApiVersion": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingCreateDefaultDiskLabeledNodes": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingDefaultDataLocality": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingDisableRevisionCounter": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingDisableSchedulingOnCordonedNode": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingFastReplicaRebuildEnabled": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingFreezeFilesystemForSnapshot": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingKubernetesClusterAutoscalerEnabled": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingNodeDownPodDeletionPolicy": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingNodeDrainPolicy": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingOrphanResourceAutoDeletion": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingPriorityClass": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingRegistrySecret": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingRemoveSnapshotsDuringFilesystemTrim": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingReplicaAutoBalance": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingReplicaSoftAntiAffinity": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingReplicaZoneSoftAntiAffinity": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingReplicaDiskSoftAntiAffinity": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingRestoreVolumeRecurringJobs": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingRwxVolumeFastFailover": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingSnapshotDataIntegrity": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingSnapshotDataIntegrityCronjob": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingSnapshotDataIntegrityImmediateCheckAfterSnapshotCreation": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingStorageNetwork": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingSystemManagedComponentsNodeSelector": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingSystemManagedPodsImagePullPolicy": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingTaintToleration": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingV1DataEngine": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornSettingV2DataEngine": {
          "dataType": "string",
          "maxLen": 200
        }
      },
      "extraFieldInfoSchema": {
        "longhornBackingImageCount": {
          "dataType": "float"
        },
        "longhornDiskBlockCount": {
          "dataType": "float"
        },
        "longhornDiskFilesystemCount": {
          "dataType": "float"
        },
        "longhornInstanceManagerAverageCpuUsageMilliCores": {
          "dataType": "float"
        },
        "longhornInstanceManagerAverageMemoryUsageBytes": {
          "dataType": "float"
        },
        "longhornManagerAverageCpuUsageMilliCores": {
          "dataType": "float"
        },
        "longhornManagerAverageMemoryUsageBytes": {
          "dataType": "float"
        },
        "longhornNamespaceUid": {
          "dataType": "string",
          "maxLen": 200
        },
        "longhornNodeCount": {
          "dataType": "float"
        },
        "longhornNodeDiskHDDCount": {
          "dataType": "float"
        },
        "longhornNodeDiskNVMeCount": {
          "dataType": "float"
        },
        "longhornNodeDiskSSDCount": {
          "dataType": "float"
        },
        "longhornOrphanCount": {
          "dataType": "float"
        },
        "longhornSettingBackingImageCleanupWaitInterval": {
          "dataType": "float"
        },
        "longhornSettingBackingImageRecoveryWaitInterval": {
          "dataType": "float"
        },
        "longhornSettingBackupConcurrentLimit": {
          "dataType": "float"
        },
        "longhornSettingBackupstorePollInterval": {
          "dataType": "float"
        },
        "longhornSettingBackupBlockSize": {
          "dataType": "float"
        },
        "longhornSettingConcurrentAutomaticEngineUpgradePerNodeLimit": {
          "dataType": "float"
        },
        "longhornSettingConcurrentReplicaRebuildPerNodeLimit": {
          "dataType": "float"
        },
        "longhornSettingConcurrentVolumeBackupRestorePerNodeLimit": {
          "dataType": "float"
        },
        "longhornSettingDefaultReplicaCount": {
          "dataType": "float"
        },
        "longhornSettingEngineReplicaTimeout": {
          "dataType": "float"
        },
        "longhornSettingFailedBackupTtl": {
          "dataType": "float"
        },
        "longhornSettingReplicaRebuildingBandwidthLimit": {
          "dataType": "float"
        },
        "longhornSettingGuaranteedInstanceManagerCpu": {
          "dataType": "float"
        },
        "longhornSettingRecurringFailedJobsHistoryLimit": {
          "dataType": "float"
        },
        "longhornSettingRecurringSuccessfulJobsHistoryLimit": {
          "dataType": "float"
        },
        "longhornSettingReplicaFileSyncHttpClientTimeout": {
          "dataType": "float"
        },
        "longhornSettingReplicaReplenishmentWaitInterval": {
          "dataType": "float"
        },
        "longhornSettingRestoreConcurrentLimit": {
          "dataType": "float"
        },
        "longhornSettingStorageMinimalAvailablePercentage": {
          "dataType": "float"
        },
        "longhornSettingStorageOverProvisioningPercentage": {
          "dataType": "float"
        },
        "longhornSettingStorageReservedPercentageForDefaultDisk": {
          "dataType": "float"
        },
        "longhornSettingSupportBundleFailedHistoryLimit": {
          "dataType": "float"
        },
        "longhornVolumeAccessModeRwoCount": {
          "dataType": "float"
        },
        "longhornVolumeAccessModeRwxCount": {
          "dataType": "float"
        },
        "longhornVolumeAccessModeUnknownCount": {
          "dataType": "float"
        },
        "longhornVolumeAverageActualSizeBytes": {
          "dataType": "float"
        },
        "longhornVolumeAverageNumberOfReplicas": {
          "dataType": "float"
        },
        "longhornVolumeAverageSizeBytes": {
          "dataType": "float"
        },
        "longhornVolumeAverageSnapshotCount": {
          "dataType": "float"
        },
        "longhornVolumeBackendStoreDriverV1Count": {
          "dataType": "float"
        },
        "longhornVolumeBackendStoreDriverV2Count": {
          "dataType": "float"
        },
        "longhornVolumeDataLocalityBestEffortCount": {
          "dataType": "float"
        },
        "longhornVolumeDataLocalityDisabledCount": {
          "dataType": "float"
        },
        "longhornVolumeDataLocalityStrictLocalCount": {
          "dataType": "float"
        },
        "longhornVolumeEncryptedTrueCount": {
          "dataType": "float"
        },
        "longhornVolumeEncryptedFalseCount": {
          "dataType": "float"
        },
        "longhornFreezeFilesystemForSnapshotTrueCount": {
          "dataType": "float"
        },
        "longhornVolumeFrontendBlockdevCount": {
          "dataType": "float"
        },
        "longhornVolumeFrontendIscsiCount": {
          "dataType": "float"
        },
        "longhornVolumeNumberOfReplicas": {
          "dataType": "float"
        },
        "longhornVolumeNumberOfSnapshots": {
          "dataType": "float"
        },
        "longhornVolumeReplicaAutoBalanceDisabledCount": {
          "dataType": "float"
        },
        "longhornVolumeReplicaSoftAntiAffinityFalseCount": {
          "dataType": "float"
        },
        "longhornVolumeReplicaZoneSoftAntiAffinityTrueCount": {
          "dataType": "float"
        },
        "longhornVolumeReplicaDiskSoftAntiAffinityTrueCount": {
          "dataType": "float"
        },
        "longhornVolumeRestoreVolumeRecurringJobFalseCount": {
          "dataType": "float"
        },
        "longhornVolumeSnapshotDataIntegrityDisabledCount": {
          "dataType": "float"
        },
        "longhornVolumeSnapshotDataIntegrityFastCheckCount": {
          "dataType": "float"
        },
        "longhornVolumeUnmapMarkSnapChainRemovedFalseCount": {
          "dataType": "float"
        },
        "longhornSettingOrphanResourceAutoDeletionGracePeriod": {
          "dataType": "float"
        }
      }
    }
image:
  repository: ${UPGRADE_RESPONDER_IMAGE_REPO}
  tag: ${UPGRADE_RESPONDER_IMAGE_TAG}
EOF

    git clone -b ${UPGRADE_RESPONDER_REPO_BRANCH} ${UPGRADE_RESPONDER_REPO}
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
