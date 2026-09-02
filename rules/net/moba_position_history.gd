## Position history for one combatant, held in a fixed-capacity circular buffer.
##
## Answers "where was this combatant at time T" for the rewind window that
## lag-compensated skillshot resolution reads (#48). Plain and node-free: it
## takes ints and Vector3s in and returns Vector3s out, touching no node and no
## scene tree, the same shape MobaFormulas keeps.
##
## ## Bounded storage
##
## Capacity is computed once in _init() as
## `ceil(DEFAULT_REWIND_WINDOW_MS / _ASSUMED_MIN_SAMPLE_INTERVAL_MS) + _CAPACITY_MARGIN`
## -- with the defaults, `ceil(120 / 10) + 4 = 16` slots -- and the array is
## filled to that size up front. record() overwrites the oldest slot once the
## buffer is full, so stored element count is capped at capacity no matter how
## long a session runs. Nothing here is evicted by age: the fixed capacity is
## the only bound, and get_capacity() reports it.
##
## The 10 ms assumed minimum interval is deliberately shorter than the interval
## this actually sees. MobaCombatant.tick() runs once per physics frame, 60 Hz
## by default, so real samples land ~16.7 ms apart and 16 slots retain ~250 ms
## -- comfortably past the 120 ms window. Assuming a faster tick than the real
## one is the safe direction: it over-allocates rather than letting the buffer
## wrap before the window is covered.
##
## That headroom is bounded, though, and the bound is the margin rather than the
## assumed interval. Mind the fencepost: N slots span N-1 intervals, because the
## oldest retained sample sits at `newest - (N-1) * spacing`. So covering 120 ms
## with 16 slots needs `15 * spacing >= 120`, i.e. a spacing of at least 8 ms --
## a physics rate of at most 125 Hz, and at exactly 125 Hz the margin of 4 is
## fully spent. Past that the buffer wraps inside the rewind window and
## position_at() clamps where it should interpolate.
##
## A project that raises physics_ticks_per_second toward or beyond ~125 must
## lower _ASSUMED_MIN_SAMPLE_INTERVAL_MS to match; that genuinely raises
## capacity, since it is the divisor above. At 5 ms it yields 28 slots spanning
## 135 ms, which is ample at 200 Hz.
##
## ## Interpolation
##
## position_at() interpolates linearly between the two samples bracketing the
## queried timestamp, so a query between ticks does not snap to whichever
## sample happens to be nearer. At 16.7 ms spacing a combatant at a typical
## ~5 m/s move speed travels ~8 cm between samples, which is a large enough
## error against hitbox radii to be worth removing rather than tolerating.
class_name MobaPositionHistory
extends RefCounted

## Default rewind window in milliseconds -- the single source of truth for how
## far back this history is meant to answer queries. §64 specifies 100-150 ms;
## 120 is the chosen default. Sizes the buffer; it is not an eviction deadline.
const DEFAULT_REWIND_WINDOW_MS := 120

## Assumed minimum interval between record() calls, in milliseconds. Sizes the
## buffer only. See the class doc: the real interval is ~16.7 ms at the default
## 60 Hz physics rate, and assuming a shorter one over-allocates on purpose.
const _ASSUMED_MIN_SAMPLE_INTERVAL_MS := 10

## Slack added to the computed capacity so jitter in the tick interval cannot
## wrap the buffer before the rewind window is covered.
const _CAPACITY_MARGIN := 4

## The samples, as two parallel fixed-size packed arrays: slot i holds one
## {timestamp_ms, position} pair. Packed arrays rather than an array of sample
## objects because every combatant owns one of these for the whole match --
## per-sample objects would put capacity (16) extra entries in ObjectDB per
## combatant to store what is really just an int and a Vector3 each.
var _timestamps_ms := PackedInt64Array()
var _positions := PackedVector3Array()

## Next slot record() will write, wrapping at capacity.
var _write_index: int = 0

## Slots currently holding a recorded sample, from 0 up to capacity.
var _sample_count: int = 0

## Rewind window this instance was sized for, in milliseconds.
var _rewind_window_ms: int


func _init(rewind_window_ms: int = DEFAULT_REWIND_WINDOW_MS) -> void:
	_rewind_window_ms = rewind_window_ms

	# Fixed capacity: ceil(window / min_interval) + margin. Computed once, here.
	var capacity: int = (
		ceili(float(_rewind_window_ms) / float(_ASSUMED_MIN_SAMPLE_INTERVAL_MS)) + _CAPACITY_MARGIN
	)

	# Size both arrays up front so neither ever resizes after construction.
	_timestamps_ms.resize(capacity)
	_positions.resize(capacity)


## Record a position sample at the given timestamp. If the buffer is full,
## this overwrites the oldest sample (circular buffer behavior).
func record(timestamp_ms: int, position: Vector3) -> void:
	var capacity := _timestamps_ms.size()

	# Overwrite whatever slot comes next. Once the buffer is full that slot is
	# the oldest sample, which is exactly the one to drop.
	_timestamps_ms[_write_index] = timestamp_ms
	_positions[_write_index] = position

	_write_index = (_write_index + 1) % capacity

	# Stops climbing at capacity: past that, every write replaces a sample.
	if _sample_count < capacity:
		_sample_count += 1


## Query the position at a specific timestamp. Returns:
## - The oldest retained sample's position if timestamp is older than all samples
## - The newest retained sample's position if timestamp is newer than all samples
## - A linearly interpolated position if the timestamp falls between two samples
func position_at(timestamp_ms: int) -> Vector3:
	if not has_samples():
		return Vector3.ZERO

	var capacity := _timestamps_ms.size()

	# Oldest and newest retained slots. Samples run forward from oldest_index,
	# wrapping, for _sample_count entries.
	var oldest_index: int = (_write_index - _sample_count + capacity) % capacity
	var newest_index: int = (_write_index - 1 + capacity) % capacity

	# Older than everything retained, or newer than everything: clamp to the end.
	if timestamp_ms <= _timestamps_ms[oldest_index]:
		return _positions[oldest_index]
	if timestamp_ms >= _timestamps_ms[newest_index]:
		return _positions[newest_index]

	# Inside the retained range: walk to the first sample at or past the query
	# and interpolate across the pair bracketing it.
	var prev_index := oldest_index
	for i in range(_sample_count):
		var current_index: int = (oldest_index + i) % capacity

		if _timestamps_ms[current_index] >= timestamp_ms:
			var span := _timestamps_ms[current_index] - _timestamps_ms[prev_index]
			if span <= 0:
				# Two samples share a timestamp; there is no span to divide by.
				return _positions[current_index]

			var time_fraction := float(timestamp_ms - _timestamps_ms[prev_index]) / float(span)
			return _positions[prev_index].lerp(_positions[current_index], time_fraction)

		prev_index = current_index

	# Unreachable: the newest-sample clamp above already covers every timestamp
	# past the last sample. Kept so every path returns a value.
	return _positions[newest_index]


## Check if any samples have been recorded yet.
func has_samples() -> bool:
	return _sample_count > 0


## Fixed number of slots allocated at construction. Never changes.
func get_capacity() -> int:
	return _timestamps_ms.size()


## Number of slots currently holding a recorded sample, capped at get_capacity().
##
## Exists so the bounded-storage guarantee is testable from outside: the
## acceptance criteria ask for a long session to assert stored element count
## never exceeds capacity, which needs the count to be observable.
func get_sample_count() -> int:
	return _sample_count
