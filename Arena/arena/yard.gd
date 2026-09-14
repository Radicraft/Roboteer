class_name Yard extends ArenaBase
## The Yard (docs/stage3-spec.md §5, brief §7 arena 1): a 10 x 10 m floor, four low walls
## with a chevron strip, a central spike patch on a physics-tick timer, an out-of-arena
## sensor and the two spawn markers. The tutorial arena: one hazard, in the middle, where
## it cannot be avoided by accident and cannot be fallen into by surprise.
##
## Everything it is built from now lives in ArenaBase, which the other five arenas share
## (docs/stage5-arenas-notes.md). The Yard's own content is the marking scheme, the cold
## grey tint and the one spike patch below. Behaviour is unchanged from Stage 3: same
## floor, same walls, same spawn marks, same spike cadence and the same seeded phase.
##
## The camera is NOT here (agent C owns the rig).

## Kept as the Yard's own names so a reader of the Stage 3 spec finds them where the spec
## says they are; the values live in ArenaBase because the Coliseum uses the same patch.
const SPIKE_PATCH_SIZE := ArenaBase.SPIKE_PATCH


func arena_id() -> String:
	return "yard"


func _configure() -> void:
	# The Yard IS the render tuning the owner passed: everything else is measured against
	# it (docs/graphics-render-notes.md), so it takes the profile defaults unchanged.
	_arena_size = FightTypes.ARENA_SIZE
	_wall_height = FightTypes.WALL_HEIGHT
	_grid_enabled = true


func _build_hazards() -> void:
	_add_spike_patch(Vector3.ZERO, SPIKE_PATCH_SIZE)


func _physics_process(_delta: float) -> void:
	_tick_spikes()
	_ticks += 1
