#!/bin/bash

export RED='\x1b[0;31m'
export NO_COLOR='\x1b[0m'

usage () {
   echo "USAGE: $0 --aws-access-key <your_aws_access_key>  \ "
   echo "          --aws-secret-access-key <your_aws_secret_access_key> \ "
   echo "          --backup-url s3://backupbucket@ap-northeast-1/backupstore?backup=<backup_name>&volume=<volume_name> \ "
   echo "          --output-file volume.raw \ "
   echo "          --output-format raw \ "
   echo "          --version <longhorn_version>"
   echo "          --backing-file <backing_file_path>"
   echo "Restore a Longhorn backup to a raw image or a qcow2 image."
   echo ""
   echo "  -u, --backup-url             (Required) Backups S3/NFS URL. e.g., s3://backupbucket@us-east-1/backupstore?backup=backup-bd326da2c4414b02&volume=volumeexamplename"
   echo "  -o, --output-file            (Required) Output file, e.g., /tmp/restore/volume.raw"
   echo "  -f, --output-format          (Required) Output file format, e.g., raw or qcow2"
   echo "  -v, --version                (Required) Longhorn version, e.g., v1.3.2"
   echo "      --aws-access-key         (Optional) AWS credentials access key"
   echo "      --aws-secret-access-key  (Optional) AWS credentials access secret key"
   echo "      --cifs-username          (Optional) CIFS credentials username"
   echo "      --cifs-password          (Optional) CIFS credentials password"
   echo "  -b, --backing-file           (Optional) backing image. e.g., /tmp/backingfile.qcow2"
   echo "  -h, --help                   Usage message"
}

error_invalid_params() {
  echo -e "${RED}[ERROR]Invalid params. Check the required params.${NO_COLOR}"
  usage
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  key="$1"
  case $key in
    --aws-access-key)
    aws_access_key="$2"
    shift # past argument
    shift # past value
    ;;
    --aws-secret-access-key)
    aws_secret_access_key="$2"
    shift # past argument
    shift # past value
    ;;
    --cifs-username)
    cifs_username="$2"
    shift # past argument
    shift # past value
    ;;
    --cifs-password)
    cifs_password="$2"
    shift # past argument
    shift # past value
    ;;
    -u|--backup-url)
    backup_url="$2"
    shift # past argument
    shift # past value
    ;;
    -o|--output-file)
    output_file="$2"
    shift # past argument
    shift # past value
    ;;
    -f|--output-format)
    output_format="$2"
    shift # past argument
    shift # past value
    ;;
    -b|--backing-file)
    backing_file="$2"
    shift # past argument
    shift # past value
    ;;
    -v|--version)
    version="$2"
    shift # past argument
    shift # past value
    ;;
    -h|--help)
    usage
    exit 0
    shift
    ;;
    *)
    error_invalid_params
    ;;
    esac
done

# Check the required parameters exits
if [ -z "${backup_url}" ] || [ -z "${output_file}" ] || [ -z "${output_format}" ] || [ -z "${version}" ]; then
      error_invalid_params
fi
if [[ "${backup_url}" =~ ^[Ss]3 ]]; then
  if [ -z "${aws_access_key}" ] || [ -z "${aws_secret_access_key}" ]; then
      error_invalid_params
  fi
fi

# Compose the docker arguments
if [[ "${backup_url}" =~ ^[Ss]3 ]]; then
  CUSTOMIZED_ARGS="-e AWS_ACCESS_KEY_ID="${aws_access_key}" -e AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}" "
else
  CUSTOMIZED_ARGS="--cap-add SYS_ADMIN --security-opt apparmor:unconfined --cap-add DAC_READ_SEARCH"
fi
if [[ "${backup_url}" =~ ^cifs ]]; then
  CUSTOMIZED_ARGS+=" -e CIFS_USERNAME=${cifs_username} -e CIFS_PASSWORD=${cifs_password} "
fi

# Start restoring a backup to an image file. 
docker run ${CUSTOMIZED_ARGS} -v /tmp/restore:/tmp/restore \
            longhornio/longhorn-engine:"${version}" longhorn backup \
            restore-to-file ""${backup_url}"" \
            --output-file "/tmp/restore/${output_file}" \
            --output-format "${output_format}" \
            --backing-file "${backing_file}"