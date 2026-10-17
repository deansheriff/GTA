extends Node
## Autoload "Street": the saved state of the street systems (M9–M11): the bus (fuel, damage,
## paint), Area heat, street reputation, achievements, fleet, home and generator, style, the
## Lagos Gist feed and daily events. Rules that only touch this state live here; the systems
## that act in the world are in game/street/.

signal changed
signal unlocked(id: String, title: String)
signal gist_posted(entry: Dictionary)

const MAX_HEAT := 5.0

var db := {}
# The bus.
var fuel := 85.0 # %
var damage := 0.0 # 0 = showroom, 100 = scrap
var paint := { "colour": "", "slogan": "Baba God Dey" }
var impounded := false
# Wahala and standing.
var heat := 0.0 # Area heat, 0–5 stars
var rep := 0.0 # street reputation, -100 to 100
var counters := {}
var achieved := {} # id -> day unlocked
# Owning things.
var fleet: Array = [] # [{id, name, slogan, colour, driver, condition, earned}]
var home_tier := 0
var generator := 0
var gen_fuel := 0.0 # litres in the home generator
var outfit := "street"
var outfits_owned := ["street"]
var phone := "basic"
var radio := 0 # station index, -1 = off
# Feed and events.
var gist_log: Array = [] # newest first: {t, kind, text}
var daily := {} # {day, id, stage, done}
var fleet_day := -1
# Vehicles (M14): what you're driving (the main vehicle node always wears this), cars parked
# around town (Baba God Dey is either `current` or parked), and the cars in your home garage.
const BABA := { "id": "baba", "kind": "danfo", "colour": "", "stolen": false, "fuel": 85.0, "damage": 0.0, "name": "Baba God Dey" }
var current := BABA.duplicate()
var parked: Array = [] # [{spec, x, y, h}]
var garage: Array = [] # [spec]
# Live (not saved): fares go up in the rain; crews that hold a route get a bonus.
var fare_k := 1.0


func _ready() -> void:
	db = JSON.parse_string(FileAccess.get_file_as_string("res://data/street.json"))
	SaveGame.extra_providers["street"] = to_dict
	SaveGame.extra_restorers["street"] = from_dict


# ---------- counters and achievements ----------

func count(key: String, n := 1) -> void:
	counters[key] = int(counters.get(key, 0)) + n
	_check(key)


## For "best so far" counters (e.g. highest heat, profit).
func record(key: String, value: int) -> void:
	if value > int(counters.get(key, 0)):
		counters[key] = value
		_check(key)


func _check(key: String) -> void:
	for a: Dictionary in db.get("achievements", []):
		if a["counter"] != key or achieved.has(a["id"]):
			continue
		if int(counters.get(key, 0)) >= int(a["goal"]):
			achieved[a["id"]] = Clock.day()
			unlocked.emit(a["id"], a["title"])
			post_gist("award", "%s unlocked \"%s\"." % [_me(), a["title"]])
	changed.emit()


func achievement_list() -> Array:
	var out := []
	for a: Dictionary in db.get("achievements", []):
		var e := a.duplicate()
		e["progress"] = mini(int(counters.get(a["counter"], 0)), int(a["goal"]))
		e["done"] = achieved.has(a["id"])
		out.append(e)
	return out


# ---------- heat and reputation ----------

func add_heat(amount: float) -> void:
	heat = clampf(heat + amount, 0.0, MAX_HEAT)
	record("heat_max", 1 if heat >= MAX_HEAT else 0)
	changed.emit()


func stars() -> int:
	return int(floor(heat + 0.001))


func add_rep(amount: float) -> void:
	rep = clampf(rep + amount, -100.0, 100.0)
	if rep >= 75.0:
		record("rep_legend", 1)
	changed.emit()


func rep_label() -> String:
	if rep >= 60.0:
		return "Street legend"
	if rep >= 25.0:
		return "Respected"
	if rep > -25.0:
		return "Nobody send you"
	if rep > -60.0:
		return "Known wahala"
	return "Area menace"


## Prices you get: respected people get small discounts, troublemakers pay "wahala tax".
func price_k() -> float:
	return clampf(1.0 - rep / 500.0, 0.85, 1.2)


# ---------- the bus ----------

## Top speed limit from damage and fuel (INF = no limit).
func bus_limit() -> float:
	if fuel <= 0.0:
		return 70.0 # sputtering on fumes
	if damage >= 85.0:
		return 160.0 # limping
	if damage >= 60.0:
		return 260.0
	return INF


func repair_cost(points: float, per_point: int) -> int:
	return int(ceil(points * per_point * price_k()))


func fuel_cost(percent: float, per_percent: int) -> int:
	return int(ceil(percent * per_percent * price_k()))


# ---------- the Lagos Gist feed ----------

func _me() -> String:
	return Net.player_name if Net.player_name != "" else Life.hero.capitalize()


func post_gist(kind: String, text: String) -> void:
	var e := { "t": Clock.minutes, "kind": kind, "text": text }
	gist_log.push_front(e)
	if gist_log.size() > 60:
		gist_log.pop_back()
	gist_posted.emit(e)


# ---------- style ----------

func outfit_look() -> Dictionary:
	for o: Dictionary in db.get("outfits", []):
		if o["id"] == outfit:
			return o["look"]
	return {}


func phone_info() -> Dictionary:
	for p: Dictionary in db.get("phones", []):
		if p["id"] == phone:
			return p
	return db["phones"][0]


func home_info() -> Dictionary:
	return db["home"][clampi(home_tier, 0, db["home"].size() - 1)]


func generator_info() -> Dictionary:
	return db["generators"][clampi(generator, 0, db["generators"].size() - 1)]


# ---------- save ----------

func to_dict() -> Dictionary:
	return {
		"fuel": fuel, "damage": damage, "paint": paint, "impounded": impounded, "heat": heat, "rep": rep,
		"counters": counters, "achieved": achieved, "fleet": fleet, "home_tier": home_tier,
		"generator": generator, "gen_fuel": gen_fuel, "outfit": outfit, "outfits_owned": outfits_owned,
		"phone": phone, "radio": radio, "current": current, "parked": parked, "garage": garage, "gist_log": gist_log.slice(0, 30), "daily": daily, "fleet_day": fleet_day,
	}


func from_dict(d: Dictionary) -> void:
	fuel = float(d.get("fuel", 85.0))
	damage = float(d.get("damage", 0.0))
	paint = d.get("paint", paint)
	impounded = bool(d.get("impounded", false))
	heat = float(d.get("heat", 0.0))
	rep = float(d.get("rep", 0.0))
	counters = d.get("counters", {})
	achieved = d.get("achieved", {})
	fleet = d.get("fleet", [])
	home_tier = int(d.get("home_tier", 0))
	generator = int(d.get("generator", 0))
	gen_fuel = float(d.get("gen_fuel", 0.0))
	outfit = String(d.get("outfit", "street"))
	outfits_owned = d.get("outfits_owned", ["street"])
	phone = String(d.get("phone", "basic"))
	radio = int(d.get("radio", 0))
	gist_log = d.get("gist_log", [])
	daily = d.get("daily", {})
	fleet_day = int(d.get("fleet_day", -1))
	current = d.get("current", BABA.duplicate())
	parked = d.get("parked", [])
	garage = d.get("garage", [])
	changed.emit()


func driving_baba() -> bool:
	return String(current.get("id", "baba")) == "baba"


func garage_slots() -> int:
	var slots: Array = db.get("vehicles", {}).get("garage_slots", [1, 2, 3, 5])
	return int(slots[clampi(home_tier, 0, slots.size() - 1)])


## New game: everything back to the start.
func reset() -> void:
	from_dict({})
