## Runtime holder for the active MobaStatModifier instances on a MobaCombatant (§60).
##
## Entries are keyed by the identity pair (source_ability_id, stat). A second
## application under the same identity is resolved by the modifier's `stacking`
## policy; a different source_ability_id on the same stat is an independent
## entry that always coexists and sums.
##
## Time advances only through tick(delta), called by MobaCombatant.tick().
## There is no _process, no _physics_process, and no SceneTreeTimer here.
##
## Signals (argument lists are exact):
##   effect_applied(source_ability_id: StringName, stat: StringName)
##       A new entry was stored, or an existing entry was replaced outright by
##       a stronger REPLACE_IF_STRONGER application.
##   effect_refreshed(source_ability_id: StringName, stat: StringName)
##       An existing entry's duration was reset. REFRESH emits this, and so
##       does every STACK application -- including ones past max_stacks.
##   effect_stacks_changed(source_ability_id: StringName, stat: StringName, stacks: int)
##       An existing entry's stack count changed.
##   effect_expired(source_ability_id: StringName, stat: StringName)
##       An entry's duration ran out during tick(), or it was removed by
##       remove_modifiers_from().
class_name MobaEffectContainer
extends Node

signal effect_applied(source_ability_id: StringName, stat: StringName)
signal effect_refreshed(source_ability_id: StringName, stat: StringName)
signal effect_stacks_changed(source_ability_id: StringName, stat: StringName, stacks: int)
signal effect_expired(source_ability_id: StringName, stat: StringName)

# Keyed by Array[source_ability_id, stat]; each value is an _Entry.
var _entries: Dictionary = {}


## One active modifier identity: (source_ability_id, stat).
##
## `magnitude` is the summed contribution of every stack, and `remaining` is a
## SINGLE SHARED DURATION for the whole identity rather than one timer per
## stack. Every STACK application refreshes it, including applications made
## once `stacks` has already reached `max_stacks`: past the cap the magnitude
## stops growing but the effect stays alive as long as it keeps being applied.
class _Entry:
	var source_ability_id: StringName
	var stat: StringName
	var magnitude: float = 0.0
	var is_percentage: bool = false
	var duration: float = 0.0
	var remaining: float = 0.0
	var stacking: int = MobaStatModifier.Stacking.REFRESH
	var max_stacks: int = 1
	var stacks: int = 1


## Apply a modifier under a source ability id.
##
## Returns true when the container's state changed, false when the application
## was rejected (invalid stat) or was a deliberate no-op (IGNORE while active,
## or a weaker REPLACE_IF_STRONGER application).
func apply_modifier(modifier: MobaStatModifier, source_ability_id: StringName) -> bool:
	if modifier == null:
		push_error(
			"MobaEffectContainer: null modifier from source ability '%s'." % source_ability_id
		)
		return false

	var stat := StringName(modifier.stat)
	if stat not in MobaStatBlock.get_valid_stats():
		push_error(invalid_stat_message(stat, source_ability_id))
		return false

	var key := _key(source_ability_id, stat)
	if key not in _entries:
		_entries[key] = _make_entry(modifier, source_ability_id, stat)
		effect_applied.emit(source_ability_id, stat)
		return true

	return _apply_to_existing_entry(_entries[key], modifier, source_ability_id, stat, key)


## Resolve an application against an already-active entry per its stacking
## policy. Split out of apply_modifier() to keep both functions under the
## project's max-returns lint limit.
func _apply_to_existing_entry(
	entry: _Entry,
	modifier: MobaStatModifier,
	source_ability_id: StringName,
	stat: StringName,
	key: Array
) -> bool:
	match entry.stacking:
		MobaStatModifier.Stacking.REFRESH:
			entry.remaining = modifier.duration
			entry.duration = modifier.duration
			effect_refreshed.emit(source_ability_id, stat)
			return true

		MobaStatModifier.Stacking.STACK:
			# Shared duration: refreshed on every application, capped or not.
			entry.remaining = modifier.duration
			entry.duration = modifier.duration
			effect_refreshed.emit(source_ability_id, stat)
			if entry.stacks < entry.max_stacks:
				entry.stacks += 1
				entry.magnitude += modifier.amount
				effect_stacks_changed.emit(source_ability_id, stat, entry.stacks)
			return true

		MobaStatModifier.Stacking.IGNORE:
			return false

		MobaStatModifier.Stacking.REPLACE_IF_STRONGER:
			if absf(modifier.amount) <= absf(entry.magnitude):
				return false
			_entries[key] = _make_entry(modifier, source_ability_id, stat)
			effect_applied.emit(source_ability_id, stat)
			return true

	return false


## Remove every entry contributed by a source ability id, emitting
## effect_expired for each.
func remove_modifiers_from(source_ability_id: StringName) -> void:
	for key in _entries.keys():
		var entry: _Entry = _entries[key]
		if entry.source_ability_id != source_ability_id:
			continue
		_entries.erase(key)
		effect_expired.emit(entry.source_ability_id, entry.stat)


## Remove every active effect entry, emitting effect_expired for each.
## Called when a combatant enters DEAD state to clear all active modifiers.
func clear_all() -> void:
	var keys_to_remove: Array = _entries.keys()
	for key in keys_to_remove:
		var entry: _Entry = _entries[key]
		_entries.erase(key)
		effect_expired.emit(entry.source_ability_id, entry.stat)


## Sum of the flat (non-percentage) magnitudes active on a stat.
func get_flat_bonus(stat: StringName) -> float:
	var total := 0.0
	for key in _entries:
		var entry: _Entry = _entries[key]
		if entry.stat == stat and not entry.is_percentage:
			total += entry.magnitude
	return total


## Sum of the percentage magnitudes active on a stat, as a fraction
## (0.5 == +50 %). Percentages sum additively among themselves.
func get_percent_bonus(stat: StringName) -> float:
	var total := 0.0
	for key in _entries:
		var entry: _Entry = _entries[key]
		if entry.stat == stat and entry.is_percentage:
			total += entry.magnitude
	return total


## Whether an entry for this identity is currently active.
func has_modifier(source_ability_id: StringName, stat: StringName) -> bool:
	return _key(source_ability_id, stat) in _entries


## Stack count for an identity, or 0 when no entry is active.
func get_stacks(source_ability_id: StringName, stat: StringName) -> int:
	var key := _key(source_ability_id, stat)
	if key not in _entries:
		return 0
	return (_entries[key] as _Entry).stacks


## Remaining duration for an identity, or 0.0 when no entry is active.
## A permanent entry (duration == 0.0) also reports 0.0; use has_modifier()
## to distinguish it from an absent one.
func get_remaining_duration(source_ability_id: StringName, stat: StringName) -> float:
	var key := _key(source_ability_id, stat)
	if key not in _entries:
		return 0.0
	return (_entries[key] as _Entry).remaining


## Advance every timed entry by delta seconds, expiring those that run out.
## Entries whose modifier had duration == 0.0 are permanent and never tick.
func tick(delta: float) -> void:
	for key in _entries.keys():
		var entry: _Entry = _entries[key]
		if entry.duration <= 0.0:
			continue
		entry.remaining -= delta
		if entry.remaining <= 0.0:
			_entries.erase(key)
			effect_expired.emit(entry.source_ability_id, entry.stat)


## The exact error text pushed when an application names a stat that is not in
## MobaStatBlock.get_valid_stats(). Exposed so tests can assert the message
## names both the offending stat and the source ability.
static func invalid_stat_message(stat: StringName, source_ability_id: StringName) -> String:
	return (
		"MobaEffectContainer: unknown stat '%s' from source ability '%s'; modifier rejected."
		% [stat, source_ability_id]
	)


func _make_entry(
	modifier: MobaStatModifier, source_ability_id: StringName, stat: StringName
) -> _Entry:
	var entry := _Entry.new()
	entry.source_ability_id = source_ability_id
	entry.stat = stat
	entry.magnitude = modifier.amount
	entry.is_percentage = modifier.is_percentage
	entry.duration = modifier.duration
	entry.remaining = modifier.duration
	entry.stacking = modifier.stacking
	entry.max_stacks = modifier.max_stacks
	entry.stacks = 1
	return entry


func _key(source_ability_id: StringName, stat: StringName) -> Array:
	return [source_ability_id, stat]
