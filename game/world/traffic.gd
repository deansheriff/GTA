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
## Rain (street/weather.gd): everyone drives slower and okadas get off the road.
var speed_k := 1.0
var no_okada := false
## Called with each newly spawned traffic vehicle (street_life.gd dresses some danfos as your fleet).
var on_spawn := Callable()
var held: Array = []


func setup(m: MapData, p: Node2D, mat: Material) -> void:
	map = m
	parent = p
	painted_mat = mat
	_rng.seed = 2026


## player_vehicle: the danfo while you drive it (traffic queues behind it). parked: the danfo when
## you've left it; traffic swerves around it instead of driving through it.
func update(delta: float, focus: Vector2, player_vehicle: Node2D, parked: Node2D = null, people: Array = []) -> void:
	# Despawn far vehicles, spawn new ones in a ring around the focus.
	for v in vehicles.duplicate():
		var gone_okada: bool = no_okada and v["kind"] == "okada" and (v["node"] as Node2D).position.distance_to(focus) > 700.0
		if gone_okada or (v["node"] as Node2D).position.distance_to(focus) > (DESPAWN * 2.0 if v.get("jam", false) else DESPAWN):
			(v["node"] as Node).queue_free()
			vehicles.erase(v)
	var tries := 0
	while vehicles.size() < target_count and tries < 6:
		tries += 1
		_try_spawn(focus)
	holdup_t = 0.0
	held.clear()
	for v in vehicles:
		_drive(v, delta, player_vehicle, parked, people)
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
	# Lagos traffic mix (M13): danfos everywhere, cars and taxis, the odd bus, trucks and tankers.
	var kind := "danfo"
	for k: Array in [["danfo", 0.32], ["car", 0.46], ["taxi", 0.55], ["suv", 0.62], ["pickup", 0.68], ["truck", 0.73], ["tanker", 0.76], ["bus", 0.81], ["keke", 0.92], ["okada", 1.01]]:
		if roll < float(k[1]):
			kind = k[0]
			break
	if kind == "okada" and no_okada:
		kind = "keke"
	spawn_on(a, b, t, kind)


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
	if on_spawn.is_valid():
		on_spawn.call(v)
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


func _drive(v: Dictionary, delta: float, player_vehicle: Node2D, parked: Node2D = null, people: Array = []) -> void:
	var n: Node2D = v["node"]
	var want: float = BASE_SPEED * float(v["cls"]) * (1.15 if v["kind"] == "okada" else 1.0) * speed_k
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
		var gap: float = (float(n.LENGTH) + float(on.LENGTH)) * 0.5 + 30.0 # long buses need more room
		if to.length() < gap + 110.0 and to.dot(fwd) > 20.0 and absf(to.cross(fwd)) < 34.0:
			# Keep a car length of gap: stop dead inside it (device test showed queues piling up).
			want = 0.0 if to.length() < gap else minf(want, float(o["speed"]) * 0.9)
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
	var old_sw := float(v.get("swerve", 0.0))
	# Steer out only while rolling (a stopped car doesn't slide sideways).
	v["swerve"] = move_toward(float(v.get("swerve", 0.0)), swerve, 90.0 * delta * clampf(absf(float(v["speed"])) / 60.0, 0.0, 1.0))
	# People in the road: stop for them (crowd, the player on foot).
	for p: Node2D in people:
		var tw := p.position - n.position
		if tw.length_squared() < 140.0 * 140.0 and tw.dot(fwd) > 0.0 and absf(tw.cross(fwd)) < 38.0:
			want = 0.0
			break
	# Gridlock breaker: stuck nose-to-nose for a while, back up a little and try again.
	if float(v.get("rev_t", 0.0)) > 0.0:
		v["rev_t"] = float(v["rev_t"]) - delta
		want = -55.0
	elif float(v.get("stuck", 0.0)) > 5.0:
		v["rev_t"] = 1.2
		v["stuck"] = 0.0
	held = held and not waiting_story and absf(player_vehicle.speed if player_vehicle else 99.0) < 25.0
	v["held"] = held
	v["held_t"] = float(v.get("held_t", 0.0)) + delta if held else 0.0
	v["speed"] = move_toward(float(v["speed"]), want, 420.0 * delta)
	var old_t := float(v["t"])
	var old_edge: Array = [v["from"], v["to"], v["len"], v["lane"], v["cls"]]
	var old_pos := n.position
	var old_heading: float = n.heading
	v["t"] = maxf(0.0, old_t + float(v["speed"]) * delta)
	if float(v["t"]) >= float(v["len"]):
		_next_edge(v)
	_place(v)
	# Solid vehicles (owner: "vehicles pass through each other"): a move that creates or deepens an
	# overlap with any vehicle (or the player's, parked or driven) is undone. Moving apart is
	# always allowed, so nothing ever locks inside another; gridlocks clear by backing up.
	var blocked := n.position != old_pos and _blocked(v, old_pos, old_heading, [player_vehicle, parked])
	if blocked:
		v["from"] = old_edge[0]
		v["to"] = old_edge[1]
		v["len"] = old_edge[2]
		v["lane"] = old_edge[3]
		v["cls"] = old_edge[4]
		v["t"] = old_t
		v["swerve"] = old_sw
		v["speed"] = 0.0
		v["stuck"] = float(v.get("stuck", 0.0)) + delta
		_place(v)
	else:
		v["stuck"] = 0.0


func _blocked(v: Dictionary, old_pos: Vector2, old_heading: float, extra: Array) -> bool:
	var n: Node2D = v["node"]
	var others: Array = extra.filter(func(x: Variant) -> bool: return x != null)
	for o in vehicles:
		if o != v:
			others.append(o["node"])
	var half := Vector2(n.LENGTH, n.WIDTH) * 0.5 + Vector2(3, 3)
	for on: Node2D in others:
		if on.position.distance_squared_to(n.position) > 200.0 * 200.0:
			continue
		var oh := Vector2(on.LENGTH, on.WIDTH) * 0.5 + Vector2(3, 3)
		var now := Collide.obb_mtv(n.position, n.heading, half, on.position, on.heading, oh).length()
		if now <= 0.0:
			continue
		var before := Collide.obb_mtv(old_pos, old_heading, half, on.position, on.heading, oh).length()
		if now > before + 0.01:
			return true
	return false


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
