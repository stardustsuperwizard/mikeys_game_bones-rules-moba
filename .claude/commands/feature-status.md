---
description: Show every implementation task under an intake Issue — its tier, its pull request, its latest verdict, and the exact command to run next
argument-hint: <intake-issue-number>
---

Report the state of every Implementation Task under intake Issue #$ARGUMENTS
in stardustsuperwizard/mikeys_game_bones-rules-moba, and say what to do next
about each one.

**This command reads. It never writes.** It files no Issues, opens no pull
requests, pushes nothing, adds no labels, and delegates to no subagent. It
answers "where is this feature and what is my next move", and the answer is a
table plus a list of commands for the user to run. If you find yourself about
to change something, you have misread this command.

Everything it reports is derived from GitHub on the spot. There is no cache
and no state file: the Issues, their labels, the pull requests, and the
reviewer's verdict comments already are the state, and re-deriving is both
cheap and correct after someone edits an Issue by hand. Do not create a file
to remember any of this.

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

## 1. The intake Issue

```bash
# LOCAL
gh issue view $ARGUMENTS --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json number,title,state,url,labels
```

```text
CLOUD — call mcp__github__issue_read with:
  method="get"
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  issue_number=$ARGUMENTS
```

If its title starts with `[impl]`, this is an Implementation Task, not an
intake Issue. Say so and report just that one task — steps 3 and 4 still
apply to it.

## 2. Its implementation tasks

```text
CLOUD — call mcp__github__issue_read with:
  method="get_sub_issues"
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  issue_number=$ARGUMENTS
```

```bash
# LOCAL — no --json field exposes sub-issues, so use the title convention the
# planner guarantees: it titles every child "[impl] [<parent>] <title>".
gh issue list --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --search "[impl] [$ARGUMENTS] in:title" \
  --state all --limit 50 \
  --json number,title,state,labels,body
```

Cross-check against the planner's plan comment on the intake Issue, which
lists every task it filed with its Issue number. If the two disagree, report
both — a task in the comment but not in the list was closed or deleted, and a
task in the list but not the comment was added by hand.

If there are none, the Issue has not been planned. Say so and stop: the next
command is `/planner $ARGUMENTS`.

## 3. Per task

From what you already fetched:

- **Tier** — the `model:haiku` / `model:sonnet` / `model:opus` label, or `—`.
- **Blocked by** — the `## Dependencies` section of the body (`Blocked by:
  #<n>`), plus the native relationship where you can read it (`gh issue view
  <n> --json blockedBy`, LOCAL only). Take the union; they disagree more often
  than you would expect.
- **State** — open or closed.

Then find its pull request. Every implementation PR in this repository is
titled starting `[<issue-number>]` and carries `Closes #<issue-number>` in its
body, so either identifies it:

```bash
# LOCAL
gh pr list --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --search "[<n>] in:title" --state all \
  --json number,title,state,isDraft,url,labels,mergeable
```

```text
CLOUD — call mcp__github__list_pull_requests with state="all", then match on a
title starting "[<n>]". mcp__github__pull_request_read with method="get"
gives draft state and mergeability for one you have found.
```

## 4. Per pull request

Read its comments once and take three things from them:

```bash
# LOCAL
gh pr view <pr> --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json comments,statusCheckRollup
```

```text
CLOUD — mcp__github__pull_request_read with method="get_comments", and
method="get_check_runs" for CI.
```

- **Verdict** — the `VERDICT:` line of the **most recent** comment containing
  `<!-- agent-review-verdict -->`. The `review:*` label is a cross-check, not
  the source: a label left over from an earlier round is not a verdict.
- **Fix rounds spent** — how many comments contain `<!-- agent-fix-applied -->`.
  This is the same counter `agent-05-fix.yml` uses to decide when to escalate
  the fixer, so it is also telling you what model the next fix round will buy.
- **CI** — whether checks are green, red, or absent.

## 5. Report

One table, in dependency order — a task after everything it is blocked by:

| # | Task | Tier | PR | CI | Verdict | Rounds | Next |
| - | ---- | ---- | -- | -- | ------- | ------ | ---- |

Fill the **Next** column with the literal command to run, or the reason there
isn't one. Work down this list and take the first that matches:

| Situation | Next |
| --- | --- |
| Issue closed and PR merged | `done` |
| Blocked by a task that is not yet merged | `blocked by #<n>` |
| No PR yet | `/execute-task <n>` |
| PR is a draft | `mark ready` — a draft in review gets a verdict against unfinished work |
| CI red | `fix CI` — red CI is work now, whatever the review says |
| PR open, no verdict comment | `/reviewer <pr>` |
| Latest verdict `FIX` | `/fixer <pr>` |
| Latest verdict `PASS` | `ready to merge` |
| Latest verdict `DESIGN AMBIGUITY` | `needs your decision` |
| Latest verdict `PLANNING FAILURE` | `re-plan — /planner $ARGUMENTS` |

Then, below the table:

1. **Do this next** — the single highest-value command, which is the `Next` of
   the first unblocked task that has one. One line, so the answer to "what
   now" is readable on a phone.
2. **Ready to merge** — every `PASS` pull request, in dependency order,
   because that is the order to merge them in.
3. **Needs you** — every task whose next step is a decision rather than a
   command, with the question the reviewer could not answer.
4. **Watch** — any task at three or more fix rounds. Past that the fixer is
   already at the top tier and further rounds buy nothing; the finding is
   probably not a model problem.

Report nothing else. No summary of the feature, no assessment of the code, no
recommendation about the design. Someone asked where things stand.
