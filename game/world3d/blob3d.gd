class_name Blob3D
extends RefCounted
## Contact shadows (D-032): a soft dark oval on the ground under people, vehicles, stalls and props,
## so they sit on the street instead of floating. The Compatibility renderer has no decals and the
## sun's shadows are short-range on phones, so a cheap textured quad does the job everywhere.

static var _mat: StandardMaterial3D
static var _quad: QuadMesh


static func material() -> StandardMaterial3D:
	if _mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.62))
		g.set_color(1, Color(0, 0, 0, 0.0))
		g.add_point(0.55, Color(0, 0, 0, 0.38))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_mat = StandardMaterial3D.new()
		_mat.albedo_texture = t
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_mat.render_priority = -1
	return _mat


static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
		_quad.orientation = PlaneMesh.FACE_Y
		_quad.material = material() # on the mesh, so overlays (hit flashes) always have a base
	return _quad


## A shadow under `parent`, size (x, z) metres, just above its feet.
static func add(parent: Node3D, size: Vector2, y := 0.03) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = quad()
	mi.scale = Vector3(size.x, 1.0, size.y)
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Blob"
	parent.add_child(mi)
	return mi
