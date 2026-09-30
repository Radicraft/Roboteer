class_name TapeCards extends RefCounted
## The tale of the tape (wave D walk-outs, docs/wave-d-walkout-notes.md): the card each
## machine gets on screen while it rolls out of its gate, and the one the house bot gets.
##
## The shell sends the finished words in `fight_config.tape` (docs/bridge-spec.md): who the
## roboteer is, the record between the two, the player's own strength and weakness lines,
## a rival's written ones. Anything it leaves out is made here from the machine's own
## configuration and `res://data/parts.json`, so a desktop run, a test fixture or an older
## shell still gets a whole card. Nothing here is read by the simulation.
##
## A card is a Dictionary of display strings:
##   side      "player", "opponent" or "house"
##   label     the small word over the name ("YOUR MACHINE", "OPPONENT", "HOUSE BOT")
##   name      the machine, as it is written
##   roboteer  who built it ("" for the player and the house bots)
##   mass, drive, weapon
##   stats     [{label, value}], two or three whole-machine numbers
##   record    the head to head line ("" when there is nothing to say)
##   strength, weakness

const STYLE_CAREER := "career"
const STYLE_QUICK := "quick"
## A line the player writes is cut to this many characters (the builder stops there too).
const LINE_MAX := 60


## The style of the walk-outs: career gets the long ones, a quick fight the short ones.
static func style(config: Dictionary) -> String:
	var tape: Variant = config.get("tape", {})
	if tape is Dictionary and str((tape as Dictionary).get("style", "")) == STYLE_QUICK:
		return STYLE_QUICK
	return STYLE_CAREER


## Every card this fight has: {"player": card, "opponent": card, "house": card or {}}.
## `bots` is the configuration's `bots` array, `house_id` the house bot on duty or "".
static func cards(config: Dictionary, house_id: String = "") -> Dictionary:
	var bots: Array = config.get("bots", []) as Array
	var sent := _sent_cards(config)
	var out := {"player": {}, "opponent": {}, "house": {}}
	if bots.size() >= 1 and bots[0] is Dictionary:
		out["player"] = _merge(default_card(bots[0], "player"), sent.get("player", {}))
	if bots.size() >= 2 and bots[1] is Dictionary:
		out["opponent"] = _merge(default_card(bots[1], "opponent"), sent.get("opponent", {}))
	if house_id != "":
		out["house"] = _merge(house_card(house_id), sent.get("house", {}))
	return out


static func _sent_cards(config: Dictionary) -> Dictionary:
	var out := {}
	var tape: Variant = config.get("tape", {})
	if not tape is Dictionary:
		return out
	var list: Variant = (tape as Dictionary).get("cards", [])
	if not list is Array:
		return out
	for c in list:
		if c is Dictionary and str((c as Dictionary).get("side", "")) in ["player", "opponent", "house"]:
			out[str((c as Dictionary)["side"])] = c
	return out


## The shell's words win over the made-up ones, field by field. Strings are trimmed and the
## two lines capped, so nothing the player typed can run off the card.
static func _merge(base: Dictionary, sent: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in ["label", "name", "roboteer", "mass", "drive", "weapon", "record", "strength", "weakness"]:
		if sent.has(key) and sent[key] is String:
			var s := clean(str(sent[key]), 80 if key == "name" else (LINE_MAX if key in ["strength", "weakness"] else 60))
			if s != "" or key in ["roboteer", "record"]:
				out[key] = s
	if sent.get("stats") is Array:
		var stats: Array = []
		for row in sent["stats"]:
			if row is Dictionary:
				stats.append({"label": clean(str(row.get("label", "")), 12),
					"value": clean(str(row.get("value", "")), 14)})
		if not stats.is_empty():
			out["stats"] = stats.slice(0, 3)
	return out


## Trimmed, one line, spaces collapsed, at most `limit` characters (cut at a word when it can).
static func clean(text: String, limit: int = LINE_MAX) -> String:
	var s := text.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	while s.find("  ") >= 0:
		s = s.replace("  ", " ")
	if s.length() > limit:
		s = s.substr(0, limit)
		var cut := s.rfind(" ")
		if cut > limit * 0.6:
			s = s.substr(0, cut)
		s = s.strip_edges()
	return s


# ---------------------------------------------------------------- made from the build

## A card from a `bots[i]` configuration alone.
static func default_card(bot: Dictionary, side: String) -> Dictionary:
	var lines := default_lines(bot)
	var written := _written_lines_for(str(bot.get("name", ""))) if side != "player" else []
	if not written.is_empty():
		lines = written
	return {
		"side": side,
		"label": "YOUR MACHINE" if side == "player" else "OPPONENT",
		"name": str(bot.get("name", "")),
		"roboteer": _roboteer_for(str(bot.get("name", ""))) if side != "player" else "",
		"mass": kg(BuildRules.total_weight(bot)),
		"drive": str(PartsCatalogue.drive(str(bot.get("drive", ""))).get("name", str(bot.get("drive", "")).to_upper())),
		"weapon": str(PartsCatalogue.weapon(str(bot.get("weapon", ""))).get("name", str(bot.get("weapon", "")))),
		"stats": default_stats(bot),
		"record": "",
		"strength": lines[0],
		"weakness": lines[1],
	}


## The house bot on duty, from `bosses` in parts.json.
static func house_card(house_id: String) -> Dictionary:
	var boss: Dictionary = (PartsCatalogue.parts().get("bosses", {}) as Dictionary).get(house_id, {}) as Dictionary
	var build: Dictionary = (boss.get("build", {}) as Dictionary).duplicate(true)
	var lines := default_lines(build) if not build.is_empty() else ["", ""]
	return {
		"side": "house",
		"label": "HOUSE BOT",
		"name": str(boss.get("name", house_id.to_upper())),
		"roboteer": str(boss.get("signature", "")),
		"mass": kg(BuildRules.total_weight(build)) if not build.is_empty() else "",
		"drive": str(PartsCatalogue.drive(str(build.get("drive", ""))).get("name", "")),
		"weapon": str(PartsCatalogue.weapon(str(build.get("weapon", ""))).get("name", "")),
		"stats": default_stats(build) if not build.is_empty() else [],
		"record": "",
		"strength": str(boss.get("strength", lines[0])),
		"weakness": str(boss.get("weakness", lines[1])),
	}


## Two numbers the arena can stand behind for the whole machine: top speed from the drive and
## the armour's weight. The shell sends its own (the builder's pips) when it can.
static func default_stats(bot: Dictionary) -> Array:
	var drive := PartsCatalogue.drive(str(bot.get("drive", "")))
	var armour := float(BuildRules.category_weights(bot).get("armour", 0.0))
	var out: Array = []
	if drive.has("top_speed"):
		out.append({"label": "SPEED", "value": "%.1f m/s" % float(drive["top_speed"])})
	out.append({"label": "ARMOUR", "value": kg(armour)})
	return out


## The default strength and weakness, from the build. The same rules as the shell's
## `TaleOfTheTape.defaultLines` (Roboteer/TaleOfTheTape.swift), so a card reads the same
## whichever side wrote it.
static func default_lines(bot: Dictionary) -> Array:
	var weapon := PartsCatalogue.weapon(str(bot.get("weapon", "")))
	var w := float(weapon.get("weight", 0.0))
	var wname := str(weapon.get("name", str(bot.get("weapon", "weapon")))).to_lower()
	var strength := "%s of %s." % [kg(w), wname] if w > 0.0 else "Nothing to lose."
	var armour: Dictionary = bot.get("armour", {}) as Dictionary
	var rear: Dictionary = armour.get("rear", {}) as Dictionary
	var top: Dictionary = armour.get("top", {}) as Dictionary
	var utility: Array = bot.get("utility", []) as Array if bot.get("utility", []) is Array else []
	var chassis := PartsCatalogue.chassis(str(bot.get("chassis", "")))
	var weakness := "It knows it."
	if str(rear.get("material", "")) in ["polycarbonate", "hdpe"] and int(rear.get("thickness", 1)) <= 1:
		weakness = "The back end is mostly hope."
	elif str(bot.get("drive", "")) == "2wd":
		weakness = "Two wheels, both load bearing."
	elif not utility.has("srimech") and not bool(chassis.get("invertible", false)):
		weakness = "Upside down, it is an ornament."
	elif int(top.get("thickness", 2)) <= 1:
		weakness = "Thin on top, and sensitive about it."
	return [strength, weakness]


## A rival's written lines, found by its machine's name. [] when the name is not a rival's.
static func _written_lines_for(machine: String) -> Array:
	var rival := _rival_named(machine)
	if rival.has("strength") and rival.has("weakness"):
		return [str(rival["strength"]), str(rival["weakness"])]
	return []


static func _roboteer_for(machine: String) -> String:
	return str(_rival_named(machine).get("roboteer", ""))


static func _rival_named(machine: String) -> Dictionary:
	if machine == "":
		return {}
	var rivals: Dictionary = PartsCatalogue.parts().get("rivals", {}) as Dictionary
	for id in rivals.keys():
		var r: Dictionary = rivals[id]
		if str(r.get("name", "")).to_lower() == machine.to_lower():
			return r
	return {}


## "24 kg" or "24.5 kg", the shell's `BuildRules.kilograms`.
static func kg(value: float) -> String:
	var r := roundf(value * 10.0) / 10.0
	if is_equal_approx(r, roundf(r)):
		return "%d kg" % int(roundf(r))
	return "%.1f kg" % r
