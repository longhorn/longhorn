# Talos Linux Support

## Summary

[Talos Linux is not based on X distro](https://www.talos.dev/v1.4/learn-more/philosophy/#not-based-on-x-distro)

>Talos Linux isn’t based on any other distribution. We think of ourselves as being the second-generation of container-optimised operating systems, where things like CoreOS, Flatcar, and Rancher represent the first generation (but the technology is not derived from any of those.)
>
>Talos Linux is actually a ground-up rewrite of the userspace, from PID 1. We run the Linux kernel, but everything downstream of that is our own custom code, written in Go, rigorously-tested, and published as an immutable, integrated image. The Linux kernel launches what we call machined, for instance, not systemd. There is no systemd on our system. There are no GNU utilities, no shell, no SSH, no packages, nothing you could associate with any other distribution.

Currently, Longhorn (at version v1.5.x) does not support Talos Linux as one of the [operating systems (OS)](https://longhorn.io/docs/1.5.0/best-practices/#operating-system) due to reliance on host binaries like BASH and iscsiadm.

The goal of this proposal is to enable Longhorn to be installed and functional on Talos Linux clusters.

### Related Issues

https://github.com/longhorn/longhorn/issues/3161

## Motivation

We have been approached by and observed a number of Talos Linux users who wish to utilize Longhorn. However, the lack of support for Talos Linux prevents them from using Longhorn as their storage solution.

### Goals

The primary goal of this proposal is to introduce support for Talos Linux, allowing users to installed and operate Longhorn on Talos Linux clusters.

### Non-goals [optional]

`None`

## Proposal

Whenever possible, replace host binary dependencies with alternative solutions:
- Develop a common thread namespace switch package that can be utilized by projects requiring interaction with the host. This is necessary due to the absence of GNU utilities in Talos Linux. For example, Longhorn is unable to utilize nsenter and execute binaries in [lockCmd](https://github.com/longhorn/nsfilelock/blob/2315476ea52e13b4112a1cdb930626f8aa848d09/nsfilelock.go#L67-L68).
- Modify the invocation of the `iscsiadm` binary to execute within the `iscsid` process namespace,
- In cases where replacing binary invocations is not feasible, leverage the Talos Linux `kubelet` namespace specifically for Talos Linux. For other operating systems, maintain the existing approach.

### User Stories

As a user running Talos Linux, I want to be able to use Longhorn as my storage solution.

Currently, Longhorn does not support Talos Linux, so I am unable to utilize its features.

With this enhancement, I will be able to install and use Longhorn on my Talos Linux cluster.

### User Experience In Detail

1. Provision a Talos Linux cluster.
1. Apply the required machine configurations to the cluster nodes:
   - Install the iscsi-tool system extension.
   - Install the util-linux system extension.
   - Add the /var/lib/longhorn extra mount.
1. Install Longhorn on the Talos Linux cluster.
1. Once Longhorn is successfully installed, access and utilize Longhorn just like users on other supported operating systems.

### API changes

`None`

## Design

### Thread Namespace Switch

- Create a package in the [longhorn/go-common-lib](https://github.com/longhorn/go-common-libs) repository that can be imported by other projects.
- The targeting function execute within a goroutine and utilize the `unix.Setns` to switch to different namespaces.
- As Golang being a multi-threaded language, to ensure exclusive use of the thread, lock the thread when switching to a different namespace.
- Once the targeting function completes its execution, the thread will switch back to the original namespace and unlock the thread to allow other goroutines to execute.

> The primary goal of this implementation is to replace the usage of GNU utilities with Go-based implementations where applicable, particularly in areas such as file handling.

### Binary Dependencies

#### Isciadm

Longhorn currently assumes that `iscsid` is running on the host. However, in Talos Linux, `iscsid` runs as a Talos extension service in a different namespace.

To address this, modify the `iscsiadm` binary invocation to execute within the `iscsid` namespace using `nsenter`.

#### fstrim

~Instead of rewriting the `fstrim` binary dependency, leverage the existing `fstrim` binary within the `kubelet` namespace. However, considering that the `kubelet` namespace might not be present in other operating systems, Longhorn needs to switch to the host namespace to retrieve the OS distribution and determine if it is a Talos Linux. If the host is identified as Talos Linux, Longhorn can then switch to the `kubelet` namespace to utilize the existing `fstrim` binary.~

Keep the binary execution in the host namespace, following a discussion with @frezbo from @siderolabs. The Talos team has proposed an approach to include the fstrim in the host as part of `util-linux` extension.

#### cryptsetup

Keep the current implementation of the binary execution in the host namespace, as the `cryptsetup` binary comes [pre-installed](https://github.com/siderolabs/pkgs/blob/release-1.4/Makefile#L40) in Talos Linux, for the [Disk Encryption](https://www.talos.dev/v1.4/talos-guides/configuration/disk-encryption/).

### Project Adpaptions

- Replace the `nsenter` path with the `iscsid` proc path when invoking `iscsiadm` binary.
- Replace the `nsenter` path with the `kubelet` proc path when invoking other dependency binaries. This change will be applied only if the operating system distribution is identified as Talos Linux, as other distributions may not have a running `kubelet` process.
- For binary invocations are not part of the [binary dependencies](#binary-dependencies), replace them with appropriate Golang libraries.
- Utilize the [thread namespace switch implementation](#thread-namespace-switch) to handle the necessary namespace switching when interacting with the host.

### Test plan

1. Update existing test cases that rely on `nsenter` to either correct the namespace or replace them with appropriate Python libraries.
1. Perform regression testing by running existing test cases to ensure that no regressions are introduced.
1. Introduce a new pipeline for testing Longhorn on Talos Linux clusters in https://ci.longhorn.io/.

### Upgrade strategy

`None`

## Note [optional]

`None`
