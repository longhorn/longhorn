# Consolidate Longhorn Instance Managers

## Summary

Longhorn architecture includes engine and replica instance manager pods on each node. After the upgrade, Longhorn adds an additional engine and replica instance manager pods. When the cluster is set with a default request of 12% guaranteed CPU, all instance manager pods will occupy 12% * 4 CPUs per node. Nevertheless, this caused high base resource requirements and is likely unnecessary.

```
NAME                STATE      E-CPU(CORES)   E-MEM(BYTES)   R-CPU(CORES)   R-MEM(BYTES)   CREATED-WORKLOADS   DURATION(MINUTES)   AGE
demo-0 (no-IO)      Complete   8.88m          24Mi           1.55m          43Mi           5                   10                  22h
demo-0-bs-512b-5g   Complete   109.70m        66Mi           36.46m         54Mi           5                   10                  16h
demo-0-bs-1m-10g    Complete   113.16m        65Mi           36.63m         56Mi           5                   10                  14h
demo-0-bs-5m-10g    Complete   114.17m        64Mi           31.37m         54Mi           5                   10                  42m
```

Aiming to simplify the architecture and free up some resource requests, this document proposes to consolidate the engine and replica instance managers into a single pod. This consolidation will not affect any data plane operations or volume migration. As the engine process is the primary consumer of CPU resources, merging the instance managers will result in a 50% reduction in CPU requests for instance managers. This is because there will only be one instance manager pod for both process types.

### Related Issues

Phase 1:
- https://github.com/longhorn/longhorn/issues/5208

Phase 2:
- https://github.com/longhorn/longhorn/issues/5842
- https://github.com/longhorn/longhorn/issues/5844

## Motivation

### Goals

- Having single instance manager pods to run replica and engine processes.
- After the Longhorn upgrade, the previous engine instance manager should continue to handle data plane operations for attached volumes until they are detached. And the replica instance managers should continue servicing data plane operations until the volume engine is upgraded or volume is detached.
- Automatically clean up any engine/replica instance managers when all instances (process) get removed.
- Online/offline upgrade volume engine should be functional. The replicas will automatically migrate to use the new `aio` (all-in-one) type instance managers, and the `engine` type instance manager will continue to serve until the first volume detachment.
- The Pod Disruption Budget (PDB) handling for cluster auto-scaler and node drain should work as expected.

### Non-goals [optional]

`None`

## Proposal

To ensure uninterrupted upgrades, this enhancement will be implemented in two phases. The existing `engine`/`replica` instance manager may coexist with the consolidated instance manager during the transition.

Phase 1:
- Introduce a new `aio` instance manager type. The `engine` and `replica` instance manager types will be deprecated and continue to serve for the upgraded volumes until the first volume detachment.
- Introduce new `Guaranteed Instance Manager CPU` setting, `Guaranteed Engine Manager CPU` and `Guaranteed Replica Manager CPU` settings will be deprecated and continues to serve for the upgraded volumes until the first volume detachment.

Phase 2:
- Remove all instance manager types.
- Remove the `Guaranteed Engine Manager CPU` and `Guaranteed Replica Manager CPU` settings.

### User Stories

- For freshly installed Longhorn, the user will see `aio` type instance managers.
- For upgraded Longhorn with all volume detached, the user will see the `engine`, and `replica` instance managers removed and replaced by `aio` type instance managers.
- For upgraded Longhorn with volume attached, the user will see existing `engine`, and `replica` instance managers still servicing the old attached volumes and the new `aio` type instance manager servicing new volume attachments.

### User Experience In Detail

#### New Installation

1. User creates and attaches a volume.
   ```
   > kubectl -n longhorn-system get volume
   NAME     STATE      ROBUSTNESS   SCHEDULED   SIZE          NODE            AGE
   demo-0   attached   unknown                  21474836480   ip-10-0-1-113   12s

   > kubectl -n longhorn-system get lhim
   NAME                                                STATE     TYPE   NODE            AGE
   instance-manager-8f81ca7c3bf95bbbf656be6ac2d1b7c4   running   aio    ip-10-0-1-105   124m
   instance-manager-7e59c9f2ef7649630344050a8d5be68e   running   aio    ip-10-0-1-102   124m
   instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc   running   aio    ip-10-0-1-113   124m

   > kubectl -n longhorn-system get lhim/instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc -o yaml
   apiVersion: longhorn.io/v1beta2
   kind: InstanceManager
   metadata:
     creationTimestamp: "2023-03-16T10:48:59Z"
     generation: 1
     labels:
       longhorn.io/component: instance-manager
       longhorn.io/instance-manager-image: imi-8d41c3a4
       longhorn.io/instance-manager-type: aio
       longhorn.io/managed-by: longhorn-manager
       longhorn.io/node: ip-10-0-1-113
     name: instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc
     namespace: longhorn-system
     ownerReferences:
     - apiVersion: longhorn.io/v1beta2
       blockOwnerDeletion: true
       kind: Node
       name: ip-10-0-1-113
       uid: 00c0734b-f061-4b28-8071-62596274cb18
     resourceVersion: "926067"
     uid: a869def6-1077-4363-8b64-6863097c1e26
   spec:
     engineImage: ""
     image: c3y1huang/research:175-lh-im
     nodeID: ip-10-0-1-113
     type: aio
   status:
     apiMinVersion: 1
     apiVersion: 3
     currentState: running
     instanceEngines:
       demo-0-e-06d4c77d:
         spec:
           name: demo-0-e-06d4c77d
         status:
           endpoint: ""
           errorMsg: ""
           listen: ""
           portEnd: 10015
           portStart: 10015
           resourceVersion: 0
           state: running
           type: engine
     instanceReplicas:
       demo-0-r-ca78cab4:
         spec:
           name: demo-0-r-ca78cab4
         status:
           endpoint: ""
           errorMsg: ""
           listen: ""
           portEnd: 10014
           portStart: 10000
           resourceVersion: 0
           state: running
           type: replica
     ip: 10.42.0.238
     ownerID: ip-10-0-1-113
     proxyApiMinVersion: 1
     proxyApiVersion: 4
   ```
   - The engine and replica instances(processes) created in the `aio` type instance manager.

#### Upgrade With Volumes Detached

1. User has a Longhorn v1.4.0 cluster and a volume in the detached state.
   ```
   > kubectl -n longhorn-system get volume
   NAME     STATE      ROBUSTNESS   SCHEDULED   SIZE          NODE   AGE
   demo-1   detached   unknown                  21474836480          12s
   
   > kubectl -n longhorn-system get lhim
   NAME                                                  STATE     TYPE      NODE            AGE
   instance-manager-r-1278a39fa6e6d8f49eba156b81ac1f59   running   replica   ip-10-0-1-113   3m44s
   instance-manager-e-1278a39fa6e6d8f49eba156b81ac1f59   running   engine    ip-10-0-1-113   3m44s
   instance-manager-e-45ad195db7f55ed0a2dd1ea5f19c5edf   running   engine    ip-10-0-1-105   3m41s
   instance-manager-r-45ad195db7f55ed0a2dd1ea5f19c5edf   running   replica   ip-10-0-1-105   3m41s
   instance-manager-e-225a2c7411a666c8eab99484ab632359   running   engine    ip-10-0-1-102   3m42s
   instance-manager-r-225a2c7411a666c8eab99484ab632359   running   replica   ip-10-0-1-102   3m42s
   ```
1. User upgraded Longhorn to v1.5.0.
   ```
   > kubectl -n longhorn-system get lhim
   NAME                                                STATE     TYPE   NODE            AGE
   instance-manager-8f81ca7c3bf95bbbf656be6ac2d1b7c4   running   aio    ip-10-0-1-105   112s
   instance-manager-7e59c9f2ef7649630344050a8d5be68e   running   aio    ip-10-0-1-102   48s
   instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc   running   aio    ip-10-0-1-113   47s
   ```
   - Unused `engine` type instance managers removed.
   - Unused `replica` type instance managers removed.
   - 3 `aio` type instance managers created.
1. User upgraded volume engine.
1. User attaches the volume.
   ```
   > kubectl -n longhorn-system get volume
   NAME     STATE      ROBUSTNESS   SCHEDULED   SIZE          NODE            AGE
   demo-1   attached   healthy                  21474836480   ip-10-0-1-113   4m51s

   > kubectl -n longhorn-system get lhim
   NAME                                                STATE     TYPE   NODE            AGE
   instance-manager-8f81ca7c3bf95bbbf656be6ac2d1b7c4   running   aio    ip-10-0-1-105   3m58s
   instance-manager-7e59c9f2ef7649630344050a8d5be68e   running   aio    ip-10-0-1-102   2m54s
   instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc   running   aio    ip-10-0-1-113   2m53s

   > kubectl -n longhorn-system get lhim/instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc -o yaml
   apiVersion: longhorn.io/v1beta2
   kind: InstanceManager
   metadata:
     creationTimestamp: "2023-03-16T13:03:15Z"
     generation: 1
     labels:
       longhorn.io/component: instance-manager
       longhorn.io/instance-manager-image: imi-8d41c3a4
       longhorn.io/instance-manager-type: aio
       longhorn.io/managed-by: longhorn-manager
       longhorn.io/node: ip-10-0-1-113
     name: instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc
     namespace: longhorn-system
     ownerReferences:
     - apiVersion: longhorn.io/v1beta2
       blockOwnerDeletion: true
       kind: Node
       name: ip-10-0-1-113
       uid: 12eb73cd-e9de-4c45-875d-3eff7cfb1034
     resourceVersion: "3762"
     uid: c996a89a-f841-4841-b69d-4218ed8d8c6e
   spec:
     engineImage: ""
     image: c3y1huang/research:175-lh-im
     nodeID: ip-10-0-1-113
     type: aio
   status:
     apiMinVersion: 1
     apiVersion: 3
     currentState: running
     instanceEngines:
       demo-1-e-b7d28fb3:
         spec:
           name: demo-1-e-b7d28fb3
         status:
           endpoint: ""
           errorMsg: ""
           listen: ""
           portEnd: 10015
           portStart: 10015
           resourceVersion: 0
           state: running
           type: engine
     instanceReplicas:
       demo-1-r-189c1bbb:
         spec:
           name: demo-1-r-189c1bbb
         status:
           endpoint: ""
           errorMsg: ""
           listen: ""
           portEnd: 10014
           portStart: 10000
           resourceVersion: 0
           state: running
           type: replica
     ip: 10.42.0.28
     ownerID: ip-10-0-1-113
     proxyApiMinVersion: 1
     proxyApiVersion: 4
   ```
   - The engine and replica instances(processes) created in the `aio` type instance manager.

#### Upgrade With Volumes Attached

1. User has a Longhorn v1.4.0 cluster and a volume in the attached state.
   ```
   > kubectl -n longhorn-system get volume
   NAME     STATE      ROBUSTNESS   SCHEDULED   SIZE          NODE            AGE
   demo-2   attached   healthy                  21474836480   ip-10-0-1-113   35s
   
   > kubectl -n longhorn-system get lhim
   NAME                                                  STATE     TYPE      NODE            AGE
   instance-manager-r-1278a39fa6e6d8f49eba156b81ac1f59   running   replica   ip-10-0-1-113   2m41s
   instance-manager-r-45ad195db7f55ed0a2dd1ea5f19c5edf   running   replica   ip-10-0-1-105   119s
   instance-manager-r-225a2c7411a666c8eab99484ab632359   running   replica   ip-10-0-1-102   119s
   instance-manager-e-1278a39fa6e6d8f49eba156b81ac1f59   running   engine    ip-10-0-1-113   2m41s
   instance-manager-e-225a2c7411a666c8eab99484ab632359   running   engine    ip-10-0-1-102   119s
   instance-manager-e-45ad195db7f55ed0a2dd1ea5f19c5edf   running   engine    ip-10-0-1-105   119s
   ```
1. User upgraded Longhorn to v1.5.0.
   ```
   > kubectl -n longhorn-system get lhim
   NAME                                                  STATE     TYPE      NODE            AGE
   instance-manager-r-1278a39fa6e6d8f49eba156b81ac1f59   running   replica   ip-10-0-1-113   5m24s
   instance-manager-r-45ad195db7f55ed0a2dd1ea5f19c5edf   running   replica   ip-10-0-1-105   4m42s
   instance-manager-r-225a2c7411a666c8eab99484ab632359   running   replica   ip-10-0-1-102   4m42s
   instance-manager-e-1278a39fa6e6d8f49eba156b81ac1f59   running   engine    ip-10-0-1-113   5m24s
   instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc     running   aio       ip-10-0-1-113   117s
   instance-manager-7e59c9f2ef7649630344050a8d5be68e     running   aio       ip-10-0-1-102   33s
   instance-manager-8f81ca7c3bf95bbbf656be6ac2d1b7c4     running   aio       ip-10-0-1-105   32s
   ```
   - 2 unused `engine` type instance managers removed.
   - 3 `aio` type instance managers created.
1. User upgraded online volume engine.
   ```
   > kubectl -n longhorn-system get lhim
   NAME                                                  STATE     TYPE     NODE            AGE
   instance-manager-8f81ca7c3bf95bbbf656be6ac2d1b7c4     running   aio      ip-10-0-1-105   6m53s
   instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc     running   aio      ip-10-0-1-113   8m18s
   instance-manager-7e59c9f2ef7649630344050a8d5be68e     running   aio      ip-10-0-1-102   6m54s
   instance-manager-e-1278a39fa6e6d8f49eba156b81ac1f59   running   engine   ip-10-0-1-113   11m
   ```
   - All `replica` type instance manager migrated to `aio` type instance managers.
1. User detached the volume.
   ```
   > kubectl -n longhorn-system get lhim
   NAME                                                STATE     TYPE   NODE            AGE
   instance-manager-8f81ca7c3bf95bbbf656be6ac2d1b7c4   running   aio    ip-10-0-1-105   8m38s
   instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc   running   aio    ip-10-0-1-113   10m
   instance-manager-7e59c9f2ef7649630344050a8d5be68e   running   aio    ip-10-0-1-102   8m39s
   ```
   - The `engine` type instance managers removed.
1. User attached the volume.
   ```
   > kubectl -n longhorn-system get volume
   NAME     STATE      ROBUSTNESS   SCHEDULED   SIZE          NODE            AGE
   demo-2   attached   healthy                  21474836480   ip-10-0-1-113   12m
   
   > kubectl -n longhorn-system get lhim
   NAME                                                STATE     TYPE   NODE            AGE
   instance-manager-7e59c9f2ef7649630344050a8d5be68e   running   aio    ip-10-0-1-102   9m40s
   instance-manager-8f81ca7c3bf95bbbf656be6ac2d1b7c4   running   aio    ip-10-0-1-105   9m39s
   instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc   running   aio    ip-10-0-1-113   11m
   
   > kubectl -n longhorn-system get lhim/instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc -o yaml
   apiVersion: longhorn.io/v1beta2
   kind: InstanceManager
   metadata:
     creationTimestamp: "2023-03-16T13:12:41Z"
     generation: 1
     labels:
       longhorn.io/component: instance-manager
       longhorn.io/instance-manager-image: imi-8d41c3a4
       longhorn.io/instance-manager-type: aio
       longhorn.io/managed-by: longhorn-manager
       longhorn.io/node: ip-10-0-1-113
     name: instance-manager-b34d5db1fe1e2d52bcfb308be3166cfc
     namespace: longhorn-system
     ownerReferences:
     - apiVersion: longhorn.io/v1beta2
       blockOwnerDeletion: true
       kind: Node
       name: ip-10-0-1-113
       uid: 6d109c40-abe3-42ed-8e40-f76cfc33e4c2
     resourceVersion: "4339"
     uid: 01556f2c-fbb4-4a15-a778-c73df518b070
   spec:
     engineImage: ""
     image: c3y1huang/research:175-lh-im
     nodeID: ip-10-0-1-113
     type: aio
   status:
     apiMinVersion: 1
     apiVersion: 3
     currentState: running
     instanceEngines:
       demo-2-e-65845267:
         spec:
           name: demo-2-e-65845267
         status:
           endpoint: ""
           errorMsg: ""
           listen: ""
           portEnd: 10015
           portStart: 10015
           resourceVersion: 0
           state: running
           type: engine
     instanceReplicas:
       demo-2-r-a2bd415f:
         spec:
           name: demo-2-r-a2bd415f
         status:
           endpoint: ""
           errorMsg: ""
           listen: ""
           portEnd: 10014
           portStart: 10000
           resourceVersion: 0
           state: running
           type: replica
     ip: 10.42.0.31
     ownerID: ip-10-0-1-113
     proxyApiMinVersion: 1
     proxyApiVersion: 4
   ```
   - The engine and replica instances(processes) created in the `aio` type instance manager.

### API changes

- Introduce new `instanceManagerCPURequest` in `Node` resource.
- Introduce new `instanceEngines` in InstanceManager resource.
- Introduce new `instanceReplicas` in InstanceManager resource.

## Design

### Phase 1: All-in-one Instance Manager Implementation Overview

Introducing a new instance manager type to have Longhorn continue to service existing attached volumes for Longhorn v1.5.x.

#### New Instance Manager Type

- Introduce a new `aio` (all-in-one) instance manager type to differentiate the handling of the old `engine`/`replica` instance managers and the new consolidated instance managers.
- When getting InstanceManagers by instance of the attached volume, retrieve the InstanceManager from the instance manager list using the new `aio` type.

#### InstanceManager `instances` Field Replacement For New InstanceManagers
- New InstanceManagers will use the `instanceEngines` and `instanceReplicas` fields, replacing the `instances` field.
- For the existing InstanceManagers for the attached Volumes, the `instances` field will remain in use.

#### Instance Manager Execution

- Rename the `engine-manager` script to `instance-manager`.
- Bump up version to `4`.

#### New Instance Manager Pod

- Replace `engine` and `replica` pod creation with spec to use for `aio` instance manager pod.
  ```
  > kubectl -n longhorn-system get pod/instance-manager-0d96990c6881c828251c534eb31bfa85 -o yaml
  apiVersion: v1
  kind: Pod
  metadata:
    annotations:
      longhorn.io/last-applied-tolerations: '[]'
    creationTimestamp: "2023-03-01T08:13:03Z"
    labels:
      longhorn.io/component: instance-manager
      longhorn.io/instance-manager-image: imi-a1873aa3
      longhorn.io/instance-manager-type: aio
      longhorn.io/managed-by: longhorn-manager
      longhorn.io/node: ip-10-0-1-113
    name: instance-manager-0d96990c6881c828251c534eb31bfa85
    namespace: longhorn-system
    ownerReferences:
    - apiVersion: longhorn.io/v1beta2
      blockOwnerDeletion: true
      controller: true
      kind: InstanceManager
      name: instance-manager-0d96990c6881c828251c534eb31bfa85
      uid: 51c13e4f-d0a2-445d-b98b-80cca7080c78
    resourceVersion: "12133"
    uid: 81397cca-d9e9-48f6-8813-e7f2e2cd4617
  spec:
    containers:
    - args:
      - instance-manager
      - --debug
      - daemon
      - --listen
      - 0.0.0.0:8500
      env:
      - name: TLS_DIR
        value: /tls-files/
      image: c3y1huang/research:174-lh-im
      imagePullPolicy: IfNotPresent
      livenessProbe:
        failureThreshold: 3
        initialDelaySeconds: 3
        periodSeconds: 5
        successThreshold: 1
        tcpSocket:
          port: 8500
        timeoutSeconds: 4
      name: instance-manager
      resources:
        requests:
          cpu: 960m
      securityContext:
        privileged: true
      terminationMessagePath: /dev/termination-log
      terminationMessagePolicy: File
      volumeMounts:
      - mountPath: /host
        mountPropagation: HostToContainer
        name: host
      - mountPath: /engine-binaries/
        mountPropagation: HostToContainer
        name: engine-binaries
      - mountPath: /host/var/lib/longhorn/unix-domain-socket/
        name: unix-domain-socket
      - mountPath: /tls-files/
        name: longhorn-grpc-tls
      - mountPath: /var/run/secrets/kubernetes.io/serviceaccount
        name: kube-api-access-hkbfc
        readOnly: true
    dnsPolicy: ClusterFirst
    enableServiceLinks: true
    nodeName: ip-10-0-1-113
    preemptionPolicy: PreemptLowerPriority
    priority: 0
    restartPolicy: Never
    schedulerName: default-scheduler
    securityContext: {}
    serviceAccount: longhorn-service-account
    serviceAccountName: longhorn-service-account
    terminationGracePeriodSeconds: 30
    tolerations:
    - effect: NoExecute
      key: node.kubernetes.io/not-ready
      operator: Exists
      tolerationSeconds: 300
    - effect: NoExecute
      key: node.kubernetes.io/unreachable
      operator: Exists
      tolerationSeconds: 300
    volumes:
    - hostPath:
        path: /
        type: ""
      name: host
    - hostPath:
        path: /var/lib/longhorn/engine-binaries/
        type: ""
      name: engine-binaries
    - hostPath:
        path: /var/lib/longhorn/unix-domain-socket/
        type: ""
      name: unix-domain-socket
    - name: longhorn-grpc-tls
      secret:
        defaultMode: 420
        optional: true
        secretName: longhorn-grpc-tls
    - name: kube-api-access-hkbfc
      projected:
        defaultMode: 420
        sources:
        - serviceAccountToken:
            expirationSeconds: 3607
            path: token
        - configMap:
            items:
            - key: ca.crt
              path: ca.crt
            name: kube-root-ca.crt
        - downwardAPI:
            items:
            - fieldRef:
                apiVersion: v1
                fieldPath: metadata.namespace
              path: namespace
  status:
    conditions:
    - lastProbeTime: null
      lastTransitionTime: "2023-03-01T08:13:03Z"
      status: "True"
      type: Initialized
    - lastProbeTime: null
      lastTransitionTime: "2023-03-01T08:13:04Z"
      status: "True"
      type: Ready
    - lastProbeTime: null
      lastTransitionTime: "2023-03-01T08:13:04Z"
      status: "True"
      type: ContainersReady
    - lastProbeTime: null
      lastTransitionTime: "2023-03-01T08:13:03Z"
      status: "True"
      type: PodScheduled
    containerStatuses:
    - containerID: containerd://cb249b97d128e47a7f13326b76496656d407fd16fc44b5f1a37384689d0fa900
      image: docker.io/c3y1huang/research:174-lh-im
      imageID: docker.io/c3y1huang/research@sha256:1f4e86b92b3f437596f9792cd42a1bb59d1eace4196139dc030b549340af2e68
      lastState: {}
      name: instance-manager
      ready: true
      restartCount: 0
      started: true
      state:
        running:
          startedAt: "2023-03-01T08:13:03Z"
    hostIP: 10.0.1.113
    phase: Running
    podIP: 10.42.0.27
    podIPs:
    - ip: 10.42.0.27
    qosClass: Burstable
    startTime: "2023-03-01T08:13:03Z"
  ```

#### Controllers Change

- Map the status of the engine/replica process to the corresponding instanceEngines/instanceReplicas fields in the InstanceManager instead of the instances field. To ensure backward compatibility, the instances field will continue to be utilized by the pre-upgrade attached volume.
- Ensure support for the previous version's attached volumes with the old engine/replica instance manager types.
- Replace the old engine/replica InstanceManagers with the aio type instance manager during replenishment.

#### New Setting

- Introduce a new `Guaranteed Instance Manager CPU` setting for the new `aio` instance manager pod.
- The `Guaranteed Engine Manager CPU` and `Guaranteed Replica Manager CPU` will co-exist with this setting in Longhorn v1.5.x.

### Phase 2 - Deprecations Overview

Based on the assumption when upgrading from v1.5.x to 1.6.x, volumes should have detached at least once and migrated to `aio` type instance managers. Then the cluster should not have volume depending on `engine` and `replica` type instance managers. Therefore in this phase, remove the related types and settings.

#### Old Instance Manager Types

- Remove the `engine`, `replica`, and `aio` instance manager types. There is no need for differentiation.

### Old Settings

- Remove the `Guaranteed Engine Manager CPU` and `Guaranteed Replica Manager CPU` settings. The settings have already been replaced by the `Guaranteed Instance Manager CPU` setting in phase 1.

#### Controllers Change

- Remove support for engine/replica InstanceManager types.

### Test plan

Support new `aio` instance manager type and run regression test cases.

### Upgrade strategy

The `instances` field in the instance manager custom resource will still be utilized by old instance managers of the attached volume.

## Note [optional]

`None`
