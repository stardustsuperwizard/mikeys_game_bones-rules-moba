---
description: Apply a bounded correction to a PR in response to its review:fix verdict (local counterpart of commenting @copilot for a fix cycle)
argument-hint: <pr-number>
---

Fix pull request #$ARGUMENTS in stardustsuperwizard/mikeys_game_bones-rules-moba per its
latest automated review.

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
gh pr view $ARGUMENTS --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json number,title,body,url,headRefName,labels,comments
```

```text
CLOUD — two calls to mcp__github__pull_request_read, same arguments except
`method`:
  method="get"           -> number, title, body, url, head.ref, labels
  method="get_comments"  -> the comments you search for the verdict marker
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  pullNumber=$ARGUMENTS
```

Find the most recent comment containing `<!-- agent-review-verdict -->`.

- If its first line is `VERDICT: FIX`, delegate to the `fixer` subagent with
  the PR number and that comment's content as context.
- If it's `VERDICT: DESIGN AMBIGUITY`, stop and show the user the ambiguity
  described in the comment — do not delegate to `fixer`, that decision is
  theirs.
- If it's `VERDICT: PLANNING FAILURE`, stop and tell the user this needs to
  go back through planning rather than a bounded fix.
- If it's `VERDICT: PASS`, say so — there's nothing to fix.
- If there's no such comment at all, ask the user what needs fixing.
