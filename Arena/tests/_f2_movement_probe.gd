extends SceneTree
## F2 measurement probe (skipped by test-arena.sh: leading underscore).
##
## `audio_test.gd` proves MachineAudio's maths against doubles. This proves the WIRING,
## in a real fight, with real bots, because the whole reason there were no movement
## sounds is that `FightFx.set_motor_state()` was a correct implementation nobody ever
## called. A unit test would not have caught that and this does: it boots a real fight,
## finds the FX subtree the way the game builds it, and prints what the mixer is actually
## playing, tick by tick.
##
##   Godot --headless --path Arena --script tests/_f2_movement_probe.gd -- --secs=25
##   ... --drive=tracks --arena=drop_zone
##
## NO AUDIO IS PLAYED. Headless Godot has a dummy audio driver; every number below comes
## from the mixer's own bookkeeping and from AudioServer.

var fight: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var secs := 25
	var drive := ""
	var packed: PackedScene = load("res://fight/fight.tscn")
	fight = packed.instantiate()
	root.add_child(fight)
	await process_frame

	var cfg_text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
	var config: Dictionary = JSON.parse_string(cfg_text)
	config["debug"] = {"opponent_ai": "normal", "player_ai": "normal"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = int(a.substr(7))
		if a.begins_with("--arena="):
			config["arena"] = a.substr(8)
		if a.begins_with("--drive="):
			drive = a.substr(8)
	if drive != "":
		for i in range(2):
			(config["bots"][i] as Dictionary)["drive"] = drive
	var rules: Dictionary = config.get("rules", {})
	rules["duration_s"] = float(secs)
	config["rules"] = rules
	fight.start_fight(config)
	await process_frame

	var fx: Node = fight.get("_fx")
	if fx == null or not fx.has_method("machine_audio"):
		print("FAIL: no FX subtree, or it has no MachineAudio")
		quit(1)
		return
	var machines: MachineAudio = fx.call("machine_audio")
	var mix: AudioMix = fx.call("audio_mix")
	print("FX subtree: MachineAudio %s, AudioMix %s"
		% [str(machines != null), str(mix != null)])

	var thuds := 0
	var skid_frames := 0
	var scrape_frames := 0
	var reported := {}
	for t in range(secs * 60 + 400):
		await physics_frame
		if machines == null:
			continue
		if t == 180:
			print("\\nat 3 s: %d machines found, loops: %s"
				% [machines.machine_count(), str(machines.loop_keys())])
			print("Ambience bus %.2f dB, crowd loop %s, ambience voices %s"
				% [mix.ambience_db(), str(mix.has_loop("ambience")),
				str(mix.loop_sound("ambience"))])
		if t % 120 == 0 and t > 180:
			var line := "[%5.1f s]" % (float(t) / 60.0)
			for id in ["player-1", "ai-1"]:
				var st: Dictionary = machines.state_of(str(id))
				if st.is_empty():
					continue
				var key: String = "machine:whine:" + str(id)
				var p: Node = mix.loop_player(key)
				var pitch := float(p.get("pitch_scale")) if p != null else 0.0
				var db := float(p.get("volume_db")) if p != null else -99.0
				line += "  %s thr %.2f spd %.2f m/s whine %.2f @ %.1f dB skid %.2f scr %.2f" % [
					id, float(st.get("throttle", 0.0)), float(st.get("speed", 0.0)),
					pitch, db, float(st.get("skid_level", 0.0)),
					float(st.get("scrape_level", 0.0))]
			print(line)
		for id in ["player-1", "ai-1"]:
			var st: Dictionary = machines.state_of(str(id))
			if st.is_empty():
				continue
			if float(st.get("skid_level", 0.0)) > 0.05:
				skid_frames += 1
			if float(st.get("scrape_level", 0.0)) > 0.05:
				scrape_frames += 1
			var landed := float(st.get("land_at", -100.0))
			if landed > 0.0 and not reported.has(str(id) + str(landed)):
				reported[str(id) + str(landed)] = true
				thuds += 1
				print("  [%5.1f s] %s LANDED at %.2f m/s" % [float(t) / 60.0, id,
					float(st.get("last_land", 0.0))])
		if fight.get("state") == 3:
			break

	print("\\n--- f2 movement probe ---")
	print("thuds %d, skid frames %d, scrape frames %d" % [thuds, skid_frames, scrape_frames])
	print("mixer loops at the end: %s" % str(mix.loop_keys()))
	print("Ambience bus %.2f dB (duck %.2f)" % [mix.ambience_db(), mix.duck_db()])
	quit(0)
