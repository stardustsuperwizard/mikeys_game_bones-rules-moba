## Client-side prediction ledger for ability activation and basic attack (#321).
##
## A networked client's ability activation and basic attack are resolved only by
## the server (#320's invariant, which nothing here weakens). That leaves the
## requesting client a full round trip with no feedback, so on sending the
## request it also records a PREDICTION here: a client-local overlay that
## MobaCombatant's public accessors read through, and that nothing else ever
## observes. It is never replicated, never broadcast, never treated as final.
##
## Holds no ledger of its own and mutates nothing. Every value here is an offset
## applied on top of MobaCombatant's real state, which is why a rollback is just
## dropping an entry: there is no spent resource to refund and no started
## cooldown to cancel, so nothing incorrect can survive one.
##
## Every prediction ends in exactly one of two ways:
##
##   rolled back -- the server refused, and said so through Actor.deny_activation().
##                  An explicit denial is required because the combat state
##                  replicates at replication_mode = 2 (on-change): a refusal
##                  leaves the server's own values untouched, so nothing is
##                  re-sent, and "wait for the next sync" would never fire.
##   superseded  -- the server's replicated ledger shows the request committed.
##                  The overlay is dropped and the real value takes over.
##
## A third exit exists only as a backstop: TIMEOUT_SECONDS. Neither answer
## arrives if the request died with the connection, and a prediction that
## outlived both is a HUD lying indefinitely -- the one outcome this task exists
## to prevent. It is a safety net, not the mechanism.
class_name MobaPredictionLedger
extends RefCounted

## Prediction key for the basic attack, which has no ability id of its own.
## Deliberately not a valid ability id: MobaAbilityLibrary ids are authored
## names, so this can never collide with one.
const BASIC_ATTACK := &"__basic_attack__"

## How long an unanswered prediction survives before it is dropped as lost.
## Generous against any plausible round trip -- this is the backstop for a
## request whose answer is never coming, not a substitute for the denial RPC.
const TIMEOUT_SECONDS := 5.0

## Float slop for "the server's timer is longer than the one we baselined".
const _EPSILON := 0.001

## In-flight predictions, keyed by BASIC_ATTACK or by the predicted ability's id.
## One entry per unconfirmed request this peer has sent to the server.
##
## Entry shape:
##   remaining/duration    the predicted cooldown sweep, decayed by tick()
##   charge_debit          charges this prediction has spent
##   resource_debit        resource this prediction has spent
##   cast_time             predicted cast-bar duration, 0.0 for an instant
##   baseline_charges      SERVER charges when the prediction was made
##   baseline_remaining    SERVER cooldown remaining when the prediction was made
##   age                   seconds since the request was sent
var _entries: Dictionary = {}

## Last cooldown values this peer received from the server, as ability_id ->
## {remaining, charges}. Written only by record_replicated().
##
## Kept apart from MobaCombatant's own cooldown ledger on purpose. That ledger is
## whatever this peer currently believes, and anything local may write it -- a
## stale client's own guess, a test wiping it to stand in for one. Confirmation
## has to be measured against what the SERVER last said, or a cooldown the server
## was already running reads as proof that it accepted a request it in fact
## refused, and the prediction retires itself as "confirmed" on a refusal that
## never arrived.
var _last_replicated: Dictionary = {}


## Record a predicted ability activation. Returns true if one was taken.
##
## The caller supplies the already-computed predicted cooldown duration and
## resource cost rather than the ability itself: deciding what an activation
## costs is MobaCombatant's and commit_activate()'s business, and a second copy
## of that arithmetic here would be free to drift from it.
##
## `fallback_remaining` / `fallback_charges` stand in for the server baseline
## when nothing has replicated yet -- offline and on the server itself, where the
## local ledger IS the authoritative one and no prediction is ever made anyway.
func predict_ability(
	ability_id: StringName,
	predicted_duration: float,
	resource_cost: float,
	cast_time: float,
	fallback_remaining: float,
	fallback_charges: int
) -> bool:
	if ability_id in _entries:
		return false

	_entries[ability_id] = {
		"remaining": predicted_duration,
		"duration": predicted_duration,
		"charge_debit": 1,
		"resource_debit": resource_cost,
		"cast_time": cast_time,
		"baseline_charges": replicated_charges(ability_id, fallback_charges),
		"baseline_remaining": replicated_remaining(ability_id, fallback_remaining),
		"age": 0.0,
	}
	return true


## Record a predicted basic attack. Returns true if one was taken.
##
## The swing has no cooldown ledger and no resource cost, so this predicts
## neither: it records only that a swing is outstanding. The visible swing itself
## stays server-driven through the replicated MobaStateMachine, which is what
## PlayerController3D's forwarded-attack latch already waits on.
func predict_basic_attack() -> bool:
	if BASIC_ATTACK in _entries:
		return false

	_entries[BASIC_ATTACK] = {
		"remaining": 0.0,
		"duration": 0.0,
		"charge_debit": 0,
		"resource_debit": 0.0,
		"cast_time": 0.0,
		"baseline_charges": 0,
		"baseline_remaining": 0.0,
		"age": 0.0,
	}
	return true


## Drop a refused prediction. Returns true if anything was actually dropped.
##
## An empty key drops every outstanding prediction, which is what a denial
## carrying no key (a refusal that could not name one) should do: err toward
## showing the server's truth.
func rollback(key: StringName = &"") -> bool:
	if _entries.is_empty():
		return false

	if key == &"":
		_entries.clear()
		return true
	if key in _entries:
		_entries.erase(key)
		return true
	return false


## True while any prediction is still waiting for the server's answer.
func has_any() -> bool:
	return not _entries.is_empty()


## True while THIS request is still waiting, keyed by ability id or BASIC_ATTACK.
##
## Separate from has_any() because the two questions differ: an outstanding swing
## says nothing about whether an ability's guess has been answered, and treating
## them as one would let either mask the other.
func has(key: StringName) -> bool:
	return key in _entries


## Total unconfirmed predicted resource spend, summed across predictions.
func resource_debit() -> float:
	var total := 0.0
	for key in _entries:
		total += _entries[key]["resource_debit"]
	return total


## Predicted cooldown remaining for an ability, or 0.0 when none is predicted.
func cooldown_remaining(ability_id: StringName) -> float:
	if ability_id in _entries:
		return _entries[ability_id]["remaining"]
	return 0.0


## Predicted cooldown duration for an ability, or 0.0 when none is predicted.
func cooldown_duration(ability_id: StringName) -> float:
	if ability_id in _entries:
		return _entries[ability_id]["duration"]
	return 0.0


## Charges an unconfirmed prediction has already spent for an ability.
func charge_debit(ability_id: StringName) -> int:
	if ability_id in _entries:
		return int(_entries[ability_id]["charge_debit"])
	return 0


## Cast time of the ability this peer is predicting, or 0.0 when none is
## predicted or the predicted ability is instant.
func predicted_cast_time() -> float:
	for key in _entries:
		var cast_time: float = _entries[key]["cast_time"]
		if cast_time > 0.0:
			return cast_time
	return 0.0


## Ability id this peer is predicting a cast for, or an empty StringName.
func predicted_cast_ability_id() -> StringName:
	for key in _entries:
		if _entries[key]["cast_time"] > 0.0:
			return key
	return &""


## Record what the server just said about every cooldown it sent, so confirmation
## has a server-sourced baseline to compare against.
##
## Entries the snapshot omits are left alone rather than cleared: a snapshot
## carries only the abilities the server has a timer for, and forgetting the rest
## would reset a baseline to "never heard" mid-flight.
func record_replicated(snapshot: Array) -> void:
	for entry in snapshot:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("ability_id"):
			continue
		_last_replicated[entry["ability_id"]] = {
			"remaining": float(entry.get("timer_remaining", 0.0)),
			"charges": int(entry.get("available_charges", 0)),
		}


## Cooldown remaining as the server last reported it, or `fallback` if the server
## has never reported this ability.
func replicated_remaining(ability_id: StringName, fallback: float) -> float:
	if ability_id in _last_replicated:
		return _last_replicated[ability_id]["remaining"]
	return fallback


## Charges as the server last reported them, or `fallback` if never reported.
func replicated_charges(ability_id: StringName, fallback: int) -> int:
	if ability_id in _last_replicated:
		return _last_replicated[ability_id]["charges"]
	return fallback


## Advance the predicted sweeps and settle anything the server has answered.
## Returns true if any prediction was retired, so the caller can notify the HUD.
##
## `is_swinging` is the replicated state machine's answer to "did the server
## start the swing" -- the basic attack's only confirmation signal.
func tick(delta: float, is_swinging: bool) -> bool:
	for key in _entries:
		var entry: Dictionary = _entries[key]
		entry["remaining"] = maxf(0.0, entry["remaining"] - delta)
		entry["age"] = entry["age"] + delta

	return _retire_confirmed(is_swinging)


## Drop predictions the server's replicated ledger has confirmed, and any that
## have waited past TIMEOUT_SECONDS without an answer.
##
## Confirmation is measured against the baseline the prediction recorded, not
## against zero: an ability whose cooldown was ALREADY running when the guess was
## made (a spare charge spent) would otherwise read as confirmed on the very
## first check, retiring the overlay before the server had answered at all.
##
## A refusal can trip neither test. Replication mode 2 re-sends only what the
## server's own change moved, and a refusal moves nothing -- which is exactly why
## the explicit denial RPC has to exist.
func _retire_confirmed(is_swinging: bool) -> bool:
	var settled: Array[StringName] = []

	for key in _entries:
		var entry: Dictionary = _entries[key]

		if entry["age"] >= TIMEOUT_SECONDS:
			settled.append(key)
			continue

		if key == BASIC_ATTACK:
			if is_swinging:
				settled.append(key)
			continue

		var baseline_charges: int = int(entry["baseline_charges"])
		var baseline_remaining: float = float(entry["baseline_remaining"])
		var spent_a_charge: bool = replicated_charges(key, baseline_charges) < baseline_charges
		var restarted_timer: bool = (
			replicated_remaining(key, baseline_remaining) > baseline_remaining + _EPSILON
		)
		if spent_a_charge or restarted_timer:
			settled.append(key)

	for key in settled:
		_entries.erase(key)
	return not settled.is_empty()


## Record a predicted activation of `ability_id` on `combatant`, deriving the
## predicted cooldown and spend from the ability's own authored data.
##
## Called by Actor.try_activate_slot() on the requesting client immediately after
## the request RPC goes out, so the cooldown sweep, the resource spend and the
## cast bar all start on the press instead of a round trip later.
##
## Refuses to predict what the client can already see is illegal, and (via
## predict_ability) refuses to stack a second guess on an ability still awaiting
## an answer: predicting an activation the server is bound to refuse only
## produces a rollback the player sees as a flicker.
##
## Reads the combatant through its public accessors and mutates nothing on it.
## The real spend still happens exactly once, on the server, inside
## commit_activate() behind the command gate.
func predict_ability_for(combatant: MobaCombatant, ability_id: StringName) -> bool:
	if combatant.can_activate(ability_id) != MobaCombatant.ActivationFailure.OK:
		return false

	var ability := MobaAbilityLibrary.get_ability(ability_id)
	if ability == null:
		return false

	# A channeled ability charges resource_cost per tick and a toggle charges it
	# per second, neither of which commit_activate() spends up front -- so
	# predicting a spend for either would show a cost the server never takes.
	# Mirrors the same condition commit_activate() applies.
	var spends_at_commit: bool = (
		ability.channel_duration <= 0.0
		and ability.targeting_type != MobaAbility.TargetingType.TOGGLE
	)
	var haste: float = combatant.get_stat(MobaStatBlock.ABILITY_HASTE)

	return predict_ability(
		ability_id,
		MobaFormulas.effective_cooldown(ability.cooldown, haste),
		ability.resource_cost if spends_at_commit else 0.0,
		ability.cast_time,
		combatant.get_cooldown_remaining(ability_id),
		combatant.get_charges(ability_id)
	)


## True while a state machine shows a swing in progress -- the server's
## confirmation that a predicted basic attack actually started. A null state
## machine (a bare fixture) simply never confirms, and the timeout collects it.
static func is_swinging(state_machine: MobaStateMachine) -> bool:
	if state_machine == null:
		return false
	return (
		state_machine.current_state == MobaState.BASIC_ATTACK_WINDUP
		or state_machine.current_state == MobaState.BASIC_ATTACK_RECOVERY
	)
