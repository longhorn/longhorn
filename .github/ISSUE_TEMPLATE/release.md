---
name: Release task
about: Create a release task
title: "[RELEASE]"
labels: release/task
assignees: ''

---

## What's the task? Please describe.
Action items for releasing v<x.y.z>

## Roles
- Release captain: <!--responsible for RD efforts of release development and coordinating with QA captain-->
- QA captain: <!--responsible for coordinating QA efforts of release testing tasks-->

## Describe the sub-tasks.

### Pre-Release

**Generate GA Images**

- [ ] Trigger GA release build by [longhorn/longhorn Actions](https://github.com/longhorn/longhorn) - Release Captain

**The QA captain needs to coordinate the following efforts and finish these items before GA release**

- [ ] Regression test plan (manual) - QA Captain
- [ ] Run e2e regression for pre-GA milestones (`install`, `upgrade`) - @yangchiu 
- [ ] Run security testing of container images for pre-GA milestones - @yangchiu
- [ ] Verify longhorn chart PR to ensure all artifacts are ready for GA (`install`, `upgrade`) - QA Captain
- [ ] Run core testing (install, upgrade) for the GA build from the previous patch (1.5.4) and the last patch of the previous feature release (1.4.4). - QA Captain
 
### Release

**Release Captain needs to finish the following items**

- [ ] Release note - Release Captain
  - [ ] Deprecation note
  - [ ] Upgrade notes including highlighted notes, deprecation, compatible changes, and others impacting the current users
- [ ] Release longhorn/chart from the release branch to publish to [ArtifactHub](https://artifacthub.io/packages/helm/longhorn/longhorn) by [longhorn/charts Actions](https://github.com/longhorn/charts) - Release Captain
- [ ] Marked the release as `latest` release in longhorn/longhorn [README.md](https://github.com/longhorn/longhorn) - Release Captain
- [ ] Marked the release as `stable` release (For the first stable release, we need to consider several factors and reach a consensus by maintainers before claiming it stable. For any patch release after a stable release, we need to wait 1-2 weeks for user feedback.) - Release Captain

### Post-Release

**After marking the release as a `stable` release, Release Captain needs to coordinate the following items**

- [ ] Create a new release branch of manager/ui/tests/engine/longhorn instance-manager/share-manager/backing-image-manager when creating the RC1 (only for new feature release)
- [ ] Update https://github.com/longhorn/longhorn/blob/master/deploy/upgrade_responder_server/chart-values.yaml  - @PhanLe1010 
- [ ] Add another request for the rancher charts for the next patch release (`1.5.6`) - @rebeccazzzz  

### Rancher Charts

- [ ] Verify the chart can be installed & upgraded - @khushboo-rancher 
- [ ] rancher/image-mirrors update - @PhanLe1010
- [ ] rancher/charts active branches (2.7 & 2.8) for rancher marketplace - @mantissahz @PhanLe1010 


cc @longhorn/qa @longhorn/dev 
