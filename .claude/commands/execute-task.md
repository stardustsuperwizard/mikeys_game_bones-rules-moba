---
description: Drive one Implementation Task Issue to a green PASS unattended — execute, subscribe, wait on CI, then loop reviewer and fixer up to four times before alerting you
argument-hint: <task-issue-number>
---

Take Implementation Task Issue #$ARGUMENTS in
stardustsuperwizard/mikeys_game_bones-rules-moba all the way from an
unimplemented Issue to a `PASS` verdict on green CI, without stopping to ask
along the way.

**This command is the unattended one.** The four role commands —
`/planner`, `/implementor`, `/reviewer`, `/fixer` — each run one agent once and
hand back to you. This one runs them in sequence and keeps going. It is the
only command here that decides on your behalf what to do with a verdict, and
the only one that escalates a model tier without asking.

It still never merges and never approves the pull request. It takes the PR as
far as a `PASS` on green CI; merging is yours.

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

## The pipeline

```text
/implementor -> subscribe -> CI -> /reviewer -> /fixer -> back to CI
                                ^                         |
                                +----- up to 4 cycles -----+
```

Each numbered step below invokes a role command rather than restating its
contract. Invoke them through the `Skill` tool by name — `implementor`,
`reviewer`, `fixer` — so there is one contract per role and this file cannot
drift from it. Where a step needs something the role command does not take as
an argument (a model tier, the CI outcome), pass it as context on the call.

### 1. Execute

Invoke the `implementor` command with the Issue number.

It runs the Issue guards, reads the `model:*` label, delegates to the
`implementor` subagent at that tier, and reports a PR URL. Note the tier it
reports — step 5 needs it.

If you have lost it (a long wait, a summarised context, a wake event hours
later), do not guess and do not ask: re-read the Issue's `model:*` label,
which is where `/implementor` got it and which is still there. An Issue with no
tier label resolves to `sonnet`, by the same rule `/implementor` applies. This
pipeline holds nothing in its head that GitHub cannot tell it again.

If it reports no PR — an ambiguity, or in-scope validation that failed —
stop here and report that. There is nothing to watch, review or fix, and
every remaining step would fail in a less obvious way than saying so now.

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

`--watch` blocks until every check settles, which is longer than one Bash
call gets. Give it an explicit timeout below the tool's ceiling and call it
again while it reports pending, rather than issuing one call and assuming it
covers the whole run — a `--watch` killed by the tool timeout looks identical
to a failure, and treating it as one sends a green PR into the fix loop.

Exit status 0 is green, 8 is "still pending", anything else is a failure. A
timed-out call is none of those: it is another 8. Re-issue it. For a failing check, take the
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
if nothing is queued and nothing
has run, stop waiting. It has two causes and they do not mean the same thing
— work out which one you are in and report that, rather than reporting "no
checks" and leaving the reader to guess:

- **Path filters.** `godot-ci-validation.yml` ignores prose, `sim/**`, and
  the whole agent control plane — `.github/agents/**`, `.claude/**`,
  `.gitignore`, the `agent-*` and `balance-*` workflows; `gdscript-lint.yml`
  only fires on `**.gd`, `.gdlintrc` and its own tooling. A PR touching none
  of the watched paths legitimately runs nothing. This is green: say that no
  checks applied, and to which paths. Read the workflow's own list rather
  than trusting this summary — it is a summary, and the list is the
  authority.
- **The PR's author cannot start workflows.** GitHub does not start
  `pull_request` runs for a PR opened by `GITHUB_TOKEN`, which is what an
  Actions run opens PRs as unless `AGENT_GITHUB_TOKEN` is set —
  see the identity comment in `agent-02-implement.yml`. This is *not* green:
  the gates did not pass, they never ran, and nothing can start them after
  the fact. Say so explicitly, on the PR, and carry it into step 4 as "CI
  suppressed" rather than as a pass.

The two are told apart by the diff: a PR that changes `**.gd` and has no
check runs at all is the second case, never the first.

The implementor already ran `.github/scripts/validate-godot.sh` locally, and
CI runs that same script. CI is not a second opinion; it is that script run
against the commit that was actually pushed. If CI is red where the local
run was green, the difference is the commit or the environment — find out
which and say so, rather than re-running the script locally and reporting
the greener of the two answers.

**Do not fix a red check here, and do not hand it straight to `/fixer`.**
Carry the result into step 4. The `fixer` acts on an
`<!-- agent-review-verdict -->` comment, so a red check with no verdict
behind it is outside its contract, and a session that repairs CI on its own
before the review has quietly become a second repair path that no verdict
records. One repair path, driven by verdicts.

### 4. Review

Invoke the `reviewer` command with the PR number, and pass **the CI outcome
from step 3** as context — green, red with the failing job's output, "no
checks applied", or "CI suppressed". A reviewer that is not told CI is red
will review around it and hand back a `PASS` on a PR that cannot merge.

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

**Route on the label. Take the payload from the comment.** The reviewer
writes both, and they are for different jobs:

- The `review:*` label is the routing signal. It is one structured value in a
  fixed vocabulary of four, and reading it is a field lookup, not a parse.
- The `<!-- agent-review-verdict -->` comment is the payload. It holds the
  **Findings** and **Required Before Merge** sections, which are the actual
  correction contract, and the label cannot carry them.

Read the label:

```bash
# LOCAL
gh pr view <pr-number> --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json labels --jq '[.labels[].name | select(startswith("review:"))]'
```

```text
CLOUD — call mcp__github__issue_read with method="get_labels",
owner="stardustsuperwizard", repo="mikeys_game_bones-rules-moba",
issue_number=<pr-number>.
```

Then route:

- **`review:pass`** — done. Go to step 7.
- **`review:fix`** — invoke the `fixer` command with the PR number, the model
  tier from the schedule below, and the latest verdict comment's content as
  context. Then go to step 6.
- **`review:planning-failure`** — stop. Alert the user that this needs to go
  back through planning; a bounded fix cannot reach it, and looping will not
  change that.
- **`review:design-ambiguity`** — stop and alert the user with the ambiguity.
  That decision is theirs, not this pipeline's.

#### When the label and the comment disagree

They are written by two calls, so a session that died between them leaves the
PR half-labelled. Check the latest comment's `^VERDICT:` line against the
label before acting on either.

**The comment wins.** Comments are append-only and timestamped; the label is
a single mutable value that may still be describing the previous cycle. A
`review:fix` label over a comment saying `VERDICT: PASS` is a stale label, not
a new finding.

- **No `review:*` label but a verdict comment exists** — the reviewer posted
  and failed before labelling. Act on the comment, and say the label is
  missing so somebody can fix the dashboards.
- **A label but no verdict comment at all** — do not fix. There is no
  correction contract to work from, and the `fixer` will refuse it anyway.
  Re-run step 4.
- **Both present, disagreeing** — act on the comment, and say so explicitly
  in your report rather than silently picking one.

#### Which model the fixer runs at

`fixer.md`'s frontmatter says `model: haiku`. Both of the rules below beat
it, and you pass the result as the `model` parameter on the subagent call.

| Fix cycle | Model |
| --- | --- |
| 1st | the tier the implementor ran at, recorded in step 1 |
| 2nd, 3rd, 4th | `opus` |

The first cycle matches the implementor because the fix is a correction to that
implementor's own work, in a codebase it just built. A model a tier below the
one that wrote the code is being asked to understand something it could not
have written.

Every later cycle is `opus`, because a second cycle on the same PR is
evidence the first one was not enough. Escalate on the second call even when
the implementor ran at `haiku` or `sonnet` — that is the case the rule exists
for. If the implementor already ran at `opus`, there is nothing to escalate to
and every cycle stays there.

This is the local shape of the escalation `agent-05-fix.yml`'s *Resolve Fixer
Model Tier* step runs, and it obeys the same floor rule: the fixer never runs
below its configured model. Locally that floor is `fixer.md`'s `haiku`, so the
implementor's tier always clears it. If you ever raise that frontmatter, the
floor wins over the table above for the first cycle.

State the model you used at the top of each cycle's report. A pipeline that
silently changes tier is one nobody can read the cost of afterwards.

### 6. Loop

The fixer commits to the same branch and pushes, which re-runs CI on the new
head. Go back to **step 3** with that head — new CI result, new review. A
verdict written against the previous commit says nothing about this one.

**Four fix cycles, then stop.** The fixer may run at most four times on one
PR. After the fourth fix, run steps 3 and 4 once more so the last fix is
actually verified — then stop regardless of what that fifth verdict says,
unless it is `PASS`.

Do not keep that count in your head. Count it off the PR, immediately before
each fix, so the limit holds across a summarised context, a wake event, or a
resumed session:

```bash
# LOCAL
gh pr view <pr-number> --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json comments \
  --jq '[.comments[] | select(.body | contains("<!-- agent-review-verdict -->"))] | length'
```

```text
CLOUD — call mcp__github__pull_request_read with method="get_comments" and
count the comments whose body contains `<!-- agent-review-verdict -->`.
```

**That number is the fix cycle you are about to start.** One verdict comment
means you are starting fix 1; four means fix 4; **five or more means stop and
alert.** The fifth verification review writes the fifth comment, which is
exactly what trips the limit — the count and the rule are the same fact, so
they cannot drift apart the way a remembered tally can.

Verdicts posted by CI count too. If someone ran `agent:review` on this PR
before you started, those were real review rounds and the budget is genuinely
smaller. Say so in the alert rather than silently starting from zero.

When you stop at the limit, alert the user. Do not start a fifth fix, and do
not quietly report the fourth cycle as if it were the end of the road. The
alert says:

1. that the pipeline hit its four-cycle limit on PR #`<n>`, so this needs a
   human;
2. what the fifth verdict says is still wrong;
3. whether the same finding has come back more than once — a finding that
   survives four fixes usually means the review and the fix disagree about
   what the finding *is*, and a fifth cycle produces a fifth identical round
   rather than a resolution;
4. the model tier each cycle ran at;
5. the PR URL.

Never open a second PR for the same Issue, and never force-push the branch:
the fixer works on the existing branch, and both would strand the review
history the next verdict is written against.

### 7. Report

On `PASS` with green CI, report: the Issue, the PR URL, how many fix cycles
it took, the model tier of each, and the final verdict. Leave the
subscription in place.

Do not narrate progress on the PR as you go. The verdict comment and the
diff are the record; a running commentary is noise in a thread the human
reads to find the verdict.

### While subscribed

A wake event re-enters at step 3: re-read CI on the PR's current head, then
act on whatever the event actually was. Skip events that echo the reviewer's
own verdict comment or a comment this session posted — those are this
pipeline's output arriving back as input, not a request.

A wake event does not reset the four-cycle counter, and neither does a
summarised context or a resumed session. The count is a property of the pull
request, read off its verdict comments in step 6 — not a tally this session
is keeping.
