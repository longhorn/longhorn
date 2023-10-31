# OpenShift / OKD Extra Configuration Steps

- [OpenShift / OKD Extra Configuration Steps](#openshift--okd-extra-configuration-steps)
  - [Notes](#notes)
  - [Known Issues](#known-issues)
  - [Preparing Nodes (Optional)](#preparing-nodes-optional)
    - [Default /var/lib/longhorn setup](#default-varliblonghorn-setup)
    - [Separate /var/mnt/longhorn setup](#separate-varmntlonghorn-setup)
      - [Create Filesystem](#create-filesystem)
      - [Mounting Disk On Boot](#mounting-disk-on-boot)
      - [Label and Annotate Nodes](#label-and-annotate-nodes)
  - [Example values.yaml](#example-valuesyaml)
  - [Installation](#installation)
  - [Refs](#refs)

## Notes

Main changes and tasks for OCP are:

- On OCP / OKD, the Operating System is Managed by the Cluster
- OCP Imposes [Security Context Constraints](https://docs.openshift.com/container-platform/4.11/authentication/managing-security-context-constraints.html)
  - This requires everything to run with the least privilege possible. For the moment every component has been given access to run as higher privilege.
  - Something to circle back on is network polices and which components can have their privileges reduced without impacting functionality.
    - The UI probably can be for example.
- openshift/oauth-proxy for authentication to the Longhorn Ui
  - **⚠️** Currently Scoped to Authenticated Users that can delete a longhorn settings object.
    - **⚠️** Since the UI it self is not protected, network policies will need to be created to prevent namespace <--> namespace communication against the pod or service object directly.
    - Anyone with access to the UI Deployment can remove the route restriction. (Namespace Scoped Admin)
- Option to use separate disk in /var/mnt/longhorn & MachineConfig file to mount /var/mnt/longhorn
- Adding finalizers for mount propagation

## Known Issues

- General Feature/Issue Thread
  - [[FEATURE] Deploying Longhorn on OKD/Openshift](https://github.com/longhorn/longhorn/issues/1831)
- 4.10 / 1.23:
  - 4.10.0-0.okd-2022-03-07-131213 to 4.10.0-0.okd-2022-07-09-073606
    - Tested, No Known Issues
- 4.11 / 1.24:
  - 4.11.0-0.okd-2022-07-27-052000 to 4.11.0-0.okd-2022-11-19-050030
    - Tested, No Known Issues
  - 4.11.0-0.okd-2022-12-02-145640, 4.11.0-0.okd-2023-01-14-152430:
    - Workaround: [[BUG] Volumes Stuck in Attach/Detach Loop](https://github.com/longhorn/longhorn/issues/4988)
      - [MachineConfig Patch](https://github.com/longhorn/longhorn/issues/4988#issuecomment-1345676772)
- 4.12 / 1.25:
  - 4.12.0-0.okd-2022-12-05-210624 to 4.12.0-0.okd-2023-01-20-101927
    - Tested, No Known Issues
  - 4.12.0-0.okd-2023-01-21-055900 to 4.12.0-0.okd-2023-02-18-033438:
    - Workaround: [[BUG] Volumes Stuck in Attach/Detach Loop](https://github.com/longhorn/longhorn/issues/4988)
      - [MachineConfig Patch](https://github.com/longhorn/longhorn/issues/4988#issuecomment-1345676772)
  - 4.12.0-0.okd-2023-03-05-022504 - 4.12.0-0.okd-2023-04-16-041331:
    - Tested, No Known Issues
- 4.13 / 1.26:
  - 4.13.0-0.okd-2023-05-03-001308 - 4.13.0-0.okd-2023-08-18-135805:
    - Tested, No Known Issues
- 4.14 / 1.27:
  - 4.14.0-0.okd-2023-08-12-022330 - 4.14.0-0.okd-2023-10-28-073550:
    - Tested, No Known Issues

## Preparing Nodes (Optional)

Only required if you require additional customizations, such as storage-less nodes, or secondary disks.

### Default /var/lib/longhorn setup

Label each node for storage with:

```bash
oc get nodes --no-headers | awk '{print $1}'

export NODE="worker-0"
oc label node "${NODE}" node.longhorn.io/create-default-disk=true
```

### Separate /var/mnt/longhorn setup

#### Create Filesystem

On the storage nodes create a filesystem with the label longhorn:

```bash
oc get nodes --no-headers | awk '{print $1}'

export NODE="worker-0"
oc debug node/${NODE} -t -- chroot /host bash

# Validate Target Drive is Present
lsblk

export DRIVE="sdb" #vdb
sudo mkfs.ext4 -L longhorn /dev/${DRIVE}
```

> ⚠️ Note: If you add New Nodes After the below Machine Config is applied, you will need to also reboot the node.

#### Mounting Disk On Boot

The Secondary Drive needs to be mounted on every boot. Save the Concents and Apply the MachineConfig with `oc apply -f`:

> ⚠️ This will trigger an machine config profile update and reboot all worker nodes on the cluster

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 71-mount-storage-worker
spec:
  config:
    ignition:
      version: 3.2.0
    systemd:
      units:
        - name: var-mnt-longhorn.mount
          enabled: true
          contents: |
            [Unit]
            Before=local-fs.target
            [Mount]
            Where=/var/mnt/longhorn
            What=/dev/disk/by-label/longhorn
            Options=rw,relatime,discard
            [Install]
            WantedBy=local-fs.target
```

#### Label and Annotate Nodes

Label and annotate storage nodes like this:

```bash
oc get nodes --no-headers | awk '{print $1}'

export NODE="worker-0"
oc annotate node ${NODE} --overwrite node.longhorn.io/default-disks-config='[{"path":"/var/mnt/longhorn","allowScheduling":true}]'
oc label node ${NODE} node.longhorn.io/create-default-disk=config
```

## Example values.yaml

Minimum Adjustments Required

```yaml
openshift:
  oauthProxy:
    repository: quay.io/openshift/origin-oauth-proxy
    tag: 4.14  # Use Your OCP/OKD 4.X Version, Current Stable is 4.14

# defaultSettings: # Preparing nodes (Optional)
  # createDefaultDiskLabeledNodes: true

openshift:
  enabled: true
  ui:
    route: "longhorn-ui"
    port: 443
    proxy: 8443
```

## Installation

```bash
# helm template ./chart/ --namespace longhorn-system --values ./chart/values.yaml --no-hooks > longhorn.yaml # Local Testing
helm template longhorn --namespace longhorn-system --values values.yaml --no-hooks  > longhorn.yaml
oc create namespace longhorn-system -o yaml --dry-run=client | oc apply -f -
oc apply -f longhorn.yaml -n longhorn-system
```

## Refs

- <https://docs.openshift.com/container-platform/4.11/storage/persistent_storage/persistent-storage-iscsi.html>
- <https://docs.okd.io/4.11/storage/persistent_storage/persistent-storage-iscsi.html>
- okd 4.5: <https://github.com/longhorn/longhorn/issues/1831#issuecomment-702690613>
- okd 4.6: <https://github.com/longhorn/longhorn/issues/1831#issuecomment-765884631>
- oauth-proxy: <https://github.com/openshift/oauth-proxy/blob/master/contrib/sidecar.yaml>
- <https://github.com/longhorn/longhorn/issues/1831>
