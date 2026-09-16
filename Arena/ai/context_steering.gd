extends RefCounted
class_name ContextSteering
## Context steering (Andrew Fray, GDC 2015 "Context Steering: Behaviour-Driven Steering at
## the Macro Scale"; the Godot recipe at kidscancode.org/godot_recipes/3.x/ai/context_map/).
##
## The idea, in one paragraph. Instead of a stack of steering FORCES that get summed (and
## which cancel each other out exactly when they matter most: "go left round the hazard"
## plus "go right round the hazard" averages to "drive into the hazard"), the driver keeps
## two small arrays indexed by direction. The INTEREST map says how much it wants to go
## each way. The DANGER map says how much that way would hurt. Interest is then masked by
## danger and the best surviving slot is taken. A direction that is wanted and safe wins;
## a direction that is wanted and lethal is not softened, it is REMOVED.
##
## That is the whole of why this file exists. The wave G driver steered by summing a
## "toward the opponent" vector with an "away from the hazard" vector, and on the phone
## the owner watched it drive into the spikes: a 1.0 long approach vector against a 0.6
## long avoid vector is still a 0.4 long approach vector, and the machine went in. Masking
## cannot do that. Whatever the interest says, a slot the danger map has condemned is not
## on the list the driver chooses from.
##
## PURE. Nothing here holds state, reads a clock or touches an rng, so every function is
## a deterministic function of its arguments and `Arena/tests/ai_test.gd` unit-tests them
## one at a time. The driver (`opponent_ai.gd`) owns all the state, including the
## smoothing memory it passes back in.
##
## Frame convention, the same one OpponentAI uses: directions are FLAT world Vector3s
## (x, 0, z), and `heading_from_world_dir` maps one to the (x, z) stick heading the bots
## consume.

## Sixteen slots: 22.5 degrees apart. Fray uses anything from 8 to 32; 8 is visibly
## faceted on a machine that turns as fast as these do, and 32 costs twice the work for a
## difference nothing on a phone can see. The chosen heading is INTERPOLATED between the
## winning slot and its neighbour rather than being the winning slot's own direction, so
## the output is continuous: sixteen slots quantise the decision, not the steering.
const SLOTS := 16
## The best a cosine interest lobe can score when its peak falls exactly between two
## slots. Dividing by it makes a clean, unobstructed run come out at full throttle
## instead of at 0.98, so "drive at them" means 1.0 and nothing has to be fudged later.
const SLOT_PEAK := 0.98078528     # cos(PI / 16)

## How much worse than the safest slot a slot may be and still be chosen from. Small, so
## danger really does mask rather than merely discourage; not zero, so a floor of uniform
## danger (standing on top of a hazard, where every direction scores the same) leaves the
## interest map free to decide instead of collapsing to one arbitrary slot.
const DANGER_CUTOFF := 0.05

## How much last tick's direction is worth when two slots score the same. Small enough to
## settle ties and nothing else; large enough that a driver keeps the side of an obstacle
## it has already chosen instead of oscillating across its nose.
const TIE_BIAS := 0.02

## Default size of the thing a `danger_positions()` entry stands for, and how far outside
## it the driver starts to care. The arenas publish danger as bare points with no radius
## (see docs/wave-f-f4-notes.md), so this is one number for a spike patch (1.6 m square),
## a grinder disc (0.55 m), a ram head and a flame jet mouth. It is deliberately the
## generous end of that range: a berth too wide reads as a driver respecting the hazard,
## a berth too narrow reads as the bug the owner reported.
const DANGER_RADIUS_M := 0.95
const DANGER_FALLOFF_M := 0.85

## What a hazard BEHIND a probe is worth.
##
## The one subtlety in this file, and it was measured twice. Scoring every slot by its
## closest approach saturates: a machine inside a hazard's radius scores 1.0 in every
## direction, every slot ties, the mask does nothing, and the driver has no opinion at the
## exact moment it most needs one. So a probe that leads AWAY from the hazard (the hazard
## is behind the direction, not along it) is scored on how near the thing is right now and
## discounted by this, while a probe that leads toward it is scored in full on how near it
## would take us. The map therefore still points out of a hazard the machine is sitting
## on, and "driving at it" is never confused with "driving away from it".
const RETREAT_WEIGHT := 0.5

## Danger at or above this is not a trade, it is a wall. The graded fallback below may
## choose the least bad of several risky ways, but it may never choose one of these, at any
## throttle, for any reason. MEASURED 2026-09-16: without this line a driver whose
## opponent was standing beyond the Yard's spike patch crept toward it at a third throttle
## -- the fallback traded a full-strength hazard against a strong wish to attack and the
## wish won -- and was still inside the patch when the spikes came up. A machine may be
## late, wide, hesitant or timid. It may not drive into a grinder.
const HARD_DANGER := 0.9

## The slowest a driver goes when everything it wants is condemned and it is picking its
## way round. Below this a machine creeps, which reads as stuck rather than as careful,
## and on a real drive it would barely overcome the floor.
const FALLBACK_MIN_THROTTLE := 0.45


## The unit direction of slot `i`. Slot 0 is +X (the bots' nose convention), and the
## slots run anticlockwise in the x/z plane.
static func slot_direction(i: int) -> Vector3:
	var angle := TAU * float(i) / float(SLOTS)
	return Vector3(cos(angle), 0.0, sin(angle))


## An empty map. Both maps are plain float arrays indexed by slot.
static func new_map() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SLOTS)
	out.fill(0.0)
	return out


# ---------------------------------------------------------------- interest

## "I want to go this way." A cosine lobe centred on `want`, which is the recipe's dot
## product: 1.0 dead ahead of the wanted direction, 0 at ninety degrees, nothing behind.
##
## `sharpness` narrows the lobe (2.0 is a noticeably more single-minded driver, 1.0 the
## recipe's own). `weight` is the intent's priority; the driver only ever runs one intent
## at a time, so in practice it is the throttle this intent asks for.
static func add_interest(map: PackedFloat32Array, want: Vector3, weight: float = 1.0,
		sharpness: float = 1.0) -> void:
	var flat := Vector3(want.x, 0.0, want.z)
	if flat.length() < 0.0001 or weight <= 0.0:
		return
	var dir := flat.normalized()
	for i in SLOTS:
		var lobe := maxf(slot_direction(i).dot(dir), 0.0)
		if sharpness != 1.0:
			lobe = pow(lobe, sharpness)
		map[i] = maxf(map[i], lobe * weight)


# ---------------------------------------------------------------- danger

## A hazard, a house bot, a pit: something at a point that must not be driven into.
##
## The measure is HOW CLOSE THIS SLOT WOULD TAKE US, not how close the thing is now: for
## each slot we probe `lookahead_m` along it and take the nearest the probe gets to the
## point. So a hazard two metres to our left condemns the slots that lead left and leaves
## the rest alone, which is the difference between a driver that gives a hazard a berth
## and a driver that freezes whenever one is on the floor.
##
## `lookahead_m` is the tier's danger lookahead in seconds turned into metres, floored by
## the driver at one metre so that a hazard already at arm's length is full danger at
## every tier, Scrapyard included. That floor is the owner's verdict in one constant.
static func add_point_danger(map: PackedFloat32Array, origin: Vector3, point: Vector3,
		lookahead_m: float, weight: float = 1.0,
		radius: float = DANGER_RADIUS_M, falloff: float = DANGER_FALLOFF_M) -> void:
	if weight <= 0.0 or lookahead_m <= 0.0:
		return
	var to_point := Vector3(point.x - origin.x, 0.0, point.z - origin.z)
	# Nothing within a probe's reach of the arena's diagonal can matter; skip early rather
	# than run sixteen closest-approach tests on a hazard on the far wall.
	if to_point.length() > lookahead_m + radius + falloff:
		return
	var here := _proximity(to_point.length(), radius, falloff) * RETREAT_WEIGHT
	for i in SLOTS:
		var dir := slot_direction(i)
		var raw := to_point.dot(dir)
		if raw <= 0.0:
			# This way leads away from it. All that is left is how near it is now, which
			# is still worth something when it is under the machine's nose.
			map[i] = maxf(map[i], here * weight)
			continue
		var along := minf(raw, lookahead_m)
		var closest := _proximity((to_point - dir * along).length(), radius, falloff)
		var ending := _proximity((to_point - dir * lookahead_m).length(), radius, falloff)
		map[i] = maxf(map[i], maxf(closest, ending) * weight)


## A cone of danger in front of a machine: the arc its weapon sweeps. Used when the
## driver's intent is anything other than "go and hit them", so it holds its ring and
## circles OUTSIDE the business end rather than through it.
static func add_arc_danger(map: PackedFloat32Array, origin: Vector3, at: Vector3,
		facing: Vector3, reach: float, lookahead_m: float, weight: float = 1.0) -> void:
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length() < 0.0001:
		return
	# The arc as one point a little way off their nose: cheap, and at these ranges a cone
	# half a machine long is a circle of about the same size.
	var mouth := at + flat.normalized() * maxf(reach, 0.35)
	add_point_danger(map, origin, mouth, lookahead_m, weight, maxf(reach, 0.35) + 0.35, 0.6)


## The walls of a square arena centred on the origin. The measure is the distance from
## `origin` to the wall ALONG each slot, so a machine a metre off the north wall condemns
## north and keeps east, west and south, which is what "run along the wall, do not nose
## into it" looks like from the stands.
##
## Distance falloff, not a hard band: at the centre of the floor this adds nothing at all.
static func add_wall_danger(map: PackedFloat32Array, origin: Vector3, half_extent: float,
		margin: float, weight: float = 1.0) -> void:
	if weight <= 0.0 or margin <= 0.0 or half_extent <= 0.0:
		return
	for i in SLOTS:
		var dir := slot_direction(i)
		var exit_m := _box_exit(origin, dir, half_extent)
		if exit_m >= margin:
			continue
		map[i] = maxf(map[i], clampf((margin - exit_m) / margin, 0.0, 1.0) * weight)


## A rectangle on the floor that is nobody's business to be in (the house bot's corner).
## Treated as its centre with a radius big enough to cover it, which is exact enough for
## a 2.2 m square and costs one closest-approach test instead of four.
static func add_rect_danger(map: PackedFloat32Array, origin: Vector3, rect: Rect2,
		lookahead_m: float, weight: float = 1.0) -> void:
	var centre := rect.get_center()
	var radius := maxf(rect.size.x, rect.size.y) * 0.5
	add_point_danger(map, origin, Vector3(centre.x, 0.0, centre.y), lookahead_m, weight,
		radius, DANGER_FALLOFF_M)


# ---------------------------------------------------------------- the choice

## Mask, then choose. Returns a flat world direction whose LENGTH is the throttle this
## steering asks for (0 when there is nothing worth driving at).
##
## 1. Find the safest slot's danger. Everything within DANGER_CUTOFF of it is eligible;
##    everything else is struck out, however much the interest map wanted it.
## 2. Take the BEST eligible slot and read the peak off it and its better eligible
##    neighbour. Not a sum over every eligible slot: when a danger cone is struck out of
##    the middle of an interest lobe the survivors are symmetric about it, they sum back
##    to the direction that was just condemned, and the driver goes straight into the
##    thing it was avoiding. (Measured: a Championship driver drove at a house bot it had
##    a wider berth of than a Regional driver, because its wider berth made the mask more
##    symmetric.) Interpolating between two neighbouring slots keeps the output continuous
##    -- a machine steering, not a machine snapping between sixteen facets -- without ever
##    averaging across the hole.
## 3. The throttle is the best eligible interest, normalised by SLOT_PEAK.
##
## `bias` is last tick's direction. It settles ties, which matters: two ways round an
## obstacle usually score exactly the same, and a driver that picks by slot index picks
## the same side of everything forever, while a driver that picks the side it is already
## going keeps its line. Deterministic either way, and this one looks like driving.
##
## When every slot is condemned equally (standing on a hazard, boxed into a corner) step
## one leaves them all eligible and the interest map decides, which is correct: the escape
## intent is already pointing out.
static func choose(interest: PackedFloat32Array, danger: PackedFloat32Array,
		bias: Vector3 = Vector3.ZERO) -> Vector3:
	var lowest := INF
	for i in SLOTS:
		lowest = minf(lowest, danger[i])
	if lowest == INF:
		return Vector3.ZERO
	var cutoff := lowest + DANGER_CUTOFF
	var flat_bias := Vector3(bias.x, 0.0, bias.z)
	if flat_bias.length() > 0.0001:
		flat_bias = flat_bias.normalized()
	else:
		flat_bias = Vector3.ZERO

	var best := -1
	var best_score := 0.0
	for i in SLOTS:
		if danger[i] > cutoff or interest[i] <= 0.0:
			continue
		var score := interest[i] * (1.0 + TIE_BIAS * slot_direction(i).dot(flat_bias))
		if best < 0 or score > best_score:
			best = i
			best_score = score
	if best < 0:
		# Everything this driver wants is condemned. Do NOT fall through to the safest slot
		# on the compass: that is usually straight backwards, and a machine that reverses
		# away from a hazard it was never going to reach reads as frightened, not careful.
		# Take the least dangerous of the directions it actually wanted instead, and let
		# the throttle (below) say how gingerly. This is Fray's subtractive fallback.
		for i in SLOTS:
			if interest[i] <= 0.0 or danger[i] >= HARD_DANGER:
				continue
			var graded := interest[i] * (1.0 - danger[i])
			if best < 0 or graded > best_score:
				best = i
				best_score = graded
		if best < 0 or best_score <= 0.0:
			# It wants nothing at all. Move off the danger if there is any, else stand.
			var safest := 0
			for i in SLOTS:
				if danger[i] < danger[safest]:
					safest = i
			return slot_direction(safest) * 0.6 if lowest > DANGER_CUTOFF else Vector3.ZERO
		return slot_direction(best) \
			* clampf(maxf(best_score, FALLBACK_MIN_THROTTLE), 0.0, 1.0)

	return _interpolate(interest, danger, cutoff, best) \
		* clampf(interest[best] / SLOT_PEAK, 0.0, 1.0)


## Where between the winning slot and its better eligible neighbour the interest actually
## peaked. The interest map is a cosine lobe, so two samples pin the peak EXACTLY:
## with i0 = w cos(d) and i1 = w cos(step - d), d = atan2((i1 - cos(step) i0) / sin(step), i0).
## Sixteen slots therefore quantise the decision and not the steering, and an unobstructed
## driver goes exactly where it meant to rather than up to eleven degrees beside it.
static func _interpolate(interest: PackedFloat32Array, danger: PackedFloat32Array,
		cutoff: float, best: int) -> Vector3:
	var step := TAU / float(SLOTS)
	var left := (best - 1 + SLOTS) % SLOTS
	var right := (best + 1) % SLOTS
	var i_left := interest[left] if danger[left] <= cutoff else 0.0
	var i_right := interest[right] if danger[right] <= cutoff else 0.0
	var neighbour := maxf(i_left, i_right)
	var towards_right := i_right >= i_left
	if neighbour <= 0.0 or interest[best] <= 0.0:
		return slot_direction(best)
	var offset := atan2((neighbour - cos(step) * interest[best]) / sin(step), interest[best])
	offset = clampf(offset, 0.0, step)
	# Slot index rises with the angle in the x/z plane, which is a NEGATIVE rotation about
	# UP in Godot's frame: rotating +X about +Y sends it toward -Z, not +Z.
	return slot_direction(best).rotated(Vector3.UP, -offset if towards_right else offset)


## Ease this tick's choice toward the last one so the machine reads as a driver turning a
## wheel rather than an array being re-evaluated sixty times a second. `alpha` is the
## fraction of the new heading taken each tick; `ready` is false on the first tick of a
## fight, when there is no previous heading to ease from and easing from zero would look
## like a machine that will not pull away.
static func smooth(previous: Vector2, wanted: Vector2, alpha: float,
		ready: bool) -> Vector2:
	if not ready:
		return wanted
	var out := previous.lerp(wanted, clampf(alpha, 0.0, 1.0))
	return out if out.length() <= 1.0 else out.normalized()


# ---------------------------------------------------------------- geometry

## 1.0 inside `radius`, tapering to 0 at `radius + falloff`.
static func _proximity(gap: float, radius: float, falloff: float) -> float:
	if gap <= radius:
		return 1.0
	if falloff <= 0.0:
		return 0.0
	return clampf(1.0 - (gap - radius) / falloff, 0.0, 1.0)


## How far a ray from `origin` along `dir` travels before it leaves a square of half
## extent `half` centred on the origin of the world. A point already outside the square
## reads as zero, which is the cautious answer.
static func _box_exit(origin: Vector3, dir: Vector3, half: float) -> float:
	var best := INF
	for pair in [[origin.x, dir.x], [origin.z, dir.z]]:
		var o := float(pair[0])
		var d := float(pair[1])
		if absf(d) < 0.0001:
			if absf(o) > half:
				return 0.0
			continue
		var edge := half * signf(d)
		var t := (edge - o) / d
		if t < 0.0:
			return 0.0
		best = minf(best, t)
	return 0.0 if best == INF else maxf(best, 0.0)
