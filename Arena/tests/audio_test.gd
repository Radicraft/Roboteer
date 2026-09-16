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
	# wave F (agent F2): the movement layer.
	"drive_whine_loop.wav",
	"roll_wheel_loop.wav",
	"track_clatter_loop.wav",
	"roll_omni_loop.wav",
	"skid_loop.wav",
	"scrape_loop.wav",
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
	await _test_crowd()
	await _test_machine_audio()
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

	# WAVE F. The ramp keeps its own six voices rather than going through AudioMix (it
	# has to: the pitch climbs per collect and the mixer's cap would steal them), and
	# until wave F those voices were on the MASTER bus at 0 dB, skipping both the SFX bus
	# and the -13 dB trim the catalogue says this sound has. Six of them at -3 dBFS sat
	# on the master limiter and pulled the whole mix down. Checked here so it cannot
	# drift back.
	var voice: AudioStreamPlayer = c.get_child(0) as AudioStreamPlayer
	_check(voice != null and voice.bus == AudioMix.BUS_SFX,
		"the collect ramp's voices are on the SFX bus, not straight onto Master (%s)"
		% (voice.bus if voice != null else "-"))
	_check(voice != null and absf(voice.volume_db
		- float(AudioMix.LEVELS["bolt_collect"])) < 0.01,
		"and at the catalogue's %.0f dB trim (%.2f)"
		% [float(AudioMix.LEVELS["bolt_collect"]),
		voice.volume_db if voice != null else 0.0])

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


# --- 6. the crowd (wave F, agent F2) ------------------------------------------
#
# The owner played wave G on his iPhone and could not hear the crowd. Two causes, both
# numbers, so both are tests now rather than notes:
#
#   LEVEL      the bed was -6 dB on a bus at -14 with a file RMS of -21 dBFS: -41 dBFS
#              of crowd against a -6 dBFS impact.
#   PLACEMENT  2.9 % of its energy above 2 kHz, which is nothing at all on a speaker
#              whose useful band starts around 700 Hz.
#
# There is no spectrum analyser here, so brightness is measured the way it can be from
# the PCM: the RMS of the first difference against the RMS of the signal. A first
# difference is a +6 dB/octave tilt, so that ratio rises with the centroid and is
# exactly the quantity that moved. Measured: the old bed -16.82 dB, this one -12.04 dB.

## dB of the first difference's RMS relative to the signal's own RMS. Higher is brighter.
const BED_MIN_RMS_DBFS := -19.0
const BED_MIN_BRIGHT_DB := -14.5
## The bolt tick went the OTHER way on purpose: a chime is bright and a nut landing in a
## steel bin is not. Old -7.94 dB, new -17.26 dB.
const BOLT_MAX_BRIGHT_DB := -13.0

func _test_crowd() -> void:
	var bed: AudioStreamWAV = load(AudioMix.SOUNDS["crowd_ambience_loop"]) as AudioStreamWAV
	if bed != null:
		var m := _levels(bed)
		print("      crowd bed   rms %.2f dBFS   brightness %.2f dB" % [m["rms"], m["bright"]])
		_check(m["rms"] >= BED_MIN_RMS_DBFS,
			"the crowd bed carries enough level to be heard (%.2f dBFS, floor %.1f)"
			% [m["rms"], BED_MIN_RMS_DBFS])
		_check(m["bright"] >= BED_MIN_BRIGHT_DB,
			"the crowd bed's energy is where a phone speaker can move air (%.2f dB, floor %.1f)"
			% [m["bright"], BED_MIN_BRIGHT_DB])
	var bolt: AudioStreamWAV = load(AudioMix.SOUNDS["bolt_collect"]) as AudioStreamWAV
	if bolt != null:
		var b := _levels(bolt)
		print("      bolt tick   rms %.2f dBFS   brightness %.2f dB" % [b["rms"], b["bright"]])
		_check(b["bright"] <= BOLT_MAX_BRIGHT_DB,
			"the bolt tick reads as metal in a bin, not a chime (%.2f dB, ceiling %.1f)"
			% [b["bright"], BOLT_MAX_BRIGHT_DB])

	# THE MIX AS A WHOLE, checked as arithmetic rather than as an opinion.
	#
	# TWO MEASURES, because one of them is not available for every file. LOUDNESS is the
	# one that matters — every file is normalised to -3 dBFS, so a peak comparison says
	# every sound in the game is the same size, which is the exact mistake that left the
	# horn quieter than the bell it is supposed to out-announce — but a QOA stream's
	# bytes cannot be read as PCM, so loudness is only measurable here for the files that
	# import as 16-bit PCM (every loop, the collect tick and the three crowd cues).
	# `docs/wave-f-f2-notes.md` carries the full measured table, from the source wavs.
	#
	#     loudness = file RMS + AudioMix.LEVELS[group] + the bus's volume_db
	#     headroom = -3 dBFS   + AudioMix.LEVELS[group] + the bus's volume_db
	var amb := _bus_db(AudioMix.BUS_AMBIENCE)
	var ui := _bus_db(AudioMix.BUS_UI)
	var sfx := _bus_db(AudioMix.BUS_SFX)
	var bed_db := _mix_db("crowd_ambience_loop", amb)
	var swell_db := _mix_db("crowd_swell_1", amb, "crowd_swell")
	var roar_db := _mix_db("crowd_roar", amb)
	var whine_db := _mix_db("drive_whine_loop", sfx)
	print("      crowd, measured dB at the master: bed %.1f  swell %.1f  roar %.1f | machine whine %.1f"
		% [bed_db, swell_db, roar_db, whine_db])
	_check(swell_db > bed_db + 1.0, "a reaction really lifts the crowd (%.1f over %.1f)"
		% [swell_db, bed_db])
	_check(roar_db > swell_db, "and a roar is bigger than a reaction (%.1f > %.1f)"
		% [roar_db, swell_db])
	# A machine flat out is level with the room: present, not a bed of its own. Both of
	# these import as PCM so both are really measured.
	_check(absf(whine_db - bed_db) < 6.0,
		"a machine at full throttle sits with the crowd (%.1f vs %.1f)" % [whine_db, bed_db])

	# The announcements, by headroom, because the bell and the horn are QOA.
	var bed_pk: float = -3.0 + float(AudioMix.LEVELS["crowd_ambience_loop"]) + amb
	var roar_pk: float = -3.0 + float(AudioMix.LEVELS["crowd_roar"]) + amb
	var bell_pk: float = -3.0 + float(AudioMix.LEVELS["bell"]) + ui
	var horn_pk: float = -3.0 + float(AudioMix.LEVELS["endgame_horn"]) + ui
	var heavy_pk: float = -3.0 + float(AudioMix.LEVELS["impact_heavy"]) + sfx
	print("      headroom: bed %.1f  roar %.1f | bell %.1f  horn %.1f  heavy %.1f"
		% [bed_pk, roar_pk, bell_pk, horn_pk, heavy_pk])
	_check(roar_pk <= bell_pk - 3.0 and roar_pk <= horn_pk - 3.0,
		"the loudest crowd cue stays 3 dB under the bell and the horn (roar %.1f, bell %.1f, horn %.1f)"
		% [roar_pk, bell_pk, horn_pk])
	_check(bed_pk >= heavy_pk - 14.0,
		"the crowd bed is within 14 dB of a heavy impact (%.1f vs %.1f)" % [bed_pk, heavy_pk])
	# G6 wrote that the horn is "the loudest announcement after the bell". Until wave F it
	# was not: its trim had been set on a peak, and a horn is a sustained tone with a low
	# crest factor where the bell is a transient with a high one.
	_check(horn_pk > heavy_pk - 4.0 and horn_pk <= heavy_pk,
		"the horn is an announcement, right under a heavy hit (%.1f vs %.1f)"
		% [horn_pk, heavy_pk])

	var mix := AudioMix.new()
	root.add_child(mix)
	await process_frame
	var base := mix.ambience_db()
	mix.start_loop("ambience", "crowd_ambience_loop")
	var bed_level: float = float(AudioMix.LEVELS["crowd_ambience_loop"])
	_check(absf(mix.ambience_voice_db() - bed_level) < 0.01,
		"the crowd bed plays at its written trim (%.2f)" % mix.ambience_voice_db())

	# The duck. docs/audio-notes.md §8 weakness 4 asked for a sidechain on Ambience keyed
	# off SFX; Godot has no sidechain, so the bell and the horn pull the crowd's VOICES
	# down. Not the bus: the fader belongs to the player's settings and to the endgame,
	# and a duck that borrowed it would have to hand back a number it does not own.
	mix.play("bell")
	var depth: float = float((AudioMix.DUCKS["bell"] as Array)[0])
	_check(absf(mix.ambience_voice_db() - (bed_level - depth)) < 0.01,
		"the bell ducks the crowd by %.0f dB (%.2f -> %.2f)"
		% [depth, bed_level, mix.ambience_voice_db()])
	_check(absf(mix.ambience_db() - base) < 0.01,
		"and does NOT touch the Ambience fader (%.2f)" % mix.ambience_db())
	# Held while it rings, then released. 1.4 s of hold plus 6 dB at 9 dB/s.
	mix.step(1.0)
	_check(mix.duck_db() >= depth - 0.01, "the duck holds while the bell is still ringing")
	for i in 40:
		mix.step(0.05)
	_check(absf(mix.ambience_voice_db() - bed_level) < 0.01,
		"the crowd is all the way back afterwards (%.2f)" % mix.ambience_voice_db())

	# A crowd cue started while the bell is ringing is born ducked, rather than arriving
	# at full level over the top of it.
	mix.play("bell")
	var ducked_swell: Node = mix.crowd_reaction("FLIPPED")
	_check(ducked_swell != null and float(ducked_swell.get("volume_db"))
		<= float(AudioMix.LEVELS["crowd_swell"]) - depth + 0.01,
		"a swell that starts under the bell starts ducked (%.2f)"
		% (float(ducked_swell.get("volume_db")) if ducked_swell != null else 0.0))
	for i in 60:
		mix.step(0.05)

	# The lift is the fader's, the duck is the voices', and they never see each other.
	mix.set_endgame(true)
	_check(absf(mix.ambience_db() - (base + AudioMix.AMBIENCE_HOT_DB)) < 0.01,
		"the endgame lifts the crowd's fader by %.0f dB" % AudioMix.AMBIENCE_HOT_DB)
	mix.play("endgame_horn")
	var horn_depth: float = float((AudioMix.DUCKS["endgame_horn"] as Array)[0])
	_check(absf(mix.ambience_voice_db() - (bed_level - horn_depth)) < 0.01,
		"the horn ducks the bed under the lift (%.2f)" % mix.ambience_voice_db())
	_check(absf(mix.ambience_db() - (base + AudioMix.AMBIENCE_HOT_DB)) < 0.01,
		"and the fader still reads the lift alone (%.2f)" % mix.ambience_db())
	mix.stop_all()
	_check(absf(mix.ambience_db() - base) < 0.01,
		"stop_all hands the fader back exactly (%.2f)" % mix.ambience_db())

	# The reactions.
	var big: Node = mix.crowd_reaction("BIG HIT")
	_check(big != null, "BIG HIT earns a crowd swell")
	if big != null:
		_check(str(big.get("bus")) == AudioMix.BUS_AMBIENCE,
			"the swell plays on the Ambience bus, with the crowd")
	_check(mix.crowd_reaction("BIG HIT") == null,
		"a second BIG HIT inside the gap does not stack a second swell")
	_check(mix.crowd_reaction("PINNED") == null,
		"a line the crowd does not care about says nothing")
	_check(mix.crowd_reaction("FLIPPED") != null, "FLIPPED earns its own swell")
	mix.step(10.0)
	_check(mix.crowd_reaction(AudioMix.SWELL_KO) != null, "the knockout count earns a roar")
	_check(mix.active_count("crowd_swell") <= mix.cap_for("crowd_swell"),
		"the crowd stayed inside its cap")

	root.remove_child(mix)
	mix.free()
	_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioMix.BUS_AMBIENCE)) - base) < 0.01,
		"a mixer freed mid-fight leaves the crowd's fader where it found it")


## RMS and a brightness proxy, in dB, straight off the imported PCM.
static func _levels(wav: AudioStreamWAV) -> Dictionary:
	var channels := 2 if wav.stereo else 1
	var data := wav.data
	var frames := data.size() / (2 * channels)
	if frames < 8:
		return {"rms": -120.0, "bright": -120.0}
	var sum_sq := 0.0
	var sum_d := 0.0
	var prev := 0.0
	for i in frames:
		var v := 0.0
		for c in channels:
			v += float(data.decode_s16(i * 2 * channels + c * 2))
		v /= float(channels) * 32768.0
		sum_sq += v * v
		if i > 0:
			sum_d += (v - prev) * (v - prev)
		prev = v
	var rms := sqrt(sum_sq / float(frames))
	var drms := sqrt(sum_d / float(frames - 1))
	return {
		"rms": linear_to_db(maxf(rms, 1e-9)),
		"bright": linear_to_db(maxf(drms, 1e-9)) - linear_to_db(maxf(rms, 1e-9)),
	}


## One group's loudness at the master: its file's own RMS, plus the catalogue trim, plus
## the bus. `file_key` is the SOUNDS entry to measure; `group` is the LEVELS entry, which
## differs for a variant set.
static func _mix_db(file_key: String, bus_db: float, group: String = "") -> float:
	var wav: AudioStreamWAV = load(AudioMix.SOUNDS[file_key]) as AudioStreamWAV
	if wav == null:
		return -120.0
	var key := group if group != "" else file_key
	return float(_levels(wav)["rms"]) + float(AudioMix.LEVELS.get(key, 0.0)) + bus_db


static func _bus_db(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_volume_db(i) if i >= 0 else 0.0


# --- 7. the movement layer (wave F, agent F2) ---------------------------------
#
# `FightFx.set_motor_state` has existed since Stage 3 and nothing in the game has ever
# called it, so there were no movement sounds at all. MachineAudio reads the machines
# itself every presentation frame; these checks are that what it reads really does move
# the loops, and that a Rumble cannot blow the voice budget doing it.

class FakeDrive extends RefCounted:
	var id := "4wd"
	var top := 3.5
	var turn := 3.2
	var power := 1.0
	var strafe := false
	func top_speed() -> float: return top
	func turn_rate() -> float: return turn
	func track_half() -> float: return 0.18
	func power_scale() -> float: return power
	func strafes() -> bool: return strafe


class FakeBot extends Node3D:
	var bot_id := "player-1"
	var chassis: RigidBody3D = null
	var drive_module: RefCounted = null
	var _last_input: Dictionary = {"heading": Vector2.ZERO, "turn": 0.0}
	var _frozen := false
	var inverted := false
	var grounded := true
	func is_inverted() -> bool: return inverted
	func wheel_contacts() -> Array: return [grounded, grounded]
	func ride_height() -> float: return 0.11


func _make_bot(id: String, drive_id: String) -> FakeBot:
	var bot := FakeBot.new()
	bot.bot_id = id
	bot.name = "Fake_" + id
	var drive := FakeDrive.new()
	drive.id = drive_id
	drive.strafe = drive_id == "omni"
	bot.drive_module = drive
	var body := RigidBody3D.new()
	body.name = "Chassis"
	body.freeze = true
	body.contact_monitor = false
	bot.add_child(body)
	bot.chassis = body
	root.add_child(bot)
	return bot


## The chassis is frozen, so `linear_velocity` is a value this test writes and nothing
## integrates: exactly the seam a headless test needs. Set the machine's motion.
static func _drive_bot(bot: FakeBot, heading: Vector2, speed_ms: float,
		yaw: float = 0.0, turn: float = 0.0) -> void:
	bot._last_input = {"heading": heading, "turn": turn}
	bot.chassis.linear_velocity = Vector3(speed_ms, 0.0, 0.0)
	bot.chassis.angular_velocity = Vector3(0.0, yaw, 0.0)


func _test_machine_audio() -> void:
	var mix := AudioMix.new()
	root.add_child(mix)
	var machines := MachineAudio.new()
	root.add_child(machines)
	machines.bind(mix)
	await process_frame

	var bot := _make_bot("player-1", "4wd")
	machines.bind_bots([bot])

	# Settle: two seconds of standing still, which is also the SETTLE_S window in which
	# nothing may thud.
	_drive_bot(bot, Vector2.ZERO, 0.0)
	for i in 120:
		machines.step(1.0 / 60.0)
	var whine_key := "machine:whine:player-1"
	var roll_key := "machine:roll:player-1"
	_check(mix.has_loop(whine_key), "a machine on the floor has a drive whine")
	_check(mix.loop_sound(roll_key) == "roll_wheel_loop",
		"a wheeled machine rolls on the tyre loop (%s)" % mix.loop_sound(roll_key))
	var idle_player: Node = mix.loop_player(whine_key)
	var idle_pitch := float(idle_player.get("pitch_scale"))
	var idle_db := float(idle_player.get("volume_db"))

	# THE ONE THAT MATTERS: pitch and level follow speed and throttle, and the loop is
	# re-pointed rather than restarted (a restart is a click per frame).
	_drive_bot(bot, Vector2(1, 0), 3.5)
	for i in 120:
		machines.step(1.0 / 60.0)
	var full_player: Node = mix.loop_player(whine_key)
	var full_pitch := float(full_player.get("pitch_scale"))
	var full_db := float(full_player.get("volume_db"))
	print("      whine: idle pitch %.3f @ %.1f dB -> full pitch %.3f @ %.1f dB"
		% [idle_pitch, idle_db, full_pitch, full_db])
	_check(full_player == idle_player,
		"the whine loop was re-pointed all the way, never restarted")
	_check(full_pitch > idle_pitch + 0.3,
		"the whine's pitch tracks speed (%.3f -> %.3f)" % [idle_pitch, full_pitch])
	_check(full_db > idle_db + 10.0,
		"the whine's level tracks throttle (%.1f -> %.1f dB)" % [idle_db, full_db])
	var expect: Array = MachineAudio.DRIVES["4wd"]["whine_pitch"]
	_check(absf(full_pitch - float(expect[1])) < 0.08,
		"at top speed it is at the 4WD's written top pitch (%.3f, want %.2f)"
		% [full_pitch, float(expect[1])])

	# Halfway is halfway: monotonic, not a switch.
	_drive_bot(bot, Vector2(0.5, 0), 1.75)
	for i in 120:
		machines.step(1.0 / 60.0)
	var half_pitch := float(mix.loop_player(whine_key).get("pitch_scale"))
	_check(half_pitch > idle_pitch and half_pitch < full_pitch,
		"half speed is between the two (%.3f)" % half_pitch)

	# Per drive: tracks clatter, an omni patters, and nothing else changes.
	for pair in [["tracks", "track_clatter_loop"], ["omni", "roll_omni_loop"],
			["6wd", "roll_wheel_loop"], ["2wd", "roll_wheel_loop"]]:
		machines.stop_all()
		var b := _make_bot("drive-" + str(pair[0]), str(pair[0]))
		machines.bind_bots([b])
		_drive_bot(b, Vector2(1, 0), 2.0)
		for i in 40:
			machines.step(1.0 / 60.0)
		var key := "machine:roll:drive-" + str(pair[0])
		_check(mix.loop_sound(key) == str(pair[1]),
			"a %s rolls on %s (%s)" % [pair[0], pair[1], mix.loop_sound(key)])
		b.queue_free()
		await process_frame

	# The skid. A pivot on the spot is both sides scrubbing and no road speed at all,
	# which is the case a speed-derived test would call "stopped".
	machines.stop_all()
	machines.bind_bots([bot])
	_drive_bot(bot, Vector2.ZERO, 0.1, 3.4, 1.0)
	for i in 60:
		machines.step(1.0 / 60.0)
	var skid_key := "machine:skid:player-1"
	_check(mix.has_loop(skid_key), "spinning on the spot makes a skid")
	_check(float(machines.state_of("player-1")["skid_level"]) > 0.2,
		"the skid is at a real level (%.2f)"
		% float(machines.state_of("player-1")["skid_level"]))

	# A stick that goes over faster than the drive can follow skids BEFORE the physics
	# catches up: full throttle along the nose, stick square across it. Ninety degrees
	# and not a hundred and eighty, because past DriveBase.REVERSE_ANGLE the drive backs
	# toward the stick instead of spinning for it, and backing up is not a scrub.
	_drive_bot(bot, Vector2(0, 1), 2.5, 0.0, 0.0)
	for i in 20:
		machines.step(1.0 / 60.0)
	_check(float(machines.state_of("player-1")["skid_raw"]) > 0.3,
		"a heading the drive cannot follow scrubs (%.2f)"
		% float(machines.state_of("player-1")["skid_raw"]))

	# And it lets go: silent for TRANSIENT_HOLD_S and the voice is freed.
	_drive_bot(bot, Vector2(1, 0), 3.5, 0.0, 0.0)
	for i in 120:
		machines.step(1.0 / 60.0)
	_check(not mix.has_loop(skid_key), "a machine that stops sliding gives the voice back")

	# The landing. Off the floor for longer than a bounce, falling hard, then down.
	var before := mix.active_count("chassis_thud")
	bot.grounded = false
	bot.chassis.global_position = Vector3(0.0, 1.4, 0.0)
	bot.chassis.linear_velocity = Vector3(0.0, -3.6, 0.0)
	for i in 30:
		machines.step(1.0 / 60.0)
	bot.grounded = true
	bot.chassis.global_position = Vector3.ZERO
	machines.step(1.0 / 60.0)
	_check(mix.active_count("chassis_thud") > before,
		"a machine that has been thrown lands with a thud")
	_check(float(machines.state_of("player-1")["last_land"]) >= MachineAudio.LAND_MIN_MS,
		"and the thud is sized by how hard it arrived")

	# A Rumble: three machines, every one of them sliding, scraping and landing at once.
	machines.stop_all()
	var crowd: Array = [bot]
	for i in 2:
		var extra := _make_bot("rumble-%d" % i, "4wd")
		crowd.append(extra)
	machines.bind_bots(crowd)
	for machine in crowd:
		_drive_bot(machine as FakeBot, Vector2(-1, 0), 2.6, 3.4, 1.0)
	for i in 120:
		machines.step(1.0 / 60.0)
	var transient := 0
	for key in machines.loop_keys():
		if str(key).begins_with("machine:skid") or str(key).begins_with("machine:scrape"):
			transient += 1
	print("      rumble: %d machine loops, %d of them transient"
		% [machines.loop_keys().size(), transient])
	_check(transient <= MachineAudio.MAX_TRANSIENT_LOOPS,
		"three machines sliding at once stay inside MAX_TRANSIENT_LOOPS (%d of %d)"
		% [transient, MachineAudio.MAX_TRANSIENT_LOOPS])
	for i in 40:
		mix.play("chassis_thud", Vector3.ZERO)
	_check(mix.active_count("chassis_thud") <= mix.cap_for("chassis_thud"),
		"forty landings in one frame stay inside the thud cap (%d of %d)"
		% [mix.active_count("chassis_thud"), mix.cap_for("chassis_thud")])

	# A MACHINE FREED BETWEEN TWO SCANS. This is not hypothetical: a bot is eliminated,
	# or a world is torn down, and MachineAudio's list is only rebuilt every RESCAN_S. A
	# freed object cannot even be PASSED to a typed parameter — GDScript checks the
	# argument's class before the body runs — so a guard inside the step function is too
	# late. Caught in a real suite run, fixed at the call site, checked here.
	var doomed: FakeBot = crowd[crowd.size() - 1] as FakeBot
	var doomed_id := doomed.bot_id
	crowd.remove_at(crowd.size() - 1)
	root.remove_child(doomed)
	doomed.free()
	for i in 10:
		machines.step(1.0 / 60.0)
	_check(machines.state_of(doomed_id).is_empty(),
		"a machine that was freed mid-fight is dropped rather than stepped")
	var orphaned := 0
	for key in mix.loop_keys():
		if str(key).ends_with(doomed_id):
			orphaned += 1
	_check(orphaned == 0, "and takes its voices with it (%d left)" % orphaned)

	# Teardown: nothing of this node's survives it.
	machines.stop_all()
	var left := 0
	for key in mix.loop_keys():
		if str(key).begins_with("machine:"):
			left += 1
	_check(left == 0, "stop_all freed every machine voice (%d left)" % left)

	for machine in crowd:
		(machine as Node).queue_free()
	root.remove_child(machines)
	machines.free()
	root.remove_child(mix)
	mix.free()
	await process_frame


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
