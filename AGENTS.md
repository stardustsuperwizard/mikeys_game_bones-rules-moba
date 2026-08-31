# Agent Instructions

## Project

`mikeys_gamebones-rules-moba` is a Godot 4 **MOBA**. Its combat ruleset lives
as a self-contained module in `rules/`, with a Python balance harness in `sim/`
and the playable game in `scenes/` and `scripts/`.

`rules/` keeps a strictly one-way dependency arrow — the game depends on the
rules, never the reverse (see `.github/instructions/rules.instructions.md`).
That isolation exists so client and server can run identical simulation, which
is what makes server-authoritative multiplayer tractable.

**Multiplayer is a first-class feature of this game, not a later extension.**
Single-player against bots stays fully supported; it is one session mode rather
than the default that networking is bolted onto afterwards. See #277 and #278.

**The player has a character that is theirs, not one they borrow.** This is the
project's distinguishing design claim. In a roster game you pick a champion, every
copy of them is identical, and you give them back at the end. Here the character is
named, dressed, statted, and kept — the reason to stand in the lobby is that the
character standing there is yours.

Presets, templates, and starting builds are **explicitly allowed and encouraged** as
the front door: picking "Warrior" and then naming, dressing, and tuning it is how
D&D character creation works. #44's four loadouts are good starting builds, not a
roster to compete with. Roles still emerge from the equipped kit —
`MobaAbility.Discipline` enumerates all six §3 disciplines — and §54's "no character
levels" is what makes creation-time and between-match choice the build system.

Stat optimisation is a **feature**, not a complexity cost to mitigate. Working out
the best combination is the retention loop.

Three modes share one ruleset and one character: arena (base), PvE tower defense
(expansion), MOBA (expansion). See `docs/GAME_MODES.md` for what is shared, what each
mode adds, and the sequencing.

> **Revised 2026-08-30.** This section previously read: "a Godot 4 project whose
> exclusive purpose is developing a portable MOBA rules engine… **It is not a
> game**… do not add game-specific content here." That is no longer true and was
> actively blocking: the repository contains a playable game, and #278 requires
> host/join and menu work that the old wording forbade outright. Game content,
> scenes, and game-flow UI that serve this MOBA are in scope. See
> `docs/rules/README.md` for the roadmap and the decisions this revision
> corrects.

Human-authored design requirements and GitHub Issues are the source of truth
for intended behavior.

## Working Rules

- Read the complete Issue before making changes.
- Read relevant project documentation before implementation.
- Inspect existing code before introducing new abstractions.
- Make the smallest change necessary to satisfy the Issue.
- Do not implement functionality listed as out of scope.
- Do not refactor unrelated code.
- **Do not add third-party dependencies or addons.** Decided 2026-08-31: this
  project builds what it needs. This reverses the older "use components that
  already exist in the wild" goal, which served a reusable framework that no
  longer exists (#276). If a task looks like it wants a plugin, say so in the
  PR rather than adding one.

## Architecture

- Rules-engine behavior stays generic and portable — do not couple `rules/`
  or `sim/` to any specific game's assets, scenes, or content.
- Prefer composition and existing extension points over new abstractions. This
  repository removed its framework layer (#276) after roughly two thirds of it
  proved unreachable; new abstractions need a second caller before they earn a
  name.
- Do not change the shared types in `scripts/` (`Actor`, `Controller`,
  `ActorBody3D`, `Action`, `ActionResult`) unless the Issue explicitly requires
  it.
- If the requested feature conflicts with the documented architecture, explain
  the conflict rather than silently working around it.

## Agent Roles

Planning, implementation, and review run as separate sessions on different
models. See `docs/AGENT_WORKFLOW.md` for role definitions, model routing,
and the handoff contract.

## Testing

- Existing tests represent established behavior.
- Do not weaken, remove, or skip tests merely to make an implementation pass.
- Add tests for new behavior when practical.
- Report validation that could not be performed.

## Completion

Before declaring a task complete:

1. Verify the acceptance criteria in the Issue.
2. Run `.github/scripts/validate-godot.sh`.
3. Summarize what changed.
4. Call out assumptions, limitations, or unresolved design questions in the PR.