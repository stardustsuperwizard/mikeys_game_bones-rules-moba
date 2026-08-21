# Core Combat Types

Fundamental types and constants for the MOBA combat system.
Includes combat stats, damage resolution, and the MobaCombatant node attachment point.

## MobaCombatant

A Node that attaches to an Actor and owns the actor's health state and stat access seam.
It duplicates the stat block on initialization to ensure runtime mutations don't
corrupt the resource file or other actors. Every health change is mirrored into
the parent Actor's character_sheet and broadcasts via the `health_changed` signal.
Death handling is guarded to fire exactly once.

Intended to be parented to an Actor and named `Combatant`.

