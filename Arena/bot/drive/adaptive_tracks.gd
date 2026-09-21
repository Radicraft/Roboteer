extends "res://bot/drive/tracks.gd"
## Adaptive tracks (brief v5 section 9.5, Level 85): tracks that turn like wheels
## and cannot be torn off.
##
## Everything about the build is the Stage 4 track unit's: three road wheels a
## side under a belt skin, one condition key per side, the six wheel slot row. Two
## things change, and they are the two the brief names.
##
## TURNS LIKE WHEELS. Nothing in code: the catalogue gives it a 4WD's `turn_rate`
## of 3.2 against the plain tracks' 1.8, and the arcade steering reads that number.
## It pays for it in top speed and in weight, and it is the dearest drive on the
## ladder.
##
## CANNOT BE TORN OFF. A plain track's belt comes off when its side reaches zero
## condition: that side stops dead, the skin is hidden, and the machine circles for
## the rest of the fight (`DriveBase.side_alive`). The adaptive belt is segmented,
## so a chewed side keeps driving at `belt_floor` of its power and the skin stays on
## the machine. It is still worth chewing (a side at zero costs 60 per cent of that
## side's drive, and it costs the owner the flawless bonus, because the condition
## key really did reach zero) but it can never take the machine's steering away.

## What is left of the drive when both belts are chewed to nothing.
const BELT_FLOOR_DEFAULT := 0.4


func belt_floor() -> float:
	return clampf(float(spec.get("belt_floor", BELT_FLOOR_DEFAULT)), 0.0, 1.0)


## The belt is bolted on in segments. It never frees its road wheels.
func side_alive(_key: String) -> bool:
	return true


## And it never comes off the machine, so the skin stays where it is.
func sheds_visual(_key: String) -> bool:
	return false


## Belt condition scales the power instead of killing a side, which is the whole
## of "cannot be torn off": the machine slows, it never circles.
func power_scale() -> float:
	if bot == null or bot.damage == null:
		return 1.0
	var total := 0.0
	for key in condition_keys:
		total += clampf(bot.damage.value_for(str(key)), 0.0, 1.0)
	var belt := total / float(maxi(condition_keys.size(), 1))
	var drive_condition := clampf(float(bot.damage.condition["drive"]), 0.15, 1.0)
	return lerpf(belt_floor(), 1.0, belt) * drive_condition
