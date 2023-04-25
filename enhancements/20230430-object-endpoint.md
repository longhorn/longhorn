# Object Support for Longhorn

## Summary

By integrating s3gw with Longhorn, we are able to provide an S3-compatible,
Object API to clients consuming Longhorn volumes. This is achieved by creating
an Object endpoint (using s3gw) for a Longhorn volume.

### Related Issues

https://github.com/longhorn/longhorn/issues/4154


## Motivation

### Goals

* Provide an Object endpoint associated with a Longhorn volume, providing an
  S3-compatible API.
* Multiple Object endpoints should be supported, with each endpoint being backed
  by one single Longhorn volume.


### Non-goals

* Integration of s3gw UI for administration and management purposes. Such an
  Enhancement Proposal should be a standalone LEP by its own right.
* Providing Object endpoints for multiple volumes. In this proposal we limit one
  object endpoint per Longhorn volume (see longhorn/longhorn#5444).
* Multiple Object endpoints for a single volume, either in Read-Write Many, or
  as active/passive for HA failover. While we believe it to be of the utmost
  importance, we are considering it future work that should be addressed in its
  own LEP.
* Specify how COSI can be implemented for Longhorn and s3gw. This too should be
  addressed in a specific LEP.


## Proposal

### User Stories

#### Story

Currently, Longhorn does not support object storage. Should the user want to use
their Longhorn cluster for object storage, they have to rely on third-party
applications.

Instead we propose to enhance the user experience by allowing a Longhorn volume
to be presented to the user as an object storage endpoint, without having the
user to install additional dependencies or manage different applications.

### User Experience In Detail

* A new page view exists specifically for "Object Endpoints"
    * Within this page there is a "Create" button, and a list of existing
      Object Endpoints.
* The user clicks on "Create"
* A modal dialog is shown, with the various Object Endpoint related fields
* User specifies the endpoint name
* User specifies their username and password combination for the administrator
  user
    * This can, potentially, be randomly generated as well.
* For publicly accessible endpoints, the user must specify a domain name to be
  used
* The user must provide SSL certificates to be used by the endpoint
* Then the user clicks "Ok"

### API changes

The API will need a new endpoint to create an object endpoint, as well as
listing, updating, and deleting them. We believe it's not reasonable to reuse
the existing `/v1/volumes` API endpoints, given they are semantically distinct
from what we are trying to achieve.

We thus propose the creation of a `/v1/endpoint/object` API endpoint. This route
could also be `/v1/object-endpoint`, but we believe that by having a
`/v1/endpoint/...` route we can potentially future proof the API in case other
endpoint types (not just object) are eventually added.


## Design

### Implementation Overview

Integrating Longhorn with s3gw will require the creation of mechanisms that
allow us to 1) describe an object endpoint; 2) deploy an `s3gw` pod consuming
a volume; and 3) deploy an `s3gw-ui` pod for management and administration. For
the purposes of this LEP, there will always be one single `s3gw-ui` pod
associated with an `s3gw` service, hence one `s3gw-ui` pod per Object Endpoint.
We do not exclude eventually allowing one single `s3gw-ui` pod being associated
with multiple Object Endpoints, but that should be considered as future work.

We believe we will need a new Custom Resource Definition, `ObjectEndpoint`,
representing an Object Endpoint deployment, containing information that will be
required to deploy an `s3gw` endpoint, as well as the `s3gw-ui` administration
interface.

Given we need backing storage for each `s3gw` instance, we will rely on
Persistent Volume Claims to request storage from the Longhorn cluster. This
allows us to abstract ourselves from volume creation, and rely on existing
Kubernetes infrastructure to provide us with the needed resources.

An `ObjectEndpointController` will also be necessary, responsible for creating
and managing `s3gw` pods, both the `s3gw` endpoint and the `s3gw-ui`. This
controller will be listening for new resources of type `objectendpoint`, and
will create the necessary bits for proper deployment, including services and
pods.

#### Custom Resource Definition

We define a new Object Endpoint Custom Resource Definition, as follows:

```golang
type ObjectEndpoint struct {
    metav1.TypeMeta
    metav1.ObjectMeta

    Spec    ObjectEndpointSpec
    Status  ObjectEndpointStatus
}
```

The endpoint `Spec`, as follows, contains the information that we consider most
relevant to the endpoint at this point. More information may be added should the
need arise.

```golang
type ObjectEndpointSpec struct {
    Credentials     ObjectEndpointCredentials
    StorageClass    string
    Size            resource.Quantity
}
```

The `Credentials` field, as defined below, contains the access and secret keys
that are to be used as seed credentials for the object endpoint. We need these
to set the credentials for the default administrator user.

The `StorageClass` field contains the name of the Storage Class to be used when
obtaining a new volume to back the `s3gw` service. This needs to be specified by
the user with an existing Storage Class; alternatively the default Storage Class
will be used.

The `Size` field represents the initial size to provision for the new volume.

```golang
type ObjectEndpointCredentials struct {
    AccessKey   string
    SecretKey   string
}
```

The Object Endpoint CRD also contains a `Status` field, represented below. This
tracks the state of the object endpoint as observed by the object endpoint controller.

```golang
type ObjectEndpointStatus struct {
    State       ObjectEndpointState
    Endpoint    string
}

type ObjectEndpointState string
```

The `State` field can have one of the following values: `unknown`, `starting`,
`running`, `stopping`, or `error`. The state machine begins at `unknown`, and
moves to `starting` once the new object endpoint is detected and resource
creation begins. Once all resources have been created, the controller then moves
the state to `running`, and remains there until the object endpoint is deleted,
at which point the controller moves the state to `stopping` while waiting for
the associated resources to be cleaned up. The state `error` means something
went wrong.


#### The Object Endpoint Controller

The Object Endpoint Controller will be responsible for lifecycle management of
Object Endpoints, from creation to their deletion.

To a large extent, the vast majority of the logic of the controller will be in
creating resources, or handling the `starting` and `stopping` states discussed
before.

When the Object Endpoint is created, the required resources will need to be
created. These include,

* `Service` associated with the pods being deployed
* Various `Secret` and `ConfigMap` needed by `s3gw` and `s3gw-ui`
* The associated `Deployment`
* A `Persistent Volume Claim` required for `s3gw` storage.

During resource creation we will also need to explicitly create a
`Persitent Volume` that will be bound to the `Persistent Volume Claim` mentioned
above. We need to do this so we can opinionate on the file system being used; in
this case, XFS, which `s3gw` requires for performance reasons.

While handling `starting`, the resources required to have already been created
through the Kubernetes API, but the controller still has to wait for them to be
ready and healthy before the transition to `running` can be performed.
Coincidentally, this is also the behavior expected when the endpoint is in state
`error`, given the controller will need to wait for resources to be healthy
before being able to move the endpoint to state `running`.

In turn, handling `stopping` means waiting for those same resources to be
removed.


#### Required changes

Aside from what has been discussed previously, we believe we need to add two new
options as arguments to `longhorn-manager`: `--object-endpoint-image`, and
`--object-endpoint-ui-image`, both expecting their corresponding image names.
These will be essential for us to be able to spin up the pods for the object
endpoints being deployed.

Additionally, we will require to add the new `ObjectEndpointController` to
`StartControllers()`, in `controller/controller_manager.go`.

A new informer will need to be created as well, `ObjectEndpointInformer`, adding
it to the `DataStore`, so we can listen for `ObjectEndpoint` resources, which we
will critically need to in the `ObjectEndpointController`.

Finally, we expect to add `s3gw` images as dependencies to be downloaded by
the Longhorn chart.

Further changes may be needed as development evolves.

### Backup and Restore

Given the data being kept by an Object Endpoint is stored in a Longhorn volume,
we rely on Longhorn's backup and restore capabilities.

However, an Object Endpoint in this context is more than just the data held by a
given volume: there's meta state that needs to be backed up and restored, in the
form of Secrets, endpoint names and their associated volume, etc.

At this point in time we don't yet have a solution for this, but we believe this
should rely on whatever mechanisms Longhorn has to backup and restore its own
state. Insights are greatly appreciated.

### Test plan

It is not clear at this moment how this can be tested, much due to lack of
knowledge on how Longhorn testing works. Help on this topic would be much
appreciated.

### Upgrade strategy

Upgrading to this enhancement should be painless. Once this feature is available
in Longhorn, the user should be able to create new object endpoints without much
else to do.

At this stage it is not clear how upgrades between Longhorn versions will
happen. We expect to be able to simply restart existing pods using new images.

### Versioning

Including the `s3gw` containers in the Longhorn chart means that, for a specific
Longhorn version, only a specific `s3gw` version is expected to have been tested
and be in working condition. We don't make assumptions as to whether other
`s3gw` versions would correctly function.

An upgrade to `s3gw` will require an upgrade to Longhorn.
