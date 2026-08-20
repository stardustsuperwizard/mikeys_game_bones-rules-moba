# rules/core/

Foundational systems shared across the ruleset: the tick loop, the combat state machine,
and the root `MobaCombatant` resource. Other subsystems depend on types defined here.
Nothing here may depend on anything outside `rules/` except Godot 4 builtins and
`addons/mikeys_game_bones/`.
