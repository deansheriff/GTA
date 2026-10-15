class_name Passengers
extends Node
## Passenger personalities (M9 #4). Every danfo run carries a few memorable riders, and each one
## brings tips or trouble along the way:
##   the Preacher (prays your BP down), the Phone-shouter (BP up, patience down), No-change man
##   (argue or let it go), Drop-me-here (stop right now, or don't), Market Mama (snacks),
##   the Big Man (tips if you drive clean), the Student (half fare, good gist), and the quiet
##   guy in the back who keeps looking at bags.

var host: StreetHost
var main: Node2D
var riders: Array = [] # [{id, name, done}]
var _event_t := 0.0
var _extra := 0 # tips minus losses, settled when the run ends
var _damage_at_start := 0.0
var _busy := false
var _rng := RandomNumberGenerator.new()


func setup(h: StreetHost) -> void:
	host = h
	main = h.main
	_rng.randomize()
	main.jobs.danfo_done.connect(_on_done)


func on_job_changed(job: Dictionary) -> void:
	if job.is_empty():
		if not riders.is_empty() and not _busy:
			riders.clear()
		return
	if job.get("type") == "danfo" and job.get("stage") == "driving" and riders.is_empty():
		_begin()


func _begin() -> void:
	riders.clear()
	_extra = 0
	_damage_at_start = Street.damage
	_event_t = _rng.randf_range(8.0, 14.0)
	var pool: Array = Street.db["passengers"]
	var n := _rng.randi_range(2, 3)
	var names := []
	for i in n:
		var total := 0
		for p: Dictionary in pool:
			total += int(p["weight"])
		var r := _rng.randi_range(1, total)
		for p: Dictionary in pool:
			r -= int(p["weight"])
			if r <= 0:
				if riders.any(func(x: Dictionary) -> bool: return x["id"] == p["id"]):
					break
				riders.append({ "id": p["id"], "name": p["name"], "done": false, "lines": p["lines"] })
				names.append(p["name"])
				break
	if riders.any(func(x: Dictionary) -> bool: return x["id"] == "preacher"):
		Street.count("carried_preacher")
	host.ticker("On board: %s, and others." % ", ".join(names), 6.0)


func tick(dt: float) -> void:
	var job: Dictionary = main.jobs.active
	if riders.is_empty() or _busy or job.get("stage") != "driving" or main.story.paused_by_story():
		return
	_event_t -= dt
	if _event_t > 0.0:
		return
	_event_t = _rng.randf_range(14.0, 26.0)
	var todo := riders.filter(func(x: Dictionary) -> bool: return not x["done"] and x["id"] not in ["nochange", "bigman", "student"])
	if todo.is_empty():
		return
	var r: Dictionary = todo[_rng.randi() % todo.size()]
	r["done"] = true
	_event(r)


func _line(r: Dictionary) -> String:
	var lines: Array = r["lines"]
	return "%s: \"%s\"" % [r["name"], lines[_rng.randi() % lines.size()]]


func _bp(x: float) -> void:
	if Life.hero == "tunde":
		Life.stats["bp"] = clampf(float(Life.stats.get("bp", 20.0)) + x, 0.0, 100.0)


func _event(r: Dictionary) -> void:
	var job: Dictionary = main.jobs.active
	match r["id"]:
		"preacher":
			host.ticker(_line(r))
			_bp(-12.0)
			Life.restore("fun", 3.0)
			main.hud.toast("The Preacher prays for the bus. BP down.")
		"phone":
			host.ticker(_line(r))
			_bp(9.0)
			job["patience"] = maxf(0.0, float(job.get("patience", 100.0)) - 10.0)
		"mama":
			host.ticker(_line(r))
			Life.add_item("puff-puff")
			main.hud.toast("Market Mama gave you puff-puff. (In your pocket.)")
		"dropme":
			_busy = true
			var c := await host.ask("Drop-me-here", _line(r), [["stop", "Stop here"], ["no", "\"No bus stop here!\""]], 6.0, "no")
			if c == "stop":
				main.danfo.speed = 0.0
				_extra += 300
				job["passengers"] = maxi(1, int(job.get("passengers", 1)) - 1)
				Street.add_rep(1.0)
				main.hud.toast("You dropped him. He tipped ₦300.")
			else:
				job["patience"] = maxf(0.0, float(job.get("patience", 100.0)) - 15.0)
				main.hud.toast("\"Na wa for this driver o!\"")
			_busy = false
		"thief":
			_busy = true
			host.ticker("Somebody shouts: \"THIEF! My phone!\"")
			var c := await host.ask("Thief on the bus!", "The quiet guy grabbed a phone and is jumping out!", [["chase", "Catch him!"], ["let", "Let him go"]])
			if c == "chase":
				var res: Dictionary = await main.story.story_minigame("quick", { "prompt": "He's at the door! Grab him!", "button": "GRAB!", "time": 1.4 })
				if int(res.get("score", 0)) >= 1:
					Street.add_rep(4.0)
					_extra += 1000
					main.hud.toast("You caught him! The owner tipped ₦1,000. Street respect!", true)
					Street.post_gist("hero", "%s caught a phone thief on a danfo!" % Street._me())
				else:
					_extra -= 500
					main.hud.toast("He escaped, and two passengers refused to pay.")
			else:
				_extra -= 500
				main.hud.toast("He got away. Two passengers refused to pay.")
			_busy = false


func _on_done(job: Dictionary, fares: int) -> void:
	_busy = true
	if Weather.raining_now:
		Street.count("rain_runs")
	for r: Dictionary in riders:
		match r["id"]:
			"nochange":
				var c := await host.ask("No change", _line(r), [["let", "Let am go (−₦%s)" % Life.fmt_naira(int(job.get("fare", 500)))], ["find", "Find change"], ["down", "\"Come down!\""]])
				match c:
					"let":
						_extra -= int(job.get("fare", 500))
						Street.add_rep(2.0)
					"find":
						_bp(6.0)
					"down":
						_bp(4.0)
						Street.add_rep(-1.0)
						main.hud.toast("He paid, grumbling.")
			"bigman":
				if Street.damage - _damage_at_start < 1.0:
					var tip := _rng.randi_range(10, 20) * 100
					_extra += tip
					main.hud.toast("The Big Man: \"Smooth driving!\" Tip: ₦%s." % Life.fmt_naira(tip))
				else:
					main.hud.toast("The Big Man spilled his zobo. No tip.")
			"student":
				_extra -= int(job.get("fare", 500)) / 2
				Life.restore("social", 4.0)
				host.ticker(_line(r))
	if _extra > 0:
		Life.earn(_extra, "Passenger tips")
	elif _extra < 0:
		Life.spend(mini(-_extra, Life.money), "Passenger wahala")
	riders.clear()
	_busy = false
