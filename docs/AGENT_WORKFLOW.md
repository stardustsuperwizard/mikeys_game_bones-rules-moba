# Agent Workflow and Model Routing

How Mikey's Game Bones MOBA Rules uses GitHub Copilot agents, and which model runs which
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
it delegates to. A planner that delegates to `implementor` in-session
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
| Implementor — native cloud agent | Claude Haiku 4.5 | The picker, when **you** dispatch — see *Four entry points* below. |
| Implementor — scripted (`agent:execute`) | Per task, from the Issue's `model:*` label; Claude Opus 5, then Sonnet 5, then Haiku 4.5 when unlabelled | `model:*` label → `agent-02-implement.yml`'s *Resolve Implementor Model Tier*; default and override in `IMPLEMENTOR_MODELS` env / `vars.IMPLEMENTOR_MODELS`. See *The implementor's tier is chosen per task* below |
| Reviewer | Claude Opus 5, then fallbacks | `REVIEWER_MODELS` env / `vars.REVIEWER_MODELS` in `agent-04-review.yml` (also used by `agent-02-implement.yml`'s pre-PR self-review) |
| Fixer | Claude Sonnet 5, then fallbacks — climbing a tier per repeat round | `FIXER_MODELS` env / `vars.FIXER_MODELS` in `agent-05-fix.yml` (also used by `agent-02-implement.yml`'s pre-PR self-fix); escalation in its *Resolve Fixer Model Tier* step |
| Lint fixer | Claude Haiku 4.5, then Sonnet 5 | `LINT_FIXER_MODELS` env / `vars.LINT_FIXER_MODELS` in `gdscript-lint.yml` |

Planner, the scripted implementor, reviewer, and fixer are all Copilot CLI
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

`PLANNER_MODELS`, `IMPLEMENTOR_MODELS`, `REVIEWER_MODELS`, and `FIXER_MODELS`
are comma-separated preference lists, resolved the same way for all four.
Planner and reviewer default to the strong tier:

```
claude-opus-5,claude-opus-4.8,claude-opus-4.7,claude-sonnet-5
```

Implementor and fixer default to a cheaper tier instead — bounded,
contract-driven work doesn't need the top model the way blind planning or
review does. See `agent-02-implement.yml` and `agent-05-fix.yml` for their
exact lists.

### Claude Code gets one fallback chain, not four lists

The `.claude` roles cannot express the table above. A Claude Code subagent's
`model:` frontmatter is a single scalar — an alias (`sonnet`, `opus`,
`haiku`, `fable`), a full model ID, or `inherit` — with no array form and no
comma-separated preference list. The `model` parameter on a subagent call is
a single value too. There is nowhere to write `PLANNER_MODELS` locally.

What exists instead is `fallbackModel`, and it is **one chain for the whole
session**, applied to every subagent in it:

```jsonc
// .claude/settings.json
{ "fallbackModel": ["claude-opus-5", "claude-opus-4-8"] }
```

**The chain only ever escalates, and that is the whole design.** A chain is
session-wide, so the same list that catches an unavailable Haiku implementor also
catches an unavailable Opus reviewer. A natural-looking
`["claude-sonnet-5", "claude-haiku-4-5"]` would quietly hand a Haiku model the
review of a pull request the planner deliberately tiered to Opus — the exact
outcome `IMPLEMENTOR_MODELS` refuses when its `haiku` tier falls *up* through
`claude-sonnet-5` to `claude-opus-5` rather than down. Escalate-only is the
one shape a single shared chain can take without contradicting the tiering
everything else in this document is built on. It costs more only when a model
is genuinely unavailable, which is rare; a review done cheaply because Opus
was busy costs a fix cycle, and that is not cheaper.

Three things about it are easy to get wrong.

- **The file has to be `.claude/settings.json`, committed.** A cloud session —
  Claude Code on the web, and therefore the Claude mobile app — runs on a
  fresh clone and reads shared project settings out of it. It does **not**
  read `~/.claude/settings.json` or `.claude/settings.local.json`; both stay
  on the machine. Anything that must apply from a phone has to be in the
  clone. `.gitignore` ignores `.claude/*` wholesale, so this file needs its
  own `!.claude/settings.json` negation next to the ones for `agents/` and
  `commands/` — without it the setting works on the desktop and is invisible
  everywhere it was written for. `settings.local.json` stays ignored on
  purpose: it is the personal override, and a personal override that reached
  cloud sessions would not be one.
- **These are Claude Code model IDs, and they use dashes.** `claude-opus-4-8`,
  not the `claude-opus-4.8` that appears in `IMPLEMENTOR_MODELS` above — that is
  the Copilot CLI spelling. This is the same two-namespace hazard
  *`model:` in an agent file takes a display name* describes for agent files
  and `--model`, and the failure is quiet: an unreachable entry is skipped and
  the chain moves on, so a mistyped ID looks exactly like a chain that was
  never needed.
- **Subagent coverage needs Claude Code v2.1.247 or later.** Before it, a
  failure the chain covers ended the subagent instead of failing it over. On
  an older build the file is harmless but does nothing for the four roles,
  which is the only place it matters here.
- **It does not reach CI.** The agent workflows run Claude with `--bare`,
  which does not read `.claude/settings.json`, so this chain applies to
  interactive and cloud sessions only. In CI the `models` preference list on
  `run-agent-session` is the fallback, per role rather than per session --
  the same mechanism the Copilot side has always used. Two fallback systems
  that happened to agree would be harder to reason about than one that
  plainly owns the job.

The trigger conditions match `run-agent-session`'s rule closely enough to
be worth stating: Claude Code switches when the primary is overloaded,
unavailable, or returns another non-retryable server error, and never on
authentication, billing, rate-limit, request-size, transport, or policy
errors. Both systems fall back on *unavailability alone* — never after a real
failure, because a cheap retry after a genuine failure defeats whichever tier
the caller chose. Claude Code caps the chain at three after removing
duplicates, and a switch lasts one turn.

### The implementor's tier is chosen per task

Every other role in the table gets one list for the whole repository. The
implementor gets a starting point per Issue, because the tasks it runs are not
alike: adding a field and its accessor is not the same work as changing how
authority is resolved, and paying the same model for both wastes money on one
and risks the other.

The planner sets it. It is the only role that sees the whole feature at once
and reads the code before it is written, so it is the only one positioned to
judge how much model a task needs — and it is already an Opus session, so the
judgement is made by the most capable model in the pipeline. The rubric it
follows is *Choosing a model tier* in `.github/agents/01-planner.agent.md`;
its one-line summary is that `haiku` is for work fully determined by the
contract, `sonnet` is the default and the answer when unsure, and `opus` is
for work where a wrong choice is expensive to undo.

It travels as a label — `model:haiku`, `model:sonnet`, `model:opus` — with the
reasoning mirrored in the Issue's **Model Tier** section. The label is what
the workflow reads; the prose is what lets you check the call and relabel by
hand when it looks wrong. Nothing re-reads the prose.

**It is a tier, not a model id, and that is load-bearing.** The Copilot CLI
and `claude-code-action` spell the same models differently —
`claude-haiku-4.5` against `claude-haiku-4-5-20251001` — and this document
warns elsewhere against copying one spelling into the other. An Issue that
named an id would bind the task to whichever pipeline used that namespace. A
tier is meaningful to both, and each workflow maps it to its own ids.

Both vendors do, from one place. `agent-02-implement.yml`'s
*Resolve Implementor Model Tier* step resolves the tier through a
`tier_models` helper that spells it for whichever vendor the label named —
`claude-haiku-4.5` for Copilot CLI, `claude-haiku-4-5` for Claude Code. One
decision, made once by the planner, read by whichever implementor the label
summons. The planner and reviewer keep their configured per-vendor lists:
planning and review are repository-wide judgements, not per-task ones.

The escalation runs per vendor on the same signal: a fix cycle counts the
same `<!-- agent-fix-applied -->` comments `agent-05-fix.yml` counts, and
climbs a tier per round past `CLAUDE_FIXER_ESCALATE_AFTER` (default `1`). A
pull request fixed once by one pipeline therefore escalates on the other,
which is the point of sharing a marker rather than each keeping its own tally.

The two bounds that hold on the Copilot side hold here as well, and for the
same reasons. Setting `vars.CLAUDE_IMPLEMENTOR_MODEL` or `vars.CLAUDE_FIXER_MODEL`
skips tier resolution entirely for that role: an operator naming a model has
made a decision about this repository, and neither a planner's guess about one
task nor an escalation counter overrules it. And the fix cycle treats its
configured model as a **floor** rather than a starting point to overwrite —
the Issue's tier applies only when it is higher, and when nothing has raised
the fixer above where it is configured to run, the configured id is handed
back untouched rather than replaced by a tier's idea of it.

Four rules bound what the recommendation can do:

- **It prepends, it does not replace.** `run-agent-session` advances through
  the list only when a model is unavailable to the calling identity, never
  after a real failure, so the list is what keeps an availability gap from
  ending the run. A single id would turn every such gap into a dead job.
- **Each tier's list ascends; the unlabelled default descends.** `model:haiku`
  resolves to `claude-haiku-4.5,claude-sonnet-5,claude-opus-5`. The asymmetry
  is deliberate: the default starts at the top and has nowhere to go but down,
  while a tier is a floor someone chose, and falling below it would silently
  run a task on less model than was asked for. Unavailability should cost
  money, not correctness.
- **An operator outranks the planner.** Setting `vars.IMPLEMENTOR_MODELS` is a
  deliberate decision about this repository; a planner's guess about one task
  does not overrule it. `vars.IMPLEMENTOR_TIER_FLOOR` (default `haiku`) raises
  the lower bound instead, without editing the rubric or relabelling anything.
  `vars.CLAUDE_IMPLEMENTOR_TIER_FLOOR` is its counterpart on the Claude
  pipeline. Both bind the implementor only: the fixers already have a floor in
  the model they are configured with, and a floor bounds a recommendation
  rather than inventing one, so an Issue carrying no tier at all is not
  raised to it — it takes the configured default as before.
- **No label means no change.** An Issue without a `model:*` label runs on the
  default list exactly as it did before this existed, which is also what
  happens if the three labels are never created — the planner applies the
  label as a follow-up edit rather than at creation time, so a missing label
  costs the hint, not the plan.

The three labels do have to exist for the hint to land: create `model:haiku`,
`model:sonnet` and `model:opus` once. Until then, planning and execution both
work, and the planner logs each label it could not apply.

**What this leans on.** A cheaper implementor is only safe because a strong
reviewer follows it — the reasoning this document already gives for the
implementor's tier being cheaper than the planner's. This change leans harder on
that, so the reviewer staying on the strong tier stops being a preference and
becomes the thing holding the arrangement up.

### A pull request that keeps coming back buys a better model

The planner calls the tier before the code exists, so it will sometimes call
it wrong, and the failure is asymmetric. Over-calling costs money once.
Under-calling costs a session that cannot finish, a review that rejects it, and
a fix cycle — repeated at the same tier for as long as nobody notices, which
is how a task scoped as cheap becomes the most expensive one in the milestone.

So `agent-05-fix.yml` climbs. Its *Resolve Fixer Model Tier* step counts the
fix rounds already completed on the pull request and raises the tier one step
for each round past `FIXER_ESCALATE_AFTER` (default `1`), to a ceiling of
`opus`. With the default, the first fix runs where the fixer runs today and the
second buys Opus. Set it to `0` to escalate immediately, or to something large
to switch escalation off.

Three properties are worth stating, because each one is a decision:

- **It only ever raises.** The base is `FIXER_BASE_TIER` (default `sonnet`),
  and the Issue's `model:*` tier applies only when it is *higher* than that. A
  cheap implementor is a cost decision made before the code existed; the fixer is
  a correction responding to a reviewer who has read the code, and spending
  less on it than this repository already does would be a regression wearing a
  feature's clothes. So `model:haiku` never produces a cheaper fixer — but
  `model:opus` does produce a stronger one, from the first round.
- **Rounds are counted from `<!-- agent-fix-applied -->`,** the marker
  *Publish Fix* posts when a fix was actually pushed. A session that crashed
  before diagnosing anything does not count against the budget: escalating on
  a crash spends more model on a problem nobody has understood yet.
- **Nothing changes until something is raised.** When the effective tier is
  no higher than the base, the configured `FIXER_MODELS` list is used
  untouched — it carries intermediate ids like `claude-sonnet-4.5` that a tier
  list does not, and narrowing the fallback walk for no reason would trade
  availability for tidiness.

`FIXER_BASE_TIER` is a tier name rather than something inferred from the first
id in `FIXER_MODELS`, so that retuning that list later does not silently move
where the climb starts.

An explicitly set `vars.FIXER_MODELS` skips all of it, the same way it does on
the implementor side: if you name the list, you own it, including on the fourth
round. And the ceiling is real — once a pull request is at `opus`, further
rounds cannot buy anything, and the run log says so. A fix that keeps failing
at the top tier is telling you the finding is not a model problem.

Copilot CLI resolves model availability against the **identity making the
request**, and in Actions that identity is the workflow's `GITHUB_TOKEN`, not
your seat. The two do not always agree. A model the cloud-agent picker offers
you can still come back as:

```
Error: Model "claude-opus-5" from --model flag is not available.
```

which is what killed the first planner run
([run 32452540331](https://github.com/stardustsuperwizard/mikeys_game_bones-rules-moba/actions/runs/32452540331)).
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
review are paid for at all. Implementor and fixer default to the cheap tier
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
API. `agent-02-implement.yml` sidesteps it by not using that API at all: it
runs Copilot CLI directly inside Actions, the same trick `agent-01-planner.yml`
and `agent-04-review.yml` already use, driven by a preference list
(`IMPLEMENTOR_MODELS`) instead of a picker. There was once an `agent:execute`
label that dispatched the cloud agent blind onto Auto; that version was
removed. The current `agent:execute` is a different mechanism entirely — a
scripted CLI session, not a cloud-agent assignment — and is very much
present. See *Step 2 — Execution* below for what it actually does.

So there are four ways in, across two products:

| Entry point | Model | Custom agent | Linked to the Issue |
| --- | --- | --- | --- |
| **Desktop agents panel** — start a session | **your choice** | `implementor` | via the Run This Task block |
| **GitHub Mobile** — new agent session | **your choice**, *or* a custom agent — never both | either, not both | via the Run This Task block |
| Issue → assign Copilot | **your choice** | no | yes |
| `agent:execute` label — scripted, not the cloud agent | preference list, led by the Issue's `model:*` tier (`IMPLEMENTOR_MODELS` otherwise) | n/a — not a custom-agent session | yes, `Closes #n` written by the workflow itself |

Only the desktop panel offers both pickers at once among the three
cloud-agent entry points. Mobile makes them exclusive: choose Copilot Agent
and you get the model list, choose a custom agent and the model list
disappears — which, per the documentation quoted above, means Auto. The
assignee screen offers a model and no agent anywhere.

**For the three cloud-agent entry points: take the model, every time.** The
`implementor` profile is worth nothing to a cloud session: its `tools:` list is
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
| `02-implementor.agent.md` | `Claude Haiku 4.5` |
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
2. **Claude Sonnet 5 is in neither.** For the implementor the Anthropic choice is
   Haiku 4.5 or Opus 5 — cheap or 5×, with nothing in between. Sonnet 4.6 is
   reachable only by taking Auto, which means accepting a random draw from a
   pool that is three-quarters non-Anthropic.

### Auto is a measurement problem, not just a cost one

Auto picks one of four models per session and does not tell you which. A task
dispatched that way cannot be attributed to a model at all, so when a run goes
badly there is no telling whether the model or the task was at fault. Pick the
model explicitly when that distinction matters.

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
Trial them on one or two mechanical tasks and compare how much rework each
needs before switching. Nothing records that for you — read the pull requests
and their review verdicts.

## The workflow

Seven workflows in `.github/workflows/`, `agent-00` through `agent-06`. The
number no longer maps to file purpose one-to-one — `agent-03-rollup.yml` and
`agent-04-review.yml` swapped which number carries which role after
`agent-05-fix.yml` was added — so treat the filename, not the number, as
authoritative. Four spend model budget (planner, implement, review, fix); two
are plumbing and cost nothing (dashboard, rollup). Each of the four runs
either vendor, chosen by its label's third segment — see *One workflow per
role, two vendors*. `agent-00-dashboard.yml` no
longer runs on every event — it renders on demand now. See *Issue views* and
*The control plane* below.

Two more workflows sit outside the `agent-*` numbering and cost nothing:
`issue-linking.yml` around dispatch bookkeeping, and `issue-dependencies.yml`
around the dependency chain. Neither appears in the diagram because neither is
a stage — they are triggered by the `blocker` label and by pull request and
assignment events, not by a stage completing.

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
        │  → plan comment on the intake Issue
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
│ agent-02-implement.yml        │       │
│ Copilot CLI, spends AI      │       ▼
│ credits: implements,        │  draft PR
│ opens a draft PR, then      │
│ validates, formats, self-   │
│ reviews, self-fixes, and    │
│ marks it ready only if      │
│ its own validation passes   │
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
| `agent:execute` label | You | `agent-02-implement.yml` | Implement this Task via the scripted CLI implementor — no live picker; walks a preference list, opens the PR, then self-reviews and self-fixes against it |
| `agent:review` label | You | `agent-04-review.yml` | Re-review this PR |
| `agent:fix` label | You | `agent-05-fix.yml` | Apply the bounded correction the last `FIX` verdict asked for |
| `planned` label | Planner | — | Intake Issue has been decomposed |
| `review:*` label | Reviewer | — | Last verdict on a PR |
| `blocker` label | Planner, any agent, you | `issue-dependencies.yml` | This Issue blocks at least one other; wire its `## Dependencies` table into GitHub dependencies |
| `dashboard:update` label | You | `agent-00-dashboard.yml` | Re-render the control plane |
| `dashboard` label | `agent-00` | `agent-00-dashboard.yml` | This Issue is the generated control plane |

`blocker` is the one row that is both. It is a state marker — an Issue carries
it for as long as something is waiting on it, and it is never consumed, so
`is:issue is:open label:blocker` is an exact list of what the rest of the work
is queued behind. Adding it is also what fires `issue-dependencies.yml`. That
combination costs the usual retry story: re-adding a label already present is
not an event, so a failed wiring run is retried by dispatching the workflow
(with **sweep** ticked to rebuild everything) rather than by re-labelling. The
trade is worth it — a trigger label that gets consumed would take the queryable
state with it, and the state is the more useful half.

`plan` is the one row that is not a trigger — nothing fires on it. It is a
state marker: every intake template applies it, and the planner consumes it
on success, so an intake Issue carries it from the moment it is filed until
it has actually been decomposed, and never afterwards. `plan` and `planned` are
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
| `human-credentials` | `#D4C5F9` | `agent-01-planner.yml` |
| `blocker` | `#B23F00` | `agent-01-planner.yml` and `sync-issue-dependencies.py` (duplicated, not shared) |
| `review:pass` | `#0E8A16` | `agent-04-review.yml` and `agent-02-implement.yml` (duplicated, not shared) |
| `review:fix` | `#D93F0B` | `agent-04-review.yml` and `agent-02-implement.yml` (duplicated, not shared) |
| `review:planning-failure` | `#B60205` | `agent-04-review.yml` and `agent-02-implement.yml` (duplicated, not shared) |
| `review:design-ambiguity` | `#FBCA04` | `agent-04-review.yml` and `agent-02-implement.yml` (duplicated, not shared) |
| `dashboard` | `#5319E7` | `agent-00-dashboard.yml` |
| `dashboard:update` | `#5319E7` | `agent-00-dashboard.yml` |

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
implementor (`agent-02-implement.yml`) and the fixer (`agent-05-fix.yml`) are
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
gh secret delete PROJECT_TOKEN --repo stardustsuperwizard/mikeys_game_bones-rules-moba
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
- posts the plan as a comment on the intake Issue;
- adds `planned` and consumes both `agent:plan` and `plan`.

Comments are read as amendments to the body, and later comments win over the
original text. The workflow skips its own machine comments so a re-plan does
not read back its previous output as a requirement.

A second run is blocked by the `<!-- automated-planner-complete -->` marker.
To genuinely re-plan, run the workflow manually with `force: true` — and close
the stale sub-issues yourself first, because nothing removes them for you.

If the run **fails**, it removes `agent:plan`, leaves `plan` in place, and
comments with a link to the failed run. That is deliberate: `agent:plan` is
what puts an Issue in the planning view, so leaving it on a failed run would
park the Issue there forever. Giving the label back returns the Issue to
the awaiting-planning view — which is true, because `plan` never came off —
and re-adding `agent:plan` is the same clean retry as always. Check for
partial sub-issues before you do.

`plan` comes off in one place only, the success path, so an Issue can never
fall out of the intake queue without a plan to show for it.

#### Every intake type is plannable

All five intake templates decompose through the same planner. Nothing in
`agent-01-planner.yml` gates on the type label: the only trigger is
`agent:plan`, and the only other gate is the already-planned marker.

| Type label | Template | What its `Acceptance Criteria` ships |
| --- | --- | --- |
| `enhancement` | `01-feature.md` | three generic lines + commented examples |
| `task` | `02-task.md` | heading only — every line commented out |
| `bug` | `03-bug.md` | five generic lines |
| `infrastructure` | `04-infrastructure_tooling.md` | two generic lines |
| `dependency` | `05-dependency.md` | five generic lines |

Every template has the section. What varies is how much of it is boilerplate,
which is why the type matters: the prompt reports it to the planner as
`Type labels:` in the `# INTAKE ISSUE` section, so the planner knows how much
it has to specialise rather than inferring the body's shape from prose.

The planner **specialises** that boilerplate into observations specific to the
Issue, and derives outright whatever the template left empty. Passing a generic
line through is the failure mode — "Expected behavior is restored"
(`03-bug.md:66`) is no more checkable than "the bug is fixed". Where the author
replaced the boilerplate with real criteria, those are authoritative.

The five type labels are ensured in `Ensure Orchestration Labels Exist`
alongside `plan`, and for the same reason: a template silently drops a label
the repository does not define. That guard heals the vocabulary for the *next*
Issue, not the one being planned — an Issue already filed without its type
label cannot be relabelled from inside the run — so `Type labels: (none)`
stays reachable, and the prompt tells the planner to infer the type from the
body's headings rather than stop.

Structural validation rejects a plan whose `acceptance_criteria` list is
empty. Note the limit of that guarantee: validation runs in
`Extract and Validate Planner JSON`, an earlier step than the render, and the
render then drops any criterion identical to the two appended automatically.
A task whose criteria were *all* standing ones therefore passes validation and
renders with only those two lines. That is a contentless contract the reviewer
should call as a planning failure; it is not something the render papers over.

A defect is scoped to the fix and the test that pins it. The refactor it hints
at and the neighbouring defects noticed while reading belong in `out_of_scope`.
A one-task plan is the normal answer for a defect, and the fix and its test are
never split into separate tasks — that leaves an intermediate state nobody can
ship.

### Step 2 — Execution

Work tasks in dependency order. The **Agent Control Plane** Issue lists what
is ready right now, grouped by Feature, with a ⚠️ against any task expected to
touch `.tscn`, `.tres`, `project.godot`, or `addons/`, and a 🔑 against any
task neither automated path can run at all. It renders on demand, so add
`dashboard:update` first if it looks stale — see *The control plane*.

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

**The scripted implementor, `agent-02-implement.yml`.** Add the `agent:execute`
label instead (works from GitHub Mobile) and the workflow does the rest with
no picker involved:

1. Checks the Issue is open, labeled `implementation`, has no open
   `blocked-by` Issue, expects to change no path this workflow's token cannot
   push (see *Paths the agent workflows cannot push*), and has no pull
   request already open for it — any failure gets a comment explaining which,
   and the label removed, not a red run.
2. Runs a Copilot CLI session (`IMPLEMENTOR_MODELS`) against the Issue body plus
   `AGENTS.md` and `.github/copilot-instructions.md`.
3. Requires an actual commit to exist afterward — not just a session that
   talked as if it finished — then immediately opens the pull request
   itself, on branch `agent-exec/<issue#>`, as a **draft**, with `Closes #n`
   already in the body.
4. Re-runs `validate-godot.sh` and applies `gdformat` to any changed
   GDScript, pushing any formatting fix onto that already-open pull
   request.
5. Runs a self-review of the diff (`REVIEWER_MODELS`, the same strong tier
   `agent-04-review.yml` uses) against the already-open pull request. If
   that verdict is `FIX`, runs one bounded self-fix pass (`FIXER_MODELS`)
   and pushes it too.
6. Runs `validate-godot.sh` one last time against whatever commit the
   branch ends up pointing at, writes the exit status into the pull
   request body, and marks it ready for review if — and only if — that run
   passed.
7. In a separate `needs:`-gated job — `Independent Validation (agent push)`,
   not part of the session's job at all — checks out the pushed SHA fresh
   and runs the same validation again, publishing the result as a check run
   on that commit. See *The independent validation gate*.

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

#### Paths the agent workflows cannot push

`GITHUB_TOKEN` cannot create or update files under `.github/workflows/` or
`.github/actions/`. There is no `permissions:` key that grants it: GitHub
reserves workflow edits for credentials carrying the `workflow` OAuth scope,
deliberately, so that a compromised workflow cannot rewrite its own CI. The
push is rejected at the remote:

```
! [remote rejected] HEAD -> agent-exec/168
  (refusing to allow a GitHub App to create or update workflow
   `.github/workflows/godot-ci-validation.yml` without `workflows` permission)
```

That rejection lands at the *last* step of an execution run. Before this
check existed, a task expecting those paths ran a full implementor session on
`claude-opus-5`, produced a complete implementation, and lost all of it at
`Push Branch and Open Pull Request` — diagnosable only by reading the run
log, and priced at a whole session either way. #167's decomposition did it
three times: the planner labelled all four of its tasks `machine`, three of
them (#168, #169, #170) edited workflow files, and the work had to be
hand-authored afterwards as #172, #173 and #174.

So the restriction is now stated in four places, all reading the same rule
out of `.github/scripts/task_scope.py`:

- **The planner** marks such a task when it generates it — `human-credentials`
  alongside `implementation` and `machine`, and a **Run This Task** block
  that says the task is not runnable by the Copilot implementor and what to do
  instead, in place of the usual paste-this-into-a-session instructions.
- **The implementor** refuses it. The `workflow_scope` guard sits with the other
  pre-flight checks in `Resolve Implementation Task Issue`, so a hand-written
  `[impl]` Issue the planner never saw is caught too. Adding `agent:execute`
  gets a comment naming the restriction and the alternative, and the label
  removed — no session, no credits.
- **The fixer** refuses it too, in `Resolve Pull Request`, before
  `Build Fix Request` reads the verdict. Same comment-and-drop-the-label
  shape, same reason.
- **The control plane** prints 🔑 against it, because *Ready to dispatch*
  otherwise tells you to paste it into a Copilot session.

The implementor and the fixer ask the same question from opposite directions,
and the difference matters. The implementor runs before any diff exists, so it
asks about the Issue's *declared expected files* — a statement of intent,
which can be wrong, vague, or absent. The fixer has a pull request in hand,
so it asks about its *actual changed files*, which are exactly what the push
will carry. `evaluate()` answers the first, `evaluate_paths()` the second,
and both test one prefix list.

Detection keys on those file lists, never on a title. For the Issue side,
`task_scope.py` reads the `## Files or Subsystems Expected to Change` section
and takes both backticked paths (how a hand-written Issue writes one) and
bare tokens on bullet lines (how the planner writes one — its `expected_files`
are plain JSON strings rendered straight into a `- ` list, so a generated
task's paths carry no backticks at all). For the pull request side there is
nothing to parse — the API returns literal paths — but there is a ceiling to
respect: the fixer reads them from `gh api --paginate .../pulls/N/files`,
not from `gh pr view --json files`, because the latter is GraphQL and stops
at the first 100 changed files. A restricted path past that boundary would
read as absent and cost exactly the session the guard exists to save. Note
also that the REST key is `filename` where GraphQL's is `path`; the wrong
one yields an empty list rather than an error. The same module supplies the
delicate-paths rule behind the control plane's ⚠️.

The fixer's exposure is the one the implementor guard could not close. Since
the implementor now refuses a workflow-scoped Issue outright, no `agent-exec/*`
branch touching those paths is ever produced by automation — but a pull
request authored by a human-credentialed session carries exactly those edits,
goes through the same reviewer, and can collect a `FIX` verdict like any
other. Its failure was also the worse of the two: the implementor's rejected
push left no branch behind, whereas the fixer commits onto an existing
branch that already carries work, so the correction lived only on the runner
and the pull request was left untouched.

**Uncertain means eligible.** An Issue with no expected-files section, an
empty one, or one naming no recognisable path dispatches exactly as it did
before the guard existed, and so does one whose parse fails outright. A pull
request whose file list cannot be read is treated the same way. A false
positive blocks real work; a false negative costs one session and comments
why.

None of this is a workaround for the scope restriction, and adding a
credential that could write these paths is not on the table — see
`.github/ISSUE_TEMPLATE/04-infrastructure_tooling.md`, which forbids storing
long-lived credentials. **Run these tasks from a human-credentialed session
instead** — Claude Code pushes with your own credentials. See *Claude Code as
an additional environment*. Assigning the Copilot cloud agent does not help:
that path is subject to the same restriction.

#### Why the draft state carries the validation result

Step 6 is the only statement *in the pull request body* about validation
that is not a session talking about itself. The completion report becomes
the body verbatim; the pre-PR review and fix comments are written by
sessions too. None of that is checked against anything, and the prose looks
the same whether a session validated, skipped validation and said so, or
merely claimed a run it never made — all three have happened.

So the body leads with a `## Workflow-verified validation` section that only
`agent-02-implement.yml` writes, and the pull request stays a draft until that
run passes. **A draft implementor PR is one no verified validation stands
behind.** Read the section, not the report.

This is load-bearing on one specific path. An implementor is told not to commit
work it has not validated, and one that follows that rule leaves the tree
dirty; `Commit Leftover Changes` then commits it anyway, so the work is not
thrown away. That is the right trade — but it manufactures the very "a
commit exists" signal the next step says it trusts, so an unvalidated
session's work can and does reach a pull request. Draft-until-verified is
what keeps that from being indistinguishable from finished work.

Draft alone would not have been enough, though. The saved views and the
control plane already read draft as *Implementing* and ready as *Awaiting
review*, which is most of the distinction being drawn for free — but
*Implementing* means "a session is working on it", and a pull request whose
validation failed is not being worked on by anyone. So step 6 also applies a
`validation:failed` label when its run does not pass, and removes it when a
later run does. The control plane tests that label ahead of draft-ness (see
**The control plane**), which is what stops a broken branch from parking
itself under *Implementing* indefinitely.

Two states, then, and they are not the same thing: **draft** means no
verified validation stands behind this pull request *yet*; **draft plus
`validation:failed`** means one ran and did not pass.

#### The independent validation gate

Everything above is still a session's own workflow measuring the tree that
session just edited. The `Record Verified Validation` step is more
trustworthy than the completion report — the workflow writes it, not the
model — but it is a run reporting on its own working directory, which is a
different claim from "this commit validates".

So both workflows that push agent-authored commits end with a separate
`needs:`-gated job, `validate-pushed-commit`, that no session touches:

- `agent-02-implement.yml` → `Independent Validation (agent push)`, check run
  `Godot Validation (agent-02 execute)`
- `agent-05-fix.yml` → `Independent Validation (agent fix)`, check run
  `Godot Validation (agent-05 fix)`

Each takes the pushing job's `pushed-sha` output, checks that SHA out into a
clean runner, and runs `.github/scripts/validate-godot.sh` against it. Both
gate on the pushing job's `pushed` output, so a run that produced no commit
skips the job rather than failing it, and both use `always()` so a commit
left behind by an otherwise-failed run still gets measured.

Neither job re-implements validation. `.github/workflows/godot-validation.yml`
is the single reusable job definition (`on: workflow_call`), and it has three
callers:

| Caller | Ref checked out | `head-sha` |
| --- | --- | --- |
| `godot-ci-validation.yml` | the caller's default (the PR merge ref) | none |
| `agent-02-implement.yml` | the implementor's pushed SHA | that SHA |
| `agent-05-fix.yml` | the fixer's pushed SHA | that SHA |

`godot-ci-validation.yml` still owns the human-authored `pull_request` path,
with its `paths-ignore` deny-list and its `workflow_dispatch` escape hatch,
unchanged. It passes no `head-sha`, because a `pull_request` run already
reports its status against the right commit.

The agent callers must pass one. Their runs are triggered by `issues` events,
so the run's own head SHA is `main` — not the branch the session pushed — and
a job's implicit check run would attach itself there, where nobody looking at
the pull request would ever see it. Passing `head-sha` makes the job POST an
explicit check run against the pushed commit instead, which is what puts the
result on the pull request.

Calling the workflow as a job of the same run is also what makes the gate
fire at all: a `pull_request`-triggered validation of an agent push has
repeatedly landed in `action_required` and never executed, so those commits
went unmeasured. A called job needs no second trigger.

**No repository secret is required.** Publishing a check run is a REST call,
not a workflow trigger, so the automatic `GITHUB_TOKEN` covers it — the
caller jobs grant `contents: read` and `checks: write` and nothing else. No
PAT, no app token, no `secrets:` block.

The gate reports and nothing else. It does not delete the branch, reset it,
change a label, or alter the pull request's state. A red check beside a green
pull request is a decision for a human.

Run it by hand against any Issue number to re-check:

```bash
gh workflow run agent-02-implement.yml -f issue_number=68
```

### Step 3 — Review

`agent-04-review.yml` runs automatically when a `copilot/*` branch's PR is
marked ready for review, or any time you add **`agent:review`**. Only the
native cloud agent's branches match `copilot/*` — the scripted implementor's
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
yourself.

Two refusals come before the verdict is even read, because they are about
what this workflow can *push* rather than what the pull request deserves: a
pull request from a fork, whose head branch this token cannot write, and one
whose diff touches `.github/workflows/` or `.github/actions/`, which it also
cannot write — see *Paths the agent workflows cannot push*. Both comment
and drop `agent:fix` without starting a session. Neither is a red run: a
refusal is not a malfunction.

The equivalent local path is `/fixer <pr-number>` or the
`fixer` Claude Code agent; commenting `@copilot` on the PR still works too,
outside this repository's scripted path. A fix push gets the same
independent check run an implementor push does — see *The independent
validation gate*.

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
it with `gh issue create --parent`, which needs a recent `gh`; the runner
image ships one, but pin it if a run ever fails on an unknown flag.

Sibling *ordering* is not created that way, and used to be. See *The
dependency chain* below: the planner writes each task's `## Dependencies`
table and `.github/scripts/sync-issue-dependencies.py` realizes it, because
`gh issue edit --add-blocked-by` needs `gh` 2.94.0 and failed as an unknown
flag on older images — after the Issues had already been created, with
nothing recording the intent to retry from.

Each implementation sub-issue:

- follows `.github/ISSUE_TEMPLATE/99-execute_task.md`;
- has the same milestone as its parent Feature;
- carries `implementation` and `machine`, plus `human-credentials` when its
  expected files land in `.github/workflows/` or `.github/actions/` (see
  *Paths the agent workflows cannot push*), and nothing else — the planner
  applies no `agent:*` label, because those are dispatch triggers a human
  adds and a pre-applied trigger is a spent one;
- records sibling ordering in its `## Dependencies` table, which becomes a
  GitHub issue dependency;
- is the only Issue assigned to the implementor; and
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
| Blocking something | `is:issue is:open label:blocker` |
| Awaiting review | `is:pr is:open draft:false -label:"review:pass","review:fix","review:planning-failure","review:design-ambiguity"` |
| Needs your attention | `is:pr is:open label:"review:fix","review:planning-failure","review:design-ambiguity","validation:failed"` |
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

What a view cannot express is the **dependency graph** — `blocker` tells you
an Issue blocks *something*, but not what, and no query orders tasks by it.
That is the one question views leave unanswered, and it happens to be the
question you actually ask: *what can I dispatch right now?* It is why the
control plane below still exists.

### The dependency chain

An Issue waiting on another is written in the `## Dependencies` table that
every Issue template carries, and nowhere else:

```markdown
| Relationship | Issue | Why |
| --- | --- | --- |
| Blocked by | #12 | Needs the effect container API |
| Blocks | #34 | #34 consumes the resolver this adds |
```

The Issue doing the blocking gets the `blocker` label.
`issue-dependencies.yml` fires on that label, reads the table, and creates
GitHub's native blocked-by relationship — which is what the control plane
orders by, what `agent:execute` refuses to run past, and what
`issue-linking.yml` warns about when a task is dispatched anyway.

**Why the table exists at all**, when GitHub has a native relationship: the
native one is invisible in a body, in a plan comment, and in every export —
and it was the piece that kept failing to get created. `gh issue create
--blocked-by` and `gh issue edit --add-blocked-by` need GitHub CLI 2.94.0
(2026-06-10) and are unknown-flag errors on anything older, which is one way
that call fails; a permissions or API change is another. The version is not
really the point. The point is that the call ran in the same step that had
already created the plan's Issues, so *any* failure of it left a plan that
existed and a chain that did not — retriable only by re-creating every Issue —
and nothing anywhere recorded what the chain was supposed to be.

So the body is the declaration and the relationship is derived state. Three
consequences, and they are the whole design:

- **It survives a failed write.** The table is on the Issue whether the POST
  worked or not, so the chain can be rebuilt at any time — dispatch
  `issue-dependencies.yml` with **sweep** ticked.
- **It has no `gh` version floor.** `sync-issue-dependencies.py` goes to the
  REST endpoint (`POST /repos/{owner}/{repo}/issues/{n}/dependencies/blocked_by`,
  taking the blocking Issue's *database id*, not its number) rather than a CLI
  flag. Only drift reporting wants the newer `gh`, and it degrades to a note
  rather than a failure.
- **It is add-only.** A dependency GitHub has that no table declares is
  reported, never deleted. Wiring one by hand in the UI is a legitimate thing
  to do; a sweep that silently unwired it would be data loss nobody noticed
  until work started in the wrong order.

Two writers, one implementation. `agent-01-planner.yml` calls the sync script
directly at the end of a plan — it cannot rely on its own `blocker` labels
firing the workflow, because a label applied with `GITHUB_TOKEN` does not
start a run. Everyone else adds the label and lets the workflow do it. Both
paths go through `.github/scripts/issue_dependencies.py`, so a hand-written
table and a generated one are read by exactly the same grammar. That grammar
also accepts the older `- Blocked by: #12` bullet form, so a sweep repairs the
backlog filed before this existed.

#### Reading the chain fails closed

Creating the chain is half of it. Three places *read* it to decide whether
work may start — `agent-02-implement.yml`'s refusal, `issue-linking.yml`'s
warning, and the control plane's *Ready to dispatch* bucket — and all three
inferred "unblocked" from an empty result without checking the result meant
anything. The pattern was:

```
[.blockedBy.nodes[]? | select(.state == "OPEN") | "#\(.number)"]
```

The `?` suppresses jq's iterate-over-null error, so a `blockedBy` arriving
null — a renamed field, a dependencies API hiccup, a `gh` reporting the field
without populating it — yields an empty list byte-identical to "this task has
no blockers". A paid implementor session then runs against a task whose
dependency has not landed, which is the outcome the guard exists to prevent.

Note this is *not* the `gh` version floor: an unknown `--json` field makes
`gh` exit non-zero, and under `set -euo pipefail` that fails the step loudly.
The fail-open is narrower and worse — the field is accepted, and its emptiness
is believed.

The two enforcement points now read
`/repos/{owner}/{repo}/issues/{n}/dependencies/blocked_by` instead: a known
shape (a JSON array of issue objects), no version floor, and a failed read is
fatal rather than empty. **Cannot tell must never resolve to go ahead.** Note
REST spells the state lowercase where the GraphQL-backed `--json` output
spells it upper, so both comparisons downcase first.

The control plane reads 500 issues in one call and cannot afford a request
each, so it reports the uncertainty rather than resolving it: an issue whose
`blockedBy` is not a `nodes` list of `{number, state}` is filed under *Needs
your attention* with `DEPENDENCIES UNREADABLE`, never under *Ready to
dispatch*.

`.github/scripts/test-issue-dependencies.sh` pins all of it — the parser, the
`gh` calls against a stub CLI, and the read side, including a grep that fails
if either enforcement point drifts back to `.blockedBy.nodes[]?`. It needs no
Godot, credentials or network, and it is the check to run when touching any of
this, because the failure mode throughout is a green run that wired or saw
nothing.

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
| `validation:failed` | **Needs your attention** |
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

*Ready to dispatch* also carries two per-task markers, both read out of the
task's expected-files section by `.github/scripts/task_scope.py` rather than
from any label: ⚠️ for a task expected to touch `.tscn`, `.tres`,
`project.godot` or `addons/`, where Auto is a bad bet; and 🔑 for one
expected to touch `.github/workflows/` or `.github/actions/`, which no
automated path can push at all — see *Tasks the scripted implementor cannot
run*. The 🔑 matters here specifically because the bucket's own instruction
is to paste the task into a Copilot session, and for those tasks that
instruction is wrong.

Order matters in the task table: a draft PR reads as *Implementing* even when
a `review:fix` label is still present, because that label persists through the
bounded correction that answers it. Testing draft-ness first is what stops
every in-flight fix from showing as waiting on you.

`validation:failed` is tested *ahead* of draft-ness, and that ordering is the
whole reason the label exists. `agent-02-implement.yml` marks a pull request
ready only after its own `validate-godot.sh` run passes, so draft is no
longer only a transient "a session is mid-flight" state — a branch that fails
validation stays draft until a human intervenes. Left to the draft rule alone
it would file itself under *Implementing* forever, which is precisely the
kind of quietly-hidden failure this dashboard exists to prevent. The label is
what separates *not finished yet* from *finished and broken*.

It is also deliberately independent of the `review:*` vocabulary: those
record a judgment about the code, this records that the build is broken. A
`review:pass` sitting on a branch that no longer validates is exactly the
combination worth surfacing rather than averaging away, so `validation:failed`
wins over all of them.

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

Status used to live on the [Mikey's Game Bones MOBA Rules
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

The sub-issue is authoritative. The implementor is given exactly one Issue and
never sees the planner's session, so **anything an implementor needs must be in
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
counterparts of the four roles, invoked as `/planner`, `/implementor`,
`/reviewer`, and `/fixer`, or their matching subagents (`planner`,
`implementor`, `reviewer`, `fixer`). The command names match the agent names
one-for-one, because the only thing each command does is guard its inputs and
run that agent:

| Role | GitHub-side | Claude Code-side |
| --- | --- | --- |
| Plan | `agent-01-planner.yml` / `.github/agents/01-planner.agent.md` | `.claude/commands/planner.md` / `.claude/agents/planner.md` |
| Execute | `agent-02-implement.yml` / `.github/agents/02-implementor.agent.md` | `.claude/commands/implementor.md` / `.claude/agents/implementor.md` |
| Review | `agent-04-review.yml` / `.github/agents/03-reviewer.agent.md` | `.claude/commands/reviewer.md` / `.claude/agents/reviewer.md` |
| Fix | `agent-05-fix.yml` / `.github/agents/05-fixer.agent.md` | `.claude/commands/fixer.md` / `.claude/agents/fixer.md` |

Each of those eight files opens with a **GitHub access** section, because the
two Claude Code surfaces do not agree on how to reach GitHub. A desktop
terminal has `gh`; a cloud session — Claude Code on the web, and therefore the
Claude mobile app, which is a client for one — does not, and reaches GitHub
through the `mcp__github__*` tools instead. Every GitHub call site in those
files is written out twice, once per surface, and the section opens with a
one-line probe (`command -v gh`) that settles which to use before any call.

Spelling both forms out is the same reasoning that spelled the `gh` commands
out in the first place. `implementor` runs on Haiku; a cheap model given "fetch
the Issue" will spend its budget discovering an API instead of implementing
the task, and a cheap model that cannot find `gh` will try to install it. So
the files say *use this exact call*, and say it for both surfaces, rather than
describing the goal and leaving the route to be worked out. The subagents also
name their `mcp__github__*` tools in `tools:`, which is what actually grants
them — the prose alone would not.

Two operations have no cloud form, and the files say so rather than
improvising one: `--add-blocked-by` (the MCP tools cover parent/child
hierarchy but not dependency edges, so the planner reports the pairs it could
not wire) and the `closingIssuesReferences` GraphQL query (unnecessary, since
this repository requires `Closes #<n>` on every PR body). One differs in
semantics and is flagged where it is used: setting labels through
`issue_write` replaces the whole set, where `gh pr edit --add-label` adds to
it, so the reviewer reads the current labels first.

The asymmetry runs the other way too. Subscribing to a pull request's
activity — the `<wake reason="external-event">` envelopes that carry comments,
CI failures and check-suite rollups back into a live session — is a cloud-side
facility with no `gh` equivalent, so `/execute-task` subscribes on the cloud
surface and polls `gh pr checks --watch` on the desktop one. Same step, two
mechanisms, both written out, and neither pretending to be the other.

### `/execute-task` drives one task to a `PASS`, unattended

The four roles are four contracts, but they are not four things a human wants
to sit and trigger in sequence. `/execute-task` is the fifth command, and the
only one that is not a role: it invokes the other four and keeps going.

It runs `/implementor` on the Issue, subscribes to the pull request that comes
back, waits for CI on the pushed commit, hands the CI outcome to `/reviewer`
along with the diff, and routes on the `review:*` label it applies. `FIX` goes to `/fixer`, whose push re-runs CI and
sends the loop round again; `DESIGN AMBIGUITY` and `PLANNING FAILURE` stop
and go to the human, because neither is a bounded correction.

**Four fix cycles, then it alerts.** After the fourth fix it runs one more
CI-and-review pass so the last fix is actually verified, and then stops
whatever that fifth verdict says, unless it is `PASS`. The alert names the
PR, what is still wrong, whether the same finding has now survived more than
one cycle, and which model tier each cycle ran at. A finding that outlives
four fixes usually means the review and the fix disagree about what the
finding *is*, which is not something a fifth round settles.

Six things about that loop are decisions rather than obvious consequences:

- **It routes on the label and reads the payload from the comment.** The
  `review:*` label is one value from a vocabulary of four, so routing is a
  field lookup rather than a parse of comment prose — which matters most on
  the cheap models this pipeline is meant to run on. But the label cannot
  carry the **Findings** and **Required Before Merge** sections, and those are
  the correction contract the fixer works from, so the comment remains the
  payload. When the two disagree — a session that died between the two calls
  leaves the PR half-labelled — the comment wins: comments are append-only and
  timestamped, where the label is a single mutable value that may still be
  describing the previous cycle.

- **The fixer's model climbs.** The first fix cycle runs at the tier the
  implementor built the code at — a model a tier below the one that wrote the
  code is being asked to understand something it could not have written. Every
  cycle after the first runs at `opus`, because a second cycle on the same PR
  is evidence the first was not enough. This is the local shape of the
  escalation `agent-05-fix.yml`'s *Resolve Fixer Model Tier* step already
  runs, and it keeps that step's floor rule: the fixer never runs below its
  configured model.
- **The implementor's model comes from the Issue.** `/implementor` reads the
  planner's `model:*` label and passes it as the subagent's model, which
  overrides `implementor.md`'s `model: haiku` frontmatter. An Issue with no tier
  label gets `sonnet`, not `haiku` — the planner's own rule is that `sonnet`
  is the answer when the tier is unclear, and an absent label is the most
  unclear a tier gets. Without this the planner's tiering, which is the one
  judgement made with the whole feature in view, was being discarded locally. When a model turns out to be unavailable rather than merely
  cheap, `.claude/settings.json`'s `fallbackModel` chain catches it — see
  *Claude Code gets one fallback chain, not four lists* above for why that
  chain only ever escalates, and why it has to be the committed project file
  rather than either of the other two settings scopes.
- **CI failures do not get their own repair path.** A red check is carried
  into the review as context, not fixed on the spot. The `fixer` finds its
  work by reading an `<!-- agent-review-verdict -->` comment, so a check
  repaired before any verdict exists is a repair nothing recorded — and a
  reviewer not told CI is red will hand back a `PASS` on a PR that cannot
  merge. One repair path, driven by verdicts.
- **It does not add `agent:review`.** That label is the entry to
  `agent-04-review.yml`, and a session that has already run the `reviewer`
  subagent would be commissioning a second full review of the same PR — two
  verdict comments, two `review:*` writes, and no way to know which one the
  fixer will read. `CLAUDE.md` tells a Claude Code session to add the label by
  hand; that instruction is for a session that stops before the review step,
  which this one does not.
- **An empty check list ends the wait, and is not automatically green.** CI
  here is path-filtered — `godot-ci-validation.yml` by `paths-ignore`,
  `gdscript-lint.yml` by `paths` — so a PR touching only prose or the agent
  control plane legitimately runs nothing, and that *is* green. A PR that
  changes `**.gd` and still has no
  checks is the other case: without `AGENT_GITHUB_TOKEN`, pull requests opened
  by `GITHUB_TOKEN` get no `pull_request` runs at all, and no approval step
  can rescue that because there is no parked run to approve. The gates did not
  pass, they never ran, and the file says to report it that way. Either way
  the wait stops: waiting for a check that will never be created is the one
  way that step hangs forever.

The loop ends at a `PASS` on green CI. It does not merge and does not approve
the pull request; that is still the human's, as it is on every other path in
this document.

It also does not release workflow runs parked in `action_required`, and an
earlier draft of this section had it doing so. That step does not belong here,
because the two ways checks fail to start on this repository are both outside
a session's reach and neither is fixed by an approval:

- **A session's own pull requests are never parked.** `/execute-task` runs in
  a Claude Code session — desktop or cloud — which reaches GitHub as
  `stardustsuperwizard`, an account with write access, and pushes a branch of
  this repository rather than a fork. GitHub parks runs for pull requests from
  forks and from first-time contributors; neither describes anything a session
  opens. No run in this repository is in `action_required` today, across 2,608
  of them.
- **The cases that do fail are Actions-authored pushes**, and they fail
  earlier than approval. A pull request authored by `GITHUB_TOKEN` gets no
  `pull_request` run created at all, and *The independent validation gate*
  above records agent pushes whose `pull_request` validation landed in
  `action_required` and never executed — which is why that gate is called as a
  job of the same run instead of relying on a second trigger. Neither has a
  parked run for a session to release.

The identity is what separates the two, and it is not the agent doing the
work. A subagent runs inside its parent session, on the same credentials and
the same GitHub connection, so the implementor subagent opens a pull request as
exactly the same account the session would. What differs is the surface: a
session carries a user token, and a workflow carries `GITHUB_TOKEN` unless
`AGENT_GITHUB_TOKEN` is set.

`/execute-task` has one reader, and that is deliberate. No workflow runs it:
`agent:implementor:{vendor}` drives `agent-02-implement.yml`, which is the
single role, not the orchestrator. A headless run is bounded, the implementor
step alone can consume most of that bound, and a run truncated inside the
third fix cycle is worse than one that stopped at a place it chose. A label is
a single role. The orchestrator is a human in a session.

### `/feature-status` — where does this feature stand?

`/execute-task` drives one task to a verdict, but a feature is many tasks, and
between them someone has to work out what is already done: which tasks exist,
which have pull requests, which came back `FIX`, which are blocked on a task
that has not merged. `/feature-status <intake-issue>` answers that in one
table, with the literal next command in the right-hand column.

```
/feature-status 283

  #  Task                              Tier    PR    CI  Verdict   Next
  1  Appearance data model             opus    #381  ok  PASS      ready to merge
  2  Character creation UI             sonnet  #390  ok  FIX (x1)  /fixer 390
  3  Placeholder appearance rendering  haiku   --    --  --        /execute-task 377
  4  Team-colour signal                sonnet  --    --  --        blocked by #377
```

**It reads and never writes.** No Issues, no pull requests, no labels, no
subagents — it answers where things stand and hands you the command, and you
decide whether to run it.

**It holds no state.** Everything in that table is derived from GitHub each
time it runs: the sub-issues, their `model:*` labels, the pull request titled
`[<n>]`, the most recent `<!-- agent-review-verdict -->` comment, and the count
of `<!-- agent-fix-applied -->` comments — the same counter `agent-05-fix.yml`
uses to decide when to escalate the fixer, so the table also tells you what
model the next fix round will buy.

That is deliberate, and it is the same decision *Where the handoff contract
lives* already made for the planner: there is no plan file. A cached index of
GitHub state drifts the moment anyone closes or relabels an Issue by hand, and
nothing reconciles it. Re-deriving is cheap and is correct by construction.

An earlier draft of this went further and orchestrated the whole pipeline from
one session — plan, then execute every task, then drive each pull request
through review and fix. It was dropped. Once a status command tells you the
next command, typing it yourself costs seconds and keeps every stopping point
visible, and the orchestrator's own bookkeeping was the only thing that needed
a state file in the first place.

The two sides share the Issue and PR graph, not a runtime. A PR opened by
Claude Code doesn't land on a `copilot/*` branch, so it won't trigger
`agent-04-review.yml`'s automatic `ready_for_review` review — add
`agent:review` by hand (works from GitHub Mobile) to put it through the same
reviewer, same as the scripted implementor's own `agent-exec/*` branches
already require.

`issue-linking.yml` cuts the other way, and the asymmetry is worth stating
plainly. It *does* run on `claude/*`, and it requires a closing reference —
so a Claude Code session working an `[impl]` Issue is covered exactly like a
Copilot one, but a session working **without** an Issue (a review or audit,
per `CLAUDE.md`) hits a job whose only success path is a link it was never
supposed to have. Nothing observable distinguishes that from an
implementation session that forgot the keyword, so the PR declares itself
with `<!-- no-originating-issue -->` on the first non-blank line of the body
— first line and matched exactly, so that the marker cannot be picked up out
of boilerplate that merely contains it, the PR template's header comment
included; the check has to fail closed. That suppresses both the failure and
the repair — the latter matters, because the repair's fallback
scan reads every `#NN` in the body and would otherwise link a freeform PR to
an Implementation Task it only mentioned in passing. The marker is inert on
a PR that does close a task, which is reported as a warning rather than
honored. Everything else — labels, the control plane, rollup, the
dashboard — reads the Issue graph the same way regardless of which tool
produced the diff, so switching tools mid-Feature, or per task, doesn't
require picking one system and discarding the other.

### One workflow per role, two vendors

Each role is one workflow, and which company answers is the label's third
segment. `agent:reviewer:copilot` and `agent:reviewer:claude` run the same
`agent-04-review.yml` against the same prompt and publish the same verdict
comment; the only difference is which CLI produced the text in between.

| Label | Target | Workflow | Models |
| --- | --- | --- | --- |
| `agent:planner:{vendor}` | intake Issue | `agent-01-planner.yml` | `vars.{VENDOR}_PLANNER_MODELS` |
| `agent:implementor:{vendor}` | `[impl]` Issue | `agent-02-implement.yml` | per-task tier, resolved to the vendor's ids |
| `agent:reviewer:{vendor}` | pull request | `agent-04-review.yml` | `vars.{VENDOR}_REVIEWER_MODELS` |
| `agent:fixer:{vendor}` | pull request | `agent-05-fix.yml` | per-cycle tier, resolved to the vendor's ids |

This replaces an earlier arrangement in which the Copilot roles and the Claude
roles were separate workflows — `agent-06-claude.yml` held the whole Claude
side — and the two drifted, because nothing forced them to agree. A verdict
published by one had a different envelope from the other's; a tier meant one
thing here and another there. Deleting that file is most of what this
standardisation *is*.

**The vendor swaps in exactly one place.** `run-agent-session` takes a
`vendor` input, runs the matching CLI, and writes one outcome file and one
text file. Everything upstream builds a prompt; everything downstream parses a
verdict and publishes it. Neither end knows who answered.

**A tier is semantic; the spelling is the vendor's.** The planner's
`model:haiku` label means "this task is mechanical", not "use
`claude-haiku-4.5`". Each workflow's `tier_models` helper resolves the tier to
the answering vendor's ids, because the two spellings are not interchangeable:
Copilot CLI writes `claude-haiku-4.5`, Claude Code writes `claude-haiku-4-5`.
A list copied between vendors does not fail loudly — it walks every candidate
and then reports that no model was available, which points the reader at
entitlements rather than at a typo.

**A label is a button, and the button that was pressed is the one released.**
Each workflow consumes its own trigger label rather than a hardcoded one, so
re-adding `agent:fixer:claude` is a clean retry of *that vendor* rather than a
silent fallback to Copilot.

**The Claude path needs `ANTHROPIC_API_KEY`.** A composite action cannot read
`secrets` itself, so every workflow threads it into `run-agent-session`'s
`api-key` input. `--bare` — the mode these runs use, so a run does not vary
with whatever hooks or `CLAUDE.md` sit on the runner — never reads OAuth
credentials, so `CLAUDE_CODE_OAUTH_TOKEN` does not authenticate this path
whatever it is set to. A missing key fails before the model loop with that
sentence, rather than walking every candidate and blaming availability.

**The legacy `agent:plan`, `agent:execute`, `agent:review` and `agent:fix`
labels still work** and mean Copilot, which is what they have always meant.
They are retired separately rather than broken mid-migration.


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
  under: planner ~9k, implementor ~4.6k, reviewer ~1.5k.
- Valid `tools` aliases are `execute`, `read`, `edit`, `search`, `agent`,
  `web`, `todo`, `*`, `[]`, plus `server-name/tool-name` for MCP. Unrecognised
  plain names are ignored, but `01-planner.agent.md` references `github/*`,
  which needs an MCP server named `github` configured for the repository — if
  the planner ever errors at session start, that is the thing to remove.

There is **no "skill" concept** for the cloud agent. The only extension points
are custom agents and MCP servers.

## Supporting files

| File | Purpose |
| --- | --- |
| `.github/workflows/agent-00-dashboard.yml` | Rewrites the pinned control plane Issue from derived state, on `dashboard:update` or dispatch |
| `.github/workflows/agent-01-planner.yml` | Decomposes an intake Issue of any type into `[impl]` sub-issues |
| `.github/workflows/agent-02-implement.yml` | Scripted implementer: implements, opens the PR, then validates, formats, self-reviews, and self-fixes against it, on `agent:execute`; ends with an independent validation job on the pushed SHA |
| `.github/workflows/agent-03-rollup.yml` | Comments on the parent Feature when its last sub-issue closes |
| `.github/workflows/agent-04-review.yml` | Reviews a PR against its task contract, emits a verdict |
| `.github/workflows/agent-05-fix.yml` | Applies a bounded correction against the latest `FIX` verdict, on `agent:fix`; refuses fork PRs and diffs it cannot push before spending a session; ends with an independent validation job on the pushed SHA |
| `.github/workflows/issue-dependencies.yml` | Turns an Issue's `## Dependencies` table into GitHub dependencies, on the `blocker` label or a dispatch; `sweep` rebuilds the whole chain |
| `.github/workflows/godot-validation.yml` | The one reusable validation job (`workflow_call`); called by `godot-ci-validation.yml`, `agent-02-implement.yml`, and `agent-05-fix.yml` |
| `.github/workflows/godot-ci-validation.yml` | Human-authored `pull_request` validation gate (`paths-ignore` deny-list) plus a manual dispatch; calls `godot-validation.yml` |
| `.github/actions/build-review-request` | Shared by `agent-04-review.yml` and `agent-02-implement.yml`'s pre-PR pass: builds the reviewer prompt |
| `.github/actions/build-fix-request` | Shared by `agent-05-fix.yml` and `agent-02-implement.yml`'s pre-PR pass: builds the fixer prompt |
| `.github/actions/run-agent-session` | The one place a vendor difference lives. Runs one agent session -- Copilot CLI or Claude Code, chosen by its `vendor` input -- walking a model preference list and classifying how the session ended into a shared outcome schema. Not yet shared by the planner, which still carries its own copy of the loop |
| `.github/actions/extract-review-verdict` | Turns a review session's text into a machine-readable `VERDICT` |
| `.github/actions/lint-gdscript` | Diff-scoped `gdformat` check/fix, used by `agent-02-implement.yml` and `gdscript-lint.yml` |
| `.github/scripts/render-dashboard.py` | Derives every task and Feature state from the repository graph |
| `.github/scripts/issue_dependencies.py` | The dependency-table grammar, shared by the planner, the sync script and the tests — the one definition of what `Blocked by` and `Blocks` mean |
| `.github/scripts/sync-issue-dependencies.py` | The only writer of GitHub issue dependencies: reads tables, POSTs the relationships, applies `blocker`, reports drift |
| `.github/scripts/test-issue-dependencies.sh` | Pins the parser and the sync's `gh` calls against a stub CLI; no Godot, credentials or network |
| `.github/scripts/task_scope.py` | The one path rule the pushing workflows share: the ⚠️ delicate-paths flag, implementor eligibility from an Issue's expected files (`agent-01-planner.yml`, `agent-02-implement.yml`, the control plane), and pushability from a pull request's changed files (`agent-05-fix.yml`) |
| `.github/agents/01-planner.agent.md` | Planner role, Issue promotion criteria |
| `.github/agents/02-implementor.agent.md` | Implementor role, scope boundaries |
| `.github/agents/03-reviewer.agent.md` | Reviewer role, verdict classification |
| `.github/agents/05-fixer.agent.md` | Fixer role, bounded-correction contract |
| `.github/scripts/validate-godot.sh` | Single source of truth for validation; CI and agents call it |
| `.github/ISSUE_TEMPLATE/99-execute_task.md` | Planner-emitted bounded task |
| `.github/pull_request_template.md` | Handoff record, verdict |
| `CLAUDE.md` | Points Claude Code at the same contract Copilot reads |
| `.claude/agents/*.md`, `.claude/commands/*.md` | Local Claude Code counterparts of the four roles, plus `/feature-status` which reports where a feature stands — see *Claude Code as an additional environment* |

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
| Copilot is assignable here | `gh api graphql -f query='{repository(owner:"stardustsuperwizard",name:"mikeys_game_bones-rules-moba"){suggestedActors(capabilities:[CAN_BE_ASSIGNED],first:20){nodes{login}}}}'` |
| `gh agent-task create` has no `--model` | `gh agent-task create --help` |
| The `plan` queue is not stale | `gh issue list --label plan --json number,title,labels` — nothing here should also carry `planned` |
| This `gh` can read dependencies in bulk | `gh issue list --json number,blockedBy --limit 1` — an "unknown JSON field" error means `gh` is older than 2.94.0, which only costs drift reporting and the control plane's blocked bucket; neither enforcement point depends on it |
| The shape of `blockedBy` | `gh issue list --json number,blockedBy --limit 5 --jq '.[].blockedBy'` — the control plane expects `{"nodes": [{"number", "state"}]}` and flags anything else rather than reading it as unblocked |
| The dependency endpoint answers | `gh api repos/stardustsuperwizard/mikeys_game_bones-rules-moba/issues/1/dependencies/blocked_by` |
| The chain matches the tables | `.github/scripts/sync-issue-dependencies.py --sweep --dry-run` |
| Derived state matches reality | `.github/scripts/render-dashboard.py --json` |