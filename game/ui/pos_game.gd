extends Control
## POS shift mini-game: customers queue for withdrawals and transfers. Tap "Process"; when the
## network fails, tap "Retry" before the customer loses patience. (Reused as a reward game in F5.)

signal finished(served: int, failed: int)

const CUSTOMERS := 6
const REQUESTS := ["Withdraw ₦5,000", "Withdraw ₦20,000", "Transfer ₦10,000", "Withdraw ₦2,000 (for transport)", "Transfer ₦35,000 to \"my brother\"", "Withdraw ₦50,000, abeg quick"]
const COMPLAINTS := ["\"Network don fail, come back tomorrow.\"", "\"Transaction pending… pending… pending.\"", "\"It's showing 'Issuer or switch inoperative'.\"", "\"Bank say make you try again.\""]

var _rng := RandomNumberGenerator.new()
var _served := 0
var _failed := 0
var _index := 0
var _net_down := false
var _timer := 0.0
var _req: Label
var _status: Label
var _btn: Button
var _bar: ProgressBar
var _fail_chance := 0.3


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
	v.custom_minimum_size = Vector2(440, 0)
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
	_btn.pressed.connect(_press)
	v.add_child(_btn)
	visible = false


func start(fail_chance: float) -> void:
	_fail_chance = fail_chance
	_rng.randomize()
	_served = 0
	_failed = 0
	_index = 0
	visible = true
	_next_customer()


func _next_customer() -> void:
	if _index >= CUSTOMERS:
		visible = false
		finished.emit(_served, _failed)
		return
	_index += 1
	_net_down = false
	_req.text = "Customer %d of %d: %s" % [_index, CUSTOMERS, REQUESTS[_rng.randi() % REQUESTS.size()]]
	_status.text = "Card inserted. Customer is watching you like a hawk."
	_btn.text = "Process"
	_timer = 0.0


func _press() -> void:
	if _net_down:
		# Retry: often works the second time, sometimes not.
		if _rng.randf() < 0.65:
			_succeed()
		else:
			_status.text = COMPLAINTS[_rng.randi() % COMPLAINTS.size()] + " Try again!"
		return
	if _rng.randf() < _fail_chance:
		_net_down = true
		_timer = 5.0
		_status.text = COMPLAINTS[_rng.randi() % COMPLAINTS.size()]
		_btn.text = "Retry (quick!)"
	else:
		_succeed()


func _succeed() -> void:
	_served += 1
	_status.text = "Approved! Customer collects money and counts it twice."
	await get_tree().create_timer(0.7).timeout
	_next_customer()


func _process(delta: float) -> void:
	if not visible or not _net_down:
		_bar.value = 0
		return
	_timer -= delta
	_bar.value = _timer / 5.0 * 100.0
	if _timer <= 0.0:
		_failed += 1
		_status.text = "Customer: \"I no fit wait! I'm going to the next POS.\""
		_net_down = false
		await get_tree().create_timer(0.8).timeout
		_next_customer()
