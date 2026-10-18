class_name Vehicle3D
extends CharacterBody3D
## One vehicle in the 3D city (D-020): AI traffic on the road graph, the player's ride, or parked.
## Forward is +X of the node; heading h points along (cos h, 0, -sin h), so rotation.y = h.
## Lagos drives on the right: AI keeps to the right-hand lane of each road.

enum Mode { AI, PLAYER, PARKED }

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
	move_and_slide()
	if get_slide_collision_count() > 0:
		speed *= 0.5
	position.y = lerpf(position.y, world.terrain.height_at(position), minf(1.0, delta * 10.0))


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
		b = nbs[randi() % nbs.size()]
		return
	var want := -Vector2(to.x, to.z).angle()
	heading = lerp_angle(heading, want, minf(1.0, delta * 2.5))
	var limit := cruise
	var ahead: float = world.clear_ahead(self)
	if ahead < 14.0:
		limit = cruise * clampf((ahead - 4.0) / 10.0, 0.0, 1.0)
	speed = move_toward(speed, limit, (6.0 if limit > speed else 14.0) * delta)
	rotation.y = heading
	position += forward() * speed * delta
