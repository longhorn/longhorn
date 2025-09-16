---
name: Hotfix
about: Create a hotfix task
title: "[HOTFIX] "
type: "Task"
labels: ["kind/hotfix", "require/important-note"]
assignees: ''

---

## What's the task? Please describe

<!--A clear and concise description of what the task is.-->

## Describe the sub-tasks

- [ ] Create temporary branch for hotfixed component repo and push the fix to this branch
- [ ] Validate the fix using hotfixed image
- [ ] Create a tag for the hotfixed component repo. The naming convention is `vX.Y.Z-hotfix-<number>`, e.g. `v1.4.0-hotfix-1`, `v1.4.0-hotfix-2`, etc.
- [ ] Validate the fix using hotfixed image <longhorn-component>:`vX.Y.Z-hotfix-<number>`
- [ ] Remove the temporary branch
- [ ] Update the important note in the official document vX.Y.Z

## Additional context

<!--Add any other context or screenshots about the task request here.-->
