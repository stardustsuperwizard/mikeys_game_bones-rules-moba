# Headless integration test for FloatingTextBinder's cross-combatant wiring.
#
# Run with:
#   godot --headless --path . --script tests/floating_text_binder_test.gd
#
# Builds a live scene tree containing a MobaFloatingText pool, a
# FloatingTextBinder pointed at it, and two Actor/MobaCombatant pairs, then
# drives real damage and healing through MobaCombatant to check what the binder
# draws. Exits non-zero on the first failed expectation.
#
# Covers, in order:
#   - the binder discovers combatants added after it is ready, and draws a
#     number over a combatant the main HUD is not bound to;
#   - a basic attack draws exactly one number, not two, even though the cycle
#     emits damage_resolved on the target and basic_attack_resolved on the
#     attacker for the same hit;
#   - a fully absorbed hit draws the shield number alone, with no "0" beside it;
#   - healing draws a number;
#   - a freed combatant leaves no watch entry behind and no error.
#
# This test is NOT wired into tests/test_bootstrap.gd; it is a manual
# integration check matching tests/crowd_control_controller_test.gd's and
# tests/mouse_action_test.gd's own precedent. The pool's own capping and
# recycling rules are unit-tested in rules/tests/floating_text_test.gd, which
# does run under the bootstrap.
extends SceneTree

const BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")
# Actor._ready() duplicates its character_sheet, so a fixture Actor needs one.
const CHARACTER_SHEET = preload("res://resources/enemy_character_sheet.tres")
const FLOATING_TEXT_SCENE = preload("res://rules/ui/moba_floating_text.tscn")

var _failures: Array[String] = []
var _pool: MobaFloatingText = null
var _binder: FloatingTextBinder = null


func _initialize() -> void:
	_run()


func _run() -> void:
	_pool = FLOATING_TEXT_SCENE.instantiate()
	_pool.name = "MobaFloatingText"
	_pool.max_concurrent = 10
	root.add_child(_pool)

	_binder = FloatingTextBinder.new()
	_binder.name = "FloatingTextBinder"
	_binder.floating_text_path = NodePath("../MobaFloatingText")
	root.add_child(_binder)

	await process_frame

	if not await _check_cross_combatant():
		return _finish()
	if not await _check_basic_attack_draws_one_number():
		return _finish()
	if not await _check_full_absorb_draws_shield_only():
		return _finish()
	if not await _check_healing_draws_a_number():
		return _finish()
	if not await _check_freed_combatant_is_released():
		return _finish()

	_finish()


# Builds an Actor with a CharacterBody3D named "Body" and a MobaCombatant named
# "MobaCombatant", the same shape scenes/main.tscn addresses as
# "WorldManager/Player/MobaCombatant". Added to the tree so the binder's
# node_added discovery sees it.
func _spawn_actor(actor_name: String, position: Vector3) -> MobaCombatant:
	var actor := Actor.new()
	actor.name = actor_name
	actor.character_sheet = CHARACTER_SHEET.duplicate()

	var body := CharacterBody3D.new()
	body.name = "Body"
	actor.add_child(body)

	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	# Crit is rolled before damage-type routing; a stray crit would change the
	# drawn text. Disable it for predictable output, as combatant_test.gd does.
	combatant._runtime_stat_block.crit_chance = 0.0
	actor.add_child(combatant)

	root.add_child(actor)
	body.global_position = position
	return combatant


# Expires every active number so the next scenario starts from an empty pool.
func _drain_pool() -> void:
	_pool._update_pool(_pool.DISPLAY_DURATION + 1.0)


func _visible_labels() -> Array[Label]:
	var labels: Array[Label] = []
	for child in _pool.get_children():
		if child is Label and child.visible:
			labels.append(child)
	return labels


func _hit(target: MobaCombatant, amount: float, attacker: MobaCombatant) -> MobaDamage:
	var damage := MobaDamage.new(amount, MobaDamage.DamageType.TRUE, attacker, false)
	target.apply_damage(damage)
	return damage


# A combatant the main HUD is not bound to still gets a number.
func _check_cross_combatant() -> bool:
	var enemy := _spawn_actor("Enemy", Vector3(3, 0, 4))
	await process_frame

	if not _binder.is_watching(enemy):
		_fail("cross_combatant: binder did not discover a combatant added after it was ready")
		return false

	_drain_pool()
	_hit(enemy, 50.0, null)

	var labels := _visible_labels()
	if labels.size() != 1:
		_fail("cross_combatant: expected 1 number over the enemy, got %d" % labels.size())
		return false

	print("PASS cross-combatant: a non-player combatant's hit draws a number")
	return true


# The basic-attack cycle emits damage_resolved on the target and
# basic_attack_resolved on the attacker for one hit. The binder watches both
# combatants, so listening to both signals would draw two numbers for that hit.
func _check_basic_attack_draws_one_number() -> bool:
	var attacker := _spawn_actor("Attacker", Vector3.ZERO)
	var target := _spawn_actor("Target", Vector3(2, 0, 0))
	await process_frame

	_drain_pool()

	# Exactly what moba_basic_attack_cycle.gd:183-185 does for a landed hit.
	var damage := _hit(target, 40.0, attacker)
	attacker.basic_attack_resolved.emit(
		target, damage.amount, damage.final_amount, damage.damage_type, damage.was_crit
	)

	var labels := _visible_labels()
	if labels.size() != 1:
		_fail("basic_attack: expected exactly 1 number for one hit, got %d" % labels.size())
		return false

	print("PASS basic attack: one hit draws exactly one number")
	return true


# A shield that eats the whole hit leaves final == 0.0. The shield number is
# drawn; a "0" damage number beside it is not.
func _check_full_absorb_draws_shield_only() -> bool:
	var shielded := _spawn_actor("Shielded", Vector3(-4, 0, 1))
	await process_frame

	shielded.apply_shield(100.0, &"test_shield", 10.0)
	_drain_pool()

	_hit(shielded, 60.0, null)

	var labels := _visible_labels()
	if labels.size() != 1:
		_fail("full_absorb: expected only the shield number, got %d numbers" % labels.size())
		return false
	if not labels[0].text.begins_with("S"):
		_fail("full_absorb: expected a shield number, got '%s'" % labels[0].text)
		return false

	print("PASS full absorb: shield number drawn alone, with no '0' beside it")
	return true


func _check_healing_draws_a_number() -> bool:
	var healed := _spawn_actor("Healed", Vector3(0, 0, -5))
	await process_frame

	_hit(healed, 100.0, null)
	_drain_pool()

	healed.apply_healing(30.0)

	var labels := _visible_labels()
	if labels.size() != 1:
		_fail("healing: expected 1 number for healing, got %d" % labels.size())
		return false
	if not labels[0].text.begins_with("+"):
		_fail("healing: expected a healing number, got '%s'" % labels[0].text)
		return false

	print("PASS healing: applied healing draws a number")
	return true


# Freeing a watched combatant must drop the binder's watch and leave nothing
# behind that errors on the next hit.
func _check_freed_combatant_is_released() -> bool:
	var doomed := _spawn_actor("Doomed", Vector3(7, 0, 7))
	var survivor := _spawn_actor("Survivor", Vector3(8, 0, 8))
	await process_frame

	var watched_before := _binder.watched_count()
	if not _binder.is_watching(doomed):
		_fail("freed_combatant: binder never watched the combatant it is about to free")
		return false

	doomed.get_parent().queue_free()
	await process_frame
	await process_frame

	if _binder.watched_count() != watched_before - 1:
		_fail(
			(
				"freed_combatant: expected the watch count to drop to %d, got %d"
				% [watched_before - 1, _binder.watched_count()]
			)
		)
		return false

	# The binder must still work for everyone else after the free.
	_drain_pool()
	_hit(survivor, 25.0, null)

	if _visible_labels().size() != 1:
		_fail("freed_combatant: a surviving combatant stopped drawing numbers after the free")
		return false

	print("PASS freed combatant: watch released, surviving combatants unaffected")
	return true


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("\nALL FLOATING TEXT BINDER CHECKS PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL " + f)
		quit(1)
