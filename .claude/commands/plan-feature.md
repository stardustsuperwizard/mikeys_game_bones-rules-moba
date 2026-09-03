---
description: Plan an intake Issue of any type (Feature, Task, Bug, Infrastructure, Dependency) into Implementation Task sub-issues (local counterpart of adding agent:plan)
argument-hint: <intake-issue-number>
---

Plan intake Issue #$ARGUMENTS in stardustsuperwizard/mikeys_game_bones-rules-moba.

First fetch it and its comments so you have real content to hand off, not a
guess. The `labels` field carries the type label, which tells the planner
which sections the body has and which it must derive:

```bash
gh issue view $ARGUMENTS --repo stardustsuperwizard/mikeys_game_bones-rules-moba \
  --json number,title,body,milestone,url,labels
gh api --paginate repos/stardustsuperwizard/mikeys_game_bones-rules-moba/issues/$ARGUMENTS/comments
```

Stop and say so, rather than proceeding, if the Issue:

- does not exist;
- already carries a `<!-- claude-planner-complete -->` or
  `<!-- automated-planner-complete -->` comment — it has been planned, unless
  the user explicitly asked for a re-plan;
- is an Implementation Task rather than an intake Issue (`implementation`
  label, `[impl]` title, or a parent Issue of its own). Those are executed
  with `/execute-task`, not planned.

**All five intake types are plannable** — `enhancement`, `task`, `bug`,
`infrastructure`, and `dependency`. A defect report is not a reason to stop,
and must never be sent back to be refiled as a Feature. All five templates
carry an `Acceptance Criteria` section, but most of what they ship is generic
boilerplate; the planner specialises it against the Issue body rather than
copying it through. That is expected, not a blocker.

Otherwise, delegate the decomposition to the `planner` subagent, giving it
the Issue number and the fetched content above as context.
