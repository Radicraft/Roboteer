extends SceneTree
## Generator for the three Environment resources in `res://render/` (agent G1).
##
##   Godot --headless --path Arena --script tests/_g1_make_envs.gd
##
## The resources are checked in and hand editable; this exists so that every value in
## them was set through the real Godot API and no hand written `.tres` key can be silently
## wrong. Re-run it after changing a number here, not instead of reading the file.
##
## Leading underscore: scripts/test-arena.sh treats `_*.gd` as helpers and never runs them.


func _initialize() -> void:
	_save(_arena_env(), "res://render/arena_env.tres")
	_save(_stage_env(), "res://render/stage_env.tres")
	_save(_default_env(), "res://render/default_env.tres")
	quit(0)


func _save(env: Environment, path: String) -> void:
	var status := ResourceSaver.save(env, path)
	print("%s -> %s" % [path, "ok" if status == OK else "FAILED %d" % status])


# ---------------------------------------------------------------- the Yard

## The arena: a cold grey blue room with one warm key. Art/direction/arena-mid-fight.png
## measures roughly four fifths cold grey blue with gold as the only saturated warm, so
## the environment must never add a second warm (docs/stage2-art-direction.md).
func _arena_env() -> Environment:
	var env := Environment.new()
	env.resource_name = "arena_env"
	# No sky. A sky would light the walls from above and flatten the whole room.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.26, 0.29, 0.34)
	env.background_energy_multiplier = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# A dark studio: cool bounce off the steel walls, not daylight.
	env.ambient_light_color = Color(0.62, 0.70, 0.84)
	# 0.22, was 0.55. The first shoot came back with the arena floor at about 215/255,
	# a flat bright grey-blue with no shading left in it. Ambient lifts every surface at
	# once, so it is the first thing to come down, not the exposure.
	env.ambient_light_energy = 0.18

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# 0.8, was 1.15, and a wider white point so the floor sits in the rolloff instead of
	# against it. Target: floor mean 110 to 130 of 255, the reference render's mid grey.
	env.tonemap_exposure = 0.7
	env.tonemap_white = 1.9

	# Glow: only the things that are meant to be bright. The bolts, the spark cores, the
	# spike tips and the bot cores are emissive above 1.0; the floor and the walls are not.
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 12.0
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.35)
	env.set_glow_level(2, 0.85)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.6)
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)

	# Contact shadow under every wheel, bolt head and panel gap. This is most of what
	# separates a PS4 class frame from a flat one, so it is the LAST thing to drop.
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 2.6
	env.ssao_power = 1.8
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	# AO normally only darkens ambient, and the ambient is now small, so without a share
	# of the direct light the wall corners and the shadow under a bot would not read at
	# all. 0.35 is enough to see it and not enough to look like dirt.
	env.ssao_light_affect = 0.35
	env.ssao_ao_channel_affect = 0.0

	# The floor is scuffed steel, so the reflection is short and broken rather than a
	# mirror. fade_out at 6 m keeps it to the pool of floor around the bots.
	env.ssr_enabled = true
	env.ssr_max_steps = 32
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 6.0
	env.ssr_depth_tolerance = 0.2

	# Enough depth haze to separate the far wall from the near one, no more.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.55, 0.62, 0.72)
	env.fog_light_energy = 0.7
	env.fog_sun_scatter = 0.0
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.02
	return env


# ---------------------------------------------------------------- the stage

## The menu and workshop stage: black, with everything visible put there by a light
## (docs/stage4-stage-notes.md). On the high tier the haze is real volumetric fog and the
## three spots become light shafts; on medium and low the stage keeps C2's additive cones.
func _stage_env() -> Environment:
	var env := Environment.new()
	env.resource_name = "stage_env"
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.40, 0.60)
	# 0.05 and no higher: ambient is what turned the first stage build into a milky wash,
	# and workshop_test.gd asserts it.
	env.ambient_light_energy = 0.05

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Slightly hotter than the arena because ACES crushes an almost black frame and the
	# beams are the only thing carrying value.
	env.tonemap_exposure = 1.25
	env.tonemap_white = 1.4

	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.05
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 12.0
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.4)
	env.set_glow_level(2, 0.9)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.75)
	env.set_glow_level(5, 0.3)
	env.set_glow_level(6, 0.0)

	# The stage floor is wet looking dark metal in the key art, so the bot and the beams
	# land in it. There is almost nothing else on screen to reflect.
	# SSR OFF on the stage. The first shoot showed it buying nothing (one bot on a black
	# floor reflects almost nothing) while costing a pipeline compile, and the high tier
	# stage took 11 seconds to produce its first frame.
	env.ssr_enabled = false
	# Nothing to occlude: the set is three meshes and a bot on a black floor.
	env.ssao_enabled = false

	# Real dry ice and real shafts, high tier only. GraphicsQuality.apply() switches this
	# off on medium and low, where the stage keeps its additive cones and billboards.
	env.volumetric_fog_enabled = true
	# 0.05 is Godot's own default and four times what this shipped at first. At 0.012 the
	# high tier stage rendered with NO visible fog and no shafts at all: the density, the
	# FogVolume densities and the lights' volumetric energy were each far too low, and
	# three small numbers multiplied together came to nothing.
	env.volumetric_fog_density = 0.05
	env.volumetric_fog_albedo = Color(0.86, 0.91, 1.0)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_emission_energy = 0.0
	env.volumetric_fog_gi_inject = 0.0
	# Forward scattering: a beam is far brighter looked into than across, which is the
	# whole reason a stage light reads as a shaft.
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 16.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9

	env.fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.0
	return env


# ---------------------------------------------------------------- the fallback

## `rendering/environment/defaults/default_environment`: what a 3D scene with no
## WorldEnvironment of its own gets. Deliberately cheap, because it is a safety net for
## scenes nobody art directed, not a look.
func _default_env() -> Environment:
	var env := Environment.new()
	env.resource_name = "default_env"
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.16, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.80)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	env.glow_enabled = false
	env.ssao_enabled = false
	env.ssr_enabled = false
	env.fog_enabled = false
	return env
