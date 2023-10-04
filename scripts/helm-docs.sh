#!/bin/bash
## Reference: https://github.com/norwoodj/helm-docs

set -o errexit
set -o xtrace

PRJ_DIR=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null || realpath "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null)
CHART_DIR="$PRJ_DIR/chart"
echo "$CHART_DIR"

echo "Running Helm-Docs"
sudo docker run \
    -v "$CHART_DIR:/helm-docs" \
    -u $(id -u) \
    jnorwood/helm-docs:v1.9.1
