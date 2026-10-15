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
## Hold-ups: how long the longest-waiting vehicle has been stuck behind the player's danfo
## (directly or further back in the queue), and those vehicles (street_clash.gd reacts).
var holdup_t := 0.0
var held: Array = []


func setup(m: MapData, p: Node2D, mat: Material) -> void:
	map = m
	parent = p
	painted_mat = mat
	_rng.seed = 2026


## player_vehicle: the danfo while you drive it (traffic queues behind it). parked: the danfo when
## you've left it; traffic swerves around it instead of driving through it.
func update(delta: float, focus: Vector2, player_vehicle: Node2D, parked: Node2D = null) -> void:
	# Despawn far vehicles, spawn new ones in a ring around the focus.
	for v in vehicles.duplicate():
		if (v["node"] as Node2D).position.distance_to(focus) > (DESPAWN * 2.0 if v.get("jam", false) else DESPAWN):
			(v["node"] as Node).queue_free()
			vehicles.erase(v)
	var tries := 0
	while vehicles.size() < target_count and tries < 6:
		tries += 1
		_try_spawn(focus)
	holdup_t = 0.0
	held.clear()
	for v in vehicles:
		_drive(v, delta, player_vehicle, parked)
		if v.get("held", false):
			held.append(v)
			holdup_t = maxf(holdup_t, float(v["held_t"]))


## The hold-up was dealt with (the drivers got out): everyone's patience starts again.
func reset_holdup() -> void:
	for v in vehicles:
		v["held_t"] = 0.0


## Story go-slow (mission 1.1): a solid queue of stopped vehicles on the road nearest `pos`,
## in both directions. `from` is where the player is coming from (unused for now, kept for tuning).
func jam(pos: Vector2, _from: Vector2) -> void:
	var best := ["", ""]
	var bd := INF
	for a in map.road_graph:
		for b in map.road_graph[a]:
			var pa: Vector2 = map.road_nodes[a]
			var pb: Vector2 = map.road_nodes[b]
			var q := Geometry2D.get_closest_point_to_segment(pos, pa, pb)
			var d := q.distance_to(pos)
			if d < bd:
				bd = d
				best = [a, b]
	if best[0] == "":
		return
	for dir in 2:
		var a: String = best[dir]
		var b: String = best[1 - dir]
		var pa: Vector2 = map.road_nodes[a]
		var pb: Vector2 = map.road_nodes[b]
		var len := pa.distance_to(pb)
		var t0 := Geometry2D.get_closest_point_to_segment(pos, pa, pb).distance_to(pa)
		for i in range(-4, 5):
			var t := clampf(t0 + i * 150.0, 20.0, len - 20.0)
			var roll := _rng.randf()
			var kind := "danfo" if roll < 0.45 else ("car" if roll < 0.85 else "keke")
			var n: Node2D = VehicleScript.new()
			n.set_kind(kind, CAR_COLOURS[_rng.randi() % CAR_COLOURS.size()] if kind == "car" else Color(0, 0, 0, 0))
			n.material = painted_mat
			parent.add_child(n)
			var v := { "node": n, "from": a, "to": b, "t": t, "len": len, "lane": _lane(a, b), "speed": 0.0, "stop_t": 40.0, "cls": _edge_speed(a, b), "kind": kind, "jam": true }
			_place(v)
			vehicles.append(v)


## The Whisperer found the gaps: the jam starts crawling again.
func release_jam() -> void:
	for v in vehicles:
		if v.get("jam", false):
			v["stop_t"] = 0.0


func clear_jam() -> void:
	for v in vehicles.duplicate():
		if v.get("jam", false):
			(v["node"] as Node).queue_free()
			vehicles.erase(v)


func _edge_speed(a: String, b: String) -> float:
	for r in map.roads:
		var nodes: Array = r["nodes"]
		var i := nodes.find(a)
		if i >= 0 and ((i + 1 < nodes.size() and nodes[i + 1] == b) or (i > 0 and nodes[i - 1] == b)):
			return r["speed"]
	return 0.7


## Lane offset from the centre line: at least 31 px so opposite lanes never overlap (a danfo is 58 px wide).
func _lane(a: String, b: String) -> float:
	return maxf(_edge_width(a, b) * 0.25, 31.0)


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
	for o in vehicles:
		if (o["node"] as Node2D).position.distance_to(pos) < 200.0:
			return # never spawn on top of another vehicle
	var roll := _rng.randf()
	spawn_on(a, b, t, "danfo" if roll < 0.4 else ("car" if roll < 0.7 else ("keke" if roll < 0.88 else "okada")))


## A vehicle on edge a -> b, t px along it (demo and tests use this directly).
func spawn_on(a: String, b: String, t: float, kind: String) -> Dictionary:
	var len: float = (map.road_nodes[a] as Vector2).distance_to(map.road_nodes[b])
	var n: Node2D = VehicleScript.new()
	n.set_kind(kind, CAR_COLOURS[_rng.randi() % CAR_COLOURS.size()] if kind == "car" else Color(0, 0, 0, 0))
	n.material = painted_mat
	parent.add_child(n)
	var v := { "node": n, "from": a, "to": b, "t": t, "len": len, "lane": _lane(a, b), "speed": 0.0, "stop_t": 0.0, "cls": _edge_speed(a, b), "kind": kind }
	_place(v)
	vehicles.append(v)
	return v


## Where a vehicle in the lane of edge a -> b sits, t px along it.
func lane_pos(a: String, b: String, t: float) -> Vector2:
	var pa: Vector2 = map.road_nodes[a]
	var dir := ((map.road_nodes[b] as Vector2) - pa).normalized()
	return pa + dir * t + Vector2(-dir.y, dir.x) * _lane(a, b)


func _place(v: Dictionary) -> void:
	var pa: Vector2 = map.road_nodes[v["from"]]
	var pb: Vector2 = map.road_nodes[v["to"]]
	var dir := (pb - pa).normalized()
	var right := Vector2(-dir.y, dir.x) # y points down, so this is the driver's right
	var n: Node2D = v["node"]
	n.position = pa + dir * float(v["t"]) + right * (float(v["lane"]) - float(v.get("swerve", 0.0)))
	var h := dir.angle()
	if absf(angle_difference(n.heading, h)) > 0.01:
		n.heading = h
		n.queue_redraw() # code-drawn vehicles only re-draw when they turn


func _drive(v: Dictionary, delta: float, player_vehicle: Node2D, parked: Node2D = null) -> void:
	var n: Node2D = v["node"]
	var want: float = BASE_SPEED * float(v["cls"]) * (1.15 if v["kind"] == "okada" else 1.0)
	var waiting_story := float(v["stop_t"]) > 0.0
	if waiting_story:
		v["stop_t"] = float(v["stop_t"]) - delta
		want = 0.0
	var held := false
	# Queue behind anything ahead in the same lane, including the player's danfo.
	var fwd := Vector2.from_angle(n.heading)
	for o in vehicles:
		if o == v:
			continue
		var on: Node2D = o["node"]
		var to := on.position - n.position
		if to.length() < 260.0 and to.dot(fwd) > 20.0 and absf(to.cross(fwd)) < 34.0:
			# Keep a car length of gap: stop dead inside 150 px (device test showed queues piling up).
			want = 0.0 if to.length() < 150.0 else minf(want, float(o["speed"]) * 0.9)
			held = held or (o.get("held", false) and to.length() < 200.0)
	if player_vehicle:
		var tp := player_vehicle.position - n.position
		if tp.length() < 240.0 and tp.dot(fwd) > 10.0 and absf(tp.cross(fwd)) < 40.0:
			want = 0.0
			held = true
	# A parked danfo in the lane: pull out around it (toward the middle of the road).
	var swerve := 0.0
	if parked:
		var tq := parked.position - n.position
		if tq.dot(fwd) > -110.0 and tq.dot(fwd) < 220.0 and absf(tq.cross(fwd)) < 60.0:
			swerve = 70.0
			want = minf(want, BASE_SPEED * 0.45)
	v["swerve"] = move_toward(float(v.get("swerve", 0.0)), swerve, 90.0 * delta)
	held = held and not waiting_story and absf(player_vehicle.speed if player_vehicle else 99.0) < 25.0
	v["held"] = held
	v["held_t"] = float(v.get("held_t", 0.0)) + delta if held else 0.0
	v["speed"] = move_toward(float(v["speed"]), want, 420.0 * delta)
	var old_t := float(v["t"])
	var old_edge: Array = [v["from"], v["to"], v["len"], v["lane"], v["cls"]]
	v["t"] = old_t + float(v["speed"]) * delta
	if float(v["t"]) >= float(v["len"]):
		_next_edge(v)
	_place(v)
	# Solid vehicles: if this move would overlap another vehicle (or the player's), undo it and wait.
	# A vehicle stuck for a long time (rare junction standoff) briefly squeezes through.
	var blocked := float(v["speed"]) > 0.0 and _blocked(v, player_vehicle)
	if blocked and float(v.get("stuck", 0.0)) < 4.0:
		v["from"] = old_edge[0]
		v["to"] = old_edge[1]
		v["len"] = old_edge[2]
		v["lane"] = old_edge[3]
		v["cls"] = old_edge[4]
		v["t"] = old_t
		v["speed"] = 0.0
		v["stuck"] = float(v.get("stuck", 0.0)) + delta
		_place(v)
	elif not blocked:
		v["stuck"] = 0.0
	# else: stuck for 4 s at a junction standoff, so it squeezes through until it's clear.


func _blocked(v: Dictionary, player_vehicle: Node2D) -> bool:
	var n: Node2D = v["node"]
	var fwd := Vector2.from_angle(n.heading)
	for o in vehicles:
		if o == v:
			continue
		var on: Node2D = o["node"]
		# Only what's in front of us blocks us (the one behind waits for us, not the other way).
		if (on.position - n.position).dot(fwd) > 0.0 and Collide.vehicles(n, on) != Vector2.ZERO:
			return true
	return player_vehicle != null and Collide.vehicles(n, player_vehicle) != Vector2.ZERO


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
	v["lane"] = _lane(at, next)
	v["cls"] = _edge_speed(at, next)
	# Junction go-slow: sometimes everyone waits for the "warden".
	if (map.road_graph.get(at, []) as Array).size() > 2 and _rng.randf() < 0.25:
		v["stop_t"] = _rng.randf_range(0.8, 3.0)
