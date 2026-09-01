class_name Actor
extends Node

@export var character_sheet: CharacterSheet
@export var color: Color = Color.WHITE

# Whether player input may target this actor for attack. Defaults to true so
# existing hostile content (the Goblin) needs no data change; a friendly
# NPC sets this false. Deliberately just a flag, not a faction/relationship
# system -- nothing today needs more than "attackable or not."
@export var hostile: bool = true

# 0 means unowned/AI-controlled; a connected LAN client's peer id otherwise.
# Checked by Authority.can_perform() before an Action is honored.
var owner_id: int = 0

# Bridges whichever presentation body this Actor has (see
# scripts/actor_body_3d.gd) into a single presentation-neutral position, so
# Controller/PlayerController/SimpleAIController never need to know or care
# whether they're driving a 3D or a 2D actor.
# 2D's XY plane maps onto 3D's XZ ground plane (Y stays up).
#
# Deliberately not cached via @onready: Godot readies children before their
# parent, and SimpleAIController._ready() (a child of this Actor) reads
# global_position to set its home position -- that would run before this
# Actor's own @onready vars were assigned.
var global_position: Vector3:
	get:
		var body := get_node_or_null("Body")
		if body is CharacterBody3D:
			return (body as CharacterBody3D).global_position
		if body is CharacterBody2D:
			var position_2d := (body as CharacterBody2D).global_position
			return Vector3(position_2d.x, 0, position_2d.y)
		return Vector3.ZERO

@onready var controller: Controller = get_node_or_null("Controller")


func _ready() -> void:
	character_sheet = character_sheet.duplicate()
	character_sheet.current_hp = character_sheet.max_hp


# --- Server-authoritative command routing (#320) ---
#
# Ability activation and basic attack both follow the try_/request_/_resolve_
# trio recorded in docs/request_resolve_pattern.md:
#
#   try_*()      runs on whichever peer wants the action, and decides whether
#                to resolve it here or ask the server for it;
#   request_*()  is the server's @rpc inbox, which reads the sender's real peer
#                id once and passes it onward as a plain parameter;
#   _resolve_*() is the single path both cases funnel through, and the only
#                place ActionRunner.run() is reached for these two commands.
#
# The `"authority"` mode is a permission, not a destination: it means the RPC is
# accepted only from the node's multiplayer authority, which world_manager.gd
# sets to the actor's owning peer. What makes request_*() server-only is that
# its sole caller sends it to peer 1.
#
# Neither _resolve_*() re-implements legality. Cooldowns, resource cost, range,
# target validity and the Authority gate all stay where they already live --
# MobaAbilityCaster, the Action, and Authority.can_perform(). These methods only
# decide which peer's call arrives there, and under whose identity.


## Route an ability slot activation, resolving locally or asking the server.
##
## Returns the ActionResult when this peer resolved the activation itself, or
## null when the ask was forwarded to the server -- a client cannot know the
## outcome synchronously, and learns it only through the replicated combat
## state (CombatStateSynchronizer), never through a return value here.
func try_activate_slot(slot_index: int, context: MobaCastContext) -> ActionResult:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		var target_path := NodePath()
		if context.explicit_target != null and context.explicit_target.is_inside_tree():
			target_path = context.explicit_target.get_path()
		request_activate_slot.rpc_id(
			1,
			slot_index,
			target_path,
			context.aim_direction,
			context.ground_point,
			Time.get_ticks_msec()
		)
		return null

	return _resolve_activate_slot(slot_index, context, multiplayer.get_unique_id())


## The server's inbox for a client's ability activation request.
##
## Only serialisable data crosses the wire: the target arrives as a NodePath and
## is re-resolved against the server's own scene tree, never as an object
## reference the client could have chosen freely.
##
## _client_ticks_msec is the requesting client's Time.get_ticks_msec() at send.
## It is carried because the recorded request payload includes a timestamp, and
## it is deliberately not used to resolve anything: the rewind window that would
## consume it is #48, and until that exists the server dates every request by
## its own arrival. Nothing here trusts the client's clock.
@rpc("authority", "call_remote", "reliable")
func request_activate_slot(
	slot_index: int,
	target_path: NodePath,
	aim_direction: Vector3,
	ground_point: Vector3,
	_client_ticks_msec: int
) -> void:
	var requester_id := multiplayer.get_remote_sender_id()

	var explicit_target: Node = null
	if not target_path.is_empty():
		explicit_target = get_node_or_null(target_path)

	var context := MobaCastContext.new(self, explicit_target, aim_direction, ground_point)
	_resolve_activate_slot(slot_index, context, requester_id)


## The one path an ability slot activation is ever actually resolved through.
##
## Delegates to the actor's own MobaAbilityCaster rather than re-deriving the
## slot lookup or the action construction: the caster is the shared type that
## owns that logic, and a second copy here would be free to drift from it. It is
## also what keeps this file clear of the direct MobaCombatant mutator calls the
## command-gate contract test forbids in scripts/.
func _resolve_activate_slot(
	slot_index: int, context: MobaCastContext, requester_id: int
) -> ActionResult:
	var caster := get_node_or_null("MobaAbilityCaster") as MobaAbilityCaster
	if caster == null:
		return ActionResult.new(false, MobaAbilityAction.FAILURE_INVALID_CONTEXT)

	return caster.activate_slot(slot_index, context, requester_id)


## Route a basic attack, resolving locally or asking the server.
##
## Returns the ActionResult when resolved locally, or null when forwarded to the
## server -- same contract as try_activate_slot().
func try_basic_attack(target: Actor) -> ActionResult:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		if target == null or not target.is_inside_tree():
			return null
		request_basic_attack.rpc_id(1, target.get_path(), Time.get_ticks_msec())
		return null

	return _resolve_basic_attack(target, multiplayer.get_unique_id())


## The server's inbox for a client's basic attack request.
##
## _client_ticks_msec is carried and unused for the same reason as in
## request_activate_slot().
@rpc("authority", "call_remote", "reliable")
func request_basic_attack(target_path: NodePath, _client_ticks_msec: int) -> void:
	var requester_id := multiplayer.get_remote_sender_id()

	var target := get_node_or_null(target_path) as Actor
	if target == null:
		return

	_resolve_basic_attack(target, requester_id)


## The one path a basic attack is ever actually resolved through.
##
## The swing's own preconditions -- the attack cycle's wind-up and recovery, the
## target having a MobaCombatant at all -- stay inside MobaBasicAttackAction.
func _resolve_basic_attack(target: Actor, requester_id: int) -> ActionResult:
	if target == null:
		return ActionResult.new(false, MobaBasicAttackAction.FAILURE_NO_TARGET_COMBATANT)

	return ActionRunner.run(MobaBasicAttackAction.new(self, target), requester_id)
