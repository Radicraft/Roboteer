extends RefCounted
class_name FightResultBuilder
## Builds the FightResult v1 payload exactly as docs/bridge-spec.md specifies.
## Nothing else in the arena may assemble that dictionary.
##
## The one subtlety is integers. JSON.parse_string hands back a float for every whole
## number, so a seed that arrived as 123456789 would leave as 1.23456789e+08 unless it is
## put back through _as_number() on the way out (the same helper main.gd uses for the
## Stage 1 spike). Swift decodes seed, tick_hz, bot_count, physics_ticks and the judges'
## scores as integers, so they must stringify without a decimal point.

const SCHEMA := 1

const TOP_LEVEL_KEYS := [
	"schema", "outcome", "duration_s", "judges", "damage", "scrap", "replay", "diagnostics",
]


## ctx keys (all required; missing ones degrade to the empty/zero shape rather than crash):
##   config: Dictionary                the FightConfig this fight ran from
##   outcome_type: String              ko | out_of_arena | judges | component_kill | timeout
##   winner: String, loser: String     bot ids
##   at_s: float                       fight time the outcome landed
##   duration_s: float                 fight time elapsed
##   judges: Dictionary                bot id -> {damage, aggression, control}
##   damage: Dictionary                bot id -> condition() dictionary
##   scrap: Dictionary                 bot id -> int
##   replay_inputs: Array              FightTypes.replay_row rows
##   ticks_msec_at_config: int
##   ticks_msec_at_result: int
##   physics_ticks: int
static func build(ctx: Dictionary) -> Dictionary:
	var config: Dictionary = ctx.get("config", {}) as Dictionary
	var bots: Array = config.get("bots", []) as Array
	var seed_value: Variant = as_number(config.get("seed", 0))

	var judges: Dictionary = {}
	var damage: Dictionary = {}
	var scrap: Dictionary = {}
	var in_judges: Dictionary = ctx.get("judges", {}) as Dictionary
	var in_damage: Dictionary = ctx.get("damage", {}) as Dictionary
	var in_scrap: Dictionary = ctx.get("scrap", {}) as Dictionary
	for bot_variant in bots:
		var bot: Dictionary = bot_variant as Dictionary
		var id := str(bot.get("id", ""))
		# The judges are always filled, even on a knockout: the card at that moment.
		var card: Dictionary = in_judges.get(id, {}) as Dictionary
		judges[id] = {
			"damage": int(card.get("damage", 0)),
			"aggression": int(card.get("aggression", 0)),
			"control": int(card.get("control", 0)),
		}
		damage[id] = in_damage.get(id, bot.get("damage", {}))
		scrap[id] = int(in_scrap.get(id, 0))

	return {
		"schema": SCHEMA,
		"outcome": {
			"type": str(ctx.get("outcome_type", "timeout")),
			"winner": str(ctx.get("winner", "")),
			"loser": str(ctx.get("loser", "")),
			"at_s": float(ctx.get("at_s", 0.0)),
		},
		"duration_s": float(ctx.get("duration_s", 0.0)),
		"judges": judges,
		"damage": damage,
		"scrap": scrap,
		# Rumble only: the ids that went out, oldest first. Always present, empty in an
		# ordinary fight, because a key that only sometimes exists is a key Swift has to
		# guess about.
		"eliminated": (ctx.get("eliminated", []) as Array).duplicate(),
		"replay": {
			"seed": seed_value,
			"tick_hz": FightTypes.TICK_HZ,
			"inputs": ctx.get("replay_inputs", []),
		},
		"diagnostics": {
			"ticks_msec_at_config": int(ctx.get("ticks_msec_at_config", 0)),
			"ticks_msec_at_result": int(ctx.get("ticks_msec_at_result", 0)),
			"physics_ticks": int(ctx.get("physics_ticks", 0)),
			"echo": {
				"arena": str(config.get("arena", "")),
				"bot_count": bots.size(),
				"seed": seed_value,
			},
		},
	}


## JSON parsing can hand back a float for a whole number. Keep whole numbers whole so the
## seed survives the round trip as an integer on the Swift side. (main.gd's _as_number.)
static func as_number(value: Variant) -> Variant:
	if value is float and value == floor(value) and absf(value) < 9.0e15:
		return int(value)
	return value
