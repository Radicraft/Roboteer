class_name FxLightPool extends Node3D
## A pool of very short lived point lights. A severe hit does not just make sparks,
## it briefly LIGHTS the two bots and the floor under them, and that one frame of
## thrown light is most of the difference between an impact that reads as an event
## and an impact that reads as a decal.
##
## Deliberately tiny: 4 lights, 0.15 s each, no shadows, a range of about a metre.
## Shadowless omnis are close to free on the Mobile renderer at this count, and 4 is
## the cap precisely so a pile-up cannot quietly turn into a lighting cost.
##
## Presentation only; stepped by FightParticles on FightFx's clock.

const POOL := 4
const LIFE_S := 0.15
const RANGE := 1.2
const EASE := 1.8          # energy falls off faster than linear, so it snaps

var _lights: Array[OmniLight3D] = []
var _age := PackedFloat32Array()
var _peak := PackedFloat32Array()
var _alive := PackedByteArray()
var _next: int = 0
var _live: int = 0
var _colour := Color(1.0, 0.86, 0.62)


func _ready() -> void:
	_age.resize(POOL)
	_peak.resize(POOL)
	_alive.resize(POOL)
	for i in POOL:
		var l := OmniLight3D.new()
		l.name = "Pop%d" % i
		l.light_color = _colour
		l.light_energy = 0.0
		l.light_specular = 0.6
		l.omni_range = RANGE
		l.shadow_enabled = false      # 4 shadow maps for 150 ms would be absurd
		l.visible = false
		add_child(l)
		_lights.append(l)
		_alive[i] = 0
	set_process(false)


## Pop one. `energy` is the peak light energy; `range_m` its reach.
func pop(at: Vector3, energy: float, range_m: float = RANGE) -> void:
	var i := _next
	_next = (_next + 1) % POOL
	var l := _lights[i]
	l.global_position = at
	l.omni_range = range_m
	l.light_energy = energy
	l.visible = true
	if _alive[i] == 0:
		_live += 1
	_age[i] = 0.0
	_peak[i] = energy
	_alive[i] = 1


func step(delta: float) -> void:
	if _live <= 0 or delta <= 0.0:
		return
	for i in POOL:
		if _alive[i] == 0:
			continue
		_age[i] += delta
		var t: float = _age[i] / LIFE_S
		if t >= 1.0:
			_alive[i] = 0
			_live -= 1
			_lights[i].light_energy = 0.0
			_lights[i].visible = false
			continue
		_lights[i].light_energy = _peak[i] * pow(1.0 - t, EASE)


## --- introspection, used by Arena/tests/fx_test.gd -------------------------

func pool_size() -> int:
	return POOL


func live_count() -> int:
	return _live
