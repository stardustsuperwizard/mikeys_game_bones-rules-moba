#!/usr/bin/env python3
"""Read an Issue's declared dependencies out of its `## Dependencies` block.

Every Issue template in this repository carries the same block, and it is the
*only* place a dependency is written in prose:

    ## Dependencies

    | Relationship | Issue | Why |
    | --- | --- | --- |
    | Blocked by | #12 | Needs the effect container API |
    | Blocks | #34 | #34 consumes the resolver this adds |

Two relationship words, and only two. `Blocked by` means "this Issue cannot
start until that one closes"; `Blocks` is the same edge written from the other
end. Both are accepted on any Issue because the person who knows about an edge
is not reliably the one on the blocked side of it -- a planner decomposing a
Feature knows the whole chain and writes `Blocks` rows, while someone filing a
bug usually knows only what they are waiting on.

Why a table at all, when GitHub has native issue dependencies: the native
relationship is invisible in an Issue body, in a plan comment, and in every
export -- and it is the thing that kept failing to get created. Writing the
edge in the body first means the intent survives even when the API call does
not, and `sync-issue-dependencies.py` can replay it later. The body is the
declaration; the native relationship is the derived state. Never the reverse:
do not hand-edit dependencies in the GitHub UI and expect the table to follow.

This module only *reads*. It does no network, spawns no `gh`, and has no
third-party dependencies, so it can be imported by a workflow step, called
from the command line, and tested without credentials.

Named with underscores rather than a hyphen for the same reason
`task_scope.py` is: it is imported (`sync-issue-dependencies.py`), and a
hyphen is not a legal module name.

Usage:

    issue_dependencies.py --body-file issue-body.md
    gh issue view 168 --json body --jq .body | issue_dependencies.py

    {
      "blocked_by": [12],
      "blocks": [34],
      "declared": true,
      "malformed": []
    }
"""

from __future__ import annotations

import argparse
import json
import re
import sys

DEPENDENCIES_HEADING = "Dependencies"

# The label an Issue carries when it blocks at least one other Issue.
# `sync-issue-dependencies.py` applies it; `issue-dependencies.yml` triggers on
# it. Defined here so the three agree on one spelling.
BLOCKER_LABEL = "blocker"

# Canonical relationship words, keyed by their normalized form. Normalization
# drops everything but letters and lowercases, so `Blocked by`, `blocked-by`,
# `**Blocked By**` and `blockedby` all arrive as `blockedby`.
#
# `blocking` is accepted as a synonym of `blocks` because it is what people
# write, not because it is canonical. The templates and the planner emit
# `Blocks` and `Blocked by`; anything else is tolerated on read and never
# produced on write.
RELATIONSHIPS = {
    "blockedby": "blocked_by",
    "isblockedby": "blocked_by",
    "dependson": "blocked_by",
    "blocks": "blocks",
    "blocking": "blocks",
    "isblocking": "blocks",
}

# Row values that mean "no edge here". The templates ship a `| None | — | — |`
# row so that the table is present and obviously empty rather than absent and
# ambiguous.
#
# `tbd` is deliberately absent: it does not mean "no dependency", it means
# "there is one and nobody has looked it up". That belongs in `malformed`,
# where it gets reported, rather than here, where it would be swallowed.
EMPTY_VALUES = {"", "none", "n/a", "na", "-", "--", "—", "–", "…", "..."}


def strip_comments(text: str) -> str:
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


def section(body: str, heading: str):
    """Return the text under a markdown heading, or None if it is absent.

    Same rule as `task_scope.section`, deliberately duplicated rather than
    imported: these two modules answer unrelated questions about an Issue
    body, and a shared helper between them would be a dependency neither one
    needs. Keep the pattern identical if either changes.

    This one returns `None` rather than `""` for a missing heading, because
    the difference matters here: an Issue with an empty Dependencies section
    has been asked the question and answered "none", while an Issue with no
    such section was never asked. The sweep reports those differently.
    """
    pattern = rf"^#{{1,6}}\s*{re.escape(heading)}\s*$(.*?)(?=^#{{1,6}}\s|\Z)"
    match = re.search(pattern, body or "", re.M | re.S | re.I)
    return match.group(1) if match else None


def normalize_relationship(cell: str) -> str:
    """Reduce a relationship cell to letters only, lowercased."""
    return re.sub(r"[^a-z]", "", cell.casefold())


def issue_numbers(cell: str) -> list[int]:
    """Every Issue this cell refers to, in the order written.

    Three spellings are read, because all three appear in practice:

    - `#34`, which is what the templates ask for and what GitHub renders;
    - a full `https://github.com/owner/repo/issues/34` URL, which is what you
      get from pasting a browser tab;
    - `GH-34`, which some tooling emits.

    A bare `34` is deliberately NOT read. The `Why` column is prose and the
    `Issue` column gets pasted into carelessly; a bare integer there is as
    likely to be a version, a section number, or a date fragment as an Issue,
    and inventing a dependency is worse than missing one -- a missing edge is
    visible the moment someone reads the table, a wrong one silently blocks
    real work.
    """
    found = []
    for match in re.finditer(
        r"(?:#|GH-|/issues/)(\d+)", cell, re.I
    ):
        number = int(match.group(1))
        if number not in found:
            found.append(number)
    return found


def is_empty(cell: str) -> bool:
    return cell.strip().strip("`*_").strip().casefold() in EMPTY_VALUES


def _rows(text: str):
    """Yield `(relationship_cell, issue_cell)` pairs from the section.

    Two shapes, because the repository has both:

    - **Table rows.** The canonical form. A markdown row is any line starting
      with `|`; the header and its `| --- |` separator fall out on their own,
      because `Relationship` and `---` normalize to words that are not in
      `RELATIONSHIPS`.
    - **`Blocked by: #12` bullets.** The form
      `.github/ISSUE_TEMPLATE/99-execute_task.md` shipped before the table,
      so every Implementation Task Issue filed to date writes it that way.
      Reading it costs one branch and means the sweep can repair the existing
      backlog instead of only new Issues.
    """
    for line in text.splitlines():
        line = line.strip()

        if line.startswith("|"):
            cells = [cell.strip() for cell in line.strip("|").split("|")]
            if len(cells) >= 2:
                yield cells[0], cells[1]
            continue

        # `- Blocked by: #12`, `* Blocks: #34, #35`, or the same without a
        # bullet. The colon is required: without it, a sentence in the section
        # that merely contains the word "blocks" would be read as a row.
        bullet = re.match(
            r"(?:[-*+]\s+|\d+[.)]\s+)?([A-Za-z][A-Za-z\s_*`-]{0,20}?)\s*:\s*(.*)",
            line,
        )
        if bullet:
            yield bullet.group(1), bullet.group(2)


def parse(body: str) -> dict:
    """Read the `## Dependencies` block.

    `declared` says whether the Issue has the section at all. An Issue that
    says "None" has answered the question; an Issue with no such heading was
    filed before the standard existed, or by hand against no template, and the
    sweep reports the two differently -- silence is not the same answer as
    "no".

    `malformed` collects rows that named a relationship but no Issue number,
    so a `| Blocked by | TBD |` row is surfaced rather than silently dropped.
    That row is the failure mode worth shouting about: it reads as a
    declaration to a human and is invisible to everything else.
    """
    raw = section(body, DEPENDENCIES_HEADING)
    declared = raw is not None
    text = strip_comments(raw or "")

    edges: dict[str, list[int]] = {"blocked_by": [], "blocks": []}
    malformed: list[str] = []

    for relationship_cell, issue_cell in _rows(text):
        kind = RELATIONSHIPS.get(normalize_relationship(relationship_cell))
        if kind is None:
            continue

        numbers = issue_numbers(issue_cell)
        if not numbers:
            if not is_empty(issue_cell):
                malformed.append(
                    f"{relationship_cell.strip()}: {issue_cell.strip()}"
                )
            continue

        for number in numbers:
            if number not in edges[kind]:
                edges[kind].append(number)

    return {
        "blocked_by": edges["blocked_by"],
        "blocks": edges["blocks"],
        "declared": declared,
        "malformed": malformed,
    }


def edges(number: int, body: str) -> list[tuple[int, int]]:
    """Every `(blocked, blocker)` pair Issue `number`'s body declares.

    Both relationship words collapse to the same edge here, which is the whole
    point of accepting both: downstream there is one kind of thing to create,
    and `Blocks`/`Blocked by` is only a choice about which end of it you are
    writing from.

    Self-edges are dropped rather than reported. `| Blocks | #7 |` on Issue #7
    is a typo with no useful reading, and GitHub rejects it anyway.
    """
    parsed = parse(body)
    pairs = []

    for blocker in parsed["blocked_by"]:
        if blocker != number:
            pairs.append((number, blocker))

    for blocked in parsed["blocks"]:
        if blocked != number:
            pairs.append((blocked, number))

    return pairs


def render_table(blocked_by=(), blocks=(), reasons=None) -> str:
    """The canonical block, so every writer emits byte-identical markdown.

    `reasons` maps an Issue number to the one-line justification for its row.
    A row with no reason gets an em dash rather than an empty cell, because an
    empty trailing cell in a markdown table renders as a ragged column.
    """
    reasons = reasons or {}
    lines = [
        "| Relationship | Issue | Why |",
        "| --- | --- | --- |",
    ]

    rows = [
        ("Blocked by", number) for number in blocked_by
    ] + [
        ("Blocks", number) for number in blocks
    ]

    if not rows:
        lines.append("| None | — | — |")
    else:
        for relationship, number in rows:
            why = reasons.get(number) or "—"
            lines.append(f"| {relationship} | #{number} | {why} |")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Report the dependencies an Issue body declares under its "
            "`## Dependencies` heading."
        )
    )
    parser.add_argument(
        "--body-file",
        help="File holding the Issue body. Defaults to reading stdin.",
    )
    parser.add_argument(
        "--number",
        type=int,
        help=(
            "The Issue's own number. When given, `edges` is included in the "
            "output as (blocked, blocker) pairs with self-edges dropped."
        ),
    )
    args = parser.parse_args()

    if args.body_file:
        with open(args.body_file, encoding="utf-8") as handle:
            body = handle.read()
    else:
        body = sys.stdin.read()

    result = parse(body)

    if args.number is not None:
        result["edges"] = [
            list(pair) for pair in edges(args.number, body)
        ]

    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
