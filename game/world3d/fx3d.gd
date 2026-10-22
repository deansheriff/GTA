class_name Fx3D
extends Node3D
## Effects (D-028): explosions with fire and smoke that keep burning (the kpo-fire refinery), hit
## flashes on whoever gets hit, floating damage numbers, dust puffs, and the screen's hit-stop on a
## heavy blow. Cheap CPU particles only, so low-end phones cope.

var world # Street3D
var _fires: Array = [] # {node, life}
var _pops: Array = [] # {label, t}
var _flash: Array = [] # {meshes: [GeometryInstance3D], t}
var _hitstop := 0.0
var _flash_mat: StandardMaterial3D


func setup(w) -> void:
	world = w
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1.0, 0.25, 0.2, 0.55)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func step(delta: float) -> void:
	for f: Dictionary in _fires.duplicate():
		f["life"] = float(f["life"]) - delta
		if float(f["life"]) <= 0.0:
			if is_instance_valid(f["node"]):
				(f["node"] as Node).queue_free()
			_fires.erase(f)
	for p: Dictionary in _pops.duplicate():
		p["t"] = float(p["t"]) + delta
		var l: Label3D = p["label"]
		if not is_instance_valid(l):
			_pops.erase(p)
			continue
		l.position.y += delta * 1.2
		l.modulate.a = clampf(1.2 - float(p["t"]), 0.0, 1.0)
		if float(p["t"]) > 1.1:
			l.queue_free()
			_pops.erase(p)
	for h: Dictionary in _flash.duplicate():
		h["t"] = float(h["t"]) - delta
		if float(h["t"]) <= 0.0:
			for g in h["meshes"]:
				if is_instance_valid(g):
					(g as GeometryInstance3D).material_overlay = null
			_flash.erase(h)
	if _hitstop > 0.0:
		_hitstop -= delta / maxf(Engine.time_scale, 0.05)
		if _hitstop <= 0.0:
			Engine.time_scale = 1.0


## A blast: flash of light, fireball, smoke, a shake and a bang. size 1 = a car, 3 = a refinery.
func explosion(at: Vector3, size := 1.0, burn := 0.0) -> void:
	Sound.sfx("crash", 0.6)
	Sound.sfx("thunder", 1.3)
	world.shake(0.4 + size * 0.25)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 6.0
	light.omni_range = 12.0 * size
	add_child(light)
	light.global_position = at + Vector3(0, 2, 0)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.9)
	tw.tween_callback(light.queue_free)
	var ball := _particles(at, Color(1.0, 0.55, 0.15), 60, 0.9, 6.0 * size, size * 1.6, true)
	ball.one_shot = true
	ball.explosiveness = 0.95
	_fires.append({ "node": ball, "life": 2.0 })
	var smoke := _particles(at + Vector3(0, 1, 0), Color(0.12, 0.11, 0.1, 0.6), 50, 3.0, 2.5, size * 2.2, false)
	smoke.one_shot = true
	smoke.explosiveness = 0.6
	_fires.append({ "node": smoke, "life": 4.0 })
	if burn > 0.0:
		fire(at, size, burn)
	# Anyone close is knocked down or hurt.
	var c = world.combat
	if c and c.active:
		for e: Dictionary in c.enemies:
			if int(e["hp"]) > 0 and is_instance_valid(e["node"]) and (e["node"] as Node3D).global_position.distance_to(at) < 5.0 * size:
				c.hurt_enemy(e, 4)
	if world.player.global_position.distance_to(at) < 3.0 * size and world.ride == null:
		c.hurt_player(2, at)


## A fire that keeps burning for `secs` (refinery tanks, a burning stilt house).
func fire(at: Vector3, size := 1.0, secs := 30.0) -> void:
	var f := _particles(at, Color(1.0, 0.5, 0.12), int(24 * size), 0.8, 3.5, size, true)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.4
	light.omni_range = 8.0 * size
	light.position = Vector3(0, 1.5, 0)
	f.add_child(light)
	var smoke := _particles(Vector3.ZERO, Color(0.1, 0.09, 0.08, 0.5), int(16 * size), 3.5, 2.0, size * 1.6, false)
	smoke.position = Vector3(0, 2.0, 0)
	smoke.reparent(f, false)
	_fires.append({ "node": f, "life": secs })


func dust(at: Vector3) -> void:
	var d := _particles(at + Vector3(0, 0.6, 0), Color(0.75, 0.68, 0.55, 0.5), 10, 0.5, 1.6, 0.35, false)
	d.one_shot = true
	d.explosiveness = 0.9
	_fires.append({ "node": d, "life": 0.8 })


## A red flash over a model for a moment (the hit landed).
func flash(n: Node, secs := 0.12) -> void:
	if n == null or not is_instance_valid(n):
		return
	# Only the body's meshes: not its shadow blob, labels or particles.
	var meshes := n.find_children("*", "MeshInstance3D", true, false).filter(func(m: Node) -> bool: return m.name != "Blob" and (m as MeshInstance3D).mesh != null)
	for g in meshes:
		(g as GeometryInstance3D).material_overlay = _flash_mat
	_flash.append({ "meshes": meshes, "t": secs })


## A number that floats up from where the hit landed.
func pop(at: Vector3, text: String, col := Color("#ffd24d")) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 48
	l.pixel_size = 0.0055
	l.outline_size = 8
	l.modulate = col
	add_child(l)
	l.global_position = at + Vector3(randf_range(-0.2, 0.2), 1.9, randf_range(-0.2, 0.2))
	_pops.append({ "label": l, "t": 0.0 })


## A heavy blow freezes the action for a split second (off with Reduced motion).
func hitstop(secs := 0.06) -> void:
	if bool(Settings.get_value("reduced_motion", false)) or bool(Settings.get_pref("motion_off", false)) or "--shots" in str(OS.get_cmdline_user_args()):
		return
	Engine.time_scale = 0.08
	_hitstop = secs


func _particles(at: Vector3, col: Color, n: int, life: float, speed: float, scale: float, glow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(4, n)
	p.lifetime = life
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0 if glow else 20.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, 1.5 if not glow else -1.0, 0)
	p.scale_amount_min = scale * 0.6
	p.scale_amount_max = scale * 1.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6 * scale
	var q := SphereMesh.new()
	q.radius = 0.5
	q.height = 1.0
	q.radial_segments = 6
	q.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 3.0
	q.material = m
	p.mesh = q
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	p.color = col
	add_child(p)
	p.global_position = at
	p.emitting = true
	return p
