---
description: Implement an Implementation Task Issue end to end (local counterpart of dispatching a Copilot agent session on it)
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

Otherwise, delegate implementation to the `executor` subagent, giving it the
Issue number and the fetched body as context.
