---
description: Review a pull request against its Implementation Task Issue's acceptance criteria and publish a verdict (local counterpart of the agent:review label)
argument-hint: <pr-number>
---

Review pull request #$ARGUMENTS in stardustsuperwizard/mikeys_game_bones-rules-moba.

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

First fetch it and the Issue it closes so you have real content to hand
off, not a guess:

```bash
# LOCAL
gh pr view $ARGUMENTS --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json number,title,body,url,headRefName,isDraft,files
gh pr diff $ARGUMENTS --repo stardustsuperwizard/mikeys_game_bones-rules-moba
```

```text
CLOUD — two calls to mcp__github__pull_request_read, same arguments except
`method`:
  method="get"       -> number, title, body, url, head.ref, draft
  method="get_diff"  -> the diff
  owner="stardustsuperwizard"
  repo="mikeys_game_bones-rules-moba"
  pullNumber=$ARGUMENTS
```

If the PR doesn't exist or is still a draft, say so and confirm with the
user before proceeding anyway — reviewing a draft against acceptance
criteria that aren't finished yet produces a misleading verdict.

Otherwise, delegate the review to the `reviewer` subagent, giving it the PR
number and the fetched content above as context.
