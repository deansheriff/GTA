extends MiniGame
## 2.2 "Japa Interview" at the fictional Republic of Northvale: quick answers against a clock while
## the officer never blinks. Calm, honest answers keep Composure up; panic and lies drop it.
## The joke is the bureaucracy, not any real country (Story Bible §8.4).

const QUESTIONS := [
	{ "q": "Purpose of your visit?", "a": [["To study content creation. And come back.", 12], ["Vacation. For… ten years.", -15], ["Japa. I mean— tourism!", -20]] },
	{ "q": "Who is sponsoring you?", "a": [["My savings. Here are six months of statements.", 15], ["My uncle. He is… somewhere.", -10], ["God.", -5]] },
	{ "q": "Describe your relationship with your grandmother's goat.", "a": [["Cordial. We respect each other's boundaries.", 12], ["The goat and I don't talk about that.", -8], ["Is this part of the visa?", -12]] },
	{ "q": "Have you ever been to Northvale?", "a": [["No, sir. First time applying.", 10], ["In my dreams, every night.", -10], ["My cousin has. Does that count?", -6]] },
	{ "q": "What will you do if your visa is refused?", "a": [["Improve my documents and try again.", 14], ["Cry. Publicly. On camera.", -10], ["Go by road.", -25]] },
	{ "q": "Why are you sweating?", "a": [["Lagos heat, sir. And respect.", 10], ["Because you haven't blinked in four minutes.", -6], ["I'm not sweating, the chair is.", -8]] },
	{ "q": "Name three things you will bring back to Nigeria.", "a": [["Skills, savings and a winter jacket for my mother.", 14], ["A Northvale wife.", -15], ["Nothing. I'm not coming— I mean everything!", -22]] },
]
const ROUND_TIME := 7.0

var _order: Array = []
var _i := 0
var _composure := 60.0
var _left := 0.0
var _q: Label
var _meter: ProgressBar
var _clock: ProgressBar
var _btns: Array[Button] = []
var _rng := RandomNumberGenerator.new()


func _build() -> void:
	set_title("Republic of Northvale · Visa Interview")
	label("Composure", 14, Color(1, 1, 1, 0.7))
	_meter = bar(GOOD)
	_q = label("", 24)
	_clock = bar(DANFO)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 58)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var idx := i
		b.pressed.connect(func() -> void: _answer(idx))
		card.add_child(b)
		_btns.append(b)


func _begin(_p: Dictionary) -> void:
	_rng.randomize()
	_order = QUESTIONS.duplicate()
	_order.shuffle()
	_order = _order.slice(0, 5)
	_i = -1
	_composure = 60.0
	_next()


func _next() -> void:
	_i += 1
	if _i >= _order.size():
		var passed := _composure >= 60.0
		_q.text = "APPROVED. (The officer still did not blink.)" if passed else "REFUSED. \"Reason: Insufficient ties to grandmother's goat.\""
		finish({ "score": int(_composure), "passed": passed })
		return
	var q: Dictionary = _order[_i]
	_q.text = "Officer: \"%s\"" % q["q"]
	var answers: Array = q["a"].duplicate()
	answers.shuffle()
	for k in 3:
		_btns[k].text = answers[k][0]
		_btns[k].set_meta("delta", answers[k][1])
	_left = ROUND_TIME
	if autoplay:
		await get_tree().create_timer(0.1).timeout
		var best := 0
		for k in 3:
			if int(_btns[k].get_meta("delta")) > int(_btns[best].get_meta("delta")):
				best = k
		_answer(best)


func _answer(k: int) -> void:
	if not _running or _i >= _order.size():
		return
	_composure = clampf(_composure + float(_btns[k].get_meta("delta")), 0.0, 100.0)
	_next()


func _process(delta: float) -> void:
	if not _running or _i >= _order.size():
		return
	_meter.max_value = 100
	_meter.value = _composure
	_left -= delta
	_clock.max_value = ROUND_TIME
	_clock.value = _left
	if _left <= 0.0:
		_composure = clampf(_composure - 12.0, 0.0, 100.0) # silence is suspicious
		_next()
