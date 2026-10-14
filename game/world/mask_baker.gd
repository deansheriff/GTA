class_name MaskBaker
extends Node
## Renders the map's coastline and road network ONCE into small textures for the terrain shader
## and the minimap (GPU, so a full city costs a single frame at load):
##   land_tex  (16 px/texel): R = land, G = lagoon water
##   road_tex  (8 px/texel):  R = 0.33 walkway, 0.66 gutter, 1.0 road (bridges: road over water)
##   dist_tex  (64 px/texel, CPU): R = distance from land to water, G = water to land

const LAND_SCALE := 1.0 / 16.0
const ROAD_SCALE := 1.0 / 8.0

var land_tex: Texture2D
var road_tex: Texture2D
var dist_tex: ImageTexture
var _map: MapData


func bake(map: MapData) -> void:
	_map = map
	land_tex = _viewport(map.world_px * LAND_SCALE, LAND_SCALE, _draw_land)
	road_tex = _viewport(map.world_px * ROAD_SCALE, ROAD_SCALE, _draw_roads)
	var img := Image.create(map.cols, map.rows, false, Image.FORMAT_RG8)
	for y in map.rows:
		for x in map.cols:
			var i := y * map.cols + x
			var d := map.coast_dist[i]
			var water := map.is_water(map.surface[i])
			img.set_pixel(x, y, Color(0.0 if water else clampf(d / 4.0, 0.0, 1.0), clampf(d / 6.0, 0.0, 1.0) if water else 0.0, 0.0))
	dist_tex = ImageTexture.create_from_image(img)


func _viewport(size: Vector2, scale: float, painter: Callable) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(ceili(size.x), ceili(size.y))
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = vp.size
	vp.add_child(bg)
	var drawer := Node2D.new()
	drawer.scale = Vector2(scale, scale)
	drawer.draw.connect(func() -> void: painter.call(drawer))
	vp.add_child(drawer)
	add_child(vp)
	return vp.get_texture()


func _draw_land(c: Node2D) -> void:
	c.draw_colored_polygon(_map.lagoon_poly, Color(0, 1, 0))
	for poly in _map.land_polys:
		c.draw_colored_polygon(poly, Color(1, 0, 0))


func _draw_roads(c: Node2D) -> void:
	# All walkways, then all gutters, then all asphalt, so crossings stay clean.
	for layer in [[MapData.GUTTER_W + MapData.WALK_W, 0.33], [MapData.GUTTER_W, 0.66], [0.0, 1.0]]:
		var col := Color(layer[1], 0, 0)
		for r in _map.roads:
			var w: float = r["width"] + 2.0 * float(layer[0])
			var pts: PackedVector2Array = r["points"]
			for i in pts.size() - 1:
				c.draw_line(pts[i], pts[i + 1], col, w)
			for p in pts:
				c.draw_circle(p, w * 0.5, col) # round joints at bends and junctions
