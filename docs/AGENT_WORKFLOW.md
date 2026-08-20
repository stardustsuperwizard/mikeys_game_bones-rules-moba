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
it delegates to. A planner that delegates to `godot-implementer` in-session
runs the implementer on the planner's expensive model.

Consequence: per-role model routing on github.com requires **separate
sessions**, not subagent delegation. That is the workflow below.

The `model:` lines in `.github/agents/*.agent.md` are still correct and still
maintained — they take effect when the same profiles are run from VS Code.

## Model routing

| Role | Model | Reasoning | Where the model is set |
| --- | --- | --- | --- |
| Planner | Claude Opus 5 | High | Picker, at task kickoff |
| Implementer | Claude Haiku 4.5 | Default | Picker, per assigned Issue |
| Reviewer | Claude Opus 5 | High | Picker, on the `@copilot` review comment |

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

Three separate sessions per feature. Slower than one continuous session,
which is the trade this project accepts.

```
Human Issue (Feature template)
        │
        ▼
┌─────────────────────────────────────────┐
│ 1. PLANNING SESSION    Opus 5, high      │
│    agent: planner                        │
│ reads repo, writes plan, opens sub-issues│
└─────────────────────────────────────────┘
        │  docs/plans/<n>-<slug>.md
        │  + one sub-issue per promoted task
        ▼
┌─────────────────────────────────────────┐
│ 2. IMPLEMENTATION      Haiku 4.5         │
│    one session per Issue                 │
│    smallest change + validation → PR     │
└─────────────────────────────────────────┘
        │  draft PR per Issue
        ▼
┌─────────────────────────────────────────┐
│ 3. REVIEW SESSION      Opus 5, high      │
│    @copilot on the PR                    │
│    VERDICT: PASS / FIX / …               │
└─────────────────────────────────────────┘
        │
   PASS ─┴─ FIX → back to step 2 (Haiku)
              PLANNING FAILURE → back to step 1 (Opus)
              DESIGN AMBIGUITY → back to the human
```

### Step 1 — Planning

1. File the feature Issue yourself using the **Feature** template. Human
   Issues remain the source of truth for intended behavior.
2. Go to the agents tab, select this repository, choose the **planner**
   agent, set the model picker to **Claude Opus 5** and reasoning to
   **high**.
3. Point it at the Issue.

The planner produces:

- `docs/plans/<issue-number>-<slug>.md` from
  `.github/templates/implementation-plan.md`
- One **Implementation Task** sub-issue per promoted task in the plan, per
  the Issue Promotion Criteria in `.github/agents/planner.agent.md`

The plan file matters more than it looks. Implementation sessions start cold
and never see the planner's reasoning — the plan is the only handoff. If a
constraint is not written down, it does not exist.

If the planner records anything under **Escalations**, resolve it before
starting implementation. Do not let a cheap model resolve architectural
ambiguity.

### Issue hierarchy

The Feature Issue is the parent and remains the source of truth for intended
behavior. Every promoted Implementation Task is a direct GitHub sub-issue of
that Feature. Writing the parent number in an Issue body is not sufficient;
the GitHub sub-issue relationship must exist.

Each implementation sub-issue:

- uses the **Implementation Task** template;
- has the same milestone as its parent Feature;
- carries `implementation`, `machine`, and `agent:implement`;
- records sibling ordering with GitHub issue dependencies;
- is the only Issue assigned to the implementation agent; and
- is closed by its own implementation PR.

The parent Feature stays open while its sub-issues are implemented. Close it
only after all required sub-issues are integrated, validation passes, and the
reviewer returns `PASS`. The Project's Parent issue and Sub-issue progress
fields provide the rollup; the parent and children retain their separate
Planner Status and Implementation Status values.

### Step 2 — Implementation

For each Implementation Task sub-issue, in dependency order:

1. Assign the Issue to Copilot.
2. Set the model picker to **Claude Haiku 4.5**. Not Auto.
3. Let it run to a draft PR.

The implementer must run `.github/scripts/validate-godot.sh` and report the
command and result. Work it finds but was not asked to do goes in the PR's
**Discovered out-of-scope work** section — it does not file Issues and does
not implement them.

Tasks with `Depends on:` set wait for their dependency to merge. Record the
same relationship using GitHub's blocked-by link so it is visible outside the
Issue body. Per CONTRIBUTING.md, new work starts from the latest `main`; do
not stack PRs. Each implementation PR closes only its assigned sub-issue, not
the parent Feature.

### Step 3 — Review

1. Comment `@copilot` on the draft PR with the review request.
2. Set the model picker to **Claude Opus 5**, reasoning **high**.

The reviewer opens with a machine-readable verdict line and does not modify
code:

| Verdict | Next action | Model |
| --- | --- | --- |
| `PASS` | Merge, squash, delete branch | — |
| `FIX` | Bounded correction on the same PR | Haiku 4.5 |
| `PLANNING FAILURE` | Revise the plan, re-delegate | Opus 5 |
| `DESIGN AMBIGUITY` | Stop, ask the human | — |

`FIX` returns to the cheap model deliberately. If a task takes more than two
`FIX` cycles, that is a signal the task was under-specified — treat it as a
planning problem, not an implementation problem, and record it.

## When to collapse to one session

Split sessions cost three kickoffs of overhead. For small, mechanical, fully
specified work — a rename, a doc fix, a Task-template Issue with no
architectural content — assign it directly to Copilot on **Haiku 4.5** and
skip planning. Review still applies if the change touches `.tscn`, `.tres`,
`project.godot`, or anything under `addons/`.

## Running in VS Code

In VS Code the `model:` frontmatter is honored, so the three profiles route
themselves and the planner can delegate in-session via the `agent` tool. This
is the faster path and the right one for exploratory work; the split-session
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
| `.github/agents/planner.agent.md` | Planner role, Issue promotion criteria |
| `.github/agents/implementer.agent.md` | Implementer role, scope boundaries |
| `.github/agents/reviewer.agent.md` | Reviewer role, verdict classification |
| `.github/scripts/validate-godot.sh` | Single source of truth for validation; CI and agents call it |
| `.github/scripts/agent-metrics.py` | Tier A outcome metrics from merged PRs |
| `.github/ISSUE_TEMPLATE/07-implementation.md` | Planner-emitted bounded task |
| `.github/pull_request_template.md` | Handoff record, verdict, model metadata |
| `.github/templates/implementation-plan.md` | Planner output format |
| `docs/plans/` | Committed plans, one per feature Issue |

## Sources

- [Creating custom agents for Copilot cloud agent](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/create-custom-agents)
- [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [Changing the AI model for Copilot cloud agent](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/changing-the-ai-model)
- [Supported AI models in GitHub Copilot](https://docs.github.com/en/copilot/reference/ai-models/supported-models)
- [Models and pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
- [Copilot usage-based billing](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/)