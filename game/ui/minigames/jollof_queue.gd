extends MiniGame
## P2 "Jollof Diplomacy": the jollof queue is politics. Serve elders, the bride's family and honest
## guests; refuse (or Stare at) takeaway-pack people and double-dippers before the pot runs dry.

const GUESTS := {
	"elder": { "label": "Elder", "lines": ["\"My daughter, small rice, plenty meat.\"", "\"I knew the groom's grandfather.\"", "\"Make it soft. My teeth are retired.\""], "ok": "serve" },
	"family": { "label": "Bride's family", "lines": ["\"I'm the bride's aunty. Her FAVOURITE aunty.\"", "\"Family first, abi?\"", "\"My aso-ebi is the original one.\""], "ok": "serve" },
	"guest": { "label": "Guest", "lines": ["\"Good evening, Aunty. One plate, please.\"", "\"The jollof is smelling like heaven.\"", "\"I came all the way from Ikotun.\""], "ok": "serve" },
	"takeaway": { "label": "Came with own takeaway pack", "lines": ["\"Aunty, put it in this my plastic.\"", "\"It's for my mother. She's… at home.\"", "\"Two packs. One is for the road.\""], "ok": "refuse" },
	"dipper": { "label": "Double-dipper (back again)", "lines": ["\"Aunty, small more.\"", "\"I didn't eat the first one, it fell.\"", "\"This is my first time here, I swear.\""], "ok": "refuse" },
}

var _queue: Array = []
var _i := 0
var _pot := 0
var _pot_max := 0
var _served := 0
var _correct := 0
var _patience := 0.0
var _rng := RandomNumberGenerator.new()
var _who: Label
var _say: Label
var _status: Label
var _pot_bar: ProgressBar
var _pat_bar: ProgressBar
var _row: HBoxContainer


func _build() -> void:
	set_title("Jollof Diplomacy")
	_status = label("", 16, Color(1, 1, 1, 0.7))
	_pot_bar = bar(Color("#c8501e"))
	_who = label("", 22, DANFO)
	_say = label("", 20)
	_pat_bar = bar(GOOD)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 10)
	card.add_child(_row)
	big_button("Serve", func() -> void: _act("serve"), _row)
	big_button("Refuse", func() -> void: _act("refuse"), _row)
	big_button("The Stare", func() -> void: _act("stare"), _row)


func _begin(p: Dictionary) -> void:
	_rng.randomize()
	var plates := int(p.get("plates", 30))
	var dippers := int(p.get("dippers", 2))
	_pot_max = int(p.get("pot", plates + 4))
	_pot = _pot_max
	_queue.clear()
	for i in plates:
		_queue.append(["elder", "family", "guest", "guest"][_rng.randi() % 4])
	for i in dippers * 2:
		_queue.append("dipper")
	for i in dippers * 2:
		_queue.append("takeaway")
	_queue.shuffle()
	_i = 0
	_served = 0
	_correct = 0
	_next()


func _next() -> void:
	if _i >= _queue.size() or _pot <= 0:
		var total := _queue.size()
		# Anyone still waiting when the pot runs dry counts against you.
		var score := int(round(float(_correct) / float(total) * 100.0))
		_say.text = "The pot is empty! Scandal." if _pot <= 0 and _i < total else "Queue cleared. Aunty Boss has done it again."
		finish({ "score": score, "served": _served, "correct": _correct })
		return
	var g: Dictionary = GUESTS[_queue[_i]]
	_who.text = "%d/%d · %s" % [_i + 1, _queue.size(), g["label"]]
	_say.text = g["lines"][_rng.randi() % g["lines"].size()]
	_patience = 4.5
	_update()
	if autoplay:
		await get_tree().create_timer(0.05).timeout
		_act("serve" if g["ok"] == "serve" else ("stare" if _rng.randf() < 0.5 else "refuse"))


func _update() -> void:
	_pot_bar.max_value = _pot_max
	_pot_bar.value = _pot
	_status.text = "Pot: %d plates left · served %d · Elders first, family second, no takeaway packs" % [_pot, _served]


func _act(action: String) -> void:
	if not _running or _i >= _queue.size():
		return
	var kind: String = _queue[_i]
	var ok: String = GUESTS[kind]["ok"]
	if action == "serve":
		_pot -= 1
		_served += 1
		if ok == "serve":
			_correct += 1
	elif ok == "refuse":
		_correct += 1
		if action == "stare":
			Life.stats["aura"] = minf(100.0, float(Life.stats.get("aura", 40.0)) + 0.5)
	_i += 1
	_next()


func _process(delta: float) -> void:
	if not _running or _i >= _queue.size():
		return
	_patience -= delta
	_pat_bar.max_value = 4.5
	_pat_bar.value = _patience
	if _patience <= 0.0:
		# Too slow: the guest helps themself (and the pot pays for it).
		_pot -= 1
		_i += 1
		_next()
