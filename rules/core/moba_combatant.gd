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
## and final (post-mitigation) amounts, plus metadata about the damage event,
## and the amount absorbed by shields.
signal damage_resolved(
	raw: float, final: float, damage_type: int, was_crit: bool, source, shield_absorbed: float
)
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

## Respawn policy controlling auto-respawn behavior, delay, and spawn location.
## Left unassigned (null) means the combatant never auto-respawns. The policy
## is read-only after assignment; respawn() may be called manually regardless.
@export var respawn_policy: MobaRespawnPolicy = null

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
var _current_resource: float = 0.0
var _cooldowns: MobaCooldowns = MobaCooldowns.new()
var _abilities: Dictionary = {}  # Maps ability_id (StringName) to MobaAbility
var _effect_container: MobaEffectContainer = null
## Crowd control ledger: hard-CC entries and the active displacement.
## Created on first use, like the trackers below.
var _crowd_control_tracker: MobaCrowdControlTracker = null
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

## In-progress channel ledger. Created on first use so it is available whether or
## not _ready() has run. Advanced from tick(), like the MobaCooldowns ledger.
var _channel_tracker: MobaChannelTracker = null

## Death/respawn ledger. Created on first use so it is available whether or
## not _ready() has run, like the cast/channel trackers above.
var _death_handler: MobaDeathHandler = null

## Shield pool ledger. Created on first use, like the trackers above.
var _shield_tracker: MobaShieldTracker = null

## Basic-attack wind-up/recovery cycle. Created on first use, like the
## trackers above.
var _basic_attack_cycle: MobaBasicAttackCycle = null


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
## Returns early and emits nothing if the combatant is not alive (DEAD state).
## Otherwise, resolution order (pinned per Architecture Constraints):
## 1. Raw amount
## 2. Crit roll and multiplier (if can_crit)
## 3. Damage-type routing (PHYSICAL/MAGICAL/TRUE)
## 4. Penetration against target's defense
## 5. Mitigation multiplier
## 6. Final amount
## 7. Shield consumption (shortest-remaining-duration first, before health)
##
## Emits damage_resolved once per packet (if not dead).
func apply_damage(damage: MobaDamage) -> void:
	# Refuse damage on dead combatants: this is what makes "two lethal hits in one
	# physics frame" fire death exactly once (the first hit transitions to DEAD,
	# the second is refused by the alive check here, not by comparing health magnitude).
	if not is_alive():
		return

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
	final = _get_shield_tracker().consume(final)
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
	damage_resolved.emit(raw, final, damage.damage_type, was_crit, damage.source, shield_absorbed)


## The death/respawn ledger for this combatant, created on first use.
func _get_death_handler() -> MobaDeathHandler:
	if _death_handler == null:
		_death_handler = MobaDeathHandler.new(self)
	return _death_handler


## True once death has fired for the combatant's current life (reset by
## respawn()). Exposed for MobaDeathHandler's own consumers (e.g. tests) that
## need to observe the flag without reaching into the handler directly.
func has_died() -> bool:
	return _get_death_handler().has_died()


## Restore the combatant from DEAD to full health/resource and clear all cooldowns.
## Moves the body to the policy's spawn point and returns to IDLE.
##
## Returns false if not currently DEAD (no state change); this is the only
## refusal condition. If no respawn_policy is assigned, or its spawn_point is
## null, the body is left at its current transform instead of being moved --
## respawn_policy separately gates *auto*-respawn eligibility in
## MobaDeathHandler.tick_respawn_countdown(), so a manually-triggered respawn()
## with no assigned policy is a no-op-in-place, not a refusal.
##
## Called automatically after a delay if respawn_policy.respawns is true; can also
## be called manually regardless of policy. Implemented by MobaDeathHandler.
func respawn() -> bool:
	return _get_death_handler().respawn()


## Whether the sibling state machine currently reports DEAD.
## Used by MobaDeathHandler.respawn() to enforce the "must be DEAD to
## respawn" rule without the handler reaching into the state machine wiring.
func is_dead() -> bool:
	var state_machine := get_state_machine()
	return state_machine != null and state_machine.current_state == MobaState.DEAD


## Transition the sibling state machine from DEAD back to IDLE. Returns the
## state machine's revive() result, or false if there is no state machine.
## Used by MobaDeathHandler.respawn() after death-cleanup state is restored.
func revive_state() -> bool:
	var state_machine := get_state_machine()
	if state_machine == null:
		return false
	return state_machine.revive()


## Clear all active effects/modifiers, shields, crowd control, and
## displacement, without emitting shield_changed -- callers emit that
## themselves once, after any other changes made in the same operation.
## Used by MobaDeathHandler for both death finalization and respawn.
func clear_all_active_effects() -> void:
	get_effect_container().clear_all()
	_get_shield_tracker().clear()
	_get_crowd_control_tracker().clear()


## Restore health and resource to maximum. Used by MobaDeathHandler.respawn().
func restore_to_full() -> void:
	_current_health = _runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	_current_resource = _runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)


## Clear all active cooldowns. Used by MobaDeathHandler.respawn().
func clear_all_cooldowns() -> void:
	_cooldowns.clear_all_cooldowns()


## Re-emit shield_changed with the current total. Used by MobaDeathHandler
## after clearing shields directly (on death and on respawn), so listeners
## see the post-mutation total.
func notify_shield_changed() -> void:
	shield_changed.emit(total_shield())


## Emit health_changed and resource_changed with current/maximum values.
## Used by MobaDeathHandler.respawn() after restoring health/resource to maximum.
func notify_health_and_resource_changed() -> void:
	health_changed.emit(_current_health, maximum_health)
	resource_changed.emit(_current_resource, maximum_resource)


## Mirror current_health into the parent Actor's character_sheet, if a parent
## Actor is attached. Shared by _update_health() and MobaDeathHandler.respawn()
## so both write through the same seam.
func sync_character_sheet_hp() -> void:
	var parent_actor := get_parent() as Actor
	if parent_actor != null:
		parent_actor.character_sheet.current_hp = int(_current_health)


## The shield pool ledger for this combatant, created on first use.
func _get_shield_tracker() -> MobaShieldTracker:
	if _shield_tracker == null:
		_shield_tracker = MobaShieldTracker.new(self)
	return _shield_tracker


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
	return _get_shield_tracker().total()


## The live list of active shields, for read-only inspection (e.g. tests).
func get_active_shields() -> Array[MobaShield]:
	return _get_shield_tracker().get_shields()


## Apply a new shield to the combatant.
## A no-op if amount <= 0.0 or the combatant is dead (terminal per #25; a dead
## combatant's shields were already cleared on death and must not come back
## before respawn()). Emits shield_changed with the post-mutation total.
func apply_shield(amount: float, source: StringName, duration: float) -> void:
	if not is_alive():
		return

	_get_shield_tracker().apply(amount, source, duration)


## Apply a stat-modifying effect (buff or debuff) to this combatant.
## Returns false and mutates nothing if the combatant is dead (terminal per
## #25; a dead combatant's modifiers were already cleared on death and must
## not come back before respawn()). Otherwise delegates to
## MobaEffectContainer.apply_modifier() and returns its result.
##
## The sole seam callers (e.g. MobaAbilityAction._apply_effects_seam()) use
## to apply a buff/debuff -- MobaEffectContainer itself stays alive-agnostic
## so this is the one place "is this combatant eligible to receive effects"
## is decided, matching apply_damage()/apply_healing()/apply_shield()/
## apply_crowd_control()'s existing pattern.
func apply_stat_modifier(
	modifier: MobaStatModifier, source_ability_id: StringName, is_debuff: bool = false
) -> bool:
	if not is_alive():
		return false

	return get_effect_container().apply_modifier(modifier, source_ability_id, is_debuff)


## The crowd control ledger for this combatant, created on first use.
func _get_crowd_control_tracker() -> MobaCrowdControlTracker:
	if _crowd_control_tracker == null:
		_crowd_control_tracker = MobaCrowdControlTracker.new(self)
	return _crowd_control_tracker


## Apply crowd control to this combatant from a source.
##
## Routes the three displacement types (KNOCKBACK/PULL/KNOCK_UP) and the seven
## hard-CC types (STUN/ROOT/SILENCE/DISARM/FEAR/TAUNT/BLIND) through
## MobaCrowdControlTracker. SLOW is a stat-modifier debuff (#219) and any other
## type is refused. Refuses outright if DEAD (terminal per #25).
##
## Both paths respect affected_by_tenacity via MobaFormulas.crowd_control_duration().
## Hard CC tracks per-CCType entries under the max(remaining, new_duration) rule
## and lives in CROWD_CONTROLLED; displacement is a one-shot forced move that is
## never subject to that stacking rule -- see MobaCrowdControlTracker for the
## rest of each path's contract.
func apply_crowd_control(spec: MobaCrowdControlSpec, source: MobaCombatant) -> void:
	if not is_alive():
		return

	_get_crowd_control_tracker().apply(spec, source)


## Cancel an in-progress cast or channel when hard CC lands, if the ability in
## progress declares itself cancellable_by_hard_cc.
##
## Called by MobaCrowdControlTracker before it applies a hard-CC entry. The
## tracker owns the CC ledger, but reaching into the cast and channel trackers
## is this combatant's business -- every other extracted tracker talks to it
## through its public methods only (see MobaDeathHandler), so the interrupt
## stays here behind one seam rather than becoming a second way in.
func interrupt_for_hard_crowd_control() -> void:
	var state_machine := get_state_machine()

	# If we're in ABILITY_CAST and the current ability is cancellable_by_hard_cc,
	# cancel the cast before applying the CC.
	if state_machine != null and state_machine.current_state == MobaState.ABILITY_CAST:
		var casting := _get_cast_tracker()
		if casting.is_casting() and casting.current_ability().cancellable_by_hard_cc:
			cancel_cast()

	# If we're in ABILITY_CHANNEL and the current ability is cancellable_by_hard_cc,
	# break the channel before applying the CC.
	if state_machine != null and state_machine.current_state == MobaState.ABILITY_CHANNEL:
		var channeling := _get_channel_tracker()
		if channeling.is_channeling() and channeling.current_ability().cancellable_by_hard_cc:
			break_channel()


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
	var state_machine := get_state_machine()
	if state_machine == null:
		return false

	var crowd_control := _get_crowd_control_tracker()
	var gated := crowd_control.gates_action(action)

	if state_machine.current_state == MobaState.CROWD_CONTROLLED and gated:
		return not crowd_control.blocks_action(action)

	if gated and not crowd_control.is_empty():
		return state_machine.can(action) and not crowd_control.blocks_action(action)

	return state_machine.can(action)


## Check if this combatant currently has an active crowd control entry of a given type.
## Returns true if the type is active, false otherwise.
func has_crowd_control(cc_type: int) -> bool:
	return _get_crowd_control_tracker().has(cc_type)


## Whether any hard-CC entry at all is active, for read-only inspection
## (e.g. tests asserting that death cleared crowd control).
func has_any_crowd_control() -> bool:
	return not _get_crowd_control_tracker().is_empty()


## Get the source combatant of an active crowd control entry.
## Returns the source MobaCombatant, or null if the type is not active.
func get_crowd_control_source(cc_type: int) -> MobaCombatant:
	return _get_crowd_control_tracker().get_source(cc_type)


## Get the spec of an active crowd control entry.
## Returns the MobaCrowdControlSpec, or null if the type is not active.
func get_crowd_control_spec(cc_type: int) -> MobaCrowdControlSpec:
	return _get_crowd_control_tracker().get_spec(cc_type)


## Whether a displacement (KNOCKBACK, PULL, or KNOCK_UP) is currently active,
## for read-only inspection (e.g. tests).
func has_displacement() -> bool:
	return _get_crowd_control_tracker().has_displacement()


## Remaining seconds for an active hard-crowd-control entry, or 0.0 if inactive.
func get_crowd_control_remaining(cc_type: int) -> float:
	return _get_crowd_control_tracker().get_remaining(cc_type)


## Forced movement direction/magnitude while a displacement is active, scaled by
## speed / ActorBody3D.SPEED so ActorBody3D._physics_process()'s unmodified
## velocity.x = move_direction.x * SPEED formula covers the authored distance
## over the authored duration, not always base walking speed. Vector3.ZERO
## when no displacement is active. A Controller consumes this directly (#222).
func get_forced_move_direction() -> Vector3:
	return _get_crowd_control_tracker().forced_move_direction()


## Queue a follow-up crowd control effect applied when a knock-up lands (e.g.
## knock-up then stun). No-op unless the active displacement is KNOCK_UP.
func queue_follow_up_effect_for_displacement(
	effect_spec: MobaCrowdControlSpec, source: MobaCombatant
) -> void:
	_get_crowd_control_tracker().queue_follow_up_effect(effect_spec, source)


## Check if the combatant is alive.
func is_alive() -> bool:
	return _current_health > 0.0


## Update health state and handle death.
func _update_health() -> void:
	# Mirror health into the parent Actor's character_sheet
	sync_character_sheet_hp()

	# Emit the health changed signal
	var max_health = _runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	health_changed.emit(_current_health, max_health)

	# Handle death: transition to DEAD state exactly once
	# This replaces the old Actor.die() call, intercepting death at the MobaCombatant
	# level so the actor node is never freed and respawn can restore it.
	#
	# The death handler's flag is set only once try_enter() actually succeeds
	# (not before): a rejected DEAD transition must leave the combatant free
	# to try again on the next damage instance, not permanently stuck at <=0
	# health and never dead.
	if _current_health <= 0.0 and not _get_death_handler().has_died():
		var state_machine := get_state_machine()
		if state_machine != null:
			if state_machine.try_enter(MobaState.DEAD):
				_get_death_handler().clear_on_death()


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

	# For a channeled ability, resource_cost is the per-tick cost: each tick
	# (including the first, at t = 0) spends it independently, so commit must
	# not also spend it here or the first tick would be charged twice.
	if ability.channel_duration <= 0.0:
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


## The ability currently being cast, or null when not casting.
func get_casting_ability() -> MobaAbility:
	return _get_cast_tracker().current_ability()


## Seconds remaining in the current cast, or 0.0 when not casting.
func get_cast_time_remaining() -> float:
	return _get_cast_tracker().get_cast_time_remaining()


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


## The in-progress channel ledger for this combatant, created on first use.
func _get_channel_tracker() -> MobaChannelTracker:
	if _channel_tracker == null:
		_channel_tracker = MobaChannelTracker.new(self)
	return _channel_tracker


## True while this combatant has a channel in progress.
func is_channeling() -> bool:
	return _get_channel_tracker().is_channeling()


## The ability currently being channeled, or null when not channeling.
func get_channeling_ability() -> MobaAbility:
	return _get_channel_tracker().current_ability()


## Seconds remaining in the current channel, or 0.0 when not channeling.
func get_channel_time_remaining() -> float:
	return _get_channel_tracker().get_channel_time_remaining()


## Start a channel that will tick according to channel_tick_interval via tick().
## Called by MobaAbilityAction when an ability with channel_duration > 0 is activated.
func start_channel(
	ability_id: StringName, ability: MobaAbility, resolved_target: Node, channel_duration: float
) -> void:
	_get_channel_tracker().start(ability_id, ability, resolved_target, channel_duration)


## Break an in-progress channel and apply the on_channel_break outcome.
## A no-op if no channel is in progress.
func break_channel() -> void:
	_get_channel_tracker().break_channel()


## Advance time by delta seconds.
## Accumulates resource and health regeneration continuously (not gated by one-second intervals).
## Health regeneration clamps at maximum and emits health_changed.
## A dead combatant does not regenerate health.
## Resource regeneration always occurs (dead or alive).
## Also advances all active cooldowns and crowd control durations.
## While DEAD, advances the auto-respawn countdown if the policy allows it.
func tick(delta: float) -> void:
	var state_machine := get_state_machine()

	# Advance auto-respawn countdown if DEAD and policy allows auto-respawn
	if state_machine != null and state_machine.current_state == MobaState.DEAD:
		_get_death_handler().tick_respawn_countdown(delta)

	# Advance in-progress cast and resolve if it reaches its expiry point.
	# Resolution wins ties: if a cast reaches resolution during this tick(),
	# it resolves synchronously before anything else observes it as in progress.
	_get_cast_tracker().tick(delta)

	# Advance in-progress channel and apply ticks at their interval.
	# Channels complete when their duration reaches zero.
	_get_channel_tracker().tick(delta)

	# Advance cooldowns
	_cooldowns.tick(delta)

	# Advance active stat modifiers so timed effects expire on the caller's clock.
	get_effect_container().tick(delta)

	# Advance shield durations and expire shields
	_get_shield_tracker().tick(delta)

	# Advance crowd control durations and expire entries
	_get_crowd_control_tracker().tick(delta)

	# Advance the sibling state machine and the basic-attack cycle together.
	# MobaCombatant.tick() is the single driver of MobaStateMachine.tick() for
	# a combatant: nothing else in rules/ ticks it. Game-side code (T4) must
	# not also call MobaStateMachine.tick() directly for a combatant driven
	# through here, or states would expire twice as fast.
	_get_basic_attack_cycle().tick(delta)

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


## The basic-attack wind-up/recovery cycle for this combatant, created on
## first use.
func _get_basic_attack_cycle() -> MobaBasicAttackCycle:
	if _basic_attack_cycle == null:
		_basic_attack_cycle = MobaBasicAttackCycle.new(self)
	return _basic_attack_cycle


## Whether basic_attack() may be called right now to start a new cycle: the
## combatant currently permits a basic attack (accounting for crowd control)
## and the attack-speed interval (1.0 / attack_speed) has elapsed since the last attack started.
## This is the minimal query the game side needs to drive repeat attacks.
## Implemented by MobaBasicAttackCycle.
func is_basic_attack_ready() -> bool:
	return _get_basic_attack_cycle().is_ready()


## Start a basic attack cycle against target. Returns false and starts
## nothing if the loadout has no weapon, target is dead, target is out of
## range, or the cycle is not ready. Implemented by MobaBasicAttackCycle.
func basic_attack(target: MobaCombatant) -> bool:
	return _get_basic_attack_cycle().start(target)


## The sibling MobaStateMachine node, or null if there is no parent or no such
## sibling. Public so MobaDeathHandler/MobaBasicAttackCycle can reach it
## without MobaCombatant re-exposing every state-machine operation itself.
func get_state_machine() -> MobaStateMachine:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("MobaStateMachine") as MobaStateMachine
