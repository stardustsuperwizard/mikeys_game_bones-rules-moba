# Game-specific enemy controller for Sword and Planet.
#
# Extends SimpleAIController to add MOBA ruleset integration:
# - Ticks the enemy's MobaCombatant once per physics frame so cooldowns,
#   resource regeneration, and the state machine advance on schedule.
# - Routes basic attacks through MobaCombatant.basic_attack() instead of
#   the framework's flat Actor.attack_cooldown, observing wind_up, recovery,
#   and attack_speed from the equipped weapon.
#
# Falls back to inherited SimpleAIController behavior for actors without a
# MobaCombatant child.
class_name EnemyAIController3D
extends SimpleAIController

# Whether a basic-attack cycle is pending toward the current attack target.
# Set to true when get_attack_target() delivers the enemy within range;
# cleared when the combatant accepts the basic_attack() call or the target
# becomes invalid or leaves range.
var _basic_attack_pending := false

# The target of the pending basic attack. Held separately from SimpleAIController's
# `target`, which the inherited aggro/leash logic is free to drop or repoint
# between frames, so the attack cycle always has something to run against.
var _pending_attack_target: Actor = null


# Ticks the MOBA combatant once per physics frame. MobaCombatant.tick() drives
# cooldowns, resource regeneration, and the internal state machine via
# _tick_state_machine_and_basic_attack(), so no separate MobaStateMachine.tick()
# call is needed here -- the combatant owns that responsibility.
#
# Also fires the ruleset basic attack when the inherited AI system has chosen
# an attack target and the enemy has closed to melee range.
func _physics_process(delta: float) -> void:
	var combatant := _combatant()
	if combatant:
		combatant.tick(delta)

		# Fire the basic attack when a target is pending and the combatant is ready.
		# _basic_attack_pending is set by get_attack_target() once the inherited
		# chase has closed to attack_range. basic_attack() returns false while the
		# cycle is still winding up or recovering, so the pending target is held
		# across those frames and only dropped once the swing is accepted.
		if not _basic_attack_pending:
			return

		if not is_instance_valid(_pending_attack_target):
			# Target despawned or was freed mid-cycle.
			_clear_pending_attack()
			return

		var target_combatant := (
			_pending_attack_target.get_node_or_null("MobaCombatant") as MobaCombatant
		)
		if target_combatant == null:
			# Target runs on the framework attack path, not the ruleset; nothing
			# for basic_attack() to resolve against, so don't latch it.
			_clear_pending_attack()
			return

		if combatant.basic_attack(target_combatant):
			_clear_pending_attack()


# Overrides SimpleAIController's get_attack_target to route basic attacks through
# the ruleset when a MobaCombatant is present.
#
# When this actor has a MobaCombatant this never returns a target: the ruleset
# path (MobaCombatant.basic_attack, driven from _physics_process) owns combat
# resolution, and returning a target would make ActorBody3D additionally fire
# Actor.try_attack() for the same swing (architecture constraint: ruleset path
# wins). Instead the would-be target is recorded for the attack cycle.
#
# When this actor has no MobaCombatant it falls through entirely to
# SimpleAIController's inherited behavior -- the flat Actor.attack_cooldown and
# Actor.try_attack() path -- which stays intact for actors without a combatant.
func get_attack_target() -> Actor:
	var combatant := _combatant()
	if combatant == null:
		return super.get_attack_target()

	# Deaggroed, leashed home, or chased out of range: drop the pending cycle
	# rather than latching a stale target the enemy would keep swinging at.
	# MobaCombatant.basic_attack() range-gates on the weapon independently, so
	# this is about not holding the reference, not about landing hits.
	if target == null:
		_clear_pending_attack()
		return null

	if actor.global_position.distance_to(target.global_position) > attack_range:
		_clear_pending_attack()
		return null

	# Assigned unconditionally so a re-target while the previous cycle is still
	# pending re-points at the current target instead of latching the old one.
	# PlayerController3D gates this on the flag purely to avoid repeat
	# cancel_order() calls; there is no movement order to cancel here.
	_pending_attack_target = target
	_basic_attack_pending = true
	return null


# Drops any pending basic-attack cycle.
func _clear_pending_attack() -> void:
	_basic_attack_pending = false
	_pending_attack_target = null


# Returns the MobaCombatant child of the actor, or null if there isn't one.
func _combatant() -> MobaCombatant:
	return actor.get_node_or_null("MobaCombatant") as MobaCombatant
