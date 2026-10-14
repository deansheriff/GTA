extends Node
## Autoload "Story": story progress for "Up NEPA!" (missions done, ability tiers, story money ₦s,
## relationships, per-hero state for switching). Mission scripts live in data/story/*.json and are
## run by MissionRunner; this node only remembers what happened.

signal progress_changed
signal hero_switched(hero: String)

const HEROES := ["tunde", "ngozi", "kc"]
const HERO_NAME := { "tunde": "Tunde", "ngozi": "Aunty Boss", "kc": "KC" }
const HERO_HOME := { "tunde": "tunde-depot", "ngozi": "aunty-boss-kitchen", "kc": "kc-room" }
const HERO_SHEET := { "tunde": "characters/tunde-walk.png", "ngozi": "characters/ngozi-walk.png", "kc": "characters/kc-walk.png" }

var missions := {} # id -> mission dictionary (data/story/missions.json)
var order: Array = [] # mission ids in story order
var dialogue := {} # id -> Array of lines
var cast := {} # id -> {name, portrait, sprite?, ped?}
var chats := {} # Family Meeting banks and off-screen events

var done := {} # mission id -> true
var current := "" # mission in progress ("" when free roaming)
var checkpoint := 0 # step index to resume `current` from
var story_money := 0 # ₦s, separate from free-roam money until the credits (Bible §9.7)
var tiers := {} # ability -> tier (0 = locked)
var switching := false # unlocked by P4
var heroes := {} # hero -> {pos: [x, y], needs: {}, away_since: minutes}
var diary_pages := 0
var evidence := 0


func _ready() -> void:
	load_data()


func load_data() -> void:
	var m: Dictionary = _json("res://data/story/missions.json")
	missions.clear()
	order.clear()
	for mission in m.get("missions", []):
		missions[mission["id"]] = mission
		order.append(mission["id"])
	dialogue = _json("res://data/story/dialogue.json").get("lines", {})
	cast = _json("res://data/story/cast.json").get("cast", {})
	chats = _json("res://data/story/chat.json")


func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


# ---------- missions ----------

func is_done(id: String) -> bool:
	return done.has(id)


func requirements_met(id: String) -> bool:
	for r in missions[id].get("requires", []):
		if not done.has(r):
			return false
	return true


## Missions the player can start now (not done, requirements met, not auto-chained).
func available() -> Array:
	var out := []
	for id in order:
		if not done.has(id) and requirements_met(id) and id != current:
			out.append(id)
	return out


func new_game() -> bool:
	return done.is_empty() and current == ""


func complete(id: String) -> void:
	done[id] = true
	if current == id:
		current = ""
		checkpoint = 0
	progress_changed.emit()


func tier(ability: String) -> int:
	return int(tiers.get(ability, 0))


func unlock(ability: String, t: int) -> void:
	if t > tier(ability):
		tiers[ability] = t
		progress_changed.emit()


func flag(name: String) -> Variant:
	return Life.flags.get(name, null)


func set_flag(name: String, value: Variant = true) -> void:
	Life.flags[name] = value


func line_list(id: String) -> Array:
	return dialogue.get(id, [])


func who(id: String) -> Dictionary:
	if HERO_NAME.has(id) and not cast.has(id):
		return { "name": HERO_NAME[id] }
	return cast.get(id, { "name": id.capitalize() })


# ---------- relationships ----------

static func pair(a: String, b: String) -> String:
	for k in ["tunde-ngozi", "tunde-kc", "ngozi-kc"]:
		if k == a + "-" + b or k == b + "-" + a:
			return k
	return a + "-" + b


func rel(a: String, b: String) -> int:
	return int(Life.relationships.get(pair(a, b), 50))


func add_rel(a: String, b: String, delta: int) -> void:
	if a == "all":
		for p in [["tunde", "ngozi"], ["tunde", "kc"], ["ngozi", "kc"]]:
			add_rel(p[0], p[1], delta)
		return
	var k := pair(a, b)
	Life.relationships[k] = clampi(int(Life.relationships.get(k, 50)) + delta, 0, 100)
	progress_changed.emit()


func family_rel() -> int:
	return (rel("tunde", "ngozi") + rel("tunde", "kc") + rel("ngozi", "kc")) / 3


# ---------- hero switching ----------

## Store the outgoing hero, load the incoming one. Returns the incoming hero's saved position
## (or Vector2.INF if they have none yet) and an off-screen event (may be empty).
func swap_hero(to: String, current_pos: Vector2) -> Dictionary:
	var from := Life.hero
	heroes[from] = { "pos": [current_pos.x, current_pos.y], "needs": Life.needs.duplicate(), "away_since": Clock.minutes }
	var st: Dictionary = heroes.get(to, {})
	var event := {}
	if st.has("away_since") and Clock.minutes - int(st["away_since"]) >= 120 and current == "":
		event = roll_offscreen(to)
	Life.hero = to
	Life.home = HERO_HOME[to]
	if st.has("needs"):
		for n in st["needs"]:
			Life.needs[n] = float(st["needs"][n])
	# Time passed for them too: needs decay a little while away (they ate somewhere, hopefully).
	if st.has("away_since"):
		var hours := (Clock.minutes - int(st["away_since"])) / 60.0
		for n in Life.NEEDS:
			Life.needs[n] = clampf(Life.needs[n] - Life.DECAY[n] * hours * 0.5, 15.0, 100.0)
	Life.changed.emit()
	hero_switched.emit(to)
	var pos := Vector2.INF
	if st.has("pos"):
		pos = Vector2(st["pos"][0], st["pos"][1])
	return { "pos": pos, "event": event }


## One weighted "while you were away" event (abilities spec §5). Cosmetic or economic only.
func roll_offscreen(hero: String) -> Dictionary:
	var table: Array = chats.get("offscreen", [])
	var pool := table.filter(func(e: Dictionary) -> bool: return e.get("hero", "any") in ["any", hero])
	var total := 0
	for e in pool:
		total += int(e["weight"])
	if total <= 0:
		return {}
	var roll := randi() % total
	for e in pool:
		roll -= int(e["weight"])
		if roll < 0:
			apply_effects(e.get("effects", {}))
			return e
	return {}


## Shared effect format used by rewards, off-screen events and dialogue choices.
func apply_effects(fx: Dictionary) -> void:
	if fx.has("story_money"):
		story_money = maxi(0, story_money + int(fx["story_money"]))
	for s in fx.get("stats", {}):
		var v := float(Life.stats.get(s, 0.0)) + float(fx["stats"][s])
		Life.stats[s] = clampf(v, 0.0, 1000.0 if s == "hype" else 100.0)
	for s in fx.get("xp", {}):
		Life.add_xp(s, int(fx["xp"][s]))
	for a in fx.get("ability", {}):
		unlock(a, int(fx["ability"][a]))
	for r in fx.get("rel", {}):
		var parts: PackedStringArray = String(r).split("-")
		if parts.size() == 2:
			add_rel(parts[0], parts[1], int(fx["rel"][r]))
		else:
			add_rel("all", "", int(fx["rel"][r]))
	for f in fx.get("flags", {}):
		set_flag(f, fx["flags"][f])
	for it in fx.get("items", {}):
		Life.add_item(it, int(fx["items"][it]))
	if fx.get("unlock_switching", false):
		switching = true
	if fx.has("diary_pages"):
		diary_pages += int(fx["diary_pages"])
	if fx.has("evidence"):
		evidence += int(fx["evidence"])
	Life.changed.emit()
	progress_changed.emit()


# ---------- save ----------

func to_dict() -> Dictionary:
	return {
		"done": done, "current": current, "checkpoint": checkpoint, "story_money": story_money,
		"tiers": tiers, "switching": switching, "heroes": heroes, "diary_pages": diary_pages, "evidence": evidence,
	}


func from_dict(d: Dictionary) -> void:
	done = d.get("done", {})
	current = String(d.get("current", ""))
	checkpoint = int(d.get("checkpoint", 0))
	story_money = int(d.get("story_money", 0))
	tiers = d.get("tiers", {})
	switching = bool(d.get("switching", false))
	heroes = d.get("heroes", {})
	diary_pages = int(d.get("diary_pages", 0))
	evidence = int(d.get("evidence", 0))
	progress_changed.emit()


func reset() -> void:
	from_dict({})
