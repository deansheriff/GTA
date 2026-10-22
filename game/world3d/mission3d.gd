class_name Mission3D
extends Node
## Plays the campaign's missions (D-021) step by step from data/story/eko/campaign.json in the
## 3D city. Steps: env, player, place, spawn, despawn, clear, title, say, item, still, escape,
## goto, fares, fight, exit, cam, black, sfx, respect, choice, flag, wait; from P2 (D-022): chase,
## pursuit, follow, escort, gun, roger, news, wanted, crowd, setpiece, pay; and from D-028:
##   region      travel to another map (Abeokuta, Kano, the Delta, Anambra, back to Lagos)
##   set / leave go into a built set (police cell, owambe, yacht...) and back out
##   checkpoint  a resume point: quitting mid-mission continues from here
##   if          branch on a choice or flag: {"choice": "sego", "is": "spare", "then": [], "else": []}
##   anim, walk  play a clip on an actor; walk or run an actor somewhere
##   stealth     guards with torches and sight cones; reach the goal unseen (or be spotted)
##   rooftop     chase a runner across the rooftops (gaps to jump)
##   photo       stand somewhere and snap a picture of someone (the SNAP button)
##   blend       owambe social stealth: spray money, dance when the drummer calls, dodge aunties
##   explode     a blast and fire (the kpo-fire refinery, a burning stilt house)
##   waves       fights one after another (defending the safe house)
##   boatfight   gunboats come at you on the water; sink them (or reach the goal)
##   board       jump from your bike onto the vehicle you caught, and fight on its roof
##   radio, music, nepa, time, buff, ending, credits
## A failed step (caught, knocked out, out of time) is retried from where it began. With
## `autopilot` (tests, QA) every interactive step completes by itself, so a whole mission can be
## checked end to end.

signal mission_done(id: String)

## Steps that only set up the world: replayed silently to resume at a checkpoint.
const STATE_STEPS := ["env", "player", "region", "set", "leave", "place", "spawn", "despawn", "clear", "crowd", "setpiece", "gun", "exit", "nepa", "time", "anim", "buff", "cam", "music"]

var world # Street3D
var autopilot := false
var running := ""
var _abort := false
var _roof := {} # the vehicle roof Dayo boarded: {center, fwd, y}
var _fail := "" # why the last step failed (shown on MISSION FAILED, with a tip)


func setup(w) -> void:
	world = w


func run(id: String, resume := 0) -> void:
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
	if String(m.get("region", "lagos")) != world.region:
		await world.load_region(String(m.get("region", "lagos")))
	var i := 0
	if resume > 0 and resume < steps.size():
		await world.black(0.4)
		await _fast_forward(steps, resume)
		i = resume
		Story.checkpoint = resume
		world.notify("Continuing from the last checkpoint.")
	while i < steps.size():
		if _abort:
			running = ""
			return
		var st: Dictionary = steps[i]
		var ok: bool = await _run_one(st)
		if ok:
			i += 1
			if String(st.get("do", "")) == "checkpoint":
				Story.checkpoint = i
				world._save_game()
		else:
			await world.show_title("MISSION FAILED", _fail_text(st), 3.4, Color("#e8483a"))
	world.set_objective("", null)
	world.clear_actors()
	world.clear_mission_vehicles()
	world.stealth.end()
	world.combat.clear()
	if world.sets.active != "":
		world.sets.leave()
	world.sets.platforms.clear() # a boarded vehicle's roof
	_roof = {}
	world.set_env(false, false)
	world.lights.set_cut("")
	world.run.cancel()
	world.run.enabled = true
	running = ""
	Story.complete(id)
	await world.show_title("MISSION PASSED", String(m.get("title", "")), 2.2, Color("#f6d04d"))
	mission_done.emit(id)


## A side job (FreeRoam3D): a short list of steps outside the story. No retries: fail = job lost.
func run_side(steps: Array, title: String) -> bool:
	running = "side"
	world.notify(title)
	world.run.enabled = false
	var ok := true
	for st: Dictionary in steps:
		if not await _step(st):
			ok = false
			break
	world.set_objective("", null)
	world.clear_actors()
	world.combat.clear()
	world.run.enabled = true
	running = ""
	return ok


func abort() -> void:
	_abort = true


## One step, retrying from where it began until it passes.
func _run_one(st: Dictionary) -> bool:
	var snap: Vector3 = world.player.position
	var set_was: String = world.sets.active
	_fail = ""
	var ok: bool = await _step(st)
	if not ok:
		world.combat.clear()
		world.stealth.end()
		if world.sets.active == set_was:
			world.retry_from(snap)
	return ok


func _fail_text(st: Dictionary) -> String:
	if _fail != "":
		var t := _fail
		_fail = ""
		return t
	return "Try again."


## Replay the world-setting steps before a checkpoint, without dialogue or play.
func _fast_forward(steps: Array, upto: int) -> void:
	var last_place: Dictionary = {}
	for i in upto:
		var st: Dictionary = steps[i]
		var kind := String(st.get("do", ""))
		if kind == "if":
			continue
		if kind == "place":
			last_place = st
		elif kind in ["region", "set", "leave"]:
			last_place = {}
			await _step(st)
		elif kind in STATE_STEPS:
			await _step(st)
	if not last_place.is_empty():
		await _step(last_place)


## Runs one step; false = failed (retry).
func _step(st: Dictionary) -> bool:
	var kind := String(st.get("do", ""))
	match kind:
		"env":
			world.set_env(bool(st.get("night", false)), bool(st.get("rain", false)))
		"player":
			world.player.set_model(String(st.get("as", "dayo")))
		"place":
			world.place_player(world.resolve(st), String(st.get("vehicle", "")), String(st.get("slogan", "")), float(st.get("yaw", 0.0)))
		"spawn":
			world.spawn_actor(String(st["id"]), String(st.get("who", "agbero")), world.resolve(st), String(st.get("anim", "idle")), String(st.get("face", "")), String(st.get("prop", "")), String(st.get("model", "")))
		"despawn":
			world.despawn_actor(String(st["id"]))
		"clear":
			world.stage.clear(false) # people go; the scene's set pieces stay until the mission ends
		"title":
			await world.show_title(String(st.get("text", "")), String(st.get("sub", "")), float(st.get("s", 2.5)))
		"say":
			await world.say(st.get("lines", []))
		"item":
			Story.give(String(st["give"]))
			world.notify("Got: " + String(st.get("text", st["give"])))
		"respect":
			Story.add_respect(int(st.get("n", 1)))
			world.notify("Respect %+d" % int(st.get("n", 1)))
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
		"music":
			Sound.music(String(st.get("name", "")))
		"black":
			await world.black(float(st.get("s", 1.5)))
		"cam":
			world.cam_mode(String(st.get("mode", "follow")), world.resolve(st) if st.has("at") else Vector3.ZERO)
		"exit":
			world.force_exit()
		"checkpoint":
			pass
		"region":
			await world.load_region(String(st.get("id", "lagos")))
			if st.has("at"):
				world.place_player(world.resolve(st))
		"set":
			world.sets.enter(String(st.get("kind", "")))
		"leave":
			world.sets.leave(world.resolve(st) if st.has("at") else null)
		"if":
			return await _branch(st)
		"anim":
			var a: Person3D = world.stage.actors.get(String(st.get("id", "")))
			if a and is_instance_valid(a):
				Models3D.play(a.ap, String(st.get("anim", "idle")), "idle")
		"walk":
			await _walk(st)
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
		"waves":
			return await _waves(st)
		"chase":
			return await _chase(st)
		"pursuit":
			return await _pursuit(st)
		"follow":
			return await _follow(st)
		"escort":
			return await _escort(st)
		"stealth":
			return await _stealth(st)
		"rooftop":
			return await _rooftop(st)
		"photo":
			return await _photo(st)
		"blend":
			return await _blend(st)
		"boatfight":
			return await _boatfight(st)
		"board":
			await _board(st)
		"roger":
			await _roger(st)
		"gun":
			world.combat.give_gun(int(st.get("rounds", 48)))
			world.notify(String(st.get("text", "Got a pistol")))
		"news":
			await world.show_title(String(st.get("headline", "")), String(st.get("text", "")), float(st.get("s", 4.0)), Color("#e8483a"))
		"radio":
			world.hud.radio("📻 " + String(st.get("text", "")))
			await world.get_tree().create_timer(float(st.get("s", 3.0))).timeout
		"spend":
			var amt: int = mini(int(st.get("amount", 0)), int(Life.money))
			Life.spend(amt, String(st.get("reason", "Story")))
			world.notify("-₦%s" % Life.fmt_naira(amt))
		"pay":
			Life.earn(int(st.get("amount", 0)), String(st.get("reason", "Story")))
			world.notify("+₦%s" % Life.fmt_naira(int(st.get("amount", 0))))
		"wanted":
			Story.wanted = clampf(float(st.get("set", Story.wanted)), 0.0, 5.0)
		"crowd":
			world.stage.crowd(String(st.get("id", "crowd")), String(st.get("model", "eyo")), world.resolve(st), int(st.get("count", 30)), float(st.get("radius", 18.0)), float(st.get("height", 1.9)), st.get("look", {}))
		"setpiece":
			world.stage.setpiece(String(st.get("id", "set")), String(st.get("model", "")), world.resolve(st), String(st.get("label", "")), float(st.get("yaw", 0.0)), float(st.get("size", 9.0)))
		"explode":
			world.fx.explosion(world.resolve(st), float(st.get("size", 1.0)), float(st.get("burn", 0.0)))
		"fire":
			world.fx.fire(world.resolve(st), float(st.get("size", 1.0)), float(st.get("s", 60.0)))
		"nepa":
			world.lights.set_cut(String(st.get("district", "")))
		"time":
			var h := int(st.get("h", 12))
			Clock.minutes = (Clock.day() - 1) * 1440 + h * 60 + int(st.get("m", 0))
		"buff":
			var b := String(st.get("id", ""))
			world.roam.buffs[b] = float(st.get("s", 1e9))
			Story.give(b)
			world.notify(String(st.get("text", "")))
		"ending":
			await _ending()
		"credits":
			await world.hud.credits_roll()
		_:
			push_warning("unknown mission step: " + kind)
	return true


func _branch(st: Dictionary) -> bool:
	var yes := false
	if st.has("choice"):
		yes = String(Story.choices.get(String(st["choice"]), "")) == String(st.get("is", ""))
	elif st.has("flag"):
		yes = Story.flags.has(String(st["flag"]))
	elif st.has("item"):
		yes = Story.items.has(String(st["item"]))
	for sub: Dictionary in st.get("then" if yes else "else", []):
		if not await _run_one(sub):
			return false
	return true


## The ending the final choice made (campaign.json "endings").
func _ending() -> void:
	var e := Story.ending()
	var data: Dictionary = Story.endings.get(e, {})
	for sub: Dictionary in data.get("steps", []):
		await _run_one(sub)
	Story.flags["ending_" + e] = true


func _walk(st: Dictionary) -> void:
	var a: Person3D = world.stage.actors.get(String(st.get("id", "")))
	if a == null or not is_instance_valid(a):
		return
	var to: Vector3 = world.resolve(st)
	var spd := 4.6 if bool(st.get("run", false)) else 1.4
	Models3D.play(a.ap, "run" if bool(st.get("run", false)) else "walk", "walk")
	var job := func() -> void:
		while is_instance_valid(a):
			var d := to - a.position
			d.y = 0.0
			if d.length() < 0.3:
				break
			a.rotation.y = atan2(d.x, d.z)
			a.position += d.normalized() * minf(spd * world.get_process_delta_time(), d.length())
			await world.get_tree().process_frame
		if is_instance_valid(a):
			Models3D.play(a.ap, String(st.get("then", "idle")), "idle")
	if bool(st.get("wait", false)) and not autopilot:
		await job.call()
	else:
		job.call()


func _goto(st: Dictionary) -> bool:
	var target: Vector3 = world.resolve(st)
	var r := float(st.get("radius", 5.0))
	var need := String(st.get("on", ""))
	var limit := float(st.get("time", 0.0))
	var text := String(st.get("text", ""))
	world.set_objective(text, target)
	if autopilot:
		world.place_player(target, "", "") if need != "vehicle" else world.teleport_ride(target)
	var t := 0.0
	while true:
		var f: Vector3 = world.focus()
		var here := Vector2(f.x - target.x, f.z - target.z).length() <= r
		var mode_ok: bool = need == "" or (need == "vehicle") == (world.ride != null)
		if here and mode_ok:
			break
		await world.get_tree().process_frame
		if limit > 0.0:
			t += world.get_process_delta_time()
			world.hud.timer(limit - t)
			if t > limit:
				world.hud.timer(-1.0)
				world.set_objective("", null)
				_fail = "Out of time. Take the shortest roads, and keep off the go-slow."
				return false
	world.hud.timer(-1.0)
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
			_fail = "You moved. Stay still until it passes."
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
	var speed := float(st.get("speed", 4.7))
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
			n.position += to / maxf(d, 0.01) * speed * delta
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


## Enemy specs with "at" (a mission position) or "on roof" get real positions before the fight.
func _place_enemies(list: Array) -> Array:
	var out: Array = []
	for i in list.size():
		var e: Dictionary = (list[i] as Dictionary).duplicate()
		if e.has("at"):
			e["pos"] = world.resolve(e)
		elif bool(e.get("roof", false)) and not _roof.is_empty():
			var along := (i - (list.size() - 1) * 0.5) * 2.6 + (3.0 if i % 2 == 0 else -3.0)
			e["pos"] = (_roof["center"] as Vector3) + (_roof["fwd"] as Vector3) * clampf(along, -3.8, 3.8)
		out.append(e)
	return out


func _autopilot_fight() -> void:
	while world.combat.alive() > 0:
		for e: Dictionary in world.combat.enemies:
			if int(e["hp"]) > 0 and is_instance_valid(e["node"]):
				world.player.position = (e["node"] as Node3D).position + Vector3(0.9, 0, 0)
				break
		for v: Vehicle3D in world.combat.hostile_vehicles:
			if is_instance_valid(v):
				v.damage(999.0)
		world.combat._player_cool = 0.0
		world.combat.player_hp = Combat3D.PLAYER_MAX
		world.combat.player_attack()
		await world.get_tree().create_timer(0.1).timeout
	world.combat.player_hp = Combat3D.PLAYER_MAX


func _fight(st: Dictionary) -> bool:
	world.set_objective(String(st.get("text", "Fight!")), null)
	world.combat.start(_place_enemies(st.get("enemies", [])))
	if autopilot:
		await _autopilot_fight()
	var won := true
	if world.combat.active:
		won = await world.combat.finished
	else:
		won = world.combat.player_hp > 0
	world.set_objective("", null)
	await world.get_tree().create_timer(0.8).timeout
	world.combat.clear()
	return won


## Fights one after another, with a breather and a line between (defending a house).
func _waves(st: Dictionary) -> bool:
	var waves: Array = st.get("waves", [])
	for w in waves.size():
		world.set_objective("%s  (wave %d/%d)" % [String(st.get("text", "Hold them off!")), w + 1, waves.size()], null)
		var hp_keep: int = world.combat.player_hp
		world.combat.start(_place_enemies(waves[w]))
		world.combat.player_hp = hp_keep if w > 0 else Combat3D.PLAYER_MAX
		if autopilot:
			await _autopilot_fight()
		var won := true
		if world.combat.active:
			won = await world.combat.finished
		if not won:
			world.combat.clear()
			world.set_objective("", null)
			_fail = "You were knocked out. Stand against a wall when they shoot: cover."
			return false
		await world.get_tree().create_timer(1.2).timeout
		world.combat.clear()
		var lines: Array = (st.get("between", []) as Array)
		if w < lines.size() and lines[w] is Array:
			await world.say(lines[w])
	world.set_objective("", null)
	return true


## Ram a fleeing vehicle until it's a wreck (or, with "catch", just get alongside it for a moment).
## Fail if it gets 260 m away.
func _chase(st: Dictionary) -> bool:
	world.set_objective(String(st.get("text", "Stop that vehicle!")), null)
	var v: Vehicle3D = world.spawn_mission_vehicle(String(st.get("vehicle", "danfo")), world.resolve(st), Vehicle3D.Mode.FLEE, String(st.get("slogan", "")))
	v.health = float(st.get("health", 100.0))
	var catch := bool(st.get("catch", false))
	world.run.story_target = v.position
	if autopilot:
		await world.get_tree().create_timer(1.0).timeout
		world.teleport_ride(v.position - v.forward() * 5.0)
		if not catch:
			v.damage(999.0)
	var close_t := 0.0
	while not v.is_wreck:
		await world.get_tree().process_frame
		world.run.story_target = v.position
		var d: float = v.position.distance_to(world.focus())
		if catch:
			close_t = close_t + world.get_process_delta_time() if d < 8.0 else 0.0
			world.prompt_text = "CLOSE IN" if d < 14.0 and d >= 8.0 else ""
			if close_t > 1.0 or (autopilot and d < 9.0):
				break
		if d > 260.0:
			world.set_objective("", null)
			_fail = "They got away. Stay close and ram them before they pull ahead."
			return false
		if world.ride and world.ride.is_wreck:
			world.set_objective("", null)
			_fail = "They got away. Stay close and ram them before they pull ahead."
			return false
	world.prompt_text = ""
	world.set_objective("", null)
	world.run.story_target = null
	if not catch:
		world.notify("Got them!")
	return true


## Reach a place while vehicles chase you. Fail if your vehicle is wrecked.
func _pursuit(st: Dictionary) -> bool:
	var target: Vector3 = world.resolve(st)
	var r := float(st.get("radius", 10.0))
	world.set_objective(String(st.get("text", "Lose them!")), target)
	var f: Vector3 = world.focus()
	var back: Vector3 = (f - target).normalized()
	var kinds: Array = st.get("chasers", ["pickup"])
	for i in kinds.size():
		var v: Vehicle3D = world.spawn_mission_vehicle(String(kinds[i]), f + back * (40.0 + i * 12.0), Vehicle3D.Mode.CHASE, "")
		v.b = ""
		if bool(st.get("shoot", false)):
			v.hostile = true
			v.gunners = 1
			world.combat.hostile_vehicles.append(v)
	if autopilot:
		world.teleport_ride(target)
	while true:
		await world.get_tree().process_frame
		var p: Vector3 = world.focus()
		if Vector2(p.x - target.x, p.z - target.z).length() <= r:
			break
		if (world.ride and world.ride.is_wreck) or world.combat.player_hp <= 0:
			world.set_objective("", null)
			world.combat.hostile_vehicles.clear()
			world.clear_mission_vehicles()
			_fail = "Your ride is wrecked. Avoid head-on hits and keep moving."
			return false
	world.combat.hostile_vehicles.clear()
	world.clear_mission_vehicles()
	world.set_objective("", null)
	return true


## Keep up with a vehicle driving a route of road nodes: the lead waits if you fall behind
## (a convoy), or with "flee" keeps going (a getaway truck) and you lose if you drop back too far.
func _follow(st: Dictionary) -> bool:
	var path: Array = st.get("path", [])
	if path.size() < 2:
		return true
	world.set_objective(String(st.get("text", "Follow the convoy.")), null)
	var lead: Vehicle3D = world.spawn_mission_vehicle(String(st.get("vehicle", "pickup")), Terrain3D.w(world.map.road_nodes[path[0]]), Vehicle3D.Mode.PARKED, String(st.get("slogan", "")))
	var gap := float(st.get("gap", 70.0))
	var flee := bool(st.get("flee", false))
	var spd0 := float(st.get("speed", 11.0))
	var i := 1
	var far_t := 0.0
	while i < path.size():
		await world.get_tree().process_frame
		var delta: float = world.get_process_delta_time()
		var tgt := Terrain3D.w(world.map.road_nodes[path[i]])
		if autopilot:
			lead.position = tgt
		var to := tgt - lead.position
		to.y = 0.0
		if to.length() < 4.0:
			i += 1
			continue
		var d := lead.position.distance_to(world.focus())
		var spd := spd0 if flee or d <= gap * 0.7 else 0.0
		lead.heading = lerp_angle(lead.heading, -Vector2(to.x, to.z).angle(), minf(1.0, delta * 3.0))
		lead.rotation.y = lead.heading
		lead.speed = spd
		lead.position += to.normalized() * minf(spd * delta, to.length())
		world.run.story_target = lead.position
		far_t = far_t + delta if d > gap else 0.0
		if far_t > 6.0 and not autopilot:
			world.set_objective("", null)
			world.run.story_target = null
			_fail = "You lost them. Keep the lead vehicle in sight."
			return false
	if autopilot:
		world.teleport_ride(lead.position - lead.forward() * 9.0)
	world.run.story_target = null
	world.set_objective("", null)
	return true


## Bring someone through on foot to a place; they follow you. Gunmen may attack on the way.
func _escort(st: Dictionary) -> bool:
	var target: Vector3 = world.resolve(st)
	var r := float(st.get("radius", 6.0))
	world.set_objective(String(st.get("text", "Get them out of here.")), target)
	var who: Person3D = world.stage.actors.get(String(st.get("id", "")))
	var enemies: Array = st.get("enemies", [])
	if not enemies.is_empty():
		world.combat.start(_place_enemies(enemies))
	if autopilot:
		world.place_player(target, "", "")
		for e: Dictionary in world.combat.enemies:
			e["hp"] = 0
	while true:
		await world.get_tree().process_frame
		var delta: float = world.get_process_delta_time()
		var p: Vector3 = world.player.position
		if who and is_instance_valid(who):
			var to := p - who.position
			to.y = 0.0
			if to.length() > 1.8:
				who.position += to.normalized() * minf(5.2 * delta, to.length() - 1.8)
				who.position.y = p.y
				who.rotation.y = atan2(to.x, to.z)
				Models3D.play(who.ap, "run" if to.length() > 4.0 else "walk", "walk")
			else:
				Models3D.play(who.ap, "idle", "")
		if world.combat.player_hp <= 0:
			world.combat.clear()
			world.set_objective("", null)
			_fail = "You were knocked out. Deal with the gunmen before you move on."
			return false
		if Vector2(p.x - target.x, p.z - target.z).length() <= r:
			break
	world.combat.clear()
	world.set_objective("", null)
	return true


## Sneak to the goal past guards with torches. Spotted: retry (or with "spotted": "fight", the
## guards and `enemies` open fire and you fight it out).
func _stealth(st: Dictionary) -> bool:
	var target: Vector3 = world.resolve(st)
	var r := float(st.get("radius", 4.0))
	var guards: Array = []
	for g: Dictionary in st.get("guards", []):
		var path: Array = []
		for at: Variant in g.get("path", []):
			path.append(world.resolve({ "at": at } if not at is Dictionary else at))
		guards.append({ "who": g.get("who", "police"), "path": path })
	var pools: Array = []
	for p: Dictionary in st.get("pools", []):
		pools.append({ "pos": world.resolve(p), "radius": float(p.get("radius", 7.0)) })
	world.stealth.begin(guards, pools)
	world.set_objective(String(st.get("text", "Get in without being seen.")), target)
	var need_down := int(st.get("takedowns", 0))
	if autopilot:
		await world.get_tree().create_timer(0.5).timeout
		for g: Dictionary in world.stealth.guards:
			g["down"] = true
		world.place_player(target, "", "")
	var flag := { "seen": false }
	var on_seen := func() -> void: flag["seen"] = true
	world.stealth.spotted.connect(on_seen)
	while true:
		await world.get_tree().process_frame
		world.hud.alarm(world.stealth.alarm)
		var p: Vector3 = world.player.position
		var here := Vector2(p.x - target.x, p.z - target.z).length() <= r
		if here and world.stealth.guards_down() >= need_down:
			break
		if flag["seen"]:
			break
	world.stealth.spotted.disconnect(on_seen)
	var seen: bool = flag["seen"]
	world.hud.alarm(-1.0)
	if seen and not autopilot:
		if String(st.get("spotted", "fail")) == "fight":
			world.notify("They've seen you!")
			var specs: Array = st.get("enemies", [{ "id": "sg1", "who": "police", "gun": true }, { "id": "sg2", "who": "police", "gun": true }])
			world.stealth.end()
			world.set_objective("", null)
			return await _fight({ "text": "Spotted! Fight your way through.", "enemies": specs })
		world.stealth.end()
		world.set_objective("", null)
		_fail = "A guard spotted you. Keep out of the torch beams, walk, and wait for them to turn."
		return false
	world.stealth.end()
	world.set_objective("", null)
	return true


## A foot chase over the rooftops: the runner jumps the gaps; catch him (or keep him in sight to
## the last roof, where he has nowhere left to go).
func _rooftop(st: Dictionary) -> bool:
	await world.black(0.5)
	world.sets.enter("rooftops")
	var course: Array[Vector3] = world.sets.course
	var who := String(st.get("who", "agbero"))
	var runner: Person3D = world.spawn_actor("runner", who, course[2], "run")
	world.set_objective(String(st.get("text", "Catch him!")), course[course.size() - 1])
	var i := 3
	var gap_t := 0.0
	var lost := 0.0
	var spd := float(st.get("speed", 4.9))
	if autopilot:
		runner.position = course[course.size() - 1]
		world.player.position = runner.position + Vector3(0.6, 0, 0)
	while true:
		await world.get_tree().process_frame
		var delta: float = world.get_process_delta_time()
		var pp: Vector3 = world.player.position
		if runner and is_instance_valid(runner):
			if i < course.size():
				var tgt := course[i]
				var to := tgt - runner.position
				var flat := Vector3(to.x, 0, to.z)
				# Between roofs (odd -> even index) the runner jumps the gap in an arc.
				if i % 2 == 0 and flat.length() > 0.3:
					gap_t += delta
					var k := clampf(gap_t / 0.45, 0.0, 1.0)
					runner.position = course[i - 1].lerp(tgt, k) + Vector3(0, sin(k * PI) * 0.9, 0)
					if k >= 1.0:
						gap_t = 0.0
						i += 1
				elif flat.length() < 0.3:
					i += 1
				else:
					runner.position += flat.normalized() * minf(spd * delta, flat.length())
					runner.position.y = tgt.y
				runner.rotation.y = atan2(flat.x, flat.z) if flat.length() > 0.01 else runner.rotation.y
				Models3D.play(runner.ap, "run", "walk")
			else:
				Models3D.play(runner.ap, "idle", "")
			var d := Vector2(pp.x - runner.position.x, pp.z - runner.position.z).length()
			if d < 1.8 and absf(pp.y - runner.position.y) < 1.5:
				break
			lost = lost + delta if d > 28.0 else 0.0
			if lost > 5.0:
				world.set_objective("", null)
				world.despawn_actor("runner")
				_fail = "He got away. Run, don't walk: running jumps the gaps."
				return false
	Models3D.play(runner.ap, "idle", "")
	world.set_objective("", null)
	world.notify("Got him!")
	return true


## Snap a photo of someone from somewhere: stand at the spot, face them, press SNAP.
func _photo(st: Dictionary) -> bool:
	var spot: Vector3 = world.resolve(st)
	var who: Person3D = world.stage.actors.get(String(st.get("of", "")))
	world.set_objective(String(st.get("text", "Get a photo.")), spot)
	var snap := { "done": false } # (lambdas capture locals by value: share state in a dictionary)
	var cb := func() -> void: snap["done"] = true
	while not snap["done"]:
		await world.get_tree().process_frame
		var p: Vector3 = world.player.position
		var near := Vector2(p.x - spot.x, p.z - spot.z).length() < float(st.get("radius", 2.5))
		if autopilot:
			break
		if near:
			world.prompt_text = "SNAP PHOTO"
			world.prompt_cb = cb
		elif world.prompt_text == "SNAP PHOTO":
			world.prompt_text = ""
	world.prompt_text = ""
	world.prompt_cb = Callable()
	if who and is_instance_valid(who):
		world.player.face(who.position)
	Sound.sfx("tap", 1.6)
	world.hud.flash_white()
	world.notify(String(st.get("got", "Photo taken.")))
	world.set_objective("", null)
	return true


## Owambe: stay in the party. Blend (the meter) drains while you stand around; spraying money on
## the dancers fills it, and when the talking drummer calls your name you must DANCE in time.
## Aunties who "know your face" wander; stay near one and the meter falls fast. Lasts `s` seconds.
func _blend(st: Dictionary) -> bool:
	var secs := float(st.get("s", 40.0))
	var t := 0.0
	var b := { "blend": 0.7, "drum": 0.0 } # shared with the SPRAY/DANCE button
	var drum_t := 9.0
	var aunties: Array[Person3D] = []
	for k in int(st.get("aunties", 2)):
		var a: Person3D = world.spawn_actor("auntie%d" % k, "aunty", world.sets.anchor("guest%d" % (k * 3 % 8)), "walk")
		if a:
			aunties.append(a)
	world.set_objective(String(st.get("text", "Blend in. Spray money, dance when called, avoid the aunties.")), null)
	var spray := func() -> void:
		if float(b["drum"]) > 0.0:
			b["drum"] = 0.0
			b["blend"] = minf(1.0, float(b["blend"]) + 0.3)
			world.notify("The drummer sings your praise!")
			Models3D.play(world.player.ap, "cheer", "idle")
		elif Life.spend(500, "Sprayed money at the owambe (3D)"):
			b["blend"] = minf(1.0, float(b["blend"]) + 0.18)
			world.notify("You spray ₦500 notes on the dancers.")
			Sound.sfx("cash", 1.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	while t < secs:
		await world.get_tree().process_frame
		var delta: float = world.get_process_delta_time()
		t += delta
		if autopilot:
			break
		b["blend"] = float(b["blend"]) - delta * 0.012
		drum_t -= delta
		if drum_t <= 0.0:
			drum_t = rng.randf_range(9.0, 14.0)
			b["drum"] = 1.8
			world.notify("🥁 \"Who be that fine boy for corner? Come dance!\"")
			Sound.sfx("notify", 0.8)
		if float(b["drum"]) > 0.0:
			b["drum"] = float(b["drum"]) - delta
			world.prompt_text = "DANCE!"
			if float(b["drum"]) <= 0.0:
				b["blend"] = float(b["blend"]) - 0.25
				world.notify("You missed the drummer's call. People are looking.")
		else:
			world.prompt_text = "SPRAY ₦500"
		world.prompt_cb = spray
		for a in aunties:
			if not is_instance_valid(a):
				continue
			var to: Vector3 = world.player.position - a.position
			to.y = 0.0
			if to.length() < 4.0:
				b["blend"] = float(b["blend"]) - delta * 0.1
				if rng.randf() < delta * 0.4:
					world.notify("\"Ah ah! Is this not Mama Àgbà's grandson?\"")
			# Aunties drift around the hall.
			var tgt: Vector3 = world.sets.anchor("guest%d" % (int(t / 6.0 + aunties.find(a) * 3) % 8))
			var w := tgt - a.position
			w.y = 0.0
			if w.length() > 0.5:
				a.position += w.normalized() * 1.0 * delta
				a.rotation.y = atan2(w.x, w.z)
		world.hud.alarm(1.0 - float(b["blend"]))
		if float(b["blend"]) <= 0.0:
			world.prompt_text = ""
			world.hud.alarm(-1.0)
			world.set_objective("", null)
			for k in aunties.size():
				world.despawn_actor("auntie%d" % k)
			_fail = "Your cover was blown. Spray money, dance when the drummer calls, avoid the aunties."
			return false
	world.prompt_text = ""
	world.prompt_cb = Callable()
	world.hud.alarm(-1.0)
	world.set_objective("", null)
	for k in aunties.size():
		world.despawn_actor("auntie%d" % k)
	return true


## Gunboats on the water: hostile boats chase and shoot. Sink them all (or reach the goal).
func _boatfight(st: Dictionary) -> bool:
	world.set_objective(String(st.get("text", "Gunboats! Sink them.")), world.resolve(st) if st.has("at") else null)
	var f: Vector3 = world.focus()
	for i in (st.get("boats", []) as Array).size():
		var b: Dictionary = st["boats"][i]
		var ang := TAU * i / maxf(1.0, (st["boats"] as Array).size())
		var pos: Vector3 = world.resolve(b) if b.has("at") else f + Vector3(cos(ang), 0, sin(ang)) * 45.0
		var v: Vehicle3D = world.spawn_mission_vehicle(String(b.get("vehicle", "speedboat")), pos, Vehicle3D.Mode.CHASE, "")
		v.hostile = true
		v.gunners = int(b.get("gunners", 1))
		v.health = float(b.get("hp", 40.0))
		world.combat.hostile_vehicles.append(v)
	var goal: Variant = world.resolve(st) if st.has("at") else null
	if autopilot:
		for v: Vehicle3D in world.combat.hostile_vehicles:
			v.damage(999.0)
		if goal != null:
			world.teleport_ride(goal)
	while true:
		await world.get_tree().process_frame
		var left: int = world.combat.hostile_vehicles.filter(func(v: Vehicle3D) -> bool: return is_instance_valid(v) and not v.is_wreck).size()
		if left == 0 and goal == null:
			break
		if goal != null:
			var p: Vector3 = world.focus()
			if Vector2(p.x - goal.x, p.z - goal.z).length() <= float(st.get("radius", 12.0)):
				break
		if (world.ride and world.ride.is_wreck) or world.combat.player_hp <= 0:
			world.combat.hostile_vehicles.clear()
			world.clear_mission_vehicles()
			world.set_objective("", null)
			world.combat.player_hp = Combat3D.PLAYER_MAX
			_fail = "Your boat went down. Keep moving so their shots miss."
			return false
	world.combat.hostile_vehicles.clear()
	world.set_objective("", null)
	return true


## Jump onto the vehicle you caught: it slews to a stop, and Dayo is up on its roof.
func _board(st: Dictionary) -> void:
	var v: Vehicle3D = world.mission_vehicles.back() if not world.mission_vehicles.is_empty() else null
	if v == null:
		return
	world.prompt_text = ""
	await world.black(0.4)
	v.mode = Vehicle3D.Mode.PARKED
	v.speed = 0.0
	world.force_exit()
	var y := float(st.get("roof", 3.1))
	var fwd := v.forward()
	var c := v.position + Vector3(0, y, 0)
	var half := Vector2(v.length * 0.5, 1.25)
	# The roof as a walkable deck (axis-aligned box round the vehicle's footprint).
	var ext := Vector2(absf(fwd.x) * half.x + absf(fwd.z) * half.y, absf(fwd.z) * half.x + absf(fwd.x) * half.y)
	world.sets.platforms.append({ "rect": Rect2(c.x - ext.x, c.z - ext.y, ext.x * 2.0, ext.y * 2.0), "y": c.y })
	_roof = { "center": c, "fwd": fwd, "y": c.y }
	world.player.position = c
	world.player.reset_physics_interpolation()
	world.notify(String(st.get("text", "You're on top of it!")))


## A checkpoint: the crew's line, then Dayo picks how to handle it. Moves Wanted and Respect.
func _roger(st: Dictionary) -> void:
	var kind := String(st.get("kind", "marshal"))
	var data: Dictionary = (Street.db.get("checkpoints", {}) as Dictionary).get(kind, {})
	var roger := int(int(st.get("roger", data.get("roger", 500))) * world.roam.roger_k())
	var fine := int(st.get("fine", data.get("fine", 2000)))
	var lines: Array = data.get("lines", ["Oya, stop there!"])
	var picked: Array = await world.say([{ "who": String(st.get("who", "agbero")), "text": String(st.get("text", lines[0])), "choices": [
		{ "id": "bribe", "text": "Drop the roger (₦%d)" % roger },
		{ "id": "argue", "text": "Argue your way through" },
		{ "id": "papers", "text": "Show papers" },
		{ "id": "flee", "text": "Floor it" },
	] }])
	var c := String((picked[0] as Dictionary).get("id", "bribe")) if not picked.is_empty() else "bribe"
	match c:
		"bribe":
			Life.spend(mini(roger, int(Life.money)), "Roger at a checkpoint (3D)")
			world.notify("They wave you through.")
		"argue":
			if Story.respect >= 10 or randf() < 0.5:
				Story.add_respect(2)
				world.notify("\"Oya go, go!\" You talked your way through.")
			else:
				Life.spend(mini(fine, int(Life.money)), "Checkpoint fine (3D)")
				world.notify("Argument lost. ₦%d fine." % fine)
		"papers":
			if Story.flags.has("papers"):
				world.notify("Papers checked. Through you go.")
			else:
				Life.spend(mini(roger * 2, int(Life.money)), "Checkpoint: no papers (3D)")
				world.notify("\"These papers no complete.\" ₦%d." % (roger * 2))
		"flee":
			world.police.raise(1.5)
			world.notify("You floored it. They're on the radio.")
