---
description: Implement an Implementation Task Issue end to end — execute, subscribe to the PR, wait on CI, review, and fix (local counterpart of dispatching a Copilot agent session on it)
argument-hint: <task-issue-number>
---

Implement Implementation Task Issue #$ARGUMENTS in
stardustsuperwizard/mikeys_game_bones-rules-moba.

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

Otherwise, run the pipeline below.

## The pipeline

`/execute-task` does not stop when the PR is open. An open PR is not a
finished task — it is a task waiting on CI, a review, and whatever the
review asks for. This command drives it the rest of the way:

```text
executor -> subscribe -> CI -> reviewer -> fixer -> back to CI
```

Each step below is the same contract the standalone command runs, invoked
from here instead of by hand. Do not re-derive them; `/review-task` and
`/fix-review` remain the entry points for a PR you did not implement in
this session.

### 1. Implement

Delegate to the `executor` subagent, giving it the Issue number and the
fetched body as context.

It reports a PR URL; the PR number is that URL's last path segment. If it
reports no PR — it stopped on an ambiguity, or validation failed for a
reason inside the task's scope — stop here and report that. There is
nothing to watch, review or fix, and the remaining steps would each fail
in a less obvious way than saying so now.

If the report is unclear about which PR it opened, resolve it from the
branch rather than guessing:

```bash
# LOCAL
gh pr list --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --head <the-branch> --json number,url
```

```text
CLOUD — call mcp__github__list_pull_requests with:
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  head="stardustsuperwizard:<the-branch>"
```

### 2. Subscribe to the PR

Do this before waiting on CI, not after. A subscription registered after a
check suite has already finished does not backfill the event you were
waiting for.

```text
CLOUD — call mcp__github__subscribe_pr_activity with:
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  pullNumber=<pr-number>

Comments, CI failures and check-suite rollups then arrive in the session as
`<wake reason="external-event">` envelopes. The call is idempotent.

Depending on the surface this tool is also exposed as a bare
`subscribe_pr_activity`. Run `ToolSearch` once with
`select:subscribe_pr_activity` if neither name is callable yet, and use
whichever one it returns.
```

```text
LOCAL — no equivalent. A desktop terminal has no event stream to subscribe
to; the subscription is a cloud-session facility, the way `--add-blocked-by`
is a `gh` one. Do not go looking for a substitute. Step 3's `--watch` is the
local form of waiting, and polling is the local form of an event.
```

Stay subscribed until the PR merges or closes, or until the user says stop
— then unsubscribe with the matching `unsubscribe_pr_activity`. Do not
unsubscribe merely because this command's own loop has finished.

### 3. Wait for CI

```bash
# LOCAL
gh pr checks <pr-number> \
  --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --watch --interval 30
```

`--watch` blocks until every check settles. Exit status 0 is green, 8 is
"still pending", anything else is a failure. For a failing check, take the
run ID out of the URL it printed and read the failing job:

```bash
gh run view <run-id> \
  --repo stardustsuperwizard/mikeys_game_bones-rules-moba --log-failed
```

```text
CLOUD — call mcp__github__pull_request_read with:
  method="get_check_runs"
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  pullNumber=<pr-number>

Re-call it while any run is `queued` or `in_progress`. A subscribed session
also gets a wake event on the rollup, so poll on a slow cadence rather than
a tight one.

For a failing check, read the failing job with mcp__github__get_job_logs:
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  run_id=<the run ID from the check run>
  failed_only=true
  return_content=true
```

**Zero check runs is a terminal state, not a pending one.** Waiting for a
check that will never be created is the one way this step hangs forever, so
if nothing is queued and nothing has run, stop waiting. It has two causes
and they do not mean the same thing — work out which one you are in and
report that, rather than reporting "no checks" and leaving the reader to
guess:

- **Path filters.** `godot-ci-validation.yml` ignores `**.md`, `docs/**`
  and `sim/**`; `gdscript-lint.yml` only fires on `**.gd` and its own
  tooling. A PR touching none of the watched paths legitimately runs
  nothing. This is green: say that no checks applied, and to which paths.
- **The PR's author cannot start workflows.** GitHub does not start
  `pull_request` runs for a PR opened by `GITHUB_TOKEN`, which is what a
  `claude:execute` run opens PRs as unless `AGENT_GITHUB_TOKEN` is set —
  see the identity comment in `agent-06-claude.yml`. This is *not* green:
  the gates did not pass, they never ran. Say so explicitly, on the PR, and
  carry it into step 4 as "CI suppressed" rather than as a pass.

The two are told apart by the diff: a PR that changes `**.gd` and has no
check runs at all is the second case, never the first.

The executor already ran `.github/scripts/validate-godot.sh` locally, and
CI runs that same script. CI is not a second opinion; it is that script run
against the commit that was actually pushed. If CI is red where the local
run was green, the difference is the commit or the environment — find out
which and say so, rather than re-running the script locally and reporting
the greener of the two answers.

**Do not fix a red check here, and do not hand it straight to `fixer`.**
Carry the result into step 4. The `fixer` acts on an
`<!-- agent-review-verdict -->` comment, so a red check with no verdict
behind it is outside its contract, and a session that repairs CI on its own
before the review has quietly become a second repair path that no verdict
records. One repair path, driven by verdicts.

### 4. Review

Run the `/review-task` contract: delegate to the `reviewer` subagent with
the PR number, its diff, and **the CI outcome from step 3** — green, red
with the failing job's output, or "no checks applied". A reviewer that is
not told CI is red will review around it and hand back a `PASS` on a PR
that cannot merge.

Because this command runs the reviewer itself, do **not** also add the
`agent:review` label. That label triggers `agent-04-review.yml`, which is a
second full review of the same PR by the Copilot reviewer — two verdict
comments, two `review:*` label writes, and no way to tell which one the
fixer will read. `CLAUDE.md`'s instruction to add the label by hand is for
a session that stops before this step; this one does not.

The reviewer posts the `<!-- agent-review-verdict -->` comment and applies
the matching `review:*` label. Wait for that comment to exist before step 5
— the fixer finds its work by reading it.

### 5. Fix

Route on the verdict's first line, the same way `/fix-review` does:

- **`VERDICT: FIX`** — delegate to the `fixer` subagent with the PR number
  and that comment's content as context.
- **`VERDICT: PLANNING FAILURE`** — stop. Report to the user that this
  needs to go back through planning; a bounded fix cannot reach it.
- **`VERDICT: DESIGN AMBIGUITY`** — stop and show the user the ambiguity.
  That decision is theirs, not this pipeline's.
- **`VERDICT: PASS`** — done. Report, and leave the subscription in place.

### 6. Loop

The fixer commits to the same branch and pushes, which re-runs CI on the
new head. Go back to step 3 with that head — new CI result, new review,
because a verdict written against the previous commit says nothing about
this one.

Stop after two fix cycles and hand it to the user with what is still
failing. A third cycle on the same finding means the review and the fix
disagree about what the finding is, and running it again produces a third
identical round rather than a resolution.

Never open a second PR for the same Issue, and never force-push the
branch: the fixer works on the existing branch, and both would strand the
review history the next verdict is written against.

### 7. While subscribed

A wake event re-enters at step 3: re-read CI on the PR's current head,
then act on whatever the event actually was. Skip events that echo the
reviewer's own verdict comment or a comment this session posted — those are
this pipeline's output arriving back as input, not a request.

Do not narrate progress on the PR. The verdict comment and the diff are the
record; a running commentary is noise in a thread the human reads to find
the verdict.

This command never merges the PR and never approves it. It takes the PR as
far as a `PASS` verdict on green CI, and that is where the human comes in.

### When nobody is watching

`agent-06-claude.yml` feeds this same file to a headless session for the
`claude:execute` label. That session has no user to hand anything back to,
and it is bounded by `--max-turns 60` — a budget the executor step alone can
consume most of. Spending what is left on a fix cycle produces a run
truncated somewhere in the middle of step 6, which is worse than one that
stopped somewhere it chose.

So when you are running unattended: do steps 1 through 4 and stop at the
verdict. Do not run step 5's fixer and do not loop. Post the verdict, and
say on the PR that the fix cycle was not run and how to start it — the
`agent:fix` label, or `/fix-review <pr-number>` from an interactive session.
Subscribing is unavailable there for the same reason it is unavailable in
any local session, so step 2 is a no-op rather than something to work
around.

Bound the CI wait as well. If checks have not settled after roughly fifteen
minutes, stop waiting and review with what you have, described as "CI still
running" — an unattended session blocked on a queue is a session that will
be killed by the job timeout with nothing published.
