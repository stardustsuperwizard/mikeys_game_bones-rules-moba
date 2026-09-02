## Player-originated command that submits a character build to the server.
##
## This is the gated half of #336. The submission is routed through
## `ActionRunner.run()`, so `Authority.can_perform()` refuses a peer trying to
## submit a build for an actor it does not own before `execute()` is ever
## reached -- no ownership logic is needed, or wanted, in this file.
##
## Applying an already-accepted build to a spawning actor is deliberately NOT a
## second Action: that is ordinary server-authoritative spawn initialization,
## the same category of work `WorldManager._spawn_actor()` already does for
## `character_sheet`. `WorldManager.submit_build()` is the seam that runs this
## Action and stores its result.
##
## Legality itself is not decided here. `execute()` delegates to
## `MobaBuildValidator.validate()` -- the single pure function the creation UI
## (#335) also calls -- and returns that function's reason verbatim on refusal.
## Copying the validator's FAILURE_* block into this class would create two
## lists free to drift apart, and the acceptance criterion is that the server
## refuses with *the exact reason the validator gives*. Returning the
## validator's own StringName makes "identical input, identical reason" true by
## construction rather than by convention.
class_name MobaSubmitBuildAction
extends Action

## No build, or no allocation policy, was supplied.
##
## The one refusal this Action owns. `MobaBuildValidator.validate()` decides the
## legality of a build that exists; it cannot speak for one that does not, so a
## null submission has no validator reason to forward and needs its own.
const FAILURE_NO_BUILD = &"no_build"

## There is no actor to submit a build for.
##
## Never returned by execute() -- an Action always has its actor. It lives here
## so the submission seam has one reason vocabulary rather than two:
## WorldManager.submit_build() emits it for a peer with no spawned actor, which
## is a case it has to catch before ActionRunner, since Authority.can_perform()
## reads ownership off an actor that would not exist.
const FAILURE_NO_ACTOR = &"no_actor"

## The build being submitted. Validated, never mutated.
var build: MobaCharacterBuild

## The authored policy the allocation is checked against.
var allocation_policy: MobaStatAllocationPolicy


func _init(
	p_actor: Actor, p_build: MobaCharacterBuild, p_allocation_policy: MobaStatAllocationPolicy
) -> void:
	super(p_actor)
	build = p_build
	allocation_policy = p_allocation_policy


func execute() -> ActionResult:
	if build == null or allocation_policy == null:
		return ActionResult.new(false, FAILURE_NO_BUILD)

	var reason := MobaBuildValidator.validate(build, allocation_policy)
	if reason != &"":
		return ActionResult.new(false, reason)

	return ActionResult.new(true)
