class_name TitleAerial
extends Control
## The title screen: tropical-island Lagos from the air (owner request 2026-10-15: "an aerial view
## of the map with planes flying over the islands and waves crashing on the shore with birds").
##  - The island is the real game map, baked from above (main.gd --bake-aerial -> art/title/).
##  - Water is alive (shaders/title_sea.gdshader): swells roll in and surf breaks on every beach.
##  - Airliners trail contrails, a light plane circles, a news helicopter hovers, seagull flocks
##    cross, boats leave wakes on the lagoon, clouds drift over with their shadows, and once the
##    map has loaded, danfos and cars move along the real roads.
##  - The camera drifts slowly between sights (the bridge, Lekki beach, Yaba, Oshodi).
## Everything is placed in bake pixels (game world px x 0.25).

const INK := Color("#1d1611")
const DANFO := Color("#e0a91c")
const CAR_COLOURS := [Color("#e0a91c"), Color("#e0a91c"), Color("#e0a91c"), Color("#c8432f"), Color("#2f6f99"), Color("#ece4d2"), Color("#3a3a3a"), Color("#2f8a52")]

var _world := Node2D.new()
var _sky: _Sky
var _meta := {}
var _bake := Vector2(3072, 2112)
var _shore: Image
var _sights: Array = []
var _cam := Vector2.ZERO
var _cam_from := Vector2.ZERO
var _cam_to := Vector2.ZERO
var _cam_t := 0.0
var _sight_i := 0
var _zoom := 1.2
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var f := FileAccess.open("res://art/title/aerial.json", FileAccess.READ)
	if f:
		_meta = JSON.parse_string(f.get_as_text())
	var tex: Texture2D = load("res://art/title/aerial.jpg")
	var shore_tex: Texture2D = load("res://art/title/aerial-shore.png")
	if tex:
		_bake = tex.get_size()
	if shore_tex:
		_shore = shore_tex.get_image()
	var k := float(_meta.get("scale", 0.25))
	for s in _meta.get("sights", []):
		_sights.append(Vector2(s[0], s[1]) * k)
	if _sights.is_empty():
		_sights = [_bake * 0.5]
	var noise := FastNoiseLite.new()
	noise.frequency = 0.01
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	var shader: Shader = preload("res://shaders/title_sea.gdshader")
	add_child(_world)
	# Open ocean beyond the map edges.
	var ocean := ColorRect.new()
	ocean.position = -_bake
	ocean.size = _bake * 3.0
	var om := ShaderMaterial.new()
	om.shader = shader
	om.set_shader_parameter("noise_tex", nt)
	om.set_shader_parameter("bake_size", _bake)
	om.set_shader_parameter("origin", -_bake)
	om.set_shader_parameter("is_map", 0.0)
	ocean.material = om
	_world.add_child(ocean)
	var map := Sprite2D.new()
	map.texture = tex
	map.centered = false
	var mm := ShaderMaterial.new()
	mm.shader = shader
	mm.set_shader_parameter("noise_tex", nt)
	mm.set_shader_parameter("shore_tex", shore_tex)
	mm.set_shader_parameter("bake_size", _bake)
	mm.set_shader_parameter("is_map", 1.0)
	map.material = mm
	_world.add_child(map)
	_sky = _Sky.new()
	_sky.owner_scene = self
	_world.add_child(_sky)
	_cam = _sights[0]
	_cam_from = _cam
	_cam_to = _sights[min(1, _sights.size() - 1)]
	resized.connect(_fit)
	_fit()


## main.gd hands over the map once it's built: start traffic on the real roads.
func set_map(m: MapData) -> void:
	_sky.start_traffic(m, float(_meta.get("scale", 0.25)))


## True when a bake pixel is open water at least `cells` map cells from land.
func is_water(p: Vector2, cells := 2) -> bool:
	if _shore == null:
		return false
	var c := Vector2i(p / 16.0)
	if c.x < 0 or c.y < 0 or c.x >= _shore.get_width() or c.y >= _shore.get_height():
		return true
	return _shore.get_pixelv(c).r * 10.0 >= float(cells) - 0.01


func _cover() -> float:
	return maxf(size.x / _bake.x, size.y / _bake.y)


func _fit() -> void:
	_apply_camera()


func _process(delta: float) -> void:
	_t += delta
	# Glide from sight to sight (14 s each, eased), breathing the zoom in and out.
	_cam_t += delta / 14.0
	if _cam_t >= 1.0:
		_cam_t = 0.0
		_sight_i = (_sight_i + 1) % _sights.size()
		_cam_from = _cam
		_cam_to = _sights[(_sight_i + 1) % _sights.size()]
	var e := _cam_t * _cam_t * (3.0 - 2.0 * _cam_t)
	_cam = _cam_from.lerp(_cam_to, e)
	_zoom = 1.25 + 0.15 * sin(_t * 0.12)
	_apply_camera()


func _apply_camera() -> void:
	if size.x <= 0.0:
		return
	var s := _cover() * _zoom
	var half := size / s * 0.5
	# Stay over the baked map (its own sea reaches past the islands).
	var c := Vector2(clampf(_cam.x, half.x, maxf(half.x, _bake.x - half.x)), clampf(_cam.y, half.y, maxf(half.y, _bake.y - half.y)))
	_world.scale = Vector2(s, s)
	_world.position = size * 0.5 - c * s
	_sky.view = Rect2(c - half, half * 2.0)


## Everything that moves over the island, in bake pixels.
class _Sky extends Node2D:
	var owner_scene: TitleAerial
	var view := Rect2()
	var planes: Array = []
	var birds: Array = []
	var boats: Array = []
	var clouds: Array = []
	var cars: Array = []
	var heli := {}
	var cessna := {}
	var _plane_t := 2.0
	var _bird_t := 1.0
	var _boat_t := 0.5
	var _map: MapData
	var _k := 0.25
	var _rng := RandomNumberGenerator.new()
	var _cloud_tex: GradientTexture2D
	var _t := 0.0

	func _ready() -> void:
		_rng.randomize()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_cloud_tex = GradientTexture2D.new()
		_cloud_tex.gradient = g
		_cloud_tex.fill = GradientTexture2D.FILL_RADIAL
		_cloud_tex.fill_from = Vector2(0.5, 0.5)
		_cloud_tex.fill_to = Vector2(1.0, 0.5)
		_cloud_tex.width = 64
		_cloud_tex.height = 64
		for i in 5:
			clouds.append(_cloud(_rng.randf_range(-400, 3200)))
		cessna = { "c": Vector2(1500, 900), "r": 520.0, "a": 0.0, "p": Vector2.ZERO, "h": 0.0 }
		heli = { "p": Vector2(1700, 1200), "goal": Vector2(1700, 1200), "h": 0.0, "rot": 0.0, "wait": 2.0 }
		for i in 4:
			_spawn_boat()

	func start_traffic(m: MapData, k: float) -> void:
		_map = m
		_k = k
		var names: Array = m.road_graph.keys()
		for i in 46:
			var a: String = names[_rng.randi() % names.size()]
			var nbs: Array = m.road_graph[a]
			if nbs.is_empty():
				continue
			cars.append({ "a": a, "b": nbs[_rng.randi() % nbs.size()], "u": _rng.randf(), "v": _rng.randf_range(22.0, 34.0), "col": TitleAerial.CAR_COLOURS[_rng.randi() % TitleAerial.CAR_COLOURS.size()], "big": _rng.randf() < 0.55 })

	# ---------- spawning ----------

	func _cloud(x: float) -> Dictionary:
		var puffs := []
		for i in _rng.randi_range(6, 11):
			puffs.append([Vector2(_rng.randf_range(-110, 110), _rng.randf_range(-45, 45)), _rng.randf_range(45, 95)])
		return { "p": Vector2(x, _rng.randf_range(-100, 2200)), "v": _rng.randf_range(10, 18), "puffs": puffs }

	func _edge_point(dir: Vector2) -> Vector2:
		# Start just outside the view, on the side the plane comes from.
		var c := view.get_center()
		var r := view.size.length() * 0.6 + 200.0
		return c - dir * r + Vector2(-dir.y, dir.x) * _rng.randf_range(-view.size.y * 0.35, view.size.y * 0.35)

	func _spawn_plane(first := false) -> void:
		var dir := Vector2.from_angle(_rng.randf_range(-0.5, 0.5) + (PI if _rng.randf() < 0.5 else 0.0) + _rng.randf_range(-0.3, 0.3))
		var p := _edge_point(dir)
		if first:
			p = view.get_center() - dir * view.size.x * 0.3
		planes.append({ "p": p, "d": dir, "v": _rng.randf_range(85, 120), "trail": [], "trail_t": 0.0, "alt": _rng.randf_range(70, 110), "size": _rng.randf_range(0.9, 1.15), "life": 40.0 })

	func _spawn_flock() -> void:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		var lead := _edge_point(dir)
		var n := _rng.randi_range(5, 9)
		var flock := []
		for i in n:
			var row := (i + 1) / 2
			var side := -1.0 if i % 2 == 0 else 1.0
			flock.append({ "off": -dir * row * 16.0 + Vector2(-dir.y, dir.x) * side * row * 12.0, "ph": _rng.randf() * TAU })
		birds.append({ "p": lead, "d": dir, "v": _rng.randf_range(40, 55), "flock": flock, "life": 70.0 })

	func _spawn_boat() -> void:
		for attempt in 40:
			var a := Vector2(_rng.randf_range(0, 3072), _rng.randf_range(0, 2112))
			if not owner_scene.is_water(a, 3):
				continue
			var dir := Vector2.from_angle(_rng.randf() * TAU)
			var b := a + dir * _rng.randf_range(400, 900)
			var ok := true
			for s in 12:
				if not owner_scene.is_water(a.lerp(b, s / 11.0), 2):
					ok = false
					break
			if ok:
				boats.append({ "p": a, "b": b, "d": dir, "v": _rng.randf_range(14, 30), "kind": _rng.randi() % 3, "wake": [], "wake_t": 0.0 })
				return

	# ---------- update ----------

	func _process(delta: float) -> void:
		var dt := minf(delta, 0.05)
		_t += dt
		if view.size == Vector2.ZERO:
			return
		if _t < 0.1:
			_spawn_plane(true)
		_plane_t -= dt
		if _plane_t <= 0.0:
			_plane_t = _rng.randf_range(9.0, 16.0)
			_spawn_plane()
		_bird_t -= dt
		if _bird_t <= 0.0:
			_bird_t = _rng.randf_range(5.0, 9.0)
			_spawn_flock()
		_boat_t -= dt
		if _boat_t <= 0.0:
			_boat_t = 3.0
			if boats.size() < 7:
				_spawn_boat()
		for pl: Dictionary in planes:
			pl["p"] += pl["d"] * pl["v"] * dt
			pl["life"] -= dt
			pl["trail_t"] -= dt
			if pl["trail_t"] <= 0.0:
				pl["trail_t"] = 0.12
				pl["trail"].push_front(pl["p"])
				if pl["trail"].size() > 34:
					pl["trail"].pop_back()
		planes = planes.filter(func(x: Dictionary) -> bool: return x["life"] > 0.0)
		for b: Dictionary in birds:
			b["p"] += b["d"] * b["v"] * dt
			b["life"] -= dt
		birds = birds.filter(func(x: Dictionary) -> bool: return x["life"] > 0.0)
		for bt: Dictionary in boats:
			bt["p"] += bt["d"] * bt["v"] * dt
			bt["wake_t"] -= dt
			if bt["wake_t"] <= 0.0:
				bt["wake_t"] = 0.25
				bt["wake"].push_front(bt["p"])
				if bt["wake"].size() > 16:
					bt["wake"].pop_back()
		boats = boats.filter(func(x: Dictionary) -> bool: return x["p"].distance_to(x["b"]) > 10.0 and (x["b"] - x["p"]).dot(x["d"]) > 0.0)
		for c: Dictionary in clouds:
			c["p"].x += c["v"] * dt
			if c["p"].x > 3500.0:
				clouds[clouds.find(c)] = _cloud(-500.0)
		# The light plane circles the islands.
		cessna["a"] += dt * 0.11
		var cp: Vector2 = cessna["c"] + Vector2(cos(cessna["a"]) * cessna["r"] * 1.5, sin(cessna["a"]) * cessna["r"])
		cessna["h"] = (cp - cessna["p"]).angle() if cessna["p"] != Vector2.ZERO else 0.0
		cessna["p"] = cp
		# The news helicopter hops between spots and hovers.
		heli["rot"] += dt * 30.0
		var to: Vector2 = heli["goal"] - heli["p"]
		if to.length() < 4.0:
			heli["wait"] -= dt
			if heli["wait"] <= 0.0:
				heli["wait"] = _rng.randf_range(3.0, 6.0)
				heli["goal"] = view.get_center() + Vector2(_rng.randf_range(-0.35, 0.35) * view.size.x, _rng.randf_range(-0.3, 0.3) * view.size.y)
		else:
			heli["h"] = lerp_angle(heli["h"], to.angle(), dt * 2.0)
			heli["p"] += to.normalized() * minf(to.length(), 45.0 * dt)
		if _map:
			for car: Dictionary in cars:
				var pa: Vector2 = _map.road_nodes[car["a"]] * _k
				var pb: Vector2 = _map.road_nodes[car["b"]] * _k
				var len := maxf(1.0, pa.distance_to(pb))
				car["u"] += car["v"] * dt / len
				if car["u"] >= 1.0:
					var nbs: Array = (_map.road_graph.get(car["b"], []) as Array).filter(func(x: String) -> bool: return x != car["a"])
					if nbs.is_empty():
						nbs = [car["a"]]
					car["a"] = car["b"]
					car["b"] = nbs[_rng.randi() % nbs.size()]
					car["u"] = 0.0
		queue_redraw()

	# ---------- drawing ----------

	func _draw() -> void:
		# Cars on the roads.
		if _map:
			for car: Dictionary in cars:
				var pa: Vector2 = _map.road_nodes[car["a"]] * _k
				var pb: Vector2 = _map.road_nodes[car["b"]] * _k
				var dir := (pb - pa).normalized()
				var pos := pa.lerp(pb, car["u"]) + Vector2(-dir.y, dir.x) * 4.0
				var l := 11.0 if car["big"] else 8.0
				draw_set_transform(pos, dir.angle())
				draw_rect(Rect2(-l * 0.5 + 1.5, -2.5 + 1.5, l, 5.0), Color(0, 0, 0, 0.25))
				draw_rect(Rect2(-l * 0.5, -2.5, l, 5.0), TitleAerial.DANFO if car["big"] else car["col"])
				draw_rect(Rect2(l * 0.5 - 3.0, -2.0, 2.0, 4.0), Color(0.2, 0.3, 0.35, 0.8))
			draw_set_transform(Vector2.ZERO)
		# Boats and their wakes.
		for bt: Dictionary in boats:
			var w: Array = bt["wake"]
			var side: Vector2 = Vector2(-bt["d"].y, bt["d"].x)
			for i in w.size():
				var a := 1.0 - float(i) / w.size()
				var spread := 2.0 + i * 2.2
				var c := Color(1, 1, 1, 0.5 * a)
				draw_line(w[i] + side * spread, w[i] + side * (spread + 3.0), c, 1.5)
				draw_line(w[i] - side * spread, w[i] - side * (spread + 3.0), c, 1.5)
			var hull: Color = [Color("#efe7d6"), Color("#c8432f"), Color("#5a3b22")][bt["kind"]]
			var l := 18.0 if bt["kind"] < 2 else 12.0
			draw_set_transform(bt["p"], bt["d"].angle())
			draw_colored_polygon(PackedVector2Array([Vector2(l * 0.5, 0), Vector2(l * 0.2, -3.5), Vector2(-l * 0.5, -3), Vector2(-l * 0.5, 3), Vector2(l * 0.2, 3.5)]), hull)
			if bt["kind"] == 0:
				draw_rect(Rect2(-4, -2, 6, 4), Color("#2f6f99"))
			draw_set_transform(Vector2.ZERO)
		# Seagull flocks (with shadows on the ground far below).
		for b: Dictionary in birds:
			for m: Dictionary in b["flock"]:
				var p: Vector2 = b["p"] + m["off"]
				var flap := sin(_t * 9.0 + m["ph"]) * 0.7
				_gull(p + Vector2(14, 20), b["d"], flap, Color(0, 0, 0, 0.18))
				_gull(p, b["d"], flap, Color(0.97, 0.97, 0.95, 0.95))
		# News helicopter.
		var hp: Vector2 = heli["p"]
		_heli(hp + Vector2(22, 32), heli["h"], heli["rot"], true)
		_heli(hp, heli["h"], heli["rot"], false)
		# Light plane.
		_cessna(cessna["p"] + Vector2(30, 44), cessna["h"], true)
		_cessna(cessna["p"], cessna["h"], false)
		# Clouds (and their shadows).
		for c: Dictionary in clouds:
			for pf in c["puffs"]:
				var r: float = pf[1]
				draw_texture_rect(_cloud_tex, Rect2(c["p"] + pf[0] + Vector2(90, 130) - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0, 0, 0, 0.13))
		for c: Dictionary in clouds:
			for pf in c["puffs"]:
				var r: float = pf[1]
				draw_texture_rect(_cloud_tex, Rect2(c["p"] + pf[0] - Vector2(r, r) * 1.3, Vector2(r, r) * 2.6), false, Color(1, 1, 1, 0.34))
		# Airliners on top: contrails, shadow far below, then the plane.
		for pl: Dictionary in planes:
			var tr: Array = pl["trail"]
			var side: Vector2 = Vector2(-pl["d"].y, pl["d"].x) * 9.0 * float(pl["size"])
			for i in range(1, tr.size()):
				var a := (1.0 - float(i) / tr.size()) * 0.55
				draw_line(tr[i - 1] + side, tr[i] + side, Color(1, 1, 1, a), 3.0 + i * 0.12)
				draw_line(tr[i - 1] - side, tr[i] - side, Color(1, 1, 1, a), 3.0 + i * 0.12)
			_airliner(pl["p"] + Vector2(pl["alt"], pl["alt"] * 1.4), pl["d"].angle(), pl["size"] * 0.9, true)
			_airliner(pl["p"], pl["d"].angle(), pl["size"], false)

	func _gull(p: Vector2, dir: Vector2, flap: float, c: Color) -> void:
		var side := Vector2(-dir.y, dir.x)
		var tip := -dir * (2.5 + flap * 2.0)
		draw_polyline(PackedVector2Array([p + side * 7.0 + tip, p, p - side * 7.0 + tip]), c, 1.8, true)

	func _airliner(p: Vector2, h: float, k: float, shadow: bool) -> void:
		draw_set_transform(p, h, Vector2(k, k))
		var body := Color(0, 0, 0, 0.22) if shadow else Color("#f4f2ec")
		var wing := Color(0, 0, 0, 0.22) if shadow else Color("#d9dde2")
		# Wings, tailplane, fuselage, engines, a stripe in danfo yellow.
		draw_colored_polygon(PackedVector2Array([Vector2(6, 0), Vector2(-8, -30), Vector2(-14, -30), Vector2(-6, 0), Vector2(-14, 30), Vector2(-8, 30)]), wing)
		draw_colored_polygon(PackedVector2Array([Vector2(-24, 0), Vector2(-31, -11), Vector2(-34, -11), Vector2(-30, 0), Vector2(-34, 11), Vector2(-31, 11)]), wing)
		draw_colored_polygon(PackedVector2Array([Vector2(30, 0), Vector2(26, -3.6), Vector2(-28, -3), Vector2(-34, 0), Vector2(-28, 3), Vector2(26, 3.6)]), body)
		if not shadow:
			draw_rect(Rect2(-6, -13.5, 7, 3.5), Color("#8c939b"))
			draw_rect(Rect2(-6, 10, 7, 3.5), Color("#8c939b"))
			draw_line(Vector2(24, 0), Vector2(-30, 0), TitleAerial.DANFO, 1.6)
			draw_circle(Vector2(27, 0), 1.4, Color("#2a3a48"))
		draw_set_transform(Vector2.ZERO)

	func _cessna(p: Vector2, h: float, shadow: bool) -> void:
		draw_set_transform(p, h)
		var c := Color(0, 0, 0, 0.2) if shadow else Color("#f1ece0")
		draw_rect(Rect2(-2, -15, 6, 30), c)
		draw_rect(Rect2(-12, -5, 4, 10), c)
		draw_colored_polygon(PackedVector2Array([Vector2(10, 0), Vector2(6, -2.5), Vector2(-13, -1.5), Vector2(-13, 1.5), Vector2(6, 2.5)]), c)
		if not shadow:
			draw_rect(Rect2(-2, -15, 6, 3), Color("#c8432f"))
			draw_rect(Rect2(-2, 12, 6, 3), Color("#c8432f"))
			draw_circle(Vector2(11, 0), 5.0, Color(0.2, 0.2, 0.2, 0.25)) # the propeller blur
		draw_set_transform(Vector2.ZERO)

	func _heli(p: Vector2, h: float, rot: float, shadow: bool) -> void:
		draw_set_transform(p, h)
		var c := Color(0, 0, 0, 0.2) if shadow else Color("#2f6f99")
		draw_circle(Vector2(2, 0), 6.0, c)
		draw_rect(Rect2(-16, -1.2, 14, 2.4), c)
		draw_rect(Rect2(-17, -4, 2, 8), c)
		if not shadow:
			draw_circle(Vector2(5, 0), 2.6, Color("#cfe4ee"))
		var blade := Color(0, 0, 0, 0.12) if shadow else Color(0.1, 0.1, 0.1, 0.55)
		for i in 2:
			var a := rot + i * PI / 2.0
			draw_line(Vector2(2, 0) - Vector2.from_angle(a) * 15.0, Vector2(2, 0) + Vector2.from_angle(a) * 15.0, blade, 1.6)
		draw_set_transform(Vector2.ZERO)
