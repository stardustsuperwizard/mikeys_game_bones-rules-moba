# gdlint:ignore = max-public-methods
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
## Emitted when healing is applied via apply_healing() and not refused.
## Carries the actual (post-clamp) amount applied.
signal healing_applied(amount: float)
## Emitted when current or maximum resource changes.
signal resource_changed(current: float, maximum: float)
## Emitted when a basic attack hit is resolved. Carries the post-mitigation resolved damage outcome.
signal basic_attack_resolved(target, raw: float, final: float, damage_type: int, was_crit: bool)
## Emitted when the shield pool changes: applied, consumed, or expired.
## Carries the post-mutation total shield amount.
signal shield_changed(total: float)

## Typed failure reason for activation checks.
enum ActivationFailure {
	OK = 0,
	ON_COOLDOWN = 1,
	NO_CHARGES = 2,
	INSUFFICIENT_RESOURCE = 3,
	UNKNOWN_ABILITY = 4,
}

## Name of the lazily created child MobaEffectContainer node.
const _EFFECT_CONTAINER_NAME := "MobaEffectContainer"
## Positive floor applied to attack_speed after modifiers.
const _MINIMUM_ATTACK_SPEED := 0.01

## The seven hard-CC types that enter/hold CROWD_CONTROLLED. SLOW (a stat-modifier
## debuff per #219) is deliberately excluded: apply_crowd_control() refuses it.
const _HARD_CC_TYPES := [
	MobaCrowdControlSpec.CCType.STUN,
	MobaCrowdControlSpec.CCType.ROOT,
	MobaCrowdControlSpec.CCType.SILENCE,
	MobaCrowdControlSpec.CCType.DISARM,
	MobaCrowdControlSpec.CCType.FEAR,
	MobaCrowdControlSpec.CCType.TAUNT,
	MobaCrowdControlSpec.CCType.BLIND,
]

## The three displacement types: one-shot forced moves via _apply_displacement(),
## never subject to the hard-CC max(remaining, new) stacking rule (#221).
const _DISPLACEMENT_TYPES := [
	MobaCrowdControlSpec.CCType.KNOCKBACK,
	MobaCrowdControlSpec.CCType.PULL,
	MobaCrowdControlSpec.CCType.KNOCK_UP,
]

## Actions gated by active hard-CC entries in can_perform_action().
const _CC_GATED_ACTIONS := [&"move", &"basic_attack", &"ability"]


## Internal entry for an active crowd control effect.
class _CCEntry:
	var type: int  # CCType enum value
	var remaining: float  # Time left in seconds
	var source: MobaCombatant  # The combatant who applied this CC
	var spec: MobaCrowdControlSpec  # The effect spec (carries magnitude for BLIND/SLOW)

	func _init(
		p_type: int, p_remaining: float, p_source: MobaCombatant, p_spec: MobaCrowdControlSpec
	) -> void:
		type = p_type
		remaining = p_remaining
		source = p_source
		spec = p_spec


## Internal entry for an active displacement effect (KNOCKBACK, PULL, KNOCK_UP).
class _DisplacementEntry:
	var type: int  # CCType enum value (KNOCKBACK, PULL, or KNOCK_UP)
	var remaining: float  # Time left in seconds
	var source: MobaCombatant  # The combatant who applied this displacement
	var spec: MobaCrowdControlSpec  # The effect spec
	var direction: Vector3  # The direction to move (normalized)
	var speed: float  # The speed in units per second
	var queued_effect: MobaCrowdControlSpec  # Optional follow-up effect (for KNOCK_UP)
	var queued_effect_source: MobaCombatant  # Source for the queued effect

	func _init(
		p_type: int,
		p_remaining: float,
		p_source: MobaCombatant,
		p_spec: MobaCrowdControlSpec,
		p_direction: Vector3,
		p_speed: float,
		p_queued_effect: MobaCrowdControlSpec = null,
		p_queued_effect_source: MobaCombatant = null,
	) -> void:
		type = p_type
		remaining = p_remaining
		source = p_source
		spec = p_spec
		direction = p_direction
		speed = p_speed
		queued_effect = p_queued_effect
		queued_effect_source = p_queued_effect_source


@export var stat_block: MobaStatBlock = preload("res://rules/data/stat_blocks/baseline.tres")

## Registers the loadout's action abilities as soon as it is assigned, so a
## combatant that never enters the tree (e.g. a standalone test fixture) or
## has its loadout assigned after _ready() still resolves them without a
## separate manual register_ability() step.
##
## Assignment duplicates the loadout (shallow copy) so each combatant holds an
## independent instance. This prevents mutations through one combatant's loadout
## from leaking to another combatant assigned the same resource file or to the
## resource Godot cached from disk. The weapon sub-resource stays deliberately
## shared across those duplicates -- MobaLoadout.weapon records why that is safe
## and what would break it. Assigning null is safe and leaves loadout null.
@export var loadout: MobaLoadout:
	set(value):
		loadout = value.duplicate() if value != null else null
		if loadout != null:
			_register_loadout_abilities()

# Property accessors for current_resource, maximum_resource, current_health, and maximum_health
var current_resource: float:
	get:
		return _current_resource

var maximum_resource: float:
	get:
		return get_stat(MobaStatBlock.RESOURCE)

var current_health: float:
	get:
		return _current_health

var maximum_health: float:
	get:
		return get_stat(MobaStatBlock.HEALTH)

var _runtime_stat_block: MobaStatBlock
var _current_health: float = 0.0
var _has_died: bool = false
var _current_resource: float = 0.0
var _cooldowns: MobaCooldowns = MobaCooldowns.new()
var _abilities: Dictionary = {}  # Maps ability_id (StringName) to MobaAbility
var _attack_target: Node = null
var _attack_time_since_ready: float = INF
var _effect_container: MobaEffectContainer = null
## Active crowd control entries keyed by CCType. Maps int (CCType) to _CCEntry.
## Multiple entries of different types can exist simultaneously; only one per type.
var _active_cc_entries: Dictionary = {}
## Active displacement entry (KNOCKBACK, PULL, or KNOCK_UP). Only one displacement
## can be active at a time. null when no displacement is active.
var _active_displacement: _DisplacementEntry = null
## Active shield pool: list of MobaShield instances, each with remaining absorption capacity.
var _active_shields: Array[MobaShield] = []
## Per-stat cache of the modifier bonuses (flat, percent), NOT the final
## value: the base is always re-read live from _runtime_stat_block so a
## direct mutation of the runtime stat block (as several existing test
## suites do) is never masked by a stale cached result. get_stat() is on the
## damage path and the movement path, so it is the container's modifier
## list -- not the stat block -- that is only scanned when it actually
## changes; any container mutation clears the whole cache through
## _invalidate_stat_cache().
var _stat_cache: Dictionary = {}

## In-progress cast ledger. Created on first use so it is available whether or
## not _ready() has run. Advanced from tick(), like the MobaCooldowns ledger.
var _cast_tracker: MobaCastTracker = null


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


## Get the current effective value of a stat: the base value with every
## active modifier in the effect container applied.
func get_stat(stat: StringName) -> float:
	return _get_modified_stat(stat)


## Get the effect container holding this combatant's active stat modifiers,
## discovering an existing child or creating one on first use. Works on a
## standalone fixture that never enters the scene tree.
func get_effect_container() -> MobaEffectContainer:
	if _effect_container != null:
		return _effect_container

	_effect_container = get_node_or_null(NodePath(_EFFECT_CONTAINER_NAME)) as MobaEffectContainer
	if _effect_container == null:
		_effect_container = MobaEffectContainer.new()
		_effect_container.name = _EFFECT_CONTAINER_NAME
		add_child(_effect_container)

	# Any container mutation makes the cached per-stat values stale.
	_effect_container.effect_applied.connect(_on_effect_container_changed)
	_effect_container.effect_refreshed.connect(_on_effect_container_changed)
	_effect_container.effect_stacks_changed.connect(_on_effect_stacks_changed)
	_effect_container.effect_expired.connect(_on_effect_container_changed)
	return _effect_container


func _on_effect_container_changed(_source_ability_id: StringName, _stat: StringName) -> void:
	_invalidate_stat_cache()


func _on_effect_stacks_changed(
	_source_ability_id: StringName, _stat: StringName, _stacks: int
) -> void:
	_invalidate_stat_cache()


## Drop every cached modifier-applied stat value.
func _invalidate_stat_cache() -> void:
	_stat_cache.clear()


## Get the unmodified base value of a stat.
func get_base_stat(stat: StringName) -> float:
	return _runtime_stat_block.get_stat_value(stat)


## Internal seam for stat modifications.
##
## Modifier order is pinned: (base + sum(flat)) * (1 + sum(percent)).
## Percentages sum additively among themselves. The (flat, percent) bonus
## pair is cached per stat and invalidated on any effect container mutation;
## the base value itself is always re-read live so a direct mutation of
## _runtime_stat_block is reflected immediately, never masked by a stale
## cached result.
func _get_modified_stat(stat: StringName) -> float:
	var bonus: Dictionary
	if stat in _stat_cache:
		bonus = _stat_cache[stat]
	else:
		var container := get_effect_container()
		bonus = {
			"flat": container.get_flat_bonus(stat), "percent": container.get_percent_bonus(stat)
		}
		_stat_cache[stat] = bonus

	var base: float = _runtime_stat_block.get_stat_value(stat)
	var value: float = (base + bonus["flat"]) * (1.0 + bonus["percent"])
	if stat == MobaStatBlock.ATTACK_SPEED:
		value = maxf(value, _MINIMUM_ATTACK_SPEED)

	return value


## Apply damage to the combatant via a MobaDamage packet.
##
## Resolution order (pinned per Architecture Constraints):
## 1. Raw amount
## 2. Crit roll and multiplier (if can_crit)
## 3. Damage-type routing (PHYSICAL/MAGICAL/TRUE)
## 4. Penetration against target's defense
## 5. Mitigation multiplier
## 6. Final amount
## 7. Shield consumption (shortest-remaining-duration first, before health)
##
## Emits damage_resolved once per packet.
func apply_damage(damage: MobaDamage) -> void:
	var raw: float = damage.amount
	var final: float = raw
	var was_crit: bool = false

	# Step 2: Crit roll and multiplier.
	#
	# Crit is the ATTACKER's statistic, so it is read off damage.source -- not
	# off self, which is the combatant taking the hit. Unattributed damage
	# (source is null, or is not a MobaCombatant) has no attacker to roll for
	# and therefore never crits.
	var attacker := damage.source as MobaCombatant
	if damage.can_crit and attacker != null:
		var crit_chance: float = attacker.get_stat(MobaStatBlock.CRIT_CHANCE)
		var crit_damage: float = attacker.get_stat(MobaStatBlock.CRIT_DAMAGE)
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

	# Step 7: Shield consumption (shortest-remaining-duration first)
	var pre_shield_final := final
	final = _consume_shields(final)
	var post_shield_final := final

	# Populate post-resolution fields on the damage packet for listeners
	damage.final_amount = final
	damage.was_crit = was_crit

	# Compute shield_absorbed and health_applied for lifesteal/omnivamp calculation
	var shield_absorbed := pre_shield_final - post_shield_final
	var current_health_before_hit := _current_health
	var health_applied := minf(post_shield_final, maxf(0.0, current_health_before_hit))
	var damage_dealt := shield_absorbed + health_applied

	# Reduce health
	_current_health -= final
	_update_health()

	# Apply lifesteal/omnivamp if attacker exists and damage was dealt
	if attacker != null and damage_dealt > 0.0:
		var lifesteal_pct := 0.0
		if damage.is_basic_attack:
			lifesteal_pct = attacker.get_stat(MobaStatBlock.LIFESTEAL)

		var omnivamp_pct := attacker.get_stat(MobaStatBlock.OMNIVAMP)
		var heal_pct := lifesteal_pct + omnivamp_pct

		if heal_pct > 0.0:
			var sustain_amount := MobaFormulas.sustain_healing(damage_dealt, heal_pct)
			attacker.apply_healing(sustain_amount)

	var attacker_name := "unattributed"
	if attacker != null and attacker.get_parent() != null:
		attacker_name = String(attacker.get_parent().name)
	var target_name := String(name)
	if get_parent() != null:
		target_name = String(get_parent().name)
	print(
		(
			"[MobaCombat] %s -> %s: %.1f raw / %.1f final (%s%s)"
			% [
				attacker_name,
				target_name,
				raw,
				final,
				MobaDamage.DamageType.keys()[damage.damage_type],
				", CRIT" if was_crit else ""
			]
		)
	)

	# Emit damage_resolved
	damage_resolved.emit(raw, final, damage.damage_type, was_crit, damage.source)


## Consume shields in order of shortest-remaining-duration first.
## Returns the remaining damage after shields absorb what they can.
## Emits shield_changed for each shield that is consumed or damaged.
func _consume_shields(incoming_damage: float) -> float:
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
			shield_changed.emit(total_shield())
		else:
			# Shield is fully consumed, remainder carries to next shield or health
			remaining_damage -= shield.amount
			_active_shields.erase(shield)
			shield_changed.emit(total_shield())

	return remaining_damage


## Apply healing to the combatant.
##
## Returns the actual amount applied (clamped to remaining health capacity).
## Returns 0.0 and mutates nothing if the combatant is dead. Emits healing_applied
## with the actual (post-clamp) amount whenever healing is not refused, including
## 0.0 when already at full health.
func apply_healing(amount: float) -> float:
	# Refuse healing on dead combatants
	if not is_alive():
		return 0.0

	# Compute the actual amount using the clamp formula
	var max_health = _runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	var actual_amount := MobaFormulas.clamped_heal(_current_health, max_health, amount)

	# Apply the healing
	_current_health += actual_amount
	_update_health()

	# Emit the healing_applied signal with the actual amount
	healing_applied.emit(actual_amount)

	return actual_amount


## Return the total absorption capacity from all active shields.
func total_shield() -> float:
	var total: float = 0.0
	for shield in _active_shields:
		total += shield.amount
	return total


## Apply a new shield to the combatant.
## A no-op if amount <= 0.0. Emits shield_changed with the post-mutation total.
func apply_shield(amount: float, source: StringName, duration: float) -> void:
	if amount <= 0.0:
		return

	var shield := MobaShield.new(amount, source, duration)
	_active_shields.append(shield)
	shield_changed.emit(total_shield())


## Apply crowd control to this combatant from a source.
##
## Routes the three displacement types (KNOCKBACK/PULL/KNOCK_UP) to
## _apply_displacement() and the seven hard-CC types (STUN/ROOT/SILENCE/DISARM/
## FEAR/TAUNT/BLIND) to _apply_hard_cc(). SLOW is a stat-modifier debuff (#219)
## and any other type is refused. Refuses outright if DEAD (terminal per #25).
##
## Both paths respect affected_by_tenacity via MobaFormulas.crowd_control_duration().
## Hard CC tracks per-CCType entries under the max(remaining, new_duration) rule
## and lives in CROWD_CONTROLLED; displacement is a one-shot forced move that is
## never subject to that stacking rule -- see _apply_displacement() and
## _apply_hard_cc() for the rest of each path's contract.
func apply_crowd_control(spec: MobaCrowdControlSpec, source: MobaCombatant) -> void:
	if not is_alive():
		return

	var state_machine := _get_state_machine()

	if spec.type in _DISPLACEMENT_TYPES:
		_apply_displacement(spec, source, state_machine)
	elif spec.type in _HARD_CC_TYPES:
		_apply_hard_cc(spec, source, state_machine)
	# SLOW and any unrecognized type are refused.


## Apply a displacement crowd control effect (KNOCKBACK, PULL, KNOCK_UP).
##
## Replaces any existing displacement outright (last write wins; unlike hard CC,
## displacement is never subject to the max(remaining, new) stacking rule since
## it resolves as a one-shot forced move, not a held duration).
##
## spec.magnitude is a validated 0.0-1.0 fraction (rules/tools/validate_ability_data.gd),
## the same "fraction of full effect" semantics SLOW already applies to movement_speed.
## Here it is a fraction of the body's own ActorBody3D.SPEED, so a 0.0 magnitude
## means no forced movement rather than an unexplained default speed.
##
## KNOCK_UP additionally enters AIRBORNE with cause KNOCK_UP. KNOCKBACK/PULL
## instead interrupt a "displacement_only" state (currently only DASHING) by
## cutting it short into IDLE -- that state leaving is the interrupt itself,
## since only displacement is ever accepted against that policy (#220).
func _apply_displacement(
	spec: MobaCrowdControlSpec, source: MobaCombatant, state_machine: MobaStateMachine
) -> void:
	var final_duration := spec.duration
	if spec.affected_by_tenacity:
		var tenacity := get_stat(MobaStatBlock.TENACITY)
		final_duration = MobaFormulas.crowd_control_duration(spec.duration, tenacity)

	var away := spec.type != MobaCrowdControlSpec.CCType.PULL
	var direction := _compute_displacement_direction(source, away)
	var speed := spec.magnitude * ActorBody3D.SPEED

	_active_displacement = _DisplacementEntry.new(
		spec.type, final_duration, source, spec, direction, speed
	)

	if state_machine == null:
		return

	if spec.type == MobaCrowdControlSpec.CCType.KNOCK_UP:
		state_machine.try_enter(
			MobaState.AIRBORNE, final_duration, MobaState.AirborneCause.KNOCK_UP
		)
	elif state_machine.hard_cc_policy() == &"displacement_only":
		state_machine.try_enter(MobaState.IDLE)


## Apply a hard crowd control effect (STUN, ROOT, SILENCE, DISARM, FEAR, TAUNT, BLIND).
func _apply_hard_cc(
	spec: MobaCrowdControlSpec, source: MobaCombatant, state_machine: MobaStateMachine
) -> void:
	# If we're in ABILITY_CAST and the current ability is cancellable_by_hard_cc,
	# cancel the cast before applying the CC.
	if state_machine != null and state_machine.current_state == MobaState.ABILITY_CAST:
		var casting := _get_cast_tracker()
		if casting.is_casting() and casting.current_ability().cancellable_by_hard_cc:
			cancel_cast()

	# Consult state machine policy for hard-CC types
	var policy := state_machine.hard_cc_policy() if state_machine != null else &"no"
	if policy == &"no" or policy == &"displacement_only":
		return

	# Enter CROWD_CONTROLLED (durationless state) if not already there
	# "yes" and "breaks_channel" both permit entry
	if state_machine != null:
		if state_machine.current_state != MobaState.CROWD_CONTROLLED:
			state_machine.try_enter(MobaState.CROWD_CONTROLLED)

	# Compute final duration
	var final_duration := spec.duration
	if spec.affected_by_tenacity:
		var tenacity := get_stat(MobaStatBlock.TENACITY)
		final_duration = MobaFormulas.crowd_control_duration(spec.duration, tenacity)

	# Track the entry (max(remaining, new_duration) rule for same CCType)
	var cc_type := spec.type
	if cc_type in _active_cc_entries:
		var existing_entry = _active_cc_entries[cc_type]
		existing_entry.remaining = maxf(existing_entry.remaining, final_duration)
		existing_entry.source = source
		existing_entry.spec = spec
	else:
		var new_entry = _CCEntry.new(cc_type, final_duration, source, spec)
		_active_cc_entries[cc_type] = new_entry


## Compute a normalized displacement direction between this combatant and source:
## away=true points from source to this (KNOCKBACK/KNOCK_UP), away=false points
## from this to source (PULL). Falls back to Vector3.BACK/FORWARD respectively
## when either position cannot be determined or the two positions coincide.
func _compute_displacement_direction(source: MobaCombatant, away: bool) -> Vector3:
	var default := Vector3.BACK if away else Vector3.FORWARD
	var this_pos = _get_parent_position(self)
	var source_pos = _get_parent_position(source)

	if this_pos == null or source_pos == null:
		return default

	var delta: Vector3 = (
		(this_pos as Vector3) - (source_pos as Vector3)
		if away
		else (source_pos as Vector3) - (this_pos as Vector3)
	)
	return delta.normalized() if delta.length() > 0.0 else default


## Query whether the combatant can perform an action right now, accounting for active crowd control.
##
## While CROWD_CONTROLLED, a CC-gated action's answer REPLACES the state table's
## conservative per_cc -> false with the precise union (OR) of active hard-CC entries'
## per-effect flags, per MobaCrowdControl -- this is the whole reason MobaStateMachine.can()
## deliberately stays generic there. Outside CROWD_CONTROLLED, a live entry can still exist
## if some other try_enter() (e.g. completing a basic-attack cycle a non-blocking CC type
## like BLIND permitted) moved the combatant out while it was ticking; there the CC union
## is INTERSECTED with, not substituted for, the current real state's own legality, so e.g.
## a new attack mid-windup is still forbidden regardless of what CC allows. Every other
## action, and every case with no active entries, delegates straight to state_machine.can(action).
func can_perform_action(action: StringName) -> bool:
	var state_machine := _get_state_machine()
	if state_machine == null:
		return false

	if state_machine.current_state == MobaState.CROWD_CONTROLLED and action in _CC_GATED_ACTIONS:
		return not _active_cc_blocks(action)

	if action in _CC_GATED_ACTIONS and not _active_cc_entries.is_empty():
		return state_machine.can(action) and not _active_cc_blocks(action)

	return state_machine.can(action)


## Whether any active hard-CC entry blocks `action`. Only called for the
## CC-gated actions (move/basic_attack/ability) with at least one active entry.
func _active_cc_blocks(action: StringName) -> bool:
	var blocked := false
	match action:
		&"move":
			for cc_entry in _active_cc_entries.values():
				blocked = blocked or MobaCrowdControl.blocks_move(cc_entry.type)
		&"basic_attack":
			for cc_entry in _active_cc_entries.values():
				blocked = blocked or MobaCrowdControl.blocks_basic_attack(cc_entry.type)
		&"ability":
			for cc_entry in _active_cc_entries.values():
				blocked = blocked or MobaCrowdControl.blocks_ability(cc_entry.type)
	return blocked


## Check if this combatant currently has an active crowd control entry of a given type.
## Returns true if the type is active, false otherwise.
func has_crowd_control(cc_type: int) -> bool:
	return cc_type in _active_cc_entries


## Get the source combatant of an active crowd control entry.
## Returns the source MobaCombatant, or null if the type is not active.
func get_crowd_control_source(cc_type: int) -> MobaCombatant:
	if cc_type not in _active_cc_entries:
		return null
	var entry = _active_cc_entries[cc_type]
	return entry.source


## Get the spec of an active crowd control entry.
## Returns the MobaCrowdControlSpec, or null if the type is not active.
func get_crowd_control_spec(cc_type: int) -> MobaCrowdControlSpec:
	if cc_type not in _active_cc_entries:
		return null
	var entry = _active_cc_entries[cc_type]
	return entry.spec


## Forced movement direction/magnitude while a displacement is active, scaled by
## speed / ActorBody3D.SPEED so ActorBody3D._physics_process()'s unmodified
## velocity.x = move_direction.x * SPEED formula covers the authored distance
## over the authored duration, not always base walking speed. Vector3.ZERO
## when no displacement is active. A Controller consumes this directly (#222).
func get_forced_move_direction() -> Vector3:
	if _active_displacement == null:
		return Vector3.ZERO

	return _active_displacement.direction * (_active_displacement.speed / ActorBody3D.SPEED)


## Queue a follow-up crowd control effect applied when a knock-up lands (e.g.
## knock-up then stun). No-op unless the active displacement is KNOCK_UP.
func queue_follow_up_effect_for_displacement(
	effect_spec: MobaCrowdControlSpec, source: MobaCombatant
) -> void:
	if (
		_active_displacement == null
		or _active_displacement.type != MobaCrowdControlSpec.CCType.KNOCK_UP
	):
		return

	_active_displacement.queued_effect = effect_spec
	_active_displacement.queued_effect_source = source


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


## Get the remaining cooldown time for an ability, in seconds.
## Pure query. Returns 0.0 for an ability id whose cooldown was never started.
func get_cooldown_remaining(ability_id: StringName) -> float:
	return _cooldowns.remaining(ability_id)


## Get the effective, haste-adjusted duration of the running cooldown timer.
## Pure query. Returns 0.0 for an ability id whose cooldown was never started.
## Divide get_cooldown_remaining() by this to compute a HUD sweep fraction.
func get_cooldown_duration(ability_id: StringName) -> float:
	return _cooldowns.duration(ability_id)


## Get the number of available charges for an ability.
## Pure query. Returns 0 for an unknown ability id.
func get_charges(ability_id: StringName) -> int:
	return _cooldowns.charges(ability_id)


## Get the maximum number of charges recorded for an ability.
## Pure query. Returns 0 for an unknown ability id.
func get_max_charges(ability_id: StringName) -> int:
	return _cooldowns.maximum_charges(ability_id)


## Get the registered MobaAbility behind an ability id.
## Pure query. Returns null for an unregistered id without pushing an error.
func get_ability(ability_id: StringName) -> MobaAbility:
	if ability_id not in _abilities:
		return null
	return _abilities[ability_id]


## Get the configured passive ability id from the assigned loadout.
## Pure query. Returns &"" when no loadout is assigned or the passive slot is empty.
func get_passive_slot_id() -> StringName:
	if loadout == null:
		return &""
	var passive_id_str: String = loadout.get_passive_slot()
	if passive_id_str == "":
		return &""
	return StringName(passive_id_str)


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
		# A single-charge ability (max_charges <= 1) that is out of charges is
		# simply on cooldown; NO_CHARGES is reserved for a multi-charge ability
		# that has spent every charge while its recharge timer is still running.
		if _cooldowns.maximum_charges(ability_id) <= 1:
			return ActivationFailure.ON_COOLDOWN
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


## The in-progress cast ledger for this combatant, created on first use.
func _get_cast_tracker() -> MobaCastTracker:
	if _cast_tracker == null:
		_cast_tracker = MobaCastTracker.new(self)
	return _cast_tracker


## True while this combatant has a cast in progress.
func is_casting() -> bool:
	return _get_cast_tracker().is_casting()


## Start a cast that will resolve after its cast_time elapses via tick().
## Called by MobaAbilityAction when an ability with cast_time > 0 is activated.
func start_cast(
	ability_id: StringName, ability: MobaAbility, resolved_target: Node, cast_time: float
) -> void:
	_get_cast_tracker().start(ability_id, ability, resolved_target, cast_time)


## Cancel an in-progress cast and apply the on_cancel outcome (resource refund,
## cooldown change). A no-op if no cast is in progress. Returns without error.
func cancel_cast() -> void:
	_get_cast_tracker().cancel()


## Reverse the cooldown started at commit for one ability, as if it never started.
## Used by the cast tracker when an interrupted cast's on_cancel undoes the cooldown.
func cancel_cooldown(ability_id: StringName) -> void:
	_cooldowns.cancel(ability_id)


## Advance time by delta seconds.
## Accumulates resource and health regeneration continuously (not gated by one-second intervals).
## Health regeneration clamps at maximum and emits health_changed.
## A dead combatant does not regenerate health.
## Resource regeneration always occurs (dead or alive).
## Also advances all active cooldowns and crowd control durations.
func tick(delta: float) -> void:
	# Advance in-progress cast and resolve if it reaches its expiry point.
	# Resolution wins ties: if a cast reaches resolution during this tick(),
	# it resolves synchronously before anything else observes it as in progress.
	_get_cast_tracker().tick(delta)

	# Advance cooldowns
	_cooldowns.tick(delta)

	# Advance active stat modifiers so timed effects expire on the caller's clock.
	get_effect_container().tick(delta)

	# Advance shield durations and expire shields
	_tick_shields(delta)

	# Advance crowd control durations and expire entries
	_tick_crowd_control(delta)

	# Advance the sibling state machine and the basic-attack cycle together.
	# MobaCombatant.tick() is the single driver of MobaStateMachine.tick() for
	# a combatant: nothing else in rules/ ticks it. Game-side code (T4) must
	# not also call MobaStateMachine.tick() directly for a combatant driven
	# through here, or states would expire twice as fast.
	if _attack_time_since_ready != INF:
		_attack_time_since_ready += delta
	_tick_state_machine_and_basic_attack(delta)

	# Accumulate resource regeneration.
	#
	# Both regeneration blocks below only emit when the value actually moved.
	# At full resource or full health the clamp makes the new value identical
	# to the old one, and emitting anyway would fire both signals on every
	# physics frame for every combatant -- re-rendering the HUD bars and
	# rebuilding the tooltip sixty times a second to say nothing changed.
	var resource_regen = get_stat(MobaStatBlock.RESOURCE_REGEN)
	var max_resource = get_stat(MobaStatBlock.RESOURCE)
	var new_resource = minf(_current_resource + resource_regen * delta, max_resource)
	if new_resource != _current_resource:
		_current_resource = new_resource
		resource_changed.emit(_current_resource, max_resource)

	# Accumulate health regeneration (only if alive).
	#
	# Skipping _update_health() on a no-op also stops this from writing over
	# the parent Actor's character_sheet.current_hp every frame. That mirror
	# write is correct when health really changed and destructive when it did
	# not: anything else that decremented current_hp between two ticks was
	# silently reset to this combatant's value.
	if is_alive():
		var health_regen = get_stat(MobaStatBlock.HEALTH_REGEN)
		var max_health = get_stat(MobaStatBlock.HEALTH)
		var new_health = minf(_current_health + health_regen * delta, max_health)
		if new_health != _current_health:
			_current_health = new_health
			_update_health()


## Advance shield durations and remove expired shields.
## Emits shield_changed when any shields expire during this tick.
func _tick_shields(delta: float) -> void:
	var shields_before := _active_shields.size()

	# Advance all shield durations
	for i in range(_active_shields.size() - 1, -1, -1):
		var shield = _active_shields[i]
		shield.remaining -= delta
		if shield.remaining <= 0.0:
			_active_shields.remove_at(i)

	# Emit shield_changed if any shields expired
	if _active_shields.size() < shields_before:
		shield_changed.emit(total_shield())


## Advance crowd control durations and expire entries.
## For hard CC: Returns to IDLE once the last active entry expires.
## For displacement: Expires displacement when duration is reached, and for KNOCK_UP,
## applies any queued follow-up effect when transitioning from AIRBORNE to IDLE.
func _tick_crowd_control(delta: float) -> void:
	var state_machine := _get_state_machine()

	# Advance all hard CC entries
	for cc_type in _active_cc_entries.keys():
		var entry = _active_cc_entries[cc_type]
		entry.remaining -= delta
		if entry.remaining <= 0.0:
			_active_cc_entries.erase(cc_type)

	# If no hard CC entries remain, return to IDLE (if we're in CROWD_CONTROLLED)
	if _active_cc_entries.is_empty() and state_machine != null:
		if state_machine.current_state == MobaState.CROWD_CONTROLLED:
			state_machine.try_enter(MobaState.IDLE)

	# Advance displacement entry
	if _active_displacement != null:
		_active_displacement.remaining -= delta
		if _active_displacement.remaining <= 0.0:
			# Displacement is expiring
			var was_knock_up := _active_displacement.type == MobaCrowdControlSpec.CCType.KNOCK_UP
			var queued_effect := _active_displacement.queued_effect
			var queued_effect_source := _active_displacement.queued_effect_source
			_active_displacement = null

			# For KNOCK_UP, handle landing logic
			if was_knock_up and state_machine != null:
				if state_machine.current_state == MobaState.AIRBORNE:
					# Transition to IDLE (the state machine handles this)
					state_machine.try_enter(MobaState.IDLE)

					# Apply any queued follow-up effect on landing
					if queued_effect != null:
						apply_crowd_control(queued_effect, queued_effect_source)


## Whether basic_attack() may be called right now to start a new cycle: the
## combatant currently permits a basic attack (accounting for crowd control)
## and the attack-speed interval (1.0 / attack_speed) has elapsed since the last attack started.
## This is the minimal query the game side needs to drive repeat attacks.
func is_basic_attack_ready() -> bool:
	if not can_perform_action(&"basic_attack"):
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

	# Check for BLIND miss: the attacker's own BLIND entry impairs its accuracy,
	# rolled against that entry's magnitude as a miss chance.
	var blind_type = MobaCrowdControlSpec.CCType.BLIND
	if has_crowd_control(blind_type):
		var blind_spec: MobaCrowdControlSpec = get_crowd_control_spec(blind_type)
		if blind_spec != null:
			var blind_roll := MobaRules.roll_blind()
			var miss_chance: float = blind_spec.magnitude
			if blind_roll < miss_chance:
				# Miss: skip apply_damage entirely; attack cycle still runs. Report
				# the same computed raw amount a hit would have, so listeners see a
				# consistent pre-mitigation figure regardless of miss/hit.
				basic_attack_resolved.emit(
					_attack_target, total_damage, 0.0, weapon.damage_type, false
				)
				return

	var damage := MobaDamage.new(
		total_damage,
		weapon.damage_type,
		self,
		true,
		get_stat(MobaStatBlock.ARMOR_PEN_FLAT),
		get_stat(MobaStatBlock.ARMOR_PEN_PERCENT),
		true
	)
	_attack_target.apply_damage(damage)
	basic_attack_resolved.emit(
		_attack_target, damage.amount, damage.final_amount, damage.damage_type, damage.was_crit
	)
