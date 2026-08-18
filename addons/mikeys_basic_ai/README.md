# Mikey's Basic AI

A reference/default AI for [Mikey's Game Bones](../mikeys_game_bones/): `SimpleAIController`, a dumb aggro-range-and-chase decision loop implementing Bones' `Controller` contract (`get_move_direction()`, `get_attack_target()`, `get_interact_target()`).

## Why this is its own addon, not part of Bones

Bones defines *what a Controller is* (something that produces intent for an Actor); it deliberately doesn't dictate *how AI decides*. That keeps Bones from becoming opinionated about behavior trees vs. utility AI vs. GOAP vs. scripted encounter logic — those choices vary enormously by game genre. `SimpleAIController` exists only to prove the `Controller` contract actually works end to end, the same role a default ENet adapter plays for networking: a reference implementation, not the architecture.

## Swapping it out

Write a new `Controller` subclass implementing the same three methods, then point an actor's `Controller` node at that script instead of `simple_ai_controller.gd`. Nothing in Bones, `Action`, `Rules`, or `Authority` needs to change — they only ever see the `Action`s a `Controller` produces, never how it decided to produce them.

## Depends on

[`mikeys_game_bones`](../mikeys_game_bones/) — extends its `Controller`, reads/writes its `Actor`.
