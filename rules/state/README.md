# Character State Machine

State definitions and transitions with interrupt handling.
Manages character availability, action restrictions, and crowd control state.

## State Definitions

`MobaState` (rules/state/moba_state.gd) enumerates the ten character states from the ruleset §56:

- **IDLE** — No action in progress. Resting state after actions complete or on entry to play.
- **MOVING** — Character is moving under player or AI control. Transitions to other states on action input.
- **BASIC_ATTACK_WINDUP** — During the startup frames of a basic attack. Movement may cancel this.
- **BASIC_ATTACK_RECOVERY** — After attack impact, during recovery frames. No new attacks allowed.
- **ABILITY_CAST** — Casting an ability with a cast time. Movement may cancel this.
- **ABILITY_CHANNEL** — Channeling an ability. Interrupts end the channel.
- **DASHING** — Executing a dash ability. Position driven by the ability, movement input locked.
- **AIRBORNE** — Knocked up or jumped. Air control reduces movement authority.
- **CROWD_CONTROLLED** — Under a crowd control effect (stun, root, etc.). Per-CC rules apply.
- **DEAD** — Character is dead. Terminal state; only `revive()` exits.

`AirborneCause` distinguishes the reason for the AIRBORNE state:

- **JUMP** — Player-initiated jump. Landing ends the state.
- **KNOCK_UP** — Knockup effect. Landing may apply crowd control.

## State Transition Table

`rules/data/state_transitions.json` encodes the legality matrix. Each state entry contains columns:

### Columns

- **move** — Movement input legality. Values: `yes`, `no`, `cancels`, `locked`, `air_control`, `per_cc`
  - `yes` — Movement is legal and does not interrupt the current action.
  - `no` — Movement input is refused.
  - `cancels` — Movement input is accepted and cancels the current action, returning to MOVING or IDLE.
  - `locked` — Movement input is ignored; position is driven by the action (e.g., dash).
  - `air_control` — Movement input is accepted at reduced authority (§5.5 60% factor).
  - `per_cc` — Legality depends on the crowd control effect (Batch 2).

- **basic_attack** — Basic attack input legality. Values: `yes`, `no`, `per_cc`
  - `yes` — Basic attack is legal.
  - `no` — Basic attack is illegal.
  - `per_cc` — Legality depends on the crowd control effect.

- **ability** — Ability input legality. Values: `yes`, `no`, `flagged`, `per_cc`
  - `yes` — Ability cast is legal.
  - `no` — Ability cast is illegal.
  - `flagged` — Ability legality is conditional on a per-ability flag. The state machine conservatively returns false; the ability system narrows based on per-ability overrides (§59).
  - `per_cc` — Legality depends on the crowd control effect.

- **jump** — Jump input legality. Values: `yes`, `no`, `per_cc`
  - `yes` — Jump is legal.
  - `no` — Jump is illegal.
  - `per_cc` — Legality depends on the crowd control effect.

- **interruptible_by_hard_cc** — Crowd control interrupt behavior. Values: `yes`, `no`, `per_cc`, `breaks_channel`, `displacement_only`
  - `yes` — Crowd control hard-interrupts this state.
  - `no` — Crowd control does not interrupt this state.
  - `per_cc` — Whether interruption applies depends on the specific effect (CROWD_CONTROLLED state itself).
  - `breaks_channel` — Crowd control hard-interrupts and breaks channeling (ABILITY_CHANNEL).
  - `displacement_only` — Only displacement effects (knockback, pull) interrupt; stuns and roots do not (DASHING).

## MobaStateMachine

`rules/state/moba_state_machine.gd` is a Node that:

1. Loads the state transition table from `state_transitions.json` on `_ready()`.
2. Tracks the current state, elapsed time in that state, and time remaining until expiration.
3. Answers action-legality and movement-policy questions by dictionary lookup, not by code branches.
4. Emits `state_changed(from: int, to: int)` on real state transitions (not on re-entry).
5. Supports zero-or-negative duration rejection, terminal DEAD state, and explicit AIRBORNE cause storage.

### Properties

- **current_state: int** — The current MobaState enum value.
- **time_in_state: float** — Seconds elapsed in the current state.
- **remaining: float** — Seconds remaining until the state expires (0 if no expiry).

### Methods

- **can(action: StringName) → bool** — Answers whether an action is legal. Actions: `"move"`, `"basic_attack"`, `"ability"`, `"jump"`. Movement's `locked` policy (DASHING) resolves to `false`: input is ignored while position is driven by the action, so it is not a legal move input.
- **movement_policy() → StringName** — Returns the movement policy as a StringName (never reduced to boolean).
- **hard_cc_policy() → StringName** — Returns the `interruptible_by_hard_cc` policy for the current state as a StringName (`"yes"`, `"no"`, `"per_cc"`, `"breaks_channel"`, `"displacement_only"`), by dictionary lookup only.
- **try_enter(state: int, duration: float = 0.0, cause: int = JUMP) → bool** — Attempt to enter a state. Durationless states (IDLE, MOVING, DEAD, and CROWD_CONTROLLED entered without a duration) are entered normally regardless of `duration`; every other state requires `duration > 0` and is rejected otherwise. Also returns false if current state is DEAD, or if `state` is invalid. Re-entering the current state returns true without emitting.
- **tick(delta: float) → void** — Advance time. Decrements remaining if tracking a duration; transitions to IDLE when duration expires.
- **revive() → bool** — Exit DEAD state and return to IDLE. Returns false if not currently DEAD.
- **get_airborne_cause() → int** — Retrieve the AirborneCause if AIRBORNE, or -1 if not.
- **get_state_table_for_testing() → Dictionary** — Expose the loaded table for testing mutation.
- **load_state_table_for_testing(data: Variant) → bool** — Feed a hand-built table through the same validation path used on `_ready()`, for testing malformed-table handling.

### Design Notes

- No `_process` or `_physics_process`. Time advances only through explicit `tick(delta)` calls from the owner.
- Action legality is determined by dictionary lookup against the loaded table, never by code branches over state values. This includes DEAD: its table row already answers `no`/`false` for every action and every policy, so `can()` and `hard_cc_policy()` need no special-case branch for it.
- Unrecognized state names, column names, or policy values cause `push_error()` and set the detectable `load_failed` flag; `can()`, `movement_policy()`, and `hard_cc_policy()` all check it and fail safe (return `false` / `"no"`) rather than silently reporting stale or partial data.
- Zero-or-negative duration is rejected only for states that require a duration to be meaningful (BASIC_ATTACK_WINDUP, BASIC_ATTACK_RECOVERY, ABILITY_CAST, ABILITY_CHANNEL, DASHING, AIRBORNE). IDLE, MOVING, DEAD, and CROWD_CONTROLLED may be entered with `duration <= 0` and simply have no expiry.
- `DEAD` is terminal and reachable through `try_enter()` like any other durationless state: once entered, every `can()` query returns false, and further `try_enter()` calls always return false. Only `revive()` exits.
- `AIRBORNE` states store the cause flag through transitions and expose it for later use.

