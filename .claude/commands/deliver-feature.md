---
description: Drive an intake Issue all the way to merge-ready pull requests — plan it, implement each task in dependency order, and put every PR through review and fix
argument-hint: <intake-issue-number>
---

Take intake Issue #$ARGUMENTS in
stardustsuperwizard/mikeys_game_bones-rules-moba from an intake ticket to a
set of pull requests that are ready for a human to merge.

You are an **orchestrator**, not an implementer. You do not read code, write
code, or form opinions about the work. Every judgement in this run belongs to
a subagent that carries its own model; yours is to dispatch them in the right
order, read one line out of each result, and pick a branch. If you find
yourself reasoning about the codebase, you have taken someone else's job.

That is why this command is safe to run on a cheap model. Keep it that way.

## GitHub access

`gh` exists in a desktop terminal and does **not** exist in a cloud session
(Claude Code on the web, the Claude mobile app). Settle which one you are in
once, before any GitHub call:

```bash
command -v gh >/dev/null 2>&1 && echo ENV=LOCAL || echo ENV=CLOUD
```

- `ENV=LOCAL` — use the `LOCAL` form at each call site below.
- `ENV=CLOUD` — use the `CLOUD` form. `gh` is absent by design: do not install
  it, do not curl the REST API, do not go looking for a token.

Repository is always `owner="stardustsuperwizard"`,
`repo="mikeys_game_bones-rules-moba"`.

## Keeping this run alive

A full delivery is one plan, then a subagent call per task, then two or three
more per pull request. That is more traffic than a session holds, and the
failure mode is silent: you forget task 4 exists and report success.

Two rules make it survivable, and they are not optional.

**Write the run state to a file after every step.** Before you start, create
`.claude-deliver-$ARGUMENTS.json` at the repository root with one entry per
task, and update it the moment anything changes. It is the only thing you
trust about run progress — never your memory of what you did.

```json
{
  "intake": 283,
  "gate": "pending | approved",
  "tasks": [
    {
      "issue": 376, "title": "...", "tier": "sonnet",
      "blocked_by": [374],
      "state": "pending | running | pr_open | passed | blocked | failed | skipped",
      "pr": null, "rounds": 0, "note": ""
    }
  ]
}
```

Add it to `.git/info/exclude` rather than committing it — it is run state, not
repository content.

**Demand short results from subagents.** Every delegation below ends by
telling the subagent exactly what to return. Hold them to it. You need an
Issue number, a PR number, and a verdict; you never need a diff, a file
listing, or a narrative. A subagent that returns an essay has cost you the
context you needed for the next task.

If you are ever unsure what has happened, re-read the state file and the
GitHub Issues. Do not reconstruct from memory.

## 1. Fetch the intake Issue

```bash
# LOCAL
gh issue view $ARGUMENTS --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json number,title,body,state,labels,url
```

```text
CLOUD — call mcp__github__issue_read with:
  method="get"
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  issue_number=$ARGUMENTS
```

Stop and tell the user, rather than proceeding, if:

- it is closed;
- its title starts with `[impl]` — that is an Implementation Task, already
  planned. `/execute-task $ARGUMENTS` is the command they want, and this one
  would plan a plan;
- it already has sub-issues, which means it has been planned before. Say so
  and ask whether to re-plan or to skip to step 3 with the existing tasks.

## 2. Plan

Delegate to the `planner` subagent, giving it the Issue number and the fetched
body. It decomposes the intake Issue into Implementation Task sub-issues and
files them; that is its whole contract and you do not second-guess it.

Tell it to end its report with nothing but a list of the Issues it created,
one per line, as `#<number> <tier> <title>` — where `<tier>` is the
`model:haiku` / `model:sonnet` / `model:opus` label it applied, or `-` if it
applied none.

If the planner reports it could not wire dependency relationships — that
happens in a cloud session, where the tools have no equivalent of
`--add-blocked-by` — note it and carry on. Step 3 reads the Issue bodies too.

## 3. Build the execution order

For each task Issue, read its dependencies from **both** sources and take the
union. They disagree more often than you would expect, and missing an edge is
what produces a task implemented against code that does not exist yet.

```bash
# LOCAL — the native relationship
gh issue view <n> --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json number,title,labels,blockedBy
```

```text
CLOUD — call mcp__github__issue_read with method="get" and read the
`## Dependencies` section of the body, which carries `Blocked by: #<n>`.
The native relationship has no MCP equivalent, so the body IS your source
there — this is why the planner writes it down as well as setting it.
```

Sort the tasks so every task comes after everything it is blocked by. If you
find a cycle, stop and report it: a cycle is a planning failure, not something
to break arbitrarily.

Write the ordered list into the state file with `state: "pending"`.

## 4. Show the plan and WAIT

Print a table — order, Issue number, title, tier, blocked by — and the count
of tasks. Then **stop and wait for the user to approve it.**

Do not begin step 5 in the same turn. Do not treat silence, a plan that looks
obviously fine, or your own confidence as approval. A bad plan is the most
expensive thing to discover late, because every task after it is wasted work,
and this is the one moment where a human can see the whole shape for the cost
of reading a table.

Set `gate: "approved"` in the state file only after they say so.

If they ask for changes to the plan, that is a new planning round: take it
back to the `planner` subagent or hand it to them, and return to step 3.

## 5. Implement, one task at a time, in order

**Serially. Never in parallel.** Two executor subagents share one working tree
and one checkout; they would overwrite each other's edits and each other's
branch. The tasks being independent in the dependency graph does not make them
independent on disk.

For each task in order:

1. If any task it is blocked by ended `failed`, `blocked`, or `skipped`, mark
   this one `skipped` with a note naming the dependency, and move on. Do not
   attempt work whose foundation is missing.
2. Set `state: "running"`.
3. Delegate to the `executor` subagent with the Issue number, **overriding its
   model from the task's tier label**:

   | Label | Pass to the Agent tool |
   | --- | --- |
   | `model:haiku` | `model: "haiku"` |
   | `model:sonnet` | `model: "sonnet"` |
   | `model:opus` | `model: "opus"` |
   | none | omit `model` — the subagent's own default applies |

   This is the same recommendation `agent-02-execute.yml` reads from the same
   label. The planner made the call once; both surfaces honour it.

4. Tell the executor to end its report with exactly two lines: `PR: #<number>`
   (or `PR: none`) and `RESULT: <one sentence>`. Record the PR number and set
   `state: "pr_open"`.
5. If it produced no PR, mark the task `failed` with its one-sentence reason
   and continue to the next task. One task failing does not end the run —
   only the tasks that depend on it.

## 6. Drive each pull request to a verdict

Do this for a task's PR as soon as it exists, before starting the next task.
A PR reviewed while its Issue is still fresh is cheaper than a queue of them
reviewed at the end.

Loop, up to **3 fix rounds**:

1. Delegate to the `reviewer` subagent with the PR number. It is read-only
   against code by design — it must not be given the fixer's job. Tell it to
   end its report with one line: `VERDICT: PASS | FIX | DESIGN AMBIGUITY |
   PLANNING FAILURE`.
2. Branch on that line, and only on that line:
   - **`PASS`** — mark the task `passed`, record the PR, stop looping. Do not
     merge it. Merging is the user's decision and this command never makes it.
   - **`FIX`** — delegate to the `fixer` subagent with the PR number and the
     reviewer's findings. Increment `rounds`. Then go back to step 1.
   - **`DESIGN AMBIGUITY`** — mark the task `blocked`. Stop this PR's loop.
     The reviewer is saying the contract does not determine the answer, and
     neither you nor the fixer may decide it. It goes to the user at the end.
   - **`PLANNING FAILURE`** — mark the task `blocked`. Stop this PR's loop.
     The task itself was mis-specified; a bounded fix cannot rescue it.
3. **Escalate the fixer after the first round.** On round 1 call `fixer`
   with no model override. On round 2 and after, pass `model: "opus"`. A
   finding the sonnet fixer has already failed to clear once is not going to
   yield to the same model a second time, and this mirrors what
   `agent-05-fix.yml` does with `FIXER_ESCALATE_AFTER` on the same situation.
4. **After 3 rounds, stop.** Mark the task `failed`, note the last verdict and
   what it asked for, and move on. A pull request that has been through three
   fix rounds at the top tier has a problem no further round will solve, and
   spending a fourth is how a cheap task becomes the most expensive one in the
   milestone.

## 7. Report

When every task is in a terminal state, report once:

1. **The intake Issue** and its URL.
2. **A table**: order, Issue, title, tier, PR, final state, fix rounds spent.
3. **Ready to merge** — every `passed` PR, in dependency order, because that
   is the order they should be merged in.
4. **Needs you** — every `blocked` task, with the verdict and the question the
   reviewer could not answer. These are decisions, not work.
5. **Failed** — every `failed` task, with the last thing that went wrong.
6. **Skipped** — every task skipped, and which dependency skipped it.
7. **What this cost**, roughly: tasks executed, review rounds, fix rounds.

Then delete the state file.

Nothing is merged. Say so plainly at the end, so nobody reads "ready" as
"done".
