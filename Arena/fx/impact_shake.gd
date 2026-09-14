class_name ImpactShake extends Node
## Camera kick. A hit that shakes the frame is most of what makes a heavy weapon
## feel heavy, and it is the one piece of impact feel that cannot live inside the
## FX tree, because the camera is C's.
##
## So this is a SOURCE, not an effect: it accumulates trauma, decays it, and offers
## a positional offset. The camera rig reads it and decides what to do with it. If
## the FX tree is deleted, the group lookup finds nothing and the rig runs exactly
## as it does today, which keeps the "deleting Arena/fx changes nothing" rule true.
##
## HOW THE RIG READS IT (for C / R, nothing in Arena/ui needs to change until then):
##
##     # once, in CameraRig._ready()
##     _shake = get_tree().get_first_node_in_group(ImpactShake.GROUP)
##
##     # in CameraRig._process, at the three places that currently end with
##     #   _camera.transform = Transform3D.IDENTITY
##     var kick := Vector3.ZERO
##     if _shake != null and is_instance_valid(_shake):
##         kick = _shake.offset()
##     _camera.transform = Transform3D(Basis(), kick)
##
## The offset is in the CAMERA's local space (x right, y up, z toward the viewer),
## so it works at any yaw, pitch and zoom, and because it is on the Camera3D child
## rather than the rig it cannot disturb the rig's own look_at.
##
## Trauma model (Squirrel Eiserloh's, the one everybody uses): kick() ADDS trauma,
## trauma decays linearly, and the shake is trauma SQUARED. Squaring is the whole
## trick: two light hits in a row barely register, one heavy hit is unmistakable,
## and the shake tails off smoothly instead of stopping dead.

## Group the camera rig looks this up by, so neither node has to know the other.
const GROUP := "roboteer_impact_shake"

## Metres of camera travel at full trauma. The fight camera sits 3 to 6 m out, so
## 7 cm is a firm shove and not a earthquake; anything past about 12 cm starts to
## look like the camera came loose.
const MAX_OFFSET := 0.07
## Trauma per second shed. A single heavy kick is visibly over in about 0.4 s.
const DECAY_PER_S := 2.6
## Three incommensurate frequencies per axis, so the motion never repeats and never
## reads as a sine wave.
const FREQ := [27.0, 19.0, 13.0]
const AXIS_PHASE := [0.0, 2.1, 4.2]

var trauma: float = 0.0
var _t: float = 0.0
var _seed: float = 0.0
var _offset := Vector3.ZERO


func _ready() -> void:
	add_to_group(GROUP)
	_seed = randf() * 100.0
	set_process(false)   # FightFx steps us on its presentation clock


## Something hit something. strength 0..1; anything bigger is clamped, because a
## 30 hit pile-up must not be able to shake the camera off the arena.
func kick(strength: float) -> void:
	trauma = clampf(trauma + clampf(strength, 0.0, 1.0), 0.0, 1.0)


## Advance the shake. FightFx passes its presentation delta, so a headless test can
## step this at a fixed rate like the rest of Arena/fx.
func step(delta: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	if trauma <= 0.0:
		if _offset != Vector3.ZERO:
			_offset = Vector3.ZERO
		return
	trauma = maxf(0.0, trauma - DECAY_PER_S * delta)
	var shake := trauma * trauma
	var amp := MAX_OFFSET * shake
	# limit_length, not three independent axes: each axis peaks at 1, so an unclamped
	# vector can reach sqrt(2.12) x amp when all three happen to peak together, and
	# MAX_OFFSET would then be a per-axis bound rather than the travel bound it claims
	# to be. Measured 0.0738 m against a stated 0.0700 before this line existed.
	_offset = Vector3(
		_wave(0),
		_wave(1),
		_wave(2) * 0.35          # less push in and out: it reads as a zoom wobble
	).limit_length(1.0) * amp


## The camera space offset for this frame. Safe to call every frame, from anywhere;
## it returns a cached vector and does no work.
func offset() -> Vector3:
	return _offset


func reset() -> void:
	trauma = 0.0
	_offset = Vector3.ZERO


func _wave(axis: int) -> float:
	var f: float = FREQ[axis]
	var p: float = AXIS_PHASE[axis] + _seed
	return sin((_t * f + p) * TAU) * 0.72 + sin((_t * f * 0.37 + p * 1.7) * TAU) * 0.28
