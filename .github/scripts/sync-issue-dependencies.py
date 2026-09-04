#!/usr/bin/env python3
"""Turn the dependency tables in Issue bodies into real GitHub dependencies.

The `## Dependencies` table is the declaration; GitHub's native blocked-by
relationship is the derived state. This script is the one thing that turns the
first into the second, and it is the *only* writer of that relationship in the
repository -- `agent-01-planner.yml` calls it after creating a plan's
sub-issues, and `issue-dependencies.yml` calls it when the `blocker` label
lands on an Issue. One implementation, so a plan and a hand-labelled Issue
cannot disagree about what the table meant.

Why a script rather than `gh issue edit --add-blocked-by`: that flag exists
only in GitHub CLI 2.94.0 and newer (2026-06-10), and on an older runner image
it is an unknown-flag error. That call was the repository's only way to create
a dependency, it ran inside the same step that had already created the plan's
Issues, and dependency chains were not getting made. Whatever the immediate
cause on any given run, a step that both creates Issues and wires them can
only be retried by re-creating the Issues -- so the wiring moved here, where
it is re-runnable, and the intent moved into the Issue body, where a failed
run cannot lose it.

The REST endpoint underneath the flag has no version floor, so this goes
straight to it with `gh api`, which every `gh` has had for years.

    POST /repos/{owner}/{repo}/issues/{n}/dependencies/blocked_by
    {"issue_id": <database id of the blocking issue>}

Note `issue_id`, not `issue_number`: the body takes the blocking Issue's
database id (the `id` field of the REST issue object), which is not the number
you see in the UI and is not the GraphQL node id `gh issue view --json id`
returns either. Passing a number there fails or, worse, links the wrong Issue.

Add-only, on purpose. An edge in GitHub that no table declares is *reported*
and never deleted: the table is the intent, but a human wiring a dependency in
the UI is a legitimate thing to do, and a sweep that quietly unwired it would
be a data-loss bug that nobody would spot until work started in the wrong
order. Drift gets printed; a person decides.

Usage:

    sync-issue-dependencies.py --issue 168
    sync-issue-dependencies.py --issue 168 --issue 169 --dry-run
    sync-issue-dependencies.py --sweep            # every open Issue
    sync-issue-dependencies.py --sweep --json

Requires `gh` authenticated against the repository, with write access to
Issues. No third-party dependencies.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import issue_dependencies
from issue_dependencies import BLOCKER_LABEL

# Colour and description for the `blocker` label, applied only if the label
# does not exist yet. Same `ensure_label` shape the agent workflows use: the
# check is on the name alone, so an existing label is never recoloured.
BLOCKER_COLOR = "B23F00"
BLOCKER_DESCRIPTION = "Blocks at least one other Issue; wires the dependency chain"

# GitHub's default page size is 30, which a long chain can exceed. Asked for
# explicitly rather than paginated: a hundred blockers on one Issue is a
# planning failure, not a pagination problem, and the count is reported so it
# is visible if it ever happens.
PAGE_SIZE = 100


class GhError(RuntimeError):
    """A `gh` call failed. Carries stderr so the caller can report it."""


def gh(args: list[str], check: bool = True) -> str:
    try:
        proc = subprocess.run(
            ["gh", *args], capture_output=True, text=True, check=False
        )
    except FileNotFoundError:
        sys.exit("gh not found on PATH. Install the GitHub CLI.")

    if proc.returncode != 0:
        message = (proc.stderr or proc.stdout).strip()
        if check:
            raise GhError(message)
        return ""

    return proc.stdout


def gh_json(args: list[str]):
    return json.loads(gh(args) or "null")


class Repository:
    """Every read and write this script makes, with per-run caching.

    The caching is not an optimisation so much as a correctness aid: a sweep
    asks about the same Issue from both ends of every edge, and re-reading it
    between the two would let a concurrent edit make the two answers
    disagree.
    """

    def __init__(self, repo: str, dry_run: bool = False):
        self.repo = repo
        self.dry_run = dry_run
        self._issues: dict[int, dict | None] = {}
        self._blocked_by: dict[int, list[int]] = {}
        # Numbers `gh issue list` returned, which is proof they are Issues
        # rather than pull requests. The REST endpoint cannot tell you that
        # without a request per Issue.
        self._lite: dict[int, dict] = {}
        self._labelled: set[int] = set()

    # -- reads ----------------------------------------------------------

    def issue(self, number: int) -> dict | None:
        """The REST issue object, or None if it does not exist here.

        One request per Issue, so it is asked only when the database `id` is
        actually needed -- which is on the blocking end of an edge, and
        nowhere else. A pull request is returned by this endpoint too (every
        PR is an Issue as far as `/issues/{n}` is concerned) and is filtered
        by the caller on the `pull_request` key, because a PR cannot take
        part in an issue dependency.
        """
        if number not in self._issues:
            try:
                self._issues[number] = gh_json(
                    ["api", f"repos/{self.repo}/issues/{number}"]
                )
            except GhError:
                self._issues[number] = None
        return self._issues[number]

    def check(self, number: int) -> str:
        """Empty string if `number` can take part in a dependency, else why not."""
        if number in self._lite:
            return ""

        issue = self.issue(number)
        if issue is None:
            return (
                f"#{number} could not be read; it may not exist in this "
                f"repository"
            )
        if "pull_request" in issue:
            return f"#{number} is a pull request, not an Issue"
        return ""

    def body(self, number: int) -> str:
        if number in self._lite:
            return self._lite[number].get("body") or ""
        return (self.issue(number) or {}).get("body") or ""

    def labels(self, number: int) -> set[str]:
        source = self._lite.get(number) or self.issue(number) or {}
        return {label["name"] for label in source.get("labels") or []}

    def blocked_by(self, number: int) -> list[int]:
        if number not in self._blocked_by:
            try:
                nodes = gh_json([
                    "api",
                    f"repos/{self.repo}/issues/{number}"
                    f"/dependencies/blocked_by?per_page={PAGE_SIZE}",
                ]) or []
            except GhError as error:
                raise GhError(
                    f"could not read the blocked-by list for #{number}: "
                    f"{error}"
                ) from error
            self._blocked_by[number] = [node["number"] for node in nodes]
        return self._blocked_by[number]

    def load_open_issues(self) -> list[int]:
        """Cache every open Issue's body and labels. Returns their numbers.

        `gh issue list` rather than the REST issues endpoint precisely because
        it excludes pull requests for us; the REST one does not. One request
        for the whole repository, which is what makes `--sweep` cheap enough
        to be the repair tool rather than a thing you avoid running.
        """
        issues = gh_json([
            "issue", "list",
            "--repo", self.repo,
            "--state", "open",
            "--limit", "500",
            "--json", "number,title,body,labels,url",
        ]) or []

        for issue in issues:
            self._lite[issue["number"]] = issue

        return [issue["number"] for issue in issues]

    def prime_blocked_by(self) -> bool:
        """Try to read the whole blocked-by graph in one request.

        `gh issue list --json blockedBy` needs GitHub CLI 2.94.0, the same
        floor this script avoids depending on for its *writes*. Here the
        dependency is soft: the bulk read only saves requests, so an older
        `gh` falls back to one REST call per Issue and everything still
        works. Returns whether the fast path was available, because drift
        reporting -- which would otherwise need that call per Issue over the
        whole repository -- is skipped rather than made slow when it is not.
        """
        try:
            issues = gh_json([
                "issue", "list",
                "--repo", self.repo,
                "--state", "open",
                "--limit", "500",
                "--json", "number,blockedBy",
            ]) or []
        except GhError:
            return False

        for issue in issues:
            nodes = (issue.get("blockedBy") or {}).get("nodes")
            if nodes is None:
                nodes = issue.get("blockedBy") or []
            self._blocked_by[issue["number"]] = [
                node["number"] for node in nodes
            ]

        return True

    # -- writes ---------------------------------------------------------

    def ensure_blocker_label_exists(self) -> None:
        existing = gh([
            "label", "list",
            "--repo", self.repo,
            "--limit", "200",
            "--json", "name",
            "--jq", ".[].name",
        ]).splitlines()

        if BLOCKER_LABEL in existing:
            return

        if self.dry_run:
            print(f"would create the `{BLOCKER_LABEL}` label")
            return

        gh([
            "label", "create", BLOCKER_LABEL,
            "--repo", self.repo,
            "--color", BLOCKER_COLOR,
            "--description", BLOCKER_DESCRIPTION,
        ], check=False)

    def add_blocked_by(self, blocked: int, blocker: int) -> None:
        blocker_id = self.issue(blocker)["id"]
        payload = json.dumps({"issue_id": blocker_id})

        if self.dry_run:
            print(f"would POST {payload} to #{blocked}'s blocked_by")
            return

        proc = subprocess.run(
            [
                "gh", "api",
                "--method", "POST",
                f"repos/{self.repo}/issues/{blocked}/dependencies/blocked_by",
                "--input", "-",
            ],
            input=payload,
            capture_output=True,
            text=True,
            check=False,
        )

        if proc.returncode != 0:
            raise GhError((proc.stderr or proc.stdout).strip())

        self._blocked_by.setdefault(blocked, []).append(blocker)

    def add_blocker_label(self, number: int) -> bool:
        """Label `number` as a blocker. True if it was actually added.

        One Issue commonly blocks several others, so this is called once per
        edge and has to answer "already done" for every call after the first
        -- including under `--dry-run`, where nothing is written and the
        caches alone cannot remember.
        """
        if number in self._labelled or BLOCKER_LABEL in self.labels(number):
            return False

        self._labelled.add(number)

        if self.dry_run:
            print(f"would add `{BLOCKER_LABEL}` to #{number}")
            return True

        gh([
            "issue", "edit", str(number),
            "--repo", self.repo,
            "--add-label", BLOCKER_LABEL,
        ], check=False)

        # Write the label back into whichever cache answered above, so a
        # second edge ending at the same blocker does not re-add it.
        cached = self._lite.get(number) or self._issues.get(number)
        if cached is not None:
            cached["labels"] = list(cached.get("labels") or []) + [
                {"name": BLOCKER_LABEL}
            ]
        return True


def collect_edges(repo: Repository, numbers: list[int], report: dict):
    """Read every named Issue's table into a de-duplicated set of edges."""
    edges: list[tuple[int, int]] = []

    for number in numbers:
        problem = repo.check(number)
        if problem:
            report["skipped"].append(f"{problem}.")
            continue

        body = repo.body(number)
        parsed = issue_dependencies.parse(body)

        if not parsed["declared"]:
            report["undeclared"].append(number)

        for row in parsed["malformed"]:
            report["malformed"].append(f"#{number}: `{row}`")

        for pair in issue_dependencies.edges(number, body):
            if pair not in edges:
                edges.append(pair)

    return edges


def realize(repo: Repository, edges, report: dict) -> None:
    """Create every declared edge that does not exist yet."""
    for blocked, blocker in edges:
        label = f"#{blocked} blocked by #{blocker}"

        problem = repo.check(blocked) or repo.check(blocker)
        if problem:
            report["skipped"].append(f"{label}: {problem}.")
            continue

        try:
            existing = repo.blocked_by(blocked)
        except GhError as error:
            report["failed"].append(f"{label}: {error}")
            continue

        if blocker in existing:
            report["already"].append(label)
        else:
            # A 2-cycle is the one cycle visible without walking the graph,
            # and it is the one a mis-typed table actually produces -- two
            # Issues each claiming to block the other. Deeper cycles are left
            # to the API, which rejects them; that rejection is reported like
            # any other failure.
            try:
                if blocked in repo.blocked_by(blocker):
                    report["failed"].append(
                        f"{label}: refused, #{blocker} is already blocked by "
                        f"#{blocked}. One of the two tables has the "
                        f"relationship backwards."
                    )
                    continue
            except GhError:
                pass

            try:
                repo.add_blocked_by(blocked, blocker)
                report["created"].append(label)
            except GhError as error:
                report["failed"].append(f"{label}: {error}")
                continue

        # The label follows the edge, not the table: an Issue earns `blocker`
        # by actually blocking something, so it is applied once the
        # relationship exists rather than on the strength of a row that might
        # still fail to create.
        if repo.add_blocker_label(blocker):
            report["labelled"].append(blocker)


def report_drift(repo: Repository, edges, numbers, report: dict) -> None:
    """Note dependencies GitHub has that no table declares.

    Only meaningful over a full sweep. Reading one Issue tells you nothing
    about whether some *other* Issue's table declares the edge, so a
    single-Issue run would report every edge the rest of the repository owns
    as drift.
    """
    declared = {(blocked, blocker) for blocked, blocker in edges}

    for number in numbers:
        try:
            existing = repo.blocked_by(number)
        except GhError:
            continue

        for blocker in existing:
            if (number, blocker) not in declared:
                report["drift"].append(
                    f"#{number} is blocked by #{blocker} in GitHub, but "
                    f"neither Issue's table says so. Nothing was removed."
                )


def render(report: dict) -> str:
    """Markdown for the Actions job summary and for stdout."""
    lines = ["### Issue dependency sync", ""]

    sections = [
        ("Created", "created"),
        ("Already wired", "already"),
        ("Labelled `blocker`", "labelled"),
        ("Failed", "failed"),
        ("Skipped", "skipped"),
        ("Rows naming no Issue", "malformed"),
        ("Undeclared dependencies", "drift"),
    ]

    wrote_any = False

    for title, key in sections:
        entries = report.get(key) or []
        if not entries:
            continue
        wrote_any = True
        lines.append(f"**{title}**")
        lines.append("")
        for entry in entries:
            if key == "labelled":
                entry = f"#{entry}"
            lines.append(f"- {entry}")
        lines.append("")

    if not wrote_any:
        lines.append("No declared dependencies to wire.")
        lines.append("")

    for note in report.get("notes") or []:
        lines.append(note)
        lines.append("")

    if report.get("undeclared"):
        lines.append(
            "Issues with no `## Dependencies` section (filed before the "
            "standard, or without a template): "
            + ", ".join(f"#{number}" for number in report["undeclared"])
        )
        lines.append("")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Create GitHub issue dependencies from the `## Dependencies` "
            "tables in Issue bodies."
        )
    )
    parser.add_argument(
        "--repo",
        default=os.environ.get("GITHUB_REPOSITORY"),
        help="owner/name. Defaults to $GITHUB_REPOSITORY.",
    )
    parser.add_argument(
        "--issue",
        type=int,
        action="append",
        default=[],
        dest="issues",
        help="An Issue whose table should be realized. Repeatable.",
    )
    parser.add_argument(
        "--sweep",
        action="store_true",
        help=(
            "Read every open Issue rather than named ones. The repair mode: "
            "also reports dependencies GitHub has that no table declares."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what would change without writing anything.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="as_json",
        help="Emit the machine-readable report instead of markdown.",
    )
    args = parser.parse_args()

    if not args.repo:
        parser.error("--repo is required when $GITHUB_REPOSITORY is unset")

    if not args.issues and not args.sweep:
        parser.error("pass --issue at least once, or --sweep")

    repo = Repository(args.repo, dry_run=args.dry_run)

    report = {
        "created": [],
        "already": [],
        "labelled": [],
        "failed": [],
        "skipped": [],
        "malformed": [],
        "drift": [],
        "undeclared": [],
        "notes": [],
    }

    bulk_graph = False

    if args.sweep:
        numbers = repo.load_open_issues()
        bulk_graph = repo.prime_blocked_by()
        # Named Issues are still honoured alongside a sweep so that a closed
        # Issue can be re-wired explicitly; the sweep only sees open ones.
        for number in args.issues:
            if number not in numbers:
                numbers.append(number)
    else:
        numbers = list(dict.fromkeys(args.issues))

    repo.ensure_blocker_label_exists()

    edges = collect_edges(repo, numbers, report)
    realize(repo, edges, report)

    if args.sweep and bulk_graph:
        report_drift(repo, edges, numbers, report)
    elif args.sweep:
        report["notes"].append(
            "Drift was not checked: reading the whole blocked-by graph needs "
            "GitHub CLI 2.94.0 or newer. Every declared dependency above was "
            "still wired."
        )

    # The rendered markdown rides along in the JSON so a caller that wants
    # both -- the workflow needs the prose for its job summary and the lists
    # to decide whether a human has to be told -- gets them from one run.
    # Running twice would ask GitHub the same questions again and could report
    # a different answer the second time.
    report["markdown"] = render(report)
    report["needs_attention"] = bool(
        report["failed"] or report["malformed"] or report["skipped"]
    )

    if args.as_json:
        json.dump(report, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(report["markdown"])

    # A failure to create a declared edge is the thing this script exists to
    # prevent, so it exits non-zero and the workflow step goes red. Skipped
    # and malformed rows do not: those are the table being wrong, which is
    # answered by editing the Issue, not by re-running the job.
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
