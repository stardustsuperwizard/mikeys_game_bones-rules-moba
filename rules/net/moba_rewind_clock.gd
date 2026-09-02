## Per-peer clock offset estimation for validating client-reported timestamps.
##
## Answers "how many milliseconds in the past is this client's timestamp" for
## the rewind window that lag-compensated skillshot resolution reads (#48).
## Plain and node-free: it takes ints in and returns ints out, touching no node,
## no scene tree and no multiplayer API, the same shape MobaPositionHistory keeps.
##
## ## Why an offset estimate is needed at all
##
## A client sends its own `Time.get_ticks_msec()`, which counts from that
## process's start. The server's `Time.get_ticks_msec()` counts from its own.
## The two are not comparable: subtracting one from the other yields the epoch
## difference plus the one-way network delay, not the delay alone. Nothing in
## this repository performs a clock-synchronization handshake, and this class
## deliberately does not add one -- it makes sense of the timestamps ordinary
## request traffic already carries.
##
## ## The minimum-offset estimate
##
## For one sample, `server_arrival_ticks_ms - client_sent_ticks_ms` equals the
## fixed epoch difference plus that packet's one-way delay. Jitter only ever
## adds delay, never removes it, so across samples the *smallest* observed
## difference is the closest approach to "epoch difference plus the true
## minimum one-way delay". record_sample() therefore keeps a running minimum:
## a new sample tightens the estimate or is discarded, and the estimate can
## only ever improve.
##
## ## Bounded storage
##
## One integer per peer id, and nothing else. The estimate is folded into that
## integer on arrival, so no sample history accumulates and the tracked entry
## count is the number of distinct peer ids no matter how many samples arrive.
## get_tracked_peer_count() reports it. Entries are never evicted: a
## disconnected peer leaves one stale integer behind, which is not a leak at
## any scale this game runs at.
##
## ## Usage
##
##     clock.record_sample(peer_id, client_sent_ticks_ms, server_arrival_ticks_ms)
##     var delay_ms := clock.get_rewind_delay_ms(
##         peer_id, client_reported_ticks_ms, server_now_ms, window_ms
##     )
##
## The returned delay is always within `[0, window_ms]`: 0 means "resolve as of
## now", window_ms means "rewind the whole window".
class_name MobaRewindClock
extends RefCounted

## Best offset estimate per peer id, as `int -> int`. The value is the smallest
## `server_arrival_ticks_ms - client_sent_ticks_ms` yet observed for that peer:
## adding it to a client tick count translates that tick count into the server's
## timeline. One entry per peer id, one integer per entry.
var _peer_offsets: Dictionary = {}


## Fold one observed `(client_sent, server_arrival)` pair into the peer's offset
## estimate, keeping whichever is smaller.
##
## Intended to be called from every request/resolve handler that already carries
## a client timestamp; wiring those call sites is a separate task. Calling this
## many times for one peer does not grow that peer's stored state.
func record_sample(peer_id: int, client_sent_ticks_ms: int, server_arrival_ticks_ms: int) -> void:
	var observed_offset := server_arrival_ticks_ms - client_sent_ticks_ms

	if not _peer_offsets.has(peer_id):
		_peer_offsets[peer_id] = observed_offset
		return

	# Jitter only ever adds delay, so a smaller observation is strictly closer
	# to the true offset. A larger one carries more jitter and is discarded.
	_peer_offsets[peer_id] = mini(_peer_offsets[peer_id], observed_offset)


## Translate a client-reported tick count into server time and report how far in
## the past it lands, clamped to `[0, window_ms]`.
##
## A peer with no recorded sample has no offset estimate and so no basis for
## trust: it gets window_ms, the maximum-rewind answer, never 0. A timestamp
## that translates to after `server_now_ms` -- a claimed-future timestamp -- is
## clamped to 0 ("resolve as of now") rather than rewinding into the future.
func get_rewind_delay_ms(
	peer_id: int, client_reported_ticks_ms: int, server_now_ms: int, window_ms: int
) -> int:
	if not _peer_offsets.has(peer_id):
		return window_ms

	var offset: int = _peer_offsets[peer_id]
	var translated_ticks_ms := client_reported_ticks_ms + offset

	return clampi(server_now_ms - translated_ticks_ms, 0, window_ms)


## Number of peer ids currently holding an offset estimate.
##
## This is the whole of the tracked state's size: it counts distinct peer ids,
## never samples. Exposed so the bounded-storage property can be asserted the
## way MobaPositionHistory.get_capacity() lets its own bound be asserted.
func get_tracked_peer_count() -> int:
	return _peer_offsets.size()


## Whether a peer has at least one recorded sample, and therefore an offset
## estimate that get_rewind_delay_ms() will use instead of the conservative
## window_ms fallback.
func has_offset_estimate(peer_id: int) -> bool:
	return _peer_offsets.has(peer_id)
