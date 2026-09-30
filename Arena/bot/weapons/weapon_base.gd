class_name WeaponBase extends RefCounted
## Contract for every primary weapon (docs/stage4-spec.md §4). One instance per bot, created by
## bot.gd from the catalogue entry `parts.weapon[<id>]`. A weapon builds its own bodies and joints,
## registers them with the bot, and drives them from the physics tick. It never touches the scene
## tree outside the bot, never reads the other bot directly (use `bot.opponent_relative`), and
## draws randomness only from the rng it was given.

var bot: Node = null            # the owning Bot
var spec: Dictionary = {}       # the catalogue row
var kind: String = ""           # spec["kind"]: spinner|drum|flipper|lifter|crusher|axe|saw|ram|flame|fbs
var jammed: bool = false
var charges: int = -1           # -1 = unlimited
var rng: RandomNumberGenerator = null
## Stage 4 additions, set by the Bot before `build()` and by `build()` itself, so a
## weapon never has to work out where it is or what it weighs.
## `socket` is the chassis socket in the bot's local frame; `mass_kg` is the
## catalogue weight at the simulation's mass scale, to share across this weapon's
## bodies.
var socket: Transform3D = Transform3D.IDENTITY
var mass_kg: float = 4.0


## Build bodies and joints. `socket` is the chassis socket transform in the bot's local frame
## (chassis sockets: "front" for floor-level weapons, "top" for overhead ones, "shell" for the
## full-body spinner). Register every body with `bot.register_part(body, part_key, part_kind, mass)`
## where part_kind is "weapon"; the bot then owns detach, damage and freeze for it.
func build(owner: Node, socket_at: Transform3D, weapon_spec: Dictionary, random: RandomNumberGenerator) -> void:
	bot = owner
	socket = socket_at
	spec = weapon_spec
	kind = str(weapon_spec.get("kind", ""))
	rng = random
	_build()


## Where this weapon mounts, in the bot's local frame.
func socket_transform() -> Transform3D:
	return socket


## The simulated mass of this weapon's bodies in total.
func mass() -> float:
	return mass_kg


## Ground clearance for an arm that has to get UNDER the other machine: Stage 3's
## measured 0.025 m, which is below an opponent's 0.033 m underside and above the
## wedge lip, and far enough off the floor that the arm never becomes a third
## ground contact (the pogo trap, docs/stage3-physics-notes.md section 5).
const ARM_TIP_CLEAR := 0.025
## Never pitch an arm further down than this, whatever the socket height says.
const ARM_MAX_PITCH := deg_to_rad(45.0)


## The angle a floor working arm (the flipper's, the lifter's forks) has to rest at
## for its tip to sit `ARM_TIP_CLEAR` above the arena floor.
##
## On a hull with a front ramp this IS the ramp angle and nothing changes: the
## wedge and the Long/Low take exactly the path they always took, and the flipper's
## signed off tuning is untouched.
##
## On a FLAT NOSED hull `weapon_rest_angle()` is zero, so the arm used to lie level
## at whatever height the .glb put the front socket, and measured 2026-09-16 that
## is 0.105 m above the floor on a Box, 0.150 m on a Tall Tank and 0.185 m on a
## Pyramid, against an opponent's underside at 0.02 to 0.06 m. The arm could not
## get under anything in the game: five seconds of driving into a machine with the
## button held threw it exactly 0.00 m on all three hulls, while the same weapon on
## a wedge threw it 1.22 m. That is half of "the weapons are not all working once
## built in the workshop", and it is geometry, not tuning.
func ground_rest_angle(arm_length: float) -> float:
	var ramp := 0.0
	if bot != null and bot.chassis_module != null:
		ramp = float(bot.chassis_module.weapon_rest_angle())
	if absf(ramp) > 0.001 or arm_length <= 0.0:
		return ramp
	var floor_y := -float(bot.ride_height()) + ARM_TIP_CLEAR
	var drop := (floor_y - socket_transform().origin.y) / arm_length
	return clampf(asin(clampf(drop, -1.0, 1.0)), -ARM_MAX_PITCH, 0.0)


func _build() -> void:
	pass


## Called by the bot every physics tick BEFORE the step, with the primary button state.
## `pressed` is the level (held), `fired` is the edge (tap). Spinners spin up while held and keep
## spinning; flippers fire on the edge; lifters/crushers move while held; axes fire on the edge.
func apply_input(pressed: bool, fired: bool, dt: float) -> void:
	pass


## Called by the bot every physics tick after apply_input; drive motors, timers, fuel.
func physics_tick(dt: float) -> void:
	pass


## "floor" | "mid" | "high", the CURRENT working height of the business end (HUD readout).
func height_band() -> String:
	return str(spec.get("height_band", "mid"))


## Reach in metres from the socket, for the AI and the readout.
func reach() -> float:
	return float(spec.get("reach", 0.3))


## 0.0 to 1.0 readiness for the AI: spin fraction, gas left, reset progress.
func readiness() -> float:
	return 1.0


## Something the HUD can show next to the weapon button: "SPIN 68%", "GAS 5", "FUEL 12s", "".
func status_text() -> String:
	return ""


## Weapon condition reached zero: stop driving it. Bodies stay attached (a jammed weapon is dead weight).
func set_jammed() -> void:
	jammed = true


## RESULT state: motors off, no further input.
func freeze() -> void:
	jammed = true


## Serialisable state the result needs beyond condition (charges left, fuel left). May be empty.
func state() -> Dictionary:
	return {}


# ---------------------------------------------------------------------------
# Spinner bite sizing (combat feel wave, owner decision D4)
# ---------------------------------------------------------------------------
## Owner decision 2026-09-24: "Spinners: a part takes two or three clean hits (not one)".
## Before this every spinner bite at speed priced out at a whole part (180 N s against a
## wheel that breaks between 18 and 90 N s), so a spinner fight was three or four hits and
## over (docs/wave-a-combat-notes.md section 5 has the before and after numbers).
##
## `raw` is the old severity (0..1, already scaled by spin, because the bite's newtons are
## `impulse x spin`), and a bite is now `raw x cap`: a full-speed bite takes half a part, so a
## clean part goes in two bites at full speed and three when the spinner has not wound back up
## between them (every bite costs spin). The victim's armour material still applies on top in
## `opponent_damage_tick`, exactly as before (titanium three bites, HDPE four).
##
## Tried and dropped: scaling by how squarely the tooth met the face (|travel . contact
## normal|). Jolt's contact normals on a spinning bar or ring were nearly perpendicular to the
## tooth's travel on almost every bite, so it read nearly every hit as a glancing one and a part
## took five bites (docs/wave-a-combat-notes.md section 5).
const SPINNER_BITE := {
	"cap": 0.5,
}


static func spinner_bite(raw: float) -> float:
	return clampf(raw, 0.0, 1.0) * float(SPINNER_BITE["cap"])


# ---------------------------------------------------------------------------
# Fitment pass 2: the drawn hinge on a flat nose (see DrawnHinge)
# ---------------------------------------------------------------------------
## Air between the drawn arm and the nose at every point of the stroke.
const DRAWN_HINGE_CLEAR := 0.006


## On a flat nosed hull, stand the arm MODEL's hinge far enough in front of the nose that
## the drawn arm clears the drawn hull and the front plate from rest to `upper` (radians,
## the joint's top limit). Presentation only: the arm body, its shapes and its joint stay
## where they are. Ramped noses keep theirs: there the arm lies on the ramp.
func draw_hinge_in_front(arm_body: Node3D, model: Node3D, hinge_at: Vector3,
		upper: float) -> void:
	if bot == null or bot.chassis_module == null or bot.chassis == null or model == null:
		return
	if absf(float(bot.chassis_module.weapon_rest_angle())) > 0.001:
		return
	var rest_model_bot: Transform3D = arm_body.transform * model.transform
	var pts := PackedVector3Array()
	var half := 0.0
	for mi in Bot._mesh_instances_under(model):
		if mi.mesh == null:
			continue
		var t := rest_model_bot * _under(mi, model)
		for v in Bot._mesh_points(mi.mesh):
			var p := t * v
			pts.append(p)
			half = maxf(half, absf(p.z))
	if pts.is_empty():
		return
	# The nose's front face at each height: the drawn hull and the front plate's box.
	var face := {}
	for o in _front_obstacles(half + 0.01):
		var k := int(floor(o.y / 0.01))
		face[k] = maxf(float(face.get(k, -INF)), o.x)
	var need := 0.0
	var steps := 12
	for i in range(steps + 1):
		var turn := Basis(Vector3.BACK, upper * float(i) / float(steps))
		for p in pts:
			var q := hinge_at + turn * (p - hinge_at)
			var k := int(floor(q.y / 0.01))
			for kk in [k - 1, k, k + 1]:
				if face.has(kk):
					need = maxf(need, float(face[kk]) + DRAWN_HINGE_CLEAR - q.x)
	if need < 0.004:
		return
	var shift := Vector3(ceilf(need / 0.002) * 0.002, 0.0, 0.0)
	var rest_model := model.transform
	model.transform = Transform3D(Basis.IDENTITY, arm_body.transform.basis.inverse() * shift) \
		* rest_model
	var node := DrawnHinge.new()
	node.name = "DrawnHinge"
	node.model = model
	node.body = arm_body
	node.chassis = bot.chassis
	node.rest_body = arm_body.transform
	node.rest_model = rest_model
	node.hinge = hinge_at + shift
	node.shift = shift
	arm_body.add_child(node)
	arm_body.set_meta("fit_draw_pivot", hinge_at + shift)


## `node`'s transform relative to `ancestor`.
static func _under(node: Node3D, ancestor: Node) -> Transform3D:
	var t := node.transform
	var walk := node.get_parent()
	while walk != null and walk != ancestor:
		if walk is Node3D:
			t = (walk as Node3D).transform * t
		walk = walk.get_parent()
	return t


## Bot-space points of the drawn hull and the front plate's box (plates are built after
## the weapon; a plate is drawn at its box) within `half` of the centre line.
func _front_obstacles(half: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var hull: Node3D = bot.chassis_module.model
	if hull != null:
		for mi in Bot._mesh_instances_under(hull):
			if mi.mesh == null or not mi.visible:
				continue
			var t: Transform3D = bot.call("_relative_to_bot", mi)
			for v in Bot._mesh_points(mi.mesh):
				var p := t * v
				if absf(p.z) <= half and p.x > 0.0:
					out.append(p)
	var socket: Dictionary = bot.chassis_module.armour_socket("front")
	var size: Vector3 = socket["size"]
	for at_variant in socket["transforms"]:
		var at: Transform3D = at_variant
		for i in range(21):
			for z in [-1.0, 0.0, 1.0]:
				out.append(at * Vector3(size.x * 0.5 + 0.004, (float(i) / 20.0 - 0.5) * size.y,
					z * minf(half, size.z * 0.5)))
	return out
