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
## The context parameter provides all input data:
## - caster: the Actor performing the ability
## - explicit_target: target for targeted abilities (or null for self)
## - aim_direction: direction for skillshot abilities (unused in Batch 1)
## - ground_point: position for ground abilities (unused in Batch 1)
func activate(ability_id: StringName, context: MobaCastContext) -> ActionResult:
	if context.caster == null:
		return ActionResult.new(false, &"invalid_context")

	var action := MobaAbilityAction.new(context.caster, ability_id, context)
	return ActionRunner.run(action)
