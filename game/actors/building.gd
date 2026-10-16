extends Node2D
## Placeholder Lagos shop/house in top-down 3/4: a corrugated zinc roof seen from above plus the
## front (south) wall with windows, burglar-proof bars, door and a painted signboard.
## The node sits at the footprint's front-left ground corner so y-sorting works.

var spec: Layout.BuildingSpec
var _art: Sprite2D


func setup(s: Layout.BuildingSpec) -> void:
	spec = s
	var fp := s.footprint()
	position = Vector2(fp.position.x, fp.end.y)
	var t := Art.tex(_art_for(s))
	if t:
		# Painted building: fit its width to the footprint (+ eaves), front wall on the ground line.
		_art = Sprite2D.new()
		_art.texture = t
		var sc := (fp.size.x + 14.0) / float(t.get_width())
		_art.scale = Vector2(sc, sc)
		_art.position = Vector2(fp.size.x * 0.5, -t.get_height() * sc * 0.5 + 6.0)
		add_child(_art)


## Painted variants (M13) of the same footprint, chosen per building so streets don't repeat:
## a third of canteens are bukkas; POS shops and provision stores that don't sell to you are
## salons and chemists; a third of two-storeys are blocks of flats.
static func look_of(s: Layout.BuildingSpec) -> String:
	match s.art:
		"canteen":
			return "bukka" if s.seed % 3 == 0 and Art.tex("buildings/bukka.png") else s.art
		"pos-shop":
			return "salon" if s.seed % 2 == 1 and Art.tex("buildings/salon.png") else s.art
		"provision-store":
			return "chemist" if s.seed % 2 == 1 and Art.tex("buildings/chemist.png") else s.art
		"two-storey":
			return "flats" if s.seed % 3 == 0 and s.landmark == "" and Art.tex("buildings/flats.png") else s.art
	return s.art


const SIGNS := {
	"bukka": ["Iya Basira Bukka", "Correct Amala Spot", "Mama Put Delight"],
	"canteen": ["Mama Nkem Kitchen", "Belle Full Canteen", "Sweet Soup Spot"],
	"salon": ["Blessed Hands Salon", "Glamour Touch Unisex", "Fine Girl Hair Palace"],
	"chemist": ["Divine Favour Chemist", "Good Health Medicine Store", "Healing Hands Chemist"],
	"pos-shop": ["God's Time POS & Recharge", "Konnect Phone Centre", "No Network No Wahala POS"],
	"provision-store": ["Ola & Sons Provisions", "Everyday Supermart", "Mama Nkem Provisions"],
}
const BOARD_COLOURS := [Color("#2f6f99"), Color("#a8382c"), Color("#2f8a52"), Color("#76418a"), Color("#c8862a")]


## The roadside signboard: the landmark's name, or a fictional shop name for this kind of shop.
func sign_name() -> String:
	if spec.sign_text != "":
		return spec.sign_text
	var names: Array = SIGNS.get(look_of(spec), [])
	return names[spec.seed % names.size()] if not names.is_empty() and spec.seed % 3 != 2 else ""


static func _art_for(s: Layout.BuildingSpec) -> String:
	if s.art != "":
		return "buildings/%s.png" % look_of(s)
	if s.size.x >= 5 or s.height >= 96:
		return "buildings/two-storey.png"
	if s.size.x == 4:
		return "buildings/bungalow.png" if s.seed % 2 == 0 else "buildings/two-storey.png"
	return ["buildings/canteen.png", "buildings/pos-shop.png", "buildings/provision-store.png"][s.seed % 3]


## A painted board on a pole at the front-left corner, as shops put up by the road.
func _draw_roadside_sign(r: RandomNumberGenerator) -> void:
	var text := sign_name()
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var fs := 12
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var bw := tw + 18.0
	var base := Vector2(-6, 18)
	var top := base + Vector2(0, -58)
	draw_line(base, top, Color("#3a2a1c"), 3.0)
	draw_line(base + Vector2(bw - 6.0, 0), top + Vector2(bw - 6.0, 0), Color("#3a2a1c"), 3.0)
	var board := Rect2(top + Vector2(-6, -24), Vector2(bw, 26))
	var col: Color = BOARD_COLOURS[spec.seed % BOARD_COLOURS.size()]
	draw_rect(Rect2(board.position + Vector2(3, 3), board.size), Color(0, 0, 0, 0.25))
	draw_rect(board, col.darkened(0.15))
	draw_rect(board, Ink.COLOR, false, 2.0)
	draw_string(font, board.position + Vector2(9, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#f1e6c8"))
	r.randf() # keep the rest of the drawing's random sequence stable


func _draw() -> void:
	var w := float(spec.size.x * Layout.CELL)
	var d := float(spec.size.y * Layout.CELL)
	var hk := spec.height * Layout.HEIGHT_K
	var r := Ink.rng(spec.seed)

	if _art:
		# Soft contact shadow along the front and right side; the painting carries its own shading.
		Ink.shadow(self, Vector2(w * 0.5, 4), Vector2(w * 0.56, 16), 0.32)
		_draw_roadside_sign(r)
		return
	# Ground shadow falling to the bottom-right.
	draw_colored_polygon(PackedVector2Array([
		Vector2(w, -d - hk * 0.2), Vector2(w + hk * 0.55, -d + hk * 0.15), Vector2(w + hk * 0.55, hk * 0.22), Vector2(8, hk * 0.22), Vector2(0, 0), Vector2(w, 0)
	]), Color(0.05, 0.04, 0.03, 0.3))

	# Front wall.
	var wall := Rect2(0, -hk, w, hk)
	Ink.rect(self, wall, spec.wall, 0.0)
	draw_rect(Rect2(0, -hk * 0.18, w, hk * 0.18), spec.wall.darkened(0.25)) # rain-splash band
	draw_rect(Rect2(0, -hk, w, hk * 0.16), Color(0.05, 0.04, 0.03, 0.35)) # eave shadow
	# Windows with burglar-proof bars, and a door.
	var door_x := w * (0.3 + r.randf() * 0.4)
	var x := 14.0
	while x + 26.0 < w - 8.0:
		if absf(x + 13.0 - door_x) > 26.0:
			var win := Rect2(x, -hk * 0.72, 26, hk * 0.38)
			Ink.rect(self, win, Color("#26303f"), 2.0)
			for k in range(1, 4):
				draw_line(Vector2(x + 26.0 * k / 4.0, win.position.y), Vector2(x + 26.0 * k / 4.0, win.end.y), Ink.COLOR, 1.4)
		x += 40.0
	Ink.rect(self, Rect2(door_x - 12, -hk * 0.66, 24, hk * 0.66), Color("#5b3a26"), 2.2)
	if spec.sign_text != "":
		var board := Rect2(w * 0.12, -hk * 0.98, w * 0.76, maxf(12.0, hk * 0.22))
		var board_col: Color = [Color("#a8382c"), Color("#2f6f99"), Color("#2f8a52"), Color("#c8862a")][spec.seed % 4]
		Ink.rect(self, board, board_col, 2.0)
		var font := ThemeDB.fallback_font
		var fs := int(clampf(board.size.y * 0.62, 8.0, 14.0))
		draw_string(font, Vector2(board.position.x, board.position.y + board.size.y * 0.5 + fs * 0.36), spec.sign_text, HORIZONTAL_ALIGNMENT_CENTER, board.size.x, fs, Color("#f1e6c8"))
	draw_polyline(PackedVector2Array([Vector2(0, -hk), Vector2(0, 0), Vector2(w, 0), Vector2(w, -hk)]), Ink.COLOR, Ink.W, true)

	# Corrugated zinc gable roof seen from above: back slope lighter, front slope darker.
	var o := 6.0
	var top := -d - hk - o
	var bottom := -hk + o
	var ridge := lerpf(top, bottom, 0.46)
	# Weathered zinc in a few tones: rusty red, sage-grey, ochre-grey, plain grey.
	var zinc: Color = [Color("#9a5a3c"), Color("#7f8c80"), Color("#9b8a66"), Color("#8c9396")][spec.seed % 4].lerp(Color("#9a7a5c"), r.randf() * 0.25)
	Ink.poly(self, PackedVector2Array([Vector2(-o, top), Vector2(w + o, top), Vector2(w + o, ridge), Vector2(-o, ridge)]), zinc.lightened(0.08), 0.0)
	Ink.poly(self, PackedVector2Array([Vector2(-o, ridge), Vector2(w + o, ridge), Vector2(w + o, bottom), Vector2(-o, bottom)]), zinc.darkened(0.12), 0.0)
	var cx := -o + 5.0
	while cx < w + o:
		draw_line(Vector2(cx, top + 1), Vector2(cx, bottom - 1), Color(0.1, 0.1, 0.12, 0.22), 1.2)
		cx += 6.0
	for i in 3 + spec.size.x * spec.size.y / 2:
		var rp := Vector2(r.randf_range(0, w), r.randf_range(top + 6, bottom - 6))
		draw_colored_polygon(Ink.ellipse_points(rp, Vector2(r.randf_range(6, 20), r.randf_range(4, 11)), 14, r.randf() * PI), Color(0.54, 0.31, 0.17, r.randf_range(0.25, 0.5)))
	draw_line(Vector2(-o, ridge), Vector2(w + o, ridge), Ink.COLOR, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(-o, top), Vector2(w + o, top), Vector2(w + o, bottom), Vector2(-o, bottom), Vector2(-o, top)]), Ink.COLOR, Ink.W + 0.6, true)
