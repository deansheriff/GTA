class_name Police3D
extends Node
## Wanted level and police response (P2, D-022). Story.wanted (0-5 stars) rises with carjacking,
## gunfire in the street and blasting checkpoints. In free roam, one police pickup per star
## (rounded up) comes after Dayo along the roads, lights flashing. If they box him in (on foot
## near them, or his vehicle stopped beside them for 2 s) he's BUSTED: a fine, and the stars clear.
## Out of their sight (70 m) for 15 s, he loses a star.

const SIGHT := 70.0
const LOSE_AFTER := 15.0

var world # Street3D
var units: Array[Vehicle3D] = []
var _unseen := 0.0
var _boxed := 0.0
var _flash_t := 0.0
var suspended := false # missions run their own pursuers

signal busted(fine: int)


func setup(w) -> void:
	world = w


func raise(stars: float) -> void:
	Story.wanted = clampf(Story.wanted + stars, 0.0, 5.0)


func step(delta: float) -> void:
	var want := 0 if suspended else int(ceil(Story.wanted - 0.01))
	while units.size() < want:
		_spawn()
	while units.size() > want:
		units.pop_back().queue_free()
	if units.is_empty():
		_unseen = 0.0
		return
	_flash_t += delta
	var f: Vector3 = world.focus()
	var seen := false
	var close := false
	for u in units:
		u.chase_step(delta)
		var d := u.position.distance_to(f)
		if d < SIGHT:
			seen = true
		if d < 7.0:
			close = true
		_flash(u)
	_unseen = 0.0 if seen else _unseen + delta
	if _unseen > LOSE_AFTER:
		_unseen = 0.0
		Story.wanted = maxf(0.0, Story.wanted - 1.0)
		world.notify("You lost them. Wanted level down.")
	var stopped: bool = world.ride == null or absf(world.ride.speed) < 2.0
	_boxed = _boxed + delta if close and stopped else 0.0
	if _boxed > 2.0:
		_boxed = 0.0
		var fine := maxi(2000, int(Life.money * 0.1))
		Life.spend(mini(fine, int(Life.money)), "Busted by the police (3D)")
		Story.wanted = 0.0
		busted.emit(fine)
		world.notify("BUSTED. They took ₦%d \"for bail\" and let you go." % fine)


func _spawn() -> void:
	var v := Vehicle3D.new()
	world.add_child(v)
	v.setup(world.models, "pickup", world)
	v.mode = Vehicle3D.Mode.CHASE
	# Arrive from a road node out of sight.
	var f: Vector3 = world.focus()
	var keys: Array = world.map.road_nodes.keys()
	var best: String = keys[0]
	for id: String in keys:
		var d := Terrain3D.w(world.map.road_nodes[id]).distance_to(f)
		if d > 110.0 and d < 200.0:
			best = id
			break
	v.position = Terrain3D.w(world.map.road_nodes[best])
	v.b = best
	v.a = best
	var light := OmniLight3D.new()
	light.name = "Siren"
	light.omni_range = 9.0
	light.light_energy = 2.0
	light.position = Vector3(0, 2.3, 0)
	v.add_child(light)
	units.append(v)


func _flash(u: Vehicle3D) -> void:
	var l := u.get_node_or_null("Siren") as OmniLight3D
	if l:
		l.light_color = Color(0.9, 0.1, 0.1) if int(_flash_t * 4.0) % 2 == 0 else Color(0.15, 0.3, 1.0)


func clear() -> void:
	for u in units:
		u.queue_free()
	units.clear()
