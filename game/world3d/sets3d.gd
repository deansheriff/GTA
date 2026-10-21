class_name Sets3D
extends Node3D
## The story's built sets (D-028): interiors and special places that aren't on the city map, built
## from boxes and the models we have, off the west edge of the map (over open sea, so nothing of
## the city shows through) and torn down when Dayo leaves:
##   police_cell  Yaba station: the packed cell, the corridor, the compound and its gate (M7)
##   owambe       the senator's daughter's wedding under a canopy, with a back room (M9)
##   stilt_house  a Makoko house on stilts: captives and red calabashes (M10)
##   home         Mama Àgbà's face-me-I-face-you room in Mushin, the iron box (M20)
##   safehouse    Uncle Obi's Festac safe house and its yard (M18)
##   cellar       the Anambra mansion's cellar where Kemi is held (M23)
##   gala         the governor-elect's Banana Island gala hall (M25)
##   yacht        Obinna's yacht deck on the dark lagoon, for the last fight (M26)
##   rooftops     a run of rooftops with gaps to jump, for the foot chases (M8, M19)
## Plus `olumo`, the climb up Olumo Rock, built on the Abeokuta map itself (M11).
## Floors are platforms (World.ground_at), walls are solid, and named anchors ("set:boy") tell a
## mission's steps where to put people.

const ORIGIN := Vector3(-320.0, 0.0, 140.0)

var world # Street3D
var active := "" # the set Dayo is in ("" = the open map)
var platforms: Array = [] # {rect: Rect2, y}
var anchors := {} # name -> Vector3 (world)
var course: Array[Vector3] = [] # rooftops: the runner's path, roof by roof
var _root: Node3D
var _return := Vector3.ZERO
var _mats := {}
var _disabled: Array[CollisionObject3D] = []


func setup(w) -> void:
	world = w


func step(_delta: float) -> void:
	pass


## Build a set and put Dayo in it (at its "start" anchor). Remembers where he was in the city.
func enter(kind: String) -> void:
	if active == "":
		_return = world.player.position
	_clear()
	active = kind
	_root = Node3D.new()
	_root.position = ORIGIN if kind != "olumo" else Vector3.ZERO
	add_child(_root)
	match kind:
		"police_cell": _police_station()
		"owambe": _owambe()
		"stilt_house": _stilt_house()
		"home": _home()
		"safehouse": _safehouse()
		"cellar": _cellar()
		"gala": _gala()
		"yacht": _yacht()
		"rooftops": _rooftops(9)
		"olumo": _olumo()
		_: push_warning("unknown set: " + kind)
	if anchors.has("start"):
		world.force_exit()
		world.player.position = anchors["start"]
		world.player.reset_physics_interpolation()


## Back to the city where Dayo was (or to `to` if given).
func leave(to: Variant = null) -> void:
	_clear()
	active = ""
	world.player.position = to if to != null else _return
	world.player.position.y = world.terrain.height_at(world.player.position)
	world.player.reset_physics_interpolation()


func anchor(name: String) -> Vector3:
	return anchors.get(name, world.player.position)


func _clear() -> void:
	if _root:
		_root.queue_free()
		_root = null
	platforms.clear()
	anchors.clear()
	course.clear()
	for b in _disabled:
		if is_instance_valid(b):
			b.collision_layer = 1
	_disabled.clear()


# ---------- building blocks (local coordinates) ----------

func _mat(name: String, col: Color, rough := 0.9, metal := 0.0) -> BaseMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	_mats[name] = m
	return m


## A textured surface from the Downtown City MegaKit set (CC0): concrete, marble, brick, metal,
## dirt; tinted (paint over plaster) and tiled every `tile` metres. Falls back to a flat colour.
const TEX := {
	"concrete": ["T_Concrete_BaseColor.png", "T_Concrete_Normal.png", "T_Concrete_ORM.png"],
	"marble": ["T_MarbleFloor_BaseColor.png", "T_MarbleFloor_Normal.png", "T_MarbleFloor_ORM.png"],
	"brick": ["T_RedBrick_BaseColor.png", "T_RedBrick_Normal.png", "T_RedBrick_ORM.png"],
	"metal": ["T_MetalConcrete_BaseColor.png", "T_MetalConcrete_Normal.png", "T_MetalConcrete_ORM.png"],
	"dirt": ["T_Dirt_BaseColor.png", "T_Dirt_Normal.png", "T_Dirt_ORM.png"],
}


func _tmat(name: String, kind: String, tint: Color, tile := 3.0) -> BaseMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var t: Array = TEX[kind]
	var m: BaseMaterial3D = Terrain3D.pbr_mat(t[0], t[1], t[2], tile)
	if m == null:
		return _mat(name, tint)
	m.albedo_color = tint
	_mats[name] = m
	return m


func _box(size: Vector3, at: Vector3, mat: Material, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	_root.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		body.position = at
		_root.add_child(body)
	return mi


## A floor you can walk on: a slab whose top is at height y.
func _floor(rect: Rect2, y: float, mat: Material) -> void:
	_box(Vector3(rect.size.x, 0.2, rect.size.y), Vector3(rect.get_center().x, y - 0.1, rect.get_center().y), mat, false)
	var o := _root.position
	platforms.append({ "rect": Rect2(rect.position + Vector2(o.x, o.z), rect.size), "y": y + o.y })


## A wall from a to b (local x, z), with an optional doorway gap in the middle.
func _wall(a: Vector2, b: Vector2, h: float, mat: Material, door := 0.0, y := 0.0) -> void:
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(len, 0.01)
	var yaw := atan2(-dir.y, dir.x)
	var parts: Array = [[0.0, len]] if door <= 0.0 else [[0.0, (len - door) * 0.5], [(len + door) * 0.5, len]]
	for p: Array in parts:
		var l: float = p[1] - p[0]
		if l <= 0.05:
			continue
		var mid := a + dir * (float(p[0]) + l * 0.5)
		var mi := _box(Vector3(l, h, 0.25), Vector3(mid.x, y + h * 0.5, mid.y), mat)
		mi.rotation.y = yaw
		(_root.get_child(_root.get_child_count() - 1) as Node3D).rotation.y = yaw


func _room(rect: Rect2, h: float, mat: Material, doors := {}) -> void:
	var c := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		_wall(c[i], c[(i + 1) % 4], h, mat, float(doors.get(i, 0.0)))


func _model(key: String, at: Vector3, size: float, yaw := 0.0, dir := Models3D.ART, by_height := false) -> Node3D:
	var m: Node3D = world.models.make(key, dir)
	if m == null:
		return null
	var bb := Models3D.aabb(m)
	var k := size / maxf(0.01, bb.size.y if by_height else maxf(bb.size.x, bb.size.z))
	m.scale = Vector3.ONE * k
	m.position = Vector3(-bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)
	var h := Node3D.new()
	h.add_child(m)
	h.position = at
	h.rotation.y = yaw
	_root.add_child(h)
	return h


func _light(at: Vector3, col := Color("#ffd9a0"), energy := 1.4, rng := 14.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.position = at
	_root.add_child(l)


func _anchor(name: String, local: Vector3) -> void:
	anchors[name] = _root.position + local


func _bars(a: Vector2, b: Vector2, h: float) -> void:
	var steel := _mat("steel", Color(0.25, 0.26, 0.28), 0.4, 0.8)
	var n := int(a.distance_to(b) / 0.22)
	for i in n + 1:
		var p := a.lerp(b, float(i) / maxf(1.0, n))
		_box(Vector3(0.05, h, 0.05), Vector3(p.x, h * 0.5, p.y), steel, false)
	# One solid slab where the bars stand, so nobody walks through them.
	var mid := (a + b) * 0.5
	var dir := (b - a).normalized()
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(a.distance_to(b), h, 0.15)
	cs.shape = sh
	body.add_child(cs)
	body.position = Vector3(mid.x, h * 0.5, mid.y)
	body.rotation.y = atan2(-dir.y, dir.x)
	_root.add_child(body)


# ---------- the sets ----------

func _police_station() -> void:
	var concrete := _tmat("concrete", "concrete", Color(0.78, 0.76, 0.72))
	var paint := _tmat("station_paint", "concrete", Color("#5d7fa0"))
	var cream := _tmat("cream", "concrete", Color("#e2d6ba"))
	_floor(Rect2(-24, -18, 48, 36), 0.0, _tmat("compound", "dirt", Color(0.85, 0.78, 0.68), 5.0))
	_floor(Rect2(-14, -12, 20, 10), 0.01, _tmat("cell_floor", "concrete", Color(0.55, 0.53, 0.5)))
	# The station block: cell, corridor, charge room.
	_room(Rect2(-14, -12, 20, 10), 3.2, paint, { 2: 1.6 })
	_wall(Vector2(-14, -7), Vector2(-4, -7), 3.2, cream)
	_bars(Vector2(-4, -12), Vector2(-4, -7), 2.6)
	_wall(Vector2(-4, -7), Vector2(-4, -2), 3.2, cream, 1.4)
	_box(Vector3(2.0, 0.8, 0.8), Vector3(2, 0.4, -10), _mat("desk", Color("#6b4a2f")))
	_model("plastic_table", Vector3(-10, 0, -9.5), 0.8, 0.0, Models3D.ART, true)
	_light(Vector3(-9, 2.8, -9.5), Color("#e8f0ff"), 1.2, 9.0)
	_light(Vector3(0, 2.8, -5), Color("#e8f0ff"), 1.2, 10.0)
	# The compound wall with the gate on the street side, and the yard.
	_room(Rect2(-24, -18, 48, 36), 2.6, concrete, { 2: 6.0 })
	_light(Vector3(0, 4.0, 6), Color("#ffd9a0"), 1.6, 22.0)
	_model("pickup", Vector3(10, 0, 4), 5.0, 0.4)
	_model("barrier", Vector3(-3, 0, 17), 2.0)
	_model("barrier", Vector3(3, 0, 17), 2.0)
	_anchor("start", Vector3(-9, 0, -9))
	_anchor("president", Vector3(-12, 0, -10.6))
	_anchor("boy", Vector3(-11, 0, -8))
	_anchor("cell_door", Vector3(-5, 0, -9.5))
	_anchor("corridor", Vector3(-2, 0, -4.5))
	_anchor("office", Vector3(2, 0, -8))
	_anchor("yard", Vector3(0, 0, 4))
	_anchor("gate", Vector3(0, 0, 17))
	_anchor("outside", Vector3(0, 0, 22))
	_floor(Rect2(-6, 17, 12, 10), 0.0, concrete)


func _owambe() -> void:
	_floor(Rect2(-22, -16, 44, 34), 0.0, _tmat("ow_floor", "marble", Color("#efe6d2"), 2.5))
	# The canopy: striped fabric roof on poles (solid overhead, so the camera stays under it).
	var gold := _mat("canopy_gold", Color("#e0a91c"), 0.8)
	var white := _mat("canopy_white", Color("#f4efe4"), 0.8)
	for k in 8:
		var stripe := _box(Vector3(5.0, 0.08, 30.0), Vector3(-17.5 + k * 5.0, 4.8, -1.0), gold if k % 2 == 0 else white, false)
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var roof := StaticBody3D.new()
	var rcs := CollisionShape3D.new()
	var rsh := BoxShape3D.new()
	rsh.size = Vector3(40, 0.2, 30)
	rcs.shape = rsh
	roof.add_child(rcs)
	roof.position = Vector3(0, 4.9, -1)
	_root.add_child(roof)
	for i in 5:
		for side in [-16.0, 14.0]:
			_box(Vector3(0.14, 4.8, 0.14), Vector3(-18 + i * 9, 2.4, side), _mat("pole_steel", Color(0.75, 0.75, 0.78), 0.4, 0.7), false)
	# Plastic tables and chairs in rows (the way every Lagos party looks); the dance floor in the middle.
	for i in 5:
		for j in 3:
			var p := Vector3(-16 + i * 8, 0, -12 + j * 7)
			if absf(p.x) < 5 and absf(p.z + 5) < 4:
				continue
			_model("plastic_table", p, 1.0, float(i + j) * 0.7, Models3D.ART, true)
	_box(Vector3(10, 0.05, 7), Vector3(0, 0.03, -5), _mat("dance", Color("#f3e9cf"), 0.15, 0.2), false)
	_box(Vector3(8, 1.0, 3), Vector3(0, 0.5, -14), _tmat("stage", "concrete", Color("#6a4a2a")))
	# Strings of bulbs under the canopy.
	var bulb := _mat("bulb", Color(1.0, 0.9, 0.6))
	bulb.emission_enabled = true
	bulb.emission = Color("#ffcf86")
	bulb.emission_energy_multiplier = 3.0
	for k in 40:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.16
		sm.radial_segments = 6
		sm.rings = 3
		mi.mesh = sm
		mi.material_override = bulb
		mi.position = Vector3(-19 + (k % 20) * 2.0, 4.4 - absf(sin(k * 0.6)) * 0.3, -10.0 if k < 20 else 8.0)
		_root.add_child(mi)
	for k in 6:
		_light(Vector3(-15 + k * 6, 4.2, -4), Color("#ffe0a8"), 1.3, 12.0)
	# The back room where the big men meet.
	var wall := _tmat("ow_wall", "concrete", Color("#f2e9d6"))
	_room(Rect2(12, 10, 9, 7), 3.0, wall, { 3: 1.4 })
	_box(Vector3(3, 0.8, 1.4), Vector3(16.5, 0.4, 14), _mat("desk", Color("#6b4a2f")))
	_light(Vector3(16.5, 2.6, 13.5), Color("#ffd9a0"), 1.0, 7.0)
	_model("suv", Vector3(-12, 0, 14), 5.0, 1.57)
	_model("suv", Vector3(-6, 0, 14), 5.0, 1.57)
	_anchor("start", Vector3(-14, 0, 12))
	_anchor("dance", Vector3(0, 0, -5))
	_anchor("band", Vector3(0, 0, -12))
	_anchor("table", Vector3(-8, 0, -5))
	_anchor("backroom_door", Vector3(12, 0, 13.5))
	_anchor("backroom", Vector3(15, 0, 12))
	_anchor("photo", Vector3(10.5, 0, 12.5))
	_anchor("exit", Vector3(-9, 0, 15))
	for k in 8:
		_anchor("guest%d" % k, Vector3(-14 + (k % 4) * 9, 0, -9 + (k / 4) * 7))


func _stilt_house() -> void:
	var wood := _mat("plank_wood", Color("#5b4632"))
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.1, 0.22, 0.26)
	water.roughness = 0.05
	_box(Vector3(80, 0.1, 80), Vector3(0, -0.4, 0), water, false)
	_floor(Rect2(-6, -5, 12, 10), 1.3, wood)
	_room(Rect2(-6, -5, 12, 10), 2.6, _tmat("zinc", "metal", Color("#a0a6a8"), 2.0), { 2: 1.4 })
	for i in 4:
		_box(Vector3(0.18, 2.4, 0.18), Vector3(-5.5 + (i % 2) * 11, 0.1, -4.5 + (i / 2) * 9), wood, false)
	# The deck outside, the canoe lane, and the red calabashes.
	_floor(Rect2(-3, 5, 6, 4), 1.24, wood)
	var red := _mat("calabash", Color("#a8231c"), 0.5)
	for i in 5:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.5
		mi.mesh = sm
		mi.material_override = red
		mi.position = Vector3(3.5 + (i % 2) * 0.8, 1.55, -3.5 + i * 0.7)
		_root.add_child(mi)
	_light(Vector3(0, 3.0, 0), Color("#ffb45e"), 1.1, 9.0)
	_anchor("start", Vector3(0, 1.3, 7))
	_anchor("door", Vector3(0, 1.3, 4.6))
	_anchor("captives", Vector3(-3.5, 1.3, -2.5))
	_anchor("calabash", Vector3(3.0, 1.3, -2))
	_anchor("canoe", Vector3(0, 0, 11))


func _home() -> void:
	var wall := _tmat("home_wall", "concrete", Color("#c9b48e"))
	_floor(Rect2(-12, -3, 24, 9), 0.0, _tmat("cement", "concrete", Color(0.62, 0.6, 0.56)))
	# The corridor of a face-me-I-face-you house: rooms on both sides.
	_wall(Vector2(-12, -3), Vector2(12, -3), 3.0, wall)
	_wall(Vector2(-12, 6), Vector2(12, 6), 3.0, wall)
	_wall(Vector2(-12, -3), Vector2(-12, 6), 3.0, wall)
	_wall(Vector2(12, -3), Vector2(12, 6), 3.0, wall, 1.4)
	for i in 4:
		var x := -10.0 + i * 6.0
		_box(Vector3(1.0, 2.1, 0.08), Vector3(x, 1.05, -2.85), _mat("door%d" % (i % 2), Color("#6b4a2f") if i % 2 == 0 else Color("#3c5a7a")), false)
		_box(Vector3(1.0, 2.1, 0.08), Vector3(x + 2, 1.05, 5.85), _mat("door%d" % ((i + 1) % 2), Color("#6b4a2f") if i % 2 == 1 else Color("#3c5a7a")), false)
	# Mama Àgbà's room at the end: her iron box under the bed.
	_room(Rect2(-12, -9, 8, 6), 3.0, wall, { 2: 1.2 })
	_floor(Rect2(-12, -9, 8, 6), 0.0, _tmat("cement", "concrete", Color(0.62, 0.6, 0.56)))
	_box(Vector3(2.0, 0.5, 1.2), Vector3(-10, 0.25, -7.8), _mat("bed", Color("#7a3a5a")))
	_box(Vector3(0.9, 0.5, 0.55), Vector3(-6, 0.25, -8.3), _mat("iron", Color(0.22, 0.24, 0.26), 0.4, 0.7))
	_light(Vector3(-8, 2.6, -6), Color("#ffcf86"), 1.0, 8.0)
	_light(Vector3(0, 2.6, 1.5), Color("#ffcf86"), 1.0, 12.0)
	_anchor("start", Vector3(10, 0, 1.5))
	_anchor("corridor", Vector3(0, 0, 1.5))
	_anchor("door", Vector3(-8, 0, -3.4))
	_anchor("box", Vector3(-6.4, 0, -7.4))
	_anchor("room", Vector3(-8.5, 0, -6))


func _safehouse() -> void:
	var wall := _tmat("sh_wall", "concrete", Color("#e8dcc0"))
	_floor(Rect2(-20, -16, 40, 32), 0.0, _tmat("yard", "dirt", Color(0.85, 0.78, 0.68), 5.0))
	_floor(Rect2(-9, -9, 18, 12), 0.01, _tmat("sh_floor", "marble", Color("#d8d0c0"), 2.0))
	_room(Rect2(-20, -16, 40, 32), 2.4, _tmat("fence", "brick", Color("#c8b8a0")), { 2: 5.0 })
	# The bungalow: living room, two bedrooms, doors front and back.
	_room(Rect2(-9, -9, 18, 12), 3.0, wall, { 2: 1.4, 0: 1.4 })
	_wall(Vector2(-1, -9), Vector2(-1, 3), 3.0, wall, 1.2)
	_wall(Vector2(-9, -3), Vector2(-1, -3), 3.0, wall, 1.2)
	_box(Vector3(3.0, 0.8, 1.0), Vector3(4, 0.4, -2), _mat("sofa", Color("#5a3a2a")))
	_box(Vector3(1.6, 0.5, 1.0), Vector3(4, 0.25, -5), _mat("table_w", Color("#7a5a3a")))
	_box(Vector3(0.9, 0.5, 0.55), Vector3(-7, 0.25, -7.5), _mat("iron", Color(0.22, 0.24, 0.26), 0.4, 0.7))
	_model("generator", Vector3(12, 0, -12), 0.9, 0.0, Models3D.ART, true)
	_model("water_tank", Vector3(-15, 0, -12), 3.6, 0.0, Models3D.ART, true)
	_model("van", Vector3(-10, 0, 10), 5.0, 0.0)
	_light(Vector3(4, 2.7, -4), Color("#ffd9a0"), 1.2, 10.0)
	_light(Vector3(-5, 2.7, -6), Color("#ffd9a0"), 0.9, 7.0)
	_light(Vector3(0, 4.0, 9), Color("#ffe8c0"), 1.5, 18.0)
	_anchor("start", Vector3(3, 0, 0))
	_anchor("living", Vector3(4, 0, -3.5))
	_anchor("mama", Vector3(-6, 0, -6.5))
	_anchor("kemi", Vector3(-4, 0, 0))
	_anchor("box", Vector3(-7, 0, -6.6))
	_anchor("front", Vector3(0, 0, 4))
	_anchor("back", Vector3(0, 0, -10))
	_anchor("yard", Vector3(0, 0, 10))
	_anchor("gate", Vector3(0, 0, 16.5))
	_anchor("street", Vector3(0, 0, 22))
	_floor(Rect2(-8, 16, 16, 12), 0.0, _tmat("concrete", "concrete", Color(0.78, 0.76, 0.72)))


func _cellar() -> void:
	var stone := _tmat("stone", "concrete", Color(0.5, 0.47, 0.43))
	_floor(Rect2(-8, -6, 16, 12), 0.0, stone)
	_room(Rect2(-8, -6, 16, 12), 3.0, stone, { 2: 1.6 })
	_bars(Vector2(-8, -1), Vector2(-3, -1), 2.5)
	_wall(Vector2(-3, -6), Vector2(-3, -1), 3.0, stone)
	_box(Vector3(1.6, 0.4, 3.6), Vector3(5, 0.2, 7.8), stone, false) # the stairs up
	_floor(Rect2(-1.5, 6, 3, 6), 0.0, stone)
	_light(Vector3(0, 2.5, 0), Color("#ffb45e"), 1.0, 9.0)
	_anchor("start", Vector3(0, 0, 9))
	_anchor("kemi", Vector3(-5.5, 0, -4))
	_anchor("cell", Vector3(-5.5, 0, -0.2))
	_anchor("guard", Vector3(2, 0, -2))
	_anchor("stairs", Vector3(0, 0, 8))


func _gala() -> void:
	var marble := _tmat("marble", "marble", Color("#f4efe6"), 3.0)
	_floor(Rect2(-24, -18, 48, 40), 0.0, marble)
	var wall := _tmat("gala_wall", "concrete", Color("#efe2c4"))
	_room(Rect2(-24, -18, 48, 30), 6.0, wall, { 2: 4.0 })
	for i in 4:
		for side in [-1.0, 1.0]:
			var pillar := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.6
			cm.bottom_radius = 0.6
			cm.height = 6.0
			pillar.mesh = cm
			pillar.material_override = _mat("gold", Color("#c8a02a"), 0.3, 0.6)
			pillar.position = Vector3(-15 + i * 10, 3.0, side * 8.0)
			_root.add_child(pillar)
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var sh := CylinderShape3D.new()
			sh.radius = 0.6
			sh.height = 6.0
			cs.shape = sh
			body.add_child(cs)
			body.position = pillar.position
			_root.add_child(body)
	for i in 4:
		for j in 2:
			_box(Vector3(2.4, 0.78, 2.4), Vector3(-15 + i * 10, 0.39, -12 + j * 24 * 0.5), _mat("gala_table", Color("#6a1f3a"), 0.5))
	# Money on the floor from the spraying.
	var naira := _mat("naira", Color("#7da36a"), 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 25
	for i in 60:
		var q := _box(Vector3(0.16, 0.01, 0.08), Vector3(rng.randf_range(-6, 6), 0.01, rng.randf_range(-4, 4)), naira, false)
		q.rotation.y = rng.randf() * TAU
	for k in 6:
		_light(Vector3(-20 + k * 8, 5.4, 0), Color("#fff0c8"), 1.4, 14.0)
	# The terrace out to the lagoon and the jetty.
	_floor(Rect2(-10, 12, 20, 12), 0.0, _mat("terrace", Color("#c9b99a")))
	_anchor("start", Vector3(0, 0, 18))
	_anchor("door", Vector3(0, 0, 12.5))
	_anchor("hall", Vector3(0, 0, 0))
	_anchor("senator", Vector3(0, 0, -14))
	_anchor("stairs", Vector3(-20, 0, -14))
	for k in 8:
		_anchor("guest%d" % k, Vector3(-16 + (k % 4) * 10, 0, -6 + (k / 4) * 12))
	for k in 6:
		_anchor("enemy%d" % k, Vector3(-18 + k * 7, 0, -15))


## Obinna's yacht: a white hull with a pointed bow, a teak deck, the saloon cabin and rails, out on
## the dark lagoon. (Built here so the deck is clear to fight on; the free yacht model sails nearby.)
func _yacht() -> void:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.03, 0.08, 0.12)
	water.roughness = 0.05
	water.metallic = 0.2
	_box(Vector3(400, 0.1, 400), Vector3(0, -0.5, 0), water, false)
	var hull := _mat("hull", Color("#f4f4f0"), 0.25, 0.1)
	_box(Vector3(8.4, 2.2, 22), Vector3(0, 0.6, 1.0), hull, false)
	var bow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(8.4, 6.0, 2.2)
	bow.mesh = pm
	bow.material_override = hull
	bow.rotation = Vector3(-PI * 0.5, 0, 0) # the prism's apex points forward (-Z)
	bow.position = Vector3(0, 0.6, -13.0)
	_root.add_child(bow)
	_box(Vector3(8.5, 0.3, 22.2), Vector3(0, -0.35, 1.0), _mat("hull_stripe", Color("#1f2f5a"), 0.3), false)
	var teak := _mat("teak", Color("#a0703f"), 0.6)
	_floor(Rect2(-4, -12, 8, 24), 1.8, teak)
	_box(Vector3(5.0, 2.4, 6.0), Vector3(0, 3.0, -6), _mat("cabin", Color("#f2f2ee"), 0.3))
	_box(Vector3(5.2, 0.8, 0.1), Vector3(0, 3.4, -2.95), _mat("glass", Color(0.1, 0.15, 0.2), 0.05, 0.6), false)
	for side in [-4.1, 4.1]:
		_box(Vector3(0.1, 1.0, 24), Vector3(side, 2.3, 0), _mat("rail", Color(0.8, 0.82, 0.85), 0.3, 0.8))
	_model("yacht", Vector3(40, -0.4, -30), 30.0, 0.4, "res://art3d/free/")
	_light(Vector3(0, 4.5, 3), Color("#cfe0ff"), 1.4, 14.0)
	_light(Vector3(0, 3.0, 10), Color("#ffd9a0"), 1.0, 8.0)
	_anchor("start", Vector3(0, 1.8, 10))
	_anchor("boss", Vector3(0, 1.8, 0))
	_anchor("bow", Vector3(0, 1.8, -11))
	_anchor("stern", Vector3(0, 1.8, 11))
	_anchor("boat", Vector3(10, 0, 14))


## Rooftops for a foot chase: flat roofs of mixed heights with gaps to jump, water tanks and low
## walls to swerve round, ending on a roof with nowhere left to go.
func _rooftops(n: int) -> void:
	var roof := _tmat("roof", "concrete", Color("#9a9288"))
	var zinc := _tmat("zinc", "metal", Color("#a0a6a8"), 2.0)
	var walls := [_tmat("bldg0", "concrete", Color("#c9b49a")), _tmat("bldg1", "concrete", Color("#b88a6a")), _tmat("bldg2", "brick", Color("#d8c8b0"))]
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var z := 0.0
	var y := 7.0
	for i in n:
		var l := rng.randf_range(9.0, 14.0)
		var w := rng.randf_range(6.0, 8.0)
		var x := rng.randf_range(-1.5, 1.5) if i > 0 else 0.0
		y = clampf(y + rng.randf_range(-1.2, 1.2), 5.5, 9.0) if i > 0 else 7.0
		var r := Rect2(x - w * 0.5, z, w, l)
		_floor(r, y, roof if i % 3 != 2 else zinc)
		# The building under the roof, down to the street.
		_box(Vector3(w, y, l), Vector3(x, y * 0.5 - 0.1, z + l * 0.5), walls[i % 3], false)
		# Neighbours on both sides, lower and higher, so the run has a skyline round it.
		for side in [-1.0, 1.0]:
			var nh := rng.randf_range(4.0, 11.0)
			var nw := rng.randf_range(7.0, 10.0)
			_box(Vector3(nw, nh, l + 1.0), Vector3(x + side * (w * 0.5 + nw * 0.5 + rng.randf_range(2.0, 5.0)), nh * 0.5, z + l * 0.5), walls[(i + 1 + int(side)) % 3], false)
			if i % 2 == 0:
				_model("ac_unit", Vector3(x + side * (w * 0.5 + 0.3), y - 2.0, z + l * 0.4), 0.7, PI * 0.5 * side, Models3D.ART, true)
		course.append(_root.position + Vector3(x, y, z + 1.0))
		course.append(_root.position + Vector3(x, y, z + l - 1.0))
		if i % 2 == 1:
			_model("water_tank", Vector3(x + w * 0.3, y, z + l * 0.5), 2.6, 0.0, Models3D.ART, true)
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.9
			cyl.height = 2.6
			cs.shape = cyl
			cs.position.y = 1.3
			body.add_child(cs)
			body.position = Vector3(x + w * 0.3, y, z + l * 0.5)
			_root.add_child(body)
		elif i > 0 and i < n - 1:
			_box(Vector3(w * 0.45, 0.5, 0.25), Vector3(x - w * 0.2, y + 0.25, z + l * 0.45), roof)
		z += l + rng.randf_range(1.6, 3.0)
	# The street far below, so the gaps look down onto a road and not into the sea.
	_box(Vector3(60, 0.2, z + 30), Vector3(0, -0.1, z * 0.5), _tmat("street_below", "dirt", Color(0.7, 0.62, 0.52), 5.0), false)
	anchors["start"] = course[0]
	anchors["end"] = course[course.size() - 1]
	_light(Vector3(0, 14, z * 0.5), Color("#ffe8c0"), 0.8, 60.0)


## Olumo Rock (Abeokuta): stone steps winding up the rock to the lookout at the top. Built on the
## region map round the rock, whose solid core is switched off while the climb is on.
func _olumo() -> void:
	var lm: Dictionary = world.map.landmarks.get("olumo-rock", {})
	var c := Terrain3D.w(lm.get("pos", world.map.player_start))
	c = Vector3(c.x + 8.0, 0, c.z - 24.0) # the rock stands north-east of the lookout spot
	for sp: Dictionary in world.map.set_pieces:
		if String(sp["model"]) == "free:mountain":
			c = Terrain3D.w(sp["pos"])
	var stone := _tmat("olumo_step", "concrete", Color("#8a8070"))
	var top := 18.0
	var steps := 70
	# Each step sits just off the rock's real surface: a ray from outside, level with the step,
	# finds the face (the rock has the exact shape of its mesh as collision).
	var space := get_world_3d().direct_space_state
	var last := Vector3.INF
	for i in steps + 1:
		var t := float(i) / steps
		var h := t * top
		var ang := PI * 0.75 + t * TAU * 1.15
		var out := Vector3(cos(ang), 0, sin(ang))
		var q := PhysicsRayQueryParameters3D.create(c + out * 60.0 + Vector3(0, h + 0.5, 0), c + Vector3(0, h + 0.5, 0), 1)
		var hit := space.intersect_ray(q)
		var p := c + out * (23.5 * (1.0 - h / 44.0) + 1.0) + Vector3(0, h, 0)
		if not hit.is_empty():
			p = (hit["position"] as Vector3) + out * 1.3
			p.y = h
		_box(Vector3(2.6, 0.3, 2.6), p - Vector3(0, 0.15, 0), stone, false)
		platforms.append({ "rect": Rect2(p.x - 1.5, p.z - 1.5, 3.0, 3.0), "y": h })
		# Fill the gap to the last step, so a long stride between them is still stone.
		if last != Vector3.INF and Vector2(p.x - last.x, p.z - last.z).length() > 2.4:
			var mid := (p + last) * 0.5
			platforms.append({ "rect": Rect2(mid.x - 1.5, mid.z - 1.5, 3.0, 3.0), "y": mid.y })
			_box(Vector3(2.6, 0.3, 2.6), mid - Vector3(0, 0.15, 0), stone, false)
		last = p
		if i == 0:
			anchors["start"] = p + out * 3.0
			platforms.append({ "rect": Rect2(p.x - 4, p.z - 4, 8, 8), "y": 0.0 })
		if i == steps:
			var lookout := p + out * 2.0
			_box(Vector3(6, 0.3, 6), lookout - Vector3(0, 0.15, 0), stone, false)
			platforms.append({ "rect": Rect2(lookout.x - 3.0, lookout.z - 3.0, 6, 6), "y": top })
			anchors["top"] = lookout
	anchors["start"].y = 0.0
