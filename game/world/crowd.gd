class_name Crowd
extends RefCounted
## Pedestrians spawn around the camera (mostly on walkways), wander, and despawn behind the player.

const WalkerScript := preload("res://actors/walker.gd")
const SPAWN_MIN := 650.0
const SPAWN_MAX := 1300.0
const DESPAWN := 1800.0

var map: MapData
var parent: Node2D
var painted_mat: Material
var target_count := 30
var anim_fps := 10.0
var people: Array[Node2D] = []
var _rng := RandomNumberGenerator.new()
var _next_id := 0


func setup(m: MapData, p: Node2D, mat: Material) -> void:
	map = m
	parent = p
	painted_mat = mat
	_rng.seed = 77


func clear() -> void:
	for n in people:
		n.queue_free()
	people.clear()


func update(delta: float, focus: Vector2) -> void:
	for n in people.duplicate():
		if n.position.distance_to(focus) > DESPAWN:
			n.queue_free()
			people.erase(n)
	var tries := 0
	while people.size() < target_count and tries < 10:
		tries += 1
		_try_spawn(focus)
	for n in people:
		if n.target == Vector2.INF:
			n.idle_t -= delta
			if n.idle_t <= 0.0:
				_pick_target(n)
				n.idle_t = _rng.randf_range(0.6, 3.5) * (2.5 if n.loiterer else 1.0)
		n.step(delta, Vector2.ZERO, map)


func _walkable(p: Vector2, prefer_walk: bool) -> bool:
	if map.is_blocked(p):
		return false
	var s := map.surface_at(p)
	if s == MapData.S.WALK:
		return true
	if s == MapData.S.GROUND or s == MapData.S.BEACH or s == MapData.S.GUTTER:
		return not prefer_walk or _rng.randf() < 0.35
	return false


func _try_spawn(focus: Vector2) -> void:
	var a := _rng.randf() * TAU
	var p := focus + Vector2(cos(a), sin(a)) * _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	if not _walkable(p, true):
		return
	var n: Node2D = WalkerScript.new()
	n.look = WalkerScript.random_look(_next_id * 17 + 900)
	n.use_pedestrian(_next_id)
	n.speed = _rng.randf_range(45.0, 85.0)
	n.anim_fps = anim_fps
	n.position = p
	n.material = painted_mat
	_next_id += 1
	parent.add_child(n)
	people.append(n)


func _pick_target(n: Node2D) -> void:
	var reach := 70.0 if n.loiterer else 320.0
	for i in 4:
		var t: Vector2 = n.position + Vector2(_rng.randf_range(-reach, reach), _rng.randf_range(-reach * 0.6, reach * 0.6))
		if _walkable(t, not n.loiterer):
			n.target = t
			return
