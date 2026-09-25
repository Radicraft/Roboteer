extends DriveBase
## 2WD: two driven wheels at the back, light and fast. Lose one and the bot can
## only circle, which falls out of the model rather than being special cased: one
## side has no wheel, so that side's speed is whatever the floor gives it.
##
## THE FRONT SKID. Two wheels at the back leave the front of the hull on the floor, and
## at the hull's own friction that nose was a brake: 1.0 to 1.9 s to 90 % of top speed,
## 0.4 to 0.5 m of drift over 7 m, a 4 cm lip it could not cross and a wall it could
## not back off (systems gauntlet D4). A real 2WD rides its nose on a skid or a caster,
## so the hull's own material is swapped for a slippery one. Everything else about the
## hull (plates, weapon, how it is hit) is unchanged.

const SKID_FRICTION := 0.08


func build() -> void:
	super.build()
	var chassis: RigidBody3D = bot.chassis
	if chassis == null:
		return
	var skid := PhysicsMaterial.new()
	var old := chassis.physics_material_override
	skid.bounce = old.bounce if old != null else 0.0
	skid.friction = SKID_FRICTION
	chassis.physics_material_override = skid

