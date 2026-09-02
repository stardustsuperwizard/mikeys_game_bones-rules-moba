## Test suite for MobaPositionHistory and its MobaCombatant wiring.
##
## Covers: has_samples() before and after the first record(), storage that stays
## at a fixed capacity across a multi-minute session, position_at() clamping to
## the oldest and newest retained samples, linear interpolation between
## bracketing samples, exact-timestamp hits, that a server-or-offline
## MobaCombatant.tick() records, and that a peer which is connected but not the
## server records nothing.
class_name PositionHistoryTest

const MobaPositionHistory = preload("res://rules/net/moba_position_history.gd")
const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## Port for the throwaway ENet client peer in the client-gating test. Nothing
## ever listens on it: the peer only has to exist and report a non-server id.
const _UNUSED_PORT := 47327


## Build an Actor with a MobaCombatant child, seeded the way the other headless
## rules suites seed theirs. Without a runtime stat block tick() reaches
## get_stat() on a null block and logs errors on its way through.
static func _make_combatant() -> MobaCombatant:
	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)
	return combatant


## Helper function to compare Vector3s with tolerance
static func _approx_equal_vec3(a: Vector3, b: Vector3, tolerance: float = 0.0001) -> bool:
	return a.distance_to(b) < tolerance


## Run the position history test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_has_samples_false_before_record())
	all_violations.append_array(_test_has_samples_true_after_record())
	all_violations.append_array(_test_capacity_is_fixed_at_construction())
	all_violations.append_array(_test_clamp_to_oldest_sample())
	all_violations.append_array(_test_clamp_to_newest_sample())
	all_violations.append_array(_test_linear_interpolation())
	all_violations.append_array(_test_exact_sample_match())
	all_violations.append_array(_test_long_session_fixed_memory())
	all_violations.append_array(_test_offline_tick_records())
	all_violations.append_array(_test_client_tick_records_nothing())

	if all_violations.is_empty():
		return true

	printerr("\n=== Position History Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


static func _test_has_samples_false_before_record() -> Array[String]:
	var violations: Array[String] = []
	var history := MobaPositionHistory.new()

	if history.has_samples():
		violations.append("has_samples() should be false before first record()")

	return violations


static func _test_has_samples_true_after_record() -> Array[String]:
	var violations: Array[String] = []
	var history := MobaPositionHistory.new()

	history.record(1000, Vector3.ONE)

	if not history.has_samples():
		violations.append("has_samples() should be true after record()")

	return violations


## Capacity is derived once from the window and the assumed sample interval, and
## the buffer is that size from construction -- before any record() call.
static func _test_capacity_is_fixed_at_construction() -> Array[String]:
	var violations: Array[String] = []
	var history := MobaPositionHistory.new()

	var expected_capacity := 16  # ceil(120 / 10) + 4
	if history.get_capacity() != expected_capacity:
		violations.append(
			(
				"capacity: a default history should allocate %d slots, got %d"
				% [expected_capacity, history.get_capacity()]
			)
		)

	if history.get_sample_count() != 0:
		violations.append(
			"capacity: a fresh history should hold 0 samples, got %d" % history.get_sample_count()
		)

	# Capacity must not move once records start landing.
	for i in range(expected_capacity * 3):
		history.record(1000 + i * 10, Vector3(float(i), 0, 0))

	if history.get_capacity() != expected_capacity:
		violations.append(
			(
				"capacity: capacity changed from %d to %d after recording"
				% [expected_capacity, history.get_capacity()]
			)
		)

	return violations


static func _test_clamp_to_oldest_sample() -> Array[String]:
	var violations: Array[String] = []
	var history := MobaPositionHistory.new()

	history.record(1000, Vector3(1, 0, 0))
	history.record(2000, Vector3(2, 0, 0))
	history.record(3000, Vector3(3, 0, 0))

	# A timestamp older than every retained sample clamps to the oldest.
	var position = history.position_at(500)

	if not _approx_equal_vec3(position, Vector3(1, 0, 0)):
		violations.append(
			"position_at(500) with oldest=1000 should clamp to (1,0,0), got %s" % position
		)

	return violations


static func _test_clamp_to_newest_sample() -> Array[String]:
	var violations: Array[String] = []
	var history := MobaPositionHistory.new()

	history.record(1000, Vector3(1, 0, 0))
	history.record(2000, Vector3(2, 0, 0))
	history.record(3000, Vector3(3, 0, 0))

	# A timestamp newer than every retained sample clamps to the newest.
	var position = history.position_at(5000)

	if not _approx_equal_vec3(position, Vector3(3, 0, 0)):
		violations.append(
			"position_at(5000) with newest=3000 should clamp to (3,0,0), got %s" % position
		)

	return violations


static func _test_linear_interpolation() -> Array[String]:
	var violations: Array[String] = []
	var history := MobaPositionHistory.new()

	history.record(1000, Vector3(0, 0, 0))
	history.record(3000, Vector3(10, 0, 0))

	# Midpoint in time is the midpoint in space.
	var position = history.position_at(2000)
	if not _approx_equal_vec3(position, Vector3(5, 0, 0)):
		violations.append("interpolation: t=2000 should be (5,0,0), got %s" % position)

	# A quarter of the way through the span is a quarter of the way along it.
	position = history.position_at(1500)
	if not _approx_equal_vec3(position, Vector3(2.5, 0, 0)):
		violations.append("interpolation: t=1500 should be (2.5,0,0), got %s" % position)

	return violations


static func _test_exact_sample_match() -> Array[String]:
	var violations: Array[String] = []
	var history := MobaPositionHistory.new()

	history.record(1000, Vector3(1, 2, 3))
	history.record(2000, Vector3(4, 5, 6))
	history.record(3000, Vector3(7, 8, 9))

	var position = history.position_at(2000)
	if not _approx_equal_vec3(position, Vector3(4, 5, 6)):
		violations.append(
			"position_at(2000) with exact sample should return (4,5,6), got %s" % position
		)

	position = history.position_at(1000)
	if not _approx_equal_vec3(position, Vector3(1, 2, 3)):
		violations.append(
			"position_at(1000) with exact sample should return (1,2,3), got %s" % position
		)

	return violations


## The bounded-storage guarantee: far more record() calls than capacity, spanning
## simulated minutes of 60 Hz ticks, and stored element count never exceeds the
## capacity fixed at construction.
static func _test_long_session_fixed_memory() -> Array[String]:
	var violations: Array[String] = []
	var history := MobaPositionHistory.new()

	var capacity := history.get_capacity()

	# 12000 ticks at 16 ms is ~3.2 simulated minutes, ~750x the buffer's capacity.
	var total_records := 12000
	var peak_sample_count := 0
	for i in range(total_records):
		history.record(1000 + i * 16, Vector3(float(i) * 0.1, float(i) * 0.2, float(i) * 0.3))

		peak_sample_count = maxi(peak_sample_count, history.get_sample_count())
		if history.get_sample_count() > capacity:
			violations.append(
				(
					"long session: stored element count reached %d after %d records, capacity is %d"
					% [history.get_sample_count(), i + 1, capacity]
				)
			)
			break

		if history.get_capacity() != capacity:
			violations.append(
				(
					"long session: capacity grew from %d to %d after %d records"
					% [capacity, history.get_capacity(), i + 1]
				)
			)
			break

	# The buffer should be saturated, not merely under the cap by never filling.
	if violations.is_empty() and peak_sample_count != capacity:
		violations.append(
			(
				"long session: expected the buffer to saturate at %d samples, peaked at %d"
				% [capacity, peak_sample_count]
			)
		)

	# The window it still answers over is the newest `capacity` samples, so the
	# newest query is exact and an ancient one clamps rather than faulting.
	var newest_timestamp := 1000 + (total_records - 1) * 16
	var expected_newest := Vector3(
		float(total_records - 1) * 0.1,
		float(total_records - 1) * 0.2,
		float(total_records - 1) * 0.3
	)
	if not _approx_equal_vec3(history.position_at(newest_timestamp), expected_newest):
		violations.append(
			(
				"long session: newest query should return %s, got %s"
				% [expected_newest, history.position_at(newest_timestamp)]
			)
		)

	var oldest_retained_index := total_records - capacity
	var expected_oldest := Vector3(
		float(oldest_retained_index) * 0.1,
		float(oldest_retained_index) * 0.2,
		float(oldest_retained_index) * 0.3
	)
	if not _approx_equal_vec3(history.position_at(0), expected_oldest):
		violations.append(
			(
				"long session: a query older than the retained window should clamp to %s, got %s"
				% [expected_oldest, history.position_at(0)]
			)
		)

	return violations


## A combatant with no multiplayer peer is offline, and offline is authoritative,
## so one tick() must leave a sample behind.
static func _test_offline_tick_records() -> Array[String]:
	var violations: Array[String] = []

	var actor := Actor.new()
	var combatant := _make_combatant()
	actor.add_child(combatant)

	var history = combatant.get_position_history()
	if history == null:
		violations.append("offline: get_position_history() returned null")
		actor.free()
		return violations

	if history.has_samples():
		violations.append("offline: history should be empty before the first tick()")

	combatant.tick(0.016)

	if not history.has_samples():
		violations.append("offline: one tick() on an offline combatant should record a sample")

	actor.free()
	return violations


## A peer that is connected but is not the server records nothing: its combatant
## is a predicted copy, and history it wrote would never be read.
static func _test_client_tick_records_nothing() -> Array[String]:
	var violations: Array[String] = []

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		violations.append("client gating: no SceneTree available")
		return violations

	# `multiplayer` resolves per subtree, so bind a client-side MultiplayerAPI to
	# a branch of its own and put the fixture under it -- the same set_multiplayer()
	# split tests/server_authority_activation_test.gd uses for two live peers.
	var branch := Node.new()
	branch.name = "PositionHistoryClientPeer"
	tree.root.add_child(branch)

	var client_api := MultiplayerAPI.create_default_interface()
	tree.set_multiplayer(client_api, ^"/root/PositionHistoryClientPeer")

	# No handshake is needed. The gate reads has_multiplayer_peer() and
	# is_server(); create_client() settles both the moment it returns, assigning
	# a unique id that is not 1 whether or not anything answers on the port.
	var client_peer := ENetMultiplayerPeer.new()
	if client_peer.create_client("127.0.0.1", _UNUSED_PORT) != OK:
		violations.append("client gating: could not create an ENet client peer")
		branch.free()
		return violations
	client_api.multiplayer_peer = client_peer

	var actor := Actor.new()
	actor.character_sheet = CharacterSheet.new()
	var combatant := _make_combatant()
	actor.add_child(combatant)
	branch.add_child(actor)

	if combatant.multiplayer == null or not combatant.multiplayer.has_multiplayer_peer():
		violations.append("client gating: fixture combatant should have a multiplayer peer")
	elif combatant.multiplayer.is_server():
		violations.append("client gating: fixture combatant should be a client, not the server")
	else:
		combatant.tick(0.016)
		if combatant.get_position_history().has_samples():
			violations.append(
				"client gating: a connected non-server peer must not record position history"
			)

	client_api.multiplayer_peer = null
	branch.free()
	return violations
