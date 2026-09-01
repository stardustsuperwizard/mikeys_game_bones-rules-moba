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

### No Client-Side Prediction (This Task)

This task does not include client-side prediction of HUD state (cooldowns, resources, cast bar). That is scope for a sibling task. A client simply waits for the server's replication to learn the action's result.

The client's soft-lock/magnetism computation (#38) stays client-side for feel — only the final confirmation (whether the projectile actually spawns) is server-side.
