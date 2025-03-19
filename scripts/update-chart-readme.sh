#!/bin/bash

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

  new_default="\"$tag\""
  escaped_new_default=$(printf '%s' \`"$new_default"\` | sed -e 's/[\/&]/\\&/g')
  escaped_key=$(printf '%s' "$key" | sed 's/\./\\./g')

  # Update the default value in the chart's README.md and save to a temporary file
  sed "s/\(|[ ]*$escaped_key[ ]*|[ ]*string[ ]*|[ ]*\)[^|]*\(|.*\)/\1$escaped_new_default \2/" chart/README.md > chart/README.md.tmp
  mv chart/README.md.tmp chart/README.md
done < "deploy/longhorn-images.txt"