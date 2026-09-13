extends SceneTree
## Main-session probe (skipped by test-arena.sh): AI vs AI for N seconds, print feel metrics.

var fight: Node
var scrap_events := 0
var scrap_total := 0
var damage_events := 0
var fires := [0, 0]
var max_height := [0.0, 0.0]
var airborne_ticks := [0, 0]
var contact_ticks := 0
var min_dist := 99.0
var max_speed := [0.0, 0.0]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://fight/fight.tscn")
	fight = packed.instantiate()
	root.add_child(fight)
	await process_frame
	var cfg_text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
	var config: Dictionary = JSON.parse_string(cfg_text)
	var args := OS.get_cmdline_user_args()
	var pai := "normal"
	var oai := "normal"
	var secs := 45
	for a in args:
		if a.begins_with("--pai="): pai = a.substr(6)
		if a.begins_with("--oai="): oai = a.substr(6)
		if a.begins_with("--secs="): secs = int(a.substr(7))
	config["debug"] = {"opponent_ai": oai, "player_ai": pai}
	fight.scrap_awarded.connect(func(_id, amount, _pos): scrap_events += 1; scrap_total += amount)
	fight.start_fight(config)
	await process_frame
	var bots: Array = fight.get("_bots")
	for i in range(2):
		var b = bots[i]
		if b == null:
			print("no bot ", i); quit(1); return
		b.damage_event.connect(func(_info): damage_events += 1)
		b.weapon_fired.connect(func(): fires[i] += 1)
	var ticks := secs * 60 + 200
	for t in range(ticks):
		await physics_frame
		var p := []
		for i in range(2):
			var ch: RigidBody3D = bots[i].chassis
			p.append(ch.global_position)
			max_height[i] = maxf(max_height[i], ch.global_position.y)
			if ch.global_position.y > 0.45:
				airborne_ticks[i] += 1
			max_speed[i] = maxf(max_speed[i], ch.linear_velocity.length())
		var d: float = p[0].distance_to(p[1])
		min_dist = minf(min_dist, d)
		if d < 1.0:
			contact_ticks += 1
		if fight.get("state") == 3:
			print("RESULT at tick ", t)
			break
	print("--- feel probe (pai=%s oai=%s, %d s) ---" % [pai, oai, secs])
	print("fires player/opp: ", fires, "  damage_events: ", damage_events, "  scrap events/total: ", scrap_events, "/", scrap_total)
	print("max chassis height: ", max_height, "  airborne ticks (>0.45m): ", airborne_ticks)
	print("ticks within 1 m: ", contact_ticks, "  min distance: ", min_dist, "  max speed: ", max_speed)
	print("gas left: ", [bots[0].gas_charges, bots[1].gas_charges], "  condition p: ", bots[0].condition())
	print("condition o: ", bots[1].condition())
	quit(0)
