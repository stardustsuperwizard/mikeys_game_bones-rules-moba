## Device-agnostic input intent vocabulary (ruleset §5.4).
##
## These types represent player input abstracted away from device: they carry
## only semantics, never device-specific details. MobaInputRouter translates
## InputMap actions into them one-for-one, so the combat rules never see a
## device.
##
## Intents are transient and per-frame: RefCounted, never Resource.
##
## Every type is an inner class of MobaIntent on purpose. Godot has no
## namespaces and class_name is one flat registry shared with every installed
## addon, so this module registers exactly one prefixed global (MobaIntent) and
## reaches the rest through it -- MobaIntent.MoveIntent, MobaIntent.AbilityIntent.
## Names as generic as MoveIntent or AimIntent would be collision bait as globals.
class_name MobaIntent
extends RefCounted


## Movement intent: translation or rotation, never both.
##
## The ruleset writes this as the terser MoveIntent(direction). Turning and
## translating are different mathematical objects in this codebase, so the type
## carries both and the router emits them separately: exactly one of direction
## or turn is non-zero per emission.
class MoveIntent:
	extends RefCounted
	## Translation, populated by move_forward/move_back/strafe_left/strafe_right.
	## Forward is -Z, right is +X.
	var direction: Vector3

	## Signed turn, populated by turn_left (negative) and turn_right (positive).
	var turn: float


## Aim intent carrying either a direction or a world point.
##
## Defined but never emitted by the router in this task: §5.4's mapping table
## has no action row producing it. Its real sources -- gamepad right stick and
## mouse ray -- arrive with camera and targeting work.
class AimIntent:
	extends RefCounted
	## Which field is authoritative for a given emission.
	enum Mode {
		DIRECTION,
		POINT,
	}

	## Aim direction, from a stick vector or mouse motion delta.
	var direction: Vector3

	## Aim point in world space, from a mouse ray.
	var point: Vector3

	## Selects which of direction or point this emission means.
	var mode: Mode = Mode.DIRECTION


## Jump intent. Traversal, not a combat ability (§5.5); carries no fields.
##
## The type itself is the payload: a consumer matches on it like any other
## intent. GDScript needs a statement to close an empty class body, and gdlint
## reads that necessary pass as a redundant one.
class JumpIntent:
	extends RefCounted
	# gdlint:ignore = unnecessary-pass
	pass


## Basic attack intent.
class BasicAttackIntent:
	extends RefCounted
	## True while the attack input is down, false on release, so hold-to-repeat
	## and press-to-fire weapons can both read the same intent.
	var held: bool


## Ability intent for one of the four action slots.
class AbilityIntent:
	extends RefCounted
	## Lifecycle of an ability gesture.
	##
	## AIM repeats every frame while the gesture is held. That is deliberate:
	## it is what drag-to-aim on touch and stick-aim on gamepad both need.
	## CANCEL is part of the vocabulary but has no producing action bound yet.
	enum Phase {
		PRESS,
		AIM,
		RELEASE,
		CANCEL,
	}

	## Action slot, 1-4, matching MobaLoadout's positional slots.
	var slot: int

	## Stage of the gesture.
	var phase: Phase = Phase.PRESS


## Lock-on intent.
class LockOnIntent:
	extends RefCounted
	## Lock-on gesture stage. CYCLE is reserved: the single bound lock_on action
	## has no cycling semantics defined yet, so the router never produces it.
	enum Phase {
		PRESS,
		RELEASE,
		CYCLE,
	}

	## Stage of the gesture.
	var phase: Phase = Phase.PRESS


## Utility intent for non-combat bound actions, identified semantically.
class UtilityIntent:
	extends RefCounted
	## Semantic action id, e.g. &"defend".
	var id: StringName
