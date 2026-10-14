extends MiniGame
## 3.4 finale: "UP NEPA!" on cue. A needle sweeps across the meter; tap when it's in the green zone
## (the second the Chief takes the stage). Three cues: lights, speakers, every phone.

const CUES := ["Floodlights", "Speakers", "Every phone in the stadium"]

var _i := 0
var _hits := 0
var _t := 0.0
var _speed := 1.1
var _zone := Vector2(0.62, 0.78)
var _meter: Control
var _prompt: Label
var _rng := RandomNumberGenerator.new()


func _build() -> void:
	set_title("UP NEPA!")
	_prompt = label("", 24)
	_meter = Control.new()
	_meter.custom_minimum_size = Vector2(0, 60)
	_meter.draw.connect(_draw_meter)
	card.add_child(_meter)
	big_button("NOW!", _tap)


func _begin(_p: Dictionary) -> void:
	_rng.randomize()
	_i = -1
	_hits = 0
	_next()


func _next() -> void:
	_i += 1
	if _i >= CUES.size():
		var score := int(round(_hits / 3.0 * 100.0))
		_prompt.text = "UP NEPAAAA!" if score >= 66 else "The light came back… a bit late. Still: UP NEPA!"
		finish({ "score": score })
		return
	_prompt.text = "Cue %d/3: %s" % [_i + 1, CUES[_i]]
	_t = 0.0
	var start := _rng.randf_range(0.45, 0.72)
	_zone = Vector2(start, start + 0.16 - _i * 0.03)
	_speed = 0.9 + _i * 0.25


func _needle() -> float:
	return pingpong(_t * _speed, 1.0)


func _tap() -> void:
	if not _running or _i >= CUES.size():
		return
	var n := _needle()
	if n >= _zone.x and n <= _zone.y:
		_hits += 1
	_next()


func _process(delta: float) -> void:
	if not _running or _i >= CUES.size():
		return
	_t += delta
	_meter.queue_redraw()
	if autoplay:
		var n := _needle()
		if n >= _zone.x + 0.02 and n <= _zone.y - 0.02:
			_tap()


func _draw_meter() -> void:
	var w := _meter.size.x
	_meter.draw_rect(Rect2(0, 10, w, 40), Color(0.12, 0.09, 0.06))
	_meter.draw_rect(Rect2(w * _zone.x, 10, w * (_zone.y - _zone.x), 40), GOOD)
	var x := w * _needle()
	_meter.draw_line(Vector2(x, 2), Vector2(x, 58), DANFO, 6.0)
	_meter.draw_rect(Rect2(0, 10, w, 40), INK, false, 3.0)
