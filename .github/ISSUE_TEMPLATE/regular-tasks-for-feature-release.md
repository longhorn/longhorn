---
name: Regular Tasks for Feature Release
about: Regular tasks for a feature release
title: "[RELEASE] Regular Tasks for Feature Release {{ env.RELEASE_VERSION }}"
labels: ["release/task", "area/install-uninstall-upgrade"]
assignees: ''
---

## What's the task? Please describe

Regular tasks for feature release {{ env.RELEASE_VERSION }} must be completed well before the release, during the development phase.

For OS distro updates for SLES and SLE Micro, need to update for each patch release as well. 

## Describe the sub-tasks

- [ ] OS Distro Version Update (QA captain)
  - [ ] Verify by ci.longhorn.io/job/public/job
  - [ ] Update `Best Practices>Operating System` in the official document and testing pipelines

- [ ] K8s Distro Version Update (QA captain)
  - [ ] Update the testing pipelines to use the latest supported K8s version (RKE2, K3s)

- [ ] BCI Image Update for Component Container Base Image

- [ ] Golang Version Update
  - [ ] BCI golang image update
  - [ ] go.mod update

- [ ] Kubernetes Version Update 
  - [ ] Update the official document with all versions we support
  - [ ] Update the minimum version in official document and chart if needed

- [ ] Kubernetes Dependent Library Version Update

- [ ] CSI Sidecar Version Update

- [ ] Support Bundle Kit Version Update

- [ ] NFS-Ganesha Version Update

- [ ] SPDK Version Update

## Additional context

https://github.com/longhorn/longhorn/wiki/Version-Update-Policy
