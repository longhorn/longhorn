---
name: Performance Benchmark
about: Performance benchmark task for feature release
title: "[Benchmark] Performance Benchmark for {{ env.RELEASE_VERSION }}"
type: "Task"
labels: ["release/task", "area/benchmark"]
assignees: ''

---

## What's the task? Please describe

Execute performance benchmark for v1 and v2 volume


## Describe the sub-tasks

- [ ] baseline based on local-path-provisioner
- v1
    - [ ] 1-replica volume (co-located replica and engine)
    - [ ] 3-replica volume 

- v2
    - Single CPU core
        - [ ] 1-replica volume (co-located replica and engine)
        - [ ] 3-replica volume 
    - Multiple CPU cores
        - [ ] 1-replica volume (co-located replica and engine)
        - [ ] 3-replica volume 

## Additional context

Update the results to https://github.com/longhorn/longhorn/wiki/Performance-Benchmark


