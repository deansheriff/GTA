class_name MissionRunner
extends Node
## Runs one data-driven story mission (data/story/missions.json) as a coroutine of steps.
## Anything visual is delegated to a host (the game, or a fake host in tests) through story_* calls,
## so the same scripts run on a phone, in the headless test suite and in the demo.
##
## Step types ("do"): say, panels, chat, tip, goto, collect, ability, film, minigame, chase, jam,
## place, switch, interior, exit_interior, npc, npc_clear, set, wait, toast.
## Any step may carry: "if"/"if_not" (flag gates), "checkpoint": true, "time" (seconds limit),
## "fail_on_battery": true.

signal objective(text: String)
signal started(id: String)
signal finished(id: String, success: bool)

const SETUP_STEPS := ["place", "switch", "interior", "exit_interior", "npc", "npc_clear", "set"]

var host: Object
var map: MapData
var mission := {}
var step_index := 0
var _token := 0
var _instant := false # replaying setup steps when resuming from a checkpoint
var _ability_seen := {} # ability -> detail, cleared before each ability step
var _fail_reason := ""


func setup(h: Object, m: MapData) -> void:
	host = h
	map = m
	if host.has_signal("ability_used"):
		host.connect("ability_used", func(a: String, detail: String) -> void: _ability_seen[a] = detail)


func running() -> bool:
	return not mission.is_empty()


func start(id: String, from_checkpoint := 0) -> void:
	if not Story.missions.has(id):
		push_error("unknown mission " + id)
		return
	_token += 1
	mission = Story.missions[id]
	Story.current = id
	Story.checkpoint = from_checkpoint
	started.emit(id)
	_run(_token, from_checkpoint)


func abort() -> void:
	_token += 1
	if not mission.is_empty():
		var id: String = mission["id"]
		mission = {}
		Story.current = ""
		Story.checkpoint = 0
		host.story_cleanup()
		objective.emit("")
		finished.emit(id, false)


func _alive(token: int) -> bool:
	return token == _token and is_inside_tree()


func _run(token: int, from: int) -> void:
	var steps: Array = mission.get("steps", [])
	if from == 0:
		await host.story_begin(mission)
	else:
		_instant = true
		for i in from:
			if steps[i].get("do", "") in SETUP_STEPS and _gate(steps[i]):
				await _step(steps[i], token)
		_instant = false
	if not _alive(token):
		return
	step_index = from
	while step_index < steps.size():
		var s: Dictionary = steps[step_index]
		if s.get("checkpoint", false) and step_index != Story.checkpoint:
			Story.checkpoint = step_index
			host.story_checkpoint()
		if _gate(s):
			_fail_reason = ""
			var ok: bool = await _step(s, token)
			if not _alive(token):
				return
			if not ok:
				var retry: bool = await host.story_fail(_fail_reason if _fail_reason != "" else mission.get("fail_line", "Wahala! Try again."))
				if not _alive(token):
					return
				if retry:
					host.story_cleanup()
					_run(token, Story.checkpoint)
				else:
					abort()
				return
		step_index += 1
	_complete(token)


func _gate(s: Dictionary) -> bool:
	if s.has("if") and not Story.flag(s["if"]):
		return false
	if s.has("if_not") and Story.flag(s["if_not"]):
		return false
	if s.has("if_eq") and Story.flag(s["if_eq"][0]) != s["if_eq"][1]:
		return false
	return true


func _complete(token: int) -> void:
	var id: String = mission["id"]
	var rewards: Dictionary = mission.get("rewards", {})
	Story.apply_effects(rewards)
	Story.complete(id)
	objective.emit("")
	host.story_waypoint(Vector2.INF)
	var next: String = mission.get("next", "")
	mission = {}
	await host.story_complete(Story.missions[id], rewards)
	finished.emit(id, true)
	if _alive(token) and next != "" and not Story.is_done(next):
		start(next)


## Resolve "landmark:<id>", "node:<id>", "npc:<id>", "room:<hotspot>", "hero" or [x, y] to a position.
func resolve(at: Variant, offset: Variant = null) -> Vector2:
	var p := Vector2.INF
	if at is Array:
		p = Vector2(at[0], at[1])
	else:
		var s := String(at)
		if s.begins_with("landmark:"):
			p = map.landmarks[s.trim_prefix("landmark:")]["pos"]
		elif s.begins_with("node:"):
			p = map.road_nodes[s.trim_prefix("node:")]
		elif s.begins_with("npc:") or s.begins_with("room:"):
			p = host.story_where(s)
		elif s == "hero":
			p = host.story_focus()
	if p != Vector2.INF and offset is Array:
		p += Vector2(offset[0], offset[1])
	return p


func _text(s: Dictionary) -> String:
	return String(s.get("text", ""))


func _step(s: Dictionary, token: int) -> bool:
	var kind: String = s.get("do", "")
	match kind:
		"say":
			if _instant:
				return true
			var lines: Array = Story.line_list(s["lines"]) if s["lines"] is String else s["lines"]
			_apply_choices(await host.story_dialogue(lines))
			return true
		"panels":
			if not _instant:
				await host.story_panels(s["panels"])
			return true
		"chat":
			if not _instant:
				await host.story_chat(Story.chats.get("scripted", {}).get(s["chat"], []), s.get("title", "Family Meeting!"))
			return true
		"tip":
			if not _instant:
				await host.story_dialogue([{ "who": "tip", "text": s["text"] }])
			return true
		"toast":
			if not _instant:
				host.story_toast(_text(s), s.get("big", false))
			return true
		"wait":
			if not _instant:
				await get_tree().create_timer(float(s.get("seconds", 1.0))).timeout
			return true
		"place":
			host.story_place(s, resolve(s["at"], s.get("offset")))
			return true
		"switch":
			await host.story_switch(s["hero"], s.get("chat", "") if not _instant else "", resolve(s["at"], s.get("offset")) if s.has("at") else Vector2.INF)
			return true
		"interior":
			host.story_interior(s["room"], s.get("spawn", "door"))
			return true
		"exit_interior":
			host.story_exit_interior()
			return true
		"npc":
			host.story_npc(s["id"], s.get("who", s["id"]), resolve(s["at"], s.get("offset")) if s.has("at") else Vector2.INF, s)
			return true
		"npc_clear":
			host.story_npc_clear(s.get("id", ""))
			return true
		"set":
			_apply_set(s)
			return true
		"goto":
			return await _goto(s, token)
		"collect":
			return await _collect(s, token)
		"ability", "film":
			return await _ability(s, token)
		"minigame":
			if _instant:
				return true
			objective.emit(_text(s))
			var res: Dictionary = await host.story_minigame(s["game"], s.get("params", {}))
			for k in s.get("store", {}):
				Story.set_flag(s["store"][k], res.get(k, 0))
			Story.apply_effects(res.get("fx", {}))
			if s.has("pass") and float(res.get("score", 0)) < float(s["pass"]):
				_fail_reason = s.get("fail_text", "")
				return false
			return true
		"chase":
			return await _chase(s, token)
		"jam":
			host.story_jam(resolve(s["at"], s.get("offset")))
			return true
	push_warning("unknown step type " + kind)
	return true


## Dialogue returns every choice the player picked; each may set a flag and carry effects.
func _apply_choices(picked: Array) -> void:
	for choice in picked:
		if choice.has("flag"):
			Story.set_flag(choice["flag"], choice.get("value", true))
		Story.apply_effects(choice.get("fx", {}))


func _apply_set(s: Dictionary) -> void:
	if s.has("day"):
		Clock.minutes = (int(s["day"]) - 1) * 1440 + Clock.minutes % 1440
	if s.has("time"):
		var hm: PackedStringArray = String(s["time"]).split(":")
		var t := int(hm[0]) * 60 + int(hm[1])
		var now := Clock.minutes % 1440
		Clock.minutes += (t - now) if s.get("same_day", true) or t >= now else (t - now + 1440)
		Clock.hour_changed.emit(Clock.hour())
	if s.has("advance"):
		Clock.advance(int(s["advance"]))
	if s.has("nepa"):
		host.story_nepa(String(s["nepa"]))
	if s.has("stats"):
		for k in s["stats"]:
			Life.stats[k] = float(s["stats"][k])
	if s.has("fx"):
		Story.apply_effects(s["fx"])
	for f in s.get("flags", {}):
		Story.set_flag(f, s["flags"][f])
	if s.has("banter"):
		host.story_banter(String(s["banter"]))
	if s.get("compute_ending", false):
		Story.set_flag("ending", Story.compute_ending())
		Story.set_flag("ending_full", Story.honest_ending_full())
		Story.set_flag("teacher_won", Story.teacher_support() >= 50)


## Common per-frame fail checks for timed and battery steps. Returns "" while fine.
func _fail_check(s: Dictionary, elapsed: float) -> String:
	if s.has("time") and elapsed > float(s["time"]):
		return s.get("fail_text", "Time don finish!")
	if s.get("fail_on_battery", false) and float(Life.stats.get("battery", 100.0)) <= 0.0:
		return "Phone don die. Guys… guys?"
	return ""


func _goto(s: Dictionary, token: int) -> bool:
	if _instant:
		return true
	var target := resolve(s["at"], s.get("offset"))
	var radius := float(s.get("radius", 160.0))
	var need: String = s.get("need", "")
	host.story_waypoint(target)
	if s.has("banter"):
		host.story_banter(String(s["banter"]))
	var elapsed := 0.0
	var hinted := false
	while true:
		var text := _text(s)
		if s.has("time"):
			text += "  ·  %d s" % maxi(0, int(float(s["time"]) - elapsed))
		objective.emit(text)
		await get_tree().process_frame
		if not _alive(token):
			return false
		if not host.story_paused():
			elapsed += get_process_delta_time()
		var f := _fail_check(s, elapsed)
		if f != "":
			_fail_reason = f
			host.story_banter("")
			return false
		if host.story_focus().distance_to(target) <= radius:
			if need == "" or host.story_mode() == need:
				break
			if not hinted:
				hinted = true
				host.story_toast("You need the danfo for this." if need == "driving" else "Come down from the bus first.", false)
	host.story_waypoint(Vector2.INF)
	if not s.has("keep_banter"):
		host.story_banter("")
	return true


func _collect(s: Dictionary, token: int) -> bool:
	if _instant:
		return true
	var points: Array = s["points"]
	var left: Array = range(points.size())
	var elapsed := 0.0
	for i in points.size():
		if points[i].has("who"):
			host.story_npc("stop-%d" % i, points[i]["who"], resolve(points[i]["at"], points[i].get("offset")) + Vector2(0, -36), {})
	while not left.is_empty():
		# Point the waypoint at the nearest remaining stop.
		var focus: Vector2 = host.story_focus()
		var best := -1
		var bd := INF
		for i in left:
			var d := focus.distance_to(resolve(points[i]["at"], points[i].get("offset")))
			if d < bd:
				bd = d
				best = i
		var p: Dictionary = points[best]
		var pos := resolve(p["at"], p.get("offset"))
		host.story_waypoint(pos)
		var text := String(s.get("text", "Visit the stops")) + "  (%d/%d)" % [points.size() - left.size(), points.size()]
		if s.has("time"):
			text += "  ·  %d s" % maxi(0, int(float(s["time"]) - elapsed))
		objective.emit(text)
		await get_tree().process_frame
		if not _alive(token):
			return false
		if not host.story_paused():
			elapsed += get_process_delta_time()
		var f := _fail_check(s, elapsed)
		if f != "":
			_fail_reason = f
			return false
		if focus.distance_to(pos) <= float(s.get("radius", 110.0)):
			left.erase(best)
			if p.has("toast_before"):
				host.story_toast(p["toast_before"], false)
			if p.has("say"):
				var picked: Array = await host.story_dialogue(Story.line_list(p["say"]))
				if not _alive(token):
					return false
				_apply_choices(picked)
			Story.apply_effects(p.get("fx", {}))
			if p.has("toast"):
				host.story_toast(p["toast"], false)
	host.story_waypoint(Vector2.INF)
	for i in points.size():
		if points[i].has("who"):
			host.story_npc_clear("stop-%d" % i)
	return true


## Wait for the player to use an ability (optionally near a place or an NPC, optionally a
## specific detail such as the Conductor call "vip"). "film" = KC holds the camera on a target.
func _ability(s: Dictionary, token: int) -> bool:
	if _instant:
		return true
	var ability: String = s.get("ability", "film")
	var detail: String = s.get("detail", "")
	var target := resolve(s["at"], s.get("offset")) if s.has("at") else Vector2.INF
	var radius := float(s.get("radius", 260.0))
	if target != Vector2.INF:
		host.story_waypoint(target)
	host.story_expect(ability, detail, s)
	_ability_seen.clear()
	var elapsed := 0.0
	var filmed := 0.0
	var need_secs := float(s.get("seconds", 0.0))
	var wrong_said := false
	while true:
		var text := _text(s)
		if need_secs > 0.0:
			text += "  ·  %d%%" % int(filmed / need_secs * 100.0)
		objective.emit(text)
		await get_tree().process_frame
		if not _alive(token):
			return false
		var dt := get_process_delta_time()
		if not host.story_paused():
			elapsed += dt
		var f := _fail_check(s, elapsed)
		if f != "":
			_fail_reason = f
			host.story_expect("", "", {})
			return false
		var near: bool = target == Vector2.INF or host.story_focus().distance_to(target) <= radius
		if s.get("do") == "film" or need_secs > 0.0:
			if near and host.story_filming():
				filmed += dt
			if filmed >= need_secs:
				break
			continue
		if _ability_seen.has(ability) and near:
			var got: String = _ability_seen[ability]
			if detail == "" or got == detail:
				break
			_ability_seen.erase(ability)
			if not wrong_said:
				wrong_said = true
				host.story_toast(s.get("wrong_text", "No be that one!"), false)
				Story.apply_effects(s.get("wrong_fx", {}))
		elif _ability_seen.has(ability):
			_ability_seen.erase(ability)
			host.story_toast("Get closer first.", false)
	host.story_expect("", "", {})
	host.story_waypoint(Vector2.INF)
	return true


func _chase(s: Dictionary, token: int) -> bool:
	if _instant:
		return true
	var target := resolve(s["to"], s.get("offset"))
	host.story_waypoint(target)
	host.story_chase_start(s)
	var elapsed := 0.0
	var ok := true
	while true:
		var st: Dictionary = host.story_chase_state()
		var text := _text(s) + "  ·  heat %d%%" % int(float(st.get("heat", 0.0)) * 100.0)
		if s.has("time"):
			text += "  ·  %d s" % maxi(0, int(float(s["time"]) - elapsed))
		objective.emit(text)
		await get_tree().process_frame
		if not _alive(token):
			return false
		if not host.story_paused():
			elapsed += get_process_delta_time()
		var f := _fail_check(s, elapsed)
		if f != "":
			_fail_reason = f
			ok = false
			break
		if host.story_chase_state().get("caught", false):
			_fail_reason = s.get("caught_text", "Dem catch you!")
			ok = false
			break
		if host.story_focus().distance_to(target) <= float(s.get("radius", 200.0)):
			break
	host.story_chase_end()
	host.story_waypoint(Vector2.INF)
	return ok
