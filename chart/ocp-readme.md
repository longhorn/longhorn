# OpenShift / OKD Extra Configuration Steps

Main changes and tasks for OCP are:

- OCP Imposes [Security Context Constraints](https://docs.openshift.com/container-platform/4.11/authentication/managing-security-context-constraints.html)
  - This requires everything to run with the least privilege possible. For the moment every component has been given access to run as higher privilege.
  - Something to circle back on is network polices and which components can have their privileges reduced without impacting functionality.
    - The UI probably can be for example.
- On OCP / OKD, the Operating System is Managed by the Cluster
- openshift/oauth-proxy for authentication to the Longhorn Ui
  - **⚠️** This provides access to ALL Authenticated users, this should be scoped down if required.
    - TODO: Validate Scope Down
- Option to use separate disk in /var/mnt/longhorn
- Exposing longhorn ui via oauth-proxy
- Adding finalizers for mount propagation
- MachineConfig file to mount /var/mnt/longhorn

## Preparing nodes

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

Minium Adjustments Required

```yaml
openshift:
  oauthProxy:
    repository: quay.io/openshift/origin-oauth-proxy
    tag: latest # Pin to OCP/OKD 4.X Version

defaultSettings:
  createDefaultDiskLabeledNodes: true

openshift:
  enabled: true
  ui:
    route: "longhorn-ui"
    port: 443
    proxy: 8443
  finalizers: true
  privileged: true
```

## Installation

```bash
helm template longhorn --namespace longhorn-system --values values.yaml --no-hooks  > longhorn.yaml
oc create namespace longhorn-system -o yaml --dry-run=client | oc apply -f -
oc apply -f longhorn.yaml -n longhorn-system
```

## REFS

- <https://docs.openshift.com/container-platform/4.11/storage/persistent_storage/persistent-storage-iscsi.html>
- <https://docs.okd.io/4.11/storage/persistent_storage/persistent-storage-iscsi.html>
- okd 4.5: <https://github.com/longhorn/longhorn/issues/1831#issuecomment-702690613>
- okd 4.6: <https://github.com/longhorn/longhorn/issues/1831#issuecomment-765884631>
- oauth-proxy: <https://github.com/openshift/oauth-proxy/blob/master/contrib/sidecar.yaml>
