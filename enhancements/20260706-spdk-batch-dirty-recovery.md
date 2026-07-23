# SPDK Batched Dirty Recovery

## Summary

Introduce a batched dirty recovery path for SPDK blobstore. The new path is enabled by
default through SPDK blobstore options, with an internal rollback knob for development
and validation. It reduces dirty recovery time by:

- Scanning the blob metadata page region with larger contiguous reads.
- Replaying discovered blob metadata chains with bounded concurrency.
- Keeping commit serial and reusing the existing metadata parse and used-mask write path.

This targets Longhorn V2/SPDK recovery cases where a large lvstore has a large blob
metadata page region but only a small number of active lvols/blobs.

Related issue: https://github.com/longhorn/longhorn/issues/12837

## Problem

The current dirty recovery path, `bs_load_replay_md()`, scans blob metadata one page at a
time:

```
┌─────────────────────────────────────────┐
│   Legacy Serial Recovery Loop           │
├─────────────────────────────────────────┤
│                                         │
│  1. Read one metadata page (4 KB I/O)   │
│     ↓                                   │
│  2. Validate CRC and root-page fields   │
│     ↓                                   │
│  3. If root page:                       │
│       → Replay its chain                │
│       → Commit it                       │
│     ↓                                   │
│  4. Continue with next unclaimed page   │
│     ↓                                   │
│  Repeat for all md_len pages            │
│                                         │
└─────────────────────────────────────────┘
```

For a 512 GiB blobstore with 1 MiB clusters, SPDK's default metadata sizing reserves one
metadata page per cluster:

```
┌─────────────────────────────────────┐
│  Example: 512 GiB Blobstore         │
├─────────────────────────────────────┤
│  md_len         = 524,288 pages     │
│  md_page_size   = 4 KiB             │
│  scan size      = 2 GiB             │
└─────────────────────────────────────┘
```

The legacy path therefore issues hundreds of thousands of small 4 KiB device reads. On
some NVMe devices this low-QD/small-I/O pattern is much slower than the device's normal
sequential read capability.

## Goals

- Reduce dirty recovery scan time by reducing device I/O count and improving I/O size.
- Preserve recovery correctness by keeping metadata validation at page granularity.
- Keep all global state mutation serial during commit.
- Provide a safe fallback to the existing serial recovery path.
- Avoid changing the on-disk blobstore format.

## Non-Goals

- Change clean recovery.
- Change blobstore or lvol metadata layout.
- Parallelize commit/global state updates.
- Optimize normal SPDK read/write I/O paths.

## Relevant Blobstore Layout

### Key Concepts

**Blobstore** = A logical storage pool backed by one block device.

**Blob** = A logical volume (lvol) backed by metadata + data clusters. Each blob has a unique blob ID.

**Cluster** = Data allocation unit (typically 1 MiB). Blobs allocate data in cluster granularity.

**Page** = Metadata allocation unit (4 KiB). Blob metadata is stored as a chain of pages.

**Relationship:**
- One blobstore contains many blobs.
- One blob = one metadata chain (linked pages) + N data clusters.
- `total_clusters = blobstore_size / cluster_size` (blobstore.c:11363)
- `md_len ≈ total_clusters` (default: one metadata page reserved per cluster)
- Metadata region itself occupies some clusters, reducing usable data clusters.

### Super Block Structure

The SPDK blobstore super block contains separate page ranges for persisted masks and blob
metadata pages:

```c
struct spdk_bs_super_block {
    uint32_t used_page_mask_start;
    uint32_t used_page_mask_len;
    uint32_t used_cluster_mask_start;
    uint32_t used_cluster_mask_len;
    uint32_t md_start;
    uint32_t md_len;
    uint32_t used_blobid_mask_start;
    uint32_t used_blobid_mask_len;
};
```

During blobstore creation, SPDK lays out the front metadata area in this order:

```
┌──────────────────────────────────────────────────────┐
│         Blobstore On-Disk Layout (Front)             │
├──────────────────────────────────────────────────────┤
│                                                      │
│  ┌────────────────┐                                  │
│  │  Super Block   │  (Fixed, 4 KB)                   │
│  └────────────────┘                                  │
│  ┌──────────────────────────┐                        │
│  │  used_md_pages mask      │  (Variable)            │
│  └──────────────────────────┘                        │
│  ┌──────────────────────────┐                        │
│  │  used_clusters mask      │  (Variable)            │
│  └──────────────────────────┘                        │
│  ┌──────────────────────────┐                        │
│  │  used_blobids mask       │  (Variable)            │
│  └──────────────────────────┘                        │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │  Blob Metadata Page Region (CONTIGUOUS)      │    │
│  │  [md_start, md_start + md_len]               │    │
│  │                                              │    │
│  │  • Root metadata pages                       │    │
│  │  • Continuation metadata pages               │    │
│  │  • Extent metadata pages                     │    │
│  │  • Unused/stale/invalid pages                │    │
│  └──────────────────────────────────────────────┘    │
│                                                      │
│  ... Data clusters follow ...                        │
│                                                      │
└──────────────────────────────────────────────────────┘
```

The region `[md_start, md_start + md_len)` contains blob metadata pages used by
blob/lvol metadata chains:

- Root metadata pages.
- Continuation metadata pages.
- Extent metadata pages.
- Unused, stale, zeroed, or invalid metadata pages.

It does not include the super block or the persisted used masks.

Blob metadata page indexes are local to this region. The device LBA is derived by adding
`md_start`:

```c
static inline uint64_t
bs_md_page_to_lba(struct spdk_blob_store *bs, uint32_t page)
{
    assert(page < bs->md_len);
    return bs_page_to_lba(bs, page + bs->md_start);
}
```

This linear mapping is the basis for chunk reads. Reading metadata pages `[N, N + count)`
maps to one contiguous disk range starting at `bs_md_page_to_lba(bs, N)`.

## Dirty Recovery Trust Boundary

Dirty recovery still starts by reading and validating the super block. The super block is
needed to locate:

- The blob metadata page region.
- The persisted used masks.
- Blobstore parameters such as cluster size and metadata page size.

After an unclean shutdown, persisted used masks are not treated as the final source of
truth. Dirty recovery rebuilds in-memory `used_md_pages`, `used_blobids`, and
`used_clusters` from blob metadata chains, then writes rebuilt masks at the end.

## Design

### Overview: Three-Phase Pipeline

```
┌────────────────────────────────────────────────────────────────────┐
│                 BATCHED DIRTY RECOVERY FLOW                        │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓     │
│  ┃ PHASE 1: SCAN (Parallel)                                  ┃     │
│  ┃ Goal: Discover all root metadata pages                    ┃     │
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛     │
│                                                                    │
│  Input:  Metadata region [0, md_len]                               │
│  Method: Chunk reads (256 pages = 1 MB per I/O)                    │
│  QD:     scan_qd = min(recovery_qd, num_chunks)                    │
│                                                                    │
│  ┌──────────┐  ┌──────────┐       ┌──────────┐                     │
│  │ Chunk 0  │  │ Chunk 1  │  ...  │ Chunk N  │                     │
│  │ 256 pgs  │  │ 256 pgs  │       │ 256 pgs  │                     │
│  │  1 MB    │  │  1 MB    │       │  1 MB    │                     │
│  └────┬─────┘  └────┬─────┘       └────┬─────┘                     │
│       │             │                   │                          │
│       └─────────────┴───────────────────┘                          │
│                     │                                              │
│       Read all chunks in parallel (up to scan_qd at once)          │
│                     │                                              │
│       Scan each chunk in memory for valid root pages:              │
│         ✓ CRC matches                                              │
│         ✓ sequence_num == 0                                        │
│         ✓ page->id == bs_page_to_blobid(page_num)                  │
│         ✗ Skip CRC mismatches (not fallback)                       │
│                     │                                              │
│  Output: root_pages[] = [100, 5000, ...]                           │
│                                                                    │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓     │
│  ┃ PHASE 2: REPLAY (Parallel)                                ┃     │
│  ┃ Goal: Reconstruct complete metadata chains                ┃     │
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛     │
│                                                                    │
│  Input:  root_pages[] and page_summaries[] from Phase 1            │
│  Method: Prefer summary-derived range replay, otherwise            │
│          standard page-by-page chain replay                        │
│  QD:     up to scan_qd range reads or replay_qd chain reads        │
│                                                                    │
│  Summary replay decision:                                          │
│    ├─ Build every chain page list from page_summaries[]            │
│    ├─ Success: split page lists into read ranges                   │
│    │    ├─ consecutive pages → chunk read                          │
│    │    └─ scattered pages   → 1-page range                        │
│    └─ Failure: use standard batched replay                         │
│                                                                    │
│  Standard replay fallback before summary replay starts:            │
│    └─ Follow page->next with up to replay_qd active chains         │
│                                                                    │
│  Runtime validation per page:                                      │
│         ✓ CRC matches                                              │
│         ✓ sequence_num matches chain position                      │
│         ✓ blob ID consistent within chain                          │
│         ✗ Any failure → FALLBACK to serial recovery                │
│                             │                                      │
│  Output: chains[] = complete metadata chains in memory             │
│                                                                    │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓     │
│  ┃ PHASE 3: COMMIT (Serial)                                  ┃     │
│  ┃ Goal: Update global blobstore state                       ┃     │
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛     │
│                                                                    │
│  Input:  chains[] from Phase 2                                     │
│  Method: Serial commit, reuse legacy parse logic                   │
│                                                                    │
│  for each chain:                                                   │
│    ├─ Verify blob ID not duplicate                                 │
│    ├─ Claim metadata pages                                         │
│    ├─ Mark used_blobids[blob_page] = true                          │
│    ├─ Parse with bs_load_replay_md_parse_page()  ← Reuse legacy    │
│    └─ If extent pages: bs_recovery_read_extent_pages()             │
│                                                                    │
│  after all chains:                                                 │
│    ├─ Claim metadata region clusters                               │
│    └─ bs_load_write_used_md()  ← Write masks once                  │
│                                                                    │
│  Output: Recovered blobstore with all blobs restored               │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘

Fallback Safety: summary build can fall back to standard batched replay before Phase 2
starts; runtime I/O or validation failures fall back to serial recovery.
```

### Phase 1: Scan Root Pages

Phase 1 discovers root metadata pages in `[0, md_len)`.

Instead of issuing one 4 KiB device read per metadata page, the batched path reads
contiguous chunks:

```text
scan_pages_per_io = min(256, md_len)
num_chunks = ceil(md_len / scan_pages_per_io)
scan_qd = min(recovery_qd, num_chunks)
```

For each submitted chunk:

```c
page_count = min(scan_pages_per_io, md_len - next_scan_page);
lba = bs_md_page_to_lba(bs, next_scan_page);
byte_count = page_count * md_page_size;
read byte_count bytes as one contiguous disk I/O;
```

After the chunk is in memory, recovery splits the buffer back into individual metadata
pages and validates each page independently:

```text
CRC must match
sequence_num must be 0
page->id must equal bs_page_to_blobid(page_num)
page must not be an extent page
```

Only valid root pages are recorded. A CRC mismatch during scan means "not a valid root
candidate" and is skipped, matching the discovery nature of this phase.

If a chunk scan I/O fails, Phase 1 does not immediately restart full serial recovery. It
locally retries the affected scan batch with single-page 4 KiB reads, records valid roots
from that range, and then continues chunk scanning. If the single-page retry also fails,
the recovery falls back to the legacy serial path.

Why this is safe:

- Chunk read changes only device I/O granularity.
- Metadata interpretation remains page-based.
- The chunk is never trusted as a single metadata object.
- Continuation and extent pages inside the chunk are ignored by scan and handled later
  through normal chain replay/commit logic.

### Page Summary

Phase 1 also records a compact summary for each CRC-valid, non-extent metadata page:

```c
struct bs_recovery_page_summary {
    spdk_blob_id id;
    uint32_t sequence_num;
    uint32_t next;
    bool valid;
};
```

The summary stores only the fields needed to reconstruct a metadata chain shape in
memory: blob id, page sequence, and next-page pointer. It does not store or replace the
full metadata page.

In Phase 2, recovery starts from each discovered root page and follows `summary.next` in
memory to build the root-reachable page list. That page list is then split into read
ranges: consecutive pages become chunk reads, while scattered pages become 1-page ranges.
This targets blobs with long metadata chains, where following the chain with many
individual 4 KiB device reads can become slow.

Example:

```text
Phase 1 summaries:
page 100: { id=A, sequence=0, next=101 }
page 101: { id=A, sequence=1, next=102 }
page 102: { id=A, sequence=2, next=900 }
page 900: { id=A, sequence=3, next=SPDK_INVALID_MD_PAGE }

Phase 2 builds:
chain A page list = [100, 101, 102, 900]

Then Phase 2 replays:
[100, 101, 102] -> one 3-page chunk read
[900]           -> one 1-page read
```

This works because Phase 1 has already read and CRC-checked the metadata page headers
while scanning the contiguous metadata region. The summary is still only a hint: Phase 2
must reread the selected pages from disk and validate the full metadata page before it is
accepted into the recovered chain.

### Phase 2: Replay Metadata Chains

Phase 2 creates one in-memory replay chain per discovered root page. It then makes one
decision before reading chain pages from disk:

```text
if page_summaries[] exists and every chain can be built from it:
    use summary-based batched range replay
else:
    use standard batched replay
```

This keeps fallback simple. Summary data is allowed to decide the optimized read plan
only before replay starts. Once a replay path starts reading chain pages from disk, any
I/O error or validation mismatch falls back to the legacy serial recovery path.

Validation is stricter in this phase:

```text
CRC must match
extent pages are not accepted as chain pages
sequence_num must match the chain position
root page id must match bs_page_to_blobid(root_page)
continuation page id must match the root blob id
next must be < md_len unless it is SPDK_INVALID_MD_PAGE
```

Unlike Phase 1, these pages are expected chain pages. Silently skipping a page could
produce an incomplete blob, so runtime uncertainty falls back to serial recovery.

#### Summary-Based Batched Range Replay

During Phase 1, recovery records only compact page summaries for CRC-valid metadata
pages: blob id, sequence number, and next-page pointer. These summaries are used as hints
to derive the root-reachable page list for each discovered chain before replay.

If every discovered chain can be derived from the summary, replay splits the page lists
into read ranges. Strictly consecutive pages become larger chunk I/Os capped by
`scan_pages_per_io`; non-consecutive pages become single-page ranges. Each batch submits
up to `scan_qd` ranges. The data is still revalidated page by page after the read and
copied into the normal in-memory chain. If the chain list cannot be built from the
summaries, recovery uses the standard Phase 2 replay instead. Once summary-assisted
replay starts reading chain pages from disk, any I/O error or page validation mismatch
falls back to the legacy serial recovery path.

This optimization is best-effort. It does not trust the Phase 1 summary as recovered
metadata. It only uses the summary to decide which metadata pages can be read as ranges.
Metadata page overlap between chains is still rejected by the normal validation and
serial commit checks.

#### Standard Batched Replay

If the summary map is not available or the chain list cannot be built from it, Phase 2
uses the standard batched replay path:

```text
replay_qd = min(recovery_qd, chain_count)
```

It keeps at most `replay_qd` chains active. For each active chain, it reads one metadata
page at a time, validates it, appends a copy to the in-memory chain, then follows
`page->next` until the chain ends.

This path does not depend on Phase 1 summaries. It is the conservative batched fallback
used before summary replay starts.

### Phase 3: Commit Serially

After all chains are replayed into memory, commit runs serially:

```text
for each replayed chain:
    verify blob id and metadata pages are not duplicates
    claim metadata pages
    mark used_blobids[blob_page]
    parse chain pages with bs_load_replay_md_parse_page()
    if extent pages were referenced:
        read and parse extent pages

after all chains:
    claim clusters backing the blobstore metadata area
    write rebuilt used masks once
```

Commit remains serial because it updates global blobstore state:

- `used_md_pages`
- `used_blobids`
- `used_clusters`
- `num_free_clusters`
- extent-page state collected by the existing parser

This keeps the risky part close to the legacy recovery behavior. Phase 1 and Phase 2 only
build temporary state.

## Configuration

Add `recovery_qd` to `struct spdk_bs_opts`:

```c
uint32_t recovery_qd;
```

Behavior:

- `0` or `1`: use legacy serial dirty recovery.
- `>1`: enable batched dirty recovery.
- Default: `16`.

This is an SPDK/internal configuration knob. It is not planned to be exposed as a
Longhorn user-facing setting. Longhorn should use the default batched behavior, while
developers can set `recovery_qd = 1` to compare or roll back to the legacy path during
testing.

The actual queue depth is capped by available work:

```c
static uint32_t
bs_recovery_qd(uint32_t configured_qd, uint32_t item_count)
{
    assert(item_count > 0);
    return spdk_min(configured_qd, item_count);
}
```

Examples:

```text
scan_qd = min(recovery_qd, number_of_scan_chunks)
replay_qd = min(recovery_qd, number_of_discovered_chains)
```

## Expected I/O Impact

### Comparison Table: 512 GiB Blobstore with 2 Volumes

**Configuration:**
- Blobstore size: 512 GiB
- Cluster size: 1 MiB
- Total clusters: 524,288
- Metadata pages: 524,288 (one per cluster)
- Metadata page size: 4 KiB
- Total metadata region: 2 GiB
- Active volumes: 2 (sparse allocation)

**I/O Pattern Comparison:**

| Metric | Legacy Serial | Batched (QD=16) | Improvement |
|--------|---------------|-----------------|-------------|
| **Phase 1: Scan** | | | |
| I/O count | 524,288 reads | 2,048 reads | **256x fewer** |
| I/O size | 4 KiB each | 1 MiB each | **256x larger** |
| Total data read | 2 GiB | 2 GiB | Same |
| Parallelism | Serial (QD=1) | QD=16 parallel | **16x concurrency** |
| Time (measured) | ~180 seconds | ~13 seconds | **~14x faster** |
| Throughput | ~11 MB/s | ~154 MB/s | **14x higher** |
| | | | |
| **Phase 2: Replay** | | | |
| I/O count | (interleaved) | 3 reads | N/A |
| I/O size | 4 KiB each | 4 KiB each | Same |
| Parallelism | Serial | QD=2 parallel | Parallel |
| Time | (interleaved) | <1 second | N/A |
| | | | |
| **Phase 3: Commit** | | | |
| I/O count | N/A | 0 (in-memory) | N/A |
| Time | (interleaved) | <1 second | N/A |
| | | | |
| **Total Recovery** | | | |
| Total time | ~180 seconds | ~15 seconds | **~12x faster** |
| Total I/Os | 524,291 | 2,051 | **256x fewer** |

### Key Insights

**Why chunk reading is faster:**

```
Legacy Approach:
  ┌────┐ ┌────┐ ┌────┐      ┌────┐
  │4 KB│ │4 KB│ │4 KB│ ···  │4 KB│  × 524,288 times
  └────┘ └────┘ └────┘      └────┘
  
  Each I/O:
    • Device seek/latency overhead
    • Small transfer inefficiency
    • No parallelism
    • Time per I/O: ~0.34 ms
    • Total: 524,288 × 0.34 ms ≈ 180 seconds

Batched Approach:
  ┌──────────────┐ ┌──────────────┐      ┌──────────────┐
  │   1 MB       │ │   1 MB       │ ···  │   1 MB       │  × 2,048 times
  │ (256 pages)  │ │ (256 pages)  │      │ (256 pages)  │
  └──────────────┘ └──────────────┘      └──────────────┘
       ↓ Parallel         ↓ Parallel           ↓ Parallel
    (16 at once)       (16 at once)          (16 at once)
  
  Each batch:
    • Larger sequential I/O (1 MB)
    • 16x parallelism
    • Better NVMe utilization
    • Time per batch: ~0.1 second
    • Total: 128 batches × 0.1 s ≈ 13 seconds
```

**Root discovery still inspects the same blob metadata page range.** The improvement comes from:
1. Reducing I/O count (256x fewer)
2. Larger I/O size (1 MB vs 4 KB)
3. Parallel I/O (QD=16 vs QD=1)
4. Moving page traversal from disk to memory

### Scalability Projection

**Assumptions:**
- NVMe device sequential read throughput: ~3 GB/s
- NVMe random 4 KiB read IOPS: ~500K IOPS
- Legacy serial recovery: limited by random 4 KiB IOPS (~11 MB/s actual)
- Batched recovery: limited by sequential read throughput (~154 MB/s with QD=16)
- Cluster size: 1 MiB (one metadata page per cluster)

| Blobstore Size | md_len (pages) | Legacy Time | Batched Time (est.) | Speedup |
|----------------|----------------|-------------|---------------------|---------|
| 512 GiB | 524,288 | ~180 s (~3 min) | ~15 s | ~12x |
| 1 TiB | 1,048,576 | ~360 s (~6 min) | ~26 s | ~14x |
| 2 TiB | 2,097,152 | ~720 s (~12 min) | ~52 s | ~14x |
| 4 TiB | 4,194,304 | ~1440 s (~24 min) | ~104 s (~2 min) | ~14x |
| 16 TiB | 16,777,216 | ~5760 s (~96 min) | ~416 s (~7 min) | ~14x |

The speedup remains consistently around **10-15x** across different blobstore sizes because:
- Legacy recovery is **IOPS-bound** (random 4 KiB reads)
- Batched recovery is **bandwidth-bound** (sequential 1 MiB reads)
- NVMe devices deliver much higher bandwidth than random IOPS at small block sizes

## Memory Usage

The batched path does not keep the whole blob metadata page region in memory.

Scan buffer:

```text
scan_qd * scan_pages_per_io * md_page_size
default = 16 * 256 * 4 KiB = 16 MiB
```

Standard replay buffer:

```text
replay_qd * md_page_size
```

Summary replay reuses the scan buffer as fixed-size per-range slots:

```text
scan_qd * scan_pages_per_io * md_page_size
```

Each submitted summary range uses one slot. This may waste memory when a range contains
only one page, but it keeps completion bookkeeping simple and remains bounded by the scan
buffer size.

Summary range slots:

```text
scan_qd * sizeof(summary slot)
```

Summary map:

```text
md_len * sizeof(page summary)
```

The summary map is optional. If allocation fails, recovery disables summary-assisted
replay and continues with the standard batched replay path. For a 512 GiB lvstore with
1 MiB clusters, this is roughly 524,288 summary entries, or about 12 MiB depending on
structure padding.

Collected chains:

```text
sum(all replayed metadata chain pages) * md_page_size
```

For sparse Longhorn lvstores this is typically much smaller than the full metadata scan
region. A workload with many blobs or unusually long metadata chains will use more memory
because Phase 2 collects chains before Phase 3 commits them.

## Fallback and Error Handling

The design separates fallback into two categories:

```text
Pre-replay optimization fallback:
    summary is unavailable or incomplete
    -> use standard batched replay

Runtime safety fallback:
    an active replay/commit path observes I/O or validation failure
    -> use legacy serial recovery
```

This avoids multiple partial replay reset paths while still allowing the optimized path
to be skipped when its summary hints are not usable.

### Phase 1 Fallback

Phase 1 is a discovery phase. It scans metadata pages to find valid roots and to collect
optional page summaries. A CRC mismatch for an individual scanned page means "not a valid
root or summary candidate" and is skipped.

If a chunk scan I/O fails, recovery does not immediately fall back to serial recovery.
Instead, it retries the current scan batch with single-page reads:

```text
chunk scan I/O failed
-> retry pages in that scan batch as 4 KiB metadata-page reads
-> continue chunk scanning if retry succeeds
-> legacy serial recovery if retry also fails
```

This is safe because Phase 1 has not committed any blobstore state. It only builds
temporary `root_pages[]` and `page_summaries[]`.

### Phase 2 Fallback

Before Phase 2 reads chain pages from disk, summary replay can be skipped safely:

```text
page_summaries[] missing
or chain list cannot be built from summaries
-> reset local chain scratch state
-> use standard batched replay
```

This fallback keeps the same root list discovered by Phase 1 and does not discard the
whole recovery attempt because no Phase 2 chain data has been replayed yet.

After Phase 2 starts reading chain pages, failures are treated as runtime safety failures:

```text
summary range read failed
or summary replay page validation mismatch
or standard replay page read/validation failed
-> legacy serial recovery
```

This is intentional. Once summary replay has committed to a summary-derived page list, a
runtime mismatch means the hint does not match what was read from disk. Falling back
directly to legacy serial recovery avoids another partial replay reset path.

### Full Serial Fallback Conditions

The batched path falls back to `bs_load_replay_md()` when it cannot safely continue, for
example:

- Allocation failure.
- Scan single-page retry I/O error.
- Replay I/O error.
- Summary-assisted replay I/O error or validation mismatch after replay starts.
- Invalid replay chain page.
- Sequence number mismatch.
- Blob id mismatch.
- `next` points outside `md_len`.
- Duplicate blob id or metadata page during commit.
- Extent page validation failure.
- Metadata cluster accounting conflict.

Fallback clears partially rebuilt masks and state before invoking serial recovery.

## Correctness Constraints

- The super block must validate before dirty recovery starts.
- The blob metadata page region must be addressed through `bs_md_page_to_lba()`.
- Chunk scanning must continue to validate pages individually.
- Phase 2 must not silently skip expected chain pages.
- Global used masks and cluster accounting must be updated serially.
- The existing used-mask write path must write rebuilt masks after commit.

## Rollback

Set the internal SPDK blobstore option `recovery_qd` to `1` to force the legacy serial
dirty recovery path. This is intended as a development and validation rollback mechanism,
not as a Longhorn user-facing setting.

## Test Plan

### Unit Tests

Run existing dirty recovery coverage with:

- `recovery_qd = 1` for legacy serial recovery.
- `recovery_qd = 8` or `16` for batched recovery.

Both runs should verify the same recovered blobstore state.

### Functional Test

1. Create a Longhorn V2 volume.
2. Create a filesystem and write a baseline file.
3. Flush/sync the file and record its checksum.
4. Start additional write I/O.
5. Force delete the instance-manager pod to trigger dirty recovery.
6. Wait for recovery.
7. Verify the baseline file checksum.

This validates that data persisted before the crash remains readable after batched dirty
recovery. In-flight I/O at the time of forced termination is not expected to be preserved.

## References

- SPDK Blobstore documentation: https://spdk.io/doc/blob.html
- Longhorn issue: https://github.com/longhorn/longhorn/issues/12837
