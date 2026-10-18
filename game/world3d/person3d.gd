class_name Person3D
extends Node3D
## A townsperson in the 3D city (D-020). Strolls along the pavements cell by cell, sometimes
## stops to chat, phone or wave, and jumps out of the way (or shouts) when a vehicle comes at them.
## Uses the rigged Meshy people and their animations (walk, run, idle, talk...).

const CELL_M := Terrain3D.CELL_M
const WALK_SPEED := 1.35
const RUN_SPEED := 4.2

enum State { WALK, PAUSE, FLEE }

var key := "walker"
var ap: AnimationPlayer
var state := State.WALK
var from := Vector2i.ZERO
var to := Vector2i.ZERO
var t := 0.0
var pause_left := 0.0
var flee_dir := Vector3.ZERO
var world # Street3D
var rng := RandomNumberGenerator.new()


func setup(lib: Models3D, k: String, w, cell: Vector2i, seed: int) -> bool:
	key = k
	world = w
	rng.seed = seed
	var got := lib.person(k, 1.62 if k in ["market_woman", "aunty_boss", "young_woman"] else 1.74)
	if got[0] == null:
		return false
	add_child(got[0])
	ap = got[1]
	Models3D.far_cull(self, 70.0)
	from = cell
	to = _next(cell, cell)
	t = rng.randf()
	position = world.cell_pos(cell)
	_anim()
	if ap and ap.current_animation != "":
		ap.seek(rng.randf() * ap.current_animation_length, true)
	return true


func _anim() -> void:
	match state:
		State.WALK:
			Models3D.play(ap, "walk", "idle")
		State.FLEE:
			Models3D.play(ap, "run", "walk", 1.1)
		State.PAUSE:
			Models3D.play(ap, ["talk", "phone", "idle", "wave", "argue"][rng.randi() % 5], "idle")


func step(delta: float) -> void:
	match state:
		State.PAUSE:
			pause_left -= delta
			if pause_left <= 0.0:
				state = State.WALK
				_anim()
		State.FLEE:
			pause_left -= delta
			position += flee_dir * RUN_SPEED * delta
			rotation.y = lerp_angle(rotation.y, atan2(flee_dir.x, flee_dir.z), minf(1.0, delta * 10.0))
			position.y = world.terrain.height_at(position)
			if pause_left <= 0.0:
				# Back to the nearest pavement and carry on.
				var c := Vector2i(int(position.x / CELL_M), int(position.z / CELL_M))
				from = c if world.is_walk(c) else from
				to = _next(from, from)
				t = 0.0
				state = State.WALK
				_anim()
		State.WALK:
			if from == to:
				to = _next(from, from)
				return
			t += delta * WALK_SPEED / CELL_M
			if t >= 1.0:
				t -= 1.0
				var came := from
				from = to
				to = _next(from, came)
				if rng.randf() < 0.06:
					state = State.PAUSE
					pause_left = rng.randf_range(3.0, 8.0)
					_anim()
					return
			var pa: Vector3 = world.cell_pos(from)
			var pb: Vector3 = world.cell_pos(to)
			# Keep to one side of the pavement (people pass each other).
			var side := (pb - pa).normalized().cross(Vector3.UP) * 0.9
			position = pa.lerp(pb, t) + side
			var dir := pb - pa
			if dir.length_squared() > 0.01:
				rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 8.0))


## A vehicle is coming: get out of the way, at a run.
func flee(from_pos: Vector3, along: Vector3) -> void:
	if state == State.FLEE:
		return
	var away := position - from_pos
	away.y = 0.0
	var side := along.cross(Vector3.UP).normalized()
	flee_dir = (side if side.dot(away) > 0.0 else -side)
	state = State.FLEE
	pause_left = 1.4
	_anim()


func _next(c: Vector2i, came: Vector2i) -> Vector2i:
	var opts: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb: Vector2i = c + d
		if nb != came and world.is_walk(nb):
			opts.append(nb)
	if opts.is_empty():
		return came if world.is_walk(came) and came != c else c
	var straight: Vector2i = c + (c - came)
	if came != c and straight in opts and rng.randf() < 0.75:
		return straight
	return opts[rng.randi() % opts.size()]
