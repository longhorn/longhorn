# Support Bundle Enhancement

## Summary

This feature replaces the support bundle mechanism with the general purpose [support bundle kit](https://github.com/rancher/support-bundle-kit).

Currently, the Longhorn support bundle file is hard to understand, and analyzing it is difficult.

With the new support bundle, the user can simulate a mocked Kubernetes cluster that is interactable with `kubectl`. Hence makes the analyzing process more intuitive.


### Related Issues

https://github.com/longhorn/longhorn/issues/2759

## Motivation

### Goals

- Replace the Longhorn support-bundle generation mechanism with the support bundle manager.
- Keep the same support bundle HTTP API endpoints.
- Executing the` support-bundle-kit simulator` on the support bundle can start a mocked Kubernetes API server that is interactable using `kubectl`.
- Introduce a new `support-bundle-manager-image` setting for easy support-bundle manager image replacement.
- Introduce a new `support-bundle-failed-history-limit` setting to avoid unexpected increase of failed support bundles.

### Non-goals [optional]

`None`

## Proposal

- Introduce the new `SupportBundle` custom resource definition.
  - Creating a new custom resource triggers the creation of a support bundle manager deployment. The support-bundle manager is responsible for support bundle collection and exposes it to `https://<ip>:8080/bundle`.
  - Deleting the SupportBundle custom resource deletes its owning support bundle manager deployment.

- Introduce a new `longhorn-support-bundle` controller.
  - Responsible for SupportBundle custom resource status updates and event recordings.
  - [The controller reacts in phases based on the SupportBundle state.](#manager-supportbundle-creation-handling-in-longhorn-support-bundle-controller)
  - Responsible for cleaning up the support bundle manager deployment when the owner `SupportBundle` custom resource is tagged for deletion.

- There is no change to the HTTP API endpoints. This feature replaces the handler function logic.

- Introduce a new `longhorn-support-bundle` service account with `cluster-admin` access. The current `longhorn-service-account` service account cannot generate the following resources.
  ```
  Failed to get /api/v1/componentstatuses
  Failed to get /apis/authentication.k8s.io/v1/tokenreviews
  Failed to get /apis/authorization.k8s.io/v1/selfsubjectrulesreviews
  Failed to get /apis/authorization.k8s.io/v1/subjectaccessreviews
  Failed to get /apis/authorization.k8s.io/v1/selfsubjectaccessreviews
  Failed to get /apis/certificates.k8s.io/v1/certificatesigningrequests
  Failed to get /apis/networking.k8s.io/v1/ingressclasses
  Failed to get /apis/policy/v1beta1/podsecuritypolicies
  Failed to get /apis/rbac.authorization.k8s.io/v1/clusterroles
  Failed to get /apis/rbac.authorization.k8s.io/v1/clusterrolebindings
  Failed to get /apis/node.k8s.io/v1/runtimeclasses
  Failed to get /apis/flowcontrol.apiserver.k8s.io/v1beta1/prioritylevelconfigurations
  Failed to get /apis/flowcontrol.apiserver.k8s.io/v1beta1/flowschemas
  Failed to get /api/v1/namespaces/default/replicationcontrollers
  Failed to get /api/v1/namespaces/default/bindings
  Failed to get /api/v1/namespaces/default/serviceaccounts
  Failed to get /api/v1/namespaces/default/resourcequotas
  Failed to get /api/v1/namespaces/default/limitranges
  Failed to get /api/v1/namespaces/default/podtemplates
  Failed to get /apis/apps/v1/namespaces/default/replicasets
  Failed to get /apis/apps/v1/namespaces/default/controllerrevisions
  Failed to get /apis/events.k8s.io/v1/namespaces/default/events
  Failed to get /apis/authorization.k8s.io/v1/namespaces/default/localsubjectaccessreviews
  Failed to get /apis/autoscaling/v1/namespaces/default/horizontalpodautoscalers
  Failed to get /apis/networking.k8s.io/v1/namespaces/default/ingresses
  Failed to get /apis/networking.k8s.io/v1/namespaces/default/networkpolicies
  Failed to get /apis/rbac.authorization.k8s.io/v1/namespaces/default/rolebindings
  Failed to get /apis/rbac.authorization.k8s.io/v1/namespaces/default/roles
  Failed to get /apis/storage.k8s.io/v1beta1/namespaces/default/csistoragecapacities
  Failed to get /apis/discovery.k8s.io/v1/namespaces/default/endpointslices
  Failed to get /apis/helm.cattle.io/v1/namespaces/default/helmcharts
  Failed to get /apis/helm.cattle.io/v1/namespaces/default/helmchartconfigs
  Failed to get /apis/k3s.cattle.io/v1/namespaces/default/addons
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/default/ingressroutetcps
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/default/ingressroutes
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/default/serverstransports
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/default/traefikservices
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/default/middlewaretcps
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/default/middlewares
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/default/tlsstores
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/default/tlsoptions
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/default/ingressrouteudps
  Failed to get /api/v1/namespaces/kube-system/bindings
  Failed to get /api/v1/namespaces/kube-system/resourcequotas
  Failed to get /api/v1/namespaces/kube-system/serviceaccounts
  Failed to get /api/v1/namespaces/kube-system/podtemplates
  Failed to get /api/v1/namespaces/kube-system/limitranges
  Failed to get /api/v1/namespaces/kube-system/replicationcontrollers
  Failed to get /apis/apps/v1/namespaces/kube-system/controllerrevisions
  Failed to get /apis/apps/v1/namespaces/kube-system/replicasets
  Failed to get /apis/events.k8s.io/v1/namespaces/kube-system/events
  Failed to get /apis/authorization.k8s.io/v1/namespaces/kube-system/localsubjectaccessreviews
  Failed to get /apis/autoscaling/v1/namespaces/kube-system/horizontalpodautoscalers
  Failed to get /apis/networking.k8s.io/v1/namespaces/kube-system/networkpolicies
  Failed to get /apis/networking.k8s.io/v1/namespaces/kube-system/ingresses
  Failed to get /apis/rbac.authorization.k8s.io/v1/namespaces/kube-system/rolebindings
  Failed to get /apis/rbac.authorization.k8s.io/v1/namespaces/kube-system/roles
  Failed to get /apis/storage.k8s.io/v1beta1/namespaces/kube-system/csistoragecapacities
  Failed to get /apis/discovery.k8s.io/v1/namespaces/kube-system/endpointslices
  Failed to get /apis/helm.cattle.io/v1/namespaces/kube-system/helmchartconfigs
  Failed to get /apis/helm.cattle.io/v1/namespaces/kube-system/helmcharts
  Failed to get /apis/k3s.cattle.io/v1/namespaces/kube-system/addons
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/kube-system/serverstransports
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/kube-system/middlewaretcps
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/kube-system/middlewares
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/kube-system/tlsstores
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/kube-system/ingressrouteudps
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/kube-system/ingressroutes
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/kube-system/ingressroutetcps
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/kube-system/traefikservices
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/kube-system/tlsoptions
  Failed to get /api/v1/namespaces/cattle-system/limitranges
  Failed to get /api/v1/namespaces/cattle-system/podtemplates
  Failed to get /api/v1/namespaces/cattle-system/resourcequotas
  Failed to get /api/v1/namespaces/cattle-system/serviceaccounts
  Failed to get /api/v1/namespaces/cattle-system/replicationcontrollers
  Failed to get /api/v1/namespaces/cattle-system/bindings
  Failed to get /apis/apps/v1/namespaces/cattle-system/replicasets
  Failed to get /apis/apps/v1/namespaces/cattle-system/controllerrevisions
  Failed to get /apis/events.k8s.io/v1/namespaces/cattle-system/events
  Failed to get /apis/authorization.k8s.io/v1/namespaces/cattle-system/localsubjectaccessreviews
  Failed to get /apis/autoscaling/v1/namespaces/cattle-system/horizontalpodautoscalers
  Failed to get /apis/networking.k8s.io/v1/namespaces/cattle-system/networkpolicies
  Failed to get /apis/networking.k8s.io/v1/namespaces/cattle-system/ingresses
  Failed to get /apis/rbac.authorization.k8s.io/v1/namespaces/cattle-system/roles
  Failed to get /apis/rbac.authorization.k8s.io/v1/namespaces/cattle-system/rolebindings
  Failed to get /apis/storage.k8s.io/v1beta1/namespaces/cattle-system/csistoragecapacities
  Failed to get /apis/discovery.k8s.io/v1/namespaces/cattle-system/endpointslices
  Failed to get /apis/helm.cattle.io/v1/namespaces/cattle-system/helmchartconfigs
  Failed to get /apis/helm.cattle.io/v1/namespaces/cattle-system/helmcharts
  Failed to get /apis/k3s.cattle.io/v1/namespaces/cattle-system/addons
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/cattle-system/tlsoptions
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/cattle-system/traefikservices
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/cattle-system/middlewares
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/cattle-system/ingressroutetcps
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/cattle-system/serverstransports
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/cattle-system/ingressroutes
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/cattle-system/middlewaretcps
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/cattle-system/tlsstores
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/cattle-system/ingressrouteudps
  Failed to get /api/v1/namespaces/longhorn-system/limitranges
  Failed to get /api/v1/namespaces/longhorn-system/podtemplates
  Failed to get /api/v1/namespaces/longhorn-system/resourcequotas
  Failed to get /api/v1/namespaces/longhorn-system/replicationcontrollers
  Failed to get /api/v1/namespaces/longhorn-system/serviceaccounts
  Failed to get /api/v1/namespaces/longhorn-system/bindings
  Failed to get /apis/apps/v1/namespaces/longhorn-system/replicasets
  Failed to get /apis/apps/v1/namespaces/longhorn-system/controllerrevisions
  Failed to get /apis/events.k8s.io/v1/namespaces/longhorn-system/events
  Failed to get /apis/authorization.k8s.io/v1/namespaces/longhorn-system/localsubjectaccessreviews
  Failed to get /apis/autoscaling/v1/namespaces/longhorn-system/horizontalpodautoscalers
  Failed to get /apis/networking.k8s.io/v1/namespaces/longhorn-system/ingresses
  Failed to get /apis/networking.k8s.io/v1/namespaces/longhorn-system/networkpolicies
  Failed to get /apis/rbac.authorization.k8s.io/v1/namespaces/longhorn-system/rolebindings
  Failed to get /apis/rbac.authorization.k8s.io/v1/namespaces/longhorn-system/roles
  Failed to get /apis/storage.k8s.io/v1beta1/namespaces/longhorn-system/csistoragecapacities
  Failed to get /apis/discovery.k8s.io/v1/namespaces/longhorn-system/endpointslices
  Failed to get /apis/helm.cattle.io/v1/namespaces/longhorn-system/helmchartconfigs
  Failed to get /apis/helm.cattle.io/v1/namespaces/longhorn-system/helmcharts
  Failed to get /apis/k3s.cattle.io/v1/namespaces/longhorn-system/addons
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/longhorn-system/serverstransports
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/longhorn-system/ingressroutes
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/longhorn-system/tlsstores
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/longhorn-system/traefikservices
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/longhorn-system/tlsoptions
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/longhorn-system/middlewares
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/longhorn-system/ingressroutetcps
  Failed to get /apis/traefik.containo.us/v1alpha1/namespaces/longhorn-system/middlewaretcps
  ```

### User Stories

#### Support Bundle Generation

This feature does not alter how the user generates the support bundle on UI.

#### Mocking Support Bundle Cluster

The user can simulate a mocked cluster with the support bundle and interact using `kubectl`.

### User Experience In Detail

#### Support Bundle Generation

1. User clicks `Generate Support BundleFile` in Longhorn UI.
  1. Longhorn creates a `SupportBundle` custom resource.
  1. Longhorn creates a support bundle manager deployment.
1. User downloads the support bundle as same as before.
  1. Longhorn deletes the `SupportBundle` custom resource.
  1. Longhorn deletes the support bundle manager deployment.

#### Support Bundle Generation Failed

1. User clicks `Generate Support BundleFile` in Longhorn UI.
  1. Longhorn creates a SupportBundle custom resource.
  1. Longhorn creates a support bundle manager deployment.
1. The SupportBundle goes into an error state.
1. User sees an error on UI. 
  1. Longhorn retains the failed SupportBundle and its support-bundle manager deployment.
1. User analyzes the failed SupportBundle on the cluster. Or generate a new support bundle so the failed SupportBundle can be analyzed off-site.
1. User deletes the failed SupportBundle when done with the analysis. Or have Longhorn automatically purge all failed SupportBundles by setting [support bundle failed history limit](#manager-support-bundle-failed-history-limit-setting) to 0.
  1. Longhorn deletes the SupportBundle custom resource.
  1. Longhorn deletes the support bundle manager deployment.


### API changes

#### Longhorn manager HTTP API

There will be no change to the HTTP API endpoints. This feature replaces the handler function logic.

| Method   | Path                                              | Description                                           |
| -------- | ------------------------------------------------- | ----------------------------------------------------- |
| **POST** | `/v1/supportbundles`                              | Creates SupportBundle custom resource                 |
| **GET**  | `/v1/supportbundles/{name}/{bundleName}`          | Get the support bundle details from the SuppotBundle custom resource |
| **GET**  | `/v1/supportbundles/{name}/{bundleName}/download` | Get the support bundle file from `https://<support-bundle-manager-ip>:8080/bundle` |


## Design

### Implementation Overview

#### Deployment: longhorn-support-bundle service account

Collecting the support bundle requires complete cluster access. Hence Longhorn will have a service account dedicated at deployment.

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: longhorn-support-bundle
  namespace: longhorn-system

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: longhorn-support-bundle
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: longhorn-support-bundle
  namespace: longhorn-system

---
```

#### Manager: HTTP API SupportBundle resource

```go
type SupportBundle struct {
	client.Resource
	NodeID             string                      `json:"nodeID"`
	State              longhorn.SupportBundleState `json:"state"`
	Name               string                      `json:"name"`
	ErrorMessage       string                      `json:"errorMessage"`
	ProgressPercentage int                         `json:"progressPercentage"`
}
```

#### Manager: POST `/v1/supportbundles`

- Creates a new `SupportBundle` custom resource.

#### Manager: GET `/v1/supportbundles/{name}/{bundleName}`

- Gets the `SupportBundle` custom resource and returns [SupportBundle resource](#manager-http-api-supportbundle-resource).

#### Manager: GET `/v1/supportbundles/{name}/{bundleName}/download`

1. Get the support bundle from [https://\<support-bundle-manager-ip>:8080/bundle](https://github.com/rancher/support-bundle-kit/blob/master/pkg/manager/httpserver.go#L104).
1. Copy the support bundle to the response writer.
1. Delete the `SupportBundle` custom resource.

#### Manager: SupportBundle custom resource

```yaml
apiVersion: v1
items:
- apiVersion: longhorn.io/v1beta2
  kind: SupportBundle
  metadata:
    creationTimestamp: "2022-11-10T02:35:45Z"
    generation: 1
    name: support-bundle-2022-11-10t02-35-45z
    namespace: longhorn-system
    resourceVersion: "97016"
    uid: a5169448-a6e5-4637-b99a-63b9a9ea0b7f
  spec:
    description: "123"
    issueURL: ""
    nodeID: ""
  status:
    conditions:
    - lastProbeTime: ""
      lastTransitionTime: "2022-11-10T03:35:29Z"
      message: done
      reason: Create
      status: "True"
      type: Manager
    filename: supportbundle_08ccc085-641c-4592-bb57-e05456241204_2022-11-10T02-36-13Z.zip
    filesize: 502608
    image: rancher/support-bundle-kit:master-head
    managerIP: 10.42.2.54
    ownerID: ip-10-0-1-113
    progress: 100
    state: ReadyForDownload
kind: List
metadata:master-head
  resourceVersion: ""
```

#### Manager: `support-bundle-manager-image` setting

The support bundle manager image for the support bundle generation.

```
Category = general
Type     = string
Default  = rancher/support-bundle-kit:master-head
```

#### Manager `support-bundle-failed-history-limit` setting

This setting specifies how many failed support bundles can exist in the cluster.

The retained failed support bundle is for analysis purposes and needs to clean up manually. Set this value to 0 to have Longhorn automatically purge all failed support bundles.

```
Category = general
Type     = integer
Default  = 1
```

#### Manager: validate at SupportBundle creation

1. Block creation if the number of failed SupportBundle exceeds the [support bundle failed history limit](#manager-support-bundle-failed-history-limit-setting).
1. Block creation if there is another SupportBundle is in progress. However, skip checking the SupportBundle that is in an error state. We will leave the user to decide what to do with the failed SupportBundles.

#### Manager: mutate at SupportBundle creation

1. Add finalizer.
#### Manager: SupportBundle creation handling in longhorn-support-bundle controller

This controller handles the support bundle in phases depending on its custom resource state.

At the end of each phase will update the SupportBundle custom resource state and then returns the queue. The controller picks up the update and enqueues again for the next phase. 

When there is no state update, the controller automatically queues the handling custom resource until the state reaches `ReadyForDownload` or `Error`.

**State: None("")** 
- Update the custom resource image with the setting value.
- Update the custom resource state to `Started`.

**State: Started**
- Update the state to `Generating` when the support bundle manager deployment exists.
- Create support bundle manager deployment and requeue this phase to check support bundle manager deployment.

**State: Generating**
- Update the [SupportBundle](#manager-supportbundle-custom-resource) status base on the support manager [https://\<support-bundle-manager-ip>:8080/status](https://github.com/rancher/support-bundle-kit/blob/master/pkg/manager/httpserver.go#L103):
  - IP
  - file name
  - progress
  - filesize
- Update the custom resource state to `ReadyForDownload` when progress reached 100.

#### Manager: SupportBundle error handling in longhorn-support-bundle controller

- Update the state to `Error` and record the error type condition when the phase encounters unexpected failure.
- When the [support bundle failed history limit](#manager-support-bundle-failed-history-limit-setting) is 0, update the state to `Purging`.

**Purging**
- Delete all failed SupportBundles in the state `Error`.

#### Manager: SupportBundle deletion handling in longhorn-support-bundle controller

When the SupportBundle gets marked with `DeletionTimestamp`, the controller updated its state to `Deleting`.

**Deleting**
- Delete its support bundle manager deployment.
- Remove the SupportBundle finalizer.

#### Manager: SupportBundle purge handling in longhorn-setting controller

- If the [support bundle failed history limit](#manager-support-bundle-failed-history-limit-setting) is 0, update all failed SupportBundle state to `Purging`.

### Test plan

- Test support bundle generation should be successful.
- Test support bundle should be cleaned up after download.
- Test support bundle should retain when generation failed.
- Test support bundle should generate when the cluster has an existing `SupportBundle` in an error state.
- Test support bundle should purge when `support bundle failed history limit` is set to 0.
- Test support bundle cluster simulation.

### Upgrade strategy

`None`

## Note [optional]

`None`
