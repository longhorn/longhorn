# Volume Deletion Flows

## Summary
This enhancement modifies the flow a user would follow for handling deletion of `Volumes` that are `Attached` or otherwise have resources such as a `Persistent Volume` associated with them. Specifically, this adds warnings in the `longhorn-ui` when deleting a `Volume` in these specific cases and provides a means for the `longhorn-manager` to clean up any leftover resources in `Kubernetes` associated with a deleted `Volume`.

### Related Issues
https://github.com/longhorn/longhorn/issues/520

## Motivation

### Goals
The goal of this enhancement is to either address or warn users about situations in which deleting a `Volume` could cause potential problems. In handling the case of cleaning up an associated `Persistent Volume` (and possibly `Persistent Volume Claim`), we can prevent there being leftover unusable `Volume`-related resources in `Kubernetes`. In warning about deletion when the `Volume` is attached, we can inform the user about possible consequences the deletion would have on existing workloads so the user can handle this accordingly.

### Non-Goals
This enhancement is not intended on completely blocking a user from pursuing any dangerous operations. For example, if a user insists on deleting a currently attached `Volume`, they should not be forbidden from doing so in case the user is absolutely sure that they want to follow through.

## Proposal
When a user wishes to delete a `Volume` from the `Longhorn UI`, the system should check to see if the `Volume` has a resource tied to it or is currently `Attached`:
- If the `Volume` is `Attached`, the user should be warned about the potential consequences of deleting the `Volume` (namely that any applications currently using the `Volume` will no longer have access to it and likely error out) before they can confirm the deletion or cancel it.
- If the `Volume` is tied to a `Volume` that is tied to a `Persistent Volume` (and possibly a `Persistent Volume Claim`), the user should be informed of this information and the fact that we will clean up those resources if the `Volume` is deleted. If the `Volume` is tied to a `Persistent Volume Claim`, the user should also be warned that there may be `Deployments` or `Stateful Sets` that depend on this `Volume` that could no longer work should the user delete the `Volume` (we cannot explicitly see this without having to monitor all `Deployments` and `Stateful Sets` to check if they use a `Longhorn`-backed `Persistent Volume Claim`). Afterwards, the user can confirm the deletion if they wish, which will lead to cleanup of the associated resources and deletion of the `Volume`.

### User Stories
#### Deletion of Volumes with Associated Resources
Before, a user deleting a `Volume` through the `longhorn-ui` would only face the default confirmation message. The user would see the related `Persistent Volume` (and possibly `Persistent Volume Claim`) from the `Volume` listing, but this information would not be displayed in the confirmation message, and on deletion, these resources would still exist, which could raise problems if a user attempted to use these in a workload since they would refer to a nonexistent `Volume`.

After this enhancement, the user would be alerted about the existence of these resources and the fact that deletion of the `Volume` would lead to cleanup of these resources. The user can decide as normal whether to follow through with deletion of the `Volume` from the `longhorn-ui` or not.

#### Deletion of an Attached Volume
Before, a user deleting a `Volume` that was `Attached` would only face the default confirmation message in the `longhorn-ui`. The fact that the `Volume` was `Attached` would not be indicated in the confirmation message, and the user could potentially cause errors in applications using the `Volume` without any warnings. 

After this enhancement, a user would be alerted about the `Volume` being `Attached` and would be able to decide on a course of action for `Volume` deletion and handling of any applications using the `Volume` accordingly.

### User Experience In Detail
#### Deletion of Volumes with Associated Resources
1. The user attempts to delete a `Volume` that has a `Persistent Volume` (and potentially a `Persistent Volume Claim`) associated with it.
2. The confirmation message will appear, asking the user to confirm the operation. Additionally, the message will tell the user that the `longhorn-manager` will delete the `Kubernetes` resources associated with the `Volume`. If the `Volume` is additionally tied to a `Persistent Volume Claim`, the user will also be warned about possible adverse effects for any `Deployments` or `Stateful Sets` that may be using that `Volume`.
3. The user can now follow through with one of two options:
    - They can press `Cancel`, which will do nothing and take them back to the `Volume` listing.
    - They can press `Confirm` to follow through with the operation. The `longhorn-manager` will process deletion of the `Volume` and automatically clean up any associated `Persistent Volume` or `Persistent Volume Claim`.

#### Deletion of an Attached Volume
1. The user attempts to delete a `Volume` from the `longhorn-ui` that is currently `Attached`.
2. The confirmation message will appear, telling the user that the `Volume` is `Attached` and that deleting the `Volume` can lead to errors in any applications using the `Volume`.
    - If the `Volume` is also attached to a `Kubernetes` workload (we can determine this from the `Kubernetes Status`) 
3. The user can now follow through with one of two options:
    - They can press `Cancel`, which will do nothing and take them back to the `Volume` listing.
    - They can press `Confirm` to follow through with the operation. The `longhorn-manager` will process deletion of the `Volume`. The user will be responsible for handling any errored applications that depend on the now-deleted `Volume`.

### API Changes
From an API perspective, the call made to delete the `Volume` should look the same. The logic for handling deletion of any `Persistent Volume` or `Persistent Volume Claim` should go into the `Volume Controller`.

## Design
### Implementation Overview
1. `longhorn-ui` changes:
    - When a user attempts to delete a `Volume`:
        - If the `Volume` has an associated `Persistent Volume` and possibly `Persistent Volume Claim`, add an additional warning to the confirmation dialog regarding cleanup of these resources.
        - If the `Volume` is `Attached`, add an additional warning to the confirmation dialog regarding possible errors that may occur that the user should account for.
2. `longhorn-manager` changes:
    - In the `Volume Controller`, if a `Volume` has a `Deletion Timestamp`, check the `Kubernetes Status` of the `Volume`:
        - If there is a `Persistent Volume`, delete it.
        - If there is a `Persistent Volume Claim`, delete it.

### Test Plan
A number of integration tests will need to be added for the `longhorn-manager` in order to test the changes in this proposal:
1. From the API, create a `Volume` and then create a `Persistent Volume` and `Persistent Volume Claim`. Wait for the `Kubernetes Status` to be populated. Attempt to delete the `Volume`. Both the `Persistent Volume` and `Persistent Volume Claim` should be deleted as well.
2. Create a `Storage Class` for `Longhorn` and use that to provision a new `Volume` for a `Persistent Volume Claim`. Attempt to delete the `Volume`. Both the `Persistent Volume` and `Persistent Volume Claim` should be deleted as well.

Additionally, some manual testing will need to be performed against the `longhorn-ui` changes for this proposal:
1. From the `longhorn-ui`, create a new `Volume` and then create a `Persistent Volume` for that `Volume`. Attempt to delete the `Volume`. The dialog box should indicate the user that there will be `Kubernetes` resources that will be deleted as a result.
2. From the `longhorn-ui`, create a new `Volume` and then `Attach` it. Attempt to delete the `Volume`. The dialog box should indicate that the `Volume` is in use and warn about potential errors.
3. Use `Kubernetes` to create a `Volume` and use it in a `Pod`. Attempt to delete the `Volume` from the `longhorn-ui`. Multiple warnings should show up in the dialog box, with one indicating removal of the `Kubernetes` resources and the other warning about the `Volume` being in use.

### Upgrade strategy
No special upgrade strategy is necessary. Once the user upgrades to the new version of `Longhorn`, these new capabilities will be accessible from the `longhorn-ui` without any special work.

### Notes
- There is interest in allowing the user to decide on whether or not to retain the `Persistent Volume` (and possibly `Persistent Volume Claim`) for certain use cases such as restoring from a `Backup`. However, this would require changes to the way `go-rancher` generates the `Go` client that we use so that `Delete` requests against resources are able to take inputs.
- In the case that a `Volume` is provisioned from a `Storage Class` (and set to be `Deleted` once the `Persistent Volume Claim` utilizing that `Volume` has been deleted), the `Volume` should still be deleted properly regardless of how the deletion was initiated. If the `Volume` is deleted from the UI, the call that the `Volume Controller` makes to delete the `Persistent Volume` would only trigger one more deletion call from the `CSI` server to delete the `Volume`, which would return successfully and allow the `Persistent Volume` to be deleted and the `Volume` to be deleted as well. If the `Volume` is deleted because of the `Persistent Volume Claim`, the `CSI` server would be able to successfully make a `Volume` deletion call before deleting the `Persistent Volume`. The `Volume Controller` would have no additional resources to delete and be able to finish deletion of the `Volume`.
