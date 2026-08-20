---
applyTo: "sim/**"
---

# Balance harness (`sim/`)

`sim/` is the Python balance harness described in ruleset §20–§51. It exists for the
statistical work GDScript cannot do well: Monte Carlo simulation, build generation across
thousands of loadouts, and property-based testing.

This is a Godot game with a Python harness attached, not a Python project.

## Data

- **The harness reads `rules/data/generated/`**, produced by the Godot-side export tool.
- **Never parse `.tres` in Python.** Godot serializes enums as integers, so a Python-side
  int-to-name map mirroring GDScript enums — with nothing verifying the two agree — would be
  a silent wrong-numbers drift vector. Godot exports; Python consumes.
- **Never copy ability numbers into Python**, and never write into `rules/` except by
  invoking the export tool.
- `rules/data/generated/` is gitignored, so the harness must be able to produce it rather
  than assume it exists. Godot is assumed present wherever these tests run; if it is
  missing, fail loudly rather than skipping or using stale output.

## Combat math

- **`sim/formulas.py` is the only Python home for combat math.** A formula written twice in
  Python is the same drift bug as one written across two languages, only closer together.
- Every function here is a future conformance-suite obligation. Do not add one without a
  test.
- **Document every clamp and rounding decision.** The GDScript side must match it, and an
  unstated decision surfaces later as a confusing conformance failure.

## Determinism

- **Seed everything.** No bare `random`, no dependence on dictionary iteration order, no
  float accumulation that varies with ordering.
- Fixed-step simulation, never variable. The step must match the GDScript side.
- The same seed produces identical results across runs. The conformance suite is worthless
  without this.

## Tests

- **Mark expensive tests `@pytest.mark.deep`.** `--strict-markers` is on. The Fast Suite is
  `-m "not deep"` and runs only on pull requests touching `rules/**` or `sim/**`; the Deep
  Suite runs on a schedule and on manual dispatch.
- **Use balance bands, not exact values** (§25). A test asserting time-to-kill is exactly
  4.7 seconds breaks on every tuning change and teaches everyone to ignore it.
- **Report confidence intervals, not point estimates.** A win rate without a sample size is
  not information (§38).

## General

- Python 3.11 or newer. Dependencies limited to `pytest`, `hypothesis`, `numpy`, and
  `jsonschema`, all pinned.
- Resolve paths from `__file__`, not the working directory — CI and local runs invoke pytest
  from different places.
- **The harness measures; it does not tune.** Humans decide what is fun (§51, §54).
