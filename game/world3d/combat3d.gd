class_name Combat3D
extends Node
## Fights (D-021, D-022): Dayo is army-trained. Hand to hand, enemies close in and take turns to
## swing; the player punches (J, left click or PUNCH) whoever is in front. With a gun (from Act I's
## Seme Run) the player shoots (K, left click or SHOOT) at the nearest enemy roughly ahead, even from
## a moving vehicle; armed enemies keep their distance and fire back. At 0 health a fighter goes
## down. Win when everyone is down; lose at 0 health. Health comes back slowly between fights.

signal finished(won: bool)

const REACH := 1.9
const ENEMY_SPEED := 2.6
const ENEMY_REACH := 1.5
const PLAYER_MAX := 10

var world # Street3D
var active := false
var player_hp := PLAYER_MAX
var enemies: Array = [] # {node: Person3D, hp, cool, busy, id}
var _player_cool := 0.0
var _rng := RandomNumberGenerator.new()
var armed := false
var clip := 12
var reserve := 48
var _reload_t := 0.0
var _regen_t := 0.0
const CLIP := 12
const GUN_RANGE := 32.0


func setup(w) -> void:
	world = w


## specs: [{id, who, hp}] (cast ids). Spawns them in a ring around the player.
func start(specs: Array) -> void:
	clear()
	active = true
	player_hp = PLAYER_MAX
	var p: Vector3 = world.focus()
	for i in specs.size():
		var s: Dictionary = specs[i]
		var ang := TAU * i / maxf(1.0, specs.size()) + 0.6
		var ring := 12.0 if bool(s.get("gun", false)) else 4.0
		var node: Person3D = world.spawn_actor("fight_" + String(s.get("id", str(i))), String(s.get("who", "agbero")), p + Vector3(cos(ang), 0, sin(ang)) * ring, "idle", "player")
		if node:
			enemies.append({ "node": node, "hp": int(s.get("hp", 3)), "cool": _rng.randf_range(0.8, 2.0), "busy": 0.0, "id": s.get("id", ""), "gun": bool(s.get("gun", false)) })


func clear() -> void:
	for e: Dictionary in enemies:
		if is_instance_valid(e["node"]):
			(e["node"] as Node).queue_free()
	enemies.clear()
	active = false


func alive() -> int:
	return enemies.filter(func(e: Dictionary) -> bool: return int(e["hp"]) > 0).size()


func step(delta: float) -> void:
	_player_cool = maxf(0.0, _player_cool - delta)
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			var take := mini(CLIP - clip, reserve)
			clip += take
			reserve -= take
	if not active:
		_regen_t += delta
		if _regen_t > 2.0 and player_hp < PLAYER_MAX:
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
		e["busy"] = maxf(0.0, float(e["busy"]) - delta)
		e["cool"] = float(e["cool"]) - delta
		var to := pp - n.position
		to.y = 0.0
		var d := to.length()
		n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 10.0))
		if float(e["busy"]) > 0.0:
			continue
		if bool(e["gun"]):
			_gunman(e, n, to, d, delta)
			continue
		var close_in := attackers < 2
		if d > ENEMY_REACH and close_in:
			n.position += to / maxf(d, 0.01) * ENEMY_SPEED * delta
			Models3D.play(n.ap, "walk", "idle")
		elif d > 3.2:
			n.position += to / maxf(d, 0.01) * ENEMY_SPEED * 0.6 * delta
			Models3D.play(n.ap, "walk", "idle")
		else:
			Models3D.play(n.ap, "idle", "")
		if close_in:
			attackers += 1
		if d <= ENEMY_REACH + 0.2 and float(e["cool"]) <= 0.0:
			e["cool"] = _rng.randf_range(1.3, 2.3)
			e["busy"] = 0.7
			Models3D.play(n.ap, "punch", "idle", 1.4)
			_land_enemy_hit.call_deferred(e)
	if player_hp <= 0:
		active = false
		finished.emit(false)
	elif alive() == 0:
		active = false
		finished.emit(true)


## An armed enemy: keep 6-14 m away, strafe a little, fire every second or two. Harder to hit a
## player who is running or driving fast.
func _gunman(e: Dictionary, n: Person3D, to: Vector3, d: float, delta: float) -> void:
	var dir := to / maxf(d, 0.01)
	if d > 14.0:
		n.position += dir * ENEMY_SPEED * delta
		Models3D.play(n.ap, "run", "walk")
	elif d < 6.0:
		n.position -= dir * ENEMY_SPEED * 0.7 * delta
		Models3D.play(n.ap, "walk", "idle")
	else:
		Models3D.play(n.ap, "idle", "")
	if float(e["cool"]) > 0.0 or d > GUN_RANGE:
		return
	e["cool"] = _rng.randf_range(1.0, 1.9)
	var from := n.position + Vector3(0, 1.4, 0)
	var target: Vector3 = world.focus() + Vector3(0, 1.1, 0)
	var moving: float = absf(world.ride.speed) if world.ride else (4.0 if world.player.moving >= 2.0 else 0.0)
	var chance := clampf(0.55 - d * 0.015 - moving * 0.02, 0.12, 0.55)
	var hit := _rng.randf() < chance
	tracer(from, target + (Vector3.ZERO if hit else Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-0.5, 1.0), _rng.randf_range(-1.5, 1.5))))
	Sound.sfx("gunshot_far", _rng.randf_range(0.9, 1.1))
	if hit:
		if world.ride:
			world.ride.damage(4.0)
		else:
			player_hp -= 1
			world.player.flinch()
			world.shake(0.2)


func _land_enemy_hit(e: Dictionary) -> void:
	await world.get_tree().create_timer(0.35).timeout
	if not active or int(e["hp"]) <= 0 or not is_instance_valid(e["node"]):
		return
	if (e["node"] as Node3D).position.distance_to(world.player.position) <= ENEMY_REACH + 0.4:
		player_hp -= 1
		world.player.flinch()
		Sound.sfx("punch", 0.8)
		world.shake(0.25)


## The player's punch: hits the nearest standing enemy roughly in front (turning to face them).
func player_attack() -> void:
	if _player_cool > 0.0:
		return
	_player_cool = 0.42
	world.player.punch()
	var best: Dictionary = {}
	var bd := REACH
	for e: Dictionary in enemies:
		if int(e["hp"]) <= 0:
			continue
		var d: float = (e["node"] as Node3D).position.distance_to(world.player.position)
		if d < bd:
			bd = d
			best = e
	if best.is_empty():
		return
	var n: Person3D = best["node"]
	world.player.face(n.position)
	best["hp"] = int(best["hp"]) - 1
	best["busy"] = 0.55
	Sound.sfx("punch", _rng.randf_range(0.95, 1.15))
	var away: Vector3 = n.position - world.player.position
	away.y = 0.0
	n.position += away.normalized() * 0.7
	if int(best["hp"]) <= 0:
		Models3D.play(n.ap, "dead", "hit")
		world.shake(0.2)
	else:
		Models3D.play(n.ap, "hit", "idle", 1.3)


## Give Dayo a pistol (Seme Run onwards).
func give_gun(rounds := 48) -> void:
	armed = true
	clip = CLIP
	reserve = maxi(reserve, rounds)


## The player's shot: the nearest standing enemy within range and roughly ahead of the camera
## (auto-aim, phone-friendly). Works on foot and from a vehicle.
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
	var best: Dictionary = {}
	var bd := GUN_RANGE
	for e: Dictionary in enemies:
		if int(e["hp"]) <= 0:
			continue
		var rel: Vector3 = (e["node"] as Node3D).position - world.focus()
		rel.y = 0.0
		var d := rel.length()
		if d < bd and rel.normalized().dot(look) > 0.35:
			bd = d
			best = e
	Sound.sfx("gunshot", _rng.randf_range(0.95, 1.05))
	world.shake(0.08)
	if world.ride == null:
		world.player.shoot_anim()
	if best.is_empty():
		tracer(from, from + look * 25.0)
		return
	var n: Person3D = best["node"]
	if world.ride == null:
		world.player.face(n.position)
	var hit := _rng.randf() < clampf(1.05 - bd * 0.02, 0.45, 0.95)
	tracer(from, n.position + Vector3(0, 1.2, 0) + (Vector3.ZERO if hit else Vector3(_rng.randf_range(-1, 1), 0.4, _rng.randf_range(-1, 1))))
	if not hit:
		return
	best["hp"] = int(best["hp"]) - 2
	best["busy"] = 0.4
	if int(best["hp"]) <= 0:
		Models3D.play(n.ap, "dead", "hit")
	else:
		Models3D.play(n.ap, "hit", "idle", 1.3)
	if clip == 0 and reserve > 0:
		_reload_t = 1.1
		Sound.sfx("reload")


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
