# SPDK Batched Dirty Recovery

## Summary

Batched recovery aims to reduce Longhorn V2 lvstore recovery time by scanning SPDK blobstore metadata in larger reads and replaying blob metadata chains concurrently. It rebuilds allocation masks serially, preserves the existing on-disk format, and allows failed loads to be retried.

### Related Issues

[longhorn/longhorn#12837](https://github.com/longhorn/longhorn/issues/12837)

## Motivation

Serial recovery scans metadata one page at a time. A large lvstore can reserve a large metadata region even when it contains few blobs, so recovery spends substantial time issuing small reads. Chunk reads and concurrent chain replay reduce this I/O overhead.

### Goals

- Reduce recovery time with larger metadata reads and concurrent replay.
- Preserve data correctness through page validation and serial allocation accounting.
- Support safe fallback when batched recovery cannot allocate its working state.

### Non-goals

- Change the blobstore format or parallelize global mask updates.
- Introduce a Longhorn setting or redesign recovery memory management.

## Proposal

### User Stories

As a Longhorn operator, I want V2 lvstores to recover faster after an instance-manager crash while preserving persisted data. If recovery encounters unreadable or invalid referenced metadata, I want the load to fail so it can be retried after the problem is resolved.

### User Experience In Detail

Recovery runs automatically after an unclean shutdown. It also runs when `force_recover` is requested or an older format lacks a persisted blobid mask. Normal clean loads continue reading the persisted masks. No new Longhorn user configuration is required.

### API changes

Add `recovery_qd` to `spdk_bs_opts`, defaulting to `16`. Values greater than `1` enable batched scan and replay; `0` or `1` selects serial recovery. Developers can use `1` for comparison or rollback.

## Design

### Object Model

The validated superblock locates the blob metadata region `[md_start, md_start + md_len)`, which excludes the superblock and persisted masks. Each blob has a root and optional continuation pages. Their descriptors reference data clusters directly or through separate extent pages. The following example shows a blob using extent pages:

```text
+------------------------------+
| Blobstore                    |
| superblock + persisted masks |
+---------------+--------------+
                | metadata region
                v
          +-----------+  next  +--------------------+
          | Blob root |------->| Continuation pages |
          +-----------+        +---------+----------+
                                         | extent-table reference
                                         v
                                 +---------------+      +---------------+
                                 | Extent pages  |----->| Data clusters |
                                 +---------------+      +---------------+
```

After an unclean shutdown, recovery rebuilds `used_md_pages`, `used_blobids`, `used_clusters`, and the free-cluster count from discovered metadata chains.

### Implementation Overview

```text
               [Chunk scan: roots + optional summaries]
                                  |
                                  v
                      [Prepare summary replay]
                         /                  \
                     ready              unavailable
                       v                     v
                [Range replay]    [Standard batched replay]
                         \                  /
                          v                v
                        [Serial mask rebuild]
                                  |
                                  v
                   [Write dirty marker if needed]
                                  |
                                  v
                     [Write masks -> Blob iteration]
```

1. **Discover roots.** Read up to 256 consecutive metadata pages per I/O, with `scan_qd = min(recovery_qd, number_of_chunks)`. A root must have a valid CRC, sequence number zero, and a blob ID matching its page index; extent pages are excluded. Invalid discovery candidates are skipped because the region also contains unused and stale pages. Optional summaries record each valid non-extent page's blob ID, sequence number, and next-page pointer.
2. **Replay chains.** Prefer deriving complete chain page lists from summaries, then read consecutive pages together, up to 256 pages per range and `scan_qd` ranges per batch. Revalidate each page's CRC, blob ID, sequence, and next link. If summary preparation fails before replay reads begin, follow `page->next` with one read per active chain and at most `min(recovery_qd, chain_count)` active chains. Both paths retain validated chain pages for commit.
3. **Rebuild and persist masks.** Process chains in root-page order, rejecting duplicate blob IDs or chain pages. Read and validate referenced extent pages in a batch per chain; these reads are not capped by `recovery_qd`. Before writing masks, validate allocation accounting, including that blob data does not occupy metadata-reserved clusters.

Interrupted snapshot operations can legitimately leave roots sharing extent pages or physical clusters. Recovery counts shared storage once, then the existing blob iteration examines snapshot markers and relationships to perform repair.

No recovery masks are written until all discovered chains and their extent pages pass recovery validation. If the superblock is clean, write `clean = 0` and wait for successful completion before submitting the mask writes. Write the page, blobid, and cluster masks in sequence, omitting the blobid mask for pre-v3 formats. A later mask-write failure does not mark the store clean; a dirty superblock on the next load triggers recovery again. This follows the existing blobstore assumptions about backend persistence and atomic writes.

Recovery validates discovered chains and allocation metadata. Discovery keeps serial recovery's treatment of unused or invalid candidates; referenced pages must pass replay validation. Full blob loading and snapshot repair follow mask reconstruction through the existing load path.

I/O sizes and DMA buffer offsets use the on-disk `md_page_size`. A full 256-page chunk is 1 MiB with 4 KiB pages or 4 MiB with 16 KiB pages.

### Why Parallel Reads Are Safe

Parallelism means multiple outstanding asynchronous reads. Recovery uses the metadata channel created on the thread calling `spdk_bs_load()`. The existing SPDK bdev completion mechanism returns callbacks to that thread, so recovery callbacks and bookkeeping execute serially even while device reads overlap.

In the normal Longhorn startup and restart flow, blobstore recovery finishes before the lvstore exposes its lvol bdevs and the RAID bdevs built on them begin serving I/O. These upper layers therefore do not modify the recovering metadata during scan and replay. The existing bdev thread model and lvstore load sequence already provide the conditions needed for parallel reads; batched recovery requires no additional application synchronization.

- **Scan ranges are known upfront.** The superblock provides the metadata region boundaries, so reading one chunk does not depend on the contents of another chunk.
- **Chains can be read independently.** Standard batched replay keeps the dependent `page->next` traversal serial within each chain while reading different chains concurrently. Summary replay already knows each chain's page list, so it can also submit multiple ranges from the same chain together. Every page is still revalidated after reading.
- **Read buffers are separate.** Each outstanding batched read has its own DMA buffer slot. Recovery processes successful batches in slot order only after the batch is closed and all reads have completed. Failed scan batches are then retried one page at a time. Buffers are never reused while their reads remain outstanding.

Scan and replay only collect temporary state. Global allocation masks and cluster counts are rebuilt later in root-page order, rejecting duplicate chain pages and counting shared extent pages or physical clusters once.

### Fallback and Error Handling

| Scenario | Behavior |
| --- | --- |
| Summaries are unavailable, chain lists cannot be built, or summary replay setup allocation fails | Use standard batched replay with the same discovered roots, before summary replay reads begin. |
| A scan chunk read fails | Retry every page in the current scan batch with single-page reads using `md_page_size`. Resume scanning if all retries succeed; otherwise fail the load. |
| Other batched working-state allocation fails or its buffer size cannot be represented | Release batched state and restart serial recovery from the beginning. Clear partial masks, reset cluster accounting, and release extent scratch buffers first. |
| Replay/extent read fails, a referenced page fails validation, or commit detects invalid metadata/accounting | Fail the load without writing recovery masks. Validation errors do not trigger serial fallback. |
| Serial recovery or finalization allocation/write fails | Return an error. If writing the dirty marker fails, no masks are submitted. A dirty superblock on the next load triggers recovery again. |

Serial recovery also validates referenced chain and extent pages and shares the final allocation checks and mask-write ordering. Fallback is a one-way switch for that load attempt; serial failure does not restart batched recovery.

Fallback from a batch completion callback runs only after the batch is closed and all its reads have completed. The caller returns immediately after fallback without accessing released contexts or buffers. This remains safe when serial callbacks execute inline.

### Memory Tradeoff

Scan buffers use `scan_qd * min(256, md_len) * md_page_size` bytes and are reused for summary range reads. The optional summary map scales with `md_len`. Saved chain pages retain the 4 KiB metadata payload per page, plus indexes and allocation overhead, even when the on-disk stride is larger.

Total memory is not bounded by QD: all replayed chain pages remain allocated until the batched context is released. This is an accepted tradeoff between memory use and recovery speed. Performance depends on metadata layout and device behavior; fewer scan I/Os do not imply a fixed end-to-end speedup.

### Test plan

#### Unit tests

- Compare recovered blobs, data, allocation masks, and free-cluster counts between serial and batched recovery, including snapshots and 4 KiB/16 KiB metadata pages.
- Inject scan/replay read failures, invalid referenced pages, and allocation failures. Verify the expected retry, fallback, or load failure and that failed validation does not write masks.
- Interrupt forced recovery during mask writes and verify that a subsequent normal load repeats recovery successfully.

#### Integration tests

- Create and attach a V2 volume.
- Write a file to the volume and sync it to disk.
- Compute and record the file hash.
- Keep additional writes running on a separate file and abruptly restart the instance-manager until the logs confirm dirty recovery. A graceful restart can unload the store cleanly and may not exercise recovery.
- After recovery, read the baseline file with the filesystem cache bypassed and compute its hash again.
- Verify that the hash matches the recorded hash.
