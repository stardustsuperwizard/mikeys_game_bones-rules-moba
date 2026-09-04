---
description: Implement an Implementation Task Issue end to end — execute, open a PR, put it through review, and drive it to a PASS verdict
argument-hint: <task-issue-number>
---

Implement Implementation Task Issue #$ARGUMENTS in
stardustsuperwizard/mikeys_game_bones-rules-moba, and stay with the pull
request until the reviewer passes it.

This is the whole loop, not just the implementation: execute, open the PR,
send it to review, watch it, correct what comes back, and send it through
review again. Do not hand over a PR and stop.

One structural exception. When this file runs as the prompt for the
`claude:execute` label (`agent-06-claude.yml` routes the label to this
path), the session ends when the run ends. Steps 1-5 apply as written; step
6 has no session to wake, and step 7's loop belongs to whoever adds
`claude:review` or `agent:review` next. Say where you stopped.

## GitHub access

`gh` exists in a desktop terminal and does **not** exist in a cloud session
(Claude Code on the web, the Claude mobile app). Settle which one you are in
once, with one command, before any GitHub call:

```bash
command -v gh >/dev/null 2>&1 && echo ENV=LOCAL || echo ENV=CLOUD
```

- `ENV=LOCAL` — use the `LOCAL` form at each call site below.
- `ENV=CLOUD` — use the `CLOUD` form. `gh` is absent by design: do not
  install it, do not curl the REST API, do not go looking for a token, and
  do not treat its absence as an error worth reporting.

Every call site below gives you both forms, written out in full. Use them
verbatim. Never translate one form into the other yourself, and never guess
a tool name. The `CLOUD` tools may need their schema loaded first — if one
is not already callable, run `ToolSearch` once with `select:<tool-name>`,
then call it.

Repository is always `owner="stardustsuperwizard"`,
`repo="mikeys_game_bones-rules-moba"`.

## 1. Fetch the contract

First fetch it so you have the real contract, not a guess.

```bash
# LOCAL
gh issue view $ARGUMENTS --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json number,title,body,url,parent,state,labels
```

```text
CLOUD — call mcp__github__issue_read with:
  method="get"
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  issue_number=$ARGUMENTS

Returns title, body, url, state, labels and the parent link in one call.
```

If the Issue doesn't exist, isn't open, or doesn't carry the
`implementation` label, say so and confirm with the user before proceeding
anyway.

For open blockers:

```bash
# LOCAL only
gh issue view $ARGUMENTS --repo stardustsuperwizard/mikeys_game_bones-rules-moba --json blockedBy
```

```text
CLOUD — no equivalent. The MCP tools expose parent/child hierarchy but not
blocked-by edges. Read the Issue's own Dependencies section instead, and if
it names a blocker, check that Issue's state with a second
mcp__github__issue_read (method="get"). Say which check you were able to
make rather than implying the blocker list was verified.
```

## 2. Implement

Delegate implementation to the `executor` subagent, giving it the Issue
number and the fetched body as context.

The executor's scope guardrails stand — it implements the smallest change
that satisfies the acceptance criteria, and it does **not** file Issues for
what it finds. It reports discoveries under `Discovered out-of-scope work`
in its completion report. Filing them is step 4, and it is yours, not its.

## 3. Open the pull request

The executor opens the PR as part of its own contract. Confirm it actually
did, and that the body is right, before moving on:

```bash
# LOCAL
gh pr view <pr> --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json number,url,body,isDraft,headRefName,labels
```

```text
CLOUD — call mcp__github__pull_request_read with:
  method="get"
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  pullNumber=<pr>
```

The body must start with `Closes #$ARGUMENTS`, follow
`.github/pull_request_template.md`, and leave the `VERDICT:` block empty —
that is the reviewer's to fill.

If the executor stopped short of a PR, open it yourself to the same
contract:

```bash
# LOCAL
gh pr create --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --title "<summary>" --body-file <prepared-body-file>
```

```text
CLOUD — call mcp__github__create_pull_request with:
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  title="<summary>"
  head="<branch>"
  base="main"
  body="<the prepared body>"
```

If it is a draft, mark it ready — a draft left in review produces a verdict
against unfinished work. Marking it ready is itself a review trigger, which
is what step 5 turns on.

## 4. File the out-of-scope work you found

**This step overrides the executor guardrail and the PR template's
instruction not to file discovered work.** Those exist to stop an executor
widening its own Issue one "while I was in there" ticket at a time, and the
user has asked for the opposite here: discoveries become tickets. Take the
executor's `Discovered out-of-scope work` list, plus anything you found
yourself driving the PR, and file each item as an intake Issue:

```bash
# LOCAL
gh issue create --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --title "[plan] <summary>" --label plan,task \
  --body-file <prepared-body-file>
```

```text
CLOUD — call mcp__github__issue_write with:
  method="create"
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  title="[plan] <summary>"
  labels=["plan", "task"]
  body="<the prepared body>"
```

Use the intake template matching the work — `.github/ISSUE_TEMPLATE/`:
`01-feature.md` (`plan,enhancement`), `02-task.md` (`plan,task`),
`03-bug.md`, `04-infrastructure_tooling.md`, `05-dependency.md`. File them
as intake (`[plan]` + the `plan` label), not as `[impl]` tasks — the planner
decomposes them, this session does not. Each one says what was found, where,
and why it was out of scope here; it does not smuggle in an implementation.

Then edit the PR's **Discovered Out-of-Scope Work** section to link the
Issues you filed (`#<n>` each), so the PR carries the trail:

```bash
# LOCAL
gh pr edit <pr> --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --body-file <updated-body-file>
```

```text
CLOUD — call mcp__github__update_pull_request with:
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  pullNumber=<pr>
  body="<the full updated body>"

This replaces the body outright, so send the whole thing, not just the
changed section.
```

Nothing you file goes into this PR's diff. Judgement still applies: file
work that is real and would otherwise be lost, not every passing thought. If
you find nothing, write `None` and say so.

## 5. Send it to review

`agent-04-review.yml` auto-fires on `ready_for_review` for `copilot/*` and
`claude/*` branches alike — see its `if:` at `agent-04-review.yml:68-70`.
So whether you need to do anything here depends on how the PR reached
"ready":

- **Step 3 marked a draft ready.** The review is already running. Do not
  add the label on top of it. `ready_for_review` and `labeled` are separate
  triggers sharing one `concurrency: cancel-in-progress` group, so a second
  run cancels the first and spends another strong-model session reaching
  the same verdict.
- **The PR was opened ready** — the usual case, since the executor's
  `gh pr create` carries no `--draft`. GitHub emits `ready_for_review` only
  on a draft→ready transition, never on `opened`, so nothing has fired yet
  and the label is what starts the first review:

```bash
# LOCAL
gh pr edit <pr> --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --add-label agent:review
```

```text
CLOUD — call mcp__github__issue_write with:
  method="update"
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  issue_number=<pr>          # a PR is an Issue to this endpoint
  labels=[<every label it already has>, "agent:review"]

This REPLACES the label set rather than adding to it, so read the PR's
current labels in step 3 and pass them back alongside agent:review. The
LOCAL form adds without replacing; the CLOUD form does not.
```

Either way the workflow removes `agent:review` when it runs
(`agent-04-review.yml:222`), which is what makes re-adding it a clean
request for another review — how step 7 asks for one.

`claude:review` is the Claude-side reviewer for the same PR
(`agent-06-claude.yml` routes it to `/review-task`). Use `agent:review`
unless the user asks otherwise; it is the gate the rest of the pipeline
labels against.

## 6. Subscribe for updates

Subscribe to the PR so review verdicts, CI results, and comments wake this
session instead of being polled for.

```text
CLOUD — call mcp__github__subscribe_pr_activity with:
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  pullNumber=<pr>
```

```text
LOCAL — no webhook to subscribe to. Schedule a check-in instead (send_later
if this session has it, or a /loop the user starts) and re-read the PR each
time.
```

Never `sleep` in a loop waiting for an event, in either environment. Stay
subscribed until the PR is merged or closed, or the user says stop.

## 7. Correct, then have the reviewer check the changes

On each verdict, read the most recent PR comment containing
`<!-- agent-review-verdict -->`:

```bash
# LOCAL
gh pr view <pr> --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json comments
```

```text
CLOUD — call mcp__github__pull_request_read with:
  method="get_comments"
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  pullNumber=<pr>
```

- **`VERDICT: PASS`** (`review:pass`) — done. Report and stop; merging is
  the user's call.
- **`VERDICT: FIX`** (`review:fix`) — delegate to the `fixer` subagent with
  the PR number and that comment as context, exactly as `/fix-review` does.
  Push the correction, then **re-add `agent:review`** (step 5's call site)
  so the reviewer checks the changes. Loop: fix, push, re-label, wait. There
  is no round limit — repeated findings mean fix the root cause, not stop.
- **`VERDICT: DESIGN AMBIGUITY`** (`review:design-ambiguity`) — stop and put
  the ambiguity to the user with `AskUserQuestion`. Do not have `fixer`
  decide it.
- **`VERDICT: PLANNING FAILURE`** (`review:planning-failure`) — stop and
  tell the user this needs to go back through planning, not a bounded fix.

Verify a finding against the file it names before acting on it, and say so
if it does not hold. A reviewer reading a diff can be wrong about the
repository around it.

Red CI or a merge conflict is work now, whatever the review state: run
`.github/scripts/validate-godot.sh` locally, reproduce the failure, fix it,
and push a validated change. Never skip, disable, or weaken a test to get
green. A `review:fix` label left over from an earlier round is not a
verdict — read the comment, not the label.

## 8. Report

When the PR reaches `PASS`, or when you stop on a blocker, report:

1. The PR URL and its current verdict.
2. **Files changed** — each file and why.
3. **Acceptance criteria** — each one, and whether it is satisfied.
4. **Validation** — the exact command run and its result.
5. **Issues filed** — each out-of-scope ticket, with its number, or `None`.
6. **Review rounds** — what each verdict asked for and what you changed.
7. **Unresolved** — anything still blocking, or `None`.
