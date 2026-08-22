## State definitions for the MOBA character state machine.
##
## Defines the ten character states from §56 of the ruleset, plus the AirborneCause
## flag that distinguishes player jumps from knock-ups.
class_name MobaState

enum {
	IDLE,
	MOVING,
	BASIC_ATTACK_WINDUP,
	BASIC_ATTACK_RECOVERY,
	ABILITY_CAST,
	ABILITY_CHANNEL,
	DASHING,
	AIRBORNE,
	CROWD_CONTROLLED,
	DEAD,
}

enum AirborneCause {
	JUMP,
	KNOCK_UP,
}


## Map state name strings to enum values.
## Returns the enum value if found, or -1 if not recognized.
static func string_to_state(state_name: String) -> int:
	match state_name:
		"IDLE":
			return IDLE
		"MOVING":
			return MOVING
		"BASIC_ATTACK_WINDUP":
			return BASIC_ATTACK_WINDUP
		"BASIC_ATTACK_RECOVERY":
			return BASIC_ATTACK_RECOVERY
		"ABILITY_CAST":
			return ABILITY_CAST
		"ABILITY_CHANNEL":
			return ABILITY_CHANNEL
		"DASHING":
			return DASHING
		"AIRBORNE":
			return AIRBORNE
		"CROWD_CONTROLLED":
			return CROWD_CONTROLLED
		"DEAD":
			return DEAD
		_:
			return -1


## Map enum values back to strings for error reporting.
static func state_to_string(state: int) -> String:
	match state:
		IDLE:
			return "IDLE"
		MOVING:
			return "MOVING"
		BASIC_ATTACK_WINDUP:
			return "BASIC_ATTACK_WINDUP"
		BASIC_ATTACK_RECOVERY:
			return "BASIC_ATTACK_RECOVERY"
		ABILITY_CAST:
			return "ABILITY_CAST"
		ABILITY_CHANNEL:
			return "ABILITY_CHANNEL"
		DASHING:
			return "DASHING"
		AIRBORNE:
			return "AIRBORNE"
		CROWD_CONTROLLED:
			return "CROWD_CONTROLLED"
		DEAD:
			return "DEAD"
		_:
			return "UNKNOWN"
