class_name Street3D
extends Node3D
## 3D Lagos (D-020): the whole island in 3D, built from the 2D game's map data and the Meshy models.
## Walk as Tunde, take any vehicle (traffic drivers get dragged out), drive through traffic past
## townspeople who get out of your way. Runs on the Compatibility renderer, like the 2D game.
## Launch: the "3D Lagos" button on the title screen, or Godot --path game -- --proto3d.

const CELL_M := Terrain3D.CELL_M
const TRAFFIC_N := 26
const PEOPLE_N := 36
const ENTER_RANGE := 3.6

var map: MapData
var models := Models3D.new()
var terrain: Terrain3D
var city: City3D
var player: Player3D
var ride: Vehicle3D # the vehicle the player is driving, or null
var vehicles: Array[Vehicle3D] = []
var people: Array[Person3D] = []
var cam: Camera3D
var cam_yaw := 0.0
var hud: Label
var _joy: Control
var _act_btn: Button
var _run_btn: Button
var _run_held := false
var _rng := RandomNumberGenerator.new()
var _fps_t := 0.0
var _frames := 0
var _recycle_t := 0.0
var _walk_cells: Array[Vector2i] = []
var run: DanfoRun3D
var people_keys: Array = []
var _minimap: Minimap3D
var _toast: Label
var _toast_t := 0.0
var _money: Label
var _env: Environment
var _sun: DirectionalLight3D
var _sky: ProceduralSkyMaterial
# QA demo inputs (--shots)
var demo_stick := Vector2.ZERO
var demo_drive := Vector2.ZERO


func _ready() -> void:
	_rng.seed = 2026
	_guard_save()
	map = MapData.shared()
	_environment()
	terrain = Terrain3D.new()
	add_child(terrain)
	terrain.build(map)
	city = City3D.new()
	add_child(city)
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
	run.message.connect(_say)
	run.paid.connect(_save_game)
	_hud()
	_day_night()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots(a.trim_prefix("--shots="))


## The 2D game's systems that feed the save (the world, jobs, garage...) are gone while we're in
## 3D. Load the latest save's money and clock, and make every save from here keep the 2D parts
## exactly as they were saved (a provider whose object is gone answers with its saved copy).
func _guard_save() -> void:
	# The title may save again only once the 2D game has reloaded its world (main.gd sets it).
	if Engine.has_meta("save_ready"):
		Engine.remove_meta("save_ready")
	var data: Dictionary = {}
	if FileAccess.file_exists(SaveGame.PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.PATH))
		if parsed is Dictionary:
			data = parsed
	if not data.is_empty():
		Clock.from_dict(data.get("clock", {}))
		Life.from_dict(data.get("life", {}))
		SaveGame.revision = int(data.get("revision", 0))
	var world_saved: Dictionary = data.get("world", {})
	var wp: Callable = SaveGame.world_provider
	SaveGame.world_provider = func() -> Dictionary: return wp.call() if wp.is_valid() else world_saved
	var extras: Dictionary = data.get("extras", {})
	for k in SaveGame.extra_providers.keys():
		var c: Callable = SaveGame.extra_providers[k]
		var frozen: Variant = extras.get(k, {})
		SaveGame.extra_providers[k] = func() -> Variant: return c.call() if c.is_valid() else frozen
	_save_ok = not Engine.has_meta("qa_no_save")


var _save_ok := true


func _save_game() -> void:
	if _save_ok:
		SaveGame.save_now()


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
	var start: Vector2 = map.road_nodes.get("yaba_c", map.player_start)
	# The nearest pavement cell to Yaba's junction.
	var best := Vector2i.ZERO
	var bd := INF
	for c in _walk_cells:
		var d := (Vector2(c) * 64.0 + Vector2(32, 32)).distance_squared_to(start)
		if d < bd:
			bd = d
			best = c
	player.position = cell_pos(best)
	# Tunde's danfo, parked at the kerb beside him.
	var nb: Array = map.road_graph.get("yaba_c", [])
	if not nb.is_empty():
		var dv := Vehicle3D.new()
		add_child(dv)
		dv.setup(models, "danfo", self)
		dv.place_on_road("yaba_c", nb[0], 0.12)
		dv.mode = Vehicle3D.Mode.PARKED
		dv.speed = 0.0
		vehicles.append(dv)
		var to_car := dv.position - player.position
		cam_yaw = atan2(-to_car.x, -to_car.z) # camera behind Tunde, looking at his bus
		player.model.rotation.y = atan2(to_car.x, to_car.z)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	_place_camera(1.0)


func _spawn_traffic() -> void:
	for i in TRAFFIC_N:
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
	if keys.is_empty() and models.has("tunde"):
		keys = ["tunde"]
	people_keys = keys
	if keys.is_empty():
		return
	for i in PEOPLE_N:
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
	if _joy:
		v += _joy.value
	return v.limit_length(1.0)


func _physics_process(delta: float) -> void:
	var inp := _input_vec()
	if ride:
		var d := demo_drive if demo_drive != Vector2.ZERO else Vector2(inp.x, -inp.y)
		ride.drive(d.y, d.x, delta)
		player.position = ride.position
	else:
		var stick := demo_stick if demo_stick != Vector2.ZERO else inp
		player.walk(stick, cam_yaw, _run_held or Input.is_physical_key_pressed(KEY_SHIFT), delta)
	for v in vehicles:
		if v.mode == Vehicle3D.Mode.AI:
			v.ai_step(delta)
	for p in people:
		p.step(delta)
	if ride and absf(ride.speed) > 3.0:
		_scatter(ride)
	run.step(delta)
	_place_camera(delta)
	_recycle(delta)
	_update_hud(delta)


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
	var target: Vector3
	var dist: float
	var height: float
	if ride:
		# Swing in behind the vehicle as it turns.
		var behind := ride.heading - PI * 0.5 # (sin, cos) of this = -forward
		cam_yaw = lerp_angle(cam_yaw, behind, minf(1.0, delta * 2.5))
		dist = 6.0 + ride.length * 0.9
		height = 3.2 + ride.length * 0.35
		target = ride.position + Vector3(0, 1.2, 0)
	else:
		if player.moving > 0.0:
			cam_yaw = lerp_angle(cam_yaw, player.facing() + PI, minf(1.0, delta * 1.2))
		dist = 5.2
		height = 2.6
		target = player.position + Vector3(0, 1.4, 0)
	var want := target + Vector3(sin(cam_yaw) * dist, height, cos(cam_yaw) * dist)
	cam.position = want if delta >= 1.0 else cam.position.lerp(want, minf(1.0, delta * 6.0))
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


## Enter the nearest vehicle, or get out of the one you're driving.
func _action() -> void:
	if ride:
		var side := Vector3(-ride.forward().z, 0, ride.forward().x) * -1.0 # driver's door (left)
		ride.mode = Vehicle3D.Mode.PARKED
		ride.speed = 0.0
		player.position = ride.position + side * (1.6 + 0.4)
		player.visible = true
		player.collision_layer = 4
		ride = null
		_act_btn.text = "ENTER"
		return
	var best: Vehicle3D = null
	var bd := ENTER_RANGE
	for v in vehicles:
		var d := v.position.distance_to(player.position) - v.length * 0.35
		if d < bd:
			bd = d
			best = v
	if best == null:
		return
	if best.mode == Vehicle3D.Mode.AI:
		_drag_out_driver(best)
	ride = best
	ride.mode = Vehicle3D.Mode.PLAYER
	player.visible = false
	player.collision_layer = 0
	_act_btn.text = "EXIT"


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


# ---------- HUD ----------

func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_color", Color("#f1e6c8"))
	hud.add_theme_color_override("font_outline_color", Color("#1d1611"))
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		_joy = preload("res://ui/joystick.gd").new()
		_joy.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_joy.position = Vector2(20, -180)
		layer.add_child(_joy)
	_act_btn = _button(layer, "ENTER", Vector2(-170, -130))
	_act_btn.pressed.connect(_action)
	_run_btn = _button(layer, "RUN", Vector2(-170, -250))
	_run_btn.button_down.connect(func() -> void: _run_held = true)
	_run_btn.button_up.connect(func() -> void: _run_held = false)
	_money = Label.new()
	_money.position = Vector2(16, 66)
	_money.add_theme_font_size_override("font_size", 24)
	_money.add_theme_color_override("font_color", Color("#f6d04d"))
	_money.add_theme_color_override("font_outline_color", Color("#1d1611"))
	_money.add_theme_constant_override("outline_size", 6)
	layer.add_child(_money)
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 110
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_color", Color("#fff4d6"))
	_toast.add_theme_color_override("font_outline_color", Color("#1d1611"))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(_toast)
	_minimap = Minimap3D.new()
	layer.add_child(_minimap)
	_minimap.setup(self)
	_minimap.anchor_left = 1.0
	_minimap.anchor_right = 1.0
	_minimap.offset_left = -232
	_minimap.offset_top = 80
	var back := _button(layer, "Back to 2D", Vector2(-230, 12), true)
	back.custom_minimum_size = Vector2(210, 52)
	back.pressed.connect(_back)


func _button(layer: CanvasLayer, text: String, at: Vector2, top := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 96)
	b.add_theme_font_size_override("font_size", 24)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 0.0 if top else 1.0
	b.anchor_bottom = b.anchor_top
	b.offset_left = at.x
	b.offset_top = at.y
	b.offset_right = at.x + b.custom_minimum_size.x
	b.offset_bottom = at.y + b.custom_minimum_size.y
	layer.add_child(b)
	return b


func _update_hud(delta: float) -> void:
	_frames += 1
	_fps_t += delta
	if _fps_t < 0.5:
		return
	var f := focus()
	var dist: Dictionary = map.district_at(Vector2(f.x, f.z) / Terrain3D.K)
	var where := String(dist.get("name", "Lagos"))
	var line := "%s · %s" % [where, ("%d km/h in the %s" % [int(absf(ride.speed) * 3.6), ride.kind]) if ride else "on foot"]
	var life: Node = get_node_or_null("/root/Life")
	var clock: Node = get_node_or_null("/root/Clock")
	var job := ""
	if run.dest >= 0:
		job = " · %d on board → %s %d m" % [run.passengers, run.stops[run.dest]["name"], int(f.distance_to(run.stops[run.dest]["pos"]))]
	elif ride and ride.kind == "danfo":
		job = " · stop at a bus stop to load passengers"
	_money.text = "₦%s  %s%s" % [_naira(int(life.money) if life else 0), String(clock.label()) if clock else "", job]
	_day_night()
	hud.text = "%s · %d fps\nWASD / stick · E get in or out · Shift run · Esc back" % [line, int(round(_frames / _fps_t))]
	_frames = 0
	_fps_t = 0.0


func _naira(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _say(text: String) -> void:
	_toast.text = text
	_toast_t = 5.0


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)


## Sun, sky and haze follow the game clock (shared with the 2D game).
func _day_night() -> void:
	var clock: Node = get_node_or_null("/root/Clock")
	if clock == null or _sun == null:
		return
	var hours: float = float(clock.hour()) + float(clock.minute()) / 60.0
	var dark: float = clamp(float(clock.darkness()), 0.0, 1.0)
	var day_t := clampf((hours - 6.0) / 12.0, 0.0, 1.0) # 06:00 -> 18:00
	_sun.rotation_degrees.x = -(10.0 + sin(day_t * PI) * 62.0)
	_sun.rotation_degrees.y = lerpf(-90.0, 90.0, day_t)
	_sun.light_energy = lerpf(1.35, 0.12, dark)
	_sun.light_color = Color("#fff1d8").lerp(Color("#9fb4e8"), dark)
	_env.ambient_light_energy = lerpf(0.8, 0.25, dark)
	_sky.sky_top_color = Color("#4f8fd0").lerp(Color("#0b1630"), dark)
	_sky.sky_horizon_color = Color("#d6e4ea").lerp(Color("#2a3150"), dark)
	_env.fog_light_color = Color("#d9dcd2").lerp(Color("#1c2236"), dark)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE: _back()
			KEY_E, KEY_F: _action()


func _back() -> void:
	_save_game()
	get_tree().change_scene_to_file("res://main.tscn")


# ---------- QA ----------

## Walk, look over the district, take a vehicle, drive; save pictures, then quit.
func _shots(dir: String) -> void:
	Engine.set_meta("qa_no_save", true) # QA earnings never touch the real save
	_save_ok = false
	SaveGame.set_process(false) # no autosave during QA either
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.5).timeout
	await _save(dir + "/3d-0-foot.png")
	demo_stick = Vector2(0, -1)
	await get_tree().create_timer(2.0).timeout
	demo_stick = Vector2.ZERO
	await _save(dir + "/3d-1-walk.png")
	# Overview: high over the district.
	var keep := cam.position
	cam.position = player.position + Vector3(-45, 55, 45)
	cam.look_at(player.position)
	set_physics_process(false)
	await get_tree().create_timer(0.6).timeout
	await _save(dir + "/3d-2-overview.png")
	set_physics_process(true)
	cam.position = keep
	# Take the nearest vehicle (Tunde's danfo) and drive.
	for v in vehicles:
		if v.mode == Vehicle3D.Mode.PARKED:
			player.position = v.position + Vector3(0, 0, 2.5)
	_action()
	demo_drive = Vector2(0, 1)
	await get_tree().create_timer(3.0).timeout
	await _save(dir + "/3d-3-drive.png")
	demo_drive = Vector2(0.18, 1)
	await get_tree().create_timer(2.0).timeout
	await _save(dir + "/3d-4-drive.png")
	demo_drive = Vector2.ZERO
	# A danfo run: pull up at the nearest stop, load, jump to the destination, unload.
	var life: Node = get_node_or_null("/root/Life")
	var before: int = int(life.money) if life else 0
	var s0 := run.nearest_stop(ride.position)
	ride.position = run.stops[s0]["pos"] + Vector3(0, 0, 0)
	ride.speed = 0.0
	await get_tree().create_timer(1.6).timeout
	await _save(dir + "/3d-5-stop.png")
	var loaded := run.dest >= 0
	if loaded:
		ride.position = run.stops[run.dest]["pos"]
		ride.speed = 0.0
		await get_tree().create_timer(1.6).timeout
	print("street3d run: loaded=%s paid=%d stops=%d" % [loaded, (int(life.money) if life else 0) - before, run.stops.size()])
	print("street3d: vehicles=%d people=%d buildings=%d | %s" % [vehicles.size(), people.size(), map.buildings.size(), hud.text.replace(char(10), " | ")])
	get_tree().quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
