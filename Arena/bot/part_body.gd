class_name BotPart extends RigidBody3D
## One rigid body of a bot: chassis, wheel, flipper arm or armour plate.
## Its only job beyond being a body is to read contact impulses inside the
## physics step and hand them to the owning Bot, which owns the damage model
## (docs/stage3-spec.md §6). Nothing is mutated here, so this is safe to run
## from `_integrate_forces`.

## Back pointer to the owning Bot. Untyped to avoid a cyclic class dependency.
var owner_bot: Node = null
## "wheel_fl", "armour_top", "weapon", "chassis"
var part_key: String = ""
## BREAK_MIN / BREAK_MAX row: "wheel" | "weapon" | "armour" | "chassis"
var part_kind: String = ""
var material_name: String = "steel"
var detached: bool = false
## Destroyed in an EARLIER fight, so never fitted to this one: out of the physics
## world and invisible, rather than shed onto the arena floor as debris.
## See `Bot._retire_part`.
var retired: bool = false
## Set by the yard's hazard area while the spikes are up and touching this part.
var hazard_contacts: int = 0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if detached or owner_bot == null:
		return
	var count := state.get_contact_count()
	if count == 0:
		return
	# Jolt reports one impulse per contact POINT. A box landing flat produces
	# four of them, so a single blow would read as four small taps. Sum them per
	# collider before the damage model sees the hit, which is what the
	# FightTypes thresholds are calibrated against.
	var ids: Array[int] = []
	var objects: Array = []
	var sums: Array[float] = []
	var spots: Array[Vector3] = []
	for i in range(count):
		var obj := state.get_contact_collider_object(i)
		var id := obj.get_instance_id() if obj != null else 0
		var slot := ids.find(id)
		if slot < 0:
			ids.append(id)
			objects.append(obj)
			sums.append(0.0)
			spots.append(Vector3.ZERO)
			slot = ids.size() - 1
		sums[slot] += state.get_contact_impulse(i).length()
		spots[slot] = state.get_contact_local_position(i)
	for slot in range(ids.size()):
		owner_bot.report_contact(self, objects[slot], sums[slot], spots[slot])
