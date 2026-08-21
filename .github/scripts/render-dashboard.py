#!/usr/bin/env python3
"""Render the agent control plane dashboard for Sword and Planet.

Every state this prints is *derived* from the repository graph at the moment
it runs — issue open/closed, GitHub issue dependencies, sub-issue links, open
pull requests, and the reviewer's `review:*` labels. Nothing is stored, so
nothing can drift out of sync. A failed workflow run leaves a stale
dashboard, never a wrong repository.

This replaced a Projects v2 board. The board could record state but could not
cause work, because there is no repository-level Actions trigger for a
project item change — see docs/AGENT_WORKFLOW.md.

Usage:
    .github/scripts/render-dashboard.py              # markdown to stdout
    .github/scripts/render-dashboard.py --json       # machine-readable
    .github/scripts/render-dashboard.py --repo o/r

Requires `gh` authenticated against the repository. No permissions beyond
normal repository read, and no third-party dependencies.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone

ISSUE_FIELDS = [
    "number", "title", "url", "state", "labels", "body",
    "blockedBy", "parent", "subIssues", "milestone",
]

PR_FIELDS = [
    "number", "title", "url", "isDraft", "labels", "closingIssuesReferences",
]

# Verdict labels the reviewer applies. agent-03-review.yml clears the other
# three before adding one, so at most one of these is ever present and it is
# always the most recent verdict.
VERDICT_PASS = "review:pass"
VERDICT_ADVERSE = {
    "review:fix": "FIX",
    "review:planning-failure": "PLANNING FAILURE",
    "review:design-ambiguity": "DESIGN AMBIGUITY",
}

# Paths where a weak or unknown model is a bad bet. Godot scene and resource
# serialization is unforgiving of small mistakes, so a task touching these is
# flagged for a strong model rather than whatever Auto happens to draw.
DELICATE_SUFFIXES = (".tscn", ".tres")
DELICATE_NAMES = ("project.godot",)
DELICATE_PREFIXES = ("addons/",)

# Task states, in the order the dashboard presents them. The first three are
# the ones that want a human; the rest are informational.
READY = "Ready to dispatch"
NEEDS_ATTENTION = "Needs your attention"
READY_TO_MERGE = "Ready to merge"
IMPLEMENTING = "Implementing"
AWAITING_REVIEW = "Awaiting review"
BLOCKED_DEPS = "Blocked — dependencies"
DONE = "Done"

# Feature states.
PLANNING = "Planning"
IN_PROGRESS = "In progress"
AWAITING_SIGNOFF = "Awaiting your sign-off"
UNPLANNED = "Unplanned"

MARKER = "<!-- agent-control-plane -->"

# Kept in step with DASHBOARD_LABEL in agent-00-dashboard.yml.
DASHBOARD_LABEL = "dashboard"


def run_gh(args: list[str], repo: str | None) -> str:
    if repo:
        args = [*args, "--repo", repo]
    try:
        proc = subprocess.run(
            ["gh", *args], capture_output=True, text=True, check=True
        )
    except FileNotFoundError:
        sys.exit("gh not found on PATH. Install the GitHub CLI.")
    except subprocess.CalledProcessError as exc:
        sys.exit(f"gh {' '.join(args)} failed:\n{exc.stderr.strip()}")
    return proc.stdout


def label_names(item: dict) -> set[str]:
    return {label["name"] for label in item.get("labels") or []}


def strip_comments(text: str) -> str:
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


def section(body: str, heading: str) -> str:
    """Return the text under a markdown heading, up to the next heading."""
    pattern = rf"^#{{1,6}}\s*{re.escape(heading)}\s*$(.*?)(?=^#{{1,6}}\s|\Z)"
    match = re.search(pattern, body or "", re.M | re.S | re.I)
    return match.group(1) if match else ""


def expected_paths(body: str) -> set[str]:
    """Backticked file paths from the task template's expected-changes block."""
    text = strip_comments(section(body, "Files or Subsystems Expected to Change"))
    paths = set()
    for token in re.findall(r"`([^`\n]+)`", text):
        token = token.strip()
        if "/" in token or re.search(r"\.\w+$", token):
            paths.add(token.lstrip("./"))
    return paths


def is_delicate(paths: set[str]) -> bool:
    return any(
        path.endswith(DELICATE_SUFFIXES)
        or path.split("/")[-1] in DELICATE_NAMES
        or path.startswith(DELICATE_PREFIXES)
        for path in paths
    )


def fetch(repo: str | None) -> tuple[list[dict], list[dict]]:
    issues = json.loads(run_gh([
        "issue", "list", "--state", "all", "--limit", "500",
        "--json", ",".join(ISSUE_FIELDS),
    ], repo))
    prs = json.loads(run_gh([
        "pr", "list", "--state", "open", "--limit", "200",
        "--json", ",".join(PR_FIELDS),
    ], repo))
    return issues, prs


def pr_index(prs: list[dict]) -> dict[int, dict]:
    """Map issue number -> the open PR that closes it.

    Built from the PR side rather than the issue side because the PR's
    `review:*` labels are needed anyway, and a merged PR means the issue is
    closed, which is already Done.
    """
    index: dict[int, dict] = {}
    for pr in prs:
        for ref in pr.get("closingIssuesReferences") or []:
            index[ref["number"]] = pr
    return index


def classify_task(issue: dict, prs: dict[int, dict]) -> tuple[str, dict]:
    """Derive one implementation task's state. Order of tests is the design."""
    detail: dict = {}

    if issue["state"] == "CLOSED":
        return DONE, detail

    blockers = [node for node in (issue.get("blockedBy") or {}).get("nodes", [])
                if node["state"] == "OPEN"]
    if blockers:
        detail["blockers"] = [node["number"] for node in blockers]
        return BLOCKED_DEPS, detail

    pr = prs.get(issue["number"])
    if pr is None:
        paths = expected_paths(issue.get("body") or "")
        detail["paths"] = sorted(paths)
        detail["delicate"] = is_delicate(paths)
        return READY, detail

    detail["pr"] = pr["number"]
    names = label_names(pr)

    # A draft PR means a session is actively working, whatever the last
    # verdict said — a `review:fix` label persists through the bounded
    # correction that answers it, so draft has to win or every in-flight fix
    # would show as waiting on you.
    if pr.get("isDraft"):
        return IMPLEMENTING, detail

    if VERDICT_PASS in names:
        return READY_TO_MERGE, detail

    for label, verdict in VERDICT_ADVERSE.items():
        if label in names:
            detail["verdict"] = verdict
            return NEEDS_ATTENTION, detail

    return AWAITING_REVIEW, detail


def classify_feature(issue: dict) -> tuple[str, dict]:
    detail: dict = {}

    if issue["state"] == "CLOSED":
        return DONE, detail

    if "agent:plan" in label_names(issue):
        return PLANNING, detail

    children = (issue.get("subIssues") or {}).get("nodes") or []
    if not children:
        return UNPLANNED, detail

    open_children = [c for c in children if c["state"] == "OPEN"]
    detail["children"] = len(children)
    detail["open_children"] = len(open_children)

    if not open_children:
        return AWAITING_SIGNOFF, detail

    return IN_PROGRESS, detail


def build(issues: list[dict], prs: list[dict]) -> dict:
    index = pr_index(prs)
    tasks, features = [], []

    for issue in issues:
        # The dashboard Issue is not work. Checked two ways because on the
        # very first run the Issue exists with a placeholder body before this
        # script has ever written the marker into it.
        if MARKER in (issue.get("body") or "") or DASHBOARD_LABEL in label_names(issue):
            continue

        # Structural, not label-based: a task is an issue with a parent, a
        # feature is one with sub-issues. Labels on tasks have proven
        # inconsistent (some carry `planned` inherited from the planner).
        if issue.get("parent"):
            state, detail = classify_task(issue, index)
            tasks.append({"issue": issue, "state": state, **detail})
        else:
            state, detail = classify_feature(issue)
            features.append({"issue": issue, "state": state, **detail})

    return {"tasks": tasks, "features": features}


def sort_key(row: dict) -> tuple[int, int]:
    """Feature number, then task number.

    Every task in the Ready bucket has all its blockers closed, so any order
    is dispatchable. Grouping by parent keeps related work together, which is
    what you actually want when picking the next thing to paste.
    """
    parent = row["issue"].get("parent") or {}
    return (parent.get("number", 0), row["issue"]["number"])


def task_table(rows: list[dict], columns: list[str], cell) -> list[str]:
    out = ["| " + " | ".join(columns) + " |",
           "|" + "|".join(["---"] * len(columns)) + "|"]
    for row in sorted(rows, key=sort_key):
        out.append("| " + " | ".join(cell(row)) + " |")
    return out


def link(issue: dict) -> str:
    return f"[#{issue['number']}]({issue['url']})"


def render(model: dict, repo: str | None) -> str:
    tasks = model["tasks"]
    features = model["features"]
    by_state: dict[str, list[dict]] = {}
    for row in tasks:
        by_state.setdefault(row["state"], []).append(row)

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    out = [
        MARKER,
        "# Agent Control Plane",
        "",
        "Every state below is derived fresh from issues, dependencies, and "
        "open pull requests. Nothing here is stored, so nothing here can be "
        "wrong — only stale. Regenerated on every issue and pull request "
        "event, and nightly.",
        "",
    ]

    ready = by_state.get(READY, [])
    out += [f"## {READY} ({len(ready)})", ""]
    if ready:
        out += [
            "Open the task, copy its **Run This Task** block, then paste it "
            "into a new Copilot agent session — mobile or desktop — on the "
            "model you chose. Pick the model, not a custom agent.",
            "",
        ]
        out += task_table(
            ready, ["Task", "Feature", "Model", "Title"],
            lambda r: [
                link(r["issue"]),
                link(r["issue"]["parent"]),
                "⚠️ strong" if r.get("delicate") else "any",
                r["issue"]["title"].removeprefix("[impl] "),
            ],
        )
        if any(r.get("delicate") for r in ready):
            out += [
                "",
                "⚠️ means the task expects to touch `.tscn`, `.tres`, "
                "`project.godot`, or `addons/`. Godot serialization is "
                "unforgiving — pick a strong model rather than Auto.",
            ]
    else:
        out.append("_Nothing ready. Everything is blocked, in flight, or done._")
    out.append("")

    attention = by_state.get(NEEDS_ATTENTION, [])
    out += [f"## {NEEDS_ATTENTION} ({len(attention)})", ""]
    if attention:
        out += task_table(
            attention, ["Task", "PR", "Verdict", "Title"],
            lambda r: [
                link(r["issue"]), f"#{r['pr']}", f"`{r.get('verdict', '?')}`",
                r["issue"]["title"].removeprefix("[impl] "),
            ],
        )
    else:
        out.append("_No adverse review verdicts outstanding._")
    out.append("")

    merge = by_state.get(READY_TO_MERGE, [])
    out += [f"## {READY_TO_MERGE} ({len(merge)})", ""]
    if merge:
        out += task_table(
            merge, ["Task", "PR", "Title"],
            lambda r: [link(r["issue"]), f"#{r['pr']}",
                       r["issue"]["title"].removeprefix("[impl] ")],
        )
    else:
        out.append("_Nothing has passed review and is waiting on a merge._")
    out.append("")

    signoff = [f for f in features if f["state"] == AWAITING_SIGNOFF]
    out += [f"## {AWAITING_SIGNOFF} ({len(signoff)})", ""]
    if signoff:
        out += [
            "Every sub-issue is closed. Confirm the Feature's own acceptance "
            "criteria hold end to end, do the Human Validation Required "
            "checks in the Godot editor, then close it. Nothing closes a "
            "Feature automatically — that is the only checkpoint in the "
            "pipeline.",
            "",
        ]
        for row in sorted(signoff, key=lambda r: r["issue"]["number"]):
            out.append(
                f"- {link(row['issue'])} {row['issue']['title']} "
                f"— {row['children']} tasks, all closed"
            )
    else:
        out.append("_No Feature is waiting on you._")
    out.append("")

    out += ["## In flight", ""]
    flight = (by_state.get(IMPLEMENTING, []) + by_state.get(AWAITING_REVIEW, []))
    if flight:
        out += task_table(
            flight, ["Task", "PR", "State", "Title"],
            lambda r: [link(r["issue"]), f"#{r['pr']}", r["state"],
                       r["issue"]["title"].removeprefix("[impl] ")],
        )
    else:
        out.append("_No sessions running._")
    out.append("")

    blocked = by_state.get(BLOCKED_DEPS, [])
    out += [f"## {BLOCKED_DEPS} ({len(blocked)})", ""]
    if blocked:
        out += task_table(
            blocked, ["Task", "Waiting on", "Title"],
            lambda r: [
                link(r["issue"]),
                " ".join(f"#{n}" for n in r["blockers"]),
                r["issue"]["title"].removeprefix("[impl] "),
            ],
        )
    else:
        out.append("_Nothing is waiting on a dependency._")
    out.append("")

    decomposed = [f for f in features
                  if f["state"] not in (DONE, UNPLANNED)]
    out += [f"## Features in flight ({len(decomposed)})", "",
            "| Feature | State | Tasks |", "|---|---|---|"]
    for row in sorted(decomposed, key=lambda r: r["issue"]["number"]):
        tally = (f"{row['children'] - row['open_children']}/{row['children']}"
                 if "children" in row else "—")
        out.append(
            f"| {link(row['issue'])} {row['issue']['title']} "
            f"| {row['state']} | {tally} |"
        )

    # The queue for `agent:plan`. Long enough to collapse, but leaving it off
    # entirely is how a backlog becomes invisible.
    waiting = sorted([f for f in features if f["state"] == UNPLANNED],
                     key=lambda r: r["issue"]["number"])
    out += ["", f"## Awaiting planning ({len(waiting)})", ""]
    if waiting:
        out += [
            "Add **`agent:plan`** to one of these when it is genuinely ready "
            "to be decomposed — not when it was filed.",
            "",
            "<details><summary>Show all</summary>",
            "",
        ]
        for row in waiting:
            out.append(f"- {link(row['issue'])} {row['issue']['title']}")
        out += ["", "</details>"]
    else:
        out.append("_Nothing waiting to be planned._")

    done = len([r for r in tasks if r["state"] == DONE])
    active = len(decomposed)
    out += [
        "",
        "---",
        "",
        f"{done} tasks done · {len(tasks) - done} open · "
        f"{active} feature{'' if active == 1 else 's'} in flight · "
        f"{len(waiting)} awaiting planning",
        "",
        f"_Generated {now} by `.github/scripts/render-dashboard.py`. "
        "Edits to this issue are overwritten._",
    ]

    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", help="OWNER/REPO, defaults to the checkout")
    parser.add_argument("--json", action="store_true",
                        help="emit the derived model instead of markdown")
    args = parser.parse_args()

    issues, prs = fetch(args.repo)
    model = build(issues, prs)

    if args.json:
        print(json.dumps({
            "tasks": [{"number": r["issue"]["number"], "state": r["state"]}
                      for r in model["tasks"]],
            "features": [{"number": r["issue"]["number"], "state": r["state"]}
                         for r in model["features"]],
        }, indent=2))
    else:
        print(render(model, args.repo))

    return 0


if __name__ == "__main__":
    sys.exit(main())
