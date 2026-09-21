class_name FxGlowPool extends MultiMeshInstance3D
## Sustained additive billboards in numbered slots: a glow that is HELD at a level
## the caller writes every frame, rather than popped and faded (wave P, agent F).
##
## `FxFlashPool` is the pop: it owns its own decay and the caller only says "now".
## Two wave P parts need the opposite. The overcharge core's heat has to rise with
## the cook value over half a minute and fall again the moment the weapon idles, and
## the hover's thruster pods pulse with the throttle. Neither is an event, so neither
## can be a flash, and a glow that is a real light for every machine is four more
## shadowless omnis than the budget has (`FxLightPool` is capped at 4 for the whole
## fight).
##
## ONE MULTIMESH, N SLOTS, and a slot is the CALLER'S: `set_glow(2, ...)` always
## writes the same instance, so a caller holding a glow does not have to remember a
## handle and cannot leak one. A slot at level 0 has a zero basis and the renderer
## draws nothing for it.
##
## Presentation only. No `_process`, no timers, no per frame cost beyond what the
## caller writes: this node has no `step()` at all, which is the point of it.
##
##     var glow := FxGlowPool.new()
##     add_child(glow)
##     glow.configure(6, Color(1.0, 0.45, 0.12), FxMaterials.FLAME_ENERGY, aabb)
##     glow.set_glow(0, core_world, 0.22, cook)      # every frame
##     glow.clear_glow(0)                            # when it stops

var _hidden := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

var _count: int = 0
var _live: int = 0
var _on := PackedByteArray()
## The level each slot is held at. Kept HERE rather than read back off the MultiMesh:
## `MultiMesh.get_instance_color` does not return what was written under the dummy
## renderer a headless test runs on, so a test that read the instance back would be
## asserting on the renderer rather than on this node.
var _level := PackedFloat32Array()


func _ready() -> void:
	set_process(false)


## Build the pool. `colour` and `nominal` are the material's; a per slot `tint`
## multiplies them, so one pool serves a hot orange core and a cold blue pod.
func configure(count: int, colour: Color, nominal: float, aabb: AABB) -> void:
	_count = maxi(1, count)

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)           # unit quad; the instance scale is the size

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = _count
	multimesh = mm
	material_override = FxMaterials.additive(
		FxMaterials.texture("spark_glow.png"), colour, nominal, true)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	custom_aabb = aabb

	_on.resize(_count)
	_level.resize(_count)
	_live = 0
	for i in _count:
		_on[i] = 0
		_level[i] = 0.0
		mm.set_instance_transform(i, _hidden)
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))


## Hold slot `slot` at `level` (0..1). `size` is the quad's width in metres at level
## 1; the quad also shrinks a little as it fades, so a dying glow recedes rather than
## going transparent in place. Level 0 or less clears the slot.
func set_glow(slot: int, at: Vector3, size: float, level: float,
		tint: Color = Color.WHITE) -> void:
	if multimesh == null or slot < 0 or slot >= _count:
		return
	var l := clampf(level, 0.0, 1.0)
	if l <= 0.001:
		clear_glow(slot)
		return
	if _on[slot] == 0:
		_on[slot] = 1
		_live += 1
	_level[slot] = l
	var s: float = size * lerpf(0.55, 1.0, l)
	multimesh.set_instance_transform(slot,
		Transform3D(Basis().scaled(Vector3(s, s, s)), at))
	multimesh.set_instance_color(slot, Color(tint.r, tint.g, tint.b, l))


func clear_glow(slot: int) -> void:
	if multimesh == null or slot < 0 or slot >= _count or _on[slot] == 0:
		return
	_on[slot] = 0
	_level[slot] = 0.0
	_live -= 1
	multimesh.set_instance_transform(slot, _hidden)
	multimesh.set_instance_color(slot, Color(1.0, 1.0, 1.0, 0.0))


func clear_all() -> void:
	for i in _count:
		clear_glow(i)


## --- introspection, used by Arena/tests/fx_test.gd -------------------------

func pool_size() -> int:
	return _count


func live_count() -> int:
	return _live


func level_of(slot: int) -> float:
	if slot < 0 or slot >= _count:
		return 0.0
	return _level[slot]
