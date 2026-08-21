# Game Content and Configuration

## Three kinds of data files

| Kind | Format | Committed? | Purpose |
|------|--------|------------|---------|
| **Authored Resources** | `.tres` (Godot Resource) | ✅ Yes | Abilities, passives, weapons, loadouts, enemies, and stat blocks. Edited in the Godot inspector against typed `MobaAbility`, `MobaPassive`, etc. Resources. GDScript loads these directly at runtime. |
| **Authored config** | `.json` | ✅ Yes | Hand-maintained tables that are not well expressed as Godot Resources: interrupt table, aim-assist table, device multipliers, conformance fixtures. |
| **Generated exports** | `.json` inside `generated/` | ❌ Gitignored | JSON produced by the Python balance harness export tool (T2). Never read by GDScript. Exists only so the Python simulator can consume ability data without launching Godot. |

The `generated/` subdirectory is listed in `.gitignore`. Do not commit files from it.

Hand-authored abilities, passives, weapons, loadouts, enemies, and stat blocks authored as `.tres` Godot Resources.
Hand-authored configuration as `.json` files (interrupt table, device multipliers, conformance fixtures).
The `generated/` subdirectory (gitignored) holds Python-exported JSON for the balance harness.
