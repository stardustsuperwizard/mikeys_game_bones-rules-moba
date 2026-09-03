## Pure function validator for character builds.
##
## Decides whether a build is legal, returning a typed reason constant on refusal.
## This is the canonical, sole place build-legality is decided — every caller must
## use this function rather than re-deriving any part of the legality logic.
##
## All methods are static, take plain resource arguments, and touch no node
## and no scene tree. The same "pure" bar MobaFormulas documents, enabling
## unit testing and deterministic validation.
##
## ## Duplicate Names and Offensive Content
##
## The validator does not check for duplicate character names or offensive content.
## No cross-peer name registry exists to check duplicates against, and no third-party
## moderation dependency is permitted in the rules module. These policies must be
## enforced by the application layer (server submission, account system, or moderators)
## rather than in the portable rules engine.
class_name MobaBuildValidator

## Maximum allowed character name length.
const MAX_NAME_LENGTH: int = 32

## Failure reasons returned as StringName (mirroring MobaAbilityAction convention)
const FAILURE_NAME_EMPTY = &"name_empty"
const FAILURE_NAME_TOO_LONG = &"name_too_long"
const FAILURE_NAME_INVALID_CHARACTERS = &"name_invalid_characters"
const FAILURE_DISCIPLINES_NOT_DISTINCT = &"disciplines_not_distinct"
const FAILURE_LOADOUT_INVALID = &"loadout_invalid"
const FAILURE_UNKNOWN_ABILITY = &"unknown_ability"
const FAILURE_ABILITY_OUTSIDE_DISCIPLINES = &"ability_outside_disciplines"
const FAILURE_STAT_ALLOCATION_NEGATIVE = &"stat_allocation_negative"
const FAILURE_STAT_ALLOCATION_UNKNOWN_STAT = &"stat_allocation_unknown_stat"
const FAILURE_STAT_ALLOCATION_EXCEEDS_PER_STAT_MAX = &"stat_allocation_exceeds_per_stat_max"
const FAILURE_STAT_POOL_OVERSPENT = &"stat_pool_overspent"


## Validate a character build against an allocation policy.
##
## Returns &"" when legal, otherwise exactly one of the FAILURE_* constants.
## This is the authoritative legality gate both the creation UI and the
## server-side submission command must call.
##
## Validation order: character_name, appearance, disciplines, loadout,
## abilities, then stat allocation. Character name is checked first so that
## invalid names are rejected early regardless of build content.
static func validate(
	build: MobaCharacterBuild, allocation_policy: MobaStatAllocationPolicy
) -> StringName:
	# Check character name first
	var failure := _check_character_name(build.character_name)
	if failure != &"":
		return failure

	# Check appearance
	failure = MobaAppearanceValidator.validate(build.appearance)
	if failure != &"":
		return failure

	# Check primary != secondary
	if build.primary_discipline == build.secondary_discipline:
		return FAILURE_DISCIPLINES_NOT_DISTINCT

	# Validate loadout structure (duplicate ids, too many actions)
	if build.loadout == null or not build.loadout.validate():
		return FAILURE_LOADOUT_INVALID

	# Check all equipped abilities exist and belong to primary/secondary
	failure = _check_abilities(build)
	if failure != &"":
		return failure

	# Check stat allocation
	failure = _check_stat_allocation(build, allocation_policy)
	if failure != &"":
		return failure

	return &""


## Check that the character name is valid.
## Returns empty StringName if legal, otherwise a FAILURE_* constant.
## Accepts only characters that character_creation.gd's _sanitize_filename()
## policy accepts unchanged: a-z, A-Z, 0-9, space, underscore, then stripped.
static func _check_character_name(name: String) -> StringName:
	# Empty names are rejected
	if name.is_empty():
		return FAILURE_NAME_EMPTY

	# Check length (after any whitespace is not yet stripped, but compare as-is)
	if name.length() > MAX_NAME_LENGTH:
		return FAILURE_NAME_TOO_LONG

	# Check character set: only letters, digits, spaces, and underscores allowed
	for char in name:
		if not (
			(char >= "a" and char <= "z")
			or (char >= "A" and char <= "Z")
			or (char >= "0" and char <= "9")
			or char == " "
			or char == "_"
		):
			return FAILURE_NAME_INVALID_CHARACTERS

	return &""


## Check that all equipped abilities exist and belong to the primary/secondary Disciplines.
## Includes both action and passive slots.
## Returns empty StringName if legal, otherwise a FAILURE_* constant.
static func _check_abilities(build: MobaCharacterBuild) -> StringName:
	if build.loadout == null:
		return &""

	var primary = build.primary_discipline
	var secondary = build.secondary_discipline

	# Check action slots 1-4
	for i in range(1, 5):
		var ability_id = build.loadout.get_action_slot(i)
		if ability_id == "":
			continue  # Empty slot is fine

		var ability = MobaAbilityLibrary.get_ability(StringName(ability_id))
		if ability == null:
			return FAILURE_UNKNOWN_ABILITY

		if ability.discipline != primary and ability.discipline != secondary:
			return FAILURE_ABILITY_OUTSIDE_DISCIPLINES

	# Check passive slot
	var passive_id = build.loadout.get_passive_slot()
	if passive_id != "":
		var passive = MobaAbilityLibrary.get_ability(StringName(passive_id))
		if passive == null:
			return FAILURE_UNKNOWN_ABILITY

		if passive.discipline != primary and passive.discipline != secondary:
			return FAILURE_ABILITY_OUTSIDE_DISCIPLINES

	return &""


## Check stat allocation against the policy.
## Returns empty StringName if legal, otherwise a FAILURE_* constant.
static func _check_stat_allocation(
	build: MobaCharacterBuild, allocation_policy: MobaStatAllocationPolicy
) -> StringName:
	var allocatable = allocation_policy.get_allocatable_stats()
	var total_spent = 0

	for stat_name in build.stat_allocation:
		var points: int = build.stat_allocation[stat_name]

		# Check non-negative
		if points < 0:
			return FAILURE_STAT_ALLOCATION_NEGATIVE

		# Check the stat is a real stat AND one this policy opens for allocation.
		# Both halves are checked: a policy may name a stat that MobaStatBlock does
		# not define, and get_allocatable_stats() falls back to every valid stat when
		# the policy leaves allocatable_stats empty.
		if stat_name not in MobaStatBlock.get_valid_stats():
			return FAILURE_STAT_ALLOCATION_UNKNOWN_STAT
		if stat_name not in allocatable:
			return FAILURE_STAT_ALLOCATION_UNKNOWN_STAT

		# Check per-stat cap
		if points > allocation_policy.per_stat_cap:
			return FAILURE_STAT_ALLOCATION_EXCEEDS_PER_STAT_MAX

		total_spent += points

	# Check total pool
	if total_spent > allocation_policy.total_points:
		return FAILURE_STAT_POOL_OVERSPENT

	return &""
