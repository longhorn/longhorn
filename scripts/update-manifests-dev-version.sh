#!/usr/bin/env bash

# Example:
#   ./scripts/update-manifests-dev-version.sh 1.3.0 1.4.0
#
# Result:
#   - Chart version will be updated to 1.4.0-dev
#   - Images (manager, engine, ui) will be updated to master-head

set -o errexit
set -o nounset

PRJ_DIR=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null || realpath "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null)
CURRENT_VERSION=${CURRENT_VERSION:-$1}
NEW_VERSION=${NEW_VERSION:-$2}-dev

mapfile -t manifests < <(find "$PRJ_DIR" -type f -a \( -name '*.yaml' -o -name 'longhorn-images.txt' \))

if [[ ${#manifests[@]} -le 0 ]]; then
  echo "No manifests found to update from $PRJ_DIR" >/dev/stderr
  exit 1
fi

echo "Updating $CURRENT_VERSION -> $NEW_VERSION-dev with master-head images in below manifests"
for f in "${manifests[@]}"; do
  f_name=$(basename "$f")

  if [[ $f_name == "Chart.yaml" ]]; then
    sed -i "s#\(version: \)${CURRENT_VERSION}#\1${NEW_VERSION}#g" "$f"
    sed -i "s#\(appVersion: v\)${CURRENT_VERSION}#\1${NEW_VERSION}#g" "$f"
  else
    sed -i "s#\(:\s*\)v${CURRENT_VERSION}#\1master-head#g" "$f"
  fi

  echo "$f updated"
done

. "$PRJ_DIR"/scripts/generate-longhorn-yaml.sh