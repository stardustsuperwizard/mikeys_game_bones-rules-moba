# Input Intent Layer

Device-agnostic input intent abstraction for keyboard, gamepad, and touch.
Converts raw input into unified capability tokens that the ability system consumes.

The combat rules must never see a device (ruleset §5.4). This module resolves a
scheme into intents; only intents reach the state machine and the rules. That is
also what makes the Python balance harness meaningful — simulations consume
intents, so a duel simulation is device-independent.

## Contents

`MobaIntent` (rules/input/moba_intent.gd) is the intent vocabulary. Every §5.4
intent is an inner class of it — `MobaIntent.MoveIntent`,
`MobaIntent.AbilityIntent`, and so on:

- **MoveIntent** — `direction` from move_forward/move_back/strafe_left/strafe_right,
  or signed `turn` from turn_left/turn_right. Exactly one of the two is non-zero
  per emission; the ruleset's terser `MoveIntent(direction)` is widened here
  because turning and translating are different mathematical objects in this
  codebase.
- **AimIntent** — `direction` or `point`, selected by `mode`. Defined but not yet
  emitted: §5.4's mapping table has no action row producing it.
- **JumpIntent** — no fields. Traversal, not a combat ability (§5.5).
- **BasicAttackIntent** — `held`, so hold-to-repeat and press-to-fire weapons read
  the same intent.
- **AbilityIntent** — `slot` (1–4) and `phase` (PRESS, AIM, RELEASE, CANCEL).
- **LockOnIntent** — `phase` (PRESS, RELEASE, CYCLE). CYCLE is reserved: the bound
  lock_on action has no cycling semantics defined yet.
- **UtilityIntent** — `id`, the semantic name of a bound convenience action.

They are `RefCounted`, never `Resource`: intents are transient and per-frame.
Nesting them keeps one prefixed global (`MobaIntent`) in Godot's flat `class_name`
registry instead of seven collision-prone bare names.

`MobaInputRouter` (rules/input/moba_input_router.gd) translates `InputMap` actions
into intents one-for-one and emits them on `intent_emitted`. It covers every §5.4
mapping-table row that produces a combat or movement intent, and deliberately
emits nothing for `action_primary` (a mouse convenience) or `camera_recenter`
(camera, not combat). A held ability gesture runs PRESS, then AIM every poll while
held, then RELEASE — AIM repeating is what drag-to-aim on touch and stick-aim on
gamepad both need.

`MobaInputScheme` (rules/input/moba_input_scheme.gd) tracks whether GAMEPAD,
KEYBOARD_MOUSE, or TOUCH is active and emits `scheme_changed` when it changes.
Schemes hot-swap with no restart and no menu. Detection classifies events by
class, never by keycode, so remapping cannot misattribute a device.
`scheme_change_threshold` is deliberately greater than the 0.2 movement deadzone
in `project.godot`: the deadzone decides when a stick is being pushed, this
decides when the player has switched hands to the pad. A hysteresis window stops
input alternating between devices from re-firing the signal every frame.

## Constraints

This is a translation layer, not a second place where control decisions are made.
Anything expressible as a binding belongs in `project.godot`. No keycode is
hardcoded here; only action names already defined there are read.

`moba_input_router.gd` and `moba_input_scheme.gd` are the only files under
`rules/` permitted to read the `Input` or `InputMap` singletons. Confining those
reads is what keeps the rest of the rules device-agnostic, so
`rules/tests/input_intent_test.gd` enforces it automatically rather than leaving
it to review — which is also why that suite drives both nodes through an
injectable strength source and direct event handoff instead of a real device.
