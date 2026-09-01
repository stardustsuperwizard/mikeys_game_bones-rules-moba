# Game-specific enemy controller for Sword and Planet.
#
# Extends SimpleAIController to add MOBA ruleset integration:
# - Ticks the enemy's MobaCombatant once per physics frame so cooldowns,
#   resource regeneration, and the state machine advance on schedule.
# - Routes basic attacks through MobaBasicAttackAction/ActionRunner instead of
#   the framework's flat Actor.attack_cooldown, so the swing passes the
#   Authority ownership gate and still observes wind_up, recovery, and
#   attack_speed from the equipped weapon.
#
# Falls back to inherited SimpleAIController behavior for actors without a
# MobaCombatant child.
class_name EnemyAIController3D
extends SimpleAIController

# Whether a basic-attack cycle is pending toward the current attack target.
# Set to true when get_attack_target() delivers the enemy within range;
# cleared when the basic attack action succeeds or the target becomes
# invalid, leaves range, or carries no MobaCombatant to attack.
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
		#
		# An AI actor is owner_id 0 and only ever ticks on the server, so
		# try_basic_attack() always takes its local branch here and the
		# ActionResult is always real -- the null case cannot arise for a bot.
		# It is still handled rather than assumed, so that the latch degrades to
		# "drop the target" instead of latching forever if that ever changes.
		if not _basic_attack_pending:
			return

		if not is_instance_valid(_pending_attack_target):
			# Target despawned or was freed mid-cycle.
			_clear_pending_attack()
			return

		var result := actor.try_basic_attack(_pending_attack_target)
		# FAILURE_NO_TARGET_COMBATANT means the target runs on the framework attack
		# path, not the ruleset -- nothing for basic_attack() to resolve against, so
		# don't latch it. Every other failure is a swing that may still land next
		# frame, so the pending target is held across those as before.
		if (
			result == null
			or result.success
			or result.reason == MobaBasicAttackAction.FAILURE_NO_TARGET_COMBATANT
		):
			_clear_pending_attack()


# Overrides SimpleAIController's get_move_direction to gate AI movement intent
# by crowd control, at the one place this controller decides where to go.
#
# Same gates as PlayerController3D, in the same precedence, applied to AI intent
# instead of input: displacement replaces the AI's decision; else a
# movement-blocking effect (STUN/ROOT) zeroes it whatever the aggro or chase
# state says; else fear redirects it away from its source; else the inherited
# AI logic runs unchanged.
func get_move_direction() -> Vector3:
	var combatant := _combatant()

	# Gate 1: displacement (KNOCKBACK/PULL/KNOCK_UP) overrides everything, a
	# blocking effect included -- being knocked back while stunned is the entire
	# point of a knockback, and #221 publishes it pre-scaled.
	if combatant:
		var displacement := combatant.get_forced_move_direction()
		if displacement != Vector3.ZERO:
			return displacement

	# Gate 2: movement not currently permitted -- hold position regardless of
	# aggro or chase state.
	# Ahead of fear deliberately: crowd-control entries are tracked per type, so
	# FEAR and STUN are routinely co-active (a fear, then a Shield Bash), and a
	# feared *and* stunned actor is stunned -- it does not flee at full speed.
	if combatant and not combatant.can_perform_action(&"move"):
		return Vector3.ZERO

	# Gate 3: fear redirects intent rather than blocking it -- it carries an
	# all-false row in the crowd-control table -- so it resolves here, after
	# every effect that can forbid movement outright has had its say.
	if combatant:
		var fleeing := _fear_move_direction(combatant)
		if fleeing != Vector3.ZERO:
			return fleeing

	# Gate 4: fall through to the inherited AI logic
	return super.get_move_direction()


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
#
# Gated by TAUNT at this same seam: while taunted the taunt source replaces the
# AI's own target selection. Out of range it stays the target and simply is not
# reachable -- falling through there would let a taunted enemy pick its own
# victim again, which is exactly what Taunt takes away. Chasing it is Batch 5
# AI behavior, not intent, so nothing here re-paths.
func get_attack_target() -> Actor:
	var combatant := _combatant()
	if combatant == null:
		return super.get_attack_target()

	var taunt_source_actor := _taunt_target(combatant)
	if taunt_source_actor:
		if actor.global_position.distance_to(taunt_source_actor.global_position) > attack_range:
			_clear_pending_attack()
			return null
		_pending_attack_target = taunt_source_actor
		_basic_attack_pending = true
		return null

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


# Unit vector pointing straight away from the recorded FEAR source, flattened to
# the ground plane, or Vector3.ZERO when not feared. Resolved here from the
# source #220 exposes for exactly this consumer, because #220 does not route
# FEAR through get_forced_move_direction() -- only displacement lands there.
# Left unscaled so ActorBody3D's existing velocity formula flees at the actor's
# normal speed; displacement is the case needing its own scaling, and #221
# already applies it before publishing.
func _fear_move_direction(combatant: MobaCombatant) -> Vector3:
	var fear_type := MobaCrowdControlSpec.CCType.FEAR
	if not combatant.has_crowd_control(fear_type):
		return Vector3.ZERO

	var fear_source := combatant.get_crowd_control_source(fear_type)
	if not is_instance_valid(fear_source):
		return Vector3.ZERO

	var fear_source_actor := fear_source.get_parent() as Actor
	if not is_instance_valid(fear_source_actor):
		return Vector3.ZERO

	var away := actor.global_position - fear_source_actor.global_position
	away.y = 0.0
	if away.length() < 0.001:
		# Source standing exactly on the actor: flee a fixed way rather than
		# stalling, and without reaching for a random number.
		return Vector3.FORWARD

	return away.normalized()


# The Actor a TAUNT is forcing this controller to attack, or null when not
# taunted. Per §19 the taunt source is itself the designated target.
func _taunt_target(combatant: MobaCombatant) -> Actor:
	if combatant == null:
		return null

	var taunt_type := MobaCrowdControlSpec.CCType.TAUNT
	if not combatant.has_crowd_control(taunt_type):
		return null

	var taunt_source := combatant.get_crowd_control_source(taunt_type)
	if not is_instance_valid(taunt_source):
		return null

	return taunt_source.get_parent() as Actor
