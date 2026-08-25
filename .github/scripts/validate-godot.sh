#!/usr/bin/env bash
# Godot headless validation for Sword and Planet.
#
# Single source of truth for "run the repository validation". CI and agents
# both call this so a passing local run means the same thing as a passing
# CI run.
#
# Usage: .github/scripts/validate-godot.sh [project-path]
#
# Requires `godot` on PATH, or GODOT_BIN pointing at the binary.

set -euo pipefail

project_path="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
godot_bin="${GODOT_BIN:-godot}"
log_dir="${RUNNER_TEMP:-$(mktemp -d)}"

if ! command -v "$godot_bin" >/dev/null 2>&1; then
  echo "Godot binary not found: $godot_bin" >&2
  echo "Install Godot 4 or set GODOT_BIN to its path." >&2
  echo "Validation could not be performed." >&2
  exit 127
fi

"$godot_bin" --version

run_pass() {
  local label="$1" log="$2"
  shift 2

  # Capture the status with `|| status=$?`, not inside `if ! cmd; then`.
  # After a negated command `$?` is the status of the negation -- always 0 --
  # so the previous form reported the failure and then exited 0, and a Godot
  # pass that returned 1 still produced a green build.
  local status=0
  "$godot_bin" --headless --path "$project_path" "$@" --log-file "$log" || status=$?

  if [ "$status" -ne 0 ]; then
    echo "Godot ${label} failed (exit ${status})."
    cat "$log" || true
    exit "$status"
  fi
}

# Pass 1: import — resources and scenes resolve.
run_pass "import pass" "$log_dir/godot-import.log" --import

# Pass 2: boot and quit — scripts parse and autoloads initialize.
run_pass "headless validation" "$log_dir/godot-headless.log" --quit

# A zero exit is not by itself proof the suites ran. tests/test_bootstrap.gd
# makes a truncated run non-zero, but it cannot cover the case where the
# bootstrap autoload never loads at all -- if that script fails to compile,
# none of its code runs, Godot still boots and quits cleanly, and this pass
# returns 0 having executed no suite whatsoever. Require the completion line
# the bootstrap prints on a full pass before believing the zero.
if ! grep -Eq 'All [0-9]+ test suites passed\.' "$log_dir/godot-headless.log"; then
  echo "Godot headless validation exited 0 but ran no test suites." >&2
  echo "The test bootstrap autoload most likely failed to load. Full log:" >&2
  cat "$log_dir/godot-headless.log" >&2 || true
  exit 1
fi

echo "Godot headless validation passed."
