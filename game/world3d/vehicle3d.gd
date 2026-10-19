class_name Vehicle3D
extends CharacterBody3D
## One vehicle in the 3D city (D-020): AI traffic on the road graph, the player's ride, or parked.
## Forward is +X of the node; heading h points along (cos h, 0, -sin h), so rotation.y = h.
## Lagos drives on the right: AI keeps to the right-hand lane of each road.

enum Mode { AI, PLAYER, PARKED, FLEE, CHASE }

signal wrecked

## Damage (P2, D-022): crashes cost health on both sides; at 0 the vehicle is a smoking wreck.
var health := 100.0
var is_wreck := false
var _bump_t := 0.0
var _smoke: CPUParticles3D

const LANE_PX := 30.0 # lane offset from the road centre line (map pixels)

var kind := "danfo"
var spec: Dictionary
var mode := Mode.AI
var heading := 0.0
var speed := 0.0
var length := 4.6
# AI route: driving from node a to node b.
var a := ""
var b := ""
var cruise := 11.0
var world # Street3D: map, terrain and the list of vehicles (to keep a gap)


func setup(lib: Models3D, k: String, w) -> void:
	kind = k
	world = w
	spec = Models3D.VEHICLES.get(k, Models3D.VEHICLES["car"])
	var size: Vector2 = spec["size"]
	length = size.x
	cruise = float(spec["top"]) * randf_range(0.55, 0.75)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 1.8 if size.x > 3.0 else 1.4, size.y)
	shape.shape = box
	shape.position.y = box.size.y * 0.5 + 0.1
	add_child(shape)
	var m := lib.make(spec["model"])
	var model: Node3D
	if m:
		model = Models3D.fit_vehicle(m, size)
		Models3D.glossy(model)
	else:
		model = _box_model(size)
	add_child(model)
	Models3D.far_cull(model, 200.0)
	collision_layer = 2
	collision_mask = 1 | 2


func _box_model(size: Vector2) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 1.5, size.y)
	mi.mesh = bm
	mi.position.y = 1.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = [Color("#2f6f99"), Color("#c8432f"), Color("#ece4d2"), Color("#1d1d1d"), Color("#e0a91c")][randi() % 5]
	mat.roughness = 0.25
	mat.metallic = 0.3
	mi.material_override = mat
	root.add_child(mi)
	return root


func place_on_road(from: String, to: String, t: float) -> void:
	a = from
	b = to
	var pa: Vector2 = world.map.road_nodes[a]
	var pb: Vector2 = world.map.road_nodes[b]
	var dir := (pb - pa).normalized()
	var p := pa.lerp(pb, t) + Vector2(-dir.y, dir.x) * LANE_PX
	position = Terrain3D.w(p)
	heading = -dir.angle()
	rotation.y = heading
	speed = cruise
	reset_physics_interpolation()


## Player driving: throttle -1..1, steer -1..1 (positive = right).
func drive(throttle: float, steer: float, delta: float) -> void:
	var top: float = spec["top"]
	var accel: float = spec["accel"]
	if absf(throttle) > 0.05:
		var braking := throttle * speed < 0.0
		speed = move_toward(speed, top * throttle * (1.0 if throttle > 0.0 else 0.35), (accel * 2.2 if braking else accel) * delta)
	else:
		speed = move_toward(speed, 0.0, 4.0 * delta)
	heading -= steer * float(spec["turn"]) * delta * clampf(absf(speed) / 5.0, 0.0, 1.0) * signf(speed if speed != 0.0 else 1.0)
	_move(delta)


func _move(delta: float) -> void:
	rotation.y = heading
	velocity = Vector3(cos(heading), 0, -sin(heading)) * speed
	var impact := absf(speed)
	move_and_slide()
	_bump_t = maxf(0.0, _bump_t - delta)
	if get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			var other := get_slide_collision(i).get_collider()
			if other is Vehicle3D and impact > 4.0 and _bump_t <= 0.0:
				_bump_t = 0.5
				(other as Vehicle3D).damage(impact * 2.6)
				damage(impact * 0.9)
				Sound.sfx("crash", randf_range(0.9, 1.1))
				if world and world.has_method("shake"):
					world.shake(0.25)
			elif other is StaticBody3D and impact > 9.0 and _bump_t <= 0.0:
				_bump_t = 0.5
				damage(impact * 0.8)
				Sound.sfx("crash", 0.8)
		speed *= 0.5
	position.y = lerpf(position.y, world.terrain.height_at(position), minf(1.0, delta * 10.0))


func damage(amount: float) -> void:
	if is_wreck:
		return
	health -= amount
	if health <= 0.0:
		health = 0.0
		is_wreck = true
		speed = 0.0
		if mode != Mode.PLAYER:
			mode = Mode.PARKED
		_smoke = CPUParticles3D.new()
		_smoke.amount = 40
		_smoke.lifetime = 2.2
		_smoke.direction = Vector3(0, 1, 0)
		_smoke.spread = 18.0
		_smoke.initial_velocity_min = 1.5
		_smoke.initial_velocity_max = 2.5
		_smoke.gravity = Vector3(0.3, 0.6, 0)
		_smoke.scale_amount_min = 0.8
		_smoke.scale_amount_max = 1.8
		var q := SphereMesh.new()
		q.radius = 0.5
		q.height = 1.0
		q.radial_segments = 6
		q.rings = 3
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.15, 0.14, 0.13, 0.55)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		q.material = m
		_smoke.mesh = q
		_smoke.position = Vector3(length * 0.3, 1.4, 0)
		add_child(_smoke)
		wrecked.emit()


func forward() -> Vector3:
	return Vector3(cos(heading), 0, -sin(heading))


## AI: follow the lane to node b, then pick a next road (not straight back unless a dead end).
## Slows for anything close ahead in its path: other vehicles, the player, people crossing.
func ai_step(delta: float) -> void:
	var map: MapData = world.map
	var pa: Vector2 = map.road_nodes[a]
	var pb: Vector2 = map.road_nodes[b]
	var dir := (pb - pa).normalized()
	var target := Terrain3D.w(pb + Vector2(-dir.y, dir.x) * LANE_PX)
	var to := target - position
	to.y = 0.0
	if to.length() < 3.0:
		var nbs: Array = (map.road_graph.get(b, []) as Array).filter(func(x: String) -> bool: return x != a)
		if nbs.is_empty():
			nbs = [a]
		a = b
		if mode == Mode.FLEE:
			# A getaway driver takes the road that leads furthest from the player.
			var f: Vector3 = world.focus()
			var best: String = nbs[0]
			for n: String in nbs:
				if Terrain3D.w(map.road_nodes[n]).distance_to(f) > Terrain3D.w(map.road_nodes[best]).distance_to(f):
					best = n
			b = best
		else:
			b = nbs[randi() % nbs.size()]
		return
	var want := -Vector2(to.x, to.z).angle()
	heading = lerp_angle(heading, want, minf(1.0, delta * 2.5))
	var limit := cruise
	if mode == Mode.FLEE:
		limit = float(spec["top"]) * 0.82 # no manners: doesn't slow for traffic
	else:
		var ahead: float = world.clear_ahead(self)
		if ahead < 14.0:
			limit = cruise * clampf((ahead - 4.0) / 10.0, 0.0, 1.0)
	speed = move_toward(speed, limit, (6.0 if limit > speed else 14.0) * delta)
	rotation.y = heading
	position += forward() * speed * delta


## CHASE: follow the roads towards the player, then go straight for them when close (and ram).
func chase_step(delta: float) -> void:
	if is_wreck:
		return
	var map: MapData = world.map
	var f: Vector3 = world.focus()
	var to_f := f - position
	to_f.y = 0.0
	var target := f
	if to_f.length() > 28.0:
		if b == "" or not map.road_nodes.has(b):
			_nearest_node()
		var pb := Terrain3D.w(map.road_nodes[b])
		if Vector2(pb.x - position.x, pb.z - position.z).length() < 6.0:
			var nbs: Array = map.road_graph.get(b, [])
			var best := b
			for n: String in nbs:
				if Terrain3D.w(map.road_nodes[n]).distance_to(f) < Terrain3D.w(map.road_nodes[best]).distance_to(f):
					best = n
			a = b
			b = best if best != b else (nbs[randi() % nbs.size()] if not nbs.is_empty() else b)
			pb = Terrain3D.w(map.road_nodes[b])
		target = pb
	var to := target - position
	to.y = 0.0
	heading = lerp_angle(heading, -Vector2(to.x, to.z).angle(), minf(1.0, delta * 2.2))
	speed = move_toward(speed, float(spec["top"]) * 0.85, float(spec["accel"]) * delta)
	_move(delta)


func _nearest_node() -> void:
	var map: MapData = world.map
	var bd := INF
	for id in map.road_nodes:
		var d := Terrain3D.w(map.road_nodes[id]).distance_squared_to(position)
		if d < bd:
			bd = d
			b = id
	a = b
