---
description: Implement one Implementation Task Issue and open the PR that closes it (local counterpart of the agent:implementor:copilot label)
argument-hint: <task-issue-number>
---

Implement Implementation Task Issue #$ARGUMENTS in
stardustsuperwizard/mikeys_game_bones-rules-moba.

This command runs the `implementor` subagent once and stops at the open PR. It
does not wait on CI, does not review, and does not fix. `/execute-task` is
the command that drives a task the rest of the way.

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
is not already callable, run `ToolSearch` once with `select:<tool-name>`, then
call it.

Repository is always `owner="stardustsuperwizard"`,
`repo="mikeys_game_bones-rules-moba"`.

First fetch it so you have the real contract, not a guess. The `labels`
field carries the model tier, which you need before delegating:

```bash
# LOCAL
gh issue view $ARGUMENTS --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json number,title,body,url,parent,state,labels
```

```text
CLOUD — call mcp__github__issue_read with: method="get"
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba" issue_number=$ARGUMENTS

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

## Model tier

The Issue carries one of `model:haiku`, `model:sonnet` or `model:opus` — the
planner's call on how much model this task needs, made by the only role that
saw the whole feature before any of it was written. Honour it.

`implementor.md`'s frontmatter says `model: haiku`. That is the floor for a task
nobody tiered, not a pin. Pass the label's tier as the `model` parameter on
the subagent call, which takes precedence over the frontmatter.

| Label on the Issue | `model` to pass |
| --- | --- |
| `model:haiku` | `haiku` |
| `model:sonnet` | `sonnet` |
| `model:opus` | `opus` |
| none of the three | `sonnet` |

An untiered Issue gets `sonnet`, not `haiku` — the planner's own rule is that
`sonnet` is the answer when the tier is unclear, and a missing label is the
most unclear a tier gets. (`agent-02-implement.yml` resolves the same label
in its *Resolve Implementor Model Tier* step, so the CI path reaches this
answer without reading this file. The two agreeing is the point; they are the
same rule written for two surfaces.) Say in your report which tier you used and whether
it came from a label or from that default; the fix cycle in `/execute-task`
reads it back, and "whatever the implementor used" has to mean something
specific.

## Run it

Delegate to the `implementor` subagent, giving it the Issue number, the fetched
body as context, and the `model` from the table above.

It reports a PR URL; the PR number is that URL's last path segment. If it
reports no PR — it stopped on an ambiguity, or validation failed for a
reason inside the task's scope — report that. There is no PR to point at,
and saying so is the whole result.

If the report is unclear about which PR it opened, resolve it from the branch
rather than guessing:

```bash
# LOCAL
gh pr list --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --head <the-branch> --json number,url
```

```text
CLOUD — call mcp__github__list_pull_requests with: owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  head="stardustsuperwizard:<the-branch>"
```

Report the implementor's completion report, the PR URL, and the model tier you
ran it at. Do not add the `agent:reviewer:copilot` label and do not review the
PR
yourself — this command's contract ends at the open PR.
