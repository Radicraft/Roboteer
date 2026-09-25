extends SceneTree
## Headless test for the house bot and its corner zone (brief v4 §3, agent G2).
##   Godot --headless --path Arena --script tests/enforcer_test.gd
##
## Six things are proved here, because six things are new:
##   1. the corner zone's geometry and its three states
##   2. zone mode puts the house bot on its mark at the countdown, and a machine that
##      enters the corner is attacked until it leaves plus two seconds
##   3. "idle_only" is the Stage 5 behaviour and nothing else, so the fights that ask for
##      it see exactly what they always saw
##   4. at the endgame the stripes go red and it hunts the more damaged machine
##   5. it never scores: not a tally, not a scrap bolt, and what it does is credited to
##      whoever put the victim in front of it
##   6. `enforcer_speed` 0.5 halves the drive and halves the turn
##
## The clock is set by hand rather than waited out, exactly as `rules_test.gd` does: every
## rule here is a rule about elapsed fight time, and a test that took three minutes to
## prove it would never be run.

const CornerZoneScript := preload("res://arena/corner_zone.gd")
const Rules := preload("res://fight/rules.gd")

const DT := 1.0 / 60.0

var _failures := 0
var _checks := 0
## `fight.gd` is loaded, never preloaded: it names the Bridge autoload, which does not
## exist yet while this script is being compiled.
var _fight_script: GDScript = null


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_zone_geometry()
	_test_zone_states()
	_test_speed_limiter()
	await _test_zone_mode()
	await _test_idle_only()
	await _test_endgame_release()
	await _test_opener_release()
	await _test_never_scores()
	await _test_hud_warning()
	_finish()


# ---------------------------------------------------------------- 1. the zone itself

func _test_zone_geometry() -> void:
	var half := FightTypes.ARENA_SIZE * 0.5
	var corner := Vector3(half - 0.7, 0.25, -(half - 0.7))     # fight.gd's _gate_position()
	var rect: Rect2 = CornerZoneScript.rect_in_corner(corner, half)

	_check(is_equal_approx(rect.size.x, CornerZoneScript.SIDE_M)
			and is_equal_approx(rect.size.y, CornerZoneScript.SIDE_M),
		"the corner zone is %0.1f m square (%s)" % [CornerZoneScript.SIDE_M, str(rect.size)])
	var inset := CornerZoneScript.WALL_INSET_M
	_check(is_equal_approx(rect.end.x, half - inset),
		"held %0.1f m off the +X wall (right edge at %0.3f)" % [inset, rect.end.x])
	_check(is_equal_approx(rect.position.y, -(half - inset)),
		"held %0.1f m off the -Z wall (far edge at %0.3f)" % [inset, rect.position.y])
	_check(rect.has_point(Vector2(corner.x, corner.z)),
		"and it covers the corner the gate logic already uses")

	var zone: Node3D = CornerZoneScript.new()
	zone.call("configure", rect, CornerZoneScript.COL_IDLE)
	root.add_child(zone)

	_check(bool(zone.call("contains", Vector3(rect.get_center().x, 0.25, rect.get_center().y))),
		"the middle of the square is inside the zone")
	_check(not bool(zone.call("contains", Vector3(0.0, 0.25, 0.0))),
		"the middle of the arena is not")
	_check(not bool(zone.call("contains", Vector3(-corner.x, 0.25, -corner.z))),
		"and neither is the opposite corner")
	_check(bool(zone.call("contains", Vector3(rect.get_center().x, 3.0, rect.get_center().y))),
		"a machine thrown over the corner is still in the corner")
	var mark: Vector3 = zone.call("centre", 0.25)
	_check(is_equal_approx(mark.x, rect.get_center().x) and is_equal_approx(mark.z, rect.get_center().y),
		"the mark is the middle of the square (%s)" % str(mark))
	var same: Rect2 = zone.call("zone_rect")
	_check(same == rect, "zone_rect() gives back the floor rectangle in metres")

	root.remove_child(zone)
	zone.queue_free()


func _test_zone_states() -> void:
	var zone: Node3D = CornerZoneScript.new()
	zone.call("configure", Rect2(Vector2(2.5, -4.7), Vector2(2.2, 2.2)), CornerZoneScript.COL_IDLE)
	root.add_child(zone)

	_check(str(zone.call("zone_state")) == CornerZoneScript.STATE_IDLE, "the zone starts idle")
	var idle: Color = zone.call("marking_colour")
	zone.call("set_zone_state", CornerZoneScript.STATE_ALERT)
	_check(str(zone.call("zone_state")) == CornerZoneScript.STATE_ALERT, "it can go to alert")
	_check(zone.call("marking_colour") != idle, "and the marking changes colour with it")
	zone.call("set_zone_state", CornerZoneScript.STATE_RELEASED)
	var released: Color = zone.call("marking_colour")
	_check(released.r > released.g * 2.0 and released.r > released.b * 2.0,
		"released is red (%s)" % str(released))
	zone.call("set_zone_state", "nonsense")
	_check(str(zone.call("zone_state")) == CornerZoneScript.STATE_RELEASED,
		"a state nobody recognises is ignored rather than fatal")

	# Drawn with plain meshes so it works on gl_compatibility as well as Forward+.
	_check(bool(zone.call("is_built")), "the marking is built")
	var meshes := 0
	var non_mesh := 0
	for child in zone.get_children():
		if child is MeshInstance3D:
			meshes += 1
			var mi := child as MeshInstance3D
			if not (mi.mesh is BoxMesh) or not (mi.material_override is StandardMaterial3D):
				non_mesh += 1
		else:
			non_mesh += 1
	_check(meshes >= CornerZoneScript.STRIPES + 4,
		"the stripes and the frame are there (%d meshes)" % meshes)
	_check(non_mesh == 0, "and every one is a BoxMesh with a StandardMaterial3D: no shader, no decal")

	root.remove_child(zone)
	zone.queue_free()


# ---------------------------------------------------------------- 2. the speed limiter

## `rules.enforcer_speed` 0.5 (brief §10 item 1) halves the drive and halves the turn. The
## weapon is not in this function at all, which is the point: a half speed THRESHER still
## crushes at full strength when it gets to you.
func _test_speed_limiter() -> void:
	var fs := _fight()
	if fs == null:
		_check(false, "fight.gd loads")
		return
	var want := Vector2(1.0, 0.0)
	var full: Vector2 = fs.call("enforcer_heading_step", want, want, 1.0, DT)
	_check(is_equal_approx(full.length(), 1.0),
		"at speed 1.0 full stick is full stick (%0.3f)" % full.length())

	var half := Vector2.ZERO
	for i in 120:
		half = fs.call("enforcer_heading_step", half, want, 0.5, DT)
	_check(is_equal_approx(half.length(), 0.5),
		"at speed 0.5 full stick is half throttle (%0.3f)" % half.length())
	_check(half.normalized().dot(want.normalized()) > 0.999,
		"and it still ends up pointing where its driver asked")

	# The turn: from facing one way to facing the other takes twice as long at half speed.
	var reverse := Vector2(-1.0, 0.0)
	var quick := Vector2(1.0, 0.0)
	var slow := Vector2(1.0, 0.0)
	var quick_ticks := 0
	var slow_ticks := 0
	for i in 600:
		if quick.normalized().dot(reverse) < 0.999:
			quick = fs.call("enforcer_heading_step", quick, reverse, 1.0, DT)
			quick_ticks += 1
		if slow.normalized().dot(reverse) < 0.999:
			slow = fs.call("enforcer_heading_step", slow, reverse, 0.5, DT)
			slow_ticks += 1
	_check(quick_ticks > 0 and slow_ticks >= quick_ticks * 2 - 2,
		"coming about takes twice as long at half speed (%d ticks against %d)"
			% [slow_ticks, quick_ticks])
	_check(fs.call("enforcer_heading_step", want, Vector2.ZERO, 0.5, DT) == Vector2.ZERO,
		"no stick is no stick, whatever the speed")


# ---------------------------------------------------------------- 3. zone mode

## The house bot is on its mark from the countdown, the corner is marked, and a machine
## that comes into the corner is attacked until it leaves plus two seconds.
func _test_zone_mode() -> void:
	var fight := await _start_fight({"enforcer": "thresher", "enforcer_speed": 1.0})
	if fight == null:
		return

	_check(str(fight.get("_enforcer_mode")) == "zone",
		"a fight naming an enforcer guards the zone by default (%s)" % str(fight.get("_enforcer_mode")))
	var house: Node = fight.get("_enforcer")
	_check(house != null, "and the house bot is on the floor from the countdown")
	var zone: Node3D = fight.get("_zone") as Node3D
	_check(zone != null, "the corner is marked")
	if house == null or zone == null:
		_end_fight(fight)
		return
	_check(zone.get_parent() == fight.get("_arena"), "the marking is a child of the arena")
	var mark: Vector3 = fight.get("_enforcer_mark")
	_check(bool(zone.call("contains", mark)), "the mark is inside the zone")
	var chassis: Node3D = house.get("chassis") as Node3D
	if chassis != null and chassis.is_inside_tree():
		_check(chassis.global_position.distance_to(mark) < 1.0,
			"and the house bot is standing on it (%0.2f m away)"
				% chassis.global_position.distance_to(mark))

	fight.set("state", 2)                       # State.FIGHTING
	fight.set("_fight_time", 5.0)
	fight.set("_last_contact_s", 5.0)           # no lull: only the corner rule is under test

	# Idling on its mark: nothing is being chased and the stripes are the arena's own colour.
	fight.call("_tick_enforcer", DT)
	_check(int(fight.get("_zone_target")) == -1, "with the floor to itself it chases nobody")
	_check(str(zone.call("zone_state")) == "idle", "and the stripes are idle")
	# The idle pose is a turret sweep with the weapon ticking over, both off the tick count.
	var swept := false
	var ticked := false
	for tick in 360:
		fight.set("_tick", tick)
		fight.call("_tick_enforcer", DT)
		var last: Dictionary = house.get("_last_input") as Dictionary
		if absf(float(last.get("turn", 0.0))) > 0.05:
			swept = true
		if bool(last.get("fire", false)):
			ticked = true
	_check(swept, "standing on its mark it sweeps")
	_check(ticked, "and its weapon ticks over, so it reads as live rather than parked")

	# A machine comes into the corner.
	var player: Node = (fight.get("_bots") as Array)[0]
	_place(player, zone.call("centre", 0.25))
	fight.set("_fight_time", 20.0)
	fight.set("_last_contact_s", 20.0)
	fight.call("_tick_enforcer", DT)
	_check(int(fight.get("_zone_target")) == 0, "a machine in the corner is the house bot's target")
	_check(str(zone.call("zone_state")) == "alert", "and the stripes go to alert")
	_check(float(fight.get("_zone_hold_until")) > 20.0, "with a hold clock running")

	# It leaves. Inside two seconds it is still being chased.
	_place(player, Vector3(0.0, 0.25, 0.0))
	fight.set("_fight_time", 21.5)
	fight.call("_tick_enforcer", DT)
	_check(int(fight.get("_zone_target")) == 0,
		"leaving the corner does not end it: it is attacked for two seconds more")

	# Past two seconds it goes home.
	fight.set("_fight_time", 22.6)
	fight.call("_tick_enforcer", DT)
	_check(int(fight.get("_zone_target")) == -1, "two seconds after it left, the chase is over")
	_check(str(zone.call("zone_state")) == "idle", "the stripes go back to idle")
	_check(not bool(fight.get("_zone_released")), "and it has not been released: that is the endgame's job")

	# Fifteen seconds of the two of them not touching still brings it out (the Stage 5 rule).
	fight.set("_fight_time", 60.0)
	fight.set("_last_contact_s", 40.0)
	fight.call("_tick_enforcer", DT)
	_check(int(fight.get("_zone_target")) >= 0,
		"fifteen seconds without contact still brings the house bot out of its corner")

	# It cannot leave the arena: put it over the wall and it is held inside.
	var house_chassis: Node3D = house.get("chassis") as Node3D
	if house_chassis != null and house_chassis.is_inside_tree():
		house_chassis.global_position = Vector3(FightTypes.ARENA_SIZE, 0.25, -FightTypes.ARENA_SIZE)
		fight.call("_tick_enforcer", DT)
		var held := house_chassis.global_position
		_check(absf(held.x) < FightTypes.ARENA_SIZE * 0.5 and absf(held.z) < FightTypes.ARENA_SIZE * 0.5,
			"the house bot cannot leave the arena (%s)" % str(held))

	# And the AI context carries the three keys G3 reads.
	var ctx: Dictionary = fight.call("_ai_context")
	_check(ctx.has("house_bot_position") and ctx["house_bot_position"] is Vector3,
		"the AI context carries house_bot_position")
	_check(ctx.has("zone_rect") and ctx["zone_rect"] is Rect2, "and zone_rect")
	_check(ctx.has("phase") and str(ctx["phase"]) in ["open", "endgame"], "and the phase")
	_check((ctx["zone_rect"] as Rect2).size.x > 0.0, "with the corner's real rectangle in it")

	_end_fight(fight)


# ---------------------------------------------------------------- 4. idle_only

## The Stage 5 behaviour, unchanged, for the fights and the tests that ask for it.
func _test_idle_only() -> void:
	var fight := await _start_fight({"enforcer": "cinder", "enforcer_mode": "idle_only"})
	if fight == null:
		return

	_check(fight.get("_enforcer") == null, "idle_only puts nothing on the floor at the countdown")
	_check(fight.get("_zone") == null, "and marks no corner")

	fight.set("state", 2)
	fight.set("_fight_time", 14.0)
	fight.set("_last_contact_s", 0.0)
	fight.call("_tick_enforcer", DT)
	_check(fight.get("_enforcer") == null, "fourteen seconds of no contact is still not enough")

	fight.set("_fight_time", 15.5)
	fight.set("_last_contact_s", 0.0)
	fight.call("_tick_enforcer", DT)
	_check(fight.get("_enforcer") != null, "fifteen seconds of no contact still sends it in")
	_check(not bool(fight.get("_zone_released")), "and the endgame never releases what was never in a corner")

	# The endgame does nothing to it: it is not a zone guard.
	fight.set("_fight_time", FightTypes.ENDGAME_AT_S + 1.0)
	fight.call("_tick_enforcer", DT)
	_check(not bool(fight.get("_zone_released")), "idle_only is untouched by the endgame")
	_end_fight(fight)

	# "off" is off, whatever rules.enforcer says.
	var quiet := await _start_fight({"enforcer": "anvil", "enforcer_mode": "off"})
	if quiet == null:
		return
	_check(quiet.get("_enforcer") == null, "enforcer_mode off puts nothing on the floor")
	quiet.set("state", 2)
	quiet.set("_fight_time", 90.0)
	quiet.set("_last_contact_s", 0.0)
	quiet.call("_tick_enforcer", DT)
	_check(quiet.get("_enforcer") == null, "and no lull, however long, brings one out")
	_end_fight(quiet)


# ---------------------------------------------------------------- 5b. the opener's early endgame

## Wave B decision 9 (docs/wave-a-contracts.md section 6): the Series 1 opener is 120 s with
## `rules.endgame_at_s` 80, and the house bot comes out at 1:20, not at the fixed 2:00.
func _test_opener_release() -> void:
	var script := _fight()
	_check(int(script.call("endgame_ticks_for", {})) == 7200,
		"no rules.endgame_at_s keeps the endgame at 2:00 (tick 7200)")
	_check(int(script.call("endgame_ticks_for", {"endgame_at_s": 80})) == 4800,
		"endgame_at_s 80 turns the round at tick 4800")
	_check(int(script.call("endgame_ticks_for", {"endgame_at_s": "soon"})) == 7200
			and int(script.call("endgame_ticks_for", {"endgame_at_s": -5})) == 7200,
		"a nonsense endgame_at_s falls back to 2:00")

	var fight := await _start_fight({"enforcer": "bandsaw", "duration_s": 120, "endgame_at_s": 80})
	if fight == null:
		return
	_check(int(fight.call("endgame_at_ticks")) == 4800, "the opener's fight reads its 80 s mark")
	fight.set("state", 2)
	_set_clock(fight, 79.5)
	fight.set("_last_contact_s", 79.5)
	fight.call("_tick_enforcer", DT)
	_check(not bool(fight.get("_zone_released")), "at 1:19.5 the opener's house bot is still in its corner")
	_check(str(fight.call("fight_phase")) == FightTypes.PHASE_OPEN, "and the round is still open")
	_set_clock(fight, 80.0)
	fight.call("_tick_enforcer", DT)
	_check(str(fight.call("fight_phase")) == FightTypes.PHASE_ENDGAME, "at 1:20 the opener is in its endgame")
	_check(bool(fight.get("_zone_released")), "and the house bot comes out hunting")
	_end_fight(fight)


# ---------------------------------------------------------------- 5. the endgame release

func _test_endgame_release() -> void:
	var fight := await _start_fight({"enforcer": "bandsaw"})
	if fight == null:
		return
	var zone: Node3D = fight.get("_zone") as Node3D
	var bots: Array = fight.get("_bots") as Array
	if zone == null or bots[0] == null or bots[1] == null:
		_check(false, "the endgame test has a zone and two machines")
		_end_fight(fight)
		return

	fight.set("state", 2)
	_set_clock(fight, 60.0)
	fight.set("_last_contact_s", 60.0)
	fight.call("_tick_enforcer", DT)
	_check(not bool(fight.get("_zone_released")), "before two minutes it is still in its corner")

	# The opponent is the more damaged machine.
	_hurt(bots[1], 0.2)
	_check(Rules.condition_total(bots[1].call("condition"))
			< Rules.condition_total(bots[0].call("condition")),
		"the opponent is the more damaged machine")

	_set_clock(fight, FightTypes.ENDGAME_AT_S + 0.5)
	fight.call("_tick_enforcer", DT)
	_check(bool(fight.get("_zone_released")), "at the endgame the house bot is released")
	_check(str(zone.call("zone_state")) == "released", "and the stripes go red")
	_check(int(fight.get("_zone_target")) == 1, "it hunts the machine with the lower condition total")

	# It re-targets every five seconds: hurt the player worse and the choice follows.
	_hurt(bots[0], 0.5)
	_set_clock(fight, FightTypes.ENDGAME_AT_S + 1.0)
	fight.call("_tick_enforcer", DT)
	_check(int(fight.get("_zone_target")) == 1, "inside five seconds it stays on the one it picked")
	_set_clock(fight, FightTypes.ENDGAME_AT_S + 7.0)
	fight.call("_tick_enforcer", DT)
	_check(int(fight.get("_zone_target")) == 0, "five seconds later it picks again, and picks the worse one")

	# It never withdraws again: even standing in its own corner with nobody near it.
	var house: Node = fight.get("_enforcer")
	_place(house, zone.call("centre", 0.25))
	_place(bots[0], Vector3(-3.0, 0.25, 3.0))
	_place(bots[1], Vector3(-3.5, 0.25, 3.5))
	_set_clock(fight, FightTypes.ENDGAME_AT_S + 30.0)
	fight.set("_last_contact_s", FightTypes.ENDGAME_AT_S + 30.0)
	fight.call("_tick_enforcer", DT)
	_check(bool(fight.get("_zone_released")) and int(fight.get("_zone_target")) >= 0,
		"and once out it never goes home again")
	_check(str(zone.call("zone_state")) == "released", "the corner stays red for the rest of the fight")

	# Flipped, it rights itself after four seconds rather than lying there: it cannot be
	# knocked out, so a house bot on its back would just be a hole in the arena.
	var righting: float = float(_fight().get_script_constant_map().get("ZONE_RIGHT_S", 0.0))
	_check(is_equal_approx(righting, 4.0), "the self righting delay is four seconds")

	_end_fight(fight)


# ---------------------------------------------------------------- 6. it never scores

func _test_never_scores() -> void:
	var fight := await _start_fight({"enforcer": "grudge"})
	if fight == null:
		return

	_check(int(fight.call("_index_of", "enforcer-1")) == -1,
		"the house bot is not one of the scored machines")
	_check((fight.get("_scrap") as Array).size() == 2, "there are still only two scrap tallies")
	_check((fight.get("_tallies") as Array).size() == 2, "and only two judges' tallies")

	fight.set("state", 2)
	fight.set("_fight_time", 30.0)
	var ids: Array = fight.get("_bot_ids") as Array

	# Nobody touched the victim: what the house bot does is credited to nobody at all.
	fight.call("_on_damage_event", {
		"victim": str(ids[1]), "attacker": "enforcer-1", "severity": 0.4,
		"detached": false, "position": Vector3.ZERO,
	})
	var tallies: Array = fight.get("_tallies") as Array
	var scrap: Array = fight.get("_scrap") as Array
	_check(is_equal_approx(float((tallies[0] as Dictionary)["damage_removed"]), 0.0),
		"a house bot hit with no toucher scores for nobody")
	_check(int(scrap[0]) == 0 and int(scrap[1]) == 0, "and pays no scrap")

	# The player shoves the opponent into it: now the damage is the player's, exactly as a
	# hazard's is (Rules.TOUCH_CREDIT_S).
	fight.call("_on_damage_event", {
		"victim": str(ids[1]), "attacker": str(ids[0]), "severity": 0.1,
		"detached": false, "position": Vector3.ZERO,
	})
	var before := float((fight.get("_tallies") as Array)[0]["damage_removed"])
	fight.call("_on_damage_event", {
		"victim": str(ids[1]), "attacker": "enforcer-1", "severity": 0.5,
		"detached": false, "position": Vector3.ZERO,
	})
	var after := float((fight.get("_tallies") as Array)[0]["damage_removed"])
	_check(is_equal_approx(after - before, 0.5),
		"shoving the opponent into the house bot credits the shover (%0.2f)" % (after - before))

	# And the credit expires with the window: three seconds later it is nobody's again.
	fight.set("_fight_time", 40.0)
	var stale := float((fight.get("_tallies") as Array)[0]["damage_removed"])
	fight.call("_on_damage_event", {
		"victim": str(ids[1]), "attacker": "enforcer-1", "severity": 0.5,
		"detached": false, "position": Vector3.ZERO,
	})
	_check(is_equal_approx(float((fight.get("_tallies") as Array)[0]["damage_removed"]), stale),
		"past the %0.f s window it is nobody's damage" % Rules.TOUCH_CREDIT_S)

	# Nothing the house bot does can win or lose the fight: it is not in the id list, so
	# no win condition can name it.
	_check(not ("enforcer-1" in (fight.get("_bot_ids") as Array)),
		"no win condition can name the house bot")

	_end_fight(fight)


# ---------------------------------------------------------------- 7. the HUD warning

func _test_hud_warning() -> void:
	var scene: PackedScene = load("res://ui/hud.tscn")
	if scene == null:
		_check(false, "hud.tscn loads")
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(1206, 556)
	root.add_child(vp)
	var hud: FightHud = scene.instantiate() as FightHud
	vp.add_child(hud)
	await process_frame
	await process_frame

	_check(not hud.zone_warning_visible(), "the corner warning is off to begin with")
	hud.set_zone_warning(true, "THRESHER")
	for i in 30:
		hud.zone_step(DT)
	_check(hud.zone_warning_visible(), "a machine in the corner raises the warning")
	_check(hud.zone_warning_name() == "THRESHER", "and it names the house bot")

	hud.set_zone_warning(false, "THRESHER")
	for i in 60:
		hud.zone_step(DT)
	_check(not hud.zone_warning_visible(), "leaving the corner takes it away again")

	hud.show_zone_coach()
	_check(hud.zone_coach_visible(), "the coach line is shown the first time")
	for i in 400:
		hud.zone_step(DT)
	_check(not hud.zone_coach_visible(), "and it goes on its own")

	root.remove_child(vp)
	vp.queue_free()
	await process_frame


# ---------------------------------------------------------------- harness

## A fight, configured with the given rules keys over the Stage 3 fixture.
func _start_fight(rules: Dictionary) -> Node:
	if not ResourceLoader.exists("res://fight/fight.tscn"):
		_check(false, "fight.tscn exists")
		return null
	var bridge: Node = root.get_node_or_null("Bridge")
	if bridge == null:
		_check(false, "the Bridge autoload is present")
		return null
	var fight: Node = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame

	var config := _fixture_config()
	var all_rules := {"mode": "fight", "duration_s": 180, "ko_count_s": 10}
	for key in rules.keys():
		all_rules[key] = rules[key]
	config["rules"] = all_rules
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame
	await process_frame
	return fight


func _end_fight(fight: Node) -> void:
	root.remove_child(fight)
	fight.queue_free()


## Both clocks at once: the fight time the enforcer rules read, and the tick count G1's
## `fight_phase()` derives the endgame from.
func _set_clock(fight: Node, seconds: float) -> void:
	fight.set("_fight_time", seconds)
	fight.set("_tick", int(round(seconds * float(FightTypes.TICK_HZ))))


## The fight script, loaded once at runtime.
func _fight() -> GDScript:
	if _fight_script == null:
		_fight_script = load("res://fight/fight.gd") as GDScript
	return _fight_script


func _fixture_config() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


## Stand a machine somewhere, for the rules under test. The whole machine moves, joints
## and all, which is what `place_at` is for.
func _place(bot: Node, at: Vector3) -> void:
	if bot == null or not is_instance_valid(bot):
		return
	if bot.has_method("place_at"):
		bot.call("place_at", at, Vector3(1.0, 0.0, 0.0))
		return
	var chassis: Node3D = bot.get("chassis") as Node3D
	if chassis != null and chassis.is_inside_tree():
		chassis.global_position = at


## Take a machine's condition down, so one of the two is visibly worse off.
func _hurt(bot: Node, amount: float) -> void:
	var damage: Object = bot.get("damage")
	if damage == null:
		return
	var condition: Dictionary = damage.get("condition")
	condition["core"] = maxf(float(condition.get("core", 1.0)) - amount, 0.05)


func _check(passed: bool, what: String) -> void:
	_checks += 1
	if passed:
		print("PASS  ", what)
	else:
		_failures += 1
		print("FAIL  ", what)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("enforcer: %d checks, all passed" % _checks)
		quit(0)
	else:
		print("enforcer: %d checks, %d failures" % [_checks, _failures])
		quit(1)
