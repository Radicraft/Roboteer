extends DriveBase
## Six wheels: heavy, best pushing, and redundant. The catalogue promises "two
## losses before it shows", so the power scale only starts falling after the
## second wheel is gone instead of dropping a sixth at a time.

const REDUNDANT_LOSSES := 2


func alive_fraction() -> float:
	var usable := float(maxi(wheels.size() - REDUNDANT_LOSSES, 1))
	return clampf(float(alive_count()) / usable, 0.0, 1.0)
