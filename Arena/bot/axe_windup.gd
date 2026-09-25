class_name AxeWindup extends Node
## The axe's wind-back (combat feel, owner decision 2026-09-24 D5: "Axe wind-up: visual
## only, no balance change"). PRESENTATION ONLY, in the same spirit as PartAnim: it turns
## the axe's imported MODEL about the hinge, never the physics arm, never a shape, never a
## force, and it runs on `_process`. The strike still starts on the press, on the same tick,
## with the same motor, so no fight changes.
##
## How it reads as anticipation without lying about the hitbox: the physics arm needs most
## of its 0.15 s window to get the 9 kg arm moving (axe.gd, phase 2 notes), so for the first
## few frames the head has hardly left the cocked pose. The model is lifted BACK over those
## frames (a hitch up, peaking at WINDUP_PEAK_S) and eased onto the real arm by WINDUP_S,
## well before the head can reach anything. From then on the picture is the physics.

## How far back the head lifts, at the peak, in degrees.
const WINDUP_DEG := 22.0
## When the lift peaks, and when the model is back on the arm, seconds after the press.
const WINDUP_PEAK_S := 0.04
const WINDUP_S := 0.11

var _model: Node3D = null
var _rest := Transform3D.IDENTITY
## The hinge in the model's parent's space (the arm body's), and the hinge axis there.
var _hinge := Vector3.ZERO
var _t: float = -1.0


func configure(model: Node3D, hinge_in_parent: Vector3) -> void:
	_model = model
	_rest = model.transform
	_hinge = hinge_in_parent


## The press. Called from the axe's fire; it only starts a presentation clock.
func trigger() -> void:
	_t = 0.0


## The lift, in degrees, `t` seconds after the press. Rises to WINDUP_DEG at WINDUP_PEAK_S,
## falls back to exactly 0 at WINDUP_S, and is 0 outside [0, WINDUP_S].
static func angle_at(t: float) -> float:
	if t <= 0.0 or t >= WINDUP_S:
		return 0.0
	if t <= WINDUP_PEAK_S:
		var up := t / WINDUP_PEAK_S
		return WINDUP_DEG * (1.0 - (1.0 - up) * (1.0 - up))
	var down := (t - WINDUP_PEAK_S) / (WINDUP_S - WINDUP_PEAK_S)
	return WINDUP_DEG * (1.0 - down * down * (3.0 - 2.0 * down))


func is_winding() -> bool:
	return _t >= 0.0 and _t < WINDUP_S


func _process(delta: float) -> void:
	if _t < 0.0 or _model == null or not is_instance_valid(_model):
		return
	_t += delta
	var angle := deg_to_rad(angle_at(_t))
	# Positive about BACK is head UP in the arm's frame (axe.gd's sign convention).
	var turn := Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO)
	var about := Transform3D(Basis(), _hinge) * turn * Transform3D(Basis(), -_hinge)
	_model.transform = about * _rest
	if _t >= WINDUP_S:
		_model.transform = _rest
		_t = -1.0
