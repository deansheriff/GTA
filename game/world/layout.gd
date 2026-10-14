class_name Layout
extends RefCounted
## M0 style-test map: one Yaba junction, top-down 3/4 (decision D-004).
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
	for p in w.props:
		if p.kind != "umbrella":
			w.block_cell(int(p.pos.x / CELL), int(p.pos.y / CELL))

	w.danfo_start = Vector2(8 * CELL, 15 * CELL - 4)
	w.player_start = Vector2(10.5 * CELL, 16.6 * CELL)
	return w
