class_name DamageDecals extends Node3D
## The damage layer: scratches and scorches projected onto whatever they land on.
##
## brief section 13 and docs/graphics-bar.md: "damage carries the visual load". A hit
## leaves a mark on the floor and on the panel it struck, and those marks accumulate over
## a fight. Decal nodes are used rather than UV painted textures because a Decal projects
## onto the bot, the floor and the walls alike without anyone owning a second texture set.
##
## PRESENTATION ONLY. Nothing here is read by the simulation, nothing here consumes the
## shared RNG, and every call is safe to make from `_process`. A decal never affects
## physics, so a fight and its replay are identical whether decals drew or not.
##
## ## API (agents R and B)
##
## ```gdscript
## const DecalsScript := preload("res://render/damage_decals.gd")
##
## var decals: DamageDecals = DecalsScript.new()   # or add res://render/damage_decals.tscn
## decals.name = "DamageDecals"
## world.add_child(decals)                          # inside the fight's SubViewport world
##
## # on a damage event: a scratch across the panel that was hit
## decals.add_scratch(info["position"], info.get("normal", Vector3.UP), 0.22)
## # on a heavy hit, a flame or a spark shower: a scorch on the floor under it
## decals.add_scorch(Vector3(info["position"].x, 0.0, info["position"].z), 0.45)
##
## decals.clear()                                   # between fights, if the node survives
## ```
##
## `add_scratch(position, normal, size)` and `add_scorch(position, size)` both return the
## `Decal` they placed, or `null` when decals are off. `size` is the width in metres.
##
## ## Pooling
##
## At most `MAX_DECALS` (48) exist. Adding the 49th recycles the oldest, and the oldest
## few are already faded down to nothing by then (`FADE_BAND`), so nothing ever pops out
## of the frame. The fade is computed on add, not per frame: no `_process`, no timers, no
## per frame cost at all once the marks are placed.
##
## ## Tiers
##
## Decals are not supported by the Compatibility renderer, so on the low tier every call
## is a no op that still returns cleanly. The API exists on every tier by design: callers
## must never branch on the renderer themselves.

const SCRATCH_ALBEDO := "res://assets/textures/scratch_decal/scratch_decal_albedo.png"
const SCRATCH_NORMAL := "res://assets/textures/scratch_decal/scratch_decal_normal.png"
const SCORCH_ALBEDO := "res://assets/textures/scorch/scorch_albedo.png"
const SCORCH_NORMAL := "res://assets/textures/scorch/scorch_normal.png"

## The whole budget. 48 decals is about 90 seconds of a busy fight at the rate damage
## events actually arrive, and it is well inside the Forward+ decal cluster on an A19.
const MAX_DECALS := 48
## How many of the oldest decals are on their way out at any time. The oldest is at zero
## opacity by the time it is recycled.
const FADE_BAND := 8

## Projection depth as a fraction of the decal's width. A scratch has to reach through a
## bevelled panel edge without also painting the part behind it.
const DEPTH_RATIO := 0.5
## Above this angle between the decal's axis and a surface, the decal stops drawing on
## it. Keeps a floor scorch off the wall it is next to.
const NORMAL_FADE := 0.45

const SCRATCH_TINT := Color(0.86, 0.88, 0.92, 1.0)
const SCORCH_TINT := Color(0.16, 0.14, 0.13, 1.0)
## A scratch is a bright scuff that mostly shows as a normal map break, so it mixes its
## albedo in only partly. A scorch replaces the colour under it.
const SCRATCH_ALBEDO_MIX := 0.65
const SCORCH_ALBEDO_MIX := 0.95

var _enabled := true
var _pool: Array[Decal] = []
var _order: Array[Decal] = []        # oldest first
var _scratch_albedo: Texture2D = null
var _scratch_normal: Texture2D = null
var _scorch_albedo: Texture2D = null
var _scorch_normal: Texture2D = null
var _textures_loaded := false


func _ready() -> void:
	var quality := _quality()
	if quality != null and quality.has_method("allows"):
		_enabled = bool(quality.call("allows", "decals"))


# ---------------------------------------------------------------- public API

## A scratch mark on the surface whose outward normal is `normal`, `size` metres across.
## `normal` may be zero, in which case the mark is projected straight down.
##
## `attach_to` (combat feel B4): the body that was struck. The mark is parented to it and
## rides with it, so a machine no longer drives out from under its own damage (and the
## empty decal box no longer paints whatever passes through it afterwards). Null keeps the
## old world-space mark, which is right for the floor and the walls.
func add_scratch(position: Vector3, normal: Vector3, size: float,
		attach_to: Node3D = null) -> Decal:
	return _place(position, normal, size, false, attach_to)


## A scorch smudge projected straight down: the floor under an impact, a flame or a
## spark shower. Use add_scratch() with a normal for a mark on a vertical panel.
func add_scorch(position: Vector3, size: float, attach_to: Node3D = null) -> Decal:
	return _place(position, Vector3.UP, size, true, attach_to)


## Every mark, gone. Called between fights when the node outlives the world.
func clear() -> void:
	for decal in _pool:
		if is_instance_valid(decal):
			decal.visible = false
	_order.clear()


## QA and the headless test: force the pool on even where the renderer would not show it,
## or off to measure what the decals cost.
func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		clear()


func is_enabled() -> bool:
	return _enabled


## How many marks are on screen.
func active_count() -> int:
	return _order.size()


func capacity() -> int:
	return MAX_DECALS


## The decals in age order, oldest first. The test reads it; nothing else should.
func decals() -> Array[Decal]:
	return _order.duplicate()


# ---------------------------------------------------------------- internals

func _place(position: Vector3, normal: Vector3, size: float, scorch: bool,
		attach_to: Node3D = null) -> Decal:
	if not _enabled:
		return null
	_load_textures()
	var decal := _next_decal()
	if decal == null:
		return null

	var width := maxf(size, 0.02)
	decal.size = Vector3(width, width * DEPTH_RATIO, width)
	decal.texture_albedo = _scorch_albedo if scorch else _scratch_albedo
	decal.texture_normal = _scorch_normal if scorch else _scratch_normal
	decal.albedo_mix = SCORCH_ALBEDO_MIX if scorch else SCRATCH_ALBEDO_MIX
	decal.modulate = SCORCH_TINT if scorch else SCRATCH_TINT
	decal.normal_fade = NORMAL_FADE
	decal.upper_fade = 0.3
	decal.lower_fade = 0.3
	decal.visible = true
	# Parent first, then place in world space, so the mark lands where it was struck and
	# then follows the body. A recycled mark comes home to this node first.
	var parent: Node = attach_to if attach_to != null and is_instance_valid(attach_to) \
		and attach_to.is_inside_tree() else self
	if decal.get_parent() != parent:
		if decal.get_parent() != null:
			decal.get_parent().remove_child(decal)
		parent.add_child(decal)
	decal.global_transform = _projection(position, normal)

	_order.append(decal)
	_refresh_fade()
	return decal


## A Decal projects along its own -Y, so the surface normal becomes its +Y. A random spin
## about that axis stops fifty scratches reading as one repeated stamp; it is drawn from
## a private RNG, never the fight's, so it can never change an outcome.
func _projection(position: Vector3, normal: Vector3) -> Transform3D:
	var up := normal
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	up = up.normalized()
	var reference := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var right := reference.cross(up).normalized()
	var forward := up.cross(right).normalized()
	var basis := Basis(right, up, forward).rotated(up, randf() * TAU)
	return Transform3D(basis, position)


## The pool: grow to MAX_DECALS, then recycle the oldest.
func _next_decal() -> Decal:
	# A mark that rode on a body is freed with it (a part freed, a world torn down).
	_pool = _pool.filter(func(d: Decal) -> bool: return is_instance_valid(d))
	_order = _order.filter(func(d: Decal) -> bool: return is_instance_valid(d))
	if _order.size() >= MAX_DECALS:
		var oldest: Decal = _order.pop_front()
		if is_instance_valid(oldest):
			return oldest
	for decal in _pool:
		if is_instance_valid(decal) and not _order.has(decal):
			return decal
	if _pool.size() >= MAX_DECALS:
		return null
	var made := Decal.new()
	made.name = "Decal%02d" % _pool.size()
	made.visible = false
	made.cull_mask = 0xFFFFF
	add_child(made)
	_pool.append(made)
	return made


## The oldest FADE_BAND decals are on a ramp to zero opacity, so the one that is about to
## be recycled is already invisible. Recomputed on add, which is the only time the order
## changes: no per frame work.
func _refresh_fade() -> void:
	var count := _order.size()
	for i in count:
		var decal := _order[i]
		if not is_instance_valid(decal):
			continue
		var from_oldest := i
		var alpha := 1.0
		if count >= MAX_DECALS - FADE_BAND and from_oldest < FADE_BAND:
			alpha = float(from_oldest + 1) / float(FADE_BAND + 1)
		var tint := decal.modulate
		tint.a = alpha
		decal.modulate = tint


func _load_textures() -> void:
	if _textures_loaded:
		return
	_textures_loaded = true
	_scratch_albedo = _texture(SCRATCH_ALBEDO)
	_scratch_normal = _texture(SCRATCH_NORMAL)
	_scorch_albedo = _texture(SCORCH_ALBEDO)
	_scorch_normal = _texture(SCORCH_NORMAL)


## A missing texture is a warning, not a crash: G2 owns these files and this node has to
## keep working in a checkout where a texture has been renamed.
func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("DamageDecals: missing texture " + path)
		return null
	return load(path) as Texture2D


func _quality() -> Node:
	var script: GDScript = load("res://render/graphics_quality.gd") as GDScript
	if script == null:
		return null
	return script.call("resolve", self)
