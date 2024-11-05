# Title

RWX Resize

## Summary

Expansion of volumes requires resizing the filesystem inside the block device /dev/longhorn/\<volume\> after the block device is grown.  In the case of an RWX volume, that is on the node where the share-manager pod has it mounted.  But the CSI layer sends the `NodeExpandVolume` RPC request to the CSI plugin on the node(s) where the volume is attached, which might not include the mount node.  If it doesn't, the resize does not take effect.

This enhancement is meant to ensure that the CSI request or some equivalent is forwarded to the share-manager node.

### Related Issues

[BUG] RWX expansion fails. Fail to resize RWX PVC at filesystem resizing step [#9736](https://github.com/longhorn/longhorn/issues/9736)

## Motivation

### Goals

Resize of RWX volume should succeed regardless of location of share-manager and workload pods.

This should also take care of the manual resize step documented in https://longhorn.io/docs/1.7.2/nodes-and-volumes/volumes/expansion/#rwx-volume, and allow fully automated expansion of RWX volumes without scale-down, resolving `[FEATURE] Automatic online RWX volume expansion` [#8118](https://github.com/longhorn/longhorn/issues/8118)

### Non-goals [optional]

## Proposal

A csi-plugin can detect that the device path does not exist locally.  But it doesn't really have to, because it can tell that the volume is RWX.  It can delegate the resize to the owning share manager in all cases, even on the local node.

Implement a "FilesystemResize" RPC call in the share-manager, much like its "FilesystemTrim", and let the csi-plugin refer the resize action to it.

### User Stories

There's no extra work for the user.  In fact, this should make an existing feature easier to use.  However, the user must have restarted the share-manager pod after upgrade to the release with this feature, to get an image that supports the RPC call.

### API changes

- Add a FilesystemResize method to share-manager RPC protocol

### Alternatives

It might be tempting to find a way to forward the request to the longhorn-csi-plugin on the correct node.

If we handle the expansion in share manager we must:
 1. re-implement the logic
 2. restart the share-manager to have new logic  

If we could handle the expansion by forwarding to correct csi-plugin, we would need to:
 1. figure out how make csi-plugin act as a CSI RPC client and forward the request payload
 2. OR send some other message, and allow csi-plugin to have kubectl client so it can fetch the secret passphrase for crypto resize (see below)
 3. restart the csi-plugin, which happens automatically on upgrade

Unfortunately, that won't work.  The csi-plugin has no idea of the actual filesystem type.  The fields of the `NodeExpandVolume` request are derived from the mount it knows about.  On the csi-plugin pod, `mount -l` shows
```
10.43.248.207:/pvc-8d1d3f46-76b6-484e-9a3a-93cc821ffd5b on /var/lib/kubelet/plugins/kubernetes.io/csi/driver.longhorn.io/46e93d5a9308ccb4b10edb9f7d2e362f5e6f45f125927196166405a669c36d2b/globalmount type nfs4 (rw,relatime,vers=4.1,rsize=1048576,wsize=1048576,namlen=255,softerr,softreval,noresvport,proto=tcp,timeo=600,retrans=5,sec=sys,clientaddr=24.144.89.5,local_lock=none,addr=10.43.248.207)
10.43.248.207:/pvc-8d1d3f46-76b6-484e-9a3a-93cc821ffd5b on /var/lib/kubelet/pods/44f0a9cc-6995-4fa9-a914-ca0748793315/volumes/kubernetes.io~csi/pvc-8d1d3f46-76b6-484e-9a3a-93cc821ffd5b/mount type nfs4 (rw,relatime,vers=4.1,rsize=1048576,wsize=1048576,namlen=255,softerr,softreval,noresvport,proto=tcp,timeo=600,retrans=5,sec=sys,clientaddr=24.144.89.5,local_lock=none,addr=10.43.248.207)
```

If asked to do a `xfs_growfs` on `/var/lib/kubelet/...` it will fail with 
```
could not find block size of device /var/lib/kubelet/plugins...
``` 

Only on the share-manager pod can we find the right mount path and filesystem type:
```
/dev/longhorn/pvc-8d1d3f46-76b6-484e-9a3a-93cc821ffd5b on /export/pvc-8d1d3f46-76b6-484e-9a3a-93cc821ffd5b type ext4 (rw,relatime)
```

We need the mount point to do resize through `ResizeFs.Resize`, which takes both the device path and the mount path: https://github.com/kubernetes/mount-utils/blob/e448c96afa03f6e2556117ed7ce7dee0462fa3ca/resizefs_linux.go#L46-L68

Specifically, that's because it knows that while resize2fs can operate on either one, xfs_growfs requires the mount path:
```go
	klog.V(3).Infof("ResizeFS.Resize - Expanding mounted volume %s", devicePath)
	switch format {
	case "ext3", "ext4":
		return resizefs.extResize(devicePath)
	case "xfs":
		return resizefs.xfsResize(deviceMountPath)
	case "btrfs":
		return resizefs.btrfsResize(deviceMountPath)
	}
	return false, fmt.Errorf("ResizeFS.Resize - resize of format %s is not supported for device %s mounted at %s", format, devicePath, deviceMountPath)"
```

If we try to use `xfs_growfs` on the device,
```
longhorn-csi-plugin-pt7cj:/ #  xfs_growfs /dev/longhorn/pvc-8d1d3f46-76b6-484e-9a3a-93cc821ffd5b 
xfs_growfs: /dev/longhorn/pvc-8d1d3f46-76b6-484e-9a3a-93cc821ffd5b is not a mounted XFS filesystem
```

## Design

### Implementation Overview

The code in [longhorn-manager/csi/node-handler.go](https://github.com/longhorn/longhorn-manager/blob/235b1ae23f6ad4d26dc56063c95358145e937c09/csi/node_server.go#L732-L793) needs to be duplicated in the share-manager RPC server.  That boils down to 
  - construct the device path
  - resize the crypto device, if encrypted
  - resize the filesystem 

Crypto resize requires the passphrase, which is part of the `NodeExpandVolume` CSI request payload. But because the share-manager does the work, there is no need to send the passphrase over the wire to it.  Share-manager already knows the crypto details from when its pod was created.  It also knows the volume, too, so the new `FilesystemResize` method in its RPC server doesn't need any parameters at all.

How does the request get sent to the share-manager?  The longhorn-csi-plugin pod will make a gRPC call directly to share manager pod to run the filesystem resize command.  For that, the csi-plugin needs to get a kubectl client to look up the pod for the associated share manager, and then also a share-manager RPC client.

- What about multiple csi-plugin pods all forwarding to the one recipient? Is that a problem?  
  Likely not.  The resize should be idempotent.  In fact, before calling `resizer.Resize`, the code checks `resizer.NeedsResize` and every instance after the first should just return.

### Test plan

See steps to reproduce in the Github issue https://github.com/longhorn/longhorn/issues/9736.  

### Upgrade strategy

Any change to the share-manager pod requires a pod restart after upgrade to pick up the new image.  That can be done at the user's convenience, but the new functionality won't be available until then.  That should be documented in the release notes.

If a FilesystemResize RPC is sent to an older share-manager, it will result in a "not implemented" error.  The client should catch that, and append additional error text noting that it will be necessary to scale the workload down and then up again for the resize to take place.  That will have the effect of upgrading the share-manager image as well, so any subsequent expansion of the volume can be done with the workload online.  Only the first one is disruptive.

## Note [optional]

*Additional notes.*
