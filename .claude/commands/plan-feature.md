---
description: Plan a Feature Issue into Implementation Task sub-issues (local counterpart of adding agent:plan)
argument-hint: <feature-issue-number>
---

Plan Feature Issue #$ARGUMENTS in stardustsuperwizard/sword-and-planet.

First fetch it and its comments so you have real content to hand off, not a
guess:

```bash
gh issue view $ARGUMENTS --repo stardustsuperwizard/sword-and-planet \
  --json number,title,body,milestone,url,labels
gh api --paginate repos/stardustsuperwizard/sword-and-planet/issues/$ARGUMENTS/comments
```

If the Issue doesn't exist, isn't a Feature, or already carries a
`<!-- claude-planner-complete -->` / `<!-- automated-planner-complete -->`
comment, say so and stop rather than proceeding.

Otherwise, delegate the decomposition to the `planner` subagent, giving it
the Issue number and the fetched content above as context.
