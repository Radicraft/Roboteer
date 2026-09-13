class_name FightTypes
## Shared constants and tables for the fight. Read-only contract for every Stage 3 agent
## (docs/stage3-spec.md). Change here first, then everywhere.

const SCHEMA := 1
const TICK_HZ := 60
const FIGHT_DURATION_S := 90.0
const KO_COUNT_S := 10.0
const COUNTDOWN_S := 3.0

## World
const ARENA_SIZE := 10.0          # metres, square floor centred on the origin, floor top at y = 0
const WALL_HEIGHT := 0.65   # raised from 0.45 on 2026-09-13: a 0.78 m throw cleared 0.45 m walls at 5 s
const WALL_THICKNESS := 0.2
const OUT_OF_ARENA_Y := -1.0
const SPAWN_PLAYER := Vector3(-3.2, 0.25, -3.2)
const SPAWN_OPPONENT := Vector3(3.2, 0.25, 3.2)

## Collision layers (bit indices are 1-based in the editor; masks below are bitmasks)
const LAYER_ARENA := 1
const LAYER_BOT := 2
const LAYER_DEBRIS := 4
const LAYER_HAZARD := 8
const LAYER_OOA := 16
const MASK_BOT := LAYER_ARENA | LAYER_BOT | LAYER_DEBRIS | LAYER_HAZARD
const MASK_DEBRIS := LAYER_ARENA | LAYER_BOT | LAYER_DEBRIS

## Bot
const BOT_MASS_CHASSIS := 22.0
const BOT_MASS_WHEEL := 2.5
const BOT_MASS_FLIPPER := 4.0
const WHEEL_RADIUS := 0.11
const WHEEL_WIDTH := 0.06
const TURN_RATE_4WD := 3.2        # rad/s, how fast the bot turns toward the stick
const TOP_SPEED_4WD := 3.5        # m/s
const FLIPPER_CHARGES := 8
const FLIPPER_COOLDOWN_S := 0.7
const SRIMECH_COOLDOWN_S := 1.2
const IMMOBILE_SPEED := 0.15      # m/s
const IMMOBILE_WINDOW_S := 0.5

## Input record, one per physics tick, produced by the controls and consumed by both bots.
## {"heading": Vector2 (stick, length 0..1), "fire": bool (edge), "secondary": bool (level)}
static func empty_input() -> Dictionary:
	return {"heading": Vector2.ZERO, "fire": false, "secondary": false}

## Replay row: [tick, heading.x, heading.y, fire 0/1, secondary 0/1]
static func replay_row(tick: int, inp: Dictionary) -> Array:
	var h: Vector2 = inp.get("heading", Vector2.ZERO)
	return [tick, h.x, h.y, 1 if inp.get("fire", false) else 0, 1 if inp.get("secondary", false) else 0]

## Part names used in damage_event.part, part_detached and condition()
const PART_WHEELS := ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]
const PART_WEAPON := "weapon"
const PART_ARMOUR := ["armour_front", "armour_sides", "armour_rear", "armour_top"]
const PART_DRIVE := "drive"
const PART_CORE := "core"

## Damage thresholds: contact impulse (N s) below MIN does nothing, at MAX removes a full 1.0 condition
const BREAK_MIN := {
	"wheel": 18.0, "weapon": 30.0, "armour": 24.0, "chassis": 40.0,
}
const BREAK_MAX := {
	"wheel": 90.0, "weapon": 160.0, "armour": 140.0, "chassis": 220.0,
}
## Material factor per damage source (brief §5.5). Wheels and the flipper arm use 1.0.
const MATERIAL_FACTOR := {
	"steel": {"impact": 1.0, "hazard": 0.6},
	"titanium": {"impact": 0.7, "hazard": 0.7},
	"hdpe": {"impact": 0.5, "hazard": 1.3},
	"polycarbonate": {"impact": 0.85, "hazard": 1.0},
}
const MATERIAL_MASS_KG := {"steel": 3.0, "titanium": 1.6, "hdpe": 1.0, "polycarbonate": 1.2}
const MATERIAL_COLOUR := {
	"steel": Color(0.62, 0.66, 0.72),
	"titanium": Color(0.30, 0.32, 0.36),
	"hdpe": Color(1, 1, 1),            # hdpe takes the livery colour
	"polycarbonate": Color(0.85, 0.88, 0.92, 0.6),
}
const LIVERY_PLAYER := Color(0.20, 0.36, 0.62)     # blue, from the arena render
const LIVERY_OPPONENT := Color(0.58, 0.16, 0.14)   # dark red; keeps gold bolts the only warm highlight
const DEBRIS_TINT := Color(0.42, 0.42, 0.44)
const BOLT_GOLD := Color(0.949, 0.757, 0.306)      # #f2c14e

## Scrap: decided by rules (R) from damage_event severity
static func scrap_for(severity: float, detached: bool) -> int:
	var n := int(round(severity * 40.0))
	return n * 2 if detached else n

## Bolt shower
const BOLT_POOL := 120
const BOLT_SCATTER_DELAY_MS := 250
const BOLT_SCATTER_JITTER := 0.9
const BOLT_COLLECT_RESET_MS := 380
const BOLT_MAX_SEMITONES := 24
const HAPTIC_MAX_PER_S := 30

## Camera
const CAM_FOV := 28.0
const CAM_YAW_DEG := 45.0
const CAM_PITCH_DEG := 50.0
const CAM_PITCH_MIN := 20.0
const CAM_PITCH_MAX := 70.0
const CAM_ZOOM_MIN := 0.55
const CAM_ZOOM_MAX := 1.0
const CAM_EASE_BACK_AFTER_S := 3.0
const CAM_EASE_BACK_S := 0.8

## Bridge message types used in Stage 3
const MSG_FIGHT_CONFIG := "fight_config"
const MSG_FIGHT_RESULT := "fight_result"
const MSG_FIGHT_STATE := "fight_state"
const MSG_HAPTIC := "haptic"
const MSG_ARENA_READY := "arena_ready"
const MSG_ARENA_LOG := "arena_log"

## Judges' scaling
const JUDGE_DAMAGE_FULL := 2.5      # condition points removed for a 10
const JUDGE_AGGRESSION_FULL_S := 45.0
const JUDGE_CONTROL_FULL_S := 15.0
