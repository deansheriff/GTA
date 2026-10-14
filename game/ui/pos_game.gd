extends Control
## POS shift mini-game: customers queue for withdrawals and transfers. Tap "Process"; when the
## network fails, Retry, Switch network or Hold it at the window before the customer loses patience.
## Free-roam shifts use start(); story mission 1.2 uses `await play(params)`. (Reused in F5.)

signal finished(served: int, failed: int)

const REQUESTS := ["Withdraw ₦5,000", "Withdraw ₦20,000", "Transfer ₦10,000", "Withdraw ₦2,000 (for transport)", "Transfer ₦35,000 to \"my brother\"", "Withdraw ₦50,000, abeg quick"]
const COMPLAINTS := ["\"Network don fail, come back tomorrow.\"", "\"Transaction pending… pending… pending.\"", "\"It's showing 'Issuer or switch inoperative'.\"", "\"Bank say make you try again.\""]
const FIXES := {
	"retry": { "text": "Retry", "odds": 0.55, "fail": "Still pending. The customer is breathing loudly." },
	"switch": { "text": "Switch network", "odds": 0.7, "fail": "9Bars has one bar. Konnekt has none. Try again!" },
	"window": { "text": "Hold it at the window", "odds": 0.6, "fail": "Higher! Towards the transformer! (Still nothing.)" },
}

var autoplay := false
var _rng := RandomNumberGenerator.new()
var _customers := 6
var _served := 0
var _failed := 0
var _index := 0
var _net_down := false
var _timer := 0.0
var _req: Label
var _status: Label
var _btn: Button
var _fix_row: HBoxContainer
var _bar: ProgressBar
var _fail_chance := 0.3
var _forced := 0 # story: guaranteed failures left
var _switch_network := false
var _running := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(500, 0)
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var h := Label.new()
	h.text = "POS shift · Tap-Tap POS"
	h.add_theme_font_size_override("font_size", 24)
	v.add_child(h)
	_req = Label.new()
	_req.add_theme_font_size_override("font_size", 20)
	_req.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_req)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 16)
	v.add_child(_bar)
	_btn = Button.new()
	_btn.custom_minimum_size = Vector2(0, 64)
	_btn.pressed.connect(func() -> void: _press("retry"))
	v.add_child(_btn)
	_fix_row = HBoxContainer.new()
	_fix_row.add_theme_constant_override("separation", 8)
	v.add_child(_fix_row)
	for k in ["switch", "window"]:
		var b := Button.new()
		b.text = FIXES[k]["text"]
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = k
		b.pressed.connect(func() -> void: _press(key))
		_fix_row.add_child(b)
	_fix_row.visible = false
	visible = false


## Free-roam shift (JobRunner listens to `finished`).
func start(fail_chance: float) -> void:
	_setup({ "network_fail": fail_chance })


## Story use: returns {score: served, served, failed}.
func play(params: Dictionary) -> Dictionary:
	_setup(params)
	var res: Array = await finished # [served, failed]
	return { "score": int(res[0]), "served": int(res[0]), "failed": int(res[1]) }


func _setup(p: Dictionary) -> void:
	_fail_chance = float(p.get("network_fail", 0.3))
	_customers = int(p.get("customers", 6))
	_forced = int(p.get("forced_failures", 0))
	_switch_network = bool(p.get("switch_network", false))
	_rng.randomize()
	_served = 0
	_failed = 0
	_index = 0
	_running = true
	visible = true
	_next_customer()


func _next_customer() -> void:
	if _index >= _customers:
		_running = false
		visible = false
		finished.emit(_served, _failed)
		return
	_index += 1
	_net_down = false
	_fix_row.visible = false
	_req.text = "Customer %d of %d: %s" % [_index, _customers, REQUESTS[_rng.randi() % REQUESTS.size()]]
	_status.text = "Card inserted. Customer is watching you like a hawk."
	_btn.text = "Process"
	_timer = 0.0
	if autoplay:
		await get_tree().create_timer(0.1).timeout
		_press("retry")


func _press(fix: String) -> void:
	if not _running:
		return
	if _net_down:
		if _rng.randf() < float(FIXES[fix]["odds"]):
			_succeed()
		else:
			_status.text = FIXES[fix]["fail"]
		return
	var forced_now := _forced > 0 and _index <= _customers
	if forced_now or _rng.randf() < _fail_chance:
		if forced_now:
			_forced -= 1
		_net_down = true
		_timer = 6.0 if _switch_network else 5.0
		_status.text = COMPLAINTS[_rng.randi() % COMPLAINTS.size()]
		_btn.text = "Retry (quick!)"
		_fix_row.visible = _switch_network
	else:
		_succeed()


func _succeed() -> void:
	_served += 1
	_net_down = false
	_fix_row.visible = false
	_status.text = "Approved! Customer collects money and counts it twice."
	await get_tree().create_timer(0.7 if not autoplay else 0.1).timeout
	_next_customer()


func _process(delta: float) -> void:
	if not visible or not _net_down:
		_bar.value = 0
		return
	if autoplay and Engine.get_process_frames() % 20 == 0:
		_press("switch" if _switch_network else "retry")
	_timer -= delta
	_bar.value = _timer / 5.0 * 100.0
	if _timer <= 0.0:
		_failed += 1
		_status.text = "Customer: \"I no fit wait! I'm going to the next POS.\""
		_net_down = false
		_fix_row.visible = false
		await get_tree().create_timer(0.8).timeout
		_next_customer()
