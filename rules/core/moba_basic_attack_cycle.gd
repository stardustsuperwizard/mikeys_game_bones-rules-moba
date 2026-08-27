## Basic-attack wind-up/recovery cycle for a single combatant: readiness gating
## on the attack-speed interval, starting a swing, and driving the sibling
## state machine's BASIC_ATTACK_WINDUP/BASIC_ATTACK_RECOVERY phases to the hit
## and back to ready.
##
## Split out of MobaCombatant to keep that file under the project's
## max-file-lines gate (see .gdlintrc). A private implementation detail of
## MobaCombatant, the same way MobaCastTracker/MobaChannelTracker/
## MobaDeathHandler/MobaShieldTracker are -- MobaCombatant.is_basic_attack_ready()
## and MobaCombatant.basic_attack() remain the sole public seam.
class_name MobaBasicAttackCycle
extends RefCounted

## The combatant this cycle belongs to.
var _combatant: MobaCombatant = null

var _attack_target: Node = null
var _attack_time_since_ready: float = INF


func _init(p_combatant: MobaCombatant) -> void:
	_combatant = p_combatant


## Whether basic_attack() may be called right now to start a new cycle: the
## combatant currently permits a basic attack (accounting for crowd control)
## and the attack-speed interval (1.0 / attack_speed) has elapsed since the last attack started.
## This is the minimal query the game side needs to drive repeat attacks.
func is_ready() -> bool:
	if not _combatant.can_perform_action(&"basic_attack"):
		return false
	var attack_speed := _combatant.get_stat(MobaStatBlock.ATTACK_SPEED)
	if attack_speed <= 0.0:
		return false
	return _attack_time_since_ready >= 1.0 / attack_speed


## Start a basic attack cycle against target, entering BASIC_ATTACK_WINDUP.
## Returns false and starts nothing if the loadout has no weapon, target is
## dead, target is out of range, or the cycle is not ready.
func start(target: MobaCombatant) -> bool:
	var loadout := _combatant.loadout
	var weapon := loadout.get_weapon() if loadout != null else null
	if (
		weapon == null
		or not target.is_alive()
		or not _is_in_range(target, weapon.attack_range)
		or not is_ready()
	):
		return false

	var state_machine := _combatant.get_state_machine()
	if not state_machine.try_enter(MobaState.BASIC_ATTACK_WINDUP, weapon.wind_up):
		return false
	_attack_target = target
	_attack_time_since_ready = 0.0
	return true


## Advance the readiness timer and the sibling state machine's attack phases
## together. Called once per MobaCombatant.tick(delta).
func tick(delta: float) -> void:
	if _attack_time_since_ready != INF:
		_attack_time_since_ready += delta
	_tick_state_machine_and_basic_attack(delta)


## Fail-closed: an attacker or target whose parent exposes no global_position
## is treated as out of range rather than in range, so range gating cannot be
## bypassed by an incomplete scene setup. Duck-typed via get("global_position")
## -- matching MobaAbilityAction._get_position() -- so rules/ keeps no
## outward reference to Actor.
func _is_in_range(target: MobaCombatant, range_m: float) -> bool:
	var this_position = _get_parent_position(_combatant)
	var target_position = _get_parent_position(target)
	if this_position == null or target_position == null:
		return false
	return (this_position as Vector3).distance_to(target_position as Vector3) <= range_m


func _get_parent_position(combatant: MobaCombatant) -> Variant:
	var parent := combatant.get_parent()
	if parent == null:
		return null
	return parent.get("global_position")


## Advances the sibling MobaStateMachine and the basic-attack cycle together.
##
## The wind-up and recovery phases are tracked through the state machine's
## own duration/expiry mechanism (try_enter()/tick()), but a naive single
## state_machine.tick(delta) call would silently drop any overshoot past a
## phase boundary (the delta beyond exactly when wind-up or recovery
## expires), making cycle durations drift with tick granularity. This loop
## ticks the state machine only up to the next phase boundary, applies the
## hit or returns to ready exactly at that boundary, and carries the
## leftover delta into the following phase - bounded to at most the two
## basic-attack phase boundaries per call, so it always terminates.
func _tick_state_machine_and_basic_attack(delta: float) -> void:
	var state_machine := _combatant.get_state_machine()
	if state_machine == null:
		return

	var remaining_delta := delta
	while remaining_delta > 0.0:
		var expiring_state = state_machine.current_state
		var in_attack_phase = (
			expiring_state == MobaState.BASIC_ATTACK_WINDUP
			or expiring_state == MobaState.BASIC_ATTACK_RECOVERY
		)

		if (
			not in_attack_phase
			or state_machine.remaining <= 0.0
			or state_machine.remaining > remaining_delta
		):
			state_machine.tick(remaining_delta)
			remaining_delta = 0.0
			continue

		# This tick exactly exhausts the current attack phase; carry the
		# overshoot into the phase that follows.
		var overshoot = remaining_delta - state_machine.remaining
		state_machine.tick(state_machine.remaining)
		_advance_basic_attack_phase(expiring_state, state_machine)
		remaining_delta = overshoot


## Called exactly when `expiring_state` (WINDUP or RECOVERY) has expired
## back to IDLE. Applies the hit and enters recovery, or clears the cycle
## and lets the readiness interval (tracked separately) gate the next
## attack.
func _advance_basic_attack_phase(expiring_state: int, state_machine: MobaStateMachine) -> void:
	if expiring_state != MobaState.BASIC_ATTACK_WINDUP:
		_attack_target = null
		return

	var loadout := _combatant.loadout
	var weapon := loadout.get_weapon() if loadout != null else null
	if weapon == null:
		_attack_target = null
		return

	_apply_basic_attack_hit(weapon)
	if not state_machine.try_enter(MobaState.BASIC_ATTACK_RECOVERY, weapon.recovery):
		_attack_target = null


func _apply_basic_attack_hit(weapon: MobaWeapon) -> void:
	if _attack_target == null or not _attack_target.is_alive():
		return

	var attack_damage := _combatant.get_stat(MobaStatBlock.ATTACK_DAMAGE)
	var total_damage := MobaFormulas.basic_attack_damage(weapon.damage, attack_damage)

	# Check for BLIND miss: the attacker's own BLIND entry impairs its accuracy,
	# rolled against that entry's magnitude as a miss chance.
	var blind_type = MobaCrowdControlSpec.CCType.BLIND
	if _combatant.has_crowd_control(blind_type):
		var blind_spec: MobaCrowdControlSpec = _combatant.get_crowd_control_spec(blind_type)
		if blind_spec != null:
			var blind_roll := MobaRules.roll_blind()
			var miss_chance: float = blind_spec.magnitude
			if blind_roll < miss_chance:
				# Miss: skip apply_damage entirely; attack cycle still runs. Report
				# the same computed raw amount a hit would have, so listeners see a
				# consistent pre-mitigation figure regardless of miss/hit.
				_combatant.basic_attack_resolved.emit(
					_attack_target, total_damage, 0.0, weapon.damage_type, false
				)
				return

	var damage := MobaDamage.new(
		total_damage,
		weapon.damage_type,
		_combatant,
		true,
		_combatant.get_stat(MobaStatBlock.ARMOR_PEN_FLAT),
		_combatant.get_stat(MobaStatBlock.ARMOR_PEN_PERCENT),
		true
	)
	_attack_target.apply_damage(damage)
	_combatant.basic_attack_resolved.emit(
		_attack_target, damage.amount, damage.final_amount, damage.damage_type, damage.was_crit
	)
