# iSCSI support

Longhorn supports iSCSI target frontend mode. The user can connect to it
through any iSCSI client, including open-iscsi, and virtual machine
hypervisor like KVM, as long as it's in the same network with the Longhorn system.

Longhorn Driver (CSI/Flexvolume) doesn't support iSCSI mode.

To start volume with iSCSI target frontend mode, select `iSCSI` as the frontend
when creating the volume. After volume has been attached, the user will see
something like following in the `endpoint` field:

```
iscsi://10.42.0.21:3260/iqn.2014-09.com.rancher:testvolume/1
```

Here:
1. The IP and port is `10.42.0.21:3260`.
2. The target name is `iqn.2014-09.com.rancher:testvolume`. `testvolume` is the
   name of the volume.
3. The LUN number is 1. Longhorn always uses LUN 1.

Then user can use above information to connect to the iSCSI target provided by
Longhorn using an iSCSI client.
