# Use PDB to protect Longhorn components from drains

## Summary

Some Longhorn components should be available to correctly handle cleanup/detach Longhorn volumes during the draining process.
They are: `csi-attacher`, `csi-provisioner`, `longhorn-admission-webhook`, `longhorn-conversion-webhook`, `share-manager`, `instance-manager`, and daemonset pods in `longhorn-system` namespace.

This LEP outlines our existing solutions to protect these components, the issues of these solutions, and the proposal for improvement.


### Related Issues

https://github.com/longhorn/longhorn/issues/3304

## Motivation

### Goals

1. Have better ways to protect Longhorn components (`csi-attacher`, `csi-provisioner`, `longhorn-admission-webhook`, `longhorn-conversion-webhook`) without demanding the users to specify the draining flags to skip these pods.

## Proposal

1. Our existing solutions to protect these components are:
   * For `instance-manager`: dynamically create/delete instance manager PDB
   * For Daemonset pods in `longhorn-system` namespace: we advise the users to specify `--ignore-daemonsets` to ignore them in the `kubectl drain` command. This actually follows the [best practice](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/#:~:text=If%20there%20are%20pods%20managed%20by%20a%20DaemonSet%2C%20you%20will%20need%20to%20specify%20%2D%2Dignore%2Ddaemonsets%20with%20kubectl%20to%20successfully%20drain%20the%20node)
   * For `csi-attacher`, `csi-provisioner`, `longhorn-admission-webhook`, and `longhorn-conversion-webhook`: we advise the user to specify `--pod-selector` to ignore these pods
1. Proposal for `csi-attacher`, `csi-provisioner`, `longhorn-admission-webhook`, and `longhorn-conversion-webhook`: <br>
   The problem with the existing solution is that sometime, users could not specify `--pod-selector` for the `kubectl drain` command.
   For example, for the users that are using the project [System Upgrade Controller](https://github.com/rancher/system-upgrade-controller), they don't have option to specify `--pod-selector`.
   Also, we would like to have a more automatic way instead of relying on the user to set kubectl drain options.

   Therefore, we propose the following design:
    * Longhorn manager automatically create PDBs for `csi-attacher`, `csi-provisioner`, `longhorn-admission-webhook`, and `longhorn-conversion-webhook` with `minAvailable` set to 1.
      This will make sure that each of these deployment has at least 1 running pod during the draining process.
    * Longhorn manager continuously watches the volumes and removes the PDBs once there is no attached volume.

   This should work for both single-node and multi-node cluster.


### User Stories



#### Story 1
Before the enhancement, users would need to specify the drain options for drain command to exclude Longhorn pods.
Sometimes, this is not possible when users use third-party solution to drain and upgrade kubernetes, such as System Upgrade Controller.

#### Story 2

### User Experience In Detail

After the enhancement, the user can doesn't need to specify the drain options for the drain command to exclude Longhorn pods.

### API changes

None

## Design

### Implementation Overview

Create a new controller inside Longhorn manager called `longhorn-pdb-controller`, the controller listens for the changes for
`csi-attacher`, `csi-provisioner`, `longhorn-admission-webhook`, `longhorn-conversion-webhook`, and Longhorn volumes to adjust the PDB correspondingly.

### Test plan

https://github.com/longhorn/longhorn/issues/3304#issuecomment-1467174481

### Upgrade strategy

No Upgrade is needed

## Note

In the original Github ticket, we mentioned that we need to add PDB to protect share manager pod from being drained before its workload pods because if share manager pod doesn't exist then its volume cannot be unmounted in the CSI flow.
However, with the fix https://github.com/longhorn/longhorn/issues/5296, we can always umounted the volume even if the share manager is not running.
Therefore, we don't need to protect share manager pod.
