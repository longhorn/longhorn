# OpenShift Usage

This setup has been tested with OCP 4.6 and 4.7, and is based on these previous discussions:
- okd 4.5: https://github.com/longhorn/longhorn/issues/1831#issuecomment-702690613
- okd 4.6: https://github.com/longhorn/longhorn/issues/1831#issuecomment-765884631
- oauth-proxy: https://github.com/openshift/oauth-proxy/blob/master/contrib/sidecar.yaml

Main changes and tasks for OCP are:
- security setup for namespace longhorn-system
- option to use separate disk in /var/mnt/longhorn
- exposing longhorn ui via oauth-proxy
- adding finalizers for mount propagation
- machineconfig file to start iscsid
- mahcineconfig file to mount /var/mnt/longhorn

## Preparing nodes

### Setup selinux and iscsid

Run `oc apply -f` using yaml like this (example is for worker nodes):
```
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 51-set-longhorn-worker
  labels:
    #{{- include "project.labels" . | nindent 4 }}
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.1.0
    systemd:
      units:
        - contents: |
            [Unit]
            Description=Set SELinux chcon for longhorn
            Before=kubelet.service

            [Service]
            Type=oneshot
            RemainAfterExit=true
            ExecStartPre=/usr/bin/mkdir -p  /var/lib/kubelet/obsoleted-longhorn-plugins /var/lib/longhorn /var/mnt/longhorn
            ExecStart=-/usr/bin/chcon -Rt container_file_t /var/lib/kubelet/obsoleted-longhorn-plugins
            ExecStart=-/usr/bin/chcon -Rt container_file_t /var/lib/longhorn
            ExecStart=-/usr/bin/chcon -Rt container_file_t /var/mnt/longhorn

            [Install]
            WantedBy=multi-user.target
          enabled: true
          name: longhorn-provisioner.service
        - name: iscsid.service
          enabled: true
          state: "started"
```

### Default /var/lib/longhorn setup

Label each node for storage with:
```
oc label node work0 node.longhorn.io/create-default-disk=true
```

### Separate /var/mnt/longhorn setup

- Create filesystem with label longhorn on storage node like:
  ```
  sudo mkfs.ext4 -L longhorn /dev/sdb
  ```
- Apply with `oc apply -f` machineconfig file like this to mount it on boot:
  ```
  apiVersion: machineconfiguration.openshift.io/v1
  kind: MachineConfig
  metadata:
    labels:
      machineconfiguration.openshift.io/role: worker
    name: 71-mount-storage-worker
  spec:
    config:
      ignition:
        version: 3.1.0
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
- Label and annotate storage nodes like this:
  ```
  # label node with node.longhorn.io/create-defaeultdisk=config
  oc label node work0 node.longhorn.io/create-default-disk=config
  ...
  
  # node.longhorn.io/default-node-tags: ["storage"]
  oc annotate node work0 --overwrite node.longhorn.io/default-node-tags='["storage"]'
  ...
  
  # node.longhorn.io/default-disks-config: [{"path":"/var/mnt/longhorn","allowScheduling":true,"tags":["ssd"],"name":"longhorn-ssd"}]
  oc annotate node work0 --overwrite node.longhorn.io/default-disks-config='[{"path":"/var/mnt/longhorn","allowScheduling":true,"tags":["ssd"],"name":"longhorn-ssd"}]'
  ...
  ```

## Example values.yaml

```
openshift:
  ui:
    route: "longhorn-ui"
    port: 443
    proxy: 8443
  finalizers: true
  mount: "/var/lib/longhorn"

defaultSettings:
  createDefaultDiskLabeledNodes: true
  defaultDataPath: /var/lib/longhorn
  defaultDataLocality: best-effort
  replicaSoftAntiAffinity: false
  defaultReplicaCount: 3
  replicaZoneSoftAntiAffinity: true
  nodeDownPodDeletionPolicy: delete-both-statefulset-and-deployment-pod

longhornManager:
  nodeSelector:
    node-role.kubernetes.io/worker: ""

longhornDriver:
  nodeSelector:
    node-role.kubernetes.io/worker: ""

longhornUI:
  nodeSelector:
    node-role.kubernetes.io/master: ""
```

## Installation

```
oc create namespace longhorn-system
oc adm policy add-scc-to-user anyuid -z default -n longhorn-system
oc adm policy add-scc-to-user privileged -z longhorn-service-account -n longhorn-system
helm install longhorn --namespace longhorn-system --values values.yaml
```
