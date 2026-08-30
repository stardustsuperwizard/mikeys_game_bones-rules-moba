---
description: Implement an Implementation Task Issue end to end (local counterpart of dispatching a Copilot agent session on it)
argument-hint: <task-issue-number>
---

Implement Implementation Task Issue #$ARGUMENTS in
stardustsuperwizard/mikeys_gamebones-rules-moba.

First fetch it so you have the real contract, not a guess:

```bash
gh issue view $ARGUMENTS --repo stardustsuperwizard/mikeys_gamebones-rules-moba \
  --json number,title,body,url,parent,state,labels
```

If the Issue doesn't exist, isn't open, doesn't carry the `implementation`
label, or still has an open blocker (check `blockedBy` via
`gh issue view $ARGUMENTS --json blockedBy`), say so and confirm with the
user before proceeding anyway.

Otherwise, delegate implementation to the `executor` subagent, giving it the
Issue number and the fetched body as context.
