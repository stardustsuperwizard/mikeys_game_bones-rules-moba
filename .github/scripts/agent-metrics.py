#!/usr/bin/env python3
"""Agent session metrics for Sword and Planet.

Computes the Tier A metrics described in docs/AGENT_WORKFLOW.md from merged
pull requests, using `gh`. No permissions beyond normal repo read, and no
third-party dependencies.

The question these metrics answer is not "which model is cheapest per token"
but "which model is cheapest per *merged task*, once rework is counted."

Usage:
    .github/scripts/agent-metrics.py                 # last 30 merged PRs
    .github/scripts/agent-metrics.py --limit 100
    .github/scripts/agent-metrics.py --since 2026-08-01
    .github/scripts/agent-metrics.py --json          # machine-readable

Requires `gh` authenticated against the repository.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import sys
from datetime import datetime, timedelta, timezone

PR_FIELDS = [
    "number", "title", "body", "createdAt", "mergedAt", "url",
    "additions", "deletions", "changedFiles", "files", "commits",
    "closingIssuesReferences", "author",
]

VERDICTS = ["PASS", "FIX", "PLANNING FAILURE", "DESIGN AMBIGUITY"]

# Tier B fields recorded by hand in the PR template.
METADATA_FIELDS = {
    "implementation_model": "Implementation model",
    "review_model": "Review model",
    "reasoning_level": "Reasoning level",
    "rework_cycles": "Rework cycles",
    "steering_messages": "Steering messages",
    "session_wall_clock": "Session wall-clock",
}

UNSET = re.compile(r"^\s*(<[^>]*>|n/?a|none|tbd|-{1,2}|_+)?\s*$", re.I)


def run_gh(args: list[str]) -> str:
    try:
        proc = subprocess.run(
            ["gh", *args], capture_output=True, text=True, check=True
        )
    except FileNotFoundError:
        sys.exit("gh not found on PATH. Install the GitHub CLI.")
    except subprocess.CalledProcessError as exc:
        sys.exit(f"gh {' '.join(args)} failed:\n{exc.stderr.strip()}")
    return proc.stdout


def parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def clean(value: str | None) -> str | None:
    """Return the value, or None if it is an unfilled template placeholder."""
    if value is None:
        return None
    value = value.strip().strip("`")
    return None if UNSET.match(value) else value


def section(body: str, heading: str) -> str:
    """Return the text under a markdown heading, up to the next heading."""
    pattern = rf"^#{{1,6}}\s*{re.escape(heading)}\s*$(.*?)(?=^#{{1,6}}\s|\Z)"
    match = re.search(pattern, body or "", re.M | re.S | re.I)
    return match.group(1) if match else ""


def strip_comments(text: str) -> str:
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


def extract_paths(text: str) -> set[str]:
    """Pull backticked file paths out of a markdown block."""
    paths = set()
    for token in re.findall(r"`([^`\n]+)`", strip_comments(text)):
        token = token.strip()
        if "/" in token or re.search(r"\.\w+$", token):
            paths.add(token.lstrip("./"))
    return paths


def extract_metadata(body: str) -> dict[str, str | None]:
    """Read the Agent Session Metadata bullets from the PR body."""
    text = strip_comments(body or "")
    found: dict[str, str | None] = {}
    for key, label in METADATA_FIELDS.items():
        match = re.search(rf"^\s*[-*]\s*{re.escape(label)}\s*:(.*)$", text, re.M | re.I)
        found[key] = clean(match.group(1)) if match else None
    return found


def extract_verdict(body: str) -> str | None:
    text = strip_comments(body or "")
    match = re.search(r"^\s*VERDICT\s*:(.*)$", text, re.M | re.I)
    if not match:
        return None
    value = (clean(match.group(1)) or "").upper()
    for verdict in sorted(VERDICTS, key=len, reverse=True):
        if value.startswith(verdict):
            return verdict
    return None


def as_int(value: str | None) -> int | None:
    if value is None:
        return None
    match = re.search(r"-?\d+", value)
    return int(match.group()) if match else None


def fetch_prs(limit: int, since: datetime | None) -> list[dict]:
    raw = run_gh([
        "pr", "list", "--state", "merged", "--limit", str(limit),
        "--json", ",".join(PR_FIELDS),
    ])
    prs = json.loads(raw)
    if since:
        prs = [p for p in prs if (parse_ts(p.get("mergedAt")) or since) >= since]
    prs.sort(key=lambda p: p["number"])
    return prs


def fetch_issue_body(number: int) -> str:
    try:
        raw = run_gh(["issue", "view", str(number), "--json", "body"])
    except SystemExit:
        return ""
    return json.loads(raw).get("body") or ""


def first_push_ci(pr: dict) -> str:
    """Conclusion of checks on the PR's first commit.

    Distinguishes "the implementer validated before opening the PR" from
    "CI caught it afterwards". NO_CHECKS means CI never ran on that commit.
    """
    commits = pr.get("commits") or []
    if not commits:
        return "UNKNOWN"
    sha = commits[0].get("oid")
    if not sha:
        return "UNKNOWN"
    try:
        raw = run_gh([
            "api", f"repos/{{owner}}/{{repo}}/commits/{sha}/check-runs",
            "--jq", "[.check_runs[] | {name, conclusion}]",
        ])
    except SystemExit:
        return "UNKNOWN"
    runs = json.loads(raw or "[]")
    if not runs:
        return "NO_CHECKS"
    conclusions = {r.get("conclusion") for r in runs}
    if conclusions <= {"success", "skipped", "neutral"}:
        return "PASS"
    if None in conclusions:
        return "PENDING"
    return "FAIL"


def scope_adherence(pr: dict) -> dict | None:
    """Compare files actually changed against the linked Issue's expectation."""
    refs = pr.get("closingIssuesReferences") or []
    if not refs:
        return None
    expected: set[str] = set()
    for ref in refs:
        body = fetch_issue_body(ref["number"])
        expected |= extract_paths(section(body, "Files Expected to Change"))
    if not expected:
        return None
    changed = {f["path"] for f in (pr.get("files") or [])}
    unexpected = sorted(changed - expected)
    untouched = sorted(expected - changed)
    return {
        "expected": sorted(expected),
        "changed": sorted(changed),
        "unexpected": unexpected,
        "untouched": untouched,
        "adherence": (len(changed) - len(unexpected)) / len(changed) if changed else None,
    }


def post_merge_fixes(prs: list[dict], window_days: int) -> dict[int, list[dict]]:
    """Later PRs that touch the same files within the window.

    A PASS that needs repair days later means review was too cheap. This is
    the metric rework-cycle counting inside a single PR cannot see.

    Overlap is a heuristic, not proof of a defect: churn-prone hub files
    (README, project.godot) make unrelated PRs look like fixes. The shared
    paths are reported so a human can dismiss the noise.
    """
    fixes: dict[int, list[dict]] = {}
    for pr in prs:
        merged = parse_ts(pr.get("mergedAt"))
        files = {f["path"] for f in (pr.get("files") or [])}
        if not merged or not files:
            fixes[pr["number"]] = []
            continue
        deadline = merged + timedelta(days=window_days)
        later = []
        for other in prs:
            if other["number"] == pr["number"]:
                continue
            other_merged = parse_ts(other.get("mergedAt"))
            if not other_merged or not (merged < other_merged <= deadline):
                continue
            shared = files & {f["path"] for f in (other.get("files") or [])}
            if shared:
                later.append({"pr": other["number"], "shared_files": sorted(shared)})
        fixes[pr["number"]] = sorted(later, key=lambda f: f["pr"])
    return fixes


def build_rows(prs: list[dict], window_days: int) -> list[dict]:
    fixes = post_merge_fixes(prs, window_days)
    rows = []
    for pr in prs:
        meta = extract_metadata(pr.get("body", ""))
        scope = scope_adherence(pr)
        created, merged = parse_ts(pr.get("createdAt")), parse_ts(pr.get("mergedAt"))
        rows.append({
            "number": pr["number"],
            "title": pr["title"],
            "url": pr["url"],
            "author": (pr.get("author") or {}).get("login"),
            "merged_at": pr.get("mergedAt"),
            "hours_to_merge": round((merged - created).total_seconds() / 3600, 1)
            if created and merged else None,
            "additions": pr.get("additions"),
            "deletions": pr.get("deletions"),
            "changed_files": pr.get("changedFiles"),
            "diff_size": (pr.get("additions") or 0) + (pr.get("deletions") or 0),
            "commits": len(pr.get("commits") or []),
            "verdict": extract_verdict(pr.get("body", "")),
            "first_push_ci": first_push_ci(pr),
            "scope": scope,
            "post_merge_fixes": fixes.get(pr["number"], []),
            "linked_issues": [r["number"] for r in (pr.get("closingIssuesReferences") or [])],
            **meta,
            "rework_cycles_n": as_int(meta.get("rework_cycles")),
            "steering_messages_n": as_int(meta.get("steering_messages")),
        })
    return rows


def summarize(rows: list[dict], window_days: int) -> dict:
    total = len(rows)
    verdicts = {v: sum(1 for r in rows if r["verdict"] == v) for v in VERDICTS}
    verdicts["unrecorded"] = sum(1 for r in rows if r["verdict"] is None)

    scoped = [r for r in rows if r["scope"]]
    diffs = [r["diff_size"] for r in rows if r["diff_size"] is not None]
    hours = [r["hours_to_merge"] for r in rows if r["hours_to_merge"] is not None]
    rework = [r["rework_cycles_n"] for r in rows if r["rework_cycles_n"] is not None]
    steering = [r["steering_messages_n"] for r in rows if r["steering_messages_n"] is not None]

    by_model: dict[str, dict] = {}
    for row in rows:
        model = row.get("implementation_model") or "unrecorded"
        entry = by_model.setdefault(model, {"prs": 0, "rework": [], "fixed": 0, "off_scope": 0})
        entry["prs"] += 1
        if row["rework_cycles_n"] is not None:
            entry["rework"].append(row["rework_cycles_n"])
        if row["post_merge_fixes"]:
            entry["fixed"] += 1
        if row["scope"] and row["scope"]["unexpected"]:
            entry["off_scope"] += 1

    return {
        "pull_requests": total,
        "window_days": window_days,
        "verdicts": verdicts,
        "scope_checked": len(scoped),
        "scope_violations": sum(1 for r in scoped if r["scope"]["unexpected"]),
        "first_push_ci": {
            k: sum(1 for r in rows if r["first_push_ci"] == k)
            for k in ("PASS", "FAIL", "NO_CHECKS", "PENDING", "UNKNOWN")
        },
        "post_merge_fix_rate": round(
            sum(1 for r in rows if r["post_merge_fixes"]) / total, 3) if total else None,
        "median_diff_size": statistics.median(diffs) if diffs else None,
        "median_hours_to_merge": round(statistics.median(hours), 1) if hours else None,
        "median_rework_cycles": statistics.median(rework) if rework else None,
        "total_steering_messages": sum(steering) if steering else None,
        "metadata_coverage": round(
            sum(1 for r in rows if r.get("implementation_model")) / total, 3) if total else None,
        "by_implementation_model": {
            m: {
                "prs": e["prs"],
                "median_rework": statistics.median(e["rework"]) if e["rework"] else None,
                "post_merge_fix_rate": round(e["fixed"] / e["prs"], 3),
                "off_scope_rate": round(e["off_scope"] / e["prs"], 3),
            }
            for m, e in sorted(by_model.items())
        },
    }


def fmt(value, dash: str = "—") -> str:
    return dash if value is None else str(value)


def render(rows: list[dict], summary: dict) -> str:
    out: list[str] = ["# Agent Session Metrics", ""]
    if not rows:
        out += ["No merged pull requests in range.", ""]
        return "\n".join(out)

    out += [
        f"{summary['pull_requests']} merged pull requests. "
        f"Post-merge window: {summary['window_days']} days.",
        "",
        "## Per pull request",
        "",
        "| PR | Verdict | 1st-push CI | Files | Diff | Off-scope | Rework | Steer | Fixed after | Impl model |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for r in rows:
        scope = r["scope"]
        off = fmt(len(scope["unexpected"]) if scope else None)
        fixed = ", ".join(f"#{f['pr']}" for f in r["post_merge_fixes"]) or "—"
        out.append(
            f"| [#{r['number']}]({r['url']}) | {fmt(r['verdict'])} | {r['first_push_ci']} | "
            f"{fmt(r['changed_files'])} | {fmt(r['diff_size'])} | {off} | "
            f"{fmt(r['rework_cycles_n'])} | {fmt(r['steering_messages_n'])} | {fixed} | "
            f"{fmt(r.get('implementation_model'))} |"
        )

    out += ["", "## Summary", ""]
    v = summary["verdicts"]
    out += [
        f"- Verdicts — PASS {v['PASS']}, FIX {v['FIX']}, "
        f"PLANNING FAILURE {v['PLANNING FAILURE']}, "
        f"DESIGN AMBIGUITY {v['DESIGN AMBIGUITY']}, unrecorded {v['unrecorded']}",
        f"- Scope: {summary['scope_violations']} of {summary['scope_checked']} "
        f"checked PRs touched files the Issue did not list",
        f"- First-push CI: " + ", ".join(
            f"{k} {n}" for k, n in summary["first_push_ci"].items() if n),
        f"- Post-merge fix rate: {fmt(summary['post_merge_fix_rate'])}",
        f"- Median diff size: {fmt(summary['median_diff_size'])} lines",
        f"- Median hours to merge: {fmt(summary['median_hours_to_merge'])}",
        f"- Median rework cycles: {fmt(summary['median_rework_cycles'])}",
        f"- Total steering messages: {fmt(summary['total_steering_messages'])}",
        f"- Metadata coverage: {fmt(summary['metadata_coverage'])}",
        "",
        "## By implementation model",
        "",
        "| Model | PRs | Median rework | Post-merge fix rate | Off-scope rate |",
        "| --- | --- | --- | --- | --- |",
    ]
    for model, e in summary["by_implementation_model"].items():
        out.append(
            f"| {model} | {e['prs']} | {fmt(e['median_rework'])} | "
            f"{e['post_merge_fix_rate']} | {e['off_scope_rate']} |"
        )

    out += [
        "",
        "> A cheap model is only cheaper if median rework, post-merge fix rate,",
        "> and off-scope rate hold. Compare rows before changing model routing.",
        "",
    ]

    unrecorded = summary["verdicts"]["unrecorded"]
    if unrecorded:
        out += [
            f"**{unrecorded} PR(s) have no VERDICT recorded.** Rows without PR-template",
            "metadata are counted but cannot be attributed to a model.",
            "",
        ]
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--limit", type=int, default=30, help="merged PRs to examine (default 30)")
    ap.add_argument("--since", help="only PRs merged on or after this date (YYYY-MM-DD)")
    ap.add_argument("--window-days", type=int, default=14,
                    help="post-merge fix detection window (default 14)")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of markdown")
    args = ap.parse_args()

    since = None
    if args.since:
        try:
            since = datetime.strptime(args.since, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        except ValueError:
            sys.exit("--since must be YYYY-MM-DD")

    prs = fetch_prs(args.limit, since)
    rows = build_rows(prs, args.window_days)
    summary = summarize(rows, args.window_days)

    if args.json:
        print(json.dumps({"summary": summary, "pull_requests": rows}, indent=2))
    else:
        print(render(rows, summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
