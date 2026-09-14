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
	# fight and UI
	"countdown_tick": "res://audio/countdown_tick.wav",
	"ko_tick": "res://audio/ko_tick.wav",
	"bell": "res://audio/bell.wav",
	# ambience
	"crowd_ambience_loop": "res://audio/crowd_ambience_loop.wav",
}

## Names that are really a set. `play("impact_heavy")` picks one of these, never the
## same one twice running, which is the whole reason three of each exist: a repeated
## sample at a repeated interval is the single most obvious "this is a game" tell.
const VARIANTS := {
	"impact_light": ["impact_light_1", "impact_light_2", "impact_light_3"],
	"impact_heavy": ["impact_heavy_1", "impact_heavy_2", "impact_heavy_3"],
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
	"countdown_tick": 2,
	"ko_tick": 1,
	"bell": 1,
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
	"flame_loop": -15.0,
	"grinder_loop": -19.0,
	"disc_spin_loop": -20.0,
	"spikes": -8.0,
	"pit_open": -5.0,
	"flame_jet": -9.0,
	"ram_crush": -2.0,
	"countdown_tick": -8.0,
	"ko_tick": -7.0,
	"bell": -4.0,
	"crowd_ambience_loop": -6.0,
}

## Anything not listed plays on SFX, which is the bus carrying the arena reverb.
const BUSES := {
	"countdown_tick": BUS_UI,
	"ko_tick": BUS_UI,
	"bell": BUS_UI,
	"crowd_ambience_loop": BUS_AMBIENCE,
}

## Sounds that are NOT placed in the arena even when a position is passed. The
## countdown, the bell and the KO count are the announcer's, not an object's: putting
## them 6 m to the left is wrong, and the ambience is the room itself.
const NON_POSITIONAL := {
	"countdown_tick": true,
	"ko_tick": true,
	"bell": true,
	"bolt_collect": true,
	"crowd_ambience_loop": true,
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
	var level: float = float(LEVELS.get(group, 0.0)) + volume_db

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

	var q: Array = _active.get(group, [])
	q.append({"player": player, "at": _now})
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
		p3.global_position = position
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
	return player


## Move an existing loop's pitch, level and place without restarting it.
func set_loop(key: String, pitch: float, volume_db: float = 0.0,
		position: Variant = null) -> void:
	var player: Node = _loops.get(key, null)
	if player == null or not is_instance_valid(player):
		return
	var sound: String = str(_loop_sound.get(key, ""))
	player.set("pitch_scale", maxf(pitch, 0.01))
	player.set("volume_db", float(LEVELS.get(sound, 0.0)) + volume_db)
	if position is Vector3 and player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).global_position = position


func stop_loop(key: String) -> void:
	var player: Node = _loops.get(key, null)
	_loops.erase(key)
	_loop_sound.erase(key)
	if player != null and is_instance_valid(player):
		player.call("stop")
		player.queue_free()


func has_loop(key: String) -> bool:
	var player: Node = _loops.get(key, null)
	return player != null and is_instance_valid(player)


func loop_keys() -> Array:
	return _loops.keys()


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
