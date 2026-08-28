## A standalone target frame showing a bound target's name, health, and shields.
##
## The frame is bound by assignment -- bind_target(combatant) -- and never
## searches the scene tree for a target. It has no idea how a target was chosen;
## acquiring one is the game side's job.
##
## Signals in, nothing out: this layer only observes MobaCombatant. It never
## calls a mutator and handles no input. No rules logic lives here; every value
## comes from a signal or a public getter.
##
## Shields are an overlay on the same bar as health, not a second number. Two
## TextureProgressBars share one rect and one scale: the shield bar sits behind
## and fills to health + shield, the health bar sits in front and fills to
## health with a transparent under-texture. What shows past the end of the
## health fill is the shield segment.
class_name MobaTargetFrame
extends Control

var _combatant: MobaCombatant = null

## True between a bind_target(combatant) and the unbind that follows it. A
## reference to a freed Object compares equal to null in GDScript, so
## `_combatant != null` cannot distinguish "never bound" from "bound to a target
## that has since been freed" -- and the freed case is exactly the one
## _process() exists to catch. This flag records the binding independently of
## the reference that may go stale.
var _bound: bool = false

var _current_health: float = 0.0
var _maximum_health: float = 0.0
var _shield: float = 0.0

var _target_name: Label = null
var _health_bar: TextureProgressBar = null
var _health_label: Label = null
var _shield_bar: TextureProgressBar = null

var _nodes_resolved: bool = false


func _ready() -> void:
	_ensure_nodes()


## Drop a binding whose target has been freed or has died, so the frame never
## keeps showing a target that is gone. #34 makes death non-destructive and the
## actor is never actually freed in practice, but the frame does not depend on
## that: it checks is_instance_valid() before every access to a bound target.
func _process(_delta: float) -> void:
	if not _bound:
		return
	if not is_instance_valid(_combatant) or not _combatant.is_alive():
		unbind_target()


## Bind the frame to one combatant. Rebinding is explicit: any previous
## connections are dropped before the new ones are made, so calling
## bind_target() twice leaves exactly one connection per signal and produces no
## duplicate updates.
func bind_target(combatant: MobaCombatant) -> void:
	_ensure_nodes()
	_disconnect_combatant()
	_combatant = combatant if is_instance_valid(combatant) else null
	_bound = _combatant != null
	_connect_combatant()
	_push_current_values()
	visible = _bound


## Drop the binding and hide the frame. Used when the target is lost, dies, or
## is freed.
func unbind_target() -> void:
	bind_target(null)


## The currently bound combatant, or null.
func get_combatant() -> MobaCombatant:
	return _combatant


## The bound target's display name, resolved from its parent Actor: the actor's
## character sheet name when it has one, and the actor's node name otherwise.
##
## The sheet is read without naming its type. CharacterSheet lives on the game
## side, and rules/ has to stay extractable without editing a file; this is the
## same untyped reach MobaCombatant.sync_character_sheet_hp() already makes.
func _get_target_name() -> String:
	if not is_instance_valid(_combatant):
		return ""

	var actor := _combatant.get_parent() as Actor
	if not is_instance_valid(actor):
		return ""

	var sheet: Resource = actor.character_sheet
	if sheet != null and "character_name" in sheet:
		var sheet_name := String(sheet.character_name)
		if not sheet_name.is_empty():
			return sheet_name

	return String(actor.name)


## Seed the frame from the combatant's current state so it is correct
## immediately after bind_target() rather than at the next signal.
func _push_current_values() -> void:
	if not is_instance_valid(_combatant):
		_current_health = 0.0
		_maximum_health = 0.0
		_shield = 0.0
		_render_target_name("")
		_refresh_bars()
		return

	_current_health = _combatant.current_health
	_maximum_health = _combatant.maximum_health
	_shield = _combatant.total_shield()
	_render_target_name(_get_target_name())
	_refresh_bars()


func _on_health_changed(current: float, maximum: float) -> void:
	_ensure_nodes()
	_current_health = current
	_maximum_health = maximum
	_refresh_bars()


func _on_shield_changed(total: float) -> void:
	_ensure_nodes()
	_shield = total
	_refresh_bars()


func _render_target_name(name_text: String) -> void:
	if _target_name != null:
		_target_name.text = name_text


## Drive both bars off one shared scale so the shield reads as an extension of
## the same bar rather than a second gauge. The scale grows past maximum health
## when a shield overshields, so a shield is never silently truncated.
##
## The shield bar stays visible at all times and carries the bar's trough. With
## no shield its fill lands exactly where the health fill does and is covered by
## it, so no blue shows; a shield pushes its fill past the health fill's end,
## and that exposed segment is the overlay.
func _refresh_bars() -> void:
	var scale_max := maxf(_maximum_health, _current_health + _shield)
	var bar_max := maxf(scale_max, 1.0)

	if _shield_bar != null:
		_shield_bar.max_value = bar_max
		_shield_bar.value = clampf(_current_health + _shield, 0.0, scale_max)

	if _health_bar != null:
		_health_bar.max_value = bar_max
		_health_bar.value = clampf(_current_health, 0.0, scale_max)

	if _health_label != null:
		_health_label.text = "%d / %d" % [roundi(_current_health), roundi(_maximum_health)]


func _connect_combatant() -> void:
	if not is_instance_valid(_combatant):
		return
	if not _combatant.health_changed.is_connected(_on_health_changed):
		_combatant.health_changed.connect(_on_health_changed)
	if not _combatant.shield_changed.is_connected(_on_shield_changed):
		_combatant.shield_changed.connect(_on_shield_changed)


func _disconnect_combatant() -> void:
	if not is_instance_valid(_combatant):
		_combatant = null
		_bound = false
		return
	if _combatant.health_changed.is_connected(_on_health_changed):
		_combatant.health_changed.disconnect(_on_health_changed)
	if _combatant.shield_changed.is_connected(_on_shield_changed):
		_combatant.shield_changed.disconnect(_on_shield_changed)
	_combatant = null
	_bound = false


## Resolves child nodes without requiring the frame to be inside the scene tree,
## so an owner (or a test) can bind a freshly instantiated frame before adding
## it. The frame's hidden-when-unbound state is authored into the scene rather
## than set here, so it holds before _ready() has run.
func _ensure_nodes() -> void:
	if _nodes_resolved:
		return
	_nodes_resolved = true

	_target_name = get_node_or_null(^"VBoxContainer/NameLabel")
	_health_bar = get_node_or_null(^"VBoxContainer/HealthContainer/HealthBar")
	_health_label = get_node_or_null(^"VBoxContainer/HealthContainer/HealthLabel")
	_shield_bar = get_node_or_null(^"VBoxContainer/HealthContainer/ShieldBar")
