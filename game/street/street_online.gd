class_name StreetOnline
extends Node
## Online street life (M11), the client side of apps/server/src/street_online.ts:
##  - Danfo races and "who get road" duels (#7): open a race to a landmark; the server decides
##    the order from its own positions.
##  - Crews (#16): form or join one, wear the tag, and hold routes by finishing danfo runs on them
##    (a held route pays +10% fares to every member).
##  - Co-op jobs (#17): one drives, the other rides along filming or working the passengers.
##  - Street boxing (#18): ranked bouts with nearby players (ratings, weekly champions) and the
##    offline Area Ladder against eight NPC fighters.
##  - Trading (#19): buy goods where they're cheap, sell where they're dear (market ₦ wallet).
##  - Photo mode and the Lagos Gist feed (#22).
## Every online action needs a connection (Settings → Online); everything offline still works.

const GIST_KINDS := { "award": "award", "impound": "impound", "zoom": "zoom", "hero": "hero", "owambe": "owambe", "fleet": "fleet", "home": "home", "event": "event", "photo": "photo", "race": "race_win", "boxing": "boxing" }
const LADDER := ["Small Pikin from Mushin", "Iya Basira's son", "Conductor Jide", "Agbero Lanre", "Mechanic Sunday", "Bouncer Big T", "Area Father's nephew", "\"The Wall\" of Oshodi"]

var host: StreetHost
var main: Node2D
var phone: Control
var crew := {} # my crew {id, name, tag, colour, members}
var crew_tag := ""
var held_routes: Array = []
var race := {} # {id, to, finish}
var ride := {} # co-op ride-along: {id, driver_pid, role}
var photo: _PhotoMode


func setup(h: StreetHost) -> void:
	host = h
	main = h.main
	phone = main.hud.phone
	Net.street_msg.connect(_on_msg)
	Net.welcomed.connect(func(_id: int, _room: String) -> void: refresh_crew())
	Street.gist_posted.connect(_share_gist)
	main.jobs.danfo_done.connect(_on_danfo_done)
	phone.add_app("Race", _app_race)
	phone.add_app("Crew", _app_crew)
	phone.add_app("Boxing", _app_boxing)
	phone.add_app("Market", _app_market)
	phone.add_app("Camera", func() -> void:
		phone.visible = false
		start_photo())


func online() -> bool:
	return Net.is_online() and int(Settings.get_pref("age_ok", -1)) != 0


func tick(_dt: float) -> void:
	# Riding along in someone's danfo (co-op): you sit in their bus.
	if not ride.is_empty():
		var d := _remote_by_pid(String(ride["driver_pid"]))
		if d.is_empty():
			return
		main.player.position = (d["danfo"] as Node2D).position
		main.player.visible = false


func riding() -> bool:
	return not ride.is_empty()


func _remote_by_pid(pid: String) -> Dictionary:
	for id in main.remotes:
		if String(Net.pids.get(id, "")) == pid:
			return main.remotes[id]
	return {}


## The closest other player within `reach` px: {id, pid, name, mode} or {}.
func nearest_player(reach: float) -> Dictionary:
	var me: Vector2 = main.danfo.position if main.mode == "driving" else main.player.position
	var best := {}
	var bd := reach
	for id in main.remotes:
		var r: Dictionary = main.remotes[id]
		var node: Node2D = r["danfo"] if r["mode"] == 1 else r["walker"]
		var d := node.position.distance_to(me)
		if d < bd and String(Net.pids.get(id, "")) != "":
			bd = d
			best = { "id": id, "pid": Net.pids[id], "name": (r["walker"] as Node2D).get("display_name"), "mode": r["mode"] }
	return best


func _err(res: Dictionary) -> String:
	var d: Variant = res.get("data", {})
	var code := String(d.get("error", "")) if d is Dictionary else ""
	return { "insufficient_funds": "Not enough market ₦ (top up in Wallet).", "not_at_destination": "", "already_in_crew": "You're already in a crew.", "name_or_tag_taken": "That name or tag is taken.", "bad_tag": "Tags are 2–4 letters or numbers.", "go_online_in_a_district": "Go online to trade." }.get(code, "Network wahala (%s)." % (code if code != "" else str(res.get("code"))))


# ---------- realtime messages ----------

func _on_msg(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"race_invite":
			var c := await host.ask("Race!" if not m.get("duel", false) else "Who get road?!", "%s challenges you to a danfo race to %s." % [m["host"], m["to"]], [["join", "Join the race"], ["no", "No, thanks"]], float(m.get("ms", 10000)) / 1000.0 - 1.0, "no")
			if c == "join":
				Net.send_msg({ "t": "race_join", "id": m["id"] })
		"race_open":
			main.hud.toast("Race to %s open! %d driver(s) invited." % [m["to"], int(m.get("invited", 0))])
		"race_joined":
			host.ticker("%s joined the race (%d racers)." % [m["name"], int(m["count"])], 4.0)
		"race_go":
			race = { "id": m["id"], "to": m["to"] }
			var f: Dictionary = m["finish"]
			main._set_waypoint(Vector2(float(f["x"]), float(f["y"])))
			if m.get("dq") != null:
				main.hud.toast("You weren't on the start line. Disqualified!")
				return
			for n in ["3", "2", "1"]:
				host.fx.pop(n, main.danfo.position + Vector2(0, -90), Color("#e0a91c"), 60, 0.9)
				Sound.sfx("tap")
				await get_tree().create_timer(1.0).timeout
			host.fx.pop("GO!", main.danfo.position + Vector2(0, -90), Color("#9fd38a"), 70, 1.0)
			Sound.sfx("horn")
			main.hud.toast("Race to %s! Who get road?!" % m["to"], true)
		"race_end":
			race = {}
			main._set_waypoint(Vector2.INF)
			if m.get("cancelled", false):
				main.hud.toast("Nobody joined the race.")
				return
			var lines := []
			for r: Dictionary in m["results"]:
				lines.append("%s %s" % ["%d." % int(r["place"]) if int(r["place"]) > 0 else "DNF", r["name"]])
				if String(r["pid"]) == Net.my_pid and int(r["place"]) == 1:
					Street.count("races_won")
					Street.add_rep(2.0)
					Street.post_gist("race", "%s won a danfo race to %s!" % [Street._me(), m["to"]])
			main.hud.toast("Race results: " + ", ".join(PackedStringArray(lines)))
		"coop_invite":
			var role := "film" if m.get("role") == "film" else "conductor"
			var c := await host.ask("Co-op job", "%s wants you on their danfo (%s) as the %s." % [m["name"], m["route"], "camera person" if role == "film" else "conductor"], [["yes", "Hop in"], ["no", "Not now"]], 18.0, "no")
			if c == "yes":
				Net.send_msg({ "t": "coop_accept", "id": m["id"] })
		"coop_start":
			if m.get("you") == "driver":
				var to: Dictionary = m["to"]
				main._set_waypoint(Vector2(float(to["x"]), float(to["y"])))
				main.hud.toast("Co-op: drive %s with %s on board. Stay together!" % [m["route"], m["partner"]])
			else:
				_start_ride(m)
		"coop_end":
			var paid: Dictionary = m.get("paid", {})
			var mine := int(paid.get("partner" if riding() else "driver", 0))
			ride = {}
			main.player.visible = main.mode == "walking"
			main._set_waypoint(Vector2.INF)
			match String(m.get("outcome", "")):
				"arrived":
					main.hud.toast("Co-op job done! ₦%s to your market wallet." % Life.fmt_naira(mine), true)
				"apart":
					main.hud.toast("You arrived, but you weren't together most of the way. No pay.")
				"declined":
					main.hud.toast("They didn't hop in.")
				_:
					main.hud.toast("Co-op job ended (%s)." % m.get("outcome", ""))
		"box_invite":
			var c := await host.ask("Street boxing", "%s (rating %d) challenges you to a ranked bout." % [m["name"], int(m.get("rating", 1000))], [["yes", "Gloves on"], ["no", "Decline"]], 18.0, "no")
			if c == "yes":
				Net.send_msg({ "t": "box_accept", "id": m["id"] })


func _start_ride(m: Dictionary) -> void:
	ride = { "id": m["id"], "driver_pid": m["driver_pid"], "role": m["you"] }
	if main.mode == "driving":
		main.danfo.speed = 0.0
		main._enter_exit()
	main.hud.toast("You're on %s's danfo. %s" % [m["driver"], "Film the best moments!" if m["you"] == "film" else "Collect the fares!"])
	await get_tree().create_timer(4.0).timeout
	var res: Dictionary
	if m["you"] == "film":
		res = await main.story.story_minigame("spray", { "title": "Film the best moments!", "beats": 16, "bpm": 100 })
	else:
		res = await main.story.story_minigame("counting", { "stacks": 12, "intro": "Count the fares as the passengers pass them forward!" })
	if not ride.is_empty():
		Net.send_msg({ "t": "coop_task", "id": ride["id"], "score": int(res.get("score", 0)) })
		main.hud.toast("Good work. Now hold on till the end of the route.")


# ---------- gist ----------

func _share_gist(e: Dictionary) -> void:
	if not online():
		return
	var kind := String(e["kind"])
	var text := String(e["text"])
	var server_kind := String(GIST_KINDS.get(kind, ""))
	var detail := ""
	if kind == "fight":
		server_kind = "taskforce" if text.contains("Task Force") else ("fight_win" if text.contains(" won ") else "fight_loss")
	elif kind == "award":
		detail = text.get_slice("\"", 1)
	elif kind == "race":
		detail = text.get_slice(" to ", 1).trim_suffix("!")
	if server_kind == "":
		return
	await Net.api("POST", "/api/gist", { "kind": server_kind, "detail": detail })


func gist_online_into(p: Control) -> void:
	if not online():
		return
	p._label("ON THE STREET (players near you)", 13, Color("#e0a91c"))
	var holder := VBoxContainer.new()
	p._screen.add_child(holder)
	var res: Dictionary = await Net.api("GET", "/api/gist")
	if not is_instance_valid(holder):
		return
	for post: Dictionary in res.get("data", {}).get("posts", []):
		var l := Label.new()
		l.text = String(post["text"])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color("#9fd38a"))
		holder.add_child(l)


# ---------- crews ----------

func refresh_crew() -> void:
	if not online():
		return
	var res: Dictionary = await Net.api("GET", "/api/crews/mine")
	var c: Variant = res.get("data", {}).get("crew")
	crew = c if c is Dictionary else {}
	var tag := String(crew.get("tag", ""))
	if tag != crew_tag:
		crew_tag = tag
		if tag != "":
			Street.count("crew_joined")
		host.life.apply_style()
	var r: Dictionary = await Net.api("GET", "/api/routes")
	held_routes = r.get("data", {}).get("held", [])


func _on_danfo_done(job: Dictionary, fares: int) -> void:
	if not online() or crew.is_empty():
		return
	if String(job.get("id", "")) in held_routes:
		var bonus := int(fares * 0.1)
		Life.earn(bonus, "Crew route bonus [%s]" % crew_tag)
		main.hud.toast("[%s] holds this route: +₦%s." % [crew_tag, Life.fmt_naira(bonus)])
	var res: Dictionary = await Net.api("POST", "/api/crews/route-run", { "route": job.get("id", "") })
	if res.get("ok", false):
		var holder: Variant = res["data"].get("holder")
		if res["data"].get("yours", false):
			host.ticker("Route point for [%s]! You hold %s this week." % [crew_tag, job.get("name", "this route")], 6.0)
		elif holder is Dictionary:
			host.ticker("Route point for [%s]. [%s] still holds it." % [crew_tag, holder["tag"]], 6.0)
		refresh_crew()


func _app_crew() -> void:
	phone._clear("Crew")
	if not online():
		phone._label("Crews need you online (Settings → Online).", 15, Color("#e0a91c"))
		return
	await refresh_crew()
	if not phone.visible or phone._title.text != "Crew":
		return
	if not crew.is_empty():
		phone._label("[%s] %s" % [crew["tag"], crew["name"]], 20, Color(String(crew.get("colour", "#e0a91c"))))
		for mem: Dictionary in crew.get("members", []):
			phone._label("%s%s" % [mem["name"], " (boss)" if mem.get("role") == "boss" else ""], 14)
		_btn("Leave crew", func() -> void:
			await Net.api("POST", "/api/crews/leave")
			_app_crew())
	else:
		phone._label("No crew yet. Join one, or start your own (₦5,000 from your market wallet).", 14)
		var name_e := LineEdit.new()
		name_e.placeholder_text = "Crew name"
		phone._screen.add_child(name_e)
		var tag_e := LineEdit.new()
		tag_e.placeholder_text = "Tag (2–4 letters)"
		tag_e.max_length = 4
		phone._screen.add_child(tag_e)
		_btn("Start a crew", func() -> void:
			var r: Dictionary = await Net.api("POST", "/api/crews", { "name": name_e.text, "tag": tag_e.text })
			main.hud.toast("Crew [%s] started!" % r["data"].get("tag", "") if r.get("ok", false) else _err(r))
			_app_crew())
		var list: Dictionary = await Net.api("GET", "/api/crews")
		for c: Dictionary in list.get("data", {}).get("crews", []):
			var cid := int(c["id"])
			_btn("Join [%s] %s (%d members)" % [c["tag"], c["name"], int(c["members"])], func() -> void:
				var r: Dictionary = await Net.api("POST", "/api/crews/%d/join" % cid)
				main.hud.toast("Welcome to the crew!" if r.get("ok", false) else _err(r))
				_app_crew())
	phone._label("ROUTES THIS WEEK", 13, Color("#e0a91c"))
	var routes: Dictionary = await Net.api("GET", "/api/routes")
	for r: Dictionary in routes.get("data", {}).get("routes", []):
		var h: Variant = r.get("holder")
		phone._label("%s: %s" % [r["name"], ("[%s] %d pts" % [h["tag"], int(h["points"])]) if h is Dictionary else "nobody yet"], 13)


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	phone._screen.add_child(b)
	return b


# ---------- races ----------

func _app_race() -> void:
	phone._clear("Race")
	if not online():
		phone._label("Races need you online (Settings → Online).", 15, Color("#e0a91c"))
		return
	phone._label("Line up with other danfos, pick a finish and race. The server judges who arrives first. No shortcuts through walls, no teleporting.", 13)
	var near := nearest_player(600.0)
	if not near.is_empty() and int(near["mode"]) == 1:
		phone._label("WHO GET ROAD? 1-on-1 with %s" % near["name"], 13, Color("#e0a91c"))
	var me: Vector2 = main.danfo.position
	var spots := []
	for id: String in main.map.landmarks:
		var d: float = (main.map.landmarks[id]["pos"] as Vector2).distance_to(me)
		if d > 1600.0 and d < 8800.0:
			spots.append(id)
	if spots.is_empty():
		phone._label("No finish line in range from here. Drive somewhere central.", 13)
	for id: String in spots.slice(0, 8):
		var lid := id
		var label := String(main.map.landmarks[id]["name"])
		_btn("Race to %s" % label, func() -> void:
			if main.mode != "driving":
				main.hud.toast("Get in your bus first.")
				return
			phone.visible = false
			Net.send_msg({ "t": "race_open", "to": lid }))
		if not near.is_empty() and int(near["mode"]) == 1:
			var pid: String = near["pid"]
			_btn("  ↳ Who get road vs %s" % near["name"], func() -> void:
				phone.visible = false
				Net.send_msg({ "t": "race_open", "to": lid, "duel": pid }))
	if not near.is_empty() and main.mode == "driving":
		phone._label("CO-OP JOB with %s" % near["name"], 13, Color("#e0a91c"))
		var pid2: String = near["pid"]
		_btn("Invite as camera person", func() -> void:
			phone.visible = false
			Net.send_msg({ "t": "coop_invite", "pid": pid2, "role": "film" }))
		_btn("Invite as conductor", func() -> void:
			phone.visible = false
			Net.send_msg({ "t": "coop_invite", "pid": pid2, "role": "conductor" }))


# ---------- boxing ----------

func _app_boxing() -> void:
	phone._clear("Boxing")
	var lvl := int(Street.counters.get("ladder", 0))
	phone._label("AREA LADDER (offline)", 13, Color("#e0a91c"))
	if lvl >= LADDER.size():
		phone._label("You beat the whole ladder. Area champion!", 15)
	else:
		phone._label("Next: %s (fight %d of %d)" % [LADDER[lvl], lvl + 1, LADDER.size()], 15)
		_btn("Fight %s" % LADDER[lvl], func() -> void:
			phone.visible = false
			_ladder_fight(lvl))
	if not online():
		phone._label("Ranked boxing with other players needs you online.", 13)
		return
	var near := nearest_player(300.0)
	if not near.is_empty() and int(near["mode"]) == 0 and main.mode == "walking":
		var pid: String = near["pid"]
		_btn("Challenge %s to a ranked bout" % near["name"], func() -> void:
			phone.visible = false
			Net.send_msg({ "t": "box_challenge", "pid": pid })
			main.hud.toast("Challenge sent to %s." % near["name"]))
	var res: Dictionary = await Net.api("GET", "/api/boxing")
	if not phone.visible or phone._title.text != "Boxing":
		return
	var d: Dictionary = res.get("data", {})
	var me: Dictionary = d.get("me", {})
	phone._label("RANKED · you: %d (%d–%d)" % [int(me.get("rating", 1000)), int(me.get("wins", 0)), int(me.get("losses", 0))], 13, Color("#e0a91c"))
	for c: Dictionary in d.get("champions", []).slice(0, 3):
		phone._label("Champion %s: %s (%d wins)" % [c["week"], c["name"], int(c["wins"])], 13, Color("#9fd38a"))
	for i in (d.get("top", []) as Array).size():
		var t: Dictionary = d["top"][i]
		phone._label("%d. %s · %d (%d–%d)" % [i + 1, t["name"], int(t["rating"]), int(t["wins"]), int(t["losses"])], 13)


func _ladder_fight(lvl: int) -> void:
	# Each rung is quicker: shorter windows to react.
	var windows := []
	for i in 10:
		windows.append(maxf(0.55, 1.4 - lvl * 0.08 - i * 0.06))
	main.street.reactions.crowd_to(main.player.position)
	var res: Dictionary = await main.story.story_minigame("fight", { "opponent": LADDER[lvl], "windows": windows, "intro": "Area Ladder, fight %d: %s" % [lvl + 1, LADDER[lvl]] })
	if int(res.get("score", 0)) > 50:
		Street.counters["ladder"] = lvl + 1
		Street.count("fights_won")
		var prize := (lvl + 1) * 1500
		Life.earn(prize, "Area Ladder prize")
		main.hud.toast("You beat %s! ₦%s prize." % [LADDER[lvl], Life.fmt_naira(prize)], true)
		Street.post_gist("boxing", "%s beat %s on the Area Ladder." % [Street._me(), LADDER[lvl]])
	else:
		Life.restore("energy", -12.0)
		main.hud.toast("%s was too much today. Train and come back." % LADDER[lvl])


# ---------- trading ----------

func _app_market() -> void:
	phone._clear("Market")
	if not online():
		phone._label("Trading needs you online: prices are set by what everybody buys and sells.", 15, Color("#e0a91c"))
		return
	var res: Dictionary = await Net.api("GET", "/api/trade?district=%s" % Net.district)
	if not phone.visible or phone._title.text != "Market":
		return
	if not res.get("ok", false):
		phone._label(_err(res), 14)
		return
	var d: Dictionary = res["data"]
	phone._label("Prices in %s · market wallet ₦%s" % [String(d["district"]).capitalize(), Life.fmt_naira(int(d["balance"]))], 15)
	phone._label("Buy cheap (Mushin, Oshodi), sell dear (Lekki, VI, Ikoyi). Every trade moves the price. 3% market levy on sales.", 12, Color(1, 1, 1, 0.6))
	var held := {}
	for h: Dictionary in d.get("holdings", []):
		held[h["good"]] = h
	for g: String in d["goods"]:
		var info: Dictionary = d["goods"][g]
		var h: Dictionary = held.get(g, {})
		phone._label("%s · ₦%s%s" % [info["name"], Life.fmt_naira(int(d["prices"][g])), "  (you have %d)" % int(h["qty"]) if not h.is_empty() else ""], 14)
		var row := HBoxContainer.new()
		phone._screen.add_child(row)
		var good := g
		for spec: Array in [["Buy 1", "buy", 1], ["Buy 5", "buy", 5], ["Sell all", "sell", int(h.get("qty", 0))]]:
			if spec[2] <= 0:
				continue
			var side: String = spec[1]
			var qty: int = spec[2]
			var b := Button.new()
			b.text = spec[0]
			b.custom_minimum_size = Vector2(90, 40)
			b.pressed.connect(func() -> void:
				var r: Dictionary = await Net.api("POST", "/api/trade", { "good": good, "qty": qty, "side": side })
				if r.get("ok", false):
					var profit := int(r["data"].get("profit", 0))
					if side == "sell":
						Street.counters["trade_total"] = int(Street.counters.get("trade_total", 0)) + profit
						Street.record("trade_profit", int(Street.counters["trade_total"]))
						main.hud.toast("Sold for ₦%s (%s₦%s)." % [Life.fmt_naira(int(r["data"]["total"])), "+" if profit >= 0 else "−", Life.fmt_naira(absi(profit))])
					else:
						main.hud.toast("Bought %d for ₦%s." % [qty, Life.fmt_naira(int(r["data"]["total"]))])
				else:
					main.hud.toast(_err(r))
				_app_market())
			row.add_child(b)


# ---------- photo mode ----------

func start_photo() -> void:
	if photo:
		return
	photo = _PhotoMode.new()
	photo.owner_online = self
	main.add_child(photo)


## Photo mode: the HUD hides, drag to look around, pinch/scroll to zoom, filters, and Snap saves
## a picture (user://photos) and posts it to the Lagos Gist feed.
class _PhotoMode extends CanvasLayer:
	var owner_online: StreetOnline
	var _cam: Camera2D
	var _filter: ColorRect
	var _ui: Control
	var _mode := 0
	const FILTERS := ["Normal", "Warm", "Black & white", "Nollywood"]

	func _ready() -> void:
		layer = 30
		var main: Node2D = owner_online.main
		main.hud.visible = false
		var old := main.get_viewport().get_camera_2d()
		_cam = Camera2D.new()
		_cam.position = old.get_screen_center_position()
		_cam.zoom = old.zoom
		main.add_child(_cam)
		_cam.make_current()
		var fl := CanvasLayer.new()
		fl.layer = 29
		add_child(fl)
		_filter = ColorRect.new()
		_filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/photo_filter.gdshader")
		_filter.material = m
		fl.add_child(_filter)
		_ui = HBoxContainer.new()
		_ui.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_ui.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_ui.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_ui.offset_bottom = -16
		_ui.add_theme_constant_override("separation", 10)
		add_child(_ui)
		for spec: Array in [["Filter", _next_filter], ["SNAP", _snap], ["Exit", _exit]]:
			var b := Button.new()
			b.text = spec[0]
			b.custom_minimum_size = Vector2(140, 60)
			b.add_theme_font_size_override("font_size", 22)
			b.pressed.connect(spec[1])
			_ui.add_child(b)
		_apply()

	func _apply() -> void:
		(_filter.material as ShaderMaterial).set_shader_parameter("mode", _mode)
		(_ui.get_child(0) as Button).text = FILTERS[_mode]

	func _next_filter() -> void:
		_mode = (_mode + 1) % FILTERS.size()
		_apply()

	func _unhandled_input(e: InputEvent) -> void:
		if e is InputEventScreenDrag or (e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT)):
			_cam.position -= e.relative / _cam.zoom
		elif e is InputEventMagnifyGesture:
			_cam.zoom = (_cam.zoom * e.factor).clamp(Vector2(0.3, 0.3), Vector2(2.5, 2.5))
		elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_cam.zoom = (_cam.zoom * (1.1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9)).clamp(Vector2(0.3, 0.3), Vector2(2.5, 2.5))

	func _snap() -> void:
		_ui.visible = false
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		_ui.visible = true
		DirAccess.make_dir_recursive_absolute("user://photos")
		var path := "user://photos/naija-%d.png" % int(Time.get_unix_time_from_system())
		img.save_png(path)
		Sound.sfx("tap", 0.8)
		Street.count("photos")
		Street.post_gist("photo", "%s posted a photo." % Street._me())
		owner_online.main.hud.toast("Saved to the app's photos folder.")

	func _exit() -> void:
		var main: Node2D = owner_online.main
		main.hud.visible = true
		main.camera.make_current()
		_cam.queue_free()
		owner_online.photo = null
		queue_free()
