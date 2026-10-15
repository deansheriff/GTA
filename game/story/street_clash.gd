class_name StreetClash
extends Node
## Collisions and street "wahala" (owner requests, 2026-10-15).
##  - Your danfo is solid against traffic and other players' vehicles (no more driving through).
##  - Most bumps pass with just a crunch. Now and then a really hard hit brings the other driver
##    out: FIGHT (slapstick fist fight) or APOLOGISE (always works with NPC drivers).
##  - Block the road: park in a lane with a clear road ahead and the drivers queued behind you
##    honk, then get out, drag you out of the bus and beat you (a forced fight). This happens in
##    story missions too; drive off before they reach you to escape.
##  - Online: crash into a player and you both choose (if either fights, you fight). On foot, you
##    can drag a player out of their stopped vehicle and fight them. The server checks and scores
##    it all (apps/server/src/clash.ts).

const IMPACT := 260.0 # px/s: a hit hard enough that the other driver might come out
const NPC_COOLDOWN := 60.0
const NPC_CHANCE := 0.5
const HOLDUP_HORN := 4.0 # s of blocking before the honking starts
const HOLDUP_DRAG := 9.0 # s before the drivers get out
const HOLDUP_COOLDOWN := 45.0
const DRAG_REACH := 120.0 # px from a stopped player vehicle to drag its driver out
const DRAG_STILL_MS := 1600 # a remote vehicle must be this still (the server checks 1500)
# Pidgin lines below are pending native-speaker review (like data/story/*.json).
const WHO_LINES := ["Oga! You don jam my motor!", "Ehn?! Are you blind?! Come down!", "My new bumper! Today na today!", "Driver, you dey craze?!"]
const HONK_LINES := ["Pim pim! Drivers behind you are honking. Move your bus!", "Oga, na road you park for?! Move!", "The queue behind you is getting angry…"]
const DRAG_LINES := ["Come down from that bus!", "You wan block road for everybody?!", "Today you go learn!", "Comot there! Comot!"]

var main: Node2D
var _npc_cd := 0.0
var _bump_cd := 0.0
var _holdup_cd := 0.0
var _horn_t := 0.0
var _honked := false
var _busy := false
var _online_id := ""
var _busy_ids := {} # online clashes we couldn't answer (busy in a mini-game or menu)
var _rng := RandomNumberGenerator.new()


func setup(m: Node2D) -> void:
	main = m
	_rng.randomize()
	Net.clash.connect(_on_clash)
	Net.clash_fight.connect(_on_clash_fight)
	Net.clash_end.connect(_on_clash_end)


func tick(dt: float) -> void:
	_npc_cd = maxf(0.0, _npc_cd - dt)
	_bump_cd = maxf(0.0, _bump_cd - dt)
	_holdup_cd = maxf(0.0, _holdup_cd - dt)
	if main.mode != "driving":
		return
	_tick_holdup(dt)
	var d: Node2D = main.danfo
	# Traffic: push the danfo out of anything it overlaps.
	for v in main.traffic.vehicles:
		var other: Node2D = v["node"]
		var mtv := Collide.vehicles(d, other, 2.0)
		if mtv == Vector2.ZERO:
			continue
		var impact := absf(d.speed)
		d.position += mtv
		d.speed *= -0.2
		if impact > 150.0:
			Sound.sfx("crash")
			if not Settings.get_value("reduced_motion", false):
				main._shake(0.12)
			if not main.rented:
				main.street.care.hit(impact, (d.position + other.position) * 0.5)
			main.street.reactions.crashed(d.position)
		if impact > IMPACT:
			if not _story_blocks() and not main.story.mission_running():
				Street.add_heat(0.25)
			_maybe_npc_clash(v)
	# Other players: their vehicles are solid too, and a hard hit starts an online clash.
	for id in main.remotes:
		var r: Dictionary = main.remotes[id]
		var node: Node2D = r["danfo"] if r["mode"] == 1 else r["walker"]
		if not node.visible:
			continue
		var hit := false
		if r["mode"] == 1:
			var mtv := Collide.vehicles(d, node, 2.0)
			if mtv != Vector2.ZERO:
				d.position += mtv
				hit = true
		elif node.position.distance_to(d.position) < 52.0:
			hit = true
		if hit:
			var impact := absf(d.speed)
			d.speed *= -0.2
			if impact > IMPACT and not _busy_elsewhere() and _pid(id) != "" and _bump_cd <= 0.0:
				_bump_cd = 3.0
				Sound.sfx("crash")
				Net.send_msg({ "t": "bump", "pid": _pid(id) })


func _pid(id: int) -> String:
	return String(Net.pids.get(id, ""))


## Story moments where nobody should get out and fight you.
func _story_blocks() -> bool:
	var s: StoryHost = main.story
	return s.paused_by_story() or s.interior.active or s.chase.active or s.abilities.in_wahala()


func _busy_elsewhere() -> bool:
	return _busy or _story_blocks()


# ---------- NPC drivers: hard crashes ----------

func _maybe_npc_clash(v: Dictionary) -> void:
	# Most crashes are just a crunch: only sometimes, and never twice in a minute, does the driver
	# come out, and never in the middle of a mission.
	if _busy or _npc_cd > 0.0 or main.story.mission_running() or _story_blocks() or main.demo:
		return
	_npc_cd = NPC_COOLDOWN * 0.3
	if _rng.randf() > NPC_CHANCE:
		return
	_npc_cd = NPC_COOLDOWN
	_npc_clash(v)


func _npc_clash(v: Dictionary) -> void:
	_busy = true
	main.danfo.speed = 0.0
	v["stop_t"] = 30.0
	var veh: Node2D = v["node"]
	var driver := _spawn_driver(veh)
	var line: String = WHO_LINES[_rng.randi() % WHO_LINES.size()]
	driver.say(line, 6.0)
	var choice: String = await _ask("Wahala!", "The other driver jumps out: \"%s\"" % line, 0)
	if choice == "fight":
		main.street.reactions.crowd_to(main.danfo.position)
		var res: Dictionary = await main.story.story_minigame("fight", { "opponent": "Angry driver" })
		_apply_fight(_score(res) > 50, _score(res) == 50, "the angry driver")
	elif _rng.randf() < 0.65:
		driver.say("Okay. Make e no happen again.", 4.0)
		main.hud.toast("You apologised. He accepted. Peace.")
		_bp(-5.0)
		Street.count("apologies")
		Street.add_rep(1.0)
	else:
		driver.say("Sorry no go fix my bumper! ₦1,000.", 5.0)
		var pay: String = await _ask("He wants ₦1,000 for the bumper", "Pay him, or just keep apologising?", 1)
		if pay == "pay" and Life.spend(1000, "Bumper wahala"):
			driver.say("God bless you. Drive well.", 4.0)
		else:
			driver.say("Na wa o. God go judge you.", 4.0)
			main.hud.toast("You kept apologising. He left, still vexing.")
	await get_tree().create_timer(4.0).timeout
	driver.queue_free()
	v["stop_t"] = 0.0
	_busy = false


func _spawn_driver(veh: Node2D) -> Node2D:
	var driver: Node2D = preload("res://actors/story_npc.gd").new()
	driver.setup("angry-driver", "angry-driver")
	driver.material = main.painted_mat
	driver.position = veh.position + Vector2.from_angle(veh.heading + PI / 2.0) * 60.0
	main.streamer.add_child(driver)
	return driver


# ---------- NPC drivers: blocking the road ----------

## True when something is stopped in front of the danfo, so you're queuing, not blocking.
func _queuing() -> bool:
	var d: Node2D = main.danfo
	var fwd := Vector2.from_angle(d.heading)
	for v in main.traffic.vehicles:
		var to: Vector2 = (v["node"] as Node2D).position - d.position
		if to.length() < 260.0 and to.dot(fwd) > 20.0 and absf(to.cross(fwd)) < 60.0:
			return true
	return false


func _tick_holdup(dt: float) -> void:
	var t: float = main.traffic.holdup_t
	if _busy or _holdup_cd > 0.0 or _story_blocks() or main.story.auto or t <= 0.0 or _queuing():
		if t <= 0.0:
			_honked = false
		return
	if t > HOLDUP_HORN:
		_horn_t -= dt
		if _horn_t <= 0.0:
			_horn_t = _rng.randf_range(0.6, 1.4)
			Sound.sfx("horn", _rng.randf_range(0.75, 1.25))
		if not _honked:
			_honked = true
			main.hud.toast(HONK_LINES[_rng.randi() % HONK_LINES.size()])
	if t > HOLDUP_DRAG:
		_drag_out_by_npcs()


## The drivers you're holding up get out, march to your bus and drag you out for a beating.
## Drive away before they arrive and you escape.
func _drag_out_by_npcs() -> void:
	_busy = true
	var d: Node2D = main.danfo
	var start: Vector2 = d.position
	var held: Array = main.traffic.held.duplicate()
	held.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["node"] as Node2D).position.distance_to(start) < (b["node"] as Node2D).position.distance_to(start))
	var drivers: Array = []
	for v: Dictionary in held.slice(0, 2):
		v["stop_t"] = 25.0
		var dr := _spawn_driver(v["node"])
		dr.speed = 150.0
		dr.say(DRAG_LINES[_rng.randi() % DRAG_LINES.size()], 3.0)
		drivers.append(dr)
	main.hud.toast("Ehn! Drivers are getting out of their cars…")
	var door: Vector2 = start + Vector2.from_angle(d.heading - PI / 2.0) * 50.0
	var t := 0.0
	var escaped := false
	while t < 7.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		if main.mode != "driving" or d.position.distance_to(start) > 90.0:
			escaped = main.mode == "driving"
			break
		var arrived := true
		for i in drivers.size():
			var dr: Node2D = drivers[i]
			var goal := door + Vector2(i * 34.0, 0)
			dr.chase_step(dt, goal, main.map)
			arrived = arrived and dr.position.distance_to(goal) < 30.0
		if arrived:
			break
	if escaped or main.mode != "driving":
		for dr: Node2D in drivers:
			dr.velocity = Vector2.ZERO
			dr.say("Coward! Oya run!" if escaped else "Hmph.", 3.0)
		if escaped:
			main.hud.toast("You drove off before they reached you. Lucky!")
	else:
		# Dragged out: you're on your feet next to the bus and it's on.
		d.speed = 0.0
		main._enter_exit()
		Sound.sfx("crash", 0.8)
		if not Settings.get_value("reduced_motion", false):
			main._shake(0.25)
		for dr: Node2D in drivers:
			dr.velocity = Vector2.ZERO
			dr.say(DRAG_LINES[_rng.randi() % DRAG_LINES.size()], 3.0)
		var who := "Angry drivers" if drivers.size() > 1 else "Angry driver"
		main.street.reactions.crowd_to(main.player.position)
		Street.add_heat(0.5)
		var res: Dictionary = await main.story.story_minigame("fight", { "opponent": who, "intro": "You blocked the road and they dragged you out of the bus!" })
		if _score(res) > 50:
			main.hud.toast("You fought them off! They go back to their cars, grumbling.", true)
			Life.restore("fun", 10.0)
			_bp(-10.0)
		else:
			main.hud.toast("They beat you small and left. Next time, no block road.")
			Life.restore("energy", -20.0)
			Life.restore("hygiene", -15.0)
			_bp(20.0)
		for dr: Node2D in drivers:
			dr.say("Make you learn sense!" if _score(res) <= 50 else "Ehn… we go see.", 3.0)
	await get_tree().create_timer(3.0).timeout
	for dr: Node2D in drivers:
		dr.queue_free()
	for v: Dictionary in held:
		v["stop_t"] = 0.0
	main.traffic.reset_holdup()
	_holdup_cd = HOLDUP_COOLDOWN
	_honked = false
	_busy = false


# ---------- shared ----------

## A two-button card. mode 0: Fight / Apologise; mode 1: Pay / Keep apologising.
func _ask(title: String, body: String, mode: int, seconds := 0.0) -> String:
	var root: Control = main.hud._root
	var card: VBoxContainer = main.hud._card(root, title, body)
	var dlg: Control = main.hud._dialog_root(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var picked := [""]
	var opts: Array = [["fight", "Fight"], ["peace", "Apologise"]] if mode == 0 else [["pay", "Pay ₦1,000"], ["peace", "Keep apologising"]]
	for o in opts:
		var key: String = o[0]
		var b: Button = main.hud._button(o[1], func() -> void: picked[0] = key)
		b.custom_minimum_size = Vector2(200, 56)
		row.add_child(b)
	main.story._busy += 1 # freezes driving input while the card is up
	var t := 0.0
	while picked[0] == "":
		await get_tree().process_frame
		t += get_process_delta_time()
		if seconds > 0.0 and t >= seconds:
			picked[0] = "peace" # no answer counts as peace
		if main.story.auto:
			picked[0] = "peace"
	main.story._busy -= 1
	dlg.queue_free()
	return picked[0]


func _score(res: Dictionary) -> int:
	return int(res.get("score", 0))


func _bp(delta: float) -> void:
	Life.stats["bp"] = clampf(float(Life.stats.get("bp", 20.0)) + delta, 0.0, 100.0)


func _apply_fight(won: bool, draw: bool, who: String) -> void:
	Street.add_heat(1.0 if won else 0.5)
	if won:
		Street.count("fights_won")
		Street.add_rep(1.0)
		Street.post_gist("fight", "%s won a street fight against %s in %s!" % [Street._me(), who, main._district])
	elif not draw:
		Street.post_gist("fight", "%s lost a street fight in %s. E pain am." % [Street._me(), main._district])
	if draw:
		main.hud.toast("A draw. You and %s shake hands, both tired." % who)
		Life.restore("energy", -8.0)
		return
	if won:
		main.hud.toast("You won the wahala! Street respect +1.", true)
		Life.restore("fun", 15.0)
		_bp(-25.0)
		if Life.hero == "ngozi":
			Life.stats["aura"] = minf(100.0, float(Life.stats.get("aura", 40.0)) + 3.0)
		elif Life.hero == "kc":
			Life.stats["hype"] = minf(1000.0, float(Life.stats.get("hype", 0.0)) + 25.0)
	else:
		main.hud.toast("You lost the fight, and a bit of dignity.")
		Life.restore("energy", -15.0)
		Life.restore("hygiene", -10.0)
		_bp(15.0)


# ---------- online players ----------

## A remote player whose vehicle you could drag them out of (you on foot, their vehicle stopped
## and close). Returns the member id, or -1.
func drag_target(focus: Vector2) -> int:
	if main.mode != "walking" or _busy_elsewhere() or not Net.is_online():
		return -1
	var now := Time.get_ticks_msec()
	for id in main.remotes:
		var r: Dictionary = main.remotes[id]
		if r["mode"] != 1 or _pid(id) == "" or now - int(r.get("moved_at", 0)) < DRAG_STILL_MS:
			continue
		if (r["danfo"] as Node2D).position.distance_to(focus) < DRAG_REACH:
			return id
	return -1


func drag(id: int) -> void:
	if _pid(id) == "" or _bump_cd > 0.0:
		return
	_bump_cd = 3.0
	main.hud.toast("You march up and yank the door open…")
	Net.send_msg({ "t": "drag", "pid": _pid(id) })


func _on_clash(m: Dictionary) -> void:
	if _busy_elsewhere():
		# Mid-mini-game or mid-card: we apologise automatically. If they fight anyway we can't
		# answer, so it costs us nothing (see _on_clash_fight).
		_busy_ids[String(m["id"])] = true
		Net.send_msg({ "t": "clash_choice", "id": m["id"], "choice": "peace" })
		return
	_busy = true
	_online_id = String(m["id"])
	var choice := await _ask("Wahala with %s!" % m.get("name", "a player"), "You collided. Fight, or apologise? (They choose too. If either of you picks Fight, it's on.)", 0, float(m.get("ms", 10000)) / 1000.0)
	Net.send_msg({ "t": "clash_choice", "id": m["id"], "choice": choice })
	if choice == "peace":
		main.hud.toast("You apologised. Waiting for %s…" % m.get("name", "them"))


func _on_clash_fight(m: Dictionary) -> void:
	var id := String(m["id"])
	var name_ := String(m.get("name", "Someone"))
	var dragged: bool = m.get("dragged", false)
	var ranked: bool = m.get("ranked", false)
	if (dragged or ranked) and _online_id != id:
		# A drag-out starts straight at the fight (no choice card first).
		if _busy_elsewhere():
			_busy_ids[id] = true
		else:
			_busy = true
			_online_id = id
	if _busy_ids.has(id):
		main.hud.toast("%s wanted to fight you, but you were busy." % name_)
		Net.send_msg({ "t": "clash_result", "id": m["id"], "log": [] })
		return
	if id != _online_id:
		return
	var victim: bool = dragged and String(m.get("by", "")) != Net.my_pid
	var intro := "%s chose to fight!" % name_
	if victim:
		intro = "%s dragged you out of your bus! Defend yourself!" % name_
		if main.mode == "driving":
			main.danfo.speed = 0.0
			main._enter_exit()
			Sound.sfx("crash", 0.8)
	elif dragged:
		intro = "You dragged %s out of their bus. Now fight!" % name_
	elif ranked:
		intro = "Ranked street boxing vs %s. Ding ding!" % name_
	elif m.get("you") == "peace":
		intro = "You apologised, but %s wants a fight. Defend yourself!" % name_
	main.hud.toast(intro)
	main.street.reactions.crowd_to(main.player.position if main.mode == "walking" else main.danfo.position)
	var res: Dictionary = await main.story.story_minigame("fight", { "opponent": name_, "seq": m["seq"], "windows": m["windows"], "intro": intro })
	Net.send_msg({ "t": "clash_result", "id": m["id"], "log": res.get("log", []) })


func _on_clash_end(m: Dictionary) -> void:
	if _busy_ids.erase(String(m["id"])):
		return
	if String(m["id"]) != _online_id:
		return
	_online_id = ""
	_busy = false
	if m.get("outcome") == "peace":
		main.hud.toast("Una settle am. Peace.")
		Street.count("apologies")
		Street.add_rep(1.0)
		Life.restore("social", 5.0)
		return
	var winner = m.get("winner")
	if m.get("ranked", false):
		# A sanctioned bout: no Area heat, just the rating.
		var won: bool = winner != null and String(winner) == Net.my_pid
		var rating := int((m.get("ratings", {}) as Dictionary).get(Net.my_pid, 0))
		main.hud.toast("%s Rating: %d." % ["You won the bout!" if won else ("Draw." if winner == null else "You lost the bout."), rating], won)
		if won:
			Street.count("fights_won")
			Street.post_gist("boxing", "%s won a ranked boxing bout." % Street._me())
		return
	_apply_fight(winner != null and String(winner) == Net.my_pid, winner == null, "them")
