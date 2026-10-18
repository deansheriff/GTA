class_name Mission3D
extends Node
## Plays the campaign's missions (D-021) step by step from data/story/eko/campaign.json in the
## 3D city. Steps: env, player, place, spawn, despawn, clear, title, say, item, still, escape,
## goto, fares, fight, exit, cam, black, sfx, respect, choice, flag, wait.
## A failed step (caught, knocked out) is retried from where it began. With `autopilot` (tests,
## QA) every interactive step completes by itself, so a whole mission can be checked end to end.

signal mission_done(id: String)

var world # Street3D
var autopilot := false
var running := ""
var _abort := false


func setup(w) -> void:
	world = w


func run(id: String) -> void:
	var m: Dictionary = Story.mission(id)
	var steps: Array = m.get("steps", [])
	if steps.is_empty():
		return
	running = id
	_abort = false
	world.run.cancel()
	world.run.enabled = false
	Story.start(id)
	world.mission_banner(m)
	var i := 0
	while i < steps.size():
		if _abort:
			running = ""
			return
		var st: Dictionary = steps[i]
		var snap: Vector3 = world.player.position
		var ok: bool = await _step(st)
		if ok:
			i += 1
			Story.checkpoint = i
		else:
			await world.show_title("MISSION FAILED", _fail_text(st), 2.2, Color("#e8483a"))
			world.retry_from(snap)
	world.set_objective("", null)
	world.clear_actors()
	world.set_env(false, false)
	world.run.cancel()
	world.run.enabled = true
	running = ""
	Story.complete(id)
	await world.show_title("MISSION PASSED", String(m.get("title", "")), 2.2, Color("#f6d04d"))
	mission_done.emit(id)


func abort() -> void:
	_abort = true


func _fail_text(st: Dictionary) -> String:
	match String(st.get("do", "")):
		"escape", "still": return "They caught you. Try again."
		"fight": return "You were knocked out. Try again."
	return "Try again."


## Runs one step; false = failed (retry).
func _step(st: Dictionary) -> bool:
	var kind := String(st.get("do", ""))
	match kind:
		"env":
			world.set_env(bool(st.get("night", false)), bool(st.get("rain", false)))
		"player":
			world.player.set_model(String(st.get("as", "dayo")))
		"place":
			world.place_player(world.resolve(st), String(st.get("vehicle", "")), String(st.get("slogan", "")))
		"spawn":
			world.spawn_actor(String(st["id"]), String(st.get("who", "agbero")), world.resolve(st), String(st.get("anim", "idle")), String(st.get("face", "")), String(st.get("prop", "")), String(st.get("model", "")))
		"despawn":
			world.despawn_actor(String(st["id"]))
		"clear":
			world.clear_actors()
		"title":
			await world.show_title(String(st.get("text", "")), String(st.get("sub", "")), float(st.get("s", 2.5)))
		"say":
			await world.say(st.get("lines", []))
		"item":
			Story.give(String(st["give"]))
			world.notify("Got: " + String(st.get("text", st["give"])))
		"respect":
			Story.add_respect(int(st.get("n", 1)))
			world.notify("Respect +%d" % int(st.get("n", 1)))
		"flag":
			Story.flags[String(st["set"])] = true
		"choice":
			var picked: Array = await world.say([{ "who": String(st.get("who", "story")), "text": String(st.get("text", "")), "choices": st.get("options", []) }])
			if not picked.is_empty():
				Story.choose(String(st["id"]), String((picked[0] as Dictionary).get("id", "")))
		"wait":
			await world.get_tree().create_timer(float(st.get("s", 1.0))).timeout
		"sfx":
			Sound.sfx(String(st.get("name", "tap")))
		"black":
			await world.black(float(st.get("s", 1.5)))
		"cam":
			world.cam_mode(String(st.get("mode", "follow")), world.resolve(st) if st.has("at") else Vector3.ZERO)
		"exit":
			world.force_exit()
		"goto":
			return await _goto(st)
		"still":
			return await _still(st)
		"escape":
			return await _escape(st)
		"fares":
			return await _fares(st)
		"fight":
			return await _fight(st)
		_:
			push_warning("unknown mission step: " + kind)
	return true


func _goto(st: Dictionary) -> bool:
	var target: Vector3 = world.resolve(st)
	var r := float(st.get("radius", 5.0))
	var need := String(st.get("on", ""))
	world.set_objective(String(st.get("text", "")), target)
	if autopilot:
		world.place_player(target, "", "") if need != "vehicle" else world.teleport_ride(target)
	while true:
		var f: Vector3 = world.focus()
		var here := Vector2(f.x - target.x, f.z - target.z).length() <= r
		var mode_ok: bool = need == "" or (need == "vehicle") == (world.ride != null)
		if here and mode_ok:
			break
		await world.get_tree().process_frame
	world.set_objective("", null)
	return true


func _still(st: Dictionary) -> bool:
	world.set_objective(String(st.get("text", "Don't move.")), null)
	var start: Vector3 = world.player.position
	var t := float(st.get("s", 3.0))
	while t > 0.0:
		await world.get_tree().process_frame
		t -= world.get_process_delta_time()
		if not autopilot and world.player.position.distance_to(start) > 1.2:
			world.set_objective("", null)
			return false
	world.set_objective("", null)
	return true


func _escape(st: Dictionary) -> bool:
	var target: Vector3 = world.resolve(st)
	var r := float(st.get("radius", 6.0))
	world.set_objective(String(st.get("text", "Run!")), target)
	var chasers: Array = []
	var back: Vector3 = (world.player.position - target).normalized()
	var models: Array = st.get("chasers", ["gunman"])
	for i in models.size():
		var p: Vector3 = world.player.position + back * (9.0 + i * 2.0) + Vector3(i * 1.5 - 0.75, 0, 0)
		var n: Person3D = world.spawn_actor("chaser%d" % i, String(models[i]), p, "run", "player")
		if n:
			chasers.append(n)
	if autopilot:
		world.place_player(target, "", "")
	var caught := false
	var grace := 1.5
	while true:
		await world.get_tree().process_frame
		var delta: float = world.get_process_delta_time()
		grace -= delta
		var pp: Vector3 = world.player.position
		if Vector2(pp.x - target.x, pp.z - target.z).length() <= r:
			break
		for n: Person3D in chasers:
			var to := pp - n.position
			to.y = 0.0
			var d := to.length()
			# A touch slower than a sprinting player, faster than a walking one.
			n.position += to / maxf(d, 0.01) * 4.7 * delta
			n.rotation.y = atan2(to.x, to.z)
			if d < 1.1 and grace <= 0.0:
				caught = true
		if caught:
			break
	for i in chasers.size():
		world.despawn_actor("chaser%d" % i)
	world.set_objective("", null)
	return not caught


func _fares(st: Dictionary) -> bool:
	var need := int(st.get("count", 1))
	var got := 0
	var text := String(st.get("text", ""))
	world.set_objective("%s  (0/%d)" % [text, need], null)
	world.run.enabled = true
	while got < need:
		if autopilot:
			world.autopilot_fare()
		await world.run.paid
		got += 1
		world.set_objective("%s  (%d/%d)" % [text, got, need], null)
	world.run.enabled = false
	world.run.cancel()
	world.set_objective("", null)
	return true


func _fight(st: Dictionary) -> bool:
	world.set_objective(String(st.get("text", "Fight!")), null)
	world.combat.start(st.get("enemies", []))
	if autopilot:
		while world.combat.alive() > 0:
			for e: Dictionary in world.combat.enemies:
				if int(e["hp"]) > 0:
					world.player.position = (e["node"] as Node3D).position + Vector3(0.9, 0, 0)
					break
			world.combat._player_cool = 0.0
			world.combat.player_attack()
			await world.get_tree().create_timer(0.1).timeout
		world.combat.player_hp = Combat3D.PLAYER_MAX
	var won := true
	if world.combat.active:
		won = await world.combat.finished
	else:
		won = world.combat.player_hp > 0
	world.set_objective("", null)
	await world.get_tree().create_timer(0.8).timeout
	world.combat.clear()
	return won
