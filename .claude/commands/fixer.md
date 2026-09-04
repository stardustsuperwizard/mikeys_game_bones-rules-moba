---
description: Apply a bounded correction to a PR in response to its review:fix verdict (local counterpart of commenting @copilot for a fix cycle)
argument-hint: <pr-number> [haiku|sonnet|opus]
---

Fix pull request #$ARGUMENTS in stardustsuperwizard/mikeys_game_bones-rules-moba per its
latest automated review.

## Arguments

`$ARGUMENTS` is a pull request number, optionally followed by a model tier.
Split it before the first GitHub call and use the two parts separately:

- **the number** — every `<pr-number>` below.
- **the tier**, if there is one — `haiku`, `sonnet` or `opus`, passed as the
  `model` parameter on the `fixer` subagent call, where it takes precedence
  over `fixer.md`'s `model: haiku` frontmatter. An invoker that names a tier
  has a reason: `/execute-task` passes the tier the implementor built the code
  at, then escalates to `opus` from the second cycle on.

With no tier given — a bare `/fixer 390`, or the headless `claude:fix` path
— the subagent runs at its frontmatter default and you say so in the report.
Do not invent a tier to fill the gap.

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

First fetch the PR and its review comments so you have the real verdict, not
a guess.

```bash
# LOCAL
gh pr view <pr-number> --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json number,title,body,url,headRefName,labels,comments
```

```text
CLOUD — two calls to mcp__github__pull_request_read, same arguments except
`method`:
  method="get"           -> number, title, body, url, head.ref, labels
  method="get_comments"  -> the comments you search for the verdict marker
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  pullNumber=<pr-number>
```

**Route on the `review:*` label; take the payload from the comment.** The
`labels` field above already has the label — it is one value from a
vocabulary of four, so routing is a lookup rather than a parse. The comment
is what the fixer actually works from: the label cannot carry the
**Findings** and **Required Before Merge** sections that are the correction
contract.

Route on the label:

- **`review:fix`** — delegate to the `fixer` subagent with the PR number and
  the latest verdict comment's content as context, at the tier from
  **Arguments** above.
- **`review:design-ambiguity`** — stop and show the user the ambiguity
  described in the comment. Do not delegate to `fixer`; that decision is
  theirs.
- **`review:planning-failure`** — stop and tell the user this needs to go
  back through planning rather than a bounded fix.
- **`review:pass`** — say so; there is nothing to fix.

The payload is the most recent comment containing
`<!-- agent-review-verdict -->`, and its verdict is the first line in that
comment matching `^VERDICT:`. That is not the comment's own first line — the
marker is — and not necessarily the second either, since the envelope carries
a heading between them.

**If the label and that line disagree, the comment wins.** Comments are
append-only and timestamped; the label is a single mutable value that may
still describe the previous cycle. Say which you followed rather than
silently picking one.

- **No `review:*` label but a verdict comment exists** — the reviewer posted
  and failed before labelling. Act on the comment, and mention the missing
  label.
- **A label but no verdict comment** — stop. There is no correction contract
  to work from; run `/reviewer <pr-number>` first.
- **Neither** — ask the user what needs fixing.
