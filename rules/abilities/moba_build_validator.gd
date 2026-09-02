## Pure function validator for character builds.
##
## Decides whether a build is legal, returning a typed reason constant on refusal.
## This is the canonical, sole place build-legality is decided — every caller must
## use this function rather than re-deriving any part of the legality logic.
##
## All methods are static, take plain resource arguments, and touch no node
## and no scene tree. The same "pure" bar MobaFormulas documents, enabling
## unit testing and deterministic validation.
class_name MobaBuildValidator

## Failure reasons returned as StringName (mirroring MobaAbilityAction convention)
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
static func validate(
	build: MobaCharacterBuild, allocation_policy: MobaStatAllocationPolicy
) -> StringName:
	# Check primary != secondary
	if build.primary_discipline == build.secondary_discipline:
		return FAILURE_DISCIPLINES_NOT_DISTINCT

	# Validate loadout structure (duplicate ids, too many actions)
	if build.loadout == null or not build.loadout.validate():
		return FAILURE_LOADOUT_INVALID

	# Check all equipped abilities exist and belong to primary/secondary
	var failure := _check_abilities(build)
	if failure != &"":
		return failure

	# Check stat allocation
	failure = _check_stat_allocation(build, allocation_policy)
	if failure != &"":
		return failure

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
