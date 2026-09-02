## Test suite for MobaRewindClock.
##
## Covers: the conservative window_ms answer for a peer with no samples, the
## minimum-offset estimate tightening toward the true one-way delay as jitter
## falls away (and refusing to relax when a later sample is more jittered),
## claimed-future timestamps clamping to 0, delays past the window clamping to
## exactly window_ms, in-window delays passing through unclamped, and per-peer
## state that counts distinct peer ids rather than samples.
class_name ClockSyncTest

const MobaRewindClock = preload("res://rules/net/moba_rewind_clock.gd")

## The epoch difference plus true minimum one-way delay that the synthetic
## samples below are generated from. No sample ever observes less than this;
## jitter is only ever added on top.
const _TRUE_OFFSET_MS := 50

## Rewind window used by every case here. Wide enough that the convergence
## probes land inside it, so they report the estimate instead of clamping.
const _WINDOW_MS := 200


## Run the clock sync test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_unproven_peer_returns_window_ms())
	all_violations.append_array(_test_convergence_with_jitter())
	all_violations.append_array(_test_future_timestamp_clamps_to_zero())
	all_violations.append_array(_test_delay_clamped_to_window_ms())
	all_violations.append_array(_test_normal_delay_in_range())
	all_violations.append_array(_test_bounded_storage_per_peer())

	if all_violations.is_empty():
		return true

	printerr("\n=== Clock Sync Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## A peer that has never been sampled has no basis for trust: it must get the
## maximum-rewind answer, exactly window_ms, and never 0.
static func _test_unproven_peer_returns_window_ms() -> Array[String]:
	var violations: Array[String] = []
	var clock := MobaRewindClock.new()

	if clock.has_offset_estimate(1):
		violations.append("unproven peer: reported an offset estimate before any sample")

	var delay := clock.get_rewind_delay_ms(1, 1000, 2000, _WINDOW_MS)
	if delay != _WINDOW_MS:
		violations.append("unproven peer: expected %d ms, got %d ms" % [_WINDOW_MS, delay])

	# The same must hold for a peer id that is unknown while other peers are
	# tracked -- the fallback is per peer, not "has this clock seen anything".
	clock.record_sample(1, 1000, 1000 + _TRUE_OFFSET_MS)
	var other := clock.get_rewind_delay_ms(2, 1000, 2000, _WINDOW_MS)
	if other != _WINDOW_MS:
		violations.append("untracked peer alongside a tracked one: got %d ms" % other)

	return violations


## Samples carrying a known constant offset plus falling jitter must tighten the
## estimate toward the true one-way delay, and a later, more jittered sample
## must not relax it back.
##
## The probe below is read as: a client tick count of `client_ticks` measured
## against a server clock at `server_now` is a delay of exactly
## `server_now - (client_ticks + estimate)`. Over-estimating the offset (which
## jitter does) under-reports the delay, so the reported delay climbs toward the
## true 100 ms as the estimate falls from 70 to 50.
static func _test_convergence_with_jitter() -> Array[String]:
	var violations: Array[String] = []
	var clock := MobaRewindClock.new()

	var peer_id := 2
	var client_ticks := 1000
	# Chosen so that with the true offset the delay is exactly 100 ms, well
	# inside _WINDOW_MS and therefore reported rather than clamped.
	var true_delay_ms := 100
	var server_now := client_ticks + _TRUE_OFFSET_MS + true_delay_ms

	# Jitter of 20 ms: the offset is over-estimated at 70, so the delay is
	# under-reported at 80.
	clock.record_sample(peer_id, 1000, 1000 + _TRUE_OFFSET_MS + 20)
	var after_jitter_20 := clock.get_rewind_delay_ms(peer_id, client_ticks, server_now, _WINDOW_MS)
	if after_jitter_20 != 80:
		violations.append("convergence: 20 ms jitter should report 80 ms, got %d" % after_jitter_20)

	# Jitter of 10 ms tightens the estimate to 60, so the delay climbs to 90.
	clock.record_sample(peer_id, 2000, 2000 + _TRUE_OFFSET_MS + 10)
	var after_jitter_10 := clock.get_rewind_delay_ms(peer_id, client_ticks, server_now, _WINDOW_MS)
	if after_jitter_10 != 90:
		violations.append("convergence: 10 ms jitter should report 90 ms, got %d" % after_jitter_10)

	if after_jitter_10 <= after_jitter_20:
		violations.append(
			(
				"convergence: a less jittered sample must tighten the answer, %d -> %d"
				% [after_jitter_20, after_jitter_10]
			)
		)

	# An unjittered sample reaches the true offset, and the delay reaches the
	# true 100 ms.
	clock.record_sample(peer_id, 3000, 3000 + _TRUE_OFFSET_MS)
	var converged := clock.get_rewind_delay_ms(peer_id, client_ticks, server_now, _WINDOW_MS)
	if converged != true_delay_ms:
		violations.append(
			(
				"convergence: unjittered sample should report %d ms, got %d"
				% [true_delay_ms, converged]
			)
		)

	# A later, more jittered sample carries strictly less information. The
	# minimum-offset estimate must discard it rather than regress.
	clock.record_sample(peer_id, 4000, 4000 + _TRUE_OFFSET_MS + 30)
	var after_regression := clock.get_rewind_delay_ms(peer_id, client_ticks, server_now, _WINDOW_MS)
	if after_regression != true_delay_ms:
		violations.append(
			(
				"convergence: a more jittered later sample must not relax the estimate, got %d"
				% after_regression
			)
		)

	return violations


## A client tick count that translates to after server_now -- a claimed-future
## timestamp -- clamps to 0 rather than rewinding into the future.
static func _test_future_timestamp_clamps_to_zero() -> Array[String]:
	var violations: Array[String] = []
	var clock := MobaRewindClock.new()

	var peer_id := 3
	var server_now := 5000
	clock.record_sample(peer_id, 1000, 1000 + _TRUE_OFFSET_MS)

	# Translates to server_now + 10, i.e. 10 ms into the server's future.
	var future_ticks := server_now + 10 - _TRUE_OFFSET_MS
	var delay := clock.get_rewind_delay_ms(peer_id, future_ticks, server_now, _WINDOW_MS)
	if delay != 0:
		violations.append("future timestamp: expected 0 ms, got %d ms" % delay)

	# Far into the future clamps the same way, not to some negative value.
	var far_future_ticks := server_now + 10_000 - _TRUE_OFFSET_MS
	var far_delay := clock.get_rewind_delay_ms(peer_id, far_future_ticks, server_now, _WINDOW_MS)
	if far_delay != 0:
		violations.append("far-future timestamp: expected 0 ms, got %d ms" % far_delay)

	return violations


## A translated delay larger than window_ms clamps to exactly window_ms.
static func _test_delay_clamped_to_window_ms() -> Array[String]:
	var violations: Array[String] = []
	var clock := MobaRewindClock.new()

	var peer_id := 4
	var server_now := 10_000
	clock.record_sample(peer_id, 1000, 1000 + _TRUE_OFFSET_MS)

	# One millisecond past the window is already clamped.
	var just_past_ticks := server_now - _WINDOW_MS - 1 - _TRUE_OFFSET_MS
	var just_past := clock.get_rewind_delay_ms(peer_id, just_past_ticks, server_now, _WINDOW_MS)
	if just_past != _WINDOW_MS:
		violations.append(
			"one ms past the window: expected %d ms, got %d ms" % [_WINDOW_MS, just_past]
		)

	# So is a timestamp from far outside it.
	var ancient := clock.get_rewind_delay_ms(peer_id, 0, server_now, _WINDOW_MS)
	if ancient != _WINDOW_MS:
		violations.append("ancient timestamp: expected %d ms, got %d ms" % [_WINDOW_MS, ancient])

	return violations


## A translated delay inside [0, window_ms] is returned unclamped, including at
## both boundaries.
static func _test_normal_delay_in_range() -> Array[String]:
	var violations: Array[String] = []
	var clock := MobaRewindClock.new()

	var peer_id := 5
	var server_now := 5000
	clock.record_sample(peer_id, 1000, 1000 + _TRUE_OFFSET_MS)

	for expected in [0, 1, _WINDOW_MS / 2, _WINDOW_MS - 1, _WINDOW_MS]:
		var ticks: int = server_now - expected - _TRUE_OFFSET_MS
		var delay := clock.get_rewind_delay_ms(peer_id, ticks, server_now, _WINDOW_MS)
		if delay != expected:
			violations.append("in-window delay: expected %d ms, got %d ms" % [expected, delay])

	return violations


## Per-peer state must count distinct peer ids, not samples. Feeding one peer
## thousands of samples, then two more peers one each, must leave exactly three
## tracked entries.
static func _test_bounded_storage_per_peer() -> Array[String]:
	var violations: Array[String] = []
	var clock := MobaRewindClock.new()

	var peer_id := 6
	var sample_count := 10_000

	for i in range(sample_count):
		var client_ticks := 1000 + i * 10
		# 50 ms offset plus [0, 4] ms of jitter, so the true offset is observed
		# on every fifth sample and the estimate is well determined.
		clock.record_sample(peer_id, client_ticks, client_ticks + _TRUE_OFFSET_MS + i % 5)

	if clock.get_tracked_peer_count() != 1:
		violations.append(
			(
				"bounded storage: %d samples for one peer left %d tracked entries, expected 1"
				% [sample_count, clock.get_tracked_peer_count()]
			)
		)

	# Two more peers, one sample each: the count follows distinct peer ids.
	clock.record_sample(7, 1000, 1000 + _TRUE_OFFSET_MS)
	clock.record_sample(8, 1000, 1000 + _TRUE_OFFSET_MS)

	if clock.get_tracked_peer_count() != 3:
		violations.append(
			(
				"bounded storage: 3 distinct peers left %d tracked entries, expected 3"
				% clock.get_tracked_peer_count()
			)
		)

	# More samples for peers already tracked add no entries at all.
	for i in range(sample_count):
		clock.record_sample(7, 1000 + i, 1000 + i + _TRUE_OFFSET_MS)

	if clock.get_tracked_peer_count() != 3:
		violations.append(
			(
				"bounded storage: resampling a tracked peer changed the count to %d, expected 3"
				% clock.get_tracked_peer_count()
			)
		)

	# Entry count alone would not catch a per-peer ring buffer, so check the
	# shape of the entry too: one plain integer, never a container that grows.
	for tracked_peer in [peer_id, 7, 8]:
		var entry: Variant = clock._peer_offsets[tracked_peer]
		if typeof(entry) != TYPE_INT:
			violations.append(
				(
					"bounded storage: peer %d holds a %s, expected a single int"
					% [tracked_peer, type_string(typeof(entry))]
				)
			)

	# The estimate itself survived the volume: peer 6 saw the true offset, so a
	# probe reports the true delay rather than a jittered one.
	var server_now := 20_000
	var probe_ticks := server_now - 100 - _TRUE_OFFSET_MS
	var delay := clock.get_rewind_delay_ms(peer_id, probe_ticks, server_now, _WINDOW_MS)
	if delay != 100:
		violations.append(
			"bounded storage: estimate after volume should report 100 ms, got %d" % delay
		)

	return violations
