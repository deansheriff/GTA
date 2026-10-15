class_name StreetClash
extends Node
## Collisions and street "wahala" (owner request, 2026-10-15).
##  - Your danfo is solid against traffic and other players' vehicles (no more driving through).
##  - Hit something hard and the other side wants words: FIGHT (slapstick fist fight) or
##    APOLOGISE. With NPCs, apologising always ends it peacefully (sometimes they ask for the bumper).
##  - With online players the server decides: if either of you chooses to fight, you fight; your
##    apology doesn't stop someone who wants wahala (apps/server/src/clash.ts).

const IMPACT := 150.0 # px/s: below this it's just a nudge
const NPC_COOLDOWN := 25.0
# Pidgin lines below are pending native-speaker review (like data/story/*.json).
const WHO_LINES := ["Oga! You don jam my motor!", "Ehn?! Are you blind?! Come down!", "My new bumper! Today na today!", "Driver, you dey craze?!"]

var main: Node2D
var _npc_cd := 0.0
var _bump_cd := 0.0
var _busy := false
var _online_id := ""
var _busy_ids := {} # clashes we auto-declined while busy


func setup(m: Node2D) -> void:
	main = m
	Net.clash.connect(_on_clash)
	Net.clash_fight.connect(_on_clash_fight)
	Net.clash_end.connect(_on_clash_end)


func tick(dt: float) -> void:
	_npc_cd = maxf(0.0, _npc_cd - dt)
	_bump_cd = maxf(0.0, _bump_cd - dt)
	if main.mode != "driving":
		return
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
		if impact > IMPACT:
			Sound.sfx("crash")
			main._shake(0.15)
			_npc_clash(v)
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
			if impact > IMPACT and not _busy_elsewhere() and Net.pids.has(id) and Net.pids[id] != "" and _bump_cd <= 0.0:
				_bump_cd = 3.0
				Sound.sfx("crash")
				Net.send_msg({ "t": "bump", "pid": Net.pids[id] })


# ---------- NPC drivers ----------

func _npc_clash(v: Dictionary) -> void:
	if _busy or _npc_cd > 0.0 or main.story.mission_running() or main.story.paused_by_story():
		main.hud.toast(["Oga, you no see road?", "Na so you dey drive?", "Who give you licence?"][randi() % 3])
		return
	_busy = true
	main.danfo.speed = 0.0
	_npc_cd = NPC_COOLDOWN
	v["stop_t"] = 30.0
	var veh: Node2D = v["node"]
	var driver: Node2D = preload("res://actors/story_npc.gd").new()
	driver.setup("angry-driver", "angry-driver")
	driver.material = main.painted_mat
	driver.position = veh.position + Vector2.from_angle(veh.heading + PI / 2.0) * 70.0
	main.streamer.add_child(driver)
	driver.say(WHO_LINES[randi() % WHO_LINES.size()], 6.0)
	var choice: String = await _ask("Wahala!", "The other driver jumps out: \"%s\"" % WHO_LINES[randi() % WHO_LINES.size()], 0)
	if choice == "fight":
		var res: Dictionary = await main.story.story_minigame("fight", { "opponent": "Angry driver" })
		_apply_fight(int(res.get("score", 0)) > 50, int(res.get("score", 0)) == 50, "the angry driver")
	else:
		if randf() < 0.65:
			driver.say("Okay. Make e no happen again.", 4.0)
			main.hud.toast("You apologised. He accepted. Peace.")
			Life.stats["bp"] = maxf(0.0, float(Life.stats.get("bp", 20.0)) - 5.0)
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


func _apply_fight(won: bool, draw: bool, who: String) -> void:
	if draw:
		main.hud.toast("A draw. You and %s shake hands, both tired." % who)
		Life.restore("energy", -8.0)
		return
	if won:
		main.hud.toast("You won the wahala! Street respect +1.", true)
		Life.restore("fun", 15.0)
		Life.stats["bp"] = maxf(0.0, float(Life.stats.get("bp", 20.0)) - 25.0)
		if Life.hero == "ngozi":
			Life.stats["aura"] = minf(100.0, float(Life.stats.get("aura", 40.0)) + 3.0)
		elif Life.hero == "kc":
			Life.stats["hype"] = minf(1000.0, float(Life.stats.get("hype", 0.0)) + 25.0)
	else:
		main.hud.toast("You lost the fight, and a bit of dignity.")
		Life.restore("energy", -15.0)
		Life.restore("hygiene", -10.0)
		Life.stats["bp"] = minf(100.0, float(Life.stats.get("bp", 20.0)) + 15.0)


# ---------- online players ----------

func _busy_elsewhere() -> bool:
	return _busy or main.story.mission_running() or main.story.paused_by_story() or main.story.interior.active


func _on_clash(m: Dictionary) -> void:
	if _busy_elsewhere():
		# Mid-mission or mid-card: we apologise automatically. If they fight anyway we can't
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
	if _busy_ids.has(String(m["id"])):
		main.hud.toast("%s wanted to fight you, but you were busy." % m.get("name", "Someone"))
		Net.send_msg({ "t": "clash_result", "id": m["id"], "log": [] })
		return
	if String(m["id"]) != _online_id:
		return
	var intro := "%s chose to fight!" % m.get("name", "They")
	if m.get("you") == "peace":
		intro = "You apologised, but %s wants a fight. Defend yourself!" % m.get("name", "they")
	main.hud.toast(intro)
	var res: Dictionary = await main.story._games["fight"].play({ "opponent": String(m.get("name", "Player")), "seq": m["seq"], "windows": m["windows"], "intro": intro })
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
		Life.restore("social", 5.0)
		return
	var winner = m.get("winner")
	_apply_fight(winner != null and String(winner) == Net.my_pid, winner == null, "them")
