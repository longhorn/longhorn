# Google Kubernetes Engine

1. GKE clusters must use `Ubuntu` OS instead of `Container-Optimized` OS, in order to satisfy Longhorn `open-iscsi` dependency.

2. GKE requires user to manually claim himself as cluster admin to enable RBAC. Before installing Longhorn, run the following command:

```
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=<name@example.com>

```

where `name@example.com` is the user's account name in GCE, and it's case sensitive. See [this document](https://cloud.google.com/kubernetes-engine/docs/how-to/role-based-access-control) for more information.
