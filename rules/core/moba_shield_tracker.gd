## Shield pool for a single combatant: apply_shield()'s absorption entries,
## shortest-remaining-duration-first consumption against incoming damage, and
## per-tick duration expiry.
##
## Split out of MobaCombatant to keep that file under the project's
## max-file-lines gate (see .gdlintrc). A private implementation detail of
## MobaCombatant, the same way MobaCastTracker, MobaChannelTracker, and
## MobaDeathHandler are -- MobaCombatant.apply_shield()/total_shield() remain
## the sole public seam; callers never reach this class directly.
class_name MobaShieldTracker
extends RefCounted

## The combatant this tracker belongs to. shield_changed is the combatant's
## own signal, so every mutation below notifies through it rather than
## emitting one of its own.
var _combatant: MobaCombatant = null

## Active shield pool: list of MobaShield instances, each with remaining
## absorption capacity.
var _active_shields: Array[MobaShield] = []


func _init(p_combatant: MobaCombatant) -> void:
	_combatant = p_combatant


## Return the total absorption capacity from all active shields.
func total() -> float:
	var result: float = 0.0
	for shield in _active_shields:
		result += shield.amount
	return result


## The live list of active shields. Read-only inspection only -- callers
## must not mutate the returned array directly; go through apply()/clear().
func get_shields() -> Array[MobaShield]:
	return _active_shields


## Apply a new shield. A no-op if amount <= 0.0. Notifies shield_changed with
## the post-mutation total.
func apply(amount: float, source: StringName, duration: float) -> void:
	if amount <= 0.0:
		return

	var shield := MobaShield.new(amount, source, duration)
	_active_shields.append(shield)
	_combatant.notify_shield_changed()


## Clear all active shields without notifying shield_changed -- matches
## MobaCombatant.clear_all_active_effects()'s contract of leaving the signal
## to the caller, who may be changing other state in the same operation.
func clear() -> void:
	_active_shields.clear()


## Consume shields in order of shortest-remaining-duration first.
## Returns the remaining damage after shields absorb what they can.
## Notifies shield_changed for each shield that is consumed or damaged.
func consume(incoming_damage: float) -> float:
	var remaining_damage: float = incoming_damage

	# Sort shields by remaining duration (ascending) so we consume shortest-remaining first
	var sorted_shields: Array[MobaShield] = _active_shields.duplicate()
	sorted_shields.sort_custom(
		func(a: MobaShield, b: MobaShield) -> bool: return a.remaining < b.remaining
	)

	# Consume shields in order
	for shield in sorted_shields:
		if remaining_damage <= 0.0:
			break

		if shield.amount >= remaining_damage:
			# Shield absorbs all remaining damage
			shield.amount -= remaining_damage
			remaining_damage = 0.0
			_combatant.notify_shield_changed()
		else:
			# Shield is fully consumed, remainder carries to next shield or health
			remaining_damage -= shield.amount
			_active_shields.erase(shield)
			_combatant.notify_shield_changed()

	return remaining_damage


## Advance shield durations and remove expired shields.
## Notifies shield_changed when any shields expire during this tick.
func tick(delta: float) -> void:
	var shields_before := _active_shields.size()

	# Advance all shield durations
	for i in range(_active_shields.size() - 1, -1, -1):
		var shield = _active_shields[i]
		shield.remaining -= delta
		if shield.remaining <= 0.0:
			_active_shields.remove_at(i)

	# Notify if any shields expired
	if _active_shields.size() < shields_before:
		_combatant.notify_shield_changed()
