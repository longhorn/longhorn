# Default disks and node configuration

## Summary

This enhancement allows the user to customize the default disks and node configurations in Longhorn for newly added nodes using Kubernetes label and annotation, instead of using Longhorn API or UI.

### Related Issues

https://github.com/longhorn/longhorn/issues/1053

https://github.com/longhorn/longhorn/issues/991

## Motivation

### Goals

1. Allow users to customize the disks and node configuration for new nodes without using Longhorn API or UI. This will make it much easier for users to scale the cluster since it will eliminate the necessity to configure Longhorn manually for each newly added node if the node contains more than one disk or the disk configuration is different between the nodes.
2. Allow users to define node tags for newly added nodes without using the Longhorn API or UI.

### Non-goals

This enhancement will not keep the node label/annotation in sync with the Longhorn node/disks configuration.

## Proposal

1. Longhorn directly uses the node annotation to set the node tags once the node contains no tag.
2. Longhorn uses the setting `Create Default Disk on Labeled Nodes` to decide if to enable the default disks customization.
If the setting is enabled, Longhorn will wait for the default disks customization set, instead of directly creating the Longhorn default disk for the node without disks (new node is included). 
Then Longhorn relies on the value of the node label `node.longhorn.io/create-default-disk` to decide how to customize default disks:
If the value is `config`, the annotation will be parsed and used as the default disks customization. 
If the value is boolean value `true`, the data path setting will be used for the default disk. 
And other values will be treated as `false` and no default disk will be created.

### User Stories

#### Scale up the cluster and add tags to new nodes

Before the enhancement, when the users want to scale up the Kubernetes cluster and add tags on the node, they would need access to the Longhorn API/UI to do that.

After the enhancement, the users can add a specified annotation to the new nodes to define the tags. In this way, the users don't need to work with Longhorn API/UI directly during the process of scaling up a cluster.

#### Scale up the cluster and add disks to new nodes
     
 Before the enhancement, when the users want to scale up the Kubernetes cluster and customize the disks on the node, they would need to:
 
 1. Enable the Longhorn setting `Create Default Disk on Labeled Nodes` to prevent the default disk to be created automatically on the node.
 2. Add new nodes to the Kubernetes cluster, e.g. by using Rancher or Terraform, etc.
 3. After the new node was recognized by Longhorn, edit the node to add disks using either Longhorn UI or API.
 
 The third step here needs to be done for every node separately, making it inconvenient for the operation.
 
 After the enhancement, the steps the user would take is:
 
 1. Enable the Longhorn setting `Create Default Disk on Labeled Nodes`.
 2. Add new nodes to the Kubernetes cluster, e.g. by using Rancher or Terraform, etc.
 3. Add the label and annotations to the node to define the default disk(s) for the new node. Longhorn will pick it up automatically and add the disk(s) for the new node.
 
 In this way, the user doesn't need to work with Longhorn API/UI directly during the process of scaling up a cluster.

### User experience description

#### Scenario 1 - Setup the default node tags:

1. The user adds the default node tags annotation `node.longhorn.io/default-node-tags=<node tag list>` to a Kubernetes node.
2. If the Longhorn node tag list was empty before step 1, the user should see the tag list for that node updated according to the annotation. Otherwise, the user should see no change to the tag list.

#### Scenario 2 - Setup and use the default disks for a new node:

1. The users enable the setting `Create Default Disk on Labeled Nodes`.
2. The users add a new node, then they will get a node without any disk.
    1. By deleting all disks on an existing node, the users can get the same result.  
3. After patching the label `node.longhorn.io/create-default-disk=config` and the annotation `node.longhorn.io/default-disks-config=<customized default disks>` for the Kubernetes node,
the node disks should be updated according to the annotation.

## Design

### Implementation Overview

##### For Node Tags:

If:

1. The Longhorn node contains no tag.
2. The Kubernetes node object of the same name contains an annotation `node.longhorn.io/default-node-tags`, for example:
```
node.longhorn.io/default-node-tags: '["fast","storage"]'
```
3. The annotation can be parsed successfully.

Then Longhorn will update the Longhorn node object with the new tags specified by the annotation.

The process will be done as a part of the node controller reconciliation logic in the Longhorn manager.

##### For Default Disks:

If:

1. The Longhorn node contains no disk.
2. The setting `Create Default Disk on Labeled Nodes` is enabled.
3. The Kubernetes node object of the same name contains the label `node.longhorn.io/create-default-disk: 'config'` and an annotation `node.longhorn.io/default-disks-config`, for example:
```
node.longhorn.io/default-disks-config: 
'[{"path":"/mnt/disk1","allowScheduling":false},
  {"path":"/mnt/disk2","allowScheduling":false,"storageReserved":1024,"tags":["ssd","fast"]}]'
```
4. The annotation can be parsed successfully.

Then Longhorn will create the customized default disk(s) specified by the annotation.

The process will be done as a part of the node controller reconciliation logic in the Longhorn manager.

##### Notice

If the label/annotations failed validation, no partial configuration will be applied and the whole annotation will be ignored. No change will be done for the node tag/disks.

The validation failure can be caused by:
1. The annotation format is invalid and cannot be parsed to tags/disks configuration.
2. The format is valid but there is an unqualified tag in the tag list.
3. The format is valid but there is an invalid disk parameter in the disk list. 
e.g., duplicate disk path, non-existing disk path, multiple disks with the same file system, the reserved storage size being out of range...

### Test plan

1. The users deploy Longhorn system.
2. The users enable the setting `Create Default Disk on Labeled Nodes`.
3. The users scale the cluster. Then the newly introduced nodes should contain no disk and no tag.
4. The users pick up a new node, create 2 random data path in the container then patch the following valid node label and annotations:
```
labels:
    node.longhorn.io/create-default-disk: "config"
},
annotations:
    node.longhorn.io/default-disks-config:
        '[{"path":"<random data path 1>","allowScheduling":false},
          {"path":"<random data path 2>","allowScheduling":true,"storageReserved":1024,"tags":["ssd","fast"]}]'
    node.longhorn.io/default-node-tags: '["fast","storage"]'
```
After the patching, the node disks and tags will be created and match the annotations.

5. The users use Longhorn UI to modify the node configuration. They will find that the node annotations keep unchanged and don't match the current node tag/disk configuration.
6. The users delete all node tags and disks via UI. Then the node tags/disks will be recreated immediately and match the annotations.
7. The users pick up another new node, directly patch the following invalid node label and annotations:
```
labels:
    node.longhorn.io/create-default-disk: "config"
},
annotations:
    node.longhorn.io/default-disks-config:
        '[{"path":"<non-existing data path>","allowScheduling":false},
    node.longhorn.io/default-node-tags: '["slow",".*invalid-tag"]'
```
Then they should find that the tag and disk list are still empty.

8. The users create a random data path then correct the annotation for the node:
```
annotations:
    node.longhorn.io/default-disks-config:
        '[{"path":"<random data path>","allowScheduling":false},
    node.longhorn.io/default-node-tags: '["slow","storage"]'
```
Now they will see that the node tags and disks are created correctly and match the annotations.

### Upgrade strategy

N/A.
