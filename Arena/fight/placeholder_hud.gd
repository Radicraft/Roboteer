extends CanvasLayer
## Placeholder HUD, live only until agent C's `res://ui/hud.tscn` lands (fight.gd swaps the
## real scene in over this holder). It exists so the desktop QA window shows the countdown,
## the timer, the knockout count and the result banner while the rest of Stage 3 is built.
## Plain sentences, no em dashes.

@onready var _label: Label = $Label

var _countdown := ""
var _timer := ""
var _scrap := ""
var _ko := ""
var _height := ""
var _result := ""
var _names := ""


func set_safe_area(_safe_area_px: Dictionary) -> void:
	pass


func show_countdown(step: String) -> void:
	_countdown = step
	_redraw()


func hide_countdown() -> void:
	_countdown = ""
	_redraw()


func set_time_left(seconds_left: float) -> void:
	var whole := int(ceil(maxf(0.0, seconds_left)))
	_timer = "%d:%02d" % [whole / 60, whole % 60]
	_redraw()


func set_scrap(total: int) -> void:
	_scrap = "SCRAP %d" % total
	_redraw()


func bump(_amount: int) -> void:
	pass


func show_ko_count(seconds_left: int, bot_name: String) -> void:
	_ko = "KNOCKOUT COUNT %d on %s" % [seconds_left, bot_name]
	_redraw()


func hide_ko_count() -> void:
	_ko = ""
	_redraw()


func set_bot_names(player: String, opponent: String) -> void:
	_names = "%s versus %s" % [player, opponent]
	_redraw()


func set_height_readout(text: String) -> void:
	_height = text
	_redraw()


func show_result(banner: String, winner: String) -> void:
	_result = "%s\n%s" % [banner, winner]
	_redraw()


func _redraw() -> void:
	if _label == null:
		return
	var lines: Array[String] = []
	for part in [_names, _result, _countdown, _timer, _scrap, _ko, _height]:
		if str(part) != "":
			lines.append(str(part))
	_label.text = "\n".join(lines)
