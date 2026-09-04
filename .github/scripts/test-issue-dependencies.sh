#!/usr/bin/env bash
# Regression check for the dependency-table contract.
#
# Two things are pinned here, and both are things that fail silently when they
# break -- which is how the dependency chain went missing in the first place:
#
#   1. `issue_dependencies.py` reads exactly the rows the templates write, and
#      does not invent edges out of prose. A parser that quietly stops
#      recognizing `| Blocked by | #12 |` produces a clean, green, empty sync.
#   2. `sync-issue-dependencies.py` turns those rows into the right `gh` calls:
#      one POST per undeclared edge, none for an edge that already exists, the
#      `blocker` label on the blocking end, and a non-zero exit when a declared
#      edge could not be created.
#
# The second half runs against a stub `gh` written into a temp directory, so
# the whole script needs nothing but python3 -- no network, no credentials, no
# GitHub CLI, and it never touches a real repository.
#
# Usage: .github/scripts/test-issue-dependencies.sh

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scripts="$repo_root/.github/scripts"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

failures=0

pass() { echo "  ok   — $1"; }
fail() { echo "  FAIL — $1" >&2; failures=$((failures + 1)); }

# ---------------------------------------------------------------------------
# Part 1: the parser.
# ---------------------------------------------------------------------------

echo "Parsing the canonical table"

# Each case is a body plus the JSON its parse is required to produce. Written
# as one python run rather than one per case so a syntax error in the module
# reports once instead of nine times.
if python3 - "$scripts" <<'PY'
import json
import sys

sys.path.insert(0, sys.argv[1])
import issue_dependencies as dep

CASES = [
    (
        "canonical table",
        """## Dependencies

<!-- | Blocks | #999 | the template's own example must not count | -->

| Relationship | Issue | Why |
| --- | --- | --- |
| Blocked by | #12 | Needs the effect container API |
| Blocks | #34 | #34 consumes the resolver |

## Out of Scope

| Blocks | #77 | a table in another section |
""",
        {"blocked_by": [12], "blocks": [34], "declared": True, "malformed": []},
    ),
    (
        "explicit none",
        "## Dependencies\n\n| Relationship | Issue | Why |\n"
        "| --- | --- | --- |\n| None | — | — |\n",
        {"blocked_by": [], "blocks": [], "declared": True, "malformed": []},
    ),
    (
        "no section at all",
        "## Scope\n\nA body written by hand against no template.\n",
        {"blocked_by": [], "blocks": [], "declared": False, "malformed": []},
    ),
    (
        "legacy bullet form",
        "## Dependencies\n\n- Blocked by: #12\n- Blocks: #34, #35\n",
        {
            "blocked_by": [12],
            "blocks": [34, 35],
            "declared": True,
            "malformed": [],
        },
    ),
    (
        "legacy bullet saying none",
        '## Dependencies\n\n- Blocked by: none\n',
        {"blocked_by": [], "blocks": [], "declared": True, "malformed": []},
    ),
    (
        "row naming no issue",
        "## Dependencies\n\n| Blocked by | TBD | nobody looked it up |\n",
        {
            "blocked_by": [],
            "blocks": [],
            "declared": True,
            "malformed": ["Blocked by: TBD"],
        },
    ),
    (
        "url and GH- spellings",
        "## Dependencies\n\n"
        "| Depends on | https://github.com/o/r/issues/44 | pasted tab |\n"
        "| blocking | GH-45 | tooling spelling |\n",
        {"blocked_by": [44], "blocks": [45], "declared": True, "malformed": []},
    ),
    (
        "bare integers are not issue references",
        "## Dependencies\n\n| Blocked by | godot 4.3 | a version, not an issue |\n",
        {
            "blocked_by": [],
            "blocks": [],
            "declared": True,
            "malformed": ["Blocked by: godot 4.3"],
        },
    ),
]

failed = 0

for name, body, expected in CASES:
    actual = dep.parse(body)
    if actual == expected:
        print(f"  ok   — {name}")
    else:
        failed += 1
        print(f"  FAIL — {name}", file=sys.stderr)
        print(f"         expected {expected}", file=sys.stderr)
        print(f"         actual   {actual}", file=sys.stderr)

# Both relationship words collapse to the same (blocked, blocker) edge, and a
# self-edge is dropped rather than reported.
edges = dep.edges(
    100,
    "## Dependencies\n\n| Blocked by | #12 | |\n| Blocks | #34 | |\n"
    "| Blocks | #100 | a typo naming this very issue |\n",
)
if edges == [(100, 12), (34, 100)]:
    print("  ok   — edges collapse both directions and drop self-edges")
else:
    failed += 1
    print(f"  FAIL — edges: {edges}", file=sys.stderr)

# Every writer emits byte-identical markdown, so a re-render is not a diff.
rendered = dep.render_table(blocked_by=[12], blocks=[34], reasons={12: "API"})
if dep.parse(f"## Dependencies\n\n{rendered}\n") == {
    "blocked_by": [12],
    "blocks": [34],
    "declared": True,
    "malformed": [],
}:
    print("  ok   — render_table round-trips through parse")
else:
    failed += 1
    print(f"  FAIL — render_table did not round-trip:\n{rendered}", file=sys.stderr)

sys.exit(1 if failed else 0)
PY
then
  :
else
  failures=$((failures + 1))
fi

# ---------------------------------------------------------------------------
# Part 2: the sync driver, against a stub `gh`.
# ---------------------------------------------------------------------------

echo
echo "Syncing declared edges into dependencies"

mkdir -p "$work_dir/bin"

cat > "$work_dir/bin/gh" <<'STUB'
#!/usr/bin/env python3
"""Stub `gh`, covering only the calls sync-issue-dependencies.py makes.

State is a JSON file so the driver's own idempotence can be tested across two
runs. Anything the driver asks for that is not modelled here exits 2, so a new
call site fails the test rather than passing unnoticed.
"""
import json
import os
import pathlib
import sys

state_path = pathlib.Path(os.environ["GH_STUB_STATE"])
state = json.loads(state_path.read_text())
args = sys.argv[1:]


def emit(obj):
    print(json.dumps(obj))


def save():
    state_path.write_text(json.dumps(state))


if args[:2] == ["label", "list"]:
    if "--jq" in args:
        print("\n".join(state["labels"]))
    else:
        emit([{"name": name} for name in state["labels"]])

elif args[:2] == ["label", "create"]:
    state["labels"].append(args[2])
    save()

elif args[:2] == ["issue", "list"]:
    fields = args[args.index("--json") + 1].split(",")
    rows = []
    for number, issue in sorted(state["issues"].items(), key=lambda kv: int(kv[0])):
        if issue.get("pull_request"):
            continue
        row = {"number": int(number)}
        for field in fields:
            if field == "number":
                continue
            if field == "blockedBy":
                if not state.get("bulk_ok"):
                    print("unknown JSON field: blockedBy", file=sys.stderr)
                    sys.exit(1)
                row["blockedBy"] = {
                    "nodes": [
                        {"number": n} for n in state["deps"].get(number, [])
                    ]
                }
            elif field == "labels":
                row["labels"] = [
                    {"name": name} for name in issue.get("labels", [])
                ]
            else:
                row[field] = issue.get(field, "")
        rows.append(row)
    emit(rows)

elif args[:2] == ["issue", "edit"] and "--add-label" in args:
    label = args[args.index("--add-label") + 1]
    state["issues"][args[2]].setdefault("labels", []).append(label)
    save()

elif args[0] == "api":
    path = next(a for a in args if a.startswith("repos/"))
    number = path.split("/issues/")[1].split("/")[0].split("?")[0]

    if "--method" in args and args[args.index("--method") + 1] == "POST":
        if state.get("post_fails"):
            print("gh: Validation Failed (HTTP 422)", file=sys.stderr)
            sys.exit(1)
        payload = json.loads(sys.stdin.read())
        blocker = next(
            key for key, value in state["issues"].items()
            if value.get("id") == payload["issue_id"]
        )
        state["deps"].setdefault(number, []).append(int(blocker))
        save()
        emit({"ok": True})

    elif "/dependencies/blocked_by" in path:
        emit([{"number": n} for n in state["deps"].get(number, [])])

    else:
        if number not in state["issues"]:
            print("gh: Not Found (HTTP 404)", file=sys.stderr)
            sys.exit(1)
        issue = dict(state["issues"][number])
        issue["number"] = int(number)
        issue["labels"] = [
            {"name": name} for name in issue.get("labels", [])
        ]
        emit(issue)

else:
    print("stub gh: unhandled call: " + " ".join(args), file=sys.stderr)
    sys.exit(2)
STUB

chmod +x "$work_dir/bin/gh"

write_state() {
  cat > "$1" <<'JSON'
{
  "labels": ["implementation", "machine"],
  "bulk_ok": true,
  "deps": {"90": [88]},
  "issues": {
    "12": {"id": 1012, "title": "Effect container API",
           "body": "## Dependencies\n\n| Relationship | Issue | Why |\n| --- | --- | --- |\n| Blocks | #13 | 13 consumes it |\n| Blocks | #14 | so does 14 |\n",
           "labels": []},
    "13": {"id": 1013, "title": "Consumer A",
           "body": "## Dependencies\n\n| Blocked by | #12 | needs the API |\n",
           "labels": []},
    "14": {"id": 1014, "title": "Consumer B",
           "body": "## Dependencies\n\n- Blocked by: #13\n",
           "labels": []},
    "15": {"id": 1015, "title": "Filed by hand", "body": "no section", "labels": []},
    "17": {"id": 1017, "title": "A pull request", "body": "x",
           "pull_request": {"url": "x"}, "labels": []},
    "88": {"id": 1088, "title": "Wired in the UI", "body": "## Dependencies\n\n| None | — | — |\n", "labels": []},
    "90": {"id": 1090, "title": "Blocked in the UI", "body": "## Dependencies\n\n| None | — | — |\n", "labels": []}
  }
}
JSON
}

export PATH="$work_dir/bin:$PATH"

run_sync() {
  local state="$1"
  shift
  GH_STUB_STATE="$state" "$scripts/sync-issue-dependencies.py" --repo o/r "$@"
}

# -- one Issue's table, wired then re-run ------------------------------------

write_state "$work_dir/single.json"

first="$(run_sync "$work_dir/single.json" --issue 12)"

if grep -q "^- #13 blocked by #12$" <<<"$first" \
   && grep -q "^- #14 blocked by #12$" <<<"$first"; then
  pass "both declared edges created from one Blocks table"
else
  fail "expected #13 and #14 to be wired to #12; got:\n$first"
fi

if python3 -c "
import json, sys
state = json.load(open('$work_dir/single.json'))
sys.exit(0 if 'blocker' in state['issues']['12']['labels'] else 1)
"; then
  pass "the blocking Issue was labelled blocker"
else
  fail "#12 should carry the blocker label"
fi

second="$(run_sync "$work_dir/single.json" --issue 12)"

if grep -q "Already wired" <<<"$second" \
   && ! grep -q "^\*\*Created\*\*$" <<<"$second"; then
  pass "re-running creates nothing (idempotent)"
else
  fail "second run should have been a no-op; got:\n$second"
fi

# -- a sweep, including drift and unreadable references ----------------------

write_state "$work_dir/sweep.json"

sweep="$(run_sync "$work_dir/sweep.json" --sweep)"

if grep -q "^- #14 blocked by #13$" <<<"$sweep"; then
  pass "the sweep reads legacy bullet rows too"
else
  fail "sweep missed #14's legacy 'Blocked by: #13' row; got:\n$sweep"
fi

if grep -q "#90 is blocked by #88 in GitHub, but neither Issue's table" <<<"$sweep"; then
  pass "an undeclared dependency is reported, not deleted"
else
  fail "sweep should report the #90/#88 drift; got:\n$sweep"
fi

if python3 -c "
import json, sys
state = json.load(open('$work_dir/sweep.json'))
sys.exit(0 if state['deps'].get('90') == [88] else 1)
"; then
  pass "the undeclared dependency was left in place"
else
  fail "the sweep must never remove a dependency"
fi

if grep -q "no \`## Dependencies\` section" <<<"$sweep" \
   && grep -q "#15" <<<"$sweep"; then
  pass "an Issue with no Dependencies section is reported separately"
else
  fail "sweep should name #15 as undeclared; got:\n$sweep"
fi

# A pull request is never a dependency endpoint. `gh issue list` filters it
# out, so the sweep must simply not mention it.
if ! grep -q "#17" <<<"$sweep"; then
  pass "pull requests are not treated as Issues"
else
  fail "sweep should not have touched pull request #17; got:\n$sweep"
fi

# -- an older gh, with no bulk dependency read -------------------------------

write_state "$work_dir/oldgh.json"
python3 -c "
import json
path = '$work_dir/oldgh.json'
state = json.load(open(path))
state['bulk_ok'] = False
json.dump(state, open(path, 'w'))
"

oldgh="$(run_sync "$work_dir/oldgh.json" --sweep)"

if grep -q "^- #13 blocked by #12$" <<<"$oldgh" \
   && grep -q "Drift was not checked" <<<"$oldgh"; then
  pass "an older gh still wires every edge, and says drift went unchecked"
else
  fail "old-gh fallback wrong; got:\n$oldgh"
fi

# -- a refused write is a red step -------------------------------------------

write_state "$work_dir/failing.json"
python3 -c "
import json
path = '$work_dir/failing.json'
state = json.load(open(path))
state['post_fails'] = True
json.dump(state, open(path, 'w'))
"

if run_sync "$work_dir/failing.json" --issue 12 > "$work_dir/failing.out" 2>&1; then
  fail "a refused dependency write must exit non-zero"
else
  if grep -q "Failed" "$work_dir/failing.out"; then
    pass "a refused dependency write exits non-zero and says why"
  else
    fail "expected a Failed section; got:\n$(cat "$work_dir/failing.out")"
  fi
fi

# -- dry run writes nothing --------------------------------------------------

write_state "$work_dir/dry.json"
before="$(cat "$work_dir/dry.json")"
run_sync "$work_dir/dry.json" --issue 12 --dry-run > /dev/null

if [ "$before" = "$(cat "$work_dir/dry.json")" ]; then
  pass "--dry-run changes nothing"
else
  fail "--dry-run wrote to the repository state"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "All dependency checks passed."
else
  echo "$failures check(s) failed." >&2
fi

exit $((failures > 0))
