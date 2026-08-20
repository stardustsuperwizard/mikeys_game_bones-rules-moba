# rules/tests/

GDScript unit and contract tests for the ruleset. Run headless via
`.github/scripts/validate-godot.sh`. The extraction contract test here verifies that no
file under `rules/` references game-layer paths forbidden by the module boundary.
