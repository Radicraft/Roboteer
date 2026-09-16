extends SceneTree
## Headless test for the commentary and the endgame cues (agent G6, brief v4 §10 item 2).
##   Godot --headless --path Arena --script tests/commentary_test.gd
## Exit code 0 = PASS.
##
## Nobody can hear anything in a headless run and the owner is working at this Mac, so
## the audio half is checked NUMERICALLY and nothing is ever played out loud: the stream
## loads, the voice is playing, the loop exists on the Music bus, and the Ambience bus
## really moved by the number the mixer says it moves by.
##
## What is checked:
##   1. every one of the seven triggers produces its own line, once;
##   2. the HUD's queue: one line every 2 s, a line that waited longer than 2 s is
##      dropped rather than shown late, and nothing at all during the countdown;
##   3. the endgame: the horn starts on the endgame phase and NOT before, the drone
##      loop runs on the Music bus, the crowd gets AMBIENCE_HOT_DB hotter, and it all
##      goes back when the fight is torn down;
##   4. commentary is presentation: no random draw, no wall clock, no write into
##      anything the simulation reads. (The replay proof itself is determinism_test,
##      which the suite runs; this file checks the property that makes it hold.)

const TICK := 1.0 / 60.0

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await _test_triggers()
	await _test_hud_queue()
	await _test_endgame_audio()
	_test_presentation_discipline()
	_finish()


# --- 1. the triggers ----------------------------------------------------------

func _test_triggers() -> void:
	var c := FightCommentary.new()
	c.reset("drop_zone", 2)

	# Nothing is said outside a running fight, however many facts arrive.
	c.note_pin(0, true)
	c.step(1.0, {"state": "countdown", "inverted": [true, false], "readiness": [1.0, 1.0],
		"spinning": [true, true]})
	_check(c.said().is_empty(), "nothing is said during the countdown (%s)" % str(c.said()))

	# BIG HIT is the FX layer's own heavy-impact threshold, so the line agrees with the
	# sample the player just heard.
	_check(is_equal_approx(FightCommentary.BIG_HIT_SEVERITY, FightFx.IMPACT_HEAVY_SEVERITY),
		"BIG HIT is the FX heavy-impact severity (%.2f)" % FightCommentary.BIG_HIT_SEVERITY)
	c.note_damage({"severity": FightCommentary.BIG_HIT_SEVERITY - 0.05, "detached": false})
	_check(c.said_count(FightCommentary.LINE_BIG_HIT) == 0, "a light hit says nothing")
	c.note_damage({"severity": FightCommentary.BIG_HIT_SEVERITY, "detached": false})
	_check(c.said_count(FightCommentary.LINE_BIG_HIT) == 1, "a heavy hit says BIG HIT")
	c.note_damage({"severity": 0.9, "detached": false})
	_check(c.said_count(FightCommentary.LINE_BIG_HIT) == 1,
		"a second heavy hit inside the repeat window does not repeat it")
	# A blow that takes a part off is a big hit whatever the severity says.
	var c2 := FightCommentary.new()
	c2.reset("yard", 2)
	c2.note_damage({"severity": 0.01, "detached": true})
	_check(c2.said_count(FightCommentary.LINE_BIG_HIT) == 1, "a detaching blow says BIG HIT")

	# PINNED needs the pin to HOLD; the rule's own answer flickers. The hold is timed
	# from the first frame the pin is SEEN, so the first step only starts the clock.
	c.note_pin(0, false)
	c.note_pin(1, true)
	c.step(TICK, _fighting())
	c.step(FightCommentary.PIN_HOLD_S * 0.5, _fighting())
	_check(c.said_count(FightCommentary.LINE_PINNED) == 0, "a momentary pin says nothing")
	c.step(FightCommentary.PIN_HOLD_S * 0.6, _fighting())
	_check(c.said_count(FightCommentary.LINE_PINNED) == 1, "a pin that holds says PINNED")
	c.step(1.0, _fighting())
	_check(c.said_count(FightCommentary.LINE_PINNED) == 1, "and it says it once, not per frame")
	c.note_pin(1, false)
	c.step(0.1, _fighting())
	c.note_pin(1, true)
	c.step(TICK, _fighting())
	c.step(FightCommentary.PIN_HOLD_S + 0.1, _fighting())
	_check(c.said_count(FightCommentary.LINE_PINNED) == 1,
		"a second pin inside the repeat window does not repeat it")

	# FLIPPED, on the rising edge of either machine's inversion.
	c.step(0.1, _fighting({"inverted": [true, false]}))
	_check(c.said_count(FightCommentary.LINE_FLIPPED) == 1, "an inverted machine says FLIPPED")
	c.step(0.1, _fighting({"inverted": [true, false]}))
	_check(c.said_count(FightCommentary.LINE_FLIPPED) == 1, "and it is an edge, not a state")

	# SPINNING UP, when a spinner reaches READY, re-armed only once it is spun down.
	c.step(0.1, _fighting({"readiness": [1.0, 0.0], "spinning": [true, false]}))
	_check(c.said_count(FightCommentary.LINE_SPINNING_UP) == 1, "a spun-up bar says SPINNING UP")
	c.step(0.1, _fighting({"readiness": [1.0, 0.0], "spinning": [true, false]}))
	_check(c.said_count(FightCommentary.LINE_SPINNING_UP) == 1, "and only as it crosses")
	# A non-spinning weapon at full readiness (a flipper with gas) never says it.
	var c3 := FightCommentary.new()
	c3.reset("yard", 2)
	c3.step(0.1, _fighting({"readiness": [1.0, 1.0], "spinning": [false, false]}))
	_check(c3.said_count(FightCommentary.LINE_SPINNING_UP) == 0,
		"a weapon that does not spin never says SPINNING UP")

	# IN THE ZONE, on the way in only.
	c.note_zone(true, "THRESHER")
	_check(c.said_count(FightCommentary.LINE_IN_THE_ZONE) == 1, "entering the corner says IN THE ZONE")
	c.note_zone(true, "THRESHER")
	_check(c.said_count(FightCommentary.LINE_IN_THE_ZONE) == 1, "and staying in it says it once")

	# HOUSE BOT OUT, and PIT OPEN only where there is a pit.
	c.note_house_bot_out()
	_check(c.said_count(FightCommentary.LINE_HOUSE_BOT_OUT) == 1, "the release says HOUSE BOT OUT")
	c.note_house_bot_out()
	_check(c.said_count(FightCommentary.LINE_HOUSE_BOT_OUT) == 1, "once a fight, not twice")
	c.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(c.said_count(FightCommentary.LINE_PIT_OPEN) == 1, "the Drop Zone endgame says PIT OPEN")
	c.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(c.said_count(FightCommentary.LINE_PIT_OPEN) == 1, "and the endgame only turns once")
	var yard := FightCommentary.new()
	yard.reset("yard", 2)
	yard.on_phase_changed(FightTypes.PHASE_OPEN)
	_check(yard.said().is_empty(), "the open phase says nothing")
	yard.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(yard.said_count(FightCommentary.LINE_PIT_OPEN) == 0,
		"an arena with no pit does not say PIT OPEN")

	# All seven of the brief's lines are reachable, and reset forgets them.
	var seen := {}
	for line in c.said():
		seen[line] = true
	for line in yard.said():
		seen[line] = true
	var missing: Array[String] = []
	for line in FightCommentary.LINES:
		if not seen.has(line):
			missing.append(line)
	_check(missing.is_empty(), "all seven lines of brief §10 item 2 fired (missing %s)" % str(missing))
	c.reset("yard", 2)
	_check(c.said().is_empty() and not c.endgame_fired(), "reset forgets the last fight")


func _fighting(extra: Dictionary = {}) -> Dictionary:
	var facts := {
		"state": "fighting",
		"inverted": [false, false],
		"readiness": [0.0, 0.0],
		"spinning": [true, true],
	}
	for key in extra:
		facts[key] = extra[key]
	return facts


# --- 2. the HUD's line --------------------------------------------------------

func _test_hud_queue() -> void:
	var hud_scene: PackedScene = load("res://ui/hud.tscn")
	_check(hud_scene != null, "hud.tscn loads")
	if hud_scene == null:
		return
	var hud: FightHud = hud_scene.instantiate() as FightHud
	root.add_child(hud)
	await _frames(1)
	hud.clear_commentary()

	# Nothing during the countdown, and nothing queued for afterwards either: a line
	# about the countdown is a line about nothing.
	hud.set_coach_phase(FightHud.COACH_COUNTDOWN)
	hud.push_commentary("BIG HIT")
	hud.commentary_step(0.1)
	_check(hud.commentary_text() == "" and hud.commentary_queued() == 0,
		"nothing is shown or queued during the countdown")

	hud.set_coach_phase(FightHud.COACH_FIGHTING)
	hud.clear_commentary()
	hud.push_commentary("big hit")
	hud.commentary_step(TICK)
	_check(hud.commentary_text() == "BIG HIT", "a line appears, in capitals (%s)"
		% hud.commentary_text())
	_check(is_equal_approx(hud.commentary_alpha(), 1.0), "at full opacity")

	# And it sits where nothing else does: the strap the wave G HUD put under the names
	# row is the Broadcast TICKER along the bottom from wave V on (docs/design-system.md
	# section 4), so the line is below the names row and below the knockout count, in the
	# bottom strip, clear of the endgame sting across the middle. Measured on the label's
	# own rect, because "it looks fine" is not a headless answer.
	var line: Label = hud.get_node_or_null("Root/Commentary") as Label
	var names: Label = hud.get_node_or_null("Root/Names") as Label
	var ko: Label = hud.get_node_or_null("Root/KoCount") as Label
	_check(line != null and names != null and ko != null, "the HUD's rows are all built")
	if line != null and names != null and ko != null:
		_check(line.global_position.y >= names.global_position.y + names.size.y,
			"the line is below the names row (%.0f vs %.0f)"
			% [line.global_position.y, names.global_position.y + names.size.y])
		_check(line.global_position.y >= ko.global_position.y + ko.size.y,
			"and below the knockout count, in the ticker (%.0f vs %.0f)"
			% [line.global_position.y, ko.global_position.y + ko.size.y])
		var strip: Rect2 = hud.ticker_rect()
		_check(line.global_position.y >= strip.position.y - 0.5
			and line.global_position.y + line.size.y <= strip.position.y + strip.size.y + 0.5,
			"and inside the ticker strip %s" % str(strip))

	# It holds, then fades, then it is gone.
	hud.commentary_step(FightHud.COMMENTARY_HOLD_S - TICK * 2.0)
	_check(is_equal_approx(hud.commentary_alpha(), 1.0),
		"it holds for %.1f s" % FightHud.COMMENTARY_HOLD_S)
	hud.commentary_step(TICK * 2.0 + FightHud.COMMENTARY_FADE_S * 0.5)
	var mid := hud.commentary_alpha()
	_check(mid > 0.1 and mid < 0.9, "then fades (%.2f through the fade)" % mid)
	hud.commentary_step(FightHud.COMMENTARY_FADE_S)
	_check(not hud.commentary_visible() and hud.commentary_text() == "",
		"and is gone after the %.2f s fade" % FightHud.COMMENTARY_FADE_S)

	# One line every two seconds, and the second one really does appear.
	hud.clear_commentary()
	hud.push_commentary("FIRST")
	hud.push_commentary("SECOND")
	hud.commentary_step(TICK)
	_check(hud.commentary_text() == "FIRST" and hud.commentary_queued() == 1,
		"two lines at once: the first shows, the second waits")
	hud.commentary_step(FightHud.COMMENTARY_GAP_S - TICK * 2.0)
	_check(hud.commentary_text() != "SECOND", "the second is still waiting before the gap")
	hud.commentary_step(TICK * 2.0)
	_check(hud.commentary_text() == "SECOND" and hud.commentary_queued() == 0,
		"and shows exactly on the %.0f s gap (%s)"
		% [FightHud.COMMENTARY_GAP_S, hud.commentary_text()])

	# A line nobody had room for inside two seconds is dropped, not shown late.
	hud.clear_commentary()
	hud.push_commentary("FIRST")
	hud.push_commentary("SECOND")
	hud.push_commentary("THIRD")
	hud.commentary_step(TICK)
	_check(hud.commentary_queued() == 2, "three at once: two are queued")
	hud.commentary_step(FightHud.COMMENTARY_GAP_S)
	_check(hud.commentary_text() == "SECOND", "the second shows on the gap")
	_check(hud.commentary_queued() == 0,
		"and the third was dropped as stale rather than shown %.0f s late"
		% (FightHud.COMMENTARY_GAP_S * 2.0))
	hud.commentary_step(FightHud.COMMENTARY_GAP_S)
	_check(hud.commentary_text() == "", "so nothing appears after it")

	# The whole chain: commentary.gd -> hud.
	hud.clear_commentary()
	var c := FightCommentary.new()
	c.bind(hud, null)
	c.reset("drop_zone", 2)
	c.note_house_bot_out()
	hud.commentary_step(TICK)
	_check(hud.commentary_text() == FightCommentary.LINE_HOUSE_BOT_OUT,
		"a rules event reaches the HUD (%s)" % hud.commentary_text())
	# And reset clears the screen as well as the memory.
	c.reset("drop_zone", 2)
	hud.commentary_step(TICK)
	_check(hud.commentary_text() == "", "a new fight starts with a clear line")
	hud.queue_free()


# --- 3. the endgame cues ------------------------------------------------------

func _test_endgame_audio() -> void:
	var mix := AudioMix.new()
	root.add_child(mix)
	await _frames(1)
	_check(mix.missing_sounds().is_empty(),
		"every sound loaded, the two new cues included (%s)" % str(mix.missing_sounds()))
	_check(AudioMix.SOUNDS.has("endgame_horn") and AudioMix.SOUNDS.has("endgame_drone_loop"),
		"the horn and the drone are in the catalogue")
	var horn: AudioStreamWAV = load(AudioMix.SOUNDS["endgame_horn"]) as AudioStreamWAV
	var drone: AudioStreamWAV = load(AudioMix.SOUNDS["endgame_drone_loop"]) as AudioStreamWAV
	_check(horn != null and horn.mix_rate == 44100 and not horn.stereo,
		"endgame_horn.wav is a 44.1 kHz mono AudioStreamWAV")
	_check(drone != null and drone.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"endgame_drone_loop.wav imported as LOOP_FORWARD")
	_check(AudioMix.BUSES.get("endgame_horn", "") == AudioMix.BUS_UI,
		"the horn is on the UI bus, beside the bell")
	_check(AudioMix.BUSES.get("endgame_drone_loop", "") == AudioMix.BUS_MUSIC,
		"the drone is the first thing on the Music bus")
	_check(int(AudioMix.CAPS.get("endgame_horn", 0)) == 1, "one horn at a time")

	var ambience_bus := AudioServer.get_bus_index(AudioMix.BUS_AMBIENCE)
	_check(ambience_bus >= 0, "the Ambience bus exists")
	var before := AudioServer.get_bus_volume_db(ambience_bus)

	var c := FightCommentary.new()
	c.bind(null, mix)
	c.reset("yard", 2)
	_check(mix.active_count("endgame_horn") == 0 and not mix.has_loop(AudioMix.ENDGAME_LOOP_KEY),
		"no horn and no music before the endgame")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(ambience_bus), before),
		"and the crowd is at its ordinary level")

	# The open phase is not the endgame.
	c.on_phase_changed(FightTypes.PHASE_OPEN)
	_check(mix.active_count("endgame_horn") == 0, "the open phase does not blow the horn")

	c.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(mix.active_count("endgame_horn") == 1, "the endgame starts the horn")
	_check(mix.has_loop(AudioMix.ENDGAME_LOOP_KEY), "and starts the drone on the Music bus")
	var loop: Node = mix.get_node_or_null("Loop_music_endgame")
	_check(loop != null and bool(loop.get("playing")), "the drone voice is really playing")
	_check(loop != null and str(loop.get("bus")) == AudioMix.BUS_MUSIC,
		"on the Music bus (%s)" % (str(loop.get("bus")) if loop != null else "-"))
	_check(loop != null and is_equal_approx(float(loop.get("volume_db")),
		float(AudioMix.LEVELS["endgame_drone_loop"])),
		"at its written trim, %.0f dB" % float(AudioMix.LEVELS["endgame_drone_loop"]))
	var hot := AudioServer.get_bus_volume_db(ambience_bus)
	_check(is_equal_approx(hot, before + AudioMix.AMBIENCE_HOT_DB),
		"the crowd is %.0f dB hotter (%.2f -> %.2f)" % [AudioMix.AMBIENCE_HOT_DB, before, hot])

	c.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(mix.active_count("endgame_horn") == 1, "the round only turns once: still one horn")

	# Teardown puts the mix back where the player's settings left it.
	mix.stop_all()
	_check(not mix.has_loop(AudioMix.ENDGAME_LOOP_KEY), "stop_all stops the drone")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(ambience_bus), before),
		"and puts the Ambience bus back (%.2f)" % AudioServer.get_bus_volume_db(ambience_bus))
	_check(not mix.endgame_active(), "and the mixer knows the endgame is over")

	# A mixer that is freed mid-endgame hands the bus back. A new fight builds a new
	# world, a new FX subtree and a new AudioMix; without this the crowd would stay 4 dB
	# hot into the next fight and 8 dB into the one after that.
	var doomed := AudioMix.new()
	root.add_child(doomed)
	await _frames(1)
	var c2 := FightCommentary.new()
	c2.bind(null, doomed)
	c2.reset("yard", 2)
	c2.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(ambience_bus),
		before + AudioMix.AMBIENCE_HOT_DB), "a second endgame lifts the crowd again")
	root.remove_child(doomed)
	doomed.free()
	_check(is_equal_approx(AudioServer.get_bus_volume_db(ambience_bus), before),
		"and freeing the mixer mid-endgame puts it back (%.2f)"
		% AudioServer.get_bus_volume_db(ambience_bus))

	# A commentary with no audio director at all is silent, not broken: the FX subtree
	# is deletable by design (docs/audio-notes.md).
	var bare := FightCommentary.new()
	bare.reset("drop_zone", 2)
	bare.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(bare.said_count(FightCommentary.LINE_PIT_OPEN) == 1,
		"with no audio director the lines still work")
	mix.queue_free()


# --- 4. presentation discipline -----------------------------------------------

## The replay proof is determinism_test, which re-simulates a fight and compares the
## result byte for byte. What THIS checks is the property that makes it hold: the
## commentary draws no randomness and reads no wall clock, so it cannot move the fight's
## seeded sequence, and it writes nothing back into the simulation.
func _test_presentation_discipline() -> void:
	var source := FileAccess.get_file_as_string("res://fight/commentary.gd")
	_check(not source.is_empty(), "commentary.gd reads back")
	for banned in ["randf(", "randi(", "randf_range(", "randi_range(",
			"Time.get_ticks_msec", "Time.get_unix_time", "OS.get_"]:
		_check(not source.contains(banned),
			"commentary.gd never calls %s (it would move the fight's sequence)" % banned)
	# It talks to the HUD and the audio director and to nothing else: no bot, no arena,
	# no rules object, so there is nothing of the simulation for it to write into.
	for banned in ["_bots", "apply_input", "set_meta", "queue_free", "_rng"]:
		_check(not source.contains(banned), "commentary.gd never touches %s" % banned)


# --- harness ------------------------------------------------------------------

func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  commentary: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  commentary: %d checks, %d failures" % [_checks, _failures])
		quit(1)
