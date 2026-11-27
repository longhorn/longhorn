#!/usr/bin/env bash
set -euo pipefail

chart_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chart_scratch="$(mktemp -d)"
trap 'rm -rf "$chart_scratch"' EXIT
failed=0

render() {
  helm template longhorn "$chart_root/chart" --namespace longhorn-system --kube-version 1.34.0 "$@"
}

expect_failure() {
  if render "$@" >"$chart_scratch/rejected.yaml" 2>"$chart_scratch/rejected.stderr"; then
    printf 'FAIL: invalid capability values rendered: %s\n' "$*" >&2
    failed=1
  fi
}

for mode in unknown V2-Only '' null 1; do
  expect_failure --set "dataEngineMode=$mode"
done
expect_failure --set dataEngineMode=v2-only
expect_failure --set dataEngineMode=v2-only --set defaultSettings.v1DataEngine=true --set defaultSettings.v2DataEngine=true --set persistence.dataEngine=v2
expect_failure --set dataEngineMode=v2-only --set defaultSettings.v1DataEngine=false --set defaultSettings.v2DataEngine=false --set persistence.dataEngine=v2
expect_failure --set dataEngineMode=v2-only --set defaultSettings.v1DataEngine=false --set defaultSettings.v2DataEngine=true
expect_failure --set dataEngineMode=v2-only --set preUpgradeChecker.jobEnabled=false --set preUpgradeChecker.upgradeVersionCheck=false

render >"$chart_scratch/default.yaml"
render --set dataEngineMode=v1-capable >"$chart_scratch/explicit-default.yaml"
cmp "$chart_scratch/default.yaml" "$chart_scratch/explicit-default.yaml"
if grep -q -- '--data-engine-mode' "$chart_scratch/default.yaml"; then
  printf '%s\n' 'FAIL: default argv changed' >&2
  failed=1
fi
if [[ -n "${CHART_DEFAULT_BASELINE:-}" ]]; then
  cmp "$CHART_DEFAULT_BASELINE" "$chart_scratch/default.yaml"
fi

v2=(--set dataEngineMode=v2-only --set defaultSettings.v1DataEngine=false --set defaultSettings.v2DataEngine=true --set persistence.dataEngine=v2)
render "${v2[@]}" >"$chart_scratch/v2.yaml"
if [[ "$(grep -c -- '--data-engine-mode' "$chart_scratch/v2.yaml" || true)" != 3 ]]; then
  printf '%s\n' 'FAIL: V2 capability must reach daemon, global manager and pre-upgrade' >&2
  failed=1
fi
for launch in daemon global pre-upgrade; do
  if ! awk -v launch="$launch" '
    $0 ~ "^[[:space:]]*-[[:space:]]+" launch "$" { state=1; next }
    state==1 { if ($0 !~ /^[[:space:]]*-[[:space:]]+--data-engine-mode$/) exit 1; state=2; next }
    state==2 { if ($0 !~ /^[[:space:]]*-[[:space:]]+v2-only$/) exit 1; found=1; state=0 }
    END { if (!found) exit 1 }
  ' "$chart_scratch/v2.yaml"; then
    printf 'FAIL: explicit V2 capability missing after %s\n' "$launch" >&2
    failed=1
  fi
done
grep -q 'v1-data-engine: false' "$chart_scratch/v2.yaml"
grep -q 'v2-data-engine: true' "$chart_scratch/v2.yaml"
for counter in false ''; do
  render "${v2[@]}" --set "persistence.disableRevisionCounter=$counter" >"$chart_scratch/counter.yaml"
  if ! grep -q 'dataEngine: "v2"' "$chart_scratch/counter.yaml"; then
    printf '%s\n' 'FAIL: revision-counter choice erased the StorageClass engine' >&2
    failed=1
  fi
done
render "${v2[@]}" --set-string persistence.disableRevisionCounter=false >"$chart_scratch/counter-string.yaml"
grep -q 'dataEngine: "v2"' "$chart_scratch/counter-string.yaml"
render --set dataEngineMode=v2-only --set defaultSettings.v1DataEngine=false --set defaultSettings.v2DataEngine=true --set persistence.createStorageClass=false >"$chart_scratch/external-class.yaml"
if grep -q 'name: longhorn-storageclass' "$chart_scratch/external-class.yaml"; then
  printf '%s\n' 'FAIL: chart claimed an externally owned StorageClass' >&2
  failed=1
fi
render "${v2[@]}" --set preUpgradeChecker.jobEnabled=false >"$chart_scratch/no-hook.yaml"
if [[ "$(grep -c -- '--data-engine-mode' "$chart_scratch/no-hook.yaml" || true)" != 2 ]]; then
  printf '%s\n' 'FAIL: disabling the hook changed manager capability' >&2
  failed=1
fi

if (( failed )); then
  exit 1
fi
printf '%s\n' 'PASS: chart capability validation, native argv, StorageClass intent and default compatibility'
