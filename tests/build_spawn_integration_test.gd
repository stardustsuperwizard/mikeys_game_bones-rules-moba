# Headless integration test for #336's spawn half: an accepted build is what a
# player's MobaCombatant actually spawns with.
#
# Run with:
#   godot --headless --path . --script tests/build_spawn_integration_test.gd
#
# Covers, in order:
#   - a peer with no accepted build spawns on the shipped fallback, not on an
#     empty loadout and not by failing to spawn;
#   - a legal build submitted through WorldManager.submit_build() is accepted,
#     and the actor spawned for that peer carries its loadout and its effective
#     stats -- not the loadout scenes/player/player.tscn bakes in;
#   - an illegal submission is refused and leaves the previously accepted build
#     in place, so the next spawn is still the last build the server agreed to;
#   - a peer cannot submit a build for another peer's actor;
#   - the build survives the spawn payload intact.
#
# That last one is the multiplayer check, and the reason it is here rather than
# asserted by eye. Spawn data crosses the wire through var_to_bytes with object
# decoding off, so a Resource put in that dictionary is silently dropped for
# every remote peer while working perfectly in single-player. Round-tripping the
# payload through WorldManager's own encode/decode is what makes a regression to
# "just put the MobaLoadout in the dict" fail a test instead of shipping as a
# bug only ever visible on a second machine.
#
# Spawning goes through WorldManager.spawn(), not a local copy of its
# initialization sequence, so deleting the build wiring from
# scripts/world_manager.gd fails this test rather than sliding past it.
#
# This test is NOT wired into tests/test_bootstrap.gd: it loads game scenes and
# a WorldManager, matching the precedent set by tests/session_manager_test.gd
# and tests/character_creation_test.gd.
extends SceneTree

const _PLAYER_SPAWN_POINT := preload("res://resources/player_spawn_point.tres")
const _ENEMY_SPAWN_POINT := preload("res://resources/enemy_spawn_point.tres")
const _FALLBACK_BUILD := preload("res://rules/data/builds/melee_bruiser_build.tres")
const _BASELINE_STAT_BLOCK := preload("res://rules/data/stat_blocks/baseline.tres")

# A peer id that is neither the server (1) nor "unowned" (0), so an actor merely
# defaulting to server ownership is distinguishable from one deliberately owned.
const _OWNING_PEER := 7
const _OTHER_PEER := 9

# Peers used only by the character-name checks. Distinct ids rather than a reuse
# of _OWNING_PEER because PeerIdentityRegistry is an autoload and therefore
# outlives each _make_world_manager(): a build accepted in an earlier check is
# still accepted here, and a name assertion is exactly the kind that would read
# a leftover from the check above it and pass for the wrong reason.
const _NAMED_PEER_A := 11
const _NAMED_PEER_B := 13
const _UNNAMED_PEER := 17

const _EXPECTED_CHECKS: Array[String] = [
	"peer with no accepted build spawns on the shipped fallback",
	"accepted build reaches the spawned combatant's loadout",
	"accepted build's stat allocation reaches the spawned combatant",
	"refused submission leaves the accepted build in place",
	"a peer cannot submit a build for another peer's actor",
	"build survives the spawn payload intact",
	"a bot spawn keeps its scene loadout and baseline stats",
	"editing a build after acceptance does not change stored state",
	"accepted build's character_name reaches the spawned actor's sheet",
	"two builds spawn two differently named actors",
	"a bot spawn keeps the character name its sheet authored",
	"a build with no name leaves the spawn point's authored name alone",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	_test_fallback_when_nothing_submitted()
	_test_accepted_build_reaches_spawned_combatant()
	_test_refusal_preserves_accepted_build()
	_test_cannot_submit_for_another_peers_actor()
	_test_build_survives_spawn_payload()
	_test_bot_spawn_is_untouched_by_the_fallback_build()
	_test_accepted_build_is_snapshotted()
	_test_build_name_reaches_the_spawned_actor()
	_test_two_builds_spawn_two_different_names()
	_test_bot_spawn_keeps_its_authored_name()
	_test_nameless_build_leaves_the_authored_name()

	_finish()


## A WorldManager attached to the tree but with no MultiplayerSpawner child, so
## spawn() falls through to _spawn_actor() -- the same function the spawner calls
## as its spawn_function in the real scene.
func _make_world_manager() -> WorldManager:
	var world_manager := WorldManager.new()
	world_manager.player_spawn_point = _PLAYER_SPAWN_POINT
	root.add_child(world_manager)
	return world_manager


## Spawn a player actor for a peer through the real WorldManager path and parent
## it, so _ready() runs exactly as a spawned actor's does.
func _spawn_player(world_manager: WorldManager, peer_id: int) -> Node:
	world_manager.spawn_player_for_peer(peer_id)
	var actor: Node = world_manager._peer_actors.get(peer_id)
	if actor != null and actor.get_parent() == null:
		world_manager.add_child(actor)
	return actor


## A legal WARRIOR/GUARDIAN build. Both abilities sit inside the pair, and the
## allocation stays inside the shipped policy's pool and per-stat cap.
func _make_legal_build(name: String, allocation: Dictionary) -> MobaCharacterBuild:
	var loadout := MobaLoadout.new()
	loadout.set_action_slot(1, "whirlwind")
	loadout.set_action_slot(2, "shield_bash")
	loadout.weapon = _FALLBACK_BUILD.loadout.weapon

	var typed_allocation: Dictionary[StringName, int] = {}
	typed_allocation.assign(allocation)

	var build := MobaCharacterBuild.new()
	build.character_name = name
	build.primary_discipline = MobaAbility.Discipline.WARRIOR
	build.secondary_discipline = MobaAbility.Discipline.GUARDIAN
	build.stat_allocation = typed_allocation
	build.loadout = loadout

	return build


## An actor whose peer never submitted anything still spawns, on the fallback.
func _test_fallback_when_nothing_submitted() -> void:
	var world_manager := _make_world_manager()
	var actor := _spawn_player(world_manager, _OWNING_PEER)

	if actor == null:
		_fail("a peer with no accepted build failed to spawn at all")
		return

	var combatant := actor.get_node_or_null("MobaCombatant")
	if combatant == null or combatant.loadout == null:
		_fail("fallback spawn produced no loadout")
		return

	if combatant.loadout.get_action_slot(1) != _FALLBACK_BUILD.loadout.get_action_slot(1):
		_fail(
			(
				"fallback spawn slot 1 is '%s', expected the shipped template's '%s'"
				% [
					combatant.loadout.get_action_slot(1),
					_FALLBACK_BUILD.loadout.get_action_slot(1),
				]
			)
		)
		return

	_pass("peer with no accepted build spawns on the shipped fallback")


## The whole point of the task: submit, spawn, and find the submitted build on
## the combatant rather than the one player.tscn baked in.
func _test_accepted_build_reaches_spawned_combatant() -> void:
	var world_manager := _make_world_manager()

	# The actor must exist before a build can be submitted for it -- ownership is
	# read off the actor, so there is nothing to gate against without one.
	var actor := _spawn_player(world_manager, _OWNING_PEER)
	if actor == null:
		_fail("setup: player actor did not spawn")
		return

	var build := _make_legal_build("Reacher", {MobaStatBlock.ATTACK_DAMAGE: 4})
	var result := world_manager.submit_build(_OWNING_PEER, build)
	if not result.success:
		_fail("setup: legal build was refused -- '%s'" % String(result.reason))
		return

	# Respawn so the accepted build is what spawn initialization reads.
	actor.queue_free()
	world_manager._peer_actors.erase(_OWNING_PEER)
	var respawned := _spawn_player(world_manager, _OWNING_PEER)
	if respawned == null:
		_fail("actor did not respawn after a build was accepted")
		return

	var combatant := respawned.get_node_or_null("MobaCombatant")
	if combatant == null or combatant.loadout == null:
		_fail("respawned combatant has no loadout")
		return

	if combatant.loadout.get_action_slot(1) != "whirlwind":
		_fail(
			(
				"spawned loadout slot 1 is '%s', expected the submitted 'whirlwind'"
				% combatant.loadout.get_action_slot(1)
			)
		)
	elif combatant.loadout.get_action_slot(1) == _FALLBACK_BUILD.loadout.get_action_slot(1):
		_fail("spawned loadout is still the scene-baked default, not the submitted build")
	else:
		_pass("accepted build reaches the spawned combatant's loadout")

	var expected_damage: float = _BASELINE_STAT_BLOCK.attack_damage + 4
	if combatant.stat_block == null:
		_fail("respawned combatant has no stat block")
	elif combatant.stat_block.attack_damage != expected_damage:
		_fail(
			(
				"spawned attack_damage is %s, expected baseline + 4 = %s"
				% [combatant.stat_block.attack_damage, expected_damage]
			)
		)
	else:
		_pass("accepted build's stat allocation reaches the spawned combatant")


## A refused submission must not cost the peer the build it already had.
func _test_refusal_preserves_accepted_build() -> void:
	var world_manager := _make_world_manager()
	if _spawn_player(world_manager, _OWNING_PEER) == null:
		_fail("setup: player actor did not spawn")
		return

	var accepted := _make_legal_build("Keeper", {})
	if not world_manager.submit_build(_OWNING_PEER, accepted).success:
		_fail("setup: legal build was refused")
		return

	# aimed_shot is MARKSMAN -- a third Discipline, outside the WARRIOR/GUARDIAN pair.
	var illegal := _make_legal_build("Usurper", {})
	illegal.loadout.set_action_slot(3, "aimed_shot")

	var refusal := world_manager.submit_build(_OWNING_PEER, illegal)
	if refusal.success:
		_fail("an illegal build was accepted")
		return
	if refusal.reason != MobaBuildValidator.FAILURE_ABILITY_OUTSIDE_DISCIPLINES:
		_fail(
			(
				"illegal build refused with '%s', expected '%s'"
				% [
					String(refusal.reason),
					String(MobaBuildValidator.FAILURE_ABILITY_OUTSIDE_DISCIPLINES),
				]
			)
		)
		return

	# Compared by content, not identity: the server stores a snapshot of an
	# accepted build rather than the caller's object (see _copy_accepted).
	var still_stored := world_manager.get_peer_build(_OWNING_PEER)
	if still_stored.character_name != accepted.character_name:
		_fail(
			(
				"a refused submission overwrote the peer's accepted build: stored '%s', expected '%s'"
				% [still_stored.character_name, accepted.character_name]
			)
		)
		return

	_pass("refused submission leaves the accepted build in place")


## Authority.can_perform() is what refuses this; submit_build() has no ownership
## check of its own, and neither does the Action.
func _test_cannot_submit_for_another_peers_actor() -> void:
	var world_manager := _make_world_manager()
	if _spawn_player(world_manager, _OWNING_PEER) == null:
		_fail("setup: player actor did not spawn")
		return

	var build := _make_legal_build("Intruder", {})
	var result := world_manager.submit_build(_OWNING_PEER, build, _OTHER_PEER)

	if result.success:
		_fail("a peer submitted a build for an actor it does not own")
		return
	if world_manager.get_peer_build(_OWNING_PEER).character_name == build.character_name:
		_fail("a denied submission was stored anyway")
		return

	_pass("a peer cannot submit a build for another peer's actor")


## The spawn payload is plain Variant data, and rebuilding from it reproduces the
## build. A Resource smuggled into that dictionary would fail here.
func _test_build_survives_spawn_payload() -> void:
	var world_manager := _make_world_manager()
	var build := _make_legal_build("Traveller", {MobaStatBlock.ARMOR: 3})

	var payload: Dictionary = world_manager._encode_build(build)

	# var_to_bytes without object support is exactly what the network layer does:
	# an Object anywhere in the payload encodes as null and is gone on arrival.
	# Checked before the round trip as well, because a dropped value reads as a
	# plausible empty string on the far side rather than as an obvious failure.
	var offender := _find_object(payload)
	if offender != "":
		_fail("spawn payload holds an object at '%s' -- it will not survive the wire" % offender)
		return

	var wire: Variant = bytes_to_var(var_to_bytes(payload))
	if not wire is Dictionary:
		_fail("spawn payload did not survive var_to_bytes as a Dictionary")
		return

	var decoded: MobaCharacterBuild = world_manager._decode_build(wire as Dictionary)

	if decoded.character_name != build.character_name:
		_fail("character_name lost in the spawn payload")
	elif decoded.primary_discipline != build.primary_discipline:
		_fail("primary_discipline lost in the spawn payload")
	elif decoded.secondary_discipline != build.secondary_discipline:
		_fail("secondary_discipline lost in the spawn payload")
	elif decoded.loadout.get_action_slot(1) != build.loadout.get_action_slot(1):
		_fail("action slot 1 lost in the spawn payload")
	elif decoded.loadout.get_action_slot(2) != build.loadout.get_action_slot(2):
		_fail("action slot 2 lost in the spawn payload")
	elif decoded.loadout.weapon == null:
		_fail("weapon lost in the spawn payload")
	elif decoded.stat_allocation != build.stat_allocation:
		_fail("stat allocation lost in the spawn payload")
	else:
		_pass("build survives the spawn payload intact")


## An actor that is not a peer must come out of spawn() exactly as its scene
## authored it.
##
## spawn() is the single path for every spawn point, so the per-peer fallback
## build was briefly applied to world and bot content too -- silently giving
## enemies the melee-bruiser allocation (+5 health, +3 attack_damage, +2 armor)
## over baseline and overwriting enemy.tscn's own loadout. Nothing in #336 asks
## for that, and it is invisible without a check like this one: today the bot's
## baked loadout and the fallback build's loadout happen to be the same file, so
## only the stats actually diverge, and only until someone changes either file.
func _test_bot_spawn_is_untouched_by_the_fallback_build() -> void:
	var world_manager := _make_world_manager()

	# Exactly how _ready() spawns world content: no build argument at all.
	var enemy: Node = world_manager.spawn(_ENEMY_SPAWN_POINT, _ENEMY_SPAWN_POINT.authority_id)
	if enemy == null:
		_fail("bot actor did not spawn")
		return
	world_manager.add_child(enemy)

	var combatant := enemy.get_node_or_null("MobaCombatant")
	if combatant == null:
		_fail("bot actor has no MobaCombatant")
		return

	# The fallback build allocates points on top of baseline, so a bot showing
	# baseline numbers is proof the build was not applied to it. Guarded first:
	# an allocation that ever went empty would make these assertions vacuous.
	var allocated := _FALLBACK_BUILD.get_effective_stat_block(_BASELINE_STAT_BLOCK)
	if allocated.attack_damage == _BASELINE_STAT_BLOCK.attack_damage:
		_fail(
			(
				"fixture is stale: the fallback build no longer changes attack_damage, "
				+ "so this check can no longer tell an equipped bot from an untouched one"
			)
		)
		return

	if combatant.stat_block.attack_damage != _BASELINE_STAT_BLOCK.attack_damage:
		_fail(
			(
				"bot attack_damage is %s, expected the scene's baseline %s"
				% [combatant.stat_block.attack_damage, _BASELINE_STAT_BLOCK.attack_damage]
			)
		)
		return
	if combatant.stat_block.armor != _BASELINE_STAT_BLOCK.armor:
		_fail(
			(
				"bot armor is %s, expected the scene's baseline %s"
				% [combatant.stat_block.armor, _BASELINE_STAT_BLOCK.armor]
			)
		)
		return
	if combatant.stat_block.health != _BASELINE_STAT_BLOCK.health:
		_fail(
			(
				"bot health is %s, expected the scene's baseline %s"
				% [combatant.stat_block.health, _BASELINE_STAT_BLOCK.health]
			)
		)
		return

	_pass("a bot spawn keeps its scene loadout and baseline stats")


## What validated is what gets stored, and it stays stored.
##
## The server keeps a snapshot rather than the submitter's object. Without that,
## a caller could hold its reference and edit the accepted build afterwards --
## an illegal build reaching a spawn having never been refused, because it only
## became illegal after the single check that would have caught it.
func _test_accepted_build_is_snapshotted() -> void:
	var world_manager := _make_world_manager()
	if _spawn_player(world_manager, _OWNING_PEER) == null:
		_fail("setup: player actor did not spawn")
		return

	var submitted := _make_legal_build("Snapshot", {MobaStatBlock.ARMOR: 2})
	if not world_manager.submit_build(_OWNING_PEER, submitted).success:
		_fail("setup: legal build was refused")
		return

	# Edit every mutable part of the build the submitter still holds, including
	# an illegal ability the validator would have refused outright.
	submitted.character_name = "Tampered"
	submitted.loadout.set_action_slot(3, "aimed_shot")
	submitted.stat_allocation[MobaStatBlock.ARMOR] = 999

	var stored := world_manager.get_peer_build(_OWNING_PEER)
	if stored.character_name != "Snapshot":
		_fail("stored build's name followed a post-acceptance edit")
		return
	if stored.loadout.get_action_slot(3) != "":
		_fail(
			(
				"stored build's loadout followed a post-acceptance edit: slot 3 is '%s'"
				% stored.loadout.get_action_slot(3)
			)
		)
		return
	if stored.stat_allocation.get(MobaStatBlock.ARMOR, 0) != 2:
		_fail(
			(
				"stored build's allocation followed a post-acceptance edit: armor is %s"
				% stored.stat_allocation.get(MobaStatBlock.ARMOR, 0)
			)
		)
		return

	_pass("editing a build after acceptance does not change stored state")


## The path of the first Object found anywhere in a payload, or "" if it is
## plain data all the way down. Recursive: a Resource nested inside an Array or
## a sub-Dictionary is dropped on the wire just as surely as a top-level one.
func _find_object(value: Variant, path: String = "build") -> String:
	if value is Object:
		return path

	if value is Dictionary:
		for key in value:
			var found := _find_object(value[key], "%s.%s" % [path, key])
			if found != "":
				return found
	elif value is Array:
		for i in range(value.size()):
			var found := _find_object(value[i], "%s[%d]" % [path, i])
			if found != "":
				return found

	return ""


## Read the name the target frame would read: the actor's own sheet.
##
## rules/ui/moba_target_frame.gd is deliberately not driven here -- it needs a
## bound MobaCombatant and a Control tree, and this suite's subject is the spawn
## path, not the frame. What it reads is `actor.character_sheet.character_name`,
## so that is what these checks assert, at the same actor the frame would be
## handed.
func _spawned_name(actor: Node) -> String:
	if actor == null:
		return ""
	var sheet: CharacterSheet = actor.character_sheet
	if sheet == null:
		return ""
	return sheet.character_name


## Submit a build under `name` for `peer_id` and return the actor spawned from
## it, or null with the failure already reported.
##
## The spawn/submit/respawn dance is the same one
## _test_accepted_build_reaches_spawned_combatant() performs: an actor has to
## exist before a build can be submitted for it, because ownership is read off
## the actor, and the accepted build is only read at spawn initialization.
func _spawn_named(world_manager: WorldManager, peer_id: int, name: String) -> Node:
	if _spawn_player(world_manager, peer_id) == null:
		_fail("setup: player actor did not spawn for peer %d" % peer_id)
		return null

	var build := _make_legal_build(name, {MobaStatBlock.ATTACK_DAMAGE: 1})
	var result := world_manager.submit_build(peer_id, build)
	if not result.success:
		_fail("setup: legal build was refused -- '%s'" % String(result.reason))
		return null

	world_manager._peer_actors[peer_id].queue_free()
	world_manager._peer_actors.erase(peer_id)
	return _spawn_player(world_manager, peer_id)


## #352: the name the player typed in character creation reaches the actor.
##
## build_survives_the_spawn_payload already covers character_name across
## _encode_build()/_decode_build(). That half was passing while every player in
## a match still displayed "Player", because nothing asserted the decoded name
## went anywhere. This check is that missing half: it reads the actor, past the
## transport boundary the other one stops at.
func _test_build_name_reaches_the_spawned_actor() -> void:
	var world_manager := _make_world_manager()
	var actor := _spawn_named(world_manager, _NAMED_PEER_A, "Distinctive Name")
	if actor == null:
		return

	var authored: String = _PLAYER_SPAWN_POINT.character_sheet.character_name
	var spawned := _spawned_name(actor)

	if spawned == authored:
		_fail(
			(
				(
					"spawned actor is still named '%s' from the spawn point's sheet, "
					+ "not the submitted build's 'Distinctive Name'"
				)
				% spawned
			)
		)
	elif spawned != "Distinctive Name":
		_fail("spawned actor is named '%s', expected 'Distinctive Name'" % spawned)
	else:
		_pass("accepted build's character_name reaches the spawned actor's sheet")


## Two peers, two builds, two names -- and not one sheet between them.
##
## The names are the user-visible half: two players in a match are two people,
## and a fix that got only one of them there is not a fix.
##
## The object-identity assertion is a separate invariant: two actors must never
## share a CharacterSheet, or one player taking damage would move the other
## one's health bar. It is deliberately NOT claimed here as the detector for a
## fix that writes through the shared resource -- it does not detect that, and a
## comment saying it did would be a lie a later reader would trust.
## Actor._ready() duplicates the sheet on entering the tree, so by the time this
## check reads them, even a scribble-on-the-shared-resource fix has handed each
## actor its own object. The check that actually catches that is
## _test_nameless_build_leaves_the_authored_name(), below, and it catches it as
## name bleed rather than as object identity.
func _test_two_builds_spawn_two_different_names() -> void:
	var world_manager := _make_world_manager()

	var first := _spawn_named(world_manager, _NAMED_PEER_A, "First Player")
	if first == null:
		return
	var second := _spawn_named(world_manager, _NAMED_PEER_B, "Second Player")
	if second == null:
		return

	var first_name := _spawned_name(first)
	var second_name := _spawned_name(second)

	if first_name == second_name:
		_fail(
			(
				(
					"both actors are named '%s' -- the name landed on a sheet the two "
					+ "actors share instead of on each actor's own"
				)
				% first_name
			)
		)
		return
	if first_name != "First Player" or second_name != "Second Player":
		_fail(
			(
				(
					"spawned names are '%s' and '%s', expected 'First Player' and "
					+ "'Second Player'"
				)
				% [first_name, second_name]
			)
		)
		return

	if first.character_sheet == second.character_sheet:
		_fail("both actors hold the same CharacterSheet object, not one each")
		return

	_pass("two builds spawn two differently named actors")


## The Goblin still displays as Enemy.
##
## Bot and world actors are spawned with no build at all, so there is no name to
## apply and the scene's authored one must survive untouched. Kept separate from
## the stats check above so a regression names itself as a naming regression.
func _test_bot_spawn_keeps_its_authored_name() -> void:
	var world_manager := _make_world_manager()

	# Exactly how _ready() spawns world content: no build argument at all.
	var enemy: Node = world_manager.spawn(_ENEMY_SPAWN_POINT, _ENEMY_SPAWN_POINT.authority_id)
	if enemy == null:
		_fail("bot actor did not spawn")
		return
	world_manager.add_child(enemy)

	var authored: String = _ENEMY_SPAWN_POINT.character_sheet.character_name
	if authored == "":
		_fail("fixture is stale: the enemy spawn point's sheet no longer authors a name")
		return

	var spawned := _spawned_name(enemy)
	if spawned != authored:
		_fail("bot actor is named '%s', expected its sheet's authored '%s'" % [spawned, authored])
		return

	_pass("a bot spawn keeps the character name its sheet authored")


## A nameless build gets the authored name -- not a blank, and not the name of
## whoever spawned last.
##
## The nameless case is not hypothetical: the non-empty check lives in
## scripts/character_creation.gd's save path, on the client. MobaBuildValidator
## -- the one the server re-runs on submission -- never looks at character_name,
## so a build with no name is a shape the server accepts. Writing it through
## would leave the target frame falling back to the actor's node name, which is
## worse than the sheet's authored one because nobody authored it.
##
## This is also the check that catches a fix which sets character_name on
## actor.character_sheet directly, without duplicating first. That sheet is the
## cached, shared instance load() hands back for
## resources/player_character_sheet.tres, so every named spawn writes its name
## into the object the *next* spawn starts from. An actor with no name of its
## own then inherits whoever spawned before it -- measured, not theorised: under
## that fix this check reports the actor named "Warrior Bruiser", the shipped
## fallback build's name, left behind by an earlier spawn in this same run.
##
## That bleed is the reason the fix duplicates. It is invisible to the two
## checks above, both of which pass under the broken version.
func _test_nameless_build_leaves_the_authored_name() -> void:
	var world_manager := _make_world_manager()

	if _spawn_player(world_manager, _UNNAMED_PEER) == null:
		_fail("setup: player actor did not spawn")
		return

	var build := _make_legal_build("", {MobaStatBlock.ATTACK_DAMAGE: 1})
	var result := world_manager.submit_build(_UNNAMED_PEER, build)
	if not result.success:
		_fail(
			(
				(
					"setup: a build with no name was refused -- '%s'. If MobaBuildValidator "
					+ "has gained a name rule, this check is obsolete and should be deleted "
					+ "rather than relaxed."
				)
				% String(result.reason)
			)
		)
		return

	world_manager._peer_actors[_UNNAMED_PEER].queue_free()
	world_manager._peer_actors.erase(_UNNAMED_PEER)
	var actor := _spawn_player(world_manager, _UNNAMED_PEER)
	if actor == null:
		_fail("actor did not respawn after a nameless build was accepted")
		return

	var authored: String = _PLAYER_SPAWN_POINT.character_sheet.character_name
	var spawned := _spawned_name(actor)
	if spawned == "":
		_fail("a nameless build blanked the actor's sheet name")
	elif spawned != authored:
		_fail(
			(
				(
					"nameless build produced the name '%s', expected the authored '%s' -- "
					+ "a name left on the shared sheet by an earlier spawn"
				)
				% [spawned, authored]
			)
		)
	else:
		_pass("a build with no name leaves the spawn point's authored name alone")


func _pass(check: String) -> void:
	_completed.append(check)
	print("PASS %s" % check)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	for check in _EXPECTED_CHECKS:
		if check not in _completed:
			_failures.append("check never ran: %s" % check)

	if _failures.is_empty():
		print("\nAll %d build spawn integration checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
