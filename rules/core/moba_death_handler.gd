## Owns the DEAD-state lifecycle for a single MobaCombatant: firing death
## exactly once, applying/restoring the minimal death visual, clearing
## carry-over effects/shields/CC when death is finalized, and respawn()
## (called manually or by the auto-respawn countdown MobaCombatant.tick()
## drives through tick_respawn_countdown()).
##
## Split out of MobaCombatant to keep that file under the project's
## max-file-lines gate (see .gdlintrc). This is a private implementation
## detail of MobaCombatant, the same way MobaCastTracker and MobaChannelTracker
## are: MobaCombatant.respawn() is still the sole public seam callers use, and
## this class only talks back to its combatant through public methods --
## several of which (documented below) exist solely for this handler to call.
class_name MobaDeathHandler
extends RefCounted

## The combatant this handler belongs to.
var _combatant: MobaCombatant = null

## True once death has already fired for the combatant's current life. Reset
## by respawn() so death can fire again in the next life.
var _has_died: bool = false

## Countdown timer for auto-respawn while DEAD. Only decrements if the policy
## allows auto-respawn. Advanced by tick_respawn_countdown(), which
## MobaCombatant.tick() calls only while the sibling state machine reports DEAD.
var _respawn_countdown: float = 0.0

## material_override captured by _apply_death_visual() before darkening, so
## _restore_death_visual() can put back exactly what was there (possibly null).
## _has_cached_material_override distinguishes "cached null" from "nothing cached".
var _cached_material_override: Material = null
var _has_cached_material_override: bool = false


func _init(p_combatant: MobaCombatant) -> void:
	_combatant = p_combatant


## True once death has fired for the combatant's current life.
func has_died() -> bool:
	return _has_died


## Clear all active effects, modifiers, shields, crowd control, and displacement
## when entering DEAD state. Also cancels in-progress casts and breaks
## in-progress channels, and applies the minimal death visual.
##
## Called exactly once when death is finalized (from MobaCombatant._update_health(),
## only after the DEAD state transition itself succeeds) to ensure nothing
## carries into the next life.
func clear_on_death() -> void:
	_has_died = true

	if _combatant.is_casting():
		_combatant.cancel_cast()

	if _combatant.is_channeling():
		_combatant.break_channel()

	_combatant.clear_all_active_effects()
	_combatant.notify_shield_changed()

	_apply_death_visual()


## Restore the combatant from DEAD to full health/resource and clear all
## cooldowns. Moves the body to the policy's spawn point and returns to IDLE.
##
## Returns false if not currently DEAD (no state change); this is the only
## refusal condition. If no respawn_policy is assigned, or its spawn_point is
## null, the body is left at its current transform instead of being moved --
## respawn_policy separately gates *auto*-respawn eligibility in
## tick_respawn_countdown(), so a manually-triggered respawn() with no
## assigned policy is a no-op-in-place, not a refusal.
##
## Called automatically after a delay if respawn_policy.respawns is true; can
## also be called manually regardless of policy.
func respawn() -> bool:
	if not _combatant.is_dead():
		return false

	# Restore health/resource to maximum and clear cooldowns
	_combatant.restore_to_full()
	_combatant.clear_all_cooldowns()

	# Clear any leftover effects/shields/CC (defensive; clear_on_death() should
	# have already done this, but be thorough here in case of edge cases)
	_combatant.clear_all_active_effects()

	# Move the body to the spawn point, if a policy with one is assigned.
	# With no policy or no spawn_point, the body stays at its current transform.
	var policy := _combatant.respawn_policy
	if policy != null and policy.spawn_point != null:
		var parent := _combatant.get_parent()
		if parent != null:
			var body := parent.get_node_or_null("Body") as Node3D
			if body != null:
				body.transform = policy.spawn_point.transform

	# Reset death flag to allow death to fire again in the next life
	_has_died = false

	# Reset respawn countdown for next death
	_respawn_countdown = 0.0

	# Restore the visual representation (remove the darkened death appearance)
	_restore_death_visual()

	# Emit health/resource/shield changed signals to update HUD, and mirror
	# to the parent Actor's character sheet.
	_combatant.notify_health_and_resource_changed()
	_combatant.notify_shield_changed()
	_combatant.sync_character_sheet_hp()

	# Transition to IDLE
	return _combatant.revive_state()


## Advance the auto-respawn countdown. Only called from MobaCombatant.tick()
## while the sibling state machine already reports DEAD; triggers respawn()
## when the countdown expires if the respawn policy permits auto-respawn.
func tick_respawn_countdown(delta: float) -> void:
	# Only count down if the policy exists and allows auto-respawn
	var policy := _combatant.respawn_policy
	if policy == null or not policy.respawns:
		return

	# Initialize countdown on first tick in DEAD state
	if _respawn_countdown == 0.0:
		_respawn_countdown = policy.respawn_delay

	# Decrement and trigger respawn when done
	_respawn_countdown -= delta
	if _respawn_countdown <= 0.0:
		respawn()


## Apply minimal visual death representation to the body.
##
## Mutates material_override, not a surface override material: ActorBody3D._ready()
## assigns material_override for placeholder meshes (both player.tscn's and
## enemy.tscn's bare CapsuleMesh), and material_override always wins over a
## surface override material in Godot's rendering priority, so a surface
## override alone would be a silent no-op on those bodies.
func _apply_death_visual() -> void:
	var mesh_instance := _get_body_mesh_instance()
	if mesh_instance == null:
		return

	# Cache whatever is set right now (possibly null, for a body with no
	# override) so _restore_death_visual() can put back exactly this later.
	_cached_material_override = mesh_instance.material_override
	_has_cached_material_override = true

	# Fall back to the mesh's own active material (surface material) when
	# there is no override yet, so a real imported model without a placeholder
	# override still darkens; get_active_material() already accounts for any
	# override, so this only differs from material_override when it is null.
	var source_material: Material = mesh_instance.material_override
	if source_material == null:
		source_material = mesh_instance.get_active_material(0)
	if source_material == null or not (source_material is StandardMaterial3D):
		return

	# Create a unique material instance for this body so we don't affect other actors
	var darkened := (source_material as StandardMaterial3D).duplicate() as StandardMaterial3D
	# Darken the albedo color significantly to show death
	darkened.albedo_color = darkened.albedo_color * Color(0.3, 0.3, 0.3, 1.0)
	mesh_instance.material_override = darkened


## Restore the visual representation when respawning (restore full color).
func _restore_death_visual() -> void:
	var mesh_instance := _get_body_mesh_instance()
	if mesh_instance == null:
		return

	if _has_cached_material_override:
		mesh_instance.material_override = _cached_material_override
		_has_cached_material_override = false


## The Body's MeshInstance3D, or null if the Body or the mesh child is missing.
func _get_body_mesh_instance() -> MeshInstance3D:
	var parent := _combatant.get_parent()
	if parent == null:
		return null

	var body := parent.get_node_or_null("Body") as Node3D
	if body == null:
		return null

	return body.get_node_or_null("MeshInstance3D") as MeshInstance3D
