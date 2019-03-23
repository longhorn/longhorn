# Use command restore-to-file
This command gives users the ability to restore a backup to a `raw` image or a `qcow2` image. If the backup is based on a backing file, users should provide the backing file as a `qcow2` image with `--backing file` parameter.

## Instruction
1. Copy the yaml template

    1.1 Volume has no base image: Make a copy of `examples/restore_to_file.yaml.template` as e.g. `restore.yaml`.
    
    1.2 Volume has a base image: Make a copy of `examples/restore_to_file_with_backing_file.yaml.template` as e.g. `restore.yaml`, and set argument `backing-file` by replacing `<BASE_IMAGE>` with your base image, e.g. `rancher/longhorn-test:baseimage-ext4`.
    
2. Set the node which the output file should be placed on by replacing `<NODE_NAME>`, e.g. `node1`.

3. Specify the host path of output file by modifying field `hostpath` of volume `disk-directory`. By default the directory is `/tmp/restore/`.

4. Set the first argument (backup url) by replacing `<BACKUP_URL>`, e.g. `s3://backupbucket@us-east-1/backupstore?backup=backup-bd326da2c4414b02&volume=volumeexamplename`. Do not delete `''`.

5. Set argument `output-file` by replacing `<OUTPUT_FILE>`, e.g. `volume.raw` or `volume.qcow2`.

6. Set argument `output-format` by replacing `<OUTPUT_FORMAT>`. Now support `raw` or `qcow2` only.

7. Set S3 Credential Secret by replacing `<S3_SECRET_NAME>`, e.g. `minio-secret`. 

8. Execute the yaml using e.g. `kubectl create -f restore.yaml`.

9. Watching the result using `kubectl -n longhorn-system get pod restore-to-file -w`

After the pod status changed to `Completed`, you should able to find `<OUTPUT_FILE>` at e.g. `/tmp/restore` on the `<NODE_NAME>`.
