class_name Signals3D
extends Node3D
## Traffic lights and junction rules (D-028). Busy junctions (three or more roads, one of them a
## main road) get lights on two poles, one for each crossing direction, cycling green, amber, red.
## AI traffic stops at the line on red. Some junctions have a traffic warden: run his red
## light and he books you.

signal message(text: String)

const GREEN := 12.0
const AMBER := 2.5
const STOP_ZONE := 26.0 # metres from the junction centre where a red light holds traffic

var world # Street3D
var junctions := {} # node id -> {pos, t, phase, axes: {nb: 0|1}, lamps: [[r, a, g], [r, a, g]], warden, crew}
var _mats := {}
var _player_in := ""
var _fine_cool := 0.0


func build(w) -> void:
	world = w
	var map: MapData = world.map
	for id: String in map.road_graph:
		var nbs: Array = map.road_graph[id]
		if nbs.size() < 3:
			continue
		var main := false
		for r: Dictionary in map.roads:
			if id in (r["nodes"] as Array) and String(r["class"]) != "street":
				main = true
		if not main:
			continue
		var c := Terrain3D.w(map.road_nodes[id])
		var axes := {}
		for nb: String in nbs:
			var d := Terrain3D.w(map.road_nodes[nb]) - c
			axes[nb] = 0 if absf(d.x) >= absf(d.z) else 1
		var j := { "pos": c, "t": float(hash(id) % 100) / 100.0 * GREEN, "phase": hash(id) % 2 * 2, "axes": axes, "lamps": [], "warden": hash(id) % 3 == 0, "crew": null }
		for axis in 2:
			# One pole on the corner for each direction, facing its traffic.
			var off := Vector3(9.0, 0, 9.0) if axis == 0 else Vector3(-9.0, 0, -9.0)
			j["lamps"].append(_pole(c + off, axis))
		junctions[id] = j
	_refresh_all()


func _mat(name: String, col: Color, on: bool) -> StandardMaterial3D:
	var key := name + ("1" if on else "0")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col if on else col.darkened(0.75)
	if on:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 3.0
	_mats[key] = m
	return m


func _pole(at: Vector3, axis: int) -> Array:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = 0.0 if axis == 0 else PI * 0.5
	add_child(root)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.12)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.08
	pm.bottom_radius = 0.1
	pm.height = 4.2
	pm.radial_segments = 6
	pole.mesh = pm
	pole.material_override = dark
	pole.position.y = 2.1
	root.add_child(pole)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.4, 1.2, 0.4)
	head.mesh = hm
	head.material_override = dark
	head.position.y = 4.5
	root.add_child(head)
	var lamps := []
	for i in 3:
		var l := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.26
		sm.radial_segments = 8
		sm.rings = 4
		l.mesh = sm
		l.position = Vector3(0, 4.85 - i * 0.36, 0.2)
		root.add_child(l)
		lamps.append([l])
	Models3D.far_cull(root, 70.0)
	Models3D.no_shadow(root)
	return lamps


## 0 green, 1 amber, 2 red for an axis at a junction.
func light(j: Dictionary, axis: int) -> int:
	var ph := int(j["phase"]) # 0: axis 0 green, 1: axis 0 amber, 2: axis 1 green, 3: axis 1 amber
	var mine := 0 if axis == 0 else 2
	if ph == mine:
		return 0
	if ph == mine + 1:
		return 1
	return 2


func step(delta: float) -> void:
	_fine_cool = maxf(0.0, _fine_cool - delta)
	for id: String in junctions:
		var j: Dictionary = junctions[id]
		j["t"] = float(j["t"]) + delta
		var dur := GREEN if int(j["phase"]) % 2 == 0 else AMBER
		if float(j["t"]) >= dur:
			j["t"] = 0.0
			j["phase"] = (int(j["phase"]) + 1) % 4
			_refresh(j)
	_watch_player()


func _refresh_all() -> void:
	for id: String in junctions:
		_refresh(junctions[id])


func _refresh(j: Dictionary) -> void:
	for axis in 2:
		var s := light(j, axis)
		var lamps: Array = j["lamps"][axis]
		var cols := [Color(0.95, 0.15, 0.1), Color(1.0, 0.7, 0.1), Color(0.2, 0.9, 0.35)]
		var want := [2, 1, 0] # top red, middle amber, bottom green
		for i in 3:
			for l: MeshInstance3D in lamps[i]:
				l.material_override = _mat("lamp%d" % i, cols[i], s == want[i])


## AI: should this vehicle (heading for node b, `dist` metres from it) wait at the line?
func must_stop(v: Vehicle3D, dist: float) -> bool:
	if not junctions.has(v.b) or dist > STOP_ZONE or dist < 10.0:
		return false
	var j: Dictionary = junctions[v.b]
	var axis: int = int((j["axes"] as Dictionary).get(v.a, 0))
	return light(j, axis) != 0


## Running a red light where a warden stands: a fine, and his whistle.
func _watch_player() -> void:
	var ride: Vehicle3D = world.ride
	if ride == null or ride.on_water:
		_player_in = ""
		return
	var p := ride.position
	for id: String in junctions:
		var j: Dictionary = junctions[id]
		var d := Vector2(p.x - j["pos"].x, p.z - j["pos"].z).length()
		if d < 8.0 and _player_in != id:
			_player_in = id
			var f := ride.forward()
			var axis := 0 if absf(f.x) >= absf(f.z) else 1
			if light(j, axis) == 2 and absf(ride.speed) > 4.0 and j["warden"] and _fine_cool <= 0.0 and world.missions.running == "":
				_fine_cool = 20.0
				var fine := 2000
				Life.spend(mini(fine, int(Life.money)), "Traffic warden: ran a red light (3D)")
				Story.wanted = minf(5.0, Story.wanted + 0.4)
				Sound.sfx("siren", 1.4)
				message.emit("A traffic warden saw you run the red light. ₦%d fine." % fine)
			return
		elif d > 14.0 and _player_in == id:
			_player_in = ""
