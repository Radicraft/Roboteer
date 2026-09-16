extends RefCounted
## The owner's first fight, as a driver (brief v4 §4): drive straight at the opponent and
## press the weapon whenever it is close enough to hit. Nothing else. No ring, no flank,
## no hazard sense, no self-righting.
##
## It exists to be the yardstick the Scrapyard tier is set against: a tier the owner's
## thumb cannot beat on its first night is not the first tier of a career, it is a wall.
## `Arena/tests/ai_test.gd` fights it against every tier and the acceptance bar is that it
## beats Scrapyard in at least 60 of 100 seeded fights.
##
## TEST ONLY. fight.gd never builds one, and it draws no random numbers at all, so it can
## be dropped into a seeded sweep without moving the shared stream one number.

## Chassis centre to chassis centre. The bots are 0.9 m long, so this is contact.
const CONTACT_M := 0.95
## The same tap cooldown OpponentAI gives a one shot weapon: a novice mashes the button,
## the machine still only fires as fast as it can fire.
const FIRE_COOLDOWN_TICKS := 48

var _fire_ready_tick: int = 0


## One tick of thought, such as it is. Same signature as OpponentAI.think.
func think(me: Object, foe: Object, ctx: Dictionary) -> Dictionary:
	if me == null or foe == null:
		return FightTypes.empty_input()
	var tick := int(ctx.get("tick", 0))
	var my_position := _position(me)
	var foe_position := _position(foe)
	var to_foe := Vector3(foe_position.x - my_position.x, 0.0, foe_position.z - my_position.z)
	var range_m := to_foe.length()
	var heading := Vector2.ZERO
	if range_m > 0.0001:
		heading = Vector2(to_foe.x, to_foe.z).normalized()

	var fire := false
	if range_m <= CONTACT_M and tick >= _fire_ready_tick:
		fire = true
		_fire_ready_tick = tick + FIRE_COOLDOWN_TICKS

	return {"heading": heading, "fire": fire, "secondary": false}


func _position(bot: Object) -> Vector3:
	var chassis: Object = bot.get("chassis")
	if chassis == null:
		return Vector3.ZERO
	return (chassis as Node3D).global_position
