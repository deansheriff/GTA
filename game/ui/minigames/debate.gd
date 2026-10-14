extends MiniGame
## 3.2 "The Debate": the Chief speaks in slogans; you play rebuttal cards. Receipts beat slogans,
## jokes win the room, insults lose it. KC's live chat multiplies a good round.

const ROUNDS := [
	{ "chief": "\"Light for All! Terms and conditions apply!\"", "cards": [["Read the transformer receipt: ₦0 paid.", 30], ["\"Your terms are the darkness.\"", 15], ["\"Your agbada is ugly.\"", -15]] },
	{ "chief": "\"I have built roads! Many roads! In my mind!\"", "cards": [["Show the photo of the road that is still a swamp.", 28], ["\"Can we drive on your mind?\"", 18], ["\"Liar!\"", -10]] },
	{ "chief": "\"The opposition stole my bag!\"", "cards": [["\"Which bag? The one your treasurer split across 40 POS agents?\"", 32], ["\"Was it a Ghana-must-go?\"", 12], ["\"Good. Keep crying.\"", -12]] },
	{ "chief": "\"Teacher is too old to lead!\"", "cards": [["Teacher: \"I taught half this ward to read. Including your campaign manager.\"", 30], ["\"Age is wisdom. You're proof of the reverse.\"", 14], ["\"You're old too!\"", -8]] },
	{ "chief": "\"Vote for me and everybody gets… something!\"", "cards": [["\"Read the diary: everybody already got nothing.\"", 30], ["\"Something like NEPA bills?\"", 16], ["Walk off stage", -20]] },
]

var _i := 0
var _points := 0.0
var _chat := false
var _chief: Label
var _btns: Array[Button] = []
var _note: Label
var _meter: ProgressBar


func _build() -> void:
	set_title("Ward Debate · live on Gidi Gist FM")
	label("The room", 14, Color(1, 1, 1, 0.7))
	_meter = bar(GOOD)
	_chief = label("", 22, DANFO)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 56)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var idx := i
		b.pressed.connect(func() -> void: _play(idx))
		card.add_child(b)
		_btns.append(b)
	var live := CheckButton.new()
	live.text = "KC controls the live chat (doubles a strong round)"
	live.toggled.connect(func(v: bool) -> void: _chat = v)
	card.add_child(live)
	_note = label("", 16, Color(1, 1, 1, 0.75))


func _begin(_p: Dictionary) -> void:
	_i = -1
	_points = 50.0
	_chat = autoplay
	_next()


func _next() -> void:
	_i += 1
	_meter.max_value = 100
	_meter.value = clampf(_points, 0.0, 100.0)
	if _i >= ROUNDS.size():
		var score := int(clampf(_points, 0.0, 100.0))
		_chief.text = "The Chief: \"…No further questions.\" (There were no questions.)" if score >= 60 else "The Chief talks for 40 minutes. The room falls asleep."
		finish({ "score": score, "fx": { "blocs": { "all": 10 if score >= 60 else 2 }, "stats": { "hype": 20 } } })
		return
	var r: Dictionary = ROUNDS[_i]
	_chief.text = "Chief: " + String(r["chief"])
	var cards: Array = r["cards"].duplicate()
	cards.shuffle()
	for k in 3:
		_btns[k].text = cards[k][0]
		_btns[k].set_meta("v", cards[k][1])
	if autoplay:
		await get_tree().create_timer(0.1).timeout
		var best := 0
		for k in 3:
			if int(_btns[k].get_meta("v")) > int(_btns[best].get_meta("v")):
				best = k
		_play(best)


func _play(k: int) -> void:
	if not _running or _i >= ROUNDS.size():
		return
	var v := float(_btns[k].get_meta("v"))
	if _chat and v >= 25.0:
		v *= 1.5
		_note.text = "Live chat: \"RECEIPTS!!! 🔥🔥\" The room roars."
	else:
		_note.text = "The room murmurs." if v > 0.0 else "Boos. Even the Chief's people winced."
	_points += v * 0.35
	_next()
