class_name Checkpoint3D
extends Node3D
## Roadside checkpoints in 3D Lagos (D-020), the 2D game's crews and prices (data/street.json):
## road marshals, motor park union boys and the area task force, with drum-and-plank barriers on
## the kerbs. Pull up slowly and you "settle" (the roger); blast through and they take your number
## (the fine, and Area Heat goes up). They move every game day.

const SPOTS := 4
const RANGE := 9.0
const SLOW := 3.0
const CREW_MODEL := { "marshal": "marshal", "agbero": "agbero", "task": "taskforce" }

var world # Street3D
var spots: Array = [] # {pos: Vector3, kind: String, fwd: Vector3, cool: float, crew: [Person3D]}
var _day := -1

signal message(text: String)
signal charged


func setup(w) -> void:
	world = w
	_place()


func _place() -> void:
	for s: Dictionary in spots:
		for n: Node in s["nodes"]:
			n.queue_free()
	spots.clear()
	var clock: Node = world.get_node_or_null("/root/Clock")
	_day = int(clock.day()) if clock else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + _day
	var map: MapData = world.map
	var keys: Array = map.road_graph.keys()
	var kinds: Array = ["marshal", "agbero", "task", "marshal"]
	var tries := 0
	while spots.size() < SPOTS and tries < 400:
		tries += 1
		var a: String = keys[rng.randi() % keys.size()]
		var nbs: Array = map.road_graph[a]
		if nbs.is_empty():
			continue
		var b: String = nbs[rng.randi() % nbs.size()]
		var pa: Vector2 = map.road_nodes[a]
		var pb: Vector2 = map.road_nodes[b]
		if pa.distance_to(pb) < 900.0:
			continue # long straight roads only, away from junctions
		var mid := Terrain3D.w(pa.lerp(pb, 0.5))
		var far_enough := true
		for s: Dictionary in spots:
			if (s["pos"] as Vector3).distance_to(mid) < 250.0:
				far_enough = false
		if mid.distance_to(world.player.position) < 60.0 or not far_enough:
			continue
		var dir := (pb - pa).normalized()
		_add(mid, Vector3(dir.x, 0, dir.y), kinds[spots.size() % kinds.size()], rng)


func _add(pos: Vector3, fwd: Vector3, kind: String, rng: RandomNumberGenerator) -> void:
	var side := Vector3(-fwd.z, 0, fwd.x)
	var nodes := []
	var crew := []
	for sgn in [1.0, -1.0]:
		var bar: Node3D = world.models.make("barrier")
		if bar:
			Models3D.fit_height(bar, 1.0)
			var h := Node3D.new()
			h.add_child(bar)
			h.position = pos + side * 5.5 * sgn
			h.rotation.y = atan2(fwd.x, fwd.z) + PI * 0.5
			add_child(h)
			nodes.append(h)
	for i in 2:
		var p := Person3D.new()
		add_child(p)
		if not p.setup(world.models, CREW_MODEL[kind], world, Vector2i(int(pos.x / 4.0), int(pos.z / 4.0)), 900 + i):
			p.free()
			continue
		p.position = pos + side * (4.2 + i * 0.9) + fwd * (i * 1.5)
		p.state = Person3D.State.PAUSE
		p.pause_left = 1e9
		p.rotation.y = atan2(-side.x, -side.z) # facing the traffic lane
		Models3D.play(p.ap, "idle" if i == 0 else "phone", "idle")
		crew.append(p)
		nodes.append(p)
	spots.append({ "pos": pos, "kind": kind, "fwd": fwd, "cool": 0.0, "crew": crew, "nodes": nodes })


func step(delta: float) -> void:
	var clock: Node = world.get_node_or_null("/root/Clock")
	if clock and int(clock.day()) != _day:
		_place()
	var ride: Vehicle3D = world.ride
	for s: Dictionary in spots:
		s["cool"] = maxf(0.0, float(s["cool"]) - delta)
		if ride == null or float(s["cool"]) > 0.0:
			continue
		if ride.position.distance_to(s["pos"]) > RANGE:
			continue
		s["cool"] = 90.0
		_stop(s, absf(ride.speed) <= SLOW)


func _stop(s: Dictionary, slow: bool) -> void:
	var street: Node = world.get_node_or_null("/root/Street")
	var life: Node = world.get_node_or_null("/root/Life")
	var data: Dictionary = (street.db.get("checkpoints", {}) as Dictionary).get(s["kind"], {}) if street else {}
	var lines: Array = data.get("lines", ["Oya, stop there!"])
	var line: String = lines[randi() % lines.size()]
	var crew_name := String(data.get("name", "Checkpoint"))
	if slow:
		var roger := int(data.get("roger", 300))
		if life and life.spend(roger, "Settled the %s (3D)" % crew_name):
			message.emit("\"%s\"  You settled the %s: ₦%d." % [line, crew_name, roger])
		else:
			message.emit("\"%s\"  No money to settle. They wave you on with a warning." % line)
	else:
		var fine := int(data.get("fine", 1000))
		for p: Person3D in s["crew"]:
			Models3D.play(p.ap, "argue", "idle")
		if street:
			street.heat = minf(5.0, float(street.heat) + 0.8)
		if life and life.spend(fine, "Fined by the %s (3D)" % crew_name):
			message.emit("\"%s\"  You blasted the %s checkpoint. They took your number: ₦%d fine." % [line, crew_name, fine])
		else:
			message.emit("\"%s\"  You blasted the %s checkpoint. Area heat is rising." % [line, crew_name])
	charged.emit()
