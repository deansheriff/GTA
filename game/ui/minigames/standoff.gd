extends MiniGame
## 1.5 "Family Meeting": a dialogue standoff over a roaring generator. Hold SHOUT while the noise is
## high so your line is heard; lines spoken into the noise are lost ("…BRRRRRM…").

var _lines: Array = []
var _i := 0
var _line_t := 0.0
var _noise := 0.0
var _noise_t := 0.0
var _heard := 0
var _shouting := false
var _shout_seen := false
var _who: Label
var _text: Label
var _meter: ProgressBar
var _result: Label
var _btn: Button
const LINE_TIME := 2.4
const LOUD := 0.55


func _build() -> void:
	set_title("Family Meeting (generator edition)")
	label("Generator noise. When the meter is red, HOLD SHOUT to be heard.", 16, Color(1, 1, 1, 0.75))
	_meter = bar(BAD)
	_who = label("", 20, DANFO)
	_text = label("", 22)
	_result = label("", 16, Color(1, 1, 1, 0.7))
	_btn = big_button("HOLD TO SHOUT", func() -> void: pass)
	_btn.button_down.connect(func() -> void:
		_shouting = (not _shouting) if Settings.get_pref("hold_as_toggle", false) else true
		_btn.text = "SHOUTING!" if _shouting else "HOLD TO SHOUT")
	_btn.button_up.connect(func() -> void:
		if not Settings.get_pref("hold_as_toggle", false):
			_shouting = false
			_btn.text = "HOLD TO SHOUT")


func _begin(p: Dictionary) -> void:
	var src: Variant = p.get("lines", [])
	_lines = Story.line_list(src) if src is String else src
	_i = -1
	_heard = 0
	_noise_t = 0.0
	_next_line()


func _next_line() -> void:
	_i += 1
	if _i >= _lines.size():
		var score := int(round(float(_heard) / float(maxi(1, _lines.size())) * 100.0))
		_text.text = "Everybody was heard. Mostly." if score >= 50 else "Nobody heard anybody."
		finish({ "score": score })
		return
	var line: Dictionary = _lines[_i]
	_who.text = String(Story.who(line["who"]).get("name", ""))
	_text.text = "…"
	_line_t = 0.0
	_shout_seen = false


func _process(delta: float) -> void:
	if not _running or _i >= _lines.size():
		return
	_noise_t += delta
	_noise = clampf(0.5 + 0.45 * sin(_noise_t * 1.7) * sin(_noise_t * 0.63 + 1.0), 0.0, 1.0)
	_meter.max_value = 1.0
	_meter.value = _noise
	if autoplay:
		_shouting = _noise > LOUD - 0.05
	_line_t += delta
	if _shouting:
		_shout_seen = true
	if _line_t >= LINE_TIME * 0.5 and _text.text == "…":
		var line: Dictionary = _lines[_i]
		var heard := _noise <= LOUD or _shouting or _shout_seen
		if heard:
			_heard += 1
			_text.text = String(line["text"])
		else:
			_text.text = "…BRRRRRRRM…  (lost in the generator)"
		_result.text = "Lines heard: %d / %d" % [_heard, _i + 1]
	if _line_t >= LINE_TIME:
		_next_line()
