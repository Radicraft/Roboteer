extends ChassisBase
## The Apex (brief v5 section 9.5, Level 100): the last hull on the ladder. Every
## weapon fits it, and it is the hardest thing in the catalogue to flip or to tip.
##
## What it is NOT is free. At 48 kg it is the heaviest hull in the game, half the
## weight budget before a drive, a weapon, a srimech or a gram of armour, so the
## machine built on one is a light armoured machine or a light weaponed one. That
## is the whole balance of it: the Apex buys you every weapon in the catalogue and
## a hull that stays on its wheels, and it charges the build for both.
##
## The profile. A full width waist with a lip at the bottom that pulls IN rather
## than out, so the lowest edge of the hull overhangs the floor line and a wedge
## climbing it meets an undercut instead of a ramp (catalogue `hard_to_get_under`).
## A long flat deck above it takes an overhead weapon, and the low centre of mass
## (0.065 m off the floor, the lowest in the catalogue) is what the 1.9 flip
## resistance and the 1.5 tip resistance are made of.
##
## It is not invertible: it needs a srimech, which is one of its two utility slots
## gone, and it is the reason a Pyramid is still worth owning at Level 100.
##
## MESHES (agent E): see the request in docs/wave-p-d2-notes.md. Until the .glb
## lands the hull is the lofted profile below, which is also its collision.

## The bottom lip, and how far it pulls in under the waist.
const LIP_Y := 0.03
const UNDERCUT := 0.04
## The top deck, shorter and narrower than the waist so the roof is not a target.
const DECK_X := 0.42
const DECK_Z_FRACTION := 0.86
const SHOULDER_DROP := 0.04

## What is left of the hull once a full body spinner has taken the bodywork over.
## The waist's far corner is sqrt(0.5^2 + 0.35^2) = 0.610 m from the middle and the
## two fbs weapons reach 0.45 m and 0.48 m, so a full size Apex would stand proud of
## its own ring at all four corners and an attacker would meet the hull first. At
## this fraction the corner comes in to 0.390 m, inside the shorter of the two
## rings with 0.06 m to spare, all the way round. Same handover as the Shell's, on
## a hull that has no separate ring mesh to hide: it pulls the whole body in
## instead.
const CORE_FRACTION := 0.64


func com_x() -> float:
	return -0.03


## The hull keeps its bodywork unless a full body spinner is actually going to take
## it over, which is the Shell's rule (`chassis/shell.gd`) on a different shape.
## The test is the catalogue KIND, so both `full_body_spinner` and the Level 95
## `vortex_spinner` take it; and it is conditional on the weapon's module existing,
## because while it does not the Bot fits an inert plate and a hull that had already
## pulled itself in would be a 0.39 m core with nothing round it.
##
## Without this the Apex kept its full body, the spinner built its ring at the front
## socket, and `vortex_spinner._shield()` correctly refused to take the armour faces
## out of the world (wave P, agent D1's note). With it, the Apex is the second hull
## in the game whose bodywork IS the weapon.
func has_own_ring() -> bool:
	var weapon_id := str(config.get("weapon", ""))
	if str(PartsCatalogue.weapon(weapon_id).get("kind", "")) != "fbs":
		return true
	return not ResourceLoader.exists("res://bot/weapons/%s.gd" % weapon_id)


## The lofted profile. It was both the collision hull and the silhouette until
## agent E's `apex.glb` landed; it is now the collision hull only, and
## `_on_model_bound` at the bottom of this file keeps the model in step with it.
## Pulled in to the core when the ring has it.
func levels() -> Array:
	var f := 1.0 if has_own_ring() else CORE_FRACTION
	return [
		{"y": floor_y(), "hx": (half_len() - UNDERCUT) * f, "hz": (half_wid() - UNDERCUT) * f},
		{"y": floor_y() + LIP_Y, "hx": half_len() * f, "hz": half_wid() * f},
		{"y": top_y() - SHOULDER_DROP, "hx": half_len() * f, "hz": half_wid() * f},
		{"y": top_y(), "hx": DECK_X * f, "hz": half_wid() * DECK_Z_FRACTION * f},
	]


## The lowest, furthest forward point of the hull. It sits inboard of the waist,
## which is what the undercut means, and comes in with the rest of the body when a
## full body spinner owns the bodywork.
func front_lip_point() -> Vector3:
	var f := 1.0 if has_own_ring() else CORE_FRACTION
	return Vector3((half_len() - UNDERCUT) * f, floor_y(), 0.0)


## AGENT E (wave P), and the only lines in this file that are not D2's.
##
## `apex.glb` has landed, so `levels()` above is no longer the silhouette: it is
## the collision hull only, and `ChassisBase._build_visual` draws the model
## instead. That means the CORE_FRACTION pull-in stopped being visible the moment
## the art arrived -- the body would have shrunk to 0.39 m while the model stayed
## at full size, so an Apex under a vortex spinner would have stood proud of its
## own ring at all four corners with nothing solid behind the overhang.
##
## The model is scaled by the same factor, which is what `shell.gd` does at this
## same hook for the same reason (it hides its ring mesh; this hull has no
## separate ring to hide, so it pulls the whole body in exactly as `levels()`
## does). Uniform, so the undercut, the catch rail and the deck keep their
## proportions; `PartVisuals.bind` already divides the texel density measurement
## by a node's own scale, so the materials do not coarsen with it.
func _on_model_bound() -> void:
	if model == null or has_own_ring():
		return
	model.scale = Vector3.ONE * CORE_FRACTION
