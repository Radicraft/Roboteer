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
