## Server-authoritative registry for peer identity: the last accepted MobaCharacterBuild
## for each peer.
##
## This autoload persists accepted character builds across WorldManager resets and
## provides a single source of truth for "what build should this peer spawn with?"
##
## Registered as the `PeerIdentityRegistry` autoload, so this script deliberately
## carries no `class_name`: a global class sharing an autoload's name is a
## parse error in Godot 4 ("hides an autoload singleton"). This follows the same
## pattern as SessionManager.
extends Node

# The build a peer spawns with when it has not had one accepted yet: a peer that
# connects before visiting character creation, and every existing test or tool
# that spawns without going through it at all. Shipped, authored, and covered by
# build_validator_test.gd's "template validates unmodified" check, so the
# fallback is a legal playable character rather than an empty loadout.
const _FALLBACK_BUILD := preload("res://rules/data/builds/melee_bruiser_build.tres")

# The policy a build's stat allocation is checked against. Preloaded rather than
# load()-ed per submit: it is authored single-instance data, and a parse-time
# failure here is a louder, earlier signal than a null at submission.
#
# The baseline stat block a build is applied on top of stays in WorldManager:
# that is spawn-time concern, and this registry never builds a stat block.
const _ALLOCATION_POLICY := preload("res://rules/data/stat_blocks/stat_allocation_policy.tres")

# Map of peer_id -> the last build that peer submitted and the server accepted.
#
# Authoritative state, and the reason a refused submission is a no-op rather
# than an erase: write access is confined to submit_build(), which only reaches
# here after MobaSubmitBuildAction has returned success. A peer with no entry
# has not had a build accepted yet and get_peer_build() returns _FALLBACK_BUILD.
var _peer_builds: Dictionary[int, MobaCharacterBuild] = {}


## Submit a character build on behalf of a peer, and store it if the server
## accepts it. Returns the ActionResult so a caller can surface the refusal.
##
## This is the server-side seam for the build submission feature. The submission
## goes through ActionRunner rather than calling MobaBuildValidator directly,
## which is what applies Authority.can_perform(): `requester_id` is the peer that
## asked, `actor.owner_id` is who it asked for, and a mismatch is refused here
## without either this function or the Action containing an ownership check of
## its own.
##
## Re-validating server-side is the point even though the creation UI already
## validated: the UI's answer arrives over the network and is not evidence. Both
## sides call the same MobaBuildValidator.validate(), so an illegal build is
## refused with the identical reason wherever it is checked.
##
## A refusal deliberately leaves any previously accepted build in place. The
## peer keeps playing the last build the server agreed to rather than being
## dropped to the fallback by a bad submission.
func submit_build(
	peer_id: int, actor: Actor, build: MobaCharacterBuild, requester_id: int = -1
) -> ActionResult:
	var action := MobaSubmitBuildAction.new(actor, build, _ALLOCATION_POLICY)
	var result := ActionRunner.run(action, peer_id if requester_id == -1 else requester_id)
	if result.success:
		_peer_builds[peer_id] = _copy_accepted(build)

	return result


## The build a peer's actor should spawn with: the last one the server accepted,
## or the shipped fallback if that peer has never had one accepted.
func get_peer_build(peer_id: int) -> MobaCharacterBuild:
	return _peer_builds.get(peer_id, _FALLBACK_BUILD)


## Clear the stored build for a peer (e.g., when they disconnect).
func clear_peer(peer_id: int) -> void:
	_peer_builds.erase(peer_id)


# Snapshot an accepted build for authoritative storage.
#
# What validated is the state of the build at the instant it was checked, and
# that is what has to be kept. Storing the caller's object would let whoever
# submitted it keep a reference and edit the server's copy afterwards -- an
# illegal build reaching a spawn without ever being refused, because it only
# became illegal after the only check. Cheap insurance now, and the submission
# path gains a real remote caller in #335.
#
# stat_allocation and loadout are copied explicitly: Resource.duplicate()
# without deep copying carries a Dictionary and a sub-Resource across as
# references, so the two mutable parts of a build would still be shared. The
# weapon inside the loadout stays shared on purpose -- MobaLoadout.weapon
# documents why that is safe, and MobaCombatant's own loadout setter makes the
# same shallow copy for the same reason.
func _copy_accepted(build: MobaCharacterBuild) -> MobaCharacterBuild:
	var copy := build.duplicate() as MobaCharacterBuild
	copy.stat_allocation = build.stat_allocation.duplicate()
	if build.loadout != null:
		copy.loadout = build.loadout.duplicate() as MobaLoadout
	return copy
