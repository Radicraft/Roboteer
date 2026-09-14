extends ChassisBase
## The Pyramid: symmetric about the axle plane, so it reads and drives identically
## either way up. Four faces slope up to a flat top and four down to a flat bottom.
##
## Because it is symmetric, its hull reaches 0.13 m either side of the axle plane
## against a standard 0.11 m wheel, which would leave it resting on its own belly.
## Spec section 3's rule for an invertible chassis is that the wheels protrude both
## ways, so this one asks for a larger wheel and the whole bot rides that much
## higher. That is the price of never needing a srimech.

## The exported hull reaches 0.162 m either side of the axle plane (the edge rails
## and the bolted hatches stand proud of the catalogue's 0.13 m half height), so
## the wheel has to clear that, not just the collision hull.
const HALF_HEIGHT_MARGIN := 0.04
## The waist is the catalogue footprint in X and a little narrower in Z, matching
## the exported hull (the wheels stand proud of it by design).
const WAIST_Z := 0.334
const CAP_X := 0.25
const CAP_Z := 0.21


func half_height() -> float:
	return height() * 0.5


func floor_y() -> float:
	return -half_height()


func top_y() -> float:
	return half_height()


func com_x() -> float:
	return -0.02


func wheel_radius_min() -> float:
	return half_height() + HALF_HEIGHT_MARGIN


func levels() -> Array:
	return [
		{"y": -half_height(), "hx": CAP_X, "hz": CAP_Z},
		{"y": 0.0, "hx": half_len(), "hz": WAIST_Z},
		{"y": half_height(), "hx": CAP_X, "hz": CAP_Z},
	]


func front_lip_point() -> Vector3:
	return Vector3(half_len(), 0.0, 0.0)
