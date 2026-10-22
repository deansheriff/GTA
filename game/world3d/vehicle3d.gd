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
var on_water := false # boats: drive only on the lagoon and creeks
var fuel := 1.0 # 0..1 of a tank (the player's rides use it up; D-028)
var hostile := false # a mission's enemy boat or car: shoots at Dayo, can be shot
var gunners := 0 # how many armed men ride in it (hostile vehicles fire this often)
var hp_max := 100.0
var _steer := 0.0
var _slip := Vector3.ZERO # sideways slide left over from the last turn (drifting)
var _ap: AnimationPlayer # horses: walk/gallop
var _bob := 0.0
var _model: Node3D
var _gun_cool := 0.0
## Handling and body (D-032): each kind drives like itself.
var hd: Dictionary
var _last_speed := 0.0
var _pitch := 0.0
var _roll := 0.0
var braking := false
var _tail_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _wake: CPUParticles3D
var _honk_t := 0.0 # AI: how long the player has blocked me
var _skid_cool := 0.0
var _bubble: Label3D
var _bubble_t := 0.0
var _overtake := 0.0 # seconds left in an overtake
var rider: Node3D # whoever sits at the wheel or on the saddle (Seat3D)
var _lane_off := 0.0
var _lane_prev := 0.0

## grip: how fast a slide stops; brake and coast: decelerations (m/s²); steer: how fast the wheel
## turns; roll/pitch: how far the body leans and dips; lean: bikes lean into turns, cars roll out.
const HANDLING := {
	"danfo": { "grip": 4.5, "brake": 7.0, "coast": 3.0, "steer": 3.5, "roll": 0.05, "pitch": 0.045 },
	"bus": { "grip": 4.0, "brake": 4.5, "coast": 2.2, "steer": 2.5, "roll": 0.045, "pitch": 0.05, "air": true },
	"truck": { "grip": 4.0, "brake": 4.0, "coast": 2.0, "steer": 2.5, "roll": 0.04, "pitch": 0.05, "air": true },
	"tanker": { "grip": 3.8, "brake": 3.6, "coast": 2.0, "steer": 2.3, "roll": 0.04, "pitch": 0.05, "air": true },
	"okada": { "grip": 10.0, "brake": 12.0, "coast": 4.0, "steer": 8.0, "roll": 0.0, "pitch": 0.03, "lean": 0.35 },
	"keke": { "grip": 5.0, "brake": 8.0, "coast": 4.0, "steer": 6.0, "roll": 0.09, "pitch": 0.04 },
	"speedboat": { "grip": 1.6, "brake": 1.8, "coast": 1.2, "steer": 3.0, "roll": 0.05, "pitch": 0.12, "lean": 0.12 },
	"canoe": { "grip": 1.4, "brake": 2.0, "coast": 1.5, "steer": 2.5, "roll": 0.03, "pitch": 0.03 },
	"yacht": { "grip": 1.0, "brake": 0.8, "coast": 0.6, "steer": 1.0, "roll": 0.01, "pitch": 0.02 },
	"horse": { "grip": 12.0, "brake": 14.0, "coast": 6.0, "steer": 7.0, "roll": 0.0, "pitch": 0.0 },
}
const CAR := { "grip": 6.5, "brake": 10.0, "coast": 4.0, "steer": 5.0, "roll": 0.035, "pitch": 0.03 }


func setup(lib: Models3D, k: String, w) -> void:
	kind = k
	world = w
	spec = Models3D.VEHICLES.get(k, Models3D.VEHICLES["car"])
	var size: Vector2 = spec["size"]
	length = size.x
	on_water = bool(spec.get("water", false))
	cruise = float(spec["top"]) * randf_range(0.55, 0.75)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 1.8 if size.x > 3.0 else 1.4, size.y)
	shape.shape = box
	shape.position.y = box.size.y * 0.5 + 0.1
	add_child(shape)
	var m := lib.make(spec["model"], String(spec.get("dir", Models3D.ART)))
	var model: Node3D
	if m:
		_ap = Models3D.find_player(m)
		model = Models3D.fit_vehicle(m, size)
		if not bool(spec.get("anim", false)):
			Models3D.glossy(model)
	else:
		model = _box_model(size)
	add_child(model)
	_model = model
	hd = HANDLING.get(k, CAR)
	if not "--no-dress" in OS.get_cmdline_user_args():
		_dress(model, size)
	if _ap:
		for a in _ap.get_animation_list():
			_ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		Models3D.play(_ap, "Idle", "")
	Models3D.far_cull(model, 200.0)
	collision_layer = 2
	collision_mask = 1 | 2


## Details the generated models lack: headlights, tail and brake lights, mirrors, number plates,
## a headlight beam after dark, and a soft shadow underneath. One mesh with a few surfaces, culled
## beyond 70 m.
func _dress(model: Node3D, size: Vector2) -> void:
	Blob3D.add(self, Vector2(size.x * 1.15, size.y * 1.35)).visibility_range_end = 90.0
	if kind in ["horse", "canoe", "yacht"]:
		return
	var bb := Models3D.aabb(model)
	var front := bb.end.x
	var back := bb.position.x
	var h := bb.size.y
	var w := bb.size.z
	var y0 := bb.position.y
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.06, 0.06, 0.07)
	black.roughness = 0.3
	black.metallic = 0.4
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(0.95, 0.95, 0.9)
	head.emission_enabled = true
	head.emission = Color("#fff6dc")
	head.emission_energy_multiplier = 1.2
	_tail_mat = StandardMaterial3D.new()
	_tail_mat.albedo_color = Color(0.6, 0.05, 0.04)
	_tail_mat.emission_enabled = true
	_tail_mat.emission = Color("#ff2414")
	_tail_mat.emission_energy_multiplier = 0.5
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.95, 0.94, 0.88)
	plate.roughness = 0.5
	var parts := { black: [], head: [], _tail_mat: [], plate: [] }
	var bike := kind == "okada"
	var hy := y0 + h * (0.55 if bike else 0.36)
	if on_water:
		# Navigation lights: red to port, green to starboard, white at the stern.
		var red := StandardMaterial3D.new()
		red.emission_enabled = true
		red.emission = Color("#ff2a1a")
		red.emission_energy_multiplier = 3.0
		var green := StandardMaterial3D.new()
		green.emission_enabled = true
		green.emission = Color("#2aff5a")
		green.emission_energy_multiplier = 3.0
		parts[red] = [[Vector3(0.12, 0.12, 0.12), Vector3(front * 0.3, y0 + h * 0.8, -w * 0.45)]]
		parts[green] = [[Vector3(0.12, 0.12, 0.12), Vector3(front * 0.3, y0 + h * 0.8, w * 0.45)]]
		parts[head] = [[Vector3(0.12, 0.12, 0.12), Vector3(back + 0.2, y0 + h * 0.85, 0)]]
	elif bike:
		parts[head] = [[Vector3(0.08, 0.14, 0.14), Vector3(front - 0.05, hy, 0)]]
		parts[_tail_mat] = [[Vector3(0.05, 0.07, 0.12), Vector3(back + 0.05, y0 + h * 0.45, 0)]]
		parts[black] = [[Vector3(0.04, 0.04, 0.5), Vector3(front - 0.35, y0 + h * 0.75, 0)]]
	else:
		for s in [-1.0, 1.0]:
			parts[head].append([Vector3(0.06, 0.16, w * 0.2), Vector3(front - 0.02, hy, s * w * 0.32)])
			parts[_tail_mat].append([Vector3(0.06, 0.18, w * 0.14), Vector3(back + 0.02, y0 + h * 0.4, s * w * 0.36)])
			# Side mirrors on short stalks.
			parts[black].append([Vector3(0.14, 0.11, 0.06), Vector3(front - (front - back) * 0.27, y0 + h * 0.62, s * (w * 0.5 + 0.1))])
		parts[plate].append([Vector3(0.03, 0.12, 0.42), Vector3(front + 0.005, y0 + h * 0.22, 0)])
		parts[plate].append([Vector3(0.03, 0.12, 0.42), Vector3(back - 0.005, y0 + h * 0.28, 0)])
		parts[black].append([Vector3(0.035, 0.03, 0.4), Vector3(front + 0.008, y0 + h * 0.22, 0)])
		parts[black].append([Vector3(0.035, 0.03, 0.4), Vector3(back - 0.008, y0 + h * 0.28, 0)])
	var mesh := ArrayMesh.new()
	var mats: Array = []
	for mat: Material in parts:
		var list: Array = parts[mat]
		if list.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for pc: Array in list:
			var bm := BoxMesh.new()
			bm.size = pc[0]
			st.append_from(bm, 0, Transform3D(Basis(), pc[1]))
		st.commit(mesh)
		mats.append(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 70.0
	model.add_child(mi)
	if not on_water:
		# The headlight beam: a faint cone of light down the road after dark.
		_beam = MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.15
		cone.bottom_radius = 2.2
		cone.height = 9.0
		cone.radial_segments = 10
		cone.rings = 1
		cone.cap_top = false
		cone.cap_bottom = false
		_beam.mesh = cone
		_beam.material_override = _beam_mat()
		_beam.rotation.z = -PI * 0.5 - 0.06
		_beam.position = Vector3(front + 4.5, hy - 0.25, 0)
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.visibility_range_end = 120.0
		_beam.visible = false
		model.add_child(_beam)


static var _beam_shared: StandardMaterial3D


static func _beam_mat() -> StandardMaterial3D:
	if _beam_shared == null:
		_beam_shared = StandardMaterial3D.new()
		_beam_shared.albedo_color = Color(1.0, 0.95, 0.8, 0.07)
		_beam_shared.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_shared.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_shared.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_shared.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_shared.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _beam_shared


## Put someone in the driver's seat (or on the saddle), seated (Seat3D). key "" empties it.
func set_rider(lib: Models3D, key: String, tone := 2) -> void:
	clear_rider()
	if key == "" or _model == null:
		return
	rider = Seat3D.make_rider(lib, key, kind, tone)
	if rider:
		_model.add_child(rider)
		Models3D.far_cull(rider, 70.0)
		Seat3D.apply.call_deferred(rider)


func clear_rider() -> void:
	if rider and is_instance_valid(rider):
		rider.queue_free()
	rider = null


## A line over a vehicle for a moment ("Comot for road!").
func shout(text: String, secs := 2.0) -> void:
	if _bubble == null:
		_bubble = Label3D.new()
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.font_size = 44
		_bubble.pixel_size = 0.008
		_bubble.outline_size = 8
		_bubble.modulate = Color("#fff4d6")
		_bubble.position = Vector3(0, 3.2, 0)
		add_child(_bubble)
	_bubble.text = text
	_bubble.visible = true
	_bubble_t = secs


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


## Player driving: throttle -1..1, steer -1..1 (positive = right). Steering eases in (no twitchy
## phone thumbs), turns less at speed, and fast turns slide a little before the tyres bite
## (boats slide a lot). An empty tank leaves only a crawl.
func drive(throttle: float, steer: float, delta: float) -> void:
	var top: float = spec["top"] * (0.25 if fuel <= 0.0 else 1.0)
	var accel: float = spec["accel"]
	var was := speed
	braking = false
	if absf(throttle) > 0.05:
		braking = throttle * speed < 0.0
		# Heavy vehicles take their time to stop; a bike or a horse stops on a coin.
		speed = move_toward(speed, top * throttle * (1.0 if throttle > 0.0 else 0.35), (float(hd["brake"]) if braking else accel) * delta)
	else:
		speed = move_toward(speed, 0.0, float(hd["coast"]) * delta)
	# Water drags on a turning boat.
	if on_water:
		speed *= 1.0 - absf(_steer) * 0.22 * delta
	_steer = move_toward(_steer, steer, delta * float(hd["steer"]))
	var at_speed := clampf(absf(speed) / float(spec["top"]), 0.0, 1.0)
	var turn := _steer * float(spec["turn"]) * delta * clampf(absf(speed) / 5.0, 0.0, 1.0) * (1.15 - at_speed * 0.4)
	heading -= turn * signf(speed if speed != 0.0 else 1.0)
	# Drift: part of a hard turn at speed carries on sideways, then grips again.
	var side := Vector3(-sin(heading), 0, -cos(heading))
	_slip += side * turn * speed * (0.9 if on_water else 0.45)
	_slip = _slip.lerp(Vector3.ZERO, minf(1.0, delta * float(hd["grip"])))
	# Braking feedback: the tyres squeal on a hard stop, big vehicles hiss their air brakes.
	_skid_cool = maxf(0.0, _skid_cool - delta)
	if braking and absf(was) > 11.0 and _skid_cool <= 0.0 and not on_water and kind != "horse":
		_skid_cool = 1.2
		Sound.sfx("airbrake" if hd.get("air", false) else "skid", randf_range(0.95, 1.05))
	elif _slip.length() > 4.0 and _skid_cool <= 0.0 and not on_water and kind != "horse":
		_skid_cool = 1.0
		Sound.sfx("skid", 1.15)
	fuel = maxf(0.0, fuel - absf(speed) * delta / 26000.0) # a tank lasts about 26 km
	_move(delta)


func _move(delta: float) -> void:
	rotation.y = heading
	velocity = Vector3(cos(heading), 0, -sin(heading)) * speed + _slip
	# Boats stay on the water and cars on land (the lagoon has no collision of its own).
	if world and world.map and absf(speed) > 0.1:
		var ahead := position + Vector3(cos(heading), 0, -sin(heading)) * signf(speed) * (length * 0.5 + 0.6) + velocity * delta
		if world.is_water_at(ahead) != on_water and not (not on_water and _bridge_at(ahead)):
			speed = -speed * 0.2
			_slip = Vector3.ZERO
			velocity = Vector3.ZERO
	var impact := absf(speed)
	move_and_slide()
	_animate(delta)
	_bump_t = maxf(0.0, _bump_t - delta)
	if get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			var other := get_slide_collision(i).get_collider()
			if other is Vehicle3D and impact > 4.0 and _bump_t <= 0.0:
				_bump_t = 0.5
				(other as Vehicle3D).damage(impact * 2.6)
				damage(impact * 0.9)
				if mode == Mode.PLAYER:
					Sound.sfx("crash", randf_range(0.9, 1.1))
				else:
					Sound.sfx_at("crash", position, randf_range(0.9, 1.1))
				if world and world.has_method("shake"):
					world.shake(0.25)
				if mode == Mode.PLAYER and world.has_method("on_bump"):
					world.on_bump(other)
			elif other is StaticBody3D and impact > 9.0 and _bump_t <= 0.0:
				_bump_t = 0.5
				damage(impact * 0.8)
				Sound.sfx("crash", 0.8)
		speed *= -0.25 if impact > 6.0 else 0.5 # a hard hit bounces you back a little
	var ground: float = -0.18 if on_water else world.terrain.height_at(position)
	position.y = lerpf(position.y, ground, minf(1.0, delta * 10.0))


func _bridge_at(p: Vector3) -> bool:
	var s: int = world.map.surface_at(Vector2(p.x, p.z) / Terrain3D.K)
	return s == MapData.S.BRIDGE


## The body on its springs: it dips its nose under braking and squats under power, rolls out of a
## turn (bikes and boats lean in), and boats rock on the swell. Horses walk and gallop. The brake
## lights come on when slowing hard; the headlight beam shows after dark.
func _animate(delta: float) -> void:
	if _ap:
		var s := absf(speed)
		Models3D.play(_ap, "Gallop" if s > 7.0 else ("Walk" if s > 0.6 else "Idle"), "Idle", clampf(s / (11.0 if s > 7.0 else 2.5), 0.6, 1.6) if s > 0.6 else 1.0)
	if _model == null or delta <= 0.0:
		return
	var acc := (speed - _last_speed) / delta
	_last_speed = speed
	if mode != Mode.PLAYER:
		braking = acc < -3.0
	var want_pitch := clampf(acc * float(hd["pitch"]) * 0.06, -0.09, 0.07) * signf(speed if speed != 0.0 else 1.0)
	if on_water:
		want_pitch = clampf(absf(speed) / 24.0, 0.0, 1.0) * float(hd["pitch"]) # the bow lifts at speed
	var turn_rate := _steer * absf(speed) if mode == Mode.PLAYER else 0.0
	var want_roll := clampf(turn_rate * float(hd["roll"]) * 0.06, -0.08, 0.08)
	if hd.has("lean"):
		want_roll = clampf(-turn_rate * float(hd["lean"]) * 0.05, -0.45, 0.45)
	_pitch = lerpf(_pitch, want_pitch, minf(1.0, delta * 6.0))
	_roll = lerpf(_roll, want_roll, minf(1.0, delta * 5.0))
	var bob_x := 0.0
	var bob_z := 0.0
	if on_water:
		_bob += delta * (1.4 + absf(speed) * 0.05)
		bob_x = sin(_bob) * 0.03
		bob_z = sin(_bob * 0.7) * 0.025
		if _wake == null and (mode == Mode.PLAYER or hostile):
			_make_wake()
		if _wake:
			_wake.emitting = absf(speed) > 3.0
	_model.rotation.z = _pitch + bob_z
	_model.rotation.x = _roll + bob_x
	if _tail_mat:
		_tail_mat.emission_energy_multiplier = 3.2 if braking and absf(speed) > 0.5 else (0.9 if world and world._dark > 0.4 else 0.35)
	if _beam:
		_beam.visible = world != null and world._dark > 0.45 and not is_wreck
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0 and _bubble:
			_bubble.visible = false


func _make_wake() -> void:
	_wake = CPUParticles3D.new()
	_wake.amount = 30
	_wake.lifetime = 1.4
	_wake.direction = Vector3(-1, 0.4, 0)
	_wake.spread = 25.0
	_wake.initial_velocity_min = 1.0
	_wake.initial_velocity_max = 2.5
	_wake.gravity = Vector3(0, -2.0, 0)
	_wake.scale_amount_min = 0.3
	_wake.scale_amount_max = 0.8
	var q := SphereMesh.new()
	q.radius = 0.4
	q.height = 0.3
	q.radial_segments = 6
	q.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.97, 1.0, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	_wake.mesh = q
	_wake.position = Vector3(-length * 0.5, 0.1, 0)
	_wake.emitting = false
	add_child(_wake)


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
			# Stuck behind Dayo: a horn, then words.
			if world.blocker_is_player(self):
				_honk_t += delta
				if _honk_t > 2.5:
					_honk_t = -4.0
					if position.distance_to(world.focus()) < 30.0:
						Sound.sfx_at("horn", position, randf_range(0.9, 1.1))
					shout(["Comot for road!", "Oga, move now!", "You dey sleep?", "Na your papa get road?"][randi() % 4])
			# Stuck behind a slow vehicle on a long straight: pull out and overtake.
			elif ahead < 8.0 and _overtake <= 0.0 and to.length() > 40.0 and world.oncoming_clear(self):
				_overtake = 3.5
		else:
			_honk_t = maxf(0.0, _honk_t - delta)
		# Easing off before a junction without lights.
		if world.signals and to.length() < 22.0 and world.is_junction(b) and not world.signals.junctions.has(b):
			limit = minf(limit, cruise * 0.6)
		# Red light at the junction ahead: stop at the line (D-028 junction rules).
		if world.signals and world.signals.must_stop(self, to.length()):
			limit = minf(limit, clampf((to.length() - 9.0) * 0.8, 0.0, cruise))
		limit *= float(world.roam.goslow_k(position)) if world.roam else 1.0
	if _overtake > 0.0:
		_overtake -= delta
		limit = maxf(limit, cruise * 1.25)
	speed = move_toward(speed, limit, (6.0 if limit > speed else 14.0) * delta)
	rotation.y = heading
	# Overtaking: drift over to the other lane, pass, and come back in.
	var want_lane := -2.0 * Terrain3D.K * LANE_PX if _overtake > 0.6 else 0.0
	_lane_off = move_toward(_lane_off, want_lane, delta * 1.6)
	var side := Vector3(-forward().z, 0, forward().x)
	position += forward() * speed * delta + side * (_lane_off - _lane_prev)
	_lane_prev = _lane_off
	_animate(delta)


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
	if on_water:
		target = f # boats cut straight across the water
	var to := target - position
	to.y = 0.0
	heading = lerp_angle(heading, -Vector2(to.x, to.z).angle(), minf(1.0, delta * 2.2))
	var want := float(spec["top"]) * 0.85
	if hostile and to_f.length() < 14.0:
		want = float(spec["top"]) * 0.45 # gunboats hold off and shoot rather than ram
	speed = move_toward(speed, want, float(spec["accel"]) * delta)
	_move(delta)
	if hostile and gunners > 0:
		_gun_cool -= delta
		if _gun_cool <= 0.0 and to_f.length() < 34.0:
			_gun_cool = randf_range(1.2, 2.2) / gunners
			world.combat.vehicle_fires(self)


func _nearest_node() -> void:
	var map: MapData = world.map
	var bd := INF
	for id in map.road_nodes:
		var d := Terrain3D.w(map.road_nodes[id]).distance_squared_to(position)
		if d < bd:
			bd = d
			b = id
	a = b
