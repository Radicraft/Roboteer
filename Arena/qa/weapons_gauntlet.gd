extends SceneTree
## QA (weapons gauntlet, 2026-09-25): every weapon in the catalogue, fitted to a legal
## machine and driven by the AI, fights real fights against a plain opponent and against
## other weapons. One JSON line per fight goes to `--out=`. Not a test: nothing here
## passes or fails, the numbers are read by docs/qa/weapons-gauntlet.md.
##
##   Godot --headless --fixed-fps 60 --path Arena --script qa/weapons_gauntlet.gd -- \
##       --weapons=flipper,axe --seeds=11,22,33 --secs=150 --out=/tmp/g.jsonl
##
## `--fixed-fps 60` matters: without it headless Godot steps physics in real time.
## The subject is always bots[0] ("player-1") with `debug.player_ai` normal, so the
## player side is an AI that attacks; the opponent is bots[1] with the ordinary AI.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const STATE_RESULT := 3

const ALL := ["horizontal_spinner", "vertical_spinner", "flipper", "lifter", "crusher",
	"axe", "saw", "ram", "flamethrower", "full_body_spinner", "shock_prod", "tesla_arc",
	"drill_lance", "twin_saw", "napalm_cannon", "vortex_spinner"]

## The hull each weapon is tried on first; the rest are fallbacks if it will not fit.
const HULLS := {
	"horizontal_spinner": ["box", "wedge"],
	"vertical_spinner": ["wedge", "box"],
	"flipper": ["wedge", "box"],
	"lifter": ["wedge", "box"],
	"crusher": ["box", "wedge"],
	"axe": ["box", "wedge"],
	"saw": ["box", "wedge"],
	"ram": ["wedge", "box"],
	"flamethrower": ["box", "wedge"],
	"full_body_spinner": ["shell"],
	"shock_prod": ["wedge", "box"],
	"tesla_arc": ["box", "wedge"],
	"drill_lance": ["box", "wedge"],
	"twin_saw": ["wedge", "box"],
	"napalm_cannon": ["box", "wedge"],
	"vortex_spinner": ["shell", "apex"],
}
const DRIVES := ["4wd", "2wd", "6wd"]
const ARMOURS := [["steel", 2], ["steel", 1], ["hdpe", 2], ["hdpe", 1], ["polycarbonate", 1]]

## Above this the foe counts as thrown.
const AIR_M := 0.45
## Damage events closer together than this are one blow.
const BLOW_GAP_S := 0.25
## A fire counts as landing if the subject damages the foe inside this window.
const LAND_WINDOW_S := 0.6

var _out_path := ""
var _weapon_list: Array = []
var _seeds: Array = [11, 22, 33]
var _secs := 150
var _opps: Array = ["plain", "weapon"]
## `--trace=N`: print one line of state every N ticks (a repro aid).
var _trace := 0
## `--hull=` / `--drive=`: force the subject's hull or drive (a repro aid).
var _hull := ""
var _drive := ""
## `--subject-skill=`: the subject's AI tier (default national, one tier above the
## opponent's regional, so the subject attacks). `regional` is the even-tier run:
## there 50 % is par, so a win rate reads as the weapon's own strength.
var _subject_skill := "national"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weapons="):
			_weapon_list = Array(a.substr(10).split(","))
		elif a.begins_with("--seeds="):
			_seeds = []
			for s in a.substr(8).split(","):
				_seeds.append(int(s))
		elif a.begins_with("--secs="):
			_secs = int(a.substr(7))
		elif a.begins_with("--out="):
			_out_path = a.substr(6)
		elif a.begins_with("--hull="):
			_hull = a.substr(7)
		elif a.begins_with("--drive="):
			_drive = a.substr(8)
		elif a.begins_with("--trace="):
			_trace = int(a.substr(8))
		elif a.begins_with("--subject-skill="):
			_subject_skill = a.substr(16)
		elif a.begins_with("--tune="):
			# `--tune=weapon.key=value;weapon.key=value`: patch the cached catalogue for
			# this process only (a tuning aid; two runs can try two numbers at once).
			for item in a.substr(7).split(";", false):
				var lhs := item.get_slice("=", 0)
				var row: Dictionary = PartsCatalogue.weapon(lhs.get_slice(".", 0))
				row[lhs.get_slice(".", 1)] = float(item.get_slice("=", 1))
				print("tune ", lhs, " = ", row[lhs.get_slice(".", 1)])
		elif a.begins_with("--opps="):
			_opps = Array(a.substr(7).split(","))
	if _weapon_list.is_empty():
		_weapon_list = ALL.duplicate()
	_run()


func _run() -> void:
	await process_frame
	for weapon in _weapon_list:
		var subject := legal_build(str(weapon), "player-1", "Subject", _hull, _drive)
		if subject.is_empty():
			_emit({"weapon": weapon, "error": "no legal build found"})
			continue
		for opp_kind in _opps:
			var opp := opponent_for(str(weapon), str(opp_kind))
			for s in _seeds:
				var row := await _fight_once(subject, opp, int(s))
				row["weapon"] = weapon
				row["opp_kind"] = opp_kind
				row["seed"] = s
				_emit(row)
	quit(0)


func _emit(row: Dictionary) -> void:
	var line := JSON.stringify(row)
	print("GAUNTLET ", line)
	if _out_path != "":
		var f: FileAccess
		if FileAccess.file_exists(_out_path):
			f = FileAccess.open(_out_path, FileAccess.READ_WRITE)
			f.seek_end()
		else:
			f = FileAccess.open(_out_path, FileAccess.WRITE)
		f.store_line(line)
		f.close()


# ---------------------------------------------------------------- builds

static func _armour(material: String, thickness: int) -> Dictionary:
	var out := {}
	for face in ["front", "sides", "rear", "top"]:
		out[face] = {"material": material, "thickness": thickness}
	return out


static func _damage() -> Dictionary:
	return {
		"wheels": [1.0, 1.0, 1.0, 1.0], "weapon": 1.0,
		"armour": {"front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0},
		"drive": 1.0, "core": 1.0,
	}


## The heaviest legal armour on the first hull and drive that take the weapon.
static func legal_build(weapon: String, id: String, name: String,
		force_hull: String = "", force_drive: String = "") -> Dictionary:
	var hulls: Array = [force_hull] if force_hull != "" else HULLS.get(weapon, ["box", "wedge"])
	var drives: Array = [force_drive] if force_drive != "" else DRIVES
	for hull in hulls:
		var chassis := PartsCatalogue.chassis(str(hull))
		var utility: Array = [] if bool(chassis.get("invertible", false)) else ["srimech"]
		for drive in drives:
			for arm in ARMOURS:
				var cfg := {
					"id": id, "name": name, "controller": "player",
					"chassis": hull, "drive": drive, "weapon": weapon,
					"utility": utility, "armour": _armour(str(arm[0]), int(arm[1])),
					"damage": _damage(),
				}
				if BuildRules.is_valid(cfg):
					return cfg
	return {}


## "plain": a box on four wheels with a ram (no moving weapon), all steel.
## "weapon": the hero wedge flipper, or a box horizontal spinner when the subject IS a
## flipper.
static func opponent_for(weapon: String, kind: String) -> Dictionary:
	var w := "ram"
	var hull := "box"
	if kind == "weapon":
		w = "horizontal_spinner" if weapon == "flipper" else "flipper"
		hull = "box" if w == "horizontal_spinner" else "wedge"
	elif kind.begins_with("w:"):
		w = kind.substr(2)
		var b := legal_build(w, "ai-1", "Opponent")
		b["controller"] = "ai"
		return b
	var cfg := {
		"id": "ai-1", "name": "Opponent", "controller": "ai",
		"chassis": hull, "drive": "4wd", "weapon": w, "utility": ["srimech"],
		"armour": _armour("steel", 2), "damage": _damage(),
	}
	if not BuildRules.is_valid(cfg):
		cfg["armour"] = _armour("steel", 1)
	return cfg


# ---------------------------------------------------------------- one fight

func _fight_once(subject: Dictionary, opp: Dictionary, seed_value: int) -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var a := subject.duplicate(true)
	a["ai_skill"] = _subject_skill
	a["temperament"] = "brawler"
	var b := opp.duplicate(true)
	b["ai_skill"] = "regional"
	b["temperament"] = "technician"
	config["seed"] = seed_value
	config["arena"] = "yard"
	config["rules"] = {"mode": "fight", "duration_s": _secs, "ko_count_s": 10}
	config["debug"] = {"opponent_ai": "normal", "player_ai": "normal"}
	config["bots"] = [a, b]

	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	var result := {"payload": {}}
	var on_sent := func(type: String, payload: Dictionary) -> void:
		if type == FightTypes.MSG_FIGHT_RESULT:
			result["payload"] = payload
	var bridge: Node = root.get_node("Bridge")
	bridge.message_sent.connect(on_sent)
	fight.call("start_fight", config)
	await process_frame

	var bots: Array = fight.get("_bots") as Array
	var me: Node = bots[0]
	var foe: Node = bots[1]
	var st := {
		"fires": 0, "fire_ticks": [], "dmg_out": 0.0, "dmg_in": 0.0, "dmg_self": 0.0,
		"dmg_arena": 0.0, "events_out": 0, "events_in": 0, "out_times": [],
		"parts_off_foe": [], "parts_off_me": [], "sources_out": {},
		"foe_inverts": 0, "me_inverts": 0, "impact_felt": 0, "first_hit_t": -1.0,
		"max_sev": 0.0,
	}
	me.damage_event.connect(func(info: Dictionary) -> void:
		var att := str(info.get("attacker", ""))
		var sev := float(info.get("severity", 0.0))
		if att == "player-1":
			st["dmg_self"] += sev
		elif att == "arena":
			st["dmg_arena"] += sev
		else:
			st["dmg_in"] += sev
			st["events_in"] += 1)
	foe.damage_event.connect(func(info: Dictionary) -> void:
		var att := str(info.get("attacker", ""))
		var sev := float(info.get("severity", 0.0))
		if att == "player-1":
			st["dmg_out"] += sev
			st["events_out"] += 1
			st["max_sev"] = maxf(float(st["max_sev"]), sev)
			(st["out_times"] as Array).append(float(fight.call("fight_time")))
			var src := str(info.get("source", ""))
			var srcs: Dictionary = st["sources_out"]
			srcs[src] = int(srcs.get(src, 0)) + 1
			if float(st["first_hit_t"]) < 0.0:
				st["first_hit_t"] = float(fight.call("fight_time"))
		elif att == "arena":
			pass)
	me.weapon_fired.connect(func() -> void:
		st["fires"] += 1
		(st["fire_ticks"] as Array).append(float(fight.call("fight_time"))))
	foe.part_detached.connect(func(p: String) -> void: (st["parts_off_foe"] as Array).append(p))
	me.part_detached.connect(func(p: String) -> void: (st["parts_off_me"] as Array).append(p))
	foe.inverted_changed.connect(func(inv: bool) -> void:
		if inv: st["foe_inverts"] += 1)
	me.inverted_changed.connect(func(inv: bool) -> void:
		if inv: st["me_inverts"] += 1)
	var fx: Node = fight.get("_fx")
	if fx != null and fx.has_signal("impact_felt"):
		fx.impact_felt.connect(func(_f: Dictionary) -> void: st["impact_felt"] += 1)

	var mix: Node = fx.get("_mix") if fx != null else null
	var wfx: Node = fx.get("_weapons") if fx != null else null
	var seen_sounds := {}
	var sounds := {}
	var loop_ticks := {}
	var wfx_counters := {}

	var throws := 0
	var up_times: Array = []
	var foe_peak := 0.0
	var me_peak := 0.0
	var was_up := false
	var me_up_ticks := 0
	var stuck_ticks := 0
	var weapon_sep_max := 0.0
	var fire_dist: Array = []
	var dist_sum := 0.0
	var close_ticks := 0
	var ticks := 0
	var weapon_state_max := {}
	var pressed_ticks := 0
	var presses := 0
	var was_pressed := false
	var frames := 0
	var budget := (_secs + 12) * 60 * 3
	var last_fire_count := 0
	while frames < budget and int(fight.get("state")) != STATE_RESULT:
		await physics_frame
		frames += 1
		if int(fight.get("state")) != 2:
			continue
		ticks += 1
		var mp: Vector3 = me.chassis.global_position
		var fp: Vector3 = foe.chassis.global_position
		var d := Vector2(mp.x - fp.x, mp.z - fp.z).length()
		dist_sum += d
		if d < 1.2:
			close_ticks += 1
		foe_peak = maxf(foe_peak, fp.y)
		me_peak = maxf(me_peak, mp.y)
		if mp.y > AIR_M:
			me_up_ticks += 1
		var up := fp.y > AIR_M
		if up and not was_up:
			throws += 1
			up_times.append(float(fight.call("fight_time")))
		was_up = up
		if me.chassis.linear_velocity.length() < 0.05 and d > 1.5:
			stuck_ticks += 1
		if int(st["fires"]) > last_fire_count:
			last_fire_count = int(st["fires"])
			fire_dist.append(snappedf(d, 0.01))
		var wb: Node3D = me.call("body_for_part", "weapon") as Node3D
		if wb != null and is_instance_valid(wb) and not bool(wb.get("detached")):
			weapon_sep_max = maxf(weapon_sep_max, wb.global_position.distance_to(mp))
		# the input record the AI gave the subject this tick
		var rows: Array = (fight.get("_recorder") as Object).get("rows") as Array
		if not rows.is_empty():
			var row: Array = rows[rows.size() - 1] as Array
			var p := int(row[3]) == 1
			if p:
				pressed_ticks += 1
			if p and not was_pressed:
				presses += 1
			was_pressed = p
		if _trace > 0 and ticks % _trace == 0:
			var rws: Array = (fight.get("_recorder") as Object).get("rows") as Array
			var lr: Array = rws[rws.size() - 1] if not rws.is_empty() else []
			var pai: Object = fight.get("_player_ai")
			print("TRACE t=%.2f tick=%d me=(%.2f,%.2f,%.2f) v=%.2f up=%.2f inv=%s foe=(%.2f,%.2f,%.2f) d=%.2f in=%s ready=%.2f fault=%s imm=%s ko=%s intent=%s wheels=%s" % [
				float(fight.call("fight_time")), int(fight.get("_tick")), mp.x, mp.y, mp.z,
				me.chassis.linear_velocity.length(), me.chassis.global_basis.y.dot(Vector3.UP),
				me.call("is_inverted"), fp.x, fp.y, fp.z, d, str(lr.slice(1, 4)),
				float(me.call("weapon_readiness")), me.call("weapon_fault"), me.call("is_immobile"),
				str((fight.get("_ko_count") as Array)), str(pai.get("_intent")) if pai != null else "-",
				str(me.call("wheel_contacts"))])
			var wav := []
			for wh in me.drive_module.wheels:
				wav.append(snappedf((wh as RigidBody3D).angular_velocity.length(), 0.1))
			var wbody: Node3D = me.call("body_for_part", "weapon") as Node3D
			print("TRACE2 angv=%.2f wheels_w=%s disrupt_drive=%.2f weapon_y=%.3f chassis_contacts=%d" % [
				me.chassis.angular_velocity.length(), str(wav), float(me.get("_disrupt_drive")),
				wbody.global_position.y if wbody != null else -1.0,
				me.chassis.get_contact_count() if me.chassis.contact_monitor else -1])
			var cb := []
			for body in me.chassis.get_colliding_bodies():
				cb.append(str(body.get_path()).get_file() + "@" + str(snappedf((body as Node3D).global_position.y, 0.01)))
			var wb2 := []
			for wh in me.drive_module.wheels:
				var wbb := []
				for body in (wh as RigidBody3D).get_colliding_bodies():
					wbb.append(str(body.name))
				wb2.append(wbb)
			print("TRACE3 chassis_touching=%s wheels_touching=%s wheel_y=%s" % [str(cb), str(wb2), str(me.drive_module.wheels.map(func(w): return snappedf(w.global_position.y, 0.001)))])
		if me.weapon != null:
			var ws: Dictionary = me.weapon.state()
			for k in ws:
				var v: Variant = ws[k]
				if v is float or v is int:
					weapon_state_max[k] = maxf(float(weapon_state_max.get(k, -1e9)), float(v))
				elif v is bool and v:
					weapon_state_max[str(k) + "_true_ticks"] = int(weapon_state_max.get(str(k) + "_true_ticks", 0)) + 1
		# numeric presentation checks: one-shot sounds started, loops alive, WeaponFx state
		if mix != null:
			var active: Dictionary = mix.get("_active")
			for group in active:
				for e in (active[group] as Array):
					var ent: Dictionary = e
					var key := "%s|%s|%d" % [group, str(ent.get("at")), (ent["player"] as Object).get_instance_id() if ent.get("player") != null else 0]
					if not seen_sounds.has(key):
						seen_sounds[key] = true
						sounds[group] = int(sounds.get(group, 0)) + 1
			for k in mix.call("loop_keys"):
				var ks := str(k)
				if ks.find("player-1") >= 0:
					loop_ticks[ks] = int(loop_ticks.get(ks, 0)) + 1
		if wfx != null:
			var ws2: Dictionary = wfx.call("state_of", "player-1")
			for k in ["arcs", "shocks", "shots", "throws", "stalls", "ticks", "steps"]:
				if ws2.has(k):
					wfx_counters[k] = maxi(int(wfx_counters.get(k, 0)), int(ws2[k]))
			for k in ["bore", "cut", "heat", "cooked"]:
				if ws2.has(k):
					wfx_counters[k + "_max"] = maxf(float(wfx_counters.get(k + "_max", 0.0)), float(ws2[k]))

	var payload: Dictionary = result["payload"]
	var outcome := str(payload.get("outcome_type", payload.get("outcome", {}).get("type", "") if payload.get("outcome") is Dictionary else ""))
	var winner := str(payload.get("winner", ""))
	var at_s := float(payload.get("at_s", float(fight.call("fight_time"))))
	if payload.has("outcome") and payload["outcome"] is Dictionary:
		var o: Dictionary = payload["outcome"]
		outcome = str(o.get("type", outcome))
		winner = str(o.get("winner", winner))
		at_s = float(o.get("at_s", at_s))

	# blows: damage events grouped by gap
	var blows := 0
	var last := -99.0
	for t in (st["out_times"] as Array):
		if float(t) - last > BLOW_GAP_S:
			blows += 1
		last = float(t)
	# fires that landed: damage, or the foe leaving the floor, inside the window
	var landed := 0
	var fire_throws := 0
	for ft in (st["fire_ticks"] as Array):
		for t in (st["out_times"] as Array) + up_times:
			if float(t) >= float(ft) - 0.05 and float(t) - float(ft) <= LAND_WINDOW_S:
				landed += 1
				break
		for t in up_times:
			if float(t) >= float(ft) - 0.05 and float(t) - float(ft) <= LAND_WINDOW_S:
				fire_throws += 1
				break

	var cond_me: Dictionary = me.call("condition")
	var cond_foe: Dictionary = foe.call("condition")
	var row := {
		"hull": subject["chassis"], "drive": subject["drive"],
		"armour": str(subject["armour"]["front"]["material"]) + str(subject["armour"]["front"]["thickness"]),
		"opp": "%s/%s" % [opp["chassis"], opp["weapon"]],
		"outcome": outcome, "winner": winner, "won": winner == "player-1", "at_s": snappedf(at_s, 0.1),
		"fires": st["fires"], "presses": presses, "pressed_s": snappedf(pressed_ticks / 60.0, 0.1),
		"fires_landed": landed, "fire_throws": fire_throws, "fire_dist_mean": snappedf(_mean(fire_dist), 0.01),
		"blows": blows, "events_out": st["events_out"], "dmg_out": snappedf(float(st["dmg_out"]), 0.001),
		"max_sev": snappedf(float(st["max_sev"]), 0.001),
		"dmg_in": snappedf(float(st["dmg_in"]), 0.001), "dmg_self": snappedf(float(st["dmg_self"]), 0.001),
		"dmg_arena": snappedf(float(st["dmg_arena"]), 0.001),
		"first_hit_s": snappedf(float(st["first_hit_t"]), 0.1),
		"parts_off_foe": st["parts_off_foe"], "parts_off_me": st["parts_off_me"],
		"sources_out": st["sources_out"],
		"throws": throws, "foe_peak_m": snappedf(foe_peak, 0.01), "foe_inverts": st["foe_inverts"],
		"me_peak_m": snappedf(me_peak, 0.01), "me_air_s": snappedf(me_up_ticks / 60.0, 0.1),
		"me_inverts": st["me_inverts"], "stuck_s": snappedf(stuck_ticks / 60.0, 0.1),
		"close_s": snappedf(close_ticks / 60.0, 0.1), "mean_dist": snappedf(dist_sum / maxf(ticks, 1.0), 0.01),
		"weapon_sep_max": snappedf(weapon_sep_max, 0.01),
		"weapon_cond_end": snappedf(float(cond_me.get("weapon", -1.0)), 0.01),
		"jammed_end": bool(me.call("weapon_jammed")),
		"foe_core_end": snappedf(float(cond_foe.get("core", -1.0)), 0.01),
		"impact_felt": st["impact_felt"], "sounds": sounds, "loop_s": _to_s(loop_ticks),
		"wfx": wfx_counters, "wstate": _snap(weapon_state_max), "ticks": ticks,
		"hits_payload": payload.get("hits", {}),
	}

	bridge.message_sent.disconnect(on_sent)
	root.remove_child(fight)
	fight.queue_free()
	await process_frame
	await process_frame
	return row


static func _mean(a: Array) -> float:
	if a.is_empty():
		return -1.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


static func _to_s(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = snappedf(float(d[k]) / 60.0, 0.1)
	return out


static func _snap(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = snappedf(float(d[k]), 0.01)
	return out
