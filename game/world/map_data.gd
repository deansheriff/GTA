class_name MapData
extends RefCounted
## The whole tropical-island Lagos (D-007, D-008), built deterministically from data/map/lagos.json.
## CPU side only (no rendering), so it runs in headless tests.

const CELL := 64
const CHUNK := 16 # cells per streaming chunk (1024 px)

enum S { SEA, LAGOON, BEACH, GROUND, WALK, GUTTER, ROAD, BRIDGE }

const GUTTER_W := 10.0
const WALK_W := 34.0

## Footprints (cells) and wall heights for each painted building.
const CATALOG := {
	"canteen": { "size": Vector2i(4, 2), "h": 52.0 },
	"pos-shop": { "size": Vector2i(3, 2), "h": 52.0 },
	"provision-store": { "size": Vector2i(3, 2), "h": 52.0 },
	"bungalow": { "size": Vector2i(5, 3), "h": 58.0 },
	"two-storey": { "size": Vector2i(5, 3), "h": 96.0 },
	"island-cottage": { "size": Vector2i(3, 2), "h": 52.0 },
	"fisher-hut": { "size": Vector2i(3, 2), "h": 48.0 },
	"beach-bar": { "size": Vector2i(5, 3), "h": 58.0 },
}
## Props that block movement (umbrellas and beach umbrellas you can walk under).
const SOLID_PROPS := ["pole", "transformer", "generator", "kiosk", "tyres", "mango", "palm", "palm-cluster", "drum-chairs", "orange-tray", "canoe", "nets", "fish-baskets", "coconut-cart"]

var cols := 0
var rows := 0
var world_px := Vector2.ZERO
var surface := PackedByteArray()
var district := PackedByteArray() # index into districts (255 = none)
var blocked := PackedByteArray()
var occupied := PackedByteArray() # building footprints (for placement only)
var coast_dist := PackedFloat32Array() # cells to the nearest water (land) or land (water)

var districts: Array = [] # [{id, name, center(px), buildings:{}, props:{}, density}]
var roads: Array = [] # [{id, class, width, speed, points: PackedVector2Array}]
var road_nodes := {} # name -> Vector2 px
var road_graph := {} # node name -> Array[node name]
var buildings: Array[Layout.BuildingSpec] = []
var props: Array[Layout.PropSpec] = []
var landmarks := {} # id -> {name, district, pos(px), kind}
var chunks := {} # Vector2i -> {"buildings": [], "props": []}
var player_start := Vector2.ZERO
var danfo_start := Vector2.ZERO
var land_polys: Array[PackedVector2Array] = []
var lagoon_poly := PackedVector2Array()

var _road_bins := {} # Vector2i bin -> Array[int] segment indices
var _segments: Array = [] # [{a, b, half, road}]
const BIN := 8 # cells per road-lookup bin

static var _shared: MapData


static func shared() -> MapData:
	if _shared == null:
		_shared = MapData.new()
		_shared.load_file("res://data/map/lagos.json")
	return _shared


func load_file(path: String) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	cols = int(data["size"][0])
	rows = int(data["size"][1])
	world_px = Vector2(cols, rows) * CELL
	for k in data["land"]:
		land_polys.append(_poly(data["land"][k]))
	lagoon_poly = _poly(data["lagoon"])
	for n in data["nodes"]:
		road_nodes[n] = _cellpx(data["nodes"][n])
	var classes: Dictionary = data["road_classes"]
	for r in data["roads"]:
		var cls: Dictionary = classes[r["class"]]
		var pts := PackedVector2Array()
		for n in r["nodes"]:
			pts.append(road_nodes[n])
		roads.append({ "id": r["id"], "class": r["class"], "width": float(cls["width"]), "speed": float(cls["speed"]), "points": pts, "nodes": r["nodes"] })
		for i in r["nodes"].size() - 1:
			_link(r["nodes"][i], r["nodes"][i + 1])
	for d in data["districts"]:
		districts.append({ "id": d["id"], "name": d["name"], "center": _cellpx(d["center"]), "buildings": d["buildings"], "props": d["props"], "density": float(d["density"]) })
	_build_segments()
	_build_cells()
	_build_coast_distance()
	_place_landmarks(data["landmarks"])
	_place_roadside()
	_fill_districts()
	_place_props(data)
	player_start = _cellpx(data["start"]["player"])
	danfo_start = _cellpx(data["start"]["danfo"])
	_index_chunks()


# ---------- queries ----------

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


func surface_at(p: Vector2) -> int:
	var c := cell_of(p)
	return surface[c.y * cols + c.x] if in_bounds(c) else S.SEA


func is_blocked(p: Vector2) -> bool:
	var c := cell_of(p)
	return blocked[c.y * cols + c.x] == 1 if in_bounds(c) else true


func is_water(s: int) -> bool:
	return s == S.SEA or s == S.LAGOON


func is_roadlike(s: int) -> bool:
	return s == S.ROAD or s == S.BRIDGE


func district_at(p: Vector2) -> Dictionary:
	var c := cell_of(p)
	if not in_bounds(c):
		return {}
	var i := district[c.y * cols + c.x]
	return districts[i] if i < districts.size() else {}


func block_cell(c: Vector2i) -> void:
	if in_bounds(c):
		blocked[c.y * cols + c.x] = 1


## Exact surface at a point (sub-cell), used for driving speed and spawning.
func fine_surface(p: Vector2) -> int:
	var land := _is_land(p)
	var d := _road_distance(p)
	var half: float = d.y
	if d.x < half:
		return S.ROAD if land else S.BRIDGE
	if not land:
		return S.LAGOON if Geometry2D.is_point_in_polygon(p, lagoon_poly) else S.SEA
	if d.x < half + GUTTER_W:
		return S.GUTTER
	if d.x < half + GUTTER_W + WALK_W:
		return S.WALK
	return S.GROUND


# ---------- building the grid ----------

func _cellpx(v: Array) -> Vector2:
	return Vector2(float(v[0]) * CELL, float(v[1]) * CELL)


func _poly(arr: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for v in arr:
		p.append(_cellpx(v))
	return p


func _link(a: String, b: String) -> void:
	if not road_graph.has(a): road_graph[a] = []
	if not road_graph.has(b): road_graph[b] = []
	if not (road_graph[a] as Array).has(b): road_graph[a].append(b)
	if not (road_graph[b] as Array).has(a): road_graph[b].append(a)


func _is_land(p: Vector2) -> bool:
	for poly in land_polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


func _build_segments() -> void:
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var pts: PackedVector2Array = r["points"]
		var half: float = r["width"] * 0.5
		for i in pts.size() - 1:
			var si := _segments.size()
			_segments.append({ "a": pts[i], "b": pts[i + 1], "half": half, "road": ri })
			var reach := half + GUTTER_W + WALK_W + CELL
			var lo := Vector2(minf(pts[i].x, pts[i + 1].x), minf(pts[i].y, pts[i + 1].y)) - Vector2(reach, reach)
			var hi := Vector2(maxf(pts[i].x, pts[i + 1].x), maxf(pts[i].y, pts[i + 1].y)) + Vector2(reach, reach)
			for by in range(int(lo.y / (BIN * CELL)), int(hi.y / (BIN * CELL)) + 1):
				for bx in range(int(lo.x / (BIN * CELL)), int(hi.x / (BIN * CELL)) + 1):
					var key := Vector2i(bx, by)
					if not _road_bins.has(key): _road_bins[key] = []
					_road_bins[key].append(si)


## Returns Vector2(distance to nearest road centreline, that road's half-width).
func _road_distance(p: Vector2) -> Vector2:
	var key := Vector2i(int(floor(p.x / (BIN * CELL))), int(floor(p.y / (BIN * CELL))))
	var best := Vector2(INF, 0.0)
	for si in _road_bins.get(key, []):
		var s: Dictionary = _segments[si]
		var q := Geometry2D.get_closest_point_to_segment(p, s["a"], s["b"])
		var d: float = p.distance_to(q) - float(s["half"])
		if d < best.x - best.y:
			best = Vector2(p.distance_to(q), s["half"])
	return best


func _build_cells() -> void:
	var n := cols * rows
	surface.resize(n)
	district.resize(n)
	blocked.resize(n)
	occupied.resize(n)
	blocked.fill(0)
	occupied.fill(0)
	for y in rows:
		for x in cols:
			var i := y * cols + x
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) * CELL
			var s := fine_surface(p)
			surface[i] = s
			if is_water(s):
				blocked[i] = 1
			var best := 255
			var bd := INF
			if not is_water(s):
				for di in districts.size():
					var dd: float = p.distance_squared_to(districts[di]["center"])
					if dd < bd:
						bd = dd
						best = di
			district[i] = best


## Breadth-first distance (in cells) between land and water; land within ~2 cells of open water is beach.
func _build_coast_distance() -> void:
	var n := cols * rows
	coast_dist.resize(n)
	coast_dist.fill(999.0)
	var queue: Array[int] = []
	for i in n:
		var w := is_water(surface[i])
		for d in [1, -1, cols, -cols]:
			var j: int = i + d
			if j >= 0 and j < n and is_water(surface[j]) != w:
				coast_dist[i] = 0.5
				queue.append(i)
				break
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var w := is_water(surface[i])
		for d in [1, -1, cols, -cols]:
			var j: int = i + d
			if j < 0 or j >= n or is_water(surface[j]) != w:
				continue
			if coast_dist[j] > coast_dist[i] + 1.0:
				coast_dist[j] = coast_dist[i] + 1.0
				queue.append(j)
	for i in n:
		if surface[i] == S.GROUND and coast_dist[i] <= 2.0:
			surface[i] = S.BEACH


# ---------- placement ----------

func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func _pick(weights: Dictionary, r: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := r.randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return weights.keys()[0]


## Try to place a building with its front-left ground corner at cell `c` (footprint grows up/right).
func _try_building(art: String, front_left: Vector2i, seed: int, margin := 1) -> Layout.BuildingSpec:
	if not CATALOG.has(art):
		return null
	var size: Vector2i = CATALOG[art]["size"]
	var top_left := Vector2i(front_left.x, front_left.y - size.y + 1)
	for y in range(top_left.y - margin, top_left.y + size.y + margin):
		for x in range(top_left.x - margin, top_left.x + size.x + margin):
			var c := Vector2i(x, y)
			if not in_bounds(c):
				return null
			var i := y * cols + x
			if occupied[i] == 1:
				return null
			var inside := x >= top_left.x and x < top_left.x + size.x and y >= top_left.y and y < top_left.y + size.y
			if inside and surface[i] != S.GROUND and surface[i] != S.BEACH:
				return null
	var b := Layout.BuildingSpec.new()
	b.cell = top_left
	b.size = size
	b.height = CATALOG[art]["h"]
	b.art = art
	b.wall = Layout.WALLS[seed % Layout.WALLS.size()]
	b.sign_text = ""
	b.seed = seed
	b.generator = seed % 4 == 0
	for y in range(top_left.y, top_left.y + size.y):
		for x in range(top_left.x, top_left.x + size.x):
			occupied[y * cols + x] = 1
			blocked[y * cols + x] = 1
	buildings.append(b)
	return b


func _place_landmarks(list: Array) -> void:
	for l in list:
		var cell := Vector2i(int(l["cell"][0]), int(l["cell"][1]))
		var pos := (Vector2(cell) + Vector2(0.5, 1.0)) * CELL
		landmarks[l["id"]] = { "name": l["name"], "district": l["district"], "pos": pos, "kind": l["kind"] }
		if CATALOG.has(l["kind"]):
			# The authored cell is a hint: roads and walkways often run through it, so search the
			# nearest free lot (closest first) instead of silently dropping the landmark's building.
			var b: Layout.BuildingSpec = null
			for r in 7:
				for dy in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if b == null and maxi(absi(dx), absi(dy)) == r:
							b = _try_building(l["kind"], cell + Vector2i(dx, dy), hash(l["id"]) & 0xffff, 0)
			if b:
				var fp := b.footprint()
				cell = Vector2i(int(fp.position.x / CELL), int(fp.end.y / CELL) - 1) # front-left cell
				b.sign_text = l["name"]
				b.landmark = l["id"]
				landmarks[l["id"]]["pos"] = Vector2(b.footprint().get_center().x, b.footprint().end.y + 24)
		# Keep a clear square in front of every landmark for missions.
		for y in range(cell.y + 1, cell.y + 3):
			for x in range(cell.x - 1, cell.x + 3):
				if in_bounds(Vector2i(x, y)):
					occupied[y * cols + x] = 1


## Buildings line both sides of every road, fronts facing the street where possible.
func _place_roadside() -> void:
	var seed := 1000
	for s in _segments:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var dir := (b - a).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var offset: float = s["half"] + GUTTER_W + WALK_W + 20.0
		var length := a.distance_to(b)
		var r := _rng(int(a.x * 31 + a.y * 17 + b.x))
		var t := 80.0
		while t < length - 80.0:
			for side in [-1.0, 1.0]:
				seed += 1
				var anchor: Vector2 = a + dir * t + normal * offset * float(side)
				var dist := district_at(anchor)
				if dist.is_empty() or r.randf() > float(dist["density"]):
					continue
				var art := _pick(dist["buildings"], r)
				var size: Vector2i = CATALOG.get(art, CATALOG["canteen"])["size"]
				var c := cell_of(anchor)
				# Above the road: front edge on the near side; below: building starts just past the walkway.
				var front := Vector2i(c.x - size.x / 2, c.y if normal.y * side < 0.0 else c.y + size.y - 1)
				if absf(dir.y) > 0.7: # roughly vertical road: buildings to the left/right
					front = Vector2i(c.x if side * normal.x > 0.0 else c.x - size.x + 1, c.y + size.y / 2)
				_try_building(art, front, seed)
			t += r.randf_range(240.0, 360.0)


## Interior blocks: more buildings away from the roads, leaving alleys.
func _fill_districts() -> void:
	var r := _rng(4242)
	var seed := 50000
	for y in range(2, rows - 2, 3):
		for x in range(2, cols - 2, 4):
			var c := Vector2i(x + r.randi_range(-1, 1), y + r.randi_range(-1, 1))
			if not in_bounds(c) or surface[c.y * cols + c.x] != S.GROUND:
				continue
			var dist := district_at(Vector2(c) * CELL)
			if dist.is_empty() or r.randf() > float(dist["density"]) * 0.55:
				continue
			seed += 1
			_try_building(_pick(dist["buildings"], r), c, seed)


func _place_props(data: Dictionary) -> void:
	var r := _rng(777)
	var seed := 90000
	# Street furniture along walkways: poles at intervals, umbrellas and kiosks by district taste.
	for s in _segments:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var dir := (b - a).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var off: float = s["half"] + GUTTER_W + WALK_W * 0.55
		var length := a.distance_to(b)
		var t := 60.0
		var k := 0
		while t < length - 60.0:
			for side in [-1.0, 1.0]:
				var p: Vector2 = a + dir * t + normal * off * float(side)
				var sf := surface_at(p)
				if sf != S.WALK and sf != S.GUTTER and sf != S.GROUND:
					continue
				if occupied[cell_of(p).y * cols + cell_of(p).x] == 1:
					continue
				seed += 1
				var kind := ""
				if k % 4 == 0 and side > 0.0:
					kind = "pole"
				else:
					var dist := district_at(p)
					if dist.is_empty() or r.randf() > 0.45:
						continue
					var pick := _pick(dist["props"], r)
					kind = pick if pick in ["umbrella", "kiosk", "orange-tray"] else ""
				if kind != "":
					_add_prop(kind, p, seed)
			k += 1
			t += r.randf_range(150.0, 230.0)
	# Yards and open ground: trees, generators, tyres by district.
	for y in range(1, rows - 1, 2):
		for x in range(1, cols - 1, 2):
			var i := y * cols + x
			if occupied[i] == 1 or blocked[i] == 1 or r.randf() > 0.16:
				continue
			var p := (Vector2(x, y) + Vector2(r.randf(), r.randf())) * CELL
			seed += 1
			if surface[i] == S.GROUND:
				var dist := district_at(p)
				if not dist.is_empty():
					_add_prop(_pick(dist["props"], r), p, seed)
			elif surface[i] == S.BEACH and r.randf() < 0.85:
				if r.randf() < 0.12:
					var b := _try_building(_pick(data["beach_buildings"], r), Vector2i(x, y), seed)
					if b:
						continue
				_add_prop(_pick(data["beach_props"], r), p, seed)


func _add_prop(kind: String, p: Vector2, seed: int) -> void:
	var c := cell_of(p)
	if not in_bounds(c) or occupied[c.y * cols + c.x] == 1:
		return
	var sp := Layout.PropSpec.new()
	sp.kind = kind
	sp.pos = p
	sp.seed = seed
	props.append(sp)
	if kind in SOLID_PROPS:
		occupied[c.y * cols + c.x] = 1
		blocked[c.y * cols + c.x] = 1


func _index_chunks() -> void:
	for b in buildings:
		var k := Vector2i(b.cell.x / CHUNK, (b.cell.y + b.size.y - 1) / CHUNK)
		_chunk(k)["buildings"].append(b)
	for p in props:
		var c := cell_of(p.pos)
		_chunk(Vector2i(c.x / CHUNK, c.y / CHUNK))["props"].append(p)


func _chunk(k: Vector2i) -> Dictionary:
	if not chunks.has(k):
		chunks[k] = { "buildings": [], "props": [] }
	return chunks[k]
