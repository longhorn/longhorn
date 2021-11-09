# Longhorn CRD Chart

> **Important**: Please install the Longhorn CRD chart in the `longhorn-system` namespace only.

> **Warning**: Longhorn doesn't support downgrading from a higher version to a lower version.

## Installation
1. Add Longhorn CRD chart repository.
```
helm repo add longhorn https://charts.longhorn.io
```

2. Update local Longhorn CRD chart information from chart repository.
```
helm repo update
```

3. Install Longhorn CRD chart.
- With Helm 2, the following command will create the `longhorn-system` namespace and install the Longhorn CRD chart together.
```
helm install longhorn/longhorn --name longhorn-crd --namespace longhorn-system
```
- With Helm 3, the following command will create the `longhorn-system` namespace and install the Longhorn CRD chart together.
```
helm install longhorn-crd longhorn/longhorn --namespace longhorn-system --create-namespace
```

## Uninstallation

With Helm 2 to uninstall Longhorn CRD.
```
helm delete longhorn-crd --purge
```

With Helm 3 to uninstall Longhorn CRD.
```
helm uninstall longhorn-crd -n longhorn-system
kubectl delete namespace longhorn-system
```

---
Please see [link](https://github.com/longhorn/longhorn) for more information.
