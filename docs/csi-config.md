# Longhorn CSI on K3S

## Requirements
  1. Kubernetes v1.11 or higher.
  2. Longhorn v0.4.1 or higher.


## Instruction
#### K3S: 
  ##### 1. For Longhorn v0.7.0 and above
  Longhorn v0.7.0 and above support k3s v0.10.0 and above only by default. 
  
  If you want to deploy these new Longhorn versions on versions before k3s v0.10.0, you need to set `--kubelet-root-dir` to `<data-dir>/agent/kubelet` for the Deployment `longhorn-driver-deployer` in `longhorn/deploy/longhorn.yaml`. 
  `data-dir` is a `k3s` arg and it can be set when you launch a k3s server. By default it is `/var/lib/rancher/k3s`.
  
  ##### 2. For Longhorn before v0.7.0
  Longhorn versions before v0.7.0 support k3s below v0.10.0 only by default. 
  
  If you want to deploy these older Longhorn versions on k3s v0.10.0 and above, you need to set `--kubelet-root-dir` to `/var/lib/kubelet` for the Deployment `longhorn-driver-deployer` in `longhorn/deploy/longhorn.yaml`

## Troubleshooting
### Common issues
#### Failed to get arg root-dir: Cannot get kubelet root dir, no related proc for root-dir detection ...

This error is due to Longhorn cannot detect where is the root dir setup for Kubelet, so the CSI plugin installation failed.

User can override the root-dir detection by manually setting argument `kubelet-root-dir` here: 
https://github.com/longhorn/longhorn/blob/master/deploy/longhorn.yaml#L329

**For K3S v0.10.0-**

Run `ps aux | grep k3s` and get argument `--data-dir` or `-d` on k3s server node.

e.g.
```
$ ps uax | grep k3s
root      4160  0.0  0.0  51420  3948 pts/0    S+   00:55   0:00 sudo /usr/local/bin/k3s server --data-dir /opt/test/k3s/data/dir
root      4161 49.0  4.0 259204 164292 pts/0   Sl+  00:55   0:04 /usr/local/bin/k3s server --data-dir /opt/test/k3s/data/dir
``` 
You will find `data-dir` in the cmdline of proc `k3s`. By default it is not set and `/var/lib/rancher/k3s` will be used. Then joining `data-dir` with `/agent/kubelet` you will get the `root-dir`. So the default `root-dir` for K3S is `/var/lib/rancher/k3s/agent/kubelet`.

If K3S is using a configuration file, you would need to check the configuration file to locate the `data-dir` parameter.

**For K3S v0.10.0+**

It is always `/var/lib/kubelet`

## Background 
#### Longhorn versions before v0.7.0 don't work on K3S v0.10.0 or above
K3S now sets its kubelet directory to `/var/lib/kubelet`. See [the K3S release comment](https://github.com/rancher/k3s/releases/tag/v0.10.0) for details.

## Reference
https://github.com/kubernetes-csi/driver-registrar
