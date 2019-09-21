# Taint Toleration

## Overview
If users want to create nodes with large storage spaces and/or CPU resources for Longhorn only (to store replica data) and reject other general workloads, they can taint those nodes and add tolerations for Longhorn components. Then Longhorn can be deployed on those nodes.

For more Kubernetes taint and toleration info, see:
[Kubernetes Taint & Tolerations](https://kubernetes.io/docs/concepts/configuration/taint-and-toleration/)

## Setup
### During installing Longhorn
Follow the instructions to set init taint tolerations: [Customize default settings](https://github.com/longhorn/longhorn/wiki/Feature:-Customized-Default-Setting#usage)

### After Longhorn has been installed
The taint toleration setting can be found at Longhorn UI:

Setting -> General -> Kubernetes Taint Toleration

Users can modify the existing tolerations or add more tolerations here, but noted that it will result in all the Longhorn system components to be recreated.

## Usage
1. Before modifying the toleration setting, users should make sure all Longhorn volumes are `detached`. Since all Longhorn components will be restarted then the Longhorn system is unavailable temporarily. If there are running Longhorn volumes in the system, this means the Longhorn system cannot restart its components and the request will be rejected.

2. During the Longhorn system updates toleration setting and restarts its components, users shouldn’t operate the Longhorn system.

3. When users set tolerations, the substring `kubernetes.io` shouldn't be contained in the setting. It is used and considered as the key of Kubernetes default tolerations.

4.  Multiple tolerations can be set here, and these tolerations are separated by the semicolon. For example: `key1=value1:NoSchedule; key2:NoExecute`. 

## History
[Original feature request](https://github.com/longhorn/longhorn/issues/584)

Available since v0.6.0
