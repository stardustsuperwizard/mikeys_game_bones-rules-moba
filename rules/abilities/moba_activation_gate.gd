## Decides whether one MobaCombatant may activate an ability, and performs the
## atomic commit (spend resource, start cooldown) when it may.
##
## Holds the readiness rules MobaCombatant.can_activate() and commit_activate()
## used to carry inline: unknown ability, resource, and the cooldown/charges
## distinction between ON_COOLDOWN and NO_CHARGES.
##
## Split out of MobaCombatant to keep that file under the project's
## max-file-lines gate (see .gdlintrc and #325). Like MobaDeathHandler, this is
## a private implementation detail of MobaCombatant: can_activate() and
## commit_activate() remain the public seams callers use, and this class only
## talks back to its combatant through public methods -- including
## start_cooldown(), which exists for this gate to call.
class_name MobaActivationGate
extends RefCounted

## The combatant whose activations this gate decides.
var _combatant: MobaCombatant = null


func _init(p_combatant: MobaCombatant) -> void:
	_combatant = p_combatant


## Check if an ability can be activated without side effects.
## Returns an ActivationFailure enum value indicating readiness or failure reason.
## This is a pure query: it mutates nothing, spends no resource, and starts no cooldown.
##
## Reads through the combatant's public accessors so an unconfirmed prediction
## (#321) counts against it: that greys the slot and stops a second press
## stacking a duplicate guess. On the server -- the only peer reaching
## commit_activate() -- there are no predictions, so this is the query it was
## before #321.
func can_activate(ability_id: StringName) -> int:
	var ability := _combatant.get_ability(ability_id)
	if ability == null:
		return MobaCombatant.ActivationFailure.UNKNOWN_ABILITY

	# Check resource
	if ability.resource_cost > _combatant.current_resource:
		return MobaCombatant.ActivationFailure.INSUFFICIENT_RESOURCE

	# Check cooldown and charges. A charge remaining while the recharge timer is
	# still running does not block activation; only being out of charges does.
	var available_charges: int = _combatant.get_charges(ability_id)
	var remaining: float = _combatant.get_cooldown_remaining(ability_id)
	if available_charges <= 0 and remaining > 0.0:
		# A single-charge ability (max_charges <= 1) that is out of charges is
		# simply on cooldown; NO_CHARGES is reserved for a multi-charge ability
		# that has spent every charge while its recharge timer is still running.
		if _combatant.get_max_charges(ability_id) <= 1:
			return MobaCombatant.ActivationFailure.ON_COOLDOWN
		return MobaCombatant.ActivationFailure.NO_CHARGES

	return MobaCombatant.ActivationFailure.OK


## Commit an ability activation: spend resource and start cooldown atomically.
## Returns the failure reason if activation cannot proceed; spends nothing and
## starts no cooldown if not OK.
## If can_activate() returns OK, this call will succeed and spend resource + start cooldown.
func commit_activate(ability_id: StringName) -> int:
	var check: int = can_activate(ability_id)
	if check != MobaCombatant.ActivationFailure.OK:
		return check

	var ability := _combatant.get_ability(ability_id)

	# For a channeled ability, resource_cost is the per-tick cost: each tick
	# (including the first, at t = 0) spends it independently, so commit must
	# not also spend it here or the first tick would be charged twice.
	# For a toggle ability, resource_cost is the per-second drain rate: drain is
	# charged per second by the tracker's own tick, not at commit.
	if (
		ability.channel_duration <= 0.0
		and ability.targeting_type != MobaAbility.TargetingType.TOGGLE
	):
		_combatant.spend_resource(ability.resource_cost)

	# Start cooldown with current haste
	var haste: float = _combatant.get_stat(MobaStatBlock.ABILITY_HASTE)
	_combatant.start_cooldown(ability_id, ability.cooldown, haste, ability.charges)

	return MobaCombatant.ActivationFailure.OK
