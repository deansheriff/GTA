class_name Traffic
extends RefCounted
## Living traffic near the camera: danfos, cars, keke and okada driving on the RIGHT along the road
## graph. Vehicles queue behind each other, sometimes stop at junctions (a phantom traffic warden,
## the source of every go-slow), and despawn when far away. Local to each phone (not networked).

const VehicleScript := preload("res://actors/danfo.gd")
const SPAWN_MIN := 900.0
const SPAWN_MAX := 1700.0
const DESPAWN := 2300.0
const BASE_SPEED := 300.0
const CAR_COLOURS := [Color("#2f6f99"), Color("#a8382c"), Color("#d9d3c4"), Color("#3a3a3a"), Color("#6b7d4a"), Color("#c8862a")]

var map: MapData
var parent: Node2D
var painted_mat: Material
var target_count := 12
var vehicles: Array = [] # [{node, from, to, t, len, lane, speed, stop_t, cls_speed}]
var _rng := RandomNumberGenerator.new()
## Set when the player rammed traffic this frame (for a toast).
var bumped := false


func setup(m: MapData, p: Node2D, mat: Material) -> void:
	map = m
	parent = p
	painted_mat = mat
	_rng.seed = 2026


func update(delta: float, focus: Vector2, player_vehicle: Node2D) -> void:
	bumped = false
	# Despawn far vehicles, spawn new ones in a ring around the focus.
	for v in vehicles.duplicate():
		if (v["node"] as Node2D).position.distance_to(focus) > DESPAWN:
			(v["node"] as Node).queue_free()
			vehicles.erase(v)
	var tries := 0
	while vehicles.size() < target_count and tries < 6:
		tries += 1
		_try_spawn(focus)
	for v in vehicles:
		_drive(v, delta, player_vehicle)


func _edge_speed(a: String, b: String) -> float:
	for r in map.roads:
		var nodes: Array = r["nodes"]
		var i := nodes.find(a)
		if i >= 0 and ((i + 1 < nodes.size() and nodes[i + 1] == b) or (i > 0 and nodes[i - 1] == b)):
			return r["speed"]
	return 0.7


func _edge_width(a: String, b: String) -> float:
	for r in map.roads:
		var nodes: Array = r["nodes"]
		var i := nodes.find(a)
		if i >= 0 and ((i + 1 < nodes.size() and nodes[i + 1] == b) or (i > 0 and nodes[i - 1] == b)):
			return r["width"]
	return 100.0


func _try_spawn(focus: Vector2) -> void:
	var names := map.road_graph.keys()
	var a: String = names[_rng.randi() % names.size()]
	var nbs: Array = map.road_graph[a]
	if nbs.is_empty():
		return
	var b: String = nbs[_rng.randi() % nbs.size()]
	var pa: Vector2 = map.road_nodes[a]
	var pb: Vector2 = map.road_nodes[b]
	var len := pa.distance_to(pb)
	var t := _rng.randf_range(0.1, 0.9) * len
	var pos := pa.lerp(pb, t / len)
	var d := pos.distance_to(focus)
	if d < SPAWN_MIN or d > SPAWN_MAX:
		return
	var roll := _rng.randf()
	var kind := "danfo" if roll < 0.4 else ("car" if roll < 0.7 else ("keke" if roll < 0.88 else "okada"))
	var n: Node2D = VehicleScript.new()
	n.set_kind(kind, CAR_COLOURS[_rng.randi() % CAR_COLOURS.size()] if kind == "car" else Color(0, 0, 0, 0))
	n.material = painted_mat
	parent.add_child(n)
	var v := { "node": n, "from": a, "to": b, "t": t, "len": len, "lane": _edge_width(a, b) * 0.25, "speed": 0.0, "stop_t": 0.0, "cls": _edge_speed(a, b), "kind": kind }
	_place(v)
	vehicles.append(v)


func _place(v: Dictionary) -> void:
	var pa: Vector2 = map.road_nodes[v["from"]]
	var pb: Vector2 = map.road_nodes[v["to"]]
	var dir := (pb - pa).normalized()
	var right := Vector2(-dir.y, dir.x) # y points down, so this is the driver's right
	var n: Node2D = v["node"]
	n.position = pa + dir * float(v["t"]) + right * float(v["lane"])
	var h := dir.angle()
	if absf(angle_difference(n.heading, h)) > 0.01:
		n.heading = h
		n.queue_redraw() # code-drawn vehicles only re-draw when they turn


func _drive(v: Dictionary, delta: float, player_vehicle: Node2D) -> void:
	var n: Node2D = v["node"]
	var want: float = BASE_SPEED * float(v["cls"]) * (1.15 if v["kind"] == "okada" else 1.0)
	if float(v["stop_t"]) > 0.0:
		v["stop_t"] = float(v["stop_t"]) - delta
		want = 0.0
	# Queue behind anything ahead in the same lane, including the player's danfo.
	var fwd := Vector2.from_angle(n.heading)
	for o in vehicles:
		if o == v:
			continue
		var on: Node2D = o["node"]
		var to := on.position - n.position
		if to.length() < 150.0 and to.dot(fwd) > 20.0 and absf(to.cross(fwd)) < 34.0:
			want = minf(want, float(o["speed"]) * 0.9)
	if player_vehicle:
		var tp := player_vehicle.position - n.position
		if tp.length() < 160.0 and tp.dot(fwd) > 10.0 and absf(tp.cross(fwd)) < 40.0:
			want = 0.0
	# Never drive through the player's danfo: stop dead and give it a little bump.
	if player_vehicle and n.position.distance_to(player_vehicle.position) < 96.0:
		want = 0.0
		v["speed"] = 0.0
		v["t"] = maxf(0.0, float(v["t"]) - 2.0)
		if absf(player_vehicle.speed) > 120.0:
			player_vehicle.speed *= 0.4
			bumped = true
	v["speed"] = move_toward(float(v["speed"]), want, 420.0 * delta)
	v["t"] = float(v["t"]) + float(v["speed"]) * delta
	if float(v["t"]) >= float(v["len"]):
		_next_edge(v)
	_place(v)


func _next_edge(v: Dictionary) -> void:
	var at: String = v["to"]
	var options: Array = (map.road_graph.get(at, []) as Array).filter(func(x: String) -> bool: return x != v["from"])
	if options.is_empty():
		options = [v["from"]] # dead end: turn around
	var next: String = options[_rng.randi() % options.size()]
	var pa: Vector2 = map.road_nodes[at]
	v["from"] = at
	v["to"] = next
	v["t"] = 0.0
	v["len"] = pa.distance_to(map.road_nodes[next])
	v["lane"] = _edge_width(at, next) * 0.25
	v["cls"] = _edge_speed(at, next)
	# Junction go-slow: sometimes everyone waits for the "warden".
	if (map.road_graph.get(at, []) as Array).size() > 2 and _rng.randf() < 0.25:
		v["stop_t"] = _rng.randf_range(0.8, 3.0)
