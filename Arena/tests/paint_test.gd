extends SceneTree
## The ten cosmetic paint jobs (wave P, agent G; brief v5 section 7, docs/paint-jobs.md).
##   Godot --headless --path Arena --script tests/paint_test.gd
##
## What this can prove headlessly, and what it deliberately does not claim:
##
## It CAN prove that every id in `Shared/parts.json`'s `progression.paint_jobs` binds
## to a real material with the overlay actually hung on it (not merely present on
## disk, which is the failure mode docs/graphics-textures-notes.md records for the
## G2 sets), that every texture loads at the size it was authored at, that the four
## embossed jobs carry their normal map and the other six do not, that an unknown
## or absent paint id gives back the SAME material a machine with no paint gets —
## byte for byte, the one thing that must not regress — and that the paint never
## leaks from one machine to the next.
##
## It CANNOT prove what the paint LOOKS like: --headless has no renderer, so nothing
## here samples a shader, and the simulator cannot stand in either (the QA launch
## flags run Godot with `-godotDisplay headless`, so the stage behind the menus is a
## still, not a render: two runs with two different paint jobs come back pixel
## identical). The look is judged from the previews in `Art/paint`, which are
## composited with this same arithmetic by Tools/paint/make_paint.py, and settled on
## a phone under Forward+. docs/wave-p-g-notes.md.

const PARTS := "res://data/parts.json"
const BOT := "res://bot/bot.tscn"

## What each paint job is supposed to be, independent of the catalogue: the test
## fails if livery.gd and this table drift apart, which is how a paint job silently
## loses its normal map or its blend mode.
const EXPECTED := {
	"paint_hazard": {"normal": false, "blend": BaseMaterial3D.BLEND_MODE_MIX},
	"paint_racing": {"normal": false, "blend": BaseMaterial3D.BLEND_MODE_MIX},
	"paint_camo": {"normal": false, "blend": BaseMaterial3D.BLEND_MODE_MUL},
	"paint_chequer": {"normal": true, "blend": BaseMaterial3D.BLEND_MODE_MIX},
	"paint_flames": {"normal": false, "blend": BaseMaterial3D.BLEND_MODE_MIX},
	"paint_carbon": {"normal": true, "blend": BaseMaterial3D.BLEND_MODE_MIX},
	"paint_chrome": {"normal": false, "blend": BaseMaterial3D.BLEND_MODE_MUL},
	"paint_circuit": {"normal": true, "blend": BaseMaterial3D.BLEND_MODE_MIX},
	"paint_hex": {"normal": true, "blend": BaseMaterial3D.BLEND_MODE_MUL},
	"paint_gold": {"normal": false, "blend": BaseMaterial3D.BLEND_MODE_MUL},
}

const LIVERY := Color(0.20, 0.34, 0.63)

var _checks := 0
var _failures := 0
var _skipped := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var catalogue_ids := _catalogue_paint_ids()
	_check(catalogue_ids.size() == 10,
		"the catalogue lists ten paint jobs (%d)" % catalogue_ids.size())

	for id in catalogue_ids:
		_check(Livery.has(id), "%s: livery.gd knows it" % id)
	for id in Livery.ids():
		_check(catalogue_ids.has(id), "%s: livery.gd invents nothing" % id)
	for id in EXPECTED:
		_check(catalogue_ids.has(id), "%s: this test and the catalogue agree" % id)

	_check_plain_is_unchanged()
	for id in catalogue_ids:
		if Livery.has(id):
			_check_one(id)
	_check_no_leak()
	_check_on_a_machine()
	_finish()


## Every paint job id the game actually ships, read from the catalogue rather than
## from a list in here, so adding one to parts.json without art fails loudly.
func _catalogue_paint_ids() -> Array:
	var file := FileAccess.open(PARTS, FileAccess.READ)
	if file == null:
		_fail("cannot open " + PARTS)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail(PARTS + " is not an object")
		return []
	var progression: Dictionary = (parsed as Dictionary).get("progression", {})
	var out: Array = []
	for entry in progression.get("paint_jobs", []):
		if entry is Dictionary:
			out.append(str((entry as Dictionary).get("id", "")))
	return out


## The one thing that must not regress: with no paint, the machine's livery material
## is the plain painted master in the machine's colour. Compared parameter by parameter
## rather than by identity, because the cache key carries the paint.
##
## Wave A (materials lead, docs/wave-a-materials-notes.md): the livery slot moved from a
## StandardMaterial3D with a detail layer to the `rb_painted` ShaderMaterial master. The
## detail layer became the `detail_*` uniforms; every guarantee below is the same one.
func _p(material: ShaderMaterial, name: String) -> Variant:
	return material.get_shader_parameter(name)


func _check_plain_is_unchanged() -> void:
	Livery.clear()
	PartVisuals.reset_cache()
	var plain := PartVisuals.slot_material("livery", LIVERY) as ShaderMaterial
	if plain == null:
		_fail("the plain livery slot gives no painted master")
		return
	_check(not _truthy(_p(plain, "detail_enabled")), "plain livery has no detail overlay")
	_check((_p(plain, "albedo") as Color).is_equal_approx(LIVERY), "plain livery keeps the colour")
	_check(is_equal_approx(float(_p(plain, "clearcoat")), 1.0)
		and float(_p(plain, "clearcoat_roughness")) <= 0.1,
		"plain livery is gloss clear coat (reference-study 3.3: 1.0 / 0.05)")
	_check(float(_p(plain, "roughness")) > 0.0,
		"plain livery base roughness is never exactly 0 under clear coat (godot#95207)")

	# An id nobody has heard of has to behave exactly like no paint at all.
	Livery.current = "paint_nonsense"
	PartVisuals.reset_cache()
	var unknown := PartVisuals.slot_material("livery", LIVERY) as ShaderMaterial
	Livery.clear()
	if unknown == null:
		_fail("an unknown paint id gives no material")
		return
	_check(not _truthy(_p(unknown, "detail_enabled")), "an unknown paint id leaves the livery plain")
	_check((_p(unknown, "albedo") as Color).is_equal_approx(_p(plain, "albedo"))
		and is_equal_approx(float(_p(unknown, "roughness")), float(_p(plain, "roughness")))
		and is_equal_approx(float(_p(unknown, "metallic")), float(_p(plain, "metallic"))),
		"an unknown paint id gives the same material as no paint")


func _check_one(id: String) -> void:
	var expected: Dictionary = EXPECTED.get(id, {})

	# The overlay has to exist at the size it was authored at.
	var albedo_path := Livery.TEXTURE_DIR + id + "_albedo.png"
	if not ResourceLoader.exists(albedo_path):
		_fail("%s: no overlay at %s" % [id, albedo_path])
		return
	var albedo := load(albedo_path) as Texture2D
	_check(albedo != null and albedo.get_width() == 1024 and albedo.get_height() == 1024,
		"%s: overlay is 1024 square" % id)

	var wants_normal: bool = bool(expected.get("normal", false))
	var normal_path := Livery.TEXTURE_DIR + id + "_normal.png"
	_check(ResourceLoader.exists(normal_path) == wants_normal,
		"%s: normal map %s" % [id, "ships" if wants_normal else "does not ship"])

	# And it has to be BOUND, which is the part that fails silently.
	Livery.current = id
	PartVisuals.reset_cache()
	var material := PartVisuals.slot_material("livery", LIVERY) as ShaderMaterial
	Livery.clear()
	if material == null:
		_fail("%s: binds no painted master" % id)
		return
	_check(_truthy(_p(material, "detail_enabled")), "%s: detail is on" % id)
	_check(_p(material, "detail_albedo") == albedo, "%s: the overlay is bound" % id)
	if expected.has("blend"):
		var want := 0 if int(expected["blend"]) == BaseMaterial3D.BLEND_MODE_MIX else 1
		_check(int(_p(material, "detail_blend")) == want,
			"%s: blend mode is the one the art was drawn for" % id)
	if wants_normal:
		_check(_truthy(_p(material, "detail_normal_enabled")) and _p(material, "detail_normal") != null,
			"%s: the relief is bound" % id)
	else:
		_check(not _truthy(_p(material, "detail_normal_enabled")), "%s: no relief is bound" % id)

	# The two metals are metal, not painted plastic with a shiny texture.
	var job: Dictionary = Livery.JOBS[id]
	if job.has("metallic"):
		_check(is_equal_approx(float(_p(material, "metallic")), float(job["metallic"])),
			"%s: metallic is %.2f" % [id, float(job["metallic"])])
	if job.has("roughness"):
		_check(is_equal_approx(float(_p(material, "roughness")), float(job["roughness"])),
			"%s: roughness is %.2f" % [id, float(job["roughness"])])
	if job.has("albedo"):
		# The master has no grain texture, so a metal's albedo is set straight.
		var mixed: Color = (job["albedo"] as Color).lerp(LIVERY, float(job.get("livery_mix", 0.0)))
		_check((_p(material, "albedo") as Color).is_equal_approx(mixed),
			"%s: the metal's albedo is its own specular colour" % id)

	# Density matching has to survive the paint, or the overlay is stretched across
	# a whole chassis instead of tiling at the kit's texel density.
	var matched := PartVisuals.density_matched(material, 0.176) as ShaderMaterial
	_check(matched != null and _truthy(_p(matched, "detail_enabled"))
		and _p(matched, "detail_albedo") == albedo, "%s: survives density matching" % id)
	_check(matched != null and (_p(matched, "uv1_scale") as Vector2).x > 1.0,
		"%s: a chassis-density surface still gets its uv1_scale" % id)


## Two machines, two paints, in the order a fight builds them. The second must not
## inherit the first, and a machine built after `clear()` must be plain.
func _check_no_leak() -> void:
	PartVisuals.reset_cache()
	Livery.begin({"paint": "paint_gold"})
	var gold := PartVisuals.slot_material("livery", LIVERY) as ShaderMaterial
	Livery.clear()
	Livery.begin({"paint": "paint_carbon"})
	var carbon := PartVisuals.slot_material("livery", LIVERY) as ShaderMaterial
	Livery.clear()
	var plain := PartVisuals.slot_material("livery", LIVERY) as ShaderMaterial

	_check(gold != null and carbon != null and plain != null, "three machines bind")
	if gold == null or carbon == null or plain == null:
		return
	_check(_p(gold, "detail_albedo") != _p(carbon, "detail_albedo"),
		"two machines in one fight wear their own paint")
	_check(not _truthy(_p(plain, "detail_enabled")), "the next machine after clear() is plain")
	_check(_truthy(_p(gold, "detail_enabled")) and _truthy(_p(carbon, "detail_enabled")),
		"neither painted machine lost its paint to the other")

	# A config with no paint key at all is the ordinary case and must be plain.
	Livery.begin({"id": "ai-1", "livery": "#b8362f"})
	_check(Livery.current == "", "a config with no paint key leaves the livery plain")
	Livery.clear()


## The whole chain on a real machine: a bot config with a `paint` key, through
## `Livery.begin`, through `Bot.setup`, to the surfaces the player looks at.
##
## This is the check that matters, because everything above it tests the material
## in isolation. It also records WHICH slots take paint: the chassis `livery` and
## the HDPE armour plates, and nothing else. Steel, titanium and polycarbonate
## armour stay bare metal and bare plastic by design.
func _check_on_a_machine() -> void:
	var scene := load(BOT) as PackedScene
	if scene == null:
		_skip("no bot scene, so the machine check cannot run")
		return
	var config := {
		"id": "player-1", "name": "Paint probe", "controller": "player",
		"chassis": "wedge", "drive": "4wd", "weapon": "flipper",
		"utility": ["srimech"],
		"armour": {
			"front": {"material": "steel", "thickness": 2},
			"sides": {"material": "hdpe", "thickness": 2},
			"rear": {"material": "polycarbonate", "thickness": 1},
			"top": {"material": "titanium", "thickness": 1}},
		"livery": LIVERY.to_html(false),
		"paint": "paint_hazard",
	}
	PartVisuals.reset_cache()
	Livery.begin(config)
	_check(Livery.current == "paint_hazard", "a bot config's paint key reaches Livery")
	var bot: Node = scene.instantiate()
	root.add_child(bot)
	if bot.has_method("setup"):
		bot.call("setup", config, 0, RandomNumberGenerator.new())
	Livery.clear()

	var slots := {}
	_collect(bot, slots)
	_check(int(slots.get("livery|painted", 0)) > 0,
		"the chassis livery surfaces are painted (%d)" % int(slots.get("livery|painted", 0)))
	_check(int(slots.get("livery|plain", 0)) == 0, "no chassis livery surface was missed")
	_check(int(slots.get("hdpe|painted", 0)) > 0,
		"the HDPE armour plates are painted (%d)" % int(slots.get("hdpe|painted", 0)))
	for bare in ["steel", "titanium", "polycarbonate", "rubber", "dark_metal"]:
		_check(int(slots.get(bare + "|painted", 0)) == 0,
			"%s is left bare, not painted" % bare)

	root.remove_child(bot)
	bot.queue_free()
	PartVisuals.reset_cache()


## slot name + "|painted" or "|plain" -> how many surfaces, over the whole machine.
func _collect(node: Node, out: Dictionary) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		for i in range(mesh_instance.mesh.get_surface_count()):
			var authored := mesh_instance.mesh.surface_get_material(i)
			var slot := "" if authored == null else str(authored.resource_name)
			var applied := mesh_instance.get_surface_override_material(i)
			if applied == null:
				applied = mesh_instance.material_override
			if applied == null or slot == "":
				continue
			var painted := false
			if applied is StandardMaterial3D:
				painted = (applied as StandardMaterial3D).detail_enabled
			elif applied is ShaderMaterial:
				painted = _truthy((applied as ShaderMaterial).get_shader_parameter("detail_enabled"))
			else:
				continue
			var key := slot + ("|painted" if painted else "|plain")
			out[key] = int(out.get(key, 0)) + 1
	for child in node.get_children():
		_collect(child, out)


func _skip(label: String) -> void:
	_skipped += 1
	print("SKIP  ", label)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _fail(label: String) -> void:
	_checks += 1
	_failures += 1
	printerr("FAIL  ", label)
	print("FAIL  ", label)


func _finish() -> void:
	PartVisuals.reset_cache()
	Livery.clear()
	print("")
	if _failures == 0:
		print("PASS  paint: %d checks, 0 failures, %d skipped" % [_checks, _skipped])
		quit(0)
	else:
		print("FAIL  paint: %d checks, %d failures, %d skipped" % [_checks, _failures, _skipped])
		quit(1)


## A shader parameter that is not set reads back null; unset means off (the bool(null) exit 97).
func _truthy(value: Variant) -> bool:
	return value != null and bool(value)
