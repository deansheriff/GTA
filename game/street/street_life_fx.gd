class_name StreetLifeFx
extends Node
## The street, more alive (M13):
##  - animals: goats and dogs wander, hens peck (with chicks), cats sit; they scatter from
##    vehicles, and a hen squawks at a speeding bus,
##  - clotheslines by the houses, suya grills smoking at evening, steam from bukkas and canteens,
##  - the ground: dashed lane lines, zebra crossings at junctions, potholes that fill into puddles
##    in the rain (and stay wet for a while after), and litter blowing about.

const ANIMALS := [["props/goat-white.png", "goat"], ["props/goat-black.png", "goat"], ["props/hen.png", "hen"], ["props/hen-chicks.png", "hen"], ["props/dog.png", "dog"], ["props/cat.png", "cat"]]
const MAX_ANIMALS := 8

var host: StreetHost
var main: Node2D
var animals: Array = []
var _spawn_t := 0.0
var _decals: _Ground
var _grills: Array = [] # {node, pos}
var _steam: Array = [] # door positions of food places
var _puff_t := 0.0
var wet := 0.0 # puddles linger after rain
var _rng := RandomNumberGenerator.new()


func setup(h: StreetHost) -> void:
	host = h
	main = h.main
	_rng.seed = 4242
	_decals = _Ground.new()
	_decals.fx = self
	main.add_child(_decals)
	_decals.build(main.map)
	_place_decor(main.map)


# ---------- decor ----------

func _place_decor(m: MapData) -> void:
	var line_tex := Art.tex("props/clothesline.png")
	var grill_tex := Art.tex("props/suya-grill.png")
	for b in m.buildings:
		var fp: Rect2 = b.footprint()
		if line_tex and b.seed % 7 == 0:
			var p := Vector2(fp.end.x + 70.0, fp.end.y - 20.0)
			if not m.is_blocked(p) and not m.is_roadlike(m.surface_at(p)):
				_add_sprite(line_tex, p, 0.85)
		if b.art in ["canteen", "bukka"] or b.landmark == "mallam-suya":
			_steam.append(Vector2(fp.get_center().x, fp.end.y + 10.0))
	for p in m.props:
		if grill_tex and p.kind == "umbrella" and p.seed % 4 == 0:
			var at: Vector2 = p.pos + Vector2(46, 14)
			if not m.is_blocked(at):
				_grills.append({ "node": _add_sprite(grill_tex, at, 0.75), "pos": at })


func _add_sprite(tex: Texture2D, at: Vector2, k: float) -> Node2D:
	var holder := Node2D.new()
	holder.position = at
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2(k, k)
	s.position = Vector2(0, -tex.get_height() * k * 0.5)
	holder.add_child(s)
	holder.material = main.painted_mat
	main.streamer.add_child(holder)
	return holder


# ---------- per frame ----------

func tick(dt: float) -> void:
	var focus: Vector2 = main.danfo.position if main.mode == "driving" else main.player.position
	# Rain fills the potholes; they dry over about an hour of game time.
	if host.weather.rain > 0.3:
		wet = minf(1.0, wet + dt * 0.2)
	else:
		wet = maxf(0.0, wet - dt / 240.0)
	_decals.queue_redraw()
	# Animals.
	_spawn_t -= dt
	if _spawn_t <= 0.0:
		_spawn_t = 1.5
		animals = animals.filter(func(a: _Animal) -> bool:
			if a.position.distance_to(focus) > 1700.0:
				a.queue_free()
				return false
			return is_instance_valid(a))
		if animals.size() < MAX_ANIMALS and not main.story.interior.active:
			_spawn_animal(focus)
	var vehicles: Array = [main.danfo]
	for v in main.traffic.vehicles:
		vehicles.append(v["node"])
	for a: _Animal in animals:
		a.step(dt, main.map, vehicles, host.fx)
	# Smoke from the suya grills in the evening, steam from the food places, near the camera only.
	_puff_t -= dt
	if _puff_t <= 0.0:
		_puff_t = 0.35
		var view: Rect2 = main._view_rect().grow(120.0)
		var evening := Clock.hour() >= 17 or Clock.hour() < 1
		for g: Dictionary in _grills:
			(g["node"] as Node2D).visible = evening
			if evening and view.has_point(g["pos"]):
				host.fx.smoke(g["pos"] + Vector2(randf_range(-10, 10), -36), 0.15)
		for s: Vector2 in _steam:
			if view.has_point(s) and randf() < 0.5:
				host.fx.smoke(s + Vector2(randf_range(-30, 30), -40), 0.0)


func _spawn_animal(focus: Vector2) -> void:
	for attempt in 8:
		var p := focus + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(600.0, 1200.0)
		var s: int = main.map.surface_at(p)
		if main.map.is_blocked(p) or main.map.is_water(s) or main.map.is_roadlike(s):
			continue
		var spec: Array = ANIMALS[_rng.randi() % ANIMALS.size()]
		var tex := Art.tex(spec[0])
		if tex == null:
			return
		var a := _Animal.new()
		a.kind = spec[1]
		a.tex = tex
		a.position = p
		a.home = p
		a.material = main.painted_mat
		main.streamer.add_child(a)
		animals.append(a)
		return


## A goat, hen, dog or cat with a simple life: wander near home, peck, sit, flee from vehicles.
class _Animal extends Node2D:
	var kind := "goat"
	var tex: Texture2D
	var home := Vector2.ZERO
	var target := Vector2.INF
	var idle := 0.0
	var flee := 0.0
	var flip := false
	var _t := 0.0
	var _squawk_cd := 0.0

	func _speed() -> float:
		return { "goat": 34.0, "hen": 22.0, "dog": 62.0, "cat": 0.0 }.get(kind, 30.0)

	func step(dt: float, m: MapData, vehicles: Array, fx: StreetFx) -> void:
		_t += dt
		_squawk_cd -= dt
		# Vehicles: get out of the way (and complain).
		for v: Node2D in vehicles:
			var d := position.distance_to(v.position)
			if d < 130.0 and absf(float(v.speed)) > 60.0 and kind != "cat":
				var away := (position - v.position).normalized()
				target = position + away * 160.0
				flee = 1.2
				if _squawk_cd <= 0.0 and kind in ["hen", "goat"]:
					_squawk_cd = 4.0
					fx.pop("BAWK!" if kind == "hen" else "MEEEH!", position + Vector2(0, -50), Color("#f1e6c8"), 22, 0.8)
				break
		flee = maxf(0.0, flee - dt)
		var speed := _speed() * (3.0 if flee > 0.0 else 1.0)
		if target == Vector2.INF:
			idle -= dt
			if idle <= 0.0 and speed > 0.0:
				var t := home + Vector2(randf_range(-160, 160), randf_range(-100, 100))
				if not m.is_blocked(t) and not m.is_water(m.surface_at(t)):
					target = t
				idle = randf_range(1.5, 4.0)
		elif speed > 0.0:
			var to := target - position
			if to.length() < 4.0:
				target = Vector2.INF
			else:
				var nxt := position + to.normalized() * minf(speed * dt, to.length())
				if m.is_blocked(nxt):
					target = Vector2.INF
				else:
					if absf(to.x) > 1.0:
						flip = to.x < 0.0
					position = nxt
		queue_redraw()

	func _draw() -> void:
		if tex == null:
			return
		var moving := target != Vector2.INF
		var bob := -absf(sin(_t * 9.0)) * 2.0 if moving else 0.0
		if kind == "hen" and not moving:
			bob = -absf(sin(_t * 3.0)) * 1.5 # pecking
		var h := float(tex.get_height())
		var w := float(tex.get_width())
		var k := { "goat": 0.55, "hen": 0.5, "dog": 0.5, "cat": 0.55 }.get(kind, 0.5) as float
		Ink.shadow(self, Vector2.ZERO, Vector2(w * k * 0.35, 5.0), 0.25)
		draw_set_transform(Vector2(0, bob), 0.0, Vector2(-k if flip else k, k))
		draw_texture(tex, Vector2(-w * 0.5, -h + 4.0))
		draw_set_transform(Vector2.ZERO)


## Ground detail, drawn just above the terrain: lane lines, zebra crossings, potholes/puddles,
## litter. Only what's on screen is drawn.
class _Ground extends Node2D:
	var fx: StreetLifeFx
	var segs: Array = [] # [a, b] road centre lines
	var zebras: Array = [] # [pos, dir]
	var holes: Array = [] # [pos, radius]
	var litter: Array = [] # [pos, colour, seed]

	func _ready() -> void:
		z_index = -95

	func build(m: MapData) -> void:
		var r := RandomNumberGenerator.new()
		r.seed = 777
		var seen := {}
		for a in m.road_graph:
			var pa: Vector2 = m.road_nodes[a]
			var deg: int = (m.road_graph[a] as Array).size()
			for b: String in m.road_graph[a]:
				var key: String = (a + "|" + b) if a < b else (b + "|" + a)
				if seen.has(key):
					continue
				seen[key] = true
				var pb: Vector2 = m.road_nodes[b]
				segs.append([pa, pb])
				var dir := (pb - pa).normalized()
				var n := int(pa.distance_to(pb) / 520.0)
				for i in n:
					var at := pa.lerp(pb, r.randf_range(0.15, 0.85)) + Vector2(-dir.y, dir.x) * r.randf_range(-28.0, 28.0)
					if m.surface_at(at) == MapData.S.ROAD:
						holes.append([at, r.randf_range(9.0, 18.0)])
			if deg > 2:
				for b: String in m.road_graph[a]:
					var dir: Vector2 = ((m.road_nodes[b] as Vector2) - pa).normalized()
					zebras.append([pa + dir * 120.0, dir])
		for p in m.props:
			if p.kind in ["umbrella", "kiosk", "orange-tray"] and r.randf() < 0.6:
				for k in 3:
					litter.append([p.pos + Vector2(r.randf_range(-70, 70), r.randf_range(10, 60)), [Color("#e8e2d0"), Color("#2f6f99"), Color("#c8432f"), Color("#3a3a3a")][k], r.randi()])

	func _draw() -> void:
		var view: Rect2 = fx.main._view_rect().grow(80.0)
		var t := Time.get_ticks_msec() / 1000.0
		# Lane lines: dashed, a little worn.
		for s: Array in segs:
			var a: Vector2 = s[0]
			var b: Vector2 = s[1]
			if not view.intersects(Rect2(a, Vector2.ZERO).expand(b)):
				continue
			var len := a.distance_to(b)
			var dir := (b - a) / len
			var d := 70.0
			while d < len - 70.0:
				var p0 := a + dir * d
				if view.has_point(p0):
					draw_line(p0, p0 + dir * 26.0, Color(0.92, 0.88, 0.72, 0.45), 3.0)
				d += 50.0
		# Zebra crossings near busy junctions.
		for z: Array in zebras:
			var c: Vector2 = z[0]
			if not view.has_point(c):
				continue
			var dir: Vector2 = z[1]
			var side := Vector2(-dir.y, dir.x)
			for i in range(-3, 4):
				var p := c + side * i * 14.0
				draw_line(p - dir * 14.0, p + dir * 14.0, Color(0.95, 0.93, 0.85, 0.5), 7.0)
		# Potholes, and puddles in them when it's wet.
		for h: Array in holes:
			var p: Vector2 = h[0]
			if not view.has_point(p):
				continue
			var rad: float = h[1]
			draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
			draw_circle(Vector2.ZERO, rad + 2.0, Color(0.2, 0.17, 0.14, 0.5))
			draw_circle(Vector2.ZERO, rad, Color(0.12, 0.1, 0.09, 0.75))
			if fx.wet > 0.05:
				draw_circle(Vector2.ZERO, rad * (0.9 + fx.wet * 0.6), Color(0.42, 0.52, 0.58, 0.55 * fx.wet))
				draw_arc(Vector2(-rad * 0.3, -rad * 0.3), rad * 0.5, PI, PI * 1.6, 8, Color(1, 1, 1, 0.35 * fx.wet), 1.5)
			draw_set_transform(Vector2.ZERO)
		# Litter: wrappers and bags, stirring in the breeze.
		for l: Array in litter:
			var p: Vector2 = l[0]
			if not view.has_point(p):
				continue
			var sd: int = l[2]
			var sway := Vector2(sin(t * 0.8 + sd) * 3.0, cos(t * 0.6 + sd) * 1.5)
			draw_set_transform(p + sway, float(sd % 6), Vector2.ONE)
			draw_rect(Rect2(-4, -2.5, 8, 5), l[1])
			draw_set_transform(Vector2.ZERO)
