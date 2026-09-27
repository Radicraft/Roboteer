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
## WHAT IT DOES. Before the menu is shown, this node walks the whole game once:
##
##   1. reads every scene the shell can open (the stage, the fight world, every arena and
##      event arena, the HUD, the controls, the camera rig, the FX tree), the two
##      environments, the arena materials, the FX textures and meshes;
##   2. reads every part model in the catalogue (bosses included) and every material slot;
##   3. reads the paint overlays for the builder's livery tab;
##   4. reads every sound the mixer can ask for;
##   5. DRAWS the lot once, off screen: every part bound with its RUNTIME materials (the
##      same `PartVisuals.bind` the stage uses, so the variants compiled are the ones the
##      stage will ask for), one chassis per paint job, and one emitter per particle
##      flavour, under the stage environment and the three light kinds with shadows on.
##
## Work is sliced by a millisecond budget and the progress is reported over the bridge, so
## the shell can animate a loading screen while it runs. The fraction the shell shows is
## files read plus batches drawn over the total of both: real work, never a timer.
##
## NOTHING HERE IS REQUIRED. If the warm up is never asked for, or fails, every path still
## loads lazily exactly as it did before: this only decides WHEN the cost is paid.

## Host -> arena. `{}`, or `{"models": false}` to skip the off screen draw.
const MSG_PRELOAD_BEGIN := "preload_begin"
## Arena -> host, once per slice: {"done": int, "total": int, "line": String, "fraction": float,
## "step": int, "step_fraction": float}. `step` is the loading screen's row (STEP_*, below) and
## `step_fraction` how far through that phase's own work the walk is. The workshop stage hears
## the same message (Bridge.message_sent) and builds the machine in step with it.
const MSG_PRELOAD_PROGRESS := "preload_progress"
## Arena -> host, once: {"ms": float, "models": int, "materials": int, "warmed": int, ...}
const MSG_PRELOAD_DONE := "preload_done"

## How long one slice of reading may take on a renderer with a RenderingDevice (the phone).
## Generous, because nothing else is on screen while it runs: the budget only protects the
## loading screen's own fade.
const SLICE_MS := 90.0
## The same on the GL Compatibility tier (the simulator draws about one frame a second),
## where every extra frame costs a second: read as much as possible per frame there.
const SLICE_MS_SLOW := 1500.0

## The off screen viewport the warm draw happens in. Small, because a pipeline is compiled
## per material and per pass, not per pixel.
const WARM_SIZE := Vector2i(96, 96)
## How many models are stood up in the warm viewport at once on the phone. A handful at a
## time keeps each frame short so the loading screen keeps moving. The slow tier draws
## everything in one batch instead, because there a frame is the expensive unit.
const WARM_BATCH := 8
## Frames each batch is left standing. Two: the first draw compiles, the second is the one
## that proves the pipeline is ready (and uploads anything that was deferred).
const WARM_FRAMES := 2
## The draw must never be able to hold the game: past this the walk finishes anyway, and
## whatever was not drawn is simply drawn later, lazily, as it always was.
const WARM_CAP_MS := 20000.0

## The colour the warm draw binds the livery slots with. The pipeline does not depend on
## the colour, only on which features the material has on.
const WARM_LIVERY := Color(0.8, 0.2, 0.15)

## The scenes and single resources the shell can open, by path. Directories are walked
## too (`_dir_paths`), so a new arena or sound is picked up without editing this list.
const SCENES := [
	"res://workshop/stage.tscn",
	"res://fight/fight_world.tscn",
	"res://bot/bot.tscn",
	"res://ui/hud.tscn",
	"res://ui/controls.tscn",
	"res://ui/camera_rig.tscn",
	"res://fx/fx.tscn",
	"res://render/stage_env.tres",
	"res://render/arena_env.tres",
	"res://render/default_env.tres",
	"res://fx/audio_bus_layout.tres",
]
const SCENE_DIRS := {
	"res://arena/": ["tscn"],
	"res://arena/events/": ["tscn"],
	"res://assets/materials/": ["tres"],
	"res://fx/textures/": ["png"],
}
const SOUND_DIR := "res://audio/"
## Arenas dressed by the venue kit (res://arena/kit/): each is stood up whole, shrunk to
## fit the warm camera, so the kit's own pipelines (the night floor, the wall trim, the
## crowd cards and specks, beams, sky, LED screen, dust and grit) compile here too. On the
## desktop the first Yard build stalled about nine seconds on these (docs/wave-a-kit-notes.md).
const VENUE_SCENES := ["res://arena/yard.tscn", "res://arena/grinder.tscn", "res://arena/drop_zone.tscn",
	"res://arena/furnace.tscn", "res://arena/crush.tscn", "res://arena/coliseum.tscn",
	# The workshop test bay (dfd7a09): the test arena now carries the kit too. Its scene
	# file is read in the hull row with every other arena; drawing it here, in the lights
	# row, is what compiles its floor, tool wall, benches and high-bay pipelines.
	"res://arena/test_arena.tscn"]
## The shrink: a 10 m arena with its 90 m sky inside a 96 px view 5.5 m away.
const VENUE_WARM_SCALE := 0.012
const STAGE_ENV := "res://render/stage_env.tres"

## The sentences the loading screen shows. Plain, one per phase, and they say what the
## player is WATCHING (the machine being put together on the turntable, 2026-09-27 direction
## A, docs/look/loading-options.html), because the phases themselves are plumbing.
const LINE_STAGE := "Opening the workshop"
const LINE_PARTS := "Fitting the drive"
const LINE_PAINT := "Bolting on the armour"
const LINE_SOUND := "Mounting the weapon"
const LINE_LIGHTS := "Warming the lights"
const LINE_READY := "Into the workshop"

## The loading screen's five rows, and the phase that owns each one. Every phase is real
## work, so a row fills when its phase's work is done, never on a timer:
##   Hull          <- STAGE   the scenes, environments, arena materials, FX textures
##   Drive         <- PARTS   every part model and material slot in the catalogue
##   Armour        <- PAINT   the paint overlays
##   Weapon        <- SOUND   every sound the mixer can ask for
##   Stage lights  <- LIGHTS  the off screen draw (pipelines compiled, textures uploaded)
## STEP_DONE is sent once, at the end.
const STEP_HULL := 0
const STEP_DRIVE := 1
const STEP_ARMOUR := 2
const STEP_WEAPON := 3
const STEP_LIGHTS := 4
const STEP_DONE := 5

enum Phase { IDLE, STAGE, PARTS, PAINT, SOUND, LIGHTS, DONE }

## Everything read here is kept for the life of the process. A Resource with no reference
## left is freed, and freeing it would undo the whole point, so the references live here.
static var _kept: Array = []

var _phase: int = Phase.IDLE
var _queue: Array = []
var _done: int = 0
var _total: int = 0
var _scenes: int = 0
var _models: int = 0
var _materials: int = 0
var _sounds: int = 0
var _warmed: int = 0
var _started_usec: int = 0
var _warm_started_usec: int = 0
var _warm_root: SubViewport = null
var _warm_holder: Node3D = null
var _warm_frames: int = 0
var _warm_batches: Array = []
var _warm_drawn: bool = false
var _finished_ms: float = -1.0
## Test seam: run the off screen draw even with no renderer, so the headless suite can
## prove the draw path runs to the end without a script error. Nothing is compiled then.
var force_draw: bool = false
var _read_ms: float = -1.0
var _draw_ms: float = -1.0
## Where the current phase's work starts in `_done`, and how much of it there is, so each
## progress message can say how far through its own row the walk is.
var _phase_from: int = 0
var _phase_size: int = 0


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
	_scenes = 0
	_models = 0
	_materials = 0
	_sounds = 0
	_warmed = 0
	_warm_drawn = bool(payload.get("models", true)) and (_warm_wanted() or force_draw)
	_queue = _scene_paths()
	_total = _queue.size() + _part_paths().size() + _material_paths().size() \
		+ _paint_paths().size() + _sound_paths().size()
	# The off screen draw adds one unit of progress per batch it stands up, so the fraction
	# the shell shows moves at a steady rate rather than stalling at the end.
	if _warm_drawn:
		_warm_batches = _plan_batches()
		_total += _warm_batches.size()
	_phase = Phase.STAGE
	_mark_phase(_queue.size())
	set_process(true)
	_send_progress(LINE_STAGE)


func _process(_delta: float) -> void:
	var budget := SLICE_MS if RenderingServer.get_rendering_device() != null else SLICE_MS_SLOW
	var until := Time.get_ticks_usec() + int(budget * 1000.0)
	match _phase:
		Phase.STAGE:
			_step_load(until, LINE_STAGE)
		Phase.PARTS:
			_step_load(until, LINE_PARTS)
		Phase.PAINT:
			_step_load(until, LINE_PAINT)
		Phase.SOUND:
			_step_load(until, LINE_SOUND)
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
			_count(res)
		_done += 1
	_send_progress(line)
	if not _queue.is_empty():
		return
	match _phase:
		Phase.STAGE:
			_phase = Phase.PARTS
			_queue = _part_paths()
			_queue.append_array(_material_paths())
			_mark_phase(_queue.size())
			_send_progress(LINE_PARTS)
		Phase.PARTS:
			_phase = Phase.PAINT
			_queue = _paint_paths()
			_mark_phase(_queue.size())
			_send_progress(LINE_PAINT)
		Phase.PAINT:
			_phase = Phase.SOUND
			_queue = _sound_paths()
			_mark_phase(_queue.size())
			_send_progress(LINE_SOUND)
		Phase.SOUND:
			_read_ms = (Time.get_ticks_usec() - _started_usec) / 1000.0
			if _warm_drawn:
				_phase = Phase.LIGHTS
				_mark_phase(_warm_batches.size())
				_begin_warm()
				_send_progress(LINE_LIGHTS)
			else:
				_finish()


func _count(res: Resource) -> void:
	match _phase:
		Phase.STAGE:
			_scenes += 1
		Phase.PARTS:
			if res is PackedScene:
				_models += 1
			else:
				_materials += 1
		Phase.PAINT:
			_materials += 1
		Phase.SOUND:
			_sounds += 1


static func _read(path: String) -> Resource:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)


# ---------------------------------------------------------------- the warm draw

func _warm_wanted() -> bool:
	# A headless or dummy run has no renderer, so there is no pipeline to compile and no
	# texture to upload: the reading above is the whole warm up and the draw would only
	# cost frames. The dummy renderer reports no adapter name.
	return DisplayServer.get_name() != "headless" and RenderingServer.get_video_adapter_name() != ""


## What gets drawn, as a list of batches. Each batch is a list of jobs:
##   {"part": id}               the part bound with its runtime materials
##   {"part": id, "paint": pid} the same with a paint job on its livery
##   {"fx": flavour}            one particle emitter of that flavour, emitting
## On the slow tier everything is one batch, because there a frame is the unit of cost.
static func _plan_batches() -> Array:
	var jobs: Array = []
	for id in _part_ids():
		jobs.append({"part": id})
	var chassis := _paint_carrier()
	if chassis != "":
		for paint_id in Livery.ids():
			jobs.append({"part": chassis, "paint": str(paint_id)})
	for flavour in FxEmitters.FLAVOURS:
		jobs.append({"fx": flavour})
	var size := WARM_BATCH if RenderingServer.get_rendering_device() != null else jobs.size()
	var batches: Array = []
	var i := 0
	while i < jobs.size():
		batches.append(jobs.slice(i, i + size))
		i += size
	# Each dressed venue is a batch of its own: it is a whole arena.
	for venue in VENUE_SCENES:
		if ResourceLoader.exists(str(venue)):
			batches.append([{"venue": str(venue)}])
	return batches


## The chassis every paint job is drawn on: the first chassis in the catalogue that has
## a model. The pipeline a paint job needs is the livery material with its detail overlay,
## which is the same whichever chassis wears it.
static func _paint_carrier() -> String:
	var parts: Dictionary = PartsCatalogue.manifest().get("parts", {}) as Dictionary
	for id in _part_ids():
		var entry: Dictionary = parts[id] as Dictionary
		if str(entry.get("path", "")).contains("/chassis/") and PartVisuals.has_model(str(id)):
			return str(id)
	return ""


## A world of its own, one camera under the stage environment, and the three light kinds
## the stage and the arena use, with shadows on, so the variants compiled here are the
## ones the stage will ask for.
func _begin_warm() -> void:
	_warm_started_usec = Time.get_ticks_usec()
	_warm_root = SubViewport.new()
	_warm_root.name = "WarmUpViewport"
	_warm_root.size = WARM_SIZE
	_warm_root.own_world_3d = true
	_warm_root.transparent_bg = true
	_warm_root.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_warm_root)

	var camera := Camera3D.new()
	camera.current = true
	var env := _read(STAGE_ENV) as Environment
	if env != null:
		camera.environment = env
	_warm_root.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 1.2, 5.5), Vector3.ZERO, Vector3.UP)

	var key := SpotLight3D.new()
	key.shadow_enabled = true
	_warm_root.add_child(key)
	key.look_at_from_position(Vector3(0.9, 2.2, 1.4), Vector3.ZERO, Vector3.UP)

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
	_warm_frames = 0


## One batch per slice, then WARM_FRAMES frames to draw it. The batch is freed before the
## next one is stood up, so the peak is one batch of meshes and no more.
func _step_warm() -> void:
	if (Time.get_ticks_usec() - _warm_started_usec) / 1000.0 > WARM_CAP_MS:
		push_warning("ArenaWarmUp: the warm draw passed %d ms; finishing, the rest draws lazily"
			% int(WARM_CAP_MS))
		_finish()
		return
	# Give the batch that is standing there its frames to be drawn in.
	if _warm_holder != null and _warm_holder.get_child_count() > 0:
		if _warm_frames < WARM_FRAMES:
			_warm_frames += 1
			return
		for child in _warm_holder.get_children():
			_warm_holder.remove_child(child)
			child.queue_free()
		_warm_frames = 0
		_done += 1
		_send_progress(LINE_LIGHTS)

	if _warm_batches.is_empty():
		_finish()
		return

	var batch: Array = _warm_batches.pop_front()
	var x := -float(batch.size()) * 0.35
	for job_variant in batch:
		var node := _stand_up(job_variant as Dictionary)
		if node != null:
			node.position = Vector3(x, 0.0, 0.0)
			_warm_holder.add_child(node)
			_warmed += 1
		x += 0.7
	if _warm_holder.get_child_count() == 0:
		# Nothing in this batch could be stood up: count it and move on next frame.
		_done += 1


func _stand_up(job: Dictionary) -> Node3D:
	if job.has("fx"):
		return _emitter(int(job["fx"]))
	if job.has("venue"):
		return _venue(str(job["venue"]))
	var id := str(job.get("part", ""))
	var node := PartVisuals.instantiate(id)
	if node == null:
		return null
	# Bind with the RUNTIME materials, exactly as the stage and the fight do, so the
	# pipelines compiled here are the ones they will ask for. `Livery.current` is global
	# state the bind reads; it is set and put back inside this one call.
	var was: String = Livery.current
	Livery.current = str(job.get("paint", ""))
	PartVisuals.bind(node, WARM_LIVERY)
	Livery.current = was
	return node


## A dressed arena, whole, shrunk into the warm camera's view. Its bodies live in the warm
## viewport's own world, never the fight's, and it is freed with the batch.
static func _venue(path: String) -> Node3D:
	var scene := _read(path) as PackedScene
	if scene == null:
		return null
	var holder := Node3D.new()
	holder.name = "WarmVenue"
	holder.scale = Vector3.ONE * VENUE_WARM_SCALE
	holder.add_child(scene.instantiate())
	return holder


## One particle emitter of a flavour, dressed the way `FxEmitters` dresses its pool.
static func _emitter(flavour: int) -> Node3D:
	var p := GPUParticles3D.new()
	p.amount = int(FxEmitters.AMOUNTS[flavour])
	p.lifetime = float(FxEmitters.LIVES[flavour])
	p.process_material = FxEmitters._process_for(flavour)
	p.draw_pass_1 = FxEmitters._mesh_for(flavour)
	p.material_override = FxEmitters._material_for(flavour)
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.emitting = true
	return p


func _finish() -> void:
	_phase = Phase.DONE
	set_process(false)
	if _warm_root != null:
		_warm_root.queue_free()
		_warm_root = null
		_warm_holder = null
	_warm_batches = []
	var now := Time.get_ticks_usec()
	_finished_ms = (now - _started_usec) / 1000.0
	if _read_ms < 0.0:
		_read_ms = _finished_ms
	_draw_ms = (now - _warm_started_usec) / 1000.0 if _warm_started_usec > 0 else 0.0
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


## The scenes, environments, arena materials and FX textures and meshes.
static func _scene_paths() -> Array:
	var out: Array = []
	for path in SCENES:
		if ResourceLoader.exists(str(path)):
			out.append(str(path))
	for dir in SCENE_DIRS.keys():
		for path in _dir_paths(str(dir), SCENE_DIRS[dir] as Array):
			if not out.has(path):
				out.append(path)
	return out


## Every sound the mixer can ask for, plus anything else in the audio folder.
static func _sound_paths() -> Array:
	var out: Array = []
	for key in AudioMix.SOUNDS.keys():
		var path := str(AudioMix.SOUNDS[key])
		if ResourceLoader.exists(path) and not out.has(path):
			out.append(path)
	for path in _dir_paths(SOUND_DIR, ["wav", "ogg", "mp3"]):
		if not out.has(path):
			out.append(path)
	return out


## The loadable resources directly in `dir` with one of `extensions`. Uses
## `ResourceLoader.list_directory`, which sees through the `.import` and `.remap` files an
## exported pck holds in place of the sources.
static func _dir_paths(dir: String, extensions: Array) -> Array:
	var out: Array = []
	for name in ResourceLoader.list_directory(dir):
		var file := str(name)
		if file.ends_with("/"):
			continue
		if not extensions.has(file.get_extension()):
			continue
		var path := dir + file
		if ResourceLoader.exists(path):
			out.append(path)
	out.sort()
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


func _mark_phase(size: int) -> void:
	_phase_from = _done
	_phase_size = size


## The loading screen row the walk is on (STEP_*).
func step() -> int:
	match _phase:
		Phase.IDLE, Phase.STAGE:
			return STEP_HULL
		Phase.PARTS:
			return STEP_DRIVE
		Phase.PAINT:
			return STEP_ARMOUR
		Phase.SOUND:
			return STEP_WEAPON
		Phase.LIGHTS:
			return STEP_LIGHTS
	return STEP_DONE


## How far through its own phase's work the walk is, 0 to 1.
func step_fraction() -> float:
	if _phase == Phase.DONE or _phase_size <= 0:
		return 1.0
	return clampf(float(_done - _phase_from) / float(_phase_size), 0.0, 1.0)


func _send_progress(line: String) -> void:
	var fraction := 1.0 if _total <= 0 else clampf(float(_done) / float(_total), 0.0, 1.0)
	_send(MSG_PRELOAD_PROGRESS, {
		"done": _done,
		"total": _total,
		"fraction": fraction,
		"line": line,
		"step": step(),
		"step_fraction": step_fraction(),
	})


func _send_done() -> void:
	_send(MSG_PRELOAD_DONE, {
		"ms": _finished_ms,
		"read_ms": _read_ms,
		"draw_ms": _draw_ms,
		"scenes": _scenes,
		"models": _models,
		"materials": _materials,
		"sounds": _sounds,
		"warmed": _warmed,
	})
