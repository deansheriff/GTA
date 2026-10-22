class_name Combat3D
extends Node
## Fights (D-021, D-022, D-028): Dayo is army-trained. Hand to hand, enemies close in and take
## turns to swing; the player punches (J, left click or PUNCH) whoever is in front. With a gun (from
## Act I's Seme Run) the player shoots (K, left click or SHOOT) at the locked target: the nearest
## enemy (or hostile boat or car) roughly ahead, marked with a red ring, even from a moving vehicle.
## Enemy types: thug (fists), brute (slow, hits hard, shrugs off a punch now and then), gunman
## (pistol, keeps his distance), rifleman (longer range, bursts) and the boss (Obinna with the lion
## staff: a telegraphed sweep, blocks punches from the front, calls his men at half health).
## Feel: hit flashes, floating damage, hit-stop on a heavy blow, a hit marker, enemy health bars.
## Standing still against a wall is cover: gunmen hit far less often. At 0 health a fighter goes
## down. Win when everyone is down; lose at 0 health. Health comes back slowly between fights.

signal finished(won: bool)

const REACH := 1.9
const ENEMY_SPEED := 2.6
const ENEMY_REACH := 1.5
const PLAYER_MAX := 10
const CLIP := 12
const GUN_RANGE := 32.0
## type -> {hp, speed, dmg, gun, range, cool: [min, max], burst}
const TYPES := {
	"thug": { "hp": 3, "speed": 2.6, "dmg": 1, "gun": false },
	"brute": { "hp": 7, "speed": 1.9, "dmg": 2, "gun": false, "tough": 0.3 },
	"gunman": { "hp": 4, "speed": 2.6, "dmg": 1, "gun": true, "range": 30.0, "cool": [1.0, 1.9], "burst": 1 },
	"rifle": { "hp": 5, "speed": 2.4, "dmg": 1, "gun": true, "range": 40.0, "cool": [1.8, 2.6], "burst": 3 },
	"boss": { "hp": 30, "speed": 2.9, "dmg": 2, "gun": false, "boss": true },
}

var world # Street3D
var active := false
var player_hp := PLAYER_MAX
var enemies: Array = [] # {node, hp, max, type, cool, busy, id, gun, bar: Label3D}
var _player_cool := 0.0
var _rng := RandomNumberGenerator.new()
var armed := false
var clip := 12
var reserve := 48
var _reload_t := 0.0
var _regen_t := 0.0
var _lock: Label3D
var _target: Variant = null # Dictionary (enemy) or Vehicle3D
var _boss_called := false
var hostile_vehicles: Array = [] # Vehicle3D shooting at Dayo (gunboats, chase cars)


func setup(w) -> void:
	world = w
	_lock = Label3D.new()
	_lock.text = "◎"
	_lock.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_lock.no_depth_test = true
	_lock.font_size = 128
	_lock.pixel_size = 0.009
	_lock.modulate = Color(1.0, 0.25, 0.2, 0.9)
	_lock.outline_size = 0
	_lock.visible = false
	world.add_child(_lock)


## Damage to Dayo scaled by the difficulty setting (Easy 0.6, Normal 1, Hard 1.4).
func _dmg_k() -> float:
	return [0.6, 1.0, 1.4][clampi(int(Settings.get_pref("difficulty", 1)), 0, 2)]


## specs: [{id, who, hp, gun, type, pos}] (cast ids). Spawns them in a ring around the player (or
## at `pos`).
func start(specs: Array) -> void:
	clear()
	active = true
	_boss_called = false
	player_hp = PLAYER_MAX
	for i in specs.size():
		_spawn(specs[i], i, specs.size())


func _spawn(s: Dictionary, i: int, n: int) -> void:
	var p: Vector3 = world.focus()
	var type := String(s.get("type", "gunman" if bool(s.get("gun", false)) else "thug"))
	var t: Dictionary = TYPES.get(type, TYPES["thug"])
	var ang := TAU * i / maxf(1.0, n) + 0.6
	var ring := float(s.get("ring", 12.0 if t["gun"] else 4.0))
	var at: Vector3 = s["pos"] if s.has("pos") else p + Vector3(cos(ang), 0, sin(ang)) * ring
	var node: Person3D = world.spawn_actor("fight_" + String(s.get("id", str(i))), String(s.get("who", "agbero")), at, "idle", "player", String(s.get("prop", "")))
	if node == null:
		return
	if s.has("pos"):
		node.position.y = (s["pos"] as Vector3).y
	var hp := int(s.get("hp", t["hp"]))
	var bar := Label3D.new()
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.no_depth_test = true
	bar.font_size = 40
	bar.pixel_size = 0.006
	bar.outline_size = 6
	bar.modulate = Color("#e8483a")
	bar.position = Vector3(0, 2.15, 0)
	node.add_child(bar)
	var e := { "node": node, "hp": hp, "max": hp, "type": type, "cool": _rng.randf_range(0.8, 2.0), "busy": 0.0, "id": s.get("id", ""), "gun": bool(t["gun"]), "bar": bar, "wind": 0.0 }
	enemies.append(e)
	_bar(e)


func _bar(e: Dictionary) -> void:
	var bar: Label3D = e["bar"]
	if not is_instance_valid(bar):
		return
	var hp := maxi(0, int(e["hp"]))
	var mx := maxi(1, int(e["max"]))
	var cells := 10 if mx > 10 else mx
	var on := int(ceil(float(hp) / mx * cells))
	bar.text = "▮".repeat(on) + "▯".repeat(cells - on) if hp > 0 else ""


func clear() -> void:
	for e: Dictionary in enemies:
		if is_instance_valid(e["node"]):
			(e["node"] as Node).queue_free()
	enemies.clear()
	hostile_vehicles.clear()
	active = false
	_target = null
	if _lock:
		_lock.visible = false


func alive() -> int:
	return enemies.filter(func(e: Dictionary) -> bool: return int(e["hp"]) > 0).size() + hostile_vehicles.filter(func(v: Vehicle3D) -> bool: return is_instance_valid(v) and not v.is_wreck).size()


func step(delta: float) -> void:
	_player_cool = maxf(0.0, _player_cool - delta)
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			var take := mini(CLIP - clip, reserve)
			clip += take
			reserve -= take
	_update_lock()
	var regen_every := 0.8 if world.roam and world.roam.buffs.has("regen") else 2.0
	if not active:
		_regen_t += delta
		if _regen_t > regen_every and player_hp < PLAYER_MAX:
			_regen_t = 0.0
			player_hp += 1
		return
	var pp: Vector3 = world.focus()
	# Only two attack at once; the rest circle, the way street fights go.
	var attackers := 0
	for e: Dictionary in enemies:
		if int(e["hp"]) <= 0:
			continue
		var n: Person3D = e["node"]
		if not is_instance_valid(n):
			e["hp"] = 0
			continue
		var t: Dictionary = TYPES.get(e["type"], TYPES["thug"])
		e["busy"] = maxf(0.0, float(e["busy"]) - delta)
		e["cool"] = float(e["cool"]) - delta
		var to := pp - n.position
		to.y = 0.0
		var d := to.length()
		n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(1.0, delta * (4.0 if t.has("boss") else 10.0)))
		if float(e["wind"]) > 0.0:
			e["wind"] = float(e["wind"]) - delta
			if float(e["wind"]) <= 0.0:
				_boss_sweep(e)
			continue
		if float(e["busy"]) > 0.0:
			continue
		if bool(e["gun"]):
			_gunman(e, n, to, d, delta, t)
			continue
		var close_in := attackers < 2 or t.has("boss")
		var spd := float(t["speed"]) * (1.35 if t.has("boss") and int(e["hp"]) < int(e["max"]) * 0.25 else 1.0)
		if d > ENEMY_REACH and close_in:
			n.position += to / maxf(d, 0.01) * spd * delta
			Models3D.play(n.ap, "run" if d > 4.0 else "walk", "idle")
		elif d > 3.2:
			n.position += to / maxf(d, 0.01) * spd * 0.6 * delta
			Models3D.play(n.ap, "walk", "idle")
		else:
			Models3D.play(n.ap, "idle", "")
		if close_in:
			attackers += 1
		var reach := 2.7 if t.has("boss") else ENEMY_REACH + 0.2
		if d <= reach and float(e["cool"]) <= 0.0:
			if t.has("boss"):
				# The staff: a wind-up you can see coming (step back!), then a wide sweep.
				e["cool"] = _rng.randf_range(1.4, 2.2)
				e["wind"] = 0.55
				Models3D.play(n.ap, "kick", "punch", 0.8)
				world.fx.pop(n.position, "!", Color("#ffd24d"))
			else:
				e["cool"] = _rng.randf_range(1.3, 2.3) * (1.3 if e["type"] == "brute" else 1.0)
				e["busy"] = 0.7
				Models3D.play(n.ap, "punch", "idle", 1.4 if e["type"] != "brute" else 1.0)
				_land_enemy_hit.call_deferred(e)
		if t.has("boss") and not _boss_called and int(e["hp"]) <= int(e["max"]) / 2:
			_boss_called = true
			world.notify("\"Boys!\" Obinna's men climb aboard.")
			for k in 2:
				_spawn({ "id": "bossman%d" % k, "who": "gunman", "type": "thug", "pos": n.position + Vector3(4 - k * 8, 0, 3) }, k, 2)
	for v: Vehicle3D in hostile_vehicles.duplicate():
		if not is_instance_valid(v):
			hostile_vehicles.erase(v)
	if player_hp <= 0:
		active = false
		finished.emit(false)
	elif alive() == 0:
		active = false
		_lock.visible = false
		finished.emit(true)


func _boss_sweep(e: Dictionary) -> void:
	var n: Person3D = e["node"]
	if not is_instance_valid(n) or int(e["hp"]) <= 0:
		return
	Models3D.play(n.ap, "punch", "idle", 1.6)
	Sound.sfx("whoosh", 0.7)
	var to: Vector3 = world.player.position - n.position
	to.y = 0.0
	var fwd := Vector3(sin(n.rotation.y), 0, cos(n.rotation.y))
	if to.length() < 2.9 and to.normalized().dot(fwd) > 0.3:
		hurt_player(int(TYPES["boss"]["dmg"]), n.position)
		world.fx.hitstop(0.08)


## An armed enemy: keep his distance, strafe a little, fire every second or two (riflemen in
## bursts). Harder to hit a player who is running, driving fast, or in cover.
func _gunman(e: Dictionary, n: Person3D, to: Vector3, d: float, delta: float, t: Dictionary) -> void:
	var dir := to / maxf(d, 0.01)
	var far := 18.0 if e["type"] == "rifle" else 14.0
	if d > far:
		n.position += dir * float(t["speed"]) * delta
		Models3D.play(n.ap, "run", "walk")
	elif d < 6.0:
		n.position -= dir * float(t["speed"]) * 0.7 * delta
		Models3D.play(n.ap, "walk", "idle")
	else:
		Models3D.play(n.ap, "gun_idle", "idle")
	if float(e["cool"]) > 0.0 or d > float(t.get("range", GUN_RANGE)):
		return
	var cool: Array = t.get("cool", [1.0, 1.9])
	e["cool"] = _rng.randf_range(float(cool[0]), float(cool[1]))
	for k in int(t.get("burst", 1)):
		_enemy_shot.call_deferred(n.position + Vector3(0, 1.4, 0), d, k * 0.12)


func _enemy_shot(from: Vector3, d: float, after: float) -> void:
	if after > 0.0:
		await world.get_tree().create_timer(after).timeout
	if not active and hostile_vehicles.is_empty():
		return
	var target: Vector3 = world.focus() + Vector3(0, 1.1, 0)
	var moving: float = absf(world.ride.speed) if world.ride else (4.0 if world.player.moving >= 2.0 else 0.0)
	var chance := clampf(0.55 - d * 0.015 - moving * 0.02, 0.12, 0.55)
	if world.ride == null and world.player.in_cover:
		chance *= 0.35
	chance *= [0.7, 1.0, 1.25][clampi(int(Settings.get_pref("difficulty", 1)), 0, 2)]
	var hit := _rng.randf() < chance
	tracer(from, target + (Vector3.ZERO if hit else Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-0.5, 1.0), _rng.randf_range(-1.5, 1.5))))
	Sound.sfx("gunshot_far", _rng.randf_range(0.9, 1.1))
	_panic(from)
	if hit:
		world.hud.guide.hit_from(from)
		if world.ride:
			world.ride.damage(4.0)
		else:
			hurt_player(1, from)


## A hostile boat or car's gunner fires at Dayo.
func vehicle_fires(v: Vehicle3D) -> void:
	_enemy_shot(v.position + Vector3(0, 1.6, 0), v.position.distance_to(world.focus()), 0.0)


func hurt_player(n: int, from := Vector3.INF) -> void:
	if from != Vector3.INF:
		world.hud.guide.hit_from(from)
	# The Ìrókò charm (Baba Fakunle): some blows just don't land. Magic or adrenaline? Who knows.
	if world.roam and world.roam.buffs.has("iroko") and _rng.randf() < 0.3:
		world.fx.pop(world.player.position, "Ìrókò", Color("#9fe0ff"))
		return
	var dmg := maxi(1, int(round(n * _dmg_k())))
	player_hp -= dmg
	world.player.flinch()
	world.fx.flash(world.player.model, 0.1)
	world.shake(0.25)
	world.hud.hurt()
	if bool(Settings.get_pref("vibration", true)):
		Input.vibrate_handheld(60)


func _land_enemy_hit(e: Dictionary) -> void:
	await world.get_tree().create_timer(0.35).timeout
	if not active or int(e["hp"]) <= 0 or not is_instance_valid(e["node"]):
		return
	if (e["node"] as Node3D).position.distance_to(world.player.position) <= ENEMY_REACH + 0.4:
		hurt_player(int(TYPES.get(e["type"], TYPES["thug"])["dmg"]), (e["node"] as Node3D).position)
		Sound.sfx("punch", 0.8)


## Hurt an enemy: flash, number, knock back; down at 0.
func hurt_enemy(e: Dictionary, n: int, from := Vector3.INF) -> void:
	var node: Person3D = e["node"]
	if not is_instance_valid(node) or int(e["hp"]) <= 0:
		return
	e["hp"] = int(e["hp"]) - n
	e["busy"] = 0.45
	world.fx.flash(node)
	world.fx.pop(node.position, "-%d" % n)
	world.hud.hitmark()
	if from != Vector3.INF:
		var away: Vector3 = node.position - from
		away.y = 0.0
		node.position += away.normalized() * (0.35 if e["type"] in ["brute", "boss"] else 0.7)
	_bar(e)
	if int(e["hp"]) <= 0:
		Models3D.play(node.ap, "dead", "hit")
		world.shake(0.2)
		world.fx.dust(node.position)
	else:
		Models3D.play(node.ap, "hit", "idle", 1.3)


## The player's punch: hits the nearest standing enemy roughly in front (turning to face them).
func player_attack() -> void:
	if _player_cool > 0.0:
		return
	_player_cool = 0.42
	world.player.punch()
	var best: Dictionary = {}
	var bd := REACH
	for e: Dictionary in enemies:
		if int(e["hp"]) <= 0 or not is_instance_valid(e["node"]):
			continue
		var d: float = (e["node"] as Node3D).position.distance_to(world.player.position)
		if d < bd:
			bd = d
			best = e
	if best.is_empty():
		return
	var n: Person3D = best["node"]
	world.player.face(n.position)
	var t: Dictionary = TYPES.get(best["type"], TYPES["thug"])
	# The boss blocks with the staff when he's facing you; a brute sometimes shrugs it off.
	if t.has("boss") and float(best["wind"]) <= 0.0:
		var to_p: Vector3 = world.player.position - n.position
		var fwd := Vector3(sin(n.rotation.y), 0, cos(n.rotation.y))
		if to_p.normalized().dot(fwd) > 0.5 and _rng.randf() < 0.5:
			world.fx.pop(n.position, "BLOCK", Color("#cfd8e0"))
			Sound.sfx("tap", 0.6)
			return
	if _rng.randf() < float(t.get("tough", 0.0)):
		world.fx.pop(n.position, "0", Color("#cfd8e0"))
		Sound.sfx("punch", 0.7)
		return
	Sound.sfx("punch", _rng.randf_range(0.95, 1.15))
	world.fx.hitstop(0.05)
	hurt_enemy(best, 1, world.player.position)


## Give Dayo a pistol (Seme Run onwards).
func give_gun(rounds := 48) -> void:
	armed = true
	clip = CLIP
	reserve = maxi(reserve, rounds)


## Whom a shot would go to: the nearest enemy or hostile vehicle within range and roughly ahead.
func _pick_target() -> Variant:
	var look: Vector3 = -world.cam.global_transform.basis.z
	look.y = 0.0
	look = look.normalized()
	var best: Variant = null
	var bd := GUN_RANGE
	for e: Dictionary in enemies:
		if int(e["hp"]) <= 0 or not is_instance_valid(e["node"]):
			continue
		var rel: Vector3 = (e["node"] as Node3D).position - world.focus()
		rel.y = 0.0
		var d := rel.length()
		if d < bd and rel.normalized().dot(look) > 0.35:
			bd = d
			best = e
	for v: Vehicle3D in hostile_vehicles:
		if not is_instance_valid(v) or v.is_wreck:
			continue
		var rel: Vector3 = v.position - world.focus()
		rel.y = 0.0
		var d := rel.length()
		if d < bd + 6.0 and rel.normalized().dot(look) > 0.3:
			bd = d
			best = v
	return best


func _update_lock() -> void:
	var show := armed and (active or not hostile_vehicles.is_empty())
	_target = _pick_target() if show else null
	_lock.visible = _target != null
	if _target is Dictionary:
		_lock.global_position = ((_target as Dictionary)["node"] as Node3D).global_position + Vector3(0, 1.2, 0)
	elif _target is Vehicle3D:
		_lock.global_position = (_target as Vehicle3D).global_position + Vector3(0, 1.6, 0)


## The player's shot at the locked target (auto-aim, phone-friendly). Works on foot and from a
## vehicle (or a boat).
func player_shoot() -> void:
	if not armed or _player_cool > 0.0 or _reload_t > 0.0:
		return
	if clip <= 0:
		if reserve > 0:
			_reload_t = 1.1
			Sound.sfx("reload")
		return
	_player_cool = 0.28
	clip -= 1
	var from: Vector3 = world.focus() + Vector3(0, 1.5, 0)
	var look: Vector3 = -world.cam.global_transform.basis.z
	look.y = 0.0
	look = look.normalized()
	var best: Variant = _pick_target()
	Sound.sfx("gunshot", _rng.randf_range(0.95, 1.05))
	world.shake(0.08)
	_panic(from)
	if world.ride == null:
		world.player.shoot_anim()
	if best == null:
		tracer(from, from + look * 25.0)
	elif best is Vehicle3D:
		var v: Vehicle3D = best
		var hit := _rng.randf() < 0.7
		tracer(from, v.position + Vector3(0, 1.2, 0) + (Vector3.ZERO if hit else Vector3(_rng.randf_range(-2, 2), 0.5, _rng.randf_range(-2, 2))))
		if hit:
			v.damage(9.0)
			world.fx.flash(v, 0.08)
			world.hud.hitmark()
			if v.is_wreck:
				world.fx.explosion(v.position, 0.8)
				world.notify("Boat down!" if v.on_water else "Got them!")
	else:
		var e: Dictionary = best
		var n: Person3D = e["node"]
		if world.ride == null:
			world.player.face(n.position)
		var bd: float = n.position.distance_to(world.focus())
		var hit := _rng.randf() < clampf(1.05 - bd * 0.02, 0.45, 0.95)
		tracer(from, n.position + Vector3(0, 1.2, 0) + (Vector3.ZERO if hit else Vector3(_rng.randf_range(-1, 1), 0.4, _rng.randf_range(-1, 1))))
		if hit:
			hurt_enemy(e, 2)
	if clip == 0 and reserve > 0:
		_reload_t = 1.1
		Sound.sfx("reload")


## Gunfire scatters the street: everyone near runs from it.
func _panic(at: Vector3) -> void:
	for p: Person3D in world.people:
		var rel := p.position - at
		rel.y = 0.0
		if rel.length() < 32.0 and p.state != Person3D.State.FLEE:
			p.flee(at, rel.normalized().cross(Vector3.UP))
			p.pause_left = 3.0


## A bright streak from gun to target, for a few frames.
func tracer(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = maxf(0.1, a.distance_to(b))
	cyl.radial_segments = 4
	cyl.rings = 1
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.4)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = (a + b) * 0.5
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.global_transform.basis = Basis(side, up, side.cross(up))
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.4)
	flash.light_energy = 2.0
	flash.omni_range = 4.0
	world.add_child(flash)
	flash.global_position = a
	world.get_tree().create_timer(0.06).timeout.connect(func() -> void:
		mi.queue_free()
		flash.queue_free())
