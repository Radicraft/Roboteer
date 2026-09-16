extends SceneTree
## `texel_density`: how many texture pixels every surface a machine wears puts behind one
## screen pixel, and the import path those pixels take to the phone. Wave V, agent V4.
##   Godot --headless --path Arena --script tests/texel_density_test.gd
##
## The owner played a fight on his iPhone: "the bot feels a bit small on screen and not
## high res enough", and earlier "house bots look blurry". Two of those three words are
## measurable without a device and this is where they are measured.
##
## TEXEL DENSITY is the only number that says whether a texture is big enough. It is
## texels per metre of real surface (the UV unwrap's density times the material's
## `uv1_scale` times the texture's size) divided by screen pixels per metre at the camera
## that matters. Above 1 the texture is minified and the mip chain is doing the work;
## below 1 it is MAGNIFIED, which is blur you cannot filter away and the only case where a
## bigger texture is the answer.
##
## What this file pins down, so a regression shows:
##   1. every .glb in the kit reports a UV density, and after `PartVisuals`' per surface
##      `uv1_scale` every machine surface lands in one band rather than the eightfold
##      spread the raw unwraps have;
##   2. nothing a machine wears is magnified at the closest view in the game (the workshop
##      turntable), which is the "blurry" complaint;
##   3. the import path: VRAM compression on, mipmaps on, no size limit, and ASTC rather
##      than ETC2 on the sets a machine wears.

const PARTS_ROOT := "res://assets/parts/"
## Every slot a machine or a house bot actually wears, and the material behind it.
const MACHINE_SLOTS := ["steel", "titanium", "hdpe", "livery", "dark_metal", "rubber",
	"polycarbonate"]
## The sets whose .import files must be ASTC (compress/high_quality=true), because they
## are what a machine is made of. The arena floor, the concrete and the chevron stay on
## ETC2 on purpose: they are half the pack's texture bytes and they are seen at a grazing
## angle where block error hides.
const MACHINE_TEXTURE_SETS := ["brushed_steel", "scratched_titanium", "hdpe_moulded",
	"polycarbonate", "tyre_rubber", "scratch_decal", "rust_spots"]

## iPhone 17 landscape, in the units the fight SubViewport is sized in.
const VIEW := Vector2i(1206, 556)
const DT := 1.0 / 60.0

## The band every machine surface must land in after the per surface uv1_scale. Wide
## enough to hold the snap to UV_SCALE_STEPS and the 8.0 cap at the top of it, tight
## enough that a part re exported with a wildly different unwrap fails here.
const BAND_LOW := 900.0
const BAND_HIGH := 3600.0
## The closest view in the game is the workshop turntable. Nothing a machine wears may be
## magnified there; 1.0 texel per screen pixel is the line, and this is the margin under it
## that is still called a pass (the normal maps of the plastics ship at half the albedo's
## size by design, so they sit at half these numbers and are excluded).
const MIN_TEXELS_PER_PIXEL := 1.0

var _failures := 0
var _checks := 0
var _rows: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var pixels := await _screen_pixels_per_metre()
	_measure_parts()
	_test_band()
	_test_close_view(pixels)
	_test_import_path()
	_finish()


# ------------------------------------------------------- the measurement

## Every .glb in the kit, every mesh in it, through the SAME code the game binds with.
func _measure_parts() -> void:
	var files := _glb_files()
	_check(files.size() >= 30,
		"the parts kit has %d .glb files to measure" % files.size())
	for path in files:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			_check(false, path + " loads")
			continue
		var root := packed.instantiate() as Node3D
		if root == null:
			continue
		for mesh_instance in _meshes(root):
			var mesh := mesh_instance.mesh
			var uv_per_m := PartVisuals.uv_per_metre(mesh)
			if uv_per_m <= 0.0:
				_check(false, "%s has a mesh with no usable UVs" % path.get_file())
				continue
			for i in range(mesh.get_surface_count()):
				var source: Material = mesh.surface_get_material(i)
				var slot := "" if source == null else str(source.resource_name)
				if not (slot in MACHINE_SLOTS):
					continue
				var material := PartVisuals.slot_material(slot, Color(0.8, 0.2, 0.2))
				var standard := material as StandardMaterial3D
				if standard == null or standard.albedo_texture == null:
					_check(false, "slot '%s' has no albedo texture behind it" % slot)
					continue
				var size := float(maxi(standard.albedo_texture.get_width(),
					standard.albedo_texture.get_height()))
				var scale := PartVisuals.uv_scale_for(uv_per_m, size)
				_rows.append({
					"part": path.get_file().get_basename(), "slot": slot,
					"uv_per_m": uv_per_m, "size": size, "scale": scale,
					"before": uv_per_m * standard.uv1_scale.x * size,
					"after": uv_per_m * scale * size,
				})
		root.free()
	_check(_rows.size() > 100,
		"%d machine surfaces measured across the kit" % _rows.size())


## Screen pixels per metre for a surface facing the camera, at the two distances that
## decide everything: the fight camera where it rests through an exchange, and the
## workshop turntable, which is the closest a machine is ever seen.
func _screen_pixels_per_metre() -> Dictionary:
	var out := {"fight": 0.0, "workshop": 0.0, "fight_m": 0.0, "workshop_m": 0.0}
	var scene: PackedScene = load("res://ui/camera_rig.tscn") as PackedScene
	if scene == null:
		return out
	var vp := SubViewport.new()
	vp.size = VIEW
	root.add_child(vp)
	var rig: CameraRig = scene.instantiate() as CameraRig
	vp.add_child(rig)
	var a := Node3D.new()
	var b := Node3D.new()
	vp.add_child(a)
	vp.add_child(b)
	await process_frame
	await process_frame
	rig.set_process(false)
	rig.set_mode(CameraRig.MODE_FIGHT)
	rig.set_targets(a, b)
	# 1.5 m apart: two machines trading, which is where a fight lives.
	a.position = Vector3(-0.75, 0.25, 0.0)
	b.position = Vector3(0.75, 0.25, 0.0)
	rig.reset_to_default()
	rig.fit_arena(FightTypes.ARENA_SIZE)
	for i in 180:
		rig._process(DT)
	out["fight_m"] = rig.distance()
	out["fight"] = _pixels_per_metre(rig.camera(), rig.distance())
	rig.set_mode(CameraRig.MODE_WORKSHOP)
	rig._process(0.0)
	out["workshop_m"] = rig.distance()
	out["workshop"] = _pixels_per_metre(rig.camera(), rig.distance())
	rig.queue_free()
	vp.queue_free()
	await process_frame
	return out


## Height of the frame in metres at `dist`, turned into pixels per metre. Godot keeps the
## vertical FOV, so the frame is 2 * dist * tan(fov / 2) tall in world units there.
func _pixels_per_metre(cam: Camera3D, dist: float) -> float:
	var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
	return float(VIEW.y) / maxf(2.0 * dist * tan_v, 0.0001)


# ------------------------------------------------------- the checks

## One band, not an eightfold spread. Before this pass a chassis carried 288 to 434 texels
## per metre while a weapon bolted to it carried 1900 to 3400, which is why the body of a
## machine read softer than the thing on the front of it.
func _test_band() -> void:
	var low := INF
	var high := 0.0
	var low_at := ""
	var high_at := ""
	var raw_low := INF
	var raw_high := 0.0
	for row in _rows:
		var after: float = row["after"]
		if after < low:
			low = after
			low_at = "%s/%s" % [row["part"], row["slot"]]
		if after > high:
			high = after
			high_at = "%s/%s" % [row["part"], row["slot"]]
		raw_low = minf(raw_low, float(row["before"]))
		raw_high = maxf(raw_high, float(row["before"]))
	_check(low >= BAND_LOW,
		"no machine surface is under %.0f texels per metre (lowest %.0f at %s)"
			% [BAND_LOW, low, low_at])
	_check(high <= BAND_HIGH,
		"and none over %.0f (highest %.0f at %s)" % [BAND_HIGH, high, high_at])
	_check(high / maxf(low, 0.001) < raw_high / maxf(raw_low, 0.001),
		"the spread is tighter than the raw unwraps give (%.1fx, was %.1fx from %.0f to %.0f)"
			% [high / maxf(low, 0.001), raw_high / maxf(raw_low, 0.001), raw_low, raw_high])


## The complaint, in numbers. Nothing a machine wears may be magnified at the closest view.
func _test_close_view(pixels: Dictionary) -> void:
	var fight: float = pixels.get("fight", 0.0)
	var workshop: float = pixels.get("workshop", 0.0)
	_check(fight > 0.0 and workshop > 0.0,
		"the fight camera rests at %.2f m (%.0f px/m) and the workshop at %.2f m (%.0f px/m)"
			% [pixels.get("fight_m", 0.0), fight, pixels.get("workshop_m", 0.0), workshop])
	if workshop <= 0.0:
		return
	var worst := INF
	var worst_at := ""
	var worst_before := INF
	var fight_worst := INF
	for row in _rows:
		var after: float = float(row["after"]) / workshop
		if after < worst:
			worst = after
			worst_at = "%s/%s" % [row["part"], row["slot"]]
		worst_before = minf(worst_before, float(row["before"]) / workshop)
		fight_worst = minf(fight_worst, float(row["after"]) / fight)
	_check(worst >= MIN_TEXELS_PER_PIXEL,
		"nothing on a machine is magnified on the workshop stage: worst is %.2f texels "
		% worst + "per screen pixel at %s (it was %.2f before this pass)"
			% [worst_at, worst_before])
	_check(worst_before < MIN_TEXELS_PER_PIXEL,
		"and that is a real change: the worst surface WAS magnified (%.2f texels per pixel)"
			% worst_before)
	# Minification at the fight camera is fine and expected; it is what the mip chain is
	# for. This only records the number so a change in it is visible in the log.
	_check(fight_worst >= 1.0,
		"at the fight camera every machine surface is minified, never magnified "
		+ "(worst %.1f texels per screen pixel)" % fight_worst)


## The import path those texels take to the phone. Every one of these fails silently.
func _test_import_path() -> void:
	for set_name in MACHINE_TEXTURE_SETS:
		var dir := DirAccess.open("res://assets/textures/" + set_name)
		if dir == null:
			_check(false, set_name + " has a texture folder")
			continue
		var checked := 0
		var faults := PackedStringArray()
		for file in dir.get_files():
			if not file.ends_with(".png.import"):
				continue
			checked += 1
			var text := FileAccess.get_file_as_string(
				"res://assets/textures/%s/%s" % [set_name, file])
			if text.find("compress/mode=2") < 0:
				faults.append(file + " is not VRAM compressed")
			if text.find("compress/high_quality=true") < 0:
				faults.append(file + " is ETC2, not ASTC")
			if text.find("mipmaps/generate=true") < 0:
				faults.append(file + " has no mipmaps")
			if text.find("process/size_limit=0") < 0:
				faults.append(file + " has a size limit")
		_check(checked >= 3 and faults.is_empty(),
			"%s: %d maps, all VRAM compressed to ASTC with mipmaps and no size limit%s"
				% [set_name, checked, "" if faults.is_empty() else " -- " + ", ".join(faults)])
	_check(bool(ProjectSettings.get_setting(
		"rendering/textures/vram_compression/import_etc2_astc", false)),
		"import_etc2_astc is on, without which iOS silently ships every texture uncompressed")
	# 0=1x, 1=2x, 2=4x, 3=8x, 4=16x. The arena floor is a 2048 plate tiled 4x seen at a 50
	# degree pitch, which is the case anisotropic filtering exists for.
	_check(int(ProjectSettings.get_setting(
		"rendering/textures/default_filters/anisotropic_filtering_level", 0)) >= 3,
		"anisotropic filtering is at least 8x")
	var bias := float(ProjectSettings.get_setting(
		"rendering/textures/default_filters/texture_mipmap_bias", 0.0))
	_check(bias < 0.0 and bias >= -0.6,
		"the mipmap bias sharpens the minified case without shimmering (%.2f)" % bias)
	# The 3D buffer is the viewport, one to one. Anything else here is a resolution loss
	# that no texture work can win back.
	_check(is_equal_approx(float(ProjectSettings.get_setting(
		"rendering/scaling_3d/scale", 1.0)), 1.0),
		"3D renders at native scale (scaling_3d/scale is 1.0)")


# ------------------------------------------------------- helpers

func _glb_files() -> PackedStringArray:
	var out := PackedStringArray()
	_walk(PARTS_ROOT, out)
	out.sort()
	return out


func _walk(path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".glb"):
			out.append(path + file)
	for sub in dir.get_directories():
		_walk(path + sub + "/", out)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _finish() -> void:
	# The table, printed once, because the numbers are the point of the file.
	var worst: Array = _rows.duplicate()
	worst.sort_custom(func(x, y): return float(x["after"]) < float(y["after"]))
	print("")
	print("  lowest texel density after the per surface uv1_scale:")
	for i in mini(8, worst.size()):
		var row: Dictionary = worst[i]
		print("    %-22s %-11s uv/m %.3f  x%.1f on %d  ->  %.0f texels/m (was %.0f)"
			% [row["part"], row["slot"], row["uv_per_m"], row["scale"], int(row["size"]),
				row["after"], row["before"]])
	print("")
	if _failures == 0:
		print("PASS  texel density: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  texel density: %d checks, %d failures" % [_checks, _failures])
		quit(1)
