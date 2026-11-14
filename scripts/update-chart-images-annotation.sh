#!/usr/bin/env bash
# Regenerate the HIP-0015 "helm.sh/images" annotation in chart/Chart.yaml from chart/values.yaml.
set -o errexit
set -o nounset
set -o pipefail

PRJ_DIR=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null || realpath "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null)
CHART_YAML="$PRJ_DIR/chart/Chart.yaml"
VALUES_YAML="$PRJ_DIR/chart/values.yaml"

if ! command -v yq >/dev/null || ! yq --version | grep -q mikefarah; then
  echo "Missing required program 'yq' (mikefarah/yq)." >&2
  exit 1
fi

IMAGES=$(yq '[(.image.longhorn, .image.csi) | .[] | {"name": (.repository | sub("^.*/"; "")), "image": .repository + ":" + .tag}]' "$VALUES_YAML")
export IMAGES

yq -i '.annotations."helm.sh/images" = strenv(IMAGES) | .annotations."helm.sh/images" style="literal"' "$CHART_YAML"
