# Backup

The user can setup a S3 or NFS type backupstore to store the backups of Longhorn volumes.

If the user doesn't have access to AWS S3 or want to give a try first, we've also provided a way to [setup a local S3 testing backupstore](https://github.com/yasker/longhorn/blob/work/docs/backup.md#setup-a-local-testing-backupstore) using [Minio](https://minio.io/).

#### Setup AWS S3 backupstore
1. Create a new bucket in AWS S3.

2. Follow the [guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html#id_users_create_console) to create a new AWS IAM user, with the following permissions set:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "GrantLonghornBackupstoreAccess0",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::<your-bucket-name>",
                "arn:aws:s3:::<your-bucket-name>/*"
            ]
        }
    ]
}
```


3. Create a Kubernetes secret with a name such as `aws-secret` in the namespace where longhorn is placed(`longhorn-system` by default). Put the following keys in the secret:

```
AWS_ACCESS_KEY_ID: <your_aws_access_key_id>
AWS_SECRET_ACCESS_KEY: <your_aws_secret_access_key>
```

4. Go to the Longhorn UI and set `Settings/General/BackupTarget` to
```
s3://<your-bucket-name>@<your-aws-region>/
```
Pay attention that you should have `/` at the end, otherwise you will get an error.

5.  Set `Settings/General/BackupTargetSecret` to
```
aws-secret
```
Your secret name with AWS keys from 3rd point.

#### Setup a local testing backupstore
We provides two testing purpose backupstore based on NFS server and Minio S3 server for testing, in `./deploy/backupstores`.

Use following command to setup a Minio S3 server for BackupStore after `longhorn-system` was created.
```
kubectl create -f https://raw.githubusercontent.com/rancher/longhorn/master/deploy/backupstores/minio-backupstore.yaml
```

Now set `Settings/General/BackupTarget` to
```
s3://backupbucket@us-east-1/backupstore
```
And `Setttings/General/BackupTargetSecret` to
```
minio-secret
```
Click the `Backup` tab in the UI, it should report an empty list without error out.

The `minio-secret` yaml looks like this:
```
apiVersion: v1
kind: Secret
metadata:
  name: minio-secret
  namespace: longhorn-system
type: Opaque
data:
  AWS_ACCESS_KEY_ID: bG9uZ2hvcm4tdGVzdC1hY2Nlc3Mta2V5 # longhorn-test-access-key
  AWS_SECRET_ACCESS_KEY: bG9uZ2hvcm4tdGVzdC1zZWNyZXQta2V5 # longhorn-test-secret-key
  AWS_ENDPOINTS: aHR0cDovL21pbmlvLXNlcnZpY2UuZGVmYXVsdDo5MDAw # http://minio-service.default:9000
```
Notice the secret must be created in the `longhorn-system` namespace for Longhorn to access.
