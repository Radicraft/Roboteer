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
	# v2 (wave P), additive: the schema stays 1 because Swift tolerates a missing key, and
	# these four are ALWAYS present so no reader has to guess whether they exist.
	"hits", "parts_lost", "condition_start", "scrap_breakdown",
]


## ctx keys (all required; missing ones degrade to the empty/zero shape rather than crash):
##   config: Dictionary                the FightConfig this fight ran from
##   outcome_type: String              ko | out_of_arena | judges | component_kill | timeout
##   winner: String, loser: String     bot ids
##   at_s: float                       fight time the outcome landed
##   duration_s: float                 fight time elapsed
##   judges: Dictionary                bot id -> {damage, aggression, control}
##   damage: Dictionary                bot id -> condition() dictionary
##   scrap: Dictionary                 bot id -> int (the banked total)
##   hits: Dictionary                  bot id -> {landed, taken}                    (v2)
##   parts_lost: Dictionary            bot id -> [{part, label, state}]             (v2)
##   condition_start: Dictionary       bot id -> condition() as the fight started   (v2)
##   scrap_breakdown: Dictionary       bot id -> {base, damage, survivor, flawless, total} (v2)
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
	# v2. Four more per bot dictionaries, each with a zero shaped default, so a caller that
	# knows nothing about wave P (a test, an older fight path) still produces a valid v2
	# result rather than a result with holes in it.
	var hits: Dictionary = {}
	var parts_lost: Dictionary = {}
	var condition_start: Dictionary = {}
	var scrap_breakdown: Dictionary = {}
	var in_hits: Dictionary = ctx.get("hits", {}) as Dictionary
	var in_parts_lost: Dictionary = ctx.get("parts_lost", {}) as Dictionary
	var in_condition_start: Dictionary = ctx.get("condition_start", {}) as Dictionary
	var in_breakdown: Dictionary = ctx.get("scrap_breakdown", {}) as Dictionary
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

		var bot_hits: Dictionary = in_hits.get(id, {}) as Dictionary
		hits[id] = {
			"landed": int(bot_hits.get("landed", 0)),
			"taken": int(bot_hits.get("taken", 0)),
		}
		parts_lost[id] = (in_parts_lost.get(id, []) as Array).duplicate(true)
		# No snapshot means nothing was simulated, so the config's own damage block IS the
		# condition this bot started the fight with.
		condition_start[id] = in_condition_start.get(id, bot.get("damage", {}))
		var lines: Dictionary = in_breakdown.get(id, {}) as Dictionary
		var base := int(lines.get("base", 0))
		var damage_line := int(lines.get("damage", 0))
		var survivor := int(lines.get("survivor", 0))
		var flawless := int(lines.get("flawless", 0))
		scrap_breakdown[id] = {
			"base": base,
			"damage": damage_line,
			"survivor": survivor,
			"flawless": flawless,
			# Recomputed rather than copied: the total is the sum of its lines by
			# definition, and Swift's ScrapBreakdown computes it the same way.
			"total": base + damage_line + survivor + flawless,
		}

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
		"hits": hits,
		"parts_lost": parts_lost,
		"condition_start": condition_start,
		"scrap_breakdown": scrap_breakdown,
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
