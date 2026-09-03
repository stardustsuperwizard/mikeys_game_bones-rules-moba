---
description: Review a pull request against its Implementation Task Issue's acceptance criteria and publish a verdict (local counterpart of the agent:review label)
argument-hint: <pr-number>
---

Review pull request #$ARGUMENTS in stardustsuperwizard/mikeys_game_bones-rules-moba.

First fetch it and the Issue it closes so you have real content to hand
off, not a guess:

```bash
gh pr view $ARGUMENTS --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json number,title,body,url,headRefName,isDraft,files
gh pr diff $ARGUMENTS --repo stardustsuperwizard/mikeys_game_bones-rules-moba
```

If the PR doesn't exist or is still a draft, say so and confirm with the
user before proceeding anyway — reviewing a draft against acceptance
criteria that aren't finished yet produces a misleading verdict.

Otherwise, delegate the review to the `reviewer` subagent, giving it the PR
number and the fetched content above as context.
