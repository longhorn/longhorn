<h1 align="center" style="border-bottom: none">
    <a href="https://longhorn.io/" target="_blank"><img alt="Longhorn" width="300px" src="https://github.com/longhorn/website/blob/master/static/img/logos/longhorn-stacked-color.png""></a>
</h1>

<p align="center">A CNCF Incubating Project. Visit <a href="https://longhorn.io/" target="_blank">longhorn.io</a> for the full documentation.</p>

<div align="center">

[![Releases](https://img.shields.io/github/release/longhorn/longhorn/all.svg)](https://github.com/longhorn/longhorn/releases)
[![GitHub](https://img.shields.io/github/license/longhorn/longhorn)](https://github.com/longhorn/longhorn/blob/master/LICENSE)
[![Docs](https://img.shields.io/badge/docs-latest-green.svg)](https://longhorn.io/docs/latest/)

</div>

Longhorn is a distributed block storage system for Kubernetes. Longhorn is cloud-native storage built using Kubernetes and container primitives.

Longhorn is lightweight, reliable, and powerful. You can install Longhorn on an existing Kubernetes cluster with one `kubectl apply` command or by using Helm charts. Once Longhorn is installed, it adds persistent volume support to the Kubernetes cluster.

Longhorn implements distributed block storage using containers and microservices. Longhorn creates a dedicated storage controller for each block device volume and synchronously replicates the volume across multiple replicas stored on multiple nodes. The storage controller and replicas are themselves orchestrated using Kubernetes. Here are some notable features of Longhorn:

1. Enterprise-grade distributed storage with no single point of failure
2. Incremental snapshot of block storage
3. Backup to secondary storage (NFSv4 or S3-compatible object storage) built on efficient change block detection
4. Recurring snapshot and backup
5. Automated non-disruptive upgrade. You can upgrade the entire Longhorn software stack without disrupting running volumes!
6. Intuitive GUI dashboard

You can read more technical details of Longhorn [here](https://longhorn.io/).

# Releases

> **NOTE**:
> - __\<version\>*__ means the release branch is under active support and will have periodic follow-up patch releases.
> - __Latest__ release means the version is the latest release of the newest release branch.
> - __Stable__ release means the version is stable and has been widely adopted by users.
> - Release EOL: One year after the first stable version. For the details, please refer to [Release Support](https://github.com/longhorn/longhorn/wiki/Release-Schedule-&-Support#release-support).

https://github.com/longhorn/longhorn/releases

| Release   | Current Version | First Stable Version | Status         | Release Note                                                   | Important Note                                              | Supported          |
|-----------|-----------------|----------------------|----------------|----------------------------------------------------------------|-------------------------------------------------------------| -------------------|
| **1.6***  | 1.6.0           | N/A                  | Latest         | [🔗](https://github.com/longhorn/longhorn/releases/tag/v1.6.0) | [🔗](https://longhorn.io/docs/1.6.0/deploy/important-notes) | ✅                 |
| **1.5***  | 1.5.4           | 1.5.3 (Nov 17, 2023) | Stable         | [🔗](https://github.com/longhorn/longhorn/releases/tag/v1.5.3) | [🔗](https://longhorn.io/docs/1.5.3/deploy/important-notes) | ✅                 |
| **1.4***  | 1.4.4           | 1.4.1 (Mar 13, 2023) | Stable         | [🔗](https://github.com/longhorn/longhorn/releases/tag/v1.4.4) | [🔗](https://longhorn.io/docs/1.4.4/deploy/important-notes) | ✅                 |
| 1.3       | 1.3.3           | 1.3.2                | Stable         | [🔗](https://github.com/longhorn/longhorn/releases/tag/v1.3.3) | [🔗](https://longhorn.io/docs/1.3.3/deploy/important-notes) |                    |
| 1.2       | 1.2.6           | 1.2.3                | Stable         | [🔗](https://github.com/longhorn/longhorn/releases/tag/v1.2.6) | [🔗](https://longhorn.io/docs/1.2.6/deploy/important-notes) |                    |
| 1.1       | 1.1.3           | 1.1.2                | Stable         | [🔗](https://github.com/longhorn/longhorn/releases/tag/v1.1.3) |                                                             |                    |

# Roadmap

https://github.com/longhorn/longhorn/wiki/Roadmap

# Components

Longhorn is 100% open-source software. Project source code is spread across several repositories:

* Engine: [![Build Status](https://drone-publish.longhorn.io/api/badges/longhorn/longhorn-engine/status.svg)](https://drone-publish.longhorn.io/longhorn/longhorn-engine)[![Go Report Card](https://goreportcard.com/badge/github.com/longhorn/longhorn-engine)](https://goreportcard.com/report/github.com/longhorn/longhorn-engine)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-engine.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-engine?ref=badge_shield)
* Manager: [![Build Status](https://drone-publish.longhorn.io/api/badges/longhorn/longhorn-manager/status.svg)](https://drone-publish.longhorn.io/longhorn/longhorn-manager)[![Go Report Card](https://goreportcard.com/badge/github.com/longhorn/longhorn-manager)](https://goreportcard.com/report/github.com/longhorn/longhorn-manager)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-manager.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-manager?ref=badge_shield)
* Instance Manager: [![Build Status](http://drone-publish.longhorn.io/api/badges/longhorn/longhorn-instance-manager/status.svg)](http://drone-publish.longhorn.io/longhorn/longhorn-instance-manager)[![Go Report Card](https://goreportcard.com/badge/github.com/longhorn/longhorn-instance-manager)](https://goreportcard.com/report/github.com/longhorn/longhorn-instance-manager)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-instance-manager.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-instance-manager?ref=badge_shield)
* Share Manager: [![Build Status](http://drone-publish.longhorn.io/api/badges/longhorn/longhorn-share-manager/status.svg)](http://drone-publish.longhorn.io/longhorn/longhorn-share-manager)[![Go Report Card](https://goreportcard.com/badge/github.com/longhorn/longhorn-share-manager)](https://goreportcard.com/report/github.com/longhorn/longhorn-share-manager)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-share-manager.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-share-manager?ref=badge_shield)
* Backing Image Manager: [![Build Status](http://drone-publish.longhorn.io/api/badges/longhorn/backing-image-manager/status.svg)](http://drone-publish.longhorn.io/longhorn/backing-image-manager)[![Go Report Card](https://goreportcard.com/badge/github.com/longhorn/backing-image-manager)](https://goreportcard.com/report/github.com/longhorn/backing-image-manager)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Fbacking-image-manager.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Fbacking-image-manager?ref=badge_shield)
* UI: [![Build Status](https://drone-publish.longhorn.io/api/badges/longhorn/longhorn-ui/status.svg)](https://drone-publish.longhorn.io/longhorn/longhorn-ui)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-ui.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-ui?ref=badge_shield)

| Component                      | What it does                                                           | GitHub repo                                                                                 |
| :----------------------------- | :--------------------------------------------------------------------- | :------------------------------------------------------------------------------------------ |
| Longhorn Backing Image Manager | Backing image download, sync, and deletion in a disk                   | [longhorn/backing-image-manager](https://github.com/longhorn/backing-image-manager)         |
| Longhorn Instance Manager      | Controller/replica instance lifecycle management                       | [longhorn/longhorn-instance-manager](https://github.com/longhorn/longhorn-instance-manager) |
| Longhorn Manager               | Longhorn orchestration, includes CSI driver for Kubernetes             | [longhorn/longhorn-manager](https://github.com/longhorn/longhorn-manager)                   |
| Longhorn Share Manager         | NFS provisioner that exposes Longhorn volumes as ReadWriteMany volumes | [longhorn/longhorn-share-manager](https://github.com/longhorn/longhorn-share-manager)       |
| Longhorn UI                    | The Longhorn dashboard                                                 | [longhorn/longhorn-ui](https://github.com/longhorn/longhorn-ui)                             |

| Library                        | What it does                                                           | GitHub repo                                                                                 |
| :----------------------------- | :--------------------------------------------------------------------- | :------------------------------------------------------------------------------------------ |
| Longhorn Engine                | V1 Core controller/replica logic                                       | [longhorn/longhorn-engine](https://github.com/longhorn/longhorn-engine)                     |
| Longhorn SPDK Engine           | V2 Core controller/replica logic                                       | [longhorn/longhorn-spdk-engine](https://github.com/longhorn/longhorn-spdk-engine)           |
| iSCSI Helper                   | V1 iSCSI client and server libraries                                   | [longhorn/go-iscsi-helper](https://github.com/longhorn/go-iscsi-helper)                     |
| SPDK Helper                    | V2 SPDK client and server libraries                                    | [longhorn/go-spdk-helper](https://github.com/longhorn/go-spdk-helper)                       |
| Backup Store                   | Backkup libraries                                                      | [longhorn/backupstore](https://github.com/longhorn/backupstore)                             |
| Common Libraries               |                                                                        | [longhorn/go-common-libs](https://github.com/longhorn/go-common-libs)                       |

![Longhorn UI](./longhorn-ui.png)

# Get Started

## Requirements

For the installation requirements, refer to the [Longhorn documentation.](https://longhorn.io/docs/latest/deploy/install/#installation-requirements)

## Installation

> **NOTE**: 
> Please note that the master branch is for the upcoming feature release development. 
> For an official release installation or upgrade, please take a look at the ways below.

Longhorn can be installed on a Kubernetes cluster in several ways:

- [Rancher App Marketplace](https://longhorn.io/docs/latest/deploy/install/install-with-rancher/)
- [kubectl](https://longhorn.io/docs/latest/deploy/install/install-with-kubectl/)
- [Helm](https://longhorn.io/docs/latest/deploy/install/install-with-helm/)

## Documentation

The official Longhorn documentation is [here.](https://longhorn.io/docs)

# Get Involved

## Discussion, Feedback

If having any discussions or feedback, feel free to [file a discussion](https://github.com/longhorn/longhorn/discussions).

## Features Request, Bug Reporting

If having any issues, feel free to [file an issue](https://github.com/longhorn/longhorn/issues/new/choose).
We have a weekly community issue review meeting to review all reported issues or enhancement requests.

When creating a bug issue, please help upload the support bundle to the issue or send it to
[longhorn-support-bundle](mailto:longhorn-support-bundle@suse.com).

## Report Vulnerabilities

If any vulnerabilities are found, please report them to [longhorn-security](mailto:longhorn-security@suse.com).

# Community

Longhorn is open-source software, so contributions are greatly welcome.
Please read [Code of Conduct](./CODE_OF_CONDUCT.md) and [Contributing Guideline](./CONTRIBUTING.md) before contributing.

Contributing code is not the only way of contributing. We value feedback very much and many of the Longhorn features originated from users' feedback.
If you have any feedback, feel free to [file an issue](https://github.com/longhorn/longhorn/issues/new/choose) and talk to the developers at the [CNCF](https://slack.cncf.io/) [#longhorn](https://cloud-native.slack.com/messages/longhorn) Slack channel.

If you are having any discussion, feedback, requests, issues, or security reports, please follow the below ways.
We also have a [CNCF Slack channel: longhorn](https://cloud-native.slack.com/messages/longhorn) for discussion.

## Community Meeting and Office Hours
Hosted by the core maintainers of Longhorn: 4th Friday of every month at 09:00 (CET) or 16:00 (CST) at https://community.cncf.io/longhorn-community/.

## Longhorn Mailing List
Stay up to date on the latest news and events: https://lists.cncf.io/g/cncf-longhorn

You can read more about the community and its events here: https://github.com/longhorn/community

# License

Copyright (c) 2014-2022 The Longhorn Authors

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

## Longhorn is a [CNCF Incubating Project](https://www.cncf.io/projects/)

![Longhorn is a CNCF Incubating Project](https://github.com/cncf/artwork/blob/main/other/cncf/horizontal/color/cncf-color.png)
