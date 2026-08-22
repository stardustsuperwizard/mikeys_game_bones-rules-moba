## State machine for character actions and interrupts.
##
## Loads the state transition table from state_transitions.json on ready
## and answers all action-legality and movement-policy questions by lookup.
## Manages current state, time tracking, and duration-based state expiration.
class_name MobaStateMachine
extends Node

signal state_changed(from: int, to: int)

var current_state: int = MobaState.IDLE
var time_in_state: float = 0.0
var remaining: float = 0.0

var _airborne_cause: int = MobaState.AirborneCause.JUMP
var _state_table: Dictionary = {}


func _ready() -> void:
	_load_state_table()


func _load_state_table() -> void:
	var json_path = "res://rules/data/state_transitions.json"
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("Failed to load state_transitions.json at %s" % json_path)
		return
	
	var content = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		push_error("Failed to parse state_transitions.json: %s" % json.get_error_message())
		return
	
	var data = json.data
	if data is not Dictionary:
		push_error("state_transitions.json root must be a dictionary")
		return
	
	# Validate and process the state table
	for state_name_str: String in data.keys():
		var state_idx = MobaState.string_to_state(state_name_str)
		if state_idx == -1:
			push_error("Unknown state name in state_transitions.json: %s" % state_name_str)
			return
		
		var state_data = data[state_name_str]
		if state_data is not Dictionary:
			push_error("State entry for %s must be a dictionary" % state_name_str)
			return
		
		# Validate all required policy columns exist
		var required_columns = ["move", "basic_attack", "ability", "jump", "interruptible_by_hard_cc"]
		for column_name in required_columns:
			if column_name not in state_data:
				push_error("State %s missing column '%s'" % [state_name_str, column_name])
				return
			
			var value = state_data[column_name]
			if value is not String:
				push_error("State %s column %s value must be string, got %s" % [state_name_str, column_name, typeof(value)])
				return
		
		_state_table[state_idx] = state_data
	
	# Verify all 10 states are present
	if _state_table.size() != 10:
		push_error("State table incomplete: expected 10 states, found %d" % _state_table.size())
		return


## Check if an action is legal in the current state.
## Returns false if the action is not legal, or if called from DEAD.
func can(action: StringName) -> bool:
	if current_state == MobaState.DEAD:
		return false
	
	if current_state not in _state_table:
		push_error("Current state %d not in state table" % current_state)
		return false
	
	var state_data = _state_table[current_state]
	var action_lower = action.to_lower()
	
	# Map action names to policy columns
	var policy_key: String
	match action_lower:
		&"move": policy_key = "move"
		&"basic_attack": policy_key = "basic_attack"
		&"ability": policy_key = "ability"
		&"jump": policy_key = "jump"
		_:
			push_error("Unknown action: %s" % action)
			return false
	
	var policy_value = state_data.get(policy_key, "")
	
	# Interpret policy values: only certain values make the action legal
	match policy_value:
		"yes", "cancels", "locked", "air_control":
			return true
		"no", "per_cc", "flagged", "breaks_channel", "displacement_only":
			return false
		_:
			push_error("Unknown policy value in state %d column %s: %s" % [current_state, policy_key, policy_value])
			return false


## Get the movement policy for the current state.
## Returns one of: "yes", "no", "cancels", "locked", "air_control", "per_cc".
func movement_policy() -> StringName:
	if current_state not in _state_table:
		push_error("Current state %d not in state table" % current_state)
		return &"no"
	
	var state_data = _state_table[current_state]
	var move_value = state_data.get("move", "no")
	
	# Validate that it's a recognized movement policy
	var valid_policies = ["yes", "no", "cancels", "locked", "air_control", "per_cc"]
	if move_value not in valid_policies:
		push_error("Unknown movement policy in state %d: %s" % [current_state, move_value])
		return &"no"
	
	return StringName(move_value)


## Attempt to enter a new state.
##
## A zero-or-negative duration state is never entered and returns false.
## Re-entering the same state returns true but does not emit state_changed.
## DEAD is terminal: returns false for any target state except revive().
## AIRBORNE states store the cause flag for later querying.
func try_enter(state: int, duration: float = 0.0, cause: int = MobaState.AirborneCause.JUMP) -> bool:
	# Validate state value
	if state < MobaState.IDLE or state > MobaState.DEAD:
		push_error("Invalid state value: %d" % state)
		return false
	
	# Zero-or-negative duration states are never entered
	if duration <= 0.0:
		return false
	
	# DEAD is terminal
	if current_state == MobaState.DEAD:
		return false
	
	# Re-entering the same state succeeds without emitting signal
	if state == current_state:
		return true
	
	# Perform the transition
	var from_state = current_state
	current_state = state
	time_in_state = 0.0
	remaining = duration
	
	if state == MobaState.AIRBORNE:
		_airborne_cause = cause
	
	state_changed.emit(from_state, state)
	return true


## Advance time in the current state.
## Decrements remaining if the state has a duration.
## Emits state_changed(current, IDLE) when duration expires.
func tick(delta: float) -> void:
	time_in_state += delta
	
	# Only decrement remaining if it was set (duration > 0)
	if remaining > 0.0:
		remaining -= delta
		
		# Check if duration expired
		if remaining <= 0.0:
			# Return to IDLE
			var from_state = current_state
			current_state = MobaState.IDLE
			time_in_state = 0.0
			remaining = 0.0
			state_changed.emit(from_state, MobaState.IDLE)


## Exit the DEAD state and return to IDLE.
## Only call succeeds if current state is DEAD.
func revive() -> bool:
	if current_state != MobaState.DEAD:
		return false
	
	var from_state = current_state
	current_state = MobaState.IDLE
	time_in_state = 0.0
	remaining = 0.0
	state_changed.emit(from_state, MobaState.IDLE)
	return true


## Get the airborne cause flag if currently AIRBORNE.
## Returns the cause (JUMP or KNOCK_UP) or -1 if not airborne.
func get_airborne_cause() -> int:
	if current_state != MobaState.AIRBORNE:
		return -1
	return _airborne_cause


## For testing only: expose the loaded state table.
## Tests may mutate this dictionary to verify data-driven behavior.
func get_state_table_for_testing() -> Dictionary:
	return _state_table
