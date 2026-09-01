## Action that fires a basic attack from one actor against another.
##
## MobaBasicAttackAction wraps MobaCombatant.basic_attack() in an Action so it can
## pass through Authority.can_perform() like ability activation does, replacing the
## two direct basic_attack() calls in PlayerController3D and EnemyAIController3D.
##
## The action resolves the attacker's and target's MobaCombatant child nodes and
## calls basic_attack() on the attacker. If the combatant rejects the call
## (no weapon, dead target, out of range, or cycle not ready) the action returns
## a failure. Unlike MobaAbilityAction, this does not attempt to disambiguate which
## condition caused the rejection -- MobaCombatant.basic_attack() is a bool that
## provides only success/failure, not granular reasons.
##
## Failure reasons returned as StringName:
## - no_combatant: actor has no MobaCombatant child
## - no_target_combatant: target has no MobaCombatant child
## - attack_not_started: MobaCombatant.basic_attack() returned false (weapon,
##   range, cycle readiness, or target state caused rejection)
class_name MobaBasicAttackAction
extends Action

const FAILURE_NO_COMBATANT = &"no_combatant"
const FAILURE_NO_TARGET_COMBATANT = &"no_target_combatant"
const FAILURE_ATTACK_NOT_STARTED = &"attack_not_started"

var target: Actor


func _init(p_actor: Actor, p_target: Actor) -> void:
	super(p_actor)
	target = p_target


func execute() -> ActionResult:
	# Resolve the attacker's MobaCombatant
	var attacker_combatant := _get_combatant(actor)
	if attacker_combatant == null:
		return ActionResult.new(false, FAILURE_NO_COMBATANT)

	# Resolve the target's MobaCombatant
	var target_combatant := _get_combatant(target)
	if target_combatant == null:
		return ActionResult.new(false, FAILURE_NO_TARGET_COMBATANT)

	# Call basic_attack and return success/failure based on its return value
	if attacker_combatant.basic_attack(target_combatant):
		return ActionResult.new(true)
	return ActionResult.new(false, FAILURE_ATTACK_NOT_STARTED)


## Find a node's MobaCombatant child node.
static func _get_combatant(node: Node) -> MobaCombatant:
	if node == null:
		return null
	return node.get_node_or_null("MobaCombatant") as MobaCombatant
