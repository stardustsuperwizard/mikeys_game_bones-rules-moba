# rules/state/

Combatant state machine — Idle, Moving, Casting, Stunned, Dead, etc. Transitions are
driven by the tick loop and validated against `rules/data/schema/state_transitions.json`.
Only this subsystem changes a combatant's current state.
