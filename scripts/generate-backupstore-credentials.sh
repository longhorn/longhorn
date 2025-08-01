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
readonly ALL_TARGET_DIR="deploy/backupstores/overlays/generated-credentials"

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

    # Conditionally required if endpoint is HTTPS
    if $BASE64_ENCODE; then
        # input is plaintext
        if [[ "$AWS_ENDPOINTS" == https://* ]]; then
            check_env_or_fail AWS_CERT
            check_env_or_fail AWS_CERT_KEY
        fi
    else
        # input is base64 encoded
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

# Entry point
BACKEND=""
BASE64_ENCODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base64-encode)
            BASE64_ENCODE=true
            ;;
        azurite|cifs|minio|nfs|all)
            BACKEND=$1
            ;;
        *)
            echo "Unknown option or argument: $1"
            echo "Usage: $0 [azurite|cifs|minio|nfs|all] [--base64-encode]"
            exit 1
            ;;
    esac
    shift
done

if [[ -z "$BACKEND" ]]; then
    echo "Error: Must specify one of: azurite, cifs, minio, nfs or all"
    echo "Usage: $0 [azurite|cifs|minio|nfs|all] [--base64-encode]"
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
