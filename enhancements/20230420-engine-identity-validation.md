# Engine Identity Validation

## Summary

Longhorn-manager communicates with longhorn-engine's gRPC ControllerService, ReplicaService, and SyncAgentService by
sending requests to TCP/IP addresses kept up-to-date by its various controllers. Additionally, the longhorn-engine
controller server sends requests to the longhorn-engine replica server's ReplicaService and SyncAgentService using
TCP/IP addresses it keeps in memory. These addresses are relatively stable in normal operation. However, during periods
of high process turnover (e.g. a node reboot or network event), it is possible for one longhorn-engine component to stop
and another longhorn-engine component to start in its place using the same ports. If this happens quickly enough, other
components with stale address lists attempting to execute requests against the old component may errantly execute
requests against the new component. One harmful effect of this behavior that has been observed is the [expansion of an
unintended longhorn-engine replica](https://github.com/longhorn/longhorn/issues/5709).

This proposal intends to ensure all gRPC requests to longhorn-engine components are actually served by the intended
component.

### Related Issues

https://github.com/longhorn/longhorn/issues/5709

## Motivation

### Goals

- Eliminate the potential for negative effects caused by a Longhorn component communicating with an incorrect
  longhorn-engine component.
- Provide effective logging when incorrect communication occurs to aide in fixing TCP/IP address related race
  conditions.

### Non-goals

- Fix race conditions within the Longhorn control plane that lead to attempts to communicate with an incorrect
  longhorn-engine component.
- Refactor the in-memory data structures the longhorn-engine controller server uses to keep track of and initiate
  communication with replicas.

## Proposal

Today, longhorn-manager knows the volume name and instance name of the process it is trying to communicate with, but it
only uses the TCP/IP information of each process to initiate communication. Additionally, longhorn-engine components are
mostly unaware of the volume name (in the case of longhorn-engine's replica server) and instance name (for both
longhorn-engine controller and replica servers) they are associated with. If we provide this information to
longhorn-engine processes when we start them and then have longhorn-manager provide it on every communication attempt,
we can ensure no accidental communication occurs.

1. Add additional flags to the longhorn-engine CLI that inform controller and replica servers of their associated volume
   and/or instance name.
1. Use [gRPC client interceptors](https://github.com/grpc/grpc-go/blob/master/examples/features/interceptor/README.md)
   to automatically inject [gRPC metadata](https://github.com/grpc/grpc-go/blob/master/Documentation/grpc-metadata.md)
   (i.e. headers) containing volume and/or instance name information every time a gRPC request is made by a
   longhorn-engine client to a longhorn-engine server.
1. Use [gRPC server interceptors](https://github.com/grpc/grpc-go/blob/master/examples/features/interceptor/README.md)
   to automatically validate the volume and/or instance name information in [gRPC
   metadata](https://github.com/grpc/grpc-go/blob/master/Documentation/grpc-metadata.md) (i.e. headers) every time a
   gRPC request made by a longhorn-engine client is received by a longhorn-engine server.
1. Reject any request (with an appropriate error code) if the provided information does not match the information a
   controller or replica server was launched with.
1. Log the rejection at the client and the server, making it easy to identify situations in which incorrect
   communication occurs.
1. Modify instance-manager's `ProxyEngineService` (both server and client) so that longhorn-manager can provide the
   necessary information for gRPC metadata injection.
1. Modify longhorn-manager so that is makes proper use of the new `ProxyEngineService` client and launches
   longhorn-engine controller and replica servers with additional flags.

### User Stories

#### Story 1

Before this proposal:

As an administrator, after an intentional or unintentional node reboot, I notice one or more of my volumes is degraded
and new or existing replicas aren't coming online. In some situations, the UI reports confusing information or one or
more of my volumes might be unable to attach at all. Digging through logs, I see errors related to mismatched sizes, and
at least one replica does appear to have a larger size reported in `volume.meta` than others. I don't know how to
proceed.

After this proposal:

As an administrator, after an intentional or unintentional node reboot, my volumes work as expected. If I choose to dig
through logs, I may see some messages about refused requests to incorrect components, but this doesn't seem to
negatively affect anything.

#### Story 2

Before this proposal:

As a developer, I am aware that it is possible for one Longhorn component to communicate with another, incorrect
component, and that this communication can lead to unexpected replica expansion. I want to work to fix this behavior.
However, when I look at a support bundle, it is very hard to catch this communication occurring. I have to trace TCP/IP
addresses through logs, and if no negative effects are caused, I may never notice it.

After this proposal:

Any time one Longhorn component attempts to communicate with another, incorrect component, it is clearly represented in
the logs.

### User Experience In Detail

See the user stories above. This enhancement is intended to be largely transparent to the user. It should eliminate rare
failures so that users can't run into them.

### API Changes

#### Longhorn-Engine

Increment the longhorn-engine CLIAPIVersion by one. Do not increment the longhorn-engine CLIAPIMinVersion. The changes
in this LEP are backwards compatible. All gRPC metadata validation is by demand of the client. If a less sophisticated
(not upgraded) client does not inject any metadata, the server performs no validation. If a less sophisticated (not
upgraded) client only injects some metadata (e.g. `volume-name` but not `instance-name`), the server only validates the
metadata provided.

Add a global `volume-name` flag and a global `engine-instance-name` flag to the engine CLI (e.g. `longhorn -volume-name
<volume-name> -engine-instance-name <engine-instance-name> <command> <args>`). Virtually all CLI commands create a
controller client and these flags allow appropriate gRPC metadata to be injected into every client request. Requests
that reach the wrong longhorn-engine controller server are rejected.

Use the global `engine-instance-name` flag and the pre-existing `volume-name` positional argument to allow the
longhorn-engine controller server to remember its volume and instance name (e.g. `longhorn -engine-instance-name
<instance-name> controller <volume-name>`). Ignore the global `volume-name` flag, as it is redundant.

Use the global `volume-name` flag or the pre-existing local `volume-name` flag and a new `replica-instance-name` flag to
allow the longhorn-engine replica server to remember its volume and instance name (e.g. `longhorn -volume-name
<volume-name> replica <directory> -replica-instance-name <replica-instance-name>`).

Use the global `volume-name` flag and a new `replica-instance-name` flag to allow the longhorn-engine sync-agent server
to remember its volume and instance name (e.g. `longhorn -volume-name <volume-name> sync-agent -replica-instance-name
<replica-instance-name>`).

Add an additional `replica-instance-name` flag to CLI commands that launch asynchronous tasks that communicate directly
with the longhorn-engine replica server (e.g. `longhorn -volume-name <volume-name> add-replica <address> -size <size>
 -current-size <current-size> -replica-instance-name <replica-instance-name>`). All such commands create a replica
client and these flags allow appropriate gRPC metadata to be injected into every client request. Requests that reach the
wrong longhorn-engine replica server are rejected.

Return 9 FAILED_PRECONDITION with an appropriate message when metadata validation fails. This code is chosen in
accordance with the [RPC API](https://grpc.github.io/grpc/core/md_doc_statuscodes.html), which instructs developers to
use FAILED_PRECONDITION if the client should not retry until the system system has been explicitly fixed.

#### Longhorn-Instance-Manager

Increment the longhorn-instance-manager InstanceManagerProxyAPIVersion by one. Do not increment the
longhorn-instance-manager InstanceManagerProxyAPIMinVersion. The changes in this LEP are backwards compatible. No added
fields are required and their omission is ignored. If a less sophisticated (not upgraded) client does not include them,
no metadata is injected into engine or replica requests and no validation occurs (the behavior is the same as before the
implementation of this LEP).

Add `volume_name` and `instance_name` fields to the `ProxyEngineRequest` protocol buffer message. This message, which
currently only contains an `address` field, is included in all `ProxyEngineService` RPCs. Updated clients can pass
information about the engine process they expect to be communicating with in these fields. When instance-manager creates
an asynchronous task to carry out the requested operation, the resulting controller client includes the gRPC interceptor
described above.

Add `replica_instance_name` fields to any `ProxyEngineService` RPC associated with an asynchronous task that
communicates directly with a longhorn-engine replica server. When instance-manager creates the task, the resulting
replica client includes the gRPC interceptor described above.

Return 5 NOT FOUND with an appropriate message when metadata validation fails at a lower layer. (The particular return
code is definitely open to discussion.)

## Design

### Implementation Overview

#### Interceptors (longhorn-engine)

Add a gRPC server interceptor to all `grpc.NewServer` calls.

```golang
server := grpc.NewServer(withIdentityValidationInterceptor(volumeName, instanceName))
```

Implement the interceptor so that it validates metadata with best effort.

```golang
func withIdentityValidationInterceptor(volumeName, instanceName string) grpc.ServerOption {
	return grpc.UnaryInterceptor(identityValidationInterceptor(volumeName, instanceName))
}

func identityValidationInterceptor(volumeName, instanceName string) grpc.UnaryServerInterceptor {
	// Use a closure to remember the correct volumeName and/or instanceName.
	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		md, ok := metadata.FromIncomingContext(ctx)
		if ok {
			incomingVolumeName, ok := md["volume-name"]
			// Only refuse to serve if both client and server provide validation information.
			if ok && volumeName != "" && incomingVolumeName[0] != volumeName {
				return nil, status.Errorf(codes.InvalidArgument, "Incorrect volume name; check controller address")
			}
		}
		if ok {
			incomingInstanceName, ok := md["instance-name"]
			// Only refuse to serve if both client and server provide validation information.
			if ok && instanceName != "" && incomingInstanceName[0] != instanceName {
				return nil, status.Errorf(codes.InvalidArgument, "Incorrect instance name; check controller address")
			}
		}

		// Call the RPC's actual handler.
		return handler(ctx, req)
	}
}
```

Add a gRPC client interceptor to all `grpc.Dial` calls.

```golang
connection, err := grpc.Dial(serviceUrl, grpc.WithInsecure(), withIdentityValidationInterceptor(volumeName, instanceName))

```

Implement the interceptor so that it injects metadata with best effort.

```golang
func withIdentityValidationInterceptor(volumeName, instanceName string) grpc.DialOption {
	return grpc.WithUnaryInterceptor(identityValidationInterceptor(volumeName, instanceName))
}

func identityValidationInterceptor(volumeName, instanceName string) grpc.UnaryClientInterceptor {
	// Use a closure to remember the correct volumeName and/or instanceName.
	return func(ctx context.Context, method string, req any, reply any, cc *grpc.ClientConn, invoker grpc.UnaryInvoker, opts ...grpc.CallOption) error {
		if volumeName != "" {
			ctx = metadata.AppendToOutgoingContext(ctx, "volume-name", volumeName)
		}
		if instanceName != "" {
			ctx = metadata.AppendToOutgoingContext(ctx, "instance-name", instanceName)
		}
		return invoker(ctx, method, req, reply, cc, opts...)
	}
}
```

Modify all client constructors to include this additional information. Wherever these client packages are consumed (e.g.
the replica client is consumed by the controller, both the replica and the controller clients are consumed by
longhorn-manager), callers can inject this additional information into the constructor and get validation for free.

```golang
func NewControllerClient(address, volumeName, instanceName string) (*ControllerClient, error) {
    // Implementation.
}
```

#### CLI Commands (longhorn-engine)

Add additional flags to all longhorn-engine CLI commands depending on their function.

E.g. command that launches a server:

```golang
func ReplicaCmd() cli.Command {
	return cli.Command{
		Name:      "replica",
		UsageText: "longhorn controller DIRECTORY SIZE",
		Flags: []cli.Flag{
			// Other flags.
            cli.StringFlag{
				Name:  "volume-name",
				Value: "",
				Usage: "Name of the volume (for validation purposes)",
			},
			cli.StringFlag{
				Name:  "replica-instance-name",
				Value: "",
				Usage: "Name of the instance (for validation purposes)",
			},
		},
        // Rest of implementation.
	}
}
```

E.g. command that directly communicates with both a controller and replica server.

```golang
func AddReplicaCmd() cli.Command {
	return cli.Command{
		Name:      "add-replica",
		ShortName: "add",
		Flags: []cli.Flag{
            // Other flags.
			cli.StringFlag{
				Name:     "volume-name",
				Required: false,
				Usage:    "Name of the volume (for validation purposes)",
			},
			cli.StringFlag{
				Name:     "engine-instance-name",
				Required: false,
				Usage:    "Name of the controller instance (for validation purposes)",
			},
			cli.StringFlag{
				Name:     "replica-instance-name",
				Required: false,
				Usage:    "Name of the replica instance (for validation purposes)",
			},
		},
		// Rest of implementation.
	}
}
```

#### Instance-Manager Integration

Modify the ProxyEngineService server functions so that they can make correct use of the changes in longhorn-engine.
Funnel information from the additional fields in the ProxyEngineRequest message and in appropriate ProxyEngineService
RPCs into the longhorn-engine task and controller client constructors so it can be used for validation.

```protobuf
message ProxyEngineRequest{
	string address = 1;
	string volume_name = 2;
	string instance_name = 3;
}
```

Modify the ProxyEngineService client functions so that consumers can provide the information required to enable
validation.

#### Longhorn-Manager Integration

Ensure the engine and replica controllers launch engine and replica processes with `-volume-name` and
`-engine-instance-name` or `-replica-instance-name` flags so that these processes can validate identifying gRPC metadata
coming from requests.

Ensure the engine controller supplies correct information to the ProxyEngineService client functions so that identity
validation can occur in the lower layers.

#### Example Validation Flow

This issue/LEP was inspired by [longhorn/longhorn#5709](https://github.com/longhorn/longhorn/issues/5709). In the
situation described in this issue:

1. An engine controller with out-of-date information (including a replica address the associated volume does not own)
   [issues a ReplicaAdd
   command](https://github.com/longhorn/longhorn-manager/blob/a7dd20cdbdb1a3cea4eb7490f14d94d2b0ef273a/controller/engine_controller.go#L1819)
   to instance-manager's EngineProxyService.
2. Instance-manager creates a longhorn-engine task and [calls its AddReplica
   method](https://github.com/longhorn/longhorn-instance-manager/blob/0e0ec6dcff9c0a56a67d51e5691a1d4a4f397f4b/pkg/proxy/replica.go#L35).
3. The task makes appropriate calls to a longhorn-engine controller and replica. The ReplicaService's [ExpandReplica
   command](https://github.com/longhorn/longhorn-engine/blob/1f57dd9a235c6022d82c5631782020e84da22643/pkg/sync/sync.go#L509)
   is used to expand the replica before a followup failure to actually add the replica to the controller's backend.

After this improvement, the above scenario will be impossible:

1. Both the engine and replica controllers will launch engine and replica processes with the `-volume-name` and
   `-engine-instance-name` or `replica-instance-name` flags.
2. When the engine controller issues a ReplicaAdd command, it will do so using the expanded embedded
   `ProxyEngineRequest` message (with `volume_name` and `instance_name` fields) and an additional
   `replica_instance_name` field.
3. Instance-manager will create a longhorn-engine task that automatically injects `volume-name` and `instance-name` gRPC
   metadata into each controller request.
4. When the task issues an ExpandReplica command, it will do so using a client that automatically injects `volume-name`
   and `instance-name` gRPC metadata into it.
5. If either the controller or the replica does not agree with the information provided, gRPC requests will fail
   immediately and there will be no change in any longhorn-engine component.

### Test plan

#### TODO: Integration Test Plan

In my test environment, I have experimented with:

- Running new versions of all components, making gRPC calls to the longhorn-engine controller and replica processes with
  wrong gRPC metadata, and verifying that these calls fail.
- Running new versions of all components, making gRPC calls to instance-manager with an incorrect volume-name or
  instance name, and verifying that these calls fail.
- Running new versions of all components, adding additional logging to longhorn-engine and verifying that metadata
  validation is occurring during the normal volume lifecycle.

This is really a better fit for a negative testing scenario (do something that would otherwise result in improper
communication, then verify that communication fails), but we have already eliminated the only known recreate for
[longhorn/longhorn#5709](https://github.com/longhorn/longhorn/issues/5709).

#### Engine Integration Test Plan

Rework test fixtures so that:

- All controller and replica processes are created with the information needed for identity validation.
- It is convenient to create controller and replica clients with the information needed for identity validation.
- gRPC metadata is automatically injected into controller and replica client requests when clients have the necessary
  information.

Do not modify the behavior of existing tests. Since these tests were using clients with identity validation information,
no identity validation is performed.

- Modify functions/fixtures that create engine/replica processes to allow the new flags to be passed, but do not pass
  them by default.
- Modify engine/replica clients used by tests to allow for metadata injection, but do not enable it by default.

Create new tests that:

- Ensure validation fails when a directly created client attempts to communicate with a controller or replica server
  using the wrong identity validation information.
- Ensure validation fails when an indirectly created client (by the engine) tries to communicate with a replica server
  using the wrong identity validation information.
- Ensure validation fails when an indirectly created client (by a CLI command) tries to communicate with a controller or
  replica server using the wrong identity validation information.

### Upgrade strategy

The user will get benefit from this behavior automatically, but only after they have upgraded all associated components
to a supporting version (longhorn-manager, longhorn-engine, and CRITICALLY instance-manager).

We will only provide volume name and instance name information to longhorn-engine controller and replica processes on a
supported version (as governed by the `CLIAPIVersion`). Even if other components are upgraded, when they send gRPC
metadata to non-upgraded processes, it will be ignored.

We will only populate extra ProxyEngineService fields when longhorn-manager is running with an update ProxyEngineService
client.

- RPCs from an old client to a new ProxyEngineService server will succeed, but without the extra fields,
  instance-manager will have no useful gRPC metadata to inject into its longhorn-engine requests.
- RPCs from a new client to an old ProxyEngineService will succeed, but instance-manager will ignore the new fields and
  not inject useful gRPC metadata into its longhorn-engine request.

## Note

### Why gRPC metadata?

We initially looked at adding volume name and/or instance name fields to all longhorn-engine ReplicaService and
ControllerService calls. However, this would be awkward with some of the existing RPCs. In addition, it doesn't make
much intuitive sense. Why should we provide the name of an entity we are communicating with to that entity as part of
its API? It makes more sense to think of this identity validation in terms of sessions or authorization/authentication.
In HTTP, information of this nature is handled through the use of headers, and metadata is the gRPC equivalent.

### Why gRPC interceptors?

We want to ensure the same behavior in every longhorn-engine ControllerService and ReplicaService call so that it is not
up to an individual developer writing a new RPC to remember to validate gRPC metadata (and to relearn how it should be
done). Interceptors work mostly transparently to ensure identity validation always occurs.
