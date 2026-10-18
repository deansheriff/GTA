class_name Combat3D
extends Node
## Hand-to-hand fights (D-021): Dayo is army-trained. Enemies close in and take turns to swing;
## the player punches (J, left click or the PUNCH button) whoever is in front. Hits stagger and
## knock back; at 0 health a fighter goes down. Win when everyone is down; lose at 0 health.

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


func setup(w) -> void:
	world = w


## specs: [{id, who, hp}] (cast ids). Spawns them in a ring around the player.
func start(specs: Array) -> void:
	clear()
	active = true
	player_hp = PLAYER_MAX
	var p: Vector3 = world.player.position
	for i in specs.size():
		var s: Dictionary = specs[i]
		var ang := TAU * i / maxf(1.0, specs.size()) + 0.6
		var node: Person3D = world.spawn_actor("fight_" + String(s.get("id", str(i))), String(s.get("who", "agbero")), p + Vector3(cos(ang), 0, sin(ang)) * 4.0, "idle", "player")
		if node:
			enemies.append({ "node": node, "hp": int(s.get("hp", 3)), "cool": _rng.randf_range(0.8, 2.0), "busy": 0.0, "id": s.get("id", "") })


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
	if not active:
		return
	var pp: Vector3 = world.player.position
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
