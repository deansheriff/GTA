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
	_spin.clear()
	_flicker.clear()
	_night_glow.clear()
	_batches.clear()
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


# ---------- decor (D-032): merged into one mesh per material, so a furnished room is a few draws ----------

var _batches := {} # Material -> SurfaceTool
var _shapes := {} # cache of primitive meshes by size
var _spin: Array = [] # [Node3D, radians per second] ceiling fans
var _flicker: Array = [] # [OmniLight3D, base energy, MeshInstance3D or null] tired fluorescent tubes
var _night_glow: Array = [] # [BaseMaterial3D, energy] windows and screens that glow after dark
var _t := 0.0


func _add(mesh: Mesh, xf: Transform3D, mat: Material) -> void:
	var st: SurfaceTool = _batches.get(mat)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[mat] = st
	st.append_from(mesh, 0, xf)


func _flush() -> void:
	for mat: Material in _batches:
		var mi := MeshInstance3D.new()
		mi.mesh = (_batches[mat] as SurfaceTool).commit()
		mi.material_override = mat
		_root.add_child(mi)
	_batches.clear()


func _bm(size: Vector3) -> BoxMesh:
	var k := "b%s" % size
	if not _shapes.has(k):
		var m := BoxMesh.new()
		m.size = size
		_shapes[k] = m
	return _shapes[k]


func _cm(top: float, bottom: float, h: float, seg := 12) -> CylinderMesh:
	var k := "c%f/%f/%f/%d" % [top, bottom, h, seg]
	if not _shapes.has(k):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = seg
		m.rings = 1
		_shapes[k] = m
	return _shapes[k]


func _sm(r: float, h := -1.0) -> SphereMesh:
	var k := "s%f/%f" % [r, h]
	if not _shapes.has(k):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0 if h < 0.0 else h
		m.radial_segments = 10
		m.rings = 6
		_shapes[k] = m
	return _shapes[k]


## A box piece of decor at a local position (and turn), merged into its material's mesh.
func _p(size: Vector3, at: Vector3, mat: Material, yaw := 0.0) -> void:
	_add(_bm(size), Transform3D(Basis(Vector3.UP, yaw), at), mat)


func _px(size: Vector3, xf: Transform3D, mat: Material) -> void:
	_add(_bm(size), xf, mat)


## Collision only (furniture you bump into).
func _solid(size: Vector3, at: Vector3, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.position = at
	body.rotation.y = yaw
	_root.add_child(body)


## Materials with their own way of taking light: fabric is matt, wood has a low sheen, painted
## metal and chrome shine, glass is see-through, and emissive things glow.
func _fabric(name: String, col: Color) -> BaseMaterial3D:
	var m := _mat("fab_" + name, col, 1.0)
	m.metallic_specular = 0.15
	return m


func _wood(name: String, col: Color) -> BaseMaterial3D:
	var m := _mat("wood_" + name, col, 0.62)
	m.metallic_specular = 0.35
	return m


func _paint(name: String, col: Color) -> BaseMaterial3D:
	return _mat("paint_" + name, col, 0.32, 0.35)


func _chrome() -> BaseMaterial3D:
	return _mat("chrome", Color(0.85, 0.86, 0.88), 0.12, 0.95)


func _glass(name: String, col := Color(0.55, 0.7, 0.8, 0.32)) -> BaseMaterial3D:
	if _mats.has("glass_" + name):
		return _mats["glass_" + name]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.04
	m.metallic = 0.2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats["glass_" + name] = m
	return m


func _emis(name: String, col: Color, energy := 2.5, night_only := false) -> BaseMaterial3D:
	if _mats.has("emis_" + name):
		return _mats["emis_" + name]
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.2)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	_mats["emis_" + name] = m
	if night_only:
		_night_glow.append([m, energy])
	return m


## A ceiling: you can't see it from the street (there is no street), but it stops the camera, so
## inside a room the camera stays inside the room.
func _ceiling(rect: Rect2, y: float, mat: Material) -> void:
	_p(Vector3(rect.size.x, 0.15, rect.size.y), Vector3(rect.get_center().x, y + 0.075, rect.get_center().y), mat)
	_solid(Vector3(rect.size.x, 0.3, rect.size.y), Vector3(rect.get_center().x, y + 0.15, rect.get_center().y))


func _chair(base: Transform3D, seat: Material, frame: Material) -> void:
	_px(Vector3(0.46, 0.06, 0.46), base * Transform3D(Basis(), Vector3(0, 0.46, 0)), seat)
	_px(Vector3(0.46, 0.5, 0.06), base * Transform3D(Basis(), Vector3(0, 0.74, -0.2)), seat)
	for x in [-0.2, 0.2]:
		for z in [-0.2, 0.2]:
			_px(Vector3(0.04, 0.46, 0.04), base * Transform3D(Basis(), Vector3(x, 0.23, z)), frame)


## A banquet table: round, the cloth falling to the floor, with chairs round it.
func _banquet(at: Vector3, r: float, cloth: Material, chairs: int, seat: Material, frame: Material, top_mat: Material = null) -> void:
	_add(_cm(r, r + 0.08, 0.76, 16), Transform3D(Basis(), at + Vector3(0, 0.38, 0)), cloth)
	if top_mat:
		_add(_cm(r * 0.35, r * 0.35, 0.02, 12), Transform3D(Basis(), at + Vector3(0, 0.77, 0)), top_mat)
	for k in chairs:
		var a := TAU * k / chairs
		var p := at + Vector3(cos(a), 0, sin(a)) * (r + 0.45)
		_chair(Transform3D(Basis(Vector3.UP, -a - PI * 0.5), p), seat, frame)
	_solid(Vector3(r * 1.6, 0.8, r * 1.6), at + Vector3(0, 0.4, 0))


func _sofa(base: Transform3D, length: float, fabric: Material, cushion: Material) -> void:
	_px(Vector3(length, 0.42, 0.85), base * Transform3D(Basis(), Vector3(0, 0.21, 0)), fabric)
	_px(Vector3(length, 0.55, 0.2), base * Transform3D(Basis(), Vector3(0, 0.7, -0.33)), fabric)
	for side in [-1.0, 1.0]:
		_px(Vector3(0.2, 0.62, 0.85), base * Transform3D(Basis(), Vector3(side * (length * 0.5 - 0.1), 0.31, 0)), fabric)
	var n := maxi(1, int(length / 0.75))
	for i in n:
		var x := -length * 0.5 + 0.2 + (length - 0.4) * (i + 0.5) / n
		_px(Vector3((length - 0.5) / n - 0.04, 0.12, 0.6), base * Transform3D(Basis(), Vector3(x, 0.48, 0.05)), cushion)
	_solid(Vector3(length, 0.9, 0.85), base.origin + Vector3(0, 0.45, 0), base.basis.get_euler().y)


func _bed(base: Transform3D, frame: Material, sheet: Material, pillow: Material, net := false) -> void:
	_px(Vector3(1.5, 0.35, 2.05), base * Transform3D(Basis(), Vector3(0, 0.18, 0)), frame)
	_px(Vector3(1.4, 0.18, 1.95), base * Transform3D(Basis(), Vector3(0, 0.44, 0)), sheet)
	_px(Vector3(0.55, 0.12, 0.35), base * Transform3D(Basis(), Vector3(-0.32, 0.58, -0.75)), pillow)
	_px(Vector3(0.55, 0.12, 0.35), base * Transform3D(Basis(), Vector3(0.32, 0.58, -0.75)), pillow)
	_px(Vector3(1.5, 0.9, 0.08), base * Transform3D(Basis(), Vector3(0, 0.6, -1.02)), frame)
	if net:
		_px(Vector3(1.7, 1.6, 2.2), base * Transform3D(Basis(), Vector3(0, 1.4, 0)), _glass("net", Color(0.95, 0.95, 0.98, 0.18)))
	_solid(Vector3(1.5, 0.6, 2.05), base.origin + Vector3(0, 0.3, 0), base.basis.get_euler().y)


## A ceiling fan that turns.
func _fan(at: Vector3) -> void:
	var hub := Node3D.new()
	hub.position = at
	_root.add_child(hub)
	var metal := _paint("fan", Color(0.9, 0.9, 0.88))
	var rod := MeshInstance3D.new()
	rod.mesh = _cm(0.02, 0.02, 0.4, 6)
	rod.material_override = metal
	rod.position.y = 0.2
	hub.add_child(rod)
	for k in 3:
		var blade := MeshInstance3D.new()
		blade.mesh = _bm(Vector3(0.62, 0.02, 0.12))
		blade.material_override = metal
		blade.position = Vector3(cos(k * TAU / 3.0) * 0.36, 0, sin(k * TAU / 3.0) * 0.36)
		blade.rotation.y = -k * TAU / 3.0
		hub.add_child(blade)
	_spin.append([hub, 6.0])


## A fluorescent tube on the ceiling with its light; `tired` ones flicker.
func _tube(at: Vector3, yaw := 0.0, tired := false, col := Color("#eef4ff"), energy := 1.2, rng := 9.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _cm(0.03, 0.03, 1.2, 6)
	mi.material_override = _emis("tube", col, 3.0)
	mi.rotation = Vector3(0, yaw, PI * 0.5)
	mi.position = at
	_root.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.position = at - Vector3(0, 0.15, 0)
	_root.add_child(l)
	if tired:
		_flicker.append([l, energy, mi])


## A board on a wall with painted words (a notice, a sign, a slogan).
func _sign(at: Vector3, yaw: float, size: Vector2, text: String, bg: Color, fg: Color, font := 48) -> void:
	_p(Vector3(size.x, size.y, 0.04), at, _paint("sign_%s" % bg.to_html(false), bg), yaw)
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.pixel_size = 0.005
	l.modulate = fg
	l.outline_size = 0
	l.width = size.x / 0.005 * 0.92
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = at + Vector3(sin(yaw), 0, cos(yaw)) * 0.03
	l.rotation.y = yaw
	_root.add_child(l)


## A window in a wall: frame, glass that glows warm after dark, and burglar-proof bars.
func _window(at: Vector3, yaw: float, w := 1.2, h := 1.1, bars := true) -> void:
	var frame := _paint("win_frame", Color(0.85, 0.83, 0.78))
	var b := Basis(Vector3.UP, yaw)
	_p(Vector3(w, h, 0.02), at, _emis("win_glow", Color("#ffcf86"), 1.2, true), yaw)
	for k in [-1.0, 1.0]:
		_px(Vector3(w + 0.1, 0.08, 0.1), Transform3D(b, at + b * Vector3(0, k * h * 0.5, 0)), frame)
		_px(Vector3(0.08, h, 0.1), Transform3D(b, at + b * Vector3(k * w * 0.5, 0, 0)), frame)
	if bars:
		var steel := _paint("burglar", Color(0.18, 0.18, 0.2))
		for i in 5:
			_px(Vector3(0.025, h, 0.025), Transform3D(b, at + b * Vector3(-w * 0.4 + i * w * 0.2, 0, 0.08)), steel)
		_px(Vector3(w, 0.025, 0.025), Transform3D(b, at + b * Vector3(0, 0, 0.08)), steel)


func _picture(at: Vector3, yaw: float, size: Vector2, col: Color) -> void:
	_p(Vector3(size.x + 0.06, size.y + 0.06, 0.03), at, _wood("frame", Color("#3a2a1a")), yaw)
	_p(Vector3(size.x, size.y, 0.035), at, _mat("pic_%s" % col.to_html(false), col, 0.5), yaw)


func _rug(rect: Rect2, col: Color, border: Color) -> void:
	_p(Vector3(rect.size.x, 0.012, rect.size.y), Vector3(rect.get_center().x, 0.016, rect.get_center().y), _fabric("rug_b%s" % border.to_html(false), border))
	_p(Vector3(rect.size.x - 0.3, 0.014, rect.size.y - 0.3), Vector3(rect.get_center().x, 0.018, rect.get_center().y), _fabric("rug_%s" % col.to_html(false), col))


func _curtain(at: Vector3, yaw: float, w: float, h: float, col: Color) -> void:
	var fab := _fabric("curtain_%s" % col.to_html(false), col)
	var b := Basis(Vector3.UP, yaw)
	for i in int(w / 0.25):
		var x := -w * 0.5 + 0.125 + i * 0.25
		_px(Vector3(0.22, h, 0.06), Transform3D(b, at + b * Vector3(x, 0, 0.05 * (i % 2))), fab)


func _speaker(at: Vector3, yaw: float, h := 1.4) -> void:
	var b := Basis(Vector3.UP, yaw)
	_px(Vector3(0.6, h, 0.55), Transform3D(b, at + Vector3(0, h * 0.5, 0)), _paint("speaker", Color(0.08, 0.08, 0.09)))
	for k in 2:
		_add(_cm(0.2 - k * 0.08, 0.2 - k * 0.08, 0.03, 12), Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), at + b * Vector3(0, h * (0.72 - k * 0.42), 0.28)), _paint("cone", Color(0.22, 0.22, 0.24)))
	_solid(Vector3(0.6, h, 0.55), at + Vector3(0, h * 0.5, 0), yaw)


func _chandelier(at: Vector3, r := 1.2) -> void:
	var crystal := _emis("crystal", Color("#fff3d6"), 2.2)
	_add(_cm(0.02, 0.02, 1.2, 6), Transform3D(Basis(), at + Vector3(0, 0.6, 0)), _chrome())
	for ring in 3:
		var rr := r * (1.0 - ring * 0.3)
		var n := 14 - ring * 4
		for k in n:
			var a := TAU * k / n
			_add(_sm(0.06), Transform3D(Basis(), at + Vector3(cos(a) * rr, -ring * 0.3, sin(a) * rr)), crystal)
	_add(_cm(r, r * 0.9, 0.06, 20), Transform3D(Basis(), at + Vector3(0, 0.04, 0)), _paint("gold_ring", Color("#d4a83a")))
	_light(at - Vector3(0, 0.4, 0), Color("#fff0cc"), 1.3, 13.0)


func _balloons(at: Vector3, cols: Array, n := 9) -> void:
	for k in n:
		var a := k * 0.7
		var p := at + Vector3(cos(a) * 0.25, k * 0.28, sin(a) * 0.25)
		var c: Color = cols[k % cols.size()]
		_add(_sm(0.2, 0.46), Transform3D(Basis(), p), _paint("balloon_%s" % c.to_html(false), c))


func _lifering(at: Vector3, yaw: float) -> void:
	var t := TorusMesh.new()
	t.inner_radius = 0.22
	t.outer_radius = 0.36
	t.rings = 12
	t.ring_segments = 6
	_add(t, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), at), _paint("lifering", Color("#e8641c")))


func _lounger(base: Transform3D, fabric: Material) -> void:
	_px(Vector3(0.7, 0.12, 1.6), base * Transform3D(Basis(), Vector3(0, 0.32, 0.1)), fabric)
	_px(Vector3(0.7, 0.1, 0.7), base * Transform3D(Basis(Vector3.RIGHT, 0.7), Vector3(0, 0.55, -0.85)), fabric)
	for z in [-0.6, 0.7]:
		_px(Vector3(0.66, 0.26, 0.05), base * Transform3D(Basis(), Vector3(0, 0.13, z)), _chrome())


## Animate what moves in a set: fans turn, tired tubes flicker, windows glow after dark.
func step(delta: float) -> void:
	if active == "":
		return
	_t += delta
	for s: Array in _spin:
		if is_instance_valid(s[0]):
			(s[0] as Node3D).rotation.y += float(s[1]) * delta
	for f: Array in _flicker:
		var l: OmniLight3D = f[0]
		if not is_instance_valid(l):
			continue
		var on := fmod(_t * 7.3, 5.0) > 0.35 and fmod(_t * 3.1, 9.0) > 0.2
		l.light_energy = float(f[1]) if on else float(f[1]) * 0.15
		if is_instance_valid(f[2]):
			(f[2] as MeshInstance3D).visible = on
	var dark: float = world._dark
	for g: Array in _night_glow:
		(g[0] as BaseMaterial3D).emission_energy_multiplier = float(g[1]) * clampf(dark * 1.4, 0.15, 1.0)


# ---------- the sets ----------

## Yaba police station: the station block (Cell Four behind bars, the corridor, the charge room)
## under one roof, and the compound with its exhibit cars, sandbags, flag and floodlight.
func _police_station() -> void:
	var concrete := _tmat("concrete", "concrete", Color(0.78, 0.76, 0.72))
	var paint := _tmat("station_paint", "concrete", Color("#5d7fa0"))
	var cream := _tmat("cream", "concrete", Color("#e2d6ba"))
	var dado := _paint("dado", Color("#2f4e6e"))
	_floor(Rect2(-24, -18, 48, 36), 0.0, _tmat("compound", "dirt", Color(0.85, 0.78, 0.68), 5.0))
	_floor(Rect2(-14, -12, 20, 10), 0.01, _tmat("cell_floor", "concrete", Color(0.55, 0.53, 0.5)))
	# The block: walls, the bars of Cell Four, the corridor wall and its door.
	_room(Rect2(-14, -12, 20, 10), 3.2, paint, { 2: 1.6 })
	_wall(Vector2(-14, -7), Vector2(-4, -7), 3.2, cream)
	_bars(Vector2(-4, -12), Vector2(-4, -7), 2.6)
	_wall(Vector2(-4, -7), Vector2(-4, -2), 3.2, cream, 1.4)
	_ceiling(Rect2(-14, -12, 20, 10), 3.2, _tmat("ceiling", "concrete", Color(0.86, 0.85, 0.82)))
	# A blue dado band round the walls at waist height: every station in Lagos has one.
	for seg: Array in [[Vector3(-4, 0.6, -11.85), 20.0, 0.0], [Vector3(-13.85, 0.6, -9.5), 5.0, PI * 0.5]]:
		_p(Vector3(seg[1], 1.2, 0.03), seg[0], dado, seg[2])
	# Cell Four: a concrete ledge to sit on, foam mats, a bucket, tally marks on the wall.
	_p(Vector3(9.4, 0.45, 0.6), Vector3(-9, 0.22, -11.6), concrete)
	_solid(Vector3(9.4, 0.45, 0.6), Vector3(-9, 0.22, -11.6))
	for i in 4:
		_p(Vector3(0.8, 0.06, 1.8), Vector3(-12.6 + i * 1.6, 0.04, -9.2 + (i % 2) * 0.4), _fabric("mat%d" % (i % 3), [Color("#3a6a8a"), Color("#8a3a2a"), Color("#5a7a3a")][i % 3]), 0.1 * i)
	_add(_cm(0.18, 0.15, 0.32, 10), Transform3D(Basis(), Vector3(-5.0, 0.16, -11.3)), _paint("bucket", Color("#2f6fb0")))
	_sign(Vector3(-11, 1.9, -11.85), 0.0, Vector2(1.4, 0.5), "IIII IIII IIII II", Color(0.85, 0.83, 0.78), Color(0.25, 0.22, 0.2), 64)
	_tube(Vector3(-9, 3.05, -9.5), 0.0, true)
	# The corridor: a notice board, a fan, a bench.
	_sign(Vector3(-1.5, 1.7, -11.85), 0.0, Vector2(2.2, 1.2), "NOTICE\nBail is free.\nReport any officer who asks for money.", Color("#e8e2cc"), Color("#1d1611"), 40)
	_sign(Vector3(3.5, 2.5, -11.85), 0.0, Vector2(2.6, 0.45), "POLICE IS YOUR FRIEND", Color("#2f4e6e"), Color("#f1e6c8"), 56)
	_p(Vector3(2.4, 0.45, 0.45), Vector3(-1.2, 0.22, -2.6), _wood("bench", Color("#6b4a2f")))
	_solid(Vector3(2.4, 0.45, 0.45), Vector3(-1.2, 0.22, -2.6))
	_fan(Vector3(-1.5, 2.75, -4.5))
	_tube(Vector3(-1.5, 3.05, -6.5), PI * 0.5)
	# The charge room: the desk and its ledger, chairs, filing cabinet, a clock, an old monitor.
	var desk := _wood("desk", Color("#6b4a2f"))
	_p(Vector3(2.2, 0.08, 1.0), Vector3(2, 0.78, -10), desk)
	_p(Vector3(2.1, 0.74, 0.06), Vector3(2, 0.37, -10.45), desk)
	_solid(Vector3(2.2, 0.8, 1.0), Vector3(2, 0.4, -10))
	_p(Vector3(0.5, 0.06, 0.36), Vector3(1.6, 0.85, -9.9), _paint("ledger", Color("#2a4a2a")), 0.2)
	_p(Vector3(0.45, 0.36, 0.4), Vector3(2.6, 1.0, -10.2), _paint("crt", Color(0.75, 0.72, 0.66)))
	_p(Vector3(0.38, 0.28, 0.02), Vector3(2.6, 1.02, -9.99), _emis("crt_screen", Color("#7fc8a0"), 0.8))
	_chair(Transform3D(Basis(Vector3.UP, PI), Vector3(2, 0, -10.9)), _fabric("chair_seat", Color("#2a2a2a")), _chrome())
	_chair(Transform3D(Basis(), Vector3(1.6, 0, -9.0)), _paint("chair_plastic", Color("#e8e4d8")), _paint("chair_plastic", Color("#e8e4d8")))
	_p(Vector3(0.6, 1.4, 0.6), Vector3(5.4, 0.7, -11.5), _paint("cabinet", Color("#6a7a6a")))
	_solid(Vector3(0.6, 1.4, 0.6), Vector3(5.4, 0.7, -11.5))
	_add(_cm(0.18, 0.18, 0.04, 16), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(4, 2.4, -11.85)), _paint("clock", Color(0.95, 0.94, 0.9)))
	_tube(Vector3(2.5, 3.05, -9.5))
	for wx in [-12.0, -7.0]:
		_window(Vector3(wx, 2.2, -12.1), 0.0, 0.9, 0.5)
	_window(Vector3(3.0, 1.6, -2.0), 0.0, 1.4, 1.1)
	# The compound wall with the gate on the street side, and the yard.
	_room(Rect2(-24, -18, 48, 36), 2.6, concrete, { 2: 6.0 })
	_light(Vector3(0, 6.0, 6), Color("#ffd9a0"), 1.8, 26.0)
	_add(_cm(0.08, 0.1, 6.0, 8), Transform3D(Basis(), Vector3(-1, 3.0, 6)), _paint("pole", Color(0.4, 0.4, 0.42)))
	_p(Vector3(0.8, 0.4, 0.5), Vector3(-1, 6.0, 6), _emis("flood", Color("#fff1d0"), 3.0, true))
	# The flag: green, white, green.
	_add(_cm(0.05, 0.06, 7.0, 8), Transform3D(Basis(), Vector3(-6, 3.5, 3)), _chrome())
	for i in 3:
		_p(Vector3(0.6, 1.0, 0.02), Vector3(-5.65 + i * 0.6, 6.4, 3), _fabric("flag%d" % (i % 2), Color("#008751") if i != 1 else Color("#f4f4f0")))
	# Sandbags at the gate, exhibit cars rusting in the yard, tyres, a generator.
	for i in 8:
		_add(_sm(0.35, 0.3), Transform3D(Basis(Vector3.UP, i * 0.4), Vector3(-5.5 + (i % 4) * 0.7, 0.15 + (i / 4) * 0.28, 15.4)), _fabric("sandbag", Color("#a89870")))
	_solid(Vector3(3.0, 0.6, 0.7), Vector3(-4.5, 0.3, 15.4))
	_model("pickup", Vector3(10, 0, 4), 5.0, 0.4)
	_model("car", Vector3(16, 0, -6), 4.4, 1.2)
	_model("okada", Vector3(13.5, 0, -10), 2.0, 2.4)
	_model("tyres", Vector3(18, 0, 8), 1.2, 0.0, Models3D.ART, true)
	_model("generator", Vector3(-18, 0, -14), 0.9, 0.0, Models3D.ART, true)
	_model("barrier", Vector3(-3, 0, 17), 2.0)
	_model("barrier", Vector3(3, 0, 17), 2.0)
	_sign(Vector3(0, 3.3, 17.9), PI, Vector2(6.0, 0.7), "NIGERIA POLICE · YABA DIVISION", Color("#2f4e6e"), Color("#f1e6c8"), 64)
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
	_flush()


## The senator's daughter's owambe: a striped canopy over plastic tables, the couple's high table on
## a stage with its backdrop and balloon arches, the DJ and his speakers, the buffet, coolers of
## drinks, a red carpet up the middle, and the back room where the big men meet.
func _owambe() -> void:
	_floor(Rect2(-22, -16, 44, 34), 0.0, _tmat("ow_floor", "marble", Color("#efe6d2"), 2.5))
	var gold := _fabric("canopy_gold", Color("#e0a91c"))
	var white := _fabric("canopy_white", Color("#f4efe4"))
	for k in 8:
		_p(Vector3(5.0, 0.08, 30.0), Vector3(-17.5 + k * 5.0, 4.8, -1.0), gold if k % 2 == 0 else white)
		# The valance: scalloped fabric hanging along both edges.
		for side in [-16.0, 14.0]:
			_p(Vector3(4.9, 0.5, 0.04), Vector3(-17.5 + k * 5.0, 4.5, side), white if k % 2 == 0 else gold)
	_solid(Vector3(40, 0.2, 30), Vector3(0, 4.95, -1))
	for i in 5:
		for side in [-16.0, 14.0]:
			_add(_cm(0.07, 0.07, 4.8, 8), Transform3D(Basis(), Vector3(-18 + i * 9, 2.4, side)), _chrome())
	# Tables: the plastic ones of every Lagos party, with gold and wine covers on the guests' rows.
	var cover_gold := _fabric("cover_gold", Color("#d9a52a"))
	var cover_wine := _fabric("cover_wine", Color("#7a1f3a"))
	var seat := _fabric("seat_white", Color("#f2efe6"))
	for i in 5:
		for j in 3:
			var p := Vector3(-16 + i * 8, 0, -9 + j * 6.5)
			if absf(p.x) < 5:
				continue
			_banquet(p, 0.8, cover_gold if (i + j) % 2 == 0 else cover_wine, 6, seat, _chrome(), _emis("centrepiece", Color("#ffe7b0"), 0.6))
	# The red carpet up the middle, from the entrance to the dance floor.
	_p(Vector3(2.2, 0.02, 14.0), Vector3(0, 0.02, 7.5), _fabric("red_carpet", Color("#9a1c22")))
	_p(Vector3(10, 0.04, 7), Vector3(0, 0.03, -5), _mat("dance", Color("#f3e9cf"), 0.12, 0.25))
	# The stage: the couple's high table, gold chairs, the backdrop with their monogram, balloons.
	_p(Vector3(12, 0.6, 3.6), Vector3(0, 0.3, -13.2), _wood("stage", Color("#4a3020")))
	_solid(Vector3(12, 0.6, 3.6), Vector3(0, 0.3, -13.2))
	_p(Vector3(6, 0.08, 1.0), Vector3(0, 1.38, -13.4), _fabric("high_table", Color("#f8f4ea")))
	_p(Vector3(6, 0.75, 0.9), Vector3(0, 0.98, -13.4), _fabric("high_skirt", Color("#d9a52a")))
	for k in 6:
		_chair(Transform3D(Basis(), Vector3(-2.5 + k, 0.6, -14.2)), _paint("gold_chair", Color("#d4a83a")), _paint("gold_chair", Color("#d4a83a")))
	_p(Vector3(12, 3.6, 0.1), Vector3(0, 2.4, -15.0), _fabric("backdrop", Color("#f4ede0")))
	_sign(Vector3(0, 3.0, -14.9), 0.0, Vector2(4.2, 1.1), "OUR FOREVER\n#JK2026", Color("#f4ede0"), Color("#b8862a"), 72)
	for side in [-1.0, 1.0]:
		_balloons(Vector3(side * 6.2, 0.6, -13.0), [Color("#d4a83a"), Color("#f4efe4"), Color("#7a1f3a")], 12)
	# The DJ in the corner and his towers of speakers; the MC's stand.
	_p(Vector3(2.4, 1.0, 1.0), Vector3(-14, 0.5, -12), _paint("dj_desk", Color(0.1, 0.1, 0.12)))
	_solid(Vector3(2.4, 1.0, 1.0), Vector3(-14, 0.5, -12))
	_p(Vector3(0.5, 0.05, 0.35), Vector3(-14.5, 1.03, -12), _emis("dj_deck", Color("#4fb3d9"), 1.5))
	for x in [-16.5, -11.5, 11.5]:
		_speaker(Vector3(x, 0, -12.5), 0.3 if x < 0 else -0.3, 1.6)
	# The buffet along the side: chafing dishes, and coolers of drinks.
	_p(Vector3(6, 0.78, 1.0), Vector3(19, 0.39, -4), _fabric("buffet", Color("#f8f4ea")))
	_solid(Vector3(6, 0.8, 1.0), Vector3(19, 0.4, -4))
	for k in 5:
		_add(_cm(0.32, 0.28, 0.22, 12), Transform3D(Basis(), Vector3(16.8 + k * 1.1, 0.9, -4)), _chrome())
	for k in 3:
		_p(Vector3(0.8, 0.55, 0.5), Vector3(17 + k * 1.2, 0.28, 0.5), _paint("cooler%d" % k, [Color("#2f6fb0"), Color("#d93a2a"), Color("#2f8a52")][k]))
		_solid(Vector3(0.8, 0.55, 0.5), Vector3(17 + k * 1.2, 0.28, 0.5))
	# Strings of bulbs under the canopy, and coloured floor lights on the dance floor.
	var bulb := _emis("bulb", Color("#ffcf86"), 3.0)
	for k in 60:
		var row := k / 20
		_add(_sm(0.07), Transform3D(Basis(), Vector3(-19 + (k % 20) * 2.0, 4.4 - absf(sin(k * 0.6)) * 0.3, [-10.0, -1.0, 8.0][row])), bulb)
	for k in 5:
		_light(Vector3(-15 + k * 7.5, 4.2, -2), Color("#ffe0a8"), 1.2, 12.0)
	for c in [[Vector3(-3, 3.6, -5), Color("#b05ad9")], [Vector3(3, 3.6, -5), Color("#e0a91c")]]:
		_light(c[0], c[1], 1.6, 7.0)
	# The back room where the big men meet: walls, a desk, leather chairs, the window you photograph through.
	var wall := _tmat("ow_wall", "concrete", Color("#f2e9d6"))
	_room(Rect2(12, 10, 9, 7), 3.0, wall, { 3: 1.4 })
	_ceiling(Rect2(12, 10, 9, 7), 3.0, _tmat("ceiling", "concrete", Color(0.86, 0.85, 0.82)))
	_p(Vector3(3, 0.08, 1.4), Vector3(16.5, 0.78, 14), _wood("exec_desk", Color("#3a2414")))
	_p(Vector3(2.9, 0.74, 1.3), Vector3(16.5, 0.37, 14), _wood("exec_desk", Color("#3a2414")))
	_solid(Vector3(3, 0.8, 1.4), Vector3(16.5, 0.4, 14))
	for x in [15.5, 17.5]:
		_chair(Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, 15.2)), _fabric("leather", Color("#2a1a12")), _chrome())
	_p(Vector3(0.3, 0.06, 0.2), Vector3(16.2, 0.85, 13.9), _paint("envelope", Color("#c9a26a")), 0.3)
	_window(Vector3(12.0, 1.5, 12.5), PI * 0.5, 1.4, 1.0, false)
	_tube(Vector3(16.5, 2.9, 13.5), 0.0, false, Color("#ffe0b0"), 1.0, 7.0)
	_model("suv", Vector3(-12, 0, 14), 5.0, 1.57)
	_model("suv", Vector3(-6, 0, 14), 5.0, 1.57)
	_model("generator", Vector3(20, 0, 15), 0.9, 0.0, Models3D.ART, true)
	_anchor("start", Vector3(-14, 0, 12))
	_anchor("dance", Vector3(0, 0, -5))
	_anchor("band", Vector3(0, 0, -11))
	_anchor("table", Vector3(-8, 0, -5))
	_anchor("backroom_door", Vector3(12, 0, 13.5))
	_anchor("backroom", Vector3(15, 0, 12))
	_anchor("photo", Vector3(10.5, 0, 12.5))
	_anchor("exit", Vector3(-9, 0, 15))
	for k in 8:
		_anchor("guest%d" % k, Vector3(-14 + (k % 4) * 9, 0, -9 + (k / 4) * 7))
	_flush()


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


## Uncle Obi's Festac safe house: a furnished bungalow (living room with its sofa set, TV, fan and
## family photos; Mama Àgbà's room with the iron box; Kemi's room with her law books; a kitchen
## corner) under one roof, and the yard with its gate, tank, generator and washing line.
func _safehouse() -> void:
	var wall := _tmat("sh_wall", "concrete", Color("#e8dcc0"))
	_floor(Rect2(-20, -16, 40, 32), 0.0, _tmat("yard", "dirt", Color(0.85, 0.78, 0.68), 5.0))
	_floor(Rect2(-9, -9, 18, 12), 0.01, _tmat("sh_floor", "marble", Color("#d8d0c0"), 2.0))
	_room(Rect2(-20, -16, 40, 32), 2.4, _tmat("fence", "brick", Color("#c8b8a0")), { 2: 5.0 })
	_room(Rect2(-9, -9, 18, 12), 3.0, wall, { 2: 1.4, 0: 1.4 })
	_wall(Vector2(-1, -9), Vector2(-1, 3), 3.0, wall, 1.2)
	_wall(Vector2(-9, -3), Vector2(-1, -3), 3.0, wall, 1.2)
	_ceiling(Rect2(-9, -9, 18, 12), 3.0, _tmat("ceiling", "concrete", Color(0.86, 0.85, 0.82)))
	# Living room.
	var fabric := _fabric("sofa", Color("#6a3a2a"))
	var cushion := _fabric("cushion", Color("#c8a06a"))
	_rug(Rect2(1.5, -6.8, 5.0, 4.0), Color("#8a2a2a"), Color("#d9a52a"))
	_sofa(Transform3D(Basis(), Vector3(4, 0, -7.9)), 2.6, fabric, cushion)
	_sofa(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(7.6, 0, -4.8)), 1.0, fabric, cushion)
	_sofa(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.6, 0, -4.8)), 1.0, fabric, cushion)
	_p(Vector3(1.4, 0.06, 0.8), Vector3(4, 0.45, -4.8), _glass("table_top", Color(0.5, 0.6, 0.6, 0.5)))
	_p(Vector3(1.3, 0.42, 0.7), Vector3(4, 0.21, -4.8), _wood("table", Color("#5a3a22")))
	_solid(Vector3(1.4, 0.5, 0.8), Vector3(4, 0.25, -4.8))
	_p(Vector3(0.5, 0.01, 0.35), Vector3(4, 0.49, -4.8), _fabric("doily", Color(0.98, 0.98, 0.95)))
	# The TV on its stand, against the wall facing the sofa (it flickers blue after dark).
	_p(Vector3(1.8, 0.6, 0.45), Vector3(4, 0.3, -1.4), _wood("tv_stand", Color("#3a2414")))
	_solid(Vector3(1.8, 0.6, 0.45), Vector3(4, 0.3, -1.4))
	_p(Vector3(1.3, 0.75, 0.06), Vector3(4, 1.0, -1.45), _paint("tv", Color(0.05, 0.05, 0.06)))
	_p(Vector3(1.2, 0.66, 0.02), Vector3(4, 1.0, -1.49), _emis("tv_screen", Color("#7fa8e0"), 0.9, true), PI)
	_fan(Vector3(4, 2.75, -4.8))
	_tube(Vector3(4, 2.95, -6.5), 0.0, false, Color("#f4f8ff"), 1.1, 9.0)
	_picture(Vector3(2.5, 1.9, -8.85), 0.0, Vector2(0.6, 0.45), Color("#8a7a5a"))
	_picture(Vector3(5.5, 1.9, -8.85), 0.0, Vector2(0.45, 0.6), Color("#6a5a4a"))
	_sign(Vector3(4, 2.45, -8.85), 0.0, Vector2(1.6, 0.35), "GOD BLESS OUR HOME", Color("#f4efe4"), Color("#7a1f3a"), 48)
	_add(_cm(0.16, 0.16, 0.04, 16), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(7.5, 2.3, -8.85)), _paint("clock", Color(0.95, 0.94, 0.9)))
	for wx in [2.0, 6.0]:
		_window(Vector3(wx, 1.6, -9.1), 0.0, 1.2, 1.1)
		_curtain(Vector3(wx, 1.6, -8.95), 0.0, 1.5, 1.4, Color("#a8823a"))
	# The kitchen corner: gas cylinder, two-burner stove, pots, the water drum.
	_p(Vector3(2.0, 0.85, 0.6), Vector3(7.6, 0.43, 1.4), _tmat("worktop", "concrete", Color(0.7, 0.68, 0.64)))
	_solid(Vector3(2.0, 0.85, 0.6), Vector3(7.6, 0.43, 1.4))
	_model("gas_tank", Vector3(6.4, 0, 2.3), 0.7, 0.0, "res://art3d/free/", true)
	for k in 2:
		_add(_cm(0.18, 0.16, 0.18, 10), Transform3D(Basis(), Vector3(7.3 + k * 0.6, 0.95, 1.4)), _chrome())
	_add(_cm(0.32, 0.32, 0.9, 12), Transform3D(Basis(), Vector3(8.4, 0.45, -0.4)), _paint("drum", Color("#2f6fb0")))
	# Mama Àgbà's room: her bed under a mosquito net, her iron box, a mat, a wrapper on a line.
	_bed(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-7.5, 0, -6.6)), _wood("bed", Color("#5a3a22")), _fabric("wrapper", Color("#2f6fb0")), _fabric("pillow", Color(0.95, 0.93, 0.88)), true)
	var iron := _paint("iron", Color(0.24, 0.26, 0.28))
	_p(Vector3(0.9, 0.5, 0.55), Vector3(-4.6, 0.25, -8.4), iron)
	for k in 3:
		_p(Vector3(0.04, 0.52, 0.57), Vector3(-4.9 + k * 0.3, 0.26, -8.4), _chrome())
	_solid(Vector3(0.9, 0.5, 0.55), Vector3(-4.6, 0.25, -8.4))
	_p(Vector3(1.0, 0.01, 1.6), Vector3(-3.0, 0.02, -6.0), _fabric("raffia", Color("#c9a86a")))
	_tube(Vector3(-5, 2.95, -6), 0.0, false, Color("#ffd9a0"), 0.8, 6.0)
	_window(Vector3(-9.1, 1.6, -6), PI * 0.5, 1.0, 1.0)
	# Kemi's room: bed, desk, law books, a lamp.
	_bed(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-2.6, 0, 0.6)), _wood("bed2", Color("#3a2a1a")), _fabric("sheet_purple", Color("#7a4aa0")), _fabric("pillow", Color(0.95, 0.93, 0.88)))
	_p(Vector3(1.2, 0.06, 0.6), Vector3(-7.4, 0.76, 2.4), _wood("desk2", Color("#7a5a3a")))
	_p(Vector3(1.2, 0.74, 0.04), Vector3(-7.4, 0.37, 2.68), _wood("desk2", Color("#7a5a3a")))
	_solid(Vector3(1.2, 0.8, 0.6), Vector3(-7.4, 0.4, 2.4))
	for k in 4:
		_p(Vector3(0.24, 0.32, 0.06), Vector3(-7.8 + k * 0.08, 0.95, 2.55), _paint("book%d" % k, [Color("#7a1f1f"), Color("#1f3a7a"), Color("#2a5a2a"), Color("#6a4a1a")][k]))
	_add(_sm(0.1), Transform3D(Basis(), Vector3(-7.0, 1.05, 2.4)), _emis("desk_lamp", Color("#ffd9a0"), 1.5, true))
	_tube(Vector3(-5, 2.95, 0), 0.0, false, Color("#f4f8ff"), 0.8, 6.0)
	# The yard: the sliding gate, the tank, the generator, the washing line, plastic chairs.
	_p(Vector3(5.0, 2.2, 0.1), Vector3(-2.6, 1.1, 16.1), _paint("gate", Color("#2a2a2c")))
	for k in 12:
		_p(Vector3(0.04, 2.2, 0.06), Vector3(-4.9 + k * 0.42, 1.1, 16.0), _paint("gate_bar", Color("#3a3a3c")))
	_model("generator", Vector3(12, 0, -12), 0.9, 0.0, Models3D.ART, true)
	_model("water_tank", Vector3(-15, 0, -12), 3.6, 0.0, Models3D.ART, true)
	_model("van", Vector3(-10, 0, 10), 5.0, 0.0)
	_model("plastic_table", Vector3(9, 0, 8), 0.8, 0.4, Models3D.ART, true)
	for x in [-16.0, -11.0]:
		_add(_cm(0.04, 0.04, 2.0, 6), Transform3D(Basis(), Vector3(x, 1.0, -2)), _chrome())
	_add(_cm(0.008, 0.008, 5.0, 4), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-13.5, 1.95, -2)), _paint("line", Color(0.9, 0.9, 0.9)))
	for k in 4:
		_p(Vector3(0.9, 1.0, 0.02), Vector3(-15.2 + k * 1.1, 1.45, -2), _fabric("ankara%d" % k, [Color("#e0a91c"), Color("#2f6fb0"), Color("#c4473a"), Color("#2f8a52")][k]))
	_light(Vector3(0, 4.0, 9), Color("#ffe8c0"), 1.5, 18.0)
	_p(Vector3(0.5, 0.25, 0.3), Vector3(0, 3.2, 3.15), _emis("security", Color("#fff1d0"), 2.5, true))
	_anchor("start", Vector3(3, 0, -2.8))
	_anchor("living", Vector3(4, 0, -3.5))
	_anchor("mama", Vector3(-6, 0, -5.5))
	_anchor("kemi", Vector3(-4, 0, -1.2))
	_anchor("box", Vector3(-4.6, 0, -7.6))
	_anchor("front", Vector3(0, 0, 4))
	_anchor("back", Vector3(0, 0, -10))
	_anchor("yard", Vector3(0, 0, 10))
	_anchor("gate", Vector3(0, 0, 16.5))
	_anchor("street", Vector3(0, 0, 22))
	_floor(Rect2(-8, 16, 16, 12), 0.0, _tmat("concrete", "concrete", Color(0.78, 0.76, 0.72)))
	_flush()


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


## The governor-elect's victory gala, Banana Island: a marble hall with chandeliers, gold columns,
## banquet tables in white and gold, red velvet curtains, the stage with the campaign banner, the
## staircase to the gallery where the senator ends up on his knees, money on the floor from the
## spraying, and the terrace with its pool out to the lagoon.
func _gala() -> void:
	var marble := _tmat("marble", "marble", Color("#f4efe6"), 3.0)
	_floor(Rect2(-24, -18, 48, 40), 0.0, marble)
	var wall := _tmat("gala_wall", "concrete", Color("#efe2c4"))
	_room(Rect2(-24, -18, 48, 30), 6.0, wall, { 2: 4.0 })
	_ceiling(Rect2(-24, -18, 48, 30), 6.0, _mat("gala_ceiling", Color("#f6efe0"), 0.6))
	# A dark wood skirting and a gold cornice round the hall.
	for seg: Array in [[Vector3(0, 0.15, -17.85), 48.0, 0.0], [Vector3(-23.85, 0.15, -3), 30.0, PI * 0.5], [Vector3(23.85, 0.15, -3), 30.0, PI * 0.5]]:
		_p(Vector3(seg[1], 0.3, 0.05), seg[0], _wood("skirting", Color("#3a2414")), seg[2])
		_p(Vector3(seg[1], 0.25, 0.08), seg[0] + Vector3(0, 5.7, 0), _paint("cornice", Color("#d4a83a")), seg[2])
	var gold := _paint("gold", Color("#d4a83a"))
	for i in 4:
		for side in [-1.0, 1.0]:
			var p := Vector3(-15 + i * 10, 0, side * 8.0)
			_add(_cm(0.55, 0.55, 5.4, 16), Transform3D(Basis(), p + Vector3(0, 3.0, 0)), gold)
			_p(Vector3(1.4, 0.3, 1.4), p + Vector3(0, 0.15, 0), _mat("plinth", Color("#2a1a12"), 0.3, 0.1))
			_p(Vector3(1.4, 0.3, 1.4), p + Vector3(0, 5.85, 0), gold)
			_solid(Vector3(1.2, 6.0, 1.2), p + Vector3(0, 3.0, 0))
	# Velvet curtains between tall windows along the back wall.
	for k in 5:
		var x := -20.0 + k * 10.0
		_window(Vector3(x, 3.0, -17.8), 0.0, 2.4, 3.6, false)
		for s in [-1.0, 1.0]:
			_curtain(Vector3(x + s * 1.7, 3.0, -17.7), 0.0, 1.0, 4.6, Color("#7a1424"))
	for k in 4:
		_chandelier(Vector3(-15 + k * 10, 5.2, -2), 1.3)
	# Banquet tables in white and gold.
	var cloth := _fabric("gala_cloth", Color("#f8f4ea"))
	var sash := _emis("centre_candle", Color("#ffcf86"), 1.0)
	var chair_gold := _paint("chiavari", Color("#d4a83a"))
	var chair_seat := _fabric("chiavari_seat", Color("#f2efe6"))
	for i in 4:
		for j in 2:
			_banquet(Vector3(-15 + i * 10, 0, -12 + j * 12), 1.1, cloth, 8, chair_seat, chair_gold, sash)
	# The stage and the campaign banner.
	_p(Vector3(14, 0.8, 4), Vector3(0, 0.4, -15.5), _wood("stage", Color("#2a1a12")))
	_solid(Vector3(14, 0.8, 4), Vector3(0, 0.4, -15.5))
	_sign(Vector3(0, 4.2, -17.7), 0.0, Vector2(9.0, 1.2), "VICTORY GALA · EKO FOR EVERYBODY", Color("#5a1a7a"), Color("#f6d04d"), 96)
	for x in [-6.0, 6.0]:
		_speaker(Vector3(x, 0.8, -16), 0.0, 1.4)
	_p(Vector3(0.6, 1.1, 0.5), Vector3(0, 1.35, -14.3), _wood("lectern", Color("#3a2414")))
	# Stairs up to the gallery at the back left, where the senator is cornered.
	for k in 6:
		_p(Vector3(3.0, 0.2, 0.5), Vector3(-20, 0.1 + k * 0.2, -11.5 - k * 0.5), marble)
	_p(Vector3(6, 0.2, 4), Vector3(-20, 1.1, -15.5), marble)
	_add(_cm(0.04, 0.04, 6.0, 6), Transform3D(Basis(Vector3.RIGHT, 0.38), Vector3(-18.4, 1.8, -13)), gold)
	# Money on the floor from the spraying: naira notes in two colours, thick by the dance floor.
	var rng := RandomNumberGenerator.new()
	rng.seed = 25
	var notes := [_mat("naira1000", Color("#8aa86a"), 0.85), _mat("naira500", Color("#5a8ac4"), 0.85)]
	for i in 160:
		var r := sqrt(rng.randf()) * 7.0
		var a := rng.randf() * TAU
		_p(Vector3(0.16, 0.004, 0.08), Vector3(cos(a) * r, 0.012 + (i % 3) * 0.002, sin(a) * r * 0.7), notes[i % 2], rng.randf() * TAU)
	# Overturned chairs and a dropped tray: the party is over.
	_chair(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(3, 0.25, 3)), chair_seat, chair_gold)
	_add(_cm(0.3, 0.3, 0.02, 16), Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3(-2, 0.02, 2)), _chrome())
	for k in 6:
		_light(Vector3(-20 + k * 8, 5.2, 6), Color("#fff0c8"), 0.9, 12.0)
	# The terrace: tiles, a pool, potted palms, and the lagoon beyond the rail.
	_floor(Rect2(-10, 12, 20, 12), 0.0, _tmat("terrace", "marble", Color("#d9cdb4"), 2.0))
	var pool := StandardMaterial3D.new()
	pool.albedo_color = Color(0.2, 0.6, 0.75)
	pool.roughness = 0.03
	pool.metallic = 0.2
	_p(Vector3(8, 0.05, 4), Vector3(4, 0.03, 18), pool)
	_p(Vector3(8.4, 0.08, 0.2), Vector3(4, 0.04, 15.9), marble)
	_solid(Vector3(8, 0.6, 4), Vector3(4, 0.3, 18))
	for x in [-8.0, 8.5]:
		_model("palm", Vector3(x, 0, 13), 3.0, 0.0, Models3D.ART, true)
		_add(_cm(0.45, 0.35, 0.6, 12), Transform3D(Basis(), Vector3(x, 0.3, 13)), _paint("planter", Color("#3a3a3a")))
	for k in 10:
		_add(_cm(0.03, 0.03, 1.0, 6), Transform3D(Basis(), Vector3(-9 + k * 2, 0.5, 23.8)), _chrome())
	_p(Vector3(20, 0.05, 0.08), Vector3(0, 1.0, 23.8), _chrome())
	_anchor("start", Vector3(0, 0, 18))
	_anchor("door", Vector3(0, 0, 12.5))
	_anchor("hall", Vector3(0, 0, 0))
	_anchor("senator", Vector3(-20, 1.2, -15.5))
	_anchor("stairs", Vector3(-20, 0, -11))
	for k in 8:
		_anchor("guest%d" % k, Vector3(-16 + (k % 4) * 10, 0, -6 + (k / 4) * 12))
	for k in 6:
		_anchor("enemy%d" % k, Vector3(-16 + k * 6.5, 0, -11))
	platforms.append({ "rect": Rect2(_root.position.x - 23, _root.position.z - 17.5, 6, 4), "y": 1.2 })
	for k in 6:
		platforms.append({ "rect": Rect2(_root.position.x - 21.5, _root.position.z - 11.75 - k * 0.5, 3.0, 0.5), "y": 0.2 + k * 0.2 })
	_flush()


## Obinna's yacht on the dark lagoon: a long white hull with a raked bow and a blue boot stripe,
## lit portholes, a teak deck, the saloon with its glowing windows and the flybridge above it, white
## sofas and sun loungers at the stern, life rings, the radar mast with its lights, and the
## navigation lights, red to port and green to starboard. Rain makes the deck shine.
func _yacht() -> void:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.03, 0.08, 0.12)
	water.roughness = 0.05
	water.metallic = 0.2
	_p(Vector3(400, 0.1, 400), Vector3(0, -0.5, 0), water)
	var hull := _paint("hull", Color("#f4f4f0"))
	hull.roughness = 0.2
	_p(Vector3(8.4, 2.2, 22), Vector3(0, 0.6, 1.0), hull)
	# The bow narrows in steps to a point.
	for k in 5:
		var w := 8.4 - (k + 1) * 1.55
		_p(Vector3(w, 2.2 + k * 0.08, 1.0), Vector3(0, 0.6 + k * 0.04, -10.5 - k * 1.0), hull)
	_p(Vector3(8.5, 0.35, 22.2), Vector3(0, -0.35, 1.0), _paint("boot", Color("#1f2f5a")))
	for k in 5:
		var w := 8.5 - (k + 1) * 1.55
		_p(Vector3(w, 0.35, 1.02), Vector3(0, -0.35, -10.5 - k * 1.0), _paint("boot", Color("#1f2f5a")))
	# Portholes along both sides.
	var port := _emis("porthole", Color("#ffd9a0"), 1.8, true)
	for z in range(-8, 11, 2):
		for s in [-4.22, 4.22]:
			_add(_cm(0.16, 0.16, 0.04, 10), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s, 0.9, z)), port)
	# The deck, the saloon and its windows, the flybridge.
	var teak := _wood("teak", Color("#a0703f"))
	teak.roughness = 0.35 if world.stage and world.stage.raining else 0.62
	_floor(Rect2(-4, -12, 8, 24), 1.8, teak)
	for z in range(-12, 12, 1):
		_p(Vector3(7.9, 0.005, 0.02), Vector3(0, 1.805, z + 0.5), _wood("caulk", Color("#2a1a10")))
	var cabin := _paint("cabin", Color("#f2f2ee"))
	_p(Vector3(5.0, 2.4, 6.0), Vector3(0, 3.0, -6), cabin)
	_solid(Vector3(5.0, 2.4, 6.0), Vector3(0, 3.0, -6))
	_p(Vector3(5.06, 0.8, 5.4), Vector3(0, 3.3, -6), _emis("saloon", Color("#ffe0b0"), 1.4, true))
	_p(Vector3(5.2, 0.8, 0.06), Vector3(0, 3.4, -2.97), _glass("saloon_front", Color(0.15, 0.2, 0.25, 0.6)))
	_p(Vector3(5.4, 0.15, 6.6), Vector3(0, 4.3, -6), cabin)
	_p(Vector3(3.0, 0.9, 2.0), Vector3(0, 4.8, -6.8), _glass("bridge_screen", Color(0.2, 0.25, 0.3, 0.5)))
	_add(_cm(0.06, 0.08, 3.0, 8), Transform3D(Basis(), Vector3(0, 5.8, -7.5)), _chrome())
	_p(Vector3(1.6, 0.06, 0.2), Vector3(0, 7.0, -7.5), _chrome())
	_add(_sm(0.1), Transform3D(Basis(), Vector3(0, 7.35, -7.5)), _emis("masthead", Color("#ffffff"), 4.0))
	_add(_sm(0.12), Transform3D(Basis(), Vector3(-2.6, 3.9, -3.2)), _emis("nav_port", Color("#ff2a1a"), 4.0))
	_add(_sm(0.12), Transform3D(Basis(), Vector3(2.6, 3.9, -3.2)), _emis("nav_star", Color("#2aff5a"), 4.0))
	# Rails, with stanchions.
	for side in [-4.1, 4.1]:
		_p(Vector3(0.05, 0.05, 23), Vector3(side, 2.8, -0.5), _chrome())
		_p(Vector3(0.05, 0.05, 23), Vector3(side, 2.35, -0.5), _chrome())
		for z in range(-11, 12, 2):
			_add(_cm(0.025, 0.025, 1.0, 6), Transform3D(Basis(), Vector3(side, 2.3, z)), _chrome())
		_solid(Vector3(0.1, 1.2, 24), Vector3(side, 2.4, 0))
	# The stern: a white sofa round a table, sun loungers, life rings, the swim platform.
	var leather := _fabric("yacht_sofa", Color("#f2efe6"))
	_sofa(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1.8, 10.9)), 5.0, leather, _fabric("yacht_cushion", Color("#1f2f5a")))
	_p(Vector3(2.0, 0.06, 1.0), Vector3(0, 2.5, 9.4), teak)
	_add(_cm(0.06, 0.06, 0.7, 8), Transform3D(Basis(), Vector3(0, 2.15, 9.4)), _chrome())
	for x in [-2.6, 2.6]:
		_lounger(Transform3D(Basis(), Vector3(x, 1.8, 5.5)), leather)
	_lifering(Vector3(-4.2, 2.6, 2), PI * 0.5)
	_lifering(Vector3(4.2, 2.6, 2), -PI * 0.5)
	_p(Vector3(8.0, 0.15, 1.6), Vector3(0, 0.1, 12.8), teak)
	_model("yacht", Vector3(40, -0.4, -30), 30.0, 0.4, "res://art3d/free/")
	_light(Vector3(0, 4.5, 3), Color("#cfe0ff"), 1.4, 14.0)
	_light(Vector3(0, 3.0, 10), Color("#ffd9a0"), 1.0, 8.0)
	_light(Vector3(0, 3.2, -10), Color("#ffd9a0"), 0.8, 7.0)
	_anchor("start", Vector3(0, 1.8, 8))
	_anchor("boss", Vector3(0, 1.8, -0.5))
	_anchor("bow", Vector3(0, 1.8, -11))
	_anchor("stern", Vector3(0, 1.8, 9))
	_anchor("boat", Vector3(10, 0, 14))
	_flush()


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
