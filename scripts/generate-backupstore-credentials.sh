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

# MinIO / S3-compatible
: "${AWS_ACCESS_KEY_ID:=}"
: "${AWS_SECRET_ACCESS_KEY:=}"
: "${AWS_ENDPOINTS:=}"
: "${AWS_CERT:=}"
: "${AWS_CERT_KEY:=}"

#########################################

readonly SUPPORTED_BACKENDS=("azurite" "cifs" "minio" "nfs")

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
        minio) generate_minio_backend "$TARGET_DIR" ;;
        nfs) generate_nfs_backend "$TARGET_DIR" ;;
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

generate_minio_backend() {
    local TARGET_DIR=$1

    check_env_or_fail AWS_ACCESS_KEY_ID
    check_env_or_fail AWS_SECRET_ACCESS_KEY
    check_env_or_fail AWS_ENDPOINTS

    if $BASE64_ENCODE; then
        if [[ "$AWS_ENDPOINTS" == https://* ]]; then
            check_env_or_fail AWS_CERT
            check_env_or_fail AWS_CERT_KEY
        fi
    else
        if ! decoded_endpoint=$(echo "$AWS_ENDPOINTS" | base64 --decode 2>/dev/null); then
            echo "ERROR: Failed to decode AWS_ENDPOINTS. Must be valid base64." >&2
            exit 1
        fi

        if [[ "$decoded_endpoint" == https://* ]]; then
            check_env_or_fail AWS_CERT
            check_env_or_fail AWS_CERT_KEY
        fi
    fi

    generate_patch_with_ns longhorn-system minio-secret minio-backupstore-secret \
        AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID" \
        AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY" \
        AWS_ENDPOINTS "$AWS_ENDPOINTS" \
        AWS_CERT "$AWS_CERT" \
        AWS_CERT_KEY "$AWS_CERT_KEY"

    generate_patch_with_ns default minio-secret minio-backupstore-secret \
        AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID" \
        AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY" \
        AWS_ENDPOINTS "$AWS_ENDPOINTS" \
        AWS_CERT "$AWS_CERT" \
        AWS_CERT_KEY "$AWS_CERT_KEY"

    cat <<EOF > "${TARGET_DIR}/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../base/minio
patches:
  - path: minio-backupstore-secret-patch-longhorn-system.yaml
  - path: minio-backupstore-secret-patch-default.yaml
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

is_base64() {
    echo "$1" | base64 --decode >/dev/null 2>&1
}

# Entry point
BACKEND=""
BASE64_ENCODE=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-encode)
            BASE64_ENCODE=false
            ;;
        azurite|cifs|minio|nfs|all)
            BACKEND=$1
            ;;
        *)
            echo "Unknown option or argument: $1"
            echo "Usage: $0 [azurite|cifs|minio|nfs|all] [--no-encode]"
            exit 1
            ;;
    esac
    shift
done

if [[ -z "$BACKEND" ]]; then
    echo "Error: Must specify one of: azurite, cifs, minio, nfs or all"
    echo "Usage: $0 [azurite|cifs|minio|nfs|all] [--no-encode]"
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
