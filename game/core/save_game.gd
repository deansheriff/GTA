extends Node
## Autoload "SaveGame": local save (atomic write) plus cloud sync to the owner's server.
## The world registers a provider for position/vehicle state; Life/Clock/jobs serialise themselves.
##
## Cloud protocol (apps/server): GET/PUT /api/save with "Authorization: Bearer <guest token>".
## The server keeps a revision number; the newer revision wins on load.

signal saved(where: String)
signal loaded(where: String)

const PATH := "user://save.json"
const VERSION := 1
const AUTOSAVE_SEC := 60.0

var world_provider: Callable # () -> Dictionary
var world_restorer: Callable # (Dictionary) -> void
var extra_providers := {} # name -> Callable returning Dictionary
var extra_restorers := {} # name -> Callable(Dictionary)
var revision := 0
var _timer := 0.0
var _http: HTTPRequest
var _pending_cloud := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= AUTOSAVE_SEC:
		_timer = 0.0
		save_now()


func snapshot() -> Dictionary:
	var extras := {}
	for k in extra_providers:
		extras[k] = (extra_providers[k] as Callable).call()
	return {
		"version": VERSION,
		"revision": revision,
		"saved_at": Time.get_unix_time_from_system(),
		"clock": Clock.to_dict(),
		"life": Life.to_dict(),
		"world": world_provider.call() if world_provider.is_valid() else {},
		"extras": extras,
	}


func save_now() -> void:
	revision += 1
	var data := snapshot()
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH))
	saved.emit("local")
	_push_cloud(data)


func load_local() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		return false
	apply(parsed)
	loaded.emit("local")
	return true


func apply(d: Dictionary) -> void:
	revision = int(d.get("revision", 0))
	Clock.from_dict(d.get("clock", {}))
	Life.from_dict(d.get("life", {}))
	if world_restorer.is_valid():
		world_restorer.call(d.get("world", {}))
	var extras: Dictionary = d.get("extras", {})
	for k in extra_restorers:
		if extras.has(k):
			(extra_restorers[k] as Callable).call(extras[k])


func wipe() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


# ---------- cloud ----------

func _base_url() -> String:
	var ws := Net.url_for(Net.server) if Net.server != "" else ""
	return ws.replace("wss://", "https://").replace("ws://", "http://").trim_suffix("/ws")


func _push_cloud(data: Dictionary) -> void:
	if Net.token == "" or Net.server == "" or _pending_cloud:
		return
	_pending_cloud = true
	var headers := ["Content-Type: application/json", "Authorization: Bearer " + Net.token]
	var body := JSON.stringify({ "revision": revision, "data": data })
	var err := _http.request(_base_url() + "/api/save", headers, HTTPClient.METHOD_PUT, body)
	if err != OK:
		_pending_cloud = false
		return
	var res: Array = await _http.request_completed
	_pending_cloud = false
	if int(res[1]) == 200:
		saved.emit("cloud")


## On start: fetch the cloud save and use it if it's newer than the local one.
func pull_cloud() -> void:
	if Net.token == "" or Net.server == "":
		return
	var err := _http.request(_base_url() + "/api/save", ["Authorization: Bearer " + Net.token], HTTPClient.METHOD_GET)
	if err != OK:
		return
	var res: Array = await _http.request_completed
	if int(res[1]) != 200:
		return
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if parsed is Dictionary and parsed.get("data") is Dictionary and int(parsed.get("revision", 0)) > revision:
		apply(parsed["data"])
		revision = int(parsed["revision"])
		loaded.emit("cloud")
