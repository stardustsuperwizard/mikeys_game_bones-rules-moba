# Networking and Synchronization

Server-authoritative combat resolution with state replication.

## Authority Model

This project implements server-authoritative command execution for all combat actions. The server is the sole peer whose calls ever reach `ActionRunner.run()` for a networked client's request, and the server checks the requesting peer's identity against that peer's real authorization to act.

**What a client may execute locally: nothing, for these two commands.** Since #320 a connected non-host client never reaches `ActionRunner.run()` for an ability activation or a basic attack. Its `try_*()` call forwards the ask and returns `null` — there is no local resolution, no optimistic mutation of `MobaCombatant`, and no return value to inspect. Everything the client learns about the outcome arrives as replicated state. What only the server executes: the `Action`, the `Authority.can_perform()` check, every cooldown and resource commitment, target and skillshot resolution, damage, crowd control, and death.

Offline play and the server's own actors are the other side of that: they resolve locally, exactly as they did before #320, and `try_*()` hands their caller the real `ActionResult` back.

### Request/Resolve Pattern

All player-initiated commands (ability activation and basic attacks) follow the request/resolve RPC pattern recorded in `docs/request_resolve_pattern.md`. The pattern has three parts:

1. **`try_*()`** — Decide whether to route locally or via RPC
   - Runs on whichever peer wants to perform the action (player or AI)
   - Checks: `multiplayer.has_multiplayer_peer() and not multiplayer.is_server()`
   - If true (client, not server): forwards to `request_*()` via RPC
   - If false (offline or server-owned): calls `_resolve_*()` directly

2. **`request_*()`** — Server's RPC inbox
   - Annotated `@rpc("authority", "call_remote", "reliable")`
   - Runs only on the server, called from the client via `rpc_id(1, ...)`
   - Reads `multiplayer.get_remote_sender_id()` once and passes it to `_resolve_*()`
   - Re-resolves node paths against the server's scene tree (clients cannot send object references)

3. **`_resolve_*()`** — Authoritative action execution
   - Runs on exactly one peer: the one whose call actually executes
   - Takes `requester_id` as a parameter (never ambient state)
   - Calls `ActionRunner.run(action, requester_id)` with the real peer id
   - `ActionRunner` passes `requester_id` to `Authority.can_perform()`, which checks:
     - Actor's `owner_id == 0` (AI-controlled): allowed from any local requester
     - Actor's `owner_id > 0` (player-controlled): requester must be the owning peer

### Local/Server Paths

Both offline single-player and the server's own local/AI-controlled actors resolve locally without an RPC round trip:

- **Offline play** (`multiplayer.has_multiplayer_peer()` is false)
  - `try_*()` calls `_resolve_*()` with `multiplayer.get_unique_id()` (always 1 offline)
  - No network peer exists; there is no `request_*()` call

- **Server-owned actors** (the server acting on AI or debug-spawned actors)
  - `try_*()` checks `multiplayer.is_server()` and calls `_resolve_*()` directly
  - The server is both requester and executor; no RPC needed

### Ability Activation

`Actor.try_activate_slot()` / `request_activate_slot()` / `_resolve_activate_slot()` implement the pattern for ability slot activation:

- `try_activate_slot(slot_index: int, context: MobaCastContext)` routes the call
- `request_activate_slot()` carries: slot index, target node path (or empty), aim direction, ground point, and the client's send-time `Time.get_ticks_msec()`
- `_resolve_activate_slot()` resolves the ability and calls `MobaAbilityCaster.activate_slot()` with the real `requester_id`

Skillshots work as follows:
- The client computes aim direction locally (aim assist, #38) as input to the activation request
- The server receives the requested direction in `context.aim_direction`
- `MobaAbilityAction.execute()` calls `MobaTargeting.resolve_skillshot()`, which spawns the authoritative projectile server-side

### Basic Attack

`Actor.try_basic_attack()` / `request_basic_attack()` / `_resolve_basic_attack()` implement the pattern for melee attack resolution:

- `try_basic_attack(target: Actor)` routes the call
- `request_basic_attack()` carries: target node path and the client's send-time `Time.get_ticks_msec()`
- `_resolve_basic_attack()` constructs a `MobaBasicAttackAction` and calls `ActionRunner.run()` with the real `requester_id`

**A forwarded swing is re-requested until the client sees the server start it.** `MobaBasicAttackAction` refuses a swing while the attack cycle is winding up or recovering, and `PlayerController3D.get_attack_target()` arms its pending-target latch only once per order — it calls `cancel_order()` first, so `_attack_target` is already gone and nothing re-arms it. A client that dropped its latch on the forwarded path would therefore turn a single refused request into a click that silently produces no swing at all. Instead the controller holds the pending target and keeps re-requesting, releasing it when its own replicated `MobaStateMachine` transitions into `BASIC_ATTACK_WINDUP` — the server having actually started the swing. The release watches for that *transition*, not for "currently swinging": a snapshot would misread a cycle already in flight when the order armed, and "was neutral, now swinging" would never fire at all, because while the latch re-requests each frame the server starts each swing as the previous one ends and the actor never returns to a neutral state. One order still yields one swing, as it does offline.

### Cooldown and Resource Enforcement

The server maintains authoritative copies of all cooldown and resource state. When `ActionRunner.run()` is called on the server with a networked client's `requester_id`, `Authority.can_perform()` checks that the requesting peer owns the actor. The server then enforces the action's preconditions:

- Cooldowns via `MobaCombatant.can_activate()`
- Resource costs via the same check
- State machine legality via `MobaStateMachine.can()`

A client request for an ability already on cooldown per the server's own ledger is refused outright and never executes, regardless of what the client's local (possibly stale) copy believed. The refusal is implicit: a server-denied action simply does not run, and does not broadcast state changes through replication. The client observes the refusal through state replication showing the cooldown is still active.

**The server ticks the ledger it enforces against.** `PlayerController3D._physics_process()` gates input and the basic-attack order on body authority, but calls `MobaCombatant.tick()` whenever this peer is the server (or offline), including on its copy of an actor some client owns and moves. Without that, the server would never advance a connected client's cooldowns, resource regeneration, cast/channel timers or respawn countdown at all: the ledger would freeze at the first cast and refuse every later request forever. This is the same point `docs/request_resolve_pattern.md` makes about the `_attack_timer` it recorded — the server must hold *and advance* the state its authority depends on, even for an actor whose movement it never simulates. A client still ticks only its own actor's local copy, which replication corrects.

**The timestamp in each request is carried, not trusted.** The recorded payload includes one, so it is sent; nothing on the server reads it to resolve anything. The rewind window that would consume it is #48. Until that exists, the server dates every request by its own arrival.

### State Replication

Health, resource, cooldowns, effects, shields, and death already replicate through existing configuration:

- `CombatStateSynchronizer` in `scenes/player/player.tscn` and `scenes/enemy/enemy.tscn`
- Owned by `MobaCombatant` (server-authoritative, per #313)
- Tracks: `MobaCombatant` properties that drive the HUD and visual state

A client's ability request succeeds or fails server-side, then its result propagates back to all connected peers through replication — not through a direct response message. The client waits for the server's state update to learn whether the activation succeeded.

### Disconnect Mid-Cast

When a connected peer disconnects, `WorldManager._on_peer_disconnected()` immediately frees that peer's actor. Any in-progress cast (in `MobaCombatant`'s cast/channel/toggle tracker) is destroyed with it — no separate cleanup is needed. This is the documented rule for handling casts interrupted by disconnection.

### Client-Side Prediction and Rollback (#321)

Since #320 the server is the sole executor of a client's ability activation and
basic attack, which leaves the requesting client a full round trip with no
feedback. So on sending the request, the client also records a **prediction**:
a client-local overlay on its own rendered state, held in `MobaPredictionLedger`
and read through `MobaCombatant`'s existing public accessors.

#### What is predicted, and what is not

| Predicted client-side, immediately | Always requires the server round trip |
| --- | --- |
| The ability's cooldown sweep starting | Whether the activation actually happens |
| The ability's resource cost being spent | The real cooldown, resource and charge ledger |
| The cast bar appearing for a cast-time ability | Damage, crowd control, shields, death |
| That a requested swing is outstanding | The swing itself, and what it hits |
| | The authoritative projectile a skillshot spawns |

The prediction is an **offset**, never a write: `MobaCombatant`'s ledger is
untouched, so a rollback is just dropping the entry — there is no spent resource
to refund and no started cooldown to cancel. It is applied only on the requesting
client, never broadcast, and never treated as final. The server remains the only
peer that reaches `ActionRunner.run()` for these commands.

Movement prediction is unrelated and unchanged: it runs off the per-peer
movement authority on `ActorBody3D` (`is_multiplayer_authority()`), which #321
does not touch.

#### How a prediction ends

Every prediction ends in exactly one of two ways:

- **Superseded** — the server's replicated ledger shows the request committed,
  the overlay is dropped, and the real value takes over. Because
  `get_cooldown_remaining()` returns the larger of the two, the replicated value
  is the same sweep a round trip further along and takes over without the sweep
  visibly restarting from full.
- **Rolled back** — the server refused, and said so with `Actor.deny_activation()`.

A third exit exists only as a backstop: `MobaPredictionLedger.TIMEOUT_SECONDS`.
Neither answer arrives if the request died with the connection, and a prediction
that outlived both would be a HUD lying indefinitely.

#### Why a denial RPC is required

The combat state replicates at `replication_mode = 2` (on-change), which re-sends
a value only when the **server's own** copy of it changes. A refusal changes
nothing on the server by definition, so nothing is re-sent, and "wait for the
next sync" would structurally never fire. The denial has to be explicit.

For the same reason, confirmation is measured against `_last_replicated` — what
the server last said — and not against the local ledger. Anything local may write
that ledger, including a stale or tampered client's own guess, and a cooldown the
server was *already* running would otherwise read as proof that it accepted a
request it in fact refused.

`Actor._deny_if_predicted()` sends the denial only for refusals the client would
have predicted through: an `Authority.can_perform()` refusal (an `ActionResult`
carrying no reason) and the `MobaCombatant.can_activate()` refusals. A swing
refused mid-cycle is deliberately excluded — `PlayerController3D`'s
forwarded-attack latch re-requests against exactly that case, so denying it would
put a reliable RPC on the wire every frame the latch holds.

#### The denial's RPC mode

`deny_activation()` is annotated `@rpc("any_peer", "call_remote", "reliable")`
and guards on `multiplayer.get_remote_sender_id() != 1`, rather than using the
`"authority"` mode the request path uses. That is the same rule read in the right
direction, not a weaker one: `world_manager.gd` sets an actor's multiplayer
authority to its **owning peer**, which is what makes `"authority"` correct for a
client-to-server request on its own actor — and wrong travelling back, where the
sender is the server and the node's authority is the client being addressed.
Godot drops every such call:

```
RPC 'deny_activation' is not allowed on node /root/ClientPeer/Arena/Player
from: 1. Mode is "authority", authority is 259047170.
```

The explicit sender check restores exactly the guarantee the annotation would
have given: only the server can deny.

#### Where it lives

- `rules/core/moba_prediction_ledger.gd` — the overlay, and the confirm/rollback rules
- `MobaCombatant.get_prediction_ledger()` — the seam; the accessors above it
  (`current_resource`, `get_cooldown_remaining()`, `get_cooldown_duration()`,
  `get_charges()`, `can_activate()`) already read through the overlay
- `Actor.try_activate_slot()` / `Actor.try_basic_attack()` — predict, then request
- `Actor.deny_activation()` — the server-to-requester denial RPC
- `rules/ui/moba_cast_bar.gd` — shows the predicted cast, still reading a public
  getter only, keeping `rules/ui/`'s "signals in, nothing out" rule intact

The client's soft-lock/magnetism computation (#38) stays client-side for feel — only the final confirmation (whether the projectile actually spawns) is server-side.

### Lag-Compensated Skillshot Hit Detection (#48)

Skillshots spawned by networked clients test combatant candidates against their **rewound** position (from `MobaPositionHistory`) at a delay validated by `MobaRewindClock`, enabling hits on targets whose current position has already left the shot's path but whose position at send-time was inside it.

#### Rewind Window

The rewind window bounds how far back a client's position is rewound. The default is `MobaPositionHistory.DEFAULT_REWIND_WINDOW_MS` (120 ms), matching the §64 specification of 100–150 ms. The recorded delay is clamped to this window regardless of the peer's measured latency:

- **Past-window clamp**: a claimed timestamp older than the window's edge is clamped to the edge, so an old/forged/stale timestamp produces a hit outcome that matches the window-edge position, never the fully-old one
- **Future clamp**: a timestamp translating to after the server's current time is clamped to 0 ("resolve as of now"), never rewinding into the future
- **Unproven-peer clamp**: a peer with no recorded sample has no offset estimate, so `get_rewind_delay_ms()` returns the full window width as a conservative fallback

#### What is and is not rewound

Only the *positions of combatant candidates* are rewound. Everything else resolves live:

- the projectile spawns at the caster's real current position and flies the direction the client sent — the caster is never rewound
- world geometry is resolved by the live `ShapeCast3D` sweep at its real current position, so a wall still blocks the shot; a wall nearer than a rewound target stops the projectile before that target is considered
- validity — aliveness, allegiance, caster exclusion — is read live through `MobaTargeting.filter_valid_targets()`, so a target that died before the shot resolves is never hit even though its rewound position still exists in history
- damage and effects apply against the target's **current** health, armour and shields; position history carries positions and nothing else

The rewind timestamp is computed once, at activation, and held constant for the projectile's whole flight, so every tick tests the same instant of history rather than a receding one.

#### Known Trade-off

Lag compensation favours the shooter: a rewound hit can land on a target from a position the target had already left on their own screen (§64/§1). That is the accepted cost of making networked skillshots feel responsive.

It is bounded in two ways. The window caps how stale the rewound position can be at `DEFAULT_REWIND_WINDOW_MS`, and because world geometry is *not* rewound, a shot still cannot travel through a wall to reach a rewound position behind it — what a victim can lose is a step of their own movement, not a corner they had already broken line of sight behind.

#### Sample Recording

Every ability activation from a networked client records a `(peer_id, client_ticks_msec, server_arrival_ticks_msec)` sample via `MobaRewindClock.shared().record_sample()`, whether the ability is a skillshot or not. This continuously improves the peer's offset estimate. The estimate converges toward the true one-way latency plus the epoch offset, and only ever improves (never relaxes) as jitter subsides.

`MobaRewindClock.shared()` is the process-wide instance: `scripts/actor.gd` records into it and `MobaTargeting.resolve_skillshot()` reads from it, and estimates are only useful when both sides see the same ones. It is a lazily created plain `RefCounted`, not an autoload — the class stays node-free, and tests construct their own isolated `MobaRewindClock.new()`.
