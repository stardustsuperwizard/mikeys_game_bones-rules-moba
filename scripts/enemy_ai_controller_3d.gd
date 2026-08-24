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

# The target of the pending basic attack. get_attack_target() cancels/updates
# the inherited movement order so this keeps a separate reference alive across
# frames for the attack cycle to actually run against.
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
		# _basic_attack_pending is set by get_attack_target() when the enemy enters
		# range; _pending_attack_target survives any movement order changes so the
		# attack cycle has something to run against. Cleared here after the combatant
		# accepts the call, or if the target becomes invalid.
		if _basic_attack_pending and is_instance_valid(_pending_attack_target):
			var target_combatant := (
				_pending_attack_target.get_node_or_null("MobaCombatant") as MobaCombatant
			)
			if target_combatant:
				if combatant.basic_attack(target_combatant):
					_basic_attack_pending = false
					_pending_attack_target = null
			else:
				# Target has no MobaCombatant; clear pending so it doesn't remain
				# latched indefinitely.
				_basic_attack_pending = false
				_pending_attack_target = null
		elif _basic_attack_pending:
			_basic_attack_pending = false
			_pending_attack_target = null


# Overrides SimpleAIController's get_attack_target to route basic attacks through
# the ruleset when a MobaCombatant is present.
#
# When this actor has a MobaCombatant:
# - Record the would-be target and schedule the attack cycle in _physics_process.
# - Return null so the framework's Actor._resolve_attack() does NOT fire for the
#   same input (architecture constraint: ruleset path wins).
# Gate the flag-set on the flag not already being live so that standing still in
# range does not repeatedly call get_attack_target().
#
# When this actor has no MobaCombatant:
# - Fall through to SimpleAIController's inherited get_attack_target() behavior,
#   using the flat Actor.attack_cooldown and Actor.try_attack() path.
func get_attack_target() -> Actor:
	if target == null:
		return null

	if actor.global_position.distance_to(target.global_position) > attack_range:
		return null

	# When this actor has a MobaCombatant the ruleset basic-attack path
	# (MobaCombatant.basic_attack) handles combat resolution, driven in
	# _physics_process once the enemy closes range.
	# Gate the flag-set on the flag not already being live so that standing
	# still in range does not repeatedly call get_attack_target().
	if _combatant() != null:
		if not _basic_attack_pending:
			_pending_attack_target = target
			_basic_attack_pending = true
		return null

	# No MobaCombatant; use the inherited framework path.
	return target


# Returns the MobaCombatant child of the actor, or null if there isn't one.
func _combatant() -> MobaCombatant:
	return actor.get_node_or_null("MobaCombatant") as MobaCombatant
