extends RigidBody3D
## One brick of a breakable wall (agent E6, docs/stage6-spec.md §1, Wall Smash).
##
## It is the armour plate's trick with a different owner. A plate is welded to the chassis
## with a locked `Generic6DOFJoint3D` (`Bot.weld`) and `BotPart._integrate_forces` reads
## the contacts inside the step; when the plate is finished the joint is freed and the
## plate becomes debris. A brick is welded to its wall's anchor the same way, reads its
## contacts the same way, and pops the same joint. There is no condition model: a brick is
## either in the wall or out of it.
##
## WHAT IS MEASURED, AND WHY IT IS NOT THE RAW CONTACT IMPULSE. The first version of this
## did what `BotPart` does: sum `get_contact_impulse` per collider and compare the total
## against a threshold. MEASURED, it does not work here, and the reason is worth keeping.
## A brick is welded to a STATIC anchor, so the joint absorbs the blow and the contact only
## has to stop the machine's penetration a little at a time. A full speed ram (2.87 m/s
## into the wall) reported a peak of 0.86 N s per step on the brick and 6.1 N s on the
## machine's own worst part, spread over about twenty steps, and a machine STALLED against
## the wall at full throttle reported the same 0.86. The number that distinguishes a ram
## from a lean is therefore not the contact impulse, it is the CLOSING SPEED: 2.87 m/s
## against 0.00 m/s, which is not a close call.
##
## So what is read here is the momentum the wall is being asked to absorb: the closing
## speed along the contact normal times the mass of the machine behind it (its whole mass,
## not the plate that happens to touch first, because the whole machine is what has to be
## stopped). That is still an impulse in newton seconds, still read inside
## `_integrate_forces`, and it makes the event say what it should: bring weight, and bring
## it up to speed.
##
## Nothing is mutated here. `_integrate_forces` runs inside the solver, so freeing a joint
## from it is not safe; the brick raises a flag and `wall_smash.gd` acts on it from its own
## `_physics_process`, which is the discipline `BotPart` follows too.

## Newton seconds of arriving momentum. Read off `wall_smash.gd`.
var break_impulse: float = 120.0
## Set inside the step, cleared by the arena when it has popped the joint.
var pending_break: bool = false
var broken: bool = false
## Biggest arriving momentum ever seen, for the test's "why did that not break" line.
var peak_impulse: float = 0.0
## Biggest raw contact impulse ever seen. Diagnostic only: see the note above for why it
## is not what the brick breaks on.
var peak_contact: float = 0.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if broken or pending_break:
		return
	var count := state.get_contact_count()
	if count == 0:
		return
	var mine := state.linear_velocity
	for i in range(count):
		peak_contact = maxf(peak_contact, state.get_contact_impulse(i).length())
		var other := state.get_contact_collider_object(i)
		if other == null:
			continue
		# Along the normal only, so a machine sliding ALONG the face does not count as
		# hitting it. `absf` because the normal's sign depends on which body the solver
		# listed first, and a contact that is separating at speed is a contact something
		# else has already thrown, which is a hit as far as the wall is concerned.
		var closing := absf(
			(state.get_contact_collider_velocity_at_position(i) - mine)
				.dot(state.get_contact_local_normal(i)))
		var arriving := closing * _striker_mass(other)
		peak_impulse = maxf(peak_impulse, arriving)
		if arriving >= break_impulse:
			pending_break = true
			return


## How much machine is behind this contact. A `BotPart` answers for its whole bot, because
## a front plate on a 100 kg machine is 100 kg arriving, not 3 kg. Anything else answers
## for itself, which is what a brick thrown by an earlier hit weighs.
func _striker_mass(other: Object) -> float:
	if other is BotPart:
		var part: BotPart = other
		if part.owner_bot != null and part.owner_bot.has_method("total_mass"):
			return maxf(float(part.owner_bot.call("total_mass")), part.mass)
		return part.mass
	if other is RigidBody3D:
		return (other as RigidBody3D).mass
	return 0.0
