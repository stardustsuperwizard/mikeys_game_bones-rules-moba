## Action that cancels an in-progress cast or breaks an in-progress channel.
##
## MobaCastCancelAction wraps the cast/channel cancellation dispatch in an Action
## so it can pass through Authority.can_perform() like ability activation does,
## replacing the direct MobaCombatant mutation MobaAbilityCaster.cancel() used to
## perform.
##
## The action resolves the actor's MobaCombatant child and dispatches to
## break_channel() when a channel is in progress, or cancel_cast() otherwise.
## Both of the silent no-op paths -- an actor with no MobaCombatant, and a
## combatant with nothing in progress -- are existing documented behavior and
## remain observably unchanged, so execute() has no failure path of its own and
## always returns success. Authority is the only gate that can refuse a cancel.
##
## Failure reasons returned as StringName:
## - none. MobaAbilityAction.FAILURE_INVALID_CONTEXT is aliased below for the
##   caller-side resolution step -- MobaAbilityCaster.cancel() returns it when it
##   cannot resolve an Actor, before an Action is even constructed. The literal
##   stays defined once, in MobaAbilityAction's canonical failure-reason block;
##   this is an alias of that constant, not a second definition of it.
class_name MobaCastCancelAction
extends Action

const FAILURE_INVALID_CONTEXT = MobaAbilityAction.FAILURE_INVALID_CONTEXT


func _init(p_actor: Actor) -> void:
	super(p_actor)


func execute() -> ActionResult:
	# No combatant means there is nothing to cancel -- a harmless no-op, matching
	# the documented behavior of MobaAbilityCaster.cancel() before this change.
	var combatant := _get_combatant(actor)
	if combatant == null:
		return ActionResult.new(true)

	# Prioritize breaking a channel over cancelling a cast (though both should never
	# be in progress simultaneously). If a channel is active, break it; otherwise
	# cancel any in-progress cast. This dispatch is moved from
	# MobaAbilityCaster.cancel() unchanged.
	if combatant.is_channeling():
		combatant.break_channel()
	else:
		combatant.cancel_cast()

	return ActionResult.new(true)


## Find a combatant's MobaCombatant child node.
static func _get_combatant(node: Node) -> MobaCombatant:
	return node.get_node_or_null("MobaCombatant") as MobaCombatant
