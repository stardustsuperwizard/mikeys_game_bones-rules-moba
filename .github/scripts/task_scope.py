#!/usr/bin/env python3
"""Read an Implementation Task Issue's declared scope, and decide who can run it.

An Implementation Task Issue declares the files it expects to change under
`## Files or Subsystems Expected to Change`. Two different questions are asked
of that list, and both are string matching rather than judgment:

- *Is this delicate?* Godot scene and resource serialization punishes small
  mistakes, so a task touching `.tscn`, `.tres`, `project.godot` or `addons/`
  wants a strong model rather than whatever Auto draws. The control plane
  flags it; nothing is blocked.
- *Can a workflow-token push carry this?* Anything under
  `.github/workflows/**` or `.github/actions/**` cannot be pushed by
  `GITHUB_TOKEN`, so the two workflows that push must refuse before paying
  for a session. That is what RESTRICTED_PREFIXES below is for. It is asked
  from two directions: `agent-02-execute.yml` asks it of an Issue's declared
  expected files, before there is any diff to look at (`evaluate`), and
  `agent-05-fix.yml` asks it of a pull request's actual changed files
  (`evaluate_paths`). Intent versus fact -- same prefix list either way.

The second restriction is GitHub's, it is deliberate, and there is no
`permissions:` key that lifts it. Workflow edits require a credential carrying
the `workflow` OAuth scope, specifically so that a compromised workflow cannot
rewrite its own CI. A push that touches those paths with the Actions token is
rejected at the remote:

    ! [remote rejected] HEAD -> agent-exec/168
      (refusing to allow a GitHub App to create or update workflow
       `.github/workflows/godot-ci-validation.yml` without `workflows`
       permission)

The failure is clean but expensive: it lands at the *push*, after a full
executor session has already been paid for and produced a complete
implementation, and it is only diagnosable by reading the run log. #167's
decomposition hit it three times.

Detection is uncertain-means-eligible, on purpose. A task whose expected-files
section is missing, empty, or unparseable is reported eligible, which is the
behaviour that predates this module — a false positive blocks real work, a
false negative costs one session and comments why.

This is the one file in `.github/scripts/` named with an underscore rather
than a hyphen: the others are only ever executed, this one is also imported
(`render-dashboard.py`), and a hyphen is not a legal module name.

Usage:

    task_scope.py --body-file issue-body.md      # JSON to stdout
    gh issue view 168 --json body --jq .body | task_scope.py

    {
      "executor_eligible": false,
      "reason": "workflow_scope",
      "expected_paths": [".github/workflows/agent-02-execute.yml"],
      "restricted_paths": [".github/workflows/agent-02-execute.yml"]
    }

    task_scope.py --paths-file pr-files.txt      # one path per line

    {
      "pushable": false,
      "reason": "workflow_scope",
      "paths": [".github/workflows/agent-05-fix.yml"],
      "restricted_paths": [".github/workflows/agent-05-fix.yml"]
    }

No third-party dependencies, no network, no `gh`.
"""

from __future__ import annotations

import argparse
import json
import re
import sys

EXPECTED_FILES_HEADING = "Files or Subsystems Expected to Change"

# Paths GITHUB_TOKEN cannot write. Keep in step with the prose in
# agent-01-planner.yml's not-executor-eligible run block and
# agent-02-execute.yml's workflow_scope guard message.
RESTRICTED_PREFIXES = (
    ".github/workflows/",
    ".github/actions/",
)

# Paths where a weak or unknown model is a bad bet, but which the executor can
# still push. Advisory only.
DELICATE_SUFFIXES = (".tscn", ".tres")
DELICATE_NAMES = ("project.godot",)
DELICATE_PREFIXES = ("addons/",)


def strip_comments(text: str) -> str:
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


def section(body: str, heading: str) -> str:
    """Return the text under a markdown heading, up to the next heading."""
    pattern = rf"^#{{1,6}}\s*{re.escape(heading)}\s*$(.*?)(?=^#{{1,6}}\s|\Z)"
    match = re.search(pattern, body or "", re.M | re.S | re.I)
    return match.group(1) if match else ""


def normalize(token: str) -> str:
    """Strip a leading `./` or `/` from a path, and nothing else.

    Not `lstrip("./")`: that takes a *character set*, so it eats the leading
    dot of a dotfile directory and turns `.github/workflows/x.yml` into
    `github/workflows/x.yml` -- which no prefix test here would then match.
    Harmless for the delicate check, which has no dotted prefixes; fatal for
    the restricted one, whose every prefix starts with a dot.
    """
    token = token.strip()
    while token.startswith("./"):
        token = token[2:]
    return token.lstrip("/")


def looks_like_path(token: str) -> bool:
    """A token is a path if it has a directory separator or an extension."""
    if not token or " " in token:
        return False
    return "/" in token or bool(re.search(r"\.\w+$", token))


def expected_paths(body: str) -> set[str]:
    """File paths from the task template's expected-changes block.

    Two sources, because real Issues use both:

    - Any backticked token in the section. This is how a hand-written Issue
      and the Issue template's own example write a path.
    - Any bare token on a bullet line. This is how the *planner* writes one.
      Its `expected_files` are plain JSON strings rendered straight into a
      `- ` list, so a generated task's paths carry no backticks at all --
      #168's section is literally `- .github/workflows/godot-validation.yml`.
      A backtick-only reader finds nothing there, which would have let every
      Issue this check exists to catch through untouched.

    Deliberately narrow either way. The section is prose written by a planner
    session, so it also contains sentences and subsystem names; only tokens
    that look like a path are read as one, and the template's commented
    example paths are stripped first so an untouched template does not report
    the example as real scope.

    The bare-token pass will also read a path out of a bullet that mentions
    one without expecting to change it ("no changes under
    `.github/workflows/`"). Inside a section whose whole job is to declare
    what changes, that reading is the right default, and the cost of being
    wrong is a refusal comment naming the path -- visible, and answered by
    editing the section.
    """
    text = strip_comments(section(body, EXPECTED_FILES_HEADING))
    paths = set()

    for token in re.findall(r"`([^`\n]+)`", text):
        if looks_like_path(token.strip()):
            paths.add(normalize(token))

    for line in text.splitlines():
        item = re.match(r"\s*(?:[-*+]|\d+[.)])\s+(.*)", line)
        if not item:
            continue
        for token in item.group(1).split():
            token = token.strip("`")

            # A matched emphasis wrapper is markup; a trailing `*` that is
            # not one is a glob, and `.github/workflows/**` has to survive
            # intact or it is counted twice -- once whole from the backtick
            # pass, once shortened here.
            emphasis = re.fullmatch(
                r"\*\*(.+)\*\*|\*(.+)\*|_(.+)_", token
            )
            if emphasis:
                token = next(
                    group for group in emphasis.groups()
                    if group is not None
                )

            token = token.strip(",;:()[]<>\"'").rstrip(".")
            if looks_like_path(token):
                paths.add(normalize(token))

    return paths


def is_delicate(paths: set[str]) -> bool:
    return any(
        path.endswith(DELICATE_SUFFIXES)
        or path.split("/")[-1] in DELICATE_NAMES
        or path.startswith(DELICATE_PREFIXES)
        for path in paths
    )


def restricted_paths(paths: set[str]) -> list[str]:
    """The subset of `paths` GITHUB_TOKEN is not allowed to push.

    A glob in the expected-files list -- `.github/workflows/**` is how the
    planner and the Issue templates usually write it -- matches by prefix like
    any other path, because the prefix is all that is tested.
    """
    return sorted(
        path for path in paths
        if path.startswith(RESTRICTED_PREFIXES)
    )


def evaluate(body: str) -> dict:
    """Decide whether `agent-02-execute.yml` can run this Issue.

    `reason` is empty when eligible, so a caller can branch on either field.
    """
    paths = expected_paths(body)
    restricted = restricted_paths(paths)
    return {
        "executor_eligible": not restricted,
        "reason": "workflow_scope" if restricted else "",
        "expected_paths": sorted(paths),
        "restricted_paths": restricted,
        "delicate": is_delicate(paths),
    }


def evaluate_paths(paths) -> dict:
    """Decide whether a workflow-token push can carry these paths.

    The companion to `evaluate()`, for the caller that has a *diff* rather
    than an Issue. `agent-02-execute.yml` asks about a task's declared
    expected files, which are a statement of intent and can be wrong or
    missing; `agent-05-fix.yml` asks about a pull request's actual changed
    files, which are exactly what its push will carry. Same restriction, same
    prefix list, different question -- hence `pushable` rather than
    `executor_eligible`.

    No parsing here: these arrive as literal paths from
    `gh pr view --json files`, not quoted out of prose. They are still
    normalized, so a leading `./` from any other caller cannot slip a
    restricted path past the prefix test.
    """
    normalized = {normalize(path) for path in paths if path.strip()}
    restricted = restricted_paths(normalized)
    return {
        "pushable": not restricted,
        "reason": "workflow_scope" if restricted else "",
        "paths": sorted(normalized),
        "restricted_paths": restricted,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Report an Implementation Task Issue's expected paths and "
            "whether the scripted executor can run it."
        )
    )
    source = parser.add_mutually_exclusive_group()
    source.add_argument(
        "--body-file",
        help="File holding the Issue body. Defaults to reading stdin.",
    )
    source.add_argument(
        "--paths-file",
        help=(
            "File holding one changed path per line, as from "
            "`gh pr view --json files`. Reports pushability instead of "
            "executor eligibility."
        ),
    )
    args = parser.parse_args()

    if args.paths_file:
        with open(args.paths_file, encoding="utf-8") as handle:
            result = evaluate_paths(handle.read().splitlines())
    elif args.body_file:
        with open(args.body_file, encoding="utf-8") as handle:
            result = evaluate(handle.read())
    else:
        result = evaluate(sys.stdin.read())

    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
