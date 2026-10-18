class_name Street3D
extends Node3D
## Naija Street Life: Èkó Ò Ní Bàjẹ́ (D-020, D-021). The whole game: Lagos in 3D, built from the map
## data and the Meshy models. Boots to the main menu over the living city; New game plays the
## prologue and the campaign (Mission3D), Continue resumes the save. Between missions, free roam:
## walk as Dayo, take any vehicle, run danfo fares, dodge checkpoints. Compatibility renderer.

const CELL_M := Terrain3D.CELL_M
const ENTER_RANGE := 3.6

## Crowd sizes and draw distance follow the graphics preset (Settings: low / medium / high).
var traffic_n := 26
var people_n := 36
var q_far := 1.0

var map: MapData
var models := Models3D.new()
var terrain: Terrain3D
var city: City3D
var player: Player3D
var ride: Vehicle3D # the vehicle the player is driving, or null
var vehicles: Array[Vehicle3D] = []
var people: Array[Person3D] = []
var people_keys: Array = []
var cam: Camera3D
var cam_yaw := 0.0
var run: DanfoRun3D
var lights: Lights3D
var checkpoints: Checkpoint3D
var stage: Stage3D
var combat: Combat3D
var missions: Mission3D
var hud: Hud3D
var police: Police3D
var mission_vehicles: Array[Vehicle3D] = []
var in_menu := true
var _look_t := 0.0
var _shake := 0.0
var _dark := 0.0
var _run_held := false
var _rng := RandomNumberGenerator.new()
var _fps_t := 0.0
var _frames := 0
var _recycle_t := 0.0
var _walk_cells: Array[Vector2i] = []
var _menu_t := 0.0
var _save_ok := true
var _env: Environment
var _sun: DirectionalLight3D
var _sky: ProceduralSkyMaterial
# QA demo inputs (--shots)
var demo_stick := Vector2.ZERO
var demo_drive := Vector2.ZERO


func _ready() -> void:
	_rng.seed = 2026
	_quality()
	map = MapData.shared()
	_environment()
	terrain = Terrain3D.new()
	add_child(terrain)
	terrain.build(map)
	city = City3D.new()
	add_child(city)
	city.far_scale = q_far
	city.build(map, models)
	for y in map.rows:
		for x in map.cols:
			if map.surface[y * map.cols + x] == MapData.S.WALK:
				_walk_cells.append(Vector2i(x, y))
	_spawn_player()
	_spawn_traffic()
	_spawn_people()
	run = DanfoRun3D.new()
	add_child(run)
	run.setup(self)
	run.message.connect(notify)
	run.paid.connect(_save_game)
	lights = Lights3D.new()
	add_child(lights)
	lights.build(self)
	checkpoints = Checkpoint3D.new()
	add_child(checkpoints)
	checkpoints.setup(self)
	checkpoints.message.connect(notify)
	checkpoints.charged.connect(_save_game)
	stage = Stage3D.new()
	add_child(stage)
	stage.setup(self)
	combat = Combat3D.new()
	add_child(combat)
	combat.setup(self)
	missions = Mission3D.new()
	add_child(missions)
	missions.setup(self)
	missions.mission_done.connect(_on_mission_done)
	police = Police3D.new()
	add_child(police)
	police.setup(self)
	checkpoints.charged.connect(func() -> void:
		if ride and absf(ride.speed) > 3.0:
			police.raise(1.0))
	hud = Hud3D.new()
	add_child(hud)
	hud.setup(self)
	hud.action_pressed.connect(_action)
	hud.punch_pressed.connect(combat.player_attack)
	hud.shoot_pressed.connect(_shoot)
	hud.run_changed.connect(func(h: bool) -> void: _run_held = h)
	hud.new_game.connect(_new_game)
	hud.continue_game.connect(_continue_game)
	_register_save()
	_apply_quality_env()
	_day_night()
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
	if shots != "":
		_shots(shots)
	else:
		hud.show_menu(FileAccess.file_exists(SaveGame.PATH))
		Sound.music("highlife")


# ---------- save ----------

func _register_save() -> void:
	SaveGame.world_provider = _world_state
	SaveGame.world_restorer = _restore_world
	SaveGame.extra_providers = { "story": Story.to_dict, "street": Street.to_dict }
	SaveGame.extra_restorers = { "story": Story.from_dict, "street": Street.from_dict }


func _world_state() -> Dictionary:
	var p := focus()
	return { "pos": [p.x, p.z], "model": player.model_key }


func _restore_world(d: Dictionary) -> void:
	var p: Array = d.get("pos", [])
	if p.size() == 2:
		player.position = Vector3(float(p[0]), terrain.height_at(Vector3(float(p[0]), 0, float(p[1]))), float(p[1]))
	player.set_model(String(d.get("model", "dayo")))


func _save_game() -> void:
	if _save_ok:
		SaveGame.save_now()


func _new_game() -> void:
	in_menu = false
	SaveGame.wipe()
	Story.reset()
	Sound.music("")
	missions.run("p0")


func _continue_game() -> void:
	in_menu = false
	SaveGame.load_local()
	Sound.music("")
	# A mission interrupted by quitting starts again from its beginning.
	var id := Story.current
	if id != "" and Story.playable(id):
		missions.run(id)
	else:
		_next_mission_marker()


func _on_mission_done(id: String) -> void:
	_save_game()
	var nxt := Story.next_mission()
	if nxt == "":
		notify("You've played every chapter so far. More of the story is coming.")
		return
	var m: Dictionary = Story.mission(nxt)
	if Story.playable(nxt) and not m.has("start"):
		missions.run(nxt)
	else:
		_next_mission_marker()


## Free roam until the player reaches the next mission's marker.
func _next_mission_marker() -> void:
	var nxt := Story.next_mission()
	if nxt == "" or not Story.playable(nxt):
		stage.set_marker(null)
		if nxt != "":
			set_objective("Next: %s (coming soon). Free roam: drive danfo, explore Lagos." % String(Story.mission(nxt).get("title", "")), null)
		return
	var m: Dictionary = Story.mission(nxt)
	var at: Vector3 = resolve({ "at": m.get("start", "player") })
	stage.set_marker(at, String(m.get("title", "")))
	set_objective("Next mission: %s · %s" % [String(m.get("title", "")), String(m.get("where", ""))], at)


# ---------- quality ----------

func _quality() -> void:
	var g: Dictionary = Settings.current
	var dd := int(g.get("draw_distance", 2))
	q_far = [0.65, 0.65, 0.85, 1.0][clampi(dd, 0, 3)]
	people_n = clampi(int(g.get("max_npcs", 30)), 10, 36)
	traffic_n = [14, 14, 22, 28][clampi(dd, 0, 3)]


func _apply_quality_env() -> void:
	var g: Dictionary = Settings.current
	var shadows := String(g.get("shadows", "blob"))
	_sun.shadow_enabled = shadows != "none"
	_sun.directional_shadow_max_distance = 70.0 if shadows == "painted" else 40.0
	_env.glow_enabled = String(g.get("effects", "low")) != "off"
	_env.fog_depth_begin = 90.0 * q_far
	_env.fog_depth_end = 175.0 * q_far


## Settings changed in a menu: lighting and haze update now; crowd sizes on the next start.
func apply_quality() -> void:
	_quality()
	_apply_quality_env()


# ---------- helpers the actors use ----------

func is_walk(c: Vector2i) -> bool:
	return map.in_bounds(c) and map.surface[c.y * map.cols + c.x] == MapData.S.WALK


func cell_pos(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL_M, Terrain3D.WALK_H, (c.y + 0.5) * CELL_M)


func focus() -> Vector3:
	return ride.position if ride else player.position


## Distance to the nearest thing in front of a vehicle, in its lane (99 if clear).
func clear_ahead(v: Vehicle3D) -> float:
	var best := 99.0
	var fwd := v.forward()
	var bodies: Array = []
	bodies.append_array(vehicles)
	bodies.append(player)
	for o in bodies:
		if o == v or not (o as Node3D).visible:
			continue
		var rel: Vector3 = (o as Node3D).position - v.position
		rel.y = 0.0
		var ahead := rel.dot(fwd)
		if ahead <= 0.0 or ahead > 30.0:
			continue
		var lateral := absf(rel.dot(Vector3(-fwd.z, 0, fwd.x)))
		var half := (o as Vehicle3D).length * 0.5 if o is Vehicle3D else 0.5
		if lateral < 2.0:
			best = minf(best, ahead - v.length * 0.5 - half)
	return best


# ---------- the story's stage directions (Mission3D calls these) ----------

## A step's position: "landmark:id", "node:id", "player", or [x, z] metres; plus "offset" [dx, dz].
func resolve(st: Dictionary) -> Vector3:
	var at: Variant = st.get("at", "player")
	var p := player.position
	if at is Array and (at as Array).size() == 2:
		p = Vector3(float(at[0]), 0, float(at[1]))
	elif at is String:
		var s := String(at)
		if s.begins_with("landmark:") and map.landmarks.has(s.substr(9)):
			p = Terrain3D.w(map.landmarks[s.substr(9)]["pos"])
		elif s.begins_with("node:") and map.road_nodes.has(s.substr(5)):
			p = Terrain3D.w(map.road_nodes[s.substr(5)])
	var off: Array = st.get("offset", [0, 0])
	p += Vector3(float(off[0]), 0, float(off[1]))
	p.y = terrain.height_at(p)
	return p


## Put Dayo somewhere: on foot, or at the wheel of a fresh vehicle (with its painted slogan).
func place_player(pos: Vector3, vehicle_kind := "", slogan := "") -> void:
	if ride and vehicle_kind == "":
		_action() # get out first
	if vehicle_kind == "":
		player.position = pos
		return
	var v := Vehicle3D.new()
	add_child(v)
	v.setup(models, vehicle_kind, self)
	# Onto the nearest road, pointing along it.
	var best := ""
	var bd := INF
	for id in map.road_nodes:
		var d := Terrain3D.w(map.road_nodes[id]).distance_squared_to(pos)
		if d < bd and not (map.road_graph.get(id, []) as Array).is_empty():
			bd = d
			best = id
	if best != "":
		v.place_on_road(best, map.road_graph[best][0], 0.15)
	else:
		v.position = pos
	v.mode = Vehicle3D.Mode.PARKED
	v.speed = 0.0
	if slogan != "":
		_paint_slogan(v, slogan)
	vehicles.append(v)
	if ride:
		_action()
	player.position = v.position + Vector3(0, 0, 2.0)
	_enter(v)


func _paint_slogan(v: Vehicle3D, text: String) -> void:
	for side in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = text
		l.font_size = 48
		l.pixel_size = 0.006
		l.modulate = Color("#1d1611")
		l.outline_size = 0
		l.position = Vector3(0, 1.35, 1.12 * side)
		l.rotation.y = 0.0 if side > 0 else PI
		v.add_child(l)


## A vehicle a mission needs (a fleeing one-chance bus, chasing customs pickups, a convoy lead),
## put on the nearest road pointing along it. Cleared when the mission ends.
func spawn_mission_vehicle(kind: String, pos: Vector3, mode: int, slogan := "") -> Vehicle3D:
	var v := Vehicle3D.new()
	add_child(v)
	v.setup(models, kind, self)
	var best := ""
	var bd := INF
	for id in map.road_nodes:
		var d := Terrain3D.w(map.road_nodes[id]).distance_squared_to(pos)
		if d < bd and not (map.road_graph.get(id, []) as Array).is_empty():
			bd = d
			best = id
	if best != "" and mode != Vehicle3D.Mode.CHASE:
		var nbs: Array = map.road_graph[best]
		# Head away from the player (a getaway driver) or along the first road.
		var pick: String = nbs[0]
		for n: String in nbs:
			if Terrain3D.w(map.road_nodes[n]).distance_to(focus()) > Terrain3D.w(map.road_nodes[pick]).distance_to(focus()):
				pick = n
		v.place_on_road(best, pick, 0.2)
	else:
		v.position = pos
		v.position.y = 0.0
	v.mode = mode
	if slogan != "":
		_paint_slogan(v, slogan)
	vehicles.append(v)
	mission_vehicles.append(v)
	return v


func clear_mission_vehicles() -> void:
	for v in mission_vehicles:
		if v != ride and is_instance_valid(v):
			vehicles.erase(v)
			v.queue_free()
	mission_vehicles.clear()


func teleport_ride(pos: Vector3) -> void:
	if ride:
		ride.position = pos
		ride.speed = 0.0
	else:
		player.position = pos


func spawn_actor(id: String, who: String, pos: Vector3, anim := "idle", face := "", prop := "", model := "") -> Person3D:
	return stage.spawn(id, who, pos, anim, face, prop, model)


func despawn_actor(id: String) -> void:
	stage.despawn(id)


func clear_actors() -> void:
	stage.clear()


func set_env(night: bool, rain: bool) -> void:
	stage.set_env(night, rain)
	_day_night()


func show_title(text: String, sub := "", secs := 2.5, col := UiStyle.DANFO) -> void:
	await hud.show_title(text, sub, secs, col)


func say(lines: Array) -> Array:
	return await hud.say(lines)


func notify(text: String) -> void:
	hud.notify(text)


func black(secs: float) -> void:
	await hud.black(secs)


func cam_mode(mode: String, at: Vector3) -> void:
	stage.cam_override = mode
	stage.cam_target = at


func force_exit() -> void:
	if ride:
		_action()


func set_objective(text: String, target: Variant) -> void:
	hud.set_objective(text)
	run.story_target = target


func mission_banner(m: Dictionary) -> void:
	var act := int(m.get("act", 0))
	hud.notify(Story.act_title(act) if act == 0 else "%s: %s" % [Story.act_title(act), String(m.get("title", ""))])


func retry_from(snap: Vector3) -> void:
	combat.clear()
	player.position = snap
	if ride:
		ride.speed = 0.0


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Autopilot (tests): load at the nearest stop, then arrive at the destination a moment later.
func autopilot_fare() -> void:
	_autopilot_fare.call_deferred()


func _autopilot_fare() -> void:
	if ride == null:
		return
	var s := run.nearest_stop(ride.position)
	ride.position = run.stops[s]["pos"]
	ride.speed = 0.0
	await get_tree().create_timer(1.6).timeout
	if run.dest >= 0:
		ride.position = run.stops[run.dest]["pos"]
		ride.speed = 0.0


# ---------- world ----------

func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color("#4f8fd0")
	mat.sky_horizon_color = Color("#d6e4ea")
	mat.ground_horizon_color = Color("#c9b99a")
	mat.sun_angle_max = 20.0
	sky.sky_material = mat
	_sky = mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.04
	env.adjustment_contrast = 1.05
	# Harmattan-ish haze hides where far buildings and props are switched off.
	env.fog_enabled = true
	env.fog_light_color = Color("#d9dcd2")
	env.fog_density = 0.0
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 90.0
	env.fog_depth_end = 175.0
	env.fog_sky_affect = 0.25
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color("#fff1d8")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	_sun = sun


func _spawn_player() -> void:
	player = Player3D.new()
	add_child(player)
	player.setup(models, self)
	var start: Vector2 = map.road_nodes.get("mushin_c", map.player_start)
	var best := Vector2i.ZERO
	var bd := INF
	for c in _walk_cells:
		var d := (Vector2(c) * 64.0 + Vector2(32, 32)).distance_squared_to(start)
		if d < bd:
			bd = d
			best = c
	player.position = cell_pos(best)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	_place_camera(1.0)


func _spawn_traffic() -> void:
	for i in traffic_n:
		var v := Vehicle3D.new()
		add_child(v)
		v.setup(models, Models3D.TRAFFIC_MIX[i % Models3D.TRAFFIC_MIX.size()], self)
		vehicles.append(v)
		_reroute(v, 20.0, 160.0)


## Put an AI vehicle on a road edge between `near` and `far` metres from the focus.
func _reroute(v: Vehicle3D, near: float, far: float) -> void:
	var keys: Array = map.road_graph.keys()
	var f := focus()
	for attempt in 40:
		var a: String = keys[_rng.randi() % keys.size()]
		var nbs: Array = map.road_graph[a]
		if nbs.is_empty():
			continue
		var b: String = nbs[_rng.randi() % nbs.size()]
		var p := Terrain3D.w((map.road_nodes[a] as Vector2).lerp(map.road_nodes[b], 0.5))
		var d := Vector2(p.x - f.x, p.z - f.z).length()
		if d >= near and d <= far or attempt == 39:
			v.place_on_road(a, b, _rng.randf_range(0.1, 0.9))
			v.mode = Vehicle3D.Mode.AI
			v.visible = true
			return


func _spawn_people() -> void:
	var keys: Array = Models3D.PEOPLE.filter(func(k: String) -> bool: return models.has(k, Models3D.CHARS))
	people_keys = keys
	if keys.is_empty():
		return
	for i in people_n:
		var c := _walk_cell_near(focus(), 6.0, 70.0)
		var p := Person3D.new()
		add_child(p)
		if not p.setup(models, keys[i % keys.size()], self, c, 100 + i):
			p.free()
			continue
		people.append(p)


func _walk_cell_near(f: Vector3, near: float, far: float) -> Vector2i:
	for attempt in 60:
		var ang := _rng.randf() * TAU
		var d := _rng.randf_range(near, far)
		var c := Vector2i(int((f.x + cos(ang) * d) / CELL_M), int((f.z + sin(ang) * d) / CELL_M))
		if is_walk(c):
			return c
	return _walk_cells[_rng.randi() % _walk_cells.size()]


# ---------- play ----------

func _input_vec() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1
	if hud and hud.joy:
		v += hud.joy.value
	return v.limit_length(1.0)


## Talking, title cards and menus freeze the player's controls.
func _controls_locked() -> bool:
	return in_menu or hud.dialogue.visible


func _physics_process(delta: float) -> void:
	var inp := Vector2.ZERO if _controls_locked() else _input_vec()
	if ride:
		var d := demo_drive if demo_drive != Vector2.ZERO else Vector2(inp.x, -inp.y)
		ride.drive(d.y, d.x, delta)
		player.position = ride.position
	else:
		var stick := demo_stick if demo_stick != Vector2.ZERO else inp
		player.walk(stick, cam_yaw, _run_held or Input.is_physical_key_pressed(KEY_SHIFT), delta)
	for v in vehicles:
		if v.mode == Vehicle3D.Mode.AI or v.mode == Vehicle3D.Mode.FLEE:
			v.ai_step(delta)
		elif v.mode == Vehicle3D.Mode.CHASE:
			v.chase_step(delta)
	police.suspended = missions.running != ""
	police.step(delta)
	if ride and ride.is_wreck and missions.running == "":
		_action() # out of the wreck
	for p in people:
		p.step(delta)
	if ride and absf(ride.speed) > 3.0:
		_scatter(ride)
	run.step(delta)
	lights.step(delta, _dark)
	checkpoints.step(delta)
	stage.step(delta)
	combat.step(delta)
	hud.fight_mode(combat.active, combat.player_hp)
	hud.gun_mode(combat.armed and (combat.active or ride == null), combat.clip, combat.reserve)
	player.show_gun(combat.armed and ride == null)
	if missions.running == "" and not in_menu and stage._marker.visible:
		if Vector2(focus().x - stage._marker.position.x, focus().z - stage._marker.position.z).length() < 6.0:
			stage.set_marker(null)
			missions.run(Story.next_mission())
	_place_camera(delta)
	_recycle(delta)
	_update_hud(delta)
	_sounds()


func _sounds() -> void:
	Sound.world(_dark > 0.5, true, ride != null, absf(ride.speed) if ride else 0.0, 1.0 if stage.raining else 0.0)


## People in front of a moving player vehicle dive out of the way.
func _scatter(v: Vehicle3D) -> void:
	var fwd := v.forward() * signf(v.speed)
	for p in people:
		var rel := p.position - v.position
		rel.y = 0.0
		var ahead := rel.dot(fwd)
		if ahead > 0.0 and ahead < 4.0 + absf(v.speed) * 0.6 and absf(rel.dot(Vector3(-fwd.z, 0, fwd.x))) < 2.2:
			p.flee(v.position, fwd)


func _place_camera(delta: float) -> void:
	if in_menu and delta < 1.0:
		# Main menu: a slow drift over the city.
		_menu_t += delta * 0.05
		var c := player.position
		cam.position = c + Vector3(sin(_menu_t) * 42.0, 30.0, cos(_menu_t) * 42.0)
		cam.look_at(c + Vector3(0, 4, 0))
		return
	var target: Vector3
	var dist: float
	var height: float
	player.visible = ride == null and not (stage and stage.cam_override == "low")
	if stage and stage.cam_override == "low":
		# Under the bridge, from the gutter: Dayo is down in it; we see only legs and feet.
		var away := (player.position - stage.cam_target)
		away.y = 0.0
		cam.position = cam.position.lerp(player.position + away.normalized() * 0.6 + Vector3(0, 0.3, 0), minf(1.0, delta * 4.0))
		cam.look_at(stage.cam_target + Vector3(0, 0.5, 0))
		return
	if stage and stage.cam_override == "look":
		target = stage.cam_target + Vector3(0, 1.4, 0)
		cam.position = cam.position.lerp(player.position + (player.position - stage.cam_target).normalized() * 3.0 + Vector3(0, 2.2, 0), minf(1.0, delta * 3.0))
		cam.look_at(target)
		return
	var sens := float(Settings.get_pref("cam_sens", 1.0))
	if ride:
		_look_t += delta
		var behind := ride.heading - PI * 0.5 # (sin, cos) of this = -forward
		if _look_t > 1.5:
			cam_yaw = lerp_angle(cam_yaw, behind, minf(1.0, delta * 2.5 * sens))
		dist = 6.0 + ride.length * 0.9
		height = 3.2 + ride.length * 0.35
		target = ride.position + Vector3(0, 1.2, 0)
	else:
		_look_t += delta
		if player.moving > 0.0 and _look_t > 2.0:
			cam_yaw = lerp_angle(cam_yaw, player.facing() + PI, minf(1.0, delta * 1.2 * sens))
		dist = 5.2
		height = 2.6
		target = player.position + Vector3(0, 1.4, 0)
	var want := target + Vector3(sin(cam_yaw) * dist, height, cos(cam_yaw) * dist)
	# Don't let the camera go inside a building: stop it at the first wall in the way.
	var q := PhysicsRayQueryParameters3D.create(target, want, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = (hit["position"] as Vector3).lerp(target, 0.12)
	cam.position = want if delta >= 1.0 else cam.position.lerp(want, minf(1.0, delta * 6.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		cam.position += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * _shake * 0.3
	cam.look_at(target)


func _recycle(delta: float) -> void:
	_recycle_t -= delta
	if _recycle_t > 0.0:
		return
	_recycle_t = 1.0
	var f := focus()
	for v in vehicles:
		if v.mode == Vehicle3D.Mode.AI and Vector2(v.position.x - f.x, v.position.z - f.z).length() > 230.0:
			_reroute(v, 110.0, 190.0)
	for p in people:
		if Vector2(p.position.x - f.x, p.position.z - f.z).length() > 85.0:
			var c := _walk_cell_near(f, 45.0, 75.0)
			p.from = c
			p.to = c
			p.state = Person3D.State.WALK
			p.position = cell_pos(c)


## Fire the pistol. Shooting in the street outside a mission draws the police.
func _shoot() -> void:
	if not combat.armed or _controls_locked():
		return
	combat.player_shoot()
	if missions.running == "" and not combat.active:
		police.raise(0.3)


## Enter the nearest vehicle, or get out of the one you're driving.
func _action() -> void:
	if _controls_locked() or combat.active:
		return
	if ride:
		var side := Vector3(-ride.forward().z, 0, ride.forward().x) * -1.0 # driver's door (left)
		ride.mode = Vehicle3D.Mode.PARKED
		ride.speed = 0.0
		player.position = ride.position + side * 2.0
		player.visible = true
		player.collision_layer = 4
		ride = null
		hud.act_btn.text = "ENTER"
		return
	var best: Vehicle3D = null
	var bd := ENTER_RANGE
	for v in vehicles:
		var d := v.position.distance_to(player.position) - v.length * 0.35
		if d < bd:
			bd = d
			best = v
	if best and not best.is_wreck:
		_enter(best)


func _enter(v: Vehicle3D) -> void:
	if v.mode == Vehicle3D.Mode.AI:
		_drag_out_driver(v)
	ride = v
	ride.mode = Vehicle3D.Mode.PLAYER
	player.visible = false
	player.collision_layer = 0
	hud.act_btn.text = "EXIT"


## Carjacking: the driver lands on the road beside his car and argues.
func _drag_out_driver(v: Vehicle3D) -> void:
	if people.is_empty():
		return
	var p: Person3D = people[_rng.randi() % people.size()]
	p.position = v.position + Vector3(-v.forward().z, 0, v.forward().x) * -2.2
	p.state = Person3D.State.PAUSE
	p.pause_left = 5.0
	Models3D.play(p.ap, "argue", "idle")
	var c := Vector2i(int(p.position.x / CELL_M), int(p.position.z / CELL_M))
	p.from = c
	p.to = c
	police.raise(0.5)


# ---------- HUD ----------

func _update_hud(delta: float) -> void:
	_frames += 1
	_fps_t += delta
	if _fps_t < 0.5:
		return
	var f := focus()
	var dist: Dictionary = map.district_at(Vector2(f.x, f.z) / Terrain3D.K)
	var where := String(dist.get("name", "Lagos"))
	var line := "%s · %s" % [where, ("%d km/h" % int(absf(ride.speed) * 3.6)) if ride else "on foot"]
	hud.info.text = "%s · %d fps" % [line, int(round(_frames / _fps_t))]
	var job := ""
	if run.dest >= 0:
		job = " · %d on board → %s %d m" % [run.passengers, run.stops[run.dest]["name"], int(f.distance_to(run.stops[run.dest]["pos"]))]
	var stars := "★".repeat(int(ceil(Story.wanted - 0.01)))
	hud.money.text = "₦%s  %s  Respect %d%s%s" % [_naira(int(Life.money)), String(Clock.label()), Story.respect, ("  WANTED " + stars) if stars != "" else "", job]
	_frames = 0
	_fps_t = 0.0
	_day_night()


func _naira(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Sun, sky and haze follow the game clock; the story can force night (the prologue).
func _day_night() -> void:
	if _sun == null:
		return
	var hours: float = float(Clock.hour()) + float(Clock.minute()) / 60.0
	var dark: float = clamp(float(Clock.darkness()), 0.0, 1.0)
	if stage and stage.night:
		dark = 1.0
		hours = 21.0
	_dark = dark
	var day_t := clampf((hours - 6.0) / 12.0, 0.0, 1.0)
	_sun.rotation_degrees.x = -(10.0 + sin(day_t * PI) * 62.0)
	_sun.rotation_degrees.y = lerpf(-90.0, 90.0, day_t)
	_sun.light_energy = lerpf(1.35, 0.12, dark)
	_sun.light_color = Color("#fff1d8").lerp(Color("#9fb4e8"), dark)
	_env.ambient_light_energy = lerpf(0.8, 0.25, dark)
	var rain_k := 0.35 if stage and stage.raining else 0.0
	_sky.sky_top_color = Color("#4f8fd0").lerp(Color("#0b1630"), dark).lerp(Color("#3a4048"), rain_k)
	_sky.sky_horizon_color = Color("#d6e4ea").lerp(Color("#2a3150"), dark).lerp(Color("#4a5058"), rain_k)
	_env.fog_light_color = Color("#d9dcd2").lerp(Color("#1c2236"), dark)


func _unhandled_input(e: InputEvent) -> void:
	if in_menu:
		return
	# Drag anywhere free (or move the mouse with the right button) to look around.
	var sens := float(Settings.get_pref("cam_sens", 1.0))
	if e is InputEventScreenDrag and e.position.x > get_viewport().get_visible_rect().size.x * 0.35:
		cam_yaw -= e.relative.x * 0.006 * sens
		_look_t = 0.0
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		cam_yaw -= e.relative.x * 0.006 * sens
		_look_t = 0.0
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and (combat.active or combat.armed):
		if combat.armed:
			_shoot()
		else:
			combat.player_attack()
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE: hud.open_pause()
			KEY_E, KEY_F: _action()
			KEY_J, KEY_SPACE:
				if combat.active:
					combat.player_attack()
			KEY_K:
				_shoot()


# ---------- QA ----------

## Plays the opening of the campaign on autopilot and saves pictures, then quits:
##   Godot --path game -- --shots=DIR
func _shots(dir: String) -> void:
	_save_ok = false # QA never touches the real save
	SaveGame.set_process(false)
	DirAccess.make_dir_recursive_absolute(dir)
	hud.show_menu(false)
	await get_tree().create_timer(1.5).timeout
	await _save(dir + "/e0-menu.png")
	hud._close_menu()
	in_menu = false
	Story.reset()
	missions.autopilot = true
	hud.dialogue.autoplay = true
	missions.mission_done.disconnect(_on_mission_done)
	for id: String in ["p0", "m01", "m02", "m03", "m04", "m05", "m06"]:
		missions.run(id)
		var t := 0.0
		var took := 0
		while missions.running == id or Story.current == id:
			await get_tree().create_timer(0.5).timeout
			t += 0.5
			# A few frames from each mission, at fixed times into it.
			if took < 2 and t >= [3.0, 9.0][took]:
				await _save(dir + "/e-%s-%d.png" % [id, took])
				took += 1
			if t > 120.0:
				print("story3d: TIMEOUT in ", id, " at step ", Story.checkpoint)
				break
		print("story3d: %s done=%s" % [id, Story.done.has(id)])
	await get_tree().create_timer(2.6).timeout # let the last title card finish
	# Free roam with two stars: police units come after Dayo.
	Story.wanted = 2.0
	await get_tree().create_timer(5.0).timeout
	await _save(dir + "/e8-police.png")
	var nearest := 999.0
	for u in police.units:
		nearest = minf(nearest, u.position.distance_to(focus()))
	print("story3d police: units=%d nearest=%.0f m" % [police.units.size(), nearest])
	Story.wanted = 0.0
	await _save(dir + "/e9-after.png")
	print("story3d: done=%s respect=%d items=%s | %s" % [Story.done.keys(), Story.respect, Story.items.keys(), hud.info.text])
	get_tree().quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
