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
var cam_pitch := 0.45 # radians above the horizon; the player drags up/down to change it
var run: DanfoRun3D
var lights: Lights3D
var checkpoints: Checkpoint3D
var stage: Stage3D
var combat: Combat3D
var missions: Mission3D
var hud: Hud3D
var police: Police3D
var mission_vehicles: Array[Vehicle3D] = []
var loading: Loading3D
var sets: Sets3D
var fx: Fx3D
var stealth: Stealth3D
var roam: FreeRoam3D
var signals: Signals3D
var explore: Explore3D
var talk: TalkCam3D
var ambience: Ambience3D
var region := "lagos" # which map is built: Lagos, or a story region (D-028)
var prompt_text := "" # a context action a mission or a stall offers (the ACT button shows it)
var prompt_cb: Callable
var prompt_at: Variant = null
var waypoint: Variant = null
var _cam_touches := {} # touch index -> true: fingers that are turning the camera # the player's map waypoint (Vector3) or null # where the prompt's tag floats (a stall, a pump), or null
var _built := false
var _maps := {} # region id -> MapData (Lagos stays cached; one region at a time besides it)
var _res_t := 0.0
var _res_frames := 0
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
	# Phones: build the city over several frames behind a loading screen (no frozen black boot).
	loading = Loading3D.new()
	add_child(loading)
	loading.open("Lagos")
	_environment()
	loading.stage(0.05, "Drawing the map of Lagos")
	map = await _map_for("lagos")
	await _build_world()
	loading.stage(0.88, "Waking up the city")
	await get_tree().process_frame
	_spawn_player()
	_spawn_traffic()
	_spawn_people()
	_spawn_map_services()
	sets = Sets3D.new()
	add_child(sets)
	sets.setup(self)
	fx = Fx3D.new()
	add_child(fx)
	fx.setup(self)
	stealth = Stealth3D.new()
	add_child(stealth)
	stealth.setup(self)
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
	hud = Hud3D.new()
	add_child(hud)
	hud.setup(self)
	hud.action_pressed.connect(_action)
	hud.punch_pressed.connect(_punch)
	hud.shoot_pressed.connect(_shoot)
	hud.run_changed.connect(func(h: bool) -> void: _run_held = h)
	hud.new_game.connect(_new_game)
	hud.continue_game.connect(_continue_game)
	talk = TalkCam3D.new(self)
	hud.dialogue.started.connect(talk.begin)
	hud.dialogue.line_shown.connect(talk.line)
	hud.dialogue.finished.connect(talk.end)
	hud.dialogue.line_shown.connect(Sound.babble)
	ambience = Ambience3D.new()
	add_child(ambience)
	ambience.setup(self)
	roam = FreeRoam3D.new()
	add_child(roam)
	roam.setup(self)
	explore = Explore3D.new()
	add_child(explore)
	explore.setup(self)
	signals.message.connect(notify)
	_register_save()
	_apply_quality_env()
	_day_night()
	_built = true
	await loading.close()
	get_viewport().size_changed.connect(func() -> void: UiStyle.fit_safe_area(hud._root))
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
	if "--perf" in OS.get_cmdline_user_args():
		_perf()
	elif shots != "" and "--look" in OS.get_cmdline_user_args():
		_look(shots)
	elif shots != "" and "--sets" in OS.get_cmdline_user_args():
		_look_sets(shots)
	elif shots != "" and "--roam" in OS.get_cmdline_user_args():
		_roam_qa(shots)
	elif shots != "" and "--lineup" in OS.get_cmdline_user_args():
		_lineup(shots)
	elif shots != "" and "--seats" in OS.get_cmdline_user_args():
		_seats_qa(shots)
	elif shots != "":
		_shots(shots)
	else:
		hud.show_menu(FileAccess.file_exists(SaveGame.PATH))
		Sound.music("highlife")


# ---------- save ----------

func _register_save() -> void:
	SaveGame.world_provider = _world_state
	SaveGame.world_restorer = _restore_world
	SaveGame.extra_providers = { "story": Story.to_dict, "street": Street.to_dict, "roam": roam.to_dict }
	SaveGame.extra_restorers = { "story": Story.from_dict, "street": Street.from_dict, "roam": roam.from_dict }


func _world_state() -> Dictionary:
	var p := focus()
	return { "pos": [p.x, p.z], "model": player.model_key, "region": region, "offmap": sets.active != "", "armed": combat.armed, "reserve": combat.reserve }


func _restore_world(d: Dictionary) -> void:
	var p: Array = d.get("pos", [])
	# Free roam is always in Lagos; a save made in a region or inside a set (a mission was
	# running, and restarts from its checkpoint) puts Dayo back home.
	if p.size() == 2 and String(d.get("region", "lagos")) == "lagos" and not bool(d.get("offmap", false)):
		player.position = Vector3(float(p[0]), terrain.height_at(Vector3(float(p[0]), 0, float(p[1]))), float(p[1]))
	else:
		player.position = home_pos()
	player.reset_physics_interpolation()
	player.set_model(String(d.get("model", "dayo")))
	if bool(d.get("armed", false)):
		combat.give_gun(int(d.get("reserve", 24)))


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
	roam.on_continue()
	# A mission interrupted by quitting starts again from its last checkpoint.
	var id := Story.current
	if id != "" and Story.playable(id):
		missions.run(id, Story.checkpoint)
	else:
		_next_mission_marker()


func _on_mission_done(id: String) -> void:
	# Free roam happens in Lagos: come home from a story region first.
	if region != "lagos":
		await load_region("lagos")
		place_player(home_pos())
	_save_game()
	var nxt := Story.next_mission()
	if nxt == "":
		# The story is over: post-game free roam in the world the ending made (D-028).
		roam.start_postgame(Story.ending())
		set_objective("", null)
		return
	var m: Dictionary = Story.mission(nxt)
	if Story.playable(nxt) and not m.has("start"):
		missions.run(nxt)
	else:
		_next_mission_marker()


## Where Dayo lives (Mama Àgbà's room in Mushin; the Festac safe house later is a mission set).
func home_pos() -> Vector3:
	var at := "landmark:" + String(Life.home) if map.landmarks.has(Life.home) else "node:mushin_c"
	return resolve({ "at": at, "offset": [2, 2] })


# ---------- building the world (staged) and regions ----------

## The map for a region, parsed on a worker thread so the loading screen keeps moving.
func _map_for(id: String) -> MapData:
	if _maps.has(id):
		return _maps[id]
	var m: MapData
	if id == "lagos" and MapData._shared != null:
		m = MapData._shared
	else:
		m = MapData.new()
		var path := "res://data/map/lagos.json" if id == "lagos" else "res://data/map/regions/%s.json" % id
		var th := Thread.new()
		th.start(m.load_file.bind(path))
		while th.is_alive():
			await get_tree().process_frame
		th.wait_to_finish()
		if id == "lagos":
			MapData._shared = m
	# Keep Lagos and at most one region in memory.
	for k in _maps.keys():
		if k != "lagos" and k != id:
			_maps.erase(k)
	_maps[id] = m
	return m


func _build_world() -> void:
	loading.stage(0.2, "Laying the roads of %s" % map.title)
	await get_tree().process_frame
	terrain = Terrain3D.new()
	add_child(terrain)
	terrain.build(map)
	loading.stage(0.35, "Putting up the buildings")
	await get_tree().process_frame
	city = City3D.new()
	add_child(city)
	city.far_scale = q_far
	city.staged = true
	await city.build(map, models)
	loading.stage(0.75, "Wiring the streetlights")
	await get_tree().process_frame
	lights = Lights3D.new()
	add_child(lights)
	lights.build(self)
	signals = Signals3D.new()
	add_child(signals)
	signals.build(self)
	_walk_cells.clear()
	for y in map.rows:
		for x in map.cols:
			if map.surface[y * map.cols + x] == MapData.S.WALK:
				_walk_cells.append(Vector2i(x, y))
	if _walk_cells.is_empty():
		_walk_cells.append(Vector2i(map.cols / 2, map.rows / 2))


## Bus stops and checkpoints belong to a map, so they are rebuilt with it.
func _spawn_map_services() -> void:
	run = DanfoRun3D.new()
	add_child(run)
	run.setup(self)
	run.message.connect(notify)
	run.paid.connect(_save_game)
	run.paid.connect(func() -> void: roam.on_fare_paid())
	checkpoints = Checkpoint3D.new()
	add_child(checkpoints)
	checkpoints.setup(self)
	checkpoints.message.connect(notify)
	checkpoints.charged.connect(_save_game)
	checkpoints.charged.connect(func() -> void:
		if ride and absf(ride.speed) > 3.0:
			police.raise(1.0))


## Travel to another map (the story goes to Abeokuta, Kano, the Delta, Anambra and back).
func load_region(id: String) -> void:
	if id == region and _built:
		return
	_built = false
	var m: Dictionary = { "lagos": "Lagos", "abeokuta": "Abeokuta", "kano": "Kano", "delta": "the Niger Delta", "anambra": "Anambra" }
	loading.open("On the road to %s" % String(m.get(id, id)))
	await get_tree().process_frame
	if ride:
		ride.clear_rider()
		ride = null
		player.visible = true
		player.collision_layer = 4
		hud.act_btn.text = "ENTER"
	clear_mission_vehicles()
	for v in vehicles:
		v.queue_free()
	vehicles.clear()
	for p in people:
		p.queue_free()
	people.clear()
	police.clear()
	for n: Node in [terrain, city, lights, signals, checkpoints, run]:
		if is_instance_valid(n):
			n.queue_free()
	await get_tree().process_frame
	region = id
	loading.stage(0.05, "Drawing the map")
	map = await _map_for(id)
	await _build_world()
	_spawn_map_services()
	signals.message.connect(notify)
	run.enabled = missions.running == ""
	player.position = cell_pos(_nearest_walk(map.player_start))
	player.reset_physics_interpolation()
	var n_traffic := traffic_n if id == "lagos" else traffic_n / 3
	for i in n_traffic:
		var v := Vehicle3D.new()
		add_child(v)
		v.setup(models, (Models3D.TRAFFIC_MIX if id == "lagos" else Models3D.REGION_MIX)[i % (Models3D.TRAFFIC_MIX if id == "lagos" else Models3D.REGION_MIX).size()], self)
		vehicles.append(v)
		_reroute(v, 20.0, 160.0)
		_traffic_rider(v, i)
	var keep := people_n
	if id != "lagos":
		people_n = people_n / 2
	_spawn_people()
	people_n = keep
	hud.minimap.setup(self)
	hud.map_screen.rebuild()
	waypoint = null
	roam.on_region()
	explore.on_region()
	ambience.on_region()
	_day_night()
	_built = true
	await loading.close()


func _nearest_walk(px: Vector2) -> Vector2i:
	var best := _walk_cells[0]
	var bd := INF
	for c in _walk_cells:
		var d := (Vector2(c) * 64.0 + Vector2(32, 32)).distance_squared_to(px)
		if d < bd:
			bd = d
			best = c
	return best


## The ground under a point: a deck or set floor (Makoko walkways, rooftops, the yacht) if one is
## within a step, else the terrain; NAN over open water (nobody walks on the lagoon).
func ground_at(pos: Vector3, from_y := 0.0) -> float:
	var best := -INF
	var xz := Vector2(pos.x, pos.z)
	for list: Array in [city.platforms, sets.platforms]:
		for pl: Dictionary in list:
			var y: float = pl["y"]
			if y <= from_y + 0.75 and y > best and (pl["rect"] as Rect2).has_point(xz):
				best = y
	if best > -INF:
		return best
	if is_water_at(pos):
		return NAN
	return terrain.height_at(pos)


func is_water_at(pos: Vector3) -> bool:
	var c := Vector2i(int(floor(pos.x / CELL_M)), int(floor(pos.z / CELL_M)))
	if not map.in_bounds(c):
		return true
	return map.is_water(map.surface[c.y * map.cols + c.x])


# ---------- phone life cycle ----------

func _notification(what: int) -> void:
	if not _built:
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			# Switching apps, a call, the power button: save, and come back to the pause menu.
			if not in_menu and _save_ok:
				SaveGame.save_now()
			# (The map already pauses the game: leave it open rather than stacking pause on it.)
			if not in_menu and not get_tree().paused and not hud.menu_open() and not hud.map_screen.visible and _save_ok and not "--shots" in str(OS.get_cmdline_user_args()):
				hud.open_pause()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if not in_menu:
				if hud.map_screen.visible:
					hud.map_screen.close_map()
				elif get_tree().paused:
					hud.pause.close()
				else:
					hud.open_pause()


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
	var dd := clampi(int(g.get("draw_distance", 2)), 1, 3)
	q_far = [0.65, 0.65, 0.85, 1.0][dd]
	people_n = [10, 10, 18, 30][dd] # phones: fewer animated people on Low/Medium
	traffic_n = [10, 10, 16, 26][dd]
	# Heat and battery: Low (and the battery saver) cap the frame rate at 30.
	var cap := String(g.get("preset", "medium")) == "low" or bool(Settings.get_pref("battery_saver", false))
	Engine.max_fps = 30 if cap else 60
	if "--perf" in OS.get_cmdline_user_args():
		Engine.max_fps = 0


func _apply_quality_env() -> void:
	var g: Dictionary = Settings.current
	var preset := String(g.get("preset", "medium"))
	# Sun shadows: off on Low, short range on Medium (only what's near you casts), longer on High.
	_sun.shadow_enabled = preset != "low"
	_sun.directional_shadow_max_distance = 45.0 if preset == "high" else 25.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if preset != "high" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_env.glow_enabled = String(g.get("effects", "low")) != "off"
	# Smooth edges: MSAA (cheap on phone tile GPUs), FXAA on Low.
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X if preset == "high" else (Viewport.MSAA_2X if preset != "low" else Viewport.MSAA_DISABLED)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if preset == "low" else Viewport.SCREEN_SPACE_AA_DISABLED
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
	for p in people:
		if p.state == Person3D.State.CROSS:
			bodies.append(p)
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


## AI: is the thing holding me up Dayo (on foot or in his ride)?
func blocker_is_player(v: Vehicle3D) -> bool:
	var o: Node3D = ride if ride else player
	if o == v:
		return false
	var fwd := v.forward()
	var rel := o.position - v.position
	rel.y = 0.0
	var ahead := rel.dot(fwd)
	return ahead > 0.0 and ahead < 14.0 and absf(rel.dot(Vector3(-fwd.z, 0, fwd.x))) < 2.4


## AI: is the oncoming lane clear far enough ahead to overtake?
func oncoming_clear(v: Vehicle3D) -> bool:
	var fwd := v.forward()
	var left := Vector3(fwd.z, 0, -fwd.x)
	for o in vehicles:
		if o == v:
			continue
		var rel := o.position - v.position
		rel.y = 0.0
		var ahead := rel.dot(fwd)
		var lat := rel.dot(left)
		if ahead > -6.0 and ahead < 45.0 and lat > 1.0 and lat < 6.5:
			return false
	return true


func is_junction(id: String) -> bool:
	return (map.road_graph.get(id, []) as Array).size() >= 3


var _bump_v: Vehicle3D
var _bump_t := 0.0


## Dayo's ride hit someone's vehicle: they stop and shout, and he can settle it or drive off.
func on_bump(other: Variant) -> void:
	if not other is Vehicle3D or missions.running != "" or _bump_t > 0.0:
		return
	var v: Vehicle3D = other
	if v.mode != Vehicle3D.Mode.AI or v.is_wreck:
		return
	v.mode = Vehicle3D.Mode.PARKED
	v.speed = 0.0
	v.shout(["Ah! You don jam my motor!", "Who teach you drive?", "Pay for my bumper o!"][_rng.randi() % 3], 5.0)
	_bump_v = v
	_bump_t = 7.0
	prompt_text = "SETTLE ₦2,000"
	prompt_cb = func() -> void:
		if Life.spend(2000, "Settled a bumper scrape (3D)"):
			Story.add_respect(1)
			notify("You settled it. \"God bless you, oga.\"")
		_end_bump(true)


func _end_bump(settled: bool) -> void:
	if is_instance_valid(_bump_v):
		_bump_v.mode = Vehicle3D.Mode.AI
		if not settled:
			_bump_v.shout("Ole! Thief! Come back here!", 2.5)
	if not settled:
		Story.add_respect(-1)
		notify("You drove off without settling. People talk. (Respect -1)")
	_bump_v = null
	_bump_t = 0.0
	if prompt_text == "SETTLE ₦2,000":
		prompt_text = ""
		prompt_cb = Callable()


func _bumps(delta: float) -> void:
	if _bump_v == null:
		return
	_bump_t -= delta
	var gone := not is_instance_valid(_bump_v) or _bump_v.position.distance_to(focus()) > 30.0
	if _bump_t <= 0.0 or gone:
		_end_bump(false)


## The horn: traffic ahead hurries on, people in the way step aside.
func horn() -> void:
	if ride == null:
		return
	Sound.sfx("horn", 1.0)
	var fwd := ride.forward()
	for v in vehicles:
		if v == ride or v.mode != Vehicle3D.Mode.AI:
			continue
		var rel := v.position - ride.position
		if rel.dot(fwd) > 0.0 and rel.length() < 25.0:
			v.speed = maxf(v.speed, v.cruise)
			v.shout(["Ehn, I dey go!", "Wetin?", "Patience!"][_rng.randi() % 3], 1.6)
	for p in people:
		var rel := p.position - ride.position
		if rel.dot(fwd) > 0.0 and rel.length() < 14.0:
			p.flee(ride.position, fwd)


# ---------- the story's stage directions (Mission3D calls these) ----------

## A step's position: "landmark:id", "node:id", "set:anchor", "player", or [x, z] metres; plus
## "offset" [dx, dz]. Set anchors and decks keep their height.
func resolve(st: Dictionary) -> Vector3:
	var at: Variant = st.get("at", "player")
	var p := player.position
	var keep_y := false
	if at is Array and (at as Array).size() == 2:
		p = Vector3(float(at[0]), 0, float(at[1]))
	elif at is String:
		var s := String(at)
		if s.begins_with("landmark:") and map.landmarks.has(s.substr(9)):
			p = Terrain3D.w(map.landmarks[s.substr(9)]["pos"])
		elif s.begins_with("node:") and map.road_nodes.has(s.substr(5)):
			p = Terrain3D.w(map.road_nodes[s.substr(5)])
		elif s.begins_with("set:"):
			p = sets.anchor(s.substr(4))
			keep_y = true
		elif s == "player":
			keep_y = true
	var off: Array = st.get("offset", [0, 0])
	p += Vector3(float(off[0]), 0, float(off[1]))
	if not keep_y:
		var g := ground_at(p, 0.0)
		p.y = 0.0 if is_nan(g) else g
	return p


## Put Dayo somewhere: on foot, or at the wheel of a fresh vehicle (with its painted slogan).
## Land vehicles go onto the nearest road, pointing along it; boats (and anything off the map) go
## exactly where asked, facing `yaw` degrees.
func place_player(pos: Vector3, vehicle_kind := "", slogan := "", yaw := 0.0) -> void:
	if ride and vehicle_kind == "":
		_action() # get out first
	if vehicle_kind == "":
		player.position = pos
		player.reset_physics_interpolation()
		return
	var v := Vehicle3D.new()
	add_child(v)
	v.setup(models, vehicle_kind, self)
	var best := ""
	var bd := INF
	if not v.on_water and map.in_bounds(Vector2i(int(pos.x / CELL_M), int(pos.z / CELL_M))):
		for id in map.road_nodes:
			var d := Terrain3D.w(map.road_nodes[id]).distance_squared_to(pos)
			if d < bd and not (map.road_graph.get(id, []) as Array).is_empty():
				bd = d
				best = id
	if v.on_water:
		pos = water_near(pos)
	if best != "":
		v.place_on_road(best, map.road_graph[best][0], 0.15)
	else:
		v.position = Vector3(pos.x, -0.18 if v.on_water else pos.y, pos.z)
		v.heading = deg_to_rad(yaw)
		v.rotation.y = v.heading
		v.reset_physics_interpolation()
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
	if v.on_water:
		best = ""
		pos = water_near(pos)
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


## A vehicle Dayo owns, parked (bought at the dealer, or waiting by the house).
func spawn_owned(kind: String, pos: Vector3) -> Vehicle3D:
	var v := Vehicle3D.new()
	add_child(v)
	v.setup(models, kind, self)
	if v.on_water:
		v.position = Vector3(pos.x, -0.18, pos.z)
	else:
		var c := _nearest_walk(Vector2(pos.x, pos.z) / Terrain3D.K)
		v.position = cell_pos(c) + Vector3(0, -Terrain3D.WALK_H, 0)
	v.mode = Vehicle3D.Mode.PARKED
	v.speed = 0.0
	v.reset_physics_interpolation()
	vehicles.append(v)
	return v


## The nearest walkable ground to a point (a story spot that fell in the lagoon comes ashore).
func land_near(pos: Vector3) -> Vector3:
	if not is_water_at(pos):
		return pos
	for r in range(1, 30):
		for k in 16:
			var q := pos + Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0)) * r * 2.0
			if not is_water_at(q):
				q.y = terrain.height_at(q)
				return q
	return pos


## The nearest open water to a point (boats are launched there, not on the shore).
func water_near(pos: Vector3) -> Vector3:
	if is_water_at(pos) and map.in_bounds(Vector2i(int(pos.x / CELL_M), int(pos.z / CELL_M))):
		return pos
	for r in range(1, 30):
		for k in 16:
			var q := pos + Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0)) * r * 3.0
			if is_water_at(q) and map.in_bounds(Vector2i(int(q.x / CELL_M), int(q.z / CELL_M))):
				# One more cell out, clear of the shore.
				return q + (q - pos).normalized() * 3.0
	return pos


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
		ride.reset_physics_interpolation()
	else:
		player.position = pos
		player.reset_physics_interpolation()


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
	if bool(Settings.get_pref("motion_off", false)):
		return
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
	mat.sun_angle_max = 30.0
	mat.sun_curve = 0.08 # a soft, hazy sun disc
	sky.sky_material = mat
	_sky = mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	# ACES: richer contrast and no washed-out highlights in the midday sun (polish, D-027).
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.06
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
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF # moved every frame
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
		_traffic_rider(v, i)


## Okadas, kekes and horses in traffic carry a rider you can see (cars keep theirs behind glass).
func _traffic_rider(v: Vehicle3D, i: int) -> void:
	if v.kind in ["okada", "keke", "horse"]:
		var men := ["p_man", "p_worker", "p_beach", "p_punk", "p_farmer", "p_adventurer"]
		v.set_rider(models, men[i % men.size()], i % Models3D.SKIN_TONES.size())


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
	var keys: Array = Models3D.TOWNSFOLK.filter(func(k: String) -> bool: return models.has_person(k))
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
	if not _built:
		return
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
	_crossings(delta)
	_bumps(delta)
	if waypoint != null and Vector2(focus().x - (waypoint as Vector3).x, focus().z - (waypoint as Vector3).z).length() < 12.0:
		waypoint = null
		notify("You've reached your waypoint.")
	_anim_lod(delta)
	if ride and absf(ride.speed) > 3.0:
		_scatter(ride)
	run.step(delta)
	lights.step(delta, _dark)
	signals.step(delta)
	checkpoints.step(delta)
	stage.step(delta)
	sets.step(delta)
	stealth.step(delta)
	fx.step(delta)
	roam.step(delta)
	explore.step(delta)
	ambience.step(delta)
	combat.step(delta)
	hud.prompt(prompt_text if not _controls_locked() else "")
	if prompt_text == "":
		prompt_at = null
	hud.fight_mode(combat.active, combat.player_hp)
	hud.gun_mode(combat.armed and (combat.active or ride == null), combat.clip, combat.reserve)
	player.show_gun(combat.armed and ride == null)
	if missions.running == "" and not in_menu and stage._marker.visible:
		if Vector2(focus().x - stage._marker.position.x, focus().z - stage._marker.position.z).length() < 6.0:
			stage.set_marker(null)
			missions.run(Story.next_mission())
	_recycle(delta)
	_update_hud(delta)
	_sounds()


func _process(delta: float) -> void:
	if not _built:
		return
	_place_camera(delta)
	_dynamic_resolution(delta)


## Keep the frame rate up on weak or hot phones: render the 3D world at a lower resolution while
## frames run slow (the HUD stays sharp), and back up when there's headroom.
func _dynamic_resolution(delta: float) -> void:
	_res_t += delta
	_res_frames += 1
	if _res_t < 2.0:
		return
	var fps := _res_frames / _res_t
	_res_t = 0.0
	_res_frames = 0
	var vp := get_viewport()
	var target := 28.0 if Engine.max_fps == 30 else 50.0
	if String(Settings.current.get("preset", "medium")) == "high" or in_menu:
		vp.scaling_3d_scale = 1.0
		return
	if fps < target * 0.85:
		vp.scaling_3d_scale = maxf(0.6, vp.scaling_3d_scale - 0.1)
	elif fps > target * 1.1 and vp.scaling_3d_scale < 1.0:
		vp.scaling_3d_scale = minf(1.0, vp.scaling_3d_scale + 0.05)


func _sounds() -> void:
	Sound.world(_dark > 0.5, roam.nepa_on() if roam else true, ride != null, absf(ride.speed) if ride else 0.0, 1.0 if stage.raining else 0.0)


## Animation level of detail: people near the camera animate every frame, further ones every 2nd
## to 6th frame, and off-screen or far ones not at all (skeletons are the main CPU cost on phones).
var _lod_frame := 0
var _lod_acc := {}


func _anim_lod(delta: float) -> void:
	_lod_frame += 1
	var c := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var crowd: Array = []
	crowd.append_array(people)
	var cast := {} # story actors: never frozen (a death or a fall happens when the story says)
	for a: Variant in stage.actors.values():
		if is_instance_valid(a):
			crowd.append(a)
			cast[(a as Node).get_instance_id()] = true
	for p in crowd:
		if not is_instance_valid(p) or p.ap == null:
			continue
		var ap: AnimationPlayer = p.ap
		if ap.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var rel: Vector3 = (p as Node3D).global_position - c
		var d := rel.length()
		var every := 1 if d < 18.0 else (2 if d < 35.0 else (4 if d < 55.0 else 6))
		if d > 75.0 or (d > 6.0 and rel.dot(fwd) < -2.0):
			every = 0 # behind the camera or beyond the haze: frozen
		if cast.has((p as Node).get_instance_id()):
			every = 1 if d < 35.0 else 2
		var id: int = p.get_instance_id()
		_lod_acc[id] = float(_lod_acc.get(id, 0.0)) + delta
		if every > 0 and (_lod_frame + id) % every == 0:
			ap.advance(_lod_acc[id])
			_lod_acc[id] = 0.0


var _cross_t := 4.0


## Now and then someone near you crosses the road to the pavement opposite.
func _crossings(delta: float) -> void:
	_cross_t -= delta
	if _cross_t > 0.0 or people.is_empty():
		return
	_cross_t = _rng.randf_range(3.0, 7.0)
	var f := focus()
	for attempt in 6:
		var p: Person3D = people[_rng.randi() % people.size()]
		if p.state != Person3D.State.WALK or p.position.distance_to(f) > 45.0:
			continue
		var c := Vector2i(int(p.position.x / CELL_M), int(p.position.z / CELL_M))
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var k := 1
			var saw_road := false
			while k < 12:
				var q: Vector2i = c + d * k
				if not map.in_bounds(q):
					break
				var s2 := map.surface[q.y * map.cols + q.x]
				if map.is_roadlike(s2):
					saw_road = true
				elif saw_road and s2 == MapData.S.WALK:
					p.cross(cell_pos(q))
					return
				elif map.is_water(s2) or (not saw_road and s2 != MapData.S.WALK and s2 != MapData.S.GUTTER):
					break
				k += 1


## People in front of a moving player vehicle dive out of the way; anyone too slow is knocked
## down (no blood: they get up, angry), and witnesses call the police.
func _scatter(v: Vehicle3D) -> void:
	var fwd := v.forward() * signf(v.speed)
	for p in people:
		var rel := p.position - v.position
		rel.y = 0.0
		var ahead := rel.dot(fwd)
		var lat := absf(rel.dot(Vector3(-fwd.z, 0, fwd.x)))
		if ahead > 0.0 and ahead < v.length * 0.5 + 0.6 and lat < 1.3 and absf(v.speed) > 6.0 and p.state != Person3D.State.PAUSE:
			p.knock(fwd)
			Sound.sfx("punch", 0.6)
			if missions.running == "":
				police.raise(0.6)
				Story.add_respect(-1)
				notify("You hit someone! They're up, but witnesses are calling the police.")
		elif ahead > 0.0 and ahead < 4.0 + absf(v.speed) * 0.6 and lat < 2.2:
			p.flee(v.position, fwd)


## The camera runs every rendered frame (not on physics ticks) and follows the interpolated
## positions of the player and vehicles, so it's smooth at any frame rate.
func _place_camera(delta: float) -> void:
	if in_menu and delta < 1.0:
		# Main menu: a slow, low drift down a street.
		_menu_t += delta * 0.04
		var c := player.position
		cam.position = c + Vector3(sin(_menu_t) * 24.0, 11.0, cos(_menu_t) * 24.0)
		cam.look_at(c + Vector3(0, 3, 0))
		return
	if stage and stage.cam_override == "fixed":
		return # a scripted shot (QA) has placed the camera
	if stage and stage.cam_override == "talk":
		player.visible = ride == null
		talk.place(cam, delta)
		return
	var target: Vector3
	var dist: float
	var height: float
	player.visible = ride == null and not (stage and stage.cam_override == "low")
	var pp := player.get_global_transform_interpolated().origin
	if stage and stage.cam_override == "low":
		# Under the bridge, from the gutter: Dayo is down in it; we see only legs and feet.
		var away := (player.position - stage.cam_target)
		away.y = 0.0
		# Just over the gutter's concrete edge (0.45 m), peeking out at the bridge.
		cam.position = cam.position.lerp(player.position + away.normalized() * 0.25 + Vector3(0, 0.62, 0), minf(1.0, delta * 4.0))
		cam.look_at(stage.cam_target + Vector3(0, 0.7, 0))
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
		dist = 6.5 + ride.length * 0.9
		target = ride.get_global_transform_interpolated().origin + Vector3(0, 1.2, 0)
	else:
		_look_t += delta
		if player.moving > 0.0 and _look_t > 2.0:
			cam_yaw = lerp_angle(cam_yaw, player.facing() + PI, minf(1.0, delta * 1.2 * sens))
		dist = 5.6
		target = pp + Vector3(0, 1.4, 0)
	# Orbit: yaw round the player, pitch from just above the street to high overhead.
	height = sin(cam_pitch) * dist
	var flat := cos(cam_pitch) * dist
	var want := target + Vector3(sin(cam_yaw) * flat, height, cos(cam_yaw) * flat)
	# Don't let the camera go inside a building: stop it at the first wall in the way.
	var q := PhysicsRayQueryParameters3D.create(target, want, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = (hit["position"] as Vector3).lerp(target, 0.12)
	cam.position = want if delta >= 1.0 else cam.position.lerp(want, minf(1.0, delta * 12.0))
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
			p.reset_physics_interpolation()


## PUNCH: a silent takedown from behind in stealth, else a punch.
func _punch() -> void:
	if _controls_locked():
		return
	if stealth.active and stealth.try_takedown():
		return
	combat.player_attack()


## Fire the pistol. Shooting in the street outside a mission draws the police.
func _shoot() -> void:
	if not combat.armed or _controls_locked():
		return
	combat.player_shoot()
	if missions.running == "" and not combat.active:
		police.raise(0.3)


## Enter the nearest vehicle, or get out of the one you're driving. A context prompt (a mission's
## "Snap photo", a stall's "Eat", a fuel pump) takes the button first.
func _action() -> void:
	if _controls_locked():
		return
	if prompt_text != "" and prompt_cb.is_valid():
		prompt_cb.call()
		return
	if combat.active:
		return
	if ride:
		var side := Vector3(-ride.forward().z, 0, ride.forward().x) * -1.0 # driver's door (left)
		ride.mode = Vehicle3D.Mode.PARKED
		ride.speed = 0.0
		ride.clear_rider()
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
	ride.set_rider(models, player.model_key, 2) # Dayo, seated at the wheel
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
	var where := String(dist.get("name", map.title))
	var line := "%s · %s" % [where, ("%d km/h" % int(absf(ride.speed) * 3.6)) if ride else "on foot"]
	hud.info.text = "%s · %d fps" % [line, int(round(_frames / _fps_t))]
	var job := ""
	if run.dest >= 0:
		job = " · %d on board → %s %d m" % [run.passengers, run.stops[run.dest]["name"], int(f.distance_to(run.stops[run.dest]["pos"]))]
	var stars := "★".repeat(int(ceil(Story.wanted - 0.01)))
	var extra := ""
	if ride and int(FreeRoam3D.TANK.get(ride.kind, 0)) > 0:
		extra = "  Fuel %d%%" % int(ride.fuel * 100.0) + ("  DAMAGED" if ride.health < 40.0 else "")
	elif roam and roam.delivery_due() and missions.running == "" and region == "lagos":
		extra = "  Delivery ₦%s/₦%s" % [_naira(mini(roam.today, FreeRoam3D.DELIVERY)), _naira(FreeRoam3D.DELIVERY)]
	hud.money.text = "₦%s  %s  Respect %d%s%s%s" % [_naira(int(Life.money)), String(Clock.label()), Story.respect, ("  WANTED " + stars) if stars != "" else "", extra, job]
	_frames = 0
	_fps_t = 0.0
	_day_night()
	_hints()


## First-time tips (each shows once): the controls as they're first needed.
func _hints() -> void:
	if in_menu or hud.dialogue.visible:
		return
	if missions.running == "" and not Story.done.is_empty():
		hud.hint("look", "Drag on the right side of the screen to look around: left and right to turn, up and down to raise the camera.")
		hud.hint("roam", "Free roam: run danfo fares, take side jobs at the blue JOBS boards, or head for the red marker to play the next mission.")
	if ride == null:
		for v in vehicles:
			if v.position.distance_to(player.position) < ENTER_RANGE + 1.0:
				hud.hint("enter", "Press ENTER to get in. Take any vehicle you like... but the owner won't be happy.")
				break
	else:
		if ride.kind == "danfo" and missions.running == "":
			hud.hint("danfo", "Stop at a yellow BUS STOP sign: passengers climb in. Drive them to their stop and stop again to get paid.")
		if ride.fuel < 0.25:
			hud.hint("fuel", "Fuel is low. Stop under a FILLING STATION canopy and press FUEL.")
		if ride.on_water:
			hud.hint("boat", "Boats only go on water. Ease off the throttle in the turns: they slide.")
	if combat.active:
		hud.hint("fight", "PUNCH whoever is in front of you. Don't let them surround you. Stand still against a wall when they shoot: cover.")
	if combat.armed:
		hud.hint("gun", "SHOOT fires at the target with the red ring. Shooting in the street brings the police.")
	if Story.wanted >= 1.0:
		hud.hint("wanted", "The police want you. Get out of their sight for a while and the stars fade.")
	if stealth.active:
		hud.hint("stealth", "Stay out of the torch beams and the pale cones. Walk, don't run. From behind, PUNCH is a silent takedown.")
	if roam and roam.cut != "" and _dark > 0.4:
		hud.hint("nepa", "NEPA has taken light: streetlights are off in one district. Darkness hides you; generators make noise and light.")
	if player.stamina < 0.3:
		hud.hint("stamina", "Out of breath: walk a moment. Mama Àgbà's amala and ewedu make you run longer.")


func _naira(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Sun, sky and haze follow the game clock; the story can force night (the prologue).
## Each region's own light and air (D-032): Lagos's coastal haze, Abeokuta's clear green hills,
## Kano's dusty harmattan, the Delta's humid grey-green, Anambra's lush village light.
const REGION_LOOK := {
	"lagos": { "fog": "#d9dcd2", "top": "#4f8fd0", "horizon": "#d6e4ea", "sun": "#fff1d8", "near": 90.0, "far": 175.0, "sat": 1.1, "sun_e": 1.35 },
	"abeokuta": { "fog": "#dfe6d6", "top": "#4a92d8", "horizon": "#dfeaf0", "sun": "#fff4e0", "near": 110.0, "far": 210.0, "sat": 1.12, "sun_e": 1.35 },
	"kano": { "fog": "#dcc29a", "top": "#8fa9c0", "horizon": "#e6cfa2", "sun": "#ffe2b0", "near": 55.0, "far": 140.0, "sat": 0.95, "sun_e": 1.45 },
	"delta": { "fog": "#b8c4b0", "top": "#7896a8", "horizon": "#c4cfc4", "sun": "#f4f0e0", "near": 60.0, "far": 150.0, "sat": 1.05, "sun_e": 1.15 },
	"anambra": { "fog": "#d6e2cc", "top": "#4c8fcf", "horizon": "#d8e6e0", "sun": "#fff0d4", "near": 100.0, "far": 200.0, "sat": 1.18, "sun_e": 1.3 },
}
var wet := 0.0 # how soaked the streets are (rain darkens them and fills the puddles)


## Sun, sky and haze follow the game clock and the region; the story can force night (the
## prologue). Rain darkens the roads and fills the puddles; shop windows glow after dark.
func _day_night() -> void:
	if _sun == null:
		return
	var look: Dictionary = REGION_LOOK.get(region, REGION_LOOK["lagos"])
	var hours: float = float(Clock.hour()) + float(Clock.minute()) / 60.0
	var dark: float = clamp(float(Clock.darkness()), 0.0, 1.0)
	if stage and stage.night:
		dark = 1.0
		hours = 21.0
	_dark = dark
	var day_t := clampf((hours - 6.0) / 12.0, 0.0, 1.0)
	_sun.rotation_degrees.x = -(10.0 + sin(day_t * PI) * 62.0)
	_sun.rotation_degrees.y = lerpf(-90.0, 90.0, day_t)
	var raining: bool = stage != null and stage.raining
	# Night stays readable (phone feedback): a cool moonlight and a blue ambient fill, not black.
	_sun.light_energy = lerpf(float(look["sun_e"]), 0.4, dark) * (0.6 if raining else 1.0)
	_sun.light_color = Color(String(look["sun"])).lerp(Color("#9fb4e8"), dark)
	_env.ambient_light_sky_contribution = lerpf(1.0, 0.25, dark)
	_env.ambient_light_color = Color(0.34, 0.4, 0.56)
	_env.ambient_light_energy = lerpf(0.8, 1.0, dark)
	_env.tonemap_exposure = lerpf(0.95, 1.25, dark)
	_env.adjustment_saturation = float(look["sat"]) * (0.85 if raining else 1.0)
	var rain_k := 0.35 if raining else 0.0
	_sky.sky_top_color = Color(String(look["top"])).lerp(Color("#0b1630"), dark).lerp(Color("#3a4048"), rain_k)
	_sky.sky_horizon_color = Color(String(look["horizon"])).lerp(Color("#2a3150"), dark).lerp(Color("#4a5058"), rain_k)
	_env.fog_light_color = Color(String(look["fog"])).lerp(Color("#1c2236"), dark).lerp(Color("#7a8088"), rain_k * (1.0 - dark))
	_env.fog_depth_begin = float(look["near"]) * q_far * (0.7 if raining else 1.0)
	_env.fog_depth_end = float(look["far"]) * q_far * (0.8 if raining else 1.0)
	# Wet streets: soak in a few seconds of rain, dry over a couple of minutes.
	wet = clampf(wet + (0.5 / 6.0 if raining else -0.5 / 90.0), 0.0, 1.0)
	terrain.set_wet(wet)
	city.set_wet(wet)
	if city.window_mat:
		city.window_mat.emission_energy_multiplier = 2.4 * clampf((dark - 0.3) * 2.0, 0.0, 1.0)


func _unhandled_input(e: InputEvent) -> void:
	if in_menu or not _built:
		return
	# Drag anywhere free (or move the mouse with the right button) to look around.
	var sens := float(Settings.get_pref("cam_sens", 1.0))
	# Drag right/left to turn the camera round, up/down to raise or lower it.
	var drag := Vector2.ZERO
	# A finger that went down on open screen turns the camera; one that pressed a button (RUN,
	# ENTER...) or the stick doesn't, however it wobbles.
	if e is InputEventScreenTouch:
		if e.pressed and not hud.over_button(e.position) and (hud.joy == null or hud.joy._touch != e.index):
			_cam_touches[e.index] = true
		else:
			_cam_touches.erase(e.index) # lifted, or pressed on a button (a stale finger id is reset)
	if e is InputEventScreenDrag and _cam_touches.has(e.index):
		drag = e.relative
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		drag = e.relative
	if drag != Vector2.ZERO:
		cam_yaw -= drag.x * 0.006 * sens
		cam_pitch = clampf(cam_pitch + drag.y * 0.005 * sens, -0.05, 1.25)
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
				if combat.active or stealth.active:
					_punch()
			KEY_K:
				_shoot()
			KEY_H:
				horn()
			KEY_M:
				hud.open_map()


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
	var args := OS.get_cmdline_user_args()
	var list: Array = ["p0", "m01", "m02", "m03", "m04", "m05", "m06"]
	if "--p0" in args:
		list = ["p0"]
	elif "--all" in args:
		list = Story.order.duplicate()
	for a in args:
		if a.begins_with("--from="):
			list = Story.order.slice(Story.order.find(a.trim_prefix("--from=")))
			for prev in Story.order.slice(0, Story.order.find(a.trim_prefix("--from="))):
				Story.done[prev] = true
		if a.begins_with("--list="):
			list = Array(a.trim_prefix("--list=").split(","))
		if a == "--slowtalk":
			hud.dialogue.auto_delay = 1.3
		if a.begins_with("--choice="):
			hud.dialogue.auto_choice = int(a.trim_prefix("--choice="))
	var resume := 0
	for a in args:
		if a.begins_with("--resume="):
			resume = int(a.trim_prefix("--resume="))
	for id: String in list:
		missions.run(id, resume if id == list[0] else 0)
		var t := 0.0
		var took := 0
		while missions.running == id or Story.current == id:
			await get_tree().create_timer(0.5).timeout
			t += 0.5
			# A few frames from each mission, at fixed times into it.
			if "--slowtalk" in args:
				if took < 40 and hud.dialogue.visible:
					await _save(dir + "/e-%s-%d.png" % [id, took])
					took += 1
			elif took < 2 and t >= [3.0, 9.0][took]:
				await _save(dir + "/e-%s-%d.png" % [id, took])
				took += 1
			if t > 240.0:
				print("story3d: TIMEOUT in ", id, " at step ", Story.checkpoint, " running=", missions.running)
				break
		print("story3d: %s done=%s region=%s set=%s" % [id, Story.done.has(id), region, sets.active])
		if region != "lagos" and missions.running == "":
			await load_region("lagos")
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


## Performance probe: draw calls, objects and triangles at a few spots (free roam, on foot).
##   Godot --path game -- --perf
func _perf() -> void:
	_save_ok = false
	SaveGame.set_process(false)
	in_menu = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var spots := ["node:yaba_c", "landmark:oshodi-market", "node:obalende", "node:lekki_c"]
	var tot := [0.0, 0.0, 0.0, 0.0]
	for sp in spots:
		player.position = resolve({ "at": sp, "offset": [3, 3] })
		await get_tree().create_timer(2.0).timeout
		var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var ob := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var pr := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		print("perf %s: draws=%d objects=%d tris=%dk cpu=%.1fms fps=%d" % [sp, dc, ob, pr / 1000, ms, Engine.get_frames_per_second()])
		for i in 4:
			tot[i] += [dc, ob, pr / 1000.0, ms][i] / spots.size()
	print("perf AVG: draws=%d objects=%d tris=%dk cpu=%.1fms" % tot)
	# What costs CPU? Switch things off one at a time at the last spot.
	var probes := {
		"minimap": func(on: bool) -> void: hud.minimap.set_process(on); hud.minimap.visible = on,
		"people": func(on: bool) -> void:
			for p in people:
				p.visible = on
				p.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED,
		"signals": func(on: bool) -> void: signals.visible = on,
		"roam stations": func(on: bool) -> void: roam.visible = on,
		"lights": func(on: bool) -> void: lights.visible = on,
		"traffic": func(on: bool) -> void:
			for v in vehicles:
				v.visible = on
				v.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED,
	}
	for k: String in probes:
		probes[k].call(false)
		await get_tree().create_timer(1.5).timeout
		var ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		print("perf without %s: cpu=%.1fms draws=%d" % [k, ms, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		probes[k].call(true)
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()


## QA: pictures from a raised camera over a few districts (buildings and street dressing).
func _look(dir: String) -> void:
	_save_ok = false
	SaveGame.set_process(false)
	in_menu = false
	DirAccess.make_dir_recursive_absolute(dir)
	var spots: Array = ["node:vi_c", "node:ikeja_c", "node:yaba_c", "node:obalende", "node:lekki_c", "landmark:oshodi-market", "landmark:alaba-market"]
	for p in city.debug_spots:
		spots.append([p.x + 18.0, p.z + 18.0])
	if "--night" in OS.get_cmdline_user_args():
		stage.set_env(true, "--rain" in OS.get_cmdline_user_args())
		wet = 1.0 if stage.raining else 0.0
		_day_night()
	for i in spots.size():
		player.position = resolve({ "at": spots[i], "offset": [4, 4] })
		player.reset_physics_interpolation()
		in_menu = true # the raised, orbiting camera
		_menu_t = 0.8 + i * 1.3
		await get_tree().create_timer(1.5).timeout
		await _save(dir + "/look-%d.png" % i)
	get_tree().quit()


## QA: every person model in a row, labelled, in daylight (checking looks and skin).
func _lineup(dir: String) -> void:
	_save_ok = false
	SaveGame.set_process(false)
	hud._close_menu() if hud.menu_open() else null
	in_menu = false
	DirAccess.make_dir_recursive_absolute(dir)
	sets.enter("gala")
	stage.cam_override = "fixed"
	var keys: Array = ["dayo", "young_dayo"] + Models3D.TOWNSFOLK + ["p_swat", "p_soldier", "p_king"]
	var origin: Vector3 = sets.anchor("hall") + Vector3(-7, 0, 2)
	for i in keys.size():
		var got: Array = models.person(String(keys[i]), 1.75, i)
		if got[0] == null:
			continue
		var n: Node3D = got[0]
		add_child(n)
		n.position = origin + Vector3((i % 9) * 1.6, 0, (i / 9) * -9.0)
		Models3D.play(got[1], "idle", "")
		var l := Label3D.new()
		l.text = String(keys[i])
		l.font_size = 32
		l.pixel_size = 0.005
		l.position = Vector3(0, 2.1, 0)
		n.add_child(l)
	for row in 2:
		cam.position = origin + Vector3(6.4, 1.5, row * -9.0 + 6.5)
		cam.look_at(origin + Vector3(6.4, 1.0, row * -9.0))
		await get_tree().create_timer(1.0).timeout
		await _save(dir + "/lineup-%d.png" % row)
	get_tree().quit()


## QA: Dayo seated in each kind of vehicle, side on.
func _seats_qa(dir: String) -> void:
	_save_ok = false
	SaveGame.set_process(false)
	hud._close_menu() if hud.menu_open() else null
	in_menu = false
	DirAccess.make_dir_recursive_absolute(dir)
	sets.enter("yacht") # a clear deck far from the city's clutter
	stage.cam_override = "fixed"
	var kinds := ["okada", "keke", "horse", "car", "danfo", "suv", "speedboat", "bus"]
	var o: Vector3 = sets.anchor("boat") + Vector3(30, 0.5, 30)
	for i in kinds.size():
		var v := Vehicle3D.new()
		add_child(v)
		v.setup(models, kinds[i], self)
		v.mode = Vehicle3D.Mode.PARKED
		v.position = o + Vector3((i % 4) * 7.0, 0, (i / 4) * 30.0)
		v.set_rider(models, "dayo", 2)
	for k in 2:
		for j in 2:
			cam.position = o + Vector3(j * 14.0 + 3.5, 1.8, k * 30.0 + 7.5)
			cam.look_at(o + Vector3(j * 14.0 + 3.5, 0.9, k * 30.0))
			await get_tree().create_timer(0.8).timeout
			await _save(dir + "/seats-%d%d.png" % [k, j])
	get_tree().quit()


## QA: free-roam systems on autopilot: a Lagos Story, a stash, each street encounter, a side job
## of each kind, the horn, a bump, the police stages, fuel and a hawker; pictures of each.
##   Godot --path game -- --shots=DIR --roam
func _roam_qa(dir: String) -> void:
	_save_ok = false
	SaveGame.set_process(false)
	hud._close_menu() if hud.menu_open() else null
	in_menu = false
	Story.done["p0"] = true
	missions.autopilot = true
	hud.dialogue.autoplay = true
	DirAccess.make_dir_recursive_absolute(dir)
	var s: Dictionary = Explore3D.STORIES[0]
	player.position = explore._story_pos[s["id"]]
	await get_tree().create_timer(1.0).timeout
	await _save(dir + "/roam-story.png")
	print("roam: story prompt=", prompt_text)
	if prompt_cb.is_valid():
		await prompt_cb.call()
	var st: Dictionary = explore._stashes[0]
	player.position = (st["pos"] as Vector3) + Vector3(0.8, 0, 0)
	await get_tree().create_timer(1.0).timeout
	await _save(dir + "/roam-stash.png")
	print("roam: stash prompt=", prompt_text)
	if prompt_cb.is_valid():
		prompt_cb.call()
	print("roam: found=", explore.found_count())
	for kind in ["pickpocket", "oranges", "fight", "danfo"]:
		player.position = resolve({ "at": "node:yaba_c", "offset": [6, 6] })
		explore._enc_t = 0.0
		explore._end_encounter(false)
		for i in 10:
			explore._enc_t = 0.0
			await get_tree().process_frame
			if not explore._enc.is_empty() and explore._enc["kind"] == kind:
				break
			explore._end_encounter(false)
		await get_tree().create_timer(1.0).timeout
		await _save(dir + "/roam-enc-%s.png" % kind)
		print("roam: encounter ", kind, " active=", not explore._enc.is_empty(), " prompt=", explore._enc.get("prompt", ""))
		explore._end_encounter(false)
	# Side jobs at a board.
	for st2: Dictionary in roam.stations:
		if st2["kind"] == "jobs":
			for k in 3:
				roam._side_job(st2)
				var t := 0.0
				while roam._side_running and t < 60.0:
					await get_tree().create_timer(0.5).timeout
					t += 0.5
				print("roam: side job ", k, " done, respect=", Story.respect, " rep=", roam.board_rep)
			break
	# Driving: horn, police stages, fuel.
	place_player(resolve({ "at": "node:surulere_c" }), "danfo")
	horn()
	police.raise(2.0)
	for i in 8:
		await get_tree().create_timer(1.0).timeout
	await _save(dir + "/roam-police.png")
	print("roam: police stage=", police.label(), " units=", police.units.size())
	Story.wanted = 0.0
	ride.fuel = 0.05
	stage.set_env(false, true)
	wet = 1.0
	_day_night()
	await get_tree().create_timer(2.0).timeout
	await _save(dir + "/roam-rain.png")
	waypoint = resolve({ "at": "landmark:alaba-market" })
	hud.open_map()
	await get_tree().create_timer(0.8).timeout
	await _save(dir + "/roam-map.png")
	hud.map_screen._zoom_by(2.5, hud.map_screen.size * 0.5)
	await get_tree().create_timer(0.4).timeout
	await _save(dir + "/roam-map-zoom.png")
	hud.map_screen.close_map()
	print("roam: done respect=%d money=%d" % [Story.respect, int(Life.money)])
	get_tree().quit()


## QA: every built set and every region, from the player's camera and from above.
##   Godot --path game -- --shots=DIR --sets
func _look_sets(dir: String) -> void:
	_save_ok = false
	SaveGame.set_process(false)
	in_menu = false
	hud._close_menu() if hud.menu_open() else null
	DirAccess.make_dir_recursive_absolute(dir)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	if "--night" in OS.get_cmdline_user_args():
		stage.set_env(true, "--rain" in OS.get_cmdline_user_args())
		_day_night()
	for kind in ["police_cell", "owambe", "stilt_house", "home", "safehouse", "cellar", "gala", "yacht", "rooftops"]:
		if only != "" and not kind in only.split(","):
			continue
		sets.enter(kind)
		cam_pitch = 0.5
		await get_tree().create_timer(1.2).timeout
		await _save(dir + "/set-%s.png" % kind)
		cam_pitch = 1.1
		await get_tree().create_timer(0.8).timeout
		await _save(dir + "/set-%s-top.png" % kind)
		sets.leave()
	cam_pitch = 0.45
	if only != "":
		get_tree().quit()
		return
	for r in ["abeokuta", "kano", "delta", "anambra"]:
		await load_region(r)
		var first: String = map.landmarks.keys()[0]
		for i in 2:
			var lm: String = map.landmarks.keys()[mini(i, map.landmarks.size() - 1)]
			player.position = resolve({ "at": "landmark:" + lm, "offset": [6, 6] })
			player.reset_physics_interpolation()
			in_menu = true
			_menu_t = 0.6 + i * 2.0
			await get_tree().create_timer(1.5).timeout
			await _save(dir + "/region-%s-%d.png" % [r, i])
			in_menu = false
		if r == "abeokuta":
			sets.enter("olumo")
			await get_tree().create_timer(1.0).timeout
			await _save(dir + "/region-olumo-start.png")
			player.position = sets.anchor("top")
			player.reset_physics_interpolation()
			await get_tree().create_timer(1.0).timeout
			await _save(dir + "/region-olumo-top.png")
			sets.leave()
	await load_region("lagos")
	# Makoko from the jetty, and a speedboat on the lagoon.
	player.position = resolve({ "at": "landmark:makoko-jetty", "offset": [0, 4] })
	player.reset_physics_interpolation()
	await get_tree().create_timer(1.5).timeout
	await _save(dir + "/makoko-jetty.png")
	place_player(resolve({ "at": "landmark:makoko-jetty", "offset": [0, 12] }), "speedboat")
	demo_drive = Vector2(0, 1)
	await get_tree().create_timer(2.5).timeout
	await _save(dir + "/makoko-boat.png")
	demo_drive = Vector2.ZERO
	get_tree().quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
