class_name AudioMix extends Node
## The mixer. Every sound in the fight goes through here (docs/audio-notes.md).
##
## `FightFx` used to hold ten `AudioStreamPlayer`s and rotate them round robin. That
## works until two things happen at once that both matter: a rotating pool has no idea
## what it is cutting off, so a 30 bolt shower silently murders the bell. This node
## replaces it with a catalogue, per sound polyphony caps, variant rotation, a 3D voice
## pool for anything with a position in the arena, and the four bus mix.
##
##     var mix := AudioMix.new()
##     add_child(mix)
##     mix.play("impact_heavy", hit_position)            # picks one of three variants
##     mix.play("bolt_collect", null, 0.0, 1.26)         # non positional, pitched
##     mix.start_loop("motor:player-1", "motor_loop", bot_position)
##     mix.set_loop("motor:player-1", 1.2, -14.0)
##     mix.stop_loop("motor:player-1")
##
## HARD RULE (spec §7): this is presentation. It never touches physics state and it
## never reads the fight's seeded RNG. Variant choice uses this node's OWN generator,
## because a presentation node drawing from the shared rng would change the fight's
## random sequence and desync a replay. That generator is seeded with a constant, so a
## headless run is still reproducible; the variation that matters is between
## consecutive hits inside one fight, not between one run and the next.

const BUS_LAYOUT := "res://fx/audio_bus_layout.tres"
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENCE := "Ambience"
const BUS_UI := "UI"

## Every wav in Arena/audio, by the name the game asks for. `FightFx.SOUNDS` is this
## same table (fx_test walks it and checks each one imports as an AudioStreamWAV).
const SOUNDS := {
	# feedback
	"bolt_collect": "res://audio/bolt_collect.wav",
	"impact_light_1": "res://audio/impact_light_1.wav",
	"impact_light_2": "res://audio/impact_light_2.wav",
	"impact_light_3": "res://audio/impact_light_3.wav",
	"impact_heavy_1": "res://audio/impact_heavy_1.wav",
	"impact_heavy_2": "res://audio/impact_heavy_2.wav",
	"impact_heavy_3": "res://audio/impact_heavy_3.wav",
	# parts coming off
	"wheel_off": "res://audio/wheel_off.wav",
	"panel_off": "res://audio/panel_off.wav",
	# weapons
	"flipper_fire": "res://audio/flipper_fire.wav",
	"axe_swing": "res://audio/axe_swing.wav",
	"axe_hit": "res://audio/axe_hit.wav",
	"ram_hit": "res://audio/ram_hit.wav",
	"crusher_clamp": "res://audio/crusher_clamp.wav",
	# loops
	"motor_loop": "res://audio/motor_loop.wav",
	"spin_up_loop": "res://audio/spin_up_loop.wav",
	"saw_cut_loop": "res://audio/saw_cut_loop.wav",
	"flame_loop": "res://audio/flame_loop.wav",
	"grinder_loop": "res://audio/grinder_loop.wav",
	"disc_spin_loop": "res://audio/disc_spin_loop.wav",
	# arena hazards
	"spikes": "res://audio/spikes.wav",
	"pit_open": "res://audio/pit_open.wav",
	"flame_jet": "res://audio/flame_jet.wav",
	"ram_crush": "res://audio/ram_crush.wav",
	# wave A: the shared warning language. Each hazard's own wind-up, played exactly
	# HazardTelegraph.WARN_LEAD_S before it acts (docs/wave-a-hazards-notes.md).
	"warn_spikes": "res://audio/warn_spikes.wav",
	"warn_flame": "res://audio/warn_flame.wav",
	"warn_ram": "res://audio/warn_ram.wav",
	"warn_pit": "res://audio/warn_pit.wav",
	# fight and UI
	"countdown_tick": "res://audio/countdown_tick.wav",
	"ko_tick": "res://audio/ko_tick.wav",
	"bell": "res://audio/bell.wav",
	# the endgame (brief v4 §2 and §10 item 2, agent G6)
	"endgame_horn": "res://audio/endgame_horn.wav",
	"endgame_drone_loop": "res://audio/endgame_drone_loop.wav",
	# the movement layer (wave F, agent F2). One whine, three rolling surfaces (a
	# tyre, a track and an omni's rollers), a skid, a scrape and the landing thud.
	"drive_whine_loop": "res://audio/drive_whine_loop.wav",
	"roll_wheel_loop": "res://audio/roll_wheel_loop.wav",
	"track_clatter_loop": "res://audio/track_clatter_loop.wav",
	"roll_omni_loop": "res://audio/roll_omni_loop.wav",
	"skid_loop": "res://audio/skid_loop.wav",
	"scrape_loop": "res://audio/scrape_loop.wav",
	"chassis_thud_1": "res://audio/chassis_thud_1.wav",
	"chassis_thud_2": "res://audio/chassis_thud_2.wav",
	"chassis_thud_3": "res://audio/chassis_thud_3.wav",
	# WAVE P (agent F). The six weapons, the three drives, the overcharge core and
	# the reactive plate. Everything here is positional: it all belongs to a machine.
	"arc_crackle_loop": "res://audio/arc_crackle_loop.wav",
	"arc_discharge_1": "res://audio/arc_discharge_1.wav",
	"arc_discharge_2": "res://audio/arc_discharge_2.wav",
	"prod_zap_1": "res://audio/prod_zap_1.wav",
	"prod_zap_2": "res://audio/prod_zap_2.wav",
	"drill_grind_loop": "res://audio/drill_grind_loop.wav",
	# One disc, played twice an octave apart (WeaponFx.SAW_OCTAVE): two blades on one
	# arbor never run at the same speed, and two voices of one file at one pitch is a
	# phase problem rather than a second blade.
	"twin_saw_loop": "res://audio/twin_saw_loop.wav",
	"napalm_launch": "res://audio/napalm_launch.wav",
	"fire_patch_loop": "res://audio/fire_patch_loop.wav",
	"vortex_spin_loop": "res://audio/vortex_spin_loop.wav",
	"vortex_throw": "res://audio/vortex_throw.wav",
	"footfall_1": "res://audio/footfall_1.wav",
	"footfall_2": "res://audio/footfall_2.wav",
	"hover_fan_loop": "res://audio/hover_fan_loop.wav",
	"hover_skirt_loop": "res://audio/hover_skirt_loop.wav",
	"leg_servo_loop": "res://audio/leg_servo_loop.wav",
	"adaptive_track_loop": "res://audio/adaptive_track_loop.wav",
	"cook_warning": "res://audio/cook_warning.wav",
	"reactive_clang_1": "res://audio/reactive_clang_1.wav",
	"reactive_clang_2": "res://audio/reactive_clang_2.wav",
	# ambience
	"crowd_ambience_loop": "res://audio/crowd_ambience_loop.wav",
	# the crowd reacting (wave F). The bed is the room; these are the audience.
	"crowd_swell_1": "res://audio/crowd_swell_1.wav",
	"crowd_swell_2": "res://audio/crowd_swell_2.wav",
	"crowd_roar": "res://audio/crowd_roar.wav",
}

## Names that are really a set. `play("impact_heavy")` picks one of these, never the
## same one twice running, which is the whole reason three of each exist: a repeated
## sample at a repeated interval is the single most obvious "this is a game" tell.
const VARIANTS := {
	"impact_light": ["impact_light_1", "impact_light_2", "impact_light_3"],
	"impact_heavy": ["impact_heavy_1", "impact_heavy_2", "impact_heavy_3"],
	# A machine thrown twice in ten seconds must not land on the same file twice.
	"chassis_thud": ["chassis_thud_1", "chassis_thud_2", "chassis_thud_3"],
	"crowd_swell": ["crowd_swell_1", "crowd_swell_2"],
	# WAVE P. Every one of these fires repeatedly inside a few seconds -- a prod bites
	# every 2.5 s, a walker puts a foot down twice a second -- which is exactly the
	# case a single sample gives itself away in.
	"arc_discharge": ["arc_discharge_1", "arc_discharge_2"],
	"prod_zap": ["prod_zap_1", "prod_zap_2"],
	"footfall": ["footfall_1", "footfall_2"],
	"reactive_clang": ["reactive_clang_1", "reactive_clang_2"],
}

## How many of one name may sound at once. Past the cap the OLDEST voice of that name
## is stolen, so a new hit is never dropped and an old one never blocks it.
##
## These are not arbitrary. `bolt_collect` is 45 ms and bolts land about 25 ms apart,
## so six is two and a bit ticks of overlap: enough that the ramp is a stream rather
## than a stutter, few enough that 120 bolts cannot become a wall. `impact_heavy` is
## three because a fourth simultaneous heavy hit is not information, it is mud. `bell`
## and `pit_open` are one because two of either is a bug.
const CAPS := {
	"bolt_collect": 6,
	"impact_light": 4,
	"impact_heavy": 3,
	"wheel_off": 2,
	"panel_off": 3,
	"flipper_fire": 2,
	"axe_swing": 2,
	"axe_hit": 2,
	"ram_hit": 2,
	"crusher_clamp": 2,
	"spikes": 2,
	"flame_jet": 3,
	"ram_crush": 2,
	"pit_open": 1,
	# One wind-up per bank: the telegraph already sends one per group (a Furnace wall's
	# three nozzles are one warning), so a second voice is the other wall or the other ram.
	"warn_spikes": 1,
	"warn_flame": 2,
	"warn_ram": 2,
	"warn_pit": 1,
	"countdown_tick": 2,
	"ko_tick": 1,
	"bell": 1,
	# One horn. Two would be a bug the way two bells would be: the round only turns once.
	"endgame_horn": 1,
	# Wave F. THREE machines in a Rumble can all be thrown at once, so the thud caps at
	# three and the crowd at two: a third overlapping swell is not a bigger reaction, it
	# is a wash that buries the bell. `crowd_roar` is one because the count only runs once.
	"chassis_thud": 3,
	"crowd_swell": 2,
	"crowd_roar": 1,
	# WAVE P. A discharge and a shove are events: two at once is a rumble, three is
	# mud. A walker has four feet and there can be two walkers, so the footfall is the
	# one here that is allowed to stack. The cook warning is ONE, for the same reason
	# the KO tick is: it is a count, and two counts at once say nothing.
	"arc_discharge": 2,
	"prod_zap": 3,
	"napalm_launch": 2,
	"vortex_throw": 2,
	"footfall": 4,
	"cook_warning": 1,
	"reactive_clang": 3,
}
const DEFAULT_CAP := 2

## Per sound trim, in dB. Every file is normalised to -3 dBFS peak, which is right for
## the encoder and wrong for the mix: normalised peaks mean a bolt tick and a ram
## landing arrive at the same level. This table is the actual balance of the game, and
## it is the first place to go when something is too loud.
const LEVELS := {
	"bolt_collect": -13.0,
	"impact_light": -9.0,
	"impact_heavy": -3.0,
	"wheel_off": -5.0,
	"panel_off": -6.0,
	"flipper_fire": -7.0,
	"axe_swing": -12.0,
	"axe_hit": -4.0,
	"ram_hit": -5.0,
	"crusher_clamp": -9.0,
	"motor_loop": -20.0,
	"spin_up_loop": -18.0,
	"saw_cut_loop": -16.0,
	# WAVE F, from the mix table in docs/wave-f-f2-notes.md. -15 made this the FOURTH
	# loudest thing in the game and 0.2 dB hotter than the horn it would have to be heard
	# over in the Furnace: the file's own RMS is -7.9 dBFS, the hottest in the catalogue,
	# so a trim chosen on peak was always going to land it too loud. -18 puts a burner
	# that runs for a whole round 3 dB under the announcements.
	"flame_loop": -18.0,
	"grinder_loop": -19.0,
	"disc_spin_loop": -20.0,
	"spikes": -8.0,
	"pit_open": -5.0,
	"flame_jet": -9.0,
	"ram_crush": -2.0,
	# Wave A wind-ups: trimmed to sit 1 to 3 dB under the activation that follows them
	# (file RMS + trim: spikes -28, flame -28, ram -24.5, pit klaxon -24 dBFS), so the
	# warning is heard and the hit is still the bigger event.
	"warn_spikes": -7.0,
	"warn_flame": -3.0,
	"warn_ram": -14.0,
	"warn_pit": -12.0,
	"countdown_tick": -8.0,
	"ko_tick": -7.0,
	"bell": -4.0,
	# The horn is the loudest announcement after the bell, because the moment it marks
	# has to be unmissable (brief v4 §2). The drone is felt, not listened to.
	# WAVE F: -3 -> -1. G6 wrote that the horn is "the loudest announcement after the
	# bell", and measured it was not: peak normalisation hides that the horn is a
	# sustained tone with a low crest factor, so its loudest 200 ms reached -24.0 dBFS at
	# the master against the bell's -21.4 and a heavy impact's -15.9. -1 dB makes the
	# sentence true (-22.0), and it is still under the bell.
	"endgame_horn": -1.0,
	"endgame_drone_loop": -22.0,
	# THE MOVEMENT LAYER (wave F). These are the "written" levels: MachineAudio hands
	# `set_loop` a RELATIVE dB that is 0 at full effort and about -20 at a standstill,
	# so the number here is what one machine driving flat out sounds like. Measured
	# against the fight rather than guessed (docs/wave-f-f2-notes.md): two machines at
	# full throttle come to about -30 dBFS at the listener, which is level with the
	# crowd bed and 10 dB under a heavy impact.
	"drive_whine_loop": -20.0,
	"roll_wheel_loop": -15.0,
	"track_clatter_loop": -15.0,
	"roll_omni_loop": -13.0,
	# A skid and a scrape are EVENTS inside the movement layer, so they sit about 5 dB
	# over the bed: the player has to be able to hear that he has lost the back end.
	"skid_loop": -7.0,
	"scrape_loop": -8.0,
	# A machine arriving is a shade under a weapon landing on it, never over.
	"chassis_thud": -6.0,
	# THE CROWD (wave F). The bed was -6 dB on a bus at -14, which put its loudest
	# 200 ms at -35 dBFS against a -13 dBFS impact: the owner could not hear it on a
	# phone and was right. It is now -4 on a bus at -10 (audio_bus_layout.tres), and the
	# file itself carries 4 dB more RMS and its energy where a phone can move air.
	"crowd_ambience_loop": -4.0,
	# The reaction sits about 4 dB over the bed at its peak and stays under the two
	# announcements by more than 3 dB even before the duck (AudioMix.DUCKS) takes another
	# 6 off it. Loudest crowd cue -25.3 dBFS, horn -22.0, bell -21.4.
	"crowd_swell": -4.0,
	"crowd_roar": -3.0,
	# WAVE P (agent F), set against the wave F table rather than by ear (the owner is
	# at the Mac; docs/wave-p-f-notes.md carries the measured loudness of every one).
	#
	# The EVENTS sit with the weapon sounds they are the equal of: a coil discharging
	# and a reactive plate firing are the two biggest single things a wave P part
	# does, so they land beside a heavy impact (-3) and under the bell. A prod bite is
	# a small bang, so it sits with the flipper.
	"arc_discharge": -2.0,
	"prod_zap": -5.0,
	"napalm_launch": -6.0,
	"vortex_throw": -5.0,
	"reactive_clang": -8.0,
	# The LOOPS are trimmed against `saw_cut_loop` (-16), which is the loudest weapon
	# loop in the game and the one a player already knows the size of. The twin saw is
	# two voices of one file, which sums to about 3 dB hotter than one, so its written
	# level is 3 dB under the single saw's and the PAIR arrives where a saw does.
	"arc_crackle_loop": -20.0,
	"drill_grind_loop": -16.0,
	"twin_saw_loop": -19.0,
	"vortex_spin_loop": -18.0,
	# Up to four patches can burn at once (`charges` 5, `fuel_s` 6 in a 180 s fight),
	# and the flamethrower's own burner is -18. Four of these sum to about -15, which
	# is 3 dB over one burner and right: the floor being on fire in four places IS a
	# bigger event than one jet. The voice cap (WeaponFx.MAX_PATCH_VOICES) is what
	# stops it going further than that.
	"fire_patch_loop": -17.0,
	# THE MOVEMENT LAYER'S wave P rows. MachineAudio hands these a RELATIVE dB that is
	# 0 at full effort, so the number is what one machine flat out sounds like, exactly
	# as the wave F rows above.
	"hover_fan_loop": -18.0,
	"hover_skirt_loop": -16.0,
	"leg_servo_loop": -13.0,
	"adaptive_track_loop": -12.0,
	# A footfall is the walker's contact with the floor, so it belongs with the roll
	# it replaces rather than with the landing thud (-6): four a second at thud level
	# would be the loudest thing in the fight.
	"footfall": -12.0,
	# Your own machine cooking itself is information you must not miss, and it is the
	# only warning in the game that is nobody else's doing. It sits with the KO tick.
	"cook_warning": -4.0,
}

## Anything not listed plays on SFX, which is the bus carrying the arena reverb.
const BUSES := {
	"countdown_tick": BUS_UI,
	"ko_tick": BUS_UI,
	"bell": BUS_UI,
	# The horn is the announcer's, like the bell, so it stays out of the arena reverb.
	# The drone is the first thing ever to play on the Music bus, which has been wired
	# and empty since Stage 6 (docs/audio-notes.md §4).
	"endgame_horn": BUS_UI,
	"endgame_drone_loop": BUS_MUSIC,
	"crowd_ambience_loop": BUS_AMBIENCE,
	# The crowd's reactions are the crowd: same bus, same hall, same fader, and they
	# duck with it rather than over it.
	"crowd_swell": BUS_AMBIENCE,
	"crowd_roar": BUS_AMBIENCE,
}

## Sounds that are NOT placed in the arena even when a position is passed. The
## countdown, the bell and the KO count are the announcer's, not an object's: putting
## them 6 m to the left is wrong, and the ambience is the room itself.
const NON_POSITIONAL := {
	"countdown_tick": true,
	"ko_tick": true,
	"bell": true,
	"bolt_collect": true,
	"endgame_horn": true,
	"endgame_drone_loop": true,
	"crowd_ambience_loop": true,
	# A crowd is not 6 m to the left. The machines ARE: everything MachineAudio starts
	# is positional and is deliberately absent from this table.
	"crowd_swell": true,
	"crowd_roar": true,
}

const VOICES_2D := 10
const VOICES_3D := 16

## 3D placement. UNIT_SIZE is the distance at which a sound is at its written level;
## at the fight camera's framing the arena is about 8 m across, so 5 m means the far
## corner is roughly 4 dB down: present, placed, never so quiet the player misses a
## hit that mattered. MAX_DISTANCE is a cull, set beyond the biggest arena (12 m).
const UNIT_SIZE := 5.0
const MAX_DISTANCE := 26.0
const PANNING_STRENGTH := 0.7

## Presentation only. See the class docstring: never the fight's rng.
const RNG_SEED := 0x52424F54      # "RBOT"

var _rng := RandomNumberGenerator.new()
var _streams: Dictionary = {}                  ## name -> AudioStream
var _voices_2d: Array[AudioStreamPlayer] = []
var _voices_3d: Array[AudioStreamPlayer3D] = []
## name -> Array of {"player": Node, "at": float}, oldest first. The voice bookkeeping
## that makes a cap a cap.
var _active: Dictionary = {}
## loop key -> AudioStreamPlayer or AudioStreamPlayer3D
var _loops: Dictionary = {}
var _loop_sound: Dictionary = {}          ## loop key -> the SOUNDS name it is playing
## loop key -> the dB its caller asked for, ON TOP of the LEVELS trim. Remembered so the
## duck can re-write a live voice's level without losing what the caller wanted.
var _loop_db: Dictionary = {}
var _last_variant: Dictionary = {}
var _now: float = 0.0
var _missing: Array[String] = []
var _layout_applied := false


func _ready() -> void:
	_rng.seed = RNG_SEED
	apply_bus_layout()
	for key in SOUNDS:
		var s: AudioStream = load(SOUNDS[key]) as AudioStream
		if s == null:
			_missing.append(key)
			push_warning("AudioMix: missing sound " + str(SOUNDS[key]))
			continue
		_streams[key] = s
	for i in VOICES_2D:
		var p := AudioStreamPlayer.new()
		p.name = "Voice2D_%d" % i
		p.bus = BUS_SFX
		add_child(p)
		_voices_2d.append(p)
	for i in VOICES_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.name = "Voice3D_%d" % i
		p3.bus = BUS_SFX
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = UNIT_SIZE
		p3.max_distance = MAX_DISTANCE
		p3.panning_strength = PANNING_STRENGTH
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p3)
		_voices_3d.append(p3)


func _process(delta: float) -> void:
	_now += delta
	_reap()
	_step_duck(delta)


## Install the four bus mix. Idempotent, and it PRESERVES the master volume and mute,
## because agent R's `settings` message writes those on bus 0 and may have arrived
## before the FX tree existed. `AudioServer.set_bus_layout` would otherwise silently
## put the volume back to 0 dB and un-mute a player who had asked for silence.
func apply_bus_layout() -> bool:
	if _layout_applied:
		return true
	var layout: AudioBusLayout = load(BUS_LAYOUT) as AudioBusLayout
	if layout == null:
		push_warning("AudioMix: " + BUS_LAYOUT + " did not load; staying on the default bus")
		return false
	var master_db := AudioServer.get_bus_volume_db(0)
	var master_mute := AudioServer.is_bus_mute(0)
	AudioServer.set_bus_layout(layout)
	AudioServer.set_bus_volume_db(0, master_db)
	AudioServer.set_bus_mute(0, master_mute)
	_layout_applied = true
	return true


## --- one shots ---------------------------------------------------------------

## Play `sound` once. `position` is a Vector3 in world space, or null for a sound that
## belongs to the whole arena rather than to a place in it. Returns the player, or
## null if the sound is unknown (which is never fatal: a missing sound is silence).
##
## `sound` may be a variant GROUP name ("impact_heavy"), in which case one of the
## three files is chosen, never the same one twice running.
func play(sound: String, position: Variant = null, volume_db: float = 0.0,
		pitch: float = 1.0) -> Node:
	var group := sound
	var key := _pick(sound)
	if not _streams.has(key):
		return null
	var cap: int = int(CAPS.get(group, DEFAULT_CAP))
	_make_room(group, cap)

	var want_3d := position is Vector3 and not NON_POSITIONAL.has(group) \
		and _has_listener()
	var bus: String = str(BUSES.get(group, BUS_SFX))
	var level: float = float(LEVELS.get(group, 0.0)) + volume_db - _duck_of(group)

	var player: Node = null
	if want_3d:
		var p3 := _free_3d()
		if p3 == null:
			return null
		p3.stream = _streams[key]
		p3.global_position = position
		p3.bus = bus
		p3.volume_db = level
		p3.pitch_scale = maxf(pitch, 0.01)
		p3.play()
		player = p3
	else:
		var p := _free_2d()
		if p == null:
			return null
		p.stream = _streams[key]
		p.bus = bus
		p.volume_db = level
		p.pitch_scale = maxf(pitch, 0.01)
		p.play()
		player = p

	_duck_for(group)

	var q: Array = _active.get(group, [])
	q.append({"player": player, "at": _now, "group": group, "db": level})
	_active[group] = q
	return player


## --- loops -------------------------------------------------------------------

## Start (or re-point) a looping voice. `key` is the caller's own handle, so a motor is
## "motor:player-1" and a hazard is "grinder:0"; starting a key that is already running
## does NOT restart it, which is the whole point: restarting a loop every time the
## throttle changes is a click per frame.
func start_loop(key: String, sound: String, position: Variant = null,
		volume_db: float = 0.0, pitch: float = 1.0) -> Node:
	if _loops.has(key):
		var existing: Node = _loops[key]
		if is_instance_valid(existing):
			set_loop(key, pitch, volume_db, position)
			return existing
		_loops.erase(key)
	if not _streams.has(sound):
		return null
	var bus: String = str(BUSES.get(sound, BUS_SFX))
	var level: float = float(LEVELS.get(sound, 0.0)) + volume_db
	var player: Node = null
	if position is Vector3 and not NON_POSITIONAL.has(sound) and _has_listener():
		var p3 := AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = UNIT_SIZE
		p3.max_distance = MAX_DISTANCE
		p3.panning_strength = PANNING_STRENGTH
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		# NOT `global_position` here: this node is not in the tree yet, and a global
		# transform on a detached Node3D is an engine error every time
		# ("Condition '!is_inside_tree()' is true" out of get_global_transform). It is
		# set below, after add_child, which is where it was always going to take effect.
		# Harmless until wave F, then one error per loop per machine per fight.
		p3.position = position
		player = p3
	else:
		player = AudioStreamPlayer.new()
	player.name = "Loop_" + key.replace(":", "_")
	player.set("stream", _streams[sound])
	player.set("bus", bus)
	player.set("volume_db", level)
	player.set("pitch_scale", maxf(pitch, 0.01))
	add_child(player)
	if position is Vector3 and player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).global_position = position
	player.call("play")
	_loops[key] = player
	_loop_sound[key] = sound
	_loop_db[key] = volume_db
	if _duck_of(sound) > 0.0:
		player.set("volume_db", level - _duck_of(sound))
	return player


## Move an existing loop's pitch, level and place without restarting it.
func set_loop(key: String, pitch: float, volume_db: float = 0.0,
		position: Variant = null) -> void:
	var player: Node = _loops.get(key, null)
	if player == null or not is_instance_valid(player):
		return
	var sound: String = str(_loop_sound.get(key, ""))
	_loop_db[key] = volume_db
	player.set("pitch_scale", maxf(pitch, 0.01))
	player.set("volume_db", float(LEVELS.get(sound, 0.0)) + volume_db - _duck_of(sound))
	if position is Vector3 and player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).global_position = position


func stop_loop(key: String) -> void:
	var player: Node = _loops.get(key, null)
	_loops.erase(key)
	_loop_sound.erase(key)
	_loop_db.erase(key)
	if player != null and is_instance_valid(player):
		player.call("stop")
		player.queue_free()


func has_loop(key: String) -> bool:
	var player: Node = _loops.get(key, null)
	return player != null and is_instance_valid(player)


func loop_keys() -> Array:
	return _loops.keys()


## The voice behind a loop key, so a test can read the pitch and level a caller asked
## for rather than trusting that it asked. Never used by the game.
func loop_player(key: String) -> Node:
	var player: Node = _loops.get(key, null)
	return player if player != null and is_instance_valid(player) else null


## The SOUNDS name a live loop key is playing, for the same reason.
func loop_sound(key: String) -> String:
	return str(_loop_sound.get(key, ""))


## --- the Ambience bus: the endgame lift, and the duck -------------------------
##
## ONE OWNER. Three separate things want to move the crowd's fader — the endgame lifts
## it, the bell and the horn duck it, and the player's `settings` message sets it — and
## before wave F two of them wrote `AudioServer` directly, which works right up until
## they overlap and one of them hands back the other's number as if it were the
## player's. So the bus level is now computed, never accumulated:
##
##     Ambience = _amb_base_db + (endgame ? AMBIENCE_HOT_DB : 0) - _duck_db
##
## `_amb_base_db` is read ONCE, the first time this node touches the bus, so whatever
## the layout or the player's settings put there is what everything is relative to and
## what is handed back when the node goes.

## How much hotter the crowd gets at the endgame. G6 chose +4 dB against a bed whose
## loudest 200 ms reached -35 dBFS; wave F raised that bed by 10 dB (LEVELS and
## audio_bus_layout.tres), so +3 is now the same size of step it was meant to be.
const AMBIENCE_HOT_DB := 3.0
const ENDGAME_LOOP_KEY := "music:endgame"

## THE DUCK (docs/audio-notes.md §8 weakness 4, which said a sidechain on Ambience keyed
## off SFX was the right fix). Godot has no sidechain, so this is the same idea done in
## code: the announcements that must never be masked pull the crowd down for as long as
## they are sounding, then let it back up. Depth in dB and hold in seconds.
##
## The crowd is 10 dB louder than it was in wave G. Without this, a roar landing on the
## knockout count would be sitting on the very tick it is reacting to.
##
## IT DUCKS THE VOICES, NOT THE BUS, and that is deliberate. The Ambience FADER belongs
## to two other things — the player's `settings` message and the endgame lift — and a
## duck that borrowed it would have to hand back a number it did not own. Every crowd
## voice this node started has its own `volume_db`, which is this node's to move, so the
## duck moves those and the fader is left alone. A reader of the bus level therefore
## always sees exactly "what the player asked for, plus the endgame", which is what
## `commentary_test.gd` asserts and what anyone tuning the mix expects to see.
const DUCKS := {
	"bell": [6.0, 1.4],
	"endgame_horn": [6.0, 1.6],
	"ko_tick": [3.0, 0.45],
}
## Which bus the duck applies to. Only the crowd is ever ducked: the fight's own sounds
## are the information and the music bed is 22 dB down already.
const DUCK_BUS := BUS_AMBIENCE
## How fast the crowd comes back, in dB per second. Slow enough not to pump, fast enough
## that the bed is whole again before the next tick of the count.
const DUCK_RELEASE_DB_S := 9.0

var _endgame: bool = false
## The Ambience bus's level before this node touched it, so everything is reversible.
var _amb_base_db: float = 0.0
var _amb_base_read: bool = false
var _duck_db: float = 0.0
var _duck_until: float = 0.0


## The horn. One shot, capped at one voice: the round only turns once.
func play_endgame_horn() -> Node:
	return play("endgame_horn")


## The music and ambience switch. Idempotent, and safe with no bus layout installed.
func set_endgame(on: bool) -> void:
	if on == _endgame:
		return
	_endgame = on
	# The fader first, so the reaction below is played against the level it will live at.
	_write_ambience()
	if on:
		# The round turning is the biggest moment in the fight that is not the bell.
		crowd_reaction(SWELL_ENDGAME)
		start_loop(ENDGAME_LOOP_KEY, "endgame_drone_loop")
	else:
		stop_loop(ENDGAME_LOOP_KEY)


func endgame_active() -> bool:
	return _endgame


## --- the crowd reacting (wave F, agent F2) -----------------------------------
##
## A crowd that never reacts is a recording. These are the four moments the brief asks
## for, and `FightCommentary` already edge-detects two of them for its own lines, so the
## swell hangs off the same event point rather than off a second detector that could
## disagree with what the ticker says.

const SWELL_BIG_HIT := "big_hit"
const SWELL_FLIPPED := "flipped"
const SWELL_KO := "ko"
const SWELL_ENDGAME := "endgame"

## Commentary line -> the reaction it earns. `FightCommentary._say()` passes its line
## straight in, so anything not in here (PINNED, SPINNING UP, IN THE ZONE) says nothing:
## a crowd that roars at every caption is noise, not an audience.
const SWELL_FOR_LINE := {
	"BIG HIT": SWELL_BIG_HIT,
	"FLIPPED": SWELL_FLIPPED,
}

## sound, extra dB, pitch, and the shortest gap before this reaction may happen again.
## The gaps are what stop a spinner fight turning the crowd into a loop of its own; they
## are per reaction, so a flip during a run of big hits is still heard.
const SWELLS := {
	SWELL_BIG_HIT: {"sound": "crowd_swell", "db": 0.0, "pitch": 1.0, "gap": 4.5},
	# A flip is a bigger moment than a hit, and it is made bigger by dropping the pitch
	# rather than by adding dB: `db` may not take a cue over its written trim, because
	# that trim is what keeps the crowd under the bell and the horn.
	SWELL_FLIPPED: {"sound": "crowd_swell", "db": 0.0, "pitch": 0.94, "gap": 4.0},
	SWELL_KO: {"sound": "crowd_roar", "db": -2.0, "pitch": 1.0, "gap": 6.0},
	SWELL_ENDGAME: {"sound": "crowd_roar", "db": 0.0, "pitch": 0.98, "gap": 6.0},
}

var _swell_at: Dictionary = {}          ## reaction key -> the _now it last fired


## `what` is a SWELL_* key or a `FightCommentary` line. Returns the voice, or null when
## the moment does not earn a reaction or one is still ringing.
func crowd_reaction(what: String, intensity: float = 1.0) -> Node:
	var key: String = str(SWELL_FOR_LINE.get(what, what))
	if not SWELLS.has(key):
		return null
	var entry: Dictionary = SWELLS[key]
	if _now - float(_swell_at.get(key, -1.0e9)) < float(entry["gap"]):
		return null
	_swell_at[key] = _now
	# Intensity only ever takes the reaction DOWN: the written level is the loudest the
	# crowd is allowed to be, and that is what keeps it under the bell.
	var quiet := linear_to_db(clampf(intensity, 0.05, 1.0))
	var jitter_pitch := float(entry["pitch"]) + jitter(-0.02, 0.02)
	return play(str(entry["sound"]), null, float(entry["db"]) + quiet, jitter_pitch)


## --- internals: the Ambience fader --------------------------------------------

func _ambience_bus() -> int:
	return AudioServer.get_bus_index(BUS_AMBIENCE)


## Read the player's level once, then never again: after this the node owns the fader.
func _read_ambience_base() -> void:
	if _amb_base_read:
		return
	var bus := _ambience_bus()
	if bus < 0:
		return
	_amb_base_db = AudioServer.get_bus_volume_db(bus)
	_amb_base_read = true


## The crowd's FADER: the player's level plus the endgame lift, and nothing else.
func _write_ambience() -> void:
	_read_ambience_base()
	var bus := _ambience_bus()
	if bus < 0 or not _amb_base_read:
		return
	AudioServer.set_bus_volume_db(bus,
		_amb_base_db + (AMBIENCE_HOT_DB if _endgame else 0.0))


## How many dB a sound is currently ducked by. Non zero only for the crowd.
func _duck_of(sound: String) -> float:
	if _duck_db <= 0.0:
		return 0.0
	return _duck_db if str(BUSES.get(sound, BUS_SFX)) == DUCK_BUS else 0.0


## Pull the crowd down for `sound`, if it is one of the announcements that must not be
## masked. Deepening an existing duck is allowed; shallowing it is not, so a KO tick
## landing under the bell cannot lift the crowd back over the bell.
func _duck_for(sound: String) -> void:
	if not DUCKS.has(sound):
		return
	var entry: Array = DUCKS[sound]
	_duck_db = maxf(_duck_db, float(entry[0]))
	_duck_until = maxf(_duck_until, _now + float(entry[1]))
	_apply_duck()


func _step_duck(delta: float) -> void:
	if _duck_db <= 0.0 or _now < _duck_until:
		return
	_duck_db = maxf(0.0, _duck_db - delta * DUCK_RELEASE_DB_S)
	_apply_duck()


## Re-write every live crowd voice at its written level minus the current duck. Loops
## remember the dB their caller asked for (`_loop_db`) and one shots remember the level
## they were played at, so nothing here has to guess and a duck can never accumulate.
func _apply_duck() -> void:
	for key in _loops.keys():
		var sound: String = str(_loop_sound.get(key, ""))
		if str(BUSES.get(sound, BUS_SFX)) != DUCK_BUS:
			continue
		var player: Node = _loops[key]
		if player == null or not is_instance_valid(player):
			continue
		player.set("volume_db",
			float(LEVELS.get(sound, 0.0)) + float(_loop_db.get(key, 0.0)) - _duck_db)
	for group in _active.keys():
		if str(BUSES.get(group, BUS_SFX)) != DUCK_BUS:
			continue
		for entry_variant in (_active[group] as Array):
			var entry: Dictionary = entry_variant
			var p: Node = entry["player"]
			if p == null or not is_instance_valid(p):
				continue
			p.set("volume_db", float(entry["db"]) - _duck_db)


## The crowd's current fader, for the test and for anyone tuning the mix.
func ambience_db() -> float:
	var bus := _ambience_bus()
	return AudioServer.get_bus_volume_db(bus) if bus >= 0 else 0.0


func duck_db() -> float:
	return _duck_db


## The lift and the duck are settings on a GLOBAL bus, and this node is not global: a new
## fight builds a new world, a new FX subtree and a new AudioMix, and the old one is
## freed. If it went without handing the level back, the crowd would stay hot (or ducked)
## into the next fight and further into the one after that. The loops go with the node;
## the bus does not.
func _exit_tree() -> void:
	_endgame = false
	_duck_db = 0.0
	_duck_until = 0.0
	var bus := _ambience_bus()
	if bus >= 0 and _amb_base_read:
		AudioServer.set_bus_volume_db(bus, _amb_base_db)


## What the crowd bed's own voice is sitting at right now, for the test: the duck is only
## visible here, never on the bus.
func ambience_voice_db(key: String = "ambience") -> float:
	var player: Node = _loops.get(key, null)
	if player == null or not is_instance_valid(player):
		return 0.0
	return float(player.get("volume_db"))


## --- volume ------------------------------------------------------------------

## The `settings` message's volume, 0..1 linear. Kept EXACTLY compatible with what
## agent R's fight.gd already does on bus 0, including the reason for the mute flag:
## linear_to_db(0) is -inf and some drivers take that badly, so silence is the mute.
func set_master_volume(linear: float) -> void:
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(0, v <= 0.0)
	if v > 0.0:
		AudioServer.set_bus_volume_db(0, linear_to_db(v))


## A presentation-only random in [lo, hi). Callers use it for pitch jitter. It draws
## from this node's generator, NEVER from the fight's seeded rng, for the reason in
## the class docstring: presentation must not be able to move the fight's sequence.
func jitter(lo: float, hi: float) -> float:
	return _rng.randf_range(lo, hi)


func set_bus_volume(bus: String, db: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, db)


## Silence everything this node owns. Loops are freed, one shot voices are stopped.
func stop_all() -> void:
	# The endgame and the duck first, so the Ambience bus goes back to the level the
	# player's settings put on it rather than staying hot (or ducked) into the next fight.
	set_endgame(false)
	_duck_db = 0.0
	_duck_until = 0.0
	_swell_at.clear()
	for key in _loops.keys():
		stop_loop(key)
	for p in _voices_2d:
		if is_instance_valid(p):
			p.stop()
	for p3 in _voices_3d:
		if is_instance_valid(p3):
			p3.stop()
	_active.clear()


## --- introspection for Arena/tests/audio_test.gd ------------------------------

func active_count(group: String) -> int:
	_reap()
	var q: Array = _active.get(group, [])
	return q.size()


func cap_for(group: String) -> int:
	return int(CAPS.get(group, DEFAULT_CAP))


func variant_names(group: String) -> Array:
	return VARIANTS.get(group, [group])


func missing_sounds() -> Array[String]:
	return _missing


func bus_layout_applied() -> bool:
	return _layout_applied


## Test seam: drive the internal clock without a running tree.
func step(delta: float) -> void:
	_now += delta
	_reap()
	_step_duck(delta)


## --- internals ----------------------------------------------------------------

## One of the group's variants, never the one played last. With three files that is a
## coin flip between the other two, which keeps the ear from finding a pattern in the
## way a plain "pick a random one" does not (a plain pick repeats a third of the time).
func _pick(sound: String) -> String:
	if not VARIANTS.has(sound):
		return sound
	var names: Array = VARIANTS[sound]
	if names.size() <= 1:
		return str(names[0])
	var last: String = str(_last_variant.get(sound, ""))
	var choices: Array = []
	for n in names:
		if str(n) != last:
			choices.append(n)
	var picked: String = str(choices[_rng.randi() % choices.size()])
	_last_variant[sound] = picked
	return picked


func _has_listener() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	return vp.get_camera_3d() != null or vp.get_audio_listener_3d() != null


func _free_2d() -> AudioStreamPlayer:
	for p in _voices_2d:
		if not p.playing:
			return p
	# Everything is busy: steal the one that has been going longest. A rotating index
	# would steal whatever came next, which on a 2.6 s bell is usually the bell.
	var oldest: AudioStreamPlayer = null
	var best := -1.0
	for p in _voices_2d:
		var pos := p.get_playback_position()
		if pos > best:
			best = pos
			oldest = p
	return oldest


func _free_3d() -> AudioStreamPlayer3D:
	for p in _voices_3d:
		if not p.playing:
			return p
	var oldest: AudioStreamPlayer3D = null
	var best := -1.0
	for p in _voices_3d:
		var pos := p.get_playback_position()
		if pos > best:
			best = pos
			oldest = p
	return oldest


## Stop the oldest voices of `group` until there is room for one more.
func _make_room(group: String, cap: int) -> void:
	var q: Array = _active.get(group, [])
	_prune(q)
	while q.size() >= cap and not q.is_empty():
		var entry: Dictionary = q.pop_front()
		var p: Node = entry["player"]
		if p != null and is_instance_valid(p):
			p.call("stop")
	_active[group] = q


func _reap() -> void:
	for group in _active.keys():
		var q: Array = _active[group]
		_prune(q)
		if q.is_empty():
			_active.erase(group)
		else:
			_active[group] = q


static func _prune(q: Array) -> void:
	var i := 0
	while i < q.size():
		var entry: Dictionary = q[i]
		var p: Node = entry["player"]
		if p == null or not is_instance_valid(p) or not bool(p.get("playing")):
			q.remove_at(i)
		else:
			i += 1
