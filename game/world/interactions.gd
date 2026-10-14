class_name Interactions
extends RefCounted
## Things you can walk up to and use: vendors (buildings and stalls), your home bed.
## Built once from MapData; queried a few times a second for the nearest one.

const RADIUS := 95.0

var points: Array = [] # [{pos, kind, label, vendor?, landmark?}]
var _bins := {}
const BIN_PX := 512.0


func build(map: MapData, vendors: Dictionary) -> void:
	points.clear()
	_bins.clear()
	for b in map.buildings:
		var fp := b.footprint()
		var door := Vector2(fp.get_center().x, fp.end.y + 26)
		if b.landmark != "":
			continue # landmarks get their own interactions below
		if vendors.has(b.art) and b.seed % 2 == 0: # not every building is open for business
			_add({ "pos": door, "kind": "vendor", "vendor": b.art, "label": vendors[b.art]["title"] })
	for p in map.props:
		if vendors.has(p.kind):
			_add({ "pos": p.pos + Vector2(0, 18), "kind": "vendor", "vendor": p.kind, "label": vendors[p.kind]["title"] })
	for id in map.landmarks:
		var l: Dictionary = map.landmarks[id]
		var kind: String = l["kind"]
		if id in ["tunde-depot", "aunty-boss-kitchen", "kc-room"]:
			_add({ "pos": l["pos"], "kind": "home", "landmark": id, "label": "Sleep (%s)" % l["name"] })
		if vendors.has(kind):
			_add({ "pos": l["pos"] + Vector2(40, 0), "kind": "vendor", "vendor": kind, "label": "%s" % l["name"] })


func _add(p: Dictionary) -> void:
	points.append(p)
	var k := Vector2i(int(p["pos"].x / BIN_PX), int(p["pos"].y / BIN_PX))
	if not _bins.has(k):
		_bins[k] = []
	_bins[k].append(p)


func nearest(pos: Vector2, home_landmark: String) -> Dictionary:
	var best := {}
	var bd := RADIUS
	var c := Vector2i(int(pos.x / BIN_PX), int(pos.y / BIN_PX))
	for y in range(c.y - 1, c.y + 2):
		for x in range(c.x - 1, c.x + 2):
			for p in _bins.get(Vector2i(x, y), []):
				if p["kind"] == "home" and p["landmark"] != home_landmark:
					continue # you can only sleep at your own place
				var d: float = pos.distance_to(p["pos"])
				if d < bd:
					bd = d
					best = p
	return best
