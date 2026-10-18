class_name Lights3D
extends Node3D
## Street lighting for 3D Lagos (D-020): solar streetlights along the main roads (batched per
## 48 m area so hundreds cost a few draw calls), lamp heads that glow after dark, real lights on
## the few lamps nearest the player, and headlights on the player's vehicle at night.

const SPACING := 34.0 # metres between lamps
const CHUNK := 48.0
const LAMP_H := 7.0
const POOL := 6

var world # Street3D
var lamps: Array[Vector3] = [] # lamp head positions
var _glow_mat: StandardMaterial3D
var _pool: Array[OmniLight3D] = []
var _head: SpotLight3D
var _t := 0.0
var _dark := 0.0


func build(w) -> void:
	world = w
	var map: MapData = world.map
	var junctions: Array[Vector2] = []
	for id in map.road_graph:
		if (map.road_graph[id] as Array).size() >= 3:
			junctions.append((map.road_nodes[id] as Vector2) * Terrain3D.K)
	var poles: Array[Transform3D] = []
	for r: Dictionary in map.roads:
		var half: float = float(r["width"]) * Terrain3D.K * 0.5
		if half < 3.0:
			continue # lanes and side streets stay dark, like real Lagos
		var pts: PackedVector2Array = r["points"]
		var carry := SPACING * 0.5
		for i in pts.size() - 1:
			var a := pts[i] * Terrain3D.K
			var b := pts[i + 1] * Terrain3D.K
			var seg := a.distance_to(b)
			var dir := (b - a) / maxf(seg, 0.001)
			var t := carry
			while t < seg:
				var p := a + dir * t + Vector2(-dir.y, dir.x) * (half + 1.1) # right-hand kerb
				t += SPACING
				var ok := true
				for q in junctions:
					if p.distance_squared_to(q) < 144.0:
						ok = false
						break
				var c := Vector2i(int(p.x / Terrain3D.CELL_M), int(p.y / Terrain3D.CELL_M))
				if not ok or not map.in_bounds(c) or map.is_water(map.surface[c.y * map.cols + c.x]) or map.occupied[c.y * map.cols + c.x] == 1:
					continue
				# The lamp arm reaches back over the road.
				var yaw := atan2(dir.y, -dir.x) - PI * 0.5
				poles.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0, p.y)))
				lamps.append(Vector3(p.x, LAMP_H, p.y) - Vector3(-dir.y, 0, dir.x) * 1.2)
			carry = t - seg
	_batch_model("streetlight", poles, LAMP_H)
	_glow(lamps)
	for i in POOL:
		var l := OmniLight3D.new()
		l.light_color = Color("#ffd9a0")
		l.light_energy = 0.0
		l.omni_range = 16.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_pool.append(l)


## One MultiMesh per mesh part per 48 m area, so far areas are culled as a block.
func _batch_model(key: String, xforms: Array[Transform3D], height: float) -> void:
	var m: Node3D = world.models.make(key)
	if m == null or xforms.is_empty():
		if m:
			m.free()
		return
	Models3D.fit_height(m, height)
	var parts := []
	for c in m.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var xf := mi.transform
		var p: Node = mi.get_parent()
		while p != null and p != m.get_parent() and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		parts.append([mi.mesh, xf, mi.get_active_material(0)])
	m.free()
	var chunks := {}
	for xf in xforms:
		var k := Vector2i(int(xf.origin.x / CHUNK), int(xf.origin.z / CHUNK))
		if not chunks.has(k):
			chunks[k] = []
		chunks[k].append(xf)
	for k in chunks:
		var list: Array = chunks[k]
		for part in parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, (list[i] as Transform3D) * (part[1] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = 120.0 * float(world.q_far)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)


func _glow(at: Array[Vector3]) -> void:
	if at.is_empty():
		return
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.4
	sm.radial_segments = 8
	sm.rings = 4
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.85, 0.84, 0.8)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color("#ffcf86")
	_glow_mat.emission_energy_multiplier = 0.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, Transform3D(Basis(), at[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _glow_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## dark: 0 (day) .. 1 (night), from the game clock.
func step(delta: float, dark: float) -> void:
	_dark = dark
	var on := dark > 0.35
	if _glow_mat:
		# Bright enough at night for the glow pass to put a halo on every lamp.
		_glow_mat.emission_energy_multiplier = 4.0 * clampf((dark - 0.3) * 2.0, 0.0, 1.0)
	_headlights(on)
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	if not on:
		for l in _pool:
			l.visible = false
		return
	# Real lights on the lamps nearest the player.
	var f: Vector3 = world.focus()
	var near := lamps.filter(func(p: Vector3) -> bool: return absf(p.x - f.x) < 60.0 and absf(p.z - f.z) < 60.0)
	near.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(f) < b.distance_squared_to(f))
	for i in _pool.size():
		var l := _pool[i]
		l.visible = i < near.size()
		if l.visible:
			l.position = near[i] - Vector3(0, 0.6, 0)
			l.light_energy = 1.6 * clampf((dark - 0.3) * 2.0, 0.0, 1.0)


func _headlights(on: bool) -> void:
	var ride: Vehicle3D = world.ride
	if _head == null:
		_head = SpotLight3D.new()
		_head.light_color = Color("#fff4dc")
		_head.light_energy = 3.0
		_head.spot_range = 32.0
		_head.spot_angle = 32.0
		_head.shadow_enabled = false
		add_child(_head)
	_head.visible = on and ride != null
	if _head.visible:
		var fwd := ride.forward()
		_head.position = ride.position + fwd * (ride.length * 0.5) + Vector3(0, 1.0, 0)
		_head.look_at(_head.position + fwd * 10.0 + Vector3(0, -1.6, 0))
