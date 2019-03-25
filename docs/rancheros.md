# Longhorn CSI on RancherOS + RKE

## Requirements
  1. Kubernetes v1.11 or higher.
  2. Longhorn v0.4.1 or higher.
  3. RancherOS Ubuntu console.


## Instruction
### For Kubernetes v1.11 only 
  The following step is not needed for Kubernetes v1.12+.

  Add extra_binds for kubelet in RKE `cluster.yml`:
  ```
   services:
     kubelet:
       extra_binds:
       - "/opt/rke/var/lib/kubelet/plugins:/var/lib/kubelet/plugins" 
   ```
   
### For each node:
  #### 1. Switch to ubuntu console

  `sudo ros console switch ubuntu`, then type `y`

  #### 2. Install open-iscsi for each node. 
  ```
  sudo apt update
  sudo apt install -y open-iscsi
  ```
  #### 3. Modify configuration for iscsi. 
    
  1. Open config file `/etc/iscsi/iscsid.conf`
  2. Comment `iscsid.startup = /bin/systemctl start iscsid.socket`
  3. Uncomment `iscsid.startup = /sbin/iscsid`
    


## Background 
CSI doesn't work with RancherOS + RKE before Longhorn v0.4.1. The reason is:

1. RancherOS sets argument `root-dir=/opt/rke/var/lib/kubelet` for kubelet, , which is different from the default value `/var/lib/kubelet`.
                                                                             
2. **For k8s v1.12+**

     Kubelet will detect the `csi.sock` according to argument `<--kubelet-registration-path>` passed in by Kubernetes CSI driver-registrar, and `<drivername>-reg.sock` (for Longhorn, it's `io.rancher.longhorn-reg.sock`) on kubelet path `<root-dir>/plugins`.
   
   **For k8s v1.11**
   
     Kubelet will find both sockets on kubelet path `/var/lib/kubelet/plugins`.
   
3. By default, Longhorn CSI driver create and expose these 2 sock files on host path `/var/lib/kubelet/plugins`.

4. Then kubelet cannot find `<drivername>-reg.sock`, so CSI driver doesn't work.

5. Furthermore, kubelet will instruct CSI plugin to mount Longhorn volume on `<root-dir>/pods/<pod-name>/volumes/kubernetes.io~csi/<volume-name>/mount`.

   But this path inside CSI plugin container won't be binded mount on host path. And the mount operation for Longhorn volume is meaningless.
   
   Hence Kubernetes cannot connect to Longhorn using CSI driver.

## Reference
https://github.com/kubernetes-csi/driver-registrar
