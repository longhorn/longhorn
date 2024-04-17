---
name: Release task
about: Create a release task
title: "[RELEASE]"
labels: release/task
assignees: ''

---

**What's the task? Please describe.**
Action items for releasing v<x.y.z>

**Roles**
- Release captain: <!--responsible for RD efforts of release development and coordinating with QA captain-->
- QA captain: <!--responsible for coordinating QA efforts of release testing tasks-->

**Describe the sub-tasks.**
  - Pre-Release (QA captain needs to coordinate the following efforts and finish these items)
    - [ ] Regression test plan (manual) - QA captain 
    - [ ] Run e2e regression for pre-GA milestones (`install`, `upgrade`) - @yangchiu 
    - [ ] Run security testing of container images for pre-GA milestones - @roger-ryao 
    - [ ] Verify longhorn chart PR to ensure all artifacts are ready for GA (`install`, `upgrade`)  @chriscchien 
    - [ ] Run core testing (install, upgrade) for the GA build from the previous patch (1.5.4) and the last patch of the previous feature release (1.4.4). - @yangchiu 
  - Release (Release captain needs to finish the following items)
    - [ ] Release longhorn/chart from the release branch to publish to ArtifactHub
    - [ ] Release note
	     - [ ] Deprecation note
	     - [ ] Upgrade notes including highlighted notes, deprecation, compatible changes, and others impacting the current users
  - Post-Release (Release captain needs to coordinate the following items)
    - [ ] Create a new release branch of manager/ui/tests/engine/longhorn instance-manager/share-manager/backing-image-manager when creating the RC1 (only for new feature release)
    - [ ] Update https://github.com/longhorn/longhorn/blob/master/deploy/upgrade_responder_server/chart-values.yaml @PhanLe1010 
    - [ ] Add another request for the rancher charts for the next patch release (`1.5.6`) @rebeccazzzz  
  - Rancher charts: verify the chart can be installed & upgraded - @khushboo-rancher 
    - [ ] rancher/image-mirrors update @PhanLe1010
    - [ ] rancher/charts active branches (2.7 & 2.8) for rancher marketplace @mantissahz @PhanLe1010 

cc @longhorn/qa @longhorn/dev 
