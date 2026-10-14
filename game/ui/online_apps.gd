class_name OnlineApps
extends Node
## Phone apps for the M5 online features (server: apps/server/src/*.ts):
##   Chat    street chat (moderated on the server), DMs, block and report
##   Gigs    F1 gig board (game money): browse, take, play the skill's mini-game, post, wallet
##   Profile F2 profile and in-game CV, phone verification (OTP)
##   Vote    F4 ward election (run, vote, receipt, results) and community polls
## Everything degrades gracefully offline: the apps say what's needed instead of failing.

const PAPER := Color("#f1e6c8")
const DANFO := Color("#e0a91c")
const DIM := Color(1, 1, 1, 0.55)
const GOOD := Color("#9fd38a")
const BAD := Color("#e8a090")
## Which mini-game proves each skill (completing a gig is gameplay, proposal F1).
const SKILL_GAME := { "cooking": "jollof", "filming": "spray", "haggling": "pos", "driving": "dodge", "charisma": "debate", "hustle": "counting" }
const SKILLS := ["driving", "cooking", "haggling", "filming", "charisma", "hustle"]
const DISTRICTS := ["ikeja", "agbado-ketu", "oshodi", "mushin", "yaba", "surulere", "lagos-island", "ikoyi", "victoria-island", "lekki"]
const REAL_SKILLS := ["photography", "video", "design", "catering", "tutoring", "delivery", "driving", "tailoring", "music", "comedy", "coding", "hair", "makeup", "events"]
const LANGS := ["English", "Pidgin", "Yoruba", "Igbo", "Hausa"]
const ERRORS := {
	"verify_phone": "Verify your phone first (Profile → Verify phone).",
	"too_new": "New accounts can post after 24 hours (or once verified).",
	"muted": "You're muted for now. Check your messages from the moderators.",
	"slow_down": "Easy! Wait a few seconds.",
	"blocked_personal_data": "Not sent: no phone numbers or emails in chat.",
	"blocked_off_platform_payment": "Not sent: no payment details or off-platform deals.",
	"blocked_links_need_verification": "Links need a verified phone.",
	"blocked_abuse": "Not sent: keep it respectful.",
	"blocked_hate": "Not sent. That's against the rules.",
	"held_for_review": "Held for a moderator to check.",
	"insufficient": "Not enough money in your market wallet.",
	"offline": "You're offline. Set your server in Settings → Online.",
	"too_fast": "Finish the job properly first!",
	"daily_cap": "Daily transfer limit reached (₦50,000).",
	"not_eligible": "Not eligible yet: verified, 14+ days, level 8+, no strikes.",
	"polls_closed": "Polling units open Sunday 10:00–18:00.",
	"not_nomination": "Nominations are Monday and Tuesday.",
}

var phone: Control
var host: Node # StoryHost: mini-games and HUD
var street: Array = [] # last street chat messages
var policies := {} # ward -> {id, name, effect}
var _policy_t := 0.0
var _phone_otp := ""
## M6: published news banter by archetype ({text, outlet, url}) and today's archetype moods.
var news_lines := {} # archetype -> Array of line dictionaries
var moods := {} # archetype -> {stance, topic}
var live_chat := false
var _news_t := 3.0
## Which archetype each named NPC speaks for.
const NPC_ARCHETYPE := { "mama-nkem": "traders", "market-woman": "traders", "sule": "drivers", "mechanic": "okada", "barber": "youth", "kiosk": "students", "teacher": "church", "bayo": "drivers", "receipts": "traders", "warden": "drivers" }


func setup(p: Control, story_host: Node) -> void:
	phone = p
	host = story_host
	phone.add_app("Chat", func() -> void: _chat_home())
	phone.add_app("Gigs", func() -> void: _gigs_board(""))
	phone.add_app("Profile", func() -> void: _profile())
	phone.add_app("Vote", func() -> void: _vote())
	Net.chat.connect(func(m: Dictionary) -> void:
		street.append(m)
		if street.size() > 40:
			street.pop_front()
		host.main.hud.toast("💬 %s: %s" % [m.get("name", ""), String(m.get("text", "")).left(60)])
		if phone.visible and phone._title.text == "Street chat":
			_chat_home())
	Net.dm.connect(func(m: Dictionary) -> void:
		if not m.get("sent", false):
			host.main.hud.toast("✉ %s: %s" % [m.get("name", ""), String(m.get("text", "")).left(60)]))
	Net.server_error.connect(func(code: String) -> void:
		if ERRORS.has(code):
			host.main.hud.toast(ERRORS[code]))


func _process(delta: float) -> void:
	_policy_t -= delta
	if _policy_t <= 0.0:
		_policy_t = 600.0
		_refresh_policies()
	_news_t -= delta
	if _news_t <= 0.0:
		_news_t = 900.0
		_refresh_news()


# ---------- news banter and moods (M6) ----------

func _refresh_news() -> void:
	if Net.server == "":
		return
	var b: Dictionary = await Net.api("GET", "/api/banter")
	if b["ok"]:
		news_lines.clear()
		for l in b["data"].get("lines", []):
			var a := String(l.get("archetype", ""))
			if not news_lines.has(a):
				news_lines[a] = []
			news_lines[a].append(l)
	var m: Dictionary = await Net.api("GET", "/api/brains/moods")
	if m["ok"]:
		moods = m["data"].get("moods", {})
	var p: Dictionary = await Net.api("GET", "/api/npc/personas")
	if p["ok"]:
		live_chat = bool(p["data"].get("live", false))


## A news line for an archetype (or any), with its source credit; {} when off or none.
func news_line(archetype: String = "") -> Dictionary:
	if not Settings.get_pref("news_chatter", true) or news_lines.is_empty():
		return {}
	var pool: Array = news_lines.get(archetype, []) if archetype != "" else []
	if pool.is_empty():
		for k in news_lines:
			pool += news_lines[k]
	return pool.pick_random() if not pool.is_empty() else {}


static func credit(line: Dictionary) -> String:
	return "%s  📰 via %s" % [line.get("text", ""), line.get("outlet", "?")]


func mood(archetype: String) -> String:
	return String(moods.get(archetype, {}).get("stance", "chill"))


## Ask a named NPC something (F8 live chat; verified players, capped, logged, reportable).
func ask_npc(who: String) -> void:
	var root: Control = host.main.hud._root
	var card: VBoxContainer = host.main.hud._card(root, "Talk to %s" % Story.who(who).get("name", who), "Say something. Keep it friendly. They know today's gist.")
	var dlg: Control = host.main.hud._dialog_root(card)
	var e := LineEdit.new()
	e.placeholder_text = "Your message"
	e.custom_minimum_size = Vector2(0, 44)
	card.add_child(e)
	var out := Label.new()
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(out)
	var last_id := [0]
	var row := HBoxContainer.new()
	card.add_child(row)
	row.add_child(host.main.hud._button("Send", func() -> void:
		if e.text.strip_edges() == "":
			return
		out.text = "…"
		var res: Dictionary = await Net.api("POST", "/api/npc/talk", { "npc": who, "text": e.text.strip_edges() })
		e.text = ""
		if res["ok"]:
			out.text = String(res["data"].get("reply", ""))
			last_id[0] = int(res["data"].get("id", 0))
			if host.ambient.has(who):
				host.ambient[who].say(out.text.left(60), 5.0)
		else:
			out.text = { "daily_cap": "That's enough gist for today. Come back tomorrow.", "live_chat_off": "They're busy right now.", "verify_phone": "Verify your phone to chat with NPCs." }.get(res["data"].get("error", ""), _err(res))))
	row.add_child(host.main.hud._button("Report reply", func() -> void:
		if last_id[0] > 0:
			await Net.api("POST", "/api/npc/talk/%d/report" % last_id[0])
			host.main.hud.toast("Reported. Thank you.")))
	row.add_child(host.main.hud._button("Bye", func() -> void: dlg.queue_free()))


# ---------- helpers ----------

func _err(res: Dictionary) -> String:
	var d: Variant = res.get("data", {})
	var code := String(d.get("error", "")) if d is Dictionary else ""
	if code == "" and int(res.get("code", 0)) == 0:
		code = "offline"
	return ERRORS.get(code, "Something went wrong (%s)." % (code if code != "" else str(res.get("code"))))


func _btn(text: String, cb: Callable, parent: Node = null) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	(parent if parent else phone._screen).add_child(b)
	return b


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	phone._screen.add_child(r)
	return r


func _edit(placeholder: String, text := "", parent: Node = null) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size = Vector2(0, 42)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(parent if parent else phone._screen).add_child(e)
	return e


func _options(items: Array, selected: String, parent: Node = null) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(String(items[i]).capitalize())
		if items[i] == selected:
			o.select(i)
	(parent if parent else phone._screen).add_child(o)
	return o


func _tabs(current: String, tabs: Dictionary) -> void:
	var r := _row()
	for name in tabs:
		var b := _btn(name, tabs[name], r)
		b.disabled = name == current
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _offline_note() -> bool:
	if Net.server == "":
		phone._label("Online features need your server: Settings → Online.", 15, DANFO)
		return true
	return false


# ---------- Chat ----------

func _chat_home() -> void:
	phone._clear("Street chat")
	_tabs("Street", { "Street": _chat_home, "DMs": _dm_threads })
	if _offline_note():
		return
	phone._label("%s · be nice: messages are checked before anyone sees them." % Net.status_text(), 12, DIM)
	if not moods.is_empty():
		var bits: Array = []
		for a in moods:
			if mood(a) != "chill":
				bits.append("%s %s" % [String(a).capitalize(), mood(a)])
		if not bits.is_empty():
			phone._label("Street mood: " + ", ".join(bits), 12, DANFO)
	for m in street.slice(maxi(0, street.size() - 25)):
		var r := _row()
		var l := Label.new()
		l.text = "%s%s: %s" % [m.get("name", ""), " ✓" if m.get("v", false) else "", m.get("text", "")]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", PAPER)
		r.add_child(l)
		if String(m.get("pid", "")) != "":
			var msg: Dictionary = m
			var more := _btn("…", func() -> void: _person_menu(msg), r)
			more.custom_minimum_size = Vector2(40, 36)
	var r2 := _row()
	var e := _edit("Say something…", "", r2)
	var send := func() -> void:
		if e.text.strip_edges() != "":
			Net.send_chat(e.text.strip_edges())
			e.text = ""
	e.text_submitted.connect(func(_t: String) -> void: send.call())
	_btn("Send", send, r2)


func _person_menu(m: Dictionary) -> void:
	phone._clear(String(m.get("name", "")))
	var pid := String(m.get("pid", ""))
	phone._label("\"%s\"" % m.get("text", ""), 14, DIM)
	_btn("Message privately", func() -> void: _dm_thread(pid, String(m.get("name", ""))))
	_btn("View profile", func() -> void: _profile_view(pid))
	_btn("Block (hide their chat and DMs)", func() -> void:
		var res: Dictionary = await Net.api("POST", "/api/blocks", { "pid": pid })
		host.main.hud.toast("Blocked." if res["ok"] else _err(res))
		street = street.filter(func(x: Dictionary) -> bool: return x.get("pid", "") != pid)
		_chat_home())
	for reason in ["Spam or scam", "Abuse or hate", "Personal data", "Something else"]:
		var why: String = reason
		_btn("Report: " + why, func() -> void:
			var res: Dictionary = await Net.api("POST", "/api/reports", { "message": int(m.get("id", 0)), "reason": why })
			host.main.hud.toast("Reported. A moderator will look at it. Thank you." if res["ok"] else _err(res))
			_chat_home())


func _dm_threads() -> void:
	phone._clear("Messages")
	_tabs("DMs", { "Street": _chat_home, "DMs": _dm_threads })
	if _offline_note():
		return
	var res: Dictionary = await Net.api("GET", "/api/dms/threads")
	if not res["ok"]:
		phone._label(_err(res), 14, BAD)
		return
	var threads: Array = res["data"].get("threads", [])
	if threads.is_empty():
		phone._label("No messages yet. Tap \"…\" next to someone in street chat to message them.", 14, DIM)
	for t in threads:
		var th: Dictionary = t
		_btn("%s: %s" % [th.get("name", ""), String(th.get("last_text", "")).left(30)], func() -> void: _dm_thread(String(th["pid"]), String(th.get("name", ""))))


func _dm_thread(pid: String, name_: String) -> void:
	phone._clear(name_)
	var res: Dictionary = await Net.api("GET", "/api/dms?with=" + pid)
	if res["ok"]:
		for m in res["data"].get("messages", []):
			var mine := String(m.get("pid", "")) != pid
			phone._label(("You: " if mine else String(m.get("name", "")) + ": ") + String(m.get("text", "")), 15, DANFO if mine else PAPER)
	var r := _row()
	var e := _edit("Message…", "", r)
	_btn("Send", func() -> void:
		if e.text.strip_edges() == "":
			return
		Net.send_dm(pid, e.text.strip_edges())
		await get_tree().create_timer(0.4).timeout
		_dm_thread(pid, name_), r)


# ---------- Gigs ----------

func _gigs_board(skill: String) -> void:
	phone._clear("Gig board")
	_tabs("Board", { "Board": func() -> void: _gigs_board(""), "Mine": _gigs_mine, "Post": _gigs_post, "Wallet": _wallet })
	if _offline_note():
		return
	var r := _row()
	for s in [""] + SKILLS:
		var sk: String = s
		var b := _btn("All" if s == "" else s.left(5).capitalize(), func() -> void: _gigs_board(sk), r)
		b.disabled = s == skill
		b.custom_minimum_size = Vector2(0, 36)
	var res: Dictionary = await Net.api("GET", "/api/gigs" + ("?skill=" + skill if skill != "" else ""))
	if not res["ok"]:
		phone._label(_err(res), 14, BAD)
		return
	for g in res["data"].get("gigs", []):
		var gig: Dictionary = g
		phone._label("%s\n₦%s · %s · %s · by %s%s · %d/%d taken" % [gig["title"], Life.fmt_naira(int(gig["pay"])), String(gig["skill"]).capitalize(), String(gig["district"]).capitalize(), gig.get("by", "?"), (" ★%.1f" % float(gig["rating"])) if gig.get("rating") != null else "", int(gig["filled"]), int(gig["slots"])], 15)
		phone._label(String(gig.get("description", "")), 12, DIM)
		_btn("Take this gig", func() -> void:
			var t: Dictionary = await Net.api("POST", "/api/gigs/%d/take" % int(gig["id"]))
			if t["ok"]:
				host.main.hud.toast("Gig taken. Play it from Gigs → Mine.")
				_gigs_mine()
			else:
				host.main.hud.toast(_err(t)))


func _gigs_mine() -> void:
	phone._clear("My gigs")
	_tabs("Mine", { "Board": func() -> void: _gigs_board(""), "Mine": _gigs_mine, "Post": _gigs_post, "Wallet": _wallet })
	if _offline_note():
		return
	var res: Dictionary = await Net.api("GET", "/api/gigs/mine")
	if not res["ok"]:
		phone._label(_err(res), 14, BAD)
		return
	phone._label("WORKING", 13, DANFO)
	for g in res["data"].get("working", []):
		var gig: Dictionary = g
		phone._label("%s · ₦%s · %s%s" % [gig["title"], Life.fmt_naira(int(gig["pay"])), gig["status"], (" (%d)" % int(gig["score"])) if gig.get("score") != null else ""], 14)
		if gig["status"] == "accepted":
			_btn("Do the job (%s)" % String(gig["skill"]).capitalize(), func() -> void: _play_gig(gig))
	phone._label("POSTED", 13, DANFO)
	for g in res["data"].get("posted", []):
		var gig: Dictionary = g
		phone._label("%s · %d/%d · %s" % [gig["title"], int(gig["filled"]), int(gig["slots"]), gig["status"]], 14)
		if gig["status"] == "open":
			_btn("Close (refund unfilled slots)", func() -> void:
				var c: Dictionary = await Net.api("POST", "/api/gigs/%d/close" % int(gig["id"]))
				host.main.hud.toast(("Refunded ₦%s to your market wallet." % Life.fmt_naira(int(c["data"].get("refunded", 0)))) if c["ok"] else _err(c))
				_gigs_mine())


## Completing a gig is gameplay: play the skill's mini-game, then report the score.
func _play_gig(gig: Dictionary) -> void:
	phone.visible = false
	var game: String = SKILL_GAME.get(String(gig["skill"]), "quick")
	var res: Dictionary
	if game == "pos":
		res = await host.main.hud.pos_game.play({ "customers": 6, "network_fail": 0.35 })
		res["score"] = int(round(float(res.get("served", 0)) / 6.0 * 100.0))
	else:
		res = await host._games[game].play({ "plates": 20, "pot": 24, "dippers": 2, "stacks": 14, "beats": 20, "bpm": 100 })
	var score := clampi(int(res.get("score", 0)), 0, 100)
	var f: Dictionary = await Net.api("POST", "/api/gigs/%d/finish" % int(gig["id"]), { "score": score })
	if f["ok"] and f["data"].get("passed", false):
		host.main.hud.toast("Job done! ₦%s paid into your market wallet." % Life.fmt_naira(int(f["data"].get("paid", 0))), true)
		Life.add_xp(String(gig["skill"]), 30)
	elif f["ok"]:
		host.main.hud.toast("Not good enough (%d). The client was refunded." % score)
	else:
		host.main.hud.toast(_err(f))


func _gigs_post() -> void:
	phone._clear("Post a gig")
	_tabs("Post", { "Board": func() -> void: _gigs_board(""), "Mine": _gigs_mine, "Post": _gigs_post, "Wallet": _wallet })
	if _offline_note():
		return
	phone._label("Game money only. Pay × slots + 2% fee is held in escrow from your market wallet. No phone numbers or payment details.", 12, DIM)
	var title := _edit("Title (e.g. Cook for my party)")
	var desc := _edit("What's the job?")
	var skill := _options(SKILLS, "cooking")
	var district := _options(DISTRICTS, Net.district)
	var pay := _edit("Pay per person (₦500–20,000)", "3000")
	var slots := _options(["1", "2", "3", "4", "5"], "1")
	_btn("Post gig", func() -> void:
		var res: Dictionary = await Net.api("POST", "/api/gigs", { "title": title.text, "description": desc.text, "skill": SKILLS[skill.selected], "district": DISTRICTS[district.selected], "pay": int(pay.text), "slots": slots.selected + 1 })
		host.main.hud.toast("Posted! ₦%s in escrow." % Life.fmt_naira(int(res["data"].get("escrowed", 0))) if res["ok"] else _err(res))
		if res["ok"]:
			_gigs_mine())


func _wallet() -> void:
	phone._clear("Market wallet")
	_tabs("Wallet", { "Board": func() -> void: _gigs_board(""), "Mine": _gigs_mine, "Post": _gigs_post, "Wallet": _wallet })
	if _offline_note():
		return
	var res: Dictionary = await Net.api("GET", "/api/wallet")
	if not res["ok"]:
		phone._label(_err(res), 14, BAD)
		return
	phone._label("Market ₦%s · Pocket ₦%s" % [Life.fmt_naira(int(res["data"].get("balance", 0))), Life.fmt_naira(Life.money)], 22)
	phone._label("Move game money between your pocket and the market (₦50,000 a day; 5% tax when you take it out).", 12, DIM)
	for amt in [2000, 10000]:
		var a: int = amt
		var r := _row()
		_btn("Put in ₦%s" % Life.fmt_naira(a), func() -> void: _move(a), r)
		_btn("Take out ₦%s" % Life.fmt_naira(a), func() -> void: _move(-a), r)
	phone._label("RECENT", 13, DANFO)
	for e in res["data"].get("ledger", []):
		var d := int(e["delta"])
		phone._label("%s₦%s  %s" % ["+" if d >= 0 else "−", Life.fmt_naira(absi(d)), e["reason"]], 13, GOOD if d >= 0 else BAD)


func _move(amount: int) -> void:
	if amount > 0 and not Life.can_afford(amount):
		host.main.hud.toast("Your pocket doesn't have ₦%s." % Life.fmt_naira(amount))
		return
	var res: Dictionary = await Net.api("POST", "/api/wallet/move", { "amount": amount })
	if res["ok"]:
		var to_save := int(res["data"].get("toSave", 0))
		if to_save < 0:
			Life.spend(-to_save, "Moved to market wallet")
		else:
			Life.earn(to_save, "From market wallet")
		SaveGame.save_now()
	else:
		host.main.hud.toast(_err(res))
	_wallet()


# ---------- Profile and phone verification ----------

func _profile() -> void:
	phone._clear("Profile")
	if _offline_note():
		return
	var me: Dictionary = await Net.api("GET", "/api/me")
	if not me["ok"]:
		phone._label(_err(me), 14, BAD)
		return
	var verified: bool = me["data"].get("verified", false)
	phone._label("%s · %s · strikes %d" % [me["data"].get("name", Net.player_name), ("✓ verified %s" % me["data"].get("phone", "")) if verified else "not verified", int(me["data"].get("strikes", 0))], 16, GOOD if verified else DANFO)
	if not verified:
		_btn("Verify phone (gigs, voting, links)", _verify_phone)
	var p: Dictionary = await Net.api("GET", "/api/profiles/" + String(me["data"].get("id", "")))
	var d: Dictionary = p["data"] if p["ok"] else {}
	phone._label("BIO", 13, DANFO)
	var bio := _edit("A line about you", String(d.get("bio", "") if d.get("bio") != null else ""))
	phone._label("DISTRICT", 13, DANFO)
	var district := _options(DISTRICTS, String(d.get("district", Net.district)))
	phone._label("LANGUAGES", 13, DANFO)
	var langs := {}
	var lr := _row()
	for l in LANGS:
		var c := CheckBox.new()
		c.text = l
		c.button_pressed = l in d.get("languages", [])
		lr.add_child(c)
		langs[l] = c
	phone._label("REAL SKILL (shown on your profile; verified by finishing gigs)", 13, DANFO)
	var skills_in: Array = d.get("skills", []) if d.get("skills") != null else []
	var sk := _options(REAL_SKILLS, String(skills_in[0]["skill"]) if skills_in.size() > 0 else "catering")
	var sk_level := _options(["1", "2", "3", "4", "5"], str(skills_in[0]["level"]) if skills_in.size() > 0 else "1")
	var avail := _options(["open", "busy", "weekends"], String(d.get("availability", "open")))
	var search := CheckBox.new()
	search.text = "Show me in public search (you can change this any time)"
	search.button_pressed = d.get("searchable", false)
	phone._screen.add_child(search)
	var private_cv := CheckBox.new()
	private_cv.text = "Keep my game CV private"
	private_cv.button_pressed = d.get("visibility", {}).get("cv", "members") == "me"
	phone._screen.add_child(private_cv)
	_btn("Save profile", func() -> void:
		var langs_out: Array = []
		for l in langs:
			if (langs[l] as CheckBox).button_pressed:
				langs_out.append(l)
		var cv_skills := {}
		for s in Life.SKILLS:
			cv_skills[s] = Life.level(s)
		var body := {
			"bio": bio.text, "district": DISTRICTS[district.selected], "languages": langs_out,
			"skills": [{ "skill": REAL_SKILLS[sk.selected], "level": sk_level.selected + 1 }],
			"availability": ["open", "busy", "weekends"][avail.selected], "searchable": search.button_pressed,
			"visibility": { "bio": "public", "skills": "public", "experience": "members", "portfolio": "members", "cv": "me" if private_cv.button_pressed else "public", "rate": "members" },
			"cv": { "skills": cv_skills, "missions": Story.done.size(), "ending": Story.flag("ending"), "hero": Life.hero },
		}
		var res: Dictionary = await Net.api("PUT", "/api/profile", body)
		host.main.hud.toast(("Profile saved. Level %d." % int(res["data"].get("level", 1))) if res["ok"] else _err(res)))
	if d.has("gigBadges") and not (d["gigBadges"] as Dictionary).is_empty():
		phone._label("Verified by gigs: " + ", ".join((d["gigBadges"] as Dictionary).keys().map(func(k: String) -> String: return "%s ×%d" % [k.capitalize(), int(d["gigBadges"][k])])), 13, GOOD)


func _profile_view(pid: String) -> void:
	phone._clear("Profile")
	var res: Dictionary = await Net.api("GET", "/api/profiles/" + pid)
	if not res["ok"]:
		phone._label(_err(res), 14, BAD)
		return
	var d: Dictionary = res["data"]
	phone._label("%s%s · level %d" % [d.get("name", ""), " ✓" if d.get("verified", false) else "", int(d.get("level", 1))], 20)
	if d.get("bio") != null:
		phone._label(String(d["bio"]), 14)
	phone._label("%s · %s" % [String(d.get("district", "")).capitalize(), ", ".join(d.get("languages", []))], 13, DIM)
	if d.get("skills") != null:
		for s in d["skills"]:
			phone._label("• %s (%d/5)" % [String(s["skill"]).capitalize(), int(s["level"])], 14)
	if d.get("rating") != null:
		phone._label("★ %.1f from %d gigs" % [float(d["rating"]), int(d.get("ratings", 0))], 14, DANFO)


func _verify_phone() -> void:
	phone._clear("Verify phone")
	phone._label("We text you a 6-digit code. Your number is never shown to anyone and is stored only as a code-like hash.", 13, DIM)
	var num := _edit("Phone number, e.g. 0803 123 4567", _phone_otp)
	var status: Label = phone._label("", 14, DANFO)
	var code := _edit("6-digit code")
	_btn("Send code", func() -> void:
		_phone_otp = num.text
		var res: Dictionary = await Net.api("POST", "/api/auth/otp/start", { "phone": num.text })
		status.text = ("Code sent to %s." % res["data"].get("sentTo", "")) if res["ok"] else ({ "otp_unavailable": "Phone verification isn't set up on this server yet.", "bad_phone": "That number doesn't look right.", "too_many_codes": "Too many codes. Try again in an hour." }.get(res["data"].get("error", ""), _err(res))))
	_btn("Verify", func() -> void:
		var res: Dictionary = await Net.api("POST", "/api/auth/otp/verify", { "phone": num.text, "code": code.text.strip_edges() })
		if not res["ok"]:
			status.text = { "wrong_code": "Wrong code.", "code_expired": "Code expired. Send a new one.", "bad_code": "Enter the 6 digits." }.get(res["data"].get("error", ""), _err(res))
			return
		if res["data"].get("switched", false):
			# This phone already had an account: sign in to it on this device.
			Net.adopt_token(String(res["data"]["token"]))
			host.main.hud.toast("Welcome back, %s! Your account is on this phone now." % res["data"].get("name", ""), true)
			SaveGame.pull_cloud()
		else:
			host.main.hud.toast("Phone verified ✓", true)
		_profile())


# ---------- Vote ----------

func _vote() -> void:
	phone._clear("Vote · WIEC")
	if _offline_note():
		return
	var ward := Net.district
	var res: Dictionary = await Net.api("GET", "/api/elections/" + ward)
	if not res["ok"]:
		phone._label(_err(res), 14, BAD)
		return
	var e: Dictionary = res["data"]
	phone._label("%s ward councillor" % ward.capitalize(), 20)
	phone._label({ "nomination": "Nominations open (Mon–Tue)", "campaign": "Campaign week (Wed–Sat)", "voting": "POLLS OPEN until 18:00", "counted": "Results are in", "frozen": "Frozen for review" }.get(String(e["phase"]), String(e["phase"])), 14, DANFO)
	var results: Variant = e.get("results")
	for c in e.get("candidates", []):
		var cand: Dictionary = c
		var tally := ""
		if results is Dictionary:
			tally = " · %d votes" % int((results as Dictionary).get(str(int(cand["id"])), 0))
		var won := e.get("winner") != null and int(e["winner"]) == int(cand["id"])
		phone._label("%s%s%s\n\"%s\" · %s%s" % ["🏆 " if won else "", cand["name"], " (NPC)" if cand.get("npc", false) else "", cand["slogan"], cand.get("policyName", ""), tally], 15, DANFO if won else PAPER)
		if e["phase"] == "voting" and e.get("myReceipt") == null:
			_btn("Vote for %s" % cand["name"], func() -> void:
				var v: Dictionary = await Net.api("POST", "/api/elections/%d/vote" % int(e["id"]), { "candidate": int(cand["id"]) })
				host.main.hud.toast(("Voted ✓ Receipt %s…" % String(v["data"].get("receipt", "")).left(10)) if v["ok"] else _err(v))
				_vote())
	if e.get("myReceipt") != null:
		phone._label("Your vote receipt: %s… (check it in the public audit)" % String(e["myReceipt"]).left(16), 12, GOOD)
	if e["phase"] == "nomination":
		phone._label("RUN FOR OFFICE · ₦5,000 from your market wallet", 13, DANFO)
		var slogan := _edit("Your slogan (checked by moderators)")
		var keys: Array = (e.get("menu", {}) as Dictionary).keys()
		var pol := _options(keys, keys[0] if keys.size() > 0 else "")
		_btn("Submit nomination", func() -> void:
			var r: Dictionary = await Net.api("POST", "/api/elections/%d/run" % int(e["id"]), { "slogan": slogan.text, "policy": keys[pol.selected] })
			host.main.hud.toast("You're on the ballot!" if r["ok"] else _err(r))
			_vote())
	var here: Dictionary = policies.get(ward, {})
	if not here.is_empty():
		phone._label("In force here: %s (%s)" % [here.get("name", ""), here.get("effect", "")], 13, GOOD)
	phone._label("COMMUNITY POLLS", 13, DANFO)
	var pr: Dictionary = await Net.api("GET", "/api/polls")
	if pr["ok"]:
		for p in pr["data"].get("polls", []):
			var poll: Dictionary = p
			phone._label(String(poll["question"]) + ("  (closed)" if poll.get("closed", false) else ""), 15)
			var opts: Array = poll["options"]
			for i in opts.size():
				var idx: int = i
				var count := ""
				if poll.get("results") != null:
					count = " · %d" % int(poll["results"][i])
				if poll.get("closed", false):
					phone._label("  %s%s" % [opts[i], count], 13, DIM)
				else:
					_btn("%s%s" % [opts[i], count], func() -> void:
						var v: Dictionary = await Net.api("POST", "/api/polls/%d/vote" % int(poll["id"]), { "choices": [idx] })
						host.main.hud.toast("Vote counted." if v["ok"] else ({ "already_voted": "You already voted." }.get(v["data"].get("error", ""), _err(v))))
						_vote())


# ---------- ward policies ----------

func _refresh_policies() -> void:
	if Net.server == "":
		return
	var res: Dictionary = await Net.api("GET", "/api/policies")
	if res["ok"]:
		policies = res["data"].get("policies", {})


## The policy the elected councillor chose for a ward ("" if none).
func policy_in(ward: String) -> String:
	return String(policies.get(ward, {}).get("id", ""))
