extends MiniGame
## Night suya stand (M10 #8): three skewers on the grill. Each one browns over time; flip it
## when golden, then serve it when the second side is golden too. Raw or burnt? The customer
## walks. Pidgin lines pending native-speaker review.

const SLOTS := 3
const GOLD := [0.55, 0.8] # the golden window of each side's cook level

var _sk: Array = [] # {cook: [side0, side1], side, state}
var _btns: Array = []
var _bars: Array = []
var _info: Label
var _left := 0.0
var _orders := 0
var _served := 0
var _burnt := 0
var _rate := 0.16


func _build() -> void:
	set_title("Mallam's suya stand")
	_info = label("", 18, PAPER)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	for i in SLOTS:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var pb := ProgressBar.new()
		pb.max_value = 1.0
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 22)
		col.add_child(pb)
		_bars.append(pb)
		var idx := i
		var b := big_button("Put stick", func() -> void: _tap(idx), col)
		_btns.append(b)


## params: {orders?, seconds?}
func _begin(p: Dictionary) -> void:
	_orders = int(p.get("orders", 8))
	_left = float(p.get("seconds", 75.0))
	_served = 0
	_burnt = 0
	_info.text = "Put sticks on. Flip when golden brown, serve when the other side is golden too."
	_sk.clear()
	for i in SLOTS:
		_sk.append({ "cook": [0.0, 0.0], "side": 0, "state": "empty" })
		_refresh(i)


func _tap(i: int) -> void:
	if not _running:
		return
	var s: Dictionary = _sk[i]
	var c: float = s["cook"][s["side"]]
	match s["state"]:
		"empty":
			s["state"] = "cooking"
			s["side"] = 0
			s["cook"] = [0.0, 0.0]
			Sound.sfx("sizzle")
		"cooking":
			if c < GOLD[0] or c > GOLD[1]:
				_spoil(i, ("Raw! Customer no gree." if c < GOLD[0] else "Burnt! Yaji no fit cover am."))
			elif s["side"] == 0:
				s["side"] = 1
				Sound.sfx("tap", 1.2)
			else:
				_served += 1
				Sound.sfx("cash")
				s["state"] = "empty"
				_info.text = "Served! %d / %d" % [_served, _orders]
				if _served >= _orders:
					_done()
					return
	_refresh(i)


func _spoil(i: int, why: String) -> void:
	_burnt += 1
	_sk[i]["state"] = "empty"
	_info.text = why
	Sound.sfx("fail")


func _refresh(i: int) -> void:
	var s: Dictionary = _sk[i]
	var b: Button = _btns[i]
	if s["state"] == "empty":
		b.text = "Put stick"
	else:
		b.text = "Flip" if s["side"] == 0 else "Serve"
	var c: float = s["cook"][s["side"]] if s["state"] == "cooking" else 0.0
	var pb: ProgressBar = _bars[i]
	pb.value = c
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#d9b26a") if c < GOLD[0] else (Color("#b5652a") if c <= GOLD[1] else Color("#2a1a12"))
	pb.add_theme_stylebox_override("fill", fill)


func _process(delta: float) -> void:
	if not _running:
		return
	_left -= delta
	for i in SLOTS:
		var s: Dictionary = _sk[i]
		if s["state"] == "cooking":
			s["cook"][s["side"]] = float(s["cook"][s["side"]]) + delta * _rate
			if float(s["cook"][s["side"]]) > 1.0:
				_spoil(i, "Charcoal! That one don burn.")
			_refresh(i)
			if autoplay and s["state"] == "cooking" and float(s["cook"][s["side"]]) >= 0.65:
				_tap(i)
		elif autoplay:
			_tap(i)
		if not _running:
			return
	if _left <= 0.0:
		_done()


func _done() -> void:
	finish({ "score": int(round(100.0 * _served / maxf(1.0, _orders))), "served": _served, "burnt": _burnt })
