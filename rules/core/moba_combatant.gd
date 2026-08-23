## Health authority, stat access, and death handling for a MOBA actor.
##
## MobaCombatant is a child of an Actor and owns the actor's MOBA rules state:
## a duplicated runtime stat block, current health, the health mutation/read seam,
## and death signaling that fires exactly once. Signals health changes into the
## parent Actor's character_sheet.
class_name MobaCombatant
extends Node

signal health_changed(current: float, maximum: float)
## Emitted when damage is resolved. Carries both raw (pre-crit, pre-mitigation)
## and final (post-mitigation) amounts, plus metadata about the damage event.
signal damage_resolved(raw: float, final: float, damage_type: int, was_crit: bool, source)
## Emitted when current or maximum resource changes.
signal resource_changed(current: float, maximum: float)
## Emitted when a basic attack hit is resolved.
signal basic_attack_resolved(target, damage_amount: float)

## Typed failure reason for activation checks.
enum ActivationFailure {
	OK = 0,
	ON_COOLDOWN = 1,
	NO_CHARGES = 2,
	INSUFFICIENT_RESOURCE = 3,
	UNKNOWN_ABILITY = 4,
}

@export var stat_block: MobaStatBlock = preload("res://rules/data/stat_blocks/baseline.tres")
## Registers the loadout's action abilities as soon as it is assigned, so a
## combatant that never enters the tree (e.g. a standalone test fixture) or
## has its loadout assigned after _ready() still resolves them without a
## separate manual register_ability() step.
@export var loadout: MobaLoadout:
	set(value):
		loadout = value
		if loadout != null:
			_register_loadout_abilities()

# Property accessors for current_resource and maximum_resource
var current_resource: float:
	get:
		return _current_resource

var maximum_resource: float:
	get:
		return get_stat(MobaStatBlock.RESOURCE)

var _runtime_stat_block: MobaStatBlock
var _current_health: float = 0.0
var _has_died: bool = false
var _current_resource: float = 0.0
var _cooldowns: MobaCooldowns = MobaCooldowns.new()
var _abilities: Dictionary = {}  # Maps ability_id (StringName) to MobaAbility
var _attack_target: Node = null
var _attack_time_since_ready: float = INF


func _ready() -> void:
	# Duplicate the stat block before any mutation
	_runtime_stat_block = stat_block.duplicate()
	_current_health = _runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	_current_resource = _runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)

	# Defer seeding the parent Actor's character_sheet because children ready before parents,
	# and the Actor's _ready() hasn't yet duplicated its character_sheet.
	# Writing it directly here would corrupt the shared resource.
	call_deferred("_seed_actor_character_sheet")


func _seed_actor_character_sheet() -> void:
	var parent_actor := get_parent() as Actor
	if parent_actor == null:
		return

	# Seed max_hp and current_hp from the stat block
	parent_actor.character_sheet.max_hp = int(
		_runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	)
	parent_actor.character_sheet.current_hp = int(_current_health)


## Get the current effective value of a stat (today equals the base value).
## Routes through an indirection that a modifier layer can later hook.
func get_stat(stat: StringName) -> float:
	return _get_modified_stat(stat)


## Get the unmodified base value of a stat.
func get_base_stat(stat: StringName) -> float:
	return _runtime_stat_block.get_stat_value(stat)


## Internal seam for stat modifications.
## Currently just returns the base value, but this is where the buff/debuff
## system will hook to apply modifiers.
func _get_modified_stat(stat: StringName) -> float:
	return _runtime_stat_block.get_stat_value(stat)


## Apply damage to the combatant via a MobaDamage packet.
##
## Resolution order (pinned per Architecture Constraints):
## 1. Raw amount
## 2. Crit roll and multiplier (if can_crit)
## 3. Damage-type routing (PHYSICAL/MAGICAL/TRUE)
## 4. Penetration against target's defense
## 5. Mitigation multiplier
## 6. Final amount
## 7. Shield seam (documented empty hook)
##
## Emits damage_resolved once per packet.
func apply_damage(damage: MobaDamage) -> void:
	var raw: float = damage.amount
	var final: float = raw
	var was_crit: bool = false

	# Step 2: Crit roll and multiplier
	if damage.can_crit:
		var crit_chance: float = get_stat(MobaStatBlock.CRIT_CHANCE)
		var crit_damage: float = get_stat(MobaStatBlock.CRIT_DAMAGE)
		var crit_roll: float = MobaRules.roll_crit()

		if MobaFormulas.is_critical(crit_roll, crit_chance):
			was_crit = true
			final = MobaFormulas.apply_crit(raw, crit_damage)
		else:
			final = raw
	else:
		final = raw

	# Step 3-6: Damage-type routing and mitigation
	match damage.damage_type:
		MobaDamage.DamageType.PHYSICAL:
			var armor: float = get_stat(MobaStatBlock.ARMOR)
			final = MobaFormulas.physical_damage(final, armor, damage.flat_pen, damage.percent_pen)

		MobaDamage.DamageType.MAGICAL:
			var resistance: float = get_stat(MobaStatBlock.MAGIC_RESISTANCE)
			final = MobaFormulas.magical_damage(
				final, resistance, damage.flat_pen, damage.percent_pen
			)

		MobaDamage.DamageType.TRUE:
			# TRUE damage ignores all defenses and penetration
			final = MobaFormulas.true_damage(final)

	# Step 7: Shield seam (documented empty hook per §16, Batch 2 sustain issue)
	# This private hook receives the final amount and returns it unchanged.
	# It exists as a placeholder for future shield implementations.
	final = _apply_shield_seam(final)

	# Reduce health
	_current_health -= final
	_update_health()

	# Emit damage_resolved
	damage_resolved.emit(raw, final, damage.damage_type, was_crit, damage.source)


## Private shield seam: documented empty hook per §16.
## This exists as a placeholder for Batch 2 sustain systems (shields, lifesteal).
## Returns the input unchanged.
func _apply_shield_seam(amount: float) -> float:
	# TODO §16: Shield mitigation hook for Batch 2
	# return amount adjusted by any active shields
	return amount


## Apply healing to the combatant.
## Increases current health but never exceeds maximum.
func apply_healing(amount: float) -> void:
	var max_health = _runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	_current_health = minf(_current_health + amount, max_health)
	_update_health()


## Check if the combatant is alive.
func is_alive() -> bool:
	return _current_health > 0.0


## Update health state and handle death.
func _update_health() -> void:
	# Mirror health into the parent Actor's character_sheet
	var parent_actor := get_parent() as Actor
	if parent_actor != null:
		parent_actor.character_sheet.current_hp = int(_current_health)

	# Emit the health changed signal
	var max_health = _runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	health_changed.emit(_current_health, max_health)

	# Handle death: call Actor.die() exactly once
	if _current_health <= 0.0 and not _has_died:
		_has_died = true
		if parent_actor != null:
			parent_actor.die()


## Get current resource value.
func get_current_resource() -> float:
	return _current_resource


## Get maximum resource value from the stat block.
func get_maximum_resource() -> float:
	return get_stat(MobaStatBlock.RESOURCE)


## Spend resource from the pool.
## Returns false and mutates nothing if amount exceeds current_resource.
## Otherwise deducts amount, emits resource_changed, and returns true.
## spend_resource(0.0) returns true even at zero current resource.
func spend_resource(amount: float) -> bool:
	if amount > _current_resource:
		return false

	_current_resource -= amount
	resource_changed.emit(_current_resource, get_stat(MobaStatBlock.RESOURCE))
	return true


## Restore resource to the pool.
## Clamps the result at maximum and emits resource_changed.
func restore_resource(amount: float) -> void:
	var max_resource = get_stat(MobaStatBlock.RESOURCE)
	_current_resource = minf(_current_resource + amount, max_resource)
	resource_changed.emit(_current_resource, max_resource)


## Register an ability for cooldown and activation tracking.
func register_ability(ability: MobaAbility) -> void:
	_abilities[StringName(ability.id)] = ability


## Get the ability id from a 1-based action slot.
## Returns empty StringName if the slot is empty or out of range.
func get_action_slot_ability_id(slot: int) -> StringName:
	if loadout == null:
		return &""
	if slot < 1 or slot > 4:
		return &""
	var ability_id_str: String = loadout.get_action_slot(slot)
	if ability_id_str == "":
		return &""
	return StringName(ability_id_str)


## Register all abilities in the loadout with this combatant.
func _register_loadout_abilities() -> void:
	for i in range(1, 5):
		var ability_id_str: String = loadout.get_action_slot(i)
		if ability_id_str != "":
			var ability := MobaAbilityLibrary.get_ability(StringName(ability_id_str))
			if ability != null:
				register_ability(ability)


## Check if an ability can be activated without side effects.
## Returns an ActivationFailure enum value indicating readiness or failure reason.
## This is a pure query: it mutates nothing, spends no resource, and starts no cooldown.
func can_activate(ability_id: StringName) -> int:
	if ability_id not in _abilities:
		return ActivationFailure.UNKNOWN_ABILITY

	var ability: MobaAbility = _abilities[ability_id]

	# Check resource
	if ability.resource_cost > _current_resource:
		return ActivationFailure.INSUFFICIENT_RESOURCE

	# Check cooldown and charges. A charge remaining while the recharge timer is
	# still running does not block activation; only being out of charges does.
	var available_charges: int = _cooldowns.charges(ability_id)
	if available_charges <= 0 and _cooldowns.remaining(ability_id) > 0.0:
		return ActivationFailure.NO_CHARGES

	return ActivationFailure.OK


## Commit an ability activation: spend resource and start cooldown atomically.
## Returns the failure reason if activation cannot proceed; spends nothing and
## starts no cooldown if not OK.
## If can_activate() returns OK, this call will succeed and spend resource + start cooldown.
func commit_activate(ability_id: StringName) -> int:
	var check: int = can_activate(ability_id)
	if check != ActivationFailure.OK:
		return check

	var ability: MobaAbility = _abilities[ability_id]

	# Spend resource
	spend_resource(ability.resource_cost)

	# Start cooldown with current haste
	var haste: float = get_stat(MobaStatBlock.ABILITY_HASTE)
	_cooldowns.start(ability_id, ability.cooldown, haste, ability.charges)

	return ActivationFailure.OK


## Advance time by delta seconds.
## Accumulates resource and health regeneration continuously (not gated by one-second intervals).
## Health regeneration clamps at maximum and emits health_changed.
## A dead combatant does not regenerate health.
## Resource regeneration always occurs (dead or alive).
## Also advances all active cooldowns.
func tick(delta: float) -> void:
	# Advance cooldowns
	_cooldowns.tick(delta)

	# Advance the sibling state machine and the basic-attack cycle together.
	# MobaCombatant.tick() is the single driver of MobaStateMachine.tick() for
	# a combatant: nothing else in rules/ ticks it. Game-side code (T4) must
	# not also call MobaStateMachine.tick() directly for a combatant driven
	# through here, or states would expire twice as fast.
	if _attack_time_since_ready != INF:
		_attack_time_since_ready += delta
	_tick_state_machine_and_basic_attack(delta)

	# Accumulate resource regeneration
	var resource_regen = get_stat(MobaStatBlock.RESOURCE_REGEN)
	var max_resource = get_stat(MobaStatBlock.RESOURCE)
	_current_resource = minf(_current_resource + resource_regen * delta, max_resource)
	resource_changed.emit(_current_resource, max_resource)

	# Accumulate health regeneration (only if alive)
	if is_alive():
		var health_regen = get_stat(MobaStatBlock.HEALTH_REGEN)
		var max_health = get_stat(MobaStatBlock.HEALTH)
		_current_health = minf(_current_health + health_regen * delta, max_health)
		_update_health()


## Whether basic_attack() may be called right now to start a new cycle: the
## state machine currently permits a basic attack and the attack-speed
## interval (1.0 / attack_speed) has elapsed since the last attack started.
## This is the minimal query the game side needs to drive repeat attacks.
func is_basic_attack_ready() -> bool:
	var state_machine := _get_state_machine()
	if state_machine == null or not state_machine.can(&"basic_attack"):
		return false
	var attack_speed := get_stat(MobaStatBlock.ATTACK_SPEED)
	if attack_speed <= 0.0:
		return false
	return _attack_time_since_ready >= 1.0 / attack_speed


func basic_attack(target: MobaCombatant) -> bool:
	var weapon := loadout.get_weapon() if loadout != null else null
	if (
		weapon == null
		or not target.is_alive()
		or not _is_in_range(target, weapon.attack_range)
		or not is_basic_attack_ready()
	):
		return false

	var state_machine := _get_state_machine()
	if not state_machine.try_enter(MobaState.BASIC_ATTACK_WINDUP, weapon.wind_up):
		return false
	_attack_target = target
	_attack_time_since_ready = 0.0
	return true


## Fail-closed: an attacker or target whose parent exposes no global_position
## is treated as out of range rather than in range, so range gating cannot be
## bypassed by an incomplete scene setup. Duck-typed via get("global_position")
## -- matching MobaAbilityAction._get_position() -- so rules/ keeps no
## outward reference to Actor.
func _is_in_range(target: MobaCombatant, range_m: float) -> bool:
	var this_position = _get_parent_position(self)
	var target_position = _get_parent_position(target)
	if this_position == null or target_position == null:
		return false
	return (this_position as Vector3).distance_to(target_position as Vector3) <= range_m


func _get_parent_position(combatant: MobaCombatant) -> Variant:
	var parent := combatant.get_parent()
	if parent == null:
		return null
	return parent.get("global_position")


func _get_state_machine() -> MobaStateMachine:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("MobaStateMachine") as MobaStateMachine


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
	var state_machine := _get_state_machine()
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
	var attack_damage := get_stat(MobaStatBlock.ATTACK_DAMAGE)
	var total_damage := MobaFormulas.basic_attack_damage(weapon.damage, attack_damage)
	var damage := MobaDamage.new(
		total_damage,
		weapon.damage_type,
		self,
		true,
		get_stat(MobaStatBlock.ARMOR_PEN_FLAT),
		get_stat(MobaStatBlock.ARMOR_PEN_PERCENT)
	)
	_attack_target.apply_damage(damage)
	basic_attack_resolved.emit(_attack_target, total_damage)
