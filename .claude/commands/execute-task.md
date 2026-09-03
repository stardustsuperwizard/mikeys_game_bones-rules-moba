---
description: Implement an Implementation Task Issue end to end — execute, open a PR, put it through agent:review, and drive it to a PASS verdict
argument-hint: <task-issue-number>
---

Implement Implementation Task Issue #$ARGUMENTS in
stardustsuperwizard/mikeys_gamebones-rules-moba, and stay with the pull
request until the reviewer passes it.

This is the whole loop, not just the implementation: execute, open the PR,
label it for review, watch it, correct what comes back, and send it through
review again. Do not hand the user a PR and stop.

## 1. Fetch the contract

First fetch the Issue so you have the real contract, not a guess:

```bash
gh issue view $ARGUMENTS --repo stardustsuperwizard/mikeys_gamebones-rules-moba \
  --json number,title,body,url,parent,state,labels
```

If the Issue doesn't exist, isn't open, doesn't carry the `implementation`
label, or still has an open blocker (check `blockedBy` via
`gh issue view $ARGUMENTS --json blockedBy`), say so and confirm with the
user before proceeding anyway.

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
gh pr view <pr> --repo stardustsuperwizard/mikeys_gamebones-rules-moba \
  --json number,url,body,isDraft,headRefName,labels
```

The body must start with `Closes #$ARGUMENTS`, follow
`.github/pull_request_template.md`, and leave the `VERDICT:` block empty —
that is the reviewer's to fill. If the executor stopped short of a PR, open
it yourself to the same contract. If it is a draft, mark it ready — a draft
left in review produces a verdict against unfinished work. Marking it ready
is itself the review trigger, which is what step 5 turns on.

## 4. File the out-of-scope work you found

**This step overrides the executor guardrail and the PR template's
instruction not to file discovered work.** Those exist to stop an executor
widening its own Issue one "while I was in there" ticket at a time, and the
user has asked for the opposite here: discoveries become tickets. Take the
executor's `Discovered out-of-scope work` list, plus anything you found
yourself driving the PR, and file each item as an intake Issue:

```bash
gh issue create --repo stardustsuperwizard/mikeys_gamebones-rules-moba \
  --title "[plan] <summary>" \
  --label plan,task \
  --body-file <prepared-body-file>
```

Use the intake template matching the work — `.github/ISSUE_TEMPLATE/`:
`01-feature.md` (`plan,enhancement`), `02-task.md` (`plan,task`),
`03-bug.md`, `04-infrastructure_tooling.md`, `05-dependency.md`. File them
as intake (`[plan]` + the `plan` label), not as `[impl]` tasks — the planner
decomposes them, this session does not. Each one says what was found, where,
and why it was out of scope here; it does not smuggle in an implementation.

Then edit the PR's **Discovered Out-of-Scope Work** section to link the
Issues you filed (`#<n>` each), so the PR carries the trail. Nothing you
file goes into this PR's diff.

Judgement still applies: file work that is real and would otherwise be lost,
not every passing thought. If you find nothing, write `None` and say so.

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
gh pr edit <pr> --repo stardustsuperwizard/mikeys_gamebones-rules-moba \
  --add-label agent:review
```

Either way the workflow removes `agent:review` when it runs
(`agent-04-review.yml:222`), which is what makes re-adding it a clean
request for another review — how step 7 asks for one.

## 6. Subscribe for updates

Subscribe to the PR so review verdicts, CI results, and comments wake this
session instead of being polled for. In Claude Code on the web, use the
`subscribe_pr_activity` tool with the repo and PR number. If that tool
isn't available in this session, schedule a check-in instead (`send_later`,
or a `/loop` the user starts) and re-read the PR each time — never
`sleep` in a loop waiting for it.

Stay subscribed until the PR is merged or closed, or the user says stop.

## 7. Correct, then have the reviewer check the changes

On each verdict — read the most recent PR comment containing
`<!-- agent-review-verdict -->`:

- **`VERDICT: PASS`** (`review:pass`) — done. Report and stop; merging is
  the user's call.
- **`VERDICT: FIX`** (`review:fix`) — delegate to the `fixer` subagent with
  the PR number and that comment as context, exactly as `/fix-review` does.
  Push the correction, then **re-add `agent:review`** so the reviewer checks
  the changes. Loop: fix, push, re-label, wait. There is no round limit —
  repeated findings mean fix the root cause, not stop.
- **`VERDICT: DESIGN AMBIGUITY`** (`review:design-ambiguity`) — stop and put
  the ambiguity to the user with `AskUserQuestion`. Do not have `fixer`
  decide it.
- **`VERDICT: PLANNING FAILURE`** (`review:planning-failure`) — stop and
  tell the user this needs to go back through planning, not a bounded fix.

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
