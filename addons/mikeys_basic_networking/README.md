# Mikey's Basic Networking

A minimal ENet transport bootstrap for Godot 4's high-level multiplayer API.

`network_bootstrap.gd` (an autoload in the consuming game) reads `--server` / `--connect=<address>` from the command line, starts an `ENetMultiplayerPeer` as host or client accordingly, and assigns it to `multiplayer.multiplayer_peer`. That's all it does.

It does not know what a "player" or an "Actor" is, and does not spawn or despawn anything. Reacting to a peer joining or leaving is the consuming game's job — connect directly to Godot's own native `multiplayer.peer_connected` / `multiplayer.peer_disconnected` signals from the game itself (see `game1_demo/runtime/session_spawner.gd`). Those signals are already the right extension point: any `MultiplayerPeer` implementation fires them, not just this addon's ENet one, so a game written against them doesn't need to change if the transport ever does.

## Depends on

Nothing. This addon doesn't reference `mikeys_game_bones` or any other addon — it only establishes a Godot multiplayer peer.
