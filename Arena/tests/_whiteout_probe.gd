extends SceneTree
## Probe (not a test): how big and how bright the shared flashes and light pops are on a hit.
## Numbers are for the device (HDR, nominal energies), computed from pool state + texture.
const STEP := 1.0 / 60.0
const A := Vector3(-0.45, 0.25, 0.0)   # attacker chassis
const V := Vector3(0.45, 0.25, 0.0)    # victim chassis
const HIT := Vector3(0.05, 0.3, 0.0)
const EXPOSURE := 0.7
const THRESH := 1.0
var _fx: FightFx
var _profile := PackedFloat32Array()   # radial alpha of spark_glow.png, 0..1 radius, 32 bins

func _initialize() -> void:
	_run()

func _pos(id: String) -> Variant:
	return A if id == "player-1" else V

func _run() -> void:
	await process_frame
	_build_profile()
	_fx = (load("res://fx/fx.tscn") as PackedScene).instantiate() as FightFx
	root.add_child(_fx)
	await process_frame
	_fx.bind(null, _pos)
	_fx.fixed_delta_override = STEP
	var scen := [
		["hit (sev 0.10) + 6 scrap", {"severity": 0.10, "impulse": 30.0, "detached": false}, 6],
		["heavy (sev 0.30) + 15 scrap", {"severity": 0.30, "impulse": 70.0, "detached": false}, 15],
		["smash detach (sev 0.9) + 40 scrap", {"severity": 0.9, "impulse": 200.0, "detached": true}, 40],
	]
	for sc in scen:
		var info: Dictionary = (sc[1] as Dictionary).duplicate()
		info.merge({"attacker": "player-1", "victim": "ai-1", "part": "armour_front", "position": HIT, "tick": 1})
		_fx.on_scrap_awarded("player-1", int(sc[2]), HIT)
		_fx.on_damage_event(info)
		await _measure(str(sc[0]))
	# The flipper's throw path (no weapon lookup: call the connect directly).
	_fx.call("_flipper_connect", "player-1", A + Vector3(0.4, 0, 0))
	await _measure("flipper throw connect")
	quit(0)

func _measure(label: String) -> void:
	var worst_disc := 0.0      # widest single above-threshold disc, m
	var worst_sum_a := 0.0     # summed above-threshold disc area near the victim, m^2
	var worst_sum_att := 0.0   # ... near the attacker
	var peak_light := 0.0
	var peak_light_range := 0.0
	var worst_quad := 0.0
	for f in int(0.9 / STEP):
		await process_frame
		var sum_v := 0.0
		var sum_a := 0.0
		for pool_info in _pools():
			var pool: FxFlashPool = pool_info[0]
			var energy: float = pool_info[1]
			var colour: Color = pool_info[2]
			var alive: PackedByteArray = pool.get("_alive")
			var ages: PackedFloat32Array = pool.get("_age")
			var scales: PackedFloat32Array = pool.get("_scale")
			var tints: PackedColorArray = pool.get("_tint")
			var poss: PackedVector3Array = pool.get("_pos")
			var base: float = pool.get("_size")
			var life: float = pool.get("_life")
			for i in alive.size():
				if alive[i] == 0:
					continue
				var tt: float = ages[i] / life
				if tt >= 1.0:
					continue
				var s: float = pool.call("drawn_size", base * scales[i], tt) if pool.has_method("drawn_size") else base * scales[i] * lerpf(1.0, FxFlashPool.GROW, tt)
				var c: Color = tints[i]
				var a: float = pow(1.0 - tt, FxFlashPool.EASE) * c.a
				var lum := (colour * Color(c.r, c.g, c.b)).get_luminance()
				var peak := energy * lum * a * EXPOSURE
				var r := _disc_radius(peak)
				var d := s * r
				var t := Transform3D(Basis(), poss[i])
				worst_quad = maxf(worst_quad, s)
				worst_disc = maxf(worst_disc, d)
				var area := PI * d * d * 0.25
				if t.origin.distance_to(V) < t.origin.distance_to(A):
					sum_v += area
				else:
					sum_a += area
		worst_sum_a = maxf(worst_sum_a, sum_v)
		worst_sum_att = maxf(worst_sum_att, sum_a)
		var lp: FxLightPool = _fx.particles().light_pool()
		var e := 0.0
		for l in lp.get_children():
			if l is OmniLight3D and (l as OmniLight3D).visible:
				e += (l as OmniLight3D).light_energy
				peak_light_range = maxf(peak_light_range, (l as OmniLight3D).omni_range)
		peak_light = maxf(peak_light, e)
	# The machine's silhouette from the fight camera: 0.8 m long, 0.5 m wide, 0.25 m tall,
	# seen at pitch 50: about 0.8 x (0.5 sin50 + 0.25 cos50) = 0.43 m^2 of screen-facing area.
	var sil := 0.8 * (0.5 * sin(deg_to_rad(50.0)) + 0.25 * cos(deg_to_rad(50.0)))
	print("WHITEOUT %-34s quad max %.2f m | white disc max %.2f m | white area on victim %.3f m2 (%.0f %% of silhouette) | on attacker %.3f m2 (%.0f %%) | light energy %.1f range %.1f m" % [
		label, worst_quad, worst_disc, worst_sum_a, 100.0 * worst_sum_a / sil,
		worst_sum_att, 100.0 * worst_sum_att / sil, peak_light, peak_light_range])
	for i in 60:
		await process_frame

func _pools() -> Array:
	var out := []
	var core: FxFlashPool = _fx.particles().flash_pool()
	out.append([core, FxMaterials.CORE_ENERGY, Color(1.0, 0.98, 0.94)])
	var collect: FxFlashPool = _fx.bolt_shower().flash_pool()
	out.append([collect, FxMaterials.FLASH_ENERGY, FightTypes.BOLT_GOLD])
	return out

## Fraction of the quad's half-size out to which texture alpha x peak stays over threshold.
func _disc_radius(peak: float) -> float:
	var r := 0.0
	for b in _profile.size():
		if _profile[b] * peak > THRESH:
			r = float(b + 1) / float(_profile.size())
	return r

func _build_profile() -> void:
	var tex := FxMaterials.texture("spark_glow.png")
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	_profile.resize(32)
	var counts := PackedInt32Array(); counts.resize(32)
	for y in h:
		for x in w:
			var dx := (x + 0.5) / w * 2.0 - 1.0
			var dy := (y + 0.5) / h * 2.0 - 1.0
			var rr := sqrt(dx * dx + dy * dy)
			if rr >= 1.0:
				continue
			var b := int(rr * 32.0)
			var c := img.get_pixel(x, y)
			_profile[b] += c.a * c.get_luminance()
			counts[b] += 1
	for b in 32:
		_profile[b] = _profile[b] / maxf(counts[b], 1)
	print("PROFILE ", _profile)
