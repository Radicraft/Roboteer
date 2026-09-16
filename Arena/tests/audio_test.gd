extends SceneTree
## Headless audio test (agent AU, docs/audio-notes.md).
##   Godot --headless --path Arena --script tests/audio_test.gd
##
## Nobody can hear anything in a headless run, so this checks the things that are
## true or false rather than the things that are good or bad:
##
##   1. every sound in AudioMix.SOUNDS imports and loads as an AudioStreamWAV, at
##      44.1 kHz, with the channel count and the loop mode it is supposed to have;
##   2. every loop is PCM (a lossy codec smears the seam) and is SEAMLESS by the
##      numeric test the generator uses: the wrap-around sample step is no larger
##      than the largest step inside the file, per channel;
##   3. variant picking never repeats a sample twice running and the polyphony caps
##      really cap;
##   4. the collect ramp's semitone maths still holds in collect_audio.gd;
##   5. the bus layout loads and installs Master / Music / SFX / Ambience / UI with
##      the reverb on SFX and the limiter on Master, and installing it does not
##      trample the master volume agent R's `settings` message writes.
##
## It does not need the FX scene, a renderer or a physics world, so it is fast and
## it cannot be broken by anything outside Arena/audio and Arena/fx/audio_*.

## Loop mode expected per file. Everything not listed must be LOOP_DISABLED.
const EXPECTED_LOOPS := [
	"motor_loop.wav",
	"spin_up_loop.wav",
	"saw_cut_loop.wav",
	"flame_loop.wav",
	"grinder_loop.wav",
	"disc_spin_loop.wav",
	"crowd_ambience_loop.wav",
	"endgame_drone_loop.wav",
]
const STEREO_FILES := ["crowd_ambience_loop.wav"]
const MIX_RATE := 44100

var _failures: int = 0
var _checks: int = 0
var _skipped: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_files()
	_test_seams()
	await _test_mixer()
	_test_collect_ramp()
	_test_bus_layout()
	_finish()


# --- 1. the files -------------------------------------------------------------

func _test_files() -> void:
	var missing: Array[String] = []
	var bad_type: Array[String] = []
	var bad_rate: Array[String] = []
	var bad_loop: Array[String] = []
	var bad_channels: Array[String] = []

	for key in AudioMix.SOUNDS:
		var path: String = AudioMix.SOUNDS[key]
		var file := path.get_file()
		if not ResourceLoader.exists(path):
			missing.append(file)
			continue
		var wav: AudioStreamWAV = load(path) as AudioStreamWAV
		if wav == null:
			bad_type.append(file)
			continue
		if wav.mix_rate != MIX_RATE:
			bad_rate.append("%s (%d)" % [file, wav.mix_rate])
		var want_loop := AudioStreamWAV.LOOP_FORWARD if file in EXPECTED_LOOPS \
			else AudioStreamWAV.LOOP_DISABLED
		if wav.loop_mode != want_loop:
			bad_loop.append("%s (is %d, want %d)" % [file, wav.loop_mode, want_loop])
		var want_stereo := file in STEREO_FILES
		if wav.stereo != want_stereo:
			bad_channels.append("%s (stereo %s, want %s)" % [file, wav.stereo, want_stereo])

	_check(missing.is_empty(), "every sound in AudioMix.SOUNDS is imported (%d files)"
		% AudioMix.SOUNDS.size(), str(missing))
	_check(bad_type.is_empty(), "every sound loads as an AudioStreamWAV", str(bad_type))
	_check(bad_rate.is_empty(), "every sound is 44.1 kHz", str(bad_rate))
	_check(bad_loop.is_empty(),
		"the %d loops are LOOP_FORWARD and nothing else is" % EXPECTED_LOOPS.size(),
		str(bad_loop))
	_check(bad_channels.is_empty(),
		"crowd_ambience_loop is stereo and every other sound is mono", str(bad_channels))

	# FightFx.SOUNDS is the alias the rest of the game (and fx_test) uses.
	_check(FightFx.SOUNDS.size() == AudioMix.SOUNDS.size(),
		"FightFx.SOUNDS is AudioMix.SOUNDS (%d entries)" % FightFx.SOUNDS.size())


# --- 2. the loop seams --------------------------------------------------------

## The same test scripts/gen-sounds.py runs before it writes the file, repeated here
## against what Godot actually imported, because the import step is where a seam gets
## destroyed: QOA compression smears the last few samples and nothing upstream knows.
func _test_seams() -> void:
	var not_pcm: Array[String] = []
	var clicks: Array[String] = []
	for file in EXPECTED_LOOPS:
		var wav: AudioStreamWAV = load("res://audio/" + file) as AudioStreamWAV
		if wav == null:
			continue
		if wav.format != AudioStreamWAV.FORMAT_16_BITS:
			not_pcm.append("%s (format %d)" % [file, wav.format])
			continue
		var channels := 2 if wav.stereo else 1
		for c in channels:
			var r := _seam(wav.data, channels, c)
			var wrap: float = r["wrap"]
			var inner: float = r["inner"]
			if wrap > inner:
				clicks.append("%s ch%d wrap %.1f > inner %.1f" % [file, c, wrap, inner])
			else:
				print("      %-26s ch%d wrap %6.0f  max inner %6.0f" % [file, c, wrap, inner])
	_check(not_pcm.is_empty(),
		"every loop imported as 16-bit PCM, not QOA (a lossy codec smears the seam)",
		str(not_pcm))
	_check(clicks.is_empty(),
		"every loop is seamless: the wrap step is no larger than the largest interior step",
		str(clicks))


## Wrap-around step and largest interior step for one channel of interleaved s16.
static func _seam(data: PackedByteArray, channels: int, channel: int) -> Dictionary:
	var frames := data.size() / (2 * channels)
	if frames < 4:
		return {"wrap": 0.0, "inner": 1.0}
	var stride := 2 * channels
	var base := channel * 2
	var prev := data.decode_s16(base)
	var first := prev
	var inner := 0
	for i in range(1, frames):
		var v := data.decode_s16(base + i * stride)
		var d: int = absi(v - prev)
		if d > inner:
			inner = d
		prev = v
	return {"wrap": float(absi(first - prev)), "inner": float(inner)}


# --- 3. the mixer -------------------------------------------------------------

func _test_mixer() -> void:
	var mix := AudioMix.new()
	root.add_child(mix)
	await process_frame

	_check(mix.missing_sounds().is_empty(),
		"AudioMix loaded every stream in its catalogue", str(mix.missing_sounds()))

	# Variants: 24 plays of a group must never give the same file twice running, and
	# must use all three. A plain random pick repeats about a third of the time.
	var bad_repeats := 0
	var seen := {}
	var last := ""
	for i in 24:
		var p: Node = mix.play("impact_heavy")
		if p == null:
			continue
		var file: String = str(p.get("stream").resource_path).get_file()
		if file == last:
			bad_repeats += 1
		last = file
		seen[file] = true
	_check(bad_repeats == 0, "impact_heavy never played the same variant twice running")
	_check(seen.size() == 3, "all three impact_heavy variants were used (%d)" % seen.size())

	# Caps. Every one of those 24 was inside one frame, so without a cap there would
	# be 24 voices of impact_heavy alive.
	_check(mix.active_count("impact_heavy") <= mix.cap_for("impact_heavy"),
		"impact_heavy stayed inside its polyphony cap (%d of %d)"
		% [mix.active_count("impact_heavy"), mix.cap_for("impact_heavy")])

	var over := 0
	for i in 40:
		mix.play("bolt_collect", null, 0.0, 1.0 + 0.05 * i)
		if mix.active_count("bolt_collect") > mix.cap_for("bolt_collect"):
			over += 1
	_check(over == 0, "40 collect ticks in one frame never exceeded the cap of %d"
		% mix.cap_for("bolt_collect"))

	# An unknown name is silence, never an error.
	_check(mix.play("no_such_sound") == null, "an unknown sound name plays nothing and does not crash")

	# Loops: starting a running key must not restart it, and stop must free it.
	mix.start_loop("motor:test", "motor_loop", null, -20.0, 0.8)
	_check(mix.has_loop("motor:test"), "start_loop made a looping voice")
	var first_player: Node = mix.start_loop("motor:test", "motor_loop", null, -20.0, 1.2)
	_check(mix.loop_keys().size() == 1,
		"starting a loop key that is already running does not make a second voice")
	_check(is_equal_approx(float(first_player.get("pitch_scale")), 1.2),
		"re-starting a live loop key re-points it instead of restarting it")
	mix.set_loop("motor:test", 1.45, -11.0)
	_check(is_equal_approx(float(first_player.get("pitch_scale")), 1.45),
		"set_loop moves the pitch without restarting the voice")
	mix.stop_loop("motor:test")
	_check(not mix.has_loop("motor:test"), "stop_loop removed it")

	# Master volume, the settings message's contract (agent R writes bus 0 directly).
	mix.set_master_volume(0.5)
	_check(not AudioServer.is_bus_mute(0) and absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.01,
		"set_master_volume(0.5) set bus 0 to %.2f dB and left it unmuted" % linear_to_db(0.5))
	mix.set_master_volume(0.0)
	_check(AudioServer.is_bus_mute(0),
		"set_master_volume(0) mutes rather than writing -inf dB")
	mix.set_master_volume(1.0)

	mix.stop_all()
	_check(mix.loop_keys().is_empty(), "stop_all freed every looping voice")

	root.remove_child(mix)
	mix.free()


# --- 4. the collect ramp ------------------------------------------------------

## brief-v3 §6 locks this: one semitone per consecutive collect, reset after 380 ms.
## The maths lives in collect_audio.gd; this checks the constant really is 2^(1/12)
## and that the ramp, the cap and the reset all behave, without a scene.
func _test_collect_ramp() -> void:
	var twelfth := pow(CollectAudio.SEMITONE_RATIO, 12.0)
	_check(absf(twelfth - 2.0) < 1e-9,
		"SEMITONE_RATIO ^ 12 is exactly an octave (%.12f)" % twelfth)
	_check(FightTypes.BOLT_COLLECT_RESET_MS == 380,
		"the reset window is the locked 380 ms (%d)" % FightTypes.BOLT_COLLECT_RESET_MS)

	var c := CollectAudio.new()
	root.add_child(c)
	var reset_s := float(FightTypes.BOLT_COLLECT_RESET_MS) / 1000.0

	var now := 1.0
	for i in 5:
		c.play_collect(now)
		now += 0.025
	_check(c.semitones == 4, "five consecutive collects climbed four semitones (%d)" % c.semitones)
	_check(absf(c.current_pitch() - pow(CollectAudio.SEMITONE_RATIO, 4.0)) < 1e-9,
		"the pitch is 2^(4/12) = %.6f" % pow(CollectAudio.SEMITONE_RATIO, 4.0))

	# A gap longer than the window resets it; a gap shorter than it does not.
	now += reset_s * 0.9
	c.play_collect(now)
	_check(c.semitones == 5, "a gap inside the window kept climbing (%d)" % c.semitones)
	now += reset_s + 0.010
	c.play_collect(now)
	_check(c.semitones == 0, "a gap past the window reset the ramp (%d)" % c.semitones)
	_check(is_equal_approx(c.current_pitch(), 1.0), "the reset pitch is exactly 1.0")

	# The cap.
	c.reset()
	now += 1.0
	for i in FightTypes.BOLT_MAX_SEMITONES + 20:
		c.play_collect(now)
		now += 0.020
	_check(c.semitones == FightTypes.BOLT_MAX_SEMITONES,
		"the ramp caps at BOLT_MAX_SEMITONES (%d)" % c.semitones)
	var cap_pitch: float = pow(CollectAudio.SEMITONE_RATIO, float(FightTypes.BOLT_MAX_SEMITONES))
	_check(absf(c.current_pitch() - cap_pitch) < 1e-6,
		"the capped pitch is %.3f, two octaves up" % cap_pitch)

	# step() expires the ramp even when no further collect ever arrives.
	c.step(now + reset_s + 0.1)
	_check(c.semitones == 0, "step() expired the ramp with no further collect")

	root.remove_child(c)
	c.free()


# --- 5. the bus layout --------------------------------------------------------

func _test_bus_layout() -> void:
	var layout: AudioBusLayout = load(AudioMix.BUS_LAYOUT) as AudioBusLayout
	_check(layout != null, "audio_bus_layout.tres loads as an AudioBusLayout")
	if layout == null:
		return

	# Installing the layout must NOT trample what the settings message wrote on bus 0.
	AudioServer.set_bus_volume_db(0, -7.0)
	AudioServer.set_bus_mute(0, true)
	var mix := AudioMix.new()
	root.add_child(mix)
	_check(mix.bus_layout_applied(), "AudioMix installed the bus layout")
	_check(absf(AudioServer.get_bus_volume_db(0) + 7.0) < 0.01 and AudioServer.is_bus_mute(0),
		"installing the layout preserved the master volume and mute the settings message set")
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_volume_db(0, 0.0)

	var names: Array[String] = []
	for i in AudioServer.bus_count:
		names.append(AudioServer.get_bus_name(i))
	var want: Array[String] = ["Master", "Music", "SFX", "Ambience", "UI"]
	_check(names == want,
		"the layout is Master, Music, SFX, Ambience, UI (%s)" % str(names))

	var sfx := AudioServer.get_bus_index(AudioMix.BUS_SFX)
	var master := 0
	_check(sfx > 0 and AudioServer.get_bus_send(sfx) == "Master", "SFX sends to Master")
	_check(AudioServer.get_bus_index(AudioMix.BUS_AMBIENCE) > 0
		and AudioServer.get_bus_send(AudioServer.get_bus_index(AudioMix.BUS_AMBIENCE)) == "Master",
		"Ambience sends to Master")
	_check(AudioServer.get_bus_index(AudioMix.BUS_UI) > 0
		and AudioServer.get_bus_send(AudioServer.get_bus_index(AudioMix.BUS_UI)) == "Master",
		"UI sends to Master")

	var reverb: AudioEffectReverb = null
	for e in AudioServer.get_bus_effect_count(sfx):
		var fx := AudioServer.get_bus_effect(sfx, e)
		if fx is AudioEffectReverb:
			reverb = fx
	_check(reverb != null, "there is a reverb on the SFX bus")
	if reverb != null:
		# An indoor arena, not a cathedral: a small hard room with a short tail and a
		# wet mix low enough that impacts stay impacts.
		_check(reverb.wet <= 0.20 and reverb.room_size <= 0.5,
			"the reverb is a small room at a low wet mix (room %.2f, wet %.2f)"
			% [reverb.room_size, reverb.wet])

	var limited := false
	for e in AudioServer.get_bus_effect_count(master):
		var fx := AudioServer.get_bus_effect(master, e)
		if fx is AudioEffectHardLimiter or fx is AudioEffectLimiter:
			limited = true
	_check(limited, "there is a limiter on the Master bus")

	root.remove_child(mix)
	mix.free()


# --- reporting ----------------------------------------------------------------

func _check(condition: bool, label: String, detail: String = "") -> void:
	if condition:
		_checks += 1
		print("PASS  ", label)
	else:
		_checks += 1
		_failures += 1
		if detail != "" and detail != "[]":
			printerr("      ", detail)
			print("      ", detail)
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	var line := "audio: %d checks, %d failures, %d skipped" % [_checks, _failures, _skipped]
	if _failures == 0:
		print("PASS  ", line)
	else:
		printerr("FAIL  ", line)
		print("FAIL  ", line)
	quit(1 if _failures > 0 else 0)
