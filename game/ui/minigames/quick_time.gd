extends MiniGame
## A one-button moment in the dark (P4 blackout): read the prompt, tap before the bar runs out.

var _prompt: Label
var _btn: Button
var _bar: ProgressBar
var _time := 3.0
var _left := 0.0


func _build() -> void:
	set_title("Two seconds of darkness…")
	_prompt = label("", 24)
	_bar = bar(DANFO)
	_btn = big_button("Go", _press)


func _begin(p: Dictionary) -> void:
	_prompt.text = String(p.get("prompt", ""))
	_btn.text = String(p.get("button", "Go"))
	_time = float(p.get("time", 3.0))
	_left = _time
	if autoplay:
		await get_tree().create_timer(0.3).timeout
		_press()


func _press() -> void:
	if _running:
		_prompt.text = "Done!"
		finish({ "score": 1 })


func _process(delta: float) -> void:
	if not _running:
		return
	_left -= delta
	_bar.max_value = _time
	_bar.value = _left
	if _left <= 0.0:
		_prompt.text = "Too slow! (But in the dark, nobody saw.)"
		finish({ "score": 0 })
