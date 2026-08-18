class_name Actor
extends Node

@export var character_sheet: CharacterSheet
@export var object_definition: ObjectDefinition
@export var color: Color = Color.WHITE
@export var attack_cooldown := 1.0

# Whether player input may target this actor for attack. Defaults to true so
# existing hostile content (the Goblin) needs no data change; a friendly
# NPC sets this false. Deliberately just a flag, not a faction/relationship
# system -- nothing today needs more than "attackable or not."
@export var hostile: bool = true

# 0 means unowned/AI-controlled; a connected LAN client's peer id otherwise.
# Checked by Authority.can_perform() before an Action is honored.
var owner_id: int = 0

# Traits/capabilities classification for this actor (see
# things/game_object.gd). Not yet consulted by ActionRunner -- see
# Action.required_capability().
var game_object: GameObject

@onready var controller: Controller = get_node_or_null("Controller")

var _attack_timer := 0.0

func _ready() -> void:
	character_sheet = character_sheet.duplicate()
	character_sheet.current_hp = character_sheet.max_hp
	game_object = GameObject.new(StringName(name), object_definition)

# Bridges whichever presentation body this Actor has (see
# actors/bodies/actor_body_3d.gd / actor_body_2d.gd) into a single
# presentation-neutral position, so Controller/PlayerController/SimpleAIController
# never need to know or care whether they're driving a 3D or a 2D actor.
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

func _physics_process(delta: float) -> void:
	# Ticks on every peer's own copy regardless of movement authority: the
	# server needs its copy of a peer-owned actor's cooldown to keep
	# decaying, since the server is what actually enforces it (see
	# _resolve_attack), even though it never simulates that actor's movement.
	if _attack_timer > 0.0:
		_attack_timer -= delta

# Only the actor's own controlling peer ever calls this (gated upstream by
# the body's authority check), so it's just "should I ask the server to
# attack" -- the server is the only one that ever actually resolves it.
func try_attack(target: Actor) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_attack.rpc_id(1, target.get_path())
		return

	_resolve_attack(target, multiplayer.get_unique_id())

@rpc("authority", "call_remote", "reliable")
func request_attack(target_path: NodePath) -> void:
	var target := get_node(target_path) as Actor
	if target:
		_resolve_attack(target, multiplayer.get_remote_sender_id())

# The only place an attack is ever actually resolved -- called directly for
# AI/single-player, or from request_attack() for a networked player. Its own
# _attack_timer check is the real cooldown enforcement; the server never
# trusts a client to have rate-limited itself.
func _resolve_attack(target: Actor, requester_id: int) -> void:
	if _attack_timer > 0.0:
		return

	_attack_timer = attack_cooldown
	ActionRunner.run(AttackAction.new(self, target), requester_id)

# Same request/resolve split as attack, minus the cooldown -- opening a door
# has no rate limit to enforce.
func try_interact(target: Node) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_interact.rpc_id(1, target.get_path())
		return

	_resolve_interact(target, multiplayer.get_unique_id())

@rpc("authority", "call_remote", "reliable")
func request_interact(target_path: NodePath) -> void:
	var target := get_node(target_path)
	if target:
		_resolve_interact(target, multiplayer.get_remote_sender_id())

# Interact currently only ever resolves to opening a door -- Controller
# returns a plain Node so future interactables (a chest, a lever) don't
# require a Controller-level API change, but OpenAction is the only
# interact Action implemented so far.
func _resolve_interact(target: Node, requester_id: int) -> void:
	var door := target as Door
	if door:
		ActionRunner.run(OpenAction.new(self, door), requester_id)

func take_damage(amount: int) -> void:
	var remaining := character_sheet.current_hp - amount
	print("%s takes %d damage (%d/%d HP)" % [character_sheet.character_name, amount, maxi(remaining, 0), character_sheet.max_hp])
	character_sheet.current_hp = remaining
	if character_sheet.current_hp <= 0:
		die()

func die() -> void:
	print("%s dies." % character_sheet.character_name)
	queue_free()
