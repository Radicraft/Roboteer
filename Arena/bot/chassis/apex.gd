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


func com_x() -> float:
	return -0.03


func levels() -> Array:
	return [
		{"y": floor_y(), "hx": half_len() - UNDERCUT, "hz": half_wid() - UNDERCUT},
		{"y": floor_y() + LIP_Y, "hx": half_len(), "hz": half_wid()},
		{"y": top_y() - SHOULDER_DROP, "hx": half_len(), "hz": half_wid()},
		{"y": top_y(), "hx": DECK_X, "hz": half_wid() * DECK_Z_FRACTION},
	]


## The lowest, furthest forward point of the hull. It sits inboard of the waist,
## which is what the undercut means.
func front_lip_point() -> Vector3:
	return Vector3(half_len() - UNDERCUT, floor_y(), 0.0)
