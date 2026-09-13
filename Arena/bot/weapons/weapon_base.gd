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


## Build bodies and joints. `socket` is the chassis socket transform in the bot's local frame
## (chassis sockets: "front" for floor-level weapons, "top" for overhead ones, "shell" for the
## full-body spinner). Register every body with `bot.register_part(body, part_key, part_kind, mass)`
## where part_kind is "weapon"; the bot then owns detach, damage and freeze for it.
func build(owner: Node, socket: Transform3D, weapon_spec: Dictionary, random: RandomNumberGenerator) -> void:
	bot = owner
	spec = weapon_spec
	kind = str(weapon_spec.get("kind", ""))
	rng = random
	_build()


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
