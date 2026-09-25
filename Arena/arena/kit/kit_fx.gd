class_name VenueFx extends RefCounted
## Venue effects built from code (docs/wave-a-kit-notes.md): pyro flame columns, spark
## fountains, confetti, hanging dust motes and light-beam cone cards. GPU particles and
## additive cards only; none of it reads or writes the simulation, and nothing here is
## random on the CPU (particle randomness is the GPU's own).
##
## Particle counts are per tier and listed in PARTICLES so the budget is one table.

const FLAME_TEX := "res://fx/textures/flame_soft.png"
const SPARK_TEX := "res://fx/textures/spark_glow.png"
const DUST_TEX := "res://fx/textures/dust_soft.png"
const BEAM_SHADER := "res://arena/kit/shaders/beam_cone.gdshader"
const NOISE_TEX := "res://arena/kit/textures/noise.png"

## Live particle ceilings per emitter kind and tier: high, medium, low.
const PARTICLES := {
	"flame": [56, 32, 12],
	"sparks": [100, 50, 20],
	"confetti": [260, 120, 40],
	"motes": [420, 160, 0],
	"grit": [70, 30, 0],
}


static func count(kind: String, tier: String) -> int:
	var row: Array = PARTICLES[kind]
	match tier:
		"high":
			return int(row[0])
		"medium":
			return int(row[1])
	return int(row[2])


## A pyro flame column: a one-shot burst of fire that rises about 3.5 m.
static func flame_column(tier: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Flame"
	p.amount = count("flame", tier)
	p.lifetime = 0.95
	p.one_shot = true
	p.explosiveness = 0.35
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 6, 4))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 6.0
	m.initial_velocity_min = 6.5
	m.initial_velocity_max = 9.0
	m.gravity = Vector3(0, 1.5, 0)
	m.damping_min = 2.0
	m.damping_max = 3.5
	m.scale_min = 0.9
	m.scale_max = 1.6
	m.scale_curve = _curve([Vector2(0, 0.35), Vector2(0.35, 1.0), Vector2(1, 1.5)])
	m.color_ramp = _ramp([
		[0.0, Color(1.0, 0.85, 0.5, 0.9)], [0.2, Color(1.0, 0.5, 0.12, 0.85)],
		[0.6, Color(0.75, 0.18, 0.04, 0.45)], [1.0, Color(0.15, 0.05, 0.02, 0.0)]])
	m.angle_min = -180.0
	m.angle_max = 180.0
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	q.material = _additive(FLAME_TEX, 1.5 if tier != "low" else 1.1, true)
	p.draw_pass_1 = q
	return p


## A spark fountain: a gerb that throws bright sparks up and lets them fall.
static func spark_fountain(tier: String, height: float = 4.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Sparks"
	p.amount = count("sparks", tier)
	p.lifetime = 1.5
	p.one_shot = true
	p.explosiveness = 0.15
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, height + 3, 8))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 16.0
	m.initial_velocity_min = sqrt(2.0 * 9.8 * height) * 0.7
	m.initial_velocity_max = sqrt(2.0 * 9.8 * height)
	m.gravity = Vector3(0, -9.8, 0)
	m.scale_min = 0.5
	m.scale_max = 1.0
	m.color_ramp = _ramp([
		[0.0, Color(1.0, 0.98, 0.9, 1.0)], [0.5, Color(1.0, 0.75, 0.3, 1.0)], [1.0, Color(1.0, 0.4, 0.1, 0.0)]])
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	q.material = _additive(SPARK_TEX, 3.5 if tier != "low" else 1.45, true)
	p.draw_pass_1 = q
	return p


## Confetti for the result: paper squares tumbling down over the arena.
static func confetti(tier: String, extent: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Confetti"
	p.amount = count("confetti", tier)
	p.lifetime = 5.0
	p.one_shot = true
	p.explosiveness = 0.6
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(-extent - Vector3(1, 8, 1), extent * 2.0 + Vector3(2, 10, 2))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extent
	m.direction = Vector3(0, -1, 0)
	m.spread = 40.0
	m.initial_velocity_min = 0.2
	m.initial_velocity_max = 1.2
	m.gravity = Vector3(0, -1.2, 0)
	m.damping_min = 0.5
	m.damping_max = 1.0
	m.angular_velocity_min = -360.0
	m.angular_velocity_max = 360.0
	m.hue_variation_min = -0.5
	m.hue_variation_max = 0.5
	m.color = Color(1.0, 0.35, 0.3)
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.035)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.roughness = 0.6
	q.material = mat
	p.draw_pass_1 = q
	return p


## Dust hanging in the flood light: slow, lit (so it only shows where light hits it).
static func motes(tier: String, extent: Vector3) -> GPUParticles3D:
	var n := count("motes", tier)
	if n <= 0:
		return null
	var p := GPUParticles3D.new()
	p.name = "Motes"
	p.amount = n
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.emitting = true
	p.local_coords = false
	p.visibility_aabb = AABB(-extent - Vector3.ONE, extent * 2.0 + Vector3(2, 2, 2))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extent
	m.direction = Vector3(0.3, 0.2, 0.1)
	m.spread = 180.0
	m.initial_velocity_min = 0.02
	m.initial_velocity_max = 0.12
	m.gravity = Vector3(0, -0.004, 0)
	m.scale_min = 0.5
	m.scale_max = 1.3
	m.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.15, Color(1, 1, 1, 1)], [0.85, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(DUST_TEX)
	mat.albedo_color = Color(1.0, 0.95, 0.85, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.55)
	mat.emission_energy_multiplier = 0.15
	mat.shadow_to_opacity = false
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Drifting grit: sparse hot flecks carried across the yard on the wind, streaked along
## their motion (the concept's sparks drifting over the far stands). Additive, dim.
static func grit(tier: String, extent: Vector3, wind: Vector3 = Vector3(0.9, -0.12, 0.5)) -> GPUParticles3D:
	var n := count("grit", tier)
	if n <= 0:
		return null
	var p := GPUParticles3D.new()
	p.name = "Grit"
	p.amount = n
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emitting = true
	p.local_coords = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.visibility_aabb = AABB(-extent - Vector3(4, 4, 4), extent * 2.0 + Vector3(8, 8, 8))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extent
	m.direction = wind.normalized()
	m.spread = 14.0
	m.initial_velocity_min = wind.length() * 0.6
	m.initial_velocity_max = wind.length() * 1.5
	m.gravity = Vector3(0, -0.05, 0)
	m.turbulence_enabled = tier == "high"
	m.turbulence_noise_strength = 0.4
	m.turbulence_noise_scale = 3.0
	m.turbulence_influence_min = 0.02
	m.turbulence_influence_max = 0.08
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.1, Color(1, 1, 1, 1)], [0.7, Color(1, 0.8, 0.6, 0.8)], [1.0, Color(1, 0.6, 0.4, 0)]])
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.16)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(SPARK_TEX)
	mat.albedo_color = Color(1.0, 0.72, 0.42)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_fog = true
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## A light beam card from `from` (the lamp) to `to`, with radius `r0` at the lamp and
## `r1` at the far end. Returns the MeshInstance3D and its own material (to animate).
static func beam(from: Vector3, to: Vector3, r0: float, r1: float, colour: Color,
		strength: float) -> MeshInstance3D:
	var length := from.distance_to(to)
	var cyl := CylinderMesh.new()
	cyl.top_radius = r0
	cyl.bottom_radius = r1
	cyl.height = length
	cyl.radial_segments = 20
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = load(BEAM_SHADER)
	mat.set_shader_parameter("beam_color", colour)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("noise_tex", load(NOISE_TEX))
	cyl.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Beam"
	mi.mesh = cyl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aim_beam(mi, from, to)
	return mi


## Point an existing beam (its +Y is the lamp end).
static func aim_beam(mi: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var up := (from - to).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var fwd := side.cross(up).normalized()
	mi.transform = Transform3D(Basis(side, up, fwd), (from + to) * 0.5)


static func _additive(tex_path: String, energy: float, vertex_colour: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = load(tex_path)
	mat.albedo_color = Color(energy, energy, energy, 1.0)
	mat.vertex_color_use_as_albedo = vertex_colour
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 2.0
	for pt in points:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(float(s[0]))
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t
