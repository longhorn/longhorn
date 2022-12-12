# Filesystem Trim

## Summary
Longhorn can reclaim disk space by allowing the filesystem to trim/unmap the unused blocks occupied by removed files.

### Related Issues
https://github.com/longhorn/longhorn/issues/836

## Motivation
### Goals
1. Longhorn volumes support the operation `unmap`, which is actually the filesystem trim. 
2. Since some unused blocks are in the snapshots, these blocks can be freed if the snapshots is no longer required.

## Proposal
1. Longhorn tgt should support module `UNMAP`. When the filesystem of a Longhorn volume receives cmd `fstrim`, the iSCSI initiator actually sends this `UNMAP` requests to the target.
   To understand the iscsi protocol message of `UNMAP` then start the implementation, we can refer to Section "3.54 UNMAP command" of [the doc](https://www.seagate.com/files/staticfiles/support/docs/manual/Interface%20manuals/100293068j.pdf).
2. By design, snapshots of a Longhorn volume are immutable and lots of the blocks of removed files may be in the snapshots. 
   This implicitly means we have to skip these blocks and free blocks in the current volume head only if we do nothing else. It will greatly degrade the effectiveness of this feature.
   To release as much space as possible, we can do unmap for all continuous unavailable (removed or system) snapshots behinds the volume head, which is similar to the snapshot prune operation.
3. Longhorn volumes won't mark snapshots as removed hence most of the time there is no continuous unavailable snapshots during the trim. 
   To make it more practicable, we introduce a new global setting for all volumes. It automatically marks the latest snapshot and its ancestors as removed and stops at the snapshot containing multiple children. 
   Besides, there is a per-volume option that can overwrite the global setting and directly indicate if this automatic removal is enabled. By default, it will be ignored and the volumes follow the global setting.     

### User Stories
#### Reclaim the space wasted by the removed files in a filesystem
Before the enhancement, there is no way to reclaim the space. To shrink the volume, users have to launch a new volume with a new filesystem, and copy the existing files from the old volume filesystem to the new one, then switch to use the new volume. 

After the enhancement, users can directly reclaim the space by trimming the filesystem via cmd `fstrim` or Longhorn UI. Besides, users can enable the new option so that Longhorn can automatically mark the snapshot chain as removed then trim the blocks recorded in the snapshots.  

### User Experience In Detail
1. Users can enable the option for a specific volume by modifying the volume option `volume.Spec.UnmapMarkSnapChainRevmoed`, or directly set the global setting `Remove Snapshots During Filesystem Trim`.
2. For an existing Longhorn volume that contains a filesystem and there are files removed from the filesystem, users can directly run cmd `fstrim <filesystem mount point>` or Click Longhorn UI button `Trim Filesystem`.
3. Users will observe that the snapshot chain are marked as removed. And both these snapshots and the volume head will be shrunk.

### API Changes
- Volume APIs: 
  - Add `updateUnmapMarkSnapChainRemoved`: Control if Longhorn will remove snapshots during the filesystem trim, or just follows the global setting.
  - Add `trimFilesystem`: Trim the filesystem of the volume. Best Effort.
- Engine APIs:
  - Add `unmap-mark-snap-chain-removed`: `--enable` or `disable`. Control if the engine and all its replicas will mark the snapshot chain as removed once receiving a `UNMAP` request.

## Design
### Implementation Overview
#### longhorn-manager:
1. Add a setting `Remove Snapshots During Filesystem Trim`.
2. Add fields for CRDs: `volume.Spec.UnmapMarkSnapChainRemoved`, `engine.Spec.UnmapMarkSnapChainRemoved`, `replica.Spec.UnmapMarkDiskChainRemoved`.
3. Add 2 HTTP APIs mentioned above: `updateUnmapMarkSnapChainRemoved` and `trimFilesystem`. 
4. Update controllers .
    1. `Volume Controller`:
        1. Update the engine and replica field based on `volume.Spec.UnmapMarkSnapChainRemoved` and the global setting. 
        2. Enqueue the change for the field and the global setting. 
    2. `Engine Controller`:
        1. The monitor thread should compare the CR field `engine.Spec.UnmapMarkSnapChainRemoved` with the current option value inside the engine process, 
           then call the engine API `unmap-mark-snap-chain-removed` if there is a mismatching.
        2. The process creation function should specify the option `unmap-mark-snap-chain-removed`.
    3. `Replica Controller`:
        1. The process creation function should specify the option `unmap-mark-disk-chain-removed`.

#### longhorn-engine:
1. Update dependency `rancher/tgt`, `longhorn/longhornlib`, and `longhorn/sparse-tools` for the operation `UNMAP` support.
2. Add new option `unmap-mark-snap-chain-removed` for the engine process creation call. 
   Add new option `unmap-mark-disk-chain-removed` for the replica process creation call.
3. Add a new API `unmap-mark-snap-chain-removed` to update the field for the engine and all its replicas.
4. The engine process should be able to recognize the request of `UNMAP` from the tgt, then forwards the requests to all its replicas via the dataconn service. This is similar to data R/W.
5. When each replica receive a trim/unmap request, it should decide if the snapshot chain can be marked as removed, then collect all trimmable snapshots, punch holes to these snapshots and the volume head, then calculate the trimmed space.

#### instance-manager:
- Update the dependencies.
- Add the corresponding proxy API for the new engine API.

#### longhorn-ui:
1. Add 2 new operations for Longhorn volume.
   - API `updateUnmapMarkSnapChainRemoved`: 
     - The backend accepts 3 values of the input `UnmapMarkSnapChainRemoved`: `"enabled"`, `"disabled"`, `"ignored"`.
     - The UI can rename this option to `Remove Current Snapshot Chain during Filesystem Trim`, and value `"ignored"` to `follow the global setting`.
   - API `trimFilesystem`: No input is required.
2. The volume creation call accepts a new option `UnmapMarkSnapChainRemoved`. This is almost the same as the above update API.

### Test Plan
#### Integration tests
Test if the unused blocks in the volume head and the snapshots can be trimmed correctly without corrupting other files, and if the snapshot removal mechanism works when the option is enabled or disabled. 

#### Manual tests
Test if the filesystem trim works correctly when there are continuous writes into the volume.

### Upgrade strategy
N/A
