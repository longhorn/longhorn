# Age-Based Retention for Recurring Jobs

## Summary

Add an `age-based` retention policy for supported recurring-job snapshot, backup, and system-backup tasks. Operators will specify a Go duration and expired artifacts will be removed by age, while the existing `count-based` retention behavior remains unchanged and is preserved for upgraded recurring jobs.

### Related Issues

- https://github.com/longhorn/longhorn/issues/12060

## Motivation

### Goals

- Let a recurring job express retention as an age window instead of a count for the `snapshot`, `snapshot-force-create`, `backup`, `backup-force-create` and `system-backup` tasks.
- Keep the two modes strictly independent and mutually exclusive.
- Ensure that recurring jobs created before the upgrade continue keeping precisely the same items as `spec.retain`.

### Non-goals

N/A

## Proposal

This proposal adds `retentionPolicy` and `retainAge` to recurring jobs. `retentionPolicy: age-based` retains snapshots, backups, and system backups until their creation timestamps are older than `retainAge`; it does not use `retain`. `retentionPolicy: count-based` continues to retain the configured number of newest items and ignores `retainAge`.

The policies are mutually exclusive. `count-based` remains the default, so existing recurring jobs are backfilled or defaulted to their current count-based behavior during upgrade and continue deleting the same items as before.

### User Stories

#### Story 1 — a compliance-driven backup window

An operator is required to keep volume backups for exactly 90 days and to purge them afterwards.

- **Before**:
  They must translate 90 days into a count against the cron schedule — a daily backup job with `retain: 90`. The translation is only correct while the schedule holds. If someone later changes the cron to twice daily, the retained window silently halves to 45 days and backups are destroyed early. Neither failure is visible in the spec; both require noticing that `retain` and `cron` have drifted apart.

- **After**:
  They set `retentionPolicy: age-based` and `retainAge: 2160h`. The window is enforced against the creation timestamp of each backup on every run, so it holds regardless of how often the job runs, whether runs were missed, or whether the cron was edited. `retain` is left at whatever it was and is not consulted.

#### Story 2 — snapshots on a low-churn volume

A team snapshots a rarely-written volume every hour with `retain: 24`, expecting roughly a day of history. Because the count threshold is only reached after 24 runs, and because runs are skipped while the workload is scaled to zero overnight and at weekends, the oldest retained snapshot is routinely several days old with the setting `allow-recurring-job-while-volume-detached` disabled. The snapshots are cheap individually but the chain grows, and the volume's snapshot count drifts up over long idle periods.

- **After**:
  `retentionPolicy: age-based`, `retainAge: 24h`. Anything older than a day is removed on the next run whether or not 24 snapshots have accumulated, so idle periods shrink the chain instead of stretching it.

### User Experience In Detail

Creating an `age-based` backup recurring job that keeps one year of backups:

```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: yearly-backup
  namespace: longhorn-system
spec:
  cron: "0 2 * * *"
  task: backup
  groups:
  - default
  retentionPolicy: age-based
  retainAge: 8760h
```

`retain` may be present and it is ignored.

A `count-based` recurring job is written exactly as before, but `retentionPolicy` should be set to `count-based`:

```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: save-24-snapshots
  namespace: longhorn-system
spec:
  cron: "0 * * * *"
  task: snapshot
  retentionPolicy: count-based
  retain: 24
```

Listing recurring jobs:

```shell
$ kubectl -n longhorn-system get lhrj
NAME            GROUPS      TASK      CRON          RETENTIONPOLICY   RETAINCOUNT   RETAINAGE   CONCURRENCY   AGE
hourly-snap     [default]   snapshot  0 * * * *     count-based       24            1m          2             31d
yearly-backup   [default]   backup    0 2 * * *     age-based         50            8760h       2             10s
```

Rejected configurations, with the error surfaced by the admission webhook at `kubectl apply` time:

| Configuration | Result |
| --- | --- |
| `retentionPolicy: age-based`, `task: snapshot-delete` (or `snapshot-cleanup`, `filesystem-trim`) | rejected — `recurring job retention policy age-based can not be used with task snapshot-delete` |
| `retentionPolicy: Age-Based` / `age_based` / any other value | rejected by the CRD enum, and by the webhook with `retentionPolicy should be count-based or age-based` |
| `retainAge: -1h` | rejected by the CRD `XValidation` — `retainAge must be a positive duration` |
| `retainAge: 1d` or `1y` | rejected at decode — Go durations have no day or year unit; write `24h` / `8760h` |
| `retentionPolicy: count-based`, `retain: 0`, `task: backup` | rejected — `recurring job retain count 0 must be greater than 0` |

### API changes

- Modify the `RecurringJobCreate` and `RecurringJobUpdate` APIs:
  - Add `RetentionPolicy` and `RetainAge` fields for creating or updating recurring jobs and returning `RecurringJob` information.

  ```golang
  type RecurringJob struct {
    client.Resource
    longhorn.RecurringJobSpec
    longhorn.RecurringJobStatus
  }
  ...
  type RecurringJobSpec struct {
    ...
    // The number of snapshots/backups to retain.
    // Retain applies only when the retention policy is "count-based".
    // +optional
    Retain int `json:"retain"`
    // The retention age of the snapshot/backup, specified as a Go duration string,
    // such as "10m", "24h", or "8760h". Note that Go durations have no day or year unit,
    // so a day is "24h". Snapshots/backups older than this are cleaned up by the recurring job.
    // Only takes effect when the retention policy is "age-based".
    // If the retention policy is "age-based" and this value is 0s, the recurring job will not start.
    // +kubebuilder:validation:XValidation:rule="!self.startsWith('-')",message="retainAge must be a positive duration"
    RetainAge metav1.Duration `json:"retainAge,omitempty"`
    // The retention policy that determines whether the recurring job cleans up
    // snapshots/backups based on their count or age. Can be "count-based" or
    // "age-based". The two policies work independently: "count-based" (the default)
    // retains the configured number of newest snapshots/backups and ignores
    // RetainAge, while "age-based" retains snapshots/backups no older than RetainAge
    // and ignores Retain.
    // +kubebuilder:default:=count-based
    RetentionPolicy RecurringJobRetentionPolicy `json:"retentionPolicy,omitempty"`
  ...
  }
  ```

## Design

### Implementation Overview

- Introduce a new `RecurringJobRetentionPolicy` field in the RecurringJob spec:
  - `count-based`
  - `age-based`

All retention logic lives in `filterExpiredItems`, a helper function in `app/recurringjob/util.go`.
The helper sorts items oldest first and applies exactly one predicate per item, selected by `policy`:

```go
func filterExpiredItems(nts []NameWithTimestamp, retainCount int, retainAge time.Duration, policy longhorn.RecurringJobRetentionPolicy, now time.Time) []string {
  ...
  switch policy {
  case longhorn.RecurringJobRetentionPolicyAgeBased:
    expired = retainAge > 0 && now.Sub(nt.Timestamp) > retainAge
  case longhorn.RecurringJobRetentionPolicyCountBased:
    expired = i < len(nts)-retainCount
  default:
    // This case is unreachable:
    // new jobs default to count-based, existing jobs are backfilled on upgrade, and the webhook rejects an empty or unrecognized policy.
    // Returning nothing is the safe failure mode, so an unexpected policy never deletes anything.
    return ret
  }
  ...
}
```

The mutating webhook's per-task retention normalization is factored out of the duplicated `Create` and `Update` bodies into `mutateRetainCountAndRetainAge`. The helper also normalizes `retainAge` to `0s` for cleanup-only tasks, where an age window is meaningless, and defaults non-positive durations to `0s`.

```go
func mutateRetainCountAndRetainAge(patchOps admission.PatchOps, recurringJob *longhorn.RecurringJob, log *logrus.Entry) admission.PatchOps {
  switch recurringJob.Spec.Task {
  case longhorn.RecurringJobTypeSnapshotCleanup, longhorn.RecurringJobTypeFilesystemTrim, longhorn.RecurringJobTypeSnapshotDelete:
    ...
    if recurringJob.Spec.RetainAge.Duration != 0 {
      patchOps = append(patchOps, `{"op": "replace", "path": "/spec/retainAge", "value": "0s"}`)
    }
  default:
    ...
    if recurringJob.Spec.RetainAge.Duration <= 0 {
    // RetainAge defaults to 0, which prevents an age-based recurring job from starting.
    patchOps = append(patchOps, `{"op": "add", "path": "/spec/retainAge", "value": "0s"}`)
    }
  }
```

The validating webhook gains `validateRetentionPolicy`, which rejects a negative `retainAge`, rejects `age-based` on a cleanup-only task, rejects an unrecognized policy, and leaves the existing `retain > 0` requirement for `count-based` untouched.

```go
func validateRetentionPolicy(policy longhorn.RecurringJobRetentionPolicy, task longhorn.RecurringJobType, retain int, retainAge metav1.Duration) error {
  if retainAge.Duration < 0 {
  return err
  }

  notCleanupTask := (task != longhorn.RecurringJobTypeSnapshotCleanup &&
    task != longhorn.RecurringJobTypeFilesystemTrim &&
    task != longhorn.RecurringJobTypeSnapshotDelete)

  switch policy {
  case longhorn.RecurringJobRetentionPolicyCountBased:
    if notCleanupTask && retain <= 0 {
      return err
    }
    return nil
  case longhorn.RecurringJobRetentionPolicyAgeBased:
    if !notCleanupTask {
      return err
    }
    return nil
  }
  return err
}
```

### Test plan

**Integration / e2e (`longhorn-tests`)** — to be added:

- Age-based backup/snapshot retention
  1. Create a volume and a `backup`/`snapshot` recurring job with `retentionPolicy: age-based` and a short `retainAge` (e.g. `5m`) on a `*/1 * * * *` cron.
  2. Verify the expected backup/snapshot creation times and that five backups/snapshots are retained over five minutes.
- Count is not consulted under `age-based`
  1. A recurring job with `retain: 1` and a `retainAge` covering several runs must retain more than one item.
- Age is not consulted under `count-based`
  1. A recurring job with `retain: 3` and a `retainAge` shorter than one cron interval must still retain three items.
- Rejection cases.
  1. Apply each row in the `Rejected configurations` table in "User Experience In Detail" through both the Kubernetes API and the HTTP API, and assert that the operation fails.
- Upgrade
  1. Install Longhorn v1.12.x
  2. Create a volume A and a `backup`/`snapshot` recurring job B and assign recurring job B to volume A.
  3. Upgrade to Longhorn v1.13.x-head or master-head
  4. The `Spec.RetentionPolicy` of recurring job B should be `count-based` automatically.
  5. Verify that recurring job B continues to work as expected with volume A.

### Upgrade strategy

- Existing RecurringJob CRs are additionally backfilled by `upgrade/v112xto1130`, which sets `RecurringJob.Spec.RetentionPolicy = count-based` on every recurring job that has an empty value.
