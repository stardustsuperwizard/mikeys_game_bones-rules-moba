## Binds the floating text pool to every MobaCombatant in the scene.
##
## All scene-tree searching lives here, on the game side: rules/ui/ is driven by
## explicit calls to MobaFloatingText's spawn methods and never looks for a
## combatant itself. This mirrors scripts/combat_hud_binder.gd, which reaches
## the HUD through a NodePath export rather than an autoload singleton.
##
## Combatants are spawned by WorldManager rather than authored into the scene,
## and addons/mikeys_game_bones/world/world_manager.gd is framework code that
## emits no spawn signal, so discovery goes through SceneTree's built-in
## node_added signal plus one startup sweep for combatants already in the tree.
##
## Impact position is read from combatant.get_parent().global_position, the same
## duck-typed pattern already used by moba_ability_action.gd::_get_position() and
## moba_basic_attack_cycle.gd::_get_parent_position().
##
## Only damage_resolved is watched, never basic_attack_resolved. A basic attack
## emits both, so listening to both would draw two numbers for one hit.
class_name FloatingTextBinder
extends Node

## The MobaFloatingText pool that spawn requests are sent to.
@export var floating_text_path: NodePath

var _floating_text: MobaFloatingText = null

## Watched combatants keyed by instance ID. Node is not RefCounted, so this
## never keeps a combatant alive; entries are erased on tree_exited so the
## dictionary cannot grow across a session's spawns and despawns.
var _watched: Dictionary = {}


func _ready() -> void:
	_floating_text = get_node_or_null(floating_text_path) as MobaFloatingText
	if _floating_text == null:
		push_error("FloatingTextBinder: floating_text_path does not resolve to a MobaFloatingText")
		return

	get_tree().node_added.connect(_on_node_added)
	_sweep_for_combatants(get_tree().root)


## Watch every combatant already in the tree when this binder became ready.
## node_added only fires for nodes added after the connection above.
func _sweep_for_combatants(node: Node) -> void:
	_watch_combatant_child_of(node)
	for child in node.get_children():
		_sweep_for_combatants(child)


func _on_node_added(node: Node) -> void:
	_watch_combatant_child_of(node)


## Watch the MobaCombatant child of node, if it has one.
##
## An Actor carries its combatant as a child named MobaCombatant -- the same
## shape scenes/main.tscn's CombatHUDBinder addresses as
## "../WorldManager/Player/MobaCombatant".
func _watch_combatant_child_of(node: Node) -> void:
	var combatant := node.get_node_or_null("MobaCombatant") as MobaCombatant
	if combatant == null:
		return
	_watch_combatant(combatant)


## Connect a combatant's damage and healing signals to the pool.
##
## Connections are guarded by is_connected() rather than by the _watched entry
## alone: tree_exited fires on any removal from the tree, not only on free, so a
## combatant removed and re-added would otherwise be connected twice and draw two
## numbers per hit.
func _watch_combatant(combatant: MobaCombatant) -> void:
	var instance_id := combatant.get_instance_id()
	_watched[instance_id] = true

	var on_damage := _on_damage_resolved.bind(combatant)
	if not combatant.damage_resolved.is_connected(on_damage):
		combatant.damage_resolved.connect(on_damage)

	var on_healing := _on_healing_applied.bind(combatant)
	if not combatant.healing_applied.is_connected(on_healing):
		combatant.healing_applied.connect(on_healing)

	var on_exit := _on_combatant_exited.bind(instance_id)
	if not combatant.tree_exited.is_connected(on_exit):
		combatant.tree_exited.connect(on_exit)


## True while the binder holds a live watch on this combatant. Exposed for
## tests that assert a freed combatant leaves no entry behind.
func is_watching(combatant: MobaCombatant) -> bool:
	return combatant != null and combatant.get_instance_id() in _watched


## The number of combatants currently watched. Exposed for tests.
func watched_count() -> int:
	return _watched.size()


## Draw the numbers for one resolved damage packet.
##
## final is the post-shield amount that reached health, and shield_absorbed is
## the part a shield ate, so a fully absorbed hit has final == 0.0. Only the
## non-zero parts are drawn: a fully absorbed hit shows the shield number alone
## rather than pairing it with a meaningless "0".
func _on_damage_resolved(
	_raw: float,
	final: float,
	damage_type: int,
	was_crit: bool,
	_source: Variant,
	shield_absorbed: float,
	combatant: MobaCombatant
) -> void:
	var resolved: Variant = _impact_position(combatant)
	if resolved == null:
		return
	var impact: Vector3 = resolved

	if final > 0.0:
		_floating_text.spawn_damage(impact, final, damage_type, was_crit)

	if shield_absorbed > 0.0:
		_floating_text.spawn_shield_absorbed(impact, shield_absorbed)


func _on_healing_applied(amount: float, combatant: MobaCombatant) -> void:
	if amount <= 0.0:
		return

	var resolved: Variant = _impact_position(combatant)
	if resolved == null:
		return
	var impact: Vector3 = resolved

	_floating_text.spawn_heal(impact, amount)


## The combatant's body position in world space, or null when it cannot be read
## -- a freed combatant, a parentless one, or a parent with no global_position.
##
## Object.get() returns null for a property the parent does not define, which is
## the same duck-typed read moba_basic_attack_cycle.gd::_get_parent_position()
## and moba_ability_action.gd::_get_position() already use. Returning null rather
## than Vector3.ZERO keeps a hit from drawing a number at the world origin when
## the position is genuinely unknown.
func _impact_position(combatant: MobaCombatant) -> Variant:
	if _floating_text == null or not is_instance_valid(combatant):
		return null

	var parent := combatant.get_parent()
	if parent == null:
		return null

	return parent.get("global_position")


## Drop the watch when a combatant leaves the tree, so the binder never holds a
## reference into a freed node. The signal connections themselves are owned by
## the combatant and die with it.
func _on_combatant_exited(instance_id: int) -> void:
	_watched.erase(instance_id)
