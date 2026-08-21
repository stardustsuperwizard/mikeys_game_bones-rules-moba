# Agent Workflow and Model Routing

How Sword and Planet uses GitHub Copilot agents, and which model runs which
role. Optimized for cost and quality; latency is explicitly not a goal.

Verified against GitHub documentation on 2026-08-19. Model availability and
pricing change often — re-check the sources at the bottom before assuming
this document is current.

## The constraint that shapes everything

**`model:` in an agent profile is ignored by Copilot cloud agent on
github.com.** GitHub's configuration steps say the property applies only
when "creating and using the agent profile in Visual Studio Code, JetBrains
IDEs, Eclipse, or Xcode."

On github.com the model comes from the **picker at task kickoff**, and that
single model covers the whole session — the parent agent and every subagent
it delegates to. A planner that delegates to `executor` in-session
runs the implementer on the planner's expensive model.

Consequence: per-role model routing on github.com requires **separate
sessions**, not subagent delegation. That is the workflow below.

The `model:` lines in `.github/agents/*.agent.md` are still correct and still
maintained — they take effect when the same profiles are run from VS Code.

## Model routing

| Role | Model | Reasoning | Where the model is set |
| --- | --- | --- | --- |
| Planner | Claude Opus 5 | High | `PLANNER_MODEL` in `agent-01-planner.yml` |
| Executor | Claude Haiku 4.5 | Default | Cloud agent default — **not currently controllable**, see below |
| Reviewer | Claude Opus 5 | High | `REVIEWER_MODEL` in `agent-03-review.yml` |

Two of these are now set in workflow env rather than a picker, which is the
main practical gain from moving planning and review into Actions: the model is
version-controlled instead of chosen by hand each time.

The executor is the exception and the open problem. `agent-02-execute.yml`
assigns Copilot through the API, which does not go through the model picker,
so the session takes whatever the cloud agent defaults to. Verify this on the
first run. If the default is not Haiku 4.5, the options are to accept it, to
assign by hand from a desktop browser where the picker exists, or to rebuild
the executor as a Copilot CLI session — which means owning branch, commit,
push, and PR plumbing that the cloud agent currently handles for free.

Rationale: reasoning is worth paying for where decisions are made, not where
they are executed. The planner and reviewer read a lot and write little, so
the expensive model burns few output tokens. Implementation is where token
volume lives, and this repository's instructions are unusually tightly
scoped — which is the condition under which a small model performs well.

### Pricing, per 1M tokens

Billing moved to usage-based AI Credits on 2026-06-01. Request multipliers
are gone; you pay per token, so a cheaper model is a real saving.

| Model | Input | Cached input | Output | Cloud agent |
| --- | --- | --- | --- | --- |
| MAI-Code-1.1-Flash | $0.20 | $0.02 | $1.20 | Picker + Auto |
| GPT-5.6 Luna | $0.20 | $0.02 | $1.20 | Picker |
| GPT-5.4 mini | $0.75 | $0.075 | $4.50 | Picker |
| **Claude Haiku 4.5** | $1.00 | $0.10 | $5.00 | Picker only |
| Claude Sonnet 5 | $2.00 | $0.20 | $10.00 | Not listed |
| Claude Sonnet 4.6 | $3.00 | $0.30 | $15.00 | Auto — retiring |
| **Claude Opus 5** | $5.00 | $0.50 | $25.00 | Picker |

Opus 5 costs 5× Haiku 4.5. Sonnet 5 — the natural middle tier — is not
currently listed for the cloud agent in either the Auto pool or the picker,
so this project routes around it.

### Do not use Auto for implementation

Haiku 4.5 is selectable in the picker but is **not in the Auto pool**.
Selecting Auto for an implementation task silently yields Sonnet 4.6 at 3×
the input cost of Haiku.

### Models retiring 2026-09-01

| Model | Replacement |
| --- | --- |
| Claude Sonnet 4.5 | Claude Sonnet 5 |
| Claude Sonnet 4.6 | Claude Sonnet 5 |
| Claude Opus 4.5 / 4.6 | Claude Opus 5 |

The agent profiles previously pinned Sonnet 4.5 and have been updated.

### Cheaper implementer candidates, not yet adopted

MAI-Code-1.1-Flash and GPT-5.6 Luna are 5× cheaper than Haiku 4.5 and are
both cloud-agent selectable. Neither is validated against GDScript and Godot
4 scene and resource serialization, which is unforgiving of small mistakes.
Trial them on one or two mechanical tasks and compare rework cycles before
switching. The PR template records the model used and the rework count so
this comparison is possible.

## The workflow

Four workflows in `.github/workflows/`, numbered in the order work moves
through them. Two of them spend AI credits; two are plumbing.

```
Intake Issue        [plan] in title, `plan` + type label
        │
        │  you add  agent:plan
        ▼
┌────────────────────────────────────────────────┐
│ agent-01-planner.yml         Status: Planning  │
│ Copilot CLI, edit/execute tools REMOVED        │
│ reads Issue body + comments + repo inventory   │
└────────────────────────────────────────────────┘
        │  validated plan JSON
        │  → [impl] sub-issues, blocked-by wired
        │  → plan comment on the Feature
        ▼                        Status: In Progress
Implementation Task     Status: Ready
        │
        │  you add  agent:execute
        ▼
┌────────────────────────────────────────────────┐
│ agent-02-execute.yml       Status: In Progress │
│ thin dispatch, no AI credits                   │
│ assigns copilot-swe-agent + customAgent        │
└────────────────────────────────────────────────┘
        │
   Copilot Cloud Agent ──▶ draft PR ──▶ ready for review
        │
        ▼
┌────────────────────────────────────────────────┐
│ agent-03-review.yml                            │
│ Copilot CLI, edit/execute tools REMOVED        │
│ diff vs. acceptance criteria → VERDICT         │
└────────────────────────────────────────────────┘
        │
   PASS  → review:pass label,  task Status: In review
   other → review:* label,     task Status: Blocked
        │
        │  you merge; the PR closes the task Issue
        ▼
┌────────────────────────────────────────────────┐
│ agent-04-rollup.yml           task → Done      │
│ no AI credits                                  │
│ last sibling closed? parent → In review        │
└────────────────────────────────────────────────┘
        │
   you do the human checks and close the Feature → Done
```

### Everything is label-driven, on purpose

Every stage starts because a label was added, and each workflow **removes the
label it consumed**. That gives three properties worth keeping:

- **It works from a phone.** The GitHub mobile apps do not expose the
  custom-agent picker, which is the whole reason `agent-02-execute.yml`
  exists — see *Step 2*. Adding a label is something every GitHub client can
  do.
- **Re-adding a consumed label is a clean retry.** No separate re-run verb.
- **No workflow fires on its own output**, so there are no dispatch loops.

| Label | Added by | Consumed by | Means |
| --- | --- | --- | --- |
| `plan` | Issue template | — | Intake ticket, type marker |
| `agent:plan` | You | `agent-01-planner.yml` | This Issue is ready to be planned |
| `agent:execute` | You | `agent-02-execute.yml` | Dispatch this task to Copilot |
| `agent:review` | You | `agent-03-review.yml` | Re-review this PR |
| `planned` | Planner | — | Feature has been decomposed |
| `review:*` | Reviewer | — | Last verdict on a PR |

### Why planning and review are CLI sessions, not cloud agents

The Copilot cloud agent is built to produce a diff: it opens a branch and a
pull request, and its harness pushes toward committing something. An agent
file that says "do not implement" is arguing with that harness, and it loses —
which is exactly what happened to the first planner.

The fix is not better prose. It is removing the capability:

```
--excluded-tools "bash,powershell,apply_patch,create,edit,task,write_agent"
```

Planner and reviewer therefore run as Copilot CLI sessions inside Actions,
where tools can be taken away. The executor is the one role that runs *with*
the cloud agent's grain, so it is the one role that runs as a cloud agent.

**Do not run the planner or reviewer as a cloud agent from the Agents tab.**
Their agent files are for `agent-01-planner.yml`, `agent-03-review.yml`, and
interactive VS Code use.

### Setup: the PROJECT_TOKEN secret

Projects v2 is not writable with the default `GITHUB_TOKEN`, so every status
transition needs a PAT in the repository secret `PROJECT_TOKEN`:

```bash
gh secret set PROJECT_TOKEN --repo stardustsuperwizard/sword-and-planet
```

Project 1 is **user-owned**, not repo-owned. That changes which permission you
need:

| PAT type | What to grant |
| --- | --- |
| Classic | `project` scope (plus `repo`) |
| Fine-grained | **Account permissions → Projects: Read and write** — *not* a repository permission |

Without it, the first status step fails and the run stops before spending any
credits, which is the intended failure mode.

The token is scoped to individual steps through
`.github/actions/set-project-status`, never to the job. Keep it that way: a
job-level PAT would sit in the environment of a Copilot CLI session running
with `--allow-all-tools`.

### Step 1 — Planning

1. File the Issue with one of the intake templates. Title starts with
   `[plan]`; the template applies `plan` plus a type label.
2. When the Issue is actually ready — not when you file it — add
   **`agent:plan`**.

`agent-01-planner.yml` then:

- moves the Feature to **Planning**;
- builds a prompt from the Issue body, **its comments**, the planner agent
  file, the task template, and a repository file inventory;
- runs Copilot CLI with implementation tools removed;
- validates the returned JSON structurally before it is allowed to create
  anything — task count, required fields, unique IDs, no self-dependency, no
  dangling `depends_on`, non-empty acceptance criteria;
- creates one `[impl]` sub-issue per task with native `--parent` and
  `--add-blocked-by` relationships;
- posts the plan as a comment on the Feature;
- moves the Feature to **In Progress** and each task to **Ready**.

Comments are read as amendments to the body, and later comments win over the
original text. The workflow skips its own machine comments so a re-plan does
not read back its previous output as a requirement.

A second run is blocked by the `<!-- automated-planner-complete -->` marker.
To genuinely re-plan, run the workflow manually with `force: true` — and close
the stale sub-issues yourself first, because nothing removes them for you.

### Step 2 — Execution

For each Implementation Task, in dependency order, add **`agent:execute`**.

`agent-02-execute.yml` is deliberately thin — it spends no AI credits:

1. Refuses if the task has open `blocked-by` Issues, parks it at **Blocked**,
   and removes the label. Override with the workflow's `ignore_blockers`
   input.
2. Moves the task to **In Progress**.
3. Assigns `copilot-swe-agent` through GraphQL
   `replaceActorsForAssignable`, passing `agentAssignment.customAgent` so the
   session runs `.github/agents/02-executor.agent.md`.
4. Removes `agent:execute` so re-adding it retries.

**This workflow exists because of the mobile apps.** Assigning Copilot by hand
from a phone gives you the default agent with no way to select a custom one.
Going through the API is the only way to pin the executor profile from a
client that has no picker.

Caveat worth checking on the first run: programmatic assignment does not go
through the model picker, so the session may not use Haiku 4.5. If the credit
line looks wrong, that is the first thing to inspect. `customAgent` must match
the `name:` frontmatter (`executor`), not the filename; if GitHub rejects it
the workflow logs a warning and falls back to the default agent rather than
stranding the task.

### Step 3 — Review

`agent-03-review.yml` runs automatically when a `copilot/*` branch's PR is
marked ready for review, or any time you add **`agent:review`**.

It answers the question the built-in Copilot code review does not: *is this
diff complete against the acceptance criteria it was authorized by?* It walks
the PR's `closingIssuesReferences` back to the Implementation Task, loads that
contract plus the plan file, and reviews the diff against it criterion by
criterion.

The first line is machine-readable:

| Verdict | Board effect | PR label | Next action |
| --- | --- | --- | --- |
| `PASS` | task → **In review** | `review:pass` | Merge, squash, delete branch |
| `FIX` | task → **Blocked** | `review:fix` | Bounded correction on the same PR |
| `PLANNING FAILURE` | task → **Blocked** | `review:planning-failure` | Revise the plan, re-delegate |
| `DESIGN AMBIGUITY` | task → **Blocked** | `review:design-ambiguity` | Stop, decide it yourself |

Fix cycles are **not** dispatched automatically. Nothing re-summons Copilot on
an adverse verdict, because an auto-fix loop can burn credits without
converging. Read the review, then either comment `@copilot` on the PR for a
bounded correction or re-plan.

If a task takes more than two `FIX` cycles, that is a planning problem, not an
implementation problem. Record it.

### Step 4 — Rollup

`agent-04-rollup.yml` fires on any Issue closing or reopening. No AI credits.

- A closed sub-issue moves to **Done**; a reopened one returns to **Ready**.
- When the last open sibling closes, the parent Feature moves to
  **In review** and gets a comment saying what is left.

What is left is human: confirm the Feature's own acceptance criteria hold end
to end, do the **Human Validation Required** checks in the Godot editor, then
close the Feature. Nothing moves a Feature to **Done** automatically — that
transition is the human sign-off, and automating it would remove the only
checkpoint in the pipeline.

Child states are read from `subIssues.nodes[].state` rather than the cached
`subIssuesSummary` counters, which can lag the close event.

### Issue hierarchy

The Feature Issue is the parent and remains the source of truth for intended
behavior. Every promoted Implementation Task is a direct GitHub sub-issue of
that Feature. Writing the parent number in an Issue body is not sufficient;
the GitHub sub-issue relationship must exist — `agent-01-planner.yml` creates
it with `gh issue create --parent`, and sibling ordering with
`gh issue edit --add-blocked-by`. Both need a recent `gh`; the runner image
ships one, but pin it if a run ever fails on an unknown flag.

Each implementation sub-issue:

- follows `.github/ISSUE_TEMPLATE/99-execute_task.md`;
- has the same milestone as its parent Feature;
- carries `implementation` and `machine`, and gets `agent:execute` from you
  when it is time to run;
- records sibling ordering with GitHub issue dependencies;
- is the only Issue assigned to the executor; and
- is closed by its own implementation PR.

The parent Feature stays open while its sub-issues are implemented.
`agent-04-rollup.yml` moves it to **In review** when the last one closes; you
close it.

### Project board

Tracked on the [Sword and Planet Workflow](https://github.com/users/stardustsuperwizard/projects/1)
project. The parent Feature and its Implementation Task sub-issues each carry
their own item on the board, distinguished by two fields:

- **Status** — one shared single-select field on every item: `Backlog`,
  `Planning`, `Ready`, `In Progress`, `In review`, `Blocked`, `Done`.
- **Work Type** — `Planning` or `Implementation`, distinguishing a Feature
  row from a Task row.

There is no separate Planner Status / Implementation Status pair; both roles
write the same Status field on their own item.

Every transition goes through the `.github/actions/set-project-status`
composite action, so the token handling and the field names live in one file
rather than in four workflows:

| Item | Status | Set by |
| --- | --- | --- |
| Feature | `Planning` | `agent-01-planner.yml`, at start |
| Feature | `In Progress` | `agent-01-planner.yml`, on success |
| Feature | `Blocked` | `agent-01-planner.yml`, on failure |
| Task | `Ready` | `agent-01-planner.yml`, at creation |
| Task | `In Progress` | `agent-02-execute.yml`, on dispatch |
| Task | `Blocked` | `agent-02-execute.yml` when blocked; `agent-03-review.yml` on an adverse verdict |
| Task | `In review` | `agent-03-review.yml`, on `PASS` |
| Task | `Done` | `agent-04-rollup.yml`, when the Issue closes |
| Feature | `In review` | `agent-04-rollup.yml`, when the last sub-issue closes |
| Feature | `Done` | **You.** Never automated. |

`Backlog` is the intake state and nothing writes it; the project's built-in
auto-add sets it when an Issue first lands on the board.

## When to collapse to one session

The full pipeline costs four workflow runs of overhead. For small, mechanical,
fully specified work — a rename, a doc fix, a Task-template Issue with no
architectural content — skip planning: file the Issue, add `agent:execute`
directly, and let `agent-02-execute.yml` dispatch it. Review still applies if
the change touches `.tscn`, `.tres`, `project.godot`, or anything under
`addons/`.

`agent-02-execute.yml` does not require an Issue to have come from the
planner. It only requires that the Issue be open and unblocked.

## Where the handoff contract lives

There is no plan file. The planner writes no repository files at all — its
`tools:` list grants no `edit`, which is the same capability-removal fix that
stopped it implementing features.

The contract is split across two durable places, both of which a cold
execution session can read:

| Artifact | Carries |
| --- | --- |
| The `[impl]` sub-issue body | Objective, scope, expected files, architecture constraints, acceptance criteria, out of scope, dependencies |
| The plan comment on the Feature | Plan summary, architecture notes, the task list with Issue numbers |

The sub-issue is authoritative. The executor is given exactly one Issue and
never sees the planner's session, so **anything an executor needs must be in
the sub-issue body** — not in the plan comment, and not in the parent Feature.
The parent is context only and does not expand scope.

This is why `agent-01-planner.yml` validates the plan JSON structurally before
creating anything: a task with empty acceptance criteria or a dangling
`depends_on` would become an Issue that cannot be executed cold, and the run
fails instead.

## Running in VS Code

In VS Code the `model:` frontmatter is honored, so the three profiles route
themselves and the planner can delegate in-session via the `agent` tool. This
is the faster path and the right one for exploratory work; the workflow-driven
flow above is for work that lands on `main`.

Caveat: [copilot-cli#2564](https://github.com/github/copilot-cli/issues/2564)
reports `model:` being ignored for subagents in the CLI, with agents falling
back to the session default. Verify empirically before trusting per-agent
routing there.

## Unsupported frontmatter on github.com

Do not add these to `.github/agents/*.agent.md` expecting them to work on
the cloud agent:

| Property | Status |
| --- | --- |
| `model` | Ignored on github.com; honored in VS Code / JetBrains / Eclipse / Xcode |
| `agents` | Not supported |
| `handoffs` | Not supported |
| reasoning level | Not settable in frontmatter — picker only ([#2904](https://github.com/github/copilot-cli/issues/2904)) |

Supported and in use: `name`, `description`, `tools`, `user-invocable`,
`disable-model-invocation`, `target`, `mcp-servers`, `metadata`. Agent
prompts cap at 30,000 characters.

## Measuring the workflow

The routing above is a hypothesis: that a cheap implementer plus expensive
planning and review beats running one mid-tier model throughout. Cost per
token does not settle it. **Cost per merged task, with rework counted,**
does.

Run the report:

```
.github/scripts/agent-metrics.py                 # last 30 merged PRs
.github/scripts/agent-metrics.py --since 2026-09-01
.github/scripts/agent-metrics.py --json          # machine-readable
```

It needs `gh` authenticated against the repository and nothing else — no
special permissions, no org.

### What it measures

| Metric | Reads | Tells you |
| --- | --- | --- |
| Verdict distribution | PR body `VERDICT:` | `PLANNING FAILURE` rate is the planner's report card — whether Opus 5 earns its 5× |
| Scope adherence | Issue *Files Expected to Change* vs. files changed | Whether the cheap implementer stays in its box |
| First-push CI | Check runs on the PR's first commit | Whether the implementer validated before opening, or CI caught it |
| Diff size | PR additions + deletions | Outliers mean bad decomposition upstream, not a bad implementer |
| Post-merge fixes | Later PRs touching the same files | A `PASS` needing repair days later means review was too cheap |
| Rework, steering | PR template metadata | Under-specification, and credits spent recovering from it |

Post-merge overlap is a heuristic, not proof of a defect. Churn-prone files
(`project.godot`, `README.md`) make unrelated PRs look like fixes, so the
report lists the shared paths — read them before believing the rate. On a
young repository where most PRs touch the same few files, expect this number
to be high and near-meaningless until the codebase spreads out.

### What it cannot measure

There is no per-PR or per-session cost attribution anywhere in GitHub's
surface. Credits are billed per token and aggregated per user per day.
Nothing ties a dollar figure to a session, which is why the PR template's
**Agent Session Metadata** block is filled in by hand and why
`agent-metrics.py` reports metadata coverage — rows without it are counted
but cannot be attributed to a model.

The Copilot usage metrics API does expose `ai_credits_used`, token sums, and
PR merge times, but it requires enterprise owners, organization
administrators, or billing managers. This repository is personally owned, so
that API is unavailable; moving it under an organization you own would open
it. Note that even then, `totals_by_model_feature` is empty in GitHub's own
example schema — do not expect clean per-model cost.

## Supporting files

| File | Purpose |
| --- | --- |
| `.github/workflows/agent-01-planner.yml` | Decomposes a Feature into `[impl]` sub-issues |
| `.github/workflows/agent-02-execute.yml` | Dispatches one task to the Copilot cloud agent |
| `.github/workflows/agent-03-review.yml` | Reviews a PR against its task contract, emits a verdict |
| `.github/workflows/agent-04-rollup.yml` | Task → Done, and parent → In review when the last one closes |
| `.github/actions/set-project-status/` | Shared Projects v2 plumbing; the only place `PROJECT_TOKEN` is read |
| `.github/agents/01-planner.agent.md` | Planner role, Issue promotion criteria |
| `.github/agents/02-executor.agent.md` | Executor role, scope boundaries |
| `.github/agents/03-reviewer.agent.md` | Reviewer role, verdict classification |
| `.github/scripts/validate-godot.sh` | Single source of truth for validation; CI and agents call it |
| `.github/scripts/agent-metrics.py` | Tier A outcome metrics from merged PRs |
| `.github/ISSUE_TEMPLATE/99-execute_task.md` | Planner-emitted bounded task |
| `.github/pull_request_template.md` | Handoff record, verdict, model metadata |

## Sources

- [Creating custom agents for Copilot cloud agent](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/create-custom-agents)
- [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [Changing the AI model for Copilot cloud agent](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/changing-the-ai-model)
- [Supported AI models in GitHub Copilot](https://docs.github.com/en/copilot/reference/ai-models/supported-models)
- [Models and pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
- [Copilot usage-based billing](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/)