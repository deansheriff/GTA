class_name Radio
extends Node
## Danfo radio (M9 #6). Tap the Radio button while driving to change station:
##   Gbedu 98.1 (street jams), Highlife Classics 89.5, Miracle FM 101.5 (talk: callers and
##   jokes), Traffic Gist 92.3 (live reports from the game: checkpoints, floods, Task Force
##   patrols, today's event, and warnings about hazards on YOUR route when a GPS route is set).
## All stations, hosts and callers are fictional.

var host: StreetHost
var main: Node2D
var _line_t := 3.0
var _line_i := 0
var _hazards: Array = [] # {kind, pos, t}


func setup(h: StreetHost) -> void:
	host = h
	main = h.main


func stations() -> Array:
	return Street.db["radio"]["stations"]


func current() -> Dictionary:
	return stations()[Street.radio] if Street.radio >= 0 and Street.radio < stations().size() else {}


func station_short() -> String:
	var s := current()
	return "Off" if s.is_empty() else String(s["name"]).get_slice(" ", 0)


func next_station() -> void:
	Street.radio += 1
	if Street.radio >= stations().size():
		Street.radio = -1
	Sound.sfx("static")
	_line_t = 1.0
	var s := current()
	if not s.is_empty():
		var key := "heard_" + String(s["id"])
		if not Street.counters.has(key):
			Street.counters[key] = 1
			Street.count("stations_heard")
		host.ticker("Radio: %s" % s["name"], 3.0)


## What the music player should play: the station's loop while driving, otherwise "" (default).
func track() -> String:
	if main.mode != "driving" or main.story.interior.active:
		return ""
	var s := current()
	return "" if s.is_empty() else String(s["music"])


func report_checkpoint(kind: String, pos: Vector2) -> void:
	_hazards.append({ "kind": "checkpoint:" + kind, "pos": pos, "t": Time.get_ticks_msec() })


func tick(dt: float) -> void:
	_hazards = _hazards.filter(func(h: Dictionary) -> bool: return Time.get_ticks_msec() - int(h["t"]) < 120000)
	var s := current()
	if s.is_empty() or main.mode != "driving" or main.story.paused_by_story():
		return
	_line_t -= dt
	if _line_t > 0.0:
		return
	_line_t = randf_range(12.0, 18.0)
	if s["id"] == "traffic":
		host.ticker("%s: %s" % [s["name"], traffic_report()], 9.0)
		return
	var lines: Array = s["lines"]
	if lines.is_empty():
		return
	_line_i = (_line_i + 1) % lines.size()
	host.ticker("%s · %s" % [s["name"], lines[_line_i]], 8.0)


func _district(p: Vector2) -> String:
	return String(main.map.district_at(p).get("name", "the island"))


## A live report built from what is actually happening on the roads.
func traffic_report() -> String:
	var items := []
	for h: Dictionary in _hazards:
		var kind := String(h["kind"]).get_slice(":", 1)
		var who: String = { "marshal": "Road Marshals", "agbero": "agberos", "task": "Task Force" }.get(kind, "a checkpoint")
		items.append({ "pos": h["pos"], "text": "%s checkpoint for %s road" % [who, _district(h["pos"])] })
	if host.weather.flood > 0.3:
		for s: Vector2 in host.weather.spots.slice(0, 3):
			items.append({ "pos": s, "text": "flood near %s" % _district(s) })
	for v: Dictionary in host.heat.vans:
		items.append({ "pos": (v["node"] as Node2D).position, "text": "Task Force van dey patrol %s" % _district((v["node"] as Node2D).position) })
	var ev := host.life.daily_event()
	if not ev.is_empty() and main.map.landmarks.has(ev["where"]):
		items.append({ "pos": main.map.landmarks[ev["where"]]["pos"], "text": "%s for %s" % [ev["name"], _district(main.map.landmarks[ev["where"]]["pos"])] })
	if items.is_empty():
		return "Roads dey free small. Na miracle! Drive with sense."
	# Your route first.
	var route: PackedVector2Array = main.route
	if route.size() > 1:
		for it: Dictionary in items:
			for i in range(0, route.size() - 1):
				if Geometry2D.get_closest_point_to_segment(it["pos"], route[i], route[i + 1]).distance_to(it["pos"]) < 400.0:
					return "ON YOUR ROUTE: %s. Find another way!" % it["text"]
	var parts := items.slice(0, 3).map(func(it: Dictionary) -> String: return it["text"])
	return "Hold your heart: " + "; ".join(PackedStringArray(parts)) + "."
