---
name: Release Task
about: Create a release task
title: "[RELEASE] Release {{ env.RELEASE_VERSION }}"
type: "Task"
labels: ["release/task", "area/install-uninstall-upgrade"]
assignees: ''

---

## What's the task? Please describe

Action items for releasing {{ env.RELEASE_VERSION }}

## Roles

- Release captain: {{ env.RELEASE_CAPTAIN }} <!--responsible for RD efforts of release development and coordinating with QA captain-->
- QA captain: {{ env.QA_CAPTAIN }} <!--responsible for coordinating QA efforts of release testing tasks-->

## Describe the sub-tasks

### Pre-Release

#### Release Captain Tasks

> [!IMPORTANT]
> The Release Captain needs to finish the following items

- [ ] This tasks are only needed when doing a feature release such as {{ env.MAJOR_MINOR_VERSION }}.
  - [ ] Before creating RC1, create a new release branch for the following component repositories by triggering [▶️ Create Longhorn Repository Branches Action](https://github.com/longhorn/release/actions/workflows/create-repo-branches.yml), and then create RC1 from the new branch. Leave the master branch for the next feature release development.
  - [ ] Add the new branch {{ env.BRANCH_NAME }} to [renovate configuration](https://github.com/longhorn/release/blob/main/renovate-default.json).
    - [ ] PR: <!--URL of the pull request-->
  - [ ] After creating the new release branch, update the version file in each repo by [▶️ Update Longhorn Repository Version File in Default Branch Action](https://github.com/longhorn/release/actions/workflows/update-repo-version-file.yml).
    - longhorn-manager
    - longhorn-ui
    - longhorn-tests
    - longhorn-engine
    - longhorn-instance-manager
    - longhorn-share-manager
    - backing-image-manager
    - longhorn-spdk-engine (needed after GA)
    - cli
  - [ ] Update `jobs.release.strategy.matrix` in [sprint release](https://github.com/longhorn/release/blob/main/.github/workflows/release-sprint.yml).
    - [ ] PR: <!--URL of the pull request-->
- [ ] Trigger the RC release build by [▶️ Release-Preview Action](https://github.com/longhorn/release/actions/workflows/release-preview.yml).

#### QA Captain Tasks

> [!IMPORTANT]  
> The QA captain needs to coordinate the following items before the GA release.

- [ ] Regression test plan (manual)
- [ ] Update Longhorn official document
  - [ ] Update `Best Practices>Operating System` and `Best Practices>Kubernetes>Kubernetes Version`
    - [ ] PR: <!--URL of the pull request-->
- [ ] Run e2e regression for pre-GA milestones (`install`, `upgrade`)
- [ ] Run security testing of container images for pre-GA milestones.
  - [ ] Investigate and fix the security issues. The issues are tracked by the sub-issue `Fix CVE issues for {{ env.RELEASE_VERSION }}` - @c3y1huang
  - [ ] Create security issues at upstream for unresolved CVEs in CSI sidecar images - @c3y1huang

---

### Release

#### Release Captain Tasks for the GA Build

> [!IMPORTANT]
> The Release Captain needs to finish the following items

- [ ] This tasks are only needed when doing a feature release such as {{ env.MAJOR_MINOR_VERSION }}.
  - [ ] Ensure the sub-issue `Regular Tasks for Feature Release for {{ env.MAJOR_MINOR_VERSION }}` is completed.
- [ ] Ensure the sub-issue `Fix CVE issues for {{ env.RELEASE_VERSION }}` is completed.
- [ ] Update image versions in [chart/README.md](https://github.com/longhorn/longhorn/tree/{{ env.RELEASE_VERSION }}/chart/README.md).
  - PR: <!--URL of the pull request-->
- [ ] Trigger the GA release build by [▶️ Release Action](https://github.com/longhorn/release/actions/workflows/release.yml).

#### QA Captain Tasks for the GA Build

> [!IMPORTANT]  
> The QA captain needs to coordinate the following items before the GA release.

- [ ] Run security testing of container images for GA build
- [ ] Verify longhorn chart PR to ensure all artifacts are ready for GA build (`install`, `upgrade`)
- [ ] Run core testing (install, upgrade) for the GA build
  - Upgrade from the previous patch of the same feature release.
  - Upgrade from the last patch of the previous feature release.

#### Release Captain Tasks after Completing the GA Build Validation

- [ ] Create a release note ([CHANGELOG](https://github.com/longhorn/longhorn/tree/{{ env.RELEASE_VERSION }}/CHANGELOG)).
  - [ ] Deprecation note.
    - PR: <!--URL of the pull request-->
  - [ ] Update notes including highlighted notes, deprecation, compatible changes, and others impacting the current users.
    - PR: <!--URL of the pull request-->
- [ ] Update [Longhorn official documentation](https://github.com/longhorn/website).
  - [ ] Update [config.toml](https://github.com/longhorn/website/blob/master/config.toml) and publish the new version of doc and add a next patch version of dev doc.
  - [ ] Update image versions in `References > Helm Values` and `Snapshot and Backups > CSI Snapshot Support > Enable CSI Snapshot Support on a Cluster`.
    - PR: <!--URL of the pull request-->
  - [ ] Update `Important Notes`.
    - PR: <!--URL of the pull request-->
- [ ] Publish the GA release in [longhorn/longhorn](https://github.com/longhorn/longhorn) and [longhorn/cli](https://github.com/longhorn/cli).
- [ ] Release longhorn/chart from the release branch to publish to [ArtifactHub](https://artifacthub.io/packages/helm/longhorn/longhorn) by [▶️ Release Charts on Demand Action](https://github.com/longhorn/charts/actions/workflows/release-ondemand.yml).
  <!-- Set "Use workflow from" to "master" and "Release branch" to "v<x.y>.x" -->
- [ ] Mark the release as `latest` release in longhorn/longhorn [README.md](https://github.com/longhorn/longhorn).
  - PR: <!--URL of the pull request-->
- [ ] Update `jobs.release.strategy.matrix` in [sprint release](https://github.com/longhorn/release/blob/main/.github/workflows/release-sprint.yml).
  - PR: <!--URL of the pull request-->
- [ ] Update Longhorn image tags in longhorn/longhorn/chart/values.yaml in the development branch by triggering [▶️ Update Longhorn Repository Branch Image Tags](https://github.com/longhorn/longhorn/actions/workflows/update-branch-image-tags.yaml).

---

### Post-Release

- [ ] Mark the release as `stable` release and update stable versions in https://github.com/longhorn/longhorn/blob/master/support-versions.txt
  - For the first stable release, we need to consider several factors and reach a consensus by maintainers before claiming it stable.
  - For any patch release after a stable release, we need to wait 1-2 weeks for user feedback.
  - PR: <!--URL of the pull request-->

**After marking the release as a `stable` release, Release Captain needs to coordinate the following items**

- [ ] Update https://github.com/longhorn/longhorn/blob/master/deploy/upgrade_responder_server/chart-values.yaml - @PhanLe1010
  - PR: <!--URL of the pull request-->
- [ ] Add another request for the rancher charts for the next patch release - @rebeccazzzz  
- [ ] Update the [support matrix](https://www.suse.com/suse-longhorn/support-matrix/all-supported-versions/) - @asettle @rebeccazzzz
- [ ] Update the [lifecycle page](https://www.suse.com/lifecycle/#suse-storage) - @asettle @rebeccazzzz

### Rancher Charts

**The Release Captain needs to coordinate the following items.**

- [ ] Verify the chart can be installed & upgraded - {{ env.QA_CAPTAIN }}
- [ ] rancher/image-mirrors update - @mantissahz @PhanLe1010
- [ ] rancher/charts active branches for Rancher App Marketplace - @mantissahz @PhanLe1010

cc @longhorn/qa @longhorn/dev
