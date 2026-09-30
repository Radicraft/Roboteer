extends SceneTree
## Headless test for the commentary and the endgame cues (agent G6, brief v4 §10 item 2;
## wave D, the commentary with a personality).
##   Godot --headless --path Arena --script tests/commentary_test.gd
## Exit code 0 = PASS.
##
## Nobody can hear anything in a headless run, so the audio half is checked NUMERICALLY and
## nothing is ever played out loud.
##
## What is checked:
##   1. the lines: every key the wave uses exists with lines; every template resolves; no
##      dash, no show words, no stray placeholder; every guard is one the code can set;
##   2. facts guard: a line never fires without its facts (a credited flip needs an
##      attacker, a part line needs a real part name, a spin line needs a spinner, a self
##      inflicted line needs nobody near), for every guarded line in the file;
##   3. variety: no immediate repeats, and a rare line stays rare;
##   4. the triggers from real fight facts: the seven wave G moments still speak, and the
##      wave D detections (first blood, part off, comeback, stall, self hazard, jam, wedge
##      under, spin lost, last ten, results, payoffs) fire when, and only when, true;
##   5. pacing: one line every ~2 s, big moments pre-empt filler, stale lines are dropped;
##   6. the ticker: every line fits one line of the ticker at 874 x 402 in sentence case AND
##      in capitals, with 18-character machine names; say_commentary shows at once, keeps
##      its case, holds its time; the wave G queue still behaves;
##   7. the endgame cues (unchanged from wave G);
##   8. presentation discipline: its own generator, no global random draw, no wall clock,
##      nothing written into the simulation. (The replay proof itself is determinism_test
##      and hazard_determinism_test, which the suite runs.)

const TICK := 1.0 / 60.0

## The keys other wave D agents call, and the ones this wave detects. Every one must exist.
const REQUIRED_KEYS := [
	"fight_start", "fight_stop", "count_start", "count_out", "lockup_tow", "fire_out",
	"marshal_wobble", "house_finish", "house_late_hit", "house_card", "verdict_clear",
	"verdict_close", "walkout_player", "walkout_opponent", "prediction",
	"big_hit", "part_off", "pinned", "flipped", "spinning_up", "in_the_zone",
	"house_bot_out", "pit_open", "endgame", "stage_hazards", "stage_wake", "stage_final",
	"payoff_spikes", "payoff_grinder", "payoff_fire", "payoff_crushed", "payoff_pit",
	"payoff_kill", "payoff_ring_out", "payoff_hazard", "knockout", "core_destroyed", "judges",
	"comeback", "stall", "hazard_self", "stuck", "weapon_jammed", "weapon_cooked",
	"first_blood", "last_ten", "wedge_under", "spin_lost", "self_right",
]
const MIN_LINES := 3
const PLACEHOLDERS := ["attacker", "victim", "part", "house_bot", "arena", "weapon", "seconds",
	"margin", "word"]
## Guard tokens the code sets (commentary.gd): plain flags, and key=value families.
const FLAGS := ["even", "favourite", "armour_edge", "record_edge", "same_weapon", "spin_vs_lift",
	"rematch", "house", "hazard", "self", "src_burn", "spin_weapon", "part_wheel", "part_armour",
	"part_top", "part_face", "after_hit", "player", "idle", "endgame", "apart", "inverted",
	"arena_other"]
const FAMILIES := ["wk", "arena", "attacker", "victim", "house_bot"]
## Brief v3 §3: none of the show's names, characters, words or branded terms.
const BANNED := ["robot wars", "battlebots", "robotica", "techno games", "roboteers",
	"activate", "cease", "refbot", "killalot", "matilda", "dead metal", "shunt", "sgt bash",
	"growler", "oblivion", "house robot", "flame pit", "floor flipper", "ready to rumble",
	"patrol zone", "cpz", "—", "–"]
## The longest facts a line can be filled with: an 18-character machine name (the builder's
## limit), the longest part and weapon names, the longest house bot and arena.
const LONG := {"attacker": "Thunderbucket Mk 2", "victim": "Wobblequeen Deluxe",
	"part": "middle right wheel", "house_bot": "THRESHER", "arena": "the Coliseum",
	"weapon": "horizontal spinner", "seconds": "12", "margin": "1.5", "word": "Side Jets Lit"}
## The phone the owner plays on, landscape, in pixels (3x), and its safe insets.
const PHONE_PX := Vector2i(2622, 1206)
const PHONE_SAFE := {"left": 186.0, "top": 0.0, "right": 186.0, "bottom": 63.0}
const DESIGN_SIZE := Vector2i(1206, 556)

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_lines()
	_test_guards()
	_test_variety()
	_test_triggers()
	_test_detections()
	_test_pacing()
	await _test_ticker_fit()
	await _test_hud()
	await _test_endgame_audio()
	_test_presentation_discipline()
	await _test_fight_unchanged()
	_finish()


# --- 1. the lines -------------------------------------------------------------

func _test_lines() -> void:
	var data := FightCommentary.data()
	var keys: Dictionary = data.get("keys", {}) as Dictionary
	_check(keys.size() >= REQUIRED_KEYS.size(), "commentary_lines.json loads (%d keys)" % keys.size())
	var total := 0
	var short: Array[String] = []
	for key in REQUIRED_KEYS:
		var lines: Array = (keys.get(key, {}) as Dictionary).get("lines", []) as Array
		if lines.size() < MIN_LINES:
			short.append("%s:%d" % [key, lines.size()])
	_check(short.is_empty(), "every key has at least %d lines (short: %s)" % [MIN_LINES, str(short)])
	var bad_placeholder: Array[String] = []
	var bad_guard: Array[String] = []
	var banned: Array[String] = []
	var unresolved: Array[String] = []
	for key in keys.keys():
		var meta: Dictionary = keys[key]
		for field in ["p", "cool", "life", "lines"]:
			if not meta.has(field):
				bad_guard.append("%s has no %s" % [key, field])
		for line_variant in (meta.get("lines", []) as Array):
			total += 1
			var entry := FightCommentary.entry_of(line_variant)
			var t := str(entry["t"])
			for field in FightCommentary.placeholders(t):
				if not field in PLACEHOLDERS:
					bad_placeholder.append("%s: {%s}" % [key, field])
			for token_variant in (entry.get("if", []) as Array):
				var tok := str(token_variant).trim_prefix("!")
				var eq := tok.find("=")
				var ok := (tok.substr(0, eq) in FAMILIES) if eq > 0 else (tok in FLAGS)
				if not ok:
					bad_guard.append("%s: %s" % [key, str(token_variant)])
			var low := t.to_lower()
			for word in BANNED:
				if low.contains(word):
					banned.append("%s: %s" % [key, t])
			var text := FightCommentary.render(t, _ctx_for(entry))
			if text.contains("{") or text.contains("}") or text.contains("  "):
				unresolved.append(text)
	_check(total >= 300, "a few hundred lines (%d)" % total)
	_check(bad_placeholder.is_empty(), "every placeholder is a known fact (%s)" % str(bad_placeholder))
	_check(bad_guard.is_empty(), "every guard is one the code sets (%s)" % str(bad_guard))
	_check(banned.is_empty(), "no show words, no dashes (%s)" % str(banned))
	_check(unresolved.is_empty(), "every template resolves cleanly (%s)" % str(unresolved.slice(0, 3)))
	# Sentence caps: every rendered line starts with a capital and so does each sentence.
	var lower_start: Array[String] = []
	for key in keys.keys():
		for line_variant in ((keys[key] as Dictionary).get("lines", []) as Array):
			var entry := FightCommentary.entry_of(line_variant)
			var text := FightCommentary.render(str(entry["t"]), _ctx_for(entry, {"attacker": "tinribs"}))
			if text.substr(0, 1) != text.substr(0, 1).to_upper():
				lower_start.append(text)
	_check(lower_start.is_empty(), "a line starting on a lower-case name is capitalised (%s)"
		% str(lower_start.slice(0, 2)))


## A context that satisfies this entry: every placeholder filled, every guard made true.
func _ctx_for(entry: Dictionary, base: Dictionary = {}) -> Dictionary:
	var ctx := LONG.duplicate()
	for k in base:
		ctx[k] = base[k]
	for token_variant in (entry.get("if", []) as Array):
		var tok := str(token_variant)
		if tok.begins_with("!"):
			continue
		var eq := tok.find("=")
		if eq > 0:
			ctx[tok.substr(0, eq)] = tok.substr(eq + 1)
			ctx[tok] = true
		else:
			ctx[tok] = true
	return ctx


# --- 2. facts guard -------------------------------------------------------------

func _test_guards() -> void:
	var keys: Dictionary = FightCommentary.data().get("keys", {}) as Dictionary
	# Every guarded line refuses a context that breaks any one of its guards, and every
	# line refuses a context missing any one of its facts.
	var leaks: Array[String] = []
	for key in keys.keys():
		for line_variant in ((keys[key] as Dictionary).get("lines", []) as Array):
			var entry := FightCommentary.entry_of(line_variant)
			var good := _ctx_for(entry)
			if not FightCommentary.fits(entry, good):
				leaks.append("never fits: " + str(entry["t"]))
				continue
			for token_variant in (entry.get("if", []) as Array):
				var bad := good.duplicate()
				var tok := str(token_variant)
				if tok.begins_with("!"):
					var t := tok.substr(1)
					bad[t] = true
					var eq := t.find("=")
					if eq > 0:
						bad[t.substr(0, eq)] = t.substr(eq + 1)
				else:
					bad.erase(tok)
					var eq2 := tok.find("=")
					if eq2 > 0:
						bad[tok.substr(0, eq2)] = "someone else"
				if FightCommentary.fits(entry, bad):
					leaks.append("%s fires without %s" % [str(entry["t"]), tok])
			for field in FightCommentary.placeholders(str(entry["t"])):
				var missing := good.duplicate()
				missing.erase(field)
				if FightCommentary.fits(entry, missing):
					leaks.append("%s fires without {%s}" % [str(entry["t"]), field])
	_check(leaks.is_empty(), "every line needs every one of its facts (%d leaks: %s)"
		% [leaks.size(), str(leaks.slice(0, 3))])

	# The classic failure, named: a flip nobody made is never credited, a credited flip
	# always names who did it.
	var c := _fresh("yard")
	for i in 40:
		var line := c.line_for("flipped", {"victim": "Tinribs", "self": true})
		_check_quiet(not line.contains("Scrapheap"), "self flip names nobody else")
		var credited := c.line_for("flipped", {"victim": "Tinribs", "attacker": "Scrapheap",
			"wk": "flipper", "wk=flipper": true})
		_check_quiet(not credited.contains("on its own") and not credited.contains("Nobody"),
			"a credited flip is never 'on its own' (%s)" % credited)
	_check(true, "40 self and 40 credited flips kept to their facts")
	# A part line with no real part name is not an event at all.
	var p := _fresh("yard")
	p.note_damage({"victim": "player-1", "attacker": "ai-1", "severity": 0.9,
		"detached": true, "part": "weapon"})
	_check(p.fired_count("part_off") == 0, "a 'detached' weapon (jams, never falls off) is not a part off")
	p.note_damage({"victim": "player-1", "attacker": "ai-1", "severity": 0.1,
		"detached": true, "part": "armour_front"})
	_check(p.fired_count("part_off") == 1 and _last(p).contains("front armour")
		or p.pending_key() == "part_off",
		"a front plate off names the front armour (%s)" % _last(p))
	_check(FightCommentary.render("{attacker}'s wedge", {"attacker": "Tinribs"}) == "Tinribs' wedge"
		and FightCommentary.render("{attacker}'s wedge", {"attacker": "Clatterbox"}) == "Clatterbox's wedge",
		"possessives: Tinribs', Clatterbox's")
	_check(FightCommentary.part_name("wheel_rl") == "rear left wheel"
		and FightCommentary.part_name("wheel_mr") == "middle right wheel"
		and FightCommentary.part_name("track_l") == "left track"
		and FightCommentary.part_name("core") == "", "part names read true")
	# Spinning up is for things that spin: never a flamethrower, a flipper or an axe.
	for kind in ["flame", "flipper", "axe", "crusher"]:
		var s := _fresh("yard", {"kinds": [kind, kind]})
		s.step(TICK, _fighting({"readiness": [1.0, 1.0], "spinning": [true, true]}))
		_check(s.fired_count("spinning_up") == 0, "a %s at full readiness never 'spins up'" % kind)
	var sp := _fresh("yard", {"kinds": ["spinner", "flipper"]})
	sp.step(TICK, _fighting({"readiness": [1.0, 1.0]}))
	_check(sp.fired_count("spinning_up") == 1, "a spinner at full speed does")


# --- 3. variety -------------------------------------------------------------------

func _test_variety() -> void:
	var c := _fresh("yard")
	var ctx := {"attacker": "Tinribs", "victim": "Scrapheap", "weapon": "flipper"}
	var last := ""
	var repeats := 0
	var seen := {}
	for i in 60:
		c.step(5.0, {"state": "fighting"})           # past the cooldown and the gap
		var line := c.call_event("big_hit", ctx)
		if line == last:
			repeats += 1
		seen[line] = true
		last = line
	_check(repeats == 0, "no immediate repeats in 60 big hits")
	_check(seen.size() >= 8, "and plenty of variety (%d different)" % seen.size())
	# A line said recently is not said again while others fit (14-line memory).
	var window := c.said().slice(-10)
	var texts := {}
	for s in window:
		texts[str((s as Dictionary)["text"])] = true
	_check(texts.size() == window.size(), "no repeat inside the last 10 lines")

	# Weighting: the w=5 stall line with {seconds} against the w=10 lines.
	var r := _fresh("yard")
	var rare := 0
	var common := {}
	var sctx := {"attacker": "A", "victim": "B", "seconds": "9"}
	for i in 3000:
		var line := r.line_for("stall", sctx)
		if line.contains("seconds without a touch"):
			rare += 1
		else:
			common[line] = int(common.get(line, 0)) + 1
	var mean := 0.0
	for k in common:
		mean += float(common[k])
	mean /= maxf(float(common.size()), 1.0)
	_check(float(rare) < mean * 0.8, "a rare line stays rare (%d vs %.0f a common line)" % [rare, mean])


# --- 4. the triggers ------------------------------------------------------------

func _test_triggers() -> void:
	var c := _fresh("drop_zone", {"house_bot": "THRESHER"})
	c.step(1.0, {"state": "countdown", "inverted": [true, false]})
	_check(c.fired_count("flipped") == 0, "nothing is detected during the countdown")
	_check(c.fired_count("prediction") == 1, "but the prediction is made as the countdown starts")
	c.step(TICK, _fighting())
	_check(c.fired_count("fight_start") == 1, "the bell says fight_start")
	# The seven wave G moments.
	c.note_damage({"victim": "ai-1", "attacker": "player-1", "severity": 0.05})
	_check(c.fired_count("first_blood") == 1, "the first real blow is first blood")
	c.step(6.0, _fighting())
	c.note_damage({"victim": "ai-1", "attacker": "player-1", "severity": FightCommentary.BIG_HIT_SEVERITY - 0.05})
	_check(c.fired_count("big_hit") == 0, "a light hit says nothing")
	c.note_damage({"victim": "ai-1", "attacker": "player-1", "severity": FightCommentary.BIG_HIT_SEVERITY})
	_check(c.fired_count("big_hit") == 1, "a heavy hit is a big hit")
	c.note_damage({"victim": "ai-1", "attacker": "player-1", "severity": 0.9})
	_check(c.fired_count("big_hit") == 1, "a second inside the cooldown is not")
	c.note_pin(1, true)
	c.step(TICK, _fighting())
	c.step(FightCommentary.PIN_HOLD_S * 0.5, _fighting())
	_check(c.fired_count("pinned") == 0, "a momentary pin says nothing")
	c.step(FightCommentary.PIN_HOLD_S * 0.6, _fighting())
	_check(c.fired_count("pinned") == 1, "a pin that holds is pinned")
	c.note_pin(1, false)
	c.step(0.1, _fighting({"inverted": [true, false], "touch_age": [0.2, 0.2]}))
	c.step(0.1, _fighting({"inverted": [false, false], "touch_age": [0.2, 0.2]}))
	_check(c.fired_count("flipped") == 0, "rolled over and straight back is not a flip")
	c.step(0.1, _fighting({"inverted": [true, false], "touch_age": [0.2, 0.2]}))
	c.step(FightCommentary.FLIP_HOLD_S + 0.05, _fighting({"inverted": [true, false], "touch_age": [0.2, 0.2]}))
	_check(c.fired_count("flipped") == 1, "a machine that stays upside down is flipped")
	c.step(0.1, _fighting({"inverted": [true, false], "touch_age": [0.2, 0.2]}))
	_check(c.fired_count("flipped") == 1, "and it is said once, not every frame")
	c.step(0.6, _fighting({"inverted": [false, false]}))
	_check(c.fired_count("self_right") == 1, "back upright is self_right")
	c.note_zone(true, "THRESHER")
	_check(c.fired_count("in_the_zone") == 1, "entering the corner is in_the_zone")
	c.note_zone(true, "THRESHER")
	_check(c.fired_count("in_the_zone") == 1, "staying in it is not")
	c.note_house_bot_out()
	_check(c.fired_count("house_bot_out") == 1, "the release is house_bot_out")
	c.note_house_bot_out()
	_check(c.fired_count("house_bot_out") == 1, "once a fight")
	c.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(c.fired_count("pit_open") == 1 and c.endgame_fired(), "the Trapdoor endgame is pit_open")
	var yard := _fresh("yard")
	yard.on_phase_changed(FightTypes.PHASE_OPEN)
	_check(yard.fired().is_empty(), "the open phase says nothing")
	yard.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(yard.fired_count("pit_open") == 0 and yard.fired_count("endgame") == 1,
		"an arena with no pit says endgame, not pit_open")
	c.reset("yard", 2)
	_check(c.said().is_empty() and c.fired().is_empty() and not c.endgame_fired(),
		"reset forgets the last fight")


func _test_detections() -> void:
	# Comeback: 25 % behind on condition, then level.
	var c := _fresh("yard")
	c.step(TICK, _fighting({"condition": [0.6, 0.85]}))
	c.step(TICK, _fighting({"condition": [0.6, 0.7]}))
	_check(c.fired_count("comeback") == 0, "closing the gap is not yet a comeback")
	c.step(TICK, _fighting({"condition": [0.6, 0.6]}))
	_check(c.fired_count("comeback") == 1, "drawing level from 25 % behind is a comeback")
	# A 10 % swing is not.
	var d := _fresh("yard")
	d.step(TICK, _fighting({"condition": [0.8, 0.9]}))
	d.step(TICK, _fighting({"condition": [0.8, 0.8]}))
	_check(d.fired_count("comeback") == 0, "a 10 % gap closed is not a comeback")

	# Stall: 8 s with no contact and no blow; contact resets it.
	var s := _fresh("yard")
	s.step(TICK, {"state": "countdown"})
	s.step(TICK, _fighting({"touch_age": [9.0, 9.0], "distance": 5.0}))
	for i in 7 * 60:
		s.step(TICK, _fighting({"touch_age": [9.0, 9.0], "distance": 5.0}))
	_check(s.fired_count("stall") == 0, "seven quiet seconds are silence, and silence is fine")
	for i in 90:
		s.step(TICK, _fighting({"touch_age": [9.0, 9.0], "distance": 5.0}))
	_check(s.fired_count("stall") == 1, "eight quiet seconds draw a jibe")
	var busy := _fresh("yard")
	busy.step(TICK, {"state": "countdown"})
	for i in 12 * 60:
		busy.step(TICK, _fighting({"touch_age": [0.1, 0.1], "distance": 0.8}))
	_check(busy.fired_count("stall") == 0, "machines in contact are never a stall")

	# Self-inflicted hazard: arena damage, nobody near for 3 s.
	var h := _fresh("yard")
	h.step(TICK, _fighting({"touch_age": [5.0, 5.0]}))
	h.note_damage({"victim": "player-1", "attacker": "arena", "severity": 0.05})
	_check(h.fired_count("hazard_self") == 1, "driving into a hazard alone is self-inflicted")
	var pushed := _fresh("yard")
	pushed.step(TICK, _fighting({"touch_age": [1.0, 1.0]}))
	pushed.note_damage({"victim": "player-1", "attacker": "arena", "severity": 0.05})
	_check(pushed.fired_count("hazard_self") == 0, "a machine touched a second ago was not alone")

	# Self flip vs credited flip.
	var f := _fresh("yard", {"kinds": ["flipper", "flipper"]})
	f.step(TICK, _fighting({"inverted": [false, true], "touch_age": [9.0, 9.0]}))
	f.step(FightCommentary.FLIP_HOLD_S + 0.05, _fighting({"inverted": [false, true], "touch_age": [9.0, 9.0]}))
	_check(f.fired_count("flipped") == 1 and (_last(f).contains("Scrapheap")),
		"an unassisted flip is about the machine that went over (%s)" % _last(f))
	_check(not _last(f).contains("Tinribs"), "and credits nobody")

	# Weapon jammed, once per machine; cooked is its own line.
	var j := _fresh("yard", {"kinds": ["axe", "axe"], "weapons": ["Axe", "Axe"]})
	j.step(TICK, _fighting({"fault": ["", ""]}))
	j.step(TICK, _fighting({"fault": ["jammed", ""]}))
	j.step(TICK, _fighting({"fault": ["jammed", ""]}))
	_check(j.fired_count("weapon_jammed") == 1, "a jammed weapon is said once")
	j.step(3.0, _fighting({"fault": ["jammed", "cooked"]}))
	_check(j.fired_count("weapon_cooked") == 1, "a cooked one is weapon_cooked")

	# Spin lost: armed then below the AI's spun-down line.
	var sl := _fresh("yard", {"kinds": ["spinner", "wedge"]})
	sl.step(TICK, _fighting({"readiness": [1.0, 0.0]}))
	sl.step(TICK, _fighting({"readiness": [FightCommentary.SPIN_REARM - 0.01, 0.0]}))
	_check(sl.fired_count("spin_lost") == 1, "a spinner losing its speed is spin_lost")

	# Wedge under: a wedge in contact, the other machine lifted and upright.
	var w := _fresh("yard", {"chassis": ["wedge", "box"]})
	w.step(TICK, _fighting({"lifted": [0.0, 0.1], "touch_age": [0.0, 0.0], "inverted": [false, false]}))
	_check(w.fired_count("wedge_under") == 1, "a wedge with the other machine on its ramp")
	var w2 := _fresh("yard", {"chassis": ["box", "box"]})
	w2.step(TICK, _fighting({"lifted": [0.0, 0.1], "touch_age": [0.0, 0.0]}))
	_check(w2.fired_count("wedge_under") == 0, "not without a wedge")

	# Last ten seconds, once.
	var t := _fresh("yard")
	t.step(TICK, _fighting({"time_left": 10.5}))
	t.step(TICK, _fighting({"time_left": 9.9}))
	t.step(TICK, _fighting({"time_left": 9.8}))
	_check(t.fired_count("last_ten") == 1, "ten seconds left, once")

	# Results and verdicts.
	var r := _fresh("yard")
	r.note_result("judges", 0, 1, 1.0)
	_check(r.fired_count("judges") == 1 and r.fired_count("verdict_close") == 1,
		"a 1-point decision is close")
	var r2 := _fresh("yard")
	r2.note_result("judges", 1, 0, 6.0)
	_check(r2.fired_count("verdict_clear") == 1, "a 6-point decision is clear")
	r2.call_event("verdict_close", {"winner": "Scrapheap", "loser": "Tinribs"})
	_check(r2.fired_count("verdict_close") == 0, "one verdict a fight, whoever calls it")
	var k := _fresh("yard")
	k.step(TICK, _fighting({"inverted": [false, true], "touch_age": [0.1, 0.1]}))
	k.note_result("ko", 0, 1)
	_check(k.fired_count("knockout") == 1, "a knockout")
	k.call_event("count_out", {"victim": "Scrapheap"})
	_check(k.fired_count("count_out") == 0, "and the Marshal's count_out does not say it twice")
	var core := _fresh("yard")
	core.note_damage({"victim": "ai-1", "attacker": "ai-1", "severity": 0.2, "part": "core", "source": "heat"})
	core.note_result("component_kill", 0, 1)
	_check(core.fired_count("core_destroyed") == 1, "a component kill")
	for i in 20:
		var line := core.line_for("core_destroyed", {"attacker": "Tinribs", "victim": "Scrapheap", "self": true})
		_check_quiet(not line.contains("found the heart"), "a self-cooked core is not credited")

	# Payoffs: credited and self.
	var p := _fresh("drop_zone")
	p.note_payoff({"kind": "pit", "by": "", "victim": "ai-1"})
	_check(p.fired_count("payoff_pit") == 1 and not _last(p).contains("Tinribs"),
		"a machine that drove into the pit alone is not pushed by anyone (%s)" % _last(p))
	var p2 := _fresh("yard")
	p2.note_payoff({"kind": "spikes", "by": "player-1", "victim": "ai-1"})
	_check(p2.fired_count("payoff_spikes") == 1, "onto the spikes")
	for kind in ["grinder", "flame", "ram", "kill", "ring_out", "turntable"]:
		var pk := _fresh("yard")
		pk.note_payoff({"kind": kind, "by": "player-1", "victim": "ai-1"})
		_check_quiet(pk.fired().size() == 1, "payoff %s has a line" % kind)
	_check(true, "every payoff kind has a line")

	# Stages, with the arena's own words.
	for arena in FightCommentary.KNOWN_ARENAS:
		var st := _fresh(arena)
		st.note_stage(1, "HAZARDS UP")
		st.step(5.0, {"state": "result"})
		st.note_stage(2, "WAKE")
		st.step(5.0, {"state": "result"})
		st.note_stage(4, "FINAL")
		_check_quiet(st.fired().size() == 3, "%s has all three stage lines (%s)" % [arena, str(st.fired())])
	_check(true, "every arena has a line for every stage")

	# The other agents' keys all answer with the facts they will send.
	var o := _fresh("yard")
	var calls := {
		"fight_stop": {}, "count_start": {"victim": "Tinribs"},
		"lockup_tow": {"attacker": "Tinribs", "victim": "Scrapheap"},
		"fire_out": {"victim": "Tinribs"}, "marshal_wobble": {},
		"house_finish": {"house_bot": "GRUDGE", "victim": "Scrapheap"},
		"house_late_hit": {"house_bot": "GRUDGE", "victim": "Scrapheap"},
		"house_card": {"house_bot": "GRUDGE"},
		"walkout_player": {"machine": "Tinribs", "weapon": "Flipper"},
		"walkout_opponent": {"machine": "Scrapheap", "weapon": "Flipper"},
	}
	for key in calls:
		o.step(10.0, {"state": "result"})
		_check_quiet(o.call_event(key, calls[key]) != "", "%s answers" % key)
	_check(true, "every key the Marshal, walk-out and house bot agents call answers")


# --- 5. pacing -------------------------------------------------------------------

func _test_pacing() -> void:
	var c := _fresh("yard")
	c.step(TICK, _fighting())
	# A burst: five things inside half a second. One shows, the biggest waits, the rest go.
	c.call_event("spinning_up", {"attacker": "Tinribs", "weapon": "spinner", "spin_weapon": true})
	c.step(0.1, _fighting())
	c.call_event("pinned", {"attacker": "Tinribs", "victim": "Scrapheap"})
	c.step(0.1, _fighting())
	c.call_event("lockup_tow", {"attacker": "Tinribs", "victim": "Scrapheap"})
	_check(c.said().size() == 1, "a burst puts one line up, not three (%d)" % c.said().size())
	# A big moment takes the ticker from filler once the filler has been read for a moment.
	c.step(0.7, _fighting())
	c.call_event("flipped", {"victim": "Scrapheap", "attacker": "Tinribs"})
	_check(c.said().size() == 2 and str((c.said()[1] as Dictionary)["key"]) == "flipped",
		"a flip pre-empts filler (%s)" % str(c.said().map(func(s): return s["key"])))
	# Everything that happens is spaced: over a busy minute, lines are 2 s apart except a
	# payoff or result taking over.
	var b := _fresh("yard", {"kinds": ["spinner", "spinner"]})
	b.step(TICK, {"state": "countdown"})
	var t := 0.0
	var i := 0
	while t < 60.0:
		b.step(0.1, _fighting({"touch_age": [0.1, 0.1]}))
		t += 0.1
		i += 1
		if i % 3 == 0:
			b.call_event("big_hit", {"attacker": "Tinribs", "victim": "Scrapheap"})
		if i % 7 == 0:
			b.call_event("pinned", {"attacker": "Scrapheap", "victim": "Tinribs"})
		if i % 11 == 0:
			b.call_event("lockup_tow", {"attacker": "Tinribs", "victim": "Scrapheap"})
	var tight := 0
	var said := b.said()
	for n in range(1, said.size()):
		var gap := float((said[n] as Dictionary)["at"]) - float((said[n - 1] as Dictionary)["at"])
		if gap < FightCommentary.MIN_GAP_S - 0.001:
			tight += 1
	_check(tight == 0, "a busy minute keeps a 2 s gap between lines (%d tight, %d lines)" % [tight, said.size()])
	_check(said.size() <= 31, "and says at most one line every 2 s (%d)" % said.size())
	# A waiting line that is no longer true is dropped: a flip line waits behind a payoff,
	# the machine rights itself, and the line never goes up.
	var tr := _fresh("yard")
	tr.step(TICK, _fighting())
	tr.call_event("payoff_spikes", {"attacker": "Tinribs", "victim": "Scrapheap"})
	tr.step(0.1, _fighting({"inverted": [false, true], "touch_age": [0.1, 0.1]}))
	tr.step(FightCommentary.FLIP_HOLD_S + 0.05, _fighting({"inverted": [false, true], "touch_age": [0.1, 0.1]}))
	_check(tr.fired_count("flipped") == 1 and tr.pending_key() == "flipped", "a flip behind a payoff waits")
	tr.step(0.5, _fighting({"inverted": [false, false], "touch_age": [0.1, 0.1]}))
	tr.step(2.0, _fighting({"inverted": [false, false], "touch_age": [0.1, 0.1]}))
	_check(tr.said_count("flipped") == 0, "and is dropped once the machine is back on its wheels")
	# A waiting line older than its life is dropped, not shown late.
	var s := _fresh("yard")
	s.step(TICK, _fighting())
	s.call_event("fight_stop", {})                   # p3, holds the ticker
	s.step(0.2, {"state": "result"})
	s.call_event("marshal_wobble", {})               # p0, waits, life 1.5 s
	s.step(1.0, {"state": "result"})
	s.step(1.0, {"state": "result"})
	s.step(1.0, {"state": "result"})
	_check(s.said_count("marshal_wobble") == 0, "a stale line is dropped, not shown late")


# --- 6. the ticker -----------------------------------------------------------------

func _test_ticker_fit() -> void:
	var hud_scene: PackedScene = load("res://ui/hud.tscn")
	var hud: FightHud = hud_scene.instantiate() as FightHud
	var host := SubViewport.new()
	host.size = PHONE_PX
	root.add_child(host)
	host.add_child(hud)
	await _frames(1)
	hud.set_safe_area(PHONE_SAFE)
	await _frames(1)
	var keys: Dictionary = FightCommentary.data().get("keys", {}) as Dictionary
	var over: Array[String] = []
	var widest := 0.0
	var room := 0.0
	var widest_line := ""
	for key in keys.keys():
		for line_variant in ((keys[key] as Dictionary).get("lines", []) as Array):
			var entry := FightCommentary.entry_of(line_variant)
			var text := FightCommentary.render(str(entry["t"]), _ctx_for(entry))
			for variant in [text, text.to_upper()]:
				var fit := hud.commentary_fit(variant)
				room = fit.y
				if fit.x > widest:
					widest = fit.x
					widest_line = variant
				if fit.x > fit.y:
					over.append(variant)
	_check(room > 100.0, "the ticker has room at 874 x 402 (%.0f px)" % room)
	# The ticker and the word DRIVE under the stick both read, on both phones.
	for phone in [[PHONE_PX, PHONE_SAFE, "874 x 402"],
			[Vector2i(2868, 1320), {"left": 186.0, "top": 0.0, "right": 186.0, "bottom": 63.0}, "956 x 440"]]:
		host.size = phone[0]
		hud.set_safe_area(phone[1])
		var controls: Node = (load("res://ui/controls.tscn") as PackedScene).instantiate()
		host.add_child(controls)
		await _frames(2)
		controls.call("set_safe_area", phone[1])
		await _frames(1)
		var label: Rect2 = controls.call("drive_label_rect")
		var strip: Rect2 = hud.ticker_rect()
		_check(label.size.x > 0.0 and not label.intersects(strip)
			and label.end.y <= float(phone[0].y) - float(phone[1]["bottom"]),
			"DRIVE (%s) clears the ticker %s at %s" % [str(label), str(strip), phone[2]])
		controls.queue_free()
		await _frames(1)
	_check(over.is_empty(), "every line fits one ticker line at 874 x 402, sentence case and capitals, with 18-character names (%d over; widest %.0f of %.0f px: %s)"
		% [over.size(), widest, room, widest_line])
	print("  widest line: %.0f of %.0f px (%.0f %%): %s" % [widest, room, 100.0 * widest / maxf(room, 1.0), widest_line])
	host.queue_free()


func _test_hud() -> void:
	var hud_scene: PackedScene = load("res://ui/hud.tscn")
	var hud: FightHud = hud_scene.instantiate() as FightHud
	var host := SubViewport.new()
	host.size = DESIGN_SIZE
	root.add_child(host)
	host.add_child(hud)
	await _frames(1)
	hud.clear_commentary()

	# Countdown: dropped, except the prediction.
	hud.set_coach_phase(FightHud.COACH_COUNTDOWN)
	_check(not hud.say_commentary("Big hit on Tinribs!", 2.0), "a line is not said over the countdown")
	_check(hud.say_commentary("My money's on Tinribs.", 2.5, true) and hud.commentary_text() == "My money's on Tinribs.",
		"the prediction is, in sentence case")
	hud.set_coach_phase(FightHud.COACH_FIGHTING)
	hud.clear_commentary()
	hud.say_commentary("What a hit from Tinribs!", 2.6)
	hud.commentary_step(TICK)
	_check(hud.commentary_text() == "What a hit from Tinribs!", "a personality line keeps its case")
	hud.commentary_step(2.5)
	_check(is_equal_approx(hud.commentary_alpha(), 1.0), "and holds its own time (2.6 s)")
	hud.commentary_step(0.2 + FightHud.COMMENTARY_FADE_S)
	_check(not hud.commentary_visible(), "then fades")
	var line: Label = hud.get_node_or_null("Root/Commentary") as Label
	var strip: Rect2 = hud.ticker_rect()
	_check(line != null and line.global_position.y >= strip.position.y - 0.5
		and line.global_position.y + line.size.y <= strip.position.y + strip.size.y + 0.5,
		"inside the ticker strip %s" % str(strip))

	# The wave G queue, unchanged: capitals, one every 2 s, stale dropped.
	hud.clear_commentary()
	hud.push_commentary("first")
	hud.push_commentary("second")
	hud.push_commentary("third")
	hud.commentary_step(TICK)
	_check(hud.commentary_text() == "FIRST" and hud.commentary_queued() == 2, "the old queue still queues")
	hud.commentary_step(FightHud.COMMENTARY_GAP_S)
	_check(hud.commentary_text() == "SECOND" and hud.commentary_queued() == 0, "and drops the stale third")

	# The whole chain, commentary -> HUD, and the house bot named under the opponent.
	hud.clear_commentary()
	var c := _fresh("drop_zone", {"house_bot": "THRESHER"})
	c.bind(hud, null)
	c.step(TICK, _fighting())
	c.note_house_bot_out()
	hud.commentary_step(TICK)
	_check(hud.commentary_text().contains("THRESHER"), "a rules event reaches the ticker, naming the house bot (%s)" % hud.commentary_text())
	_check(hud.house_bot_out() and hud.house_bot_name() == "THRESHER", "and the HUD names it under the opponent")
	c.reset("drop_zone", 2)
	hud.commentary_step(TICK)
	_check(hud.commentary_text() == "", "a new fight starts with a clear ticker")
	host.queue_free()


# --- 7. the endgame cues ------------------------------------------------------

func _test_endgame_audio() -> void:
	var mix := AudioMix.new()
	root.add_child(mix)
	await _frames(1)
	_check(mix.missing_sounds().is_empty(), "every sound loaded (%s)" % str(mix.missing_sounds()))
	var ambience_bus := AudioServer.get_bus_index(AudioMix.BUS_AMBIENCE)
	var before := AudioServer.get_bus_volume_db(ambience_bus)
	var c := FightCommentary.new()
	c.bind(null, mix)
	c.reset("yard", 2)
	_check(mix.active_count("endgame_horn") == 0 and not mix.has_loop(AudioMix.ENDGAME_LOOP_KEY),
		"no horn and no music before the endgame")
	c.on_phase_changed(FightTypes.PHASE_OPEN)
	_check(mix.active_count("endgame_horn") == 0, "the open phase does not blow the horn")
	c.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(mix.active_count("endgame_horn") == 1, "the endgame starts the horn")
	_check(mix.has_loop(AudioMix.ENDGAME_LOOP_KEY), "and the drone on the Music bus")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(ambience_bus), before + AudioMix.AMBIENCE_HOT_DB),
		"the crowd is %.0f dB hotter" % AudioMix.AMBIENCE_HOT_DB)
	c.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(mix.active_count("endgame_horn") == 1, "the round only turns once")
	mix.stop_all()
	_check(is_equal_approx(AudioServer.get_bus_volume_db(ambience_bus), before),
		"stop_all puts the Ambience bus back")
	var bare := _fresh("drop_zone")
	bare.on_phase_changed(FightTypes.PHASE_ENDGAME)
	_check(bare.fired_count("pit_open") == 1, "with no audio director the lines still work")
	mix.queue_free()


# --- 8. presentation discipline -------------------------------------------------

func _test_presentation_discipline() -> void:
	var source := FileAccess.get_file_as_string("res://fight/commentary.gd")
	_check(not source.is_empty(), "commentary.gd reads back")
	for banned in ["randf(", "randi(", "randf_range(", "randi_range(", "RandomNumberGenerator.new",
			"seed(", "Time.get_ticks", "Time.get_unix_time", "OS.get_"]:
		_check(not source.contains(banned),
			"commentary.gd never calls %s (it would move the fight's sequence)" % banned)
	for banned in ["_bots", "apply_input", "set_meta", "queue_free", "_rng", "apply_central"]:
		_check(not source.contains(banned), "commentary.gd never touches %s" % banned)
	# The same seed says the same lines: a replay reads like the fight it replays.
	var a := _fresh("yard", {"seed": 42})
	var b := _fresh("yard", {"seed": 42})
	var same := true
	for i in 20:
		a.step(5.0, {"state": "fighting"})
		b.step(5.0, {"state": "fighting"})
		if a.call_event("big_hit", {"attacker": "A", "victim": "B"}) != b.call_event("big_hit", {"attacker": "A", "victim": "B"}):
			same = false
	_check(same, "the same seed says the same lines")


# --- 9. the fight does not hear the commentary ---------------------------------

## The same real fight twice: once with the commentary talking (it says lines all through
## it), once with no commentary object at all (`debug.commentary: "off"`). Every machine's
## position, rotation and condition every second, the result and its tick must match.
func _test_fight_unchanged() -> void:
	var talking := await _fight_trace(false)
	var silent := await _fight_trace(true)
	_check(int(talking["lines"]) >= 5, "the talking fight really talked (%d lines)" % int(talking["lines"]))
	_check(int(silent["lines"]) == 0, "the silent fight built no commentary")
	_check(str(talking["trace"]) != "" and talking["trace"] == silent["trace"],
		"the fight is the same tick for tick with and without the commentary (%d samples, %s)"
		% [(talking["trace"] as Array).size(), str(talking["hash"])])
	_check(talking["result"] == silent["result"], "and ends the same way (%s)" % str(talking["result"]))
	var t1: Array = talking["trace"]
	var t2: Array = silent["trace"]
	for i in mini(t1.size(), t2.size()):
		if str(t1[i]) != str(t2[i]):
			print("  DIVERGE ", t1[i], "\n          ", t2[i])
			break


func _fight_trace(silent: bool) -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json"))
	config["seed"] = 4242
	config["arena"] = "yard"
	config["rules"] = {"mode": "fight", "duration_s": 45, "ko_count_s": 10, "endgame_at_s": 20,
		"enforcer": "thresher", "enforcer_mode": "zone", "enforcer_speed": 1.0}
	config["debug"] = {"opponent_ai": "normal", "player_ai": "normal"}
	if silent:
		config["debug"]["commentary"] = "off"
	var fight: Node = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	fight.call("start_fight", config)
	await process_frame
	var trace: Array = []
	var last_tick := -1
	var frames := 0
	while frames < 60 * 60 * 4 and int(fight.get("state")) != 3:
		await physics_frame
		frames += 1
		var tick := int(fight.get("_tick"))
		# Tick 0 lasts the whole countdown (the machines settle while the clock waits), so
		# the first sample is a second in: a sample is always a fight tick, never a frame.
		if tick == last_tick or tick % 60 != 0 or tick == 0:
			continue
		last_tick = tick
		var row: Array = [tick]
		for bot in (fight.get("_bots") as Array):
			var ch: Node3D = (bot as Node).get("chassis")
			row.append(str(ch.global_transform.origin.snapped(Vector3.ONE * 1e-4)))
			row.append(str(ch.global_transform.basis.get_euler().snapped(Vector3.ONE * 1e-4)))
			row.append(str(FightRules.condition_total((bot as Node).call("condition") as Dictionary)))
		trace.append(row)
	var comm: Variant = fight.call("commentary")
	var lines := (comm as FightCommentary).said().size() if comm != null else 0
	var result := [int(fight.get("_tick")), str(fight.get("_hud_banner")), str(fight.get("_hud_winner"))]
	root.remove_child(fight)
	fight.queue_free()
	await process_frame
	return {"trace": trace, "hash": str(str(trace).hash()), "result": result, "lines": lines}


# --- harness ------------------------------------------------------------------

func _fresh(arena: String, extra: Dictionary = {}) -> FightCommentary:
	var c := FightCommentary.new()
	c.reset(arena, 2)
	var info := {"names": ["Tinribs", "Scrapheap"], "ids": ["player-1", "ai-1"],
		"weapons": ["Flipper", "Horizontal spinner"], "kinds": ["flipper", "spinner"],
		"chassis": ["wedge", "box"], "armour": [10.0, 10.0], "house_bot": "",
		"seed": 7, "player_index": 0}
	for k in extra:
		info[k] = extra[k]
	c.setup(info)
	return c


func _fighting(extra: Dictionary = {}) -> Dictionary:
	var facts := {"state": "fighting", "inverted": [false, false], "readiness": [0.0, 0.0],
		"touch_age": [0.5, 0.5]}
	for key in extra:
		facts[key] = extra[key]
	return facts


func _last(c: FightCommentary) -> String:
	var s := c.said()
	return str((s[s.size() - 1] as Dictionary)["text"]) if not s.is_empty() else ""


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


## A check inside a loop: counted, printed only when it fails.
func _check_quiet(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
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
