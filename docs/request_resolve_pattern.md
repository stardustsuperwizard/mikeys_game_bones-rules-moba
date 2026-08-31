# The Request/Resolve RPC Pattern

A worked example of the client-to-server request/resolve pattern for
server-authoritative actions in Godot 4, recorded from the only implementation
this repository ever had.

Written 2026-08-31, from `addons/mikeys_game_bones/actors/actor.gd` as it stood
at that time. That implementation is deleted by task #289 (see
[Why this document exists](#why-this-document-exists)); the code quoted below is
therefore a historical record, not something you can still go read.

Intended reader: a future multiplayer session (#277, #278) that needs a
server-authoritative action path and has none of this session's context.

---

## The shape

Three methods, one per responsibility:

| Method | Runs on | Responsibility |
| --- | --- | --- |
| `try_*()` | Whichever peer wants the action | Decide: act locally, or ask the server |
| `request_*()` | The server only | Receive the remote ask, identify who sent it |
| `_resolve_*()` | Wherever the action is authoritative | Actually do it, after re-checking state |

The point of the split is that `_resolve_*()` is reached by exactly one code
path in both the networked and the non-networked case. A local actor and a
remote client's actor do not resolve their attacks through different logic; they
differ only in which peer id arrives as `requester_id`.

## `try_*()` — route the call

`try_*()` is the entry point a controller calls. It asks a single question: am I
a client that is not the server? If so, the action is not mine to perform, and
it forwards the ask over RPC instead of acting.

From `actor.gd` (lines 61–69):

```gdscript
# Only the actor's own controlling peer ever calls this (gated upstream by
# the body's authority check), so it's just "should I ask the server to
# attack" -- the server is the only one that ever actually resolves it.
func try_attack(target: Actor) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_attack.rpc_id(1, target.get_path())
		return

	_resolve_attack(target, multiplayer.get_unique_id())
```

Both halves of the guard matter:

- `multiplayer.has_multiplayer_peer()` is false in single-player. Without it,
  an offline session would try to RPC to a peer that does not exist.
- `not multiplayer.is_server()` means the server itself skips the round trip and
  resolves directly. The server does not send itself a request.

So the local branch covers two cases at once — single-player, and the server
acting on an actor it owns (an AI-driven one, typically) — and passes
`multiplayer.get_unique_id()`, the local peer's own id, as the requester. On the
server that is `1`; with no peer active Godot also reports `1`.

`rpc_id(1, ...)` is what fixes the direction of the call. Peer `1` is always the
server in Godot's high-level multiplayer, so this is a client-to-server send to
one specific peer, not a broadcast. `target.get_path()` is sent rather than the
`Actor` itself because a `NodePath` is serializable and an object reference is
not; the server re-resolves it against its own scene tree.

## `request_*()` — the server's inbox

```gdscript
@rpc("authority", "call_remote", "reliable")
func request_attack(target_path: NodePath) -> void:
	var target := get_node(target_path) as Actor
	if target:
		_resolve_attack(target, multiplayer.get_remote_sender_id())
```

(`actor.gd` lines 71–75.)

Read the annotation carefully, because its first argument is the one most often
misread:

- **`"authority"`** is a *permission* mode, not a destination. It means the RPC
  is only accepted from the node's multiplayer authority. It does not say "this
  runs on the server." What makes `request_attack()` server-only is that its
  sole caller sends it to peer `1`.

  This repository set each `Actor`'s authority to its owning peer
  (`world_manager.gd` called `actor.set_multiplayer_authority(...)` with the
  owner's id), so the client that owns the actor *is* its authority and its call
  is accepted. The looser alternative, `"any_peer"`, would let any connected
  client invoke the method on any actor — at which point the sender id below
  becomes the only thing standing between you and one player driving another
  player's character. Prefer `"authority"` and let the authority assignment do
  the gating.
- **`"call_remote"`** means the caller does *not* also run the method locally.
  Without it the client would resolve its own attack alongside the server's,
  which is precisely what a server-authoritative design is avoiding.
- **`"reliable"`** means delivery is guaranteed and ordered. Correct for
  discrete state-changing commands. Continuous, self-correcting streams
  (position updates) are the case for `"unreliable"`; a dropped attack is not
  self-correcting.

`multiplayer.get_remote_sender_id()` is valid only inside an RPC body, and only
for the duration of that call. Read it here and pass it onward — do not stash it
in a field and read it later.

## `_resolve_*()` — the one authoritative path

```gdscript
# The only place an attack is ever actually resolved -- called directly for
# AI/single-player, or from request_attack() for a networked player. Its own
# _attack_timer check is the real cooldown enforcement; the server never
# trusts a client to have rate-limited itself.
func _resolve_attack(target: Actor, requester_id: int) -> void:
	if _attack_timer > 0.0:
		return

	_attack_timer = attack_cooldown
	ActionRunner.run(AttackAction.new(self, target), requester_id)
```

(`actor.gd` lines 77–86.)

Two entry points, one body:

- from `try_attack()`, with `multiplayer.get_unique_id()` — the local peer acting
  on its own actor;
- from `request_attack()`, with `multiplayer.get_remote_sender_id()` — a remote
  client's ask.

Everything downstream takes `requester_id` as a plain integer and never needs to
know which of the two it came from. That is the property worth preserving when
you rebuild this: keep the requester's identity a parameter, not ambient state,
and the networked and non-networked paths stay a single implementation.

## Why the server re-checks its own state

`_resolve_attack()` tests `_attack_timer` even though the client has a copy of
that timer ticking down too. The re-check is the actual enforcement; the
client's is a prediction.

**A client's `try_attack()` call is a request, not evidence.** It says "I would
like to attack," not "I have verified I am allowed to attack." Nothing in the
message can establish the latter — a client can send whatever it likes, whenever
it likes, whether through a modified build or a plain bug. Trusting it makes the
cooldown advisory.

**The server's copy of `_attack_timer` is the only authoritative one.** This is
why `_physics_process()` decays the timer on every peer's copy of an actor,
including the server's copy of a client-owned one, even though the server never
simulates that actor's movement:

```gdscript
func _physics_process(delta: float) -> void:
	# Ticks on every peer's own copy regardless of movement authority: the
	# server needs its copy of a peer-owned actor's cooldown to keep
	# decaying, since the server is what actually enforces it (see
	# _resolve_attack), even though it never simulates that actor's movement.
	if _attack_timer > 0.0:
		_attack_timer -= delta
```

(`actor.gd` lines 53–59.) An authority split is per-concern: movement authority
lived with the owning client, action authority with the server, and the server
still had to maintain the state its own authority depended on.

Generalise it as: for any precondition on an action — cooldowns, resource costs,
range, ownership, whether the target is even a legal target — the server must
hold the state and check it inside `_resolve_*()`. The client-side check stays
worth keeping, but as responsiveness, not as enforcement.

## Interact: the same shape, minus the cooldown

`try_interact()` / `request_interact()` / `_resolve_interact()` are the identical
three-method shape. The only difference is that `_resolve_interact()` has no
rate-limit check — opening a door has no cooldown to enforce.

From `actor.gd` (lines 88–110):

```gdscript
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
```

Having both verbs recorded is the useful part: it shows which pieces are
structural and which belong to the specific action. The routing guard, the
`rpc_id(1, ...)` send, the annotation, and the `requester_id` hand-off are the
pattern and appear identically in both. The `_attack_timer` check is attack's
own precondition and lives only in `_resolve_attack()`.

## Why this document exists

The methods quoted above were the repository's only implementation of this
pattern, and they were unreachable in the shipped game — nothing called
`try_attack()` or `try_interact()`. Task #289 deletes `Actor`'s dead attack and
interact verbs on that basis, which is correct for the code and would have taken
the worked example with it.

So this document was written first, deliberately, as task #289's precondition.
When multiplayer work (#277, #278) needs a server-authoritative action path,
this is the record of how one was shaped here — read it as a reference to build
from, not as a description of code that still exists.
