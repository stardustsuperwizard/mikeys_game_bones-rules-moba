## Helper node for activating abilities through the action pipeline.
##
## MobaAbilityCaster provides a convenient interface for activating abilities.
## It creates a MobaAbilityAction and runs it through ActionRunner, handling
## the full ability activation pipeline including legality checks, target resolution,
## resource commitment, and damage application.
class_name MobaAbilityCaster
extends Node


## Activate an ability for the given caster.
## Returns an ActionResult indicating success or failure with a specific reason.
##
## requester_id is the peer whose identity Authority.can_perform() is checked
## against, supplied by whatever called in: the local peer's own id on an
## offline, AI, or server-owned activation, or the remote sender's id when the
## caller took the ask from a client over RPC. It defaults to 1 so that offline
## callers and the rules/ unit suites keep the pre-#320 behaviour of resolving
## as the server.
##
## Named generically on purpose. This module does not depend on the game side
## and must not name its symbols, not even in prose -- the caller is simply
## whoever established the requester's identity.
##
## The context parameter provides all input data:
## - caster: the Actor performing the ability
## - explicit_target: target for targeted abilities (or null for self)
## - aim_direction: direction for skillshot abilities (unused in Batch 1)
## - ground_point: position for ground abilities (unused in Batch 1)
##
## Before checking legality, this stands in for real loadout-time ability
## registration (#28): if the ability id resolves in MobaAbilityLibrary, it is
## registered with the caster's MobaCombatant via register_ability() (idempotent),
## so a caller that hasn't separately registered the ability still activates it.
func activate(
	ability_id: StringName, context: MobaCastContext, requester_id: int = 1
) -> ActionResult:
	if context.caster == null:
		return ActionResult.new(false, MobaAbilityAction.FAILURE_INVALID_CONTEXT)

	var ability := MobaAbilityLibrary.get_ability(ability_id)
	if ability != null:
		var combatant := context.caster.get_node_or_null("MobaCombatant") as MobaCombatant
		if combatant != null:
			combatant.register_ability(ability)

	var action := MobaAbilityAction.new(context.caster, ability_id, context)
	return ActionRunner.run(action, requester_id)


## Activate an ability from a positional action slot (1-based).
## Returns an ActionResult indicating success or failure with a specific reason.
## Returns a failed ActionResult with reason empty_slot if the slot is empty.
## Returns a failed ActionResult if the index is out of range [1..4].
##
## requester_id carries the same meaning as in activate(), and is forwarded
## unchanged: the slot lookup decides *which* ability, never *who* may cast it.
func activate_slot(index: int, context: MobaCastContext, requester_id: int = 1) -> ActionResult:
	if context.caster == null:
		return ActionResult.new(false, MobaAbilityAction.FAILURE_INVALID_CONTEXT)

	var combatant := context.caster.get_node_or_null("MobaCombatant") as MobaCombatant
	if combatant == null:
		return ActionResult.new(false, MobaAbilityAction.FAILURE_INVALID_CONTEXT)

	if index < 1 or index > 4:
		return ActionResult.new(false, MobaAbilityAction.FAILURE_INVALID_CONTEXT)

	var ability_id: StringName = combatant.get_action_slot_ability_id(index)
	if ability_id == &"":
		return ActionResult.new(false, MobaAbilityAction.FAILURE_EMPTY_SLOT)

	return activate(ability_id, context, requester_id)


## Cancel an in-progress cast or break an in-progress channel for the given caster.
## If the caster has no in-progress cast or channel, this is a harmless no-op
## and returns a successful ActionResult.
##
## The caster can be identified by:
## - An Actor, from which the MobaCombatant child is discovered
## - A MobaCastContext, from which the caster Actor is extracted
##
## Args:
##     caster: An Actor or MobaCastContext identifying the caster
##
## Returns:
##     ActionResult indicating success or failure with a specific reason.
##     Success indicates the cancel/break was requested (or no-opped safely).
##     Failure (invalid_context) indicates the caster could not be resolved.
func cancel(caster: Variant) -> ActionResult:
	var resolved_actor: Actor = null

	# Resolve an Actor from the input, exactly as activate() does
	if caster is Actor:
		resolved_actor = caster as Actor
	elif caster is MobaCastContext:
		var context := caster as MobaCastContext
		resolved_actor = context.caster

	# If no Actor could be resolved, return failure
	if resolved_actor == null:
		return ActionResult.new(false, MobaAbilityAction.FAILURE_INVALID_CONTEXT)

	# Construct the action and route through ActionRunner
	var action := MobaCastCancelAction.new(resolved_actor)
	return ActionRunner.run(action)
