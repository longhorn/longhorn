#!/usr/bin/env bash

set -o errexit
set -o xtrace

PRJ_DIR=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null || realpath "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null)
CHART_DIR="$PRJ_DIR/chart"
DEPLOY_YAML="$PRJ_DIR/deploy/longhorn.yaml"
DEPLOY_YAML_TMP="$PRJ_DIR/deploy/longhorn.yaml.tmp"
NAMESPACE=${NAMESPACE:-longhorn-system}

if ! command -v helm &> /dev/null || ! helm version --short | grep -q "v3"; then
  echo "Please install helm v3 first before generating $DEPLOY_YAML!"
  exit 1
fi

cat <<EOD > "$DEPLOY_YAML"
---
# Builtin: "helm template" does not respect --create-namespace
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
EOD

helm template longhorn "$CHART_DIR" --namespace "$NAMESPACE" --create-namespace --no-hooks >>"$DEPLOY_YAML"
< "$DEPLOY_YAML" grep -v 'helm.sh\|app.kubernetes.io/managed-by: Helm' | grep -v "helm.sh/chart:" > "$DEPLOY_YAML_TMP"
mv "$DEPLOY_YAML_TMP" "$DEPLOY_YAML"


