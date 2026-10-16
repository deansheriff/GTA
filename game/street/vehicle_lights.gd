class_name VehicleLights
extends Node
## Night driving (M13): every vehicle on screen gets headlight beams and red tail lights, drawn
## into the night lighting buffer (world/light_layer.gd) so they light up the road around them.
## Only vehicles near the camera get lights; they're recycled as traffic comes and goes.

var host: StreetHost
var main: Node2D
var _cone: Texture2D
var _by_node := {} # instance id -> {node, head, tail}


func setup(h: StreetHost) -> void:
	host = h
	main = h.main
	_cone = _make_cone()


## A soft beam: bright at the lamp, widening and fading forward. Points right (+x).
static func _make_cone() -> Texture2D:
	var w := 128
	var hgt := 64
	var img := Image.create(w, hgt, false, Image.FORMAT_RGBA8)
	for x in w:
		var fx := float(x) / w
		var half := 6.0 + fx * (hgt * 0.5 - 6.0)
		for y in hgt:
			var dy := absf(y - hgt * 0.5)
			var edge := clampf((half - dy) / 8.0, 0.0, 1.0)
			var a := edge * (1.0 - fx) * (0.35 + 0.65 * (1.0 - fx))
			img.set_pixel(x, y, Color(1.0, 0.95, 0.8, a))
	return ImageTexture.create_from_image(img)


func tick(_dt: float) -> void:
	var lights: LightLayer = main.lights
	var on: bool = lights.is_night() and not main.story.interior.active
	var want := {}
	if on:
		var view: Rect2 = main._view_rect().grow(300.0)
		var nodes: Array = [main.danfo]
		for v in main.traffic.vehicles:
			nodes.append(v["node"])
		for v: Dictionary in host.heat.vans:
			nodes.append(v["node"])
		for n: Node2D in nodes:
			if is_instance_valid(n) and n.visible and view.has_point(n.position):
				want[n.get_instance_id()] = n
	# Drop lights for vehicles that left.
	for id in _by_node.keys():
		if not want.has(id):
			var e: Dictionary = _by_node[id]
			lights.remove_light(e["head"])
			lights.remove_light(e["tail"])
			_by_node.erase(id)
	for id in want:
		var n: Node2D = want[id]
		if not _by_node.has(id):
			_by_node[id] = { "head": lights.add_moving_light(_cone, Color(1.0, 0.95, 0.8, 0.85)), "tail": lights.add_moving_light(lights.radial_texture(), Color(1.0, 0.18, 0.1, 0.7)) }
		var e: Dictionary = _by_node[id]
		var fwd := Vector2.from_angle(n.heading)
		var half_len: float = float(n.LENGTH) * 0.5
		var reach: float = 260.0 if n.kind != "okada" else 170.0
		var width: float = float(n.WIDTH) * 2.2
		# The beam's lamp end sits on the bumper; the texture spans `reach` forward.
		lights.move_light(e["head"], n.position + fwd * (half_len + reach * 0.5), n.heading, Vector2(reach / 128.0, width / 64.0))
		var braking: bool = absf(float(n.speed)) < 20.0
		lights.move_light(e["tail"], n.position - fwd * (half_len + 4.0), n.heading, Vector2.ONE * (0.55 if braking else 0.38))
