extends Node2D
## M0 style test: one painted Yaba junction in top-down 3/4 (D-004), Android-first Godot (D-005).
## Walk Tunde, drive "Baba God Dey", watch the street, flip night on, survive NEPA.
##
## Demo/screenshot mode for automated checks:
##   Godot --path game -- --demo --shots=C:/some/dir

const BuildingScript := preload("res://actors/building.gd")
const PropScript := preload("res://actors/prop.gd")
const WalkerScript := preload("res://actors/walker.gd")
const DanfoScript := preload("res://actors/danfo.gd")
const HudScript := preload("res://ui/hud.gd")

var world: Layout.WorldData
var terrain: ColorRect
var entities: Node2D
var player: Node2D
var danfo: Node2D
var npcs: Array[Node2D] = []
var props: Array[Node2D] = []
var camera: Camera2D
var hud: CanvasLayer
var modulate_node: CanvasModulate
var lights_on: Array[PointLight2D] = [] # street and window lights (need NEPA)
var lights_gen: Array[PointLight2D] = [] # generator-powered lights
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


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--demo":
			demo = true
		elif a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
		elif a.begins_with("--preset="):
			Settings.use_preset(a.trim_prefix("--preset="))
		elif a.begins_with("--server="):
			Net.server = a.trim_prefix("--server=")
		elif a == "--perf-no-terrain":
			_perf_flags["no_terrain"] = true
		elif a == "--perf-no-vignette":
			_perf_flags["no_vignette"] = true
	world = Layout.build_yaba()
	_build_materials()
	_build_terrain()
	_build_entities()
	_build_lighting()
	_build_camera()
	hud = HudScript.new()
	add_child(hud)
	hud.toggle_night.connect(_toggle_night)
	hud.toggle_nepa.connect(func() -> void: _set_nepa(not nepa_on))
	hud.enter_exit.connect(_enter_exit)
	Settings.changed.connect(_apply_settings)
	_apply_settings(Settings.current)
	Net.met.connect(_on_met)
	Net.moved.connect(_on_moved)
	Net.gone.connect(_on_gone)
	Net.status_changed.connect(func(_t: String) -> void: _push_state())
	Net.start({ "look": _look_to_wire(player.look), "x": int(player.position.x), "y": int(player.position.y) })
	if _perf_flags.get("no_terrain", false):
		terrain.material = null
		terrain.color = Color("#8a7656")
	if _perf_flags.get("no_vignette", false):
		for c in get_children():
			if c is CanvasLayer and c != hud:
				c.visible = false
	if demo:
		_run_demo()


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
	terrain.size = Layout.WORLD
	terrain.z_index = -100
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/terrain.gdshader")
	m.set_shader_parameter("world_size", Layout.WORLD)
	m.set_shader_parameter("noise_lo", _noise_texture(0.012, 11))
	m.set_shader_parameter("noise_hi", _noise_texture(0.05, 23))
	m.set_shader_parameter("main_y0", float(Layout.MAIN_Y0))
	m.set_shader_parameter("main_y1", float(Layout.MAIN_Y1))
	m.set_shader_parameter("cross_x0", float(Layout.CROSS_X0))
	m.set_shader_parameter("cross_x1", float(Layout.CROSS_X1))
	m.set_shader_parameter("gutter", Layout.GUTTER)
	m.set_shader_parameter("walk", Layout.WALK)
	# Painted ground textures, if generated (game/art/ground); otherwise procedural colours.
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
	m.set_shader_parameter("island_center", Layout.ISLAND_CENTER)
	m.set_shader_parameter("island_radii", Layout.ISLAND_RADII)
	m.set_shader_parameter("beach_start", Layout.BEACH_START)
	m.set_shader_parameter("road_end", Layout.ROAD_END)
	terrain.material = m
	add_child(terrain)


func _build_entities() -> void:
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	for b in world.buildings:
		var n: Node2D = BuildingScript.new()
		n.setup(b)
		n.material = painted_mat
		entities.add_child(n)
	for p in world.props:
		var n: Node2D = PropScript.new()
		n.setup(p)
		n.material = painted_mat
		entities.add_child(n)
		props.append(n)
	# Sagging wires between the poles on the north walkway (drawn above the ground, below roofs).
	var wires := Node2D.new()
	wires.z_index = 5
	wires.draw.connect(func() -> void: _draw_wires(wires))
	add_child(wires)

	danfo = DanfoScript.new()
	danfo.position = world.danfo_start
	danfo.material = painted_mat
	entities.add_child(danfo)

	player = WalkerScript.new()
	player.look = WalkerScript.tunde()
	player.position = world.player_start
	player.use_hero_sheet("characters/tunde-walk.png")
	player.material = painted_mat
	entities.add_child(player)


func _draw_wires(c: Node2D) -> void:
	var tops: Array[Vector2] = []
	for p in props:
		if (p.kind == "pole" or p.kind == "transformer") and absf(p.position.y - (13.5 * Layout.CELL)) < 1.0:
			tops.append(p.position + p.wire_anchor())
	tops.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for i in tops.size() - 1:
		for off in [-14.0, 0.0, 14.0]:
			var a := tops[i] + Vector2(0, off * 0.3 - 2)
			var b := tops[i + 1] + Vector2(0, off * 0.3 - 2)
			var pts := PackedVector2Array()
			for k in 13:
				var t := k / 12.0
				pts.append(a.lerp(b, t) + Vector2(0, sin(t * PI) * 16.0))
			c.draw_polyline(pts, Color(0.1, 0.08, 0.07, 0.8), 1.4, true)


func _spawn_npcs(count: int) -> void:
	for n in npcs:
		n.queue_free()
	npcs.clear()
	var r := Ink.rng(2026)
	var tries := 0
	while npcs.size() < count and tries < 800:
		tries += 1
		var p := Vector2(r.randf_range(32, Layout.WORLD.x - 32), r.randf_range(32, Layout.WORLD.y - 32))
		if world.is_blocked(p) or Layout.surface_at(p) == "road":
			continue
		var n: Node2D = WalkerScript.new()
		n.look = WalkerScript.random_look(900 + npcs.size() * 17)
		n.use_pedestrian(npcs.size())
		n.position = p
		n.speed = r.randf_range(45, 85)
		n.material = painted_mat
		entities.add_child(n)
		npcs.append(n)


func _build_lighting() -> void:
	modulate_node = CanvasModulate.new()
	modulate_node.color = Color.WHITE
	add_child(modulate_node)
	var tex := GradientTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.93, 0.74, 1.0))
	g.set_color(1, Color(1.0, 0.93, 0.74, 0.0))
	tex.gradient = g
	var add_light := func(pos: Vector2, scale_: float, energy: float, generator: bool) -> void:
		var l := PointLight2D.new()
		l.texture = tex
		l.position = pos
		l.texture_scale = scale_
		l.energy = energy
		l.enabled = false
		add_child(l)
		(lights_gen if generator else lights_on).append(l)
	for p in props:
		if p.kind == "pole" or p.kind == "transformer":
			add_light.call(p.position + Vector2(0, 10), 1.6, 1.1, false)
	for b in world.buildings:
		var fp := b.footprint()
		var door := Vector2(fp.get_center().x, fp.end.y + 18)
		add_light.call(door, 1.2, 0.9, false)
		if b.generator:
			add_light.call(door, 1.5, 1.2, true)


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = -120
	camera.limit_right = int(Layout.WORLD.x)
	camera.limit_bottom = int(Layout.WORLD.y)
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
	_spawn_npcs(int(s.get("max_npcs", 30)))
	for n in npcs:
		n.anim_fps = float(s.get("npc_anim_fps", 10))
	_update_lighting()


# ---------- world state ----------

func _toggle_night() -> void:
	night = not night
	_update_lighting()
	_push_state()


func _set_nepa(on: bool) -> void:
	if on == nepa_on:
		return
	nepa_on = on
	hud.toast("UP NEPA!" if on else "NEPA don take light", on)
	_update_lighting()
	_push_state()


func _update_lighting() -> void:
	var simple: bool = Settings.get_value("lighting", "full") == "simple"
	if not night:
		modulate_node.color = Color.WHITE
	elif nepa_on:
		modulate_node.color = Color(0.36, 0.34, 0.52)
	else:
		modulate_node.color = Color(0.17, 0.15, 0.28)
	for l in lights_on:
		l.enabled = night and nepa_on and not simple
	for l in lights_gen:
		l.enabled = night and not nepa_on and not simple
	var gens: bool = not nepa_on and Settings.get_value("effects", "low") != "off"
	for p in props:
		p.set_generator_running(gens)


func _enter_exit() -> void:
	if mode == "driving":
		if absf(danfo.speed) > 40.0:
			return
		mode = "walking"
		var side := Vector2.from_angle(danfo.heading + PI / 2) * 52.0
		player.position = danfo.position + side if not world.is_blocked(danfo.position + side) else danfo.position - side
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
	return player.position.distance_to(danfo.position) < 90.0


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
			camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.5, 0.5), Vector2(2, 2))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.5, 0.5), Vector2(2, 2))
		elif event.button_index == MOUSE_BUTTON_LEFT and mode == "walking":
			var wp := get_global_mouse_position()
			if not world.is_blocked(wp):
				player.target = wp
	elif event is InputEventMagnifyGesture:
		camera.zoom = (camera.zoom * event.factor).clamp(Vector2(0.5, 0.5), Vector2(2, 2))


# ---------- loop ----------

var demo_input := Vector2.ZERO
var _perf_flags := {}


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var inp := _input_vector()
	if mode == "walking":
		if inp != Vector2.ZERO:
			player.target = Vector2.INF
		player.step(dt, inp, world)
		danfo.drive(dt, Vector2.ZERO, world)
	else:
		var ev: String = danfo.drive(dt, inp, world)
		player.position = danfo.position
		if ev == "crash":
			hud.toast("Ehn! Who put wall there?")
			if not Settings.get_value("reduced_motion", false):
				_shake(0.18)
	for n in npcs:
		if n.target == Vector2.INF:
			n.idle_t -= dt
			if n.idle_t <= 0.0:
				var reach := 60.0 if n.loiterer else 220.0
				var t: Vector2 = n.position + Vector2(randf_range(-reach, reach), randf_range(-reach * 0.5, reach * 0.5))
				if not world.is_blocked(t) and Layout.surface_at(t) != "road":
					n.target = t
				n.idle_t = randf_range(0.5, 3.0)
		n.step(dt, Vector2.ZERO, world)

	_net_tick(dt)

	if night:
		outage_t -= dt
		if outage_t <= 0.0:
			outage_t = randf_range(40.0, 90.0)
			_set_nepa(not nepa_on)

	fps_frames += 1
	fps_time += delta
	if fps_time >= 1.0:
		fps = int(round(fps_frames / fps_time))
		fps_frames = 0
		fps_time = 0.0
	state_t -= dt
	if state_t <= 0.0:
		state_t = 0.5
		_push_state()


var _shake_t := 0.0
func _shake(t: float) -> void:
	_shake_t = t
	var tw := create_tween()
	for i in 6:
		tw.tween_property(camera, "offset", Vector2(randf_range(-6, 6), randf_range(-6, 6)), t / 6.0)
	tw.tween_property(camera, "offset", Vector2.ZERO, 0.05)


func _push_state() -> void:
	hud.set_state(mode, mode == "walking" and _near_danfo(), night, nepa_on, fps)
	hud.set_online("%s · %d nearby" % [Net.status_text(), remotes.size()] if Net.is_online() else Net.status_text())


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
	w.visible = false # shown on first position
	entities.add_child(w)
	var d: Node2D = DanfoScript.new()
	d.material = painted_mat
	d.visible = false
	entities.add_child(d)
	remotes[id] = { "walker": w, "danfo": d, "target": Vector2.INF, "code": 0, "mode": 0, "heading": 0.0 }
	_push_state()


func _on_moved(id: int, pos: Vector2, code: int, mode_: int, heading_deg: float) -> void:
	var r: Dictionary = remotes.get(id, {})
	if r.is_empty():
		return
	var w: Node2D = r["walker"]
	if r["target"] == Vector2.INF:
		w.position = pos
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


func _run_demo() -> void:
	await _wait(1.0)
	# Whole-island overview from a temporary camera.
	var over := Camera2D.new()
	over.position = Layout.WORLD * 0.5
	over.zoom = Vector2(0.5, 0.5)
	add_child(over)
	over.make_current()
	await _wait(0.4)
	await _shot("00-island-overview")
	camera.make_current()
	over.queue_free()
	# Beach close-up on the south shore, then back to town.
	var home: Vector2 = player.position
	player.position = Vector2(1240, 1560)
	await _wait(1.0)
	await _shot("00b-beach")
	player.position = home
	await _wait(1.0)
	await _shot("01-day-walk")
	await _measure("day")
	player.target = danfo.position + Vector2(0, 60)
	await _wait(1.5)
	_enter_exit()
	demo_input = Vector2(1, 0)
	await _wait(2.0)
	demo_input = Vector2(0.3, 1)
	await _wait(0.9)
	demo_input = Vector2.ZERO
	await _wait(0.6)
	await _shot("02-driving")
	print("danfo at ", danfo.position, " mode ", mode)
	_toggle_night()
	await _wait(0.8)
	await _shot("03-night")
	_set_nepa(false)
	await _wait(1.2)
	await _shot("04-nepa-off")
	_set_nepa(true)
	await _wait(0.3)
	await _shot("05-up-nepa")
	await _measure("night")
	get_tree().quit()


func _measure(label: String) -> void:
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await _wait(2.5)
	print("perf %s: %.1f fps (max_fps %d, preset %s, npcs %d)" % [label, (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0), Engine.max_fps, Settings.get_value("preset"), npcs.size()])
