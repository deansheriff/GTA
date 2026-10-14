class_name JobRunner
extends Node
## Runs one free-roam hustle at a time: danfo runs, deliveries and POS shifts.
## The phone's Hustle app lists today's offers; accepting sets a waypoint to the start.

signal offers_changed
signal job_changed(active: Dictionary)
signal message(text: String)

var map: MapData
var db := {}
var offers: Array = [] # today's gigs: {type, id, name, from, to, pay, ...}
var active := {} # current job state; empty when idle
var _rng := RandomNumberGenerator.new()
var _offer_day := -1


func setup(m: MapData) -> void:
	map = m
	db = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	Clock.day_changed.connect(func(_d: int) -> void: refresh_offers())
	refresh_offers()


## New gigs every in-game morning: two danfo runs, two deliveries and a POS shift.
func refresh_offers() -> void:
	if _offer_day == Clock.day():
		return
	_offer_day = Clock.day()
	_rng.seed = Clock.day() * 7919
	offers.clear()
	var routes: Array = db["danfo_routes"].duplicate()
	routes.shuffle()
	for r in routes.slice(0, 2):
		offers.append({ "type": "danfo", "id": r["id"], "name": "Danfo: " + r["name"], "from": r["from"], "to": r["to"], "fare": r["fare"], "pay": int(r["fare"]) * 12 })
	var dels: Array = db["deliveries"].duplicate()
	dels.shuffle()
	for d in dels.slice(0, 2):
		var o: Dictionary = d.duplicate()
		o["type"] = "delivery"
		offers.append(o)
	var parks := map.props.filter(func(p: Layout.PropSpec) -> bool: return p.kind == "umbrella")
	if not parks.is_empty():
		var u: Layout.PropSpec = parks[_rng.randi() % parks.size()]
		offers.append({ "type": "pos", "id": "pos-shift", "name": "POS shift at a roadside umbrella", "pos": u.pos, "pay": 2000 })
	offers_changed.emit()


func start_pos(o: Dictionary) -> Vector2:
	if o.has("pos"):
		return o["pos"]
	return map.landmarks[o["from"]]["pos"]


func end_pos(o: Dictionary) -> Vector2:
	return map.landmarks[o["to"]]["pos"] if o.has("to") else start_pos(o)


func accept(o: Dictionary) -> void:
	if o.get("type", "") == "danfo" and Life.hero != "tunde":
		message.emit("Only Tunde drives Baba God Dey. Switch to him for danfo runs.")
		return
	active = o.duplicate()
	active["stage"] = "go_to_start"
	job_changed.emit(active)
	message.emit("Head to the start: %s" % _place_name(o.get("from", "")))


func cancel() -> void:
	if not active.is_empty():
		message.emit("Hustle cancelled.")
	active = {}
	job_changed.emit(active)


func _place_name(id: String) -> String:
	return map.landmarks[id]["name"] if map.landmarks.has(id) else "the stand"


func target() -> Vector2:
	if active.is_empty():
		return Vector2.INF
	return start_pos(active) if active["stage"] == "go_to_start" else end_pos(active)


## Called every frame by the game. `mode` is walking/driving; `stuck` = danfo crawling in traffic.
func tick(delta: float, focus: Vector2, mode: String, stuck: bool) -> void:
	if active.is_empty():
		return
	match active["type"]:
		"danfo":
			_tick_danfo(delta, focus, mode, stuck)
		"delivery":
			_tick_delivery(delta, focus)
		"pos":
			if active["stage"] == "go_to_start" and focus.distance_to(start_pos(active)) < 120.0:
				active["stage"] = "shift"
				job_changed.emit(active) # the HUD opens the POS mini-game


func _tick_danfo(delta: float, focus: Vector2, mode: String, stuck: bool) -> void:
	match active["stage"]:
		"go_to_start":
			if mode == "driving" and focus.distance_to(start_pos(active)) < 220.0:
				var n := _rng.randi_range(8, 14)
				active["passengers"] = n
				active["patience"] = 100.0
				active["stage"] = "driving"
				message.emit("%d passengers enter. Conductor: \"%s! Enter with your change!\"" % [n, map.landmarks[active["to"]]["district"].capitalize()])
				job_changed.emit(active)
			elif mode != "driving" and focus.distance_to(start_pos(active)) < 220.0 and not active.get("hinted", false):
				active["hinted"] = true
				message.emit("You need the danfo for this one.")
		"driving":
			if stuck:
				active["patience"] = float(active["patience"]) - delta * 6.0
				Life.stats["bp"] = minf(100.0, float(Life.stats["bp"]) + delta * 2.0)
				if float(active["patience"]) < 40.0 and int(active["passengers"]) > 3 and _rng.randf() < delta * 0.15:
					active["passengers"] = int(active["passengers"]) - 1
					message.emit(["\"Driver, drop me here, I go trek!\"", "\"This go-slow no be my portion.\"", "\"I don late for work because of you!\""][_rng.randi() % 3])
			else:
				active["patience"] = minf(100.0, float(active["patience"]) + delta * 2.0)
			if mode == "driving" and focus.distance_to(end_pos(active)) < 240.0:
				var fares := int(active["passengers"]) * int(active["fare"])
				var agbero := int(fares * 0.1)
				Life.earn(fares - agbero, "Danfo fares: %s" % active["name"])
				Life.add_xp("driving", 25 + int(active["passengers"]) * 2)
				message.emit("Fares: ₦%s. Agbero took ₦%s \"for the boys\". Baba God dey!" % [Life.fmt_naira(fares), Life.fmt_naira(agbero)])
				active = {}
				job_changed.emit(active)


func _tick_delivery(delta: float, focus: Vector2) -> void:
	match active["stage"]:
		"go_to_start":
			if focus.distance_to(start_pos(active)) < 140.0:
				active["stage"] = "deliver"
				active["deadline"] = Clock.minutes + int(active["minutes"])
				message.emit("Picked up. %s Deliver before %02d:%02d." % [active.get("line", ""), (int(active["deadline"]) % 1440) / 60, int(active["deadline"]) % 60])
				job_changed.emit(active)
		"deliver":
			if focus.distance_to(end_pos(active)) < 140.0:
				var late := Clock.minutes > int(active["deadline"])
				var pay := int(active["pay"]) / (2 if late else 1)
				Life.earn(pay, "Delivery: %s" % active["name"])
				Life.add_xp("hustle", 20)
				message.emit("Delivered%s. ₦%s." % [" (late, half pay)" if late else "", Life.fmt_naira(pay)])
				active = {}
				job_changed.emit(active)


## POS mini-game result reported by the HUD.
func finish_pos(served: int, failed: int) -> void:
	var c: Array = db["pos"]["commission"]
	var earned := 0
	for i in served:
		earned += _rng.randi_range(int(c[0]), int(c[1]))
	Life.earn(earned, "POS shift commission")
	Life.add_xp("haggling", served * 4)
	message.emit("Shift done: %d served, %d lost to \"network\". ₦%s commission." % [served, failed, Life.fmt_naira(earned)])
	active = {}
	job_changed.emit(active)


func to_dict() -> Dictionary:
	return { "active": active, "offer_day": _offer_day }


func from_dict(d: Dictionary) -> void:
	active = d.get("active", {})
	if active.has("pos") and active["pos"] is String:
		active["pos"] = str_to_var(active["pos"])
	job_changed.emit(active)
