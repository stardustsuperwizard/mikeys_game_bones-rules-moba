## Configuration for automatic respawning behavior.
##
## Specifies whether a combatant respawns, the delay before respawn,
## and which SpawnPoint to use. Authored as .tres resources.
class_name MobaRespawnPolicy
extends Resource

## Whether the combatant auto-respawns on death. If false, respawn()
## can still be called manually but does not happen automatically.
@export var respawns: bool = false

## Delay in seconds before auto-respawn triggers (ignored if respawns == false).
## Countdown happens in MobaCombatant.tick() during DEAD state.
@export var respawn_delay: float = 3.0

## The spawn point location to move the body to on respawn.
## Read-only after assignment; never mutated at runtime.
@export var spawn_point: SpawnPoint = null
