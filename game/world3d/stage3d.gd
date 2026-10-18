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


func step(_delta: float) -> void:
	if raining and world.cam:
		_rain.global_position = world.cam.global_position + Vector3(0, 10, 0)


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
	var p := Person3D.new()
	add_child(p)
	var cell := Vector2i(int(pos.x / Terrain3D.CELL_M), int(pos.z / Terrain3D.CELL_M))
	var ok := false
	for k in [key, "walker", "agbero"]:
		if world.models.has(k, Models3D.CHARS) and p.setup(world.models, k, world, cell, hash(id)):
			ok = true
			break
	if not ok:
		p.free()
		return null
	p.position = Vector3(pos.x, world.terrain.height_at(pos), pos.z)
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
	actors[id] = p
	return p


func despawn(id: String) -> void:
	if actors.has(id):
		var n: Variant = actors[id] # may already be freed (fighters are freed by Combat3D)
		if is_instance_valid(n):
			(n as Node).queue_free()
		actors.erase(id)


func clear() -> void:
	for id in actors.keys():
		despawn(id)
	cam_override = "follow"
