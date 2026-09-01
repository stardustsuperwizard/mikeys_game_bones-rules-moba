# Game-specific player controller for Sword and Planet.
#
# Keyboard: W=forward, S=back, Q=strafe left, E=strafe right,
#           A=turn left, D=turn right, Space=jump.
#
# Mouse: left click is the contextual action button. What it does depends on
# what was clicked -- ground walks there, a wall walks up to it and stops, a
# hostile actor closes to melee range and attacks, an interactable closes and
# uses it. Each click issues a single order that the controller then carries
# out over the following frames; a new click, or any keyboard movement,
# replaces or cancels it.
#
# Extends Bones' Controller contract so the existing ActorBody3D/Actor
# pipeline drives movement and combat unchanged -- the mouse only decides
# *what* to ask for, never how it resolves.
class_name PlayerController3D
extends Controller

# A surface at least this upright counts as ground the player can stand on;
# anything steeper is a wall, which is walked up to rather than onto.
const WALKABLE_NORMAL_Y := 0.7

# How head-on a wall contact must be to count as "blocked" rather than
# "brushing past": the dot of the wall normal with the direction of travel,
# so this is roughly 60 degrees either side of straight into the surface.
# A glancing contact keeps walking and slides along instead, which is what
# lets a click far along a wall you are already leaning on still get there.
const WALL_BLOCK_DOT := -0.5

## How close the player must get to a clicked ground point to have arrived.
@export var arrival_distance: float = 0.4

## How close the player must get to a clicked actor before attacking it.
@export var attack_range: float = 2.0

## How close the player must get to a clicked interactable before using it.
@export var interact_range: float = 2.0

## Yaw error, in degrees, at which the auto-turn toward an order runs at full
## turn speed. Smaller errors turn proportionally slower so the facing eases
## in instead of oscillating around the target heading.
@export var turn_ease_degrees: float = 15.0

## How far the click raycast reaches into the world, in meters.
@export var max_click_distance: float = 100.0

## Physics layers the click raycast can select.
@export_flags_3d_physics var click_collision_mask: int = 1

## How long the player may fail to close on an order before it is abandoned.
## There is no pathfinding yet, so an order behind an obstacle would
## otherwise leave the player shoving into it forever.
@export var stall_timeout: float = 0.75

## Distance, in meters, that counts as real progress toward an order.
@export var stall_progress: float = 0.05

var _jump_requested := false

# Whether a basic-attack cycle is pending toward the current attack target.
# Set to true when the click-order system has delivered the player into range;
# cleared when the basic attack action succeeds, the target leaves range or
# is freed, or the target carries no MobaCombatant to attack.
var _basic_attack_pending := false

# The target of the pending basic attack. get_attack_target() cancels the
# movement order (which clears _attack_target) so the player stops walking,
# so this keeps a separate reference alive across frames for the attack cycle
# to actually run against.
var _pending_attack_target: Actor = null

# The current click order -- at most one of these three is ever live.
var _destination := Vector3.ZERO
var _has_destination := false
var _destination_is_wall := false
var _attack_target: Actor = null
var _interact_target: Node = null

# Stall bookkeeping for the live order.
var _closest_distance := INF
var _stall_timer := 0.0

# The active input scheme, exposed for future consumers like prompt glyph swapping.
var _input_scheme: MobaInputScheme


func _ready() -> void:
	actor.add_to_group("players")

	# Wire the input intent layer for abilities and jump.
	var input_router := actor.get_node_or_null("MobaInputRouter") as MobaInputRouter
	if input_router:
		input_router.intent_emitted.connect(_on_intent_emitted)

	_input_scheme = actor.get_node_or_null("MobaInputScheme") as MobaInputScheme


# Ticks the MOBA combatant once per physics frame.  MobaCombatant.tick() drives
# cooldowns, resource regeneration, and the internal state machine via
# _tick_state_machine_and_basic_attack(), so no separate MobaStateMachine.tick()
# call is needed here -- the combatant owns that responsibility.
#
# Also fires the ruleset basic attack when the click-order system has delivered
# the player into melee range of an attack target.  Doing it here (on approach)
# rather than on button press means a single left click issues an order and the
# attack fires automatically once the player closes the distance, instead of
# one press both ordering and immediately attacking.
#
# Input and the basic-attack order only run for the actor this controller has
# multiplayer authority over. A missing Body fails that gate closed, matching
# every other _body() caller here: an authority gate that falls through when it
# cannot identify the owner is not a gate.
#
# MobaCombatant.tick() sits deliberately outside that gate, on the server. Since
# #320 the server is the sole executor of a client's activation and the sole
# holder of the cooldown/resource ledger it is refused against -- and a ledger
# that never advances is not enforcement, it is a permanent denial. Gated on
# body authority alone, the server would never tick a connected client's actor
# at all: that client's cooldowns, resource regeneration, cast and channel
# timers and respawn countdown would all freeze at the first cast, and every
# later request would be refused forever.
#
# So the server (and an offline session, which is the server) ticks every actor
# it holds, exactly as docs/request_resolve_pattern.md describes for the
# _attack_timer it recorded: "the server needs its copy of a peer-owned actor's
# cooldown to keep decaying, since the server is what actually enforces it, even
# though it never simulates that actor's movement." A client still ticks only
# its own actor, which is the same local copy it ticked before #320 -- unchanged
# here, and corrected by replication either way.
func _physics_process(delta: float) -> void:
	var body := _body()
	var has_body_authority := body != null and body.is_multiplayer_authority()
	var is_server := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

	var combatant := _combatant()
	if combatant and (is_server or has_body_authority):
		combatant.tick(delta)

	if not has_body_authority:
		return

	if combatant:
		# Fire the basic attack as soon as the player reaches the order target.
		# _basic_attack_pending is set by get_attack_target() when the player
		# enters range; _pending_attack_target survives the cancel_order() call
		# that clears _attack_target, so the attack cycle has something to run
		# against. Cleared here after the action succeeds.
		#
		# The swing now goes through Actor.try_basic_attack(), which resolves it
		# here on the offline/server path and forwards it to the server otherwise.
		# A null result means it was forwarded: a client cannot see the outcome,
		# so the pending target is dropped rather than re-sent every frame, and
		# the swing's real effect arrives through replication. On the local path
		# the ActionResult is still in hand and the latch behaves exactly as it
		# did before #320.
		if _basic_attack_pending and is_instance_valid(_pending_attack_target):
			var result := actor.try_basic_attack(_pending_attack_target)
			# FAILURE_NO_TARGET_COMBATANT is not a swing that might land next frame:
			# the target has no MobaCombatant at all, so clear pending rather than
			# leaving it set indefinitely. Every other failure (authority denial, the
			# cycle still winding up) holds the target across frames as before.
			if (
				result == null
				or result.success
				or result.reason == MobaBasicAttackAction.FAILURE_NO_TARGET_COMBATANT
			):
				_basic_attack_pending = false
				_pending_attack_target = null
		elif _basic_attack_pending:
			_basic_attack_pending = false
			_pending_attack_target = null


# Click-to-order is read only by the peer that owns this actor; see
# _physics_process above for why a missing Body fails closed.
func _unhandled_input(event: InputEvent) -> void:
	var body := _body()
	if body == null or not body.is_multiplayer_authority():
		return

	if event.is_action_pressed("action_primary"):
		# The camera captures the mouse while right-drag look is active, which
		# parks the cursor at screen center -- a click then would pick whatever
		# happens to be under the crosshair rather than what the player aimed at.
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_issue_order_from_click(get_viewport().get_mouse_position())
		else:
			print("Left click ignored: mouse is captured by camera look")
	# NOTE: basic_attack is also bound to left mouse button (same as
	# action_primary in project.godot).  It is intentionally NOT consumed
	# here: reading it from _unhandled_input would cause a single left click
	# to both issue a click-to-order (via action_primary) and fire an extra
	# basic attack.  Instead, the basic attack fires automatically in
	# _physics_process once the click-order brings the player into range.
	# Gamepad RT (axis 5) shares the binding; Batch 3 will add a device-
	# agnostic intent layer (§1.6) that unifies RT vs keyboard routing.


# Returns world-space movement direction. Keyboard input is relative to the
# player's current facing so forward/back/strafe respect which way the body
# is pointing, and takes precedence over -- and cancels -- any click order.
#
# Crowd control is gated here, at the one place this controller decides where it
# wants to go, in strict precedence: displacement replaces the player's intent
# outright; else a movement-blocking effect (STUN/ROOT) zeroes it whatever is
# held; else fear redirects it away from its source; else the normal logic
# below runs unchanged.
func get_move_direction() -> Vector3:
	var combatant := _combatant()

	# Gate 1: displacement (KNOCKBACK/PULL/KNOCK_UP) overrides everything, a
	# blocking effect included -- being knocked back while stunned is the entire
	# point of a knockback, and #221 publishes it pre-scaled.
	if combatant:
		var displacement := combatant.get_forced_move_direction()
		if displacement != Vector3.ZERO:
			return displacement

	# Gate 2: movement not currently permitted -- stand still regardless of
	# what is being pressed or where the player last clicked.
	# Ahead of fear deliberately: crowd-control entries are tracked per type, so
	# FEAR and STUN are routinely co-active (a fear, then a Shield Bash), and a
	# feared *and* stunned actor is stunned -- it does not flee at full speed.
	if combatant and not combatant.can_perform_action(&"move"):
		return Vector3.ZERO

	# Gate 3: fear redirects intent rather than blocking it -- it carries an
	# all-false row in the crowd-control table -- so it resolves here, after
	# every effect that can forbid movement outright has had its say.
	if combatant:
		var fleeing := _fear_move_direction(combatant)
		if fleeing != Vector3.ZERO:
			return fleeing

	# Gate 4: fall through to normal input/order logic
	var body := _body()
	if not body:
		return Vector3.ZERO

	var keyboard := _keyboard_move_direction(body)
	if keyboard != Vector3.ZERO:
		cancel_order()
		return keyboard

	return _order_move_direction(body)


# Signed turn input: negative = turn left, positive = turn right. Falls back
# to turning toward the current order when the player isn't steering.
func get_turn_direction() -> float:
	var turn := 0.0
	if Input.is_action_pressed("turn_left"):
		turn -= 1.0
	if Input.is_action_pressed("turn_right"):
		turn += 1.0
	if turn != 0.0:
		return turn
	return _order_turn_direction()


# Handles input intents from the MobaInputRouter: abilities and jump.
# The router emits these when the corresponding actions are pressed.
func _on_intent_emitted(intent: RefCounted) -> void:
	if intent is MobaIntent.JumpIntent:
		_jump_requested = true
	elif intent is MobaIntent.AbilityIntent:
		var ability_intent := intent as MobaIntent.AbilityIntent
		if ability_intent.phase == MobaIntent.AbilityIntent.Phase.PRESS:
			_activate_slot(ability_intent.slot)


# Consumes and returns the buffered jump request.
func consume_jump() -> bool:
	var requested := _jump_requested
	_jump_requested = false
	return requested


# Bones polls these once the body has moved for the frame, so an order that
# arrived this frame resolves on the same frame it arrived.
#
# Gated by TAUNT at this same seam: while taunted the taunt source replaces the
# player's click order as the attack target. Out of range it stays the target
# and simply is not reachable -- falling through there would let a taunted
# player keep swinging at their own pick, which is the whole thing Taunt takes
# away. Chasing it is AI behavior (Batch 5), not intent, so nothing here moves.
func get_attack_target() -> Actor:
	var combatant := _combatant()

	var taunt_source_actor := _taunt_target(combatant)
	if taunt_source_actor:
		if not _in_range_of(taunt_source_actor, attack_range):
			_basic_attack_pending = false
			_pending_attack_target = null
			return null
		# Re-point rather than gate on the flag alone: a taunt landing mid-cycle
		# must steal a cycle already pending against the player's own target.
		if _pending_attack_target != taunt_source_actor:
			cancel_order()
			_pending_attack_target = taunt_source_actor
			_basic_attack_pending = true
		return null

	if _attack_target == null or not _in_range_of(_attack_target, attack_range):
		return null
	# When this actor has a MobaCombatant the ruleset basic-attack path
	# (MobaCombatant.basic_attack) handles combat resolution, driven in
	# _physics_process once the player closes range.  Cancel the movement
	# order so the player stops walking, schedule the attack cycle, but
	# return null so Actor._resolve_attack() does NOT additionally fire for
	# the same input (architecture constraint: ruleset path wins).
	# Gate the order-cancel + flag-set on the flag not already being live so
	# that standing still in range does not repeatedly call cancel_order().
	if combatant != null:
		if not _basic_attack_pending:
			var pending_target := _attack_target
			cancel_order()
			_pending_attack_target = pending_target
			_basic_attack_pending = true
		return null
	var target := _attack_target
	cancel_order()
	return target


func get_interact_target() -> Node:
	if _interact_target == null or not _in_range_of(_interact_target, interact_range):
		return null
	var target := _interact_target
	cancel_order()
	return target


# Drops the live order, whatever kind it is, and resets its stall tracking.
# Also clears any pending basic attack: without this, disengaging (keyboard
# movement or a new click) while a basic_attack() call was still waiting on
# its cooldown would leave _basic_attack_pending latched forever, since
# get_attack_target() only arms it when it isn't already live -- silently
# blocking every future attack order for the rest of the session.
func cancel_order() -> void:
	_has_destination = false
	_destination_is_wall = false
	_attack_target = null
	_interact_target = null
	_closest_distance = INF
	_stall_timer = 0.0
	_basic_attack_pending = false
	_pending_attack_target = null


# Raycasts from the camera through the clicked pixel and turns whatever it
# hits into an order. A click that hits nothing at all just clears the
# current order.
func _issue_order_from_click(screen_position: Vector2) -> void:
	var body := _body()
	var camera := get_viewport().get_camera_3d()
	if not body or not camera:
		return

	var from := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + camera.project_ray_normal(screen_position) * max_click_distance
	)
	query.collision_mask = click_collision_mask
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)

	cancel_order()
	if hit.is_empty():
		print("Left click hit nothing (no order issued)")
		return

	var collider := hit["collider"] as Node
	var hit_actor := _actor_of(collider)
	if hit_actor and hit_actor != actor and hit_actor.hostile:
		_attack_target = hit_actor
	elif collider and collider.is_in_group("interactables"):
		_interact_target = collider
	else:
		# Walls included: the destination sits on the clicked surface itself,
		# and the body's own collision is what stops the walk flush against
		# it. Since the approach is measured on the ground plane, a click
		# high up a wall still walks to the wall's base.
		_destination = hit["position"]
		_destination_is_wall = (hit["normal"] as Vector3).y < WALKABLE_NORMAL_Y
		_has_destination = true


func _keyboard_move_direction(body: Node3D) -> Vector3:
	var forward := -body.global_basis.z
	var right := body.global_basis.x
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir += forward
	if Input.is_action_pressed("move_back"):
		dir -= forward
	if Input.is_action_pressed("strafe_left"):
		dir -= right
	if Input.is_action_pressed("strafe_right"):
		dir += right
	return dir.normalized()


# Walks toward the live order until inside the distance at which it resolves.
# Also where stall detection is metered, since Bones calls this exactly once
# per physics frame.
func _order_move_direction(body: CharacterBody3D) -> Vector3:
	if not _refresh_order():
		return Vector3.ZERO

	var to_goal := _order_goal() - body.global_position
	to_goal.y = 0.0
	var distance := to_goal.length()
	if distance <= _order_stop_distance():
		return Vector3.ZERO

	var direction := to_goal / distance

	# A wall destination is reached as soon as the body is up against
	# something blocking the way to it: the walk can never close the last
	# body-radius of distance, so waiting on arrival_distance would leave the
	# player grinding into the wall until the stall guard eventually fired.
	# Only walls the body is pushing *into* count, so brushing along one on
	# the way somewhere else doesn't read as arrival.
	if (
		_destination_is_wall
		and body.is_on_wall()
		and body.get_wall_normal().dot(direction) < WALL_BLOCK_DOT
	):
		cancel_order()
		return Vector3.ZERO

	if distance < _closest_distance - stall_progress:
		_closest_distance = distance
		_stall_timer = 0.0
	else:
		_stall_timer += actor.get_physics_process_delta_time()
		if _stall_timer >= stall_timeout:
			cancel_order()
			return Vector3.ZERO

	return direction


func _order_turn_direction() -> float:
	var body := _body()
	if not body or not _refresh_order():
		return 0.0

	var to_goal := _order_goal() - body.global_position
	to_goal.y = 0.0
	if to_goal.length() < arrival_distance:
		return 0.0

	# The body's forward is -Z, so this is the yaw that would point it at the
	# goal. PlayerBody3D rotates by -turn, so a left turn is a negative value.
	var desired_yaw := atan2(-to_goal.x, -to_goal.z)
	var error := wrapf(desired_yaw - body.global_rotation.y, -PI, PI)
	return -clampf(rad_to_deg(error) / turn_ease_degrees, -1.0, 1.0)


# True while an order is live. Drops orders whose target has been freed --
# a killed enemy, a despawned prop -- so the player stops walking at a ghost.
func _refresh_order() -> bool:
	if _attack_target and not is_instance_valid(_attack_target):
		cancel_order()
	if _interact_target and not is_instance_valid(_interact_target):
		cancel_order()
	return _has_destination or _attack_target != null or _interact_target != null


func _order_goal() -> Vector3:
	if _attack_target:
		return _attack_target.global_position
	if _interact_target:
		return (_interact_target as Node3D).global_position
	return _destination


func _order_stop_distance() -> float:
	if _attack_target:
		return attack_range
	if _interact_target:
		return interact_range
	return arrival_distance


# Range is measured on the ground plane, matching how the approach in
# _order_move_direction decides it has arrived. Measuring in 3D instead would
# deadlock on a target whose origin sits above the floor -- a door's does --
# by stopping the walk at a distance the range check still calls too far.
func _in_range_of(target: Node, range_limit: float) -> bool:
	if not is_instance_valid(target):
		return false
	var target_position := (
		(target as Actor).global_position if target is Actor else (target as Node3D).global_position
	)
	return _ground_distance(target_position - actor.global_position) <= range_limit


func _ground_distance(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()


func _actor_of(collider: Node) -> Actor:
	if collider == null:
		return null
	return collider.get_parent() as Actor


func _body() -> CharacterBody3D:
	return actor.get_node_or_null("Body") as CharacterBody3D


# Returns the MobaCombatant child of the actor, or null if there isn't one.
func _combatant() -> MobaCombatant:
	return actor.get_node_or_null("MobaCombatant") as MobaCombatant


# Activate ability slot `index` (1-4) through the actor's request/resolve routing.
#
# An empty slot stays silent -- pressing 3 with nothing bound to it is not an
# error worth printing every keypress. Every other failure is reported, because
# a targeted ability that silently declines to fire is indistinguishable in play
# from an input that never arrived.
#
# try_activate_slot() returns null when the ask went to the server instead of
# resolving here. There is no failure to report in that case -- the outcome is
# the server's to decide, and it reaches this peer as replicated state -- so the
# diagnostic below stays on the offline/server path where the result is real.
func _activate_slot(index: int) -> void:
	var context := MobaCastContext.new(actor, _ability_target())
	var result := actor.try_activate_slot(index, context)
	if result == null:
		return
	if result.success or result.reason == MobaAbilityAction.FAILURE_EMPTY_SLOT:
		return
	# ActionRunner returns an empty reason when Authority refuses the action
	# outright, which would otherwise print as a blank line.
	var reason: StringName = result.reason if result.reason != &"" else &"denied"
	print("Ability slot %d did not activate: %s" % [index, reason])


# The target a targeted ability resolves against.
#
# PLACEHOLDER, replaced by #39's lock-on. Reuses whichever actor the click-order
# system is already pointing at -- the live attack order, or the target of an
# attack cycle in flight -- because that is the only expressed target intent the
# player currently has. It is not acquisition: there is no candidate search, no
# cycling, and nothing on screen saying what is targeted. Without it a TARGETED
# ability has no target at all and fails with invalid_target on every press.
func _ability_target() -> Node:
	if _attack_target != null and is_instance_valid(_attack_target):
		return _attack_target
	if _pending_attack_target != null and is_instance_valid(_pending_attack_target):
		return _pending_attack_target
	return null


# Returns the MobaCombatant of the current attack target, or null if there is
# no valid target. This is a public accessor for the placeholder target concept
# that _ability_target() already computes. Used by the target frame binder to
# poll for target changes once per frame. Does not add targeting logic; #39's
# lock-on will replace the underlying target selection without changing this API.
func get_current_target_combatant() -> MobaCombatant:
	var target_actor := _ability_target() as Actor
	if not is_instance_valid(target_actor):
		return null
	return target_actor.get_node_or_null("MobaCombatant") as MobaCombatant


# Returns the active MobaInputScheme for this player, exposing the
# scheme_changed signal for future consumers like prompt glyph swapping.
# Returns null if the scheme was not successfully initialized.
func get_input_scheme() -> MobaInputScheme:
	return _input_scheme


# Unit vector pointing straight away from the recorded FEAR source, flattened to
# the ground plane, or Vector3.ZERO when not feared. Resolved here from the
# source #220 exposes for exactly this consumer, because #220 does not route
# FEAR through get_forced_move_direction() -- only displacement lands there.
# Left unscaled so ActorBody3D's existing velocity formula flees at the actor's
# normal speed; displacement is the case needing its own scaling, and #221
# already applies it before publishing.
func _fear_move_direction(combatant: MobaCombatant) -> Vector3:
	var fear_type := MobaCrowdControlSpec.CCType.FEAR
	if not combatant.has_crowd_control(fear_type):
		return Vector3.ZERO

	var fear_source := combatant.get_crowd_control_source(fear_type)
	if not is_instance_valid(fear_source):
		return Vector3.ZERO

	var fear_source_actor := fear_source.get_parent() as Actor
	if not is_instance_valid(fear_source_actor):
		return Vector3.ZERO

	var away := actor.global_position - fear_source_actor.global_position
	away.y = 0.0
	if away.length() < 0.001:
		# Source standing exactly on the actor: flee a fixed way rather than
		# stalling, and without reaching for a random number.
		return Vector3.FORWARD

	return away.normalized()


# The Actor a TAUNT is forcing this controller to attack, or null when not
# taunted. Per §19 the taunt source is itself the designated target.
func _taunt_target(combatant: MobaCombatant) -> Actor:
	if combatant == null:
		return null

	var taunt_type := MobaCrowdControlSpec.CCType.TAUNT
	if not combatant.has_crowd_control(taunt_type):
		return null

	var taunt_source := combatant.get_crowd_control_source(taunt_type)
	if not is_instance_valid(taunt_source):
		return null

	return taunt_source.get_parent() as Actor
