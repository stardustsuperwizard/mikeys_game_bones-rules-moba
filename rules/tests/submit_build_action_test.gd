## Test suite for MobaSubmitBuildAction (#336).
##
## Scope is the command itself: the gate in front of it and the reason that
## comes out of it. The spawn half of #336 -- an accepted build reaching a real
## MobaCombatant through WorldManager.spawn() -- needs game scenes, which
## rules/ may not load, and lives in tests/build_spawn_integration_test.gd.
##
## Covers, in order:
##   - a legal build submitted by a peer for its own actor is accepted
##   - an illegal build is refused
##   - the refusal reason is byte-identical to the one MobaBuildValidator gives
##     for the same input called directly, across every failure shape
##   - a submission for an actor the requester does not own is refused by
##     Authority.can_perform() before execute() runs at all
##   - a null build is refused with this Action's own reason rather than a
##     borrowed validator one
##
## The reason-parity checks are the load-bearing ones. "The server re-validates
## with the same pure function the UI uses" is not observable by reading the
## code from the outside; identical reasons for identical inputs is what makes
## it a fact, and it is asserted per failure shape rather than once so a future
## hand-rolled special case in the Action fails here instead of drifting quietly.
class_name SubmitBuildActionTest

const _ALLOCATION_POLICY = preload("res://rules/data/stat_blocks/stat_allocation_policy.tres")

# A peer id that is neither the server (1) nor "unowned" (0), so an actor merely
# defaulting to server ownership is distinguishable from one deliberately owned.
const _OWNING_PEER := 7
const _OTHER_PEER := 9


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_legal_build_accepted())
	violations.append_array(_test_illegal_build_refused())
	violations.append_array(_test_reason_matches_validator_for_every_failure())
	violations.append_array(_test_unowned_actor_submission_denied())
	violations.append_array(_test_null_build_refused())

	if violations.is_empty():
		return true

	printerr("\n=== Submit Build Action Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


## An Actor owned by the given peer. No scene, no tree: Authority reads
## actor.owner_id and nothing else, and Action holds the Actor by reference.
static func _make_actor(owner_id: int) -> Actor:
	var actor := Actor.new()
	actor.owner_id = owner_id
	return actor


## A build with the given Discipline pair and equipped ability ids.
##
## Legality is entirely the caller's choice -- this helper never repairs a build,
## so a test asking for an illegal shape gets exactly that shape.
static func _make_build(
	primary: MobaAbility.Discipline,
	secondary: MobaAbility.Discipline,
	action_ids: Array,
	passive_id: String = ""
) -> MobaCharacterBuild:
	var loadout := MobaLoadout.new()
	for i in range(action_ids.size()):
		loadout.set_action_slot(i + 1, action_ids[i])
	if passive_id != "":
		loadout.set_passive_slot(passive_id)

	var build := MobaCharacterBuild.new()
	build.character_name = "Fixture"
	build.primary_discipline = primary
	build.secondary_discipline = secondary
	build.loadout = loadout

	return build


## A legal WARRIOR/GUARDIAN build: both abilities are inside the pair.
static func _make_legal_build() -> MobaCharacterBuild:
	return _make_build(
		MobaAbility.Discipline.WARRIOR, MobaAbility.Discipline.GUARDIAN, ["power_strike", "brace"]
	)


static func _test_legal_build_accepted() -> Array[String]:
	var violations: Array[String] = []

	var action := MobaSubmitBuildAction.new(
		_make_actor(_OWNING_PEER), _make_legal_build(), _ALLOCATION_POLICY
	)
	var result := ActionRunner.run(action, _OWNING_PEER)

	if not result.success:
		violations.append(
			"legal build submitted by its owner was refused: '%s'" % String(result.reason)
		)

	return violations


static func _test_illegal_build_refused() -> Array[String]:
	var violations: Array[String] = []

	# aimed_shot is MARKSMAN -- a third Discipline, outside the WARRIOR/GUARDIAN pair.
	var build := _make_build(
		MobaAbility.Discipline.WARRIOR,
		MobaAbility.Discipline.GUARDIAN,
		["power_strike", "brace", "aimed_shot"]
	)
	var action := MobaSubmitBuildAction.new(_make_actor(_OWNING_PEER), build, _ALLOCATION_POLICY)
	var result := ActionRunner.run(action, _OWNING_PEER)

	if result.success:
		violations.append("third-Discipline ability was accepted")
	if result.reason != MobaBuildValidator.FAILURE_ABILITY_OUTSIDE_DISCIPLINES:
		(
			violations
			. append(
				(
					"third-Discipline refusal reason was '%s', expected '%s'"
					% [
						String(result.reason),
						String(MobaBuildValidator.FAILURE_ABILITY_OUTSIDE_DISCIPLINES),
					]
				)
			)
		)

	return violations


## For each distinct illegal shape, the Action's reason must equal the reason
## MobaBuildValidator.validate() returns for that same build.
static func _test_reason_matches_validator_for_every_failure() -> Array[String]:
	var violations: Array[String] = []

	var cases := {
		"third-Discipline action ability":
		_make_build(
			MobaAbility.Discipline.WARRIOR,
			MobaAbility.Discipline.GUARDIAN,
			["power_strike", "aimed_shot"]
		),
		"passive outside the pair":
		_make_build(
			MobaAbility.Discipline.WARRIOR,
			MobaAbility.Discipline.GUARDIAN,
			["power_strike"],
			"energy_bolt"
		),
		"primary equals secondary":
		_make_build(
			MobaAbility.Discipline.WARRIOR, MobaAbility.Discipline.WARRIOR, ["power_strike"]
		),
		"unknown ability id":
		_make_build(
			MobaAbility.Discipline.WARRIOR, MobaAbility.Discipline.GUARDIAN, ["no_such_ability_id"]
		),
	}

	# Stat-allocation failures, built off a legal base so the only illegal thing
	# about each is the allocation itself.
	#
	# Overspending is spread across three stats rather than dumped on one: the
	# per-stat cap is below the pool total, so a single oversized stat trips
	# FAILURE_STAT_ALLOCATION_EXCEEDS_PER_STAT_MAX first and the pool check never
	# runs. Each stat here stays at the cap while their sum clears the pool.
	var overspent_allocation: Dictionary[StringName, int] = {
		MobaStatBlock.ATTACK_DAMAGE: _ALLOCATION_POLICY.per_stat_cap,
		MobaStatBlock.ARMOR: _ALLOCATION_POLICY.per_stat_cap,
		MobaStatBlock.HEALTH: _ALLOCATION_POLICY.per_stat_cap,
	}
	var overspent := _make_legal_build()
	overspent.stat_allocation = overspent_allocation
	cases["stat pool overspent"] = overspent

	var over_cap_allocation: Dictionary[StringName, int] = {
		MobaStatBlock.ATTACK_DAMAGE: _ALLOCATION_POLICY.per_stat_cap + 1,
	}
	var over_cap := _make_legal_build()
	over_cap.stat_allocation = over_cap_allocation
	cases["single stat over the per-stat cap"] = over_cap

	var negative_allocation: Dictionary[StringName, int] = {MobaStatBlock.ATTACK_DAMAGE: -1}
	var negative := _make_legal_build()
	negative.stat_allocation = negative_allocation
	cases["negative allocation"] = negative

	var unknown_stat_allocation: Dictionary[StringName, int] = {&"not_a_stat": 1}
	var unknown_stat := _make_legal_build()
	unknown_stat.stat_allocation = unknown_stat_allocation
	cases["unknown allocated stat"] = unknown_stat

	for label in cases:
		var build: MobaCharacterBuild = cases[label]

		var direct_reason := MobaBuildValidator.validate(build, _ALLOCATION_POLICY)
		var action := MobaSubmitBuildAction.new(
			_make_actor(_OWNING_PEER), build, _ALLOCATION_POLICY
		)
		var action_reason := ActionRunner.run(action, _OWNING_PEER).reason

		# A case that stopped being illegal proves nothing about parity, so the
		# fixture itself is checked rather than assumed.
		if direct_reason == &"":
			violations.append("case '%s' is no longer illegal -- fixture is stale" % label)
			continue

		if action_reason != direct_reason:
			violations.append(
				(
					"case '%s': action reason '%s' != validator reason '%s'"
					% [label, String(action_reason), String(direct_reason)]
				)
			)

	return violations


## Authority.can_perform() refuses a submission for someone else's actor.
##
## The build is legal, so the only thing that can refuse it is the ownership
## gate -- if this ever passes, routing through ActionRunner has been lost.
static func _test_unowned_actor_submission_denied() -> Array[String]:
	var violations: Array[String] = []

	var action := MobaSubmitBuildAction.new(
		_make_actor(_OWNING_PEER), _make_legal_build(), _ALLOCATION_POLICY
	)
	var result := ActionRunner.run(action, _OTHER_PEER)

	if result.success:
		violations.append("a peer submitted a build for an actor it does not own")

	# Same legal build, submitted by its actual owner, must still be accepted --
	# otherwise the check above could pass for the wrong reason.
	var owner_action := MobaSubmitBuildAction.new(
		_make_actor(_OWNING_PEER), _make_legal_build(), _ALLOCATION_POLICY
	)
	if not ActionRunner.run(owner_action, _OWNING_PEER).success:
		violations.append("ownership denial fixture also refuses the legitimate owner")

	return violations


static func _test_null_build_refused() -> Array[String]:
	var violations: Array[String] = []

	var action := MobaSubmitBuildAction.new(_make_actor(_OWNING_PEER), null, _ALLOCATION_POLICY)
	var result := ActionRunner.run(action, _OWNING_PEER)

	if result.success:
		violations.append("a null build was accepted")
	if result.reason != MobaSubmitBuildAction.FAILURE_NO_BUILD:
		violations.append(
			(
				"null build reason was '%s', expected '%s'"
				% [String(result.reason), String(MobaSubmitBuildAction.FAILURE_NO_BUILD)]
			)
		)

	return violations
