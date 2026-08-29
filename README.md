# Sword and Planet
**Sword and Planet Roleplaying Game** features a default setting that is based around 20th century pulp adventure stories as well as original content. This is an open source project that is being made to have fun!

## About the Project

### Philosophy
**Game Style**: This is a single player and multiplayer 3D game that will feature "low poly" or "stylized graphics" made popular by the game [World of Warcraft](https://worldofwarcraft.blizzard.com/en-us/) and game rules will be based on the popular and fast [MOBA](https://en.wikipedia.org/wiki/Multiplayer_online_battle_arena) gameplay. Players will have the ability to be both player characters or as a literal all powerful Game Master in the style of [Neverwinter Nights](https://en.wikipedia.org/wiki/Neverwinter_Nights).

**Goals:**  
The following are the main, but certainly not the only, soft goals of the project (ie not time boxed or SMART).  
* Produce an open-source computer role-play game for both single player and multiplayer play.
* Implement Game Master functionality that allows play groups to create curated game experiences whether in a planned session or ad-hoc in a persistent world.
* Foster creative story telling and "bring to life" story ideas.
* Learn to develop automated and AI workflows to build an end product using natural language (currently, English).
* Enable game development for a busy dad, during his limited downtime.

### Technical
**Game Engine:** [Godot 4](https://godotengine.org) (client and server)

**Third-Party Addons:**  
These live under `addons/` but are excluded from git (`.gitignore` has `addons/*`,
`!addons/mikeys_*` — only the first-party `mikeys_*` addons are tracked). Anyone
setting up the project needs to install these locally; without them, `project.godot`
references autoloads and a plugin that won't exist.
* [Maaack's Game Template](https://github.com/Maaack/Godot-Game-Template)
  (`addons/maaacks_game_template`) — v1.5.3, from the
  [Godot Asset Library](https://godotengine.org/asset-library/asset/2709). Provides
  the main menu, pause/options menus, credits, and scene loader. Its example scenes
  were copied out into the project proper (`scenes/opening/`, `scenes/menus/`,
  `scenes/windows/`, etc.) rather than referenced in place; only its reusable
  `base/` autoloads and framework scripts are still loaded from `addons/`.
* Universal Inventory (`addons/universal_inventory`) — ships no version metadata or
  plugin.cfg; re-source it the same way it was originally obtained if it needs
  reinstalling. Provides the inventory/equipment/tooltip system, wired up via
  `scenes/inventory/`, `scenes/ui/`, `scripts/inventory/`.
  **Required patch after (re)installing:** several of its own scripts hardcode
  `res://scenes/...` and `res://scripts/...` paths, assuming the addon sits at the
  project root rather than nested under `addons/universal_inventory/`. Prefix each
  of the following with `res://addons/universal_inventory/`, or the inventory UI and
  tooltips fail to load:
    - `scripts/inventory/InventoryView.gd` — the `INVENTORY_SLOT_SCENE` preload
    - `scripts/tooltip/ItemTooltip.gd` — the `default_label` preload
    - `scripts/tooltip/sections/{Name,Description,Price,Slot,Equipped,Affixes}Section.gd`
      — each one's `label_path`
    - `scenes/quantity_selector.tscn` — the `P_Red03.png` texture `ext_resource`

**Future Game Assets:**  
These assets are not yet a part of the project but have been scoped in the past for inclusion.
* [quaternius](https://quaternius.com)
* [Godot D20 Framework](https://dax272.itch.io/godot-d20-framework)

## Player Controls

These are the bindings that exist in the current build. The full control design
— gamepad, keyboard + mouse, and touch — is specified in
[docs/pulp_moba_rpg_ruleset.md](docs/pulp_moba_rpg_ruleset.md) §5. Touch is not
bound at all yet, and the combat actions listed below as *bound, not yet used*
are waiting on the ability system.

### Keyboard

| Action | Key |
|---|---|
| Move Forward | W |
| Move Back | S |
| Turn Left | A |
| Turn Right | D |
| Strafe Left | Q |
| Strafe Right | E |
| Jump | Space |
| Recenter Camera | C |

### Mouse

| Action | Input |
|---|---|
| Contextual action | Left click |
| Look around | Right click and drag |
| Zoom in / out | Scroll wheel |

### Gamepad

| Action | Input |
|---|---|
| Move forward / back | Left stick, up / down |
| Strafe left / right | Left stick, left / right |
| Turn left / right | Right stick, left / right |
| Jump | Left stick click (L3) |
| Recenter camera | Right stick click (R3) |

The right stick turns the character rather than orbiting the camera, because
camera look is currently mouse-only. Ruleset §5.1 puts the right stick on the
camera; that swap happens once stick-driven camera orbit exists.

### Bound, not yet used

These actions exist in the `InputMap` so the ability system has something to
bind against when it lands. Nothing reads them today.

| Action | Keyboard / Mouse | Gamepad |
|---|---|---|
| Basic attack | Left click | Right trigger |
| Ability 1–4 | 1 / 2 / 3 / 4 | A / B / X / Y |
| Targeting lock-on | Tab or middle click | Right bumper |
| Contextual defense | Shift | Left bumper |

Left click is a single contextual action button — what it does depends on what
you clicked:

| Clicked | Result |
|---|---|
| Ground | Walk there |
| Hostile character | Walk into melee range, then attack |
| Door or other interactable | Walk into range, then use it |
| Wall | Walk up to it and stop against it |
| Sky, or anything else | Nothing |

Each click issues one order that the character carries out on its own, turning
to face where it is headed. A new click replaces the order, any keyboard
movement cancels it, and an order the character cannot reach is abandoned
rather than walked into forever. There is no pathfinding yet, so orders only
work along a clear line to the destination.


## A note about Generative AI
Generative AI is being used in this project. 

This was a deliberate choice due to limited time and a desire to design and play a game that no one else is making (see goals). Generative AI is being used across many industries and as of 2026 there is the assumption that the technology is not going to be, "going away" in the near future. One of the drivers behind this fun project is to continue to build skills that will be relevant in the future software world. 

It is okay if you do not wish to play a game that has been made this way. You do not have to play this game. It was made for someone else. If you like the concept of the game and would like to contribute you can fork the repo and replace the AI code with human written code and play the game your way. You can also submit a PR with human written code in it that either replaces or enhances machine written code.

### Human made content
While generative AI is used to produce the code infrastructure to play the game, the "promise" of AI is to enable creative pursuits by and for humans. This game is not being created to be a second job that has to be debugged late at night, it is to create interactive stories to explore! To that end, generative AI's role in story telling should minimal and mostly around helping humans make their ideas coherent and real, not writing content.

---

This project is designed with heart :heart: by humans and built with speed :fast_forward: by machines.
