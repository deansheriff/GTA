extends Node
## Test double for StoryHost: answers every story_* call instantly. The hero "teleports" to each
## waypoint, uses whatever ability is expected, wins every mini-game and picks choice `pick`.

signal ability_used(ability: String, detail: String)

var runner: Node
var focus := Vector2.ZERO
var pick := 0
var log: Array = []
var fails := 0
var minigames: Array = []
var fail_games := 0 # lose this many mini-games first


func _step() -> Dictionary:
	var steps: Array = runner.mission.get("steps", [])
	return steps[runner.step_index] if runner.step_index < steps.size() else {}


func story_begin(m: Dictionary) -> void:
	log.append("begin " + String(m["id"]))


func story_complete(m: Dictionary, _rewards: Dictionary) -> void:
	log.append("done " + String(m["id"]))


func story_checkpoint() -> void:
	pass


func story_fail(text: String) -> bool:
	fails += 1
	log.append("fail " + text)
	return fails < 5


func story_cleanup() -> void:
	pass


func story_where(s: String) -> Vector2:
	return Vector2(100, 100) if s.begins_with("room:") else focus


func story_focus() -> Vector2:
	return focus


func story_mode() -> String:
	return String(_step().get("need", "walking"))


func story_paused() -> bool:
	return false


func story_waypoint(p: Vector2) -> void:
	if p != Vector2.INF:
		focus = p


func story_toast(_t: String, _big: bool) -> void:
	pass


func story_dialogue(lines: Array) -> Array:
	var picked: Array = []
	for l in lines:
		var c: Array = l.get("choices", [])
		if not c.is_empty():
			picked.append(c[clampi(pick, 0, c.size() - 1)])
	return picked


func story_panels(_p: Array) -> void:
	pass


func story_chat(_lines: Array, _title: String) -> void:
	pass


func story_minigame(game: String, _params: Dictionary) -> Dictionary:
	minigames.append(game)
	if fail_games > 0:
		fail_games -= 1
		return { "score": 0 }
	return { "score": 100, "passed": true, "fx": { "evidence": 3 } if game == "board" else {} }


func story_switch(hero: String, _chat: String, _at: Vector2) -> void:
	Story.swap_hero(hero, focus)


func story_place(_s: Dictionary, p: Vector2) -> void:
	focus = p


func story_interior(_room: String, _spawn: String) -> void:
	pass


func story_exit_interior() -> void:
	pass


func story_npc(_id: String, _who: String, _pos: Vector2, _s: Dictionary) -> void:
	pass


func story_npc_clear(_id: String) -> void:
	pass


func story_expect(ability: String, detail: String, _s: Dictionary) -> void:
	if ability != "" and ability != "film":
		await get_tree().process_frame
		ability_used.emit(ability, detail)


func story_filming() -> bool:
	return true


func story_jam(_p: Vector2) -> void:
	pass


func story_chase_start(_s: Dictionary) -> void:
	pass


func story_chase_state() -> Dictionary:
	return { "heat": 0.0, "caught": false }


func story_chase_end() -> void:
	pass


func story_nepa(_v: String) -> void:
	pass


func story_banter(_b: String) -> void:
	pass
