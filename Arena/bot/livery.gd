class_name Livery extends RefCounted
## The ten cosmetic paint jobs of brief v5 section 7, as materials.
##
## One job: turn (the machine's livery colour, a paint job id) into the material
## `PartVisuals`'s livery section hangs on every `livery` surface of the kit. The
## paint is a Godot DETAIL map over the existing painted-metal material, not a
## material of its own, so a paint job inherits the clear coat, the moulded
## grain, the normal map, the roughness and the texel density matching that
## `part_visuals.gd` already does. Nothing about a machine with no paint on it
## changes by a single byte: `painted()` is never called for an empty id.
##
## WHY DETAIL AND NOT A SHADER. The simulator renders through GL Compatibility
## and the phone through Forward+ (docs/graphics-bar.md). `detail_albedo`,
## `detail_normal` and `detail_blend_mode` are `BaseMaterial3D` features, which
## every renderer generates the same shader code for, so what the sim shows and
## what the phone shows differ only in lighting. A custom `ShaderMaterial` would
## have meant writing the clear coat, the normal mapping and the PBR by hand and
## maintaining two paths.
##
## THE TWO BLEND MODES, and why a paint job takes one or the other:
##
##   MIX  ALBEDO = mix(livery, overlay.rgb, overlay.a)
##        The overlay carries its OWN value, so the paint is achromatic over the
##        machine's colour: black hazard stripes, a pale racing stripe, carbon
##        black, bright circuit traces. This is what a real two-pack paint job
##        or a printed wrap does.
##   MUL  ALBEDO = mix(livery, livery * overlay.rgb, overlay.a)
##        The overlay only shades the livery, so the paint STAYS the player's
##        colour: a works camo scheme, hexagonal plate with its seams in shadow,
##        and the micro detail on the two metals. It can darken, never brighten,
##        which is why anything needing a light mark is MIX.
##
## One texture therefore serves every livery colour, which is the whole point:
## ten paint jobs times six liveries would otherwise have been sixty textures.
##
## The two metals (chrome, champion gold) are mostly MATERIAL, not texture. A
## mirror is metallic 1.0 and roughness 0.05; no albedo map can fake that. They
## null the base's metallic and roughness textures (hdpe ships a constant ZERO
## metallic map, which would multiply any metallic scalar to nothing) and set
## the scalars directly, and their overlay carries only the polish swirl and the
## engine turning.
##
## Art and the tiling method: docs/paint-jobs.md. Built by Tools/paint/make_paint.py.

const TEXTURE_DIR := "res://assets/textures/paint/"

## The paint job of the machine being built RIGHT NOW, or "" for plain livery.
##
## The livery material is reached through eleven call sites in `bot.gd`,
## `chassis_base.gd` and six weapon scripts, none of which are this agent's
## files and all of which run inside `Bot.setup()`. Rather than thread a paint
## id through all of them, whoever is about to build a machine says which paint
## it wears and clears it afterwards (`fight.gd` for both bots and the house
## bot, `workshop/stage.gd` for the turntable). Set and cleared around one
## synchronous `setup()` call, so two machines with two different paints in the
## same fight cannot cross.
static var current := ""

## Albedo compensation for the base material's texture mean.
##
## `hdpe_moulded_albedo.png` is graded to a mean of 0.72 so a livery colour
## multiplied through it keeps its moulding grain (docs/graphics-textures-notes.md).
## For a METAL that grain is right but the darkening is not: the albedo of a
## metal is its specular colour, so 0.72 of gold is a duller gold rather than a
## dimmer one. The metals scale their albedo back up by this, which lands the
## mean on the real value and lets the brightest grain run about 18 % over it.
const METAL_GRAIN_COMPENSATION := 1.35

## Per paint job. `blend` and `normal` describe the overlay; everything else is
## a material change, and a key that is absent leaves the base material alone.
##
##   blend      BaseMaterial3D.BLEND_MODE_MIX or _MUL, as described above
##   normal     true when a `<id>_normal.png` ships (the embossed four)
##   metallic   nulls the base metallic MAP and sets this scalar
##   roughness  nulls the base roughness MAP and sets this scalar
##   clearcoat  0.0 turns the clear coat off, otherwise its strength
##   albedo     the metal's own albedo, before the grain compensation
##   livery_mix how much of the player's colour survives in that metal
##   normal_scale  the base normal map's depth, pulled down on the metals
const JOBS := {
	"paint_hazard": {
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "normal": false,
	},
	"paint_racing": {
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "normal": false,
	},
	"paint_camo": {
		"blend": BaseMaterial3D.BLEND_MODE_MUL, "normal": false,
		# Camo is flat, not glossy: a machine that wants to be hard to see does
		# not wear three coats of lacquer.
		"clearcoat": 0.10, "clearcoat_roughness": 0.65, "roughness": 0.82,
	},
	"paint_chequer": {
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "normal": true,
	},
	"paint_flames": {
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "normal": false,
		# A flame job is a show finish: more clear coat than anything else here.
		"clearcoat": 0.60, "clearcoat_roughness": 0.10,
	},
	"paint_carbon": {
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "normal": true,
		# Carbon is a weave under lacquer. The lacquer is the whole look.
		"clearcoat": 0.85, "clearcoat_roughness": 0.06, "roughness": 0.34,
	},
	"paint_chrome": {
		"blend": BaseMaterial3D.BLEND_MODE_MUL, "normal": false,
		"metallic": 1.0, "roughness": 0.055, "clearcoat": 0.0,
		# Chrome's own albedo is darker than people expect; it reads bright
		# because it is a mirror, not because it is white.
		"albedo": Color(0.78, 0.80, 0.84), "livery_mix": 0.14,
		"normal_scale": 0.30,
	},
	"paint_circuit": {
		"blend": BaseMaterial3D.BLEND_MODE_MIX, "normal": true,
		"clearcoat": 0.45, "clearcoat_roughness": 0.14,
	},
	"paint_hex": {
		"blend": BaseMaterial3D.BLEND_MODE_MUL, "normal": true,
		"roughness": 0.58,
	},
	"paint_gold": {
		"blend": BaseMaterial3D.BLEND_MODE_MUL, "normal": false,
		"metallic": 1.0, "roughness": 0.24, "clearcoat": 0.0,
		"albedo": Color(1.00, 0.78, 0.34), "livery_mix": 0.0,
		"normal_scale": 0.40,
	},
}

## paint id + "|albedo" or "|normal" -> Texture2D. Textures are immutable and
## shared by every machine in the fight, so this is never cleared.
static var _textures: Dictionary = {}


## Every paint job id, in the order `Shared/parts.json` lists them.
static func ids() -> Array:
	return JOBS.keys()


static func has(paint_id: String) -> bool:
	return paint_id != "" and JOBS.has(paint_id)


## Say what the machine about to be built is wearing. An id this build does not
## know is the same as no paint, never an error: a save from a later build of
## the game must not stop a fight.
static func begin(bot_config: Dictionary) -> void:
	var id := str(bot_config.get("paint", ""))
	current = id if has(id) else ""


static func clear() -> void:
	current = ""


## The livery material with a paint job on it.
##
## `base` is `PartVisuals`'s painted-metal livery material for this colour,
## already carrying the albedo, normal, roughness and clear coat. This never
## mutates it: a duplicate comes back, and the caller caches that.
##
## Returns `base` UNCHANGED when the id is unknown or the overlay is missing
## from disk, so a build with no paint art in it renders exactly as it does
## today rather than losing the livery.
static func painted(base: StandardMaterial3D, colour: Color, paint_id: String) -> StandardMaterial3D:
	if base == null or not has(paint_id):
		return base
	var overlay := _texture(paint_id, "albedo")
	if overlay == null:
		return base
	var job: Dictionary = JOBS[paint_id]
	var material := base.duplicate() as StandardMaterial3D
	if material == null:
		return base

	if job.has("albedo"):
		var metal: Color = job["albedo"]
		var mixed := metal.lerp(colour, float(job.get("livery_mix", 0.0)))
		material.albedo_color = Color(
			mixed.r * METAL_GRAIN_COMPENSATION,
			mixed.g * METAL_GRAIN_COMPENSATION,
			mixed.b * METAL_GRAIN_COMPENSATION, 1.0)
	if job.has("metallic"):
		# hdpe_moulded ships a constant ZERO metallic map and the scalar
		# MULTIPLIES it, so the map has to go or no metal is possible.
		material.metallic_texture = null
		material.metallic = float(job["metallic"])
	if job.has("roughness"):
		material.roughness_texture = null
		material.roughness = float(job["roughness"])
	if job.has("clearcoat"):
		var strength := float(job["clearcoat"])
		material.clearcoat_enabled = strength > 0.0
		material.clearcoat = strength
		material.clearcoat_roughness = float(job.get("clearcoat_roughness", 0.25))
	if job.has("normal_scale") and material.normal_enabled:
		# A strong normal on a metallic = 1.0 surface speckles at phone screen
		# footprints; G1 measures that in render_test.gd and the metallic
		# materials in the kit all carry a halved normal for it.
		material.normal_scale = float(job["normal_scale"])

	material.detail_enabled = true
	material.detail_blend_mode = job["blend"]
	# UV1, so the overlay rides the same `uv1_scale` that PartVisuals.density_matched
	# picks for this surface and the paint lands at the kit's texel density
	# instead of being stretched across a whole chassis.
	material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
	material.detail_albedo = overlay
	if bool(job.get("normal", false)):
		var relief := _texture(paint_id, "normal")
		if relief != null:
			material.detail_normal = relief
	return material


## The same paint job on the wave A painted master (`rb_painted.gdshader`), which is what
## the `livery` slot is now (docs/wave-a-materials-notes.md). Same JOBS table, same overlay
## textures, same two blend modes; the only differences are that the parameters are shader
## uniforms and there is no grain texture to compensate for (the master's albedo is the
## colour itself, so a metal's albedo is set straight).
##
## `hdpe` panels are still StandardMaterial3D and still go through `painted()` above.
static func painted_master(base: ShaderMaterial, colour: Color, paint_id: String) -> ShaderMaterial:
	if base == null or not has(paint_id):
		return base
	var overlay := _texture(paint_id, "albedo")
	if overlay == null:
		return base
	var job: Dictionary = JOBS[paint_id]
	var material := base.duplicate() as ShaderMaterial
	if job.has("albedo"):
		var metal: Color = job["albedo"]
		material.set_shader_parameter("albedo",
			metal.lerp(colour, float(job.get("livery_mix", 0.0))))
	if job.has("metallic"):
		material.set_shader_parameter("metallic", float(job["metallic"]))
		# A mirror has no room for breakup: +-0.08 on 0.055 would be a patchy mirror.
		material.set_shader_parameter("roughness_range", 0.02)
	if job.has("roughness"):
		material.set_shader_parameter("roughness", float(job["roughness"]))
	if job.has("clearcoat"):
		material.set_shader_parameter("clearcoat", float(job["clearcoat"]))
		material.set_shader_parameter("clearcoat_roughness",
			float(job.get("clearcoat_roughness", 0.05)))
	if job.has("normal_scale"):
		material.set_shader_parameter("normal_scale", float(job["normal_scale"]))
	material.set_shader_parameter("detail_enabled", true)
	material.set_shader_parameter("detail_blend",
		0 if int(job["blend"]) == BaseMaterial3D.BLEND_MODE_MIX else 1)
	material.set_shader_parameter("detail_albedo", overlay)
	if bool(job.get("normal", false)):
		var relief := _texture(paint_id, "normal")
		if relief != null:
			material.set_shader_parameter("detail_normal_enabled", true)
			material.set_shader_parameter("detail_normal", relief)
	return material


static func _texture(paint_id: String, kind: String) -> Texture2D:
	var key := paint_id + "|" + kind
	if _textures.has(key):
		return _textures[key]
	var path := TEXTURE_DIR + paint_id + "_" + kind + ".png"
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_textures[key] = texture
	return texture
