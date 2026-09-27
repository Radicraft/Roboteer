extends RefCounted
class_name ReplayRecorder
## Records the player's input record once per physics tick, and plays one back.
##
## Spec §7: the record is `[tick, heading.x, heading.y, fire 0/1, secondary 0/1, turn, boost 0/1]`
## (FightTypes.replay_row). The AI's input is never logged; it is regenerated from the
## seed on replay, which is why the AI may only draw from the shared RNG.
##
## Playback is what makes `Arena/tests/determinism_test.gd` possible: the same scripted
## rows are fed to the same fixture twice and both runs must agree at tick 1800.

var rows: Array = []

var _playback: Array = []
var _playback_by_tick: Dictionary = {}
var _playing: bool = false


func is_playing() -> bool:
	return _playing


## Append this tick's input record. Called every FIGHTING tick, including idle ticks,
## so the row index and the tick number stay in step.
func record(tick: int, input_record: Dictionary) -> void:
	rows.append(FightTypes.replay_row(tick, input_record))


## Switch to playback. `input_rows` is a list of FightTypes.replay_row rows; ticks that
## are not in the list produce an empty input, so a sparse script is legal.
func play(input_rows: Array) -> void:
	_playback = input_rows
	_playback_by_tick.clear()
	for row_variant in input_rows:
		var row: Array = row_variant as Array
		if row.size() >= 5:
			_playback_by_tick[int(row[0])] = row
	_playing = true


func stop() -> void:
	_playing = false
	_playback.clear()
	_playback_by_tick.clear()


## The input record for this tick during playback. Returns an empty input when the
## script does not cover the tick. Never call this when is_playing() is false.
func input_for(tick: int) -> Dictionary:
	if not _playing or not _playback_by_tick.has(tick):
		return FightTypes.empty_input()
	var row: Array = _playback_by_tick[tick] as Array
	return {
		"heading": Vector2(float(row[1]), float(row[2])),
		"fire": int(row[3]) != 0,
		"secondary": int(row[4]) != 0,
		# Rows recorded before the turn column existed are five wide and pivot none.
		"turn": float(row[5]) if row.size() > 5 else 0.0,
		# Rows recorded before the boost (wave B pacing, 2026-09-27) are six wide and boost never.
		"boost": int(row[6]) != 0 if row.size() > 6 else false,
	}


## The recorded rows for FightResult.replay.inputs.
func to_inputs() -> Array:
	return rows


func clear() -> void:
	rows.clear()
