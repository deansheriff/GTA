class_name Stage3D
extends Node3D
## The story's stagehands (D-021): actors spawned by missions (cast members, gunmen, fighters) with
## props such as the lion-head walking stick, rain and forced night for the prologue, the camera's
## story modes (low under the bridge, looking at someone), and the marker of the next mission.

var world # Street3D
var actors := {} # id -> Person3D
var night := false
var raining := false
var cam_override := "follow"
var cam_target := Vector3.ZERO
var _rain: CPUParticles3D
var _marker: MeshInstance3D
var _marker_label: Label3D
var _crowds := {} # id -> [Node3D] bobbing festival figures
var _sets := {} # id -> Node3D
var _t := 0.0


func setup(w) -> void:
	world = w
	_rain = CPUParticles3D.new()
	_rain.amount = 700
	_rain.lifetime = 0.9
	_rain.emitting = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(18, 0.5, 18)
	_rain.direction = Vector3(0.1, -1, 0)
	_rain.spread = 4.0
	_rain.initial_velocity_min = 22.0
	_rain.initial_velocity_max = 26.0
	_rain.gravity = Vector3(0, -9.8, 0)
	var drop := QuadMesh.new()
	drop.size = Vector2(0.025, 0.55)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = dm
	_rain.mesh = drop
	add_child(_rain)
	_marker = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.6
	cyl.height = 30.0
	_marker.mesh = cyl
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.92, 0.28, 0.2, 0.3)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker.material_override = mm
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)
	_marker_label = Label3D.new()
	_marker_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker_label.font_size = 64
	_marker_label.pixel_size = 0.02
	_marker_label.outline_size = 12
	_marker_label.modulate = Color("#f6d04d")
	_marker_label.no_depth_test = true
	_marker_label.visible = false
	add_child(_marker_label)


func step(delta: float) -> void:
	if raining and world.cam:
		_rain.global_position = world.cam.global_position + Vector3(0, 10, 0)
	_t += delta
	# Festival figures sway and drift (Eyo masquerades are never still).
	for id in _crowds:
		var list: Array = _crowds[id]
		for i in list.size():
			var n: Node3D = list[i]
			n.rotation.y += sin(_t * 0.7 + i) * delta * 0.6
			n.position.y = absf(sin(_t * 3.0 + i * 1.7)) * 0.08


## A festival crowd around a place: Eyo masquerades, Durbar horses ("free:horse"), or Mmanwu
## (the Eyo figure recoloured with `look`, our own model). Rigged figures play their idle.
func crowd(id: String, model: String, at: Vector3, count: int, radius: float, height: float, look: Dictionary = {}) -> void:
	clear_crowd(id)
	var list := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	for i in count:
		var m: Node3D = world.models.make(model.trim_prefix("free:"), "res://art3d/free/" if model.begins_with("free:") else Models3D.ART)
		if m == null:
			break
		Models3D.fit_height(m, height * rng.randf_range(0.93, 1.07))
		if not look.is_empty() and not model.begins_with("free:"):
			Models3D.restyle(m, look)
		var ap := Models3D.find_player(m)
		if ap:
			for a in ap.get_animation_list():
				if String(a).ends_with("Idle"):
					ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
					ap.play(a)
					ap.seek(rng.randf() * 2.0, true)
					break
		var h := Node3D.new()
		h.add_child(m)
		var ang := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		h.position = at + Vector3(cos(ang) * d, 0, sin(ang) * d)
		h.rotation.y = rng.randf() * TAU
		add_child(h)
		Models3D.far_cull(h, 90.0)
		Models3D.no_shadow(h)
		list.append(h)
	_crowds[id] = list


func clear_crowd(id: String) -> void:
	for n: Node in _crowds.get(id, []):
		n.queue_free()
	_crowds.erase(id)


## A one-off building or prop placed for a mission (the Seme border post, a Badagry church).
## "free:x" models come from the free folder; `size` is the footprint in metres.
func setpiece(id: String, model: String, at: Vector3, label: String, yaw: float, size := 9.0) -> void:
	if _sets.has(id):
		(_sets[id] as Node).queue_free()
	var root := Node3D.new()
	root.position = at
	root.rotation.y = deg_to_rad(yaw)
	add_child(root)
	if model == "gutter" or model == "overpass" or model == "lamp":
		_build_piece(root, model)
	var m: Node3D = world.models.make(model.trim_prefix("free:"), "res://art3d/free/" if model.begins_with("free:") else Models3D.ART) if model != "" and not model in ["gutter", "overpass", "lamp"] else null
	if m:
		var bb := Models3D.aabb(m)
		var k := size / maxf(bb.size.x, maxf(bb.size.z, 0.1))
		m.scale = Vector3.ONE * k
		m.position = Vector3(-bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)
		root.add_child(m)
	if label != "":
		var l := Label3D.new()
		l.text = label
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 56
		l.pixel_size = 0.012
		l.outline_size = 10
		l.position = Vector3(0, 7.0, 0)
		root.add_child(l)
	_sets[id] = root


func set_env(n: bool, r: bool) -> void:
	night = n
	raining = r
	_rain.emitting = r


## The next mission's start marker (null hides it).
func set_marker(pos: Variant, text := "") -> void:
	_marker.visible = pos != null
	_marker_label.visible = pos != null
	if pos != null:
		_marker.position = (pos as Vector3) + Vector3(0, 15, 0)
		_marker_label.position = (pos as Vector3) + Vector3(0, 4.5, 0)
		_marker_label.text = text


func spawn(id: String, who: String, pos: Vector3, anim := "idle", face := "", prop := "", model := "") -> Person3D:
	despawn(id)
	var info: Dictionary = Story.who(who)
	var key := model if model != "" else String(info.get("model", who))
	var own := false
	var p := Person3D.new()
	add_child(p)
	var cell := Vector2i(int(pos.x / Terrain3D.CELL_M), int(pos.z / Terrain3D.CELL_M))
	var ok := false
	for k in [key, "walker", "agbero"]:
		if world.models.has_person(k) and p.setup(world.models, k, world, cell, hash(id)):
			ok = true
			break
	if not ok:
		p.free()
		return null
	if model == "" and not own and not Models3D.is_free(key):
		Models3D.restyle(p, info.get("look", {})) # Meshy stand-ins get their own colours
	var gy: float = world.ground_at(pos, pos.y + 0.1)
	p.position = Vector3(pos.x, pos.y if is_nan(gy) else gy, pos.z)
	p.state = Person3D.State.PAUSE
	p.pause_left = 1e9
	Models3D.far_cull(p, 120.0)
	Models3D.play(p.ap, anim, "idle")
	if face == "player":
		var to: Vector3 = world.player.position - p.position
		p.rotation.y = atan2(to.x, to.z)
	elif actors.has(face):
		var to: Vector3 = (actors[face] as Node3D).position - p.position
		p.rotation.y = atan2(to.x, to.z)
	if prop != "":
		var pr: Node3D = world.models.make(prop)
		if pr:
			Models3D.fit_height(pr, 1.05)
			var h := Node3D.new()
			h.add_child(pr)
			h.position = Vector3(0.38, 0, 0.25) # leaning on it, by the right hand
			p.add_child(h)
	p.set_meta("who", who)
	actors[id] = p
	return p


## Pieces built in code for the story: an open concrete gutter, an overpass on pillars, a lamp.
func _build_piece(root: Node3D, kind: String) -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.55, 0.53, 0.5)
	concrete.roughness = 0.9
	match kind:
		"gutter":
			# An open drain: two kerbs of concrete with black water between them.
			for side in [-0.75, 0.75]:
				_box(root, Vector3(0.3, 0.45, 16.0), Vector3(side, 0.22, 0), concrete)
			var water := StandardMaterial3D.new()
			water.albedo_color = Color(0.05, 0.06, 0.06)
			water.roughness = 0.05
			water.metallic = 0.3
			_box(root, Vector3(1.2, 0.04, 16.0), Vector3(0, 0.03, 0), water)
		"overpass":
			# Oshodi's flyover: a deck on pillars, the city's roof for the people beneath.
			_box(root, Vector3(10.0, 1.1, 44.0), Vector3(0, 6.5, 0), concrete)
			for z in [-18.0, -6.0, 6.0, 18.0]:
				_box(root, Vector3(1.2, 6.0, 1.2), Vector3(0, 3.0, z), concrete)
			var rail := StandardMaterial3D.new()
			rail.albedo_color = Color(0.85, 0.75, 0.3)
			for side in [-5.0, 5.0]:
				_box(root, Vector3(0.25, 0.8, 44.0), Vector3(side, 7.45, 0), rail)
		"lamp":
			var l := OmniLight3D.new()
			l.light_color = Color("#ffb45e")
			l.light_energy = 2.6
			l.omni_range = 14.0
			l.position = Vector3(0, 3.6, 0)
			root.add_child(l)
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.18
			sm.height = 0.36
			bulb.mesh = sm
			var bm := StandardMaterial3D.new()
			bm.albedo_color = Color(1.0, 0.85, 0.6)
			bm.emission_enabled = true
			bm.emission = Color("#ffb45e")
			bm.emission_energy_multiplier = 5.0
			bulb.material_override = bm
			bulb.position = Vector3(0, 3.6, 0)
			root.add_child(bulb)
			_box(root, Vector3(0.08, 3.6, 0.08), Vector3(0, 1.8, 0), concrete)


func _box(root: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	root.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = at
	if size.y > 1.0:
		root.add_child(body) # pillars and the deck are solid; kerbs and water you can step over
	else:
		body.free()


func despawn(id: String) -> void:
	if actors.has(id):
		var n: Variant = actors[id] # may already be freed (fighters are freed by Combat3D)
		if is_instance_valid(n):
			(n as Node).queue_free()
		actors.erase(id)


## Remove the mission's people and crowds; set pieces too when `all` (the mission is over).
func clear(all := true) -> void:
	for id in actors.keys():
		despawn(id)
	for id in _crowds.keys():
		clear_crowd(id)
	if all:
		for id in _sets.keys():
			(_sets[id] as Node).queue_free()
		_sets.clear()
	cam_override = "follow"
