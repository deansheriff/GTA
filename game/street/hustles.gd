class_name Hustles
extends Node
## More side hustles (M10 #8), offered in the phone's Hustle app next to danfo runs, deliveries
## and POS shifts:
##  - Night suya stand at Mallam Suya (7 pm – 2 am): the grill mini-game, paid per stick sold.
##  - KekeGo ride-hailing: rent a keke at Ojota, take three riders where they want to go.
##  - Okada deliveries: rent an okada at Oshodi market, race three parcels across town.
## Renting swaps your vehicle for the keke or okada (your danfo waits where you left it).

const TYPES := ["suya", "keke", "okada"]

var host: StreetHost
var main: Node2D
var _saved := {} # the danfo while you ride a rented keke/okada: {pos, heading}
var _rng := RandomNumberGenerator.new()


func setup(h: StreetHost) -> void:
	host = h
	main = h.main
	_rng.randomize()
	main.jobs.offers_changed.connect(_add_offers)
	_add_offers()


func build_points(_m: MapData) -> Array:
	return []


func prompt_for(_p: Dictionary) -> String:
	return ""


func use(_p: Dictionary) -> void:
	pass


func renting() -> bool:
	return not _saved.is_empty()


func _lm(id: String) -> Vector2:
	return main.map.landmarks[id]["pos"] if main.map.landmarks.has(id) else Vector2.INF


func _add_offers() -> void:
	var jobs: JobRunner = main.jobs
	if jobs.offers.any(func(o: Dictionary) -> bool: return o.get("type") in TYPES):
		return
	var db: Dictionary = Street.db
	if _lm("mallam-suya") != Vector2.INF:
		jobs.offers.append({ "type": "suya", "id": "suya", "name": "Night suya stand at Mallam Suya (7pm–2am)", "pos": _lm("mallam-suya"), "pay": int(db["suya"]["price"]) * int(db["suya"]["customers"]) * 2 / 5 })
	if _lm("ojota-bus-stop") != Vector2.INF:
		jobs.offers.append({ "type": "keke", "id": "keke", "name": "KekeGo ride-hailing (rent a keke at Ojota, ₦%s)" % Life.fmt_naira(int(db["keke"]["rent"])), "pos": _lm("ojota-bus-stop"), "pay": int(db["keke"]["fare"]) * 3 * 2 })
	if _lm("oshodi-market") != Vector2.INF:
		jobs.offers.append({ "type": "okada", "id": "okada", "name": "Okada parcel deliveries (rent at Oshodi market, ₦%s)" % Life.fmt_naira(int(db["okada"]["rent"])), "pos": _lm("oshodi-market"), "pay": int(db["okada"]["pay"]) * 3 })


func _end(text: String) -> void:
	if renting():
		_return_vehicle()
	main.jobs.active = {}
	main.jobs.job_changed.emit(main.jobs.active)
	if text != "":
		main.hud.toast(text)


func tick(_dt: float) -> void:
	var job: Dictionary = main.jobs.active
	if job.is_empty() or not job.get("type") in TYPES:
		if renting() and job.is_empty():
			_return_vehicle()
		return
	if main.story.mission_running():
		_end("Hustle paused for the story.")
		return
	var focus: Vector2 = main.danfo.position if main.mode == "driving" else main.player.position
	match job.get("stage"):
		"go_to_start":
			if focus.distance_to(job["pos"]) < 160.0:
				match job["type"]:
					"suya":
						_suya()
					"keke", "okada":
						_rent(job)
		"ride":
			var dest: Vector2 = job["stops"][int(job["i"])]
			if main.mode == "driving" and focus.distance_to(dest) < 220.0:
				_arrive(job)


# ---------- suya ----------

func _suya() -> void:
	var h := Clock.hour()
	if h < 19 and h >= 2:
		main.jobs.active["stage"] = "wait"
		_end("Mallam opens at 7pm. Come back at night.")
		return
	main.jobs.active["stage"] = "grill"
	var db: Dictionary = Street.db["suya"]
	var res: Dictionary = await main.story.story_minigame("suya", { "orders": int(db["customers"]), "seconds": 75.0 })
	var served := int(res.get("served", 0))
	var pay := served * int(int(db["price"]) * 0.4)
	if pay > 0:
		Life.earn(pay, "Suya stand commission")
	Life.add_xp("cooking", served * 5)
	Street.count("suya_sold", served)
	_end("Suya shift done: %d sticks sold, ₦%s for you. Mallam: \"You fit work!\"" % [served, Life.fmt_naira(pay)])


# ---------- keke / okada ----------

func _rent(job: Dictionary) -> void:
	var cfg: Dictionary = Street.db[job["type"]]
	if not Life.spend(int(cfg["rent"]), "%s rent" % job["type"].capitalize()):
		_end("Money no reach for the rent.")
		return
	var d: Node2D = main.danfo
	if main.mode == "driving":
		d.speed = 0.0
		main._enter_exit()
	_saved = { "pos": d.position, "heading": d.heading }
	d.set_kind(job["type"])
	d.refresh_art()
	d.set_paint(Color(0, 0, 0, 0))
	d.max_road = 320.0 if job["type"] == "keke" else 440.0
	d.position = main.player.position + Vector2(40, 0)
	d.speed = 0.0
	main.rented = true
	main._enter_exit()
	# Three stops across town.
	var ids: Array = main.map.landmarks.keys()
	ids.shuffle()
	var stops := []
	var from: Vector2 = job["pos"]
	for id: String in ids:
		var p: Vector2 = main.map.landmarks[id]["pos"]
		if p.distance_to(from) > 1400.0 and stops.size() < 3:
			stops.append(p)
			from = p
	job["stops"] = stops
	job["i"] = 0
	job["stage"] = "ride"
	job["deadline"] = Clock.minutes + int(cfg.get("minutes", 9999))
	main._set_waypoint(stops[0])
	main.hud.toast("KekeGo: rider 1 wants %s." % _place(stops[0]) if job["type"] == "keke" else "Parcel 1 → %s. Move!" % _place(stops[0]))


func _place(p: Vector2) -> String:
	return String(main.map.district_at(p).get("name", "town"))


func _arrive(job: Dictionary) -> void:
	var cfg: Dictionary = Street.db[job["type"]]
	var pay := 0
	if job["type"] == "keke":
		pay = int(int(cfg["fare"]) * Street.fare_k)
		Life.earn(pay, "KekeGo fare")
	else:
		var late: bool = Clock.minutes > int(job["deadline"])
		pay = int(cfg["pay"]) / (2 if late else 1)
		Life.earn(pay, "Okada delivery")
		job["deadline"] = Clock.minutes + int(cfg["minutes"])
	Sound.sfx("cash")
	Life.add_xp("driving", 12)
	job["i"] = int(job["i"]) + 1
	if int(job["i"]) >= (job["stops"] as Array).size():
		_end("Shift done! ₦%s on the last one. Vehicle returned." % Life.fmt_naira(pay))
		return
	var next: Vector2 = job["stops"][int(job["i"])]
	main._set_waypoint(next)
	main.hud.toast("₦%s. Next: %s." % [Life.fmt_naira(pay), _place(next)])


func _return_vehicle() -> void:
	var d: Node2D = main.danfo
	if main.mode == "driving":
		d.speed = 0.0
		main._enter_exit()
	d.position = _saved.get("pos", d.position)
	d.heading = float(_saved.get("heading", d.heading))
	_saved = {}
	main.rented = false
	host.garage.reapply_current() # back to whatever you were driving before the rental
	main._set_waypoint(Vector2.INF)
