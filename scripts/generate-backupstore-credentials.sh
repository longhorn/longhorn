#!/bin/bash
set -euo pipefail

#########################################
# Credential Configuration
#########################################

# Azurite / AzBlob
: "${AZBLOB_ACCOUNT_NAME:=}"
: "${AZBLOB_ACCOUNT_KEY:=}"
: "${AZBLOB_ENDPOINT:=}"

# CIFS
: "${CIFS_USERNAME:=}"
: "${CIFS_PASSWORD:=}"

# RustFS / S3-compatible
: "${AWS_ACCESS_KEY_ID:=}"
: "${AWS_SECRET_ACCESS_KEY:=}"
: "${AWS_ENDPOINTS:=}"
: "${AWS_CERT:=}"
: "${AWS_CERT_KEY:=}"

#########################################

readonly SUPPORTED_BACKENDS=("azurite" "cifs" "nfs" "rustfs")

# Always work relative to the repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ALL_TARGET_DIR="${PROJECT_ROOT}/deploy/backupstores/overlays/generated-credentials"


check_env_or_fail() {
    local var_name="$1"
    if [[ -z "${!var_name:-}" ]]; then
        echo "ERROR: Environment variable '$var_name' is not set or empty." >&2
        exit 1
    fi
}

generate_all_overlay() {
    local ALL_DIR="${ALL_TARGET_DIR}/all"
    rm -rf "${ALL_DIR:?}" && mkdir -p "${ALL_DIR}"

    {
        echo "apiVersion: kustomize.config.k8s.io/v1beta1"
        echo "kind: Kustomization"
        echo ""
        echo "resources:"
        for backend in "${SUPPORTED_BACKENDS[@]}"; do
            echo "  - ../${backend}"
        done
    } > "${ALL_DIR}/kustomization.yaml"

    echo "Unified overlay generated at: ${ALL_DIR}"
}

generate_backend() {
    local backend=$1
    TARGET_DIR="${ALL_TARGET_DIR}/${backend}"
    rm -rf "${TARGET_DIR:?}" && mkdir -p "${TARGET_DIR}"

    case "$backend" in
        azurite) generate_azurite_backend "$TARGET_DIR" ;;
        cifs) generate_cifs_backend "$TARGET_DIR" ;;
        nfs) generate_nfs_backend "$TARGET_DIR" ;;
        rustfs) generate_rustfs_backend "$TARGET_DIR" ;;
        *)
            echo "Unsupported backend: $backend"
            exit 1
            ;;
    esac

    echo "Credentials for $backend generated at: ${TARGET_DIR}"
}

generate_azurite_backend() {
    local TARGET_DIR=$1

    check_env_or_fail AZBLOB_ACCOUNT_NAME
    check_env_or_fail AZBLOB_ACCOUNT_KEY
    check_env_or_fail AZBLOB_ENDPOINT

    generate_patch_with_ns longhorn-system azblob-secret azurite-backupstore-secret \
        AZBLOB_ACCOUNT_NAME "$AZBLOB_ACCOUNT_NAME" \
        AZBLOB_ACCOUNT_KEY "$AZBLOB_ACCOUNT_KEY" \
        AZBLOB_ENDPOINT "$AZBLOB_ENDPOINT"

    cat <<EOF > "${TARGET_DIR}/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../base/azurite
patches:
  - path: azurite-backupstore-secret-patch-longhorn-system.yaml
EOF
}

generate_cifs_backend() {
    local TARGET_DIR=$1

    check_env_or_fail CIFS_USERNAME
    check_env_or_fail CIFS_PASSWORD

    generate_patch_with_ns longhorn-system cifs-secret cifs-backupstore-secret \
        CIFS_USERNAME "$CIFS_USERNAME" \
        CIFS_PASSWORD "$CIFS_PASSWORD"

    generate_patch_with_ns default cifs-secret cifs-backupstore-secret \
        CIFS_USERNAME "$CIFS_USERNAME" \
        CIFS_PASSWORD "$CIFS_PASSWORD"

    cat <<EOF > "${TARGET_DIR}/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../base/cifs
patches:
  - path: cifs-backupstore-secret-patch-longhorn-system.yaml
  - path: cifs-backupstore-secret-patch-default.yaml
EOF
}

generate_rustfs_backend() {
    local TARGET_DIR=$1

    check_env_or_fail AWS_ACCESS_KEY_ID
    check_env_or_fail AWS_SECRET_ACCESS_KEY
    check_env_or_fail AWS_ENDPOINTS

    local endpoint="$AWS_ENDPOINTS"
    if ! $BASE64_ENCODE; then
        if ! endpoint=$(echo "$AWS_ENDPOINTS" | base64 --decode 2>/dev/null); then
            echo "ERROR: Failed to decode AWS_ENDPOINTS. Must be valid base64." >&2
            exit 1
        fi
    fi

    local tls_enabled=false
    local secret_data=(
        AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
        AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
        AWS_ENDPOINTS "$AWS_ENDPOINTS"
    )
    if [[ "$endpoint" == https://* ]]; then
        tls_enabled=true
        check_env_or_fail AWS_CERT
        check_env_or_fail AWS_CERT_KEY
        secret_data+=(AWS_CERT "$AWS_CERT" AWS_CERT_KEY "$AWS_CERT_KEY")
    fi

    generate_patch_with_ns longhorn-system rustfs-secret rustfs-backupstore-secret "${secret_data[@]}"
    generate_patch_with_ns default rustfs-secret rustfs-backupstore-secret "${secret_data[@]}"

    cat <<EOF > "${TARGET_DIR}/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../base/rustfs
patches:
  - path: rustfs-backupstore-secret-patch-longhorn-system.yaml
  - path: rustfs-backupstore-secret-patch-default.yaml
EOF

    if $tls_enabled; then
        generate_rustfs_tls_patch "$TARGET_DIR"
        echo "  - path: rustfs-backupstore-tls-patch.yaml" >> "${TARGET_DIR}/kustomization.yaml"
    fi
}

# RustFS serves plain HTTP unless RUSTFS_TLS_PATH points at a directory
# holding rustfs_cert.pem and rustfs_key.pem.
generate_rustfs_tls_patch() {
    local TARGET_DIR=$1

    cat <<EOF > "${TARGET_DIR}/rustfs-backupstore-tls-patch.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: longhorn-test-rustfs
  namespace: default
spec:
  template:
    spec:
      volumes:
      - name: rustfs-certificates
        secret:
          secretName: rustfs-secret
          items:
          - key: AWS_CERT
            path: rustfs_cert.pem
          - key: AWS_CERT_KEY
            path: rustfs_key.pem
      containers:
      - name: rustfs
        env:
        - name: RUSTFS_TLS_PATH
          value: "/opt/tls"
        readinessProbe:
          httpGet:
            scheme: HTTPS
        volumeMounts:
        - name: rustfs-certificates
          mountPath: "/opt/tls"
          readOnly: true
EOF
}

generate_nfs_backend() {
    local TARGET_DIR=$1

    cat <<EOF > "${TARGET_DIR}/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../../base/nfs
EOF
}

generate_patch_with_ns() {
    local ns=$1
    local name=$2
    local file=$3
    shift 3

    {
        echo "apiVersion: v1"
        echo "kind: Secret"
        echo "metadata:"
        echo "  name: $name"
        echo "  namespace: $ns"
        echo "type: Opaque"
        echo "data:"
        while [[ $# -gt 1 ]]; do
            key=$1
            val=$2
            fail_if_base64_encoded "$key" "$val"
            echo "  $key: $(b64 "$val")"
            shift 2
        done
    } > "${TARGET_DIR}/${file}-patch-${ns}.yaml"
}


b64() {
    if $BASE64_ENCODE; then
        echo -n "$1" | base64 | tr -d '\n'
    else
        echo -n "$1"
    fi
}

fail_if_base64_encoded() {
    local key="$1"
    local val="$2"

    if $BASE64_ENCODE && is_base64 "$val"; then
        echo "ERROR: Input for $key appears to be already base64-encoded. Refusing to double-encode." >&2
        echo "Hint: Use --no-encode if your input is already base64." >&2
        exit 1
    fi
}

# Decoding alone is not a reliable test: BSD/macOS base64 silently skips
# characters outside the alphabet, so plaintext would look encoded.
is_base64() {
    local val="$1"

    [[ -n "$val" ]] || return 1
    [[ "$val" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
    (( ${#val} % 4 == 0 )) || return 1

    printf '%s' "$val" | base64 --decode >/dev/null 2>&1 || return 1

    # Plaintext like AWS access key IDs is valid base64 too, but decodes to binary.
    local non_printable
    non_printable=$(printf '%s' "$val" | base64 --decode 2>/dev/null | LC_ALL=C tr -d '[:print:][:space:]' | wc -c)
    (( non_printable == 0 ))
}

# Entry point
BACKEND=""
BASE64_ENCODE=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-encode)
            BASE64_ENCODE=false
            ;;
        azurite|cifs|nfs|rustfs|all)
            BACKEND=$1
            ;;
        *)
            echo "Unknown option or argument: $1"
            echo "Usage: $0 [azurite|cifs|nfs|rustfs|all] [--no-encode]"
            exit 1
            ;;
    esac
    shift
done

if [[ -z "$BACKEND" ]]; then
    echo "Error: Must specify one of: azurite, cifs, nfs, rustfs or all"
    echo "Usage: $0 [azurite|cifs|nfs|rustfs|all] [--no-encode]"
    exit 1
fi

if $BASE64_ENCODE; then
    echo "Base64 encoding: enabled"
else
    echo "Base64 encoding: disabled"
fi

if [[ "$BACKEND" == "all" ]]; then
    for backend in "${SUPPORTED_BACKENDS[@]}"; do
        generate_backend "$backend"
    done
    generate_all_overlay
else
    generate_backend "$BACKEND"
fi
