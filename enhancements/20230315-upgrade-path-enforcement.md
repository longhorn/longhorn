# Upgrade Path Enforcement

## Summary

Currently, Longhorn does not enforce the upgrade path, even though we claim Longhorn only supports upgrading from the previous stable release, for example, upgrading to 1.5.x is only supported from 1.4.x or 1.5.0.

Without upgrade enforcement, we will allow users to upgrade from any previous version. This will cause extra testing efforts to cover all upgrade paths. Additionally, the goal of this enhancement is to support rollback after upgrade failure and prevent downgrades.

### Related Issues

https://github.com/longhorn/longhorn/issues/5131

## Motivation

### Goals

- Enforce an upgrade path to prevent users from upgrading from any unsupported version. After rejecting the user's upgrade attempt, the user's Longhorn setup should remain intact without any impacts.
- Upgrade Longhorn from the authorized versions to a major release version.
- Support rollback the failed upgrade to the previous version.
- Prevent unexpected downgrade.

### Non-goals

- Automatic rollback if the upgrade failed.

## Proposal

- When upgrading with `kubectl`, it will check the upgrade path at entry point of the pods for `longhorn-manager`, `longhorn-admission-webhook`, `longhorn-conversion-webhook` and `longhorn-recovery-backend`.
- When upgrading with `Helm` or as a `Rancher App Marketplace`, it will check the upgrade path by a `pre-upgrade` job of `Helm hook`

### User Stories

- As the admin, I want to upgrade Longhorn from x.y.* or x.(y+1).0 to x.(y+1).* by `kubectl`, `Helm` or `Rancher App Marketplace`, so that the upgrade should succeed.
- As the admin, I want to upgrade Longhorn from the previous authorized versions to a new major/minor version by `kubectl`, `Helm`, or `Rancher App Marketplace`, so that the upgrade should succeed.
- As the admin, I want to upgrade Longhorn from x.(y-1).* to x.(y+1).* by 'kubectl', 'Helm' or 'Rancher App Marketplace', so that the upgrade should be prevented and the system with the current version continues running w/o any interruptions.
- As the admin, I want to roll back Longhorn from the failed upgrade to the previous install by `kubectl`, `Helm`, or `Rancher App Marketplace`, so that the rollback should succeed.
- As the admin, I want to downgrade Longhorn to any lower version by `kubectl`, `Helm`, or `Rancher App Marketplace`, so that the downgrade should be prevented and the system with the current version continues running w/o any interruptions.

### User Experience In Detail

#### Upgrade Longhorn From x.y.* or x.(y+1).0 To x.(y+1).*

##### Upgrade With `kubectl`

1. Install Longhorn on any Kubernetes cluster by using this command:

   ```shell
   kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/vx.y.*/deploy/longhorn.yaml
   ```
   or
   ```shell
   kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/vx.(y+1).0/deploy/longhorn.yaml
   ```

1. After Longhorn works normally, upgrade Longhorn by using this command:

    ```shell
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/vx.(y+1).*/deploy/longhorn.yaml
    ```

1. It will be allowed and Longhorn will be upgraded successfully.

##### Upgrade With `Helm` Or `Rancher App Marketplace`

1. Install Longhorn x.y.* or x.(y+1).0 with Helm as [Longhorn Install with Helm document](https://longhorn.io/docs/1.4.1/deploy/install/install-with-helm/) or install Longhorn x.y.* or x.(y+1).0 with a Rancher Apps as [Longhorn Install as a Rancher Apps & Marketplace document](https://longhorn.io/docs/1.4.1/deploy/install/install-with-rancher/)
1. Upgrade to Longhorn x.(y+1).* with Helm as [Longhorn Upgrade with Helm document](https://longhorn.io/docs/1.4.1/deploy/upgrade/longhorn-manager/#upgrade-with-helm) or upgrade to Longhorn x.(y+1).* with a Rancher Catalog App as [Longhorn Upgrade as a Rancher Apps & Marketplace document](https://longhorn.io/docs/1.4.1/deploy/upgrade/longhorn-manager/#upgrade-as-a-rancher-catalog-app)
1. It will be allowed and Longhorn will be upgraded successfully.

#### Upgrade Longhorn From The Authorized Versions To A Major Release Version

##### Upgrade With `kubectl`

1. Install Longhorn on any Kubernetes cluster by using this command:

   ```shell
   kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/vx.y.*/deploy/longhorn.yaml
   ```

1. After Longhorn works normally, upgrade Longhorn by using this command:

    ```shell
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v(x+1).0.*/deploy/longhorn.yaml
    ```

1. It will be allowed and Longhorn will be upgraded successfully.

##### Upgrade With `Helm` Or `Rancher App Marketplace`

1. Install Longhorn x.y.* with Helm such as [Longhorn Install with Helm document](https://longhorn.io/docs/1.4.1/deploy/install/install-with-helm/) or install Longhorn x.y.* with a Rancher Apps as [Longhorn Install as a Rancher Apps & Marketplace document](https://longhorn.io/docs/1.4.1/deploy/install/install-with-rancher/)
1. Upgrade to Longhorn (x+1).0.* with Helm as [Longhorn Upgrade with Helm document](https://longhorn.io/docs/1.4.1/deploy/upgrade/longhorn-manager/#upgrade-with-helm) or upgrade to Longhorn (x+1).0.* with a Rancher Catalog App as [Longhorn Upgrade as a Rancher Apps & Marketplace document](https://longhorn.io/docs/1.4.1/deploy/upgrade/longhorn-manager/#upgrade-as-a-rancher-catalog-app)
1. It will be allowed and Longhorn will be upgraded successfully.

#### Upgrade Longhorn From x.(y-1).* To x.(y+1).*

##### Upgrade With `kubectl`

1. Install Longhorn on any Kubernetes cluster by using this command:

    ```shell
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/vx.(y-1).*/deploy/longhorn.yaml
    ```

1. After Longhorn works normally, upgrade Longhorn by using this command:

    ```shell
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/vx.(y+1).*/deploy/longhorn.yaml
    ```

1. It will be not allowed and Longhorn will block the upgrade for `longhorn-manager`, `longhorn-admission-webhook`, `longhorn-conversion-webhook` and `longhorn-recovery-backend`.
1. Users need to roll back Longhorn manually to restart `longhorn-manager` pods.

##### Upgrade With `Helm` Or `Rancher App Marketplace`

1. Install Longhorn x.(y-1).* with Helm as [Longhorn Install with Helm document](https://longhorn.io/docs/1.4.1/deploy/install/install-with-helm/) or install Longhorn x.(y-1).* with a Rancher Apps as [Longhorn Install as a Rancher Apps & Marketplace document](https://longhorn.io/docs/1.4.1/deploy/install/install-with-rancher/)
1. Upgrade to Longhorn x.(y+1).* with Helm as [Longhorn Upgrade with Helm document](https://longhorn.io/docs/1.4.1/deploy/upgrade/longhorn-manager/#upgrade-with-helm) or upgrade to Longhorn x.(y+1).* with a Rancher Catalog App as [Longhorn Upgrade as a Rancher Apps & Marketplace document](https://longhorn.io/docs/1.4.1/deploy/upgrade/longhorn-manager/#upgrade-as-a-rancher-catalog-app)
1. It will not be allowed and a `pre-upgrade`job of `Helm hook` failed makes the whole helm upgrading process failed.
1. Longhorn is intact and continues serving.

#### Roll Back Longhorn From The Failed Upgrade To The Previous Install

##### Roll Back With `kubectl`

1. Users need to recover Longhorn by using this command again:

   ```shell
   kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/[previous installed version]/deploy/longhorn.yaml
   ```

1. Longhorn will be rolled back successfully.
1. And users might need to delete new components introduced by new version Longhorn manually.

##### Roll Back With `Helm` Or `Rancher App Marketplace`

1. Users need to recover Longhorn with `Helm` by using commands:

    ```shell
    helm history longhorn # to get previous installed Longhorn REVISION
    helm rollback longhorn [REVISION]
    ```
    or
    ```shell
    helm upgrade longhorn longhorn/longhorn --namespace longhorn-system --version [previous installed version]
    ```

1. Users need to recover Longhorn with `Rancher Catalog Apps` by upgrading the previous installed Longhorn version at `Rancher App Marketplace` again.
1. Longhorn will be rolled back successfully.

##### Manually Cleanup Example

When users try to upgrade Longhorn from v1.3.x to v1.5.x, a new deployment `longhorn-recovery-backend` will be introduced and the upgrade will fail.
Users need to delete the deployment `longhorn-recovery-backend` manually after rolling back Longhorn

#### Downgrade Longhorn To Any Lower Version

##### Downgrade With `kubectl`

1. Install Longhorn on any Kubernetes cluster by using this command:

    ```shell
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/vx.y.*/deploy/longhorn.yaml
    ```

1. After Longhorn works normally, upgrade Longhorn by using this command:

    ```shell
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/vx.(y-z).*/deploy/longhorn.yaml
    ```

1. It will be not allowed and Longhorn will block the downgrade for `longhorn-manager`. [or `longhorn-admission-webhook`, `longhorn-conversion-webhook` and `longhorn-recovery-backend` if downgrading version had these components]
1. Users need to roll back Longhorn manually to restart `longhorn-manager` pods.

##### Downgrade With `Helm` Or `Rancher App Marketplace`

1. Install Longhorn x.y.* with Helm as [Longhorn Install with Helm document](https://longhorn.io/docs/1.4.1/deploy/install/install-with-helm/) or install Longhorn x.y.* with a Rancher Apps as [Longhorn Install as a Rancher Apps & Marketplace document](https://longhorn.io/docs/1.4.1/deploy/install/install-with-rancher/)
1. Downgrade to Longhorn (x-z).y.* or x.(y-z).* with Helm as [Longhorn Upgrade with Helm document](https://longhorn.io/docs/1.4.1/deploy/upgrade/longhorn-manager/#upgrade-with-helm) or downgrade to Longhorn (x-z).y.* or x.(y-z).* with a Rancher Catalog App as [Longhorn Upgrade as a Rancher Apps & Marketplace document](https://longhorn.io/docs/1.4.1/deploy/upgrade/longhorn-manager/#upgrade-as-a-rancher-catalog-app)
1. It will not be allowed and a `pre-upgrade`job of `Helm hook` failed makes the whole helm downgrading process failed.
1. Longhorn is intact and continues serving.

### API changes

`None`

## Design

### Implementation Overview

#### Blocking Upgrade With `kubectl`

Check the upgrade path is supported or not at entry point of the `longhorn-manager`, `longhorn-admission-webhook`, `longhorn-conversion-webhook` and `longhorn-recovery-backend`

1. Get Longhorn current version `currentVersion` by the function `GetCurrentLonghornVersion`
1. Get Longhorn upgrading version `upgradeVersion` from `meta.Version`
1. Compare currentVersion and upgradeVersion, only allow authorized version upgrade (e.g., 1.3.x to 1.5.x is not allowed) as following table.

  |  currentVersion |  upgradeVersion |  Allow |
  |    :-:      |    :-:      |   :-:  |
  |  x.y.*      |  x.(y+1).*  |   ✓    |
  |  x.y.0      |  x.y.*      |   ✓    |
  |  x.y.*      |  (x+1).y.*  |   ✓    |
  |  x.(y-1).*  |  x.(y+1).*  |   X    |
  |  x.(y-2).*  |  x.(y+1).*  |   X    |
  |  x.y.*      |  x.(y-1).*  |   X    |
  |  x.y.*      |  x.y.(*-1)  |   X    |

1. Downgrade is not allowed.
2. When the upgrade path is not supported, new created pods of the `longhorn-manager`, `longhorn-admission-webhook`, `longhorn-conversion-webhook` and `longhorn-recovery-backend` will show logs and broadcast events for the upgrade path is not supported and return errors.
3. Previous installed Longhorn will work normally still.

#### Blocking Upgrade With `Helm` Or `Rancher App Marketplace`

1. Add a new job for pre-upgrade hook of `Helm` as the [`post-upgrade` job](https://github.com/longhorn/longhorn/blob/master/chart/templates/postupgrade-job.yaml).

```txt
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-delete-policy": hook-succeeded,before-hook-creation,hook-failed
  name: longhorn-pre-upgrade
  ...
spec:
  ...
  template:
    metadata:
      name: longhorn-pre-upgrade
      ...
    spec:
      containers:
      - name: longhorn-post-upgrade
        ...
        command:
        - longhorn-manager
        - pre-upgrade
        env:
        ...
```

1. When upgrading starts, the `pre-upgrade` job will start to run firstly and it will be failed if the upgrade path is not supported then `Helm` upgrading process will be failed.

### Test plan

#### Test Supported Upgrade Path

1. Install Longhorn v1.4.x.
1. Wait for all pods ready.
1. Create a Volume and write some data.
1. Upgrade to Longhorn v1.5.0.
1. Wait for all pods upgraded successfully.
1. Check if data is not corrupted.

#### Test Unsupported Upgrade Path

1. Install Longhorn v1.3.x.
1. Wait for all pods ready.
1. Create a Volume and write some data.
1. Upgrade to Longhorn v1.5.0.
1. Upgrading process will be stuck or failed.
1. Check if data is not corrupted.
1. Rollback to Longhorn v1.3.x with the same setting.
1. Longhorn v1.3.x will work normally.

### Upgrade strategy

`None`

## Note

`None`
