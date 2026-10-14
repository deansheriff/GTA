extends Node2D
## Naija Street Life: the open world of tropical-island Lagos (D-004, D-005, D-007, D-008).
## Walk Tunde, drive "Baba God Dey" through traffic, cross the Third Mainland Bridge, survive NEPA.
##
## Demo/screenshot mode for automated checks:
##   Godot --path game -- --demo --shots=C:/some/dir [--preset=low|medium|high] [--server=host]
##   Godot --path game -- --story-auto --shots=C:/some/dir   (plays the Prologue + Act 1 by itself)

const WalkerScript := preload("res://actors/walker.gd")
const DanfoScript := preload("res://actors/danfo.gd")
const HudScript := preload("res://ui/hud.gd")

var map: MapData
var baker: MaskBaker
var terrain: ColorRect
var streamer: Streamer
var traffic := Traffic.new()
var nav := Nav.new()
var waypoint := Vector2.INF
var route := PackedVector2Array()
var route_line: Node2D
var player_path := PackedVector2Array()
var _route_t := 0.0
var crowd := Crowd.new()
var player: Node2D
var danfo: Node2D
var camera: Camera2D
var hud: CanvasLayer
var lights: LightLayer
var painted_mat: ShaderMaterial
## Other players on this street: id -> { walker, danfo, target, code, mode, heading }
var remotes := {}

var mode := "walking"
var night := false
var nepa_on := true
var outage_t := 45.0
var state_t := 0.0
var fps_frames := 0
var fps_time := 0.0
var fps := 0
var demo := false
var shots_dir := ""
var demo_input := Vector2.ZERO
var _district := ""
var jobs: JobRunner
var interactions := Interactions.new()
var _action := "" # current context action id
var _action_target := {}
var _action_t := 0.0
var night_forced := -1 # dev/demo override: -1 follows the clock, 0 day, 1 night
var nepa_forced := -1
var _outages: Array = [] # today's NEPA outage windows [{start, end, districts}]
var _outage_day := -1
const RICH := ["ikoyi", "victoria-island", "lekki"]
var story: StoryHost
var story_auto := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--demo":
			demo = true
		elif a == "--story-auto":
			demo = true
			story_auto = true
		elif a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
		elif a.begins_with("--preset="):
			Settings.use_preset(a.trim_prefix("--preset="))
		elif a.begins_with("--server="):
			Net.server = a.trim_prefix("--server=")
	map = MapData.shared()
	_build_materials()
	baker = MaskBaker.new()
	add_child(baker)
	baker.bake(map)
	_build_terrain()
	lights = LightLayer.new()
	add_child(lights)
	streamer = Streamer.new()
	add_child(streamer)
	streamer.setup(map, painted_mat, lights)
	_build_actors()
	nav.setup(map)
	route_line = Node2D.new()
	route_line.z_index = 6
	route_line.draw.connect(_draw_route)
	add_child(route_line)
	traffic.setup(map, streamer, painted_mat)
	crowd.setup(map, streamer, painted_mat)
	_build_camera()
	hud = HudScript.new()
	add_child(hud)
	hud.toggle_night.connect(_toggle_night)
	hud.toggle_nepa.connect(func() -> void: _set_nepa(not nepa_on))
	hud.enter_exit.connect(_enter_exit)
	hud.action_pressed.connect(_do_action)
	jobs = JobRunner.new()
	add_child(jobs)
	jobs.setup(map)
	interactions.build(map, Life.items_db.get("vendors", {}))
	hud.setup_life(jobs)
	hud.phone.accept_job.connect(func(o: Dictionary) -> void:
		if story and story.mission_running():
			hud.toast("Finish the story mission first.")
			return
		jobs.accept(o)
		_set_waypoint(jobs.target()))
	hud.phone.cancel_job.connect(func() -> void:
		jobs.cancel()
		_set_waypoint(Vector2.INF))
	jobs.message.connect(func(m: String) -> void: hud.toast(m))
	jobs.job_changed.connect(_on_job_changed)
	hud.pos_game.finished.connect(func(s: int, f: int) -> void: jobs.finish_pos(s, f))
	Life.toast.connect(func(m: String) -> void: hud.toast(m))
	SaveGame.world_provider = _world_state
	SaveGame.world_restorer = _restore_world
	SaveGame.extra_providers["jobs"] = jobs.to_dict
	SaveGame.extra_restorers["jobs"] = jobs.from_dict
	SaveGame.extra_providers["story"] = Story.to_dict
	SaveGame.extra_restorers["story"] = Story.from_dict
	if not demo:
		SaveGame.load_local()
	Net.welcomed.connect(func(_id: int, _room: String) -> void: SaveGame.pull_cloud())
	hud.setup_maps(map, baker.land_tex, baker.road_tex)
	hud.waypoint_set.connect(_set_waypoint)
	hud.waypoint_cleared.connect(func() -> void: _set_waypoint(Vector2.INF))
	Settings.changed.connect(_apply_settings)
	_apply_settings(Settings.current)
	Net.met.connect(_on_met)
	Net.moved.connect(_on_moved)
	Net.gone.connect(_on_gone)
	Net.status_changed.connect(func(_t: String) -> void: _push_state())
	Net.start({ "look": _look_to_wire(player.look), "x": int(player.position.x), "y": int(player.position.y) })
	story = StoryHost.new()
	story.auto = story_auto
	add_child(story)
	story.setup(self)
	if story_auto:
		_run_story_demo()
	elif demo:
		_run_demo()
	else:
		story.begin()


# ---------- build ----------

func _noise_texture(freq: float, seed: int, size := 256) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	return t


func _build_materials() -> void:
	painted_mat = ShaderMaterial.new()
	painted_mat.shader = preload("res://shaders/painted.gdshader")
	painted_mat.set_shader_parameter("noise_hi", _noise_texture(0.06, 7))


func _build_terrain() -> void:
	terrain = ColorRect.new()
	terrain.size = map.world_px
	terrain.z_index = -100
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/terrain.gdshader")
	m.set_shader_parameter("world_size", map.world_px)
	m.set_shader_parameter("land_tex", baker.land_tex)
	m.set_shader_parameter("road_tex", baker.road_tex)
	m.set_shader_parameter("dist_tex", baker.dist_tex)
	m.set_shader_parameter("noise_lo", _noise_texture(0.012, 11))
	m.set_shader_parameter("noise_hi", _noise_texture(0.05, 23))
	var ground := { "tex_dirt": "ground/dirt.png", "tex_grass": "ground/grass.png", "tex_asphalt": "ground/asphalt.png", "tex_walk": "ground/interlock.png" }
	var all_found := true
	for key in ground:
		var gt := Art.tex(ground[key])
		all_found = all_found and gt != null
		m.set_shader_parameter(key, gt)
	m.set_shader_parameter("use_tex", all_found)
	var sand := Art.tex("ground/sand.png")
	m.set_shader_parameter("tex_sand", sand)
	m.set_shader_parameter("use_sand_tex", sand != null)
	terrain.material = m
	add_child(terrain)


func _build_actors() -> void:
	danfo = DanfoScript.new()
	danfo.set_kind("danfo")
	danfo.position = map.danfo_start
	danfo.heading = PI * 0.5
	danfo.material = painted_mat
	streamer.add_child(danfo)
	player = WalkerScript.new()
	player.look = WalkerScript.tunde()
	player.position = map.player_start
	player.use_hero_sheet("characters/tunde-walk.png")
	player.material = painted_mat
	streamer.add_child(player)


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(map.world_px.x)
	camera.limit_bottom = int(map.world_px.y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	player.add_child(camera)
	camera.make_current()
	var vignette := CanvasLayer.new()
	vignette.layer = 5
	var tr := TextureRect.new()
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	var vt := GradientTexture2D.new()
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.05, 1.05)
	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	vg.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.05, 0.03, 0.02, 0.05), Color(0.05, 0.03, 0.02, 0.6)])
	vt.gradient = vg
	tr.texture = vt
	vignette.add_child(tr)
	add_child(vignette)


# ---------- settings ----------

func _apply_settings(s: Dictionary) -> void:
	var q := { "low": 0, "medium": 1, "high": 2 }
	var quality: int = q.get(s.get("preset"), 1 if s.get("effects") != "off" else 0)
	(terrain.material as ShaderMaterial).set_shader_parameter("quality", quality)
	painted_mat.set_shader_parameter("strength", 0.0 if s.get("effects") == "off" else 1.0)
	streamer.radius = clampi(int(s.get("draw_distance", 2)) - 1, 0, 2)
	crowd.target_count = int(s.get("max_npcs", 30))
	crowd.anim_fps = float(s.get("npc_anim_fps", 10))
	traffic.target_count = { 0: 6, 1: 12, 2: 18 }.get(quality, 12)
	_update_lighting()


# ---------- world state ----------

## Dev/demo: force night on/off (normally the clock decides).
func _toggle_night() -> void:
	night_forced = 0 if night else 1
	_tick_day_night(player.position)
	_push_state()


## Dev/demo: force NEPA on/off (normally today's outage schedule decides).
func _set_nepa(on: bool) -> void:
	nepa_forced = 1 if on else 0
	_apply_nepa(on)


func _apply_nepa(on: bool) -> void:
	if on == nepa_on:
		return
	nepa_on = on
	hud.toast("UP NEPA!" if on else "NEPA don take light", on)
	_update_lighting()
	_push_state()


func _tick_day_night(focus: Vector2) -> void:
	var dark := Clock.darkness() if night_forced == -1 else float(night_forced)
	var now_night := dark > 0.02
	lights.darkness = dark
	if now_night != night or absf(dark - _last_dark) > 0.02:
		_last_dark = dark
		night = now_night
		_update_lighting()
	if nepa_forced == -1:
		_apply_nepa(not _in_outage(focus))


var _last_dark := -1.0


## Each in-game day has its own outage windows; rich districts suffer less (generators are another
## story). Deterministic per day so every player on the street shares the same blackout.
func _in_outage(focus: Vector2) -> bool:
	if _outage_day != Clock.day():
		_outage_day = Clock.day()
		_outages.clear()
		var r := RandomNumberGenerator.new()
		r.seed = Clock.day() * 104729
		for i in r.randi_range(3, 6):
			var start := r.randi_range(0, 23) * 60 + r.randi_range(0, 59)
			_outages.append({ "start": start, "end": start + r.randi_range(25, 150), "rich": r.randf() < 0.3 })
	var t := Clock.minutes % 1440
	var d: Dictionary = map.district_at(focus)
	var rich: bool = d.get("id", "") in RICH
	for o in _outages:
		if t >= int(o["start"]) and t < int(o["end"]) and (not rich or o["rich"]):
			return true
	return false


func _update_lighting() -> void:
	var simple: bool = Settings.get_value("lighting", "full") == "simple"
	lights.configure(not simple, 0.25 if Settings.get_value("preset") == "low" else 0.5)
	lights.set_state(night, nepa_on)
	streamer.set_lighting(night, nepa_on, Settings.get_value("effects", "low") != "off")


func _enter_exit() -> void:
	if mode != "driving" and _near_danfo() and Life.hero != "tunde":
		hud.toast("Na Tunde get this bus. (Hail a keke from the phone.)")
		return
	if mode == "driving":
		if absf(danfo.speed) > 40.0:
			return
		mode = "walking"
		var side := Vector2.from_angle(danfo.heading + PI / 2) * 60.0
		player.position = danfo.position + side if not map.is_blocked(danfo.position + side) else danfo.position - side
		player.target = Vector2.INF
		player.visible = true
		camera.reparent(player, false)
		camera.position = Vector2.ZERO
	elif _near_danfo():
		mode = "driving"
		player.visible = false
		camera.reparent(danfo, false)
		camera.position = Vector2.ZERO
	_push_state()


func _near_danfo() -> bool:
	return player.position.distance_to(danfo.position) < 100.0


# ---------- input ----------

func _input_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1
	v += hud.joystick.value
	if demo_input != Vector2.ZERO:
		v = demo_input
	return v.limit_length(1.0) if v.length() > 0.15 else Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		_enter_exit()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.35, 0.35), Vector2(2, 2))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.35, 0.35), Vector2(2, 2))
		elif event.button_index == MOUSE_BUTTON_LEFT and story and story.interior.active:
			story.interior.tap(event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT and mode == "walking":
			_walk_to(get_global_mouse_position())
	elif event is InputEventMagnifyGesture:
		camera.zoom = (camera.zoom * event.factor).clamp(Vector2(0.35, 0.35), Vector2(2, 2))


# ---------- loop ----------

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var inp := _input_vector()
	if story.abilities.in_wahala() or story.paused_by_story():
		inp = Vector2.ZERO
	if story.interior.active:
		danfo.drive(dt, Vector2.ZERO, map)
	elif mode == "walking":
		if inp != Vector2.ZERO:
			player.target = Vector2.INF
			player_path = PackedVector2Array()
		elif player.target == Vector2.INF and not player_path.is_empty():
			player.target = player_path[0]
			player_path.remove_at(0)
		player.step(dt, inp, map)
		danfo.drive(dt, Vector2.ZERO, map)
	else:
		var ev: String = danfo.drive(dt, inp, map)
		player.position = danfo.position
		if ev == "crash":
			hud.toast("Ehn! Who put wall there?")
			if Life.hero == "tunde":
				Life.stats["bp"] = minf(100.0, float(Life.stats.get("bp", 20.0)) + 4.0)
			if not Settings.get_value("reduced_motion", false):
				_shake(0.18)
	var focus: Vector2 = danfo.position if mode == "driving" else player.position
	var view := _view_rect()
	streamer.update_view(view, dt)
	lights.sync(get_viewport().get_camera_2d(), get_viewport_rect().size)
	traffic.update(dt * story.abilities.traffic_scale(), focus, danfo if mode == "driving" and not story.abilities.ghost() else null)
	if traffic.bumped:
		hud.toast(["Oga, you no see road?", "Na so you dey drive?", "Who give you licence?"][randi() % 3])
	crowd.update(dt, focus)
	_net_tick(dt)
	_route_tick(dt, focus)

	_tick_day_night(focus)
	story.tick(dt)
	player.speed = 150.0 * Life.pace_factor() * (1.25 if story.chase.active else 1.0)
	var stuck: bool = mode == "driving" and absf(danfo.speed) < 40.0
	jobs.tick(dt, focus, mode, stuck)
	_action_t -= dt
	if _action_t <= 0.0:
		_action_t = 0.2
		_update_action(focus)

	fps_frames += 1
	fps_time += delta
	if fps_time >= 1.0:
		fps = int(round(fps_frames / fps_time))
		fps_frames = 0
		fps_time = 0.0
	state_t -= dt
	if state_t <= 0.0:
		state_t = 0.5
		var d := map.district_at(focus)
		var dn: String = d.get("name", "Lagoon")
		if dn != _district:
			_district = dn
			hud.toast(dn)
		_push_state()


func _view_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	var size := get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - size * 0.5, size)


func _shake(t: float) -> void:
	var tw := create_tween()
	for i in 6:
		tw.tween_property(camera, "offset", Vector2(randf_range(-6, 6), randf_range(-6, 6)), t / 6.0)
	tw.tween_property(camera, "offset", Vector2.ZERO, 0.05)


func _push_state() -> void:
	hud.set_state(mode, mode == "walking" and _near_danfo(), night, nepa_on, fps)
	var online: String = "%s · %d nearby" % [Net.status_text(), remotes.size()] if Net.is_online() else Net.status_text()
	hud.set_online("%s · %s" % [_district, online] if _district != "" else online)


# ---------- life: actions, jobs, saving ----------

func _update_action(focus: Vector2) -> void:
	_action_target = {}
	var sp := story.mission_prompt(focus)
	if story.interior.active or story.paused_by_story():
		_action = ""
		hud.set_action("")
	elif sp != "":
		_action = "mission"
		hud.set_action(sp)
	elif mode == "walking" and story.ambient_prompt(focus) != "":
		_action = "talk"
		hud.set_action(story.ambient_prompt(focus))
	elif mode == "driving":
		_action = "exit"
		hud.set_action("Comot from danfo")
	elif _near_danfo():
		_action = "enter"
		hud.set_action("Enter Baba God Dey")
	else:
		var p := interactions.nearest(focus, Life.home)
		if p.is_empty():
			_action = ""
			hud.set_action("")
		else:
			_action_target = p
			_action = p["kind"]
			hud.set_action(("Buy · " + p["label"]) if p["kind"] == "vendor" else p["label"])
	var j := jobs.active
	if j.is_empty() or story.mission_running():
		hud.set_job("")
	elif j["type"] == "danfo" and j["stage"] == "driving":
		hud.set_job("%s · %d passengers · patience %d%%" % [j["name"], int(j["passengers"]), int(j["patience"])])
	elif j["type"] == "delivery" and j["stage"] == "deliver":
		hud.set_job("%s · due %02d:%02d" % [j["name"], (int(j["deadline"]) % 1440) / 60, int(j["deadline"]) % 60])
	else:
		hud.set_job("%s · go to the start" % j["name"])


func _do_action() -> void:
	match _action:
		"mission":
			story.start_prompted()
		"talk":
			story.talk()
		"enter", "exit":
			_enter_exit()
		"vendor":
			var v: Dictionary = Life.items_db["vendors"][_action_target["vendor"]]
			hud.open_shop(_action_target["label"], v["stock"])
		"home":
			var dur := Life.sleep()
			hud.toast("You slept %d hours. Fresh like new money." % (dur / 60))
			SaveGame.save_now()


func _on_job_changed(j: Dictionary) -> void:
	if j.is_empty():
		_set_waypoint(Vector2.INF)
		SaveGame.save_now()
		return
	_set_waypoint(jobs.target())
	if j["type"] == "pos" and j["stage"] == "shift":
		hud.pos_game.start(float(jobs.db["pos"]["network_fail"]))


func _world_state() -> Dictionary:
	return {
		"mode": mode, "player": [player.position.x, player.position.y],
		"danfo": [danfo.position.x, danfo.position.y, danfo.heading],
	}


func _restore_world(w: Dictionary) -> void:
	if w.has("player"):
		player.position = Vector2(w["player"][0], w["player"][1])
	if w.has("danfo"):
		danfo.position = Vector2(w["danfo"][0], w["danfo"][1])
		danfo.heading = float(w["danfo"][2])
		danfo.queue_redraw()
	if w.get("mode", "walking") == "driving" and mode != "driving":
		player.position = danfo.position
		_enter_exit()
	camera.reset_smoothing()


func _notification(what: int) -> void:
	# Save when Android pauses/closes the app.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not demo:
			SaveGame.save_now()


# ---------- navigation ----------

func _walk_to(wp: Vector2) -> void:
	var path := nav.walk_path(player.position, wp)
	if path.size() < 2:
		return
	player_path = path
	player_path.remove_at(0)
	player.target = Vector2.INF


func _set_waypoint(wp: Vector2) -> void:
	waypoint = wp
	_route_t = 0.0
	if wp == Vector2.INF:
		route = PackedVector2Array()
		hud.minimap.waypoint = Vector2.INF
		hud.minimap.route = route
		route_line.queue_redraw()


func _route_tick(dt: float, focus: Vector2) -> void:
	var heading: float = danfo.heading if mode == "driving" else (player.velocity.angle() if player.velocity.length() > 1.0 else -PI / 2)
	hud.minimap.update_view(focus, heading)
	hud.minimap.stars = story.marker_positions()
	hud.map_screen.stars = hud.minimap.stars
	if hud.map_screen.visible:
		hud.map_screen.refresh(focus, waypoint, route)
	if waypoint == Vector2.INF:
		return
	if focus.distance_to(waypoint) < 140.0:
		if not story.mission_running():
			hud.toast("You don reach!")
		_set_waypoint(Vector2.INF)
		return
	_route_t -= dt
	if _route_t <= 0.0:
		_route_t = 1.5
		route = nav.drive_path(focus, waypoint) if mode == "driving" else nav.walk_path(focus, waypoint)
		hud.minimap.waypoint = waypoint
		hud.minimap.route = route
		route_line.queue_redraw()


## Dotted GPS line on the street, like a danfo conductor pointing the way.
func _draw_route() -> void:
	if route.size() < 2:
		return
	var travelled := 0.0
	for i in route.size() - 1:
		var a: Vector2 = route[i]
		var b: Vector2 = route[i + 1]
		var seg := a.distance_to(b)
		var t := fmod(-travelled, 36.0)
		while t < seg:
			if t >= 0.0:
				route_line.draw_circle(a.lerp(b, t / seg), 5.0, Color(0.88, 0.66, 0.11, 0.85))
			t += 36.0
		travelled += seg
		if travelled > 4000.0:
			break


# ---------- multiplayer ----------

func _look_to_wire(look: Dictionary) -> Dictionary:
	var out := {}
	for k in look.keys():
		var v: Variant = look[k]
		out[k] = "#" + (v as Color).to_html(false) if v is Color else String(v)
	return out


func _look_from_wire(look: Dictionary) -> Dictionary:
	var out := WalkerScript.random_look(look.hash())
	for k in look.keys():
		var v := String(look[k])
		out[k] = Color(v) if v.begins_with("#") else v
	return out


func _on_met(id: int, name_: String, look: Dictionary) -> void:
	if remotes.has(id):
		return
	var w: Node2D = WalkerScript.new()
	w.look = _look_from_wire(look)
	w.use_pedestrian(id * 3 + 1)
	w.display_name = name_
	w.material = painted_mat
	w.visible = false
	streamer.add_child(w)
	var d: Node2D = DanfoScript.new()
	d.set_kind("danfo")
	d.material = painted_mat
	d.visible = false
	streamer.add_child(d)
	remotes[id] = { "walker": w, "danfo": d, "target": Vector2.INF, "code": 0, "mode": 0, "heading": 0.0 }
	_push_state()


func _on_moved(id: int, pos: Vector2, code: int, mode_: int, heading_deg: float) -> void:
	var r: Dictionary = remotes.get(id, {})
	if r.is_empty():
		return
	if r["target"] == Vector2.INF:
		(r["walker"] as Node2D).position = pos
		(r["danfo"] as Node2D).position = pos
	r["target"] = pos
	r["code"] = code
	r["mode"] = mode_
	r["heading"] = deg_to_rad(heading_deg)


func _on_gone(id: int) -> void:
	var r: Dictionary = remotes.get(id, {})
	if r.is_empty():
		return
	(r["walker"] as Node).queue_free()
	(r["danfo"] as Node).queue_free()
	remotes.erase(id)
	_push_state()


func _net_tick(dt: float) -> void:
	var pos: Vector2 = danfo.position if mode == "driving" else player.position
	var heading_deg := rad_to_deg(danfo.heading) if mode == "driving" else 0.0
	Net.send_move(pos, player.facing_code(), 1 if mode == "driving" else 0, heading_deg)
	for id in remotes:
		var r: Dictionary = remotes[id]
		if r["target"] == Vector2.INF:
			continue
		var w: Node2D = r["walker"]
		var d: Node2D = r["danfo"]
		var driving: bool = r["mode"] == 1
		w.visible = not driving
		d.visible = driving
		if driving:
			d.position = d.position.lerp(r["target"], minf(1.0, dt * 10.0)) if d.position.distance_to(r["target"]) < 320.0 else r["target"]
			d.heading = lerp_angle(d.heading, r["heading"], minf(1.0, dt * 10.0))
			d.queue_redraw()
			w.position = d.position
		else:
			w.follow(dt, r["target"], r["code"])
			d.position = w.position


# ---------- demo / screenshots ----------

func _shot(name: String) -> void:
	if shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join(name + ".png"))
	print("shot: ", name)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _measure(label: String) -> void:
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await _wait(2.5)
	print("perf %s: %.1f fps (max_fps %d, preset %s, people %d, vehicles %d)" % [label, (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0), Engine.max_fps, Settings.get_value("preset"), crowd.people.size(), traffic.vehicles.size()])


func _teleport(p: Vector2) -> void:
	player.position = p
	camera.reset_smoothing()


## Story QA: play the Prologue and all of Act 1 with autoplaying UI, screenshots along the way.
func _run_story_demo() -> void:
	Story.reset()
	await _wait(0.8)
	var t0 := Time.get_ticks_msec()
	story.begin()
	while not Story.is_done("P4") and Time.get_ticks_msec() - t0 < 240000:
		await _wait(0.5)
	print("story: prologue done=%s switching=%s hero=%s" % [Story.is_done("P4"), Story.switching, Life.hero])
	for id in ["1.1", "1.2", "1.3", "1.4", "1.5"]:
		var m: Dictionary = Story.missions[id]
		var hero: String = m["hero"] if m["hero"] in Story.HEROES else Life.hero
		if hero != Life.hero:
			await story._do_switch(hero, Vector2.INF)
		_teleport(story._start_pos(id))
		await _wait(0.4)
		story.start_mission(id)
		var t1 := Time.get_ticks_msec()
		while not Story.is_done(id) and Time.get_ticks_msec() - t1 < 180000:
			await _wait(0.5)
		print("story: %s done=%s money_s=%d flags=%s" % [id, Story.is_done(id), Story.story_money, Life.flags])
	await _wait(1.0)
	await _shot("story-zz-free-roam")
	# Phone story apps and a named character on their daily routine.
	hud.phone.open()
	story._build_story_app(hud.phone)
	await _wait(0.4)
	await _shot("story-zz-phone-story")
	story._build_switch_app(hud.phone)
	await _wait(0.4)
	await _shot("story-zz-phone-switch")
	hud.phone.visible = false
	Clock.minutes = (Clock.day()) * 1440 + 10 * 60
	_teleport(map.landmarks["tunde-depot"]["pos"] + Vector2(-40, 90))
	await _wait(2.5)
	await _shot("story-zz-sule-at-depot")
	await _measure("story")
	print("story: complete=%s tiers=%s rel=%s" % [Story.is_done("1.5"), Story.tiers, Life.relationships])
	get_tree().quit()


func _run_demo() -> void:
	await _wait(1.0)
	# Whole-map overview from a temporary camera.
	var over := Camera2D.new()
	over.position = map.world_px * 0.5
	var z := minf(1280.0 / map.world_px.x, 720.0 / map.world_px.y)
	over.zoom = Vector2(z, z)
	add_child(over)
	over.make_current()
	await _wait(0.5)
	await _shot("00-lagos-overview")
	camera.make_current()
	over.queue_free()
	for spot in [["01-surulere-start", map.player_start], ["02-yaba", map.road_nodes["yaba_c"] + Vector2(0, 120)], ["03-oshodi", map.road_nodes["oshodi_c"] + Vector2(140, 120)], ["04-obalende", map.landmarks["obalende-motor-park"]["pos"]], ["05-lekki-beach", map.road_nodes["lekki_beach"] + Vector2(0, 260)]]:
		_teleport(spot[1])
		await _wait(1.6)
		await _shot(spot[0])
	await _measure("day")
	# Life systems: buy food, take a delivery, sleep.
	Life.needs["hunger"] = 20.0
	Life.buy("amala")
	print("life: hunger %.0f money %d mood %s" % [Life.needs["hunger"], Life.money, Life.mood_label()])
	jobs.accept(jobs.offers.filter(func(o: Dictionary) -> bool: return o["type"] == "delivery")[0])
	_teleport(jobs.start_pos(jobs.active))
	await _wait(0.6)
	_teleport(jobs.end_pos(jobs.active))
	await _wait(0.6)
	print("life: after delivery money %d, hustle lv %d" % [Life.money, Life.level("hustle")])
	hud.phone.open()
	await _wait(0.4)
	await _shot("05a-phone")
	hud.phone.visible = false
	_set_waypoint(map.landmarks["lekki-event-centre"]["pos"])
	hud.map_screen.visible = true
	await _wait(0.6)
	await _shot("05b-map-screen")
	hud.map_screen.visible = false
	# Drive across the Third Mainland Bridge.
	_teleport(map.road_nodes["yaba_s"] + Vector2(-40, 0))
	danfo.position = map.road_nodes["yaba_s"]
	danfo.heading = (map.road_nodes["tmb_mid"] - map.road_nodes["yaba_s"]).angle()
	await _wait(0.5)
	_enter_exit()
	demo_input = (map.road_nodes["tmb_mid"] - map.road_nodes["yaba_s"]).normalized()
	await _wait(2.2)
	await _shot("06-third-mainland-bridge")
	demo_input = Vector2.ZERO
	await _wait(0.8)
	_toggle_night()
	await _wait(0.8)
	await _shot("07-night")
	_set_nepa(false)
	await _wait(1.0)
	await _shot("08-nepa-off")
	_set_nepa(true)
	await _measure("night")
	get_tree().quit()
