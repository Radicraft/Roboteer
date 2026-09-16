extends SceneTree
## Wave F agent F3's frame cost probe for the scrap shower. Not a test: it prints
## numbers so docs/wave-f-f3-notes.md can quote a measured before and after.
##
##   Godot --headless --path Arena --script tests/_f3_budget_probe.gd
##
## Headless has the DUMMY renderer, so RenderingServer's per frame counters are all
## zero and nothing is rasterised. What headless CAN measure honestly is the CPU side
## of the effect (the per frame step cost of the pools) and the draw DATA the effect
## would hand a real renderer: how many MultiMesh banks exist, how many instances of
## each are live at the peak, and how many triangles that is. Those are the numbers
## that move when the shower changes shape, so those are the ones written down.

const STEP := 1.0 / 60.0
const SPAWN_AT := Vector3(-0.9, 0.34, 0.7)
const TARGET_AT := Vector3(1.1, 0.22, -0.6)

var _fx: FightFx = null
var _peak_us: int = 0
var _total_us: int = 0
var _frames: int = 0
var _peak_instances: int = 0
var _peak_banks: int = 0


class FakeHud extends RefCounted:
	var total: int = 0
	func bump(amount: int) -> void:
		total += amount


class FakeHost extends Node:
	signal message_from_host(message: Dictionary)
	func emit_message_to_host(_message: Dictionary) -> void:
		pass


func _initialize() -> void:
	_run()


func _run() -> void:
	var host := FakeHost.new()
	host.name = "__swiftgodotkit_bridge__"
	root.add_child(host)

	var packed: PackedScene = load("res://fx/fx.tscn") as PackedScene
	_fx = packed.instantiate() as FightFx
	root.add_child(_fx)
	await process_frame
	_fx.bind(FakeHud.new(), func(_id: String) -> Vector3: return TARGET_AT)
	# We step the shower by hand and time it, so the node's own _process is off.
	# The award is handed its damage event explicitly, in the order fight.gd produces
	# them (award inside the physics tick, event on the presentation drain).
	_fx.fixed_delta_override = 0.0
	_fx.set_process(false)

	print("renderer: display=%s rendering_device=%s"
		% [DisplayServer.get_name(), str(RenderingServer.get_rendering_device() != null)])
	print("")
	print("--- node census under FX ---")
	_census(_fx)
	print("")

	# A 30 scrap hit, then a 500 scrap hit that fills the pool, timed.
	await _time_shower(30, "30 scrap (a spinner scrape)")
	await _time_shower(500, "500 scrap (a panel off, pool saturating)")

	print("")
	print("--- draw data ---")
	_draw_data(_fx)
	print("")
	print("peak live pool instances seen: %d" % _peak_instances)
	print("peak banks drawing at once:    %d" % _peak_banks)
	print("step() cost: peak %.3f ms, mean %.3f ms over %d frames"
		% [_peak_us / 1000.0, (_total_us / maxf(1.0, float(_frames))) / 1000.0, _frames])
	print("RenderingServer draw calls this frame: %d (0 under the dummy renderer)"
		% RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	print("RenderingServer objects this frame:    %d"
		% RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	print("RenderingServer primitives this frame: %d"
		% RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))

	_fx.stop_all_audio()
	await create_timer(0.2).timeout
	root.remove_child(_fx)
	_fx.free()
	_fx = null
	root.remove_child(host)
	host.free()
	quit(0)


func _time_shower(amount: int, label: String) -> void:
	print("--- %s ---" % label)
	_fx.on_scrap_awarded("player-1", amount, SPAWN_AT)
	_fx.on_damage_event({
		"attacker": "player-1", "victim": "ai-1", "part": "armour_front",
		"severity": clampf(float(amount) / 40.0, 0.0, 1.0),
		"position": SPAWN_AT, "impulse": 120.0, "detached": amount > 40, "tick": 1,
	})
	var frames := int(4.0 / STEP)
	for i in frames:
		var t0 := Time.get_ticks_usec()
		_step(STEP)
		var dt := Time.get_ticks_usec() - t0
		_peak_us = maxi(_peak_us, dt)
		_total_us += dt
		_frames += 1
		var live: int = _fx.bolt_shower().visible_instance_count()
		_peak_instances = maxi(_peak_instances, live)
		_peak_banks = maxi(_peak_banks, _live_banks(_fx))
		await process_frame
	print("  pool free after: %d of %d" % [_fx.bolt_shower().free_slots(), FightTypes.BOLT_POOL])


func _step(dt: float) -> void:
	_fx.bolt_shower().step(dt)
	if _fx.particles() != null:
		_fx.particles().step(dt)


func _live_banks(node: Node) -> int:
	var n := 0
	for child in _all(node):
		if child is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = child
			if mmi.multimesh != null and mmi.visible and mmi.multimesh.instance_count > 0:
				var vis: int = mmi.multimesh.visible_instance_count
				if vis != 0:
					n += 1
	return n


func _census(node: Node) -> void:
	var nodes := _all(node)
	var counts := {}
	for c in nodes:
		var k := c.get_class()
		counts[k] = int(counts.get(k, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort()
	print("  %d nodes under FX" % nodes.size())
	for k in keys:
		print("    %-24s %d" % [str(k), int(counts[k])])


func _draw_data(node: Node) -> void:
	var total_instances := 0
	var total_tris := 0
	for c in _all(node):
		if c is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = c
			if mmi.multimesh == null or mmi.multimesh.mesh == null:
				print("  %-22s (no mesh)" % mmi.name)
				continue
			var tris := _tris(mmi.multimesh.mesh)
			total_instances += mmi.multimesh.instance_count
			total_tris += tris * mmi.multimesh.instance_count
			print("  %-22s %4d instances x %4d tris = %6d tris"
				% [mmi.name, mmi.multimesh.instance_count, tris, tris * mmi.multimesh.instance_count])
		elif c is GPUParticles3D:
			var p: GPUParticles3D = c
			print("  %-22s GPUParticles amount %d, lifetime %.2f" % [p.name, p.amount, p.lifetime])
	print("  TOTAL allocated MultiMesh: %d instances, %d triangles" % [total_instances, total_tris])
	# The allocated figure over counts badly once the scrap is split into banks: every
	# bank is allocated at the pool size, but the banks SHARE that one pool, so at most
	# BOLT_POOL pieces are ever drawn across all of them. What the renderer actually
	# sees in the worst frame is the fixed pools plus the pool's own slots filled with
	# the heaviest shape.
	var shower: BoltShower = _fx.bolt_shower()
	var pieces: ScrapPieces = shower.pieces()
	if pieces != null:
		var heaviest := 0
		for kind in ScrapPieces.KIND_COUNT:
			heaviest = maxi(heaviest, pieces.triangles_of(kind))
		var fixed := 0
		for c in _all(node):
			if c is MultiMeshInstance3D:
				var mmi: MultiMeshInstance3D = c
				if mmi.multimesh == null or mmi.multimesh.mesh == null:
					continue
				if str(mmi.name).begins_with("Scrap") and mmi.multimesh.instance_count == FightTypes.BOLT_POOL:
					continue
				fixed += _tris(mmi.multimesh.mesh) * mmi.multimesh.instance_count
		print("  REALISTIC worst frame: %d scrap slots x %d tris (heaviest shape) + %d fixed = %d triangles"
			% [FightTypes.BOLT_POOL, heaviest, fixed, FightTypes.BOLT_POOL * heaviest + fixed])


func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.size() > 0:
			n += idx.size() / 3
		else:
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			n += v.size() / 3
	return n


func _all(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	var queue: Array[Node] = [node]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		out.append(n)
		for c in n.get_children():
			queue.append(c)
	return out
