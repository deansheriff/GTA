class_name DanfoRun3D
extends Node3D
## Danfo passenger runs in 3D Lagos (D-020), the 2D game's core hustle: every district has a bus
## stop (a sign and people waiting). Stop the danfo at one and passengers climb in, shouting the
## next stop; drive there (follow the beacon and the minimap) and stop to collect the fares.
## Money goes into the same wallet as the 2D game (Life.earn).

const BOARD_RANGE := 14.0
const STOP_SPEED := 1.5
const WAIT_TO_BOARD := 1.2
const WAITERS := 4

var world # Street3D
var stops: Array = [] # {name, pos: Vector3, node: String}
var passengers := 0
var fare := 0
var dest := -1 # index into stops, -1 = no run
var origin := -1
var _still := 0.0
var _beacon: MeshInstance3D
var _waiting := {} # stop index -> [Person3D]
var _rng := RandomNumberGenerator.new()

signal message(text: String)
signal paid


func setup(w) -> void:
	world = w
	var map: MapData = world.map
	# One stop per district, on the road node nearest its centre.
	for d: Dictionary in map.districts:
		var c: Vector2 = d.get("center", Vector2.ZERO)
		var best := ""
		var bd := INF
		for id in map.road_nodes:
			var dd := (map.road_nodes[id] as Vector2).distance_squared_to(c)
			if dd < bd:
				bd = dd
				best = id
		if best == "" or (map.road_graph.get(best, []) as Array).is_empty():
			continue
		var nb: String = map.road_graph[best][0]
		var pa: Vector2 = map.road_nodes[best]
		var dir := ((map.road_nodes[nb] as Vector2) - pa).normalized()
		# On the kerb, a few metres along the road from the junction.
		var p := pa + dir * 140.0 + Vector2(-dir.y, dir.x) * 120.0
		stops.append({ "name": String(d.get("name", "Stop")), "pos": Terrain3D.w(p), "node": best })
		_sign(Terrain3D.w(p), String(d.get("name", "")), -dir.angle())
	_beacon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.2
	cyl.bottom_radius = 2.2
	cyl.height = 40.0
	_beacon.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.8, 0.2, 0.28)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beacon.material_override = bm
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.visible = false
	add_child(_beacon)


func _sign(at: Vector3, text: String, yaw: float) -> void:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = yaw
	add_child(root)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.05
	pm.height = 2.8
	pole.mesh = pm
	pole.position.y = 1.4
	root.add_child(pole)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.9, 0.6, 0.06)
	board.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#e0a91c")
	board.material_override = mat
	board.position.y = 2.75
	root.add_child(board)
	for side in [1.0, -1.0]:
		var lbl := Label3D.new()
		lbl.text = "BUS STOP\n" + text.to_upper()
		lbl.font_size = 34
		lbl.pixel_size = 0.0075
		lbl.modulate = Color("#1d1611")
		lbl.outline_size = 0
		lbl.position = Vector3(0, 0, 0.04 * side)
		lbl.rotation.y = 0.0 if side > 0 else PI
		board.add_child(lbl)
	Models3D.far_cull(root, 120.0)


func nearest_stop(pos: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in stops.size():
		var d := pos.distance_to(stops[i]["pos"])
		if d < bd:
			bd = d
			best = i
	return best


func target() -> Variant:
	return stops[dest]["pos"] if dest >= 0 else null


func step(delta: float) -> void:
	_update_waiters()
	var ride: Vehicle3D = world.ride
	if ride == null or ride.kind != "danfo":
		_still = 0.0
		return
	if absf(ride.speed) > STOP_SPEED:
		_still = 0.0
		return
	_still += delta
	if _still < WAIT_TO_BOARD:
		return
	var at := nearest_stop(ride.position)
	if at < 0 or ride.position.distance_to(stops[at]["pos"]) > BOARD_RANGE:
		return
	if dest >= 0 and at == dest:
		_arrive()
	elif dest < 0:
		_board(at)


func _board(at: int) -> void:
	var here: Vector3 = stops[at]["pos"]
	var options: Array[int] = []
	for i in stops.size():
		var d := here.distance_to(stops[i]["pos"])
		if i != at and d > 150.0 and d < 900.0:
			options.append(i)
	if options.is_empty():
		for i in stops.size():
			if i != at:
				options.append(i)
	if options.is_empty():
		return
	dest = options[_rng.randi() % options.size()]
	origin = at
	passengers = _rng.randi_range(6, 14)
	var dist := here.distance_to(stops[dest]["pos"])
	fare = int(round((150.0 + dist * 0.5) / 50.0)) * 50 # ₦ per head, rounded like conductors do
	for p in _waiting.get(at, []):
		(p as Node3D).visible = false # they've climbed in
	var dname: String = stops[dest]["name"]
	message.emit("%s! %s! %d passengers on board. Next stop: %s (₦%d each)" % [dname, dname, passengers, dname, fare])
	_beacon.position = stops[dest]["pos"] + Vector3(0, 20, 0)
	_beacon.visible = true


func _arrive() -> void:
	var total := passengers * fare
	var life: Node = world.get_node_or_null("/root/Life") # the 2D game's wallet
	if life:
		life.earn(total, "Danfo run (3D): %s to %s" % [stops[origin]["name"], stops[dest]["name"]])
	message.emit("Owa o! %d passengers paid ₦%d. Find the next load." % [passengers, total])
	paid.emit()
	dest = -1
	passengers = 0
	_beacon.visible = false


## People waiting at stops near the player (pooled from the townspeople list).
func _update_waiters() -> void:
	var f: Vector3 = world.focus()
	for i in stops.size():
		var near: bool = f.distance_to(stops[i]["pos"]) < 90.0 and i != dest
		if near and not _waiting.has(i):
			var group := []
			for k in WAITERS:
				var p := Person3D.new()
				add_child(p)
				var keys: Array = world.people_keys
				if keys.is_empty() or not p.setup(world.models, keys[(i + k) % keys.size()], world, Vector2i(int(stops[i]["pos"].x / 4.0), int(stops[i]["pos"].z / 4.0)), 500 + i * 10 + k):
					p.free()
					continue
				p.position = stops[i]["pos"] + Vector3(cos(k * 1.7) * 1.4, Terrain3D.WALK_H, sin(k * 1.7) * 1.4)
				p.state = Person3D.State.PAUSE
				p.pause_left = 1e9
				Models3D.play(p.ap, ["idle", "phone", "talk", "idle"][k % 4], "idle")
				group.append(p)
			_waiting[i] = group
		elif not near and _waiting.has(i):
			for p in _waiting[i]:
				(p as Node).queue_free()
			_waiting.erase(i)
	# Each frame, waiters only idle; they don't need step().
