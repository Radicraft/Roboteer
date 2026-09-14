extends ChassisBase
## Long and Low: a stretched wedge with a ramp at BOTH ends, so it is as hard to
## get under from behind as from the front. Long wheelbase, so it turns badly
## (catalogue `turn_rate_factor` 0.7) and resists being flipped (`flip_resistance`
## 1.6).

const DECK_X := 0.35
const LIP_TOP_DROP := 0.035


func com_x() -> float:
	return -0.05


func levels() -> Array:
	return [
		{"y": floor_y(), "hx": half_len(), "hz": half_wid()},
		{"y": floor_y() + LIP_TOP_DROP, "hx": half_len(), "hz": half_wid()},
		{"y": top_y(), "hx": DECK_X, "hz": half_wid()},
	]


func front_lip_point() -> Vector3:
	return Vector3(half_len(), floor_y(), 0.0)


## Both ends ramp, so a front weapon rests along the front one.
func weapon_rest_angle() -> float:
	return atan2(floor_y() + LIP_TOP_DROP - top_y(), half_len() - DECK_X)
