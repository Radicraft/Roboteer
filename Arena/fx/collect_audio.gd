class_name CollectAudio extends Node
## The collect pitch ramp. brief-v3.md §6 calls this "the single biggest contributor
## to the feel. Cheap to build, disproportionate payoff." It is one line of maths and
## a handful of voices, and it is the whole reason the bolt stream is satisfying.
##
## Each consecutive collect plays bolt_collect.wav one semitone higher than the last
## (x 2^(1/12)). A gap of FightTypes.BOLT_COLLECT_RESET_MS with no collect resets the
## ramp to 1.0. The ramp is capped at FightTypes.BOLT_MAX_SEMITONES.
##
## Voices rotate so a fast stream overlaps itself instead of cutting itself off: the
## tick is 40 ms and bolts can land 20 ms apart, so a single player would stutter.
##
## Timing runs on FightFx's presentation clock, not Time.get_ticks_msec(), so the
## headless test can step it at a fixed delta.

const PLAYER_COUNT := 6
const SEMITONE_RATIO := 1.0594630943592953    # 2 ^ (1/12)
const STREAM_PATH := "res://audio/bolt_collect.wav"

## Current rung of the ramp. 0 = the base pitch, capped at BOLT_MAX_SEMITONES.
var semitones: int = 0

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _last_collect_s: float = -1000.0
var _haptics: FightHaptics = null
var _reset_s: float = float(FightTypes.BOLT_COLLECT_RESET_MS) / 1000.0


func _ready() -> void:
	var stream: AudioStream = load(STREAM_PATH) as AudioStream
	for i in PLAYER_COUNT:
		var p := AudioStreamPlayer.new()
		p.name = "Collect%d" % i
		p.stream = stream
		p.bus = "Master"
		add_child(p)
		_players.append(p)


func bind_haptics(haptics: FightHaptics) -> void:
	_haptics = haptics


## Called once per presentation frame so the ramp expires on its own even when the
## next collect never comes (the test reads `semitones` after the stream ends).
func step(now: float) -> void:
	if semitones > 0 and now - _last_collect_s > _reset_s:
		semitones = 0


## One bolt landed. now is the presentation clock in seconds.
func play_collect(now: float) -> void:
	if now - _last_collect_s > _reset_s:
		semitones = 0
	elif semitones < FightTypes.BOLT_MAX_SEMITONES:
		semitones += 1
	_last_collect_s = now

	var p := _players[_next]
	_next = (_next + 1) % PLAYER_COUNT
	p.pitch_scale = current_pitch()
	p.play()

	if _haptics != null:
		_haptics.send("tick", now)


func current_pitch() -> float:
	return pow(SEMITONE_RATIO, float(semitones))


func stop_all() -> void:
	for p in _players:
		p.stop()


## Test seam: forget the ramp without waiting out the reset window.
func reset() -> void:
	semitones = 0
	_last_collect_s = -1000.0
