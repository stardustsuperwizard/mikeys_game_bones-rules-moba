## Standalone cast bar control showing ability name and progress for in-progress
## casts and channels.
##
## The bar is bound by assignment — bind(combatant) — and never searches the
## scene tree, so the same scene can be placed in a HUD or elsewhere without change.
##
## Signals in, nothing out: this control only reads MobaCombatant state through
## public getters. It never calls a mutator and never calls cancel_cast() or
## break_channel() itself.
##
## Visibility and content are driven by a per-frame poll, matching the pattern
## MobaAbilitySlot._process() uses for its cooldown sweep. The bar is visible
## whenever combatant.is_casting() or combatant.is_channeling() is true; hidden
## otherwise. Every exit path (completion, cancellation, hard CC break) clears
## the tracker's in-progress state on the same frame, so polling this way
## satisfies "clears on every exit path" with no new signal.
class_name MobaCastBar
extends Control

var _combatant: MobaCombatant = null

var _name_label: Label = null
var _progress_bar: TextureProgressBar = null


func _ready() -> void:
	_ensure_nodes()
	refresh()


## Polling for casting/channeling state is the only per-frame work.
func _process(_delta: float) -> void:
	refresh()


## Re-render both visibility and progress. Called on binding changes and
## on ready; per-frame updates use the same pair since this bar has no
## narrower refresh to fall back to.
func refresh() -> void:
	_refresh_visibility()
	_refresh_progress()


## Bind this bar to one combatant. Rebinding is explicit: any previous
## connections are dropped before the new ones are made, so calling bind()
## twice leaves exactly one connection per signal and produces no duplicate
## updates. Since this bar uses polling instead of signals, there are no
## connections to drop, but we follow the same pattern for consistency.
func bind(combatant: MobaCombatant) -> void:
	_ensure_nodes()
	_disconnect_combatant()
	_combatant = combatant if is_instance_valid(combatant) else null
	refresh()


## Drop the binding and render the empty state.
func unbind() -> void:
	bind(null)


## The currently bound combatant, or null.
func get_combatant() -> MobaCombatant:
	return _combatant


func _refresh_visibility() -> void:
	if not is_instance_valid(_combatant):
		visible = false
		return

	# Visible when casting or channeling; hidden otherwise
	visible = _combatant.is_casting() or _combatant.is_channeling()


func _refresh_progress() -> void:
	if not is_instance_valid(_combatant):
		_render_empty()
		return

	if _combatant.is_casting():
		var ability := _combatant.get_casting_ability()
		if ability == null:
			_render_empty()
			return
		_render_cast(ability)
	elif _combatant.is_channeling():
		var ability := _combatant.get_channeling_ability()
		if ability == null:
			_render_empty()
			return
		_render_channel(ability)
	else:
		_render_empty()


func _render_cast(ability: MobaAbility) -> void:
	_set_name(ability)
	var cast_time: float = ability.cast_time
	var time_remaining: float = _combatant.get_cast_time_remaining()
	_set_progress(cast_time, time_remaining)


func _render_channel(ability: MobaAbility) -> void:
	_set_name(ability)
	var channel_time: float = ability.channel_duration
	var time_remaining: float = _combatant.get_channel_time_remaining()
	_set_progress(channel_time, time_remaining)


func _set_name(ability: MobaAbility) -> void:
	if _name_label == null:
		return

	if ability.name == "":
		_name_label.text = String(ability.id)
	else:
		_name_label.text = ability.name


func _set_progress(total_time: float, time_remaining: float) -> void:
	if _progress_bar == null:
		return

	# Guard against division by zero for a zero-duration ability
	if total_time <= 0.0:
		_progress_bar.value = 0.0
		return

	# Progress fraction: 1.0 - (remaining / total)
	var fraction: float = 1.0 - (time_remaining / total_time)
	# Clamp to [0, 1] for display defensiveness
	fraction = clampf(fraction, 0.0, 1.0)
	_progress_bar.value = fraction


func _render_empty() -> void:
	if _name_label != null:
		_name_label.text = ""
	if _progress_bar != null:
		_progress_bar.value = 0.0


## No signals to disconnect: this bar uses polling only. bind() still calls
## this before reassigning _combatant, matching MobaCombatHUD.bind()'s
## disconnect-then-reconnect shape, so the seam stays obvious for whoever
## adds a signal here later.
func _disconnect_combatant() -> void:
	pass


## Resolves child nodes without requiring the bar to be inside the scene tree,
## so an owner (or a test) can bind a freshly instantiated bar before adding it.
func _ensure_nodes() -> void:
	if _name_label != null and _progress_bar != null:
		return

	_name_label = get_node_or_null(^"VBox/NameLabel")
	_progress_bar = get_node_or_null(^"VBox/ProgressBar")
