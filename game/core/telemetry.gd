extends Node
## Autoload "Telemetry": opt-in, anonymous gameplay stats and crash reports (M7, privacy policy).
## Nothing is recorded or sent unless the player said yes (Settings pref "telemetry").
## The session id is random per install, never linked to the account. Events are whitelisted on
## the server too. Script errors are captured with a Godot Logger and sent with the next batch.

const FLUSH_SEC := 60.0
const MAX_QUEUE := 100

var session := ""
var _events: Array = []
var _crashes: Array = []
var _t := 0.0
var _fps_t := 0.0
var _mutex := Mutex.new()
var _logger: Logger


class CrashLogger extends Logger:
	var owner: Node

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		owner.record_crash(("%s %s" % [code, rationale]).strip_edges(), "%s:%d in %s" % [file.get_file(), line, function])

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://telemetry.cfg")
	session = String(cfg.get_value("t", "session", ""))
	if session == "":
		var c := Crypto.new()
		session = c.generate_random_bytes(12).hex_encode()
		cfg.set_value("t", "session", session)
		cfg.save("user://telemetry.cfg")
	_logger = CrashLogger.new()
	_logger.owner = self
	OS.add_logger(_logger)
	event("session_start", { "preset": String(Settings.get_value("preset", "")), "os": OS.get_name() })


func enabled() -> bool:
	return Settings.get_pref("telemetry", false) == true


func event(name: String, props := {}) -> void:
	if not enabled():
		return
	_mutex.lock()
	if _events.size() < MAX_QUEUE:
		_events.append({ "name": name, "props": props })
	_mutex.unlock()


func record_crash(message: String, where: String) -> void:
	if not enabled():
		return
	_mutex.lock()
	if _crashes.size() < 10:
		_crashes.append({ "message": message.left(300), "stack": where.left(500) })
	_mutex.unlock()


func _process(delta: float) -> void:
	if not enabled():
		return
	_fps_t += delta
	if _fps_t >= 300.0:
		_fps_t = 0.0
		var fps := Engine.get_frames_per_second()
		event("fps_bucket", { "bucket": 60 if fps >= 55 else (45 if fps >= 40 else (30 if fps >= 25 else 15)), "preset": String(Settings.get_value("preset", "")) })
	_t += delta
	if _t >= FLUSH_SEC:
		_t = 0.0
		flush()


func flush() -> void:
	if Net.server == "" or not enabled():
		return
	_mutex.lock()
	var events := _events.duplicate()
	var crashes := _crashes.duplicate()
	_events.clear()
	_crashes.clear()
	_mutex.unlock()
	if events.is_empty() and crashes.is_empty():
		return
	await Net.api("POST", "/api/telemetry", {
		"session": session, "version": String(ProjectSettings.get_setting("application/config/version", "0.9.0")),
		"platform": OS.get_name(), "events": events, "crashes": crashes,
	})


func _exit_tree() -> void:
	if _logger:
		OS.remove_logger(_logger)
