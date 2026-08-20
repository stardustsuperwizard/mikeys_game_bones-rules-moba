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
  if ! "$godot_bin" --headless --path "$project_path" "$@" --log-file "$log"; then
    local status=$?
    echo "Godot ${label} failed."
    cat "$log" || true
    exit "$status"
  fi
}

# Pass 1: import — resources and scenes resolve.
run_pass "import pass" "$log_dir/godot-import.log" --import

# Pass 2: boot and quit — scripts parse and autoloads initialize.
run_pass "headless validation" "$log_dir/godot-headless.log" --quit

echo "Godot headless validation passed."
