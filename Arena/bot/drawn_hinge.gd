class_name DrawnHinge extends Node
## Fitment pass 2 (docs/wave-d-fitment2-notes.md, decisions 2026-09-30 §9: "flippers and
## lifters get a drawn slot or a limited drawn stroke on flat noses (Apex first) so the arm
## never passes through the hull"). PRESENTATION ONLY, in the spirit of AxeWindup: it moves
## the arm's imported MODEL, never the physics arm, a shape, a joint or a force, and runs on
## `_process`, so no fight changes.
##
## On a flat nose the physics hinge sits inside the nose (the Apex's 83 mm behind its face,
## the Pyramid's 100 mm), so the drawn arm's root was buried in the hull at rest and swung
## up through the front plate and the hull's front edge on every stroke. A limited stroke
## was measured and does not help: any turn at all about that hinge sweeps more hull (the
## Box's arm meets its plate in the first 4 degrees). So the DRAWN hinge stands in front of
## the nose, `shift` ahead of the physics one, and the drawn arm turns about it by exactly
## the angle the physics arm has turned. The drawn arm is the physics arm moved forward by
## `shift` at rest and a little less than that at full stroke.

var model: Node3D = null
var body: Node3D = null
var chassis: Node3D = null
## The arm body and the model at rest, in the chassis' frame.
var rest_body := Transform3D.IDENTITY
var rest_model := Transform3D.IDENTITY
## The drawn hinge and the shift, in the chassis' frame.
var hinge := Vector3.ZERO
var shift := Vector3.ZERO
var _last := Transform3D.IDENTITY


func _process(_delta: float) -> void:
	if model == null or body == null or chassis == null:
		return
	if not is_instance_valid(model) or not is_instance_valid(body) or not is_instance_valid(chassis):
		return
	if bool(body.get("detached")) or not body.is_inside_tree() or not chassis.is_inside_tree():
		return
	var rel := chassis.global_transform.affine_inverse() * body.global_transform
	if rel.is_equal_approx(_last):
		return
	_last = rel
	model.transform = pose(rel)


## The model's local transform for the arm body at `rel` (chassis frame).
func pose(rel: Transform3D) -> Transform3D:
	var turn := rel.basis * rest_body.basis.inverse()
	var about := Transform3D(turn, hinge - turn * hinge)
	var desired := about * Transform3D(Basis.IDENTITY, shift) * rest_body * rest_model
	return rel.affine_inverse() * desired
