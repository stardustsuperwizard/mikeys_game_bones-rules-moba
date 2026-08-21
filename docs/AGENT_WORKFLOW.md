# Agent Workflow and Model Routing

How Sword and Planet uses GitHub Copilot agents, and which model runs which
role. Optimized for cost and quality; latency is explicitly not a goal.

Verified against GitHub documentation on 2026-08-21. Model availability and
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
maintained — they take effect when the same profiles are run from VS Code,
JetBrains, Eclipse, or Xcode, and are inert everywhere else.

## Model routing

| Role | Model | Where the model is set |
| --- | --- | --- |
| Planner | Claude Opus 5 | `PLANNER_MODEL` env / `vars.PLANNER_MODEL` in `agent-01-planner.yml` |
| Executor | Claude Haiku 4.5 | The picker, when **you** assign Copilot. Auto in label mode. |
| Reviewer | Claude Opus 5 | `REVIEWER_MODEL` env / `vars.REVIEWER_MODEL` in `agent-03-review.yml` |

Planner and reviewer are Copilot CLI sessions, so their model is a string in
version control rather than a dropdown someone has to remember. Both are
overridable with a repository variable, so changing one does not need a
commit.

### Three entry points, three different capabilities

Execution can start three ways, and they differ in what you get to choose.
This is the single most confusing part of the setup, so it is tabulated
rather than described.

| Entry point | Model | Custom agent | Linked to the Issue | Blocked-by check |
| --- | --- | --- | --- | --- |
| **Agents panel** — start a session | **your choice** | **`executor`** | no, free text | none |
| Issue → assign Copilot | **your choice** | no | yes | after the fact |
| `agent:execute` label | Auto | **`executor`** | yes | **before dispatch** |

The agents panel is the only place you get both, which makes it the preferred
path — and it is available on GitHub Mobile. What it does not give you is a
link back to the Issue, because it takes a free-text task description instead.

That gap is closed by the **Run This Task** block the planner writes at the
top of every `[impl]` Issue: a pre-filled description carrying the Issue's own
number and a `Closes #n` line. Copy it, open the agents panel, pick `executor`
and your model, paste. The resulting PR closes the right Issue, and
`agent-02-execute.yml` picks the task up from the `pull_request` event.

The assignee screen on an Issue offers a model picker but no agent picker.
That is a property of that screen, not of mobile.

**No programmatic path can select a model.** Three independent confirmations,
checked 2026-08-21:

- `AgentAssignmentInput` — the only input to `replaceActorsForAssignable`, the
  mutation that assigns Copilot — has exactly four fields:
  `targetRepositoryId`, `baseRef`, `customInstructions`, `customAgent`. No
  model.
- `gh agent-task create` has `--custom-agent` but no `--model`.
- [cli/cli#13222](https://github.com/cli/cli/issues/13222) is an open request
  to add exactly that flag.

And the model documentation states: *"Where a model picker is not available,
Auto will be used automatically."* That is why label mode runs on Auto.

Whenever a session runs without the `executor` profile, the contract still
applies: it is in the Issue body, and in *Executing an Implementation Task* in
`.github/copilot-instructions.md`, which the cloud agent always reads.

Label mode remains for mechanical work where the model does not matter. Avoid
it for anything touching `.tscn`, `.tres`, `project.godot`, or `addons/`.

### `model:` in an agent file takes a display name

All three agent files carry a `model:` line again:

| File | `model:` |
| --- | --- |
| `01-planner.agent.md` | `Claude Opus 5` |
| `02-executor.agent.md` | `Claude Haiku 4.5` |
| `03-reviewer.agent.md` | `Claude Opus 5` |

They were removed once on the theory that `Claude Haiku 4.5` is a display
name where an identifier was wanted, and that a bad value was making custom
agents error at session start. Both halves of that were wrong, and the
correction matters because the two config formats do not agree:

- **Agent files take the display name.** VS Code documents `model:` as the
  name shown in the model picker, optionally vendor-qualified
  (`Claude Opus 5 (copilot)`), and accepts an array tried in order. So
  `Claude Haiku 4.5` was always the right spelling here.
- **Copilot CLI takes the lowercase identifier.** That is the `claude-opus-5`
  and `gpt-5.4` form the workflows pass via `--model`. Do not copy those
  strings into an agent file, or the display names out of one into a workflow.

An unresolvable `model:` is also not fatal: VS Code falls back to whatever is
selected in the model picker, so it could not have been the session-start
error. Keep the values in the table above in sync with the routing table, and
confirm a new one appears in the picker's autocomplete before committing it.

The property is still ignored by the cloud agent on github.com, so this
changes nothing about the routing above — planner and reviewer keep taking
their model from workflow env, and cloud sessions keep taking theirs from the
picker.


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
| Claude Sonnet 5 | $2.00 | $0.20 | $10.00 | Neither |
| Claude Sonnet 4.6 | $3.00 | $0.30 | $15.00 | Auto only |
| **Claude Opus 5** | $5.00 | $0.50 | $25.00 | Picker |

Opus 5 costs 5× Haiku 4.5.

### The cloud agent has no Anthropic middle tier

Verified 2026-08-21 against GitHub's model docs. Two different tables get
confused with each other, so both are recorded here.

**Auto pool for the cloud agent** — from *Supported AI models in Auto model
selection*, which is the table people misread as an availability list:

> GPT-5.3-Codex · GPT-5.4 · Claude Sonnet 4.6 · MAI-Code-1.1-Flash

**Cloud agent picker** — from *Changing the AI model for Copilot cloud agent*,
which is the actual availability list:

> Auto · Claude Sonnet 4.5 · Claude Opus 4.7 · Claude Opus 5 ·
> Claude Haiku 4.5 · Gemini 3.1 Pro · Gemini 3.5/3.6/3.7 Flash ·
> GPT-5.4 mini · GPT-5.6 Luna/Sol/Terra · Grok 4.5/4.6 ·
> MAI-Code-1-Flash · MAI-Code-1.1-Flash

Two consequences:

1. **Claude Haiku 4.5 and Claude Opus 5 are both pickable** for the cloud
   agent. Reading the Auto table alone suggests otherwise; it is not an
   availability list.
2. **Claude Sonnet 5 is in neither.** For the executor the Anthropic choice is
   Haiku 4.5 or Opus 5 — cheap or 5×, with nothing in between. Sonnet 4.6 is
   reachable only by taking Auto, which means accepting a random draw from a
   pool that is three-quarters non-Anthropic.

### Auto is a measurement problem, not just a cost one

Auto picks one of four models per session and does not tell you which. That
makes `agent-metrics.py`'s whole premise — cost per merged task, attributed
per model — unanswerable for any task dispatched that way. If you care about
the routing experiment, pick the model.

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
        ├── paste its "Run This Task" block into      ← default
        │   the agents panel                            model + agent
        │
        ├── or assign Copilot from the Issue            model only
        │
        └── or add  agent:execute                       agent only, Auto
                 │
                 ▼
┌────────────────────────────────────────────────┐
│ agent-02-execute.yml       Status: In Progress │
│ board plumbing, no AI credits                  │
│ panel  → fires on the draft PR                 │
│ assign → observes, warns on blockers           │
│ label  → refuses if blocked, then assigns      │
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

### Mostly label-driven, on purpose

Every stage but execution starts because a label was added, and each workflow
**removes the label it consumed**. That gives three properties worth keeping:

- **It works from a phone.** Adding a label is something every GitHub client
  can do, including ones with no agent controls at all.
- **Re-adding a consumed label is a clean retry.** No separate re-run verb.
- **No workflow fires on its own output**, so there are no dispatch loops.

Execution is the exception: its default trigger is *assigning Copilot*, not a
label, because that is the only way to choose the model. See
*The executor cannot have both a model and a custom agent* above.

| Trigger | Added by | Consumed by | Means |
| --- | --- | --- | --- |
| `plan` label | Issue template | — | Intake ticket, type marker |
| `agent:plan` label | You | `agent-01-planner.yml` | This Issue is ready to be planned |
| **assigning Copilot** | You | `agent-02-execute.yml` | Run this task on the model you picked |
| `agent:execute` label | You | `agent-02-execute.yml` | Run this task on Auto, with the `executor` agent |
| `agent:review` label | You | `agent-03-review.yml` | Re-review this PR |
| `planned` label | Planner | — | Feature has been decomposed |
| `review:*` label | Reviewer | — | Last verdict on a PR |

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

Work tasks in dependency order. `agent-02-execute.yml` spends no AI credits in
any mode; it is board plumbing and a dependency check. See *Three entry
points, three different capabilities* above for why there are three.

#### Agents panel — the default

Open the Implementation Task, copy its **Run This Task** block, then open the
Copilot agents panel, select the `executor` agent and **Claude Haiku 4.5**,
and paste. This is the only path that gives you both the model and the agent,
and it works from GitHub Mobile.

The workflow has nothing to fire on until the session opens its draft pull
request. At that point the `pull_request` job resolves the PR's
`closingIssuesReferences` and moves those tasks to **In Progress**. There is
no pre-flight dependency check on this path — the Run This Task block only
exists on tasks the planner created, and the Issue lists its blockers, so
check them before you paste.

#### Assign mode

Open the Implementation Task and assign it to Copilot, picking
**Claude Haiku 4.5** in the model picker. You get the model but not the
`executor` agent, because the assignee screen has no agent picker.

The workflow fires on the `assigned` event and:

1. Moves the task to **In Progress**.
2. Checks `blocked-by`. Because the session has already started, an open
   blocker is reported as a warning comment rather than a refusal — the
   session is deliberately *not* cancelled, since unassigning a live agent
   orphans its branch rather than reliably stopping it. Decide whether to let
   it finish.

You get the model you chose and no custom agent. The scope contract still
applies: it is in the Issue body, and in *Executing an Implementation Task* in
`.github/copilot-instructions.md`, which the cloud agent always reads.

#### Label mode — one tap, Auto model

Add **`agent:execute`**. The workflow:

1. **Refuses** if the task has open `blocked-by` Issues, parks it at
   **Blocked**, and removes the label. This is the only mode that can gate
   before work starts. Override with the `ignore_blockers` dispatch input.
2. Moves the task to **In Progress**.
3. Assigns `copilot-swe-agent` via `replaceActorsForAssignable` with
   `agentAssignment.customAgent`, so the session runs
   `.github/agents/02-executor.agent.md`.
4. Removes `agent:execute` so re-adding it retries.

The model is **Auto**. Use this for mechanical work where that does not
matter; avoid it for anything touching `.tscn`, `.tres`, `project.godot`, or
`addons/`.

How a custom agent is named in the API is not precisely documented —
`gh agent-task create --help` implies the filename stem, the file's own
frontmatter says `executor`, and with `02-executor.agent.md` those differ. The
workflow tries `executor`, `02-executor`, and `02-executor.agent` in turn and
logs which one GitHub accepted. If none is accepted it falls back to the
default agent rather than stranding the task. **Check the first run's log and
pin `EXECUTOR_AGENT_CANDIDATES` to the winner.**

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
- carries `implementation` and `machine`, and nothing else — the planner
  deliberately does not pre-apply `agent:execute`, because that label is a
  trigger and a pre-applied trigger is a spent one;
- records sibling ordering with GitHub issue dependencies;
- is the only Issue assigned to the executor; and
- is closed by its own implementation PR.

The parent Feature stays open while its sub-issues are implemented.
`agent-04-rollup.yml` moves it to **In review** when the last one closes; you
close it.

### Project board

Tracked on the [Sword and Planet Workflow](https://github.com/users/stardustsuperwizard/projects/1)
project. The parent Feature and its Implementation Task sub-issues each carry
their own item on the board, carrying one field:

- **Status** — one shared single-select field on every item: `Backlog`,
  `Planning`, `Ready`, `In Progress`, `In review`, `Blocked`, `Done`.

There is no separate Planner Status / Implementation Status pair; both roles
write the same Status field on their own item. A Feature row is told apart
from a Task row by the Issue itself — a Feature carries the `planned` label
and owns sub-issues; a Task is a sub-issue.

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
architectural content — skip planning: file the Issue and either assign
Copilot directly or add `agent:execute`. This is the case label mode is for.
Review still applies if the change touches `.tscn`, `.tres`, `project.godot`,
or anything under `addons/`.

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
| `model` | **Removed from all three files.** Was set to display names like `Claude Haiku 4.5`, which are not resolvable identifiers. See *Do not put `model:` in an agent file*. |
| `agents` | Not supported |
| `handoffs` | Not supported |
| reasoning level | Not settable in frontmatter — picker only ([#2904](https://github.com/github/copilot-cli/issues/2904)) |

Supported: `name`, `description`, `tools`, `user-invocable`,
`disable-model-invocation`, `target`, `mcp-servers`, `metadata`, and `model`
when given a real identifier.

Other requirements worth knowing, since violating them makes an agent fail to
load rather than degrade gracefully:

- The file must be **committed to the default branch**. An agent that exists
  only on a feature branch is not selectable.
- Filenames may contain only `.`, `-`, `_`, `a-z`, `A-Z`, `0-9`.
- The prompt body caps at **30,000 characters**. All three files are well
  under: planner ~9k, executor ~4.6k, reviewer ~1.5k.
- Valid `tools` aliases are `execute`, `read`, `edit`, `search`, `agent`,
  `web`, `todo`, `*`, `[]`, plus `server-name/tool-name` for MCP. Unrecognised
  plain names are ignored, but `01-planner.agent.md` references `github/*`,
  which needs an MCP server named `github` configured for the repository — if
  the planner ever errors at session start, that is the thing to remove.

There is **no "skill" concept** for the cloud agent. The only extension points
are custom agents and MCP servers.

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
- [Customize the reasoning level for Copilot cloud agent](https://github.blog/changelog/2026-08-03-customize-the-reasoning-level-for-copilot-cloud-agent/)
- [cli/cli#13222 — add `--model` to `gh agent-task create`](https://github.com/cli/cli/issues/13222) — open; why no programmatic path can pick a model

### Things checked directly against the API, not the docs

Re-check these with the commands rather than trusting this table.

| Claim | How to re-check |
| --- | --- |
| `AgentAssignmentInput` has no model field | `gh api graphql -f query='{__type(name:"AgentAssignmentInput"){inputFields{name}}}'` |
| `customAgent` exists on that input | same command |
| Copilot is assignable here | `gh api graphql -f query='{repository(owner:"stardustsuperwizard",name:"sword-and-planet"){suggestedActors(capabilities:[CAN_BE_ASSIGNED],first:20){nodes{login}}}}'` |
| `gh agent-task create` has no `--model` | `gh agent-task create --help` |
| Project field names and options | `gh project field-list 1 --owner stardustsuperwizard` |