extends "res://bot/weapons/full_body_spinner.gd"
## Vortex spinner (brief v5 section 9.5, Level 95, wave P agent D1).
##
## The last weapon on the ladder, and it is the Level 78 full body spinner with
## its teeth raked over: same ring, same handover from the hull, same no weak
## side, same terrible controllability. Read `full_body_spinner.gd` first; every
## word of it applies here, and this file is only the difference.
##
## THE DIFFERENCE IS ONE VECTOR. The full body spinner spends its bite along the
## ring's tangent with the vertical component thrown away (`_tangential` zeroes
## y), because a flat bar hits sideways. The vortex's teeth are raked, so the same
## bite leaves along the tangent AND upward, in the `lift` proportion from the
## catalogue: 0.45 means a little under half of the blow goes into getting the
## other machine off the floor. A machine in the air is not driving, is not
## weapon-facing and lands where the arena puts it, which at Level 95 is worth
## more than the extra condition a bigger number in the `impulse` column would
## have bought.
##
## The catalogue does both anyway: `impulse` 250 against 200, `spin_up_s` 3.2
## against 3.5, `control_penalty` 0.55 against 0.5 (a shade more of your driving
## survives the spin), 32 kg against 30. It is dearer, heavier and better, and the
## weight is the thing that keeps it honest: on a Shell only a 2wd or a 4wd fits
## underneath it inside the 100 kg budget.
##
## The recoil goes the other way too, and that is deliberate rather than
## incidental: `_spend_hit` shoves the wielder along minus the bite direction, so
## a vortex throwing its opponent up presses ITSELF down, and a spinning vortex
## grips the floor slightly harder each time it connects.
##
## This one is not welded to the Shell the way the full body spinner is: the
## catalogue gives it no `requires_chassis`, and the hulls that list it in
## `weapons_allowed` are the Shell and, at Level 100, the Apex.


## How much of each bite goes straight up. Nought is the full body spinner's flat
## hit; one would be a vertical spinner that happens to be a ring.
func lift() -> float:
	return clampf(float(spec.get("lift", 0.45)), 0.0, 1.0)


## The direction one bite leaves in. The parent works out the flat tangent at the
## contact point and refuses hits that are too slow to matter (Vector3.ZERO); the
## rake tilts whatever survives that test upward.
func _tangential(point: Vector3) -> Vector3:
	var flat: Vector3 = super(point)
	if flat == Vector3.ZERO:
		return flat
	var raked := flat * (1.0 - lift()) + Vector3.UP * lift()
	if raked.length_squared() < 0.000001:
		return flat
	return raked.normalized()


## NO WEAK SIDE IS THE HULL'S TRICK, NOT THE WEAPON'S, and this is the one place
## the vortex has to be stricter than its parent.
##
## `full_body_spinner.gd` takes the armour panels out of the collision world above
## 30 percent spin, because on a Shell the ring IS the bodywork: the hull has
## handed its own ring over, shrunk its collision to the hub, and there is
## genuinely nothing for an attacker to reach. The full body spinner can assume
## that, because the catalogue welds it to the Shell with `requires_chassis`.
##
## The vortex has no `requires_chassis`: the Shell and the Apex list it in their
## `weapons_allowed`, and every other hull in the catalogue declares no list at
## all, which in `BuildRules` means "anything fits". So a vortex can be bolted to
## a Wedge, and if it shielded there it would hand a 30 kg wedge the Shell's
## unreachable flanks for nothing. It does not: the faces only leave the world on
## a hull that has actually given up its own ring to this weapon.
##
## Everything else the weapon costs still applies on those hulls: the 32 kg, the
## 3.2 s wind-up and the control penalty are all paid whatever it is bolted to.
func _shield(on: bool) -> void:
	super(on and _hull_gave_up_its_ring())


## True only on a hull that turns its own bodywork into this weapon.
func _hull_gave_up_its_ring() -> bool:
	if bot == null:
		return false
	var hull: ChassisBase = bot.chassis_module
	if hull == null or not hull.has_method("has_own_ring"):
		return false
	return not bool(hull.call("has_own_ring"))


func status_text() -> String:
	if jammed:
		return "JAMMED"
	return "VORTEX %d%%" % int(round(readiness() * 100.0))
