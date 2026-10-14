extends Node
## Autoload "Life": everything about the player's life that gets saved — needs, money, inventory,
## skills, story flags and relationships. Game rules live here; UI and world only read and request.

signal changed
signal money_changed(amount: int, delta: int, reason: String)
signal skill_up(skill: String, level: int)
signal toast(text: String)

const NEEDS := ["hunger", "energy", "fun", "social", "hygiene"]
## Points lost per game hour.
const DECAY := { "hunger": 4.5, "energy": 3.2, "fun": 2.5, "social": 2.0, "hygiene": 2.2 }
const SKILLS := ["driving", "cooking", "haggling", "filming", "charisma", "composure", "hustle"]

var hero := "tunde"
var needs := { "hunger": 80.0, "energy": 85.0, "fun": 60.0, "social": 60.0, "hygiene": 75.0 }
var money := 15000 # ₦
var ledger: Array = [] # last 100 entries: {t, delta, reason}
var inventory := {} # item id -> count
var skills_xp := {} # skill -> xp
var flags := {} # story / world flags
var relationships := { "tunde-ngozi": 50, "tunde-kc": 45, "ngozi-kc": 60 }
var home := "tunde-depot" # landmark id where this hero sleeps
var stats := { "bp": 20.0, "aura": 40.0, "hype": 100.0, "battery": 60.0 } # hero stats (M3 uses them)
var items_db := {}


func _ready() -> void:
	items_db = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	Clock.minute_passed.connect(_on_minute)


func _on_minute(_m: int) -> void:
	for n in NEEDS:
		needs[n] = clampf(needs[n] - DECAY[n] / 60.0, 0.0, 100.0)
	changed.emit()


# ---------- needs and mood ----------

func mood() -> float:
	var total := 0.0
	for n in NEEDS:
		total += needs[n]
	return total / NEEDS.size()


func mood_label() -> String:
	var m := mood()
	if needs["hunger"] < 12.0:
		return "Belle dey cry"
	if needs["energy"] < 12.0:
		return "Tired die"
	if m > 75.0:
		return "Enjoyment"
	if m > 50.0:
		return "I dey kampe"
	if m > 30.0:
		return "Manageable"
	return "Wahala"


## Walking/working pace multiplier from energy and hunger.
func pace_factor() -> float:
	var f := 1.0
	if needs["energy"] < 15.0:
		f *= 0.75
	if needs["hunger"] < 10.0:
		f *= 0.85
	return f


func restore(need: String, amount: float) -> void:
	needs[need] = clampf(needs[need] + amount, 0.0, 100.0)
	changed.emit()


# ---------- money ----------

func can_afford(amount: int) -> bool:
	return money >= amount


func earn(amount: int, reason: String) -> void:
	_money(amount, reason)


func spend(amount: int, reason: String) -> bool:
	if amount > money:
		toast.emit("Money no reach. You get ₦%s." % fmt_naira(money))
		return false
	_money(-amount, reason)
	return true


func _money(delta: int, reason: String) -> void:
	money += delta
	ledger.push_front({ "t": Clock.minutes, "delta": delta, "reason": reason })
	if ledger.size() > 100:
		ledger.resize(100)
	money_changed.emit(money, delta, reason)
	changed.emit()


static func fmt_naira(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# ---------- items ----------

func item(id: String) -> Dictionary:
	return items_db.get("items", {}).get(id, {})


func add_item(id: String, count := 1) -> void:
	inventory[id] = int(inventory.get(id, 0)) + count
	changed.emit()


func has_item(id: String) -> bool:
	return int(inventory.get(id, 0)) > 0


## Buy from a vendor. Food is eaten on the spot unless `keep`.
func buy(id: String, keep := false) -> bool:
	var it := item(id)
	if it.is_empty():
		return false
	var price := int(it["price"])
	# Haggling skill shaves a little off (market banter is a skill).
	price = int(round(price * (1.0 - 0.02 * level("haggling"))))
	if not spend(price, "Bought %s" % it["name"]):
		return false
	add_xp("haggling", 2)
	if keep or not it.has("effects"):
		add_item(id)
	else:
		use_effects(it)
	return true


func use_item(id: String) -> bool:
	if not has_item(id):
		return false
	inventory[id] = int(inventory[id]) - 1
	if int(inventory[id]) <= 0:
		inventory.erase(id)
	use_effects(item(id))
	return true


func use_effects(it: Dictionary) -> void:
	for need in it.get("effects", {}):
		if needs.has(need):
			restore(need, float(it["effects"][need]))
		elif stats.has(need):
			stats[need] = clampf(float(stats[need]) + float(it["effects"][need]), 0.0, 1000.0)
	if it.has("line"):
		toast.emit(it["line"])
	changed.emit()


# ---------- skills ----------

## XP to reach the next level: 100 × level^1.5 (Story deliverable 3 §1).
static func xp_for(level_: int) -> int:
	return int(round(100.0 * pow(float(level_), 1.5)))


func level(skill: String) -> int:
	var xp := int(skills_xp.get(skill, 0))
	var lv := 1
	while lv < 10 and xp >= xp_for(lv):
		xp -= xp_for(lv)
		lv += 1
	return lv


func add_xp(skill: String, amount: int) -> void:
	var before := level(skill)
	skills_xp[skill] = int(skills_xp.get(skill, 0)) + amount
	var after := level(skill)
	if after > before:
		skill_up.emit(skill, after)
		toast.emit("%s level %d!" % [skill.capitalize(), after])
	changed.emit()


# ---------- sleep ----------

## Sleep until 06:30 (or 8 hours if it's daytime). Restores energy; time passes; hunger drops.
func sleep() -> int:
	var now := Clock.minutes % 1440
	var target := 6 * 60 + 30
	var dur := (target - now + 1440) % 1440
	if dur < 120 or dur > 11 * 60:
		dur = 8 * 60
	Clock.advance(dur)
	needs["energy"] = 100.0
	for n in ["hunger", "fun", "social", "hygiene"]:
		needs[n] = clampf(needs[n] - DECAY[n] * dur / 60.0 * 0.4, 5.0, 100.0)
	changed.emit()
	return dur


# ---------- save ----------

func to_dict() -> Dictionary:
	return {
		"hero": hero, "needs": needs, "money": money, "ledger": ledger.slice(0, 30), "inventory": inventory,
		"skills_xp": skills_xp, "flags": flags, "relationships": relationships, "home": home, "stats": stats,
	}


func from_dict(d: Dictionary) -> void:
	hero = String(d.get("hero", hero))
	for k in d.get("needs", {}):
		needs[k] = float(d["needs"][k])
	money = int(d.get("money", money))
	ledger = d.get("ledger", [])
	inventory = d.get("inventory", {})
	skills_xp = d.get("skills_xp", {})
	flags = d.get("flags", {})
	for k in d.get("relationships", {}):
		relationships[k] = int(d["relationships"][k])
	home = String(d.get("home", home))
	for k in d.get("stats", {}):
		stats[k] = float(d["stats"][k])
	changed.emit()
