"""How a finished agent session's raw output is read.

`run-agent-session` hands every caller the same two things: an outcome file
classified by `classify-copilot-outcome.py` / `classify-claude-outcome.py`,
and the session's text. Deciding whether that text can be trusted is the
same question for every caller, and it has exactly one right answer:

- **Cut off** means the session stopped before it chose to stop -- an
  unfinished turn, or a session that errored out. Nothing it produced is a
  complete answer, whatever shape the fragment happens to have.
- **Budget hit** means it ran into its credit or turn ceiling. That is not
  the same fault: a session can spend its last credit on the final line of a
  perfectly complete answer. Whether *this* answer is complete is the
  caller's own question, asked against its own required shape.

Conflating the two sends a vendor crash back to a human as "your prompt is
wrong", which is the wrong fix for that failure and the reason these live in
one place rather than being re-typed per caller.

This module only *reads* dictionaries and strings. It does no network,
spawns no `gh`, and has no third-party dependencies, so it can be imported
by a workflow step, called from the command line, and tested without
credentials -- the same contract `issue_dependencies.py` states for itself.

Named with underscores rather than a hyphen because it is imported, and a
hyphen is not a legal module name.
"""

import re

SESSION_ERROR = "session_error"
BUDGET_EXHAUSTED = "budget_exhausted"


def was_cut_off(outcome: dict) -> bool:
    """True when the session stopped before it chose to stop.

    Deliberately NOT true for a budget ceiling -- see `hit_budget`. A caller
    that wants "stopped for any reason" wants `was_cut_off(o) or
    hit_budget(o)` and should say so, so the two stay distinguishable in
    whatever it reports to a human.
    """

    return bool(
        outcome.get("unfinished_turn") or outcome.get("reason") == SESSION_ERROR
    )


def hit_budget(outcome: dict) -> bool:
    """True when the session ran into its credit or turn ceiling."""

    return outcome.get("reason") == BUDGET_EXHAUSTED


def strip_code_fence(text: str) -> str:
    """Drop one ``` fence wrapping the whole answer, if there is one.

    Only a fence the answer *opens with*, and only its own closing line --
    a fenced block in the middle of a report is content, not packaging.
    """

    if not text.startswith("```"):
        return text

    lines = text.splitlines()[1:]

    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]

    return "\n".join(lines).strip()


def strip_fenced_blocks(text: str) -> str:
    """Remove every fenced code block, so quoted Markdown is not read as real.

    A heading inside a ``` fence is an example of a heading, not one. Any
    caller that finds sections by matching `^#` against a body a human or a
    model wrote has to drop fences first, or a pasted template becomes a
    section boundary of its own.

    Kept here rather than beside `strip_comments` in `issue_dependencies.py`
    because that module's callers read Issue *tables*, where a fence has
    never been the hazard; this one's read prose sections.
    """

    return re.sub(r"^```.*?(?:^```|\Z)", "", text or "", flags=re.MULTILINE | re.DOTALL)
