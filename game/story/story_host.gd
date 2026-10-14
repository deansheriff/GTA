class_name StoryHost
extends Node
## Connects "Up NEPA!" to the running game: implements the story_* calls MissionRunner makes
## (dialogue, panels, chats, mini-games, NPCs, interiors, chases), shows mission markers, handles
## hero switching (Family Meeting 🔥), abilities, the Story / Switch / Keke phone apps and the
## story autoplay used for headless QA (--story-auto).

signal ability_used(ability: String, detail: String)

const NpcScript := preload("res://actors/story_npc.gd")
const GAMES := {
	"jollof": preload("res://ui/minigames/jollof_queue.gd"),
	"spray": preload("res://ui/minigames/money_spray.gd"),
	"quick": preload("res://ui/minigames/quick_time.gd"),
	"counting": preload("res://ui/minigames/counting.gd"),
	"standoff": preload("res://ui/minigames/standoff.gd"),
	"interview": preload("res://ui/minigames/visa_interview.gd"),
	"dresscode": preload("res://ui/minigames/dress_code.gd"),
	"board": preload("res://ui/minigames/evidence_board.gd"),
	"dodge": preload("res://ui/minigames/jerrycan_dodge.gd"),
	"gist": preload("res://ui/minigames/rumour_graph.gd"),
	"debate": preload("res://ui/minigames/debate.gd"),
	"cue": preload("res://ui/minigames/light_cue.gd"),
	"spray_dance": preload("res://ui/minigames/money_spray.gd"),
}
const INK := Color("#1d1611")
const PAPER := Color("#f1e6c8")
const DANFO := Color("#e0a91c")

var main: Node2D
var runner := MissionRunner.new()
var abilities := Abilities.new()
var chase := Chase.new()
var interior := Interior.new()
var auto := false # story autoplay (QA / demo)
var npcs := {} # id -> world StoryNPC
var dialogue: Control
var panels: Control
var chat: Control
var bar: Control
var _games := {}
var _objective: Label
var _subtitle: Label
var _subtitle_t := 0.0
var _banner: Label
var _banter := ""
var _banter_t := 0.0
var _markers: Node2D
var _expect := ""
var _expect_detail := ""
var _auto_t := 0.0
var _auto_wp := Vector2.INF
var _story_wp := Vector2.INF
var _vote_box: Control
var _shot_n := 0
var _busy := 0 # modal story UI open (dialogue, panels, chat, game)
var prompt_id := "" # mission offered at the marker the hero stands on
var ambient := {} # who -> StoryNPC living their daily routine in free roam
var _amb_t := 0.0
var _talk_who := ""
var _radio_t := 40.0


func setup(m: Node2D) -> void:
	main = m
	add_child(runner)
	add_child(abilities)
	runner.setup(self, main.map)
	runner.objective.connect(_set_objective)
	runner.finished.connect(func(id: String, ok: bool) -> void:
		_set_objective("")
		Telemetry.event("mission_complete" if ok else "mission_fail", { "id": id })
		if id == "3.5" and ok:
			Telemetry.event("ending", { "ending": String(Story.flag("ending")) }))
	runner.started.connect(func(id: String) -> void: Telemetry.event("mission_start", { "id": id }))
	chase.setup(main.map, main.nav, main.streamer, main.painted_mat)
	add_child(interior)
	var root: Control = main.hud._root
	bar = preload("res://ui/ability_bar.gd").new()
	root.add_child(bar)
	root.move_child(bar, main.hud.phone.get_index()) # under the phone and dialogs
	bar.ability_pressed.connect(on_ability)
	bar.call_pressed.connect(func(c: String) -> void: abilities.use("conductor", c))
	abilities.message.connect(func(t: String) -> void: subtitle(t))
	abilities.used.connect(func(a: String, d: String) -> void: ability_used.emit(a, d))
	_objective = _outlined_label(20)
	_objective.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_objective.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_objective.offset_top = 104
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_objective)
	_subtitle = _outlined_label(18)
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_subtitle.offset_bottom = -190
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size = Vector2(760, 0)
	root.add_child(_subtitle)
	_banner = _outlined_label(46)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_color", DANFO)
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.visible = false
	root.add_child(_banner)
	for k in GAMES:
		var g: Control = GAMES[k].new()
		root.add_child(g)
		_games[k] = g
	dialogue = preload("res://ui/dialogue_box.gd").new()
	root.add_child(dialogue)
	chat = preload("res://ui/chat_view.gd").new()
	root.add_child(chat)
	panels = preload("res://ui/story_panels.gd").new()
	root.add_child(panels)
	_markers = Node2D.new()
	_markers.z_index = -50
	_markers.draw.connect(_draw_markers)
	main.add_child(_markers)
	_add_phone_apps()
	Story.hero_switched.connect(func(_h: String) -> void: abilities.reset_for_hero())
	set_auto(auto)


func set_auto(on: bool) -> void:
	auto = on
	dialogue.autoplay = on
	panels.autoplay = on
	chat.autoplay = on
	main.hud.pos_game.autoplay = on
	for g in _games.values():
		g.autoplay = on


func _outlined_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", PAPER)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------- game start / save ----------

## New game: the Prologue starts on its own. Loaded game: resume a mission from its checkpoint.
func begin() -> void:
	_apply_hero_look()
	if Story.current != "":
		runner.start(Story.current, Story.checkpoint)
	elif Story.new_game():
		runner.start("P1")


func _apply_hero_look() -> void:
	main.player.use_hero_sheet(Story.HERO_SHEET[Life.hero])
	if interior.active:
		interior.set_hero_sheet(Story.HERO_SHEET[Life.hero])


# ---------- per frame ----------

func tick(dt: float) -> void:
	var focus := story_focus()
	# Story Bible world rule 2: story missions pause the life-sim clock; free roam runs it.
	Clock.paused = runner.running()
	var near_home := false
	var home: Dictionary = main.map.landmarks.get(Life.home, {})
	if not home.is_empty() and main.player.position.distance_to(home["pos"]) < 160.0:
		near_home = true
	if Life.hero == "kc" and Story.flag("canteen_socket") and main.player.position.distance_to(main.map.landmarks["aunty-boss-kitchen"]["pos"]) < 160.0:
		near_home = true
	abilities.tick(dt, {
		"mode": main.mode, "stuck": main.mode == "driving" and absf(main.danfo.speed) < 40.0 and _in_traffic(),
		"moving": main.mode == "driving" and absf(main.danfo.speed) > 120.0, "crashed": false,
		"at_home": near_home and not interior.active, "nepa_on": main.nepa_on,
	})
	if interior.active:
		interior.step(dt, main._input_vector())
	if chase.active:
		var vote: Dictionary = chase.tick(dt, focus)
		if not vote.is_empty():
			_show_vote(vote)
	if abilities.rallying():
		for p in main.crowd.people:
			var n: Node2D = p
			if n.position.distance_to(focus) < 600.0:
				n.target = focus + Vector2(randf_range(-90, 90), randf_range(40, 110))
	# Banter in the bus while a goto step runs.
	if _banter != "" and not interior.active:
		_banter_t -= dt
		if _banter_t <= 0.0:
			_banter_t = 8.0
			var bank: Array = Story.chats.get("banter", {}).get(_banter, [])
			var news: Dictionary = main.online.news_line("drivers") if _banter == "debates" and main.online and randf() < 0.4 else {}
			if not news.is_empty():
				subtitle("Passenger: \"%s\"" % OnlineApps.credit(news), 7.0)
			elif not bank.is_empty():
				subtitle(bank.pick_random(), 6.0)
	_radio_t -= dt
	if _radio_t <= 0.0:
		_radio_t = 95.0
		if main.mode == "driving" and not runner.running() and main.online:
			var r: Dictionary = main.online.news_line("")
			if not r.is_empty():
				subtitle("📻 Gidi Gist FM: %s" % OnlineApps.credit(r), 8.0)
	if _subtitle_t > 0.0:
		_subtitle_t -= dt
		if _subtitle_t <= 0.0:
			_subtitle.text = ""
	_tick_ambient(dt, focus)
	_tick_pages(focus)
	bar.refresh(abilities)
	_markers.queue_redraw()
	if auto:
		_auto_tick(dt)


func _in_traffic() -> bool:
	for v in main.traffic.vehicles:
		if (v["node"] as Node2D).position.distance_to(main.danfo.position) < 200.0:
			return true
	return false


func subtitle(text: String, seconds := 4.0) -> void:
	_subtitle.text = text
	_subtitle_t = seconds


func _set_objective(text: String) -> void:
	_objective.text = ("★ " + text) if text != "" else ""


func mission_running() -> bool:
	return runner.running()


func paused_by_story() -> bool:
	return _busy > 0


# ---------- named characters' daily routines ----------

## Story characters keep a schedule in free roam (cast.json "routine"): Sule washes the bus at the
## depot by day, Mama Nkem runs the market, Officer Gbenga mans his checkpoint. Spawned near you only.
func _tick_ambient(dt: float, focus: Vector2) -> void:
	_amb_t -= dt
	if _amb_t > 0.0:
		return
	_amb_t = 1.0
	var hour := Clock.hour()
	for who in Story.cast:
		var c: Dictionary = Story.cast[who]
		if not c.has("routine"):
			continue
		var want := Vector2.INF
		if not runner.running() and not interior.active:
			for r in c["routine"]:
				if hour >= int(r["from"]) and hour < int(r["to"]):
					want = runner.resolve(r["at"], r.get("offset"))
		var near := want != Vector2.INF and focus.distance_to(want) < 1800.0
		if near and not ambient.has(who):
			var n: Node2D = NpcScript.new()
			n.setup("amb-" + who, who)
			n.material = main.painted_mat
			n.position = want
			main.streamer.add_child(n)
			ambient[who] = n
		elif not near and ambient.has(who):
			(ambient[who] as Node).queue_free()
			ambient.erase(who)


## Hidden diary pages (missions.json "collectibles"): four in the world after Act 1, needed for
## the Secret ending together with the pages from missions.
func _page_list() -> Array:
	var out: Array = []
	for c in Story.collectibles:
		if Story.flag("got_" + String(c["id"])) or not Story.flag(String(c.get("needs", ""))):
			continue
		out.append({ "c": c, "pos": runner.resolve(c["at"], c.get("offset")) })
	return out


func _tick_pages(focus: Vector2) -> void:
	if runner.running() or interior.active or _busy > 0 or Engine.get_process_frames() % 10 != 0:
		return
	for p in _page_list():
		if focus.distance_to(p["pos"]) < 90.0:
			var c: Dictionary = p["c"]
			Story.set_flag("got_" + String(c["id"]), true)
			Story.apply_effects(c.get("fx", {}))
			_busy += 1
			await dialogue.play([{ "who": "tip", "text": "%s  (Diary pages: %d/%d)" % [c.get("text", "Diary page!"), Story.diary_pages, Story.PAGES_FOR_D] }])
			_busy -= 1
			SaveGame.save_now()
			return


func ambient_prompt(focus: Vector2) -> String:
	_talk_who = ""
	for who in ambient:
		if (ambient[who] as Node2D).position.distance_to(focus) < 110.0:
			_talk_who = who
			return "Talk to %s" % Story.who(who).get("name", who)
	return ""


func talk() -> void:
	if not ambient.has(_talk_who):
		return
	Life.restore("social", 4.0)
	var online: OnlineApps = main.online
	# Live chat (when the owner has switched it on) for the characters with a server persona.
	if online and online.live_chat and Net.server != "" and _talk_who in ["mama-nkem", "sule", "barber", "mechanic", "teacher", "bayo", "kiosk"]:
		online.ask_npc(_talk_who)
		return
	var news: Dictionary = online.news_line(OnlineApps.NPC_ARCHETYPE.get(_talk_who, "")) if online else {}
	if not news.is_empty() and randf() < 0.5:
		ambient[_talk_who].say(String(news.get("text", "")).left(70), 6.0)
		subtitle(OnlineApps.credit(news), 6.0)
		return
	var lines: Array = Story.cast[_talk_who].get("chatter", ["…"])
	ambient[_talk_who].say(lines.pick_random(), 4.5)


# ---------- markers and mission prompts ----------

func _start_pos(id: String) -> Vector2:
	var m: Dictionary = Story.missions[id]
	return runner.resolve(m["start"]) if m.has("start") else Vector2.INF


func marker_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if runner.running():
		return out
	for id in Story.available():
		var p := _start_pos(id)
		if p != Vector2.INF:
			out.append(p)
	return out


## Context action text for the mission marker under the hero ("" when none).
func mission_prompt(focus: Vector2) -> String:
	prompt_id = ""
	if runner.running() or interior.active:
		return ""
	for id in Story.available():
		var p := _start_pos(id)
		if p != Vector2.INF and focus.distance_to(p) < 150.0:
			prompt_id = id
			var m: Dictionary = Story.missions[id]
			if m["hero"] != "any" and m["hero"] != Life.hero:
				return "★ %s (play as %s)" % [m["title"], Story.HERO_NAME[m["hero"]]]
			return "★ Start: %s" % m["title"]
	return ""


func start_prompted() -> void:
	if prompt_id == "":
		return
	var m: Dictionary = Story.missions[prompt_id]
	if m["hero"] != "any" and m["hero"] != Life.hero:
		main.hud.toast("Switch to %s in the phone first." % Story.HERO_NAME[m["hero"]])
		return
	start_mission(prompt_id)


func start_mission(id: String) -> void:
	if not main.jobs.active.is_empty():
		main.jobs.cancel()
	runner.start(id)


func _draw_markers() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var view: Rect2 = main._view_rect().grow(200)
	for p in marker_positions():
		if not view.has_point(p):
			continue
		var r := 46.0 + sin(t * 3.0) * 6.0
		_markers.draw_circle(p, r, Color(0.88, 0.66, 0.11, 0.18))
		_markers.draw_arc(p, r, 0, TAU, 40, DANFO, 7.0, true)
		_markers.draw_arc(p, r, 0, TAU, 40, INK, 2.0, true)
		_star(p + Vector2(0, -r - 34 + sin(t * 4.0) * 5.0), 20.0)
	for p in _page_list():
		var pp: Vector2 = p["pos"]
		if view.has_point(pp):
			_markers.draw_circle(pp, 26.0 + sin(t * 5.0) * 4.0, Color(1.0, 0.85, 0.4, 0.25))
			var r := Rect2(pp - Vector2(11, 14), Vector2(22, 28))
			_markers.draw_rect(r, Color("#f6efd9"))
			_markers.draw_rect(r, INK, false, 2.0)
			for k in 3:
				_markers.draw_line(pp + Vector2(-7, -7 + k * 7), pp + Vector2(7, -7 + k * 7), Color(0.3, 0.25, 0.2), 1.5)
	if _story_wp != Vector2.INF and not interior.active and view.has_point(_story_wp):
		var r2 := 70.0 + sin(t * 4.0) * 8.0
		_markers.draw_arc(_story_wp, r2, 0, TAU, 48, DANFO, 8.0, true)
		_markers.draw_arc(_story_wp, r2, 0, TAU, 48, INK, 2.5, true)


func _star(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5.0
		pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.45))
	_markers.draw_colored_polygon(pts, DANFO)
	pts.append(pts[0])
	_markers.draw_polyline(pts, INK, 2.5, true)


# ---------- abilities from the HUD ----------

func on_ability(a: String) -> void:
	match a:
		"whisperer":
			if main.mode != "driving":
				main.hud.toast("Go-Slow Whisperer works in the danfo.")
				return
			if abilities.use(a):
				main.traffic.release_jam() # the hidden gaps open up
		"stare":
			var target := _nearest_npc(220.0)
			if target.is_empty():
				main.hud.toast("Nobody close enough to Stare at.")
				return
			if abilities.use("stare", target["id"]):
				var victims: Array = [target["node"]]
				if abilities.tier("stare") >= 2:
					# Tier 2 (after Generator Wars): the Stare works on groups of up to 4.
					var pool: Array = interior._npcs.values() if interior.active else npcs.values() + ambient.values() + main.crowd.people
					for n in pool:
						if victims.size() >= 4:
							break
						if n != target["node"] and (n as Node2D).position.distance_to(story_focus()) < 280.0:
							victims.append(n)
				for v in victims:
					var node: Node2D = v
					if node.has_method("freeze"):
						node.freeze(abilities.stare_seconds())
					else:
						node.target = Vector2.INF
						node.idle_t = abilities.stare_seconds()
				subtitle(["\"…I'll pay. I'll pay! Just stop looking at me like that!\"", "\"Aunty, I confess! It was me that finished the meat!\"", "\"Ma, I'm sorry for whatever I did, and whatever I'm about to do.\""].pick_random())
		"ajo":
			if not abilities.available("ajo"):
				main.hud.toast("Ajo Network unlocks in Act 1 (\"Ajo Day\").")
				return
			open_keke(true)
		_:
			abilities.use(a)


func _nearest_npc(radius: float) -> Dictionary:
	var focus := story_focus()
	var best := {}
	var bd := radius
	var pool: Dictionary = interior._npcs if interior.active else npcs
	for id in pool:
		var n: Node2D = pool[id]
		var d := n.position.distance_to(focus)
		if d < bd:
			bd = d
			best = { "id": id, "node": n }
	if best.is_empty() and not interior.active:
		for p in main.crowd.people:
			var n: Node2D = p
			var d := n.position.distance_to(focus)
			if d < bd:
				bd = d
				best = { "id": "ped", "node": n }
	return best


# ---------- hero switching (free roam) ----------

func can_switch() -> String:
	if not Story.switching:
		return "Switching unlocks after the Prologue."
	if runner.running():
		return "Finish (or quit) the mission first."
	if interior.active:
		return "Not now."
	return ""


func switch_hero(to: String) -> void:
	if to == Life.hero:
		return
	var why := can_switch()
	if why != "":
		main.hud.toast(why)
		return
	main.hud.phone.visible = false
	var cold := Story.rel(Life.hero, to) < 30
	var bank: Array = Story.chats.get("switch_cold", []) if cold else Story.chats.get("switch", {}).get(to, [])
	if not bank.is_empty():
		_busy += 1
		await chat.play(bank.pick_random(), "Family Meeting 🔥" if Story.flag("group_chat") else "Phone", to)
		_busy -= 1
	_do_switch(to, Vector2.INF)


func _do_switch(to: String, at: Vector2) -> void:
	Telemetry.event("switch_hero", { "to": to })
	_force_walk()
	var res: Dictionary = Story.swap_hero(to, main.player.position)
	_apply_hero_look()
	var pos: Vector2 = at
	if pos == Vector2.INF:
		pos = res["pos"]
	if pos == Vector2.INF or (not interior.active and main.map.is_blocked(pos)):
		pos = main.map.landmarks[Story.HERO_HOME[to]]["pos"]
	if interior.active:
		interior.player.position = pos
	else:
		main.player.position = pos
		main.player.target = Vector2.INF
		main.camera.reset_smoothing()
	var ev: Dictionary = res["event"]
	if not ev.is_empty():
		_busy += 1
		await dialogue.play([{ "who": "tip", "text": "%s %s" % [ev.get("title", ""), ev.get("text", "")] }])
		_busy -= 1
	SaveGame.save_now()


func _force_walk() -> void:
	if main.mode == "driving":
		main.mode = "walking"
		main.player.position = main.danfo.position + Vector2.from_angle(main.danfo.heading + PI / 2) * 60.0
		main.player.visible = true
		main.camera.reparent(main.player, false)
		main.camera.position = Vector2.ZERO


func _force_drive() -> void:
	if main.mode != "driving":
		main.mode = "driving"
		main.player.visible = false
		main.camera.reparent(main.danfo, false)
		main.camera.position = Vector2.ZERO


# ---------- phone apps ----------

func _add_phone_apps() -> void:
	var phone: Control = main.hud.phone
	phone.add_app("Story", func() -> void: _build_story_app(phone))
	phone.add_app("Switch", func() -> void: _build_switch_app(phone))
	phone.add_app("Keke", func() -> void:
		phone.visible = false
		open_keke(false))


func _build_story_app(phone: Control) -> void:
	phone._clear("Up NEPA!")
	phone._label("Story money ₦s %s · Family trust %d%% · Diary pages %d/%d · Evidence %d" % [Life.fmt_naira(Story.story_money), Story.family_rel(), Story.diary_pages, Story.PAGES_FOR_D, Story.evidence], 14, DANFO)
	if Story.is_done("2.8"):
		var bits: Array = []
		for b in Story.BLOCS:
			bits.append("%s %d" % [Story.BLOC_NAME[b], int(Story.blocs[b])])
		phone._label("WIEC poll · Teacher %d%%: %s" % [Story.teacher_support(), ", ".join(bits)], 13, PAPER)
	if Story.flag("story_complete"):
		phone._label("THE END · Ending %s. Replay to find the others." % String(Story.flag("ending")), 15, DANFO)
		var rb := Button.new()
		rb.text = "Start the story again (keep your money and skills)"
		rb.pressed.connect(func() -> void: _replay_story(phone))
		phone._screen.add_child(rb)
	if runner.running():
		var m: Dictionary = runner.mission
		phone._label("NOW: %s · %s" % [m["id"], m["title"]], 18)
		var q := Button.new()
		q.text = "Quit this mission"
		q.pressed.connect(func() -> void:
			runner.abort()
			_build_story_app(phone))
		phone._screen.add_child(q)
	for id in Story.order:
		var m: Dictionary = Story.missions[id]
		var state := "✓" if Story.is_done(id) else ("★" if Story.requirements_met(id) else "🔒")
		var who: String = "All" if m["hero"] in ["all", "any"] else Story.HERO_NAME[m["hero"]]
		phone._label("%s  %s · %s  (%s)" % [state, id, m["title"], who], 16, PAPER if Story.requirements_met(id) else Color(1, 1, 1, 0.45))
		if not Story.is_done(id) and Story.requirements_met(id) and not m.get("auto", false):
			var p := _start_pos(id)
			var b := Button.new()
			b.text = "Set GPS to the start"
			var pos := p
			b.pressed.connect(func() -> void:
				phone.visible = false
				main._set_waypoint(pos))
			phone._screen.add_child(b)
	phone._label("Act 2 opens in any order; Act 3 follows the Midpoint. Hidden diary pages glow on the street.", 12, Color(1, 1, 1, 0.5))


## New story run: progress and story flags reset; wallet, skills and found diary pages stay.
func _replay_story(phone: Control) -> void:
	phone.visible = false
	var keep := {}
	for f in Life.flags:
		if String(f).begins_with("got_page"):
			keep[f] = Life.flags[f]
	Story.reset()
	Life.flags = keep
	Story.diary_pages = keep.size()
	runner.start("P1")


func _build_switch_app(phone: Control) -> void:
	phone._clear("Family Meeting 🔥" if Story.flag("group_chat") else "Switch hero")
	var why := can_switch()
	if why != "":
		phone._label(why, 15, DANFO)
	for h in Story.HEROES:
		var row := HBoxContainer.new()
		var tex := TextureRect.new()
		tex.texture = Art.tex("portraits/%s.png" % h)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(72, 72)
		row.add_child(tex)
		var b := Button.new()
		b.text = Story.HERO_NAME[h] + (" (you)" if h == Life.hero else "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = h == Life.hero or why != ""
		var hero: String = h
		b.pressed.connect(func() -> void: switch_hero(hero))
		row.add_child(b)
		phone._screen.add_child(row)
	phone._label("Trust: Tunde–Aunty %d · Tunde–KC %d · Aunty–KC %d" % [Story.rel("tunde", "ngozi"), Story.rel("tunde", "kc"), Story.rel("ngozi", "kc")], 13, Color(1, 1, 1, 0.6))


## Keke rides: pay by distance (time passes), or ride free on the Ajo Network.
func open_keke(free: bool) -> void:
	if runner.running():
		main.hud.toast("Finish the mission first.")
		return
	if main.mode == "driving":
		main.hud.toast("You're already driving!")
		return
	var root: Control = main.hud._root
	var card: VBoxContainer = main.hud._card(root, "Ajo Network keke (free)" if free else "Hail a keke", "Where to?" if not free else "Mama Nkem's trusted keke man. One free ride today.", true)
	var dlg: Control = main.hud._dialog_root(card)
	var focus: Vector2 = main.player.position
	var ids: Array = main.map.landmarks.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return main.map.landmarks[a]["name"] < main.map.landmarks[b]["name"])
	for id in ids:
		var l: Dictionary = main.map.landmarks[id]
		var dist := focus.distance_to(l["pos"])
		if dist < 400.0:
			continue
		var fare := 0 if free else int(round((300.0 + dist / 64.0 * 12.0) / 50.0)) * 50
		var mins := int(dist / 350.0) + 5
		var b: Button = main.hud._button("%s · %s · %d min" % [l["name"], "free" if free else "₦" + Life.fmt_naira(fare), mins], func() -> void:
			if fare > 0 and not Life.spend(fare, "Keke to " + String(l["name"])):
				return
			if free:
				abilities.spend_ajo()
			dlg.queue_free()
			Clock.advance(mins)
			main.player.position = l["pos"] + Vector2(0, 40)
			main.player.target = Vector2.INF
			main.camera.reset_smoothing()
			main.hud.toast("Keke man: \"We don reach. Mind your head.\""))
		card.add_child(b)
	card.add_child(main.hud._button("Waka pass (cancel)", func() -> void: dlg.queue_free()))


# ---------- passenger votes ----------

func _show_vote(v: Dictionary) -> void:
	if is_instance_valid(_vote_box):
		return
	var root: Control = main.hud._root
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.offset_top = 150
	var q := _outlined_label(22)
	q.text = String(v["q"])
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(q)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_vote_box = box
	var pick := func(i: int) -> void:
		if not is_instance_valid(box):
			return
		box.queue_free()
		subtitle(chase.resolve_vote(i), 4.0)
	for i in 2:
		var b: Button = main.hud._button(String(v["a" if i == 0 else "b"]), func() -> void: pick.call(i))
		b.custom_minimum_size = Vector2(240, 58)
		row.add_child(b)
	root.add_child(box)
	await get_tree().create_timer(0.6 if auto else 5.0).timeout
	pick.call(randi() % 2)


# ---------- story_* API used by MissionRunner ----------

func story_begin(m: Dictionary) -> void:
	_set_objective("")
	_banner.text = "%s\n%s" % [m.get("act", ""), m.get("title", "")]
	_banner.visible = true
	_auto_shot("begin-" + String(m["id"]))
	await get_tree().create_timer(0.6 if auto else 2.2).timeout
	_banner.visible = false


func story_complete(m: Dictionary, rewards: Dictionary) -> void:
	var bits: Array = []
	if rewards.has("story_money"):
		bits.append("₦s +%s" % Life.fmt_naira(int(rewards["story_money"])))
	for s in rewards.get("xp", {}):
		bits.append("%s XP +%d" % [String(s).capitalize(), int(rewards["xp"][s])])
	for a in rewards.get("ability", {}):
		bits.append("Unlocked: %s" % Abilities.LABELS.get(a, a))
	for s in rewards.get("stats", {}):
		bits.append("%s +%d" % [String(s).capitalize(), int(rewards["stats"][s])])
	if rewards.get("unlock_switching", false):
		bits.append("Hero switching unlocked")
	_banner.text = "MISSION COMPLETE\n%s\n%s" % [m.get("title", ""), "  ·  ".join(bits)]
	_banner.visible = true
	main.hud.toast("Baba God dey!" if Life.hero == "tunde" else ("Write it down." if Life.hero == "ngozi" else "Like and subscribe!"))
	_auto_shot("done-" + String(m["id"]))
	SaveGame.save_now()
	await get_tree().create_timer(0.6 if auto else 3.0).timeout
	_banner.visible = false


func story_checkpoint() -> void:
	if not main.demo:
		SaveGame.save_now()


func story_fail(text: String) -> bool:
	_busy += 1
	story_cleanup_soft()
	if auto:
		_busy -= 1
		push_warning("story-auto: mission step failed: " + text)
		return true
	var root: Control = main.hud._root
	var card: VBoxContainer = main.hud._card(root, "Mission failed", text)
	var dlg: Control = main.hud._dialog_root(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var emitter := Node.new()
	emitter.add_user_signal("picked", [{ "name": "retry", "type": TYPE_BOOL }])
	add_child(emitter)
	row.add_child(main.hud._button("Try again", func() -> void: emitter.emit_signal("picked", true)))
	row.add_child(main.hud._button("Quit mission", func() -> void: emitter.emit_signal("picked", false)))
	var retry: bool = await Signal(emitter, "picked")
	emitter.queue_free()
	dlg.queue_free()
	_busy -= 1
	return retry


func story_cleanup_soft() -> void:
	chase.stop()
	_attach_load(false)
	_banter = ""


func story_cleanup() -> void:
	story_cleanup_soft()
	story_npc_clear("")
	if interior.active:
		interior.exit()
	story_waypoint(Vector2.INF)
	main.traffic.clear_jam()
	Story.set_flag("live_mission", false)


func story_where(s: String) -> Vector2:
	if s.begins_with("room:"):
		return interior.where(s)
	var id := s.trim_prefix("npc:")
	if interior.active and interior.npc(id):
		return interior.npc(id).position
	if npcs.has(id):
		return (npcs[id] as Node2D).position
	return Vector2.INF


func story_focus() -> Vector2:
	if interior.active:
		return interior.focus()
	return main.danfo.position if main.mode == "driving" else main.player.position


func story_mode() -> String:
	return "interior" if interior.active else main.mode


func story_paused() -> bool:
	return _busy > 0 or main.hud.phone.visible


func story_waypoint(p: Vector2) -> void:
	if p != _story_wp:
		_auto_t = 0.6
	_story_wp = p
	_auto_wp = p
	if interior.active:
		interior.waypoint = p
	elif p != main.waypoint:
		main._set_waypoint(p)


func story_toast(text: String, big: bool) -> void:
	main.hud.toast(text, big)


func story_dialogue(lines: Array) -> Array:
	_busy += 1
	_auto_shot("say")
	var picked: Array = await dialogue.play(lines)
	_busy -= 1
	return picked


func story_panels(list: Array) -> void:
	_busy += 1
	_auto_shot("panel")
	await panels.play(list)
	_busy -= 1


func story_chat(lines: Array, title: String) -> void:
	_busy += 1
	await chat.play(lines, title, Life.hero)
	_busy -= 1


func story_minigame(game: String, params: Dictionary) -> Dictionary:
	_busy += 1
	var res: Dictionary
	_auto_shot("game-" + game)
	if game == "pos":
		res = await main.hud.pos_game.play(params)
	else:
		var g: MiniGame = _games[game]
		res = await g.play(params)
	_busy -= 1
	print("story: minigame %s -> %s" % [game, res])
	Telemetry.event("minigame", { "game": game, "score": int(res.get("score", 0)) })
	return res


func story_switch(hero: String, chat_id: String, at: Vector2) -> void:
	if chat_id != "":
		await story_chat(Story.chats.get("scripted", {}).get(chat_id, []), "Family Meeting 🔥")
	if hero == Life.hero and at == Vector2.INF:
		return
	if hero == Life.hero:
		if interior.active:
			interior.player.position = at
		else:
			_force_walk()
			main.player.position = at
			main.camera.reset_smoothing()
		return
	if hero != "tunde":
		_force_walk()
	var res: Dictionary = Story.swap_hero(hero, story_focus())
	_apply_hero_look()
	var pos := at if at != Vector2.INF else (res["pos"] as Vector2)
	if pos == Vector2.INF:
		pos = main.map.landmarks[Story.HERO_HOME[hero]]["pos"]
	if interior.active:
		interior.player.position = pos
	else:
		main.player.position = pos
		main.camera.reset_smoothing()


func story_place(s: Dictionary, pos: Vector2) -> void:
	if s.get("danfo", false):
		main.danfo.position = pos
		main.danfo.heading = deg_to_rad(float(s.get("heading", 0.0)))
		main.danfo.speed = 0.0
		main.danfo.queue_redraw()
		if s.get("driving", false):
			main.player.position = pos
			_force_drive()
	else:
		_force_walk()
		main.player.position = pos
	main.camera.reset_smoothing()


func story_interior(room: String, spawn: String) -> void:
	interior.enter(room, spawn, Story.HERO_SHEET[Life.hero], main.painted_mat)
	interior.set_dark(not main.nepa_on)


func story_exit_interior() -> void:
	interior.exit()


func story_npc(id: String, who: String, pos: Vector2, s: Dictionary) -> void:
	story_npc_clear(id)
	var n: Node2D = NpcScript.new()
	n.setup(id, who)
	n.material = main.painted_mat
	var in_room: bool = interior.active and (String(s.get("at", "")).begins_with("room:") or String(s.get("at", "")) == "hero" or String(s.get("at", "")).begins_with("npc:"))
	if in_room:
		interior.add_npc(id, n, pos)
	else:
		n.position = pos
		main.streamer.add_child(n)
		npcs[id] = n


func story_npc_clear(id: String) -> void:
	interior.clear_npcs(id)
	for k in npcs.keys():
		if id == "" or k == id:
			(npcs[k] as Node).queue_free()
			npcs.erase(k)


func story_expect(ability: String, detail: String, _s: Dictionary) -> void:
	_expect = ability
	_expect_detail = detail
	if ability == "":
		if abilities.filming and auto:
			abilities.filming = false
		return
	if auto:
		await get_tree().create_timer(0.4).timeout
		match ability:
			"film":
				abilities.filming = true
			"conductor":
				abilities.cooldowns.erase("conductor")
				abilities.use("conductor", detail)
			"whisperer":
				abilities.cooldowns.erase(ability)
				if abilities.use(ability):
					main.traffic.release_jam()
			"stare":
				abilities.cooldowns.erase("stare")
				abilities.use("stare", detail)
			_:
				abilities.cooldowns.erase(ability)
				abilities.use(ability, detail)


func story_filming() -> bool:
	return abilities.filming


func story_jam(pos: Vector2) -> void:
	main.traffic.jam(pos, main.danfo.position)


func story_chase_start(s: Dictionary) -> void:
	var focus := story_focus()
	if s.get("on", "") == "watch":
		var ids: Array = []
		var ws: Array = s.get("watchers", [])
		for i in ws.size():
			var wid := "watch-%d" % i
			story_npc(wid, ws[i]["who"], runner.resolve(ws[i]["at"], ws[i].get("offset")), {})
			ids.append(wid)
		var s2 := s.duplicate()
		s2["chasers"] = ids
		chase.start(s2, focus, 0.0, npcs)
		_attach_load(true)
		_auto_shot("sneak")
		return
	var heading: float = main.danfo.heading if main.mode == "driving" else (focus - main.map.landmarks[Story.HERO_HOME["kc"]]["pos"]).angle()
	chase.start(s, focus, heading, npcs)
	if s.get("on", "danfo") == "danfo":
		_banter = "chase"
		_banter_t = 3.0
	_auto_shot("chase")


func story_chase_state() -> Dictionary:
	return chase.state()


## The 60 kVA generator the hero pushes during Generator Wars.
var _load: Sprite2D


func _attach_load(on: bool) -> void:
	if is_instance_valid(_load):
		_load.queue_free()
	if not on:
		return
	_load = Sprite2D.new()
	_load.texture = Art.tex("props/generator.png")
	_load.scale = Vector2(1.3, 1.3)
	_load.position = Vector2(30, -18)
	_load.material = main.painted_mat
	main.player.add_child(_load)


func story_chase_end() -> void:
	var watch := chase.on == "watch"
	_attach_load(false)
	chase.stop()
	_banter = ""
	if watch:
		for k in npcs.keys():
			if String(k).begins_with("watch-"):
				story_npc_clear(k)


func story_nepa(v: String) -> void:
	match v:
		"off":
			main._set_nepa(false)
		"on":
			main._set_nepa(true)
		"auto":
			main.nepa_forced = -1
	if interior.active:
		interior.set_dark(v == "off")


func story_banter(bank: String) -> void:
	_banter = bank
	_banter_t = 4.0
	if bank == "":
		_subtitle.text = ""


# ---------- autoplay (QA) ----------

func _auto_tick(dt: float) -> void:
	if not runner.running() or _busy > 0:
		return
	if _auto_wp == Vector2.INF:
		return
	_auto_t -= dt
	if _auto_t > 0.0:
		return
	_auto_t = 0.6
	var p := _auto_wp
	if interior.active:
		interior.player.position = p
		return
	var step: Dictionary = runner.mission.get("steps", [])[runner.step_index] if runner.step_index < runner.mission.get("steps", []).size() else {}
	var need: String = step.get("need", "")
	if (need == "driving" or step.get("on", "") == "danfo") and main.mode != "driving":
		main.danfo.position = main.player.position
		_force_drive()
	if main.mode == "driving":
		main.danfo.position = p
		main.danfo.speed = 0.0
	else:
		main.player.position = p
	main.camera.reset_smoothing()


## Fire-and-forget screenshot a moment after a story beat appears (story autoplay only).
func _auto_shot(tag: String) -> void:
	if not auto or main.shots_dir == "":
		return
	_shot_n += 1
	await get_tree().create_timer(0.08).timeout
	await main._shot("story-%03d-%s-%s" % [_shot_n, String(runner.mission.get("id", "x")).replace(".", "_"), tag])
