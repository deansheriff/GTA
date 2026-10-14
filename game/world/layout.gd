class_name Layout
extends RefCounted
## M0 style-test map: Ayo Town, the market junction at the heart of Ayo Island (decisions D-004, D-007).
## Layout sits on an invisible square grid (CELL px). The ground is one painted surface (terrain shader).

const CELL := 64
const COLS := 40
const ROWS := 30
const WORLD := Vector2(COLS * CELL, ROWS * CELL)

## Road bands in world px: the main road runs east-west, the cross street north-south.
const MAIN_Y0 := 14 * CELL
const MAIN_Y1 := 16 * CELL
const CROSS_X0 := 19 * CELL
const CROSS_X1 := 21 * CELL
const GUTTER := 10.0
const WALK := 34.0

## Height foreshortening for anything that stands up (walls, poles, people).
const HEIGHT_K := 0.62

## The island: an irregular oval coastline. The SAME formula runs in shaders/terrain.gdshader.
const ISLAND_CENTER := Vector2(1280, 940)
const ISLAND_RADII := Vector2(1150, 820)
const BEACH_START := 0.86 # island radius where land turns to beach
const ROAD_END := 0.9 # roads stop where the sand gets deep


## 0 at the centre, 1.0 at the waterline, >1 out at sea.
static func island_r(p: Vector2) -> float:
	var d := (p - ISLAND_CENTER) / ISLAND_RADII
	var a := atan2(d.y, d.x)
	return d.length() + 0.05 * sin(a * 5.0 + 1.3) + 0.035 * sin(a * 9.0 + 0.4) + 0.02 * sin(a * 13.0 + 2.1)

const WALLS := [Color("#c9a66b"), Color("#86a58a"), Color("#c08566"), Color("#8f9cbf"), Color("#d6c49c"), Color("#b78aa6")]
const SIGNS := ["AUNTY BOSS KITCHEN", "KONFAM POS", "GIDI BARBING SALON", "9BARS RECHARGE", "GOD'S TIME REPAIRS", "MIRACLE FM 99.9", "TAP-TAP POS", "NO CONDITION IS PERMANENT"]


class BuildingSpec:
	var cell: Vector2i
	var size: Vector2i # in cells; the south wall is the visible front
	var height: float
	var wall: Color
	var sign_text: String
	var seed: int
	var generator: bool
	var art := "" # painted building key (MapData.CATALOG); "" = pick by size
	var landmark := "" # story landmark id, if any

	func footprint() -> Rect2:
		return Rect2(Vector2(cell) * CELL, Vector2(size) * CELL)


class PropSpec:
	var kind: String # umbrella, pole, transformer, generator, mango, palm, kiosk, tyres
	var pos: Vector2
	var seed: int


class WorldData:
	var buildings: Array[BuildingSpec] = []
	var props: Array[PropSpec] = []
	var blocked := PackedByteArray()
	var player_start := Vector2.ZERO
	var danfo_start := Vector2.ZERO

	func is_blocked(p: Vector2) -> bool:
		var c := int(floor(p.x / CELL))
		var r := int(floor(p.y / CELL))
		if c < 0 or r < 0 or c >= COLS or r >= ROWS:
			return true
		return blocked[r * COLS + c] == 1

	func block_cell(c: int, r: int) -> void:
		if c >= 0 and r >= 0 and c < COLS and r < ROWS:
			blocked[r * COLS + c] = 1


## What is painted at a ground point (before noise picks grass, dirt or laterite).
static func surface_at(p: Vector2) -> String:
	var r := island_r(p)
	if r > 1.0:
		return "sea"
	if r > ROAD_END:
		return "beach"
	var town := _town_surface(p)
	if town == "ground" and r > BEACH_START:
		return "beach"
	return town


static func _town_surface(p: Vector2) -> String:
	var in_main := p.y >= MAIN_Y0 and p.y < MAIN_Y1
	var in_cross := p.x >= CROSS_X0 and p.x < CROSS_X1
	if in_main or in_cross:
		return "road"
	var d_main := MAIN_Y0 - p.y if p.y < MAIN_Y0 else p.y - MAIN_Y1
	var d_cross := CROSS_X0 - p.x if p.x < CROSS_X0 else p.x - CROSS_X1
	var d := minf(d_main, d_cross)
	var near_junction := p.x > CROSS_X0 - WALK - GUTTER and p.x < CROSS_X1 + WALK + GUTTER and p.y > MAIN_Y0 - WALK - GUTTER and p.y < MAIN_Y1 + WALK + GUTTER
	if d < GUTTER and not near_junction:
		return "gutter"
	if d < GUTTER + WALK:
		return "walk"
	return "ground"


static func build_yaba() -> WorldData:
	var w := WorldData.new()
	w.blocked.resize(COLS * ROWS)
	w.blocked.fill(0)
	# [col, row, w, d, wall height] — the row above the main road fronts onto it.
	var lots := [
		[3, 9, 4, 3, 70], [8, 10, 3, 2, 52], [12, 9, 4, 3, 96], [23, 9, 4, 3, 58], [28, 10, 3, 2, 52], [32, 8, 5, 4, 110],
		[3, 18, 4, 3, 58], [9, 18, 3, 3, 70], [13, 19, 3, 2, 52], [23, 18, 4, 3, 84], [29, 19, 3, 2, 52], [33, 18, 4, 3, 64],
		[4, 2, 4, 3, 64], [11, 3, 3, 2, 52], [25, 2, 4, 3, 70], [4, 24, 5, 3, 90], [24, 24, 4, 3, 58], [31, 25, 4, 2, 52],
	]
	for i in lots.size():
		var l: Array = lots[i]
		# Keep only lots fully on solid land (not on the beach or in the sea).
		var fp := Rect2(Vector2(l[0], l[1]) * CELL, Vector2(l[2], l[3]) * CELL)
		if maxf(maxf(island_r(fp.position), island_r(fp.end)), maxf(island_r(Vector2(fp.end.x, fp.position.y)), island_r(Vector2(fp.position.x, fp.end.y)))) > BEACH_START - 0.02:
			continue
		var b := BuildingSpec.new()
		b.cell = Vector2i(l[0], l[1])
		b.size = Vector2i(l[2], l[3])
		b.height = float(l[4])
		b.wall = WALLS[i % WALLS.size()]
		b.sign_text = "" if i % 4 == 3 else SIGNS[i % SIGNS.size()]
		b.seed = 100 + i * 31
		b.generator = i % 3 == 0
		w.buildings.append(b)
		for r in range(b.cell.y, b.cell.y + b.size.y):
			for c in range(b.cell.x, b.cell.x + b.size.x):
				w.block_cell(c, r)

	var add := func(kind: String, c: float, r: float, seed: int) -> void:
		var p := PropSpec.new()
		p.kind = kind
		p.pos = Vector2((c + 0.5) * CELL, (r + 0.5) * CELL)
		p.seed = seed
		w.props.append(p)
	var umbrellas := [[7, 13], [17, 13], [22, 16], [27, 13], [11, 16], [34, 16]]
	for i in umbrellas.size():
		add.call("umbrella", umbrellas[i][0], umbrellas[i][1], i)
	add.call("kiosk", 15, 13, 50)
	add.call("kiosk", 30, 16, 51)
	for c in range(2, COLS, 6):
		add.call("transformer" if c == 26 else "pole", c, 13, c)
	for r in range(3, ROWS, 6):
		if r < 12 or r > 17:
			add.call("pole", 21, r, 60 + r)
	var gi := 0
	for b in w.buildings:
		if b.generator:
			add.call("generator", b.cell.x + b.size.x, b.cell.y + b.size.y - 1, 300 + gi)
			gi += 1
	var trees := [[1, 6], [9, 6], [17, 4], [30, 4], [38, 12], [1, 21], [16, 23], [21, 26], [37, 22], [12, 27]]
	for i in trees.size():
		add.call("palm" if i % 3 == 0 else "mango", trees[i][0], trees[i][1], 400 + i)
	add.call("tyres", 8, 21, 500)
	add.call("tyres", 19, 7, 501)
	# Drop props that ended up in the sea; town props on the beach are fine.
	w.props = w.props.filter(func(p: PropSpec) -> bool: return island_r(p.pos) < 0.98)
	# Beach life: canoes, nets, palm-thatch umbrellas, a coconut seller, fishermen's huts, a beach bar.
	_place_beach(w)
	for p in w.props:
		if p.kind != "umbrella" and p.kind != "beach-umbrella":
			w.block_cell(int(p.pos.x / CELL), int(p.pos.y / CELL))
	# The sea is solid for walking and driving.
	for r in ROWS:
		for c in COLS:
			if island_r((Vector2(c, r) + Vector2(0.5, 0.5)) * CELL) > 1.0:
				w.block_cell(c, r)

	w.danfo_start = Vector2(9 * CELL, 15 * CELL - 4)
	w.player_start = Vector2(10.5 * CELL, 16.6 * CELL)
	return w


## Walk around the coast and place beach things on the sand band, with buildings on bigger gaps.
static func _place_beach(w: WorldData) -> void:
	var kinds := ["canoe", "palm-cluster", "nets", "beach-umbrella", "coconut-cart", "canoe", "fish-baskets", "palm-cluster"]
	var k := 0
	var steps := 36
	for i in steps:
		var a := TAU * float(i) / float(steps) + 0.07
		# Find the beach mid-line (r ≈ 0.93) along this direction.
		var dir := Vector2(cos(a), sin(a))
		var pos := ISLAND_CENTER
		for s in 120:
			pos = ISLAND_CENTER + dir * ISLAND_RADII * (s / 100.0)
			if island_r(pos) >= 0.93:
				break
		if pos.x < CELL or pos.y < CELL or pos.x > WORLD.x - CELL or pos.y > WORLD.y - CELL:
			continue
		if _town_surface(pos) == "road":
			continue # keep the road ends clear
		var p := PropSpec.new()
		if i % 9 == 4:
			p.kind = "beach-bar" if i < 18 else "fisher-hut"
		elif i % 9 == 7:
			p.kind = "island-cottage"
		else:
			p.kind = kinds[k % kinds.size()]
			k += 1
		p.pos = pos
		p.seed = 700 + i
		w.props.append(p)
