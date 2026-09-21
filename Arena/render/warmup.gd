class_name ArenaWarmUp extends Node
## The load the shell's loading screen stands in front of (2026-09-21, docs/stage-bug-2026-09-21.md).
##
## WHY THIS EXISTS. The one Godot view lives behind every menu, so the first frame the
## player ever sees is a full 3D frame: the workshop stage with its six lights and its dry
## ice, the Yard behind it, the whole FX tree, and then the machine bound onto the
## turntable. Every material in that frame has its pipeline compiled the first time it is
## drawn, and every texture in it is uploaded the first time it is sampled. All of that
## happens inside one `Main::iteration()` on the main thread, so until it finishes the
## SwiftUI menu in front cannot redraw either: the app looks frozen, the turntable looks
## empty and the menu reads as inactive. Wave P made the frame heavier (13 part models, two
## PBR armour sets, ten paint jobs, the arc bolt pool, the glow pool and fourteen new
## particle emitters), so what used to be a beat became a wait.
##
## WHAT IT DOES. Before the menu is shown, this node walks the whole catalogue once:
##
##   1. reads every part model and every material the catalogue can ask for, so no later
##      bind ever touches the disk;
##   2. reads the paint overlays, which are the same story for the builder's livery tab;
##   3. DRAWS them all once, off screen, so the renderer compiles their pipelines and
##      uploads their textures here rather than in front of the player.
##
## Work is sliced by a millisecond budget and the progress is reported over the bridge, so
## the shell can animate a loading screen while it runs and the frame rate never drops to
## the point where the screen itself stops moving.
##
## NOTHING HERE IS REQUIRED. If the warm up is never asked for, or fails, every path still
## loads lazily exactly as it did before: this only decides WHEN the cost is paid.

## Host -> arena. `{}`, or `{"models": false}` to skip the off screen draw.
const MSG_PRELOAD_BEGIN := "preload_begin"
## Arena -> host, once per slice: {"done": int, "total": int, "line": String, "fraction": float}
const MSG_PRELOAD_PROGRESS := "preload_progress"
## Arena -> host, once: {"ms": float, "models": int, "materials": int, "warmed": int}
const MSG_PRELOAD_DONE := "preload_done"

## How long one slice of work may take. Generous, because nothing else is on screen while
## it runs: the only thing the budget protects is the loading screen's own animation.
const SLICE_MS := 90.0

## The off screen viewport the warm draw happens in. Small, because a pipeline is compiled
## per material and per pass, not per pixel.
const WARM_SIZE := Vector2i(96, 96)
## How many models are stood up in the warm viewport at once. All 53 at once is 9.5 MB of
## meshes and one frame; a handful at a time keeps the peak lower and the progress honest.
const WARM_BATCH := 8

## The sentences the loading screen shows. Plain, in the owner's words, one per phase.
const LINE_PARTS := "Rolling out the machines"
const LINE_PAINT := "Mixing the paint"
const LINE_LIGHTS := "Warming the lights"
const LINE_READY := "Ready"

enum Phase { IDLE, PARTS, PAINT, LIGHTS, DONE }

## Everything read here is kept for the life of the process. A Resource with no reference
## left is freed, and freeing it would undo the whole point, so the references live here.
static var _kept: Array = []

var _phase: int = Phase.IDLE
var _queue: Array = []
var _done: int = 0
var _total: int = 0
var _models: int = 0
var _materials: int = 0
var _warmed: int = 0
var _started_usec: int = 0
var _warm_root: SubViewport = null
var _warm_holder: Node3D = null
var _warm_frames: int = 0
var _finished_ms: float = -1.0


func _ready() -> void:
	set_process(false)


## True once the whole walk has finished, whether it did any work or not.
func finished() -> bool:
	return _phase == Phase.DONE


## Milliseconds the walk took, or -1 before it finishes. The shell logs this.
func elapsed_ms() -> float:
	return _finished_ms


func running() -> bool:
	return _phase != Phase.IDLE and _phase != Phase.DONE


## Start the walk. Safe to call twice: the second call is ignored while one is running and
## answers straight away once one has finished, so a shell that retries cannot double it.
func begin(payload: Dictionary = {}) -> void:
	if running():
		return
	if finished():
		_send_done()
		return
	_started_usec = Time.get_ticks_usec()
	_done = 0
	_models = 0
	_materials = 0
	_warmed = 0
	_queue = _part_paths()
	_total = _queue.size() + _material_paths().size() + _paint_paths().size()
	# The off screen draw adds one unit of progress per batch, so the bar the shell draws
	# from `fraction` moves at a steady rate rather than stalling at the end.
	if bool(payload.get("models", true)):
		_total += int(ceil(float(_queue.size()) / float(WARM_BATCH))) + 1
	_phase = Phase.PARTS
	set_process(true)
	_send_progress(LINE_PARTS)


func _process(_delta: float) -> void:
	var until := Time.get_ticks_usec() + int(SLICE_MS * 1000.0)
	match _phase:
		Phase.PARTS:
			_step_load(until, LINE_PARTS)
		Phase.PAINT:
			_step_load(until, LINE_PAINT)
		Phase.LIGHTS:
			_step_warm()
		_:
			set_process(false)


# ---------------------------------------------------------------- the reading

## Read resources off the queue until the slice is spent. Finishing the queue moves the
## walk on to the next phase.
func _step_load(until_usec: int, line: String) -> void:
	while not _queue.is_empty() and Time.get_ticks_usec() < until_usec:
		var path := str(_queue.pop_front())
		var res: Resource = _read(path)
		if res != null:
			_kept.append(res)
			if res is PackedScene:
				_models += 1
			else:
				_materials += 1
		_done += 1
	_send_progress(line)
	if not _queue.is_empty():
		return
	match _phase:
		Phase.PARTS:
			_phase = Phase.PAINT
			_queue = _material_paths()
			_queue.append_array(_paint_paths())
			_send_progress(LINE_PAINT)
		Phase.PAINT:
			if _warm_wanted():
				_phase = Phase.LIGHTS
				_begin_warm()
				_send_progress(LINE_LIGHTS)
			else:
				_finish()


static func _read(path: String) -> Resource:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)


# ---------------------------------------------------------------- the warm draw

func _warm_wanted() -> bool:
	# A headless run has no renderer, so there is no pipeline to compile and no texture to
	# upload: the reading above is the whole warm up and the draw would only cost time.
	return DisplayServer.get_name() != "headless" and RenderingServer.get_video_adapter_name() != ""


## A world of its own, one camera, and the three light kinds the stage and the arena use,
## with shadows on, so the variants compiled here are the ones the stage will ask for.
func _begin_warm() -> void:
	_warm_root = SubViewport.new()
	_warm_root.name = "WarmUpViewport"
	_warm_root.size = WARM_SIZE
	_warm_root.own_world_3d = true
	_warm_root.transparent_bg = true
	_warm_root.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_warm_root)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.6, 2.4)
	camera.look_at_from_position(Vector3(0.0, 0.6, 2.4), Vector3.ZERO, Vector3.UP)
	camera.current = true
	_warm_root.add_child(camera)

	var key := SpotLight3D.new()
	key.position = Vector3(0.9, 2.2, 1.4)
	key.look_at_from_position(key.position, Vector3.ZERO, Vector3.UP)
	key.shadow_enabled = true
	_warm_root.add_child(key)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.shadow_enabled = true
	_warm_root.add_child(sun)

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-1.2, 1.4, 0.8)
	lamp.shadow_enabled = true
	_warm_root.add_child(lamp)

	_warm_holder = Node3D.new()
	_warm_holder.name = "Warming"
	_warm_root.add_child(_warm_holder)

	_queue = _part_ids()
	_warm_frames = 0


## One batch per slice, then one frame to draw it. The batch is freed before the next one
## is stood up, so the peak is WARM_BATCH machines' worth of meshes and no more.
func _step_warm() -> void:
	# Give the batch that is standing there a frame of its own to be drawn in.
	if _warm_holder != null and _warm_holder.get_child_count() > 0:
		if _warm_frames < 1:
			_warm_frames += 1
			return
		for child in _warm_holder.get_children():
			_warm_holder.remove_child(child)
			child.queue_free()
		_warm_frames = 0
		_done += 1
		_send_progress(LINE_LIGHTS)

	if _queue.is_empty():
		_finish()
		return

	var taken := 0
	var x := -float(WARM_BATCH) * 0.5
	while not _queue.is_empty() and taken < WARM_BATCH:
		var id := str(_queue.pop_front())
		var node := PartVisuals.instantiate(id)
		if node != null:
			node.position = Vector3(x, 0.0, 0.0)
			_warm_holder.add_child(node)
			_warmed += 1
		x += 1.0
		taken += 1


func _finish() -> void:
	_phase = Phase.DONE
	set_process(false)
	if _warm_root != null:
		_warm_root.queue_free()
		_warm_root = null
		_warm_holder = null
	_finished_ms = (Time.get_ticks_usec() - _started_usec) / 1000.0
	_done = _total
	_send_progress(LINE_READY)
	_send_done()


# ---------------------------------------------------------------- what to read

static func _part_ids() -> Array:
	var parts: Dictionary = PartsCatalogue.manifest().get("parts", {}) as Dictionary
	var ids: Array = parts.keys()
	ids.sort()
	return ids


static func _part_paths() -> Array:
	var parts: Dictionary = PartsCatalogue.manifest().get("parts", {}) as Dictionary
	var out: Array = []
	for id in _part_ids():
		var entry: Dictionary = parts[id] as Dictionary
		var path: String = str(entry.get("path", ""))
		if path != "":
			out.append(path)
	return out


static func _material_paths() -> Array:
	var out: Array = []
	for slot in PartVisuals.MATERIAL_FILES.keys():
		out.append(str(PartVisuals.MATERIAL_FILES[slot]))
	return out


## Every paint overlay the builder's livery tab can put on the turntable. A paint job with
## no normal map simply has no second file, and a path that is not there is skipped.
static func _paint_paths() -> Array:
	var out: Array = []
	var dir: String = Livery.TEXTURE_DIR
	for paint_id in Livery.ids():
		for kind in ["albedo", "normal"]:
			var path: String = dir + str(paint_id) + "_" + str(kind) + ".png"
			if ResourceLoader.exists(path):
				out.append(path)
	return out


# ---------------------------------------------------------------- the bridge

## The Bridge autoload, reached BY NODE rather than by its global identifier. A `--script`
## run (which is how every test in Arena/tests is driven) compiles this file before the
## autoload globals are registered, so `Bridge` is not an identifier here.
func _bridge() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("Bridge")


func _send(type: String, payload: Dictionary) -> void:
	var bridge := _bridge()
	if bridge != null:
		bridge.call("send", type, payload)


func _send_progress(line: String) -> void:
	var fraction := 1.0 if _total <= 0 else clampf(float(_done) / float(_total), 0.0, 1.0)
	_send(MSG_PRELOAD_PROGRESS, {
		"done": _done,
		"total": _total,
		"fraction": fraction,
		"line": line,
	})


func _send_done() -> void:
	_send(MSG_PRELOAD_DONE, {
		"ms": _finished_ms,
		"models": _models,
		"materials": _materials,
		"warmed": _warmed,
	})
