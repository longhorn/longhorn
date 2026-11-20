---
name: Release Task
about: Create a release task
title: "[RELEASE] Release {{ env.RELEASE_VERSION }}"
type: "Task"
labels: ["release/task", "area/install-uninstall-upgrade"]
assignees: ''

---

## What's the task? Please describe

Action items for releasing {{ env.RELEASE_VERSION }}.

## Roles

- Release Captain: {{ env.RELEASE_CAPTAIN }} <!--drives the release process and coordinates with the QA Captain-->
- QA Captain: {{ env.QA_CAPTAIN }} <!--drives the release testing process and coordinates with the QA team-->

## Describe the sub-tasks

### Pre-Release

#### Release Captain

> [!IMPORTANT]
> The Release Captain completes these items.

- [ ] Feature release only ({{ env.MAJOR_MINOR_VERSION }}):
  - [ ] Create the release branch {{ env.BRANCH_NAME }} in each component repository by triggering [▶️ Create Longhorn Repository Branches Action](https://github.com/longhorn/release/actions/workflows/create-repo-branches.yml). RC1 and later builds come from this branch; master stays open for the next feature release.
  - [ ] Add the new branch {{ env.BRANCH_NAME }} to the [renovate configuration](https://github.com/longhorn/release/blob/main/renovate-default.json).
    - PR: <!--URL of the pull request-->
  - [ ] After the release branch exists, update the version file on the default branch of each component repository by triggering [▶️ Update Longhorn Repository Version File in Default Branch Action](https://github.com/longhorn/release/actions/workflows/update-repo-version-file.yml):
    - longhorn-manager
    - longhorn-ui
    - longhorn-tests
    - longhorn-engine
    - longhorn-instance-manager
    - longhorn-share-manager
    - backing-image-manager
    - longhorn-spdk-engine (after GA)
    - cli
  - [ ] Update `jobs.release.strategy.matrix` in [release-sprint.yml](https://github.com/longhorn/release/blob/main/.github/workflows/release-sprint.yml).
    - PR: <!--URL of the pull request-->
- [ ] Trigger the RC build by [▶️ Release-Preview Action](https://github.com/longhorn/release/actions/workflows/release-preview.yml).

#### QA Captain

> [!IMPORTANT]
> The QA Captain coordinates these items before GA.

- [ ] Prepare the manual regression test plan.
- [ ] Update the Longhorn documentation: `Best Practices > Operating System` and `Best Practices > Kubernetes > Kubernetes Version`.
  - PR: <!--URL of the pull request-->
- [ ] Run e2e regression for pre-GA milestones (`install`, `upgrade`).
- [ ] Run security testing of container images for pre-GA milestones.
  - [ ] Address the reported CVEs. Tracked in sub-issue `Fix CVE issues for {{ env.RELEASE_VERSION }}` - @c3y1huang
  - [ ] Open upstream issues for unresolved CVEs in CSI sidecar images - @c3y1huang

---

### Release

#### Release Captain: Build GA

> [!IMPORTANT]
> The Release Captain completes these items.

- [ ] Feature release only ({{ env.MAJOR_MINOR_VERSION }}):
  - [ ] Confirm sub-issue `Regular Tasks for Feature Release for {{ env.MAJOR_MINOR_VERSION }}` is complete.
- [ ] Confirm sub-issue `Fix CVE issues for {{ env.RELEASE_VERSION }}` is complete.
- [ ] Update image versions in [chart/README.md](https://github.com/longhorn/longhorn/tree/{{ env.RELEASE_VERSION }}/chart/README.md).
  - PR: <!--URL of the pull request-->
- [ ] Trigger the GA build by [▶️ Release Action](https://github.com/longhorn/release/actions/workflows/release.yml).

#### QA Captain: Validate GA

> [!IMPORTANT]
> The QA Captain coordinates these items before GA.

- [ ] Run security testing of container images for the GA build.
- [ ] Verify the longhorn chart PR has all artifacts for the GA build (`install`, `upgrade`).
- [ ] Run core testing (`install`, `upgrade`) for the GA build:
  - Upgrade from the previous patch of the same feature release.
  - Upgrade from the last patch of the previous feature release.

#### Release Captain: Publish GA

> [!IMPORTANT]
> The Release Captain completes these items.

- [ ] Write the release note in [CHANGELOG](https://github.com/longhorn/longhorn/tree/{{ env.RELEASE_VERSION }}/CHANGELOG).
  - [ ] Deprecation note.
    - PR: <!--URL of the pull request-->
  - [ ] Highlights, compatibility changes, and other changes that affect current users.
    - PR: <!--URL of the pull request-->
- [ ] Update the [Longhorn documentation](https://github.com/longhorn/website).
  - [ ] Update [config.toml](https://github.com/longhorn/website/blob/master/config.toml) and copy `content/docs/{{ env.RELEASE_VERSION }}` to the next patch `-dev` directory.
    - PR: <!--URL of the pull request-->
  - [ ] Update image versions in `References > Helm Values` and `Snapshot and Backups > CSI Snapshot Support > Enable CSI Snapshot Support on a Cluster`.
    - PR: <!--URL of the pull request-->
  - [ ] Update `Important Notes`.
    - PR: <!--URL of the pull request-->
- [ ] Publish the GA release in [longhorn/longhorn](https://github.com/longhorn/longhorn) and [longhorn/cli](https://github.com/longhorn/cli).
- [ ] Publish the chart from the release branch to [ArtifactHub](https://artifacthub.io/packages/helm/longhorn/longhorn) by [▶️ Release Charts on Demand Action](https://github.com/longhorn/charts/actions/workflows/release-ondemand.yml).
  - Set `Use workflow from` to `master` and `Release branch` to `v<x.y>.x`.
- [ ] Mark the release as `latest` in [README.md](https://github.com/longhorn/longhorn).
  - PR: <!--URL of the pull request-->
- [ ] Update `jobs.release.strategy.matrix` in [release-sprint.yml](https://github.com/longhorn/release/blob/main/.github/workflows/release-sprint.yml).
  - PR: <!--URL of the pull request-->
- [ ] Update the image tags in chart/values.yaml on the development branch by triggering [▶️ Update Longhorn Repository Branch Image Tags](https://github.com/longhorn/longhorn/actions/workflows/update-branch-image-tags.yaml).
  - PR: <!--URL of the pull request-->

---

### Post-Release

> [!IMPORTANT]
> The Release Captain coordinates these items.

- [ ] Update the [support matrix](https://www.suse.com/suse-longhorn/support-matrix/all-supported-versions/) - @rebeccazzzz
- [ ] Update the [lifecycle page](https://www.suse.com/lifecycle/#suse-storage) - @rebeccazzzz

#### Stable Release

> [!NOTE]
> - A feature release (x.y.0) is never marked stable.
> - The first stable release of a release line requires maintainer consensus.
> - Later patch releases wait 1-2 weeks for user feedback before being marked stable.

- [ ] Mark the release as `stable` and update [support-versions.txt](https://github.com/longhorn/longhorn/blob/master/support-versions.txt).
  - PR: <!--URL of the pull request-->
- [ ] Update [upgrade_responder_server/chart-values.yaml](https://github.com/longhorn/longhorn/blob/master/deploy/upgrade_responder_server/chart-values.yaml) - @mantissahz
  - PR: <!--URL of the pull request-->

#### Rancher Charts

> [!IMPORTANT]
> Start these tasks only after the release is marked `stable`.

- [ ] Prepare the Rancher chart in the active rancher/charts branches for the Rancher App Marketplace - @carterli0407-cell @mantissahz
- [ ] Update rancher/image-mirrors - @carterli0407-cell @mantissahz
- [ ] Verify the Rancher chart installs and upgrades - {{ env.QA_CAPTAIN }}
- [ ] Request the Rancher chart for the next patch release - @rebeccazzzz

cc @longhorn/qa @longhorn/dev
