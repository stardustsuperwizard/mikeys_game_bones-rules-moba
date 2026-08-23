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
| Planner | Claude Opus 5, then fallbacks | `PLANNER_MODELS` env / `vars.PLANNER_MODELS` in `agent-01-planner.yml` |
| Executor — native cloud agent | Claude Haiku 4.5 | The picker, when **you** dispatch — see *Four entry points* below. |
| Executor — scripted (`agent:execute`) | Claude Haiku 4.5, then Sonnet 5 | `EXECUTOR_MODELS` env / `vars.EXECUTOR_MODELS` in `agent-02-execute.yml` |
| Reviewer | Claude Opus 5, then fallbacks | `REVIEWER_MODELS` env / `vars.REVIEWER_MODELS` in `agent-04-review.yml` (also used by `agent-02-execute.yml`'s pre-PR self-review) |
| Fixer | Claude Sonnet 5, then fallbacks | `FIXER_MODELS` env / `vars.FIXER_MODELS` in `agent-05-fix.yml` (also used by `agent-02-execute.yml`'s pre-PR self-fix) |
| Lint fixer | Claude Haiku 4.5, then Sonnet 5 | `LINT_FIXER_MODELS` env / `vars.LINT_FIXER_MODELS` in `gdscript-lint.yml` |

Planner, the scripted executor, reviewer, and fixer are all Copilot CLI
sessions, so each one's model is a string in version control rather than a
dropdown someone has to remember. All four are overridable with a repository
variable, so changing one does not need a commit. Only the native cloud
agent — the other way to execute a task — still requires a human at a
picker; see *Four entry points* below.

The lint fixer isn't part of that four-role pipeline — it's not behind an
`agent:*` label or a *Four entry points* path, it's a narrow, unlabeled
self-heal step inside the plain `gdscript-lint.yml` status check: `gdformat`
runs unconditionally and deterministically first (no model), and only the
`gdlint` findings gdformat can't touch — which gdtoolkit has no auto-fix for
at all — go to a capped Copilot CLI session scoped to just those findings and
the files they're in. See the comment at the top of `gdscript-lint.yml` for
why that's a deliberate, narrow exception to spending a Copilot session
without a human decision first.

### All four are lists, because CLI availability is per-identity

`PLANNER_MODELS`, `EXECUTOR_MODELS`, `REVIEWER_MODELS`, and `FIXER_MODELS`
are comma-separated preference lists, resolved the same way for all four.
Planner and reviewer default to the strong tier:

```
claude-opus-5,claude-opus-4.8,claude-opus-4.7,claude-sonnet-5
```

Executor and fixer default to a cheaper tier instead — bounded,
contract-driven work doesn't need the top model the way blind planning or
review does. See `agent-02-execute.yml` and `agent-05-fix.yml` for their
exact lists.

Copilot CLI resolves model availability against the **identity making the
request**, and in Actions that identity is the workflow's `GITHUB_TOKEN`, not
your seat. The two do not always agree. A model the cloud-agent picker offers
you can still come back as:

```
Error: Model "claude-opus-5" from --model flag is not available.
```

which is what killed the first planner run
([run 32452540331](https://github.com/stardustsuperwizard/sword-and-planet/actions/runs/32452540331)).
The id was right — `claude-opus-5` is a documented Copilot CLI model — and the
`copilot-requests: write` permission was present. It was an entitlement
resolution, and there is a live history of those going wrong:
[copilot-cli#4390](https://github.com/github/copilot-cli/issues/4390) and
[#4422](https://github.com/github/copilot-cli/issues/4422) tracked a
catalogue regression that removed *every* Anthropic model from the CLI while
the policy pages still showed them enabled, resolved 2026-08-19.

So the run steps walk the list and take the first model that starts. This is
free: an unavailable model is rejected at startup, before a token is billed,
so retrying the real prompt on the next candidate costs nothing that probing
each id first would not have cost more. Only the availability error is
retried — any other failure means the model ran and failed, and re-running it
elsewhere would burn credits reproducing the same failure.

**Every entry in the planner's and reviewer's lists stays in the strong
tier.** A silent fallback to Haiku would defeat the reason planning and
review are paid for at all. Executor and fixer default to the cheap tier
deliberately, for the opposite reason — see *Model routing* above. Whichever
tier a role's list draws from, if the whole list is refused the job fails
loudly with the list it tried rather than downgrading out of tier.

The model that actually ran is recorded in the step summary, and the reviewer
names it in its PR comment — so read that, not this table, when you want to
know what reviewed a PR.

Single-valued `vars.PLANNER_MODEL` / `vars.REVIEWER_MODEL` are still honoured
and, when set, are used as the entire list.

### Four entry points, two different products

The native Copilot cloud agent (Issue assignment, the agents panel, GitHub
Mobile) cannot have its model chosen programmatically — only a human at the
picker can do that. Three independent confirmations, re-checked against the
live API on 2026-08-21 and again on 2026-08-22:

- `AgentAssignmentInput` — the only input to `replaceActorsForAssignable`, the
  mutation that assigns Copilot — has exactly four fields:
  `targetRepositoryId`, `baseRef`, `customInstructions`, `customAgent`. No
  model.
- `gh agent-task create` (v2.97.0) has `--custom-agent` but no `--model`.
- [cli/cli#13222](https://github.com/cli/cli/issues/13222) is an open request
  to add exactly that flag.

And the model documentation states: *"Where a model picker is not available,
Auto will be used automatically."* So anything dispatched through that API
without a human at the picker would run on Auto — a blind draw from a pool
that is three-quarters non-Anthropic, on a codebase whose `.tscn` and `.tres`
serialization is unforgiving.

That constraint is specific to the cloud agent's assignment API, though — it
doesn't block automation in general, only automation that goes through that
API. `agent-02-execute.yml` sidesteps it by not using that API at all: it
runs Copilot CLI directly inside Actions, the same trick `agent-01-planner.yml`
and `agent-04-review.yml` already use, driven by a preference list
(`EXECUTOR_MODELS`) instead of a picker. There was once an `agent:execute`
label that dispatched the cloud agent blind onto Auto; that version was
removed. The current `agent:execute` is a different mechanism entirely — a
scripted CLI session, not a cloud-agent assignment — and is very much
present. See *Step 2 — Execution* below for what it actually does.

So there are four ways in, across two products:

| Entry point | Model | Custom agent | Linked to the Issue |
| --- | --- | --- | --- |
| **Desktop agents panel** — start a session | **your choice** | `executor` | via the Run This Task block |
| **GitHub Mobile** — new agent session | **your choice**, *or* a custom agent — never both | either, not both | via the Run This Task block |
| Issue → assign Copilot | **your choice** | no | yes |
| `agent:execute` label — scripted, not the cloud agent | fixed preference list (`EXECUTOR_MODELS`) | n/a — not a custom-agent session | yes, `Closes #n` written by the workflow itself |

Only the desktop panel offers both pickers at once among the three
cloud-agent entry points. Mobile makes them exclusive: choose Copilot Agent
and you get the model list, choose a custom agent and the model list
disappears — which, per the documentation quoted above, means Auto. The
assignee screen offers a model and no agent anywhere.

**For the three cloud-agent entry points: take the model, every time.** The
`executor` profile is worth nothing to a cloud session: its `tools:` list is
ignored because the cloud agent's toolset is fixed, its `model:` line is
ignored because you just picked one, and its prose is mirrored into
*Executing an Implementation Task* in `.github/copilot-instructions.md`,
which **every** cloud session reads no matter how it started. If you'd
rather not be at a picker at all, that's what `agent:execute` is for — it
gives up the live choice on purpose, in exchange for full automation. See
*Step 2 — Execution* below.

What a pasted session does not give you for free is a link back to the Issue,
because it takes a free-text task description instead. That gap is closed by
the **Run This Task** block the planner writes at the top of every `[impl]`
Issue: a pre-filled description carrying the Issue's own number, a pointer to
the contract in `.github/copilot-instructions.md`, and a `Closes #n` line.
Copy it, start a session on the model you chose, paste. The resulting PR
closes the right Issue.

Directly beneath it the planner writes an **Implementation Agent Contract**
section — the short form of the same contract, ahead of the Objective rather
than below Dependencies, because an execution session starts cold and reads
top-down. So the contract reaches the session three ways: the repository
instructions file, the pasted description, and the Issue body itself. Losing
any one of them is survivable.

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
  A correct identifier is still not a guarantee of access — see *Both are
  lists* above.

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

Seven workflows in `.github/workflows/`, `agent-00` through `agent-06`. The
number no longer maps to file purpose one-to-one — `agent-03-rollup.yml` and
`agent-04-review.yml` swapped which number carries which role after
`agent-05-fix.yml` was added — so treat the filename, not the number, as
authoritative. Four spend AI credits (planner, execute, review, fix); three are
plumbing and cost nothing (dashboard, rollup, metrics). `agent-00-dashboard.yml` no
longer runs on every event — it renders on demand now. See *Issue views* and
*The control plane* below.

```
Intake Issue        [plan] in title, `plan` + type label
        │
        │  you add  agent:plan
        ▼
┌────────────────────────────────────────────────┐
│ agent-01-planner.yml                           │
│ Copilot CLI, edit/execute tools REMOVED        │
│ reads Issue body + comments + repo inventory   │
└────────────────────────────────────────────────┘
        │  validated plan JSON
        │  → [impl] sub-issues, blocked-by wired
        │  → plan comment on the Feature
        ▼
Implementation Task
        │
        ├─────────────────────────────┬───────────────────────────┐
        │  you add  agent:execute     │  you paste its "Run This  │
        │  (scripted, no live picker) │  Task" block into the     │
        │                             │  agents panel, model you  │
        │                             │  chose. (Assigning        │
        │                             │  Copilot from the Issue   │
        │                             │  also works: model, no    │
        │                             │  agent.)                  │
        ▼                             ▼
┌─────────────────────────────┐  Copilot Cloud Agent
│ agent-02-execute.yml        │       │
│ Copilot CLI, spends AI      │       ▼
│ credits: implements,        │  draft PR
│ opens the PR, then          │
│ validates, formats, self-   │
│ reviews, self-fixes         │
└─────────────────────────────┘
        │                             │
        └──────────────┬──────────────┘
                        ▼
                PR ready for review
                        │
        │  you add agent:review (auto only for the
        │  cloud agent's copilot/* branches)
        ▼
┌────────────────────────────────────────────────┐
│ agent-04-review.yml                            │
│ Copilot CLI, edit/execute tools REMOVED        │
│ diff vs. acceptance criteria → VERDICT         │
└────────────────────────────────────────────────┘
        │
   PASS  → review:pass label
   other → review:fix / planning-failure / design-ambiguity
        │
        │  review:fix?  you add  agent:fix
        ▼
┌────────────────────────────────────────────────┐
│ agent-05-fix.yml               spends AI credits│
│ Copilot CLI, edits + commits on the same branch│
│ bounded correction against the FIX verdict     │
└────────────────────────────────────────────────┘
        │
        │  you merge; the PR closes the task Issue
        ▼
┌────────────────────────────────────────────────┐
│ agent-03-rollup.yml            no AI credits   │
│ last sibling closed? comment on the parent     │
└────────────────────────────────────────────────┘
        │
   you do the human checks and close the Feature


        you add  dashboard:update  (or dispatch it)
                    │
                    ▼
┌────────────────────────────────────────────────┐
│ agent-00-dashboard.yml         no AI credits   │
│ derives every state from the repository graph  │
│ and rewrites the pinned control plane Issue    │
└────────────────────────────────────────────────┘
```

### Mostly label-driven, on purpose

Every stage starts because a label was added, and each workflow **removes
the label it consumed**. That gives three properties worth keeping:

- **It works from a phone.** Adding a label is something every GitHub client
  can do, including ones with no agent controls at all.
- **Re-adding a consumed label is a clean retry.** No separate re-run verb.
- **No workflow fires on its own output**, so there are no dispatch loops.

Execution has two products, and only one of them is label-driven. The
scripted `agent:execute` path follows the rule above like everything else,
trading a live model choice for full automation. The native cloud agent is
the exception, because a label cannot carry a model — see *Four entry
points, two different products* above.

| Trigger | Added by | Consumed by | Means |
| --- | --- | --- | --- |
| `plan` label | Issue template | `agent-01-planner.yml` | Filed, not yet decomposed |
| `agent:plan` label | You | `agent-01-planner.yml` | This Issue is ready to be planned |
| **a pasted agent session** | You | — | Run this task via the native cloud agent, on the model you picked |
| **assigning Copilot** | You | — | Run this task via the native cloud agent, on the model you picked |
| `agent:execute` label | You | `agent-02-execute.yml` | Implement this Task via the scripted CLI executor — no live picker; walks a preference list, opens the PR, then self-reviews and self-fixes against it |
| `agent:review` label | You | `agent-04-review.yml` | Re-review this PR |
| `agent:fix` label | You | `agent-05-fix.yml` | Apply the bounded correction the last `FIX` verdict asked for |
| `planned` label | Planner | — | Feature has been decomposed |
| `review:*` label | Reviewer | — | Last verdict on a PR |
| `dashboard:update` label | You | `agent-00-dashboard.yml` | Re-render the control plane |
| `dashboard` label | `agent-00` | `agent-00-dashboard.yml` | This Issue is the generated control plane |

`plan` is the one row that is not a trigger — nothing fires on it. It is a
state marker: every intake template applies it, and the planner consumes it
on success, so a Feature carries it from the moment it is filed until it has
actually been decomposed, and never afterwards. `plan` and `planned` are
mutually exclusive by construction, which is what makes
`is:issue is:open label:plan` an exact awaiting-planning queue rather than an
approximate one. See *Issue views* below.

Review is the one thing that fires without a tap, on `ready_for_review`. That
is deliberate: it is a safety net on work you already chose to start, and
gating it means an unreviewed PR can sit looking finished.

### Label colors

Colors are cosmetic — no workflow reads a label's color back, only its name
(`github.event.label.name`, `.labels[].name` in `jq` queries). Safe to
recolor any of these from the repository's Labels settings; nothing here
depends on the color. Checked live against the repository on 2026-08-22:

| Label | Color | Bootstrapped by |
| --- | --- | --- |
| `agent:plan` | `#1D76DB` | — not created by any workflow; must already exist |
| `agent:execute` | `#1D76DB` | — not created by any workflow; must already exist |
| `agent:review` | `#1D76DB` | — not created by any workflow; must already exist |
| `agent:fix` | `#1D76DB` | — not created by any workflow; must already exist |
| `plan` | `#0E8A16` | `agent-01-planner.yml` |
| `planned` | `#0E8A16` | `agent-01-planner.yml` |
| `implementation` | `#1D76DB` | `agent-01-planner.yml` |
| `machine` | `#70A8BD` | `agent-01-planner.yml` |
| `review:pass` | `#0E8A16` | `agent-04-review.yml` and `agent-02-execute.yml` (duplicated, not shared) |
| `review:fix` | `#D93F0B` | `agent-04-review.yml` and `agent-02-execute.yml` (duplicated, not shared) |
| `review:planning-failure` | `#B60205` | `agent-04-review.yml` and `agent-02-execute.yml` (duplicated, not shared) |
| `review:design-ambiguity` | `#FBCA04` | `agent-04-review.yml` and `agent-02-execute.yml` (duplicated, not shared) |
| `dashboard` | `#5319E7` | `agent-00-dashboard.yml` |
| `dashboard:update` | `#5319E7` | `agent-00-dashboard.yml` |
| `metrics:update` | `#5319E7` | `agent-06-metrics.yml` |

"Bootstrapped by" only matters if the label is ever deleted: whichever
workflow's `ensure_label` guard runs next recreates it, from that workflow's
own hardcoded color, because the guard only checks whether the name exists —
never whether the color or description still match. The four `agent:*`
labels have no such guard anywhere in `.github/`: if one of them is ever
deleted, nothing recreates it, and every trigger keyed on that name silently
stops firing until it's added back by hand.

`plan`'s color and description drifted from `agent-01-planner.yml`'s
`ensure_label "plan"` call at some point after the label was created; both
were brought back in sync with the live values on 2026-08-22.

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
where tools can be taken away entirely — `agent-01-planner.yml` and
`agent-04-review.yml` both exclude everything but reading. The scripted
executor (`agent-02-execute.yml`) and the fixer (`agent-05-fix.yml`) are
Copilot CLI sessions too, but keep `edit`/`execute` — only `task` and
`write_agent` (sub-agent spawning) are excluded — because writing code and
committing is exactly their job. The one role that still runs *with* the
cloud agent's grain instead of against it is execution's other entry point:
assigning the Issue to Copilot, or pasting the Run This Task block into the
agents panel.

**Do not run the planner or reviewer as a cloud agent from the Agents tab.**
Their agent files are for `agent-01-planner.yml`, `agent-04-review.yml`, and
interactive VS Code use.

### Setup

None. Every workflow runs on the default `GITHUB_TOKEN`.

This used to say something else. Status lived on a Projects v2 board, which
`GITHUB_TOKEN` cannot write, so every transition needed a PAT in a
`PROJECT_TOKEN` repository secret — a standing credential whose only job was
keeping a mirror in sync. The board is gone and so is the secret. **Delete
it** if it is still set:

```bash
gh secret delete PROJECT_TOKEN --repo stardustsuperwizard/sword-and-planet
```

### Step 1 — Planning

1. File the Issue with one of the intake templates. Title starts with
   `[plan]`; the template applies `plan` plus a type label.
2. When the Issue is actually ready — not when you file it — add
   **`agent:plan`**.

`agent-01-planner.yml` then:

- builds a prompt from the Issue body, **its comments**, the planner agent
  file, the task template, and a repository file inventory;
- runs Copilot CLI with implementation tools removed;
- validates the returned JSON structurally before it is allowed to create
  anything — task count, required fields, unique IDs, no self-dependency, no
  dangling `depends_on`, non-empty acceptance criteria;
- creates one `[impl]` sub-issue per task with native `--parent` and
  `--add-blocked-by` relationships;
- posts the plan as a comment on the Feature;
- adds `planned` and consumes both `agent:plan` and `plan`.

Comments are read as amendments to the body, and later comments win over the
original text. The workflow skips its own machine comments so a re-plan does
not read back its previous output as a requirement.

A second run is blocked by the `<!-- automated-planner-complete -->` marker.
To genuinely re-plan, run the workflow manually with `force: true` — and close
the stale sub-issues yourself first, because nothing removes them for you.

If the run **fails**, it removes `agent:plan`, leaves `plan` in place, and
comments with a link to the failed run. That is deliberate: `agent:plan` is
what puts a Feature in the planning view, so leaving it on a failed run would
park the Feature there forever. Giving the label back returns the Feature to
the awaiting-planning view — which is true, because `plan` never came off —
and re-adding `agent:plan` is the same clean retry as always. Check for
partial sub-issues before you do.

`plan` comes off in one place only, the success path, so a Feature can never
fall out of the intake queue without a plan to show for it.

### Step 2 — Execution

Work tasks in dependency order. The **Agent Control Plane** Issue lists what
is ready right now, grouped by Feature, with a ⚠️ against any task expected to
touch `.tscn`, `.tres`, `project.godot`, or `addons/`. It renders on demand,
so add `dashboard:update` first if it looks stale — see *The control plane*.

Two products can execute a task, trading a live model choice for automation
in opposite directions — see *Four entry points, two different products*
above for why only one of them can pick a model:

**The native Copilot cloud agent.** Open the Implementation Task, copy its
**Run This Task** block, start a new Copilot agent session on the model you
chose — mobile or desktop — and paste. Pick the model, not a custom agent.
Assigning Copilot from the Issue is the alternative: same model choice, no
paste. `issue-linking.yml` handles the closing-reference bookkeeping this
path needs, since a pasted session gets a free-text description instead of a
form.

**The scripted executor, `agent-02-execute.yml`.** Add the `agent:execute`
label instead (works from GitHub Mobile) and the workflow does the rest with
no picker involved:

1. Checks the Issue is open, labeled `implementation`, has no open
   `blocked-by` Issue, and has no pull request already open for it — any
   failure gets a comment explaining which, and the label removed, not a red
   run.
2. Runs a Copilot CLI session (`EXECUTOR_MODELS`) against the Issue body plus
   `AGENTS.md` and `.github/copilot-instructions.md`.
3. Requires an actual commit to exist afterward — not just a session that
   talked as if it finished — then immediately opens the pull request
   itself, on branch `agent-exec/<issue#>`, with `Closes #n` already in the
   body.
4. Re-runs `validate-godot.sh` and applies `gdformat` to any changed
   GDScript, pushing any formatting fix onto that already-open pull
   request.
5. Runs a self-review of the diff (`REVIEWER_MODELS`, the same strong tier
   `agent-04-review.yml` uses) against the already-open pull request. If
   that verdict is `FIX`, runs one bounded self-fix pass (`FIXER_MODELS`)
   and pushes it too.

A `PASS` (or an unfixed `FIX`) is posted to the pull request as the real
verdict, `review:*` label included — so adding `agent:review` to it is a
second opinion, not a first one. The pull request opens right after step 3,
before validation, formatting, or review ever run, so a failure in any of
those (e.g. a validation failure) just leaves a comment on the already-open
pull request explaining what got skipped — there is always something to
work with instead of a dead-end Issue comment. Only a failure *before* the
pull request exists — no commit, an uncommitted session, `gh pr create`
itself failing — comments on the Issue and removes `agent:execute` rather
than opening a broken PR, so re-adding the label is a clean retry in that
case.

Run it by hand against any Issue number to re-check:

```bash
gh workflow run agent-02-execute.yml -f issue_number=68
```

### Step 3 — Review

`agent-04-review.yml` runs automatically when a `copilot/*` branch's PR is
marked ready for review, or any time you add **`agent:review`**. Only the
native cloud agent's branches match `copilot/*` — the scripted executor's
`agent-exec/*` branches and a Claude Code PR's branch don't, so both need the
manual label.

It answers the question the built-in Copilot code review does not: *is this
diff complete against the acceptance criteria it was authorized by?* It walks
the PR's `closingIssuesReferences` back to the Implementation Task, loads that
contract plus the plan file, and reviews the diff against it criterion by
criterion.

The first line is machine-readable:

| Verdict | PR label | Means | Next action |
| --- | --- | --- | --- |
| `PASS` | `review:pass` | Ready to merge | Merge, squash, delete branch |
| `FIX` | `review:fix` | Needs your attention | Bounded correction on the same PR |
| `PLANNING FAILURE` | `review:planning-failure` | Needs your attention | Revise the plan, re-delegate |
| `DESIGN AMBIGUITY` | `review:design-ambiguity` | Needs your attention | Stop, decide it yourself |

These four labels are load-bearing, not decoration: they are the only part of
a PR's state that is not implied by the issue graph, so a "needs attention"
view is exactly `label:review:fix,review:planning-failure,review:design-ambiguity`.
`agent-04-review.yml` clears the other three before adding one, which is what
makes "the `review:*` label on a PR" and "the most recent verdict" the same
thing — and what keeps those views from double-counting a PR.

Fix cycles are not automatic — nothing re-summons a session just because a
verdict came back adverse, because an auto-fix loop can burn credits without
converging. A human decides when to spend one, by adding **`agent:fix`**
(works from GitHub Mobile), which runs `agent-05-fix.yml`: it re-reads the
latest `<!-- agent-review-verdict -->` comment, requires that verdict to
still say `FIX` — a stale `review:fix` label surviving a later review is a
no-op, not a wasted session — and applies one bounded correction against its
**Required Before Merge** list on the same branch. `PLANNING FAILURE` and
`DESIGN AMBIGUITY` verdicts get a comment explaining why the fixer won't
touch them instead of a session — re-plan the former, decide the latter
yourself. The equivalent local path is `/fix-review <pr-number>` or the
`fixer` Claude Code agent; commenting `@copilot` on the PR still works too,
outside this repository's scripted path.

If a task takes more than two `FIX` cycles, that is a planning problem, not an
implementation problem. Record it.

### Step 4 — Rollup

`agent-03-rollup.yml` fires on any Issue closing or reopening. No AI credits.
It writes no status, because status is derived — its whole job is to
**notify**. When the last open sibling closes, it comments on the parent
Feature saying so.

A comment specifically, because a comment sends a push notification. The
control plane Issue shows the same Feature under *Awaiting your sign-off* once
it is re-rendered, and an issue view can be filtered to surface it — but
neither one pushes.

What is left is human: confirm the Feature's own acceptance criteria hold end
to end, do the **Human Validation Required** checks in the Godot editor, then
close the Feature. Nothing closes a Feature automatically — that transition is
the human sign-off, and automating it would remove the only checkpoint in the
pipeline.

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
  applies no `agent:*` label, because those are dispatch triggers a human
  adds and a pre-applied trigger is a spent one;
- records sibling ordering with GitHub issue dependencies;
- is the only Issue assigned to the executor; and
- is closed by its own implementation PR.

The parent Feature stays open while its sub-issues are implemented.
`agent-03-rollup.yml` comments on it when the last one closes; you close it.

This structure is also what the issue views read. A task is an issue with a
parent; a Feature is an issue with sub-issues. That is deliberately structural
rather than label-based — labels on tasks have drifted before, the graph has
not.

### Issue views

There is no dashboard. State is a **label query**, saved as a GitHub issue
view, and the label vocabulary above is designed so that each state is one
filter. Views cost nothing, cannot go stale, and are edited in the UI without
a workflow run, a token, or a pinned Issue to keep clean.

The views worth having, and the queries behind them:

| View | Query |
| --- | --- |
| Awaiting planning | `is:issue is:open label:plan -label:"agent:plan"` |
| Planning in flight | `is:issue is:open label:"agent:plan"` |
| Planned Features | `is:issue is:open label:planned` |
| Open tasks | `is:issue is:open label:implementation` |
| Awaiting review | `is:pr is:open draft:false -label:"review:pass","review:fix","review:planning-failure","review:design-ambiguity"` |
| Needs your attention | `is:pr is:open label:"review:fix","review:planning-failure","review:design-ambiguity"` |
| Ready to merge | `is:pr is:open label:"review:pass"` |

Quote any label containing a colon. `label:agent:plan` is parsed as a label
named `agent` qualified by a stray `plan`, and silently returns the wrong
set; `label:"agent:plan"` is unambiguous. Commas inside a single `label:`
qualifier are OR.

Two properties make these queries exact rather than approximate, and both are
enforced by the workflows:

- **`plan` and `planned` are mutually exclusive.** The planner adds one and
  removes the other in the same step, and only on success. So *Awaiting
  planning* is never a Feature that already has tasks, and never silently
  loses one that failed to plan.
- **A PR carries at most one `review:*` label.** `agent-04-review.yml` clears
  the other three before adding one, so *Needs your attention* and *Ready to
  merge* cannot both claim the same PR.

The `-label:"agent:plan"` exclusion is what separates "queued" from
"running": `agent:plan` is consumed by the planner on success and given back
on failure, so a Feature is in exactly one of the two views at any moment.

What a view cannot express is the **dependency graph** — there is no label
for "blocked by #12", and no query that orders tasks by it. That is the one
question views leave unanswered, and it happens to be the question you
actually ask: *what can I dispatch right now?* It is why the control plane
below still exists.

### The control plane

`agent-00-dashboard.yml` regenerates a pinned Issue titled **Agent Control
Plane**. It spends no AI credits, needs no secrets beyond `GITHUB_TOKEN`, and
answers the one thing a view cannot: what is unblocked right now, grouped by
Feature, in dependency order.

Every state it shows is **derived** — computed from the repository graph at
the moment it runs, and stored nowhere:

| Condition | Task state |
| --- | --- |
| Issue closed | Done |
| Open `blocked-by` issues | Blocked — dependencies |
| No linked PR | **Ready to dispatch** |
| Draft PR open | Implementing |
| PR ready, no `review:*` | Awaiting review |
| `review:fix` / `-planning-failure` / `-design-ambiguity` | **Needs your attention** |
| `review:pass` | **Ready to merge** |

| Condition | Feature state |
| --- | --- |
| Issue closed | Done |
| `agent:plan` present | Planning |
| No sub-issues | Awaiting planning |
| Sub-issues, some open | In progress |
| Sub-issues, all closed | **Awaiting your sign-off** |

Order matters in the task table: a draft PR reads as *Implementing* even when
a `review:fix` label is still present, because that label persists through the
bounded correction that answers it. Testing draft-ness first is what stops
every in-flight fix from showing as waiting on you.

#### Rendering it

It runs **on demand**, not on every event:

| How | When to use it |
| --- | --- |
| Add `dashboard:update` to any Issue | The normal way. Works from any GitHub client, including mobile |
| Run the workflow manually | From the Actions tab, when you are already there |

`dashboard:update` is a button, not a state. The last step of every run
clears it, so re-adding it is another refresh. Nothing subscribes to
`unlabeled`, so removing it cannot re-trigger anything.

That step is deliberately **trigger-agnostic**: it sweeps every Issue carrying
the label rather than only the one whose `labeled` event fired. A render is a
render, so a manual dispatch — or a re-enabled `schedule` run — clears a
pending request too, instead of leaving a label sitting on an Issue whose
refresh has already happened.

It runs under `if: always()`, so a *failed* render still clears the label. The
board is stale either way, and a stale board with the button already pressed
is a dead end — you could not ask again without removing the label by hand.
The cost is that a failed refresh looks the same as one that was never
requested; the step summary and the run's own failure are where you see it.

The label is applied to *any* Issue; the pinned control plane Issue itself is
the obvious place, since that is what you are looking at when you notice it is
stale. The workflow ignores which Issue it came from.

Two triggers are **commented out in the workflow rather than deleted**, so
they can be restored with an editor and no thought:

- **`pull_request`** — the expensive one. It fired on every PR event including
  `opened`, stacking a render onto PR creation alongside `agent-04-review.yml`
  and `godot-ci-validation.yml`. Re-enable it if a stale control plane starts
  costing more than the noise does.
- **`schedule`** (nightly `17 6 * * *`) — this was the staleness *bound*: a
  missed refresh could not leave the board wrong for longer than a day.
  Without it, staleness is bounded only by you remembering to press the
  button. That is the live trade-off, and the cheapest one to reverse.

Run the same derivation locally at any time, no workflow involved:

```bash
.github/scripts/render-dashboard.py            # the markdown
.github/scripts/render-dashboard.py --json     # just the states
```

#### Why this replaced a Projects v2 board

Status used to live on the [Sword and Planet
Workflow](https://github.com/users/stardustsuperwizard/projects/1) project,
written by eleven steps across four workflows through a shared
`set-project-status` composite action. Three problems, in order of how fatal:

1. **A board cannot cause work.** There is no repository-level Actions trigger
   for a project item change — that webhook exists only at organization scope,
   and Project 1 is user-owned. So a board can record state and never act on
   it. A control plane that cannot cause anything is a report; better to build
   an honest report.
2. **It needed a PAT.** `GITHUB_TOKEN` cannot write Projects v2, so a
   `PROJECT_TOKEN` secret existed purely to keep a mirror in sync.
3. **It was a second source of truth.** Every one of its `Status` values was
   already implied by issue state, dependencies, and labels. Eleven writes
   maintained a copy of facts GitHub already stored, and any failed run left
   the copy wrong.

Derived state cannot drift. A failed render leaves the Issue stale — visibly,
with its own timestamp — and never leaves the repository misdescribed. That
property is what makes an on-demand refresh safe: the worst an un-pressed
button can do is show you yesterday.

#### Finding and re-creating it

The dashboard Issue is located by its `dashboard` label, not by title or body,
so renaming it is harmless. If it is ever deleted, the next run creates and
pins a new one. If three Issues are already pinned the pin fails with a
warning and the dashboard still works.

The `dashboard:update` label is created by the workflow too, on any run — so
if it does not exist yet, dispatch the workflow once from the Actions tab and
the button will be there afterwards.

Do not edit the Issue by hand — the next run overwrites the body.

## When to collapse to one session

For small, mechanical, fully specified work — a rename, a doc fix, a
Task-template Issue with no architectural content — skip planning. File the
Issue and dispatch it straight from an agent session or by assigning Copilot.
Nothing requires an Issue to have come from the planner.

Review still applies if the change touches `.tscn`, `.tres`, `project.godot`,
or anything under `addons/`.

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

## Claude Code as an additional environment

Every path above assumes GitHub Copilot. Claude Code — the terminal/desktop
app, Claude Code on the web, or Remote Control — can execute the same
Implementation Task Issues instead, because the contract those Issues encode
is tool-agnostic: acceptance criteria, scope, and expected files live in the
Issue body, with `AGENTS.md` and `.github/copilot-instructions.md` for the
rest. `CLAUDE.md` at the repository root exists for exactly this — it points
Claude Code at those same files rather than duplicating them, so there is one
contract, not two to keep in sync.

`.claude/agents/*.md` and `.claude/commands/*.md` are local Claude Code
counterparts of the four roles, invoked as `/plan-feature`, `/execute-task`,
`/review-task`, and `/fix-review`, or their matching subagents (`planner`,
`executor`, `reviewer`, `fixer`):

| Role | GitHub-side | Claude Code-side |
| --- | --- | --- |
| Plan | `agent-01-planner.yml` / `.github/agents/01-planner.agent.md` | `.claude/commands/plan-feature.md` / `.claude/agents/planner.md` |
| Execute | `agent-02-execute.yml` / `.github/agents/02-executor.agent.md` | `.claude/commands/execute-task.md` / `.claude/agents/executor.md` |
| Review | `agent-04-review.yml` / `.github/agents/03-reviewer.agent.md` | `.claude/commands/review-task.md` / `.claude/agents/reviewer.md` |
| Fix | `agent-05-fix.yml` / `.github/agents/05-fixer.agent.md` | `.claude/commands/fix-review.md` / `.claude/agents/fixer.md` |

The two sides share the Issue and PR graph, not a runtime. A PR opened by
Claude Code doesn't land on a `copilot/*` branch, so it won't trigger
`agent-04-review.yml`'s automatic `ready_for_review` review — add
`agent:review` by hand (works from GitHub Mobile) to put it through the same
reviewer, same as the scripted executor's own `agent-exec/*` branches
already require. Everything else — labels, the control plane, rollup, the
dashboard — reads the Issue graph the same way regardless of which tool
produced the diff, so switching tools mid-Feature, or per task, doesn't
require picking one system and discarding the other.

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

### Getting the report without a shell

`agent-06-metrics.yml` posts the same report as an Issue comment on demand,
same button-not-state pattern as the control plane: add **`metrics:update`**
to any Issue and it comments a fresh `agent-metrics.py` run there, then
removes the label. Works from GitHub Mobile. `workflow_dispatch` also takes
`issue_number`, `limit`, `since`, and `window_days` directly, for a
one-off run against a specific range without touching a label at all.

It is still the same outcome-metrics report, not a cost report — see *What it
cannot measure* above. Comparing Opus vs. Haiku sessions means comparing rows
by `implementation_model` in the output, not a credits figure.

## Supporting files

| File | Purpose |
| --- | --- |
| `.github/workflows/agent-00-dashboard.yml` | Rewrites the pinned control plane Issue from derived state, on `dashboard:update` or dispatch |
| `.github/workflows/agent-01-planner.yml` | Decomposes a Feature into `[impl]` sub-issues |
| `.github/workflows/agent-02-execute.yml` | Scripted implementer: implements, opens the PR, then validates, formats, self-reviews, and self-fixes against it, on `agent:execute` |
| `.github/workflows/agent-03-rollup.yml` | Comments on the parent Feature when its last sub-issue closes |
| `.github/workflows/agent-04-review.yml` | Reviews a PR against its task contract, emits a verdict |
| `.github/workflows/agent-05-fix.yml` | Applies a bounded correction against the latest `FIX` verdict, on `agent:fix` |
| `.github/workflows/agent-06-metrics.yml` | Posts an `agent-metrics.py` report as an Issue comment, on `metrics:update` or dispatch |
| `.github/actions/build-review-request` | Shared by `agent-04-review.yml` and `agent-02-execute.yml`'s pre-PR pass: builds the reviewer prompt |
| `.github/actions/build-fix-request` | Shared by `agent-05-fix.yml` and `agent-02-execute.yml`'s pre-PR pass: builds the fixer prompt |
| `.github/actions/run-copilot-session` | Shared by planner, executor, reviewer, and fixer: walks a model preference list, enforces the credit cap |
| `.github/actions/extract-review-verdict` | Turns a review session's text into a machine-readable `VERDICT` |
| `.github/actions/lint-gdscript` | Diff-scoped `gdformat` check/fix, used by `agent-02-execute.yml` and `gdscript-lint.yml` |
| `.github/scripts/render-dashboard.py` | Derives every task and Feature state from the repository graph |
| `.github/agents/01-planner.agent.md` | Planner role, Issue promotion criteria |
| `.github/agents/02-executor.agent.md` | Executor role, scope boundaries |
| `.github/agents/03-reviewer.agent.md` | Reviewer role, verdict classification |
| `.github/agents/05-fixer.agent.md` | Fixer role, bounded-correction contract |
| `.github/scripts/validate-godot.sh` | Single source of truth for validation; CI and agents call it |
| `.github/scripts/agent-metrics.py` | Tier A outcome metrics from merged PRs |
| `.github/ISSUE_TEMPLATE/99-execute_task.md` | Planner-emitted bounded task |
| `.github/pull_request_template.md` | Handoff record, verdict, model metadata |
| `CLAUDE.md` | Points Claude Code at the same contract Copilot reads |
| `.claude/agents/*.md`, `.claude/commands/*.md` | Local Claude Code counterparts of the four roles — see *Claude Code as an additional environment* |

## Sources

- [Creating custom agents for Copilot cloud agent](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/create-custom-agents)
- [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [Changing the AI model for Copilot cloud agent](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/changing-the-ai-model)
- [Supported AI models in GitHub Copilot](https://docs.github.com/en/copilot/reference/ai-models/supported-models)
- [Models and pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
- [Copilot usage-based billing](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/)
- [Customize the reasoning level for Copilot cloud agent](https://github.blog/changelog/2026-08-03-customize-the-reasoning-level-for-copilot-cloud-agent/)
- [cli/cli#13222 — add `--model` to `gh agent-task create`](https://github.com/cli/cli/issues/13222) — open; why no programmatic path can pick a model
- [Using Copilot CLI in GitHub Actions with `GITHUB_TOKEN`](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli-in-actions) — the `copilot-requests: write` permission
- [copilot-cli#4390](https://github.com/github/copilot-cli/issues/4390) and [#4422](https://github.com/github/copilot-cli/issues/4422) — Anthropic models absent from the CLI catalogue while shown enabled in policy

### Things checked directly against the API, not the docs

Re-check these with the commands rather than trusting this table.

| Claim | How to re-check |
| --- | --- |
| `AgentAssignmentInput` has no model field | `gh api graphql -f query='{__type(name:"AgentAssignmentInput"){inputFields{name}}}'` |
| `customAgent` exists on that input | same command |
| Copilot is assignable here | `gh api graphql -f query='{repository(owner:"stardustsuperwizard",name:"sword-and-planet"){suggestedActors(capabilities:[CAN_BE_ASSIGNED],first:20){nodes{login}}}}'` |
| `gh agent-task create` has no `--model` | `gh agent-task create --help` |
| The `plan` queue is not stale | `gh issue list --label plan --json number,title,labels` — nothing here should also carry `planned` |
| Derived state matches reality | `.github/scripts/render-dashboard.py --json` |