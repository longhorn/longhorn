---
name: Release task
about: Create a release task
title: "[RELEASE]"
labels: release/task
assignees: ''

---

**What's the task? Please describe.**
Action items for releasing v<x.y.z>

**Describe the sub-tasks.**
  - Pre-Release
    - [ ] Regression test plan (manual) - @khushboo-rancher 
    - [ ] Run e2e regression for pre-GA milestones (`install`, `upgrade`) - @yangchiu 
    - [ ] Run security testing of container images for pre-GA milestones - @yangchiu 
    - [ ] Verify longhorn chart PR to ensure all artifacts are ready for GA (`install`, `upgrade`)  @chriscchien 
    - [ ] Run core testing (install, upgrade) for the GA build from the previous patch and the last patch of the previous feature release (1.4.2). - @yangchiu 
  - Release
    - [ ] Release longhorn/chart from the release branch to publish to ArtifactHub
    - [ ] Release note
	     - [ ] Deprecation note
	     - [ ] Upgrade notes including highlighted notes, deprecation, compatible changes, and others impacting the current users
  - Post-Release
    - [ ] Create a new release branch of manager/ui/tests/engine/longhorn instance-manager/share-manager/backing-image-manager when creating the RC1
    - [ ] Update https://github.com/longhorn/longhorn/blob/master/deploy/upgrade_responder_server/chart-values.yaml @PhanLe1010 
    - [ ] Add another request for the rancher charts for the next patch release (`1.5.1`) @rebeccazzzz  
  - Rancher charts: verify the chart is able to install & upgrade - @khushboo-rancher 
    - [ ] rancher/image-mirrors update @weizhe0422 (@PhanLe1010 )
        - https://github.com/rancher/image-mirror/pull/412
    - [ ] rancher/charts 2.7 branches for rancher marketplace @weizhe0422 (@PhanLe1010)
        - `dev-2.7`: https://github.com/rancher/charts/pull/2766

cc @longhorn/qa @longhorn/dev 
