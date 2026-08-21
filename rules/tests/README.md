# Ruleset Automated Tests

Unit tests, integration tests, and automated regression tests.

## Extraction Contract Test

The **extraction contract test** (`extraction_contract_test.gd`) verifies that the rules module
maintains the strict architectural boundary required for it to be extracted wholesale into
`addons/mikeys_game_rules_moba` without editing a single file.

### What it checks

The test ensures that no files under `rules/` contain outward references to:
- `res://scripts/`
- `res://scenes/`
- `res://resources/`

These prefixes represent game-specific code, scenes, and assets outside the ruleset module.
The `rules/` directory must be self-contained and depend only on Godot 4 and
`addons/mikeys_game_bones/`.

### How it runs

The test runs automatically during headless validation (`godot --headless --path . --quit`)
as part of the project's validation flow. It is wired as an autoload (`TestBootstrap`)
that checks the extraction contract when the project loads in headless mode.

### Failure output

If the test detects a violation, it prints actionable output showing the file path and
line number of each offending reference. For example:

```
=== Extraction Contract Violations ===
Files in rules/ must not reference res://scripts/, res://scenes/, or res://resources/

FAIL res://rules/core/example.gd:42: res://scripts/
FAIL res://rules/data/abilities/example.tres:15: res://scenes/
```

