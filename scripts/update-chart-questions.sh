#!/bin/bash

function die() {
  echo >&2 "$@"
  exit 1
}

function check_yq() {
  if ! command -v yq >/dev/null; then
    die "Missing required program 'yq'."
  fi

  yq --version | grep mikefarah >/dev/null
  if [ $? -ne 0 ]; then
    die "yq exists but it's not the one we need (mikefarah/yq)."
  fi
}

check_yq

while IFS= read -r line; do
  image="$line"
  repo="${image%:*}"
  tag="${image##*:}"
  component="${repo#longhornio/}"

  if [ "$component" = "csi-attacher" ]; then
    key="image.csi.attacher.tag"
  elif [ "$component" = "csi-provisioner" ]; then
    key="image.csi.provisioner.tag"
  elif [ "$component" = "csi-resizer" ]; then
    key="image.csi.resizer.tag"
  elif [ "$component" = "csi-snapshotter" ]; then
    key="image.csi.snapshotter.tag"
  elif [ "$component" = "csi-node-driver-registrar" ]; then
    key="image.csi.nodeDriverRegistrar.tag"
  elif [ "$component" = "livenessprobe" ]; then
    key="image.csi.livenessProbe.tag"
  elif [ "$component" = "backing-image-manager" ]; then
    key="image.longhorn.backingImageManager.tag"
  elif [ "$component" = "longhorn-engine" ]; then
    key="image.longhorn.engine.tag"
  elif [ "$component" = "longhorn-instance-manager" ]; then
    key="image.longhorn.instanceManager.tag"
  elif [ "$component" = "longhorn-manager" ]; then
    key="image.longhorn.manager.tag"
  elif [ "$component" = "longhorn-share-manager" ]; then
    key="image.longhorn.shareManager.tag"
  elif [ "$component" = "longhorn-ui" ]; then
    key="image.longhorn.ui.tag"
  elif [ "$component" = "longhorn-cli" ]; then
    key="image.longhorn.cli.tag"
  elif [ "$component" = "support-bundle-kit" ]; then
    key="image.longhorn.supportBundleKit.tag"
  else
    echo "Component $component is not found in the chart"
    continue
  fi

  yq eval -i ".questions[].subquestions[] |= (select(.variable == \"$key\") | .default = \"$tag\")" chart/questions.yaml

done < "deploy/longhorn-images.txt"
