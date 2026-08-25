## Test suite for the Brace ability's buff delivery through the ability pipeline.
##
## Covers rules/data/abilities/brace.tres and MobaAbilityAction._apply_effects_seam():
## activating Brace must push its authored buffs into the caster's
## MobaEffectContainer, measurably change damage resolution, and revert on expiry.
##
## Lives in its own file rather than appended to ability_activation_test.gd, which
## is already near the repo's gdlint max-file-lines limit.
class_name BraceAbilityTest

const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaAbilityAction = preload("res://rules/abilities/moba_ability_action.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## Base defensive values this suite pins on the caster before activating Brace,
## so the buffed figures are predictable. These are test fixture values, not
## authored balance -- Brace's own +40/+30/4.0s live only in brace.tres.
const BASE_ARMOR := 30.0
const BASE_MAGIC_RESISTANCE := 0.0

## Brace's authored buff carries duration 4.0; tick past it to force expiry.
const TICK_PAST_EXPIRY := 4.1

## The raw physical hit both the buffed and unbuffed damage assertions resolve.
const RAW_PHYSICAL_HIT := 100.0

## §8 mitigation is multiplier = 100 / (100 + Defense), so the same 100 raw
## physical hit resolves to these values at the two armor figures §19 produces.
## Asserted as absolute magnitudes -- comparing MobaFormulas to itself on both
## sides of the assertion would hold even if mitigation were broken.
const EXPECTED_DAMAGE_AT_BASE_ARMOR := 76.9  # 100 / 130 * 100
const EXPECTED_DAMAGE_AT_BRACED_ARMOR := 58.8  # 100 / 170 * 100

## Slack allowed against the two figures above, which §19 quotes to one decimal.
const DAMAGE_TOLERANCE := 0.05


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_brace_buff_application())
	all_violations.append_array(_test_brace_buff_expiry())

	if all_violations.is_empty():
		return true

	printerr("\n=== Brace Ability Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Build a caster with a real MobaCombatant and MobaStateMachine as child nodes,
## matching how MobaAbilityAction looks them up in production via
## get_node_or_null(), with Brace registered and base defences pinned.
##
## Returns an empty Dictionary if brace.tres does not resolve, so callers can
## report that as a violation rather than crashing.
static func _create_braced_caster() -> Dictionary:
	var brace_ability = MobaAbilityLibrary.get_ability(&"brace")
	if brace_ability == null:
		return {}

	var actor = Actor.new()
	actor.owner_id = 1

	var combatant = MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)
	combatant.register_ability(brace_ability)
	combatant._runtime_stat_block.armor = BASE_ARMOR
	combatant._runtime_stat_block.magic_resistance = BASE_MAGIC_RESISTANCE
	actor.add_child(combatant)

	var state_machine = MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	return {"actor": actor, "combatant": combatant}


## Activate Brace on the caster itself, through the real ability pipeline, so
## MobaAbilityAction._apply_effects_seam() is what delivers the buffs.
static func _activate_brace(caster: Node):
	var context = MobaCastContext.new(caster, null)
	var action = MobaAbilityAction.new(caster, &"brace", context)
	return action.execute()


## Test 1: Brace's authored buffs reach the caster's effect container and change
## damage resolution.
static func _test_brace_buff_application() -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()

	var caster_data = _create_braced_caster()
	if caster_data.is_empty():
		MobaAbilityLibrary._reset()
		violations.append(
			"brace_buff_application: brace.tres did not load as a MobaAbility with id 'brace'"
		)
		return violations

	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	# Capture the pre-buff hit before activation, so the buffed figure is compared
	# against a real earlier measurement rather than a restatement of itself.
	var unbuffed_armor: float = caster_combatant.get_stat(&"armor")
	var unbuffed_damage := MobaFormulas.physical_damage(RAW_PHYSICAL_HIT, unbuffed_armor)

	var result = _activate_brace(caster)
	if not result.success:
		violations.append(
			"brace_buff_application: activation should succeed, got: %s" % result.reason
		)

	var buffed_armor: float = caster_combatant.get_stat(&"armor")
	if not is_equal_approx(buffed_armor, BASE_ARMOR + 40.0):
		violations.append(
			"brace_buff_application: armor should be 70.0 after Brace, got %f" % buffed_armor
		)

	var buffed_magic_resistance: float = caster_combatant.get_stat(&"magic_resistance")
	if not is_equal_approx(buffed_magic_resistance, BASE_MAGIC_RESISTANCE + 30.0):
		violations.append(
			(
				"brace_buff_application: magic_resistance should be 30.0 after Brace, got %f"
				% buffed_magic_resistance
			)
		)

	var buffed_damage := MobaFormulas.physical_damage(RAW_PHYSICAL_HIT, buffed_armor)

	if not (buffed_damage < unbuffed_damage):
		violations.append(
			(
				"brace_buff_application: braced hit should resolve lower than unbuffed"
				+ " (got %f vs %f)" % [buffed_damage, unbuffed_damage]
			)
		)

	if absf(unbuffed_damage - EXPECTED_DAMAGE_AT_BASE_ARMOR) > DAMAGE_TOLERANCE:
		violations.append(
			(
				"brace_buff_application: unbuffed hit should resolve to about %f per §8, got %f"
				% [EXPECTED_DAMAGE_AT_BASE_ARMOR, unbuffed_damage]
			)
		)

	if absf(buffed_damage - EXPECTED_DAMAGE_AT_BRACED_ARMOR) > DAMAGE_TOLERANCE:
		violations.append(
			(
				"brace_buff_application: braced hit should resolve to about %f per §8, got %f"
				% [EXPECTED_DAMAGE_AT_BRACED_ARMOR, buffed_damage]
			)
		)

	MobaAbilityLibrary._reset()

	return violations


## Test 2: Brace's buffs expire after their authored duration, returning both
## stats and the resolved hit to their pre-buff values.
static func _test_brace_buff_expiry() -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()

	var caster_data = _create_braced_caster()
	if caster_data.is_empty():
		MobaAbilityLibrary._reset()
		violations.append(
			"brace_buff_expiry: brace.tres did not load as a MobaAbility with id 'brace'"
		)
		return violations

	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	var unbuffed_armor: float = caster_combatant.get_stat(&"armor")
	var unbuffed_damage := MobaFormulas.physical_damage(RAW_PHYSICAL_HIT, unbuffed_armor)

	var result = _activate_brace(caster)
	if not result.success:
		violations.append("brace_buff_expiry: activation should succeed, got: %s" % result.reason)

	var buffed_armor: float = caster_combatant.get_stat(&"armor")
	if not is_equal_approx(buffed_armor, BASE_ARMOR + 40.0):
		violations.append(
			"brace_buff_expiry: armor should be 70.0 after Brace, got %f" % buffed_armor
		)

	caster_combatant.tick(TICK_PAST_EXPIRY)

	var expired_armor: float = caster_combatant.get_stat(&"armor")
	if not is_equal_approx(expired_armor, BASE_ARMOR):
		violations.append(
			(
				"brace_buff_expiry: armor should revert to exactly %f after expiry, got %f"
				% [BASE_ARMOR, expired_armor]
			)
		)

	var expired_magic_resistance: float = caster_combatant.get_stat(&"magic_resistance")
	if not is_equal_approx(expired_magic_resistance, BASE_MAGIC_RESISTANCE):
		violations.append(
			(
				"brace_buff_expiry: magic_resistance should revert to %f after expiry, got %f"
				% [BASE_MAGIC_RESISTANCE, expired_magic_resistance]
			)
		)

	# The post-expiry hit must land back on the value measured before activation.
	var expired_damage := MobaFormulas.physical_damage(RAW_PHYSICAL_HIT, expired_armor)
	if not is_equal_approx(expired_damage, unbuffed_damage):
		violations.append(
			(
				"brace_buff_expiry: post-expiry hit should match the pre-buff hit"
				+ " (expected %f, got %f)" % [unbuffed_damage, expired_damage]
			)
		)

	if absf(expired_damage - EXPECTED_DAMAGE_AT_BASE_ARMOR) > DAMAGE_TOLERANCE:
		violations.append(
			(
				"brace_buff_expiry: post-expiry hit should resolve to about %f per §8, got %f"
				% [EXPECTED_DAMAGE_AT_BASE_ARMOR, expired_damage]
			)
		)

	MobaAbilityLibrary._reset()

	return violations
