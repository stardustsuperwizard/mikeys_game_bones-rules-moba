# rules/data/

Authored game content for the MOBA ruleset. All numeric values, ability definitions,
enemy templates, and loadout configurations live here as `.tres` resources or committed
JSON. GDScript loads these at runtime — no values are hard-coded in `.gd` files.
The `generated/` subdirectory is gitignored and written only by the Python balance harness.
