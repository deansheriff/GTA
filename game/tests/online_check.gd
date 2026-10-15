extends SceneTree
## End-to-end check of the M5 client against a running dev server:
##   (server) OTP_DEV_ECHO=1 CHAT_MIN_AGE_HOURS=0 GIG_MIN_SECONDS=0 npm run dev:server
##   Godot --headless --path game --script res://tests/online_check.gd -- --server=localhost:8787

var failures := 0
var passes := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	await process_frame
	var net: Node = root.get_node("Net")
	var server := "localhost:8787"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			server = a.trim_prefix("--server=")
	net.server = server
	net.token = ""
	net.player_name = "OnlineCheck"
	net.start({ "look": {}, "x": 3000, "y": 3000 })
	var t0 := Time.get_ticks_msec()
	while net.my_id < 0 and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	check(net.my_id >= 0 and net.token != "", "client connects and receives a guest token")

	var me: Dictionary = await net.api("GET", "/api/me")
	check(me["ok"] and me["data"].get("verified") == false, "GET /api/me as a guest")
	var start: Dictionary = await net.api("POST", "/api/auth/otp/start", { "phone": "0809%07d" % (randi() % 10000000) })
	check(start["ok"] and String(start["data"].get("devCode", "")).length() == 6, "OTP code requested (%s)" % str(start["data"]))
	var phone: String = "0809"
	var ver: Dictionary = {}
	if start["ok"]:
		# Re-derive the phone used for the request from the masked echo is impossible; ask again with a known one.
		phone = "0807%07d" % (randi() % 10000000)
		var s2: Dictionary = await net.api("POST", "/api/auth/otp/start", { "phone": phone })
		ver = await net.api("POST", "/api/auth/otp/verify", { "phone": phone, "code": s2["data"].get("devCode", "") })
	check(ver.get("ok", false) and ver["data"].get("verified", false), "phone verified with the code")

	var mv: Dictionary = await net.api("POST", "/api/wallet/move", { "amount": 5000 })
	check(mv["ok"] and int(mv["data"].get("toSave", 0)) == -5000, "deposit into the market wallet")
	var board: Dictionary = await net.api("GET", "/api/gigs")
	var gigs: Array = board["data"].get("gigs", [])
	check(board["ok"] and gigs.size() >= 6, "gig board lists NPC gigs (%d)" % gigs.size())
	if gigs.size() > 0:
		var take: Dictionary = await net.api("POST", "/api/gigs/%d/take" % int(gigs[0]["id"]))
		check(take["ok"], "take a gig (%s)" % str(take))
		var fin: Dictionary = await net.api("POST", "/api/gigs/%d/finish" % int(gigs[0]["id"]), { "score": 77 })
		check(fin["ok"] and fin["data"].get("passed", false), "finish a gig with a passing score")
	var prof: Dictionary = await net.api("PUT", "/api/profile", { "bio": "Online check", "district": "yaba", "cv": { "skills": { "driving": 3 } } })
	check(prof["ok"], "save profile")
	var el: Dictionary = await net.api("GET", "/api/elections/yaba")
	check(el["ok"] and (el["data"].get("candidates", []) as Array).size() >= 2, "ward election with candidates")
	var pol: Dictionary = await net.api("GET", "/api/policies")
	check(pol["ok"] and pol["data"].has("menu"), "policy menu")
	var banter: Dictionary = await net.api("GET", "/api/banter")
	check(banter["ok"] and banter["data"].has("lines"), "news banter endpoint")
	var moods: Dictionary = await net.api("GET", "/api/brains/moods")
	check(moods["ok"] and (moods["data"].get("moods", {}) as Dictionary).has("drivers"), "archetype moods")
	var ch: Dictionary = await net.api("POST", "/api/challenges/dodge/start")
	check(ch["ok"] and (ch["data"].get("seq", []) as Array).size() == 10, "challenge run issued by the server")
	if ch["ok"]:
		var log: Array = (ch["data"]["seq"] as Array).map(func(d: String) -> Dictionary: return { "dodge": d, "t": 0.5 })
		var fin2: Dictionary = await net.api("POST", "/api/challenges/runs/%d/finish" % int(ch["data"]["run"]), { "log": log })
		check(fin2["ok"] and int(fin2["data"].get("score", 0)) == 100, "server replays the input log")
	var settings: Node = root.get_node("Settings")
	var tele: Node = root.get_node("Telemetry")
	var was: Variant = settings.get_pref("telemetry", false)
	settings.prefs["telemetry"] = true
	tele.event("mission_complete", { "id": "P1" })
	await tele.flush()
	settings.prefs["telemetry"] = was
	check(true, "telemetry flush completes")
	var got_err := [""]
	net.server_error.connect(func(c: String) -> void: got_err[0] = c)
	net.send_chat("my number is 08031234567")
	t0 = Time.get_ticks_msec()
	while got_err[0] == "" and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	check(got_err[0] == "blocked_personal_data", "server blocks phone numbers in chat (%s)" % got_err[0])
	# M11 street life.
	await net.api("POST", "/api/wallet/move", { "amount": 12000 })
	var crew_name := "Check Crew %d" % (randi() % 100000)
	var crew: Dictionary = await net.api("POST", "/api/crews", { "name": crew_name, "tag": "C%d" % (randi() % 999) })
	check(crew["ok"], "start a crew (%s)" % str(crew["data"]))
	var mine: Dictionary = await net.api("GET", "/api/crews/mine")
	check(mine["ok"] and mine["data"].get("crew") is Dictionary, "my crew")
	var routes: Dictionary = await net.api("GET", "/api/routes")
	check(routes["ok"] and (routes["data"].get("routes", []) as Array).size() == 6, "route standings for all six routes")
	var box: Dictionary = await net.api("GET", "/api/boxing")
	check(box["ok"] and int(box["data"].get("me", {}).get("rating", 0)) == 1000, "boxing board with my rating")
	var trade: Dictionary = await net.api("GET", "/api/trade")
	check(trade["ok"] and trade["data"].get("district") == net.district, "market prices for the district I'm in")
	var buy: Dictionary = await net.api("POST", "/api/trade", { "good": "pepper", "qty": 1, "side": "buy" })
	check(buy["ok"] and int(buy["data"].get("qty", 0)) == 1, "buy goods with market money (%s)" % str(buy["data"]))
	var gist: Dictionary = await net.api("POST", "/api/gist", { "kind": "fight_win" })
	check(gist["ok"] and String(gist["data"].get("text", "")).begins_with("OnlineCheck"), "post to the Lagos Gist feed")
	var feed: Dictionary = await net.api("GET", "/api/gist")
	check(feed["ok"] and (feed["data"].get("posts", []) as Array).size() >= 1, "read the feed")
	got_err[0] = ""
	net.send_look({ "outfit": "agbada", "cap": "#efe8d6", "bus": "#2f6f99", "sl": "3", "crew": "CC" })
	await create_timer(1.0).timeout
	check(got_err[0] == "", "style update accepted by the server (%s)" % got_err[0])
	print("online: %d passed, %d failed" % [passes, failures])
	net.set_server("", "Tunde") # don't leave this machine pointed at the test server
	quit(1 if failures > 0 else 0)
