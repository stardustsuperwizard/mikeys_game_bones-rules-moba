#!/usr/bin/env bash
# Regression check for the exit-code contract of validate-godot.sh.
#
# Issue #196: a headless run that aborted partway through tests/test_bootstrap.gd
# still exited 0, so validate-godot.sh reported success having run only some of
# the suites -- a green check that meant nothing. This script pins the four
# outcomes that contract now has to produce.
#
# The defect lives in the harness, not in ruleset logic, so it cannot be a
# rules/tests/*.gd suite: the whole point is what happens when a suite never
# runs. Instead each case copies the project to a temporary directory, breaks
# the copy, and runs validate-godot.sh against it end to end. The repository's
# own files are never modified.
#
# Usage: .github/scripts/test-validate-truncation.sh
#
# Requires `godot` on PATH, or GODOT_BIN pointing at the binary.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"

if ! command -v "$godot_bin" >/dev/null 2>&1; then
  echo "Godot binary not found: $godot_bin" >&2
  echo "Install Godot 4 or set GODOT_BIN to its path." >&2
  exit 127
fi

# The suite the parent Issue used to reproduce the abort. Mid-list, so breaking
# it leaves suites on both sides of the failure.
victim="rules/tests/cooldown_test.gd"
if [ ! -f "$repo_root/$victim" ]; then
  echo "Fixture suite missing: $victim" >&2
  echo "Update this script to point at a suite that still exists." >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

failures=0

# Copy the working tree into a scratch project. .git is skipped (large, and
# irrelevant to a headless run); .godot is kept so the import pass is warm.
make_project() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest"
  (cd "$repo_root" && tar --exclude=.git -cf - .) | (cd "$dest" && tar -xf -)
}

# Run one case: break the copy, run validation, check exit code and output.
#
#   $1 case name
#   $2 expected exit: "zero" or "nonzero"
#   $3 extended regex the output must contain
#   $4 shell snippet that breaks the project (cwd is the copy; empty = leave it)
run_case() {
  local name="$1" expect="$2" want_re="$3" break_cmd="$4"
  local project="$work_dir/$name" log="$work_dir/$name.log"

  make_project "$project"
  if [ -n "$break_cmd" ]; then
    (cd "$project" && eval "$break_cmd")
  fi

  local status=0
  "$repo_root/.github/scripts/validate-godot.sh" "$project" >"$log" 2>&1 || status=$?

  local ok=1
  case "$expect" in
    zero) [ "$status" -eq 0 ] || ok=0 ;;
    nonzero) [ "$status" -ne 0 ] || ok=0 ;;
  esac
  if [ "$ok" -eq 1 ] && ! grep -Eq "$want_re" "$log"; then
    ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    echo "PASS $name (exit $status)"
  else
    echo "FAIL $name (exit $status, expected $expect matching /$want_re/)" >&2
    echo "--- tail of $log ---" >&2
    tail -20 "$log" >&2 || true
    echo "--- end ---" >&2
    failures=$((failures + 1))
  fi
}

# 1. The baseline still has to pass, or the other three prove nothing.
run_case "full-pass" zero 'All [0-9]+ test suites passed\.' ""

# 2. Issue #196's repro: a suite that fails to compile. Referencing its class
#    then aborts _ready(), so every later suite is skipped. The run must fail
#    and must name the suites that never ran, not just report a generic error.
run_case "compile-abort" nonzero '[0-9]+ of [0-9]+ test suites never ran:.*Cooldown Test' \
  "printf '\nconst RegressionGhost = preload(\"res://rules/core/does_not_exist.gd\")\n' >> $victim"

# 3. A runtime error inside a suite's run(). Godot unwinds to the caller rather
#    than tearing down _ready(), so this lands as a FAIL rather than a
#    truncation -- either way the contract is that it cannot exit 0.
run_case "runtime-error" nonzero 'test suites (FAILED|never ran):.*Cooldown Test' \
  "awk '/^static func run\(\) -> bool:/ && !done { print; print \"\tvar regression_nil: Node = null\"; print \"\tregression_nil.get_name()\"; done=1; next } { print }' $victim > $victim.tmp && mv $victim.tmp $victim"

# 4. The bootstrap autoload itself failing to compile. None of its code runs, so
#    it cannot self-report; validate-godot.sh catches this one by requiring the
#    completion line before it trusts a zero exit.
run_case "bootstrap-broken" nonzero 'exited 0 but ran no test suites' \
  "printf '\nfunc _regression_broken() -> void:\n\tthis is not valid gdscript\n' >> tests/test_bootstrap.gd"

# 5. The expected list drifting out of sync with the _check() calls. An unlisted
#    suite would push the actual count past the expected one and switch
#    truncation detection off, so the bootstrap reports the drift as a failure.
run_case "list-drift" nonzero 'HUD Test ran but is not in _expected_suites' \
  "grep -v '^\t\"HUD Test\",$' tests/test_bootstrap.gd > tests/tb.tmp && mv tests/tb.tmp tests/test_bootstrap.gd"

echo
if [ "$failures" -ne 0 ]; then
  echo "$failures of 5 exit-code regression cases FAILED." >&2
  exit 1
fi
echo "All 5 exit-code regression cases passed."
