extends SceneTree
## G2 material probe: does every texture set and every material resource
## actually load in a headless Godot, with every map bound to the right slot?
##
## Named with a leading underscore so scripts/test-arena.sh treats it as a
## helper and does not run it as part of the suite: it is an asset check for
## agent G2's own work, not a behaviour test of the game.
##
##   Godot --headless --path Arena --import                   (once, first)
##   Godot --headless --path Arena --script tests/_g2_material_probe.gd
##
## Exits 0 only when every check passes.

const TEX_DIR := "res://assets/textures"
const MAT_DIR := "res://assets/materials"

## The tiling sets: five maps each, and a .tres that must bind all five.
const TILING := [
	"brushed_steel",
	"scratched_titanium",
	"hdpe_moulded",
	"polycarbonate",
	"tyre_rubber",
	"arena_plate",
	"chevron",
	"concrete_dark",
]

## Damage decals: consumed by Decal nodes, which take textures directly rather
## than a StandardMaterial3D, so these have textures but no .tres.
const DECALS := ["scorch", "scratch_decal", "rust_spots"]

const TILING_MAPS := ["albedo", "normal", "roughness", "metallic", "ao"]
const DECAL_MAPS := ["albedo", "normal", "roughness"]

var _pass := 0
var _fail := 0


func _ok(label: String) -> void:
	_pass += 1
	print("PASS  ", label)


func _bad(label: String, why: String) -> void:
	_fail += 1
	print("FAIL  ", label, "  -- ", why)


func _check_texture(path: String, label: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		_bad(label, "no such resource (did you run --import?): " + path)
		return null
	var tex := ResourceLoader.load(path) as Texture2D
	if tex == null:
		_bad(label, "loaded but is not a Texture2D: " + path)
		return null
	if tex.get_width() <= 0 or tex.get_height() <= 0:
		_bad(label, "zero-sized texture: " + path)
		return null
	_ok("%s  %dx%d" % [label, tex.get_width(), tex.get_height()])
	return tex


func _initialize() -> void:
	print("=== G2 textures and materials ===")

	for name: String in TILING:
		for map_name: String in TILING_MAPS:
			_check_texture(
				"%s/%s/%s_%s.png" % [TEX_DIR, name, name, map_name],
				"texture %s/%s" % [name, map_name]
			)

	for name: String in DECALS:
		for map_name: String in DECAL_MAPS:
			_check_texture(
				"%s/%s/%s_%s.png" % [TEX_DIR, name, name, map_name],
				"texture %s/%s" % [name, map_name]
			)

	print("")
	for name: String in TILING:
		_check_material(name)

	print("")
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _check_material(name: String) -> void:
	var path := "%s/%s.tres" % [MAT_DIR, name]
	var label := "material " + name
	if not ResourceLoader.exists(path):
		_bad(label, "no such resource: " + path)
		return
	var mat := ResourceLoader.load(path) as StandardMaterial3D
	if mat == null:
		_bad(label, "loaded but is not a StandardMaterial3D: " + path)
		return

	# Every map must be bound, not merely present on disk. A normal_texture on
	# a material with normal_enabled false is the classic silent failure.
	var problems: Array[String] = []
	if mat.albedo_texture == null:
		problems.append("albedo_texture unset")
	if mat.normal_texture == null:
		problems.append("normal_texture unset")
	elif not mat.normal_enabled:
		problems.append("normal_texture set but normal_enabled is false")
	if mat.roughness_texture == null:
		problems.append("roughness_texture unset")
	if mat.metallic_texture == null:
		problems.append("metallic_texture unset")
	if mat.ao_texture == null:
		problems.append("ao_texture unset")
	elif not mat.ao_enabled:
		problems.append("ao_texture set but ao_enabled is false")

	# The livery contract: code assigns the livery colour straight into
	# albedo_color on the HDPE material, so the texture must be neutral and the
	# colour must ship as pure white or every livery comes out wrong.
	if name == "hdpe_moulded" and mat.albedo_color != Color(1, 1, 1, 1):
		problems.append("hdpe albedo_color must be opaque white, is %s" % mat.albedo_color)

	if name == "polycarbonate":
		if mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
			problems.append("polycarbonate must use TRANSPARENCY_ALPHA")
		if not is_equal_approx(mat.albedo_color.a, 0.6):
			problems.append("polycarbonate alpha must be 0.6, is %f" % mat.albedo_color.a)

	# Anti-sparkle, owned by G1 and also asserted in render_test.gd. Duplicated here so
	# that regenerating the materials with make_materials.py fails fast rather than
	# quietly undoing a rendering fix that lives in someone else's suite.
	if mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
		problems.append("texture_filter must be anisotropic-with-mipmaps, is %d" % mat.texture_filter)
	if mat.metallic > 0.0 and mat.normal_scale > 0.5:
		problems.append("metallic material needs normal_scale <= 0.5, is %.2f" % mat.normal_scale)

	if name == "arena_plate":
		if mat.uv1_triplanar:
			problems.append("arena_plate must have uv1_triplanar off")
		if not is_equal_approx(mat.uv1_scale.x, 4.0) or not is_equal_approx(mat.uv1_scale.y, 4.0):
			problems.append("arena_plate uv1_scale must be 4x4, is %s" % mat.uv1_scale)

	if problems.is_empty():
		_ok("%s  metallic=%.2f uv1=%s" % [label, mat.metallic, mat.uv1_scale])
	else:
		_bad(label, ", ".join(problems))
