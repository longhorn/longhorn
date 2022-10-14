# Longhorn

Longhorn is a distributed block storage system for Kubernetes. Longhorn is cloud native storage because it is built using Kubernetes and container primitives.

Longhorn is lightweight, reliable, and powerful. You can install Longhorn on an existing Kubernetes cluster with one `kubectl apply` command or using Helm charts. Once Longhorn is installed, it adds persistent volume support to the Kubernetes cluster.

Longhorn implements distributed block storage using containers and microservices. Longhorn creates a dedicated storage controller for each block device volume and synchronously replicates the volume across multiple replicas stored on multiple nodes. The storage controller and replicas are themselves orchestrated using Kubernetes. Here are some notable features of Longhorn:

1. Enterprise-grade distributed storage with no single point of failure
2. Incremental snapshot of block storage
3. Backup to secondary storage (NFSv4 or S3-compatible object storage) built on efficient change block detection
4. Recurring snapshot and backup
5. Automated non-disruptive upgrade. You can upgrade the entire Longhorn software stack without disrupting running volumes!
6. Intuitive GUI dashboard

You can read more technical details of Longhorn [here](https://longhorn.io/).

## Current Status

The latest release of Longhorn is [![Releases](https://img.shields.io/github/release/longhorn/longhorn/all.svg)](https://github.com/longhorn/longhorn/releases)

## Build Status
* Engine: [![Build Status](https://drone-publish.longhorn.io/api/badges/longhorn/longhorn-engine/status.svg)](https://drone-publish.longhorn.io/longhorn/longhorn-engine)[![Go Report Card](https://goreportcard.com/badge/github.com/longhorn/longhorn-engine)](https://goreportcard.com/report/github.com/longhorn/longhorn-engine)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-engine.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-engine?ref=badge_shield)
* Manager: [![Build Status](https://drone-publish.longhorn.io/api/badges/longhorn/longhorn-manager/status.svg)](https://drone-publish.longhorn.io/longhorn/longhorn-manager)[![Go Report Card](https://goreportcard.com/badge/github.com/longhorn/longhorn-manager)](https://goreportcard.com/report/github.com/longhorn/longhorn-manager)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-manager.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-manager?ref=badge_shield)
* Instance Manager: [![Build Status](http://drone-publish.longhorn.io/api/badges/longhorn/longhorn-instance-manager/status.svg)](http://drone-publish.longhorn.io/longhorn/longhorn-instance-manager)[![Go Report Card](https://goreportcard.com/badge/github.com/longhorn/longhorn-instance-manager)](https://goreportcard.com/report/github.com/longhorn/longhorn-instance-manager)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-instance-manager.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-instance-manager?ref=badge_shield)
* Share Manager: [![Build Status](http://drone-publish.longhorn.io/api/badges/longhorn/longhorn-share-manager/status.svg)](http://drone-publish.longhorn.io/longhorn/longhorn-share-manager)[![Go Report Card](https://goreportcard.com/badge/github.com/longhorn/longhorn-share-manager)](https://goreportcard.com/report/github.com/longhorn/longhorn-share-manager)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-share-manager.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-share-manager?ref=badge_shield)
* Backing Image Manager: [![Build Status](http://drone-publish.longhorn.io/api/badges/longhorn/backing-image-manager/status.svg)](http://drone-publish.longhorn.io/longhorn/backing-image-manager)[![Go Report Card](https://goreportcard.com/badge/github.com/longhorn/backing-image-manager)](https://goreportcard.com/report/github.com/longhorn/backing-image-manager)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Fbacking-image-manager.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Fbacking-image-manager?ref=badge_shield)
* UI: [![Build Status](https://drone-publish.longhorn.io/api/badges/longhorn/longhorn-ui/status.svg)](https://drone-publish.longhorn.io/longhorn/longhorn-ui)[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-ui.svg?type=shield)](https://app.fossa.com/projects/custom%2B25850%2Fgithub.com%2Flonghorn%2Flonghorn-ui?ref=badge_shield)
* Test: [![Build Status](http://drone-publish.longhorn.io/api/badges/longhorn/longhorn-tests/status.svg)](http://drone-publish.longhorn.io/longhorn/longhorn-tests)

## Release Status

| Release | Version | Type   |    
|---------|---------|--------|
| 1.3     | 1.3.2   | Stable |
| 1.2     | 1.2.5   | Stable |
| 1.1     | 1.1.3   | Stable |

## Get Involved

### Community Meeting and Office Hours
Hosted by the core maintainers of Longhorn: 4th Friday of the every month at 09:00 (CET) or 16:00 (CST) at https://community.cncf.io/longhorn-community/.

### Longhorn Mailing List
Stay up to date on the latest news and events: https://lists.cncf.io/g/cncf-longhorn

You can read more about the community and its events here: https://github.com/longhorn/community

## Source code

Longhorn is 100% open source software. Project source code is spread across a number of repos:

| Component                      | What it does                                                           | GitHub repo                                                                                 |
| :----------------------------- | :--------------------------------------------------------------------- | :------------------------------------------------------------------------------------------ |
| Longhorn Backing Image Manager | Backing image download, sync, and deletion in a disk                   | [longhorn/backing-image-manager](https://github.com/longhorn/backing-image-manager)         |
| Longhorn Engine                | Core controller/replica logic                                          | [longhorn/longhorn-engine](https://github.com/longhorn/longhorn-engine)                     |
| Longhorn Instance Manager      | Controller/replica instance lifecycle management                       | [longhorn/longhorn-instance-manager](https://github.com/longhorn/longhorn-instance-manager) |
| Longhorn Manager               | Longhorn orchestration, includes CSI driver for Kubernetes             | [longhorn/longhorn-manager](https://github.com/longhorn/longhorn-manager)                   |
| Longhorn Share Manager         | NFS provisioner that exposes Longhorn volumes as ReadWriteMany volumes | [longhorn/longhorn-share-manager](https://github.com/longhorn/longhorn-share-manager)       |
| Longhorn UI                    | The Longhorn dashboard                                                 | [longhorn/longhorn-ui](https://github.com/longhorn/longhorn-ui)                             |

![Longhorn UI](./longhorn-ui.png)

## Requirements

For the installation requirements, refer to the [Longhorn documentation.](https://longhorn.io/docs/latest/deploy/install/#installation-requirements)

## Installation

> **NOTE**: Please note that the master branch is for the upcoming feature release development. 
> For an official release installation or upgrade, please refer to the below ways.

Longhorn can be installed on a Kubernetes cluster in several ways:

- [Rancher catalog app](https://longhorn.io/docs/latest/deploy/install/install-with-rancher/)
- [kubectl](https://longhorn.io/docs/latest/deploy/install/install-with-kubectl/)
- [Helm](https://longhorn.io/docs/latest/deploy/install/install-with-helm/)

## Documentation

The official Longhorn documentation is [here.](https://longhorn.io/docs)

# Community

Longhorn is open source software, so contributions are greatly welcome.
Please read [Code of Conduct](./CODE_OF_CONDUCT.md) and [Contributing Guideline](./CONTRIBUTING.md) before contributing.

Contributing code is not the only way of contributing. We value feedbacks very much and many of the Longhorn features are originated from users' feedback.
If you have any feedbacks, feel free to [file an issue](https://github.com/longhorn/longhorn/issues/new/choose) and talk to the developers at the [CNCF](https://slack.cncf.io/) [#longhorn](https://cloud-native.slack.com/messages/longhorn) Slack channel.

If having any discussion, feedbacks, requests, issues or security reports, please follow below ways.
We also have a [CNCF Slack channel: longhorn](https://cloud-native.slack.com/messages/longhorn) for discussion.

## Discussions or Feedbacks

If having any discussions or feedbacks, feel free to [file a discussion](https://github.com/longhorn/longhorn/discussions).

## Requests or Issues

If having any issues, feel free to [file an issue](https://github.com/longhorn/longhorn/issues/new/choose).
We have a weekly community issue review meeting to review all reported issues or enhancement requests.

When creating a bug issue, please help upload the support bundle to the issue or send to
[longhorn-support-bundle](mailto:longhorn-support-bundle@suse.com).

## Report Vulnerabilities

If having any vulnerabilities found, please report to [longhorn-security](mailto:longhorn-security@suse.com).

# License

Copyright (c) 2014-2021 The Longhorn Authors

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

## Longhorn is a [CNCF Incubating Project](https://www.cncf.io/projects/)

![Longhorn is a CNCF Incubating Project](https://github.com/cncf/artwork/blob/master/other/cncf/horizontal/color/cncf-color.png)
