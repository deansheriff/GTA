class_name Weather
extends Node
## Rain and floods (M9 #5). Each day brings zero to two rain spells. While it rains:
##  - streaks, a darker sky and thunder (when Settings "weather" is on), and rain on the roof,
##  - low roads near the lagoon and sea flood: the bus crawls through, splashing,
##  - okadas vanish from the road, traffic slows (the jams get worse), and fares go up 50%,
##  - people on foot run for cover.
## Floods and slowdowns wait while a story mission is on; the rain itself can fall any time.

static var raining_now := false

var host: StreetHost
var main: Node2D
var rain := 0.0 # 0–1 intensity
var flood := 0.0 # 0–1 water level on the low roads
var spots: Array = [] # flood-prone road spots (world px)
var _spells: Array = [] # today's [start, end] in minutes of the day
var _day := -1
var _overlay: _RainOverlay
var _puddles: _Puddles
var _thunder_t := 20.0
var _splash_t := 0.0
var _flood_day := -1
var _was_raining := false


func setup(h: StreetHost) -> void:
	host = h
	main = h.main
	_find_spots()
	var layer := CanvasLayer.new()
	layer.layer = 5
	main.add_child(layer)
	_overlay = _RainOverlay.new()
	layer.add_child(_overlay)
	_puddles = _Puddles.new()
	_puddles.owner_w = self
	main.add_child(_puddles)


## Low roads near water flood first.
func _find_spots() -> void:
	var m: MapData = main.map
	for id in m.road_nodes:
		var p: Vector2 = m.road_nodes[id]
		for nb: String in m.road_graph.get(id, []):
			var mid: Vector2 = (p + (m.road_nodes[nb] as Vector2)) * 0.5
			if m.surface_at(mid) == MapData.S.ROAD and _near_water(mid, 4) and not spots.any(func(s: Vector2) -> bool: return s.distance_to(mid) < 500.0):
				spots.append(mid)
	spots = spots.slice(0, 14)


func _near_water(p: Vector2, cells: int) -> bool:
	var m: MapData = main.map
	for dy in range(-cells, cells + 1):
		for dx in range(-cells, cells + 1):
			var q := p + Vector2(dx, dy) * MapData.CELL
			var c := m.cell_of(q)
			if m.in_bounds(c) and m.is_water(m.surface[c.y * m.cols + c.x]):
				return true
	return false


func _plan_day() -> void:
	_day = Clock.day()
	var r := RandomNumberGenerator.new()
	r.seed = _day * 4241 + 7
	_spells.clear()
	for i in r.randi_range(0, 2):
		var start := r.randi_range(6 * 60, 21 * 60)
		_spells.append([start, start + r.randi_range(30, 90)])


func is_spell_now() -> bool:
	var m := Clock.minutes % 1440
	for s: Array in _spells:
		if m >= int(s[0]) and m < int(s[1]):
			return true
	return false


## Dev/demo: start a rain spell now for `minutes`.
func force_rain(minutes := 60) -> void:
	var m := Clock.minutes % 1440
	_spells.append([m, m + minutes])


func tick(dt: float) -> void:
	if Clock.day() != _day:
		_plan_day()
	var want := 1.0 if is_spell_now() and not main.story.auto else 0.0
	rain = move_toward(rain, want, dt / 8.0)
	raining_now = rain > 0.5
	var calm := host.story_busy()
	# Floods rise while it pours and drain slowly afterwards.
	flood = clampf(flood + (dt / 40.0 if rain > 0.7 else -dt / 90.0), 0.0, 1.0)
	Street.fare_k = 1.5 if raining_now else 1.0
	var traffic: Traffic = main.traffic
	traffic.no_okada = rain > 0.3
	traffic.speed_k = 1.0 if calm else lerpf(1.0, 0.7, rain)
	if raining_now and not _was_raining:
		main.hud.toast("Rain don start! Fares up, okadas gone, roads go flood.")
		host.reactions.rain_started()
	_was_raining = raining_now
	# The bus in a flood.
	if not calm and flood > 0.3 and main.mode == "driving":
		var d: Node2D = main.danfo
		for s: Vector2 in spots:
			if d.position.distance_to(s) < 170.0 * flood:
				d.limit = minf(d.limit, 110.0)
				_splash_t -= dt
				if _splash_t <= 0.0 and absf(d.speed) > 30.0:
					_splash_t = 0.5
					host.fx.splash(d.position + Vector2(randf_range(-40, 40), 10))
					Sound.sfx("splash", randf_range(0.9, 1.1))
				if _flood_day != Clock.day():
					_flood_day = Clock.day()
					Street.count("floods")
					main.hud.toast("Flood! Drive slowly or the engine go drink water.")
				break
	# Thunder.
	var show: bool = Settings.get_value("weather", true)
	if rain > 0.8:
		_thunder_t -= dt
		if _thunder_t <= 0.0:
			_thunder_t = randf_range(14.0, 35.0)
			if show:
				_overlay.flash()
			Sound.sfx("thunder", randf_range(0.85, 1.1))
	_overlay.rain = rain if show else 0.0
	_overlay.lite = Settings.get_value("effects", "low") != "full"
	_puddles.level = flood
	if flood > 0.0:
		_puddles.queue_redraw()


## Screen-space rain streaks, a darker sky and lightning flashes.
class _RainOverlay extends Control:
	var rain := 0.0
	var lite := true
	var _flash := 0.0
	var _drops: Array = []

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 220:
			_drops.append(Vector3(randf(), randf(), randf_range(0.6, 1.0)))

	func flash() -> void:
		_flash = 1.0

	func _process(delta: float) -> void:
		_flash = maxf(0.0, _flash - delta * 3.0)
		visible = rain > 0.01 or _flash > 0.0
		if not visible:
			return
		for i in _drops.size():
			var d: Vector3 = _drops[i]
			d.y += delta * 1.6 * d.z
			d.x -= delta * 0.25 * d.z
			if d.y > 1.0:
				d.y -= 1.0
				d.x = randf()
			if d.x < 0.0:
				d.x += 1.0
			_drops[i] = d
		queue_redraw()

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.12, 0.16, 0.22, 0.28 * rain))
		var n := int(_drops.size() * rain * (0.5 if lite else 1.0))
		for i in n:
			var d: Vector3 = _drops[i]
			var p := Vector2(d.x * s.x, d.y * s.y)
			draw_line(p, p + Vector2(-6, 22) * d.z, Color(0.8, 0.88, 0.95, 0.45 * d.z), 1.5)
		if _flash > 0.0:
			draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.55 * _flash))


## Flood water on the low roads (world space, under the vehicles).
class _Puddles extends Node2D:
	var owner_w: Weather
	var level := 0.0

	func _ready() -> void:
		z_index = -90 # on the road, under everything that stands on it

	func _draw() -> void:
		if level <= 0.02:
			return
		var t := Time.get_ticks_msec() / 1000.0
		for s: Vector2 in owner_w.spots:
			var r := 170.0 * level
			draw_set_transform(s, 0.0, Vector2(1.0, 0.62))
			draw_circle(Vector2.ZERO, r, Color(0.36, 0.33, 0.24, 0.55 * level))
			draw_circle(Vector2.ZERO, r * 0.75, Color(0.42, 0.5, 0.52, 0.35 * level))
			for k in 2:
				var rr := fmod(t * 18.0 + k * 40.0, r)
				draw_arc(Vector2.ZERO, rr, 0.0, TAU, 32, Color(0.85, 0.9, 0.95, 0.25 * (1.0 - rr / r)), 1.5)
			draw_set_transform(Vector2.ZERO)
