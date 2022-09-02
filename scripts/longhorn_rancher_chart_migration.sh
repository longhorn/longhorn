#!/bin/bash
#set -x

kubectl get-all version &> /dev/null
if [ $? -ne 0 ]; then
  echo "ERROR: command (kubectl get-all) is not found. Please install it here: https://github.com/corneliusweig/ketall#installation"
  exit 1
fi

set -e

usage() {
  echo ""
  echo "The migration includes:"
  echo "1. Running the script with --type migrate to migrate the labels and annotations for Longhorn resources"
  echo "2. Manually installing Longhorn chart in app&marketplace UI"
  echo "3. Running script with --type cleanup to remove the old Longhorn chart from old catalog UI"
  echo ""
  echo "usage:"
  echo "$0 [options]"
  echo "  -u | --upstream-kubeconfig:      upstream rancher cluster kubeconfig path"
  echo "  -d | --downstream-kubeconfig:    downstream cluster kubeconfig path"
  echo "  -t | --type:                     specify the type you want to run (migrate or cleanup)"
  echo "  --dry-run:                       do not run migriation"
  echo ""
  echo "example:"
  echo "  $0 -u /path/to/upstream/rancher/cluster/kubeconfig -d /path/to/downstream/cluster/kubeconfig"
}

SCRIPT_DIR="$(dirname "$0")"
UPSTREAM_KUBECONFIG=""
DOWNSTREAM_KUBECONFIG=""
KUBECTL_DRY_RUN=""

while [ "$1" != "" ]; do
  case $1 in
  -u | --upstream-kubeconfig)
    shift
    UPSTREAM_KUBECONFIG="$1"
    ;;
  -d | --downstream-kubeconfig)
    shift
    DOWNSTREAM_KUBECONFIG="$1"
    ;;
  -t | --type)
    shift
    TYPE="$1"
    ;;
  --dry-run)
    KUBECTL_DRY_RUN="--dry-run=client"
    ;;
  *)
    usage
    exit 1
    ;;
  esac
  shift
done

if [ -z "$UPSTREAM_KUBECONFIG" ]; then
  echo "--upstream-kubeconfig is mandatory"
  usage
  exit 1
fi
if [ -z "$DOWNSTREAM_KUBECONFIG" ]; then
  echo "--downstream-kubeconfig is mandatory"
  usage
  exit 1
fi
if [ "$TYPE" != "migrate" ] &&  [ "$TYPE" != "cleanup" ] ; then
  echo "--type must be set to migrate or cleanup"
  usage
  exit 1
fi


# Longhorn Namespace
RELEASE_NAMESPACE=longhorn-system
# Longhorn Release Name
RELEASE_NAME=longhorn-system


echo "Looking up Rancher Project App '${RELEASE_NAME}' ..."
DOWNSTREAMCLUSTERID=$(cat  ${DOWNSTREAM_KUBECONFIG} | grep "server:.*https://.*/k8s/clusters/.*"  | awk -F'/' '{print $(NF)}' | awk -F'"' '{print $1}')
RANCHERAPP=$(kubectl --kubeconfig ${UPSTREAM_KUBECONFIG} get --all-namespaces apps.project.cattle.io -o jsonpath='{range.items[*]}{.metadata.namespace} {.metadata.name} {.spec.targetNamespace} {.spec.projectName} {.spec.externalId}{"\n"}{end}' | grep -s "${RELEASE_NAME} ${RELEASE_NAMESPACE} ${DOWNSTREAMCLUSTERID}")
RANCHERAPPNS=$(echo "${RANCHERAPP}" | awk '{print $1}')
RANCHERAPPEXTERNALID=$(echo "${RANCHERAPP}" | awk '{print $5}')
RANCHERAPPCATALOG=$(echo "${RANCHERAPPEXTERNALID}" | sed -n 's/.*catalog=\(.*\)/\1/p' | awk -F '&' '{print $1}' | sed 's/migrated-//')
RANCHERAPPTEMPLATE=$(echo "${RANCHERAPPEXTERNALID}" | sed -n 's/.*template=\(.*\)/\1/p' | awk -F '&' '{print $1}')
RANCHERAPPTEMPLATEVERSION=$(echo "${RANCHERAPPEXTERNALID}" | sed -n 's/.*version=\(.*\)/\1/p' | awk -F '&' '{print $1}')
RANCHERAPPVALUES=""
RANCHERAPPANSWERS=""

if [ -z "$DOWNSTREAMCLUSTERID" ] || [ -z "$RANCHERAPP" ] || [ -z "$RANCHERAPPNS" ] || [ -z "$RANCHERAPPCATALOG" ] || [ -z "$RANCHERAPPTEMPLATE" ] || [ -z "$RANCHERAPPTEMPLATEVERSION" ]; then
  echo "Rancher Project App '${RELEASE_NAME}' not found!"
  exit 1
fi

RANCHERAPPVALUES=$(kubectl --kubeconfig ${UPSTREAM_KUBECONFIG} -n ${RANCHERAPPNS} get apps.project.cattle.io ${RELEASE_NAME} -o go-template='{{if .spec.valuesYaml}}{{.spec.valuesYaml}}{{end}}')
if [ -z "${RANCHERAPPVALUES}" ]; then
  RANCHERAPPANSWERS=$(kubectl --kubeconfig ${UPSTREAM_KUBECONFIG} -n ${RANCHERAPPNS} get apps.project.cattle.io ${RELEASE_NAME} -o go-template='{{if .spec.answers}}{{range $key,$value := .spec.answers}}{{$key}}: {{$value}}{{"\n"}}{{end}}{{end}}' | sed 's/: /=/' | sed 's/$/,/' | sed '$ s/.$//' | tr -d '\n')
fi
if [ -z "${RANCHERAPPVALUES:-$RANCHERAPPANSWERS}" ]; then
  echo "No valid answers found!"
  exit 1
fi

echo ""
echo "Rancher Project App '${RELEASE_NAME}' found:"
echo "  Project-Namespace: ${RANCHERAPPNS}"
echo "  Downstream-Cluster: ${DOWNSTREAMCLUSTERID}"
echo "  Catalog: ${RANCHERAPPCATALOG}"
echo "  Template: ${RANCHERAPPTEMPLATE} (${RANCHERAPPTEMPLATEVERSION})"
echo "  Answers:"
printf '%s\n' "${RANCHERAPPVALUES:-$RANCHERAPPANSWERS}"
echo ""

if [ "$TYPE" == "cleanup" ] ; then

  MANAGER=$(kubectl --kubeconfig ${DOWNSTREAM_KUBECONFIG} -n ${RELEASE_NAMESPACE} get ds longhorn-manager -ojsonpath="{.metadata.labels['app\.kubernetes\.io/managed-by']}")
  if [ $MANAGER != "Helm" ] ; then
    echo "Labels have not been migrated. Did you run the part 1 by specifying the flag --type migrate ?"
    exit 1
  fi

  echo ""
  echo "Patching Project App Catalog ..."
  kubectl --kubeconfig ${UPSTREAM_KUBECONFIG} -n ${RANCHERAPPNS} ${KUBECTL_DRY_RUN} patch apps.project.cattle.io ${RELEASE_NAME} --type=merge --patch-file=/dev/stdin <<-EOF
  {
    "metadata": {
      "annotations": {
        "cattle.io/skipUninstall": "true",
        "catalog.cattle.io/ui-source-repo": "helm3-library",
        "catalog.cattle.io/ui-source-repo-type": "cluster",
        "apps.cattle.io/migrated": "true"
      }
    }
  }
EOF

  if [ $? -ne 0 ]; then
     echo "Failed Patching Project App Catalog"
     exit 1
  fi

  echo ""
  echo "Deleting Project App Catalog ..."
  kubectl --kubeconfig ${UPSTREAM_KUBECONFIG} -n ${RANCHERAPPNS} ${KUBECTL_DRY_RUN} delete apps.project.cattle.io ${RELEASE_NAME}

  exit 0
fi

echo ""
echo ""
echo "Checking concurrent-automatic-engine-upgrade-per-node-limit setting ..."
SETTING=$(kubectl --kubeconfig ${DOWNSTREAM_KUBECONFIG} -n ${RELEASE_NAMESPACE} get settings.longhorn.io concurrent-automatic-engine-upgrade-per-node-limit -ojsonpath="{.value}")
if [ "$SETTING" != "0" ]; then
  echo "concurrent-automatic-engine-upgrade-per-node-limit must be set to 0 before the migration"
  exit 1
fi

echo ""
echo ""
echo "Looking up existing Resources ..."
RESOURCES=$(kubectl get-all --kubeconfig ${DOWNSTREAM_KUBECONFIG} --exclude AppRevision -o name -l io.cattle.field/appId=${RELEASE_NAME} 2>/dev/null | sort)
if [[ "$RESOURCES" == "No resources"* ]]; then
  RESOURCES=""
fi

echo ""
echo "Patching CRD Resources ..."
for resource in $RESOURCES; do
  if [[ $resource == "customresourcedefinition.apiextensions.k8s.io/"* ]]; then
    kubectl --kubeconfig ${DOWNSTREAM_KUBECONFIG} -n ${RELEASE_NAMESPACE} ${KUBECTL_DRY_RUN} annotate --overwrite ${resource} "meta.helm.sh/release-name"="longhorn-crd" "meta.helm.sh/release-namespace"="${RELEASE_NAMESPACE}" "helm.sh/resource-policy"="keep"
    kubectl --kubeconfig ${DOWNSTREAM_KUBECONFIG} -n ${RELEASE_NAMESPACE} ${KUBECTL_DRY_RUN} label --overwrite ${resource} "app.kubernetes.io/managed-by"="Helm"
  fi

done

echo ""
echo "Patching Other Resources ..."
for resource in $RESOURCES; do
  if [[ $resource == "customresourcedefinition.apiextensions.k8s.io/"* ]]; then
    continue
  fi
  kubectl --kubeconfig ${DOWNSTREAM_KUBECONFIG} -n ${RELEASE_NAMESPACE} ${KUBECTL_DRY_RUN} annotate --overwrite ${resource} "meta.helm.sh/release-name"="longhorn" "meta.helm.sh/release-namespace"="${RELEASE_NAMESPACE}"
  kubectl --kubeconfig ${DOWNSTREAM_KUBECONFIG} -n ${RELEASE_NAMESPACE} ${KUBECTL_DRY_RUN} label --overwrite ${resource} "app.kubernetes.io/managed-by"="Helm"
done


echo ""
echo "-----------------------------"
echo "Successfully updated the annotations and labels for the resources!"
echo "Next step:"
echo "  1. Go to Rancher UI -> Go to the downstream cluster -> App&Marketplace -> Charts"
echo "  2. Find and select the Longhorn chart"
echo "  3. Select the chart version corresponding the Longhorn version ${RANCHERAPPTEMPLATEVERSION}"
echo "  4. Install the chart with the correct helm values. Here are the helm values of your old charts: "
printf '%s\n' "${RANCHERAPPVALUES:-$RANCHERAPPANSWERS}"
echo "  5. Verify that the migrated charts are working ok"
echo "  6. Run this script again with the flag --type cleanup to remove the old chart from the legacy UI"
