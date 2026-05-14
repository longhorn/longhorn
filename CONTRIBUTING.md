# Contributing to Longhorn

Welcome, and thank you for your interest in contributing to Longhorn!

Longhorn is a cloud-native distributed block storage system for Kubernetes. Contributions are not limited to code changes. You can help by reporting issues, improving documentation, reviewing pull requests, testing fixes, proposing new features, or sharing feedback from real-world deployments.

This guide applies to contributions to the Longhorn project and its related repositories.

## Getting Started

Before contributing code, please read the Longhorn developer guide:

- [Getting started with Longhorn development](https://github.com/longhorn/longhorn/wiki/Getting-started-with-Longhorn-Development)

You can also join the Longhorn community discussions through the available Longhorn community channels.

## Before Opening a Pull Request

Before submitting a pull request, make sure there is a related issue in the Longhorn issue tracker:

- https://github.com/longhorn/longhorn/issues

If no issue exists, please create one first.

Having an issue for every pull request helps the community:

- Track bugs, enhancements, regressions, and design discussions.
- Understand the motivation and scope of the change.
- Coordinate review, testing, release planning, and backport decisions.
- Avoid duplicated or conflicting work.

Small changes such as typo fixes may be submitted directly, but larger bug fixes, behavior changes, features, refactoring, dependency updates, or chart-related changes should always be linked to an issue.

## Pull Request Requirements

Each pull request must include:

1. A clear summary of the change.
2. A link to the related Longhorn issue.
3. The motivation and context for the change.
4. The test plan and actual test results.
5. Any known risks, limitations, compatibility concerns, or follow-up work.

A pull request should be focused and reviewable. Avoid combining unrelated fixes, refactoring, formatting changes, and feature work in the same pull request.

## Testing Requirements

Every pull request must be tested before submission.

The pull request description must include:

- What was tested.
- How it was tested.
- The environment used for testing.
- The test result.
- Any tests that were not run and the reason.

Examples of useful test information include:

```text
Test environment:
- Longhorn version/image:
- Kubernetes version:
- Kubernetes distribution:
- Node count:
- OS:
- Data engine:
- Installation method:

Test steps:
1.
2.
3.

Result:
- PASS / FAIL
- Relevant logs, screenshots, or command output if applicable.
```

Depending on the change, testing may include:

- Unit tests.
- Integration tests.
- End-to-end tests.
- Upgrade tests.
- Regression tests.
- Manual validation in a Kubernetes cluster.
- Helm installation or upgrade validation.
- UI validation.
- Backup, restore, snapshot, replica rebuild, engine, node, disk, or volume lifecycle validation.

If a pull request affects storage behavior, upgrade behavior, data path logic, scheduling, recovery, backup, restore, snapshot handling, CSI behavior, or Kubernetes object reconciliation, provide enough detail for reviewers to reproduce the test.

## Commit and Pull Request Title Convention

Pull request titles and commit titles must follow the Conventional Commits format:

```text
<type>(optional scope): <description>
```

Common types include:

```text
fix:
feat:
chore:
docs:
test:
refactor:
ci:
build:
perf:
```

Examples:

```text
fix(manager): prevent stale disk ready condition after node recovery
feat(engine): add validation for v2 live switchover
docs: update snapshot restore troubleshooting guide
test(e2e): add regression test for replica rebuild failure
chore(deps): update CSI sidecar images
```

Use a clear and concise description. The title should explain what changed, not only where the change happened.

## DCO Sign-off

All commits must be signed off.

Longhorn uses the Developer Certificate of Origin (DCO). By signing off your commit, you certify that you have the right to submit the contribution under the project license.

Use the `--signoff` or `-s` option when creating commits:

```bash
git commit -s -m "fix(manager): handle replica cleanup error"
```

This adds a `Signed-off-by` line to the commit message:

```text
Signed-off-by: Your Name <your-email@example.com>
```

Every commit in the pull request must include a valid sign-off.

If you already created commits without sign-off, you can amend or rebase them:

```bash
git commit --amend --signoff
```

or, for multiple commits:

```bash
git rebase --signoff <base-branch>
```

## Coding Convention

Go code must follow the Longhorn coding convention:

- https://github.com/longhorn/longhorn/wiki/coding-convention

In particular, Go imports must follow the project import grouping convention. Import groups should be organized consistently with the existing codebase and separated by blank lines.

The expected grouping is generally:

1. Go standard library packages.
2. Third-party packages.
3. Kubernetes-related packages.
4. Longhorn component packages outside the current repository.
5. Packages from the current repository.

When aliases are used, keep them grouped consistently with nearby imports and existing Longhorn code patterns.

Before submitting a pull request, run the relevant formatting and validation commands for the repository you are changing.

## Chart Changes

Do not submit pull requests directly to:

- https://github.com/longhorn/charts

The `longhorn/charts` repository is used for publishing released Helm charts. Chart changes should be submitted to the source repository instead:

- https://github.com/longhorn/longhorn

After chart changes are merged and ready for release, they will be synced to the charts repository through the release process.

## Documentation Changes

Documentation improvements are welcome.

For documentation pull requests, please make sure:

- The content is accurate and matches the current Longhorn behavior.
- The change is linked to a related issue when it affects user-facing behavior, troubleshooting, installation, upgrade, settings, or feature documentation.
- The wording is clear and concise.
- Examples, commands, and YAML snippets are tested when possible.

## Review Process

Maintainers and reviewers may ask for:

- More test coverage.
- Additional manual validation.
- Design clarification.
- Backward compatibility analysis.
- Upgrade or rollback considerations.
- Documentation updates.
- Smaller or more focused pull requests.

Please keep discussions constructive and technical. Review comments are part of the normal contribution process and help maintain Longhorn quality.

## Security Issues

Do not publicly disclose security vulnerabilities through GitHub issues or pull requests before they are properly reported and triaged.

If you believe you have found a security vulnerability, follow the Longhorn security reporting process instead of opening a public issue.

## Contribution Checklist

Before requesting review, confirm that:

- [ ] There is a related issue in https://github.com/longhorn/longhorn/issues.
- [ ] The pull request description explains the motivation and scope.
- [ ] The pull request title follows Conventional Commits.
- [ ] Each commit title follows Conventional Commits.
- [ ] Each commit includes a valid DCO sign-off.
- [ ] The change has been tested.
- [ ] The test steps and results are included in the pull request description.
- [ ] Go imports follow the Longhorn coding convention.
- [ ] Documentation has been updated when needed.
- [ ] Chart changes are submitted to `longhorn/longhorn`, not `longhorn/charts`.
- [ ] The pull request contains only related changes.

Thank you for helping improve Longhorn!