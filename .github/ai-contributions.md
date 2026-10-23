# AI Contributions Guide

AI assistance (large language models, coding assistants, agents) is a legitimate
tool for contributing to Longhorn. This guide has two purposes:

1. It states what the project expects when you use AI — the normal
   [`CONTRIBUTING.md`](../CONTRIBUTING.md) rules apply in full; this clarifies how
   they apply to AI-assisted work.
2. It gives an agent enough operating instructions to actually **perform** the
   common tasks correctly: opening an issue, writing commits and a pull request,
   choosing the right repository, and changing CRDs, the chart, or settings.

If you drive a contribution with an agent, point the agent at this file. The
sections below are written so the agent can follow them directly.

---

## Part 1 — What the project expects from AI-assisted work

### You are accountable for what you submit

Longhorn uses the Developer Certificate of Origin (DCO). Your `Signed-off-by`
line certifies that you have the right to submit the contribution and that you
stand behind it. That responsibility does not transfer to a tool: AI-generated
code, text, or analysis is *your* contribution. Read it, understand it, and be
able to explain and defend it in review.

A `Co-authored-by:` trailer naming an AI tool is optional and stylistic. It does
**not** satisfy the DCO — only a human's `Signed-off-by` does. If you add one,
still sign off yourself.

### Verify everything before you submit

AI tools confidently produce details that are wrong. Before opening an issue or
pull request, confirm against the actual repository:

- Issue and PR numbers, and the `longhorn/longhorn#NNNN` references.
- File paths, function names, flags, settings, and API fields.
- Commands, YAML snippets, and configuration.
- Test results — never paste generated or assumed output. Run it.

Do not let a tool invent a reproduction, a test plan, or a benchmark. If it was
not actually run, say so.

### Meet the same quality bar

- **Test for real.** Every PR needs a genuine test plan and actual results — what
  was tested, how, in which environment, and anything not run and why. See
  [Testing Requirements](../CONTRIBUTING.md#testing-requirements). Report SKIPs
  and failures honestly rather than forcing a green result.
- **Keep it focused.** One reviewable change per PR. AI makes it easy to generate
  large, sprawling diffs; resist that. See
  [Pull Request Requirements](../CONTRIBUTING.md#pull-request-requirements).
- **Write for humans.** A concise, accurate description beats an AI-padded one.
  Reviewers should understand the motivation and scope quickly. Maintainers
  actively push back on AI-generated filler in issues and PRs — terse and correct
  wins over long and padded.

### Low-quality AI output is unwelcome

The project's [`SECURITY.md`](../SECURITY.md) is explicit that reports missing
required information "might be considered AI generated spam," and that a working
proof of concept is "mandatory as a proof of work to reduce the noise of AI
generated low quality reports." The same expectation applies to issues and pull
requests: unverified, untested, or auto-generated submissions waste maintainer
time and will be deprioritized or closed.

**Never** disclose a suspected security vulnerability through a public issue or
pull request — AI-assisted or not. Follow the process in
[`SECURITY.md`](../SECURITY.md).

---

## Part 2 — How to perform the tasks

### The mental model (read this first)

1. **Every change starts with an issue in `longhorn/longhorn`.** The tracking
   issue *always* lives in the umbrella repo `longhorn/longhorn`, even when the
   code lives in a component repo. No issue → open one first (trivial typo fixes
   excepted).
2. **Code PRs go to the component repo that owns the code**, not to
   `longhorn/longhorn`. The chart, deploy manifests, enhancement proposals, and
   design docs *do* go to `longhorn/longhorn`. User-facing product docs go to
   `longhorn/website`.
3. **Issues use a template**, which stamps a title prefix (`[BUG]`, `[FEATURE]`,
   …), a GitHub issue *type*, and labels. Keep the prefix.
4. **Commits and PR titles are Conventional Commits**, and every commit *and* the
   PR description must reference the issue.

### Decision guide — what are you doing?

| Goal | Do this |
|---|---|
| Report a bug / request a feature / etc. | Pick the matching issue template; keep its title prefix; fill required fields |
| Open a pull request | Ensure an issue exists → PR against the *owning* repo → Conventional Commits title → `Issue #` link in body → real test results |
| Write a commit message | `type(scope): description` + `Signed-off-by` + `longhorn/longhorn#NNNN` reference |
| Change a CRD field / API type | Edit the `v1beta2` type in longhorn-manager → regenerate → mirror into the chart CRD in `longhorn/longhorn` |
| Change the Helm chart / install manifest | PR to `longhorn/longhorn` (chart source), **never** `longhorn/charts` |
| Add/change a global setting | `types/setting.go` in longhorn-manager + chart `default-setting.yaml`/`values.yaml` |
| Large feature / API / data-path change | Write a Longhorn Enhancement Proposal (LEP) PR first |

### Where does my change go? (repositories)

`longhorn/longhorn` is the **umbrella** repo: issue tracking, enhancement
proposals (`enhancements/`), release manifests (`deploy/`), the Helm chart source
(`chart/`), and design docs. **It does not contain component source code.** The
tracking issue is always filed here regardless of which repo the code targets.

Open **code** PRs against the repo that owns the code:

| Component | What it does | Repo |
|---|---|---|
| Backing Image Manager | Backing image download/sync/deletion on a disk | `longhorn/backing-image-manager` |
| Longhorn Engine | Core **V1** data engine controller/replica logic | `longhorn/longhorn-engine` |
| Longhorn SPDK Engine | Core **V2** data engine controller/replica logic | `longhorn/longhorn-spdk-engine` |
| Instance Manager | Controller/replica instance lifecycle | `longhorn/longhorn-instance-manager` |
| Longhorn Manager | Orchestration + CSI driver; owns API types & CRDs | `longhorn/longhorn-manager` |
| Share Manager | NFS provisioner for ReadWriteMany volumes | `longhorn/longhorn-share-manager` |
| Longhorn UI | The dashboard | `longhorn/longhorn-ui` |

Supporting libraries you may also touch: `longhorn/types` (protobuf/gRPC
definitions shared across components), `longhorn/go-spdk-helper` (SPDK client
wrappers), `longhorn/dep-versions` (pinned build dependency versions).

Goes in `longhorn/longhorn`, **not** a component repo: the Helm chart (`chart/`,
never `longhorn/charts` — that is a published mirror synced at release time),
install/deploy manifests (`deploy/`), enhancement proposals (`enhancements/`),
design documents, and every issue. User-facing docs published at
https://longhorn.io live in `longhorn/website`; a user-facing change often needs
**two** doc PRs (the component repo *and* `longhorn/website`).

A cross-cutting feature (e.g. a new volume field surfaced from gRPC up to the
StorageClass) means one tracking issue in `longhorn/longhorn`, then coordinated
PRs with a stated merge order, each referencing the issue — e.g.
`longhorn/types` → `longhorn/go-spdk-helper` → `longhorn/longhorn-spdk-engine` →
`longhorn/longhorn-instance-manager` → `longhorn/longhorn-manager`, plus the
easy-to-forget chart CRD mirror + deploy manifests in `longhorn/longhorn`.

### Opening an issue (pick the right template)

All issues are filed in **`longhorn/longhorn`**; blank issues are disabled, so you
must pick a template from
[`issues/new/choose`](https://github.com/longhorn/longhorn/issues/new/choose).
Each template stamps a **title prefix**, a GitHub issue **type**, and default
**labels** — keep the prefix. Source of truth:
[`.github/ISSUE_TEMPLATE/`](https://github.com/longhorn/longhorn/tree/master/.github/ISSUE_TEMPLATE).

| Template | Type · key labels | Use when |
|---|---|---|
| `[BUG]` | Bug · `kind/bug`, `require/backport` | Broken behavior in a release. Note affected versions for backport; attach a support bundle. |
| `[FEATURE]` | Feature · `kind/feature`, `require/lep` | A capability that doesn't exist (expect an LEP). |
| `[IMPROVEMENT]` | Improvement · `kind/improvement` | Make an existing capability better. |
| `[REFACTOR]` | Task · `kind/refactoring` | Internal cleanup, no user-visible change. |
| `[DOC]` | Doc · `kind/doc` | Docs only (add a `longhorn/website` PR if user-facing). |
| `[TEST]` | Test · `kind/test` | Add/update test coverage. |
| `[TASK]` / `[CI]` / `[INFRA]` | Task · `kind/task` (+`area/ci`/`area/infra`) | General, pipeline, or dev/test-infra work. |
| `[EPIC]` | Epic · `Epic` | A body of work spanning several issues. |

`[BUG]` requires: description; expected behavior; a support bundle (from the
Longhorn UI footer, or email longhorn-support-bundle@suse.com); and the
environment block (Longhorn version, install method, k8s distro/version, node
counts, per-node OS/kernel/CPU/memory/disk, etc.). Release/hotfix/CVE templates
are driven by the release process — don't use them for ordinary contributions.

Open one with `gh` (keep the template's title prefix):

```bash
gh issue create --repo longhorn/longhorn \
  --title "[BUG] replica rebuild stalls after node reboot" \
  --label "kind/bug" --body-file bug.md
```

### Writing commits

**Conventional Commits, on the PR title *and* every commit title:**

```
<type>(<optional scope>): <description>
```

- **Allowed types:** `fix`, `feat`, `chore`, `docs`, `test`, `refactor`, `ci`,
  `build`, `perf`. An unknown/missing type fails commit-lint.
- **Scope** (optional, encouraged): the area touched, e.g. `(manager)`,
  `(engine)`, `(csi)`, `(chart)`, `(proto)`, `(deps)`.
- **Description:** imperative, lower-case, no trailing period; explain *what*
  changed, not only *where*.
- **Breaking changes:** a `!` after type/scope (`feat(api)!: ...`) or a
  `BREAKING CHANGE:` footer.

**Every commit body must reference the issue** — this is separate from the PR's
linking line — and **every commit must be DCO-signed** (`git commit -s`). The
sign-off email must be a **verified email on your GitHub account**, or the
DCO/CLA bots flag the PR even though the line is present.

```bash
git commit -s -m "fix(manager): prevent stale disk ready condition after node recovery" \
  -m "longhorn/longhorn#1234"
# title is Conventional Commits; body carries the issue ref; -s adds Signed-off-by
```

Fix missing sign-offs after the fact with `git commit --amend --signoff` (last
commit) or `git rebase --signoff <base-branch>` (a range).

### Opening the pull request

Open it against the repo that **owns the code**. Fill the PR template
(`.github/PULL_REQUEST_TEMPLATE.md`):

```
#### Which issue(s) this PR fixes:
Issue #

#### What this PR does / why we need it:

#### Special notes for your reviewer:

#### Additional documentation or context
```

**Critical:** link the issue with `Issue #<number>` or
`Issue longhorn/longhorn#<number>` — **do NOT** use `Fixes #<n>` / `Closes #<n>`.
The template avoids auto-closing keywords on purpose: merging the PR must not
close the tracking issue (maintainers close it after QA review and backports).

The PR body must include a clear summary, the issue link, motivation/context, a
real **test plan and actual results**, and any known risks/limitations. Suggested
test block:

```text
Test environment:
- Longhorn version/image:
- Kubernetes version / distribution:
- Node count / OS:
- Data engine / installation method:

Test steps:
1.

Result:
- PASS / FAIL
- Relevant logs or command output.
```

Report SKIPs honestly (e.g. "not run because the guard webhook is absent from the
deployed release") rather than forcing green. Keep imports in the Longhorn
grouping (stdlib → third-party → Kubernetes → other Longhorn repos → current
repo) and run the repo's formatting/validation before pushing.

```bash
gh pr create --repo longhorn/longhorn-manager --base master \
  --head <you>:<branch> --draft \
  --title "feat(volume): add dataEngineTransport StorageClass param for v2 RDMA" \
  --body-file pr.md
```

### Changing CRDs, the chart, or settings (generated artifacts)

**CRD / API type change is a 2-repo workflow.** In `longhorn/longhorn-manager`
(source of truth): edit the Go API type under `k8s/pkg/apis/longhorn/v1beta2/`
with the right kubebuilder markers, run `make generate`, and commit the API edit
**plus all regenerated files** (CI re-runs generation and diffs — any drift
fails; pin the tool versions `k8s/generate_code.sh` declares so output matches CI
byte-for-byte). A plain scalar field usually needs no deepcopy/clientset changes,
but the HTTP client model, api/ passthrough, CSI parsing, controllers, and
engineapi/ may need the field threaded through by hand.

Then, in `longhorn/longhorn` — **the step people forget** —
`chart/templates/crds.yaml` is a generated byte-mirror of the manager's
`k8s/crds.yaml`. If you don't mirror the new field there, a Helm/manifest install
validates CRs against a CRD lacking the field and the API server **prunes it via
structural-schema validation** (the field silently disappears at apply time). Add
the identical field block, regenerate manifests with
`bash scripts/generate-longhorn-yaml.sh`, verify the diff is *only* your field
across `chart/templates/crds.yaml`, `deploy/longhorn.yaml`, and
`deploy/longhorn-okd.yaml`, and open it as a **separate** chart PR referencing the
same tracking issue.

**Global settings** are not CRD fields: edit `types/setting.go` in
longhorn-manager plus the chart's `templates/default-setting.yaml` and
`values.yaml`. A per-volume knob (replica count, data locality, per-volume
transport, …) is legitimately a **StorageClass parameter** parsed in the CSI
layer — add a global setting only when the behavior is genuinely cluster-wide.

---

## Checklist for AI-assisted contributions

In addition to the [Contribution Checklist](../CONTRIBUTING.md#contribution-checklist):

- [ ] I understand the change and can explain it without the tool.
- [ ] I verified every reference (issue numbers, paths, APIs, flags) against the repo.
- [ ] The test plan and results are real, not generated or assumed.
- [ ] The right issue template was used and its title prefix kept.
- [ ] The PR targets the repo that owns the code; chart changes go to `longhorn/longhorn`.
- [ ] Every commit title is Conventional Commits and references `longhorn/longhorn#NNNN`.
- [ ] Each commit is signed off by me (DCO); any `Co-authored-by` is in addition, not instead.
- [ ] The PR links the issue with `Issue #` (not `Fixes #`) and is focused, written for human reviewers.
- [ ] CRD field changes are mirrored into the chart CRD and the deploy manifests.
