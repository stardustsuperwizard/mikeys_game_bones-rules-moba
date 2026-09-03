## Test suite for MobaCharacterBuild and MobaBuildValidator.
##
## Covers: Discipline distinctness and membership (action slots and the passive
## slot), loadout structural validity, ability resolution, stat allocation
## against the authored policy, and the deliberate absence of any weapon check.
class_name BuildValidatorTest

const MobaCharacterBuild = preload("res://rules/abilities/moba_character_build.gd")
const MobaBuildValidator = preload("res://rules/abilities/moba_build_validator.gd")
const MobaStatAllocationPolicy = preload("res://rules/core/moba_stat_allocation_policy.gd")
const MobaLoadout = preload("res://rules/abilities/moba_loadout.gd")
const MobaAppearance = preload("res://rules/appearance/moba_appearance.gd")
const MobaAppearanceValidator = preload("res://rules/appearance/moba_appearance_validator.gd")
const MobaWeapon = preload("res://rules/core/moba_weapon.gd")
const _ALLOCATION_POLICY = preload("res://rules/data/stat_blocks/stat_allocation_policy.tres")
const _TEMPLATE_BUILD = preload("res://rules/data/builds/melee_bruiser_build.tres")

# Discipline ordinals, mirroring MobaAbility.Discipline, so a reader can check a
# fixture's ability ids against the Discipline it claims without opening the enum.
# The authored abilities available to each, as of this suite:
#
#   WARRIOR (0)     power_strike, whirlwind
#   GUARDIAN (1)    brace, shield_bash
#   SLAYER (2)      none authored yet
#   MARKSMAN (3)    aimed_shot -- the "third Discipline" in the refusal fixtures
#   MYSTIC (4)      cataclysm, energy_bolt, force_barrier
#   ADVENTURER (5)  field_dressing
const _WARRIOR := 0
const _GUARDIAN := 1
const _MYSTIC := 4
const _ADVENTURER := 5


## Static entry point for headless test execution.
static func run() -> bool:
	var results: Array[bool] = []

	results.append(_test_empty_character_name_refused())
	results.append(_test_character_name_too_long_refused())
	results.append(_test_character_name_invalid_characters_refused())
	results.append(_test_character_name_with_valid_characters_legal())
	results.append(_test_appearance_with_unknown_helm_refused())
	results.append(_test_appearance_with_unknown_chest_refused())
	results.append(_test_appearance_with_unknown_color_scheme_refused())
	results.append(_test_appearance_does_not_affect_stat_block())
	results.append(_test_appearance_does_not_affect_loadout())
	results.append(_test_primary_equals_secondary_refused())
	results.append(_test_legal_3_1_discipline_split())
	results.append(_test_legal_2_2_discipline_split())
	results.append(_test_ability_from_third_discipline_refused())
	results.append(_test_passive_from_outside_disciplines_refused())
	results.append(_test_ranged_weapon_with_melee_disciplines_legal())
	results.append(_test_stat_pool_exactly_at_cap_legal())
	results.append(_test_stat_pool_one_over_cap_refused())
	results.append(_test_single_discipline_build_legal())
	results.append(_test_template_build_validates_legal())
	results.append(_test_negative_stat_allocation_refused())
	results.append(_test_unknown_stat_allocation_refused())
	results.append(_test_stat_exceeds_per_stat_cap_refused())
	results.append(_test_unknown_ability_refused())
	results.append(_test_loadout_with_duplicate_abilities_refused())
	results.append(_test_effective_stat_block_does_not_mutate_baseline())

	return results.all(func(result: bool) -> bool: return result)


## Build a MobaCharacterBuild from a Discipline pair, ability ids, and an allocation.
## action_ids fills slots 1..n in order; passive_id may be empty.
static func _make_build(
	primary: int,
	secondary: int,
	action_ids: Array,
	passive_id: String = "",
	allocation: Dictionary[StringName, int] = {}
) -> MobaCharacterBuild:
	var build := MobaCharacterBuild.new()
	build.character_name = "Fixture"
	build.primary_discipline = primary
	build.secondary_discipline = secondary
	build.stat_allocation = allocation

	var loadout := MobaLoadout.new()
	for i in range(action_ids.size()):
		loadout.set_action_slot(i + 1, action_ids[i])
	if passive_id != "":
		loadout.set_passive_slot(passive_id)
	build.loadout = loadout

	return build


## Report a mismatch between the expected and actual validator verdict.
static func _expect(label: String, actual: StringName, expected: StringName) -> bool:
	if actual != expected:
		printerr("ERROR: %s -- expected '%s', got '%s'" % [label, String(expected), String(actual)])
		return false
	return true


## An empty character name is refused with FAILURE_NAME_EMPTY.
static func _test_empty_character_name_refused() -> bool:
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"])
	build.character_name = ""

	return _expect(
		"empty character_name",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_NAME_EMPTY
	)


## A character name exceeding MAX_NAME_LENGTH is refused with FAILURE_NAME_TOO_LONG.
static func _test_character_name_too_long_refused() -> bool:
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"])
	# Create a name longer than MAX_NAME_LENGTH (32)
	build.character_name = "a".repeat(MobaBuildValidator.MAX_NAME_LENGTH + 1)

	return _expect(
		"character_name exceeds MAX_NAME_LENGTH",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_NAME_TOO_LONG
	)


## A character name with invalid characters is refused with FAILURE_NAME_INVALID_CHARACTERS.
static func _test_character_name_invalid_characters_refused() -> bool:
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"])
	build.character_name = "Invalid@Name"  # @ is not allowed

	return _expect(
		"character_name with invalid characters",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_NAME_INVALID_CHARACTERS
	)


## A character name with valid characters (letters, digits, spaces, underscores) is legal.
static func _test_character_name_with_valid_characters_legal() -> bool:
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"])
	build.character_name = "Brave Knight 42_v2"  # Mix of valid characters

	return _expect(
		"character_name with valid characters",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		&""
	)


## An unknown helm id is refused with the appearance validator's reason, verbatim.
static func _test_appearance_with_unknown_helm_refused() -> bool:
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"])
	build.character_name = "ValidName"
	var appearance := MobaAppearance.new()
	appearance.helm_id = "nonexistent_helm"
	build.appearance = appearance

	return _expect(
		"appearance with unknown helm_id",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaAppearanceValidator.FAILURE_UNKNOWN_HELM
	)


## An unknown chest id is refused with the appearance validator's reason, verbatim.
static func _test_appearance_with_unknown_chest_refused() -> bool:
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"])
	build.character_name = "ValidName"
	var appearance := MobaAppearance.new()
	appearance.chest_id = "nonexistent_chest"
	build.appearance = appearance

	return _expect(
		"appearance with unknown chest_id",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaAppearanceValidator.FAILURE_UNKNOWN_CHEST
	)


## An unknown colour scheme id is refused with the appearance validator's reason, verbatim.
static func _test_appearance_with_unknown_color_scheme_refused() -> bool:
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"])
	build.character_name = "ValidName"
	var appearance := MobaAppearance.new()
	appearance.color_scheme_id = "nonexistent_scheme"
	build.appearance = appearance

	return _expect(
		"appearance with unknown color_scheme_id",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaAppearanceValidator.FAILURE_UNKNOWN_COLOR_SCHEME
	)


## Changing appearance between two otherwise identical builds produces identical
## get_effective_stat_block() output.
##
## The comparison is over a plain-value snapshot of every stat, not over the
## MobaStatBlock resources themselves: var_to_bytes() does not serialize an
## Object's contents, so comparing two resource instances directly compares
## identity and would answer the same way whatever appearance did.
static func _test_appearance_does_not_affect_stat_block() -> bool:
	var appearance1 := MobaAppearance.new()
	appearance1.helm_id = &"basic_helm"
	appearance1.chest_id = &"basic_chest"
	appearance1.color_scheme_id = &"crimson"

	var appearance2 := MobaAppearance.new()
	appearance2.helm_id = &"iron_helm"
	appearance2.chest_id = &"leather_chest"
	appearance2.color_scheme_id = &"azure"

	var allocation: Dictionary[StringName, int] = {MobaStatBlock.ATTACK_DAMAGE: 5}
	var build1 := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"], "", allocation)
	build1.character_name = "TestChar"
	build1.appearance = appearance1

	var build2 := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"], "", allocation)
	build2.character_name = "TestChar"
	build2.appearance = appearance2

	var baseline := MobaStatBlock.new()
	var bytes1 := var_to_bytes(_stat_snapshot(build1.get_effective_stat_block(baseline)))
	var bytes2 := var_to_bytes(_stat_snapshot(build2.get_effective_stat_block(baseline)))

	if bytes1 != bytes2:
		printerr("ERROR: appearance affects stat block; byte representations differ")
		return false

	# Both builds must still be legal, or the comparison proved nothing.
	if MobaBuildValidator.validate(build1, _ALLOCATION_POLICY) != &"":
		printerr("ERROR: appearance stat-block fixture build1 is not legal")
		return false
	if MobaBuildValidator.validate(build2, _ALLOCATION_POLICY) != &"":
		printerr("ERROR: appearance stat-block fixture build2 is not legal")
		return false

	return true


## Every stat value in declaration order, as plain floats.
##
## get_valid_stats() fixes the order, so the resulting array is a deterministic
## value-only view of the block that var_to_bytes() can encode faithfully.
static func _stat_snapshot(block: MobaStatBlock) -> Array[float]:
	var snapshot: Array[float] = []
	for stat_name in MobaStatBlock.get_valid_stats():
		snapshot.append(block.get_stat_value(stat_name))
	return snapshot


## Changing appearance between two otherwise identical builds leaves loadout unchanged.
##
## Compared as a plain-value snapshot for the same reason as the stat block above.
static func _test_appearance_does_not_affect_loadout() -> bool:
	var appearance1 := MobaAppearance.new()
	appearance1.helm_id = &"basic_helm"

	var appearance2 := MobaAppearance.new()
	appearance2.helm_id = &"iron_helm"

	var build1 := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"])
	build1.character_name = "TestChar"
	build1.appearance = appearance1

	var build2 := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"])
	build2.character_name = "TestChar"
	build2.appearance = appearance2

	var bytes1 := var_to_bytes(_loadout_snapshot(build1.loadout))
	var bytes2 := var_to_bytes(_loadout_snapshot(build2.loadout))

	if bytes1 != bytes2:
		printerr("ERROR: appearance affects loadout; byte representations differ")
		return false

	return true


## Every occupied slot id in slot order, as plain strings.
static func _loadout_snapshot(loadout: MobaLoadout) -> Array[String]:
	var snapshot: Array[String] = []
	for i in range(1, 5):
		snapshot.append(loadout.get_action_slot(i))
	snapshot.append(loadout.get_passive_slot())
	return snapshot


## Primary equal to secondary is refused with FAILURE_DISCIPLINES_NOT_DISTINCT.
static func _test_primary_equals_secondary_refused() -> bool:
	var build := _make_build(_WARRIOR, _WARRIOR, ["power_strike"])

	return _expect(
		"primary == secondary",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_DISCIPLINES_NOT_DISTINCT
	)


## A 3/1 split -- three abilities from the primary Discipline, one from the
## secondary -- is legal. MYSTIC is the only Discipline with three authored
## abilities, so it supplies the "3" side.
static func _test_legal_3_1_discipline_split() -> bool:
	var build := _make_build(
		_MYSTIC, _ADVENTURER, ["cataclysm", "energy_bolt", "force_barrier", "field_dressing"]
	)

	return _expect(
		"3/1 Discipline split", MobaBuildValidator.validate(build, _ALLOCATION_POLICY), &""
	)


## A 2/2 split -- two abilities from each Discipline -- is legal.
static func _test_legal_2_2_discipline_split() -> bool:
	var build := _make_build(
		_WARRIOR, _GUARDIAN, ["power_strike", "whirlwind", "brace", "shield_bash"]
	)

	return _expect(
		"2/2 Discipline split", MobaBuildValidator.validate(build, _ALLOCATION_POLICY), &""
	)


## An action ability from a third Discipline is refused with
## FAILURE_ABILITY_OUTSIDE_DISCIPLINES.
static func _test_ability_from_third_discipline_refused() -> bool:
	# aimed_shot is MARKSMAN, outside the WARRIOR/GUARDIAN pair.
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace", "aimed_shot"])

	return _expect(
		"action ability from a third Discipline",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_ABILITY_OUTSIDE_DISCIPLINES
	)


## The passive slot is inside the Discipline-membership check, not exempt from it:
## a passive from outside the pair is refused the same way an action slot is.
static func _test_passive_from_outside_disciplines_refused() -> bool:
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike"], "aimed_shot")

	return _expect(
		"passive from outside the Discipline pair",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_ABILITY_OUTSIDE_DISCIPLINES
	)


## D3: weapon choice is unconstrained by Discipline. A long-range, slow-projectile
## weapon on an all-melee WARRIOR/GUARDIAN kit is legal -- the validator never
## reads the weapon at all, and this test exists to keep it that way.
##
## Built in-fixture rather than loaded: rules/data/weapons/ ships only the melee
## longsword today, and a fixture-owned MobaWeapon is safe to configure freely
## (see the sharing note on MobaLoadout.weapon).
static func _test_ranged_weapon_with_melee_disciplines_legal() -> bool:
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"])

	var bow := MobaWeapon.new()
	bow.damage = 40.0
	bow.attack_range = 25.0
	bow.projectile_speed = 60.0
	build.loadout.weapon = bow

	return _expect(
		"ranged weapon with melee-Discipline abilities",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		&""
	)


## An allocation summing to exactly the policy's total pool is legal.
static func _test_stat_pool_exactly_at_cap_legal() -> bool:
	var allocation := _allocation_summing_to(_ALLOCATION_POLICY.total_points)
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"], "", allocation)

	return _expect(
		"stat allocation exactly at the pool size",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		&""
	)


## One point over the pool is refused with FAILURE_STAT_POOL_OVERSPENT.
##
## The overspend is spread across stats so no single stat trips the per-stat cap
## first -- otherwise this would assert the wrong constant.
static func _test_stat_pool_one_over_cap_refused() -> bool:
	var allocation := _allocation_summing_to(_ALLOCATION_POLICY.total_points + 1)
	var build := _make_build(_WARRIOR, _GUARDIAN, ["power_strike", "brace"], "", allocation)

	return _expect(
		"stat allocation one point over the pool size",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_STAT_POOL_OVERSPENT
	)


## Spread `total` points across distinct allocatable stats without exceeding the
## policy's per-stat cap, so a pool-size assertion is not masked by the cap check.
static func _allocation_summing_to(total: int) -> Dictionary[StringName, int]:
	var allocation: Dictionary[StringName, int] = {}
	var remaining := total
	for stat_name in _ALLOCATION_POLICY.get_allocatable_stats():
		if remaining <= 0:
			break
		var points: int = mini(remaining, _ALLOCATION_POLICY.per_stat_cap)
		allocation[stat_name] = points
		remaining -= points

	assert(remaining == 0, "Policy cannot express an allocation of %d points" % total)
	return allocation


## A build that equips only its primary Discipline is legal -- the secondary is a
## permission, not a quota. Uses every MYSTIC ability authored today plus a MYSTIC
## passive, with ADVENTURER declared and unused.
static func _test_single_discipline_build_legal() -> bool:
	var build := _make_build(
		_MYSTIC, _ADVENTURER, ["cataclysm", "energy_bolt", "force_barrier"], "energy_bolt"
	)

	return _expect(
		"single-Discipline build with the secondary unused",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		&""
	)


## The shipped template build validates as legal unmodified.
static func _test_template_build_validates_legal() -> bool:
	return _expect(
		"shipped rules/data/builds/ template",
		MobaBuildValidator.validate(_TEMPLATE_BUILD, _ALLOCATION_POLICY),
		&""
	)


## A negative point value is refused with FAILURE_STAT_ALLOCATION_NEGATIVE.
static func _test_negative_stat_allocation_refused() -> bool:
	var build := _make_build(
		_WARRIOR, _GUARDIAN, ["power_strike", "brace"], "", {MobaStatBlock.ATTACK_DAMAGE: -5}
	)

	return _expect(
		"negative stat allocation",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_STAT_ALLOCATION_NEGATIVE
	)


## An allocation key that is not a MobaStatBlock stat is refused with
## FAILURE_STAT_ALLOCATION_UNKNOWN_STAT.
static func _test_unknown_stat_allocation_refused() -> bool:
	var build := _make_build(
		_WARRIOR, _GUARDIAN, ["power_strike", "brace"], "", {&"nonexistent_stat": 1}
	)

	return _expect(
		"unknown stat in the allocation",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_STAT_ALLOCATION_UNKNOWN_STAT
	)


## A single stat above the per-stat cap is refused with
## FAILURE_STAT_ALLOCATION_EXCEEDS_PER_STAT_MAX, even when the total pool is fine.
static func _test_stat_exceeds_per_stat_cap_refused() -> bool:
	var over_cap: int = _ALLOCATION_POLICY.per_stat_cap + 1
	var build := _make_build(
		_WARRIOR, _GUARDIAN, ["power_strike", "brace"], "", {MobaStatBlock.ATTACK_DAMAGE: over_cap}
	)

	# Guard the premise: this must fail on the per-stat cap, not the pool.
	assert(over_cap <= _ALLOCATION_POLICY.total_points)

	return _expect(
		"single stat over the per-stat cap",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_STAT_ALLOCATION_EXCEEDS_PER_STAT_MAX
	)


## An equipped ability id that does not resolve is refused with
## FAILURE_UNKNOWN_ABILITY.
static func _test_unknown_ability_refused() -> bool:
	var build := _make_build(_WARRIOR, _GUARDIAN, ["nonexistent_ability"])

	return _expect(
		"unresolvable ability id",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_UNKNOWN_ABILITY
	)


## A structurally invalid loadout is refused with FAILURE_LOADOUT_INVALID.
##
## The duplicate is written to the slot fields directly rather than through
## set_action_slot(), which refuses duplicates at the setter and so cannot
## produce the state under test. An authored .tres reaches the same state the
## same way, which is why the validator must catch it rather than trusting that
## every loadout was built through the setter.
static func _test_loadout_with_duplicate_abilities_refused() -> bool:
	var build := _make_build(_WARRIOR, _GUARDIAN, [])
	build.loadout.action_slot_1 = "power_strike"
	build.loadout.action_slot_2 = "power_strike"

	return _expect(
		"loadout with a duplicate ability id",
		MobaBuildValidator.validate(build, _ALLOCATION_POLICY),
		MobaBuildValidator.FAILURE_LOADOUT_INVALID
	)


## get_effective_stat_block() returns a new block and leaves the baseline alone.
static func _test_effective_stat_block_does_not_mutate_baseline() -> bool:
	var baseline := MobaStatBlock.new()
	var baseline_attack_damage: int = baseline.attack_damage

	var build := _make_build(
		_WARRIOR, _GUARDIAN, ["power_strike"], "", {MobaStatBlock.ATTACK_DAMAGE: 3}
	)
	var effective := build.get_effective_stat_block(baseline)

	if baseline.attack_damage != baseline_attack_damage:
		print("ERROR: get_effective_stat_block() mutated the baseline stat block")
		return false
	if effective.attack_damage != baseline_attack_damage + 3:
		print(
			(
				"ERROR: expected effective attack_damage %d, got %d"
				% [baseline_attack_damage + 3, effective.attack_damage]
			)
		)
		return false

	return true
