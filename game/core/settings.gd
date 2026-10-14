extends Node
## Autoload "Settings": the current graphics settings, persisted to user://settings.cfg.

signal changed(settings: Dictionary)

const PATH := "user://settings.cfg"

var current: Dictionary = DeviceProfile.from_preset("medium")
var suggestion: Dictionary = {}
var first_run := true


func _ready() -> void:
	suggestion = DeviceProfile.suggest(DeviceProfile.read_signals())
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK and cfg.has_section("graphics"):
		first_run = false
		var base := DeviceProfile.from_preset(String(cfg.get_value("graphics", "preset", "medium")))
		for key in base.keys():
			base[key] = cfg.get_value("graphics", key, base[key])
		current = base
	else:
		current = DeviceProfile.from_preset(suggestion["preset"], suggestion["data_saver"])
	_apply_engine()


func set_all(next: Dictionary) -> void:
	current = next
	_apply_engine()
	_save()
	changed.emit(current)


func set_value(key: String, value: Variant) -> void:
	var next := current.duplicate()
	next[key] = value
	next["preset"] = "custom"
	set_all(next)


func use_preset(preset: String) -> void:
	set_all(DeviceProfile.from_preset(preset, current.get("data_saver", false)))


func get_value(key: String, fallback: Variant = null) -> Variant:
	return current.get(key, fallback)


func _apply_engine() -> void:
	Engine.max_fps = int(current.get("fps_cap", 60))


func _save() -> void:
	var cfg := ConfigFile.new()
	for key in current.keys():
		cfg.set_value("graphics", key, current[key])
	cfg.save(PATH)
