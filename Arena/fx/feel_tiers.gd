class_name FeelTiers extends RefCounted
## FEEL TIERS (combat feel wave, docs/wave-a-combat-notes.md section 3).
##
## Until this wave every blow got the same feedback sized only by the condition it took off,
## split at severity 0.3. That is the right number for the rules and the wrong one for the
## senses: an axe slamming a steel lid takes little condition and is a huge event; a saw tick
## takes little and is tiny. So feedback is chosen here from the BLOW: the attacker's weapon,
## the severity, the impulse, whether a part came off and the material that was struck, and
## the tier then sizes everything at once: the sound, the sparks, the camera (shake, kick,
## zoom punch), the haptic and the hit-stop.
##
## Pure presentation: static, reads a payload and two strings, returns a Dictionary. Every
## number that decides how a hit FEELS is in TIERS, WEAPON_FLOOR, MATERIAL and CONTINUOUS, so
## tuning is editing a table, never reading the code.

const SCUFF := "scuff"
const HIT := "hit"
const HEAVY := "heavy"
const SMASH := "smash"
const ORDER := [SCUFF, HIT, HEAVY, SMASH]

## What each tier does. `trauma` is ImpactShake trauma (squared on the way out), `kick_deg` the
## directional/rotational camera kick, `fov_punch_deg` how far the lens closes and springs
## back, `stop_ms` the hit-stop (fight/hit_stop.gd caps it at 120 and keeps 250 ms between
## stops), `slowmo_s` wall seconds of quarter speed. `haptic` is a bridge haptic kind.
const TIERS := {
	"scuff": {"sound": "impact_light", "sound_db": -4.0, "haptic": "",
		"trauma": 0.10, "kick_deg": 0.0, "fov_punch_deg": 0.0, "stop_ms": 0.0,
		"slowmo_s": 0.0, "sparks": 0.25, "crowd": false},
	"hit": {"sound": "impact_light", "sound_db": 0.0, "haptic": "impact_light",
		"trauma": 0.30, "kick_deg": 0.45, "fov_punch_deg": 0.0, "stop_ms": 45.0,
		"slowmo_s": 0.0, "sparks": 0.55, "crowd": false},
	"heavy": {"sound": "impact_heavy", "sound_db": 0.0, "haptic": "impact_heavy",
		"trauma": 0.55, "kick_deg": 1.0, "fov_punch_deg": 1.6, "stop_ms": 80.0,
		"slowmo_s": 0.0, "sparks": 0.85, "crowd": true},
	"smash": {"sound": "impact_heavy", "sound_db": 2.0, "haptic": "impact_heavy",
		"trauma": 0.75, "kick_deg": 1.5, "fov_punch_deg": 2.8, "stop_ms": 110.0,
		"slowmo_s": 0.6, "sparks": 1.0, "crowd": true},
}

## Severity (condition removed) at which a blow reaches each tier, before the weapon floor.
const SEVERITY_AT := {"hit": 0.015, "heavy": 0.16, "smash": 0.45}
## Impulse (N s) at which a CONTACT blow (a shove, a landing, a wall slam) reaches each tier.
## Only collisions carry impulse; weapon bites arrive as direct damage with impulse 0.
const IMPULSE_AT := {"hit": 6.0, "heavy": 22.0, "smash": 55.0}

## The least a connecting blow from these weapons can be. An axe's head landing is a big
## event whatever condition it took (its median hit was 0.30, right on the old 0.3 line, so
## four of its six hits played the LIGHT sound); a ram's blow is momentum, never a tap.
const WEAPON_FLOOR := {
	"axe": "heavy",
	"ram": "hit",
	"spinner": "hit",
	"drum": "hit",
	"fbs": "hit",
}
## The weapon's own sound, layered over the tier's impact sound when it is the blow.
const WEAPON_LAYER := {
	"axe": "axe_hit",
	"ram": "ram_hit",
}

## The struck face's material: a pitch for the impact sound and a scale on the camera. Steel
## rings, titanium pings higher, HDPE thocks, polycarbonate cracks, a reactive plate bangs.
const MATERIAL := {
	"steel": {"pitch": 1.0, "trauma": 1.0},
	"titanium": {"pitch": 1.12, "trauma": 1.0},
	"hdpe": {"pitch": 0.82, "trauma": 0.85},
	"polycarbonate": {"pitch": 1.2, "trauma": 0.9},
	"reactive": {"pitch": 0.9, "trauma": 1.15},
}

## CONTINUOUS damage (a saw in the cut, a crusher chewing, a flame, the prod, the arc, the
## drill, the core cooking). One event per part per tick is right for the ledger and wrong for
## the senses (the saw sent 146 events in one second). The presentation keeps a running sum
## per attacker and victim and only answers with a BITE each time `bite_every` of condition
## has gone; in between it shows a thin spark stream at most every `stream_gap_s`.
const CONTINUOUS := {
	"sources": ["cut", "burn", "heat", "fire", "shock", "arc", "pierce"],
	"bite_every": 0.035,
	"stream_gap_s": 0.09,
	"bite_tier": "hit",
	# A pair that has had no continuous damage for this long starts a new cut (a crusher's
	# first grip plays its clamp again).
	"state_gap_s": 0.6,
}

## You feel your own machine being hit a little more than you feel hitting the other one.
const PLAYER_VICTIM_TRAUMA := 1.2


## The tier of one blow. `weapon_kind` is the ATTACKER's WeaponBase.kind ("" for the arena, a
## wall or a machine with no weapon), `material` the struck face's armour material ("" if the
## part was not a plate).
static func classify(info: Dictionary, weapon_kind: String) -> String:
	var severity := float(info.get("severity", 0.0))
	var impulse := float(info.get("impulse", 0.0))
	var tier := SCUFF
	if bool(info.get("detached", false)):
		return SMASH
	for name in ["hit", "heavy", "smash"]:
		if severity >= float(SEVERITY_AT[name]) or (impulse > 0.0 and impulse >= float(IMPULSE_AT[name])):
			tier = name
	var floor_tier := str(WEAPON_FLOOR.get(weapon_kind, ""))
	var from_weapon := str(info.get("source", "impact")) == "impact" and severity > 0.0
	if floor_tier != "" and from_weapon and _rank(floor_tier) > _rank(tier):
		tier = floor_tier
	return tier


static func is_continuous(info: Dictionary) -> bool:
	return float(info.get("impulse", 0.0)) <= 0.0 \
		and str(info.get("source", "")) in (CONTINUOUS["sources"] as Array)


## Everything the tier says, with the material and the victim folded in. The caller adds
## where and which way.
static func feel(tier: String, material: String, victim_is_player: bool) -> Dictionary:
	var out: Dictionary = (TIERS.get(tier, TIERS[SCUFF]) as Dictionary).duplicate()
	out["tier"] = tier
	var m: Dictionary = MATERIAL.get(material, MATERIAL["steel"])
	out["pitch"] = float(m["pitch"])
	var trauma := float(out["trauma"]) * float(m["trauma"])
	if victim_is_player:
		trauma *= PLAYER_VICTIM_TRAUMA
	out["trauma"] = minf(trauma, 1.0)
	return out


static func rank(tier: String) -> int:
	return _rank(tier)


static func _rank(tier: String) -> int:
	return ORDER.find(tier)
