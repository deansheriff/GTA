extends Node
## Autoload "Sound": music, ambience and effects (all synthesised by tools/audio/synth.mjs, so no
## licences are needed; licensed music can replace the loops later under the same names).
## Three buses (Music, SFX, Ambience) with volumes from Settings prefs.

const SFX := ["horn", "tap", "cash", "power_on", "power_off", "crash", "success", "fail", "stare", "whoosh", "notify", "siren", "splash", "thunder", "static", "sizzle", "punch", "gunshot", "gunshot_far", "reload", "skid", "whistle", "airbrake", "find", "babble"]
## Radio Gbedu's music, in turn (D-033).
const RADIO_TRACKS := ["highlife", "afrobeat", "juju"]

var _sfx := {} # name -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_name := ""
var _amb := {} # name -> AudioStreamPlayer (looping)
var _engine: AudioStreamPlayer
var _pool3d: Array[AudioStreamPlayer3D] = [] # sounds that come from a place in the world (D-033)
var _bed: AudioStreamPlayer # the region's background (birds, insects)
var _bed_name := ""
var _voice: AudioStreamPlayer


func _ready() -> void:
	for bus in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	for n in SFX:
		var s: AudioStream = _load("res://audio/sfx/%s.wav" % n, false)
		if s:
			_sfx[n] = s
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	for n in ["generator", "street", "rain"]:
		var a := AudioStreamPlayer.new()
		a.bus = "Ambience"
		a.stream = _load("res://audio/amb/%s.wav" % n, true)
		a.volume_db = -80.0
		add_child(a)
		_amb[n] = a
	_engine = AudioStreamPlayer.new()
	_engine.bus = "Ambience"
	_engine.stream = _load("res://audio/amb/engine.wav", true)
	add_child(_engine)
	for i in 10:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 9.0
		p.max_distance = 140.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3d.append(p)
	_bed = AudioStreamPlayer.new()
	_bed.bus = "Ambience"
	_bed.volume_db = -80.0
	add_child(_bed)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "SFX"
	add_child(_voice)
	apply_volumes()
	Settings.changed.connect(func(_s: Dictionary) -> void: apply_volumes())


func _load(path: String, loop: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if loop and s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	return s


func apply_volumes() -> void:
	for bus in ["Music", "SFX", "Ambience"]:
		var v := float(Settings.get_pref("vol_" + bus.to_lower(), 0.8 if bus != "Music" else 0.6))
		var i := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.01)


func sfx(name: String, pitch := 1.0) -> void:
	if not _sfx.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _sfx[name]
			p.pitch_scale = pitch
			p.play()
			return


## A sound from a place in the world: louder near, quieter far, panned to where it is.
func sfx_at(name: String, pos: Vector3, pitch := 1.0, db := 0.0) -> void:
	if not _sfx.has(name):
		return
	for p in _pool3d:
		if not p.playing:
			p.stream = _sfx[name]
			p.pitch_scale = pitch
			p.volume_db = db
			p.global_position = pos
			p.play()
			return


## A looping copy of a sound (the shared one stays a one-shot).
func loop_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = (load(path) as AudioStream).duplicate()
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	return s


## The dialogue "voice": a few syllables at the speaker's own pitch (the same person always sounds
## the same).
func babble(who: String) -> void:
	if not _sfx.has("babble") or who in ["story", "tip", "chat", ""]:
		return
	var h := absi(hash(who))
	_voice.stream = _sfx["babble"]
	_voice.pitch_scale = 0.75 + float(h % 50) / 100.0 + (0.15 if who in ["kemi", "amaka", "hauwa", "mama_agba", "tolu", "aunty", "captive", "passenger", "neighbour"] else 0.0)
	_voice.volume_db = -8.0
	_voice.play()


## The region's background (birds in the villages, insects in the creeks; "" for none).
func bed(name: String) -> void:
	if name == _bed_name:
		return
	_bed_name = name
	if name == "":
		_bed.stop()
		return
	_bed.stream = _load("res://audio/amb/%s.wav" % name, true)
	_bed.volume_db = -14.0
	_bed.play()


func music(name: String) -> void:
	if name == _music_name:
		return
	_music_name = name
	if name == "":
		_music.stop()
		return
	var s := _load("res://audio/music/%s.wav" % name, true)
	if s == null:
		return
	_music.stream = s
	_music.volume_db = -6.0
	_music.play()


## Called every frame by the game: the generator hum during blackouts, street murmur by day,
## rain, and the danfo engine pitched by speed.
func world(night: bool, nepa_on: bool, driving: bool, speed: float, rain := 0.0) -> void:
	_fade(_amb["generator"], 0.6 if not nepa_on else 0.0)
	_fade(_amb["rain"], rain * 0.7)
	_fade(_amb["street"], 0.0 if night else 0.45)
	if driving:
		if not _engine.playing:
			_engine.play()
		_engine.pitch_scale = 0.8 + clampf(absf(speed) / 380.0, 0.0, 1.0) * 0.9
		_engine.volume_db = -10.0
	elif _engine.playing:
		_engine.stop()


func _fade(p: AudioStreamPlayer, target: float) -> void:
	if p.stream == null:
		return
	var want := linear_to_db(maxf(target, 0.0001))
	p.volume_db = lerpf(p.volume_db, want, 0.05)
	if target > 0.0 and not p.playing:
		p.play()
	elif target <= 0.0 and p.volume_db < -60.0 and p.playing:
		p.stop()
