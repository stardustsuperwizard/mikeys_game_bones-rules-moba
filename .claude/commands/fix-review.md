---
description: Apply a bounded correction to a PR in response to its review:fix verdict (local counterpart of commenting @copilot for a fix cycle)
argument-hint: <pr-number>
---

Fix pull request #$ARGUMENTS in stardustsuperwizard/sword-and-planet per its
latest automated review.

First fetch the PR and its review comments so you have the real verdict, not
a guess:

```bash
gh pr view $ARGUMENTS --repo stardustsuperwizard/sword-and-planet \
  --json number,title,body,url,headRefName,labels,comments
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
