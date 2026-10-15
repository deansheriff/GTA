class_name Reactions
extends Node
## Pedestrians react (M9 #20): they shout at near-misses, gasp at crashes, run from the rain,
## and a crowd gathers in a ring to watch every fight. Knock someone over and the area notices
## (Area heat, street reputation).

var host: StreetHost
var main: Node2D
var _cool := {} # ped instance id -> seconds until they can shout again
var _watching: Array = [] # crowd members gathered round a fight
var _watch_t := 0.0
var _rain_t := 0.0
var _hit_cd := 0.0


func setup(h: StreetHost) -> void:
	host = h
	main = h.main


func _lines(kind: String) -> Array:
	return Street.db["reactions"][kind]


func _can(p: Node2D) -> bool:
	return float(_cool.get(p.get_instance_id(), 0.0)) <= 0.0


func _shout(p: Node2D, kind: String, cool := 6.0) -> void:
	host.fx.say(p, host.pick(_lines(kind)), 2.2)
	_cool[p.get_instance_id()] = cool


func tick(dt: float) -> void:
	for k in _cool.keys():
		_cool[k] = float(_cool[k]) - dt
		if float(_cool[k]) < -30.0:
			_cool.erase(k)
	_hit_cd = maxf(0.0, _hit_cd - dt)
	if main.mode == "driving":
		var d: Node2D = main.danfo
		var sp := absf(d.speed)
		if sp > 180.0:
			for p: Node2D in main.crowd.people:
				var dist := p.position.distance_to(d.position)
				if dist < 85.0 and _can(p):
					_shout(p, "near_miss")
					if dist < 50.0 and sp > 250.0 and _hit_cd <= 0.0 and not host.story_busy():
						# Knocked somebody over.
						_hit_cd = 4.0
						host.fx.pop("OUCH!", p.position + Vector2(0, -40), Color("#ff7a5c"), 30)
						Street.add_heat(0.5)
						Street.add_rep(-2.0)
	# Fight watchers stay put until it's over.
	if _watch_t > 0.0:
		_watch_t -= dt
		if _watch_t <= 0.0:
			_watching.clear()
	# Rain: everyone hurries.
	if _rain_t > 0.0:
		_rain_t -= dt
		if _rain_t <= 0.0:
			for p: Node2D in main.crowd.people:
				p.speed = minf(p.speed, 85.0)


## A crowd gathers in a ring round `at` to watch (fights).
func crowd_to(at: Vector2, seconds := 25.0) -> void:
	_watching.clear()
	_watch_t = seconds
	var near: Array = main.crowd.people.filter(func(p: Node2D) -> bool: return p.position.distance_to(at) < 1000.0)
	near.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.position.distance_to(at) < b.position.distance_to(at))
	var n: int = mini(8, near.size())
	for i in n:
		var p: Node2D = near[i]
		var spot := at + Vector2.from_angle(i * TAU / n) * randf_range(85.0, 130.0)
		if not main.map.is_blocked(spot):
			p.target = spot
			p.idle_t = seconds
		_watching.append(p)
		if i < 3:
			_shout(p, "fight", 4.0)


func crashed(at: Vector2) -> void:
	var k := 0
	for p: Node2D in main.crowd.people:
		if p.position.distance_to(at) < 420.0 and _can(p):
			_shout(p, "crash", 8.0)
			k += 1
			if k >= 2:
				return


func rain_started() -> void:
	_rain_t = 40.0
	var k := 0
	for p: Node2D in main.crowd.people:
		p.speed = maxf(p.speed, 125.0)
		if k < 3 and p.position.distance_to(main.player.position) < 800.0:
			_shout(p, "rain", 10.0)
			k += 1
