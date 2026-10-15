extends Node
## Autoload "Net": connection to the Naija Street Life server (docs/COOLIFY.md).
## Protocol: see apps/server/src/realtime.ts. Reconnects with backoff on flaky mobile networks.

signal status_changed(text: String)
signal welcomed(id: int, room: String)
signal met(id: int, name: String, look: Dictionary)
signal moved(id: int, pos: Vector2, facing: int, mode: int, heading: float)
signal gone(id: int)
signal chat(msg: Dictionary) # street chat {id, pid, name, text, v}
signal dm(msg: Dictionary) # direct message {id, pid, to, name, text, sent?}
signal server_error(code: String)
signal clash(msg: Dictionary) # a collision with another player: {id, pid, name, ms}
signal clash_fight(msg: Dictionary) # {id, name, seq, windows, you, them}
signal clash_end(msg: Dictionary) # {id, outcome, winner?, scores?}
signal street_msg(msg: Dictionary) # M11: race_*, coop_*, box_* (street/street_online.gd)

const CFG := "user://net.cfg"
const SEND_HZ := 10.0

var server := ""
var player_name := "Tunde"
var token := ""
var my_id := -1
var my_pid := ""
var room := ""
var bytes_in := 0
var bytes_out := 0

var _ws: WebSocketPeer
var _state := "offline" # offline, connecting, online, waiting
var _retry_in := 0.0
var _backoff := 2.0
var _send_t := 0.0
var _last_sent := ""
var _last_pos := Vector2.INF
var _pending_hello := {}
var district := "yaba"
## Player ids (pid) of people met on the street, by member id: DMs, blocks and reports use them.
var pids := {}


func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	server = String(cfg.get_value("net", "server", ProjectSettings.get_setting("naija/online/default_server", "")))
	token = String(cfg.get_value("net", "token", ""))
	player_name = String(cfg.get_value("net", "name", "Tunde"))


func is_online() -> bool:
	return _state == "online"


func status_text() -> String:
	match _state:
		"online": return "Online · %s" % room
		"connecting": return "Connecting…"
		"waiting": return "Offline · retrying in %ds" % int(ceil(_retry_in))
	return "Offline"


func set_server(address: String, name_: String) -> void:
	server = address.strip_edges()
	player_name = name_.strip_edges().left(20) if name_.strip_edges() != "" else "Tunde"
	_save()
	disconnect_now()


## Begin connecting; `hello` carries look/position for the first message.
func start(hello: Dictionary) -> void:
	_pending_hello = hello
	if int(Settings.get_pref("age_ok", -1)) == 0:
		_set_state("offline") # safe mode for under-18s: no online play at all
		return
	if server == "":
		_set_state("offline")
		return
	_open()


func disconnect_now() -> void:
	if _ws:
		_ws.close()
	_ws = null
	my_id = -1
	_set_state("offline")


func url_for(address: String) -> String:
	var a := address.strip_edges().trim_suffix("/")
	if a.begins_with("ws://") or a.begins_with("wss://"):
		return a if a.ends_with("/ws") else a + "/ws"
	a = a.trim_prefix("https://").trim_prefix("http://")
	if a.begins_with("localhost"):
		a = "127.0.0.1" + a.trim_prefix("localhost") # Godot tries IPv6 first; dev servers listen on IPv4
	var local := a.begins_with("localhost") or a.begins_with("127.") or a.begins_with("10.") or a.begins_with("192.168.")
	return ("ws://" if local else "wss://") + a + "/ws"


func _open() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	var err := _ws.connect_to_url(url_for(server))
	if err != OK:
		_schedule_retry()
		return
	_set_state("connecting")


func _process(delta: float) -> void:
	if _state == "waiting":
		_retry_in -= delta
		if _retry_in <= 0.0:
			_open()
		return
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if _state == "connecting":
				var hello := _pending_hello.duplicate()
				hello["t"] = "hello"
				hello["name"] = player_name
				hello["district"] = district
				if token != "":
					hello["token"] = token
				_send(hello)
				_set_state("online")
				_backoff = 2.0
			while _ws.get_available_packet_count() > 0:
				var pkt := _ws.get_packet()
				bytes_in += pkt.size()
				_handle(JSON.parse_string(pkt.get_string_from_utf8()))
			_send_t -= delta
		WebSocketPeer.STATE_CLOSED:
			_ws = null
			my_id = -1
			_schedule_retry()


## Called every frame by the game; actually sends at most SEND_HZ and only on change.
func send_move(pos: Vector2, facing: int, mode: int, heading_deg: float) -> void:
	if _state != "online" or my_id < 0 or _send_t > 0.0:
		return
	var msg := { "t": "move", "x": int(round(pos.x)), "y": int(round(pos.y)), "f": facing, "m": mode, "h": int(round(heading_deg)) }
	var key := JSON.stringify(msg)
	if key == _last_sent:
		return
	# A big jump (story warp, fast travel) is flagged so the server's speed check accepts it.
	if _last_pos != Vector2.INF and pos.distance_to(_last_pos) > 400.0:
		msg["w"] = 1
	_last_pos = pos
	_last_sent = key
	_send_t = 1.0 / SEND_HZ
	_send(msg)


## Style changed (M10): the server re-introduces us to everyone nearby with the new look.
func send_look(look: Dictionary) -> void:
	if _pending_hello.has("look"):
		_pending_hello["look"] = look # reconnects say hello with the current style
	send_msg({ "t": "look", "look": look })


## Any other realtime message (clash bump/choice/result).
func send_msg(msg: Dictionary) -> void:
	if _state == "online" and _ws:
		_send(msg)


func _send(msg: Dictionary) -> void:
	var s := JSON.stringify(msg)
	bytes_out += s.length()
	_ws.send_text(s)


func _handle(m: Variant) -> void:
	if typeof(m) != TYPE_DICTIONARY:
		return
	match String(m.get("t", "")):
		"welcome":
			my_id = int(m["id"])
			my_pid = String(m.get("pid", ""))
			_last_pos = Vector2.INF
			room = String(m.get("room", ""))
			if m.has("token"):
				token = String(m["token"])
				_save()
			welcomed.emit(my_id, room)
			_set_state("online")
		"snap":
			for p in m.get("meet", []):
				pids[int(p["id"])] = String(p.get("pid", ""))
				met.emit(int(p["id"]), String(p.get("name", "")), p.get("look", {}))
			for r in m.get("p", []):
				moved.emit(int(r[0]), Vector2(r[1], r[2]), int(r[3]), int(r[4]), float(r[5]))
			for id in m.get("gone", []):
				gone.emit(int(id))
		"chat":
			chat.emit(m)
		"dm":
			dm.emit(m)
		"clash":
			clash.emit(m)
		"clash_fight":
			clash_fight.emit(m)
		"clash_end":
			clash_end.emit(m)
		_ when String(m.get("t", "")).begins_with("race_") or String(m.get("t", "")).begins_with("coop_") or String(m.get("t", "")).begins_with("box_"):
			street_msg.emit(m)
		"err":
			server_error.emit(String(m.get("code", "?")))
			push_warning("server: %s" % m.get("code", "?"))


func send_chat(text: String) -> void:
	if _state == "online" and my_id >= 0:
		_send({ "t": "chat", "text": text.left(280) })


func send_dm(to_pid: String, text: String) -> void:
	if _state == "online" and my_id >= 0:
		_send({ "t": "dm", "to": to_pid, "text": text.left(280) })


func http_base() -> String:
	var ws := url_for(server) if server != "" else ""
	return ws.replace("wss://", "https://").replace("ws://", "http://").trim_suffix("/ws")


## REST call to the server: `await Net.api("GET", "/api/gigs")` →
## { ok: bool, code: int, data: Variant }. Works offline too (ok = false, code = 0).
func api(method: String, path: String, body: Variant = null) -> Dictionary:
	if server == "":
		return { "ok": false, "code": 0, "data": { "error": "offline" } }
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var m: int = { "GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST, "PUT": HTTPClient.METHOD_PUT, "DELETE": HTTPClient.METHOD_DELETE }.get(method, HTTPClient.METHOD_GET)
	var payload := JSON.stringify(body) if body != null else ("{}" if method in ["POST", "PUT"] else "")
	var err := http.request(http_base() + path, headers, m, payload)
	if err != OK:
		http.queue_free()
		return { "ok": false, "code": 0, "data": { "error": "offline" } }
	var res: Array = await http.request_completed
	http.queue_free()
	var code := int(res[1])
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	var json := JSON.new()
	var parsed: Variant = json.data if text != "" and json.parse(text) == OK else null
	return { "ok": code >= 200 and code < 300, "code": code, "data": parsed if parsed is Dictionary else {} }


## After phone verification on a new device the server hands back the original account's token.
func adopt_token(t: String) -> void:
	token = t
	_save()
	disconnect_now()
	start(_pending_hello)


func _schedule_retry() -> void:
	_retry_in = _backoff
	_backoff = minf(_backoff * 2.0, 30.0)
	_set_state("waiting" if server != "" else "offline")


func _set_state(s: String) -> void:
	_state = s
	status_changed.emit(status_text())


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "server", server)
	cfg.set_value("net", "token", token)
	cfg.set_value("net", "name", player_name)
	cfg.save(CFG)
