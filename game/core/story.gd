extends Node
## Autoload "Story": progress through the campaign "Èkó Ò Ní Bàjẹ́" (D-021, docs/story/eko-oni-baje.md).
## Missions, cast and lines live in data/story/eko/campaign.json and are played by Mission3D in the
## 3D city; this node only remembers what happened: missions done, the mission in progress and
## its checkpoint, the big choices, evidence found, and Dayo's Respect and Wanted level.

signal progress_changed

const DATA := "res://data/story/eko/campaign.json"

var cast := {} # id -> {name, model, colour}
var acts: Array = [] # [{id, title}]
var missions := {} # id -> mission dictionary
var order: Array = [] # mission ids in story order
var endings := {} # ending id -> {title, steps} (played by the last mission's "ending" step)

var done := {} # mission id -> true
var current := "" # mission in progress ("" = free roam)
var checkpoint := 0 # step index to resume `current` from
var choices := {} # choice id -> option id ("ballot": "swap", "sego": "spare", "final": "judgment"...)
var flags := {}
var items := {} # evidence and keepsakes: "father_phone", "tolu_id", "ledger"...
var respect := 0 # street cred, -100..100
var wanted := 0.0 # 0..5 stars


func _ready() -> void:
	load_data()


func load_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if not parsed is Dictionary:
		push_error("story data missing: " + DATA)
		return
	cast = parsed.get("cast", {})
	acts = parsed.get("acts", [])
	endings = parsed.get("endings", {})
	missions.clear()
	order.clear()
	for m: Dictionary in parsed.get("missions", []):
		missions[m["id"]] = m
		order.append(m["id"])


## Name, colour and model of a speaker (dialogue boxes use this).
func who(id: String) -> Dictionary:
	if cast.has(id):
		return cast[id]
	return { "name": id.capitalize() if id != "" else "", "colour": "#e0a91c" }


func mission(id: String) -> Dictionary:
	return missions.get(id, {})


func playable(id: String) -> bool:
	return not (mission(id).get("steps", []) as Array).is_empty()


## The next mission in story order that isn't done ("" when the campaign is finished).
func next_mission() -> String:
	for id in order:
		if not done.has(id):
			return id
	return ""


func act_title(act: int) -> String:
	for a: Dictionary in acts:
		if int(a["id"]) == act:
			return String(a["title"])
	return ""


func start(id: String) -> void:
	current = id
	checkpoint = 0
	progress_changed.emit()


func complete(id: String) -> void:
	done[id] = true
	if current == id:
		current = ""
		checkpoint = 0
	progress_changed.emit()


func choose(choice_id: String, option: String) -> void:
	choices[choice_id] = option
	progress_changed.emit()


func give(item: String) -> void:
	items[item] = true
	progress_changed.emit()


func add_respect(n: int) -> void:
	respect = clampi(respect + n, -100, 100)
	progress_changed.emit()


## Which ending the final choice leads to, and whether Judgment holds (Ballot Box swap).
func ending() -> String:
	var f := String(choices.get("final", ""))
	if f == "judgment":
		return "judgment" if choices.get("ballot", "") == "swap" else "judgment_bitter"
	return f


func to_dict() -> Dictionary:
	return { "done": done, "current": current, "checkpoint": checkpoint, "choices": choices, "flags": flags, "items": items, "respect": respect, "wanted": wanted }


func from_dict(d: Dictionary) -> void:
	done = d.get("done", {})
	current = String(d.get("current", ""))
	checkpoint = int(d.get("checkpoint", 0))
	choices = d.get("choices", {})
	flags = d.get("flags", {})
	items = d.get("items", {})
	respect = int(d.get("respect", 0))
	wanted = float(d.get("wanted", 0.0))
	progress_changed.emit()


func reset() -> void:
	from_dict({})
