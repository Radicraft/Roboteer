extends OpponentAI
class_name BossAI
## The five arena bosses (brief §8, docs/stage5-spec.md §4). Not entrants: enforcers.
##
## Each one is a personality laid over the ordinary weapon driver, not a replacement for
## it. `OpponentAI` already knows how to recover from being inverted, dodge the spikes,
## hold a ring, find a flank and work a weapon of a given kind; a boss is that, plus one
## rule that makes it recognisable from the stands. Keeping them subclasses means a boss
## can never silently lose the safety behaviours, and it means the rng is drawn on exactly
## the same fixed cadence as any other driver, so a career fight with a boss in it replays.
##
## The builds come from the catalogue's `bosses` key when agent S3 has landed it, and from
## FALLBACK_BUILDS until then. `build_for()` is the one place either is read.

const BOSS_THRESHER := "thresher"
const BOSS_GRUDGE := "grudge"
const BOSS_BANDSAW := "bandsaw"
const BOSS_ANVIL := "anvil"
const BOSS_CINDER := "cinder"
const BOSSES := [BOSS_THRESHER, BOSS_GRUDGE, BOSS_BANDSAW, BOSS_ANVIL, BOSS_CINDER]

## The catalogue names the personalities by what they DO rather than by who does it
## (`bosses[*].ai_mode`, agent S3), so both spellings are accepted everywhere a boss id is.
## An ai_mode nobody recognises drives like an ordinary machine rather than failing.
const AI_MODES := {
	"pin": BOSS_THRESHER,
	"disable": BOSS_GRUDGE,
	"herd": BOSS_BANDSAW,
	"wall": BOSS_ANVIL,
	"thrower": BOSS_CINDER,
}


## Accepts a boss id ("thresher") or a catalogue ai_mode ("pin"). Returns "" for anything
## else, which the caller reads as "drive this one normally".
static func resolve(id: String) -> String:
	if id in BOSSES:
		return id
	return str(AI_MODES.get(id, ""))

## THRESHER is immovable, not a pursuer: past this it goes home rather than chasing.
const LEASH_M := 3.2
const THRESHER_THROTTLE := 0.62      # slow and heavy, always
## GRUDGE stops burning and withdraws below this much fuel, so it is never caught dry.
const GRUDGE_RESERVE := 0.2
const GRUDGE_WITHDRAW_M := 3.0
## BANDSAW has the target pinned once the target is this close to a wall.
const WALL_PIN_M := 0.9
const HERD_LEAD_M := 1.1             # how far past the target it aims, to shove it along
const HERD_FROM_M := 1.8             # a hunting BANDSAW closes to this before it herds
## ANVIL never shows its back: below this dot it turns to face before it does anything.
const ANVIL_FACE_DOT := 0.2
const ANVIL_HOLD_M := 2.2            # it waits rather than chasing beyond this
## CINDER lines up so that a throw sends the victim at something nasty.
const CINDER_MIN_HAZARD_M := 0.4

## Used until `Shared/parts.json` carries a `bosses` key (agent S3). The chassis, drive and
## weapon of each are docs/stage5-spec.md §4 exactly; these are builds the assembler can
## already make.
##
## Every one is inside the 100 kg builder budget, measured with `BuildRules.total_weight`.
## A boss is not an entrant (brief §8) and arguably should not be held to the entrants'
## budget, but an over budget boss logs a validation error on every assembly and reads as
## an accident rather than a decision. If a later stage wants genuinely heavier bosses that
## should be an explicit exemption in the catalogue, not a silent 47 kg.
##
## The weight goes into the machine rather than the plate, which is the trade these five
## are meant to embody: THRESHER is a chassis and a crusher with almost no armour on it,
## and ANVIL puts what it has on the front, where its whole character is.
const FALLBACK_BUILDS := {
	BOSS_THRESHER: {
		"name": "THRESHER", "chassis": "long_low", "drive": "6wd", "weapon": "crusher",
		"utility": ["srimech", "counterweight"], "material": "titanium", "thickness": 1,
		"livery": "#4a4f56",
	},
	BOSS_GRUDGE: {
		"name": "GRUDGE", "chassis": "box", "drive": "tracks", "weapon": "flamethrower",
		"utility": ["srimech", "skirts"], "material": "steel", "thickness": 1,
		"livery": "#5d3320",
	},
	BOSS_BANDSAW: {
		"name": "BANDSAW", "chassis": "wedge", "drive": "2wd", "weapon": "saw",
		"utility": ["srimech"], "material": "titanium", "thickness": 2,
		"livery": "#6b6f36",
	},
	BOSS_ANVIL: {
		"name": "ANVIL", "chassis": "tall_tank", "drive": "4wd", "weapon": "axe",
		"utility": ["srimech", "counterweight"], "material": "titanium", "thickness": 1,
		# Nothing of yours gets through the FRONT (brief §8), so that is where the plate
		# goes. The sides and the back are deliberately thin: get round it and it is soft.
		"armour": {
			"front": {"material": "steel", "thickness": 2},
			"sides": {"material": "titanium", "thickness": 1},
			"rear": {"material": "hdpe", "thickness": 1},
			"top": {"material": "titanium", "thickness": 1},
		},
		"livery": "#3a3d42",
	},
	BOSS_CINDER: {
		"name": "CINDER", "chassis": "box", "drive": "6wd", "weapon": "flipper",
		"utility": ["srimech", "scoop"], "material": "hdpe", "thickness": 2,
		"livery": "#7a4a12",
	},
}

var boss: String = BOSS_THRESHER
## Where this boss came in from and where it withdraws to. Set by the enforcer.
var gate: Vector3 = Vector3.ZERO
## True on the ticks this boss is the released house bot (brief v4 §3: at the endgame it
## "leaves the corner for good and hunts"). Worked out each tick in `think` from the
## context fight.gd already sends; the personality still shows, but nothing in it may
## send the machine home, hold it back or make it withdraw while this is set.
var hunting := false

## Hunting pace for THRESHER: still the slowest thing on the floor, but it comes.
const THRESHER_HUNT_THROTTLE := 0.85
## A dry GRUDGE that is hunting keeps coming and shoves rather than backing off.
const GRUDGE_HUNT_SHOVE := 1.0


func _init(random: RandomNumberGenerator, boss_id: String = BOSS_THRESHER) -> void:
	super(random, MODE_NORMAL)
	var resolved := resolve(boss_id)
	boss = resolved if resolved != "" else BOSS_THRESHER


## The FightConfig bot entry for a boss: the catalogue's `bosses` row when it exists,
## otherwise FALLBACK_BUILDS. `bot_id` is what the rules will credit damage to.
static func build_for(boss_id: String, bot_id: String) -> Dictionary:
	var resolved := resolve(boss_id)
	var id := resolved if resolved != "" else BOSS_THRESHER
	var row := _catalogue_row(id)
	if row.is_empty():
		row = FALLBACK_BUILDS[id] as Dictionary
	var material := str(row.get("material", "steel"))
	var thickness := int(row.get("thickness", 2))
	var face := {"material": material, "thickness": thickness}
	var armour: Dictionary = (row.get("armour", {}) as Dictionary).duplicate(true)
	for key in ["front", "sides", "rear", "top"]:
		if not armour.has(key):
			armour[key] = face.duplicate()
	return {
		"id": bot_id,
		"name": str(row.get("name", id.to_upper())),
		"controller": "boss",
		"chassis": str(row.get("chassis", "box")),
		"drive": str(row.get("drive", "4wd")),
		"weapon": str(row.get("weapon", "ram")),
		"utility": (row.get("utility", ["srimech"]) as Array).duplicate(),
		"livery": str(row.get("livery", "#4a4f56")),
		"armour": armour,
		"damage": {
			"wheels": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0], "weapon": 1.0,
			"armour": {"front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0},
			"drive": 1.0, "core": 1.0,
		},
	}


## `bosses` in the catalogue, when S3 has landed it. Read through the same PartsCatalogue
## everything else uses, and tolerated missing.
static func _catalogue_row(boss_id: String) -> Dictionary:
	if not ClassDB.class_exists("PartsCatalogue") and not ResourceLoader.exists("res://bot/catalogue.gd"):
		return {}
	var catalogue: GDScript = load("res://bot/catalogue.gd")
	if catalogue == null or not catalogue.has_method("boss"):
		return {}
	var row: Variant = catalogue.call("boss", boss_id)
	return row as Dictionary if row is Dictionary else {}


## One tick. The base driver decides, then the personality edits.
##
## ctx adds one key beyond OpponentAI's: `hazards`, an array of world positions the arena
## would like things thrown into. fight.gd fills it from the arena's `hazard_helpers()`
## when the arena has one, and from the spike patch centre otherwise.
func think(me: Object, foe: Object, ctx: Dictionary) -> Dictionary:
	# The house bot is sent the same context as the competitors, which carries its OWN
	# position as "the released house bot, keep clear" and its own corner as a keep-out.
	# Steered by that, it avoids itself and flees its own corner into the wall behind it
	# (A1, systems gauntlet: GRUDGE 0.0 m after release). Strip both for the house bot.
	var own_house := me != null and _is_house_bot(me, ctx)
	if own_house:
		ctx = ctx.duplicate()
		ctx.erase("house_bot_position")
		ctx.erase("zone_rect")
	hunting = own_house \
		and str(ctx.get("phase", FightTypes.PHASE_OPEN)) == FightTypes.PHASE_ENDGAME
	var out := super(me, foe, ctx)
	if me == null or foe == null:
		return out

	var my_position := _position(me)
	var foe_position := _position(foe)
	var forward := _flat(_forward(me))
	var to_foe := _flat(foe_position - my_position)
	var range_m := to_foe.length()
	var to_foe_dir := to_foe.normalized() if range_m > 0.0001 else forward

	match boss:
		BOSS_THRESHER:
			return _thresher(out, my_position, range_m, to_foe_dir)
		BOSS_GRUDGE:
			return _grudge(out, me, range_m, to_foe_dir)
		BOSS_BANDSAW:
			return _bandsaw(out, my_position, foe_position, range_m, to_foe_dir)
		BOSS_ANVIL:
			return _anvil(out, forward, range_m, to_foe_dir)
		BOSS_CINDER:
			return _cinder(out, my_position, foe_position, range_m, to_foe_dir, ctx)
	return out


## Is `me` the machine fight.gd calls the house bot? It sends that machine's chassis
## position as `house_bot_position` (and Vector3.ZERO when there is none).
func _is_house_bot(me: Object, ctx: Dictionary) -> bool:
	var house: Variant = ctx.get("house_bot_position", null)
	if not (house is Vector3) or (house as Vector3) == Vector3.ZERO:
		return false
	return _position(me).distance_to(house as Vector3) < 0.01


## How close to a wall "get off the hazard" stops pushing into that wall.
const ESCAPE_WALL_M := 0.7

## The base driver's last line ("get off the hazard") points straight away from the
## hazard's centre, which for a machine between a hazard and a wall is INTO the wall: it
## pushes there for ever, stays inside the hazard's radius, and so keeps escaping (the
## Furnace house bot sat 1 m from a north jet lane with its tracks against the east wall,
## 0.0 m of travel in 50 s). For a boss the push slides along the wall instead, and when
## nothing is left of it, heads for the middle of the floor.
func _escape(my_position: Vector3, forward: Vector3, ctx: Dictionary, tick: int) -> Vector3:
	var away := super(my_position, forward, ctx, tick)
	if away == Vector3.ZERO:
		return away
	return off_the_wall(my_position, away, _half_extent)


static func off_the_wall(position: Vector3, away: Vector3, half_extent: float) -> Vector3:
	var slid := away
	if absf(position.x) > half_extent - ESCAPE_WALL_M and signf(slid.x) == signf(position.x):
		slid.x = 0.0
	if absf(position.z) > half_extent - ESCAPE_WALL_M and signf(slid.z) == signf(position.z):
		slid.z = 0.0
	slid.y = 0.0
	if slid.length() < 0.2:
		slid = Vector3(-position.x, 0.0, -position.z)
		if slid.length() < 0.0001:
			return away
	return slid.normalized()


# ---------------------------------------------------------------- the five

## Slow, immovable, ends fights by pinning. It does not chase: past the leash it walks back
## to its gate and waits, which is what makes it a hazard with wheels rather than a rival.
func _thresher(out: Dictionary, my_position: Vector3, range_m: float, to_foe_dir: Vector3) -> Dictionary:
	var heading: Vector2 = out["heading"]
	if hunting:
		# Released: no leash. It walks the target down at its own heavy pace.
		if heading.length() < 0.05:
			heading = heading_from_world_dir(to_foe_dir)
		out["heading"] = heading * THRESHER_HUNT_THROTTLE
		return out
	if range_m > LEASH_M:
		var home := _flat(gate - my_position)
		heading = heading_from_world_dir(home) if home.length() > 0.5 else Vector2.ZERO
		out["fire"] = false
	elif heading.length() < 0.05:
		heading = heading_from_world_dir(to_foe_dir)
	out["heading"] = heading * THRESHER_THROTTLE
	return out


## Does not damage much: it cooks you. It holds its own reach, sweeps, and withdraws once
## the fuel is nearly gone rather than being caught dry at contact range.
func _grudge(out: Dictionary, me: Object, range_m: float, to_foe_dir: Vector3) -> Dictionary:
	if _weapon_readiness(me) <= GRUDGE_RESERVE:
		out["fire"] = false
		if hunting:
			# Dry but released: it keeps coming and leans on you until the fuel is back.
			out["heading"] = heading_from_world_dir(to_foe_dir) * GRUDGE_HUNT_SHOVE
		elif range_m < GRUDGE_WITHDRAW_M:
			out["heading"] = heading_from_world_dir(-to_foe_dir)
	return out


## Fast and light: it herds you into a wall and holds you there while it cuts. It aims past
## the target toward the nearest wall rather than at the target, which is what pushes them.
func _bandsaw(out: Dictionary, my_position: Vector3, foe_position: Vector3,
		range_m: float, to_foe_dir: Vector3) -> Dictionary:
	if hunting and range_m > HERD_FROM_M:
		# Released: close first, herd once it is on them (it herded from across the
		# floor and never arrived: 0.7 m of travel at the Drop Zone endgame).
		out["heading"] = heading_from_world_dir(to_foe_dir)
		return out
	var wall := nearest_wall_point(foe_position)
	var to_wall := _flat(wall - foe_position)
	if to_wall.length() <= WALL_PIN_M:
		# Pinned. Stop herding and hold them on the wall, cutting.
		out["heading"] = heading_from_world_dir(to_foe_dir)
		out["fire"] = true
		return out
	var lead := foe_position + to_wall.normalized() * HERD_LEAD_M
	out["heading"] = heading_from_world_dir(_flat(lead - my_position))
	return out


## A wall with wheels. Nothing of yours gets through the front, so it never turns its back:
## facing comes before everything, and it waits rather than chasing.
func _anvil(out: Dictionary, forward: Vector3, range_m: float, to_foe_dir: Vector3) -> Dictionary:
	if forward.dot(to_foe_dir) < ANVIL_FACE_DOT:
		# Turning is driving toward them in an arcade drive, so this both faces and closes.
		out["heading"] = heading_from_world_dir(to_foe_dir)
		out["fire"] = false
		return out
	if range_m > ANVIL_HOLD_M and not hunting:
		out["heading"] = heading_from_world_dir(to_foe_dir) * 0.35
	return out


## Does not try to damage you: it tries to throw you into whatever is nearest. So it lines
## up on the far side of you from the hazard, and only then fires.
func _cinder(out: Dictionary, my_position: Vector3, foe_position: Vector3,
		range_m: float, to_foe_dir: Vector3, ctx: Dictionary) -> Dictionary:
	var hazard := nearest_hazard(foe_position, ctx)
	var from_hazard := _flat(foe_position - hazard)
	if from_hazard.length() < CINDER_MIN_HAZARD_M:
		return out          # already on top of it: throw from wherever we are
	var launch_spot := foe_position + from_hazard.normalized() * maxf(range_m * 0.5, 0.9)
	var to_spot := _flat(launch_spot - my_position)
	var lined_up := to_spot.length() < 0.45
	if not lined_up:
		out["heading"] = heading_from_world_dir(to_spot)
		out["fire"] = false
	else:
		out["heading"] = heading_from_world_dir(to_foe_dir)
	return out


# ---------------------------------------------------------------- geometry

## The point on the arena wall nearest a position. Used for herding.
static func nearest_wall_point(position: Vector3) -> Vector3:
	var half := FightTypes.ARENA_SIZE * 0.5
	var dx := half - absf(position.x)
	var dz := half - absf(position.z)
	if dx <= dz:
		return Vector3(half * signf(position.x if position.x != 0.0 else 1.0), position.y, position.z)
	return Vector3(position.x, position.y, half * signf(position.z if position.z != 0.0 else 1.0))


## The nastiest thing near a position. `ctx.hazards` is filled by fight.gd from the
## arena's `hazard_helpers()` when it has one; the spike patch is the Stage 3 fallback.
static func nearest_hazard(position: Vector3, ctx: Dictionary) -> Vector3:
	var hazards: Array = ctx.get("hazards", []) as Array
	if hazards.is_empty():
		var centre: Variant = ctx.get("spike_centre", Vector3.ZERO)
		return centre if centre is Vector3 else Vector3.ZERO
	var best: Vector3 = hazards[0]
	var best_d := INF
	for entry in hazards:
		var at: Vector3 = entry
		var d := Vector2(at.x - position.x, at.z - position.z).length()
		if d < best_d:
			best_d = d
			best = at
	return best
