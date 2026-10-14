class_name Streamer
extends Node2D
## Streams buildings, props, street lights and wires in 1024 px chunks around the camera.
## Only nearby chunks exist as nodes; work is spread over frames so moving never hitches.

const BuildingScript := preload("res://actors/building.gd")
const PropScript := preload("res://actors/prop.gd")
const MAX_NODES_PER_FRAME := 40

var map: MapData
var painted_mat: Material
var lights: LightLayer
var radius := 1 # extra chunks around the visible area (Settings draw_distance)

var _active := {} # Vector2i -> ChunkNode
var _queue: Array = [] # pending [chunk_key, kind, spec]
var _night := false
var _nepa_on := true
var _simple_lights := false
var _effects := true
var _check_t := 0.0


class ChunkNode:
	var root: Node2D
	var light_handles: Array[int] = []
	var props: Array[Node2D] = []
	var buildings: Array[Node2D] = []


func _init() -> void:
	y_sort_enabled = true


func setup(m: MapData, mat: Material, light_layer: LightLayer) -> void:
	map = m
	painted_mat = mat
	lights = light_layer


func set_lighting(night: bool, nepa_on: bool, effects: bool) -> void:
	_night = night
	_nepa_on = nepa_on
	_effects = effects
	for k in _active:
		for p in (_active[k] as ChunkNode).props:
			p.set_generator_running(not _nepa_on and _effects)


func active_buildings() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for k in _active:
		out.append_array((_active[k] as ChunkNode).buildings)
	return out


## Call every frame with the camera's visible world rect.
func update_view(view: Rect2, delta: float) -> void:
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.2
		_refresh(view)
	var budget := MAX_NODES_PER_FRAME
	while budget > 0 and not _queue.is_empty():
		var job: Array = _queue.pop_front()
		if _active.has(job[0]):
			_spawn(_active[job[0]], job[1], job[2])
		budget -= 1


func _refresh(view: Rect2) -> void:
	var cpx := float(MapData.CHUNK * MapData.CELL)
	var lo := Vector2i(int(floor(view.position.x / cpx)) - radius, int(floor(view.position.y / cpx)) - radius)
	var hi := Vector2i(int(floor(view.end.x / cpx)) + radius, int(floor(view.end.y / cpx)) + radius)
	var want := {}
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			want[Vector2i(x, y)] = true
	for k in _active.keys():
		if not want.has(k):
			var old: ChunkNode = _active[k]
			for h in old.light_handles:
				lights.remove_light(h)
			old.root.queue_free()
			_active.erase(k)
	# Nearest chunks first.
	var centre := view.get_center() / cpx
	var keys := want.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_squared_to(centre) < Vector2(b).distance_squared_to(centre))
	for k in keys:
		if _active.has(k) or not map.chunks.has(k):
			continue
		var cn := ChunkNode.new()
		cn.root = Node2D.new()
		cn.root.y_sort_enabled = true
		add_child(cn.root)
		_active[k] = cn
		var data: Dictionary = map.chunks[k]
		for b in data["buildings"]:
			_queue.append([k, "building", b])
		for p in data["props"]:
			_queue.append([k, "prop", p])
		_queue.append([k, "wires", null])


func _spawn(cn: ChunkNode, kind: String, spec: Variant) -> void:
	match kind:
		"building":
			var b: Node2D = BuildingScript.new()
			b.setup(spec)
			b.material = painted_mat
			cn.root.add_child(b)
			cn.buildings.append(b)
			var fp: Rect2 = spec.footprint()
			var door := Vector2(fp.get_center().x, fp.end.y + 18)
			if spec.generator:
				# Generator houses glow when NEPA is off; some windows glow when it's on.
				cn.light_handles.append(lights.add_light(door, 170.0, 0.9, true))
			if spec.seed % 3 == 0 or spec.landmark != "":
				cn.light_handles.append(lights.add_light(door, 130.0, 0.6, false))
		"prop":
			var p: Node2D = PropScript.new()
			p.setup(spec)
			p.material = painted_mat
			cn.root.add_child(p)
			cn.props.append(p)
			p.set_generator_running(not _nepa_on and _effects)
			if spec.kind == "pole" or spec.kind == "transformer":
				cn.light_handles.append(lights.add_light(spec.pos + Vector2(0, 10), 200.0, 0.85, false))
		"wires":
			var w := Node2D.new()
			w.z_index = 5
			w.draw.connect(func() -> void: _draw_wires(w, cn))
			cn.root.add_child(w)
			w.queue_redraw.call_deferred()


## Sagging wires between neighbouring poles of this chunk (and into the next one).
func _draw_wires(c: Node2D, cn: ChunkNode) -> void:
	var tops: Array[Vector2] = []
	for p in cn.props:
		if p.kind == "pole" or p.kind == "transformer":
			tops.append(p.position + p.wire_anchor())
	for a in tops:
		var best := Vector2.INF
		for b in tops:
			var dd := b - a
			var along := (absf(dd.y) < 50.0 and dd.x > 0.0) or (absf(dd.x) < 50.0 and dd.y > 0.0)
			if along and dd.length() > 100.0 and dd.length() < 360.0 and a.distance_to(b) < a.distance_to(best):
				best = b
		if best == Vector2.INF:
			continue
		for off in [-4.0, 0.0, 4.0]:
			var pts := PackedVector2Array()
			for k in 13:
				var t := k / 12.0
				pts.append(a.lerp(best, t) + Vector2(0, off + sin(t * PI) * 16.0))
			c.draw_polyline(pts, Color(0.1, 0.08, 0.07, 0.8), 1.4, true)
