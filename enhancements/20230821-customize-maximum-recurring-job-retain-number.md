# Customize Maximum Recurring Job Retain Number

## Summary

Hardcoding the `MaxRecurringJobRetain` to be 100 may be inadequate in some cases such as that users try to keep 125 backups onn the remote backup target.
This feature will make the `MaxRecurringJobRetain` to be customizable by users.

**NOTE**:

1. Having more snapshots will consume disk storage capacity.
2. The maximum number of snapshots is 250. It will be failed if recurring job start to create a new snapshot after the number of snapshots is up to 250.
3. 1 and 2 might cause volume rebuilding/taking a snapshot/taking a backup unstable.

### Related Issues

- [Longhorn S3 backup retain limit](https://github.com/longhorn/longhorn/discussions/5710)
- [Customize MaxRecurringJobRetain](https://github.com/longhorn/longhorn/issues/5713)
- [Longhorn snapshot space management](https://github.com/longhorn/longhorn/issues/6563)

## Motivation

### Goals

- Add a global setting and users will be able to customize the retain number of a recurring job.

### Non-goals [optional]

- Retain number can exceed 250.

## Proposal

### User Stories

Users can customize the maximum retain number when creating a recurring job to keep more snapshots or backups or restrict resources consumption especially disk storage capacity.

### User Experience In Detail

Users can customize maximum retain number of the recurring job and maximum retain number cannot be exceeded when creating a recurring job. In [Longhorn snapshot space management](https://github.com/longhorn/longhorn/issues/6563) will help users handle the snapshot space management but user sill need to consider the total disk storage capacity as well as the size and number of volumes to determine the retain number.

#### Kubectl

User can set the global setting `recurring-job-max-retention` value to be a customized number under 250.

```txt
kubectl -n longhorn-system edit setting recurring-job-max-retention

--
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  annotations:
    longhorn.io/configmap-resource-version: "6789"
  creationTimestamp: "2023-08-21T00:00:00Z"
  generation: 1
  name: recurring-job-max-retention
  namespace: longhorn-system
  resourceVersion: "87651"
  uid: ab1f01cf-xxxx-45ab-9999-8ca1ebf61xxx
value: "200"
```

#### Helm

User can set `recurringJobMaxRetain` value to be a customized number under 250 such as:

```bash
helm upgrade longhorn longhorn/longhorn --set defaultSettings.recurringJobMaxRetain=200
```

#### Longhorn UI

There is a global setting named `Recurring Job Maximum Retain Number` on the `Setting`/`General` page of UI.
Users can fill out the retain number under 250 and save the setting.

### API changes

`None`

## Design

### Implementation Overview

1. Add the global setting `recurring-job-max-retention` and default value is `100`.
2. The number of global setting `recurring-job-max-retention` cannot be exceeded `250` because of the maximum number of snapshots for a volume.

### Test plan

1. Set the global setting `recurring-job-max-retention` to be 251 and it will fail.
2. Set the global setting `recurring-job-max-retention` to be 50 and it will success.
3. Create a recurring job with retain number 50 and it will success.
4. Create a recurring job with retain number 51 and it will fail.

### Upgrade strategy

`None`
